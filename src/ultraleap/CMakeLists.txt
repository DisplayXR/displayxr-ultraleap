# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# The provider binary. Reproduces the trunk linkage of `drv_ultraleap_plugin`
# (displayxr-runtime src/xrt/drivers/CMakeLists.txt) per platform:
#
#   Windows / macOS  XRT_USING_RUNTIME_DLL + the runtime's import library
#                    (one log sink and one u_var registry per process, ADR-019)
#                    + the static aux libs for the non-exported helpers.
#   Linux            self-contained: static aux libs only; the version script
#                    keeps xrtInputPluginNegotiate the single exported symbol.
#
# The target is NOT named drv_ultraleap_plugin: the fetched runtime tree still
# defines that target when it finds a LeapC SDK itself.

add_library(displayxr_ultraleap SHARED
    ultraleap_interface.h
    ultraleap_map.c
    ultraleap_map.h
    ultraleap_plugin.c
    ultraleap_provider.cpp
)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_libraries(displayxr_ultraleap PRIVATE
        xrt-interfaces aux_util aux_os aux_math drv_includes)
else()
    if(NOT RUNTIME_TARGET OR NOT TARGET ${RUNTIME_TARGET})
        message(FATAL_ERROR
            "The runtime tree did not define its runtime library target (RUNTIME_TARGET='${RUNTIME_TARGET}'). "
            "On Windows / macOS the provider links the runtime's import library.")
    endif()
    target_compile_definitions(displayxr_ultraleap PRIVATE XRT_USING_RUNTIME_DLL)
    target_link_libraries(displayxr_ultraleap PRIVATE
        # Generator expression, not the target: linking the target would drag
        # in its PUBLIC interface (every compositor, the state tracker, ...).
        $<TARGET_LINKER_FILE:${RUNTIME_TARGET}>
        xrt-interfaces
        aux_util
        aux_os
        aux_math
        drv_includes
    )
    add_dependencies(displayxr_ultraleap ${RUNTIME_TARGET})
endif()

target_include_directories(displayxr_ultraleap PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${DXR_RUNTIME_ROOT}/src/xrt/auxiliary
)
# SYSTEM: the SDK header is not ours to warn about.
target_include_directories(displayxr_ultraleap SYSTEM PRIVATE ${ULTRALEAP_LEAPC_INCLUDE_DIR})

if(ULTRALEAP_LEAPC_IS_STUB)
    target_link_libraries(displayxr_ultraleap PRIVATE leapc_stub)
    set(_ul_output_name "DisplayXR-Ultraleap-STUBCHECK")
else()
    target_link_libraries(displayxr_ultraleap PRIVATE ${ULTRALEAP_LEAPC_LIBRARY})
    set(_ul_output_name "DisplayXR-Ultraleap")
endif()

set_target_properties(displayxr_ultraleap PROPERTIES
    OUTPUT_NAME "${_ul_output_name}"
    PREFIX ""
    LINKER_LANGUAGE CXX
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

# One exported symbol.
if(APPLE)
    target_link_options(displayxr_ultraleap PRIVATE
        "LINKER:-exported_symbol,_xrtInputPluginNegotiate")
    # macOS: the provider imports u_log / u_var from @rpath/openxr_displayxr.dylib
    # (two-level namespace), so it must be able to FIND the runtime library when
    # the host has not loaded it already (displayxr-cli has not).
    #   build tree  -> the runtime library's build directory (as the trunk's
    #                  sim_stylus / sim_tracking plug-ins do);
    #   installed   -> @loader_path/../.. : the runtime's own layout, plug-ins in
    #                  <lib>/displayxr/plugins and the runtime library in <lib>.
    # An install OUTSIDE the runtime's prefix needs its own rpath - see
    # docs/packaging.md (macOS is not a shipped platform yet).
    set_property(TARGET displayxr_ultraleap APPEND PROPERTY
        BUILD_RPATH "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>")
    set_property(TARGET displayxr_ultraleap APPEND PROPERTY
        INSTALL_RPATH "@loader_path/../..")
elseif(NOT WIN32)
    target_link_options(displayxr_ultraleap PRIVATE
        "LINKER:--version-script=${CMAKE_CURRENT_SOURCE_DIR}/input_plugin_exports.version"
        "LINKER:--no-undefined")
endif()

message(STATUS "Ultraleap input provider: ENABLED -> ${_ul_output_name} (runtime ${DXR_RUNTIME_GIT_TAG})")

if(ULTRALEAP_LEAPC_IS_STUB)
    # Never installed, never packaged.
    return()
endif()

include(GNUInstallDirs)
if(WIN32)
    install(TARGETS displayxr_ultraleap
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}/plugins
        LIBRARY DESTINATION ${CMAKE_INSTALL_BINDIR}/plugins)

    # LeapC.dll and #933 - see docs/packaging.md for both choices.
    #
    # The LeiaSR Platform puts its own LeapC.dll on the system PATH. The
    # runtime's input loader loads the provider by absolute path with
    # LOAD_WITH_ALTERED_SEARCH_PATH, so a LeapC.dll staged NEXT TO the provider
    # wins the dependency search; without one, the by-name import resolves
    # through the default search order and can bind to a different LeapC.
    if(ULTRALEAP_BUNDLE_LEAPC)
        if(NOT ULTRALEAP_LEAPC_RUNTIME_DLL)
            message(FATAL_ERROR
                "ULTRALEAP_BUNDLE_LEAPC=ON but no LeapC.dll was found next to ${ULTRALEAP_LEAPC_LIBRARY}.")
        endif()
        add_custom_command(TARGET displayxr_ultraleap POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different "${ULTRALEAP_LEAPC_RUNTIME_DLL}"
                "$<TARGET_FILE_DIR:displayxr_ultraleap>/LeapC.dll"
            COMMENT "Staging LeapC.dll app-local next to DisplayXR-Ultraleap (#933)")
        install(FILES "${ULTRALEAP_LEAPC_RUNTIME_DLL}" DESTINATION ${CMAKE_INSTALL_BINDIR}/plugins)
        message(STATUS "LeapC.dll: BUNDLED from ${ULTRALEAP_LEAPC_RUNTIME_DLL} (check the redistribution licence before publishing)")
    else()
        message(STATUS "LeapC.dll: NOT bundled (default). The installed provider resolves LeapC from the "
                       "Ultraleap tracking software; dev builds: scripts\\build-windows.bat stages a local copy.")
    endif()
else()
    install(TARGETS displayxr_ultraleap
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/displayxr/plugins)
endif()
