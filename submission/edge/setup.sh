#!/usr/bin/env bash
#
# setup.sh — Edge device provisioning script
#
# TASK: Implement a provisioning script for a new edge device.
# Reference data/site_spec.json for hardware and requirements.
#
# Requirements:
#   - Error handling (set -euo pipefail, trap for cleanup)
#   - Docker installation and configuration
#   - NTP configuration for time synchronization
#   - Log rotation setup
#   - Systemd service for the video ingest container
#   - GPU driver setup (NVIDIA)
#   - Basic security hardening

set -euo pipefail

SITE_ID="${SITE_ID:-SITE-UNKNOWN}"
LOG_FILE="/var/log/edge-setup-${SITE_ID}.log"

log() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $1" | tee -a "$LOG_FILE"
}

log "Starting edge device setup for site: $SITE_ID"

# ============================================
# SECTION 1: System Updates and Base Packages
# ============================================
# TODO: Update system packages, install prerequisites

# ============================================
# SECTION 2: Docker Installation
# ============================================
# TODO: Install Docker CE, configure daemon (log driver, storage driver)
# TODO: Add the service user to the docker group

# ============================================
# SECTION 3: NVIDIA GPU Drivers and Container Toolkit
# ============================================
# TODO: Install NVIDIA drivers and nvidia-container-toolkit
# TODO: Configure Docker to use the NVIDIA runtime

# ============================================
# SECTION 4: NTP Configuration
# ============================================
# TODO: Configure NTP to use the site's NTP server
# Hint: See data/site_spec.json for the NTP server address

# ============================================
# SECTION 5: Log Rotation
# ============================================
# TODO: Configure logrotate for application and Docker logs

# ============================================
# SECTION 6: Systemd Service
# ============================================
# TODO: Create a systemd service that runs the video-ingest container
# Requirements:
#   - Restart on failure
#   - Start after Docker
#   - GPU access
#   - Mount local storage for video buffer

# ============================================
# SECTION 7: Security Hardening
# ============================================
# TODO: Basic security (disable root SSH, configure UFW, etc.)

log "Edge device setup complete for site: $SITE_ID"
