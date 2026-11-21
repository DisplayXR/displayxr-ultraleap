# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

The **Ultraleap hands input provider** for the DisplayXR runtime, moved out of the
runtime trunk (`src/xrt/drivers/ultraleap/`). It builds `DisplayXR-Ultraleap.{dll,so,dylib}`
(export `xrtInputPluginNegotiate`, registered id `ultraleap`, ProbeOrder 50) and
doubles as the worked example of an out-of-tree input provider that wraps a vendor
SDK. The contract it implements lives in the runtime repo:
`src/xrt/include/xrt/xrt_input_plugin.h`, `docs/guides/input-provider-onboarding.md`,
`docs/specs/runtime/input-provider-discovery.md`, ADR-034, ADR-054, ADR-063.

## Invariants — read before changing anything

1. **The runtime pin is exact.** `DXR_RUNTIME_GIT_TAG` (`CMakeLists.txt`),
   `RUNTIME_REF` (`.github/workflows/build.yml` and `release.yml`) and the range in
   `catalog/ultraleap-hands.json` (`requires.runtime`, `runtime_range.min`, `.max`)
   are one value. Change all of them in one commit; the `pin` CI job fails otherwise.
   The reason is `docs/trunk-dependencies.md`: the provider returns raw
   `struct xrt_device`, which the input ABI version does not cover (ADR-063). Never
   describe a binary as compatible with a range of runtimes on the strength of the
   ABI major. Keep the CMake pin a plain `set(DXR_RUNTIME_GIT_TAG "vX.Y.Z"` literal —
   the runtime's pin tooling regexes it.
2. **LeapC is never committed, fetched or bundled by default.** No Ultraleap header,
   library or DLL in this repository or in a CI cache that is public.
   `ULTRALEAP_BUNDLE_LEAPC` stays OFF until the redistribution licence is cleared.
3. **`tests/leapc_stub/` is a compile-check stand-in, not LeapC.** It declares only
   the names the provider uses, with invented layouts. A stub build is named
   `DisplayXR-Ultraleap-STUBCHECK`, has no install or packaging rule, and proves only
   that the sources compile and link. When the provider starts using a new LeapC name,
   add it to the stub. Never report a stub result as "the provider works".
4. **One exported symbol.** Hidden visibility plus the exported-symbol list (macOS) /
   version script (ELF); CI asserts it.
5. **The installer owns only its own rows and files**: `InputProviders\ultraleap`,
   `Plugins\Ultraleap`, its ARP key, its one allowlist row, and a `LeapC.dll` only if a
   run of this installer placed it (`LeapCPlaced`). It never touches the runtime's
   directory, another provider's row, `InputProviders\Policy`, or the Ultraleap layer's
   registration.
6. **The provider sources are still byte-identical to the trunk at the pinned tag.**
   Until the trunk copy is removed (`docs/trunk-removal-plan.md`), a change here is a
   fork: say so in the commit, and decide whether it also goes to the trunk.

## Layout

| Path | What |
|---|---|
| `src/ultraleap/ultraleap_plugin.c` | entry point, host iface slots (`get_setting`, `get_display_geometry`), the vtable, the implicit-layer warning |
| `src/ultraleap/ultraleap_provider.cpp` | the process-scoped hub (LeapC connection + poll thread, presence, idle watchdog) and the two devices |
| `src/ultraleap/ultraleap_map.{c,h}` | pure sensor → display-plane mapping and the declared settings; no LeapC, no OS |
| `src/ultraleap/CMakeLists.txt` | per-platform linkage: runtime import library + `XRT_USING_RUNTIME_DLL` on Windows / macOS, static aux on Linux |
| `cmake/FindLeapC.cmake` | SDK discovery (`LEAPSDK_DIR`, default paths, the stub) |
| `tests/` | `tests_ultraleap_map` (runs everywhere) and the LeapC stub |
| `installer/` | NSIS script, allowlist-row generator |
| `manifest/` | POSIX discovery manifest template |
| `catalog/` | draft catalog entry; `scripts/check_catalog.py` keeps it equal to the pin |
| `scripts/` | build entry points, Linux tarball, `sign-release.sh`, `runtime_range.py` |
| `docs/` | dependency audit, packaging, template notes, trunk-removal plan |

## Build and test

```bash
scripts/build-posix.sh                 # no SDK: unit test only, prints the NOT BUILT message
scripts/build-posix.sh --stub          # compile-check against tests/leapc_stub
scripts/build-posix.sh --sdk <LeapSDK> # the real provider
```
```bat
scripts\build-windows.bat all          REM needs LEAPSDK_DIR and a runtime checkout at the pin
```

The first configure fetches and later builds runtime libraries: minutes, not seconds.
`--runtime <checkout>` reuses a local runtime tree; it must be at the pinned tag for
anything shipped. Do not build inside, or write into, the runtime checkout.

Loading a build through the runtime (use a `displayxr-cli` of the pinned release):
POSIX `XRT_PLUGIN_SEARCH_PATH=<dir with manifests>`; Windows
`register_dev_plugin.bat input <dll> ultraleap` (elevated, re-run after each rebuild).
On macOS a plug-in needs an rpath to `openxr_displayxr.dylib`; this build sets one,
the runtime's raw build-tree `DisplayXR-SimDisplay.dylib` does not.

## Honesty about verification

`README.md` has the list of what was run and what was not. As of the initial import
nothing was built against the real SDK and nothing ran on Windows. When you verify
something on the Windows box with the hardware, move it across in that list and
remove the matching *to verify* marker in `docs/packaging.md` or the catalog entry.
Do not remove a marker on the strength of reading code.

## Conventions

- Runtime code style: tabs, `snake_case`, the `ul_` prefix, C11 / C++17.
- `U_LOG_W` only for one-off lifecycle events; never per frame.
- Read settings through `host->get_setting` and declare them in `describe_settings`.
  The two remaining `getenv` knobs are known debt, not a pattern to copy.
- New provider sources: BSL-1.0, `The DisplayXR Project`. Files adapted from
  `displayxr-input-template` keep Apache-2.0.
- No vendor SDK material, no private repository names, no signing-provider path in
  this repository. The signing provider is `DXR_SIGN_REPO`, from the environment.

## Releasing

Tag `vX.Y.Z` → `release.yml` on the self-hosted `ultraleap-sdk` runner → unsigned
installer on the GitHub release → optional signed replacement
(`scripts/sign-release.sh`) → optional `versions-bump` dispatch. None of this has run.
The runner, the signing component and the runtime's `ultraleap` field do not exist
yet (`docs/trunk-removal-plan.md`, section B).
