# What this provider takes from the runtime trunk

Audit of every runtime header and aux symbol the provider uses beyond the public
input-provider contract, at runtime `v2.69.3`. It answers one question: **on which
runtime releases is a provider binary built at release N valid?**

Short answer: on the releases whose shared headers are byte-identical to N's — a range
that can be computed and is checked in CI. Section 7 is the rule.

How this was established: by reading the sources, by `nm` / `otool` on a macOS build
(LeapC replaced by the stand-in, see `tests/leapc_stub/`), and by reading the runtime
headers at the pinned tag. The Windows import table is printed by the `windows` CI job.

## 1. The public contract (versioned, safe)

| Header | What the provider uses | Why it is safe |
|---|---|---|
| `xrt/xrt_input_plugin.h` | `xrtInputPluginNegotiate`, `xrt_input_plugin_iface`, `xrt_input_plugin_host_iface` (`get_setting`, `get_display_geometry`), `xrt_input_host_display_geometry`, `xrt_input_provider_presence`, `XRT_INPUT_PLUGIN_API_VERSION_CURRENT` (= 1) | ADR-020: `struct_size` first, append-only slots, the loader rejects another major. The provider `struct_size`-checks both host slots before use. |
| `xrt/xrt_component_settings.h` | `xrt_component_setting_desc`, `xrt_component_get_setting_fn_t`, the `XRT_COMPONENT_SETTING_TYPE_*` words | Part of the same contract; four `const char *` fields, frozen by rule. |
| `xrt/xrt_results.h` | `XRT_SUCCESS`, `XRT_ERROR_ALLOCATION`, `XRT_ERROR_PROBER_NOT_SUPPORTED`, `XRT_ERROR_DEVICE_CREATION_FAILED`, `XRT_ERROR_INPUT_UNSUPPORTED` | Explicit numeric values. |

A provider that used only these would be valid for the whole life of input ABI 1.
This one does not.

## 2. Memory the runtime reads from the provider (NOT versioned — ADR-063)

The two devices returned from `create_devices` are raw runtime-internal structs. The
runtime reads their fields and calls their function pointers directly. None of it is
covered by input ABI 1.

| Type | Where the provider touches it | Risk across releases |
|---|---|---|
| `struct xrt_device` | allocated by `U_DEVICE_ALLOCATE`; fields `name`, `device_type`, `str`, `serial`, `tracking_origin`, `inputs` / `input_count`, `outputs` / `output_count`, `supported.{orientation,position,hand}_tracking`; slots `update_inputs`, `get_tracked_pose`, `get_hand_tracking`, `get_view_poses`, `set_output`, `destroy` | **Unsafe.** No `struct_size`. A field or slot added anywhere but the tail shifts everything after it; the struct's own convention is "add new functions above `destroy`". Negotiation still succeeds; the failure is a wrong callback or a wrong field, inside the runtime. |
| `struct xrt_input`, `struct xrt_output` (arrays) | `active`, `timestamp`, `value.boolean`, `name` | **Unsafe**, same reason. |
| `struct xrt_tracking_origin` | `type`, `name` (`XRT_TRACKING_NAME_LEN`) | **Unsafe**, same reason. |
| `enum xrt_device_name` | `XRT_DEVICE_SIMPLE_CONTROLLER` | **Unsafe**: positional. An enumerator inserted before it rebinds the hands to another profile. |
| `enum xrt_device_type` | `XRT_DEVICE_TYPE_LEFT_HAND_CONTROLLER`, `_RIGHT_HAND_CONTROLLER` | **Unsafe**: positional. |
| `enum xrt_tracking_type` | `XRT_TRACKING_TYPE_RIG_LOCAL` | **Unsafe**: positional, and not the last enumerator. |
| `enum xrt_input_name` / `xrt_output_name` | `XRT_INPUT_SIMPLE_{SELECT_CLICK,MENU_CLICK,GRIP_POSE,AIM_POSE}`, `XRT_INPUT_HT_UNOBSTRUCTED_{LEFT,RIGHT}`, `XRT_OUTPUT_NAME_SIMPLE_VIBRATION` | Explicit ids, so stable in practice; not frozen by any rule. |
| `struct xrt_hand_joint_set` | written into the runtime's buffer by `get_hand_tracking` (26 joints) | Plain data but large and unversioned (ADR-063 open question 2). A change to `XRT_HAND_JOINT_COUNT` or the joint struct is a buffer overrun or a garbled hand. |
| `struct xrt_space_relation`, `xrt_pose`, `xrt_vec3`, `xrt_quat`, `union xrt_output_value` | poses out, haptics in | Layout-stable math; safe in practice. |

