# Packaging: registration, LeapC.dll, signing

Status of everything on this page: **written, not run on Windows.** The NSIS script
compiles (`makensis` on macOS, with placeholder payloads); no installer has been
built from a real provider DLL, installed, or uninstalled. Items marked *to verify*
need the Windows box with the Ultraleap hardware.

## What gets registered

| Platform | Registration | Written by |
|---|---|---|
| Windows | `HKLM\Software\DisplayXR\InputProviders\ultraleap` (64-bit view): `Binary`, `DisplayName`, `Vendor`, `ProbeOrder` = 50, `UninstallString`, `Version` (written last) | `installer/DisplayXRUltraleapInstaller.nsi` |
| Windows | `HKLM\Software\DisplayXR\Trust\Allowlist\<sha256 of the DLL>` | generated at packaging time by `installer/gen_allowlist_nsh.cmake`; removed by the uninstaller |
| Windows | `HKLM\Software\DisplayXR\Plugins\Ultraleap`: `InstallPath`, `Version`, `RuntimePin`, `AllowlistDigest`, `LeapCState`, `LeapCPlaced`, `LeapCSource` | the installer's own bookkeeping |
| Linux | `${XDG_DATA_HOME:-~/.local/share}/DisplayXR/DisplayProcessors/050-ultraleap-input-provider.json` | `install.sh` inside the tarball (`scripts/package_posix.sh`) |
| Linux / macOS system install | `<prefix>/share/DisplayXR/DisplayProcessors/050-ultraleap-input-provider.json` | `cmake --install` (from `manifest/050-ultraleap-input-provider.json.in`) |

ProbeOrder 50 is the value the runtime's documentation gives for this provider
("the in-tree Ultraleap provider ships at 50"; gamepad 150, sim-stylus 190, sim-input
200). The registry subkey and the manifest `id` are `ultraleap`, the provider's
declared `iface->id` — the id the CLI's `input set / use / enable` take.

