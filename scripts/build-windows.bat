@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: DisplayXR Ultraleap hands input provider - local Windows build
:: Copyright 2026, The DisplayXR Project. SPDX-License-Identifier: BSL-1.0
:: ============================================================
:: Usage: scripts\build-windows.bat [generate|build|installer|all] [config]
::   generate   - CMake configure only
::   build      - build the provider DLL + install into _package\
::   installer  - build the NSIS installer (needs build)
::   all        - everything (default)
::   config     - Release (default) | RelWithDebInfo | Debug
::
:: Environment:
::   LEAPSDK_DIR            - Ultraleap LeapSDK root (has include\LeapC.h). Only the
::                            HEADER is used: LeapC.dll is bound at run time.
::                            Default search: C:\Program Files\Ultraleap\LeapSDK.
::   DXR_RUNTIME_SOURCE_DIR - a local displayxr-runtime checkout that has been
::                            built once with its scripts\build_windows.bat (it
::                            carries the vcpkg toolchain + OpenXR loader). If
::                            unset, the sibling ..\displayxr-runtime is used.
::                            IT MUST BE AT THE TAG PINNED IN CMakeLists.txt
::                            (DXR_RUNTIME_GIT_TAG) for anything you ship; CMake
::                            warns when it is not. Without a local checkout,
::                            CMake fetches the pinned tag, and you must supply
::                            the runtime's build dependencies yourself (vcpkg
::                            toolchain, OpenXR loader) - see .github\workflows.
::   SIGN_CMD               - code-signing command; empty = unsigned build.
::   BUILD_NUM              - fourth version component of the installer name.
::
:: LeapC.dll is never copied or staged: the provider opens it by absolute path
:: from the Ultraleap install at run time (LEAPC_PATH setting to override).
:: ============================================================

set SCRIPT_DIR=%~dp0
set REPO=%SCRIPT_DIR%..\
set TARGET=%~1
if "%TARGET%"=="" set TARGET=all
set CONFIG=%~2
if "%CONFIG%"=="" set CONFIG=Release

if "%DXR_RUNTIME_SOURCE_DIR%"=="" (
    if exist "%REPO%..\displayxr-runtime\CMakeLists.txt" (
        set DXR_RUNTIME_SOURCE_DIR=%REPO%..\displayxr-runtime
        echo Detected local runtime at !DXR_RUNTIME_SOURCE_DIR!
    ) else (
        echo No local runtime checkout: CMake will fetch the pinned tag.
    )
)

echo === Setting up MSVC environment ===
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VCVARS="
if exist "%VSWHERE%" (
    for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
        if exist "%%i\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=%%i\VC\Auxiliary\Build\vcvars64.bat"
    )
)
if not defined VCVARS (
    echo ERROR: VS 2022 with the C++ workload not found.
    exit /b 1
)
call "%VCVARS%" >nul 2>&1

if "%TARGET%"=="build" if exist "%REPO%build\build.ninja" goto :do_build
if "%TARGET%"=="installer" if exist "%REPO%build\build.ninja" goto :do_installer

echo === CMake Generate ===
set CMAKE_ARGS=-S "%REPO%." -B "%REPO%build" -G "Ninja Multi-Config" -DCMAKE_INSTALL_PREFIX="%REPO%_package"
if not "%LEAPSDK_DIR%"=="" set CMAKE_ARGS=!CMAKE_ARGS! -DLEAPSDK_DIR="%LEAPSDK_DIR%"
if not "%BUILD_NUM%"=="" set CMAKE_ARGS=!CMAKE_ARGS! -DBUILD_NUM=%BUILD_NUM%
if not "%DXR_RUNTIME_SOURCE_DIR%"=="" (
    set CMAKE_ARGS=!CMAKE_ARGS! -DDXR_RUNTIME_SOURCE_DIR="%DXR_RUNTIME_SOURCE_DIR%"
    if exist "%DXR_RUNTIME_SOURCE_DIR%\vcpkg\scripts\buildsystems\vcpkg.cmake" (
        set CMAKE_ARGS=!CMAKE_ARGS! -DCMAKE_TOOLCHAIN_FILE="%DXR_RUNTIME_SOURCE_DIR%\vcpkg\scripts\buildsystems\vcpkg.cmake" -DVCPKG_MANIFEST_DIR="%DXR_RUNTIME_SOURCE_DIR%"
        echo Using the runtime checkout's vcpkg toolchain.
    )
    if exist "%DXR_RUNTIME_SOURCE_DIR%\openxr_sdk\x64\lib\openxr_loader.lib" (
        set CMAKE_ARGS=!CMAKE_ARGS! -DOpenXR_ROOT="%DXR_RUNTIME_SOURCE_DIR%\openxr_sdk"
    )
)
cmake !CMAKE_ARGS!
if errorlevel 1 exit /b 1
if "%TARGET%"=="generate" goto :done

:do_build
echo === Build + install (%CONFIG%) ===
cmake --build "%REPO%build" --config %CONFIG% --target install
if errorlevel 1 exit /b 1
if not exist "%REPO%_package\bin\plugins\DisplayXR-Ultraleap.dll" (
    echo.
    echo No provider DLL was produced - LeapC.h was not found.
    echo Set LEAPSDK_DIR to a LeapSDK root ^(it needs include\LeapC.h^) and run again.
    exit /b 1
)
if "%TARGET%"=="build" goto :done

:do_installer
echo === Installer ===
cmake --build "%REPO%build" --config %CONFIG% --target installer
if errorlevel 1 exit /b 1

:done
echo.
echo Done. Provider: %REPO%_package\bin\plugins\DisplayXR-Ultraleap.dll
echo Register for dev ^(elevated; re-run after every rebuild - it allowlists the digest^):
echo   ^<runtime^>\scripts\register_dev_plugin.bat input "%REPO%_package\bin\plugins\DisplayXR-Ultraleap.dll" ultraleap
endlocal
