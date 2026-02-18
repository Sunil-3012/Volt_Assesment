# Getting Started

## Prerequisites

- Python 3.8+ (for running the syntax checker)
- Git
- A text editor or IDE

Optional:
- [shellcheck](https://github.com/koalaman/shellcheck) — shell script linter (the syntax checker uses it if available)

## Setup

```bash
# Clone your private copy of this repo
git clone <your-private-repo-url>
cd devops-interview

# Install dependencies
pip install -r requirements.txt

# Verify the syntax checker works
python -m check
```

## Workflow

1. **Read the architecture** — Start with `docs/ARCHITECTURE.md` to understand the system
2. **Pick a module** — Work on whichever module you're strongest in first
3. **Edit files in `submission/`** — Each file has instructions and TODOs
4. **Reference `data/`** — Scenario data is in the `data/` directory (read-only)
5. **Run the syntax checker** — Validate your files parse correctly as you go
6. **Commit frequently** — We review git history for your approach

## Syntax Checker

```bash
python -m check                      # Check all files
python -m check --module terraform   # Check one module
python -m check --module k8s
python -m check --module network
python -m check --module cicd
```

This validates file syntax (HCL, YAML, Python, shell) but does **not** score your work. Full evaluation is done by the hiring team.

## Module Guide

### Module 1: Terraform (`submission/terraform/`)
- Fix 3 bugs in `networking.tf`
- Complete `main.tf` (EKS cluster)
- Create `cost_optimization.tf` — analyze `data/aws_cost_report.json`

### Module 2: Kubernetes (`submission/k8s/`)
- Complete deployment, service, HPA, configmap, networkpolicy manifests
- Write incident responses in `incident_responses/` — use data from `data/incident/`

### Module 3: Edge & Networking (`submission/network/` + `submission/edge/`)
- Write network plan based on `data/site_spec.json`
- Implement firewall rules and camera discovery script
- Write edge provisioning script and golden image strategy

### Module 4: CI/CD (`submission/cicd/`)
- Define a pipeline in `pipeline.yaml`
- Implement `deploy.py` with argparse subcommands
- Write monitoring strategy in `monitoring_setup.md`

### Module 5: Debug (`submission/debug/`)
- Investigate `data/debug_scenario/` files
- Write root cause analysis, remediation script, postmortem, and product recommendations

## Tips

- **Quality over quantity** — A well-done subset scores better than a rushed complete submission
- **Show your reasoning** — Comments in code and explanations in markdown matter
- **Think production** — Security, monitoring, and failure handling are valued
- **Commit often** — Small, logical commits show your thought process
