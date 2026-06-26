#define LORE_THUNK_CALLBACK_REPLACE

#include "Desc.h"
#include <lorelei/ThunkInterface/ManifestGuest.cpp.inc>

#include <dlfcn.h>

namespace lore::thunk {

    // SDL_AudioFilter holds SDL's own host-internal audio converters (see Manifest_host.cpp);
    // they never cross the boundary, so the Adapt layer is a plain pass-through to Caller. The
    // guest TU is the receiver for the HostToGuest direction of this callback.
    template <>
    struct ProcCb<::SDL_AudioFilter, HostToGuest, Adapt> {
        static void invoke(void *callback, SDL_AudioCVT *cvt, SDL_AudioFormat format) {
            ProcCb<::SDL_AudioFilter, HostToGuest, Caller>::invoke(callback, cvt, format);
        }
    };

    // SDL's dynamic-loading API must act on the guest's own loader, not be forwarded to the host:
    // a guest program loading a plugin .so expects a guest-side handle. Resolve these locally.
    template <>
    struct ProcFn<::SDL_LoadObject, GuestToHost, Entry> {
        static void *invoke(const char *sofile) {
            return dlopen(sofile, RTLD_NOW);
        }
    };

    template <>
    struct ProcFn<::SDL_LoadFunction, GuestToHost, Entry> {
        static void *invoke(void *handle, const char *name) {
            return dlsym(handle, name);
        }
    };

    template <>
    struct ProcFn<::SDL_UnloadObject, GuestToHost, Entry> {
        static int invoke(void *handle) {
            return dlclose(handle);
        }
    };

}
