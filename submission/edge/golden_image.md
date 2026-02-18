# Golden Image Strategy

## Overview

I follow an **immutable image** approach — bake the OS, Docker, and NVIDIA drivers into a versioned disk image upfront, then apply site-specific config as a thin layer at first boot. Every device starts from an identical, tested baseline. No per-device manual setup.

The key separation: the image holds everything that's identical across all sites. Everything that varies (SITE_ID, camera IPs, AWS endpoints, secrets) comes from AWS SSM Parameter Store at first boot — nothing sensitive is ever baked into the image.

## Base Image

Built from **Ubuntu 22.04 LTS** using HashiCorp Packer. The image includes:

- Docker CE (pinned version) + nvidia-container-toolkit configured as default runtime
- NVIDIA driver 535 (CUDA 12.x, validated for T4)
- Core packages: chrony, awscli, jq, iptables-persistent, logrotate, unattended-upgrades
- Security hardening: root SSH disabled, password auth off, `edgeuser` only, unused services removed

**Not in the image:** site config files, firewall rules, the `video-ingest` systemd unit, or any secrets.

## Image Creation Process

1. Update `packer/edge-golden.pkr.hcl` with the new Ubuntu ISO SHA256 and pinned package versions
2. Run `packer build` — boots a VM, installs Ubuntu via autoinstall, runs provisioner scripts, outputs a signed raw `.img`
3. Automated tests verify: Docker starts, `nvidia-smi` works, SSH hardening applied, `edgeuser` exists
4. Upload to S3 with SHA256 and GPG signature: `s3://vlt-model-artifacts-prod/golden-images/edge-golden-v1.x.img`
5. Field tech writes the image to NVMe with `dd`, then runs `provision_site.sh` for site-specific config

## Configuration Management

Site values (SITE_ID, NTP server, camera IPs, S3 bucket, SQS URL) live in **AWS SSM Parameter Store** under `/edge/{SITE_ID}/`. At first boot, `provision_site.sh` fetches them and writes `/etc/edge/video-ingest.env` and `/etc/chrony/chrony.conf`. No secrets are ever baked in.

Each image embeds `/etc/edge/image-version` with the version tag and build date — surfaced in healthcheck JSON output so I can see exactly which image version is running on each device.

## Patching and Updates

I maintain three separate tracks:

- **Full re-image (quarterly or on critical CVE):** New Packer build for kernel/driver updates. Staged rollout: 1 site → 10% → 50% → 100%, gated by CloudWatch alarms from healthcheck output.
- **`unattended-upgrades` (continuous):** Security-only apt patches between image cycles. Reboots are manual only — never automatic.
- **Container updates (on demand):** Push a new image tag to ECR and restart the systemd unit. No OS change needed.

## Rollback

I roll back by re-imaging from the previous S3 artifact and re-running `provision_site.sh`. Since site config lives in SSM, everything is restored automatically — no manual re-entry.

```bash
aws s3 cp s3://vlt-model-artifacts-prod/golden-images/edge-golden-v1.3.img /tmp/
sha256sum -c edge-golden-v1.3.img.sha256            # verify before writing
dd if=/tmp/edge-golden-v1.3.img of=/dev/nvme0n1 bs=4M status=progress
SITE_ID=SITE-2847 bash /opt/edge/provision_site.sh
```

Target RTO: **under 30 minutes** per site. The last two known-good images are pre-cached on a USB drive at each site.
