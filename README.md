# LORETHUNK

LoreThunk is a collection of thunk libraries for [Lorelei](https://github.com/rover2024/lorelei), the cross-ISA compatibility layer. Each thunk library lets an emulated guest program call one native host library (zlib, SDL, ...) so the real work runs at host speed instead of being emulated.

## How it works

Lorelei runs the guest under a patched QEMU with `guest_base == 0`, so a guest pointer and a host pointer are the same number. The guest reaches the host through a single magic syscall that a QEMU TCG plugin intercepts and forwards to the host runtime. See the [Lorelei](https://github.com/rover2024/lorelei) README for the full mechanism.

A thunk library is the per-library glue that rides on top of that mechanism. For each library this repository ships a small manifest, and the Thunk Library Compiler (TLC, provided by Lorelei) reads the library's headers and emits the marshalling code:

- a **guest thunk library** (GTL), built for the guest ISA, that the guest links against in place of the real library; it issues the syscall on every call.
- a **host thunk library** (HTL), built for the host ISA, that the host runtime loads to `dlopen`/`dlsym` the real library and invoke it with the guest's arguments.

Because the address space is shared, pointers, structs and buffers pass through untouched, with no per-call serialization.

## Project layout

- `src/thunks/<lib>`: one directory per thunk library. Each holds the manifests (`Manifest_guest.cpp`, `Manifest_host.cpp`), an optional `Desc.h` of per-proc pass descriptors, the symbol lists (`Symbols*.conf`) and a `CMakeLists.txt` that calls `add_thunk()`.
- `src/thunks/AddThunk.cmake`: the `add_thunk()` macro that wires a library's manifest through TLC `stat`/`generate` into the GTL and HTL targets.
- `cmake/LoreThunkBuildApi.cmake`: the lower-level build helpers (arch detection, TLC invocation, install rpath, `thunk_add_library`, ...).
- `src/libs/Midware`: host-side support libraries (X11, xcb) that some thunks depend on.
- `include/lorethunk`: public headers for the support libraries above.
- `share/lorelei`: shared data installed alongside the libraries (the thunk database, ...).

## Build From Source

LoreThunk builds against an installed Lorelei (which provides `LoreTLC`, the runtimes, and the `ThunkInterface` headers) and uses `qmsetup` for configuration. Build and install both of those first; see the Lorelei README for its own build steps.

Only `zlib` is needed for the default build.

```bash
export INSTALL_DIR=/home/user/install

sudo apt install zlib1g-dev

git clone https://github.com/rover2024/lorelei-thunks.git
cd lorelei-thunks

cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
    -Dqmsetup_DIR=$INSTALL_DIR/qmsetup/lib/cmake/qmsetup \
    -Dlorelei_DIR=$INSTALL_DIR/lib/cmake/lorelei \
    -DTHUNK_BUILD_HOST_TARGETS=TRUE \   # Disable if building for guest ISA
    -DTHUNK_BUILD_GUEST_TARGETS=TRUE    # Disable if building for host ISA
cmake --build build --target all
cmake --build build --target install
```

## Build Options

- `THUNK_BUILD_HOST_TARGETS` (default `ON`): build the host thunk libraries (HTL).
- `THUNK_BUILD_GUEST_TARGETS` (default `OFF`): build the guest thunk libraries (GTL); enable when building for the guest ISA.
- `THUNK_INSTALL` (default `ON`): install the libraries, headers and shared data.
- `THUNK_DISABLE_LIBRARIES` (default empty): semicolon-separated list of thunk library names to skip, for example `-DTHUNK_DISABLE_LIBRARIES="zlib;SDL2"`.
- `THUNK_DATA_DIR`: directory holding each thunk's TLC stat result. When set to a pre-generated directory, the stat step is skipped and its results are taken as-is (and not reinstalled); otherwise stat runs into the build tree and its results are installed for reuse. The thunk sources are always regenerated.

## Adding a thunk

Create `src/thunks/<lib>/` with a `Manifest_guest.cpp` and `Manifest_host.cpp` (including `<lorelei/ThunkInterface/ManifestGuest.cpp.inc>` and `ManifestHost.cpp.inc` respectively), the symbol list, and a `CMakeLists.txt` that sets the convention variables and calls `add_thunk()`. Then add the directory name to the `_thunks` list in `src/thunks/CMakeLists.txt`. See `src/thunks/zlib` for a worked example.

## Dependencies

- lorelei (https://github.com/rover2024/lorelei)
- qmsetup (https://github.com/stdware/qmsetup)
- zlib (https://github.com/madler/zlib)
