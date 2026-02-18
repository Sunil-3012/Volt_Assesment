# Monitoring and Observability Setup

## Metrics

I collect metrics across four layers using **Prometheus + CloudWatch**:

**Application (video-processor service)**
- Request latency (p50, p95, p99) per endpoint
- Error rate (HTTP 5xx / total requests)
- Kafka consumer lag — how far behind the processing queue is
- Video chunks processed per minute, upload success/failure rate

**Infrastructure (EKS)**
- CPU and memory utilization per pod (compared to requests/limits)
- JVM heap usage — critical for catching pre-OOM conditions before they kill pods
- Pod restart count — leading indicator of crash loops

**Edge device (per-site)**
- GPU utilization and temperature (from `healthcheck.sh` JSON to CloudWatch custom metric)
- Disk % used on `/data/video-buffer`
- Camera reachability (0–8 cameras online)
- NTP offset, VPN tunnel state

**Business**
- End-to-end latency: camera capture → cloud processing
- Upload backlog size (how many chunks are waiting to leave the edge)
- Per-site availability: % of time all 8 cameras are processing

## SLOs

| Objective | Target | Measurement window |
|-----------|--------|--------------------|
| Platform availability | 99.9% (43 min/month downtime budget) | Rolling 30 days |
| Video processing latency p95 | < 5 seconds end-to-end | 1 hour |
| Data freshness (edge to cloud) | < 30 seconds under normal conditions | Per upload cycle |
| Edge device uptime (per site) | 99.5% (3.6 hr/month) | Rolling 30 days |
| Deployment success rate | > 99% (CI pipeline) | Rolling 7 days |

I track SLO burn rate using multi-window alerting (1h fast burn + 6h slow burn) to detect both sudden spikes and gradual degradation.

## Alerting

I distinguish between pages (wake someone up) and tickets (fix next business day):

**Page immediately (PagerDuty)**
- Platform availability drops below 99.9% SLO burn rate threshold
- Video-processor pod crash loop (>3 restarts in 5 min)
- Edge device: VPN tunnel down OR 0/8 cameras reachable
- Kafka consumer lag > 10,000 messages (video processing falling behind)
- Disk on edge device > 95% full

**Ticket (Jira, next business day)**
- Edge device disk > 85% (approaching limit)
- p95 latency elevated but under SLO budget
- 1–2 cameras unreachable (single device issue, not fleet-wide)
- Deployment pipeline failure (not production-impacting)

**Alert fatigue prevention:** I set minimum 5-minute evaluation windows and require 2 consecutive breaches before firing. All alerts have runbook links and auto-remediation scripts where possible (e.g., `healthcheck.sh` output posted to the alert).

## Escalation

| Level | Who | Trigger | Response time |
|-------|-----|---------|--------------|
| L1 | Automated (Lambda/runbook) | Alert fires | Immediate — restarts service, purges disk buffer, runs healthcheck |
| L2 | On-call engineer (PagerDuty) | L1 fails or L1 not applicable | 5 minutes (business hours), 15 minutes (off-hours) |
| L3 | Platform lead / senior engineer | L2 cannot resolve in 30 min, or production data loss | 30 minutes |
| Customer | Account team notifies customer | > 5 minutes of confirmed customer-facing impact | As soon as impact confirmed |

L2 engineers always check `bash healthcheck.sh | jq .` on the affected edge device first — it gives the full picture in one command.

## Dashboards

I maintain three Grafana dashboards:

**Fleet Health** — one panel per site, showing: camera count, GPU temp, disk %, VPN state, last healthcheck timestamp. Red/amber/green at a glance for all deployed sites.

**Service Performance** — video-processor request latency percentiles, error rate, Kafka lag, pod restarts, SLO burn rate gauges. This is what the on-call engineer opens first during an incident.

**Pipeline & Deployments** — deployment frequency, lead time from commit to production, rollback count, Trivy CVE trend. Used in weekly engineering review to track delivery health.
