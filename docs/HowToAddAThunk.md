# How To Add A Thunk

This guide explains how a thunk library is written: the files involved, how a library's surface is declared, the proc model that TLC generates, and how to hand-write or override individual pieces.

`src/thunks/zlib` is the smallest real example worth reading alongside it.

## What a Thunk Is

A thunk for a library `<lib>` is compiled into two shared libraries:

- the **guest thunk library** (GTL), which the guest links in place of the real `<lib>`. It exports the same symbols and forwards every call across the boundary.
- the **host thunk library** (HTL), which the host runtime loads to run the real `<lib>` on the guest's behalf.

You do not write the per-call marshalling. TLC reads the library's real headers and generates both sides. Your job is to declare which symbols to thunk, give TLC the headers, and hand-write only the few cases the generator cannot handle on its own.

## The Files

A thunk lives in `src/thunks/<lib>/` and has five files (see `src/thunks/zlib` for the smallest real example):

| File | Purpose |
|------|---------|
| `Symbols.conf` | which functions and callbacks to thunk |
| `Desc.h` | includes the library headers and declares per-proc pass descriptors |
| `Manifest_guest.cpp` | guest-side entry point and overrides |
| `Manifest_host.cpp` | host-side entry point and overrides |
| `CMakeLists.txt` | calls `add_thunk()` with the link/alias settings |

Then add `<lib>` to the `_thunks_stable` list in `src/thunks/CMakeLists.txt` (or `_thunks_experimental` while it is still work in progress).

## 1. `Symbols.conf`: declaring the surface

`Symbols.conf` lists the symbols to thunk, grouped into sections:

```ini
[Function]
deflate
inflate

[Callback]
alloc_func
free_func

[Guest Function]
XSync
XOpenDisplay
```

The recognized sections are:

- **`[Function]`**: host functions the guest calls (the `GuestToHost` direction). This is the bulk of a normal library.
- **`[Guest Function]`**: guest functions the host needs to call back into (the `HostToGuest` direction), for example so host code can open the guest's own X display. These are exported from the HTL under a `GTL_` prefix (see [Entry is the exported symbol](#entry-is-the-exported-symbol)).
- **`[Callback]`**: named callback function-pointer types that cross the boundary.

Another file can be pulled in with `include "<file>"`. In practice the long `[Function]` list is generated once from the built library with `DumpSyms.py` (below) into `Symbols_autogen.conf` and checked in, so a hand-written `Symbols.conf` often only includes it and adds the few extra entries:

```ini
include "Symbols_autogen.conf"

[Guest Function]
XSync
XOpenDisplay
```

### Generating the list with `DumpSyms.py`

`scripts/DumpSyms.py` produces a `Symbols_autogen.conf` from a built shared object. It runs `nm -D --defined-only` over the object's dynamic symbol table, strips the `@@version` suffix from each name, sorts them, and buckets them into two sections: `T`/`t` (text) symbols become `[Function]`, and `D`/`B`/`R` (data/bss/rodata) symbols become `[Variable]`.

Note that `[Variable]` (thunking an exported global variable) is not supported yet, so DumpSyms emits it only for reference. Drop the `[Variable]` section when you prune the output.

```sh
python3 scripts/DumpSyms.py /usr/lib/x86_64-linux-gnu/libz.so.1 src/thunks/zlib/Symbols_autogen.conf
```

Point it at the actual `.so` the thunk will stand in for (follow the soname, e.g. `libz.so.1`, not the `-dev` `libz.so` symlink), so the exported set matches what the guest links against.

If the object is built for another architecture, pass the matching toolchain's `nm` so it can read it:

```sh
python3 scripts/DumpSyms.py --nm aarch64-linux-gnu-nm ./libfoo.so.1 src/thunks/foo/Symbols_autogen.conf
```

The output is a starting point, not the final surface. Everything defined lands in `[Function]`/`[Variable]`, so you still prune symbols you do not want to thunk, move guest-callable entries into `[Guest Function]`, and add `[Callback]` entries by hand. Keep those edits in `Symbols.conf`, which `include`s the generated file, so a regenerated `Symbols_autogen.conf` never clobbers them.

## 2. `Desc.h`: headers and proc descriptors

`Desc.h` is parsed by TLC (during `stat`) and included into the generated source (during `generate`). It includes the library's headers and the thunk-interface headers, and declares any per-proc descriptors:

```cpp
#pragma once

#include <zlib.h>

#include <lorelei/ThunkInterface/Proc.h>
#include <lorelei/ThunkInterface/PassTags.h>

namespace lore::thunk {}
```

If a library header defines a macro that collides with an identifier (Xlib's `Success`, zlib's `gzgetc`), undefine it here.

### Proc descriptors

A descriptor tells TLC to handle one proc specially. Declare them in the `lore::thunk` namespace:

- `ProcFnDesc<F>` for a function `F`.
- `ProcCbDesc<F>` for a callback type `F`.

