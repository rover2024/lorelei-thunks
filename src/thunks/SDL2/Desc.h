#pragma once

#include <SDL2/SDL.h>
#include <SDL2/SDL_syswm.h>

#include <lorelei/ThunkInterface/Proc.h>
#include <lorelei/ThunkInterface/PassTags.h>

// Xlib (pulled in transitively by SDL_syswm.h) defines Success as a macro.
#ifdef Success
#  undef Success
#endif

namespace lore::thunk {

    // SDL_LogMessageV takes a printf-style format + va_list, so the builder marshals its variadic
    // arguments via the printf pass.
    template <>
    struct ProcFnDesc<::SDL_LogMessageV> {
        _DESC pass::printf<> builder_pass = {};
    };

}
