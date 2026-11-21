#!/usr/bin/env python3
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
"""Check the draft catalog entry against this repository's pins.

    check_catalog.py catalog/ultraleap-hands.json --runtime-pin v2.69.3 [--version 0.1.0]

Fails when runtime_range.build is not the CMake pin, when the range does not
contain the pin (min <= build <= verified_max), when requires.runtime is not
">=min", when the registered id / ABI range / prerequisite / layer note are
missing, or when --version is given and the entry advertises another version.
Whether the range is TRUE (identical shared headers on every release in it) is
checked separately, against the runtime's tags: scripts/runtime_range.py.
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

    def ver(text):
        try:
            return tuple(int(x) for x in str(text).split("."))
        except ValueError:
            return None

    need(rr.get("build") == pin, f"runtime_range.build {rr.get('build')!r} != CMake pin {pin!r}")
    lo, hi = ver(rr.get("min")), ver(rr.get("verified_max"))
    need(lo is not None and hi is not None, "runtime_range.min / verified_max must be X.Y.Z")
    if lo and hi:
        need(lo <= ver(pin) <= hi, f"the pin {pin} is outside runtime_range {rr.get('min')}..{rr.get('verified_max')}")
    need(c.get("requires", {}).get("runtime") == f">={rr.get('min')}", "requires.runtime must be '>=' + runtime_range.min")
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
        print(f"catalog OK: {c['component']} {c['recommended']}, built at runtime {pin}, range {rr['min']}..{rr['verified_max']}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
