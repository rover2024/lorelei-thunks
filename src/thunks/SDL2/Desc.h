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

    // SDL_LogMessage and the other variadic SDL_Log* helpers carry a printf format attribute
    // (SDL_PRINTF_VARARG_FUNC), so the builder recognises them automatically with no descriptor.
    //
    // SDL_LogMessageV is the va_list form. A va_list function carries no format attribute and its
    // name does not end in "printf", so it cannot be detected automatically and must be tagged by
    // hand with the vprintf builder.
    template <>
    struct ProcFnDesc<::SDL_LogMessageV> {
        _DESC pass::vprintf<> builder_pass = {};
    };

}
