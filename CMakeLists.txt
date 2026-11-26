# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# DisplayXR Ultraleap hands input provider — standalone (out-of-tree) build.
#
# Builds DisplayXR-Ultraleap.{dll,so,dylib}: the `ultraleap` input provider
# (export `xrtInputPluginNegotiate`), moved out of the runtime trunk
# (`src/xrt/drivers/ultraleap/`). Two external inputs:
#
#   1. The DisplayXR runtime source at a PINNED RELEASE TAG. The provider does
#      not only use the public input-provider headers: it links runtime aux
#      libraries (device allocator, relation history, u_var, threading) and, on
#      Windows / macOS, the runtime's import library. See
#      docs/trunk-dependencies.md — that is why the pin is exact, not a floor.
#   2. The Ultraleap tracking SDK's HEADER (LeapC.h). NOT redistributed here
#      and not fetched: point LEAPSDK_DIR at an install, or let the default SDK
#      paths find it. Without it nothing shippable is built (see the message
#      below). The LeapC LIBRARY is not linked: the provider binds it at run
#      time from the user's Ultraleap install (src/ultraleap/ultraleap_leapc.c).

cmake_minimum_required(VERSION 3.22)

project(
    DisplayXR-Ultraleap
    VERSION 0.1.0
    LANGUAGES C CXX
    DESCRIPTION "DisplayXR Ultraleap hands input-provider plug-in"
)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED BUILD_NUM)
    set(BUILD_NUM "0")
endif()

option(ULTRALEAP_BUILD_TESTS "Build the hardware-free unit tests (ctest)" ON)
option(ULTRALEAP_USE_LEAPC_STUB
    "COMPILE-CHECK ONLY: build against the stand-in header in tests/leapc_stub instead of the real LeapC.h. The result is NOT a working provider and is never installed or packaged."
    OFF)

# --------------------------------------------------------------------------
# Runtime dependency — pinned EXACTLY.
#
#   - DXR_RUNTIME_SOURCE_DIR set to a local displayxr-runtime checkout: fast
#     dev iteration. The checkout must be AT the pinned tag for anything you
#     intend to ship (the configure step warns when it is not).
#   - Otherwise FetchContent fetches DXR_RUNTIME_GIT_TAG from GitHub.
#
# Keep the pin a plain literal: the runtime's downstream-pin tooling
# (downstream-pins.json, kind=cmake_set) regexes `set(DXR_RUNTIME_GIT_TAG "vX.Y.Z"`.
#
# WHAT THE PIN MEANS: the provider returns raw `struct xrt_device`s, which the
# input plug-in ABI version does not cover (runtime ADR-063, Proposed). A
# binary built at this tag is valid on the runtime releases whose shared
# headers are byte-identical to this tag's (scripts/runtime_range.py). That
# VERIFIED RANGE is recorded in catalog/ultraleap-hands.json and checked in CI;
# the installer's runtime floor derives from it (docs/trunk-dependencies.md).
# --------------------------------------------------------------------------
set(DXR_RUNTIME_GIT_TAG "v2.70.10" CACHE STRING
    "displayxr-runtime release tag this provider is built against (exact pin, ADR-063).")
set(DXR_RUNTIME_SOURCE_DIR "" CACHE PATH
    "Optional local displayxr-runtime checkout to build against instead of fetching.")

# The runtime tree is only a dependency: none of its tests, and nothing of it
# in `all` / `install`.
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(XRT_FEATURE_DEBUG_GUI OFF CACHE BOOL "" FORCE)
set(XRT_FEATURE_WINDOW_PEEK OFF CACHE BOOL "" FORCE)
# NOTE on cJSON: aux_util (linked statically into the provider) uses the
# SYSTEM cJSON when the runtime tree finds one (XRT_HAVE_SYSTEM_CJSON), which
# leaves the provider with a load dependency on a cJSON shared library. This
# project does not override that choice: on macOS, forcing it OFF fails to
# compile the runtime's bundled copy at v2.69.3 when Homebrew's cjson headers
# are also on the include path (docs/trunk-dependencies.md, "cJSON").

if(DXR_RUNTIME_SOURCE_DIR)
    get_filename_component(_dxr_rt "${DXR_RUNTIME_SOURCE_DIR}" ABSOLUTE)
    message(STATUS "Using local runtime checkout: ${_dxr_rt}")
    find_package(Git QUIET)
    if(Git_FOUND)
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${_dxr_rt}" describe --tags --always
            OUTPUT_VARIABLE _dxr_rt_describe OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
        if(NOT _dxr_rt_describe STREQUAL DXR_RUNTIME_GIT_TAG)
            message(WARNING
                "Local runtime checkout is at '${_dxr_rt_describe}', not the pinned ${DXR_RUNTIME_GIT_TAG}. "
                "Fine for development; do NOT ship this binary - the xrt_device layout is not "
                "ABI-versioned (ADR-063), so a provider is only known-good on the release it was built at.")
        endif()
    endif()
    add_subdirectory("${_dxr_rt}" runtime-build EXCLUDE_FROM_ALL)
