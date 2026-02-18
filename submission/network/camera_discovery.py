#!/usr/bin/env python3
"""
camera_discovery.py — ONVIF Camera Discovery Tool

TASK: Implement a camera discovery script that:
  1. Reads an ONVIF WS-Discovery XML response (like data/onvif_mock_response.xml)
  2. Parses the XML to extract camera information
  3. Outputs a JSON array of discovered cameras
  4. Handles timeouts and malformed XML gracefully

Requirements:
  - Parse the ONVIF ProbeMatch elements
  - Extract: endpoint address (UUID), hardware model, name, location, service URL
  - Output valid JSON to stdout
  - Accept --input flag for XML file path (default: stdin)
  - Accept --timeout flag for discovery timeout in seconds
  - Handle errors gracefully (timeout, parse errors, missing fields)

Example output:
[
  {
    "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "model": "P3265-LVE",
    "name": "AXIS P3265-LVE",
    "location": "LoadingDockA",
    "service_url": "http://10.50.20.101:80/onvif/device_service",
    "ip": "10.50.20.101"
  }
]
"""

import argparse
import json
import sys
import xml.etree.ElementTree as ET


def parse_args():
    """Parse command line arguments."""
    # TODO: Implement argparse with --input and --timeout flags
    pass


def parse_onvif_response(xml_content):
    """Parse ONVIF WS-Discovery XML and return list of camera dicts."""
    # TODO: Implement XML parsing
    # Hint: Use namespaces for SOAP/WS-Discovery/ONVIF elements
    pass


def main():
    # TODO: Implement main function
    #   1. Parse arguments
    #   2. Read XML input (from file or stdin)
    #   3. Parse the ONVIF response
    #   4. Output JSON to stdout
    pass


if __name__ == "__main__":
    main()
