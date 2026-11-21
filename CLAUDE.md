# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

The **Ultraleap hands input provider** for the DisplayXR runtime. It builds
`DisplayXR-Ultraleap.dll` (export `xrtInputPluginNegotiate`, registered id
`ultraleap`, ProbeOrder 50) and doubles as the worked example of an out-of-tree input
provider that wraps a vendor SDK. It started as the runtime's in-tree
`src/xrt/drivers/ultraleap/` (v2.69.3) and is now a **fork**: it binds LeapC at run
time, reads every knob through the settings contract, and owns the Ultraleap
layer-advice text. The trunk copy still exists until
`docs/trunk-removal-plan.md` is carried out; do not expect the two to match.

The contract it implements lives in the runtime repo:
`src/xrt/include/xrt/xrt_input_plugin.h`, `docs/guides/input-provider-onboarding.md`,
`docs/specs/runtime/input-provider-discovery.md`, ADR-034, ADR-054, ADR-063.

**Windows is the only supported platform.** Linux and macOS build files are kept and
CI builds and load-checks them against the stand-in; they are experimental and not
released. Do not describe them as supported.

## Invariants — read before changing anything

1. **Pin and range.** `DXR_RUNTIME_GIT_TAG` (`CMakeLists.txt`) and `RUNTIME_REF` in
   every workflow are one value; change them in one commit (the `lint` job fails
   otherwise). Keep the CMake pin a plain `set(DXR_RUNTIME_GIT_TAG "vX.Y.Z"` literal —
   the runtime's pin tooling regexes it. `catalog/ultraleap-hands.json`
   `runtime_range` records which runtime releases the binary is valid for: `build` =
   the pin, `min`..`verified_max` = the releases whose shared headers are
   byte-identical to the pin's (`scripts/runtime_range.py`; the `range` job fails on a
   range that is not true). Never widen the range by hand without running the script,
   and never describe a binary as compatible with a runtime on the strength of the ABI
   major: the provider returns raw `struct xrt_device` (ADR-063). The rule is
   `docs/trunk-dependencies.md` section 7.
