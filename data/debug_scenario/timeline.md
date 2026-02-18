# NOC Event Timeline — SITE-2847

## Incident: Video Upload Failures at Denver Distribution Center

| Time (UTC) | Source | Event |
|------------|--------|-------|
| 08:00 | Monitoring | All systems normal. Upload success rate: 100% |
| 08:15 | Change Log | Scheduled network maintenance: netplan configuration applied to edge device eno1 (ticket NET-4521: "Enable jumbo frames for camera VLAN performance") |
| 08:15 | Edge syslog | eno1 MTU changed from 1500 to 9000 |
| 08:18 | Edge syslog | ICMP "fragmentation needed" messages from gateway 10.50.1.1 |
| 08:18 | App logs | S3 upload timeouts begin — large chunks failing, health checks still passing |
| 08:20 | CloudWatch | Upload error count spikes from 0 to 18 per 5-min window |
| 08:21 | VPN log | IPSec tunnel DOWN — DPD timeout. Re-established after 10 seconds |
| 08:21 | App logs | VPN recovery detected, retry uploads — still failing |
| 08:22 | App logs | Network throughput measured at 1.8 Mbps (expected 50 Mbps) |
| 08:25 | VPN log | Second tunnel flap — DOWN then UP |
| 08:30 | App logs | CRITICAL alert: disk usage 85%, upload queue backlog 22 chunks |
| 08:30 | NOC | Alert received: EDGE_UPLOAD_FAILURE for SITE-2847 |
| 08:35 | VPN log | Third tunnel flap |
| 08:45 | NOC | NOC engineer begins investigation |
| 08:50 | VPN log | Fourth tunnel flap |
| 09:00 | NOC | MTU reverted to 1500 on eno1. Uploads resume immediately. Tunnel stabilizes |

## Notes

- The edge device has two NICs: eno1 (management + WAN) and eno2 (camera VLAN)
- The VPN tunnel traverses eno1 to reach AWS
- The site gateway (10.50.1.1) has a 1500-byte MTU and does not support jumbo frames
- The change ticket NET-4521 intended to apply jumbo frames to eno2 (camera VLAN) only, but the netplan config was applied to eno1 instead
