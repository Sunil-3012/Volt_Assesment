# Root Cause Analysis — SITE-2847 Upload Failure (2025-11-12)

## Summary

At 08:15 UTC a scheduled network change (NET-4521) intended to enable jumbo frames on the camera VLAN interface (`eno2`) was accidentally applied to the WAN interface (`eno1`) instead, raising its MTU from 1500 to 9000. The upstream gateway (`10.50.1.1`) only supports MTU 1500 and cannot forward oversized frames. Because IPSec ESP packets have the DF (Don't Fragment) bit set, the gateway dropped large packets and returned ICMP "fragmentation needed" — causing S3 upload throughput to collapse from 44 Mbps to 1.8 Mbps. The degraded tunnel triggered repeated DPD timeouts, causing the VPN to flap 4 times. Video chunks accumulated on disk (45% → 91%) for 45 minutes until NOC reverted the MTU at 09:00.

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 08:00 | All systems normal — uploads completing at 41–44 Mbps, 0 errors |
| 08:15:03 | `eno1` MTU changed 1500 → 9000 (`kernel: device eno1: MTU changed via netplan apply`) |
| 08:15:05 | strongSwan logs: *"IKE SA keepalive: packet size 9000 exceeds path MTU 1500"* |
| 08:15 | CloudWatch: first 2 upload errors appear in the 08:15 window |
| 08:18:01 | Uploader starts batch of 12 chunks (847 MB total) |
| 08:18:33 | Kernel: repeated *"ICMP: 10.50.1.1: fragmentation needed and DF set, mtu=1500"* |
| 08:18 | VPN log: *"IPSec throughput degraded: expected 50 Mbps, actual 2.3 Mbps"* |
| 08:19:07 | First chunk upload fails after 3 attempts — `SocketTimeoutException: Read timed out` |
| 08:20 | CloudWatch: upload errors spike to 18 per 5-min window |
| 08:21:08 | strongSwan DPD timeout — **VPN tunnel flap #1** (down 2s, re-established 08:21:10) |
| 08:21:15 | Uploader retries after tunnel recovery — still failing (MTU still wrong) |
| 08:22:16 | App logs: *"Network throughput: 1.8 Mbps (expected 50 Mbps)"* |
| 08:25 | **VPN tunnel flap #2** |
| 08:30 | Disk usage 85%, queue backlog 22 chunks — NOC alert fires |
| 08:35 | **VPN tunnel flap #3** |
| 08:45 | NOC engineer begins investigation (15 min after alert) |
| 08:50 | **VPN tunnel flap #4**, 34% sustained packet loss on ESP tunnel |
| 09:00 | NOC reverts `eno1` MTU to 1500 — uploads resume immediately, tunnel stabilises |

## Root Cause

**MTU misconfiguration on the WAN interface (`eno1`).**

Change ticket NET-4521 intended to apply `mtu: 9000` to `eno2` (camera VLAN, a local-only interface that never leaves the building). Instead, the netplan config was applied to `eno1` — the interface used for all WAN/VPN traffic.

The causal chain:

1. **eno1 MTU set to 9000** — edge device now tries to send 9000-byte Ethernet frames to the gateway.
2. **Gateway drops oversized frames** — `10.50.1.1` has MTU 1500 and cannot forward them. It returns ICMP Type 3 Code 4 ("fragmentation needed, DF set") because IPSec ESP uses the DF bit.
3. **PMTUD black hole** — the S3 uploader uses large TCP segments for multipart uploads. These exceed 1500 bytes and are silently dropped. The ICMP signals are either not propagated correctly into the container or not acted on fast enough, so the sender keeps retrying at full size until timeout.
4. **Throughput collapses** — only packets under ~1500 bytes (ICMP pings, small TCP ACKs) traverse the path. Upload throughput drops from 44 Mbps to 1.8 Mbps.
5. **VPN tunnel flaps** — strongSwan DPD keepalives are also impacted by the packet loss. After 3 consecutive DPD timeouts, it declares the peer dead and rekeys (teardown + re-establish). This happens 4 times, adding ~2s of full outage each cycle.
6. **Disk fills** — video-ingest continues recording to local buffer during the outage. Disk grows from 52% → 91% over 45 minutes.

## Contributing Factors

- **Wrong interface in change ticket**: The netplan config in NET-4521 targeted `eno1` instead of `eno2`. No diff review or staging test caught this before apply.
- **Health checks gave false green**: The Docker container healthcheck (`/health/live`) sends small HTTP requests — well under 1500 bytes — which passed through the degraded path without issue. The monitoring system saw a healthy container while uploads were completely broken.
- **No upload throughput metric**: CloudWatch had upload error counts but no throughput (Mbps) metric. A throughput drop from 44 → 1.8 Mbps would have alerted immediately; the error count took 5 minutes to register.
- **Slow NOC response**: The alert fired at 08:30 (15 minutes into full failure). The engineer only began investigation at 08:45 — 15 minutes after the alert. Total time to remediation was 45 minutes.
- **No pre-change validation**: No automated check verified that the netplan change was being applied to the intended interface, nor that connectivity was maintained post-change.

## Evidence

| Evidence | Source | Significance |
|----------|--------|--------------|
| `kernel: device eno1: MTU changed from 1500 to 9000` at 08:15:03 | edge_syslog.txt:6 | Confirms exact time and wrong interface |
| `ICMP: 10.50.1.1: fragmentation needed and DF set, mtu=1500` at 08:18:33 | edge_syslog.txt:12–14 | Gateway confirming it cannot forward oversized frames |
| `IPSec throughput degraded: expected 50Mbps, actual 2.3Mbps` at 08:18:31 | vpn_status.log:10 | Direct evidence of throughput collapse caused by fragmentation |
| `SocketTimeoutException: Read timed out` on every S3 PutObject | app_logs.txt:8,10,12 | Large TCP segments silently dropped at gateway |
| `Network throughput: 1.8 Mbps` at 08:22:16 | app_logs.txt:20 | App itself diagnosed the MTU/fragmentation issue |
| VPN flaps at 08:21, 08:25, 08:35, 08:50 | vpn_status.log | DPD timeouts caused by packet loss on the degraded path |
| CloudWatch: errors 0 → 18 → 24 per window, drops to 0 at 09:00 | cloudwatch_metrics.json | Perfectly correlated with MTU change (08:15) and revert (09:00) |
| Disk: 52% at 08:15, 91% at 08:45, 65% at 09:00 | cloudwatch_metrics.json | Buffer filling during outage, draining after fix |