Each can carry two fields:

- `builder_pass`: selects a non-default Builder for this proc (the printf/scanf family, for variadic functions).
- `passes`: a `pass::PassTagList<...>` of extra passes to apply.

```cpp
// SDL_LogMessageV is the va_list form of a printf-style call. It carries no format attribute and
// its name does not end in "vprintf", so it cannot be auto-detected and is tagged by hand.
template <>
struct ProcFnDesc<::SDL_LogMessageV> {
    _DESC pass::vprintf<> builder_pass = {};
};
```

The available pass tags (`pass::printf` / `pass::vprintf` / `pass::scanf` / `pass::vscanf` for variadic functions, `pass::GetProcAddress` for `*GetProcAddress*`-style functions) are documented in `<lorelei/ThunkInterface/PassTags.h>`.

Most procs need no descriptor at all. The default Builder handles them.

## 3. The proc model: directions and phases

For every symbol, TLC generates a set of specializations of two templates:

```cpp
template <auto F,  ProcDirection Direction, ProcPhase Phase> struct ProcFn;  // functions
template <class F, ProcDirection Direction, ProcPhase Phase> struct ProcCb;  // callbacks
```

`Direction` is `GuestToHost` (guest calls host, the common case) or `HostToGuest` (host calls back into the guest).

`Phase` is one layer of the call. Each proc is split into a chain of four layers, run `Entry -> Adapt -> Caller -> Exec`:

| Phase | Role | `invoke` signature |
|-------|------|--------------------|
| `Entry` | The wire boundary. On the receiver side it unpacks the raw `args[]` buffer into typed arguments. On the sender side it is the real C function the caller links against. | receiver: `(void **args, void *ret, void *metadata)`<br>sender: the real C signature |
| `Adapt` | Typed adaptation. The non-Builder passes (callback substitution, type/handle filters, GetProcAddress) inject here. A plain pass-through to `Caller` by default. | the typed argument signature |
| `Caller` | Constructs the actual call (default forwarding, or the printf/scanf wrapper). | the typed argument signature |
| `Exec` | The real library call, or the cross-boundary invoke into the other side. Fixed boilerplate that you do not override. | the typed argument signature |

Each layer's `invoke` calls the next, so overriding one layer leaves the others intact. This is the point of the split: you can replace the adaptation of one proc without rewriting its marshalling.

### Entry is the exported symbol

`Entry` is special: its sender-side `invoke` is the symbol the library actually exports.

- The GTL exports every `[Function]` under its real name (`deflate`, `glXSwapBuffers`, ...), aliased to the guest `Entry`. That is how the GTL stands in for the real library: the guest links `deflate` and gets the thunk.
- The HTL exports every `[Guest Function]` under a `GTL_` prefix (`GTL_XOpenDisplay`, ...), aliased to the host `Entry`. Host-side code calls these to reenter the guest, which is why such code declares them by hand:

```cpp
extern "C" {
Display *GTL_XOpenDisplay(const char *);
int GTL_XSync(Display *, int);
}
```

## 4. The manifests

`Manifest_guest.cpp` and `Manifest_host.cpp` are the two translation units TLC generates into. Each sets its feature macros, includes `Desc.h`, includes the manifest entry header, and then opens `namespace lore::thunk` for your overrides:

```cpp
#define LORE_THUNK_CALLBACK_REPLACE   // optional, see below
#define LORE_THUNK_AUTO_LINK          // host only, optional, see below

#include "Desc.h"
#include <lorelei/ThunkInterface/ManifestHost.cpp.inc>   // ManifestGuest.cpp.inc on the guest side

namespace lore::thunk {

    // overrides go here

}
```

The two feature macros:

- **`LORE_THUNK_CALLBACK_REPLACE`**: turn on callback substitution. With it, function pointers the guest passes are wrapped in trampolines so the host can call them back across the boundary. Enable it for any library with callbacks (zlib's `zalloc`/`zfree`, SDL's event filters). A few callbacks sit in positions the automatic substituter cannot rewrite. Those need a hand-written `Adapt` (see below).
- **`LORE_THUNK_AUTO_LINK`** (host manifest only): fold the real library's symbol addresses straight into the HTL at link time instead of resolving them with `dlopen`/`dlsym` at run time. The HTL must then link the real library itself (set `HTL_EXTRA_LINKS` in the CMakeLists).

## 5. Overriding a phase

To override a layer, declare the matching specialization in the manifest. Providing `ProcFn<F, Direction, Phase>` (or `ProcCb<...>`) makes the generator skip its default code for exactly that proc, direction and phase. Everything else is still generated. The `invoke` signature must be call-compatible with the generated one. You may use the library's own typedefs.

Which manifest an override goes in depends on the receiver side: for a `GuestToHost` function the receiver is the host, so it goes in `Manifest_host.cpp`. A callback is generated in both, so its substitution lands on the guest for the `HostToGuest` direction and the host for the `GuestToHost` direction.

