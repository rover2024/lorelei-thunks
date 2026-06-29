// This thunk is LD_PRELOADed and interposes the allocator, so it must keep forwarding through process
// teardown (libc's exit cleanup calls free() after static destructors run). PERSIST makes its thunk
// context a no-destroy singleton: the HTL stays mapped to the end, the OS reclaims it at exit.
#define LORE_THUNK_PERSIST

#include "Desc.h"
#include <lorelei/ThunkInterface/ManifestGuest.cpp.inc>

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cerrno>
#include <cstdio>
#include <dlfcn.h>

#include <lorelei/Modules/GuestRT/GuestClient.h>

// The std-stream remap (ProcArgFilter<FILE*>) this thunk applies to its interposed stdio functions
// is the same shared libc-shim utility the FILE*-taking library thunks use, so pull it in rather than
// keeping a second copy here.
#include <lorethunk/ThunkUtils/Guest/libc-shim/StdStream.h>

// Guest-side libc interposer (allocator + stdio).
//
// This thunk is LD_PRELOADed into the guest ahead of the real libc, so the symbols below become the
// guest program's malloc/free/fopen/.... Each is the Entry layer of its proc, which the GTL exports
// under the real name; the generated Adapt -> Caller -> Exec chain underneath still forwards to the
// host libc, so the bytes a host-side thunked library hands back can be freed here and vice versa
// (one heap on both sides), and a FILE the guest opens is a host FILE the host library can use. The
// host call is reached with ProcFn<F, GuestToHost, Adapt>::invoke(...).
//
// The stdio family forwards by default; the only handling it needs is remapping the guest's
// stdin/stdout/stderr to the host's, done once in ProcArgFilter<FILE*> below (Adapt layer, so the
// printf-family Entry/Caller machinery is left alone).
//
// Two things the allocator forwarding alone cannot handle, solved here:
//
//   * Ownership. Once we export free(), the guest hands us every pointer it frees, but glibc's own
//     strdup / getline / asprintf / ... allocate through libc-internal malloc (not via the PLT, so
//     not interposed) and return guest-heap pointers. Handing one of those to the host free()
//     corrupts the host heap. So every pointer we return carries a Header immediately before it;
//     free() checks the magic and routes host-owned pointers to the host free() and everything else
//     (foreign / guest-heap) to the real libc free() via RTLD_NEXT.
//
//   * Bootstrap. Allocations can happen before this thunk's static init has resolved the host cross
//     (other libraries' constructors, our own init). Until g_hostReady flips, requests are served
//     from a small static arena; their Header is flagged so free() just drops them.
//
// Status: first cut, to be shaken out with a Docker build. errno is out of scope here (it needs care
// so a guest syscall's own errno is not shadowed), as are the allocate-and-return stdio helpers
// (getline / getdelim / asprintf): their buffer is host-internal-malloc'd and carries no tag.

namespace lore::thunk {

    namespace {

        // 32-byte, 16-aligned record placed right before every pointer we return.
        struct Header {
            uint64_t magic;  // ours when it matches kMagic
            uint32_t flags;  // kBootstrap when served from the static arena
            uint32_t pad;
            void *base;      // the underlying host (or arena) allocation to release
            size_t size;     // usable bytes, for realloc copies
        };
        static_assert(sizeof(Header) == 32, "Header must stay 16-aligned");

        constexpr uint64_t kMagic = 0x4c4f52454d454d31ULL; // "LOREMEM1"
        constexpr uint32_t kBootstrap = 1u;
        constexpr size_t kDefaultAlign = alignof(std::max_align_t);

        // Forwarding is live only between these two points. g_hostReady is set by a static initializer
        // ordered after this TU's thunk-context init (the host cross is resolved by then). g_finalizing
        // is set by that same object's destructor at process teardown, before the runtime we forward
        // through goes away. Outside the window, requests stay on the guest side.
        bool g_hostReady = false;
        bool g_finalizing = false;

        inline bool canForward() {
            return g_hostReady && !g_finalizing;
        }

        // Bump arena for the pre-ready window. Never reclaimed; sized for the handful of early allocs.
        alignas(16) unsigned char g_arena[64 * 1024];
        size_t g_arenaUsed = 0;

        inline uintptr_t alignUp(uintptr_t p, size_t a) {
            return (p + (a - 1)) & ~static_cast<uintptr_t>(a - 1);
        }

        void *arenaRaw(size_t total) {
            uintptr_t start = alignUp(reinterpret_cast<uintptr_t>(g_arena) + g_arenaUsed, 16);
            uintptr_t end = start + total;
            uintptr_t limit = reinterpret_cast<uintptr_t>(g_arena) + sizeof(g_arena);
            if (end > limit) {
                return nullptr; // arena exhausted; should not happen with the early-only traffic
            }
            g_arenaUsed = end - reinterpret_cast<uintptr_t>(g_arena);
            return reinterpret_cast<void *>(start);
        }

