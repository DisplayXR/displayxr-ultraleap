#!/usr/bin/env python3
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
"""Is a provider built at runtime tag A plausibly valid on runtime tag B?

    runtime_range.py --runtime <displayxr-runtime clone> --from v2.69.3 --to v2.69.4 [--list]
    runtime_range.py --runtime <clone> --pin v2.69.3 --range 2.68.0 2.69.3   # verify a claimed range
    runtime_range.py --runtime <clone> --pin v2.69.3 --suggest               # the widest true range

--range exits 1 when a release inside the claimed range differs from the pin
(the claim is false), and 3 when the claim is true but a NEWER runtime release
exists outside it (the range is stale: widen it if --suggest says identical,
otherwise repin and rebuild). --suggest prints the contiguous run of release
tags around the pin whose shared headers are identical.

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


TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def release_tags(repo):
    r = subprocess.run(["git", "-C", repo, "tag", "-l", "v*"], capture_output=True, text=True)
    tags = []
    for t in r.stdout.split():
        m = TAG.match(t)
        if m:
            tags.append((tuple(int(x) for x in m.groups()), t))
    return sorted(tags)


def same(repo, a, b, cache):
    for t in (a, b):
        if t not in cache:
            cache[t] = closure(repo, t)
    return any(cache[a].values()) and cache[a] == cache[b]


def true_range(repo, pin):
    """Contiguous run of release tags around `pin` with identical shared headers."""
    tags = release_tags(repo)
    names = [t for _, t in tags]
    if pin not in names:
        return None, None, names
    i = names.index(pin)
    cache = {}
    lo = i
    while lo > 0 and same(repo, pin, names[lo - 1], cache):
        lo -= 1
    hi = i
    while hi + 1 < len(names) and same(repo, pin, names[hi + 1], cache):
        hi += 1
    return names[lo], names[hi], names


def range_mode(a) -> int:
    lo, hi, names = true_range(a.runtime, a.pin)
    if lo is None:
        print(f"{a.pin} is not a release tag in {a.runtime} (fetch tags?)", file=sys.stderr)
        return 2
    print(f"pin {a.pin}: shared headers identical on {lo} .. {hi}")
    newest = names[-1]
    if a.suggest:
        if newest != hi:
            print(f"newest runtime release {newest} DIFFERS from the pin: covering it needs a repin + rebuild")
        return 0
    want_lo, want_hi = "v" + a.range[0].lstrip("v"), "v" + a.range[1].lstrip("v")
    for w in (want_lo, want_hi):
        if w not in names:
            print(f"claimed bound {w} is not a runtime release tag", file=sys.stderr)
            return 1
    il, ih = names.index(lo), names.index(hi)
    if not (il <= names.index(want_lo) and names.index(want_hi) <= ih):
        print(f"FALSE RANGE: claimed {want_lo} .. {want_hi}, but the headers are only identical on {lo} .. {hi}")
        return 1
    print(f"claimed range {want_lo} .. {want_hi}: verified")
    if names.index(newest) > names.index(want_hi):
        if names.index(newest) <= ih:
            print(f"STALE RANGE: runtime {newest} is released and identical - raise verified_max to {hi.lstrip('v')}")
        else:
            print(f"STALE RANGE: runtime {newest} is released and DIFFERS from the pin - repin, rebuild, release")
        return 3
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runtime", required=True)
    ap.add_argument("--from", dest="a")
    ap.add_argument("--to", dest="b")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--pin")
    ap.add_argument("--range", nargs=2, metavar=("MIN", "MAX"))
    ap.add_argument("--suggest", action="store_true")
    a = ap.parse_args()
    if a.pin:
        if not (a.range or a.suggest):
            ap.error("--pin needs --range MIN MAX or --suggest")
        return range_mode(a)
    if not (a.a and a.b):
        ap.error("give --from A --to B, or --pin")
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
