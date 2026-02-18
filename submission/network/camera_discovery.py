#!/usr/bin/env python3
"""
camera_discovery.py — Parse ONVIF WS-Discovery XML and output camera info as JSON.

Usage:
    python3 camera_discovery.py --input data/onvif_mock_response.xml
    onvif-discover | python3 camera_discovery.py --timeout 10
"""

import argparse
import json
import sys
import signal
import xml.etree.ElementTree as ET
from urllib.parse import urlparse, unquote

# XML namespace map for ONVIF WS-Discovery SOAP responses.
# ElementTree requires full URI prefixes in all find()/findall() calls.
NAMESPACES = {
    "soap": "http://www.w3.org/2003/05/soap-envelope",
    "d":    "http://schemas.xmlsoap.org/ws/2005/04/discovery",
    "dn":   "http://www.onvif.org/ver10/network/wsdl",
}


def parse_scopes(text):
    """Extract model, name, location from ONVIF scope URIs (space-separated)."""
    result = {"model": None, "name": None, "location": None}
    for scope in (text or "").split():
        if not scope.startswith("onvif://www.onvif.org/"):
            continue
        parts = scope[len("onvif://www.onvif.org/"):].split("/", 1)
        if len(parts) == 2:
            cat, val = parts[0], unquote(parts[1])
            if cat == "hardware":
                result["model"] = val
            elif cat in ("name", "location"):
                result[cat] = val
    return result


def extract_ip(xaddrs):
    """Parse hostname/IP from the first URL in XAddrs."""
    try:
        return urlparse((xaddrs or "").split()[0]).hostname
    except Exception:
        return None


def parse_onvif_response(xml_content):
    """Parse ONVIF ProbeMatches XML and return list of camera dicts."""
    root = ET.fromstring(xml_content)
    body = root.find("soap:Body", NAMESPACES)
    if body is None:
        raise ValueError("No SOAP Body in XML")
    probe_matches = body.find("d:ProbeMatches", NAMESPACES)
    if probe_matches is None:
        raise ValueError("No ProbeMatches element in SOAP Body")

    cameras = []
    for match in probe_matches.findall("d:ProbeMatch", NAMESPACES):
        cam = {"uuid": None, "model": None, "name": None,
               "location": None, "service_url": None, "ip": None}

        # UUID from EndpointReference/Address (strip "urn:uuid:" prefix)
        addr = match.find("d:EndpointReference/d:Address", NAMESPACES)
        if addr is not None and addr.text:
            cam["uuid"] = addr.text.strip().replace("urn:uuid:", "")

        # Scopes → model, name, location
        scopes_el = match.find("d:Scopes", NAMESPACES)
        cam.update(parse_scopes(scopes_el.text if scopes_el is not None else ""))

        # XAddrs → service_url, ip
        xaddrs_el = match.find("d:XAddrs", NAMESPACES)
        if xaddrs_el is not None and xaddrs_el.text:
            cam["service_url"] = xaddrs_el.text.split()[0]
            cam["ip"] = extract_ip(xaddrs_el.text)

        cameras.append(cam)
    return cameras


def main():
    parser = argparse.ArgumentParser(description="Parse ONVIF WS-Discovery XML to JSON")
    parser.add_argument("--input", metavar="FILE", default=None,
                        help="Path to XML file (defaults to stdin)")
    parser.add_argument("--timeout", type=int, default=10,
                        help="Stdin read timeout in seconds (default: 10)")
    args = parser.parse_args()

    try:
        if args.input:
            with open(args.input, encoding="utf-8") as f:
                xml = f.read()
        else:
            signal.signal(signal.SIGALRM,
                          lambda s, f: (_ for _ in ()).throw(TimeoutError("stdin timeout")))
            signal.alarm(args.timeout)
            xml = sys.stdin.read()
            signal.alarm(0)
    except (FileNotFoundError, PermissionError, TimeoutError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    if not xml.strip():
        print("ERROR: Empty input", file=sys.stderr)
        sys.exit(1)

    try:
        cameras = parse_onvif_response(xml)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    if not cameras:
        print("WARNING: No cameras found in ONVIF response", file=sys.stderr)

    print(json.dumps(cameras, indent=2))


if __name__ == "__main__":
    main()
