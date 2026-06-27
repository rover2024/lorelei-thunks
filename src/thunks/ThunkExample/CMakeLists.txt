project(ThunkExample)

include("../AddThunk.cmake")

# Desc.h includes <lorethunk/ThunkExample/ThunkExample.h>, so put lorethunk's own headers on the
# TLC and compile path.
set(ALL_extra_includes ${THUNK_SOURCE_DIR}/include)

set(GTL_alias libThunkExample.so.0)

# Manifest_host.cpp uses LORE_THUNK_AUTO_LINK, so the HTL links the example host library (le_*);
# the libc routines they forward to come in with it.
set(HTL_extra_links ThunkExample)

add_thunk()
