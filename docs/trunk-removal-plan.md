# Removing the provider from the runtime trunk

The edit list for the later `displayxr-runtime` PR that deletes
`src/xrt/drivers/ultraleap/`. Nothing here has been done: the runtime checkout was not
touched. Line numbers are against runtime `main` at `069a1fbda` (2026-11-20, just
after `v2.69.2`); re-check them before editing.

## Order of operations

1. Publish this repository and validate the provider on the Windows box with the
   hardware (`README.md`, "What has and has not been verified").
2. Cut the first provider release, pinned to a runtime tag `T` that **still** carries
   the in-tree sources. Nothing in this build uses the trunk's `drivers/ultraleap/`
   directory, so the pin can move past the removal later without any change here.
3. Runtime PR A — *additions* (section B): `versions.json` field,
   `downstream-pins.json` track, catalog component, release-skill row. Safe to merge
   before the removal.
4. Runtime PR B — *the removal* (section A). It ships in the next runtime release.
5. Repin this repository to that release and release again (the exact-pin rule).

Do not merge B before a provider release exists: between the two, a from-source
Windows box with the SDK would lose hands with nothing to install.

## A. Removal PR — runtime-repo edits

### A1. Delete

| Path | Note |
|---|---|
| `src/xrt/drivers/ultraleap/` (5 files) | Now `src/ultraleap/` here, byte-identical at `v2.69.3`. |
| `tests/tests_ultraleap_map.cpp` | Now `tests/tests_ultraleap_map.cpp` here (runs in this repo's CI without the SDK). |

### A2. Build system

| File | Lines | Edit |
|---|---|---|
| `src/xrt/drivers/CMakeLists.txt` | 1233–1348 | Delete the whole block, from the `####` banner "DisplayXR-Ultraleap input-provider plug-in DLL (#825 Tier 1)" through `endif() # LeapC SDK found`. It contains the `find_path` / `find_library` for LeapC, the `drv_ultraleap_plugin` target, the #933 `LeapC.dll` staging and both install rules. Keep the following `endif() # XRT_FEATURE_OPENXR AND NOT ANDROID` line. `input_plugin_exports.version` stays (the other providers use it). |
| `tests/CMakeLists.txt` | 159 | Remove `tests_ultraleap_map` from the test list. |
| `tests/CMakeLists.txt` | 1249–1261 | Delete the `tests_ultraleap_map` `target_sources` / `target_include_directories` / `target_link_libraries` block and its comment. |
| `CMakeLists.txt` | 421–423 | Comment only: it says the qwerty floor and Ultraleap emulate the controller profiles and that `XR_EXT_hand_tracking` stays on because "Ultraleap serves it". Reword to "an input provider (e.g. the out-of-tree Ultraleap provider) serves it". The option's default does not change. |

After this, `LEAPSDK_DIR` means nothing to the runtime build and the cache variables
`LEAPC_INCLUDE_DIR` / `LEAPC_LIBRARY` / `LEAPC_RUNTIME_DLL` disappear.

### A3. CI

| File | Lines | Edit |
|---|---|---|
| `.github/workflows/cts.yml` | 48 | Delete the path trigger `- 'src/xrt/drivers/ultraleap/**'`. |
| `.github/workflows/build-windows.yml` | 269–280 | **Keep, unchanged.** This is the vendor-identifier guard: `$forbiddenDeps` contains `LeapC` and `DisplayXR-Ultraleap`, `$forbiddenLibs` contains `drv_ultraleap` and `LeapC`. With the sources gone it can no longer be tripped by accident, and it is what stops a later change from linking LeapC or the provider back into the runtime DLL, the service or the CLI. The comment at 269–270 lists "the Ultraleap provider and its LeapC.dll" among in-tree components: reword it to say the provider now ships from its own repository, and leave the patterns. |
| `scripts/run_cts.ps1` | 440–441 | Comment only (the history of the #1545 crash). Leave it; it explains an environment setting that still applies to a box with the provider installed. |

### A4. Dev scripts

| File | Lines | Edit |
|---|---|---|
| `scripts/register_dev_plugin.bat` | 194 | The special case `if /I "!IPID!"=="DisplayXR-Ultraleap" set "IPID=ultraleap"`. Two options. **Recommended:** keep the line for one release and change the comment above it (193) from "In-tree providers" to "Known provider DLL names", because this repository's dev build produces a DLL with the same name and developers will keep typing `input <dll>` without an id. Then remove it; this repository's instructions already pass the id explicitly (`... input <dll> ultraleap`). Removing it at once is also correct, but a developer who forgets the id gets a row named `DisplayXR-Ultraleap` (the loader warns and falls back to the row for settings). |
| `scripts/register_dev_plugin.bat` | 24, 146–148 | Comments. Line 24 ("Known in-tree DLLs map to theirs (DisplayXR-Ultraleap -> ultraleap)"): follow whichever option was taken for 194. Lines 146–148 use the provider as the historical example of the id-vs-basename bug: leave. |
| `scripts/push-runtime-pf.sh` | 91–110 | Step 3b refreshes plug-in DLLs **already present** under `Program Files\DisplayXR\Runtime\plugins` from `_package/plugins`. After the removal `_package/plugins` never contains `DisplayXR-Ultraleap.dll`, so a hand-placed copy in `Runtime\plugins` is never refreshed again — the stale-provider time bomb the step's own comment (93–95) describes. Add: if `"$PF/plugins/DisplayXR-Ultraleap.dll"` exists, print a WARN that it is a leftover of the in-tree provider, that the provider now installs to `Plugins\Ultraleap\`, and that the file (and a `LeapC.dll` next to it) should be removed and the registry row re-pointed by the new installer. Do not delete it silently: the row may still point at it. Update the comment at 93–95 to past tense. |

### A5. Tests and fixtures

| File | Lines | Edit |
|---|---|---|
| `src/dashboard/DisplayXR.Dashboard.Tests/Data/input-list-n3.json` | 6, 11 | Fixture row with id `DisplayXR-Ultraleap` and `binary_path` `C:\Program Files\DisplayXR\Runtime\plugins\DisplayXR-Ultraleap.dll` — the old basename id and the old location. Update to id `ultraleap` and `C:\Program Files\DisplayXR\Plugins\Ultraleap\DisplayXR-Ultraleap.dll` so the fixture shows a shape that can occur. |
| `src/dashboard/DisplayXR.Dashboard.Tests/ComponentPolicyTests.cs` | 57, 214 | Assert on the id above (`"DisplayXR-Ultraleap"`): change with the fixture. |
| `tests/tests_cli_input_predict.cpp` | 117 | `cli_input_id_valid("ultraleap")`: keep; it tests the id syntax, not the provider. |
| `tests/tests_openxr_layers.cpp` | whole file | **Keep**: `u_openxr_layers.{h,c}` stays in the trunk for now (section A7). |
| `tests/tests_sim_input_hands.cpp` | 221–222 | Comment refers to `ultraleap_map.h`: point it at this repository. |

### A6. Lever census and generated catalog — this one fails lint if skipped

`src/xrt/targets/cli/cli_lever_catalog.h:81` lists `DXR_ULTRALEAP_SETTLE_MS`. The
header is generated by `scripts/gen_lever_catalog.py` from Appendix A (the census) of
`docs/roadmap/control-panel-performance-settings.md` (row at line 659, source given as
`drivers/ultraleap/ultraleap_provider.cpp`), and the lint workflow runs the generator
with `--check`, which **fails when a name in the catalog no longer occurs in
`src/xrt`**. Deleting the sources without touching the census therefore turns lint red.

In the removal PR: delete the census row, re-run `scripts/gen_lever_catalog.py`, and
fix the lever totals wherever they are quoted (the generated header's "82 levers"
line updates itself; check the census's own totals and the runtime `CLAUDE.md`
documentation index). The variable still exists — in this repository — and should
become a declared provider setting (`docs/trunk-dependencies.md`, section 5).

### A7. What must NOT be removed

| Path | Why it stays |
|---|---|
| `src/xrt/auxiliary/util/u_openxr_layers.{h,c}` | This provider still calls `u_openxr_implicit_layer_find` and `u_openxr_layer_ultraleap_advice` from the pinned runtime tree, and `displayxr-cli` shares the advice text. Moving the Ultraleap-specific half here and making the CLI warning data-driven is a separate change (`docs/trunk-dependencies.md`, section 6). |
| `src/xrt/targets/cli/cli_query.{c,h}` — `check_ultraleap_layer`, `input_ultraleap_layer_*`, the `ULTRALEAP_OPENXR_LAYER` warning | Same reason; it matches a registered provider by the string `ultraleap`, which still works for the out-of-tree row. |
| `build-windows.yml` vendor-identifier guard | Section A3. |
| `src/xrt/drivers/input_plugin_exports.version` | Shared by the remaining providers. |
| The comments in `target_input_plugin_loader.c:353`, `target_input_arbiter.{c,h}`, `net_input_hub.c:502`, `xrt_tracking.h:66`, `sim_input_*` | They use the provider as an example or cite its mapping gain. Optional rewording; no behaviour. |

### A8. Documentation sweep

Files that mention the provider (count of matching lines at `069a1fbda`;
`grep -rn -i "ultraleap\|leapc" docs CLAUDE.md`):

| File | Lines | What to do |
|---|---|---|
| `CLAUDE.md` | 2 | The `drivers/` list names `ultraleap/` (SDK-gated hands): remove it and add the repository to the *Repos & issue routing* table. The "zero … Ultraleap/LeapC identifiers" sentence about the link lines stays. |
| `docs/specs/runtime/input-provider-discovery.md` | 14 | The provider table row at 1159 ("Shipped, SDK-gated (`src/xrt/drivers/ultraleap/` …)") becomes "ships from `displayxr-ultraleap`". The lifetime section (around 360–362) cites `g_ul_hub` as "the in-tree Ultraleap provider is the reference shape": keep the content, change the pointer. |
| `docs/guides/input-provider-onboarding.md` | 3 | "Where to start" lists `src/xrt/drivers/ultraleap/` as the real-hardware example: point at this repository. Section 12 says "the in-tree Ultraleap provider ships at 50": drop "in-tree". The hand-tracking row of the device-type table links `../../src/xrt/drivers/ultraleap/`: a dead link after the removal. |
| `docs/reference/xrt_input_plugin_iface.md` | 1 | Pointer update. |
| `docs/guides/vendor-plugin-onboarding.md` | 2 | Pointer update. |
| `docs/getting-started/troubleshooting.md` | 13 | The two sections on the implicit layer stay as they are (user-facing, still true). Add where the provider comes from now. |
| `docs/architecture/service-architecture.md` | 6 | Check each for "in-tree" / path wording. |
| `docs/roadmap/input-modality-switching.md` | 9 | Same. |
| `docs/roadmap/control-panel-performance-settings.md` | 2 | Section A6. |
| `docs/adr/ADR-034-input-provider-plugins.md` | 9 | An ADR is a record: do not rewrite. Add a dated note that the provider moved out of tree. |
| `docs/adr/ADR-063-input-provider-device-abi-hardening.md` | 1 | "Why it has not bitten yet" lists `ultraleap` among the providers rebuilt with the runtime. That stops being true the day this ships: say so — this repository is the first external provider exposed to the gap the ADR describes. |
| `docs/adr/ADR-035-…md` | 1 | Check wording. |

Dead-link check after the sweep: `grep -rn "drivers/ultraleap" .` must return nothing
outside ADR history notes.

### A9. Machines that already have the in-tree build

A dev box that hand-registered the trunk DLL has a row `InputProviders\ultraleap` (or
the older `InputProviders\DisplayXR-Ultraleap`) whose `Binary` is under
`Runtime\plugins\` or a build tree. This repository's installer overwrites the
`ultraleap` row. It does not delete a `DisplayXR-Ultraleap` row or the old files. The
release notes of the runtime version that carries the removal should say: delete
`InputProviders\DisplayXR-Ultraleap` if present, delete
`Runtime\plugins\DisplayXR-Ultraleap.dll` and the `LeapC.dll` beside it, then install
this component.

## B. Additions — runtime-repo entries for the new component

### B1. `versions.json`

```json
"ultraleap": "v0.1.0",
```

It meets the membership rule ("the desktop orchestrator can install it as a released
asset"). Like `browser` it must be **opt-in** (`--with ultraleap`), never a default:
it needs third-party software and a camera. Follow-ups that come with a new field:

- `scripts/setup-displayxr.{sh,bat}`: the component table (asset
  `DisplayXRUltraleapSetup-*.exe`, marker
  `HKLM\Software\DisplayXR\Plugins\Ultraleap\Version`, opt-in).
- `.github/workflows/versions-bump.yml`: the default tag shape (`vX.Y.Z`) already
  fits. Add a gate for this field: refuse the bump when the provider tag's
  `DXR_RUNTIME_GIT_TAG` is not the runtime version `versions.json` then pins, since
  the pair must match exactly. Then set this repository's variable
  `DXR_VERSIONS_BUMP=true` (the `bump` job in `release.yml` is gated on it).
- `displayxr-installer` mirrors the file byte for byte; the bundle does not enrol a
  new field by itself (`build-bundle` reads its pins by name), which is the right
  default here.
- `docs/specs/runtime/versions-json-autobump.md`: document the field.

### B2. `downstream-pins.json` track

```json
"displayxr-ultraleap": {
  "role": "Ultraleap hands input provider (first out-of-tree hardware input provider; links runtime aux + returns raw xrt_device)",
  "tracks": {
    "all": {
      "bump_when": "features",
      "reason": "The provider returns raw struct xrt_device (ADR-063): a binary is only known-good on the runtime release it was built at, so the catalog pins an exact runtime range and a repin is a new provider release. No existing policy matches that exactly. 'abi' never fires (input ABI is 1 and stays 1). 'features' over the device headers catches an added or re-signed function-pointer slot and feature-macro changes, but is BLIND to a plain field added to xrt_device and to an enumerator inserted in xrt_device_name / xrt_device_type / xrt_tracking_type - the changes ADR-063 is about. Until a 'layout' policy exists (byte-diff of the shared-header closure; this repo's scripts/runtime_range.py is a working sketch), treat a skipped release as 'not proven safe', not 'safe'.",
      "feature_headers": [
        "src/xrt/include/xrt/xrt_input_plugin.h",
        "src/xrt/include/xrt/xrt_component_settings.h",
        "src/xrt/include/xrt/xrt_device.h",
        "src/xrt/include/xrt/xrt_defines.h",
        "src/xrt/include/xrt/xrt_tracking.h"
      ],
      "locations": [
        { "file": "CMakeLists.txt", "kind": "cmake_set", "key": "DXR_RUNTIME_GIT_TAG" },
        { "file": ".github/workflows/build.yml", "kind": "yaml_env", "key": "RUNTIME_REF" },
        { "file": ".github/workflows/release.yml", "kind": "yaml_env", "key": "RUNTIME_REF" }
      ]
    }
  }
}
```

Three things to settle with it:

- **The catalog file carries the pin too** (`catalog/ultraleap-hands.json`:
  `requires.runtime`, `runtime_range.min`, `runtime_range.max`), and this repository's
  `pin` job fails when they differ from the CMake pin. Neither existing location kind
  (`cmake_set`, `yaml_env`) can rewrite JSON, so an automatic repin PR would be red
  until edited by hand. Preferred fix: the catalog generator derives the range from
  the CMake pin at the provider's tag (the way the Leia installer's
  `MIN_RUNTIME_VERSION` is derived, never listed) and the hand-written copy goes away.
- **`feature_surface.headers`** is the default set for `features` tracks and is all
  display-processor headers; this track sets its own list, so no change there.
- **`scripts/check_plugin_abi.py`** already knows `xrt_input_plugin.h` in
  `ABI_HEADERS`; nothing to add for an `abi` gate, should one be wanted alongside.

### B3. Catalog

`catalog/ultraleap-hands.json` here is the draft entry. To publish it, in the runtime:

- `scripts/gen_catalog.py` `COMPONENTS`: add `{name: ultraleap, pin: ultraleap, repo:
  displayxr-ultraleap, kind: input_provider, asset: DisplayXRUltraleapSetup-*.exe,
  args: [/S], registry_version: HKLM\Software\DisplayXR\Plugins\Ultraleap\Version}`.
- The generator publishes a `windows` block only for an asset whose Authenticode
  signature is valid with a listed signer. **An unsigned provider release is therefore
  "not fetchable"**: the signing lane is a prerequisite for catalog presence, not a
  nicety.
- Schema 1 cannot express a maximum runtime, an external prerequisite or a note
  (`docs/specs/runtime/component-catalog.md`). A schema-1 client would read
  `requires.runtime: ">=2.69.3"` as a floor and offer the provider on every later
  runtime. Publishing this entry needs the schema that adds `runtime_range` and
  `prerequisites`, and a `dxr-get` that honours them.

### B4. Release tooling and other surfaces

- `.claude/skills/dxr-release/SKILL.md`: add component `ultraleap` →
  `DisplayXR/displayxr-ultraleap`, signing component name `ultraleap`.
- The signing provider (`$DXR_SIGN_REPO`): teach `build-signed-release.yml` the
  component and give its runner the Ultraleap SDK.
- `displayxr-website`: the components page.
- `docs/guides/input-provider-onboarding.md` "Where to start": add this repository as
  the real-hardware, aux-linking example beside `displayxr-input-template`.