2. **Nothing of Ultraleap's in this repository or its artifacts.** No Ultraleap
   header, library or DLL committed, cached publicly, staged, copied or packaged. The
   provider does not link LeapC: it binds it at run time, by absolute path, from the
   user's Ultraleap install (`src/ultraleap/ultraleap_leapc.c`). CI asserts the
   provider has no LeapC import. Never open LeapC by bare name — that is how another
   `LeapC.dll` on `PATH` gets loaded (#933).
3. **A missing Ultraleap install is a state, not a failure.** `probe()` and
   `create_devices` succeed without LeapC; the provider reports `ABSENT`, logs where
   it looked, and retries. Do not reintroduce a path where the provider fails to load
   or `create_devices` fails because the vendor software is absent.
4. **`tests/leapc_stub/` is a stand-in, not LeapC.** It declares only the names the
   provider uses, with invented layouts, and builds a loadable library carrying a
   marker symbol. A stand-in build is named `DisplayXR-Ultraleap-STUBCHECK`, has no
   install or packaging rule, and binds only a library with the marker; a real build
   refuses one. When the provider starts using a new LeapC name, add it to the header,
   the `.c`, `struct ul_leapc`, `bind_all` and the signature check. Never report a
   stand-in result as "the provider works".
5. **One exported symbol.** Hidden visibility plus the exported-symbol list (macOS) /
   version script (ELF); CI asserts it.
6. **Settings only through the host.** Every knob is in the table in
   `ultraleap_map.c` (declared by `describe_settings`, parsed there, unit-tested) and
   read via `host->get_setting`. The only `getenv` left is the one-release alias for
   the two old `DXR_ULTRALEAP_*` names in `ultraleap_plugin.c`; do not add another.
7. **The installer owns only its own rows and files**: `InputProviders\ultraleap`,
   `Plugins\Ultraleap`, its ARP key, its one allowlist row, one DLL. It never touches
   the runtime's directory, another provider's row, `InputProviders\Policy`, the
   Ultraleap install, or the Ultraleap layer's registration.

## Layout

| Path | What |
|---|---|
| `src/ultraleap/ultraleap_plugin.c` | entry point, host iface slots (`get_setting`, `get_display_geometry`), the vtable, settings read, the implicit-layer warning |
| `src/ultraleap/ultraleap_provider.cpp` | the process-scoped hub (LeapC connection + poll thread, presence, idle watchdog, the no-LeapC retry) and the two devices |
| `src/ultraleap/ultraleap_leapc.{h,c}` | run-time binding of LeapC: candidates, absolute-path load, state, signature check |
| `src/ultraleap/ultraleap_map.{c,h}` | pure sensor → display-plane mapping and **all** declared settings; no LeapC, no OS |
| `src/ultraleap/ultraleap_layer.{h,c}` | Ultraleap's implicit OpenXR layer: name, off switch, advice text |
| `src/ultraleap/CMakeLists.txt` | per-platform linkage: runtime import library + `XRT_USING_RUNTIME_DLL` on Windows / macOS, static aux on Linux; no LeapC |
| `cmake/FindLeapC.cmake` | finds `LeapC.h` (`LEAPSDK_DIR`, default paths, the stand-in) |
| `tests/` | `tests_ultraleap_map`, `tests_ultraleap_leapc`, the stand-in (`leapc_stub/`) |
| `installer/` | NSIS script, allowlist-row generator |
| `manifest/` | POSIX discovery manifest template (experimental platforms) |
| `catalog/` | draft catalog entry, including the runtime range |
| `scripts/` | build entry points, `ci-load-check.{sh,ps1}`, `runtime_range.py`, `check_catalog.py`, `sign-release.sh` |
| `docs/` | dependency audit + range rule, packaging, Windows validation checklist, template notes, trunk-removal plan |

## Build and test

```bash
scripts/build-posix.sh                 # no SDK: unit tests only, prints the NOT BUILT message
scripts/build-posix.sh --stub          # stand-in build of the provider + unit tests
cmake --build build-stub --target cli drv_sim_display_plugin leapc_stub
scripts/ci-load-check.sh build-stub    # load through the pinned runtime: not-found state, then the stand-in
```
```bat
scripts\build-windows.bat all          REM needs LEAPSDK_DIR (LeapC.h) and a runtime checkout at the pin
```

The first configure fetches and later builds runtime libraries: minutes, not seconds.
`--runtime <checkout>` reuses a local runtime tree; it must be at the pinned tag for
anything shipped. Do not build inside, or write into, the runtime checkout.

Driving a stand-in build by hand: `XRT_PLUGIN_SEARCH_PATH=<dir with manifests>` on
POSIX, and `DXR_INPUT_ULTRALEAP_LEAPC_PATH=<build>/tests/leapc_stub_lib` to bind the
stand-in library (unset = the not-found state). On macOS a plug-in needs an rpath to
`openxr_displayxr.dylib`; this build sets one, the runtime's raw build-tree
`DisplayXR-SimDisplay.dylib` does not (`ci-load-check.sh` adds it).

CI (`.github/workflows/build.yml`) runs all of the above on hosted Linux, macOS and
Windows. After changing a workflow, read the logs of the run; a green tick on a job
that skipped its work is not a result.

## Honesty about verification

`README.md` has the list of what was run and what was not, and
`docs/windows-validation.md` is the checklist for the box with the hardware. Nothing
has run against a real LeapC or a camera. When you verify something there, move it
across in the README list and remove the matching *to verify* marker. Do not remove a
marker on the strength of reading code or of a stand-in run.

## Conventions

- Runtime code style: tabs, `snake_case`, the `ul_` prefix, C11 / C++17.
- `U_LOG_W` only for one-off lifecycle events; never per frame.
- New provider sources: BSL-1.0, `The DisplayXR Project`. Files adapted from
  `displayxr-input-template` keep Apache-2.0.
- No vendor SDK material, no private repository names, no signing-provider path in
  this repository. The signing provider is `DXR_SIGN_REPO`, from the environment.

## Releasing

Not done yet, and not to be done without the project lead's say-so. Tag `vX.Y.Z` →
`release.yml` on the self-hosted `ultraleap-sdk` runner → unsigned Windows installer
on the GitHub release → optional signed replacement (`scripts/sign-release.sh`) →
optional `versions-bump` dispatch. The runner, the signing component and the runtime's
`ultraleap` field do not exist yet (`docs/trunk-removal-plan.md`, section B). `main`
has no ruleset yet: an org admin still has to apply the org ruleset and the
publish-bot bypass.
