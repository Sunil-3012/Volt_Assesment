# Made 5 changes - Added the management cidr for extra security, added one general node group and one GPU node group, added the S3 bucket names and kubernetes version checker which will not let workloads breaks unexpectedly when AWS initiates any upgrades


variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "site_id" {
  description = "Customer site identifier"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "video-analytics"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# --- ADDED: Management CIDR ---
# it is used to restrict SSH access to the bastion host.
# we should never use 0.0.0.0/0(unless if we intentionally want hacker to hack our system :)) only the VPN/office IP range should reach port 22.
variable "management_cidr" {
  description = "CIDR block for management/VPN access (used to restrict SSH to bastion)"
  type        = string
  default     = "10.100.0.0/16" # should be replaced with the actual VPN/office egress CIDR in production
}

# --- ADDED: General Node Group ---
# c5.xlarge gives a good CPU/memory ratio for video-processing workloads.
# Using a list allows mixed instance policy (spot fallback) defined in cost_optimization.tf.
variable "general_node_instance_types" {
  description = "Instance types for the general EKS node group"
  type        = list(string)
  default     = ["c5.xlarge", "c5.2xlarge", "c5a.xlarge"]
}

variable "general_node_min_size" {
  description = "Minimum number of nodes in the general node group"
  type        = number
  default     = 2
}

variable "general_node_max_size" {
  description = "Maximum number of nodes in the general node group"
  type        = number
  default     = 10
}

variable "general_node_desired_size" {
  description = "Desired number of nodes in the general node group"
  type        = number
  default     = 3
}

# --- ADDED: GPU Node Group ---
# g4dn.xlarge = 1x NVIDIA T4 GPU, matches the edge device GPU for consistent inference.
# GPU nodes are kept on-demand and spot interruptions would drop active inference sessions.
variable "gpu_node_instance_types" {
  description = "Instance types for the GPU inference EKS node group"
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

variable "gpu_node_min_size" {
  description = "Minimum number of GPU nodes"
  type        = number
  default     = 1
}

variable "gpu_node_max_size" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 8
}

variable "gpu_node_desired_size" {
  description = "Desired number of GPU nodes"
  type        = number
  default     = 2
}

# --- ADDED: S3 Bucket Names ---
# Centralised here so they can be referenced in both main.tf and cost_optimization.tf.
variable "video_chunks_bucket_name" {
  description = "S3 bucket for video chunk storage uploaded from edge devices"
  type        = string
  default     = "volt-video-chunks-prod"
}

variable "model_artifacts_bucket_name" {
  description = "S3 bucket for AI model artifacts"
  type        = string
  default     = "volt-model-artifacts-prod"
}

variable "logs_bucket_name" {
  description = "S3 bucket for application and infrastructure logs"
  type        = string
  default     = "volt-logs-prod"
}

# --- ADDED: Kubernetes version ---
# Pinned the version explicitly and never let it float. Upgrades should be planned and tested.
variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}
