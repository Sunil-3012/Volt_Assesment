#!/usr/bin/env bash
#
# firewall_rules.sh — Edge device firewall configuration
#
# TASK: Implement iptables rules for the edge device.
# Reference data/site_spec.json for network details.
#
# Requirements:
#   - Default DROP policy on INPUT and FORWARD chains
#   - Allow RTSP (554/tcp, 554/udp) from camera VLAN only
#   - Allow HTTPS (443/tcp) outbound for S3 uploads and API calls
#   - Allow SSH (22/tcp) from management VLAN only
#   - Camera VLAN must not be able to reach management or corporate VLANs
#   - Allow established/related connections
#   - Allow loopback traffic
#   - Allow ICMP for diagnostics
#
# Hints:
#   - Camera VLAN: (define based on your site_plan.md)
#   - Management VLAN: 10.50.1.0/24
#   - Edge device interfaces: eno1 (mgmt/WAN), eno2 (camera VLAN)

set -euo pipefail

# --- Flush existing rules ---
# TODO

# --- Default policies ---
# TODO

# --- Loopback ---
# TODO

# --- Established/Related ---
# TODO

# --- SSH from management VLAN only ---
# TODO

# --- RTSP from camera VLAN only ---
# TODO

# --- HTTPS outbound ---
# TODO

# --- Camera VLAN isolation (block camera-to-management/corporate) ---
# TODO

# --- ICMP ---
# TODO

# --- Logging for dropped packets (optional but recommended) ---
# TODO

echo "Firewall rules applied successfully"
