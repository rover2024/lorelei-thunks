# Each entry is a subdirectory holding one or more thunk libraries, grouped by maturity. zlib and lzma
# are stable; the rest are work in progress (see THUNK_BUILD_EXPERIMENTAL_LIBRARIES in the root CMakeLists for
# the selection rules). Selection per thunk, in the loop below: an explicit THUNK_ENABLE_LIBRARIES
# allowlist wins; otherwise stable always builds, experimental builds only when opted in, and the
# THUNK_DISABLE_LIBRARIES denylist removes individual ones.
#
# Shared guest-side thunk utility headers (lorethunk/ThunkUtils/Guest/...) live under the repo's
# include/ tree; put it on every thunk's include path, for both the TLC parse and the compile.
list(APPEND THUNK_ALL_EXTRA_INCLUDES ${CMAKE_SOURCE_DIR}/include)

set(_thunks_stable
    zlib
    lzma
)
set(_thunks_experimental
    SDL2
    libc-shim
    bzip2
    openssl
)

foreach(_thunk IN LISTS _thunks_stable _thunks_experimental)
    if(THUNK_ENABLE_LIBRARIES)
        if(NOT _thunk IN_LIST THUNK_ENABLE_LIBRARIES)
            continue()
        endif()
    else()
        if(_thunk IN_LIST _thunks_experimental AND NOT THUNK_BUILD_EXPERIMENTAL_LIBRARIES)
            message(STATUS "lorethunk: skipping experimental thunk (set THUNK_BUILD_EXPERIMENTAL_LIBRARIES=ON to build): ${_thunk}")
            continue()
        endif()

        if(_thunk IN_LIST THUNK_DISABLE_LIBRARIES)
            message(STATUS "lorethunk: skipping disabled thunk library: ${_thunk}")
            continue()
        endif()
    endif()

    add_subdirectory(${_thunk})
endforeach()
