# Validation on the Windows box with the Ultraleap hardware

CI covers the build against a stand-in, the load through the runtime, and the "no
Ultraleap software" state; it cannot cover the real LeapC or a camera. Tick items
here, then move them to the verified list in `README.md` and remove the matching
*to verify* markers in `docs/packaging.md`, `src/ultraleap/ultraleap_leapc.c` and
`catalog/ultraleap-hands.json`.

Record for the run: Ultraleap software version, camera model, runtime version,
provider commit.

**Run 1 (2026-11-23, 8k-box, #9):** Ultraleap 6.2.0+2025.07.11.824112c4, Leap Motion
Controller 2 (USB VID_2936 PID_1206, firmware 3.8.7), installed runtime v2.70.3 with
the Leia SR plug-in 2.23.4 (the LeiaSR Platform is installed, with its own
`LeapC.dll` on the machine `PATH`), provider 58668b1 and branch
`fix/9-desktop-tracking-mode`. Built against a runtime checkout at v2.69.3 (see #11).

## 1. Build against the real SDK header

- [x] `scripts\build-windows.bat all` with `LEAPSDK_DIR` set, runtime checkout at the
      pinned tag. It must compile: `ultraleap_leapc.c` contains a compile-time check
      that the six bound function-pointer types equal the prototypes of the SDK's
      `LeapC.h`, so a signature drift is a build error here, not a crash later.
      *Run 1: compiles. Needs `DXR_RUNTIME_SOURCE_DIR` (a runtime checkout with
      `vcpkg\`) and a short repo path; the FetchContent route stops at Eigen3 (#11).*
- [x] `dumpbin /dependents _package\bin\plugins\DisplayXR-Ultraleap.dll` lists
      `DisplayXRClient.dll` and **no** `LeapC.dll`; `dumpbin /exports` lists only
      `xrtInputPluginNegotiate`.
- [x] No `LeapC.dll` anywhere under `_package\`.
- [x] Against the **installed, released** runtime: every non-system DLL in the
      provider's `dumpbin /dependents` (CI saw `pthreadVCE3.dll` and `cjson.dll`) is
      also in `dumpbin /dependents "C:\Program Files\DisplayXR\Runtime\DisplayXRClient.dll"`
      or sits in that directory. If not, the provider cannot load from
      `Plugins\Ultraleap\`: build it with the runtime release's own vcpkg
      configuration. *Run 1: both are imported by the v2.70.3 client and sit in its
      directory.*

## 2. Finding LeapC at run time

- [x] Where the current Ultraleap installer puts `LeapC.dll`. The provider's only
      default is `%ProgramW6432%\Ultraleap\LeapSDK\lib\x64\LeapC.dll`. If the
      tracking software installs without the SDK folder, or keeps `LeapC.dll`
      elsewhere, add that location to `ul_leapc_default_candidate` — otherwise every
      user needs `LEAPC_PATH`. *Run 1: 6.2.0 installs `LeapSDK\lib\x64\LeapC.dll`;
      the default is right.*
- [x] With the dev DLL registered (`register_dev_plugin.bat input <dll> ultraleap`),
      the log (`%LOCALAPPDATA%\DisplayXR\DisplayXR_<exe>.<pid>_<ts>.log`) says
      `ultraleap: LeapC loaded from <that path>`.
- [x] **#933**: on a box that also has the LeiaSR Platform (its own `LeapC.dll` on
      `PATH`), confirm with Process Explorer / `listdlls` that the `LeapC.dll` mapped
      into the host is the Ultraleap one, not `LeiaSR\Platform\bin\LeapC.dll`.
      *Run 1: the provider's LeapC is `Ultraleap\LeapSDK\lib\x64\LeapC.dll`. In a D3D11
      app the SR stack also maps `LeiaSR\Platform\bin\LeapC.dll` for itself; the
      provider still binds the Ultraleap one by absolute path.*
- [ ] `displayxr-cli input set ultraleap LEAPC_PATH <dir>` pointing at a copy in
      another folder is honoured; pointing at a folder with no `LeapC.dll` falls back
      to the default location, and the load line says so: `LeapC loaded from <default>
      - the LEAPC_PATH setting '<dir>' has no usable LeapC (no LeapC.dll at …), so a
      default location was used`. (The fallback is deliberate, #10: a stale setting
      must not break hands on a box that has the software.) *Run 1: a copy (folder
      or file path) is honoured. A folder without LeapC fell back with no line saying
      so (#10, fixed).*
- [ ] Not-found state for real: rename the Ultraleap folder (or test on a box
      without the software). `displayxr-cli selftest` passes, `input_providers` says
      the provider loaded with its hardware absent, the log has
      `Ultraleap tracking software NOT FOUND`, apps get the keyboard/mouse
      controllers. Restore the folder while an app is running: hands appear within
      about 5 s plus the connect time, no restart.

## 3. Tracking

- [x] Camera on the desk, Desktop mode, the Ultraleap layer disabled (section 5):
      both hands drive the right controllers, left is left. *Run 1, by eye: "hand
      tracking is perfect" once Desktop mode held.*
- [ ] Pinch → select click, grab → menu click, with hysteresis (no chatter at the
      threshold).
- [x] `XR_EXT_hand_tracking` joints in an app that draws them (26 joints, plausible
      radii, fingertips that touch stay touching). *Run 1: `cube_handle_d3d11_win
      --hands`. A test-app build older than 5695f5c6b (runtime repo) draws the hands
      far too small in a window; rebuild the test apps first.*
- [ ] Pose prediction: no visible lag or overshoot on fast motion.
- [ ] `MAPPING=relative` defaults place a hand held about 25 cm above the camera at
      the display centre; `MAPPING=physical` with measured `MOUNT_*_M` is 1:1.
- [ ] Both hosting paths: in-process app, and `XRT_FORCE_MODE=ipc` against a running
      `displayxr-service.exe` (settings then come from the store / the **service's**
      environment). *Run 1: in-process only.*

## 4. Presence and lifetime

- [ ] Start with the camera unplugged: roles on keyboard/mouse; plug in: roles move
      to the provider without restarting the app (`displayxr-cli input haptic-test 30`
      prints the role generation changes); unplug: they move back.
- [ ] Stop the Ultraleap tracking service while running: presence goes absent, the
      provider reconnects when the service returns.
- [ ] Idle watchdog (#941): with no app polling for 5 s the Leap connection closes
      (log line, and the tracking service's CPU use drops); the next app's first poll
      reopens it.
- [ ] `SETTLE_MS=0` and the default 300: the first `xrSyncActions` binds the provider
      when the camera is attached (no interaction-profile flip right after start).
- [ ] `PERSIST_HUB`: default keeps one Leap connection across `xrCreateInstance` /
      `xrDestroyInstance` cycles; `0` logs the per-instance teardown.
- [ ] Old names: `DXR_ULTRALEAP_SETTLE_MS` / `DXR_ULTRALEAP_PERSIST_HUB` in the host's
      environment still take effect and log the deprecation warning once.
- [ ] Conformance smoke (the #1545 case): a run that creates and destroys many
      instances does not re-spin LeapC each time.

## 5. The Ultraleap implicit OpenXR layer

- [x] With the layer enabled, the provider logs the advice once and
      `displayxr-cli selftest` prints `WARN: ULTRALEAP_OPENXR_LAYER`.
- [x] `DISABLE_XR_APILAYER_ULTRALEAP_HAND_TRACKING_1=1` in the user environment,
      OpenXR apps restarted, Desktop mode re-selected: hands are no longer swapped.
- [x] The registry value name of the layer's manifest contains
      `UltraleapHandTracking` (the installer's check matches on that), and which hive
      it is in. *Run 1: `C:\Program Files\Ultraleap\OpenXR\UltraleapHandTracking.json`
      in HKLM, DWORD 0 = enabled.*
- [x] What switches the mode (#9). *Run 1: an app that only loads the layer did not
      switch it. An app that loads it and creates a hand tracker switches the service
      to HMD, and switches it back about 0.8 s after every change, so re-asserting
      against it only flaps the tracker. When that app closes, the service returns
      to Desktop within seconds. The DisplayXR Browser loads the layer.*
- [x] Provider with `TRACKING_MODE=desktop` (#9): connect logs "asked the service for
      Desktop tracking mode" and then the mode the service reports. Against the
      layer's push-back each provider re-asserts once, then logs "not fighting it"
      once and stops (no flapping from our side).

## 6. Installer

- [ ] `scripts\build-windows.bat installer`, then run
      `DisplayXRUltraleapSetup-*.exe` interactively and with `/S`. *Run 1: `/S` only.*
- [x] Rows written: `InputProviders\ultraleap` (`Binary`, `ProbeOrder` 50, `Version`
      last), the allowlist digest, `Plugins\Ultraleap\*`. `displayxr-cli input list`
      shows the provider with provenance `allowlisted` (or `signed`).
- [x] Only `DisplayXR-Ultraleap.dll` and `Uninstall.exe` in
      `C:\Program Files\DisplayXR\Plugins\Ultraleap\`.
- [ ] Runtime range: on a runtime older than the minimum the installer stops with
      exit code 3 (`/FORCE` installs); on one newer than the verified maximum it
      installs with the notice. Check the format of
      `HKLM\Software\DisplayXR\Runtime\Version` that the comparison reads.
- [ ] Without the Ultraleap software: the installer says so and still installs.
- [ ] Upgrade over itself while `displayxr-service.exe` is running: the DLL is
      released (Restart Manager) and the service comes back non-elevated.
- [ ] Uninstall removes exactly its rows and files, with and without the runtime
      installed. *Run 1: with the runtime installed, PASS.*
- [x] Layer handling (#9). *Run 1:*
      - `/S` with DisplayXR the active runtime: layer DWORD 0 -> 1, `DisabledUltraleapLayer` recorded, the selftest warning is gone, and an app run with the user-level disable cleared no longer loads the layer (mode stays Desktop).
      - Uninstall: DWORD back to 0.
      - `/S /LAYER=keep`: untouched.
      - Turned off, then re-enabled by hand, then uninstall: left at 0.
- [ ] Do not run the installer or uninstaller on a shared dev box that has a
      hand-registered dev row you want to keep: it overwrites
      `InputProviders\ultraleap`.

## 7. Release lane (when a runner exists)

- [ ] A self-hosted runner labelled `ultraleap-sdk` with the SDK installed; set the
      repository variables `ULTRALEAP_SDK_RUNNER=true` and `ULTRALEAP_LEAPSDK_DIR`.
      The `sdk-windows` job goes green.
- [ ] Signed build path: `SIGN_CMD` set, `scripts\build-windows.bat all` signs the
      DLL, the installer and the uninstaller.