Files install to `C:\Program Files\DisplayXR\Plugins\Ultraleap\`, a sibling of
`Runtime\`, never inside it. The installer has no install-order requirement and owns
only the rows above.

## The runtime pin in the installer

The binary is valid for one runtime release (`docs/trunk-dependencies.md`). The
installer is given that release as `RUNTIME_PIN` and, **when a runtime is installed**
(`HKLM\Software\DisplayXR\Runtime\Version` present), compares major.minor.patch. On a
mismatch it stops with exit code 3; `/FORCE` overrides. With no runtime installed it
proceeds, as the onboarding guide requires.

*To verify:* the exact format of the runtime's `Version` value (the comparison takes
the first three dot-separated components).

What it cannot do: notice a runtime that is updated **after** the provider was
installed. That needs the catalog client to honour the range, or the runtime's loader
to check (ADR-063 step 1).

## LeapC.dll: three choices and what #933 means for each

Background (#933). The provider imports `LeapC.dll` by name. The runtime's input
loader loads the provider by absolute path with `LOAD_WITH_ALTERED_SEARCH_PATH`, so
the provider's own directory is searched first for its dependencies. The LeiaSR
Platform installs its own `LeapC.dll` in `LeiaSR\Platform\bin`, which is on the system
`PATH`. A `LeapC.dll` next to the provider therefore wins; with none there, the import
falls through to `PATH` and can bind to LeiaSR's copy, and any version difference
between that copy and the installed Ultraleap tracking service breaks the provider
without an error that says why.

| | Choice | What ships | #933 | Other consequences |
|---|---|---|---|---|
| A | **Copy at install time** — `/LEAPC=copy`, the default | Nothing of Ultraleap's. The installer copies `LeapC.dll` from the user's own Ultraleap install (`%ProgramFiles%\Ultraleap\LeapSDK\lib\x64`, or `/LEAPSDK=<dir>`) into the provider's directory. | **Safe**: app-local copy wins the search. | The copy matches the user's tracking service on the day of install and goes stale when they update the Ultraleap software: re-run the installer. If Ultraleap is not installed, the provider is registered but cannot load; the installer says so and the runtime falls back to keyboard/mouse. Depends on the SDK folder being part of the user's Ultraleap install (*to verify* for the current installer). Whether copying a file on the user's own machine counts as redistribution is a licence question, though a much smaller one than C. |
| B | **Do not place it** — `/LEAPC=none` | Nothing. | **Exposed**: `LeapC.dll` resolves through the Windows search order. On a machine with the LeiaSR Platform that is LeiaSR's copy. On a machine without it, nothing on `PATH` provides `LeapC.dll` unless the user added the SDK folder, and the provider fails to load. | The only choice that touches no Ultraleap file at all. Only useful with a follow-up code change (below). |
| C | **Bundle** — build with `-DULTRALEAP_BUNDLE_LEAPC=ON` (`ULTRALEAP_BUNDLE_LEAPC=1` for `scripts\build-windows.bat`) | The SDK's `LeapC.dll`, packed into the installer. | **Safe**: app-local, and independent of what the user installed. | **Needs Ultraleap's redistribution terms checked first** — not done. The bundled LeapC can be newer or older than the user's tracking service. The release is then tied to one SDK version, and the SDK must be available wherever the release is built and signed. |

The switch for C is off by default and nothing in the release workflow turns it on.

Better than all three, but a code change and therefore not done here: delay-load
`LeapC.dll` and resolve it explicitly from the Ultraleap install directory before the
first LeapC call (the pattern `displayxr-leia-plugin` uses for the SR client DLLs).
That is choice B without the exposure: nothing copied, nothing shipped, always the
user's current LeapC, never LeiaSR's.

The allowlist row covers `DisplayXR-Ultraleap.dll` only. The provenance gate
classifies the component binary the loader opens, not its dependencies.

Dev builds are separate from all of this: `scripts\build-windows.bat` always stages
the SDK's `LeapC.dll` next to the build-tree DLL so that a developer's provider is not
shadowed. That copy is packaged only under choice C.

## The Ultraleap implicit OpenXR layer

The installer checks `HKLM\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit` for an
enabled `UltraleapHandTracking` manifest and, if it finds one, explains the desk-use
workaround (`DISABLE_XR_APILAYER_ULTRALEAP_HAND_TRACKING_1=1`). It is advisory: the
installer never changes the layer's registration or anyone's environment. The
provider logs the same advice once per process, and `displayxr-cli` reports
`ULTRALEAP_OPENXR_LAYER`.

*To verify:* the manifest's value name on the test box (the check looks for
`UltraleapHandTracking` in it), and whether the per-user hive needs checking too (the
runtime's helper reads both; the installer reads HKLM only, because an elevated
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
  taken from the signed bytes, then NSIS signs the installer and the uninstaller
  (`!finalize` / `!uninstfinalize`).
- `scripts/sign-release.sh <tag>` dispatches `$DXR_SIGN_REPO`'s
  `build-signed-release.yml` with `component=ultraleap`, follows the run it
  dispatched (never "the newest"), re-dispatches once if displaced, checks that the
  artifact is exactly `DisplayXRUltraleapSetup-<version>*.exe`, and replaces the
  release asset. Every failure leaves the unsigned asset in place.
- `release.yml` runs that script only when a repository **variable** `DXR_SIGN_REPO`
  is set.

Provider-side work that does not exist yet: the provider must learn the `ultraleap`
component, and its runner needs the Ultraleap SDK (`LEAPSDK_DIR`) because the signed
build compiles the DLL.

## macOS

Not a shipped platform. No macOS LeapC SDK was available, so there is no evidence the
provider works there. Two things are known from the stub build: the provider depends
on `@rpath/openxr_displayxr.dylib` and on a cJSON dylib (`docs/trunk-dependencies.md`,
sections 4 and 5), so a standalone macOS package has to decide where the runtime
library is and what to do about cJSON before it can exist.
