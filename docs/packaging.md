# Packaging: registration, LeapC, the runtime range, signing

Status of everything on this page: **written, not run on Windows hardware.** The NSIS
script compiles (CI, placeholder payload); no installer has been built from a real
provider DLL, installed, or uninstalled. Items marked *to verify* need the Windows box
with the Ultraleap hardware.

Windows is the only supported platform. Linux and macOS build files are kept and
exercised in CI against a stand-in, but nothing is released for them.

## What gets registered (Windows)

| Registration | Written by |
|---|---|
| `HKLM\Software\DisplayXR\InputProviders\ultraleap` (64-bit view): `Binary`, `DisplayName`, `Vendor`, `ProbeOrder` = 50, `UninstallString`, `Version` (written last) | `installer/DisplayXRUltraleapInstaller.nsi` |
| `HKLM\Software\DisplayXR\Trust\Allowlist\<sha256 of the DLL>` | generated at packaging time by `installer/gen_allowlist_nsh.cmake`; removed by the uninstaller |
| `HKLM\Software\DisplayXR\Plugins\Ultraleap`: `InstallPath`, `Version`, `RuntimePin`, `RuntimeMin`, `RuntimeVerifiedMax`, `AllowlistDigest`, `UltraleapSoftware` | the installer's own bookkeeping |

ProbeOrder 50 is the value the runtime's documentation gives for this provider
(gamepad 150, sim-stylus 190, sim-input 200). The registry subkey is `ultraleap`, the
provider's declared `iface->id` — the id the CLI's `input set / use / enable` take.

