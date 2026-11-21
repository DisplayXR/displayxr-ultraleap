# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# Hardware-free tests.
#
#   tests_ultraleap_map   the display-plane mapping + settings parse. Pure C,
#                         no LeapC, no device: runs everywhere.
#   leapc_stub            a COMPILE-CHECK stand-in for LeapC, built only with
#                         -DULTRALEAP_USE_LEAPC_STUB=ON (see leapc_stub/LeapC.h).

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

if(ULTRALEAP_USE_LEAPC_STUB)
    add_library(leapc_stub STATIC leapc_stub/leapc_stub.c)
    target_include_directories(leapc_stub PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/leapc_stub")
    set_target_properties(leapc_stub PROPERTIES POSITION_INDEPENDENT_CODE ON)
endif()
