#define LORE_THUNK_CALLBACK_REPLACE

#include "Desc.h"
#include <lorelei/ThunkInterface/ManifestGuest.cpp.inc>

// Remap the guest std streams to the host's for any libcrypto function that takes a FILE*
// (BIO_new_fp(stdout/stderr), PEM_read(...), ...), so passing one across the boundary is safe.
#include <lorethunk/ThunkUtils/Guest/libc-shim/StdStream.h>

#include <cstdio>
#include <cstdlib>

namespace lore::thunk {

    // OSSL_provider_init_fn's own arguments carry an OSSL_DISPATCH** (a runtime-length function-pointer
    // table), so the substituter cannot marshal the callback and emits "unsupported callback type".
    // It is invoked host-to-guest (the host calls a provider's init the guest registered), so the
    // unsupported proc lands on the guest receiver side; hand its Adapt here so it does not break the
    // build, aborting if a provider is ever actually initialized across the boundary (the CLI's
    // built-in providers are host-internal and never cross). The host-side counterpart, and the
    // TXT_DB procs, are handled in Manifest_host.cpp.
    [[noreturn]] static void crypto_unsupported(const char *fn) {
        std::fprintf(stderr,
                     "lorethunk openssl: %s takes a callback whose shape cannot be marshalled across "
                     "the guest/host boundary yet; refusing to call it.\n",
                     fn);
        std::abort();
    }

    template <>
    struct ProcCb<OSSL_provider_init_fn *, HostToGuest, Adapt> {
        static int invoke(void *, const OSSL_CORE_HANDLE *, const OSSL_DISPATCH *,
                          const OSSL_DISPATCH **, void **) {
            crypto_unsupported("OSSL_provider_init_fn");
        }
    };

}
