#!/usr/bin/env bash
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# Package a `cmake --install` tree as a user-level tarball (Linux):
#   package_posix.sh <dist-dir> <version> <runtime-pin> <out-dir>
#
# The tarball carries install.sh, which copies the provider to
# ${XDG_DATA_HOME:-~/.local/share}/DisplayXR/Ultraleap and writes the discovery
# manifest 050-ultraleap-input-provider.json beside the other plug-in manifests
# (input-provider-discovery spec: the `-input-provider.json` suffix routes it to
# the input loader; NNN = ProbeOrder).
#
# libLeapC.so is NOT shipped: the provider's DT_NEEDED resolves it from the
# Ultraleap tracking package the user installed (install.sh checks and says so).
# The tarball refuses to be built from a compile-check (stub) tree.
set -euo pipefail
dist=$1; ver=$2; pin=$3; out=$4
so=$(find "$dist" -name 'DisplayXR-Ultraleap.so' | head -1)
if [ -z "$so" ]; then
	echo "package_posix.sh: no DisplayXR-Ultraleap.so under $dist (a stub build is never packaged)" >&2
	exit 1
fi
name=displayxr-ultraleap-$ver-linux-$(uname -m)
root=$(mktemp -d)
stage=$root/$name
mkdir -p "$stage/payload" "$out"
cp "$so" "$stage/payload/"
cp "$(dirname "$0")/../LICENSE" "$stage/payload/LICENSE"
echo "$ver" > "$stage/VERSION"
echo "$pin" > "$stage/RUNTIME_PIN"

cat > "$stage/install.sh" <<'INST'
#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}/DisplayXR
dest=$data/Ultraleap
ver=$(cat "$here/VERSION")
pin=$(cat "$here/RUNTIME_PIN")
mkdir -p "$dest" "$data/DisplayProcessors"
cp -a "$here/payload/." "$dest/"

# External prerequisite: the Ultraleap tracking software (libLeapC + its service).
if ! ldd "$dest/DisplayXR-Ultraleap.so" 2>/dev/null | grep -q 'libLeapC.*=> /'; then
	echo "WARNING: libLeapC was not found by the dynamic loader."
	echo "         Install the Ultraleap tracking software for Linux; until then the"
	echo "         provider fails to load and DisplayXR keeps its keyboard/mouse controllers."
fi
# The runtime pin is exact (the device struct is not ABI-versioned, runtime
# ADR-063). Not checked here: reading the runtime's version means instantiating
# it (`displayxr-cli info`, line `git-tag:`), which an installer should not do.
echo "NOTE: this provider build is made for DisplayXR runtime $pin exactly."
echo "      Compare with the 'git-tag:' line of 'displayxr-cli info'."

tmp=$(mktemp "$data/DisplayProcessors/.ul.XXXXXX")
cat > "$tmp" <<JSON
{
    "file_format_version": "1.0",
    "plugin": {
        "id":           "ultraleap",
        "display_name": "Ultraleap Hand Tracking (controller emulation)",
        "vendor":       "DisplayXR",
        "version":      "$ver",
        "binary_path":  "$dest/DisplayXR-Ultraleap.so",
        "probe_order":  50
    }
}
JSON
mv "$tmp" "$data/DisplayProcessors/050-ultraleap-input-provider.json"
echo "installed to $dest (runtime pin $pin)"
INST

cat > "$stage/uninstall.sh" <<'UNINST'
#!/usr/bin/env bash
# Removes only this provider's manifest and files.
set -euo pipefail
data=${XDG_DATA_HOME:-$HOME/.local/share}/DisplayXR
rm -f "$data/DisplayProcessors/050-ultraleap-input-provider.json"
rm -rf "$data/Ultraleap"
UNINST

chmod +x "$stage/install.sh" "$stage/uninstall.sh"
tar -C "$root" -czf "$out/$name.tar.gz" "$name"
rm -rf "$root"
echo "$out/$name.tar.gz"
