# Each entry is a thunk library living in a subdirectory of the same name. A library named
# in THUNK_DISABLE_LIBRARIES is skipped.
set(_thunks
    zlib
    SDL2
)

foreach(_thunk IN LISTS _thunks)
    if(_thunk IN_LIST THUNK_DISABLE_LIBRARIES)
        message(STATUS "lorethunk: skipping disabled thunk library: ${_thunk}")
        continue()
    endif()

    add_subdirectory(${_thunk})
endforeach()