Files install to `C:\Program Files\DisplayXR\Plugins\Ultraleap\`, a sibling of
`Runtime\`, never inside it. The installer ships exactly one binary,
`DisplayXR-Ultraleap.dll`, has no install-order requirement, and owns only the rows
above.

The provider imports `u_log` / `u_var` from the runtime's `DisplayXRClient.dll`. From
its own directory it could not find that DLL; it does not have to, because the
runtime's loader pins `DisplayXRClient.dll` into the hosting process by absolute path
before loading any component (`target_plugin_preload_runtime_core_dll`). CI checks
this with exactly this layout — runtime in one tree, provider in another
(`scripts/ci-load-check.ps1`).

## LeapC: bound at run time, never shipped

The provider does not link LeapC. It is compiled against `LeapC.h` and binds the six
entry points it calls when it starts (`src/ultraleap/ultraleap_leapc.c`):

1. the `LEAPC_PATH` setting, if set — the library, or the directory holding it;
2. otherwise `%ProgramW6432%\Ultraleap\LeapSDK\lib\x64\LeapC.dll` (*to verify*: that
   this is where the current Ultraleap installer puts it).

It opens the library by **absolute path** with `LOAD_WITH_ALTERED_SEARCH_PATH` and
never by bare name.

| Question | Answer |
|---|---|
| What of Ultraleap's does DisplayXR ship, copy or stage? | Nothing. No redistribution question arises. |
| #933 — the LeiaSR Platform puts its own `LeapC.dll` on `PATH`; could the provider bind that one? | No. Nothing is resolved through `PATH`: the provider has no import of `LeapC.dll` (CI asserts it with `dumpbin /dependents`) and only ever opens the one absolute path. |
| Which LeapC version runs? | The one the user's Ultraleap tracking service came with. It cannot go stale relative to the service. |
| The Ultraleap software is not installed | Not an error. The provider loads, logs `Ultraleap tracking software NOT FOUND (no LeapC library at: …)`, creates its devices, and reports its hardware **absent**, so the runtime keeps its keyboard/mouse controllers. It looks again every 5 s: installing the Ultraleap software later needs no reinstall and no restart of DisplayXR. |
| A LeapC that cannot be used (does not load, lacks an entry point) | Same behaviour, with `found but NOT USABLE` and the reason in the log. |
| The Ultraleap software is in a non-default place | `displayxr-cli input set ultraleap LEAPC_PATH <folder holding LeapC.dll>` (per user), or `DXR_INPUT_ULTRALEAP_LEAPC_PATH` in the hosting process. |

How "not found" is reported: the input-provider contract has no platform-state slot
(the display-processor contract does), so the state reaches the runtime as
`get_presence()` = `ABSENT`, the user as the log line above, and a debugger as the
`leapc_state` variable of the "Ultraleap Input Hub" `u_var` root. A platform-state slot
on the input iface would let `displayxr-cli` say "Ultraleap software not installed"
instead of "hardware absent"; that is a runtime change, noted in
`docs/trunk-removal-plan.md`.

The installer **looks** for `LeapC.dll` in the default place only to tell the user
(a note in the log, a dialog when interactive, `UltraleapSoftware` in its registry
key). It installs either way.

*How this was tested:* against the in-repo stand-in library only, on macOS and in CI
on Linux, macOS and Windows — the loader's found / not-found / refused paths
(`tests/tests_ultraleap_leapc.c`), the provider running through the pinned runtime in
the not-found state and with the stand-in bound, and the stand-in appearing while the
provider was already running. Never against a real LeapC.

## The runtime range in the installer

One provider binary is valid for the runtime releases whose shared headers are
identical to the one it was built at (`docs/trunk-dependencies.md`, "The rule"). The
installer is given `RUNTIME_MIN` and `RUNTIME_MAX` (the catalog's `runtime_range.min`
and `verified_max`) and, **when a runtime is installed**
(`HKLM\Software\DisplayXR\Runtime\Version` present):

- older than `RUNTIME_MIN` → stops, exit code 3 (`/FORCE` overrides);
- newer than `RUNTIME_MAX` → says the build was not verified for it, and installs.
  "Newer than verified" is not "known bad", and the installer's maximum is frozen at
  build time while the catalog's is not.

With no runtime installed it proceeds.

*To verify:* the exact format of the runtime's `Version` value (the comparison takes
the first three dot-separated components).

## The Ultraleap implicit OpenXR layer

The installer checks `HKLM\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit` for an
enabled `UltraleapHandTracking` manifest and, if it finds one, explains the desk-use
workaround (`DISABLE_XR_APILAYER_ULTRALEAP_HAND_TRACKING_1=1`). It is advisory: the
installer never changes the layer's registration or anyone's environment. The
provider logs the same advice once per process (`ultraleap_layer.c`).

*To verify:* the manifest's value name on the test box (the check looks for
`UltraleapHandTracking` in it), and whether the per-user hive needs checking too (the
runtime's lookup reads both; the installer reads HKLM only, because an elevated
installer's HKCU is not reliably the user's).

## Signing

The runtime's convention (`docs/specs/runtime/release-signing.md` there):

- CI builds are unsigned. The installer carries the allowlist row, so an unsigned
  provider still passes the enforcing provenance gate.
- A signed release is produced by a **signing provider**: a repository named by the
  `DXR_SIGN_REPO` environment variable on the release machine. It rebuilds the tag on
  its own runner with a runner-local `SIGN_CMD` and the unsigned asset is replaced.
  This repository names no provider.
- Signing never gates publishing.

What this repository provides for it:

- `SIGN_CMD` in the environment makes `scripts\build-windows.bat all` a full signed
  build: the provider DLL is signed in the install tree first, the allowlist digest is
  taken from the signed bytes, then NSIS signs the installer and the uninstaller.
- `scripts/sign-release.sh <tag>` dispatches `$DXR_SIGN_REPO`'s
  `build-signed-release.yml` with `component=ultraleap`, follows the run it
  dispatched (never "the newest"), re-dispatches once if displaced, checks that the
  artifact is exactly `DisplayXRUltraleapSetup-<version>*.exe`, and replaces the
  release asset. Every failure leaves the unsigned asset in place.
- `release.yml` runs that script only when a repository **variable** `DXR_SIGN_REPO`
  is set.

Provider-side work that does not exist yet: the signing provider must learn the
`ultraleap` component, and its runner needs the Ultraleap SDK header (`LEAPSDK_DIR`)
because the signed build compiles the DLL.

## Linux and macOS (experimental)

`cmake --install` writes `<prefix>/share/DisplayXR/DisplayProcessors/050-ultraleap-input-provider.json`
(from `manifest/050-ultraleap-input-provider.json.in`) and `scripts/package_posix.sh`
can make a user-level tarball. Neither is released or supported. Known obstacles to a
standalone package: on macOS the provider depends on `@rpath/openxr_displayxr.dylib`
and on a cJSON dylib (`docs/trunk-dependencies.md`); on both, the default LeapC
locations are guesses.
