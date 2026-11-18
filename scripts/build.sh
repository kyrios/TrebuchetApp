#!/bin/zsh
# Build the patched CrossOver 26.3 ntdll and the x87sidecar.
#
# Needs:
#   CX_SOURCES   path to crossover-sources-26.3.0.tar.gz (from codeweavers.com/crossover/source)
#   LLVM_MINGW   path to an llvm-mingw toolchain (e.g. llvm-mingw-20260616-ucrt-macos-universal)
#   BISON_BIN    (optional) directory with bison >= 3 (macOS ships 2.3, which is too old)
#   Xcode command line tools, python3, git
#
# Output in $WORK (default ./work):
#   build/dlls/ntdll/ntdll.so, build/dlls/ntdll/x86_64-windows/ntdll.dll
#   sidecar/build/bin/x87sidecar
set -euo pipefail
here=${0:A:h}
WORK=${WORK:-$PWD/work}
: ${CX_SOURCES:?set CX_SOURCES to crossover-sources-26.3.0.tar.gz}
: ${LLVM_MINGW:?set LLVM_MINGW to an llvm-mingw toolchain directory}
SDK=$(xcrun --show-sdk-path)
CLANG=$(xcrun -f clang)
mkdir -p "$WORK"
cd "$WORK"

# 1. Wine source + patch
if [[ ! -d src/sources/wine ]]; then
  mkdir -p src && tar -xzf "$CX_SOURCES" -C src sources/wine
  (cd src/sources/wine && patch -p1 < "$here/../patches/crossover-26.3.0-ntdll-aoe2-softfault.patch")
fi

# 2. configure + build ntdll only
export PATH="$LLVM_MINGW/bin:${BISON_BIN:+$BISON_BIN:}$PATH"
mkdir -p build && cd build
if [[ ! -f Makefile ]]; then
  CC="$CLANG -arch x86_64 -isysroot $SDK" ../src/sources/wine/configure \
    --host=x86_64-apple-darwin --enable-win64 --without-x --without-vulkan \
    --without-gstreamer --without-freetype > configure.log 2>&1
fi
make -j"$(sysctl -n hw.ncpu)" dlls/ntdll/all > ntdll-build.log 2>&1
cd ..

# 3. x87sidecar (NerRobDog fork with the soft-fault decoder hook, MIT)
if [[ ! -d sidecar ]]; then
  git clone https://github.com/NerRobDog/x87sidecar sidecar
  git -C sidecar checkout c407ddf
fi
if ! command -v cmake >/dev/null; then
  python3 -m venv .venv && .venv/bin/pip -q install cmake && export PATH="$WORK/.venv/bin:$PATH"
fi
cmake -S sidecar -B sidecar/build -DCMAKE_OSX_ARCHITECTURES=arm64 > sidecar-config.log
cmake --build sidecar/build -j8 > sidecar-build.log
sidecar/build/bin/x87sidecar --probe | tail -1

ls -la build/dlls/ntdll/ntdll.so build/dlls/ntdll/x86_64-windows/ntdll.dll sidecar/build/bin/x87sidecar
