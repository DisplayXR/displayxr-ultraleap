# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# Hardware-free tests.
#
#   tests_ultraleap_map   the display-plane mapping + settings parse. Pure C,
#                         no LeapC, no device: runs everywhere.
#   tests_ultraleap_leapc the run-time LeapC loader, against the stand-in
#                         library below: found / not found / refused.
#   leapc_stub            a stand-in for LeapC (see leapc_stub/LeapC.h): a build
#                         and test aid, never a dependency of a shipped binary.

# Catch2 from the runtime tree (the amalgamated copy the trunk tests use). The
# runtime only defines its own target when BUILD_TESTING is ON, which this
# project forces OFF, so build the two files here.
set(_catch_dir "${DXR_RUNTIME_ROOT}/src/external/Catch2")
if(NOT EXISTS "${_catch_dir}/catch_amalgamated.cpp")
    message(WARNING "Catch2 not found in the runtime tree (${_catch_dir}) - unit tests skipped.")
else()
    add_library(ultraleap_catch2 STATIC "${_catch_dir}/catch_amalgamated.cpp")
    target_include_directories(ultraleap_catch2 SYSTEM PUBLIC "${_catch_dir}")

    add_executable(tests_ultraleap_map
        tests_ultraleap_map.cpp
        "${PROJECT_SOURCE_DIR}/src/ultraleap/ultraleap_map.c"
    )
    target_include_directories(tests_ultraleap_map PRIVATE
        "${PROJECT_SOURCE_DIR}/src/ultraleap"
        "${DXR_RUNTIME_ROOT}/src/xrt/auxiliary"
    )
    # aux_math: the hand-frame re-expression (ul_map_joints_to_hand_frame) is pose math.
    target_link_libraries(tests_ultraleap_map PRIVATE ultraleap_catch2 xrt-interfaces aux_math)
    add_test(NAME tests_ultraleap_map COMMAND tests_ultraleap_map)
endif()

# ---------------------------------------------------------------------------
# The LeapC stand-in, as a SHARED library the run-time loader can open, and a
# library that is NOT it. Always built: they are test fixtures, in-repo, and
# need no SDK.
#   leapc_stub   exports the six LeapC entry points the provider binds, plus
#                the marker symbol that identifies it as the stand-in.
#   not_leapc    a shared library with neither: the loader must refuse it.
# ---------------------------------------------------------------------------
add_library(leapc_stub SHARED leapc_stub/leapc_stub.c)
target_include_directories(leapc_stub PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/leapc_stub")
set_target_properties(leapc_stub PROPERTIES
    OUTPUT_NAME "LeapC"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/leapc_stub_lib"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/leapc_stub_lib"
    WINDOWS_EXPORT_ALL_SYMBOLS ON)
foreach(_cfg IN LISTS CMAKE_CONFIGURATION_TYPES)
    string(TOUPPER "${_cfg}" _CFG)
    set_target_properties(leapc_stub PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY_${_CFG} "${CMAKE_CURRENT_BINARY_DIR}/leapc_stub_lib"
        RUNTIME_OUTPUT_DIRECTORY_${_CFG} "${CMAKE_CURRENT_BINARY_DIR}/leapc_stub_lib")
endforeach()

add_library(not_leapc SHARED leapc_stub/not_leapc.c)
set_target_properties(not_leapc PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)

# The loader, compiled against the stand-in header (so it is in "compile-check"
# mode and will only bind the stand-in), driven through every outcome.
add_executable(tests_ultraleap_leapc
    tests_ultraleap_leapc.c
    "${PROJECT_SOURCE_DIR}/src/ultraleap/ultraleap_leapc.c"
)
target_include_directories(tests_ultraleap_leapc PRIVATE
    "${PROJECT_SOURCE_DIR}/src/ultraleap"
    "${CMAKE_CURRENT_SOURCE_DIR}/leapc_stub")
target_compile_definitions(tests_ultraleap_leapc PRIVATE
    "UL_TEST_STUB_LIB=\"$<TARGET_FILE:leapc_stub>\""
    "UL_TEST_STUB_DIR=\"$<TARGET_FILE_DIR:leapc_stub>\""
    "UL_TEST_NOT_LEAPC_LIB=\"$<TARGET_FILE:not_leapc>\"")
target_link_libraries(tests_ultraleap_leapc PRIVATE ${CMAKE_DL_LIBS})
add_dependencies(tests_ultraleap_leapc leapc_stub not_leapc)
add_test(NAME tests_ultraleap_leapc COMMAND tests_ultraleap_leapc)
