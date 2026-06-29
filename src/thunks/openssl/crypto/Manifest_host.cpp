#define LORE_THUNK_CALLBACK_REPLACE
#define LORE_THUNK_AUTO_LINK

#include "Desc.h"
#include <lorelei/ThunkInterface/ManifestHost.cpp.inc>

#include <cstdio>
#include <cstdlib>

namespace lore::thunk {

    // A handful of libcrypto procs carry a callback shape the automatic CallbackSubstituter cannot
    // marshal across the boundary, so it emits "unsupported callback type". They sit in code paths the
    // common CLI never exercises (the TXT_DB flat-file database is only used by `openssl ca`; the
    // provider-init callback only crosses when loading a provider from an external module), so we hand
    // these few Adapt layers, which suppresses the generated default, and abort if one is ever called.
    [[noreturn]] static void crypto_unsupported(const char *fn) {
        std::fprintf(stderr,
                     "lorethunk openssl: %s takes a callback whose shape cannot be marshalled across "
                     "the guest/host boundary yet; refusing to call it.\n",
                     fn);
        std::abort();
    }

    // TXT_DB_* take a TXT_DB whose `qual` field is a pointer to a runtime-length array of callbacks
    // (one qualifier per field), a shape the substituter cannot wrap.
    template <>
    struct ProcFn<::TXT_DB_create_index, GuestToHost, Adapt> {
        static int invoke(TXT_DB *, int, int (*)(OPENSSL_STRING *), OPENSSL_LH_HASHFUNC,
                          OPENSSL_LH_COMPFUNC) {
            crypto_unsupported("TXT_DB_create_index");
        }
    };

    template <>
    struct ProcFn<::TXT_DB_free, GuestToHost, Adapt> {
        static void invoke(TXT_DB *) {
            crypto_unsupported("TXT_DB_free");
        }
    };

    template <>
    struct ProcFn<::TXT_DB_get_by_index, GuestToHost, Adapt> {
        static OPENSSL_STRING *invoke(TXT_DB *, int, OPENSSL_STRING *) {
            crypto_unsupported("TXT_DB_get_by_index");
        }
    };

    template <>
    struct ProcFn<::TXT_DB_insert, GuestToHost, Adapt> {
        static int invoke(TXT_DB *, OPENSSL_STRING *) {
            crypto_unsupported("TXT_DB_insert");
        }
    };

    template <>
    struct ProcFn<::TXT_DB_write, GuestToHost, Adapt> {
        static long invoke(BIO *, TXT_DB *) {
            crypto_unsupported("TXT_DB_write");
        }
    };

    // OSSL_provider_init_fn's own arguments carry an OSSL_DISPATCH** (a runtime-length function-pointer
    // table), so the callback itself cannot be marshalled. OSSL_PROVIDER_add_builtin is the proc that
    // takes it; hand its Adapt and the callback's Adapt so neither emits the unsupported #error.
    template <>
    struct ProcCb<OSSL_provider_init_fn *, GuestToHost, Adapt> {
        static int invoke(void *, const OSSL_CORE_HANDLE *, const OSSL_DISPATCH *,
                          const OSSL_DISPATCH **, void **) {
            crypto_unsupported("OSSL_provider_init_fn");
        }
    };

}
