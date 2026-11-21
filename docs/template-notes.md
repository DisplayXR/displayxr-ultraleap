# Using this repository as the starting point for your own input provider

## First: is this the right starting point?

There are two out-of-tree input-provider starting points, and they make opposite
trade-offs.

| | [`displayxr-input-template`](https://github.com/DisplayXR/displayxr-input-template) | this repository |
|---|---|---|
| Device | a 6-DoF stylus (one dominant-hand device) | a left/right hand pair + 26-joint hand tracking |
| Vendor SDK | none; a transport stub you replace | a real, non-redistributable SDK (LeapC): header found at configure time, library bound at run time from the vendor's own install |
| Runtime dependency | **public headers only** — no runtime build, no aux, no import library | the runtime source at a pinned tag: static aux libraries, and the runtime's import library on Windows / macOS |
| Build time | seconds | minutes (it builds runtime libraries) |
| Runtime range of one binary | bounded the same way (it fills `xrt_device` too), but nothing else couples it | bounded by the shared headers, computed and CI-checked (`docs/trunk-dependencies.md`, section 7), and coupled in a few more ways |
| What it shows | the contract, minimal | a production provider: process-scoped transport hub, presence from transport events, an idle watchdog, timestamped pose history with prediction, a pure unit-tested mapping layer, run-time binding of a vendor library with a "vendor software not installed" state, SDK-less CI that still loads the provider through the runtime |

Start from `displayxr-input-template` unless you specifically need what the right
column has. Linking runtime aux buys `m_relation_history`, `u_device_allocate` and the
shared log sink, and costs you the build time and the couplings. If you do start here,
the notes below are what to change.

## What to change

### 1. Names (mechanical)

| Here | Yours |
|---|---|
| `ultraleap` — `iface->id`, the registry subkey, the manifest id, `PROVIDER_ID` in the `.nsi` | your id, lower-case, the one string users type in `displayxr-cli input use <id>`. It must be identical in all four places. |
| `DisplayXR-Ultraleap` — `OUTPUT_NAME`, `PROVIDER_DLL` | `DisplayXR-<YourDevice>` |
| `displayxr_ultraleap` (CMake target), `src/ultraleap/`, the `ul_` / `UL_` prefixes | your own |
| `Plugins\Ultraleap`, `DisplayXRUltraleap` (ARP key), `DisplayXRUltraleapSetup-*` | your own |
| `050-ultraleap-input-provider.json` | `NNN-<id>-input-provider.json`, NNN = your ProbeOrder |
| `ULTRALEAP_*` CMake options and `ULTRALEAP_ALLOWLIST_*` NSIS macros | your own |
| `.vendor = "DisplayXR"`, `display_name` in `ultraleap_plugin.c` | yours |

Pick a **ProbeOrder** in 1–99 that differs from every provider you expect to coexist
with (this one is 50; the runtime's gamepad is 150, its simulated providers 190–200).

### 2. The SDK seam

- `cmake/FindLeapC.cmake` → a find module for your SDK's **header**. Keep its shape:
  an explicit root variable, the default install paths, a `*_FOUND` result, and
  **your own cache variable names**.
- `src/ultraleap/ultraleap_leapc.{h,c}` → the run-time binding. This is the pattern
  for a vendor library you may not ship: a table of function pointers, opened by
  absolute path from the vendor's install (a setting to override the location), a
  small state (`loaded` / `not-found` / `incompatible`) instead of a load failure,
  and a compile-time check that the table's types are the header's prototypes. Change
  the entry-point list, the file name and the default locations.
- The provider's side of it: `ul_hub_ensure_connection` and the top of
  `ul_poll_thread` in `ultraleap_provider.cpp` — come up without the vendor library,
  report `ABSENT`, retry.
- The configure-time message in the top-level `CMakeLists.txt` ("NOT BUILT - LeapC SDK
  not found"): keep one like it. A silently skipped target is how a provider goes
  unbuilt for months.
- `tests/leapc_stub/` → a stand-in for *your* SDK, written from *your* sources' usage:
  a header so the provider compiles without the SDK, and a shared library the run-time
  loader can open in tests. Keep the guard rails: a stand-in build has a different
  output name and no install or packaging rule; it binds only a library carrying the
  stand-in's marker symbol, and a real build refuses that library; CI says loudly that
  it proves compile, link and load only.
- If your SDK **can** be redistributed, link it and ship its DLLs next to your
  provider instead; if your provider has no SDK at all, you are much closer to
  `displayxr-input-template`.

### 3. The provider itself

`ultraleap_plugin.c` (entry point, host slots, settings) and the hub / device split in
`ultraleap_provider.cpp` are the reusable shape. Replace:

- the poll thread's SDK calls and event handling (`ul_poll_thread`,
  `ul_handle_tracking_event`, `ul_handle_presence_event`);
- the device description in `ul_create_device`: `name` (the interaction profile),
  `device_type` (the role), the inputs and outputs, the tracking-origin type. A stylus
  uses `XRT_DEVICE_TYPE_DOMINANT_HAND_CONTROLLER` and
  `XRT_TRACKING_TYPE_RIG_LOCAL_PHYSICAL`, not what is here;
- `ultraleap_map.{c,h}`: the sensor-frame → display-plane mapping and the settings it
  declares. Keep it pure (no SDK, no OS) so its tests run anywhere.

Keep, because the runtime's contract depends on them:

- `probe()` always succeeds; hardware presence is `get_presence()`, maintained by the
  transport thread, non-blocking;
- the expensive part (SDK connection, threads) is process-scoped and created lazily;
  the devices are cheap and per `xrCreateInstance`;
- poses go through a timestamped history and `get_tracked_pose` answers for the
  requested time;
- no rig, navigation or head-parallax compensation in the poses you publish;
- one exported symbol; every host slot `struct_size`- and NULL-checked.

Read every knob through `host->get_setting` and declare it in `describe_settings`
(`ultraleap_map.c` holds the whole table, pure and unit-tested). Never `getenv` a
knob: inside the service the environment is the service's.

### 4. The runtime pin and range

`DXR_RUNTIME_GIT_TAG` in `CMakeLists.txt` and `RUNTIME_REF` in the workflows must be
the same release (the `lint` job checks it), and `catalog/*.json` records the range of
runtime releases the binary is valid for. Read `docs/trunk-dependencies.md` section 7:
with a raw `xrt_device`, the range is "the releases whose shared headers are identical
to the pin's", `scripts/runtime_range.py` computes it, and CI refuses a range that is
not true. If your provider includes other runtime headers that define shared memory,
add them to `ROOTS` in that script.

Remove the dependency on `u_openxr_layers` and `ultraleap_layer.{h,c}` unless your
vendor also installs an implicit OpenXR layer that interferes.

### 5. Packaging

- The installer (`installer/*.nsi`) follows the runtime's rules: it owns only its own
  rows and files, has no install-order requirement, releases its DLL through Restart
  Manager, never starts the service elevated, honours `/S`, and writes the allowlist
  row for the exact DLL it packs.
- The Ultraleap check in the installer is the pattern for **a prerequisite you do not
  ship**: look for it, explain when it is missing, install anyway — because the
  provider itself copes (`docs/packaging.md`). If you own your SDK's DLLs, ship them
  next to your provider and delete the check.
- The runtime-range check in `.onInit` shrinks to a plain minimum once your devices
  are behind a versioned contract (ADR-063).

### 6. CI and release

- Keep the gate on the self-hosted job (`vars.<X>_SDK_RUNNER`): a job whose label no
  runner carries queues forever with no error.
- Before making a fork private, read the billing note at the top of `build.yml`.
- `scripts/sign-release.sh` and the `sign` job work for any component name: change
  `component=ultraleap` and the installer file pattern.

### 7. Licence

The provider sources came from the runtime trunk (and were then changed here) and are BSL-1.0; the installer files
were adapted from `displayxr-input-template` and are Apache-2.0. Keep the headers on
what you keep. The stub header is original work that declares only the names this
provider uses; write your own for your SDK rather than copying a vendor header into a
public repository.
