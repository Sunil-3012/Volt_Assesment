#!/usr/bin/env bash
# healthcheck.sh — Edge device health monitor
# Exit: 0=healthy  1=degraded  2=critical
# Usage: bash healthcheck.sh | jq .

SITE_ID="${SITE_ID:-SITE-2847}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
SEVERITY=0
CHECKS=""

# Add a check result and escalate overall severity
add() {
    local name=$1 status=$2 msg=$3
    [ -n "$CHECKS" ] && CHECKS="$CHECKS, "
    CHECKS="${CHECKS}\"$name\": {\"status\": \"$status\", \"message\": \"$msg\"}"
    [ "$status" = "critical" ] && [ "$SEVERITY" -lt 2 ] && SEVERITY=2
    [ "$status" = "degraded" ] && [ "$SEVERITY" -lt 1 ] && SEVERITY=1
}

# 1. Docker daemon
if systemctl is-active --quiet docker && docker info &>/dev/null; then
    add "docker" "ok" "Docker running ($(docker ps -q | wc -l) containers)"
else
    add "docker" "critical" "Docker not running — systemctl start docker"
fi

# 2. video-ingest container
state=$(docker inspect video-ingest --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
case "$state" in
    running)     add "video_ingest" "ok"       "Container running" ;;
    exited|dead) add "video_ingest" "critical" "Container stopped — docker logs video-ingest" ;;
    restarting)  add "video_ingest" "degraded" "Container restarting — possible crash loop" ;;
    *)           add "video_ingest" "critical" "Container not found — systemctl start video-ingest" ;;
esac

# 3. GPU (NVIDIA T4 — max temp 83°C, warn at 78°C)
if gpu=$(nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu \
             --format=csv,noheader,nounits 2>/dev/null); then
    IFS=',' read -r name drv temp util <<< "$gpu"
    temp="${temp// /}"
    [ "$temp" -ge 78 ] \
        && add "gpu" "degraded" "GPU ${name// /} temp=${temp}C (near 83C limit)" \
        || add "gpu" "ok"       "GPU ${name// /} driver=${drv// /} temp=${temp}C util=${util// /}%"
else
    add "gpu" "critical" "nvidia-smi failed — driver not loaded (reboot required?)"
fi

# 4. Disk usage on video buffer
pct=$(df /data/video-buffer 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}')
if   [ "${pct:-0}" -ge 95 ]; then add "disk" "critical" "Disk ${pct}% full — video buffer at risk"
elif [ "${pct:-0}" -ge 85 ]; then add "disk" "degraded" "Disk ${pct}% used — approaching limit"
else                               add "disk" "ok"       "Disk ${pct}% used on /data/video-buffer"
fi

# 5. NTP sync (chrony) — video timestamps must be accurate to <0.5s
offset=$(chronyc tracking 2>/dev/null | grep "System time" | grep -oP '\d+\.\d+' | head -1)
if   awk -v v="${offset:-9999}" 'BEGIN{exit(v+0>=2.0?0:1)}'; then
    add "ntp" "critical" "NTP offset ${offset}s exceeds critical threshold (2.0s)"
elif awk -v v="${offset:-9999}" 'BEGIN{exit(v+0>=0.5?0:1)}'; then
    add "ntp" "degraded" "NTP offset ${offset}s exceeds warning threshold (0.5s)"
else
    add "ntp" "ok" "NTP synced (offset: ${offset}s)"
fi

# 6. VPN tunnel to AWS
vpn=$(ip link show 2>/dev/null | grep -oE '(vti|ipsec|tun)[0-9]+' | head -1)
if [ -n "$vpn" ]; then
    add "vpn" "ok"       "VPN tunnel up ($vpn)"
else
    add "vpn" "critical" "No VPN interface found — check: ipsec status"
fi

# 7. Camera VLAN connectivity (10.50.20.101–108)
ok=0; failed=""
for i in $(seq 101 108); do
    ping -c1 -W2 -q "10.50.20.$i" &>/dev/null && ok=$((ok+1)) || failed="$failed 10.50.20.$i"
done
if   [ "$ok" -eq 8 ]; then add "cameras" "ok"       "All 8/8 cameras reachable"
elif [ "$ok" -eq 0 ]; then add "cameras" "critical" "No cameras reachable — check VLAN 20"
else                       add "cameras" "degraded" "$ok/8 cameras reachable; unreachable:$failed"
fi

# Output JSON
status=$([ $SEVERITY -eq 0 ] && echo healthy || { [ $SEVERITY -eq 1 ] && echo degraded || echo critical; })
printf '{\n  "timestamp": "%s",\n  "site_id": "%s",\n  "overall_status": "%s",\n  "checks": { %s }\n}\n' \
    "$TIMESTAMP" "$SITE_ID" "$status" "$CHECKS"
exit $SEVERITY
