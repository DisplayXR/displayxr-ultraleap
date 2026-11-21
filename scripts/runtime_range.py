#!/usr/bin/env python3
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
"""Is a provider built at runtime tag A plausibly valid on runtime tag B?

    runtime_range.py --runtime <displayxr-runtime checkout> --from v2.69.3 --to v2.69.4 [--list]

The provider hands the runtime raw `struct xrt_device`s (runtime ADR-063), so a
binary is only known-good on the release it was built at. This script gives a
CONSERVATIVE way to widen the catalog's runtime range without waiting for
ADR-063: it hashes, at both tags, every runtime header that defines memory the
two sides share -

  * the include closure of the headers the provider compiles against that the
    RUNTIME reads or writes through (xrt_device.h, xrt_input_plugin.h,
    xrt_component_settings.h, xrt_results.h and everything they include under
    src/xrt/include), and
  * the aux headers whose functions the provider IMPORTS from the runtime
    library on Windows / macOS (u_logging.h, u_var.h).

Identical bytes at both tags => identical layouts and signatures => the pin can
cover B. Any difference => "rebuild" (it may be a harmless comment edit; the
script does not try to tell). It reads `git show <tag>:<path>` only: nothing in
the checkout is modified. It is a heuristic for a human deciding a range, not a
substitute for the versioned device contract.
"""
import argparse
import hashlib
import re
import subprocess
import sys

ROOTS = [
    "src/xrt/include/xrt/xrt_device.h",
    "src/xrt/include/xrt/xrt_input_plugin.h",
    "src/xrt/include/xrt/xrt_component_settings.h",
    "src/xrt/include/xrt/xrt_results.h",
    "src/xrt/include/xrt/xrt_tracking.h",
    "src/xrt/auxiliary/util/u_logging.h",
    "src/xrt/auxiliary/util/u_var.h",
]
INC = re.compile(r'^\s*#\s*include\s+"(xrt/[^"]+)"', re.M)


def show(repo, tag, path):
    r = subprocess.run(["git", "-C", repo, "show", f"{tag}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def closure(repo, tag):
    seen, todo, out = set(), list(ROOTS), {}
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        data = show(repo, tag, p)
        if data is None:
            out[p] = None
            continue
        out[p] = hashlib.sha256(data).hexdigest()
        for inc in INC.findall(data.decode("utf-8", "replace")):
            todo.append("src/xrt/include/" + inc)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runtime", required=True)
    ap.add_argument("--from", dest="a", required=True)
    ap.add_argument("--to", dest="b", required=True)
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    ca, cb = closure(a.runtime, a.a), closure(a.runtime, a.b)
    if not any(ca.values()) or not any(cb.values()):
        print("could not read the headers at one of the tags (is it fetched?)", file=sys.stderr)
        return 2
    diff = sorted(p for p in set(ca) | set(cb) if ca.get(p) != cb.get(p))
    if a.list:
        for p in sorted(set(ca) | set(cb)):
            print(("DIFF  " if p in diff else "same  ") + p)
    if diff:
        print(f"{a.a} -> {a.b}: REBUILD ({len(diff)} shared header(s) differ)")
        for p in diff:
            print(f"  {p}")
        return 1
    print(f"{a.a} -> {a.b}: shared headers identical ({len(ca)} files) - the range may cover {a.b}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
