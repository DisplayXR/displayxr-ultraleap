# DisplayXR Ultraleap hands

An input provider for the [DisplayXR runtime](https://github.com/DisplayXR/displayxr-runtime):
an Ultraleap / Leap Motion camera on the desk becomes a pair of OpenXR controllers
and `XR_EXT_hand_tracking` joints in every app on a DisplayXR display.

- Binary: `DisplayXR-Ultraleap.{dll,so,dylib}`, one export, `xrtInputPluginNegotiate`.
- Registered id: `ultraleap`, ProbeOrder 50.
- Palm pose → grip / aim, pinch → select, grab → menu (`khr/simple_controller`), plus
  the 26-joint hand set. Hands are placed relative to the display (`MAPPING`,
  `ANCHOR_*_H`, `GAIN_H_PER_M`, `MOUNT_*_M`; see `displayxr-cli input options ultraleap`).

The sources were moved out of the runtime trunk (`src/xrt/drivers/ultraleap/`) and are
byte-identical to runtime `v2.69.3`. This repository adds a standalone build, an
installer, CI, and a draft catalog entry. It also serves as a worked example of an
out-of-tree input provider that wraps a vendor SDK
([`docs/template-notes.md`](docs/template-notes.md)).

> **State: prepared, not validated.** Nothing here has been built against the real
> Ultraleap SDK or run with a camera since it left the trunk. See
> [What has and has not been verified](#what-has-and-has-not-been-verified).

## Prerequisites

To **use** it:

1. DisplayXR runtime **2.69.3 exactly**. A provider binary is valid for the one
   runtime release it was built at ([why](docs/trunk-dependencies.md)).
2. The **Ultraleap tracking software** (Gemini / Hyperion) from Ultraleap, with its
   tracking service running. It is not included and not downloaded for you. Without
   it the provider cannot load and the runtime keeps its keyboard/mouse controllers.
3. A supported Ultraleap / Leap Motion camera, on the desk facing up.
4. Read [the layer caveat](#the-ultraleap-openxr-layer-caveat) below.

To **build** it, additionally:

- the Ultraleap SDK (`LeapC.h` + the LeapC library). Point `LEAPSDK_DIR` at it, or
  install it in the default place (`C:\Program Files\Ultraleap\LeapSDK`,
  `/opt/ultraleap-hand-tracking/LeapSDK`);
- the runtime's own build prerequisites, because this project compiles runtime
  libraries from source: VS 2022 + Ninja + the runtime's vcpkg set on Windows; the
  package list in the runtime's `scripts/build_linux.sh` on Linux; `brew install cmake
  ninja eigen glslang molten-vk vulkan-headers vulkan-loader` on macOS.

## Build

```bash
# Linux / macOS
scripts/build-posix.sh                      # fetches the runtime at the pinned tag
scripts/build-posix.sh --sdk /path/to/LeapSDK
scripts/build-posix.sh --runtime ../displayxr-runtime   # local checkout (warns if not at the pin)
```

```bat
:: Windows
set LEAPSDK_DIR=C:\Program Files\Ultraleap\LeapSDK
scripts\build-windows.bat all
```

or plain CMake:

```bash
cmake -S . -B build -G Ninja -DLEAPSDK_DIR=/path/to/LeapSDK
cmake --build build && ctest --test-dir build
```

Without the SDK, configure prints `Ultraleap input provider: NOT BUILT - LeapC SDK
not found`, and only the hardware-free mapping test is built and run.

`-DULTRALEAP_USE_LEAPC_STUB=ON` (or `scripts/build-posix.sh --stub`) compiles the
provider against `tests/leapc_stub/`, a stand-in that only lets the sources compile
and link. The result is named `DisplayXR-Ultraleap-STUBCHECK`, is never installed or
packaged, and produces no hand data. It exists so that CI and SDK-less machines can
catch build breaks.

On Windows the realistic setup is a local runtime checkout **at the pinned tag** that
has been built once with its own `scripts\build_windows.bat` (it then carries the
vcpkg toolchain and the OpenXR loader); `build-windows.bat` picks up the sibling
`..\displayxr-runtime` automatically.

### The runtime pin

`DXR_RUNTIME_GIT_TAG` in `CMakeLists.txt` (currently `v2.69.3`) is an **exact** pin,
repeated as `RUNTIME_REF` in the workflows and as the range in
`catalog/ultraleap-hands.json`; CI fails when they differ. Moving it means a new
release of this provider.

## Register for development

**Windows** (elevated prompt; from a runtime checkout). Re-run after every rebuild,
because it also allowlists the DLL's digest:

```bat
<runtime>\scripts\register_dev_plugin.bat input <this repo>\_package\bin\plugins\DisplayXR-Ultraleap.dll ultraleap
displayxr-cli input list
displayxr-cli selftest
```

`build-windows.bat` stages the SDK's `LeapC.dll` next to the dev DLL so that another
`LeapC.dll` on `PATH` (the LeiaSR Platform installs one) cannot shadow it
([docs/packaging.md](docs/packaging.md)).

**Linux / macOS**: write a manifest that points at the build-tree binary into a
directory of your choice and hand that directory to the runtime:

```bash
scripts/build-posix.sh --sdk /path/to/LeapSDK --dev-plugins /tmp/dxr-dev-plugins
XRT_PLUGIN_SEARCH_PATH=/tmp/dxr-dev-plugins displayxr-cli input list
XRT_PLUGIN_SEARCH_PATH=/tmp/dxr-dev-plugins displayxr-cli selftest   # also needs a display plug-in manifest there
```

Use a `displayxr-cli` from the **same runtime release** as the pin.

## Install (end users)

`DisplayXRUltraleapSetup-<version>.exe` installs to
`C:\Program Files\DisplayXR\Plugins\Ultraleap\`, registers
`HKLM\Software\DisplayXR\InputProviders\ultraleap`, and copies `LeapC.dll` from your
Ultraleap install next to the provider. It stops if the installed runtime is not the
release this build was made for. Details, switches and the reasoning:
[docs/packaging.md](docs/packaging.md).

## The Ultraleap OpenXR layer caveat

Ultraleap's installer registers its own OpenXR API layer,
`XR_APILAYER_ULTRALEAP_hand_tracking`, as an **implicit** layer. The OpenXR loader
puts implicit layers into every OpenXR app, whichever runtime is active — DisplayXR
apps and the DisplayXR Browser included — and each load switches the Ultraleap
tracking service back to **Head-mounted** mode. With the camera on the desk that
swaps left and right and turns sideways motion into depth.

For desk use:

1. Set `DISABLE_XR_APILAYER_ULTRALEAP_HAND_TRACKING_1=1` in the **user** environment
   (the layer manifest's own off switch).
2. Close every OpenXR app that already loaded the layer, browsers included.
3. Select Desktop mode again in the Ultraleap Control Panel.

The provider logs this once when the layer is active, `displayxr-cli selftest` /
`info` report `WARN: ULTRALEAP_OPENXR_LAYER`, and the installer says it too. None of
them changes the layer for you. The same layer also intercepts
`XR_EXT_hand_tracking` before it reaches the runtime; see the runtime's
`docs/getting-started/troubleshooting.md`.

## What has and has not been verified

Checked by running, on macOS (arm64), with **no** Ultraleap SDK:

- CMake configure fetching the runtime at `v2.69.3`, ending in the "NOT BUILT"
  message;
- the mapping unit test (`tests_ultraleap_map`) built and passing;
- the provider sources compiling and linking against the **stub** LeapC, with exactly
  one exported symbol;
- that stub build loading through the real `v2.69.3` loader in `displayxr-cli`:
  `input list` shows the row; `selftest` negotiates input ABI 1, creates both devices,
  claims the hand-tracking roles, reports the hardware absent and passes;
- the provider sources passing a syntax-only compile against a real `LeapC.h` (an
  older copy found in an unrelated local SDK tree, not committed here);
- the NSIS script compiling with placeholder payloads; `actionlint` and `shellcheck`
  clean; the catalog checker.

Not verified — everything that needs the SDK, Windows, or a camera:

- any build against the real LeapC library, on any platform;
- any Windows build at all (MSVC, the `dllimport` linkage, the import table);
- the installer and uninstaller actually running; the `LeapC.dll` copy step; the
  default SDK path; the runtime-version check against a real registry;
- tracking: hands, pinch / grab, presence on plug and unplug, the idle watchdog;
- the Linux build (`--no-undefined`, the version script) and the tarball;
- both workflows (never executed); the signing script (no provider was contacted);
- the catalog entry (a draft in a schema the catalog does not have yet).

## Documents

| | |
|---|---|
| [docs/trunk-dependencies.md](docs/trunk-dependencies.md) | what the provider uses from the runtime beyond the public contract, and the exact-pin rule |
| [docs/packaging.md](docs/packaging.md) | registration, the three LeapC.dll choices and #933, signing |
| [docs/template-notes.md](docs/template-notes.md) | turning this repository into your own provider |
| [docs/trunk-removal-plan.md](docs/trunk-removal-plan.md) | the runtime-repo edits for removing the in-tree copy |
| [catalog/ultraleap-hands.json](catalog/ultraleap-hands.json) | draft component-catalog entry |

## Licence

Provider sources: BSL-1.0 (from the DisplayXR runtime; the LeapC poll loop and joint
processing derive from Monado's `ultraleap_v5` driver, © Joseph Albers — headers
kept). Installer files adapted from `displayxr-input-template`: Apache-2.0. The
Ultraleap SDK and `LeapC` are Ultraleap's and are not part of this repository.
