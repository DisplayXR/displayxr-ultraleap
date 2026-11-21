#!/usr/bin/env bash
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# Load the COMPILE-CHECK build of the provider through the pinned runtime's own
# loader, headlessly, with `displayxr-cli` built from the same runtime tree:
#
#   ci-load-check.sh <stub build dir>
#
# The build dir must have the targets `displayxr_ultraleap`, `cli`,
# `drv_sim_display_plugin` and `leapc_stub` built with
# -DULTRALEAP_USE_LEAPC_STUB=ON. Three runs:
#
#   1. `input list`            the manifest is discovered, ProbeOrder 50.
#   2. `selftest`, no LeapC    the "Ultraleap tracking software NOT FOUND" state:
#                              the provider must LOAD, create its devices, report
#                              ABSENT, and the selftest must pass.
#   3. `selftest`, stand-in    LEAPC_PATH points at the in-tree stand-in library:
#                              the run-time loader binds it and opens a connection.
#
# This proves the load / negotiate / bind path against the pinned runtime. It
# proves nothing about hand tracking: the stand-in produces no data.
# Linux and macOS only (Windows discovery is the registry).
set -euo pipefail

build=$(cd "${1:?usage: ci-load-check.sh <stub build dir>}" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Short socket / temp paths: the runtime builds a unix socket path under TMPDIR.
export TMPDIR="$work"

find1() { find "$build" -name "$1" -not -path '*/CMakeFiles/*' | head -1; }
cli=$(find1 displayxr-cli)
prov=$(find1 'DisplayXR-Ultraleap-STUBCHECK.*')
sim=$(find1 'DisplayXR-SimDisplay.*')
stubdir="$build/tests/leapc_stub_lib"
for f in "$cli" "$prov" "$sim"; do
	if [ -z "$f" ] || [ ! -e "$f" ]; then
		echo "missing a build product (cli / provider / sim display) under $build" >&2
		exit 2
	fi
done
ls "$stubdir"/*LeapC* >/dev/null

plugins="$work/plugins"
mkdir -p "$plugins"
cp "$sim" "$plugins/"
sim="$plugins/$(basename "$sim")"
if [ "$(uname)" = "Darwin" ]; then
	# A raw build-tree plug-in has no rpath to the runtime library; the
	# runtime's own dev script adds one when it stages plug-ins.
	rt=$(dirname "$(find1 openxr_displayxr.dylib)")
	install_name_tool -add_rpath "$rt" "$sim" 2>/dev/null || true
	codesign -f -s - "$sim" 2>/dev/null || true
fi
manifest() { # <file> <id> <name> <binary> <order>
	printf '{ "file_format_version": "1.0", "plugin": { "id": "%s", "display_name": "%s", "vendor": "DisplayXR", "version": "ci", "binary_path": "%s", "probe_order": %s } }\n' \
		"$2" "$3" "$4" "$5" > "$plugins/$1"
}
manifest 200-sim-display.json sim-display "DisplayXR Sim Display" "$sim" 200
manifest 050-ultraleap-input-provider.json ultraleap "Ultraleap (LeapC STUB CHECK - not a real provider)" "$prov" 50
export XRT_PLUGIN_SEARCH_PATH="$plugins"

# Never let a hung runtime hold the job: bound every run.
run() { # <log> <cmd...>
	local log=$1; shift
	"$@" > "$log" 2>&1 &
	local pid=$!
	( sleep 120; kill -9 "$pid" 2>/dev/null ) &
	local dog=$!
	local rc=0
	wait "$pid" || rc=$?
	kill "$dog" 2>/dev/null || true
	return "$rc"
}
want() { # <log> <pattern>
	grep -q -- "$2" "$1" || { echo "FAIL: expected '$2' in $1:"; cat "$1"; exit 1; }
}

echo "== 1. input list"
run "$work/list.log" "$cli" input list || { cat "$work/list.log"; exit 1; }
want "$work/list.log" "ultraleap"
grep -n "ultraleap" "$work/list.log"

echo "== 2. selftest with no LeapC (tracking software not found)"
run "$work/absent.log" "$cli" selftest || { cat "$work/absent.log"; exit 1; }
want "$work/absent.log" "active input provider: id=ultraleap"
want "$work/absent.log" "Ultraleap tracking software NOT FOUND"
want "$work/absent.log" "presence after settle = ABSENT"
want "$work/absent.log" "provider 'ultraleap' loaded but its hardware is absent"
want "$work/absent.log" "SELF-TEST PASSED"
grep -n "ultraleap:\|input_providers\|SELF-TEST" "$work/absent.log" | cut -c1-220

echo "== 3. selftest with the stand-in LeapC bound at run time"
DXR_INPUT_ULTRALEAP_LEAPC_PATH="$stubdir" run "$work/stub.log" "$cli" selftest || { cat "$work/stub.log"; exit 1; }
want "$work/stub.log" "LeapC loaded from"
want "$work/stub.log" "connection open"
want "$work/stub.log" "supplied 2 device(s)"
want "$work/stub.log" "SELF-TEST PASSED"
grep -n "ultraleap:\|input_providers\|SELF-TEST" "$work/stub.log" | cut -c1-220

echo "load check OK (stand-in LeapC only - no tracking was exercised)"
