# Per-thunk build entry. A thunk's CMakeLists.txt is expected to:
#
#   project(<libname>)                  # e.g. project(z) -> libz
#   include("../AddThunk.cmake")
#   set(GTL_alias libz.so.1)            # optional, guest-side soname symlink
#   set(ALL_extra_includes ...)         # optional, extra include dirs for TLC + targets
#   add_thunk()
#
# It produces:
#   <name>_HTL   host thunk  (when THUNK_BUILD_HOST_TARGETS is ON)
#   <name>_GTL   guest thunk (when THUNK_BUILD_GUEST_TARGETS is ON)
#
# Optional convention variables (all empty by default). ALL_* apply everywhere; STAT_*/GTL_*/
# HTL_* are scoped to the stat / guest-generate / host-generate steps respectively:
#   ALL_extra_args     / STAT_extra_args     / GTL_extra_args     / HTL_extra_args
#       extra compiler args passed to the TLC stat / generate invocations (after `--`)
#   ALL_extra_includes / STAT_extra_includes / GTL_extra_includes / HTL_extra_includes
#       extra include dirs; passed to TLC and (for ALL/GTL/HTL) added to the built target
#   GTL_extra_links    / HTL_extra_links       extra link libraries
#   GTL_extra_options  / HTL_extra_options     extra compile options
#   GTL_force_links    / HTL_force_links       libraries force-linked (-Wl,--no-as-needed)
#   GTL_alias          / HTL_alias             soname symlink(s), e.g. libz.so.1
#   PLUGIN_target                              a Clang pass-plugin target to load into generate
#
# Note: a host manifest that defines LORE_THUNK_AUTO_LINK folds the real library's symbol
# addresses (&adler32, ...) straight into the host thunk instead of resolving them via dlsym
# at runtime. Such a manifest must link the real library itself; set HTL_extra_links to it
# (e.g. ZLIB::ZLIB), otherwise the symbols stay undefined and the library is missing from
# DT_NEEDED.
#
# Global (not reset here): THUNK_TLC_EXTRA_ARGS applies to every TLC invocation.

set(GTL ${PROJECT_NAME}_GTL)
set(HTL ${PROJECT_NAME}_HTL)

get_filename_component(_dir_name ${CMAKE_CURRENT_SOURCE_DIR} NAME)
set(_thunk_data_dir ${THUNK_DATA_DIR}/${_dir_name})
set(_thunk_gen_dir ${THUNK_GEN_SOURCE_DIR}/${_dir_name})

set(_desc_file Desc.h)
set(_symbols_config Symbols.conf)
set(_manifest_guest_file Manifest_guest.cpp)
set(_manifest_host_file Manifest_host.cpp)

# stat result lives in the (optionally caller-supplied) data dir; generated thunk sources
# are always regenerated into THUNK_GEN_SOURCE_DIR.
set(_stat_file ${_thunk_data_dir}/ThunkStat.json)
set(GTL_src ${_thunk_gen_dir}/Thunk_guest.cpp)
set(HTL_src ${_thunk_gen_dir}/Thunk_host.cpp)

# Convention variables (reset per thunk; add_subdirectory gives each its own scope).
set(ALL_extra_args)
set(STAT_extra_args)
set(GTL_extra_args)
set(HTL_extra_args)
set(ALL_extra_includes)
set(STAT_extra_includes)
set(GTL_extra_includes)
set(HTL_extra_includes)
set(GTL_extra_links)
set(HTL_extra_links)
set(GTL_extra_options)
set(HTL_extra_options)
set(GTL_force_links)
set(HTL_force_links)
set(GTL_alias)
set(HTL_alias)
set(PLUGIN_target)

