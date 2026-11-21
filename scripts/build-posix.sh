#!/usr/bin/env bash
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# Build the Ultraleap input provider on Linux / macOS.
#
# EXPERIMENTAL platforms: only Windows is supported and released. This script
# exists for the hardware-free tests and the compile / load checks.
#
#   scripts/build-posix.sh [--stub] [--runtime <dir>] [--sdk <dir>] [--clean]
#                          [--dev-plugins <dir>] [--release]
#
#   --stub            COMPILE-CHECK ONLY: build against the stand-in header in
#                     tests/leapc_stub instead of the Ultraleap SDK's LeapC.h.
#                     Output is DisplayXR-Ultraleap-STUBCHECK, which is not a
#                     working provider and is never packaged.
#   --runtime <dir>   use a local displayxr-runtime checkout instead of fetching
#                     the pinned tag (warns when it is not AT the pinned tag).
#   --sdk <dir>       LeapSDK root holding include/LeapC.h (same as LEAPSDK_DIR
#                     in the environment). Only the header is used.
#   --dev-plugins <dir>
#                     after the build, write an NNN-ultraleap-input-provider.json
#                     pointing at the build-tree binary into <dir>, for
#                     XRT_PLUGIN_SEARCH_PATH=<dir> dev runs. Nothing is written
#                     to the per-user discovery root.
#   --release         CMAKE_BUILD_TYPE=Release (default RelWithDebInfo).
#
# Prerequisites are the runtime's (this project builds runtime aux libraries
# from source): see the runtime's scripts/build_linux.sh / build_macos.sh
# headers. Without a LeapC SDK and without --stub, only the hardware-free unit
# test is built and run.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
build="$here/build"
stub=OFF
runtime=""
sdk="${LEAPSDK_DIR:-}"
devdir=""
type=RelWithDebInfo
clean=0

while [ $# -gt 0 ]; do
	case "$1" in
	--stub) stub=ON; build="$here/build-stub" ;;
	--runtime) runtime=$2; shift ;;
	--sdk) sdk=$2; shift ;;
	--dev-plugins) devdir=$2; shift ;;
	--release) type=Release ;;
	--clean) clean=1 ;;
	-h | --help) sed -n '5,33p' "$0"; exit 0 ;;
	*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

[ "$clean" = 1 ] && rm -rf "$build"

args=(-S "$here" -B "$build" -G Ninja "-DCMAKE_BUILD_TYPE=$type" "-DULTRALEAP_USE_LEAPC_STUB=$stub")
[ -n "$runtime" ] && args+=("-DDXR_RUNTIME_SOURCE_DIR=$runtime")
[ -n "$sdk" ] && args+=("-DLEAPSDK_DIR=$sdk")

cmake "${args[@]}"
cmake --build "$build"
ctest --test-dir "$build" --output-on-failure

bin=$(find "$build/src/ultraleap" -maxdepth 1 \( -name 'DisplayXR-Ultraleap*.so' -o -name 'DisplayXR-Ultraleap*.dylib' \) 2>/dev/null | head -1 || true)
if [ -z "$bin" ]; then
	echo
	echo "No provider binary was built (LeapC.h not found). Unit tests ran."
	exit 0
fi
echo
echo "Built: $bin"

if [ -n "$devdir" ]; then
	mkdir -p "$devdir"
	name="Ultraleap Hand Tracking (controller emulation)"
	ver=dev
	if [ "$stub" = ON ]; then
		name="Ultraleap (LeapC STUB CHECK - not a real provider)"
		ver=stubcheck
	fi
	cat > "$devdir/050-ultraleap-input-provider.json" <<JSON
{
    "file_format_version": "1.0",
    "plugin": {
        "id":           "ultraleap",
        "display_name": "$name",
        "vendor":       "DisplayXR",
        "version":      "$ver",
        "binary_path":  "$bin",
        "probe_order":  50
    }
}
JSON
	echo "Dev manifest: $devdir/050-ultraleap-input-provider.json"
	echo "Try:  XRT_PLUGIN_SEARCH_PATH=$devdir displayxr-cli input list"
fi
