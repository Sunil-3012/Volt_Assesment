# Evaluation Rubric

## Scoring Overview

Total: **100 points** across 5 modules. Your submission is evaluated by the hiring team after you submit.

## Syntax Checker

You can validate that your files parse correctly before submitting:

```bash
pip install -r requirements.txt
python -m check                      # Check all files
python -m check --module terraform   # Check one module
```

## Module 1: Infrastructure-as-Code / Terraform (25 pts)

| Check | Points |
|-------|--------|
| HCL files parse without errors | 5 |
| No HCL syntax errors in plan structure | 5 |
| VPC with public + private subnets, NAT gateway | 4 |
| Security groups: no `0.0.0.0/0` on SSH (port 22) | 2 |
| EKS cluster with IAM roles, node group configuration | 2 |
| Cost optimization: spot/mixed instances, S3 lifecycle, rightsizing | 4 |
| Cost analysis response: parses `data/aws_cost_report.json`, proposes savings | 3 |

## Module 2: Kubernetes & Troubleshooting (25 pts)

| Check | Points |
|-------|--------|
| All YAML files parse without errors | 3 |
| Resource requests and limits defined | 1 |
| Liveness and readiness probes | 1 |
| HPA with min/max replicas and metrics | 1 |
| Anti-affinity or topology spread constraints | 1 |
| NetworkPolicy restricts ingress | 1 |
| Security context: non-root, read-only root filesystem | 2 |
| Image tag is not `:latest` | 1 |
| ConfigMap referenced from deployment | 1 |
| Incident 1: identifies OOMKilled + proposes remediation | 4 |
| Incident 2: identifies label mismatch + NetworkPolicy issue | 4 |
| Incident 3: identifies ECR image pull + auth fix | 4 |
| Prevention measures mentioned in incident responses | 1 |

## Module 3: Edge Device & Networking (20 pts)

| Check | Points |
|-------|--------|
| shellcheck passes on all `.sh` files | 2 |
| Python syntax valid on `camera_discovery.py` | 1 |
| Firewall: default DROP policy | 3 |
| Firewall: RTSP from camera VLAN only, HTTPS outbound, SSH from mgmt, camera isolation | 3 |
| `setup.sh`: Docker install, NTP config, log rotation, systemd service, error handling | 5 |
| `camera_discovery.py`: parses ONVIF XML, outputs JSON, handles timeout | 3 |
| `site_plan.md`: VLAN design, IP scheme, camera isolation | 2 |
| `golden_image.md`: creation process, base vs config separation, patching strategy | 1 |

## Module 4: CI/CD & Automation (15 pts)

| Check | Points |
|-------|--------|
| Pipeline YAML syntax valid | 1 |
| Build, test, deploy stages in correct order | 3 |
| ECR push, staging deploy, production with manual approval gate | 3 |
| Rollback / failure handling in pipeline | 1 |
| `deploy.py`: valid Python, argparse, rollback + healthcheck functions | 4 |
| `monitoring_setup.md`: metrics, SLOs, alerting, escalation | 3 |

## Module 5: Debugging & Ops Insights (15 pts)

| Check | Points |
|-------|--------|
| RCA: identifies MTU as root cause | 3 |
| RCA: identifies VPN tunnel flapping + packet fragmentation | 3 |
| RCA: correct timeline reconstruction | 1 |
| `remediation.sh`: sets MTU correctly, passes shellcheck | 3 |
| `postmortem.md`: all required sections with action items | 2 |
| `product_recommendations.md`: monitoring improvements + automated detection | 3 |

## Scoring Bands

| Score | Recommendation |
|-------|---------------|
| 80–100 | **Strong Hire** — Demonstrates broad, production-grade infrastructure skills |
| 65–79 | **Hire** (with discussion) — Solid fundamentals, some gaps to explore in interview |
| 50–64 | **Borderline** — May be suitable depending on team needs and growth potential |
| < 50 | **No Hire** — Significant gaps in core infrastructure competencies |

## Example Report Output

```json
{
  "total_score": 72,
  "max_score": 100,
  "band": "Hire",
  "modules": {
    "terraform": {"score": 18, "max": 25, "checks": [...]},
    "k8s": {"score": 20, "max": 25, "checks": [...]},
    "network": {"score": 14, "max": 20, "checks": [...]},
    "cicd": {"score": 10, "max": 15, "checks": [...]},
    "debug": {"score": 10, "max": 15, "checks": [...]}
  }
}
```

## Notes

- External tools (`shellcheck`, `terraform`, `kubeconform`) enhance grading but are not required — the evaluator degrades gracefully without them
- Document scoring uses keyword/concept matching — write clearly and use standard terminology
- Partial credit is awarded where applicable