        // Real libc free / realloc, for pointers we did not allocate (resolved past our interposition).
        void realFree(void *p) {
            using fn = void (*)(void *);
            static auto f = reinterpret_cast<fn>(dlsym(RTLD_NEXT, "free"));
            if (f) {
                f(p);
            }
        }

        void *realRealloc(void *p, size_t n) {
            using fn = void *(*) (void *, size_t);
            static auto f = reinterpret_cast<fn>(dlsym(RTLD_NEXT, "realloc"));
            return f ? f(p, n) : nullptr;
        }

        inline Header *headerOf(void *user) {
            return reinterpret_cast<Header *>(static_cast<unsigned char *>(user) - sizeof(Header));
        }

        // Core allocate: reserve room for the Header plus alignment slack, tag it, hand back the
        // aligned user pointer. Host-backed once ready, arena-backed before.
        void *allocTagged(size_t n, size_t align, bool zero) {
            if (align < kDefaultAlign) {
                align = kDefaultAlign;
            }
            size_t slack = align + sizeof(Header);
            if (n > SIZE_MAX - slack) {
                return nullptr; // overflow
            }
            size_t total = n + slack;

            bool boot = !canForward();
            void *base = boot ? arenaRaw(total)
                              : ProcFn<::malloc, GuestToHost, Adapt>::invoke(total);
            if (!base) {
                return nullptr;
            }

            uintptr_t user = alignUp(reinterpret_cast<uintptr_t>(base) + sizeof(Header), align);
            Header *h = headerOf(reinterpret_cast<void *>(user));
            h->magic = kMagic;
            h->flags = boot ? kBootstrap : 0;
            h->pad = 0;
            h->base = base;
            h->size = n;
            if (zero) {
                std::memset(reinterpret_cast<void *>(user), 0, n);
            }
            return reinterpret_cast<void *>(user);
        }

        void freeTagged(void *user) {
            if (!user) {
                return;
            }
            Header *h = headerOf(user);
            if (h->magic != kMagic) {
                realFree(user); // foreign / guest-heap pointer
                return;
            }
            if (h->flags & kBootstrap) {
                return; // arena memory: never reclaimed
            }
            if (!canForward()) {
                return; // host-owned, but forwarding is down (teardown): leak, the OS reclaims it
            }
            ProcFn<::free, GuestToHost, Adapt>::invoke(h->base); // host-owned
        }

    } // namespace

    // The Adapt-layer std-stream remap that ProcArgFilter<FILE*> applies to every interposed stdio
    // function (fread/fwrite/fclose/fprintf/...) comes from the shared StdStream.h pulled in above.

    // --- interposed entries --------------------------------------------------

    template <>
    struct ProcFn<::malloc, GuestToHost, Entry> {
        static void *invoke(size_t n) {
            return allocTagged(n, kDefaultAlign, false);
        }
    };

    template <>
    struct ProcFn<::calloc, GuestToHost, Entry> {
        static void *invoke(size_t nmemb, size_t size) {
            if (size != 0 && nmemb > SIZE_MAX / size) {
                return nullptr; // overflow
            }
            return allocTagged(nmemb * size, kDefaultAlign, true);
        }
    };

    template <>
    struct ProcFn<::realloc, GuestToHost, Entry> {
        static void *invoke(void *p, size_t n) {
            if (!p) {
                return allocTagged(n, kDefaultAlign, false);
            }
            if (n == 0) {
                freeTagged(p);
                return nullptr;
            }
            Header *h = headerOf(p);
            if (h->magic != kMagic) {
                return realRealloc(p, n); // foreign / guest-heap pointer
            }
            void *np = allocTagged(n, kDefaultAlign, false);
            if (!np) {
                return nullptr;
            }
            std::memcpy(np, p, h->size < n ? h->size : n);
            freeTagged(p);
            return np;
        }
    };

    template <>
    struct ProcFn<::free, GuestToHost, Entry> {
        static void invoke(void *p) {
            freeTagged(p);
        }
    };

    template <>
    struct ProcFn<::aligned_alloc, GuestToHost, Entry> {
        static void *invoke(size_t align, size_t size) {
            return allocTagged(size, align, false);
        }
    };

    template <>
    struct ProcFn<::posix_memalign, GuestToHost, Entry> {
        static int invoke(void **memptr, size_t align, size_t size) {
            if (align < sizeof(void *) || (align & (align - 1)) != 0) {
                return EINVAL;
            }
            void *p = allocTagged(size, align, false);
            if (!p) {
                return ENOMEM;
            }
            *memptr = p;
            return 0;
        }
    };

    namespace {
        // Drives the forwarding window. Defined after this TU's thunk-context object, so it is
        // constructed after the host cross is resolved (open the window) and destroyed first at
        // teardown, before the runtime we forward through is gone (close it). The context itself is
        // a no-destroy singleton (LORE_THUNK_PERSIST), so it never enters this ordering.
        struct ForwardGate {
            ForwardGate() {
                g_hostReady = true;
            }
            ~ForwardGate() {
                g_finalizing = true;
            }
        };
        ForwardGate g_forwardGate;
    } // namespace

}