macro(add_thunk)
    set(_plugin_opts)
    if(PLUGIN_target)
        set(_plugin_opts PLUGINS $<TARGET_FILE:${PLUGIN_target}>)
    endif()

    # --- stat -------------------------------------------------------------
    # Skip stat when the caller pointed THUNK_DATA_DIR at a pre-generated ThunkStat.json;
    # otherwise produce it (generate consumes it below).
    if(NOT THUNK_DATA_DIR_USER_DEFINED)
        thunk_tlc_stat(${PROJECT_NAME} ${_desc_file} ${_symbols_config} ${_stat_file}
            EXTRA_INCLUDES ${ALL_extra_includes} ${STAT_extra_includes}
            EXTRA_ARGS ${ALL_extra_args} ${STAT_extra_args} ${THUNK_TLC_EXTRA_ARGS}
        )
    endif()

    # --- host thunk -------------------------------------------------------
    if(THUNK_BUILD_HOST_TARGETS)
        thunk_tlc_generate(${HTL} ${_manifest_host_file} ${HTL_src} ${_stat_file} host
            ${_plugin_opts}
            EXTRA_INCLUDES ${ALL_extra_includes} ${HTL_extra_includes}
            EXTRA_ARGS ${ALL_extra_args} ${HTL_extra_args} ${THUNK_TLC_EXTRA_ARGS}
        )

        # The host thunk keeps its _HTL suffix (lib<name>_HTL.so); only the guest thunk takes
        # the bare library name so it can stand in for the real guest library.
        add_library(${HTL} SHARED ${HTL_src})
        thunk_default_install_rpath(_htl_rpath ${THUNK_HOST_ARCH}-LoreHTL)
        set_target_properties(${HTL} PROPERTIES
            LIBRARY_OUTPUT_DIRECTORY ${QMSETUP_BUILD_DIR}/lib/${THUNK_HOST_ARCH}-LoreHTL
            INSTALL_RPATH "${_htl_rpath}"
        )
        thunk_configure_target(${HTL} ${THUNK_HOST_FIXED_REGISTER})
        target_link_libraries(${HTL} PRIVATE lorelei::LoreHostRT)

        if(ALL_extra_includes OR HTL_extra_includes)
            target_include_directories(${HTL} PRIVATE ${ALL_extra_includes} ${HTL_extra_includes})
        endif()
        if(HTL_extra_links)
            target_link_libraries(${HTL} PRIVATE ${HTL_extra_links})
        endif()
        if(HTL_extra_options)
            target_compile_options(${HTL} PRIVATE ${HTL_extra_options})
        endif()
        if(HTL_force_links)
            target_link_options(${HTL} PRIVATE -Wl,--no-as-needed)
            target_link_libraries(${HTL} PRIVATE ${HTL_force_links})
        endif()

        if(THUNK_INSTALL)
            install(TARGETS ${HTL}
                LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/${THUNK_HOST_ARCH}-LoreHTL
            )
        endif()

        if(HTL_alias)
            thunk_make_alias(${HTL} ${CMAKE_INSTALL_LIBDIR}/${THUNK_HOST_ARCH}-LoreHTL ${HTL_alias})
        endif()
    endif()

    # --- guest thunk ------------------------------------------------------
    if(THUNK_BUILD_GUEST_TARGETS)
        thunk_tlc_generate(${GTL} ${_manifest_guest_file} ${GTL_src} ${_stat_file} guest
            ${_plugin_opts}
            EXTRA_INCLUDES ${ALL_extra_includes} ${GTL_extra_includes}
            EXTRA_ARGS ${ALL_extra_args} ${GTL_extra_args} ${THUNK_TLC_EXTRA_ARGS}
        )

        add_library(${GTL} SHARED ${GTL_src})
        thunk_default_install_rpath(_gtl_rpath ${THUNK_GUEST_ARCH}-LoreGTL)
        set_target_properties(${GTL} PROPERTIES
            OUTPUT_NAME ${PROJECT_NAME}
            LIBRARY_OUTPUT_DIRECTORY ${QMSETUP_BUILD_DIR}/lib/${THUNK_GUEST_ARCH}-LoreGTL
            INSTALL_RPATH "${_gtl_rpath}"
        )
        thunk_configure_target(${GTL} ${THUNK_GUEST_FIXED_REGISTER})
        target_link_libraries(${GTL} PRIVATE lorelei::LoreGuestRT)

        if(ALL_extra_includes OR GTL_extra_includes)
            target_include_directories(${GTL} PRIVATE ${ALL_extra_includes} ${GTL_extra_includes})
        endif()
        if(GTL_extra_links)
            target_link_libraries(${GTL} PRIVATE ${GTL_extra_links})
        endif()
        if(GTL_extra_options)
            target_compile_options(${GTL} PRIVATE ${GTL_extra_options})
        endif()
        if(GTL_force_links)
            target_link_options(${GTL} PRIVATE -Wl,--no-as-needed)
            target_link_libraries(${GTL} PRIVATE ${GTL_force_links})
        endif()

        if(THUNK_INSTALL)
            install(TARGETS ${GTL}
                LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/${THUNK_GUEST_ARCH}-LoreGTL
            )
        endif()

        if(GTL_alias)
            thunk_make_alias(${GTL} ${CMAKE_INSTALL_LIBDIR}/${THUNK_GUEST_ARCH}-LoreGTL ${GTL_alias})
        endif()
    endif()
endmacro()
