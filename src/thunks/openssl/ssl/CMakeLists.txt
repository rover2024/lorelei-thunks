project(ssl)

include("../../AddThunk.cmake")

set(GTL_ALIAS libssl.so.3)
set(HTL_EXTRA_LINKS ssl)

add_thunk()
