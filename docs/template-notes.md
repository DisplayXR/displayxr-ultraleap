# Using this repository as the starting point for your own input provider

## First: is this the right starting point?

There are two out-of-tree input-provider starting points, and they make opposite
trade-offs.

| | [`displayxr-input-template`](https://github.com/DisplayXR/displayxr-input-template) | this repository |
|---|---|---|
| Device | a 6-DoF stylus (one dominant-hand device) | a left/right hand pair + 26-joint hand tracking |
| Vendor SDK | none; a transport stub you replace | a real, non-redistributable SDK (LeapC) found at configure time |
| Runtime dependency | **public headers only** — no runtime build, no aux, no import library | the runtime source at a pinned tag: static aux libraries, and the runtime's import library on Windows / macOS |
| Build time | seconds | minutes (it builds runtime libraries) |
| Runtime range of one binary | still tied to one release today (it fills `xrt_device` too), but nothing else couples it | exact, and coupled in four more ways (`docs/trunk-dependencies.md`) |
| What it shows | the contract, minimal | a production provider: process-scoped transport hub, presence from transport events, an idle watchdog, timestamped pose history with prediction, a pure unit-tested mapping layer, an external-prerequisite installer, SDK-less CI |

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

- `cmake/FindLeapC.cmake` → a find module for your SDK. Keep its shape: an explicit
  root variable, the default install paths, a `*_FOUND` result, and **your own cache
  variable names**.
- The configure-time message in the top-level `CMakeLists.txt` ("NOT BUILT - LeapC SDK
  not found"): keep one like it. A silently skipped target is how a provider goes
  unbuilt for months.
- `tests/leapc_stub/` → a stub of *your* SDK header written from *your* sources' usage,
  if your SDK cannot be on CI. Keep the three guard rails: the stub build has a
  different output name, has no install or packaging rule, and CI says loudly that it
  proves compilation only.
- If your SDK **can** be redistributed or fetched, delete the stub and fetch the SDK
  instead; if your provider has no SDK at all, you are much closer to
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

Do better than this repository in one place: read every knob through
`host->get_setting` and declare it in `describe_settings`. Two knobs here still use
`getenv` (`docs/trunk-dependencies.md`, section 5).

### 4. The runtime pin

`DXR_RUNTIME_GIT_TAG` in `CMakeLists.txt`, `RUNTIME_REF` in both workflows, and the
range in `catalog/*.json` must be the same release. The `pin` CI job checks it. Read
`docs/trunk-dependencies.md` section 7 before deciding how often you will release:
with a raw `xrt_device`, one binary is valid for one runtime release.

Remove the dependency on `u_openxr_layers` unless your vendor also installs an
implicit OpenXR layer that interferes; it is the one runtime aux file here that is
about a specific vendor.

### 5. Packaging

- The installer (`installer/*.nsi`) follows the runtime's rules: it owns only its own
  rows and files, has no install-order requirement, releases its DLL through Restart
  Manager, never starts the service elevated, honours `/S`, and writes the allowlist
  row for the exact DLL it packs.
- The LeapC section (`/LEAPC=`, `ULTRALEAP_BUNDLE_LEAPC`, `docs/packaging.md`) is the
  pattern for **a prerequisite you do not ship**: detect it, explain it, place a local
  copy so another copy on `PATH` cannot shadow yours. If you own your SDK's DLLs, ship
  them next to your provider and delete the section.
- The runtime-pin check in `.onInit` goes away once your devices are behind a
  versioned contract (ADR-063).

### 6. CI and release

- Keep the gate on the self-hosted job (`vars.<X>_SDK_RUNNER`): a job whose label no
  runner carries queues forever with no error.
- Before making a fork private, read the billing note at the top of `build.yml`.
- `scripts/sign-release.sh` and the `sign` job work for any component name: change
  `component=ultraleap` and the installer file pattern.

### 7. Licence

The provider sources came from the runtime trunk and are BSL-1.0; the installer files
were adapted from `displayxr-input-template` and are Apache-2.0. Keep the headers on
what you keep. The stub header is original work that declares only the names this
provider uses; write your own for your SDK rather than copying a vendor header into a
public repository.
