# cost_optimization.tf — Cost Optimization Resources
#
Current Monthly Cost: $47,832
#
# Top Cost services:
#   1. EC2 (EKS nodes) - $22,146 (under utilized at 22 - 34%)
#   2. S3 Storage - $12,341 (all in STANDARD tier)
#   3. RDS - $4,856 (oversized instance at 28% utilization)


# Top Saving Oppurtunities:
## S3 Storage ($10,350): The vlt-video-chunks-prod bucket has 45TB in Standard tier, but 95% of access happens in the first 30 days. Moving data to Infrequent Access (IA) or Glacier after 30 days will save thousands.

## EC2 Under-utilization ($17,064): Video-processing nodes are at 34% utilization. We should switch these to Spot Instances since Kafka is resilient.

## General nodes are at 22% utilization. These are "right-sizing" candidates (moving from m5.2xlarge to m5.large).

## RDS Over-provisioning ($4,856): The Read Replicas are only at 12% utilization. We can downsize these instances.##