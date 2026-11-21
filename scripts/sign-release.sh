#!/usr/bin/env bash
# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# Replace a release's unsigned installer with a signed one, through the signing
# provider named by DXR_SIGN_REPO (environment only - this repository names no
# provider). Implements the provider contract and the three run-identity rules
# of displayxr-runtime docs/specs/runtime/release-signing.md:
#
#   sign-release.sh <tag> [<owner/repo>]
#
#   - DXR_SIGN_REPO unset / unreachable  -> exit 0, release stays UNSIGNED.
#   - dispatches <DXR_SIGN_REPO>/build-signed-release.yml with
#       component=ultraleap  repo=<owner/repo>  ref=<tag>
#     The provider must know the `ultraleap` component (its build is
#     `scripts\build-windows.bat all` with SIGN_CMD set) and its runner must
#     have the Ultraleap SDK - both are provider-side work, not done yet.
#   - tracks the run `gh workflow run` prints, never "the newest run";
#   - a cancelled run was displaced: wait, re-dispatch ONCE;
#   - asserts the artifact is exactly DisplayXRUltraleapSetup-<version>*.exe
#     before `gh release upload --clobber`.
#
# Signing never gates publishing: every failure path leaves the unsigned asset.
set -uo pipefail

tag=${1:?usage: sign-release.sh <tag> [<owner/repo>]}
repo=${2:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}
ver=${tag#v}
sign_repo=${DXR_SIGN_REPO:-}

unsigned() {
	echo "UNSIGNED: $1 - the release keeps the unsigned CI installer."
	exit 0
}

[ -n "$repo" ] || unsigned "could not determine this repository"
[ -n "$sign_repo" ] || unsigned "DXR_SIGN_REPO is not set"
gh workflow view build-signed-release.yml -R "$sign_repo" >/dev/null 2>&1 ||
	unsigned "signing provider not reachable"

dispatch() {
	# Recent gh prints the created run's URL; that URL is the only identity we trust.
	gh workflow run build-signed-release.yml -R "$sign_repo" \
		-f component=ultraleap -f repo="$repo" -f ref="$tag" 2>&1 |
		grep -Eo 'https://github\.com/[^ ]+/actions/runs/[0-9]+' | tail -1
}

watch_run() { # <run url> -> conclusion
	local id=${1##*/}
	gh run watch "$id" -R "$sign_repo" >/dev/null 2>&1 || true
	gh run view "$id" -R "$sign_repo" --json conclusion -q .conclusion 2>/dev/null
}

url=$(dispatch)
[ -n "$url" ] || unsigned "the dispatch printed no run URL (cannot identify the run safely)"
concl=$(watch_run "$url")
if [ "$concl" = "cancelled" ]; then
	echo "run displaced by another dispatch - waiting for the provider to go idle, then retrying once"
	while [ -n "$(gh run list -R "$sign_repo" -w build-signed-release.yml --json status -q '.[] | select(.status!="completed") | .status' 2>/dev/null)" ]; do
		sleep 30
	done
	url=$(dispatch)
	[ -n "$url" ] || unsigned "the retry printed no run URL"
	concl=$(watch_run "$url")
fi
[ "$concl" = "success" ] || unsigned "signing run ended '$concl' ($url)"

work=$(mktemp -d)
gh run download "${url##*/}" -R "$sign_repo" -n signed-installer -D "$work" >/dev/null 2>&1 ||
	unsigned "could not download the signed-installer artifact"

# Artifact identity: exactly one file, ours, carrying this version.
count=$(find "$work" -type f | wc -l | tr -d ' ')
file=$(find "$work" -type f -name "DisplayXRUltraleapSetup-$ver*.exe" | head -1)
if [ "$count" != "1" ] || [ -z "$file" ]; then
	find "$work" -type f
	unsigned "artifact is not exactly DisplayXRUltraleapSetup-$ver*.exe (another component's run?)"
fi

# Replace the unsigned asset(s) of the same name pattern.
for old in $(gh release view "$tag" -R "$repo" --json assets -q '.assets[].name' | grep -E '^DisplayXRUltraleapSetup-.*\.exe$' || true); do
	[ "$old" = "$(basename "$file")" ] || gh release delete-asset "$tag" "$old" -R "$repo" -y || true
done
gh release upload "$tag" "$file" -R "$repo" --clobber || unsigned "upload failed"
echo "SIGNED: $(basename "$file") uploaded to $repo $tag"
