#define LORE_THUNK_CALLBACK_REPLACE

#include "Desc.h"
#include <lorelei/ThunkInterface/ManifestHost.cpp.inc>

#include <cstdio>
#include <cstdlib>

namespace lore::thunk {

    // A handful of SDL procs carry a function pointer in a position the automatic
    // CallbackSubstituter cannot rewrite (a pointer inside an array, or a pointer to a
    // function pointer), so it emits "unsupported callback type". We supply the Adapt layer
    // by hand for those, which suppresses the generated default Adapt for the proc.

    // SDL_AudioCVT holds its converters in SDL_AudioFilter filters[]. Those entries are SDL's
    // own host-internal converter functions; SDL fills them in SDL_BuildAudioCVT and calls
    // them host-side in SDL_ConvertAudio. The guest never registers or invokes them, and the
    // shared address space makes the host pointers directly callable, so no substitution is
    // needed and the Adapt layer is a plain pass-through to Caller.
    template <>
    struct ProcFn<::SDL_BuildAudioCVT, GuestToHost, Adapt> {
        static int invoke(SDL_AudioCVT *cvt, SDL_AudioFormat src_format, Uint8 src_channels,
                          int src_rate, SDL_AudioFormat dst_format, Uint8 dst_channels,
                          int dst_rate) {
            return ProcFn<::SDL_BuildAudioCVT, GuestToHost, Caller>::invoke(
                cvt, src_format, src_channels, src_rate, dst_format, dst_channels, dst_rate);
        }
    };

    template <>
    struct ProcFn<::SDL_ConvertAudio, GuestToHost, Adapt> {
        static int invoke(SDL_AudioCVT *cvt) {
            return ProcFn<::SDL_ConvertAudio, GuestToHost, Caller>::invoke(cvt);
        }
    };

    // SDL_AudioFilter is the type of those host-internal converters; for the same reason its
    // Adapt layer is a pass-through.
    template <>
    struct ProcCb<::SDL_AudioFilter, GuestToHost, Adapt> {
        static void invoke(void *callback, SDL_AudioCVT *cvt, SDL_AudioFormat format) {
            ProcCb<::SDL_AudioFilter, GuestToHost, Caller>::invoke(callback, cvt, format);
        }
    };

    [[noreturn]] static void sdl2_get_callback_unsupported(const char *fn) {
        std::fprintf(stderr,
                     "lorethunk SDL2: %s returns a host callback pointer through an out "
                     "parameter; retrieving callbacks across the guest/host boundary is not "
                     "supported yet.\n",
                     fn);
        std::abort();
    }

    // The SDL_Get* / SDL_LogGet* queries return a callback into a caller-provided slot (a
    // pointer to a function pointer). Handing the guest a raw host function pointer would need
    // a reverse trampoline; until that is implemented these abort with a clear message rather
    // than silently returning an unusable pointer.
    template <>
    struct ProcFn<::SDL_GetEventFilter, GuestToHost, Adapt> {
        static SDL_bool invoke(SDL_EventFilter *, void **) {
            sdl2_get_callback_unsupported("SDL_GetEventFilter");
        }
    };

    template <>
    struct ProcFn<::SDL_GetMemoryFunctions, GuestToHost, Adapt> {
        static void invoke(SDL_malloc_func *, SDL_calloc_func *, SDL_realloc_func *,
                           SDL_free_func *) {
            sdl2_get_callback_unsupported("SDL_GetMemoryFunctions");
        }
    };

    template <>
    struct ProcFn<::SDL_LogGetOutputFunction, GuestToHost, Adapt> {
        static void invoke(SDL_LogOutputFunction *, void **) {
            sdl2_get_callback_unsupported("SDL_LogGetOutputFunction");
        }
    };

}
