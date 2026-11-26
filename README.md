# DisplayXR Ultraleap hands

An input provider for the [DisplayXR runtime](https://github.com/DisplayXR/displayxr-runtime):
an Ultraleap / Leap Motion camera on the desk becomes a pair of OpenXR controllers
and `XR_EXT_hand_tracking` joints in every app on a DisplayXR display.

- Binary: `DisplayXR-Ultraleap.dll`, one export, `xrtInputPluginNegotiate`.
- Registered id: `ultraleap`, ProbeOrder 50.
- Palm pose → grip / aim, pinch → select, grab → menu (`khr/simple_controller`), plus
  the 26-joint hand set. Hands are placed relative to the display; every knob is a
  setting (`displayxr-cli input options ultraleap`).
- **Windows only.** Linux and macOS build files are kept and exercised in CI, but
  those platforms are experimental: unsupported and not released.

The provider started as the runtime's in-tree `src/xrt/drivers/ultraleap/` (v2.69.3)
and was then changed here: it binds LeapC at run time instead of linking it, its two
environment knobs became settings, and it owns the advice about Ultraleap's OpenXR
layer. This repository also serves as a worked example of an out-of-tree input
provider that wraps a vendor SDK ([`docs/template-notes.md`](docs/template-notes.md)).

> **State: prepared, not validated on hardware.** Nothing here has run against the
> real Ultraleap software or a camera. No release has been made. See
> [What has and has not been verified](#what-has-and-has-not-been-verified).

## Prerequisites

To **use** it:

1. A DisplayXR runtime in the verified range — currently **2.70.7** (only)
   ([how the range is determined](docs/trunk-dependencies.md#7-the-rule); the current
   values are in [`catalog/ultraleap-hands.json`](catalog/ultraleap-hands.json)).
2. The **Ultraleap tracking software** (Gemini / Hyperion) from Ultraleap, with its
   tracking service running. It is not included and not downloaded for you. The
   provider finds it at run time; without it the provider still loads, reports its
   hardware absent, and the runtime keeps its keyboard/mouse controllers — and it
   starts working by itself once the software is installed.
3. A supported Ultraleap / Leap Motion camera, on the desk facing up.
4. Read [the layer caveat](#the-ultraleap-openxr-layer-caveat) below.

To **build** it, additionally:

- the Ultraleap SDK's header, `LeapC.h` (only the header — nothing links LeapC).
  Point `LEAPSDK_DIR` at an SDK root, or install the SDK in the default place
  (`C:\Program Files\Ultraleap\LeapSDK`);
- the runtime's own build prerequisites, because this project compiles runtime
  libraries from source: VS 2022 + Ninja + the runtime's vcpkg set on Windows.

## Build (Windows)

```bat
set LEAPSDK_DIR=C:\Program Files\Ultraleap\LeapSDK
scripts\build-windows.bat all
```

On Windows a local runtime checkout **at the pinned tag** that has been built once
with its own `scripts\build_windows.bat` is **required** (it then carries the vcpkg
toolchain and the OpenXR loader). `build-windows.bat` picks up the sibling
`..\displayxr-runtime` automatically, or set `DXR_RUNTIME_SOURCE_DIR`; without one
(or without its `vcpkg\`) the script stops before configuring, because the
fetch-the-tag route has no source for the runtime's dependencies.
`.github/workflows/build.yml` shows the same build from scratch, supplying them
itself (`DXR_ALLOW_FETCH_RUNTIME=1` lets the script take that route).

Keep the checkout at a **short path** (e.g. `C:\dxr-ul`): CMake's stamp files under
`build\_deps\` otherwise pass Windows' 260-character limit and ninja fails with
`Filename longer than 260 characters`. The script warns when the path is longer than
80 characters.

Without `LeapC.h`, configure prints `Ultraleap input provider: NOT BUILT - LeapC SDK
not found`, and only the hardware-free tests are built.

### The stand-in build

`-DULTRALEAP_USE_LEAPC_STUB=ON` compiles the provider against `tests/leapc_stub/`, a
stand-in for the SDK header written from this provider's usage. The result is named
`DisplayXR-Ultraleap-STUBCHECK`, is never installed or packaged, and will bind only
the stand-in library (`tests/leapc_stub` built as `LeapC.dll`), never a real LeapC.
It exists so that CI and SDK-less machines can build the provider, load it through
the runtime, and exercise the "no Ultraleap software" path. It produces no hand data.

```bash
# Linux / macOS (experimental): unit tests, stand-in build, load check
scripts/build-posix.sh --stub
cmake --build build-stub --target cli drv_sim_display_plugin leapc_stub
scripts/ci-load-check.sh build-stub
```

### The runtime pin and range

`DXR_RUNTIME_GIT_TAG` in `CMakeLists.txt` (currently `v2.70.7`) is the runtime release
the provider is built at; `RUNTIME_REF` in the workflows repeats it and CI fails when
they differ. A binary built there is valid on every runtime release whose shared
headers are identical to that tag's. `scripts/runtime_range.py` computes that range
from the runtime's tags, the catalog entry records it, CI refuses a range that is not
true, and a weekly workflow reports when a new runtime release needs the range raised
(identical headers) or the provider rebuilt (changed headers).

## Register for development (Windows)

Elevated prompt, from a runtime checkout. Re-run after every rebuild, because it also
allowlists the DLL's digest:

```bat
<runtime>\scripts\register_dev_plugin.bat input <this repo>\_package\bin\plugins\DisplayXR-Ultraleap.dll ultraleap
displayxr-cli input list
displayxr-cli input options ultraleap
displayxr-cli selftest
```

Use a `displayxr-cli` from a runtime release inside the range.

## Settings

| Key | Default | |
|---|---|---|
| `MAPPING` | `relative` | `relative`: hands placed in display heights, no measuring; `physical`: 1:1 metres from a measured mount |
| `ANCHOR_X_H`, `ANCHOR_Y_H`, `ANCHOR_Z_H`, `GAIN_H_PER_M` | 0, -0.625, 0, 2.5 | relative mapping |
| `MOUNT_X_M`, `MOUNT_Y_M`, `MOUNT_Z_M` | 0, -0.15, 0.10 | physical mapping |
| `SETTLE_MS` | 300 | how long `xrCreateInstance` waits for a "camera attached?" answer (was `DXR_ULTRALEAP_SETTLE_MS`) |
| `PERSIST_HUB` | 1 | keep one Leap connection for the process (was `DXR_ULTRALEAP_PERSIST_HUB`) |
| `LEAPC_PATH` | empty | where `LeapC.dll` is, if not in the default Ultraleap location |
| `TRACKING_MODE` | `desktop` | `desktop`: ask the Ultraleap service for Desktop mode and put it back after another app switches it; `leave`: never change it (a head-mounted Leap) |

`displayxr-cli input set ultraleap <KEY> <value>` (per user, next session), or
`DXR_INPUT_ULTRALEAP_<KEY>` in the hosting process. The two old `DXR_ULTRALEAP_*`
variables still work for one release, with a warning.

## Install (end users)

`DisplayXRUltraleapSetup-<version>.exe` installs one file to
`C:\Program Files\DisplayXR\Plugins\Ultraleap\` and registers
`HKLM\Software\DisplayXR\InputProviders\ultraleap`. It installs nothing of
Ultraleap's. It stops if the installed runtime is older than the range and tells you
if the Ultraleap software or its OpenXR layer needs attention. Details:
[docs/packaging.md](docs/packaging.md). No installer has been released yet.

## The Ultraleap OpenXR layer caveat

Ultraleap's installer registers its own OpenXR API layer,
`XR_APILAYER_ULTRALEAP_hand_tracking`, as an **implicit** layer. The OpenXR loader
puts implicit layers into every OpenXR app, whichever runtime is active — DisplayXR
apps and the DisplayXR Browser included. Once such an app creates a hand tracker,
the layer switches the Ultraleap tracking service to **Head-mounted** mode and
switches it back within about a second of any change. With the camera on the desk
that swaps left and right and turns sideways motion into depth. (Measured on a Leap
Motion Controller 2 with Ultraleap 6.2.0: an app that only loads the layer did not
switch it.)

What this repository does about it (#9):

- **The installer offers to turn the layer off** (its HKLM implicit-layer DWORD = 1),
  records what it changed, and turns it back on at uninstall unless someone changed
  it since. `/LAYER=off` or `/LAYER=keep` decides without asking; a silent install
  without `/LAYER` turns it off only when DisplayXR is the active OpenXR runtime.
- **The provider holds Desktop** (`TRACKING_MODE=desktop`): it asks for Desktop at
  connect, logs the mode the service reports, and puts Desktop back after a one-off
  switch. Against the layer's immediate push-back it stops for a minute with one
  warning instead of flapping the tracker, then retries once.
- The provider logs the layer advice once while the layer is enabled, and
  `displayxr-cli selftest` / `info` report `WARN: ULTRALEAP_OPENXR_LAYER`.

By hand, per user: set `DISABLE_XR_APILAYER_ULTRALEAP_HAND_TRACKING_1=1` in the
**user** environment (the layer manifest's own off switch) and restart every OpenXR
app that already loaded the layer, browsers included. The same layer also intercepts
`XR_EXT_hand_tracking` before it reaches the runtime; see the runtime's
`docs/getting-started/troubleshooting.md`.

## What has and has not been verified

Checked by running — locally on macOS (arm64) and in CI on hosted Linux, macOS and
Windows runners, all **without** the Ultraleap SDK, against the in-repo stand-in:

- configure without the SDK ends in the "NOT BUILT" message;
- unit tests: the display-plane mapping, the settings (including the two former
  environment knobs), and the run-time LeapC loader (found / not found / a library
  that is not LeapC is refused);
- the provider builds against the stand-in header with exactly one exported symbol
  and no dependency on LeapC;
- the stand-in build loads through the real `v2.69.3` loader in `displayxr-cli`: with
  no LeapC it reports "Ultraleap tracking software NOT FOUND", creates both devices,
  says ABSENT, and `selftest` passes; with the stand-in library named by `LEAPC_PATH`
  it binds it and opens a connection. On Windows this runs with the runtime in one
  directory tree and the provider in another, as the installer lays them out;
- locally on macOS only: the stand-in library appearing while the provider is already
  running is picked up within the 5 s retry; a syntax-only compile of the sources
  against a real `LeapC.h` (an older copy found in an unrelated local SDK tree, not
  part of this repository), including the check that the bound function-pointer types
  are that header's prototypes;
- the NSIS script compiles with a placeholder payload; the catalog's runtime range is
  re-derived from the runtime's tags.

See the latest [`build` run](../../actions/workflows/build.yml) for the current state
of each job.

Not verified — everything that needs the real Ultraleap software, or a camera:

- a build against the real, current `LeapC.h`, and binding the real `LeapC.dll`
  (entry-point names, calling convention, struct layouts as the provider reads them);
- the default location the provider looks in for `LeapC.dll`;
- tracking: hands, pinch / grab, presence on plug and unplug, the idle watchdog;
- the installer and uninstaller actually running;
- the `sdk-windows` and `release` jobs (need a self-hosted runner with the SDK); the
  signing script (no provider was contacted);
- the catalog entry (a draft in a schema the catalog does not have yet).

The checklist for the Windows box with the hardware is
[docs/windows-validation.md](docs/windows-validation.md).

## Documents

| | |
|---|---|
| [docs/trunk-dependencies.md](docs/trunk-dependencies.md) | what the provider uses from the runtime beyond the public contract, and the runtime-range rule |
| [docs/packaging.md](docs/packaging.md) | registration, run-time LeapC binding and #933, the range in the installer, signing |
| [docs/windows-validation.md](docs/windows-validation.md) | what to check on the Windows box with the camera |
| [docs/template-notes.md](docs/template-notes.md) | turning this repository into your own provider |
| [docs/trunk-removal-plan.md](docs/trunk-removal-plan.md) | the runtime-repo edits for removing the in-tree copy |
| [catalog/ultraleap-hands.json](catalog/ultraleap-hands.json) | draft component-catalog entry |

## Licence

Provider sources: BSL-1.0 (from the DisplayXR runtime; the LeapC poll loop and joint
processing derive from Monado's `ultraleap_v5` driver, © Joseph Albers — headers
kept). Installer files adapted from `displayxr-input-template`: Apache-2.0. The
Ultraleap SDK and LeapC are Ultraleap's and are not part of this repository;
`tests/leapc_stub/` is an original stand-in, not Ultraleap code.
