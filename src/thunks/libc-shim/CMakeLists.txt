# A partial libc thunk: it forwards a hand-picked subset of libc symbols (for now the allocator
# family) to the host libc, so memory a host-side thunked library allocates and the guest later frees
# share one allocator instead of crossing between the guest and host heaps.
#
# Unlike a normal thunk, this one is meant to be loaded with LD_PRELOAD ahead of the real libc, NOT by
# soname resolution. project(c-shim) builds it as libc-shim.so (the thunk's OUTPUT_NAME is the project
# name); the "c-shim" name deliberately avoids colliding with libc.so* so it can sit in LD_PRELOAD.
project(c-shim)

# Configure thunks
include("../AddThunk.cmake")

# Large-file programs (bzip2, ...) call the *64 stdio symbols (fopen64, freopen64, fseeko64, ...).
# Those are declared only under _GNU_SOURCE / _LARGEFILE64_SOURCE, which must be set before any header
# is seen. Desc.h cannot do it (the generated TU pulls in other headers before Desc.h), so define it
# on the command line for both the TLC parse (ALL_EXTRA_ARGS) and the compile (GTL/HTL options).
set(ALL_EXTRA_ARGS -D_GNU_SOURCE)
set(GTL_EXTRA_OPTIONS -D_GNU_SOURCE)
set(HTL_EXTRA_OPTIONS -D_GNU_SOURCE)

add_thunk()
