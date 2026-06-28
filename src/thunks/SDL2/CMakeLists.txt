project(SDL2)

# SDL2 headers, used to parse Desc.h and compile the generated thunk. Point THUNK_SDL2_INCLUDE_DIR
# at a specific SDL2 (e.g. the patched host SDL's install include) to override; otherwise the
# system headers (which already resolve <SDL2/SDL.h>) are used.
include("../AddThunk.cmake")

set(ALL_EXTRA_INCLUDES ${THUNK_SDL2_INCLUDE_DIR})

# The guest thunk stands in for the real libSDL2; ship its sonames as aliases.
set(GTL_ALIAS libSDL2-2.0.so libSDL2-2.0.so.0)

# SDL_LoadObject/Function are reimplemented on the guest with dlopen/dlsym (see Manifest_guest.cpp).
set(GTL_EXTRA_LINKS dl)

# SDL2 2.26 headers still reference a few deprecated symbols.
set(GTL_EXTRA_OPTIONS -Wno-deprecated-declarations)
set(HTL_EXTRA_OPTIONS -Wno-deprecated-declarations)

add_thunk()
