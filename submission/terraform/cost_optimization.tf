# cost_optimization.tf — Cost Optimization Resources
#
# =============================================================================
# COST ANALYSIS — November 2025 (source: data/aws_cost_report.json)
# =============================================================================
#
# TOTAL MONTHLY SPEND: $47,832
#
# TOP COST DRIVERS:
#   1. EC2 (EKS nodes)          $22,146  (46%) ← biggest opportunity
#   2. S3 storage               $12,341  (26%) ← easy wins via lifecycle
#   3. RDS                       $4,856  (10%) ← oversized instances
#   4. Data Transfer             $3,200   (7%) ← architecture issue
#   5. EKS cluster fees          $2,190   (5%) ← fixed cost (3 clusters @ $0.10/hr)
#
# PROPOSED CHANGES AND ESTIMATED SAVINGS:
#
#   Change 1 — EC2: Spot instances for general + video-processing node groups
#     - These groups run stateless, interruptible workloads at 22–34% utilisation
#     - Spot pricing for c5/m5 family = ~60–70% discount vs on-demand
#     - Current cost:  $11,520 (video-processing) + $5,544 (general) = $17,064
#     - Estimated saving: ~$11,000/month (64% reduction)
#     - Implemented: capacity_type = "SPOT" on aws_eks_node_group.general in main.tf
#     - GPU node group stays ON_DEMAND — spot interruptions during inference cause
#       data loss and session drops, which is unacceptable for the product SLA
#
#   Change 2 — S3: Lifecycle tiering for video chunks bucket
#     - 45 TB stored entirely in STANDARD ($0.023/GB) = $10,350/month
#     - Access pattern: 95% of reads happen within the first 30 days
#     - After 30 days → STANDARD_IA ($0.0125/GB): saves ~45% on cold data
#     - After 90 days → GLACIER_IR ($0.004/GB): saves ~83% on archive data
#     - Expire at 730 days (2 years) — older footage has no analytical value
#     - Estimated saving: ~$5,500/month
#
#   Change 3 — S3: Lifecycle tiering for logs bucket
#     - 8.2 TB at $0.023/GB = $1,416/month
#     - Access pattern: rarely accessed after 7 days (hot only for incident triage)
#     - After 7 days → STANDARD_IA; after 30 days → GLACIER; delete at 180 days
#     - Estimated saving: ~$900/month
#
#   Change 4 — RDS: Right-size the primary PostgreSQL instance
#     - db.r5.2xlarge at 28% average utilisation = massively oversized
#     - Recommendation: db.r5.xlarge (half the size, ~$1,728/month vs $3,456/month)
#     - Implemented as a Terraform note below (requires a planned maintenance window)
#     - Estimated saving: ~$1,728/month
#
#   Change 5 — Bastion: Consolidate 3 instances to 1
#     - 3× t3.medium at 5% utilisation = $793/month wasted
#     - One bastion with SSM Session Manager as a no-bastion fallback
#     - Estimated saving: ~$529/month
#
# TOTAL ESTIMATED SAVINGS: ~$19,657/month (41% reduction → ~$28,175/month)
#
# TRADE-OFFS AND RISKS:
#   - Spot interruptions: mitigated by multi-instance-type list and pod disruption
#     budgets (PDBs) defined in the k8s module. If a node is reclaimed, the
#     cluster autoscaler provisions a replacement within ~2 minutes.
#   - S3 retrieval costs: STANDARD_IA and GLACIER_IR charge per-GB retrieval.
#     The access pattern data shows <5% of reads hit data older than 30 days,
#     so retrieval fees are negligible (~$20–50/month).
#   - RDS downtime: resizing requires a Multi-AZ failover. Schedule during the
#     weekly maintenance window (Sunday 03:00–05:00 UTC) with prior customer notice.
# =============================================================================


# =============================================================================
# S3 BUCKETS
# =============================================================================
# Declare the buckets as resources so lifecycle policies can be attached.
# Bucket names come from variables.tf to keep them configurable per environment.

resource "aws_s3_bucket" "video_chunks" {
  bucket = var.video_chunks_bucket_name

  tags = {
    Name    = var.video_chunks_bucket_name
    Purpose = "edge-video-storage"
  }
}

