# Per-thunk build entry. A thunk's CMakeLists.txt is expected to:
#
#   project(<libname>)                  # e.g. project(z) -> libz
#   include("../AddThunk.cmake")
#   set(GTL_ALIAS libz.so.1)            # optional, guest-side soname symlink
#   set(ALL_EXTRA_INCLUDES ...)         # optional, extra include dirs for TLC + targets
#   add_thunk()
#
# It produces:
#   <name>_HTL   host thunk  (when THUNK_BUILD_HOST_TARGETS is ON)
#   <name>_GTL   guest thunk (when THUNK_BUILD_GUEST_TARGETS is ON)
#
# Optional convention variables (all empty by default), set in the thunk's CMakeLists.txt. The ALL_*
# variants apply everywhere; the STAT_* / GTL_* / HTL_* variants are scoped to the stat /
# guest-generate / host-generate steps respectively. Each one has a global THUNK_<NAME> counterpart
# (settable from outside with -D, not reset per thunk) that is merged in ahead of the per-thunk value;
# the global STAT_/GTL_ args are how a cross host points the x86_64 TLC parse at its own toolchain.
#
# Extra compiler args passed to the TLC stat / generate invocations (after `--`):
#   ALL_EXTRA_ARGS    / THUNK_ALL_EXTRA_ARGS
#   STAT_EXTRA_ARGS   / THUNK_STAT_EXTRA_ARGS
#   GTL_EXTRA_ARGS    / THUNK_GTL_EXTRA_ARGS
#   HTL_EXTRA_ARGS    / THUNK_HTL_EXTRA_ARGS
#
# Extra include dirs; passed to TLC and (for the ALL/GTL/HTL ones) added to the built target:
#   ALL_EXTRA_INCLUDES  / THUNK_ALL_EXTRA_INCLUDES
#   STAT_EXTRA_INCLUDES / THUNK_STAT_EXTRA_INCLUDES
#   GTL_EXTRA_INCLUDES  / THUNK_GTL_EXTRA_INCLUDES
#   HTL_EXTRA_INCLUDES  / THUNK_HTL_EXTRA_INCLUDES
#
# Extra link libraries:
#   GTL_EXTRA_LINKS / THUNK_GTL_EXTRA_LINKS
#   HTL_EXTRA_LINKS / THUNK_HTL_EXTRA_LINKS
#
# Extra compile options:
#   GTL_EXTRA_OPTIONS / THUNK_GTL_EXTRA_OPTIONS
#   HTL_EXTRA_OPTIONS / THUNK_HTL_EXTRA_OPTIONS
#
# Libraries force-linked (-Wl,--no-as-needed):
#   GTL_FORCE_LINKS / THUNK_GTL_FORCE_LINKS
#   HTL_FORCE_LINKS / THUNK_HTL_FORCE_LINKS
#
# Soname symlink(s), e.g. libz.so.1 (per-thunk only):
#   GTL_ALIAS
#   HTL_ALIAS
#
# A Clang pass-plugin target to load into generate (per-thunk only):
#   PLUGIN_TARGET

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

# Per-thunk convention variables (reset per thunk; add_subdirectory gives each its own scope). The
# THUNK_* globals are intentionally not reset, so an outer -D persists across every thunk.
set(ALL_EXTRA_ARGS)
set(STAT_EXTRA_ARGS)
set(GTL_EXTRA_ARGS)
set(HTL_EXTRA_ARGS)
set(ALL_EXTRA_INCLUDES)
set(STAT_EXTRA_INCLUDES)
set(GTL_EXTRA_INCLUDES)
set(HTL_EXTRA_INCLUDES)
set(GTL_EXTRA_LINKS)
set(HTL_EXTRA_LINKS)
set(GTL_EXTRA_OPTIONS)
set(HTL_EXTRA_OPTIONS)
set(GTL_FORCE_LINKS)
set(HTL_FORCE_LINKS)
set(GTL_ALIAS)
set(HTL_ALIAS)
set(PLUGIN_TARGET)

