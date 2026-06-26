project(z)

# Configure thunks
include("../AddThunk.cmake")

set(GTL_alias libz.so.1)
set(ALL_extra_includes ${ZLIB_INCLUDE_DIRS})

# Manifest_host.cpp uses LORE_THUNK_AUTO_LINK.
set(HTL_extra_links z)

add_thunk()