resource "aws_s3_bucket" "model_artifacts" {
  bucket = var.model_artifacts_bucket_name

  tags = {
    Name    = var.model_artifacts_bucket_name
    Purpose = "ml-model-storage"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = var.logs_bucket_name

  tags = {
    Name    = var.logs_bucket_name
    Purpose = "application-logs"
  }
}

# Block all public access on every bucket — video footage and logs must never
# be publicly readable, even accidentally via a misconfigured bucket policy.
resource "aws_s3_bucket_public_access_block" "video_chunks" {
  bucket                  = aws_s3_bucket.video_chunks.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "model_artifacts" {
  bucket                  = aws_s3_bucket.model_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning on the video chunks bucket so accidental deletes are recoverable.
resource "aws_s3_bucket_versioning" "video_chunks" {
  bucket = aws_s3_bucket.video_chunks.id
  versioning_configuration {
    status = "Enabled"
  }
}


# =============================================================================
# S3 LIFECYCLE — VIDEO CHUNKS BUCKET
# =============================================================================
# Finding: 45 TB entirely in STANDARD storage = $10,350/month.
# 95% of access is within the first 30 days (hot), the rest is cold.
#
# Tiering ladder:
#   Day 0–30   → STANDARD         (fast reads for active analysis)
#   Day 31–90  → STANDARD_IA      (~45% cheaper, 30-day minimum billing)
#   Day 91–730 → GLACIER_IR       (~83% cheaper, millisecond retrieval for audits)
#   Day 730+   → EXPIRE           (2-year retention, then auto-delete)
#
# Non-current versions (from versioning above) are expired after 30 days
# to avoid paying twice for the same data.

resource "aws_s3_bucket_lifecycle_configuration" "video_chunks" {
  bucket = aws_s3_bucket.video_chunks.id

  rule {
    id     = "tiered-storage-video-chunks"
    status = "Enabled"

    filter {
      prefix = "" # applies to all objects in the bucket
    }

    # Move to STANDARD_IA after 30 days.
    # WHY STANDARD_IA and not GLACIER directly?
    # Incident investigation often requires pulling clips from 30–90 days ago.
    # STANDARD_IA provides millisecond access at nearly half the storage cost.
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move to GLACIER_IR after 90 days.
    # GLACIER_IR (Instant Retrieval) costs $0.004/GB — 83% cheaper than STANDARD.
    # Still provides millisecond retrieval for rare audit/legal requests.
    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    # Delete objects after 2 years.
    # Footage older than 730 days has no operational or analytical value.
    # Retaining it would cost ~$180/month/TB in GLACIER_IR with no benefit.
    expiration {
      days = 730
    }

    # Clean up old versions after 30 days to avoid double-charging on versioned objects.
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}


# =============================================================================
# S3 LIFECYCLE — LOGS BUCKET
# =============================================================================
# Finding: 8.2 TB in STANDARD = $1,416/month.
# Logs are only accessed in the first 7 days (incident triage window).
# After that, they are essentially cold archives.
#
# Tiering ladder:
#   Day 0–7    → STANDARD         (hot, needed for active debugging)
#   Day 8–30   → STANDARD_IA      (warm, occasionally needed for post-mortems)
#   Day 31–180 → GLACIER          (cold archive, legal hold minimum)
#   Day 180+   → EXPIRE           (6-month retention policy)

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "tiered-storage-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    # 180-day retention satisfies most compliance requirements for operational logs.
    # Extend to 365 if subject to SOC2 or HIPAA audit requirements.
    expiration {
      days = 180
    }
  }
}


# =============================================================================
# S3 LIFECYCLE — MODEL ARTIFACTS BUCKET
# =============================================================================
# Finding: 2.5 TB in STANDARD = $575/month. Access pattern: periodic reads
# during model deployments. Historical model versions rarely accessed after 365 days.
# Lower-priority optimization but still worth doing.

resource "aws_s3_bucket_lifecycle_configuration" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  rule {
    id     = "archive-old-model-versions"
    status = "Enabled"

    filter {
      prefix = "archive/" # only archive old model versions, not active ones
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER_IR"
    }
  }
}


# =============================================================================
# RDS RIGHT-SIZING NOTE
# =============================================================================
# Finding: db.r5.2xlarge running at 28% average CPU/memory utilisation.
#
# This block documents the recommended right-sizing. To apply it:
#   1. Schedule the change in a maintenance window (Multi-AZ failover takes ~60s)
#   2. Update the instance_class to "db.r5.xlarge"
#   3. Monitor for 1 week post-change with CloudWatch enhanced monitoring
#
# This Terraform local captures the recommendation so it shows up in plan output
# and can be tracked in git history as a deliberate decision.
#
# Current:    db.r5.2xlarge @ $3,456/month (28% utilisation)
# Recommended: db.r5.xlarge  @ $1,728/month (will run at ~56% utilisation — healthy)
# Saving:      $1,728/month
#
# If RDS is managed by a separate module or team, raise this as a Jira ticket
# with the utilisation data from the cost report as evidence.

locals {
  rds_rightsizing_recommendation = {
    current_instance     = "db.r5.2xlarge"
    recommended_instance = "db.r5.xlarge"
    current_utilization  = "28%"
    expected_utilization = "56%"
    monthly_saving_usd   = 1728
    action               = "Resize during next maintenance window. Monitor for 7 days post-resize."
  }

  # Summarise total estimated monthly savings from all optimisations above.
  estimated_monthly_savings = {
    ec2_spot_general_nodes   = 11000
    s3_video_lifecycle       = 5500
    s3_logs_lifecycle        = 900
    rds_rightsizing          = 1728
    bastion_consolidation    = 529
    total_usd                = 19657
    new_estimated_monthly    = 28175
    reduction_pct            = "41%"
  }
}
