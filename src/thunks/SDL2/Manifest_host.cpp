#define LORE_THUNK_CALLBACK_REPLACE

#include "Desc.h"
#include <lorelei/ThunkInterface/ManifestHost.cpp.inc>

namespace lore::thunk {

    // A couple of SDL procs carry a function pointer in a position the automatic
    // CallbackSubstituter cannot rewrite (a pointer inside an array), so it emits "unsupported
    // callback type". We supply the Adapt layer by hand for those, which suppresses the generated
    // default Adapt for the proc.

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

}
