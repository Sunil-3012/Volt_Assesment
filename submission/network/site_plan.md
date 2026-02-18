# Site Network Plan — SITE-2847

## VLAN Design

| VLAN | Name        | Subnet           | Purpose                                          |
|------|-------------|------------------|--------------------------------------------------|
| 1    | management  | 10.50.1.0/24     | IT management, SSH, DNS, NTP (10.50.1.10)        |
| 10   | corporate   | 10.50.10.0/24    | Office workstations — no camera/edge access      |
| 20   | camera      | 10.50.20.0/24    | IP cameras only — fully isolated from other VLANs |

Cameras get a dedicated VLAN because they're embedded Linux devices with minimal hardening. Isolating them means a compromised camera can't reach management or corporate infrastructure.

## IP Addressing

**Management VLAN (10.50.1.0/24)** — pre-existing
- `10.50.1.1` — core switch / gateway
- `10.50.1.10` — DNS + NTP server
- `10.50.1.50` — edge device `eno1` (static, management interface)

**Camera VLAN (10.50.20.0/24)** — new
- `10.50.20.1` — edge device `eno2` (gateway for cameras, static)
- `10.50.20.100–199` — camera DHCP pool (MAC-reserved for stable IPs)

| Camera  | Location           | Model           | IP            |
|---------|--------------------|-----------------|---------------|
| CAM-001 | Loading Dock A     | Axis P3265-LVE  | 10.50.20.101  |
| CAM-002 | Loading Dock B     | Axis P3265-LVE  | 10.50.20.102  |
| CAM-003 | Warehouse Entrance | Axis P3265-LVE  | 10.50.20.103  |
| CAM-004 | Parking Lot North  | Axis Q6135-LE   | 10.50.20.104  |
| CAM-005 | Parking Lot South  | Axis Q6135-LE   | 10.50.20.105  |
| CAM-006 | Receiving Area     | Axis P3265-LVE  | 10.50.20.106  |
| CAM-007 | Shipping Area      | Axis P3265-LVE  | 10.50.20.107  |
| CAM-008 | Main Hallway       | Axis P3265-LVE  | 10.50.20.108  |

## Camera Network Isolation

Three-layer defence in depth:

1. **Switch VLAN** — camera ports are access VLAN 20 only. Physical layer isolation.
2. **No inter-VLAN routing** — the switch doesn't route between VLANs. Only the edge device bridges VLAN 1 and VLAN 20, in a controlled way.
3. **iptables FORWARD rules** — the edge device explicitly DROPs packets from `eno2` (camera VLAN) destined for `10.50.1.0/24` (management) or `10.50.10.0/24` (corporate).

Cameras **can**: send RTSP streams to the edge device, receive DHCP, respond to ICMP.
Cameras **cannot**: reach management, corporate, VPN, or the internet.

## Traffic Flow

```
Camera (10.50.20.x)
    │  RTSP/554 on VLAN 20
    ▼
Edge Device eno2 (10.50.20.1)
    │  AI inference on NVIDIA T4 GPU
    ▼
Edge Device eno1 (10.50.1.50)
    │  HTTPS/443 via IPSec VPN tunnel
    ▼
AWS: S3 (video chunks) + SQS (inference events)
```

- Upload capped at 50 Mbps; 8 cameras average ~24 Mbps — well within the WAN limit
- 24h local buffer on 2×1 TB RAID1 NVMe — continues recording if VPN drops
