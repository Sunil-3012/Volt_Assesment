# Product & Engineering Recommendations

## Monitoring Improvements

The core failure of this incident was that monitoring gave a false-green signal for 15 minutes while uploads were completely broken. Two changes would fix this:

**Upload throughput metric (highest priority).** I'd add a real-time `UploadThroughputMbps` metric to CloudWatch, measured by the uploader itself and pushed every 60 seconds. A drop below 5 Mbps (10% of expected 50 Mbps) fires an immediate P2 alert. Error counts lag by up to 5 minutes and require multiple full timeout cycles — throughput drops are visible within seconds.

**MTU monitoring in `healthcheck.sh`.** Add a check that reads `ip link show eno1 | grep mtu` and alerts if the value is anything other than 1500. This would have caught the misconfiguration at 08:15 rather than at 08:45. Cost: 2 lines of bash.

**ICMP fragmentation counter.** Parse `/proc/net/snmp` for `InAddrErrors` and `FragFails`, or count ICMP type-3-code-4 messages from kernel logs. A non-zero value on `eno1` should immediately raise a ticket — fragmentation needed on a WAN interface is never expected behaviour in this infrastructure.

**VPN throughput vs. baseline.** strongSwan already logs throughput — I'd scrape it and compare against a rolling 1-hour baseline. A drop to <10% of baseline fires a degraded alert even before DPD timeout triggers.

## Automated Detection

I'd implement two automated responses:

**Auto-detect PMTUD black hole.** A cron job running every 5 minutes on the edge device sends a large-payload ping (`ping -c 1 -s 1472 -M do <vpn_peer>`) and a small one. If the large ping fails but the small one succeeds, it's a PMTUD black hole — the script immediately checks the MTU on `eno1` and alerts with the current value. This is a definitive test that takes <2 seconds.

**Auto-remediate MTU drift.** If `eno1` MTU is detected as anything other than 1500, the edge device can self-heal by running `ip link set eno1 mtu 1500` automatically (since 1500 is always correct for this WAN path) and posting the event to CloudWatch. A human should still review, but uploads resume in seconds rather than waiting for a NOC engineer.

## Platform Changes

**Netplan change control.** Before any `netplan apply` takes effect, a validation hook should: (1) diff the config to identify which interfaces are being changed, (2) verify those interfaces match the change ticket, and (3) run a 30-second connectivity test post-apply before the ticket can be closed. This is a 10-line wrapper script that would have caught this incident at the point of change.

**MTU pinning in the golden image.** The golden image's base netplan config should explicitly set `mtu: 1500` on `eno1`. That way, even if a change incorrectly sets it to 9000, a `golden-image-restore` emergency procedure will reset it. It also makes the expected MTU self-documenting.

**Larger upload health check.** The application's `/health/ready` endpoint should attempt a small S3 connectivity test (e.g., `HeadBucket`) rather than just checking internal state. This test would have failed during the MTU incident and caused the Kubernetes readiness probe to mark the pod as not ready — triggering an alert within 30 seconds instead of 15 minutes.

## Edge Device Improvements

**Post-change validation as part of the provisioning workflow.** Any time `setup.sh`, `firewall_rules.sh`, or a netplan config is applied to an edge device, `healthcheck.sh` should be run automatically as the final step. A failed healthcheck blocks the change from being marked complete. This creates a feedback loop: config changes must leave the device in a healthy state or they're immediately visible.

**Interface-scoped change tagging.** When a network change ticket is created, the system should require the engineer to tag which physical interface(s) will be modified. The automation that applies the change validates the tag matches the actual diff before proceeding. A `netplan apply` that touches `eno1` when the ticket says `eno2` would be rejected with an error.

**Upload backlog alert threshold.** The current alert fires at 22 chunks in the queue. I'd lower this to 5 chunks (about 3 minutes of backlog) with a degraded alert, and keep 22 chunks as the critical page. Earlier warning gives more time to diagnose before disk pressure becomes a problem.
