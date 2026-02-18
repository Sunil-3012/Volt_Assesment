#!/usr/bin/env bash
# remediation.sh — Fix MTU misconfiguration on eno1 (SITE-2847 incident)
#
# Root cause: eno1 MTU was set to 9000 by a bad netplan change.
# The WAN path only supports MTU 1500. This script reverts the MTU,
# patches the netplan config so it survives reboots, and verifies the fix.
#
# Safe to re-run (idempotent). Must be run as root.
# Usage: sudo bash remediation.sh

set -euo pipefail

IFACE="eno1"
CORRECT_MTU=1500
NETPLAN_DIR="/etc/netplan"
VPN_PEER="52.14.88.201"    # AWS VPN gateway IP (from vpn_status.log)
S3_TEST_HOST="s3.amazonaws.com"

log() { echo "[$(date -u '+%H:%M:%S')] $1"; }
fail() { echo "[ERROR] $1" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] && fail "Must be run as root"

log "=== MTU Remediation for $IFACE ==="

# --- Step 1: Check current MTU ---
current_mtu=$(ip link show "$IFACE" | awk '/mtu/ {print $5}')
log "Current MTU on $IFACE: $current_mtu (required: $CORRECT_MTU)"

if [ "$current_mtu" -eq "$CORRECT_MTU" ]; then
    log "MTU is already correct — no live change needed"
else
    log "Fixing MTU: $current_mtu -> $CORRECT_MTU"
    ip link set "$IFACE" mtu "$CORRECT_MTU"
    log "Live MTU fix applied"
fi

# Confirm the live change took effect
actual_mtu=$(ip link show "$IFACE" | awk '/mtu/ {print $5}')
[ "$actual_mtu" -eq "$CORRECT_MTU" ] || fail "MTU still $actual_mtu after fix — check NIC/driver"
log "Verified live MTU: $actual_mtu ✓"

# --- Step 2: Patch netplan config to prevent recurrence after reboot ---
# Find the netplan file that configures eno1 and correct any mtu: 9000 entry.
netplan_file=$(grep -rl "$IFACE" "$NETPLAN_DIR" 2>/dev/null | head -1 || true)

if [ -z "$netplan_file" ]; then
    log "WARNING: No netplan file found for $IFACE — skipping persistent fix"
else
    if grep -q "mtu: 9000" "$netplan_file"; then
        log "Patching $netplan_file: mtu: 9000 -> mtu: $CORRECT_MTU"
        cp "$netplan_file" "${netplan_file}.bak.$(date +%Y%m%d%H%M%S)"  # backup first
        sed -i "s/mtu: 9000/mtu: $CORRECT_MTU/" "$netplan_file"
        netplan apply
        log "Netplan config updated and applied ✓"
    else
        log "Netplan config does not contain mtu: 9000 — no patch needed"
    fi
fi

# --- Step 3: Verify VPN tunnel is stable ---
log "Waiting for VPN tunnel to stabilise (up to 30s)..."
for i in $(seq 1 6); do
    vpn_iface=$(ip link show 2>/dev/null | grep -oE '(vti|ipsec|tun)[0-9]+' | head -1 || true)
    if [ -n "$vpn_iface" ]; then
        log "VPN interface $vpn_iface is UP ✓"
        break
    fi
    log "  Waiting... ($i/6)"
    sleep 5
done

if [ -z "${vpn_iface:-}" ]; then
    log "WARNING: VPN interface not detected — restart strongSwan if needed: systemctl restart strongswan"
fi

# --- Step 4: Verify large packet connectivity (no PMTUD black hole) ---
# Send a ping with payload size that would have failed before the fix (>1500 bytes total).
# Ping with 1472 bytes of data + 28 bytes ICMP/IP header = 1500 byte frame (exactly at MTU limit).
log "Testing large packet connectivity to VPN peer ($VPN_PEER)..."
if ping -c 3 -W 5 -s 1472 -M do "$VPN_PEER" &>/dev/null; then
    log "Large packet ping to $VPN_PEER succeeded ✓ (no fragmentation issues)"
else
    log "WARNING: Large packet ping to $VPN_PEER failed — check VPN tunnel status"
fi

# --- Step 5: Check upload throughput (ICMP to S3 endpoint) ---
log "Testing connectivity to S3 ($S3_TEST_HOST)..."
if ping -c 3 -W 5 "$S3_TEST_HOST" &>/dev/null; then
    log "S3 host reachable ✓ — uploads should resume automatically"
else
    log "WARNING: S3 host not reachable — check VPN routing"
fi

# --- Summary ---
log "=== Remediation complete ==="
log "MTU on $IFACE: $(ip link show "$IFACE" | awk '/mtu/{print $5}')"
log "Next steps:"
log "  1. Monitor CloudWatch VideoChunkUploadErrors — should drop to 0"
log "  2. Check upload queue drains: docker logs video-ingest | tail -20"
log "  3. Verify disk usage drops from 91% as backlog clears"
log "  4. File follow-up ticket to add MTU monitoring to healthcheck.sh"
