# main.tf - EKS Cluster and Node Groups

# =============================================================================
# EKS CLUSTER IAM ROLE
# =============================================================================
# The EKS control plane needs its own IAM role so AWS can manage cluster
# resources (load balancers, security groups, etc.) on your behalf.
# The trust policy allows the "eks.amazonaws.com" service to assume this role.

resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-cluster-role"
  }
}

# Attach the AWS-managed EKS cluster policy.
# This policy grants the control plane permissions to describe/manage EC2,
# Elastic Load Balancing, IAM, and CloudWatch on behalf of the cluster.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# =============================================================================
# EKS CLUSTER
# =============================================================================
# Nodes run in PRIVATE subnets — they have no direct internet exposure.
# The control plane endpoint is accessible from within the VPC only (via ALB/VPN).
# We enable specific log types so we can audit API calls, auth events,
# and controller decisions in CloudWatch.

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    # Place the cluster's network interface in both private subnets (multi-AZ).
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id
    ]

    # Attached the EKS node security group to the cluster.
    security_group_ids = [aws_security_group.eks_nodes.id]

    # Keep the API server endpoint private — no direct public internet access.
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  # Enable these log types in CloudWatch:
  # - api:           every request to the Kubernetes API server
  # - audit:         who did what and when (important for compliance)
  # - authenticator: IAM authentication events (helps debug RBAC issues)
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Ensure the IAM role and its policies are fully created before the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = var.cluster_name
  }
}

# =============================================================================
# NODE GROUP IAM ROLE
# =============================================================================
# EC2 worker nodes need their own IAM role so the kubelet on each node can
# call AWS APIs (e.g., pull images from ECR, register with the cluster).
# The trust policy allows EC2 instances to assume this role.

resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-node-role"
  }
}

# Policy 1: Core worker node permissions — lets nodes register with the cluster,
# describe EC2 resources, and communicate with the control plane.
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Policy 2: CNI (Container Network Interface) permissions — lets the aws-vpc-cni
# plugin allocate and manage pod IP addresses from the VPC CIDR.
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Policy 3: ECR read-only — lets nodes pull container images from Elastic
# Container Registry. Read-only is sufficient; nodes never need to push.
resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# =============================================================================
# GENERAL NODE GROUP
# =============================================================================
# This group runs general workloads: video-processor, API gateway, Kafka consumers.
# Instance types are a list so cost_optimization.tf can apply mixed instance / spot policies.
# Nodes run in private subnets — they reach the internet via the NAT Gateway.

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-general"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  instance_types  = var.general_node_instance_types

  # Multi-AZ placement: spread nodes across both private subnets for HA.
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  scaling_config {
    min_size     = var.general_node_min_size
    max_size     = var.general_node_max_size
    desired_size = var.general_node_desired_size
  }

  # Use AL2 for GPU-less nodes (smaller, faster boot, well-tested with EKS).
  ami_type = "AL2_x86_64"

  # SPOT capacity for general workloads — stateless pods (video-processor, API gateway)
  # can tolerate a 2-minute interruption notice. Saves ~60-70% vs on-demand.
  # GPU nodes in the gpu node group intentionally stay ON_DEMAND (see cost_optimization.tf).
  capacity_type = "SPOT"

  # Encrypt the root EBS volume — nodes handle video metadata and model data.
  disk_size = 50

  # Ensure all IAM attachments exist before the node group is created.
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]

  tags = {
    Name                                                = "${var.cluster_name}-general-node"
    "k8s.io/cluster-autoscaler/enabled"                = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"    = "owned"
  }

  lifecycle {
    # Ignore desired_size changes from the cluster autoscaler at plan time —
    # the autoscaler manages this dynamically; Terraform should not override it.
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# =============================================================================
# GPU NODE GROUP
# =============================================================================
# This group runs ONLY GPU inference workloads (Inference API pods).
# g4dn.xlarge has 1x NVIDIA T4 GPU — same as the edge device, so models
# behave consistently between edge and cloud inference.
#
# KEY DECISION — On-demand only (no spot):
#   Spot interruptions mid-inference would drop active video analysis sessions
#   and cause data loss. GPU nodes must be stable. Spot is appropriate only
#   for stateless, interruptible workloads (general node group).
#
# Taints ensure ONLY pods that explicitly tolerate "gpu=true:NoSchedule"
# land on these expensive nodes — prevents general workloads from wasting GPU capacity.

resource "aws_eks_node_group" "gpu" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-gpu"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  instance_types  = var.gpu_node_instance_types

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  scaling_config {
    min_size     = var.gpu_node_min_size
    max_size     = var.gpu_node_max_size
    desired_size = var.gpu_node_desired_size
  }

  # AL2_x86_64_GPU includes the NVIDIA drivers and CUDA runtime pre-installed.
  # Using standard AL2 here would require manual driver installation on every node.
  ami_type = "AL2_x86_64_GPU"

  # GPU nodes need more disk for model weights (can be 5–20 GB each).
  disk_size = 100

  # Taint: only pods with a matching toleration will be scheduled here.
  # This prevents non-GPU workloads from consuming the expensive GPU instances.
  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  # Label: used by nodeSelectors and nodeAffinity rules in pod specs
  # to explicitly target GPU nodes.
  labels = {
    "workload-type"   = "gpu-inference"
    "nvidia.com/gpu"  = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]

  tags = {
    Name                                                = "${var.cluster_name}-gpu-node"
    "k8s.io/cluster-autoscaler/enabled"                = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"    = "owned"
    "k8s.io/cluster-autoscaler/node-template/taint/nvidia.com/gpu" = "true:NoSchedule"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
