project(lzma)

# Configure thunks
include("../AddThunk.cmake")

# The xz command-line tool links liblzma.so.5; ship that soname as the guest alias.
set(GTL_ALIAS liblzma.so.5)

# Manifest_host.cpp uses LORE_THUNK_AUTO_LINK.
set(HTL_EXTRA_LINKS lzma)

add_thunk()
