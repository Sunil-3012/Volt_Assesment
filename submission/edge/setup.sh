#!/usr/bin/env bash
# setup.sh — Edge device provisioning for SITE-2847
# Usage: SITE_ID=SITE-2847 sudo bash setup.sh

set -euo pipefail

SITE_ID="${SITE_ID:-SITE-UNKNOWN}"
EDGE_USER="edgeuser"
VIDEO_INGEST_IMAGE="123456789012.dkr.ecr.us-east-1.amazonaws.com/video-ingest:v1.5.2"
NTP_SERVER="10.50.1.10"
VIDEO_BUFFER_DIR="/data/video-buffer"
NVIDIA_DRIVER="535"

log() { echo "[$(date -u '+%H:%M:%S')] $1"; }
cleanup() { [ $? -ne 0 ] && log "Setup failed at line ${BASH_LINENO[0]}"; }
trap cleanup EXIT

[ "$(id -u)" -ne 0 ] && { echo "Run as root"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
exec > >(tee -a "/var/log/edge-setup.log") 2>&1
log "Starting edge device setup for $SITE_ID"

# --- Base packages ---
apt-get update -y && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg lsb-release \
    chrony logrotate jq awscli htop net-tools \
    iptables netfilter-persistent iptables-persistent unattended-upgrades

# --- Docker CE (official repo) ---
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

cat > /etc/docker/daemon.json <<'EOF'
{"log-driver":"json-file","log-opts":{"max-size":"100m","max-file":"5"},"storage-driver":"overlay2"}
EOF

id "$EDGE_USER" &>/dev/null || useradd --system --shell /usr/sbin/nologin --create-home "$EDGE_USER"
usermod -aG docker "$EDGE_USER"
systemctl enable --now docker

# --- NVIDIA driver + container toolkit ---
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -sL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -y
apt-get install -y "nvidia-driver-${NVIDIA_DRIVER}" nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker --set-as-default
systemctl restart docker

# --- NTP (chrony) ---
cat > /etc/chrony/chrony.conf <<EOF
server ${NTP_SERVER} iburst prefer
pool ntp.ubuntu.com iburst
makestep 1 3
driftfile /var/lib/chrony/drift
EOF
systemctl enable --now chrony

# --- Log rotation ---
cat > /etc/logrotate.d/docker-containers <<'EOF'
/var/lib/docker/containers/*/*.log {
    daily
    rotate 7
    compress
    copytruncate
    maxsize 100M
}
EOF

# --- Video buffer directory ---
mkdir -p "$VIDEO_BUFFER_DIR"
chown "$EDGE_USER:$EDGE_USER" "$VIDEO_BUFFER_DIR"

# --- video-ingest systemd service ---
mkdir -p /etc/edge
cat > /etc/edge/video-ingest.env <<EOF
SITE_ID=${SITE_ID}
AWS_REGION=us-east-1
S3_BUCKET=vlt-video-chunks-prod
SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/123456789012/video-events
KAFKA_BROKER=kafka-prod.internal:9092
LOG_LEVEL=INFO
EOF
chmod 600 /etc/edge/video-ingest.env

cat > /etc/systemd/system/video-ingest.service <<EOF
[Unit]
Description=Video Ingest — ${SITE_ID}
After=docker.service network-online.target
Requires=docker.service

[Service]
EnvironmentFile=/etc/edge/video-ingest.env
ExecStartPre=/usr/bin/docker pull ${VIDEO_INGEST_IMAGE}
ExecStartPre=-/usr/bin/docker rm -f video-ingest
ExecStart=/usr/bin/docker run --name video-ingest \
    --gpus all \
    --env-file /etc/edge/video-ingest.env \
    --volume ${VIDEO_BUFFER_DIR}:/data/video-buffer \
    --network host \
    --restart no \
    ${VIDEO_INGEST_IMAGE}
ExecStop=/usr/bin/docker stop video-ingest
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable video-ingest

# --- Security hardening ---
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
grep -q "AllowUsers" /etc/ssh/sshd_config || echo "AllowUsers ${EDGE_USER}" >> /etc/ssh/sshd_config
systemctl reload sshd

for svc in snapd avahi-daemon cups bluetooth; do
    systemctl disable --now "$svc" 2>/dev/null || true
done

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };
Unattended-Upgrade::Automatic-Reboot "false";
EOF

log "Setup complete for $SITE_ID"
log "Next steps: reboot → nvidia-smi → systemctl start video-ingest → bash healthcheck.sh"
