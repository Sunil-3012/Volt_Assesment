#!/usr/bin/env bash
# firewall_rules.sh — Edge device iptables rules for SITE-2847
# eno1 = management (10.50.1.0/24) + WAN/VPN uplink
# eno2 = camera VLAN (10.50.20.0/24) — fully isolated

set -euo pipefail

MGMT_IFACE="eno1"
CAM_IFACE="eno2"
MGMT_CIDR="10.50.1.0/24"
CAM_CIDR="10.50.20.0/24"
CORPORATE_CIDR="10.50.10.0/24"

# Flush all existing rules (clean slate)
iptables -F && iptables -X && iptables -Z
iptables -t nat -F && iptables -t mangle -F

# Default policy: DROP all inbound and forwarded, allow outbound
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT

# Allow loopback (required for local inter-process communication)
iptables -A INPUT -i lo -j ACCEPT

# Allow established/related connections (stateful — responses to our outbound requests)
iptables -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH — management VLAN only (never open 22 to 0.0.0.0/0)
iptables -A INPUT -i "$MGMT_IFACE" -s "$MGMT_CIDR" -p tcp --dport 22 \
    -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# RTSP — camera VLAN only (port 554 TCP/UDP + RTP dynamic ports)
iptables -A INPUT -i "$CAM_IFACE" -s "$CAM_CIDR" -p tcp --dport 554 \
    -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i "$CAM_IFACE" -s "$CAM_CIDR" -p udp --dport 554      -j ACCEPT
iptables -A INPUT -i "$CAM_IFACE" -s "$CAM_CIDR" -p udp --dport 1024:65535 -j ACCEPT

# HTTPS inbound (responses to our outbound S3/SQS/ECR calls)
iptables -A INPUT -i "$MGMT_IFACE" -p tcp --sport 443 \
    -m conntrack --ctstate ESTABLISHED -j ACCEPT

# Camera VLAN isolation — cameras cannot reach management, corporate, or WAN
iptables -A FORWARD -i "$CAM_IFACE" -d "$MGMT_CIDR"      -j DROP
iptables -A FORWARD -i "$CAM_IFACE" -d "$CORPORATE_CIDR" -j DROP
iptables -A FORWARD -i "$CAM_IFACE" -o "$MGMT_IFACE"     -j DROP

# ICMP — allow ping for diagnostics and VPN keepalives
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-reply   -j ACCEPT

# Log dropped packets (rate-limited) — grep "IPTABLES-DROPPED" in syslog
iptables -A INPUT   -m limit --limit 5/min -j LOG --log-prefix "IPTABLES-DROPPED-INPUT: "   --log-level 4
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "IPTABLES-DROPPED-FORWARD: " --log-level 4

# Persist rules across reboots
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
else
    iptables-save > /etc/iptables/rules.v4
fi

echo "Firewall rules applied. Active rules:"
iptables -L -n -v --line-numbers