### Override `Entry`: run locally on the guest

Overriding the guest `Entry` replaces the whole call, including the syscall, so the body runs on the guest. SDL's dynamic-loading API must act on the guest's own loader rather than be forwarded to the host:

```cpp
// Manifest_guest.cpp
template <>
struct ProcFn<::SDL_LoadObject, GuestToHost, Entry> {
    static void *invoke(const char *sofile) {
        return dlopen(sofile, RTLD_NOW);
    }
};
```

### Override `Adapt`: adapt arguments around the real call

`Adapt` is the natural place for transformations that wrap the real call. A trivial pass-through (used when the automatic callback substituter bailed but no substitution is actually needed):

```cpp
// Manifest_host.cpp
template <>
struct ProcFn<::SDL_ConvertAudio, GuestToHost, Adapt> {
    static int invoke(SDL_AudioCVT *cvt) {
        return ProcFn<::SDL_ConvertAudio, GuestToHost, Caller>::invoke(cvt);
    }
};
```

`Adapt` is also where you reject a call the bridge cannot serve. SDL's `*Get*` queries return a host callback pointer through an out parameter, which the guest cannot use, so the SDL2 thunk overrides their `Adapt` to fail loudly instead of handing back an unusable pointer:

```cpp
// Manifest_host.cpp
template <>
struct ProcFn<::SDL_GetEventFilter, GuestToHost, Adapt> {
    static SDL_bool invoke(SDL_EventFilter *, void **) {
        std::fprintf(stderr, "SDL_GetEventFilter is not supported across the boundary\n");
        std::abort();
    }
};
```

`Adapt` is also where you translate a handle around the call: swap a guest handle for the matching host one before forwarding and restore it after. When the translation depends only on the argument's type (rather than one named proc), prefer an argument filter (below), which applies the same conversion everywhere that type appears.

### Override `Caller`

Override `Caller` when the call itself must be constructed differently (rewriting a struct field before the real call, dropping an argument). It forwards to `Exec` rather than `Caller`:

```cpp
template <>
struct ProcFn<::some_function, GuestToHost, Caller> {
    static int invoke(SomeStruct *info) {
        // adjust the call here: rewrite an argument, edit a struct field, drop a parameter
        return ProcFn<::some_function, GuestToHost, Exec>::invoke(info);
    }
};
```

### Argument and return filters

For a transformation that applies wherever a given type appears (rather than to one named proc), specialize `ProcArgFilter<T>` or `ProcReturnFilter<T>`. The `TypeFilter` pass discovers these and injects them into the `Adapt` layer of every proc that has an argument or return of type `T`:

```cpp
// Apply a conversion to every argument of type Handle (here only for guest-to-host calls).
template <>
struct ProcArgFilter<Handle> {
    template <class Desc, size_t Index, ProcKind Kind, ProcDirection Direction, class... Args>
    static void filter(Handle &h, ProcArgContext<Args...> ctx) {
        if constexpr (Direction == GuestToHost) {
            h = convert_guest_to_host(h);
        }
    }
};
```

## 6. `CMakeLists.txt`

The CMakeLists names the project, includes `AddThunk.cmake`, sets the convention variables, and calls `add_thunk()`:

```cmake
project(z)

include("../AddThunk.cmake")

set(GTL_ALIAS libz.so.1)

# Manifest_host.cpp uses LORE_THUNK_AUTO_LINK, so the HTL links the real zlib.
set(HTL_EXTRA_LINKS z)

add_thunk()
```

The common variables are `GTL_ALIAS` / `HTL_ALIAS` (soname symlinks so the GTL can stand in for the real library), `GTL_EXTRA_LINKS` / `HTL_EXTRA_LINKS`, `GTL_FORCE_LINKS` / `HTL_FORCE_LINKS`, and `ALL_EXTRA_INCLUDES` / `*_EXTRA_INCLUDES`. The full list is documented in the header of `src/thunks/AddThunk.cmake`.

## Checklist

1. `src/thunks/<lib>/Symbols.conf`: list the symbols (`[Function]`, `[Guest Function]`, `[Callback]`). Seed the `[Function]` list from the built `.so` with `python3 scripts/DumpSyms.py <lib>.so Symbols_autogen.conf`, then prune and add the rest by hand.
2. `Desc.h`: include the library headers and add any `ProcFnDesc` / `ProcCbDesc` descriptors.
3. `Manifest_guest.cpp` / `Manifest_host.cpp`: set `LORE_THUNK_CALLBACK_REPLACE` / `LORE_THUNK_AUTO_LINK` as needed, and add any `Entry` / `Adapt` / `Caller` overrides.
4. `CMakeLists.txt`: `project()`, `include("../AddThunk.cmake")`, set aliases and links, `add_thunk()`.
5. Add `<lib>` to `src/thunks/CMakeLists.txt`.
