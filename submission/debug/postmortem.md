# Post-Incident Report

## Incident Summary

| Field | Value |
|-------|-------|
| Date | 2025-11-12 |
| Duration | 45 minutes (08:15 – 09:00 UTC) |
| Severity | P2 — Video uploads fully down at one site, cameras still recording locally |
| Services Affected | Video chunk upload pipeline, VPN tunnel stability (SITE-2847) |
| Customer Impact | 45 minutes of video analytics data not delivered to cloud dashboard. No permanent data loss — chunks were buffered locally and uploaded after fix. |

## What Happened

A scheduled network maintenance change (ticket NET-4521) intended to enable jumbo frames on the camera VLAN interface (`eno2`) was accidentally applied to the WAN interface (`eno1`) instead, raising its MTU from 1500 to 9000. The upstream gateway only supports MTU 1500, so all large packets (video chunk uploads to S3) were silently dropped at the network layer. Small packets (health checks, ICMP pings) continued to pass, giving monitoring a false-green signal for 15 minutes before error counts triggered an alert. The VPN tunnel flapped 4 times due to DPD timeout from packet loss. A NOC engineer reverted the MTU at 09:00, restoring normal operation instantly.

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 08:00 | All systems healthy, uploads at 41–44 Mbps |
| 08:15 | NET-4521 applied — `eno1` MTU changed 1500 → 9000 |
| 08:15 | strongSwan warns: keepalive packet size exceeds path MTU |
| 08:18 | Gateway returns ICMP "fragmentation needed" — S3 upload timeouts begin |
| 08:20 | CloudWatch: upload errors spike to 18/5min |
| 08:21 | VPN tunnel flap #1 (DPD timeout) — re-established after 2s |
| 08:22 | App logs measured throughput: 1.8 Mbps vs 50 Mbps expected |
| 08:25 | VPN tunnel flap #2 |
| 08:30 | Disk 85%, backlog 22 chunks — NOC alert fires |
| 08:35 | VPN tunnel flap #3 |
| 08:45 | NOC engineer begins investigation |
| 08:50 | VPN tunnel flap #4, 34% sustained packet loss |
| 09:00 | NOC reverts `eno1` MTU to 1500 — uploads resume, tunnel stabilises |

## Root Cause

Wrong interface targeted by the netplan change. `eno1` (WAN/VPN) received `mtu: 9000` instead of `eno2` (camera VLAN). IPSec ESP packets with the DF bit set could not be forwarded by the gateway at MTU 1500, causing a PMTUD black hole. All large TCP segments (S3 multipart uploads) were silently dropped. Small packets (health checks) passed normally, masking the failure from monitoring.

## Resolution

NOC engineer identified the MTU mismatch by correlating the 08:15 syslog entry (`eno1 MTU changed`) with the onset of upload failures. Reverted with `ip link set eno1 mtu 1500` and updated the netplan config. Uploads resumed within 60 seconds of the fix.

## Impact

- **Duration**: 45 minutes of complete upload failure
- **Data**: 22 video chunks (~1.8 GB) delayed — all successfully uploaded after remediation. No permanent data loss.
- **Disk**: Buffer grew from 52% to 91% during outage, returned to 65% after uploads resumed
- **VPN**: 4 tunnel flaps, each causing ~2s of full connectivity loss
- **Customer**: 45 minutes of stale data on the analytics dashboard for SITE-2847

## Action Items

| Action | Owner | Priority | Due Date |
|--------|-------|----------|----------|
| Add MTU check to `healthcheck.sh` — alert if `eno1` MTU ≠ 1500 | Platform team | P1 | 2025-11-19 |
| Add upload throughput metric to CloudWatch (Mbps, not just error count) | Platform team | P1 | 2025-11-19 |
| Add pre-change validation hook to netplan — verifies target interface before apply | Networking team | P1 | 2025-11-26 |
| Update change process: network changes require a 5-min connectivity test post-apply before closing the ticket | Engineering manager | P2 | 2025-11-19 |
| Add ICMP "fragmentation needed" counter as a CloudWatch metric | Platform team | P2 | 2025-11-26 |
| Reduce NOC alert-to-action SLA from 15 min to 5 min for P2 upload failures | NOC lead | P2 | 2025-11-26 |
| Document PMTUD black hole runbook — how to diagnose and fix MTU issues quickly | On-call engineer | P3 | 2025-12-03 |

## Lessons Learned

### What went well

- Local buffering worked as designed — no video data was permanently lost
- The application itself correctly diagnosed the issue at 08:22 (`"Possible MTU/fragmentation issue"`) — this clue was available before the NOC alert even fired
- Once the root cause was found, the fix took under 60 seconds

### What could be improved

- Health checks that only test small packets give a completely false picture of upload health — a health check that actually sends a large test payload (or monitors real upload throughput) would have alerted within 3 minutes instead of 15
- Change tickets for network config should require specifying both the target interface and a post-change connectivity test — a two-line diff review would have caught this immediately
- The NOC took 15 minutes to begin investigating after the alert fired — for a site with disk filling at 2.5% per minute, that delay matters
