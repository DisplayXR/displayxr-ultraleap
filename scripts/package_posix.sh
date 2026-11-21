#!/usr/bin/env bash
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# EXPERIMENTAL - Linux is not a supported platform of this provider yet; no
# release lane calls this script.
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
# libLeapC.so is NOT shipped and not linked: the provider binds it at run time
# from the Ultraleap install (LEAPC_PATH setting, or the default locations).
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

# External prerequisite: the Ultraleap tracking software. Not checked here -
# the provider loads without it, reports its hardware absent and logs where it
# looked for libLeapC (set LEAPC_PATH if it is somewhere else).
echo "NOTE: built at DisplayXR runtime $pin; see the release notes for the verified range."
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
