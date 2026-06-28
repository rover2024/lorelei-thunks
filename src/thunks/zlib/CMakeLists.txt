project(z)

# Configure thunks
include("../AddThunk.cmake")

set(GTL_ALIAS libz.so.1)
set(ALL_EXTRA_INCLUDES ${ZLIB_INCLUDE_DIRS})

# Manifest_host.cpp uses LORE_THUNK_AUTO_LINK.
set(HTL_EXTRA_LINKS z)

add_thunk()