else()
    include(FetchContent)
    message(STATUS "Fetching displayxr-runtime via FetchContent @ ${DXR_RUNTIME_GIT_TAG}")
    FetchContent_Declare(
        displayxr_runtime
        GIT_REPOSITORY https://github.com/DisplayXR/displayxr-runtime.git
        GIT_TAG "${DXR_RUNTIME_GIT_TAG}"
        GIT_SHALLOW TRUE
        EXCLUDE_FROM_ALL
    )
    FetchContent_MakeAvailable(displayxr_runtime)
    set(_dxr_rt "${displayxr_runtime_SOURCE_DIR}")
endif()
set(DXR_RUNTIME_ROOT "${_dxr_rt}")

if(NOT TARGET aux_util OR NOT TARGET aux_math OR NOT TARGET aux_os OR NOT TARGET xrt-interfaces)
    message(FATAL_ERROR "The runtime tree at ${DXR_RUNTIME_ROOT} did not define the aux targets this provider links.")
endif()

string(REGEX REPLACE "^v" "" DXR_RUNTIME_PIN_VERSION "${DXR_RUNTIME_GIT_TAG}")
# The verified runtime range lives in the catalog entry (one source of truth).
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/catalog/ultraleap-hands.json" _ul_catalog)
string(JSON DXR_RUNTIME_RANGE_MIN GET "${_ul_catalog}" runtime_range min)
string(JSON DXR_RUNTIME_RANGE_MAX GET "${_ul_catalog}" runtime_range verified_max)
message(STATUS "Runtime pin ${DXR_RUNTIME_GIT_TAG}; verified range ${DXR_RUNTIME_RANGE_MIN} .. ${DXR_RUNTIME_RANGE_MAX}")

# --------------------------------------------------------------------------
# LeapC.
# --------------------------------------------------------------------------
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(FindLeapC)

# --------------------------------------------------------------------------
# Unit tests first: the mapping test needs neither LeapC nor a device, so it
# runs on every machine, including the ones that cannot build the provider.
# --------------------------------------------------------------------------
if(ULTRALEAP_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(NOT ULTRALEAP_LEAPC_FOUND)
    message(STATUS "")
    message(STATUS "==================================================================")
    message(STATUS " Ultraleap input provider: NOT BUILT - LeapC SDK not found.")
    message(STATUS "")
    message(STATUS " Install the Ultraleap tracking software + SDK (Gemini / Hyperion),")
    message(STATUS " or point LEAPSDK_DIR at an SDK root that has include/LeapC.h")
    message(STATUS " (only the header is needed to build; LeapC is bound at run time):")
    message(STATUS "     cmake -S . -B build -DLEAPSDK_DIR=<path to LeapSDK>")
    message(STATUS " Default locations searched:")
    foreach(_p IN LISTS ULTRALEAP_LEAPC_DEFAULT_ROOTS)
        message(STATUS "     ${_p}")
    endforeach()
    message(STATUS "")
    message(STATUS " Only the hardware-free unit tests are configured. To compile-check")
    message(STATUS " the provider sources without the SDK (NOT a usable binary):")
    message(STATUS "     cmake -S . -B build -DULTRALEAP_USE_LEAPC_STUB=ON")
    message(STATUS "==================================================================")
    message(STATUS "")
    return()
endif()

add_subdirectory(src/ultraleap)

if(ULTRALEAP_USE_LEAPC_STUB)
    message(WARNING
        "ULTRALEAP_USE_LEAPC_STUB=ON: building DisplayXR-Ultraleap-STUBCHECK against tests/leapc_stub. "
        "This is a syntax / link-surface check only. No install rules, no manifest, no installer.")
    return()
endif()

# POSIX registration manifest (generated with the install path baked in).
if(NOT WIN32)
    include(GNUInstallDirs)
    set(ULTRALEAP_BINARY_PATH
        "${CMAKE_INSTALL_FULL_LIBDIR}/displayxr/plugins/$<TARGET_FILE_NAME:displayxr_ultraleap>")
    configure_file(manifest/050-ultraleap-input-provider.json.in
        "${CMAKE_CURRENT_BINARY_DIR}/050-ultraleap-input-provider.json.gen" @ONLY)
    file(GENERATE
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/050-ultraleap-input-provider.json"
        INPUT "${CMAKE_CURRENT_BINARY_DIR}/050-ultraleap-input-provider.json.gen")
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/050-ultraleap-input-provider.json"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/DisplayXR/DisplayProcessors")
endif()

if(WIN32)
    add_subdirectory(installer)
endif()
