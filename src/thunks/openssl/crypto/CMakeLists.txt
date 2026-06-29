project(crypto)

include("../../AddThunk.cmake")

set(GTL_ALIAS libcrypto.so.3)
set(HTL_EXTRA_LINKS crypto)

add_thunk()
