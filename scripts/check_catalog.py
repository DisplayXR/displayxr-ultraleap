#!/usr/bin/env python3
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
"""Check the draft catalog entry against this repository's pins.

    check_catalog.py catalog/ultraleap-hands.json --runtime-pin v2.69.3 [--version 0.1.0]

Fails when the entry's runtime range is not EXACTLY the CMake pin (the ADR-063
rule: min == max == the runtime the binary was built at), when the registered
id / ABI range / prerequisite / layer note are missing, or when --version is
given and the entry advertises another version.
"""
import argparse
import json
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--runtime-pin", required=True)
    ap.add_argument("--version")
    a = ap.parse_args()

    with open(a.path, encoding="utf-8") as f:
        c = json.load(f)
    pin = a.runtime_pin.lstrip("v")
    errs = []

    def need(cond, msg):
        if not cond:
            errs.append(msg)

    need(c.get("kind") == "input_provider", "kind must be input_provider")
    need(c.get("id") == "ultraleap", "id must be the registered provider id 'ultraleap'")
    abi = c.get("abi", {}).get("xrt_input_plugin", {})
    need(abi.get("min") == 1 and abi.get("max") == 1, "abi.xrt_input_plugin must be {min:1,max:1}")
    rr = c.get("runtime_range", {})
    need(rr.get("min") == pin, f"runtime_range.min {rr.get('min')!r} != CMake pin {pin!r}")
    need(rr.get("max") == pin, f"runtime_range.max {rr.get('max')!r} != CMake pin {pin!r} (exact range, ADR-063)")
    need(c.get("requires", {}).get("runtime") == f">={pin}", f"requires.runtime must be '>={pin}'")
    pre = [p.get("id") for p in c.get("prerequisites", [])]
    need("ultraleap-tracking" in pre, "the external prerequisite 'ultraleap-tracking' is missing")
    notes = [n.get("id") for n in c.get("notes", [])]
    need("ultraleap-openxr-layer" in notes, "the implicit OpenXR layer note is missing")
    if a.version:
        need(c.get("recommended") == a.version, f"recommended {c.get('recommended')!r} != release {a.version!r}")
        need(c.get("windows", {}).get("version") == a.version, "windows.version != release version")

    for e in errs:
        print(f"catalog: {e}", file=sys.stderr)
    if not errs:
        print(f"catalog OK: {c['component']} {c['recommended']} for runtime {pin} (exact)")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
