# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# Locate the Ultraleap tracking SDK's C API (LeapC).
#
# Inputs (first match wins):
#   -DLEAPSDK_DIR=<root>   or the LEAPSDK_DIR environment variable
#   the default SDK install locations per platform
#   -DULTRALEAP_USE_LEAPC_STUB=ON   compile-check stub (tests/leapc_stub), NOT an SDK
#
# Outputs:
#   ULTRALEAP_LEAPC_FOUND          TRUE when a header + library (or the stub) is usable
#   ULTRALEAP_LEAPC_INCLUDE_DIR    directory holding LeapC.h
#   ULTRALEAP_LEAPC_LIBRARY        the import / shared library (empty for the stub: it is a target)
#   ULTRALEAP_LEAPC_RUNTIME_DLL    Windows: LeapC.dll next to the import library, if present
#   ULTRALEAP_LEAPC_IS_STUB        TRUE for the compile-check stub
#   ULTRALEAP_LEAPC_DEFAULT_ROOTS  the default roots searched (for the "not found" message)
#
# The variable names are deliberately NOT `LEAPC_INCLUDE_DIR` / `LEAPC_LIBRARY`:
# the runtime tree this project adds as a subdirectory still has its own
# SDK-gated ultraleap block using those cache names, and the two must not share
# state (docs/trunk-removal-plan.md removes that block).

set(LEAPSDK_DIR "" CACHE PATH "Root of an Ultraleap LeapSDK install (has include/LeapC.h and lib/)")

set(ULTRALEAP_LEAPC_DEFAULT_ROOTS
    "C:/Program Files/Ultraleap/LeapSDK"
    "/opt/ultraleap-hand-tracking/LeapSDK"
    "/usr/local"
    "/usr"
    # macOS: where the Ultraleap app bundle is believed to carry its SDK. NOT
    # verified (no macOS SDK was available when this was written) - LEAPSDK_DIR
    # is the reliable route there.
    "/Applications/Ultraleap Hand Tracking.app/Contents/LeapSDK"
)

set(ULTRALEAP_LEAPC_FOUND FALSE)
set(ULTRALEAP_LEAPC_IS_STUB FALSE)
set(ULTRALEAP_LEAPC_RUNTIME_DLL "")

if(ULTRALEAP_USE_LEAPC_STUB)
    # The stub target (leapc_stub) is defined in tests/leapc_stub.
    set(ULTRALEAP_LEAPC_INCLUDE_DIR "${PROJECT_SOURCE_DIR}/tests/leapc_stub")
    set(ULTRALEAP_LEAPC_LIBRARY "")
    set(ULTRALEAP_LEAPC_IS_STUB TRUE)
    set(ULTRALEAP_LEAPC_FOUND TRUE)
    message(STATUS "LeapC: using the COMPILE-CHECK STUB (${ULTRALEAP_LEAPC_INCLUDE_DIR}) - not an SDK")
    return()
endif()

set(_leapc_hints "")
if(LEAPSDK_DIR)
    list(APPEND _leapc_hints "${LEAPSDK_DIR}")
endif()
if(DEFINED ENV{LEAPSDK_DIR})
    list(APPEND _leapc_hints "$ENV{LEAPSDK_DIR}")
endif()

find_path(ULTRALEAP_LEAPC_INCLUDE_DIR LeapC.h
    HINTS ${_leapc_hints}
    PATHS ${ULTRALEAP_LEAPC_DEFAULT_ROOTS}
    PATH_SUFFIXES include LeapSDK/include
)
find_library(ULTRALEAP_LEAPC_LIBRARY NAMES LeapC
    HINTS ${_leapc_hints}
    PATHS ${ULTRALEAP_LEAPC_DEFAULT_ROOTS}
    PATH_SUFFIXES lib lib/x64 lib/x86_64 LeapSDK/lib LeapSDK/lib/x64
)

if(ULTRALEAP_LEAPC_INCLUDE_DIR AND ULTRALEAP_LEAPC_LIBRARY)
    set(ULTRALEAP_LEAPC_FOUND TRUE)
    message(STATUS "LeapC: header ${ULTRALEAP_LEAPC_INCLUDE_DIR}/LeapC.h")
    message(STATUS "LeapC: library ${ULTRALEAP_LEAPC_LIBRARY}")
    if(WIN32)
        get_filename_component(_leapc_libdir "${ULTRALEAP_LEAPC_LIBRARY}" DIRECTORY)
        find_file(ULTRALEAP_LEAPC_RUNTIME_DLL LeapC.dll HINTS "${_leapc_libdir}" NO_DEFAULT_PATH)
        if(NOT ULTRALEAP_LEAPC_RUNTIME_DLL)
            set(ULTRALEAP_LEAPC_RUNTIME_DLL "")
        endif()
    endif()
endif()
