
# Added the VPC id,Public subnet id, private subnet id, eks cluster endpoint, added the CA certificate as well with the S3 bucket names

# --- VPC ---
# Needed by any downstream module that needs to place resources in the same VPC
# (e.g., RDS, MSK, additional security groups).
output "vpc_id" {
  description = "ID of the VPC" # we need to replace it with the actual VPC id
  value       = aws_vpc.main.id
}

# --- Public Subnet IDs ---
# Used by ALB and NAT Gateway resources that require internet-facing placement.
output "public_subnet_ids" {
  description = "IDs of the public subnets (used by ALB, NAT Gateway)"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

# --- Private Subnet IDs ---
# Used by EKS nodes, RDS, and MSK  - all of wjich must stay off the public internet.
output "private_subnet_ids" {
  description = "IDs of the private subnets (used by EKS nodes, RDS, MSK)"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# --- NAT Gateway Public IP ---
# Useful for whitelisting the cluster's outbound IP at customer firewalls
# or third-party services that need to allowlist our egress.
output "nat_gateway_ip" {
  description = "Public IP of the NAT Gateway (egress IP for all private subnet traffic)"
  value       = aws_eip.nat.public_ip
}

# --- EKS Cluster ---
# The endpoint is used by kubectl, CI/CD pipelines, and monitoring tools to
# communicate with the Kubernetes API server.
output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

# The CA certificate is required to authenticate connections to the API server
# (used when configuring kubectl or the Kubernetes Terraform provider).
output "eks_cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true  # mark sensitive so it doesn't print in CI logs
}

# The cluster's OIDC issuer URL is needed to set up IAM Roles for Service Accounts (IRSA),
# which lets individual pods assume fine grained IAM roles without node level credentials.
output "eks_cluster_oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster (used to configure IRSA)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# --- S3 Bucket Names ---
# Consumed by edge device provisioning scripts, application configs, and
# CI/CD pipelines that need to know where to read/write data.
output "video_chunks_bucket" {
  description = "S3 bucket name for video chunk storage"
  value       = var.video_chunks_bucket_name
}

output "model_artifacts_bucket" {
  description = "S3 bucket name for AI model artifacts"
  value       = var.model_artifacts_bucket_name
}

output "logs_bucket" {
  description = "S3 bucket name for application logs"
  value       = var.logs_bucket_name
}