macro(add_thunk)
    set(_plugin_opts)
    if(PLUGIN_TARGET)
        set(_plugin_opts PLUGINS $<TARGET_FILE:${PLUGIN_TARGET}>)
    endif()

    # Effective args/includes per step: global THUNK_* first, then the per-thunk value.
    set(_stat_args ${THUNK_ALL_EXTRA_ARGS} ${ALL_EXTRA_ARGS} ${THUNK_STAT_EXTRA_ARGS} ${STAT_EXTRA_ARGS})
    set(_htl_args  ${THUNK_ALL_EXTRA_ARGS} ${ALL_EXTRA_ARGS} ${THUNK_HTL_EXTRA_ARGS} ${HTL_EXTRA_ARGS})
    set(_gtl_args  ${THUNK_ALL_EXTRA_ARGS} ${ALL_EXTRA_ARGS} ${THUNK_GTL_EXTRA_ARGS} ${GTL_EXTRA_ARGS})
    set(_stat_incs ${THUNK_ALL_EXTRA_INCLUDES} ${ALL_EXTRA_INCLUDES} ${THUNK_STAT_EXTRA_INCLUDES} ${STAT_EXTRA_INCLUDES})
    set(_htl_incs  ${THUNK_ALL_EXTRA_INCLUDES} ${ALL_EXTRA_INCLUDES} ${THUNK_HTL_EXTRA_INCLUDES} ${HTL_EXTRA_INCLUDES})
    set(_gtl_incs  ${THUNK_ALL_EXTRA_INCLUDES} ${ALL_EXTRA_INCLUDES} ${THUNK_GTL_EXTRA_INCLUDES} ${GTL_EXTRA_INCLUDES})

    # --- stat -------------------------------------------------------------
    # stat only feeds generate, so skip it when the caller supplied a pre-generated ThunkStat.json
    # or pre-generated sources (generate is skipped too); otherwise produce it.
    if(NOT THUNK_DATA_DIR_USER_DEFINED AND NOT THUNK_GEN_SOURCE_DIR_USER_DEFINED)
        thunk_tlc_stat(${PROJECT_NAME} ${_desc_file} ${_symbols_config} ${_stat_file}
            EXTRA_INCLUDES ${_stat_incs}
            EXTRA_ARGS ${_stat_args}
        )
    endif()

    # --- generate ---------------------------------------------------------
    # Generation is independent of which library this build compiles. Both the host and guest sources
    # are produced here (unless the caller supplied pre-generated ones); THUNK_BUILD_*_TARGETS only
    # selects which library is then built. So a host-only (cross) build still emits the guest source
    # too: the native host TLC cross-targets x86_64 for it, and a following guest build compiles it
    # straight from THUNK_GEN_SOURCE_DIR without a runnable TLC of its own.
    if(NOT THUNK_GEN_SOURCE_DIR_USER_DEFINED)
        thunk_tlc_generate(${HTL} ${_manifest_host_file} ${HTL_src} ${_stat_file} host
            ${_plugin_opts}
            EXTRA_INCLUDES ${_htl_incs}
            EXTRA_ARGS ${_htl_args}
        )
        thunk_tlc_generate(${GTL} ${_manifest_guest_file} ${GTL_src} ${_stat_file} guest
            ${_plugin_opts}
            EXTRA_INCLUDES ${_gtl_incs}
            EXTRA_ARGS ${_gtl_args}
        )
        # A library whose side is disabled does not consume its source, so force both to be produced
        # (and thus installed) with an always-built target.
        add_custom_target(${PROJECT_NAME}_gen ALL DEPENDS ${HTL_src} ${GTL_src})
    endif()

    # --- host thunk -------------------------------------------------------
    if(THUNK_BUILD_HOST_TARGETS)
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

        if(_htl_incs)
            target_include_directories(${HTL} PRIVATE ${_htl_incs})
        endif()
        set(_htl_links ${THUNK_HTL_EXTRA_LINKS} ${HTL_EXTRA_LINKS})
        if(_htl_links)
            target_link_libraries(${HTL} PRIVATE ${_htl_links})
        endif()
        set(_htl_opts ${THUNK_HTL_EXTRA_OPTIONS} ${HTL_EXTRA_OPTIONS})
        if(_htl_opts)
            target_compile_options(${HTL} PRIVATE ${_htl_opts})
        endif()
        set(_htl_force ${THUNK_HTL_FORCE_LINKS} ${HTL_FORCE_LINKS})
        if(_htl_force)
            target_link_options(${HTL} PRIVATE -Wl,--no-as-needed)
            target_link_libraries(${HTL} PRIVATE ${_htl_force})
        endif()

        if(THUNK_INSTALL)
            install(TARGETS ${HTL}
                LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/${THUNK_HOST_ARCH}-LoreHTL
            )
        endif()

        if(HTL_ALIAS)
            thunk_make_alias(${HTL} ${CMAKE_INSTALL_LIBDIR}/${THUNK_HOST_ARCH}-LoreHTL ${HTL_ALIAS})
        endif()
    endif()

    # --- guest thunk ------------------------------------------------------
    if(THUNK_BUILD_GUEST_TARGETS)
        add_library(${GTL} SHARED ${GTL_src})
        thunk_default_install_rpath(_gtl_rpath ${THUNK_GUEST_ARCH}-LoreGTL)
        set_target_properties(${GTL} PROPERTIES
            OUTPUT_NAME ${PROJECT_NAME}
            LIBRARY_OUTPUT_DIRECTORY ${QMSETUP_BUILD_DIR}/lib/${THUNK_GUEST_ARCH}-LoreGTL
            INSTALL_RPATH "${_gtl_rpath}"
        )
        thunk_configure_target(${GTL} ${THUNK_GUEST_FIXED_REGISTER})
        target_link_libraries(${GTL} PRIVATE lorelei::LoreGuestRT)

        if(_gtl_incs)
            target_include_directories(${GTL} PRIVATE ${_gtl_incs})
        endif()
        set(_gtl_links ${THUNK_GTL_EXTRA_LINKS} ${GTL_EXTRA_LINKS})
        if(_gtl_links)
            target_link_libraries(${GTL} PRIVATE ${_gtl_links})
        endif()
        set(_gtl_opts ${THUNK_GTL_EXTRA_OPTIONS} ${GTL_EXTRA_OPTIONS})
        if(_gtl_opts)
            target_compile_options(${GTL} PRIVATE ${_gtl_opts})
        endif()
        set(_gtl_force ${THUNK_GTL_FORCE_LINKS} ${GTL_FORCE_LINKS})
        if(_gtl_force)
            target_link_options(${GTL} PRIVATE -Wl,--no-as-needed)
            target_link_libraries(${GTL} PRIVATE ${_gtl_force})
        endif()

        if(THUNK_INSTALL)
            install(TARGETS ${GTL}
                LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/${THUNK_GUEST_ARCH}-LoreGTL
            )
        endif()

        if(GTL_ALIAS)
            thunk_make_alias(${GTL} ${CMAKE_INSTALL_LIBDIR}/${THUNK_GUEST_ARCH}-LoreGTL ${GTL_ALIAS})
        endif()
    endif()
endmacro()
