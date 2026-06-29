project(bz2)

# Configure thunks
include("../AddThunk.cmake")

# The bzip2 command-line tool links libbz2.so.1.0; ship that soname as the guest alias.
set(GTL_ALIAS libbz2.so.1.0)

# Manifest_host.cpp uses LORE_THUNK_AUTO_LINK.
set(HTL_EXTRA_LINKS bz2)

add_thunk()
