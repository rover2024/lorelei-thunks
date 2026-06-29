#pragma once

#include <cstdio>

#include <lorelei/ThunkInterface/Proc.h>
#include <lorelei/Modules/GuestRT/GuestClient.h>

namespace lore::thunk {

    namespace detail {

        /// Read the host libc's \a name std stream variable (\c "stdin" / \c "stdout" / \c "stderr")
        /// via the host dlsym, dereferenced directly thanks to the shared address space.
        inline FILE *resolveHostStream(const char *name) {
            void *p = mod::GuestClient::getProcAddress(nullptr, name); // &(host's FILE* variable)
            return p ? *reinterpret_cast<FILE **>(p) : nullptr;
        }

        /// Map a guest std stream to the host libc's matching one. The guest's stdin/stdout/stderr are
        /// guest-libc FILE objects, and a host library handed one trips the host's stdio vtable check
        /// (\c "invalid stdio handle"). Any other FILE is assumed to already be a host FILE (e.g. from
        /// libc-shim's interposed fopen) and passes through unchanged.
        inline FILE *toHostStream(FILE *f) {
            static FILE *hostStdin = resolveHostStream("stdin");
            static FILE *hostStdout = resolveHostStream("stdout");
            static FILE *hostStderr = resolveHostStream("stderr");
            if (f == stdin) {
                return hostStdin;
            }
            if (f == stdout) {
                return hostStdout;
            }
            if (f == stderr) {
                return hostStderr;
            }
            return f;
        }

    } // namespace detail

    /// ProcArgFilter<FILE *> - guest std-stream remap for a thunk of a host library that takes a
    /// FILE*. The TypeFilter pass applies it on the guest Adapt to every FILE* argument (\c BIO_new_fp,
    /// \c PEM_read, ...), so the pointer is host-callable before the call crosses and the host side
    /// stays a plain pass-through. It pairs with libc-shim's fopen interposer: that makes files the
    /// guest opens host-side but cannot reach a std stream passed straight into the library, while this
    /// cannot reach a file the guest opened, so a thunk may need either or both.
    template <>
    struct ProcArgFilter<FILE *> {
        using type = FILE *;
        template <class Desc, size_t Index, ProcKind Kind, ProcDirection Direction, class... Args>
        static void filter(FILE *&arg, ProcArgContext<Args...> ctx) {
            arg = detail::toHostStream(arg);
        }
    };

}
