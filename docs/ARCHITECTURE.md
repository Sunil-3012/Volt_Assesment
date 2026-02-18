# System Architecture

## Overview

The company provides AI-powered video analytics for enterprise customers. Each customer site has IP cameras monitored by an edge device that runs AI inference locally and uploads video data to the cloud.

```
┌─────────────────────────────────────────────────────┐
│                   Customer Site                      │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │ Camera 1 │  │ Camera 2 │  │ Camera N │         │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘         │
│       │   RTSP/ONVIF │             │               │
│       └──────┬───────┘─────────────┘               │
│              │                                      │
│       ┌──────▼──────┐                              │
│       │ Edge Device  │ (Dell PowerEdge + NVIDIA T4) │
│       │             │                              │
│       │ ┌─────────┐ │                              │
│       │ │Video    │ │  Video chunks                │
│       │ │Ingest   │──────► S3 (via VPN)            │
│       │ └─────────┘ │                              │
│       │ ┌─────────┐ │                              │
│       │ │AI       │ │  Inference results           │
│       │ │Inference│──────► SQS (via VPN)           │
│       │ └─────────┘ │                              │
│       └──────┬──────┘                              │
│              │ IPSec VPN                            │
└──────────────┼──────────────────────────────────────┘
               │
    ┌──────────▼───────────────────────────────────────┐
    │                  AWS Cloud                        │
    │                                                   │
    │  ┌─────────────────────────────────────────────┐ │
    │  │                  VPC                          │ │
    │  │                                              │ │
    │  │  ┌───────────────┐  ┌───────────────┐       │ │
    │  │  │ Public Subnet │  │ Public Subnet │       │ │
    │  │  │  (us-east-1a) │  │  (us-east-1b) │       │ │
    │  │  │  ┌─────────┐  │  │  ┌─────────┐  │       │ │
    │  │  │  │   ALB   │  │  │  │   NAT   │  │       │ │
    │  │  │  └─────────┘  │  │  └─────────┘  │       │ │
    │  │  └───────────────┘  └───────────────┘       │ │
    │  │                                              │ │
    │  │  ┌───────────────┐  ┌───────────────┐       │ │
    │  │  │ Private Subnet│  │ Private Subnet│       │ │
    │  │  │  (us-east-1a) │  │  (us-east-1b) │       │ │
    │  │  │               │  │               │       │ │
    │  │  │  ┌──────────────────────────┐    │       │ │
    │  │  │  │      EKS Cluster         │    │       │ │
    │  │  │  │                          │    │       │ │
    │  │  │  │  ┌────────────────────┐  │    │       │ │
    │  │  │  │  │ Video Processor    │  │    │       │ │
    │  │  │  │  │ (Kafka Streams)    │  │    │       │ │
    │  │  │  │  └────────────────────┘  │    │       │ │
    │  │  │  │  ┌────────────────────┐  │    │       │ │
    │  │  │  │  │ Inference API      │  │    │       │ │
    │  │  │  │  │ (GPU nodes)        │  │    │       │ │
    │  │  │  │  └────────────────────┘  │    │       │ │
    │  │  │  │  ┌────────────────────┐  │    │       │ │
    │  │  │  │  │ API Gateway        │  │    │       │ │
    │  │  │  │  └────────────────────┘  │    │       │ │
    │  │  │  └──────────────────────────┘    │       │ │
    │  │  └───────────────┘  └───────────────┘       │ │
    │  └─────────────────────────────────────────────┘ │
    │                                                   │
    │  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
    │  │    S3    │  │   SQS   │  │   RDS    │       │
    │  │ (video) │  │ (events)│  │(metadata)│       │
    │  └──────────┘  └──────────┘  └──────────┘       │
    │                                                   │
    │  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
    │  │   ECR   │  │  MSK    │  │CloudWatch│       │
    │  │(images) │  │ (Kafka) │  │ (logs)   │       │
    │  └──────────┘  └──────────┘  └──────────┘       │
    └───────────────────────────────────────────────────┘
```

## Data Flow

1. **IP cameras** stream video via RTSP to the **edge device**
2. **Edge device** runs video ingest (fragments video into MPEG-TS chunks) and AI inference
3. Video chunks are uploaded to **S3** via IPSec VPN tunnel
4. Inference results and metadata are published to **SQS**
5. **Video Processor** (Kafka Streams on EKS) consumes fragments, concatenates into time-based chunks, uploads to S3
6. **Inference API** (GPU nodes on EKS) serves model inference for cloud-side processing
7. **API Gateway** serves customer-facing dashboards and APIs

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Edge OS | Ubuntu 22.04 LTS |
| Edge GPU | NVIDIA T4 + CUDA |
| Container Runtime | Docker CE |
| Orchestration | Amazon EKS (Kubernetes) |
| Message Broker | Amazon MSK (Kafka) |
| Object Storage | Amazon S3 |
| Queue | Amazon SQS |
| Database | Amazon RDS (PostgreSQL) |
| Container Registry | Amazon ECR |
| CI/CD | GitHub Actions + CodeBuild/CodePipeline |
| Monitoring | CloudWatch + Prometheus + Grafana |
| VPN | AWS VPN Gateway + strongSwan |
| IaC | Terraform |

## Network Architecture

- **Customer site** connects to AWS via IPSec VPN (site-to-site)
- **Camera VLAN** is isolated from management and corporate networks
- **Edge device** bridges camera VLAN and management VLAN
- **All cloud traffic** traverses the VPN tunnel
- **EKS nodes** run in private subnets, accessed via NAT gateway and ALB

## Deployment Model

- **One EKS cluster** per environment (dev, staging, production)
- **One edge device** per customer site (some large sites have 2+)
- **Deployments** use rolling updates with health checks
- **Edge updates** use golden images + configuration management
- **Infrastructure** managed with Terraform, state in S3

## Key Operational Concerns

- **Edge reliability**: devices must operate autonomously if VPN drops
- **Video data volume**: each camera generates ~2-5 Mbps, sites have 4-32 cameras
- **Cost management**: S3 storage and EC2 compute are the largest cost drivers
- **Security**: camera networks must be isolated, all traffic encrypted
- **Scale**: 50+ customer sites, growing 10+ per quarter
