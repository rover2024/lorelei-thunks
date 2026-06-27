# Build helpers for Lorelei thunk libraries.
#
# A thunk is compiled in two stages by the Lorelei Thunk Library Compiler (LoreTLC,
# provided by the installed `lorelei` package):
#
# 1. stat     Desc.h + Symbols.conf      -> ThunkStat.json
# 2. generate Manifest_{guest,host}.cpp  -> Thunk_{guest,host}.cpp
#
# The generated source is then built into a shared library (the GTL/HTL). These libraries
# are plugins loaded into the guest/host runtime, so they are intentionally linked WITHOUT
# `-z,defs`: DLCall symbols (VariadicAdaptor, ffcall, ...) are resolved by the loading
# process at runtime.

# ----------------------------------
# Architecture / fixed-register selection
# ----------------------------------
# Guest architecture: x86_64
set(THUNK_GUEST_ARCH "x86_64")
set(THUNK_GUEST_TRIPLET "x86_64-pc-linux-gnu")
set(THUNK_GUEST_FIXED_REGISTER "r11")

execute_process(
    COMMAND ${CMAKE_C_COMPILER} -dumpmachine
    OUTPUT_VARIABLE _target_triplet
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
string(REGEX MATCH "^[^-]+" _target_arch "${_target_triplet}")

if(NOT THUNK_HOST_ARCH)
    if(_target_arch MATCHES "x86_64|amd64")
        set(THUNK_HOST_ARCH "x86_64")
        set(THUNK_HOST_FIXED_REGISTER "r11")
    elseif(_target_arch MATCHES "aarch64|arm64")
        set(THUNK_HOST_ARCH "aarch64")
        set(THUNK_HOST_FIXED_REGISTER "x16")
    elseif(_target_arch MATCHES "riscv64")
        set(THUNK_HOST_ARCH "riscv64")
        set(THUNK_HOST_FIXED_REGISTER "t1")
    else()
        message(FATAL_ERROR "lorelei-thunks: unsupported host architecture '${_target_arch}'")
    endif()
endif()

# The lorelei install include directory (carries ThunkInterface/, DLCall/, ...) comes from the
# imported `lorelei` package and is reused by every compile. Take it from LoreSupport: it is the base
# library every side depends on, so it is present whichever lorelei install (host or x86_64) is used.
get_target_property(LORE_INSTALL_INCLUDE_DIR lorelei::LoreSupport INTERFACE_INCLUDE_DIRECTORIES)

# The TLC executable is only needed when this build generates sources. A guest build pointed at
# pre-generated sources (THUNK_GEN_SOURCE_DIR) finds them via the x86_64 lorelei package, which ships
# no runnable TLC, so only resolve the compiler when we are actually going to run it.
if(NOT THUNK_GEN_SOURCE_DIR_USER_DEFINED)
    get_target_property(THUNK_TLC_EXECUTABLE lorelei::LoreTLC LOCATION)
endif()

# ----------------------------------
# TLC custom commands
# ----------------------------------

# thunk_tlc_stat(<name> <desc> <config> <out> [EXTRA_INCLUDES...] [EXTRA_ARGS...])
function(thunk_tlc_stat _name _desc _config _out)
    set(options)
    set(oneValueArgs)
    set(multiValueArgs EXTRA_INCLUDES EXTRA_ARGS)
    cmake_parse_arguments(FUNC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(_includes -I${LORE_INSTALL_INCLUDE_DIR})

    foreach(_inc IN LISTS FUNC_EXTRA_INCLUDES)
        list(APPEND _includes -I${_inc})
    endforeach()

    get_filename_component(_dir ${_out} DIRECTORY)
    file(MAKE_DIRECTORY ${_dir})

    add_custom_command(OUTPUT ${_out}
        COMMAND ${THUNK_TLC_EXECUTABLE} stat -o ${_out} -c ${_config} ${_desc}
        -- -xc++ ${_includes} ${FUNC_EXTRA_ARGS}
        DEPENDS ${_desc} ${_config} ${THUNK_TLC_EXECUTABLE}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        COMMENT "TLC stat ${_name}"
        VERBATIM
    )
endfunction()

# thunk_tlc_generate(<name> <manifest> <out> <stat> <guest|host>
# [PLUGINS...] [EXTRA_INCLUDES...] [EXTRA_ARGS...])
function(thunk_tlc_generate _name _manifest _out _stat _mode)
    set(options)
    set(oneValueArgs)
    set(multiValueArgs PLUGINS EXTRA_INCLUDES EXTRA_ARGS)
    cmake_parse_arguments(FUNC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(_target_opt)

    if(_mode STREQUAL "guest")
        set(_target_opt -target ${THUNK_GUEST_TRIPLET})
    endif()

    # Load each Clang pass plugin via the frontend so the generate run can apply it.
    set(_plugin_opts)

    foreach(_plugin IN LISTS FUNC_PLUGINS)
        list(APPEND _plugin_opts -Xclang -load -Xclang ${_plugin})
    endforeach()

    set(_includes -I${LORE_INSTALL_INCLUDE_DIR} -I${CMAKE_CURRENT_SOURCE_DIR})

    foreach(_inc IN LISTS FUNC_EXTRA_INCLUDES)
        list(APPEND _includes -I${_inc})
    endforeach()

    get_filename_component(_dir ${_out} DIRECTORY)
    file(MAKE_DIRECTORY ${_dir})

    add_custom_command(OUTPUT ${_out}
        COMMAND ${THUNK_TLC_EXECUTABLE} generate -o ${_out} -s ${_stat} -m ${_mode} ${_manifest}
        -- -xc++ ${_plugin_opts} ${_target_opt} ${_includes} ${FUNC_EXTRA_ARGS}
        DEPENDS ${_manifest} ${_stat} ${THUNK_TLC_EXECUTABLE} ${FUNC_PLUGINS}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        COMMENT "TLC generate ${_mode} ${_name}"
        VERBATIM
    )
endfunction()

# thunk_default_install_rpath(<out-var> <lib-subdir>)
#
# Compute the lorelei-style install RPATH for a library installed at <prefix>/<libdir>/<subdir>:
# $ORIGIN (its own dir) plus the install lib root, reached as <hops-up-to-prefix>/<libdir> so the
# final component is always the real lib dir (robust to a custom/multiarch CMAKE_INSTALL_LIBDIR).
# <subdir> may be empty and may contain "..": the location is normalized before counting hops.
function(thunk_default_install_rpath _out _subdir)
    set(_loc lib)
    if(_subdir)
        set(_loc lib/${_subdir})
    endif()

    # Normalize (resolve "." / "..") by anchoring at a fake root, then strip it back off.
    get_filename_component(_loc "/${_loc}" ABSOLUTE)
    file(RELATIVE_PATH _loc "/" "${_loc}")

    # One ".." per surviving path component takes us from the library back up to the prefix.
    string(REGEX REPLACE "[^/]+" ".." _up "${_loc}")

    set(${_out} "\$ORIGIN:\$ORIGIN/${_up}/lib" PARENT_SCOPE)
endfunction()

# Common settings for both the guest (GTL) and host (HTL) thunk libraries.
function(thunk_configure_target _target _fixed_register)
    set_target_properties(${_target} PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        CXX_STANDARD 20
        CXX_STANDARD_REQUIRED ON
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
    )

    # The fixed register is reserved for the thunk calling convention; both sides must
    # keep the compiler off it.
    target_compile_options(${_target} PRIVATE -fno-exceptions -fno-rtti "-ffixed-${_fixed_register}")
    target_include_directories(${_target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
endfunction()

# thunk_make_alias(<target> <outdir> <alias>...)
#
# Create one or more `<alias>` symlinks next to the built thunk (e.g. libz.so.1 -> libz.so),
# both in the build tree and on install. Several aliases may be given (the guest SDL2 thunk,
# for instance, needs both libSDL2-2.0.so and libSDL2-2.0.so.0).
function(thunk_make_alias _target _outdir)
    foreach(_alias IN LISTS ARGN)
        add_custom_command(TARGET ${_target} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E create_symlink $<TARGET_FILE_NAME:${_target}> ${_alias}
            WORKING_DIRECTORY $<TARGET_FILE_DIR:${_target}>
            VERBATIM
        )

        if(THUNK_INSTALL)
            install(CODE "
                execute_process(COMMAND \${CMAKE_COMMAND} -E create_symlink
                    \"$<TARGET_FILE_NAME:${_target}>\" \"${_alias}\"
                    WORKING_DIRECTORY \${CMAKE_INSTALL_PREFIX}/${_outdir})")
        endif()
    endforeach()
endfunction()

# ----------------------------------
# General support libraries
# ----------------------------------

# thunk_add_library(<target> [LIBRARY_DIRECTORY <lib-subdir>] <qm_configure_target args...>)
#
# Build a regular shared library (e.g. a host middleware lib). Everything except LIBRARY_DIRECTORY
# is forwarded verbatim to qm_configure_target (SOURCES/LINKS/INCLUDE/FEATURES/CCFLAGS/...); this
# wrapper only adds what qm_configure_target does not: shared-library defaults (PIC, hidden
# visibility, C++20, no exceptions/rtti), the public include interface, the output/install
# location, and install into the lorethunkTargets export set. Public headers are installed
# wholesale from include/ by the root CMakeLists.
#
# LIBRARY_DIRECTORY places the binary under <lib>/<lib-subdir> in both the build tree and on
# install (host middleware passes ${THUNK_HOST_ARCH}-LoreHTL so it sits next to the host thunks).
function(thunk_add_library _target)
    set(options)
    set(oneValueArgs LIBRARY_DIRECTORY)
    set(multiValueArgs)
    cmake_parse_arguments(FUNC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(_out_libdir ${QMSETUP_BUILD_DIR}/lib)
    set(_install_libdir lib)
    if(FUNC_LIBRARY_DIRECTORY)
        set(_out_libdir ${_out_libdir}/${FUNC_LIBRARY_DIRECTORY})
        set(_install_libdir ${_install_libdir}/${FUNC_LIBRARY_DIRECTORY})
    endif()
    thunk_default_install_rpath(_rpath "${FUNC_LIBRARY_DIRECTORY}")

    add_library(${_target} SHARED)

    # Forward the caller's qm_configure_target arguments untouched.
    qm_configure_target(${_target} ${FUNC_UNPARSED_ARGUMENTS})

    # The rest, which qm_configure_target does not handle, set directly.
    set_target_properties(${_target} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY ${_out_libdir}
        INSTALL_RPATH "${_rpath}"
    )
    target_compile_features(${_target} PRIVATE cxx_std_20)
    target_include_directories(${_target} PUBLIC
        $<BUILD_INTERFACE:${THUNK_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    )

    if(THUNK_INSTALL)
        install(TARGETS ${_target}
            EXPORT lorethunkTargets
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            LIBRARY DESTINATION ${_install_libdir}
            ARCHIVE DESTINATION ${_install_libdir}
        )
        set_property(GLOBAL PROPERTY THUNK_HAS_EXPORTS TRUE)
    endif()
endfunction()

# thunk_generate_global_header(<target> <include-rel> [PREFIX <prefix>])
#
# Opt-in helper for libraries that would rather have their export macro generated than hand-write
# it. Sets -D<PREFIX>_LIBRARY (via qm_export_defines) and emits a matching <include-rel>/Global.h
# defining <PREFIX>_EXPORT (default visibility while the library is built, nothing for consumers).
# <PREFIX> defaults to the upper-cased target name. qmsetup has no header generator of its own,
# the same reason lorelei hand-rolls lore_generate_global_header.
function(thunk_generate_global_header _target _rel)
    set(options)
    set(oneValueArgs PREFIX)
    set(multiValueArgs)
    cmake_parse_arguments(FUNC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(FUNC_PREFIX)
        set(_prefix ${FUNC_PREFIX})
    else()
        string(TOUPPER ${_target} _prefix)
    endif()

    string(MAKE_C_IDENTIFIER ${_prefix} _prefix)

    qm_export_defines(${_target} PREFIX ${_prefix})

    set(_content "#pragma once

#ifdef ${_prefix}_LIBRARY
#  define ${_prefix}_EXPORT __attribute__((visibility(\"default\")))
#else
#  define ${_prefix}_EXPORT
#endif
")
    set(_out_dir ${QMSETUP_BUILD_DIR}/include/${_rel})
    set(_out_file ${_out_dir}/Global.h)

    if(NOT EXISTS ${_out_file})
        file(MAKE_DIRECTORY ${_out_dir})
        file(WRITE ${_out_file} "${_content}")
    endif()

    target_include_directories(${_target} PUBLIC $<BUILD_INTERFACE:${QMSETUP_BUILD_DIR}/include>)

    if(THUNK_INSTALL)
        install(FILES ${_out_file} DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${_rel})
    endif()
endfunction()
