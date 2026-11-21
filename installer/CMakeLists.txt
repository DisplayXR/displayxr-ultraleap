# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: Apache-2.0
#
# NSIS installer for the Ultraleap input provider (Windows). Installs the DLL,
# registers it under HKLM\Software\DisplayXR\InputProviders\ultraleap, and
# writes the provenance allowlist row for the exact DLL it packs.

if(NOT WIN32)
    return()
endif()

find_program(NSIS_EXECUTABLE makensis
    PATHS
        "$ENV{PROGRAMFILES}/NSIS"
        "$ENV{PROGRAMFILES\(X86\)}/NSIS"
        "C:/Program Files/NSIS"
        "C:/Program Files (x86)/NSIS"
)
if(NOT NSIS_EXECUTABLE)
    message(WARNING "NSIS not found - the 'installer' target is not available. "
                    "Install NSIS (https://nsis.sourceforge.io) to build the provider installer.")
    return()
endif()
message(STATUS "Found NSIS: ${NSIS_EXECUTABLE}")

set(UL_BIN_DIR "${CMAKE_INSTALL_PREFIX}/bin")
set(UL_ALLOWLIST_NSH "${CMAKE_CURRENT_BINARY_DIR}/Allowlist.nsh")
file(TO_NATIVE_PATH "${UL_ALLOWLIST_NSH}" UL_ALLOWLIST_NSH_NATIVE)

# Code-signing command from the SIGN_CMD environment variable (empty = unsigned).
# This is the runtime's convention: CI is unsigned; a signing provider rebuilds
# the tag on its own runner with a runner-local SIGN_CMD (docs/packaging.md).
# The DLL is signed BEFORE the allowlist digest is taken, so the row matches
# the bytes that are packed.
set(SIGN_CMD "$ENV{SIGN_CMD}" CACHE STRING "Code-signing command (empty = unsigned)")

set(_ul_bundle_define "")
if(ULTRALEAP_BUNDLE_LEAPC)
    set(_ul_bundle_define "/DBUNDLE_LEAPC=1")
endif()

set(_ul_sign_step "")
if(SIGN_CMD)
    separate_arguments(_ul_sign_argv NATIVE_COMMAND "${SIGN_CMD}")
    set(_ul_sign_step COMMAND ${_ul_sign_argv} "${UL_BIN_DIR}/plugins/DisplayXR-Ultraleap.dll")
endif()

add_custom_target(installer
    # 0. Sign the provider DLL in the install tree (only when SIGN_CMD is set).
    ${_ul_sign_step}
    # 1. Digest of exactly the DLL that gets packed -> Allowlist.nsh.
    COMMAND "${CMAKE_COMMAND}"
        "-DDLL=${UL_BIN_DIR}/plugins/DisplayXR-Ultraleap.dll"
        "-DVERSION=${PROJECT_VERSION}"
        "-DOUT=${UL_ALLOWLIST_NSH}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/gen_allowlist_nsh.cmake"
    # 2. The installer itself.
    COMMAND "${NSIS_EXECUTABLE}"
        "/DVERSION=${PROJECT_VERSION}"
        "/DVERSION_MAJOR=${PROJECT_VERSION_MAJOR}"
        "/DVERSION_MINOR=${PROJECT_VERSION_MINOR}"
        "/DVERSION_PATCH=${PROJECT_VERSION_PATCH}"
        "/DBUILD_NUM=${BUILD_NUM}"
        "/DRUNTIME_PIN=${DXR_RUNTIME_PIN_VERSION}"
        "/DBIN_DIR=${UL_BIN_DIR}"
        "/DSOURCE_DIR=${PROJECT_SOURCE_DIR}"
        "/DOUTPUT_DIR=${CMAKE_INSTALL_PREFIX}"
        "/DALLOWLIST_NSH=${UL_ALLOWLIST_NSH_NATIVE}"
        "/DSIGN_CMD=${SIGN_CMD}"
        ${_ul_bundle_define}
        "${CMAKE_CURRENT_SOURCE_DIR}/DisplayXRUltraleapInstaller.nsi"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Building the DisplayXR Ultraleap installer..."
    VERBATIM
)
add_dependencies(installer displayxr_ultraleap)
