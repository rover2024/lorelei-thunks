# Each entry is a subdirectory holding one or more thunk libraries. Selection: if
# THUNK_ENABLE_LIBRARIES is set, only the entries it names are built (an allowlist); otherwise every
# entry is built except those in THUNK_DISABLE_LIBRARIES (a denylist). The allowlist is for hosts
# where some thunk cannot build (e.g. SDL2's multiarch headers on a cross arch): name just the ones
# that do.
#
# Shared guest-side thunk utility headers (lorethunk/ThunkUtils/Guest/...) live under the repo's
# include/ tree; put it on every thunk's include path, for both the TLC parse and the compile.
list(APPEND THUNK_ALL_EXTRA_INCLUDES ${CMAKE_SOURCE_DIR}/include)

set(_thunks
    zlib
    lzma
    SDL2
    libc-shim
    bzip2
    openssl
)

foreach(_thunk IN LISTS _thunks)
    if(THUNK_ENABLE_LIBRARIES)
        if(NOT _thunk IN_LIST THUNK_ENABLE_LIBRARIES)
            message(STATUS "lorethunk: skipping thunk library not enabled: ${_thunk}")
            continue()
        endif()
    elseif(_thunk IN_LIST THUNK_DISABLE_LIBRARIES)
        message(STATUS "lorethunk: skipping disabled thunk library: ${_thunk}")
        continue()
    endif()

    add_subdirectory(${_thunk})
endforeach()
