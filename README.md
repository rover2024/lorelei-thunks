# LORETHUNK

LoreThunk is a collection of thunk libraries for [Lorelei](https://github.com/rover2024/lorelei), the cross-ISA compatibility layer. Each thunk library lets an emulated guest program call one native host library (zlib, SDL, ...) so the real work runs at host speed instead of being emulated.

## How It Works

Lorelei runs the guest under a patched QEMU with `guest_base == 0`, so a guest pointer and a host pointer are the same number. The guest reaches the host through a single magic syscall that a QEMU TCG plugin intercepts and forwards to the host runtime.

A thunk library is the per-library glue that rides on top of that mechanism. For each library this repository ships a small manifest, and the Thunk Library Compiler (TLC, provided by Lorelei) reads the library's headers and emits the marshalling code:

- a **guest thunk library** (GTL), built for the guest ISA, that the guest links against in place of the real library, and issues the syscall on every call.
- a **host thunk library** (HTL), built for the host ISA, that the host runtime loads to `dlopen`/`dlsym` the real library and invoke it with the guest's arguments.

Because the address space is shared, pointers, structs and buffers pass through untouched, with no per-call serialization.

## Build From Source

LoreThunk builds against an installed Lorelei (which provides `LoreTLC`, the runtimes, and the `ThunkInterface` headers) and uses `qmsetup` for configuration.

Build and install both of those first. See the [Lorelei README](https://github.com/rover2024/lorelei#build-from-source) for its own build steps. The steps below assume you install LoreThunk into the same `INSTALL_DIR` as Lorelei.

Each thunk is two libraries that target **different** ISAs: the guest thunk (GTL) is built for the guest ISA (x86_64), and the host thunk (HTL) is built for the host ISA (the machine that runs the emulator).

Each library is compiled by the toolchain for its own ISA, so in the general cross-ISA case you configure and build twice, once per toolchain.

- `THUNK_BUILD_GUEST_TARGETS` selects the GTL
- `THUNK_BUILD_HOST_TARGETS` selects the HTL

The active compiler must match whichever one is enabled.

By default only the stable thunks (zlib and lzma) are built, so a fresh checkout configures without needing every wrapped library's dev headers. The other thunks are still work in progress; add `-DTHUNK_BUILD_EXPERIMENTAL_LIBRARIES=ON` to build them too, or build an exact set with `-DTHUNK_ENABLE_LIBRARIES="zlib;openssl"`.

### Build on X86_64

The guest and host ISA are the same, so a single x86_64 compiler builds both halves in one configure:

```bash
# the same prefix you installed Lorelei into
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

The host ISA differs from the guest x86_64, so the two halves need two different compilers and two separate builds. Build the **host** half first: it runs the native TLC, which both stats and generates, and installs `ThunkStat.json` together with *both* thunk sources (`Thunk_host.cpp` and `Thunk_guest.cpp`) under `share/lorelei/thunks`. Then build the **guest** half with an x86_64 compiler, pointing `THUNK_GEN_SOURCE_DIR` at those installed sources: it skips TLC entirely and just compiles `Thunk_guest.cpp`, linking the x86_64 `LoreGuestRT`. Because the guest build runs no TLC, its `lorelei_DIR` points at the x86_64 lorelei install (which carries the x86_64 runtime), not the host one.

```bash
# 1. Host thunks (HTL), built with the native host toolchain. Runs the TLC and installs
#    ThunkStat.json and both generated sources (Thunk_host.cpp + Thunk_guest.cpp) under
#    share/lorelei/thunks.
cmake -B build-host -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
    -Dqmsetup_DIR=$INSTALL_DIR/qmsetup/lib/cmake/qmsetup \
    -Dlorelei_DIR=$INSTALL_DIR/lib/cmake/lorelei \
    -DTHUNK_BUILD_HOST_TARGETS=TRUE \
    -DTHUNK_BUILD_GUEST_TARGETS=FALSE
cmake --build build-host --target install

# 2. Guest thunks (GTL), built with an x86_64 toolchain. Reuse the sources generated in
#    step 1 via THUNK_GEN_SOURCE_DIR, so no TLC runs here, and lorelei_DIR is the x86_64 install,
#    whose LoreGuestRT the GTL links against.
cmake -B build-guest -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR/x86_64 \
    -DCMAKE_C_COMPILER=x86_64-linux-gnu-gcc \
    -DCMAKE_CXX_COMPILER=x86_64-linux-gnu-g++ \
    -Dqmsetup_DIR=$INSTALL_DIR/qmsetup/lib/cmake/qmsetup \
    -Dlorelei_DIR=$INSTALL_DIR/x86_64/lib/cmake/lorelei \
    -DTHUNK_GEN_SOURCE_DIR=$INSTALL_DIR/share/lorelei/thunks \
    -DTHUNK_BUILD_HOST_TARGETS=FALSE \
    -DTHUNK_BUILD_GUEST_TARGETS=TRUE
cmake --build build-guest --target install
```

The host ISA is detected from the compiler, while the guest ISA is fixed to x86_64. The GTL and HTL install into separate `<arch>-LoreGTL` / `<arch>-LoreHTL` library directories, so the two builds do not collide.

Generation does not depend on which side is built, so the host build emits both sources. Pointing `THUNK_GEN_SOURCE_DIR` at the installed directory skips both `stat` and `generate` and compiles the sources directly, which is exactly what the guest step above does and how a fully generated package can be rebuilt without running TLC.

## Running a Thunk Under QEMU

The thunks run on the patched QEMU (`guest_base == 0`, a shared address space) with its `dlcall` plugin. Build it once:

```bash
git clone https://github.com/rover2024/qemu.git
cd qemu
git checkout minimal-passthrough-plugin
mkdir -p build/release && cd build/release
../../configure --target-list=x86_64-linux-user --enable-plugins --python=python3
ninja
```

This produces `qemu-x86_64` and `contrib/plugins/libdlcall.so`.

With Lorelei and the thunks installed as above, any x86_64 program runs over a thunk by putting the guest thunk first on the guest library path. The examples below run the distribution's `minizip` over the installed zlib thunk, so its `deflate` / `compress` calls run on the host's native libz while minizip itself stays emulated. The only difference between hosts is where the guest half was installed.

On an x86_64 host the guest and host halves share `$INSTALL_DIR`, and the native `minizip` is already x86_64:

```bash
export QEMU=/path/to/qemu/build/release/qemu-x86_64
export PLUGIN=/path/to/qemu/build/release/contrib/plugins/libdlcall.so

LORELEI_ROOT=$INSTALL_DIR LORELEI_GUEST_ROOT=$INSTALL_DIR \
LD_LIBRARY_PATH=$INSTALL_DIR/lib \
    $QEMU -plugin $PLUGIN \
    -E LD_LIBRARY_PATH=$INSTALL_DIR/lib/x86_64-LoreGTL:$INSTALL_DIR/lib \
    "$(command -v minizip)" -8 -o /tmp/archive.zip /path/to/some/file
```

On a cross (ARM64/RISC-V64) host the guest half is under `$INSTALL_DIR/x86_64`, and the program must be an x86_64 minizip (the native one cannot run under `qemu-x86_64`):

```bash
export QEMU=/path/to/qemu/build/release/qemu-x86_64
export PLUGIN=/path/to/qemu/build/release/contrib/plugins/libdlcall.so

LORELEI_ROOT=$INSTALL_DIR LORELEI_GUEST_ROOT=$INSTALL_DIR/x86_64 \
LD_LIBRARY_PATH=$INSTALL_DIR/lib \
    $QEMU -plugin $PLUGIN \
    -E LD_LIBRARY_PATH=$INSTALL_DIR/x86_64/lib/x86_64-LoreGTL:$INSTALL_DIR/x86_64/lib \
    /path/to/minizip.x86_64 -8 -o /tmp/archive.zip /path/to/some/file
```

In both cases `LORELEI_ROOT` makes the host runtime read the installed `share/lorelei/ThunkDB.json` (which lists the thunk) and find the HTL under `lib/<host-arch>-LoreHTL`, while `LORELEI_GUEST_ROOT` locates the GTL under `lib/x86_64-LoreGTL`. The QEMU process loads the host runtime from `LD_LIBRARY_PATH`, while the guest program loads the GTL and the guest runtime from the path passed through with `-E`.

## Adding a Thunk

`src/thunks/zlib` is the smallest worked example. The short version is below. For the full guide (proc descriptors, the proc phases, and how to override them) see [docs/HowToAddAThunk.md](docs/HowToAddAThunk.md). To add a library `<lib>`:

1. Create the directory `src/thunks/<lib>/`.
2. Write `Desc.h`: include the library's headers and `<lorelei/ThunkInterface/Proc.h>` / `<lorelei/ThunkInterface/PassTags.h>`, then declare any per-proc pass descriptors (`ProcFnDesc` / `ProcCbDesc`, for example to route a variadic function through the printf pass).
3. Write the symbol list `Symbols.conf`: the functions and callbacks to thunk. It usually just does `include "Symbols_autogen.conf"` and adds a `[Guest Function]` section for any guest symbols the host needs to call back into.
4. Write `Manifest_guest.cpp` and `Manifest_host.cpp`: each includes `Desc.h` and then `<lorelei/ThunkInterface/ManifestGuest.cpp.inc>` or `ManifestHost.cpp.inc`. Put any hand-written `ProcFn` / `ProcCb` overrides here.
5. Write `CMakeLists.txt`: `project(<libname>)`, `include("../AddThunk.cmake")`, set the convention variables (`GTL_ALIAS`, `*_EXTRA_LINKS`, `*_EXTRA_INCLUDES`, ...), then call `add_thunk()`. See the header of `src/thunks/AddThunk.cmake` for the full list.
6. Add `<lib>` to the `_thunks_stable` list in `src/thunks/CMakeLists.txt` (or `_thunks_experimental` while it is still work in progress).

## Dependencies

- lorelei (https://github.com/rover2024/lorelei)
- qmsetup (https://github.com/stdware/qmsetup)
