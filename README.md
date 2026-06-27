# LORETHUNK

LoreThunk is a collection of thunk libraries for [Lorelei](https://github.com/rover2024/lorelei), the cross-ISA compatibility layer. Each thunk library lets an emulated guest program call one native host library (zlib, SDL, ...) so the real work runs at host speed instead of being emulated.

## How it works

Lorelei runs the guest under a patched QEMU with `guest_base == 0`, so a guest pointer and a host pointer are the same number. The guest reaches the host through a single magic syscall that a QEMU TCG plugin intercepts and forwards to the host runtime.

A thunk library is the per-library glue that rides on top of that mechanism. For each library this repository ships a small manifest, and the Thunk Library Compiler (TLC, provided by Lorelei) reads the library's headers and emits the marshalling code:

- a **guest thunk library** (GTL), built for the guest ISA, that the guest links against in place of the real library; it issues the syscall on every call.
- a **host thunk library** (HTL), built for the host ISA, that the host runtime loads to `dlopen`/`dlsym` the real library and invoke it with the guest's arguments.

Because the address space is shared, pointers, structs and buffers pass through untouched, with no per-call serialization.

## Build From Source

LoreThunk builds against an installed Lorelei (which provides `LoreTLC`, the runtimes, and the `ThunkInterface` headers) and uses `qmsetup` for configuration. Build and install both of those first; see the Lorelei README for its own build steps.

Each thunk is two libraries that target **different** ISAs: the guest thunk (GTL) is built for the guest ISA (x86_64), and the host thunk (HTL) is built for the host ISA (the machine that runs the emulator).

Each library is compiled by the toolchain for its own ISA, so in the general cross-ISA case you configure and build twice, once per toolchain.

- `THUNK_BUILD_GUEST_TARGETS` selects the GTL
- `THUNK_BUILD_HOST_TARGETS` selects the HTL

The active compiler must match whichever one is enabled.

### Build on X86_64

The guest and host ISA are the same, so a single x86_64 compiler builds both halves in one configure:

```bash
export INSTALL_DIR=/home/user/install

git clone https://github.com/rover2024/lorelei-thunks.git
cd lorelei-thunks

cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
    -Dqmsetup_DIR=$INSTALL_DIR/qmsetup/lib/cmake/qmsetup \
    -Dlorelei_DIR=$INSTALL_DIR/lib/cmake/lorelei \
    -DTHUNK_BUILD_HOST_TARGETS=TRUE \
    -DTHUNK_BUILD_GUEST_TARGETS=TRUE
cmake --build build --target all
cmake --build build --target install
```

### Build on ARM64/RISC-V64

The host ISA differs from the guest x86_64, so the two halves need two different compilers and two separate builds. Build the **host** half first: it runs the TLC stat step and installs `ThunkStat.json` under `share/lorelei/thunks`. Then build the **guest** half with an x86_64 compiler, pointing `THUNK_DATA_DIR` at the installed stat so it is reused instead of re-running stat.

```bash
# 1. Host thunks (HTL), built with the native host toolchain. Produces and installs
#    ThunkStat.json and the generated host source under share/lorelei/thunks.
cmake -B build-host -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
    -Dqmsetup_DIR=$INSTALL_DIR/qmsetup/lib/cmake/qmsetup \
    -Dlorelei_DIR=$INSTALL_DIR/lib/cmake/lorelei \
    -DTHUNK_BUILD_HOST_TARGETS=TRUE \
    -DTHUNK_BUILD_GUEST_TARGETS=FALSE
cmake --build build-host --target install

# 2. Guest thunks (GTL), built with an x86_64 toolchain. Reuse the stat installed
#    in step 1 via THUNK_DATA_DIR, so the stat step is skipped here.
cmake -B build-guest -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
    -DCMAKE_C_COMPILER=x86_64-linux-gnu-gcc \
    -DCMAKE_CXX_COMPILER=x86_64-linux-gnu-g++ \
    -Dqmsetup_DIR=$INSTALL_DIR/qmsetup/lib/cmake/qmsetup \
    -Dlorelei_DIR=$INSTALL_DIR/lib/cmake/lorelei \
    -DTHUNK_DATA_DIR=$INSTALL_DIR/share/lorelei/thunks \
    -DTHUNK_BUILD_HOST_TARGETS=FALSE \
    -DTHUNK_BUILD_GUEST_TARGETS=TRUE
cmake --build build-guest --target install
```

The host ISA is detected from the compiler; the guest ISA is fixed to x86_64. The GTL and HTL install into separate `<arch>-LoreGTL` / `<arch>-LoreHTL` library directories, so the two builds do not collide.

Each build also installs the thunk source it generated (`Thunk_host.cpp` from the host build, `Thunk_guest.cpp` from the guest build) next to `ThunkStat.json`. Pointing `THUNK_GEN_SOURCE_DIR` at that directory on a later build skips both `stat` and `generate` and compiles the installed sources directly, so a fully generated package can be rebuilt without running TLC.

## Adding a thunk

Two existing thunks are worth reading as examples:

- `src/thunks/zlib`: the smallest worked example.
- `src/thunks/ThunkExample`: a broader one that exercises every feature.

The short version is below; for the full guide (proc descriptors, the proc phases, and how to override them) see [docs/HowToAddAThunk.md](docs/HowToAddAThunk.md). To add a library `<lib>`:

1. Create the directory `src/thunks/<lib>/`.
2. Write `Desc.h`: include the library's headers and `<lorelei/ThunkInterface/Proc.h>` / `<lorelei/ThunkInterface/PassTags.h>`, then declare any per-proc pass descriptors (`ProcFnDesc` / `ProcCbDesc`, for example to route a variadic function through the printf pass).
3. Write the symbol list `Symbols.conf`: the functions and callbacks to thunk. It usually just does `include "Symbols_autogen.conf"` and adds a `[Guest Function]` section for any guest symbols the host needs to call back into.
4. Write `Manifest_guest.cpp` and `Manifest_host.cpp`: each includes `Desc.h` and then `<lorelei/ThunkInterface/ManifestGuest.cpp.inc>` or `ManifestHost.cpp.inc`. Put any hand-written `ProcFn` / `ProcCb` overrides here.
5. Write `CMakeLists.txt`: `project(<libname>)`, `include("../AddThunk.cmake")`, set the convention variables (`GTL_alias`, `*_extra_links`, `*_extra_includes`, ...), then call `add_thunk()`. See the header of `src/thunks/AddThunk.cmake` for the full list.
6. Add `<lib>` to the `_thunks` list in `src/thunks/CMakeLists.txt`.

## Dependencies

- lorelei (https://github.com/rover2024/lorelei)
- qmsetup (https://github.com/stdware/qmsetup)
