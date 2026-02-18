# Submission Directory

All your work goes here. Each subdirectory corresponds to a module.

## Checklist

Before submitting, verify:

- [ ] **Module 1 — Terraform**: All `.tf` files in `terraform/` are complete, bugs fixed in `networking.tf`, `cost_optimization.tf` created
- [ ] **Module 2 — Kubernetes**: All manifests in `k8s/` are complete, incident responses filled in
- [ ] **Module 3 — Network/Edge**: `network/` and `edge/` files completed
- [ ] **Module 4 — CI/CD**: Pipeline, deploy script, and monitoring doc in `cicd/` completed
- [ ] **Module 5 — Debug**: Root cause analysis, remediation script, and postmortem in `debug/` completed

## Submission Instructions

1. Commit all changes to your private repository
2. Run the syntax checker: `python -m check`
3. Add the reviewers listed in your assessment email as collaborators
4. Reply to the assessment email with your repository URL

## Syntax Checker

```bash
# From the repo root
pip install -r requirements.txt
python -m check
```