This table is the whole reason the runtime range is bounded. ADR-063 step 1 (a layout
fingerprint the loader checks) would turn a mismatch into a logged refusal; step 2
(the provider-device descriptor) would remove the table.

## 3. Aux code compiled into the provider (source-coupled, load-safe)

Linked statically from the runtime tree at the pinned tag. The provider carries its
own copy, so nothing here can skew at load time. It does couple the **source** to the
runtime tree: these files must exist, with these signatures, at whatever tag is
pinned.

| Symbol | From | Note |
|---|---|---|
| `U_DEVICE_ALLOCATE` / `u_device_allocate`, `u_device_free`, `u_device_ni_get_view_poses`, `U_DEVICE_ALLOC_TRACKING_NONE` | `util/u_device.{h,c}` | The allocator is where section 2 becomes concrete: the size and layout of the `xrt_device` it allocates are the **provider's** compile-time view. |
| `m_relation_history_{create,push,get,destroy}` | `math/m_relation_history.{h,cpp}` | Timestamped pose history + prediction. Private to the provider. |
| `math_pose_transform`, `math_pose_invert` | `math/m_api.h` (Eigen) | Used by `ultraleap_map.c`. |
| `os_mutex_*`, `os_thread_helper_*`, `os_monotonic_get_ns`, `os_nanosleep` | `os/os_threading.h`, `os/os_time.h` | Mostly header-inline over pthreads / Win32. |
| `U_TYPED_CALLOC`, `U_ZERO` | `util/u_misc.h` | Macros. |
| `u_openxr_implicit_layer_find`, `struct u_openxr_implicit_layer` | `util/u_openxr_layers.{h,c}` | The generic lookup only; the Ultraleap-specific half now lives here (section 6). In the trunk since 2026-11-03 (#2508), so no runtime tag older than that can be pinned. |
| cJSON | via `aux_util` | See section 5. |

On **Linux** this list also includes `u_log*` and `u_var_*`: the provider links no
runtime library there, so it has its own log sink and its own `u_var` registry (the
runtime's debug UI does not see the provider's variables). That is the trunk's
behaviour too.

## 4. Symbols imported from the runtime library at load time (unversioned exports)

On Windows and macOS the provider is built with `XRT_USING_RUNTIME_DLL` and links the
runtime's import library, so that it shares the process's single log sink and `u_var`
registry (ADR-019).

Measured on macOS (`nm -u` of the stub-check build), all bound to
`@rpath/openxr_displayxr.dylib`:

```
u_log  u_log_get_global_level
u_var_add_root  u_var_remove_root
u_var_add_bool  u_var_add_f32  u_var_add_ro_i32  u_var_add_ro_u64  u_var_add_vec3_f32
```

On Windows the same functions are `__declspec(dllimport)` from `DisplayXRClient.dll`
(`XRT_API_FUNC` in `u_logging.h` and `u_var.h`); the `windows` CI job prints the
import table of the stand-in build.

Risk: these are ordinary exported functions with no version. If a runtime release
removes or renames one, the provider fails to load (a clean, logged `LOAD_FAILED`).
If one changes its signature or the `u_logging_level` values, the failure is silent. They have been stable, but nothing guarantees it.

Two consequences that only show up out of tree:

- **The provider must be able to find the runtime library.** On macOS it carries a
  dependency on `@rpath/openxr_displayxr.dylib`. In an app that library is already
  loaded; in `displayxr-cli` it is not, and a provider with no rpath fails to
  `dlopen` (observed here with the runtime's own `DisplayXR-SimDisplay.dylib` in a
  raw build tree). The build sets a build-tree rpath and an install rpath of
  `@loader_path/../..`, which is right only when the provider is installed inside
  the runtime's `lib/displayxr/plugins`. An install elsewhere needs its own rpath.
  On Windows the same question has an answer in the runtime: its loader pins
  `DisplayXRClient.dll` into the hosting process by absolute path before loading any
  component (`target_plugin_preload_runtime_core_dll`), so a provider installed under
  `Plugins\Ultraleap\` resolves its imports in `displayxr-service.exe` and
  `displayxr-cli.exe` too. The `windows` CI job runs exactly that layout.
- **The whole runtime is a build dependency.** Linking the import library means
  building the runtime library first (minutes), with its full dependency set.

The clean way out is to stop importing anything: a `log` slot on the host iface
(appended, ADR-020) would let the provider drop the runtime library, and with the
ADR-063 descriptor it could then build against headers only, like
`displayxr-input-template`.

## 5. Other couplings found

- **cJSON.** `aux_util` uses the system cJSON when the runtime tree finds one. On this
  Mac the provider ends up needing `/opt/homebrew/opt/cjson/lib/libcjson.1.dylib` — a
  build-machine path. Forcing `XRT_HAVE_SYSTEM_CJSON=OFF` did not help: at `v2.69.3`
  the runtime's bundled `cJSON.c` then fails to compile on macOS when Homebrew's
  `cjson` headers are also on the include path ("cJSON.h and cJSON.c have different
  versions"). A release build must therefore be made where the dependency is
  acceptable (Linux: the distro's `libcjson1`) or the install must rewrite it as the
  runtime's own packaging does for its plug-ins.
- **Windows DLL imports the provider does not ship.** Built in CI with the runtime's
  vcpkg manifest, the provider imports `DisplayXRClient.dll`, `pthreadVCE3.dll` and
  `cjson.dll` besides system DLLs. Installed alone under `Plugins\Ultraleap\` it
  resolves the last two only because `DisplayXRClient.dll` imports them as well and is
  already pinned in the host. CI asserts that every non-system import of the provider
  is also an import of the runtime core built from the same tree. What CI cannot see
  is the **shipped** runtime: if a release build of the runtime links pthreads or
  cJSON differently from the provider's build, the provider would fail to load. The
  provider must therefore be built with the same vcpkg configuration as the runtime
  release it targets (`docs/windows-validation.md`, section 1).
- **`getenv` (fixed here).** The trunk version reads `DXR_ULTRALEAP_SETTLE_MS` and
  `DXR_ULTRALEAP_PERSIST_HUB` from the process environment. In this repository they
  are the declared settings `SETTLE_MS` and `PERSIST_HUB`, read through
  `host->get_setting`; the old variable names still work for one release when the
  setting is not set, with a warning. `DXR_ULTRALEAP_SETTLE_MS` is also a row of the
  trunk's lever census, which must lose it when the sources leave
  (`docs/trunk-removal-plan.md`, A6).
- **LeapC (changed here).** The trunk version links LeapC and, on Windows, stages the
  SDK's `LeapC.dll` next to the plug-in. This repository links nothing of Ultraleap's
  and binds LeapC at run time (`docs/packaging.md`).
- **CMake.** The build needs the runtime's targets `xrt-interfaces`, `aux_util`,
  `aux_os`, `aux_math`, `drv_includes` and the `RUNTIME_TARGET` variable. While the
  trunk still has its own SDK-gated block, a machine **with** the SDK configures two
  targets that produce `DisplayXR-Ultraleap` (the trunk's `drv_ultraleap_plugin` and
  this repo's `displayxr_ultraleap`); the trunk's is excluded from `all`, and this
  repo uses its own cache variable names so the two do not share state.
- **Catch2.** The mapping unit test compiles the runtime tree's amalgamated Catch2.
- **Cosmetic.** A `displayxr-cli` built from the fetched tree reports this project's
  description as the runtime's (`info` reads `CMAKE_PROJECT_DESCRIPTION`). Only the
  dev-built CLI is affected.

## 6. The layer-advice helper

`u_openxr_layers.{h,c}` in the trunk's `aux_util` holds two different things:

1. generic, vendor-neutral lookups — `u_openxr_layer_manifest_declares`,
   `u_openxr_implicit_layer_find`: "is implicit layer X registered and active?";
2. Ultraleap-specific knowledge — the layer name and disable-variable constants
   (`U_OPENXR_LAYER_ULTRALEAP_*`) and `u_openxr_layer_ultraleap_advice`, the advisory
   text, shared in the trunk by the in-tree provider and `displayxr-cli`
   (`check_ultraleap_layer` in `cli_query.c`, the `ULTRALEAP_OPENXR_LAYER` warning).

Done in this repository: (2) is forked into `src/ultraleap/ultraleap_layer.{h,c}`
(`UL_OPENXR_LAYER_NAME`, `UL_OPENXR_LAYER_DISABLE_ENV`, `ul_layer_advice`). The
provider now takes only the generic lookup (1) from the runtime tree.

Left for the runtime (the trunk was not touched):

- Keep (1) in the trunk's aux. It is generic and unit-tested there.
- Remove (2) from the trunk once `displayxr-cli` no longer needs it, by making the CLI
  warning data-driven so that the trunk names no vendor: either the catalog note
  carries it (`notes[].detect.kind = openxr_implicit_layer_active`, as drafted in
  `catalog/ultraleap-hands.json`), or a provider declares the layers it conflicts with
  in its registration (a `ConflictingLayers` value / manifest array) and the CLI
  prints a generic "implicit layer X conflicts with provider Y" line. Until then the
  advice text exists twice and can drift.

The removal PR must not delete `u_openxr_layers.{h,c}`: this provider still compiles
the generic lookup from the pinned runtime tree.

## 7. The rule

**A provider binary built at runtime tag P is valid on every runtime release whose
shared headers are byte-identical to P's.** "Shared headers" are the ones that define
memory or calls the two sides share: the include closure of `xrt_device.h`,
`xrt_input_plugin.h`, `xrt_component_settings.h`, `xrt_results.h` and
`xrt_tracking.h` under `src/xrt/include` (sections 1 and 2), plus `u_logging.h` and
`u_var.h` (section 4). Identical bytes mean identical layouts, enumerator values and
signatures; nothing else in the runtime can change what the provider and the runtime
exchange.

`scripts/runtime_range.py` computes it from the runtime's tags:

```
runtime_range.py --runtime <clone> --pin v2.69.3 --suggest
pin v2.69.3: shared headers identical on v2.68.0 .. v2.69.3
```

How it is applied:

- `catalog/ultraleap-hands.json` records `runtime_range.build` (the pin), `min` and
  `verified_max`. Today: built at 2.69.3, valid 2.68.0 – 2.69.3. `v2.67.0` and older
  differ (three shared headers changed between 2.67.0 and 2.68.0).
- CI (`range` job) fails if any release inside the recorded range differs from the
  pin, so the range can only be claimed when it is true.
- A runtime **newer** than `verified_max` is *unverified*, not known-bad. When the
  runtime releases, the weekly `runtime-range` workflow goes red and says which of two
  things to do:
  - headers identical → raise `verified_max` in the catalog entry. No rebuild, no new
    provider release;
  - headers differ → repin (`DXR_RUNTIME_GIT_TAG` + `RUNTIME_REF`), rebuild, release.
    The new binary's range starts where the headers changed.
- The installer refuses a runtime older than `min` and warns, without refusing, about
  one newer than the `verified_max` it was built with.

What the rule does not cover, stated plainly:

- **It is conservative, not exact.** A comment edit in a shared header ends the range
  although nothing changed. The script does not try to tell; the cost is one
  unnecessary rebuild.
- **It assumes the headers are the whole contract.** A runtime change in *behaviour*
  with unchanged headers (the runtime reading a field it used to ignore, say) is
  invisible to it. That risk exists for every plug-in and is what release testing is
  for.
- **Nothing stops a pair outside the range from loading.** The runtime's loader checks
  only the ABI major. The range is enforced by the installer (floor) and by whatever
  client reads the catalog. Closing that needs the runtime: ADR-063 step 1, a layout
  fingerprint the loader compares.
- **After ADR-063 step 2** (the provider-device descriptor) the rule relaxes to: `min`
  = the build pin, no maximum inside one input ABI major — provided section 4 is dealt
  with too.
