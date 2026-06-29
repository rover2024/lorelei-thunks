# Each entry is a subdirectory holding one or more thunk libraries.
# An entry named in THUNK_DISABLE_LIBRARIES is skipped.
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
    if(_thunk IN_LIST THUNK_DISABLE_LIBRARIES)
        message(STATUS "lorethunk: skipping disabled thunk library: ${_thunk}")
        continue()
    endif()

    add_subdirectory(${_thunk})
endforeach()
