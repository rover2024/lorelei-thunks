add_subdirectory(Midware)

# Host-side implementation backing the ThunkExample example thunk.
if(THUNK_BUILD_HOST_TARGETS)
    add_subdirectory(ThunkExample)
endif()
