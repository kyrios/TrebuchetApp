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
  (cd src/sources/wine && for p in crossover-26.3.0-ntdll-aoe2-softfault crossover-26.3.0-ntdll-f59-release crossover-26.3.0-ntdll-envstrip-release; do
     patch -p1 < "$here/../patches/$p.patch"; done)   # Part A, then the release ntdll changes (same order as SOURCE.md)
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
#    + our translation-time substitution (AOE_SUBST_*), used for the health-bar speed-up
if [[ ! -d sidecar ]]; then
  git clone https://github.com/NerRobDog/x87sidecar sidecar
  git -C sidecar checkout c407ddf
  git -C sidecar apply "$here/../patches/x87sidecar-c407ddf-trebuchet.patch"
fi
if ! command -v cmake >/dev/null; then
  python3 -m venv .venv && .venv/bin/pip -q install cmake && export PATH="$WORK/.venv/bin:$PATH"
fi
cmake -S sidecar -B sidecar/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 > sidecar-config.log
cmake --build sidecar/build -j8 --target x87sidecar > sidecar-build.log
sidecar/build/bin/x87sidecar --probe | tail -1

ls -la build/dlls/ntdll/ntdll.so build/dlls/ntdll/x86_64-windows/ntdll.dll sidecar/build/bin/x87sidecar

# MANIFEST for install.sh: the CrossOver version these sources are for (from the tarball name, e.g.
# crossover-sources-26.3.0.tar.gz -> 26.3.0, matched as a prefix of CrossOver's build number) and the
# hashes of what was built. install.sh refuses any other CrossOver.
cxv=$(basename "$CX_SOURCES" | sed -n 's/^crossover-sources-\([0-9.]*[0-9]\)\.tar\.gz$/\1/p')
[[ -n "$cxv" ]] || { echo "cannot read the CrossOver version from $CX_SOURCES; set it in work/MANIFEST by hand"; exit 1; }
{
  print "built_for_cx $cxv"
  print "src ntdll.so $(shasum -a 256 build/dlls/ntdll/ntdll.so | cut -d' ' -f1)"
  print "src ntdll.dll $(shasum -a 256 build/dlls/ntdll/x86_64-windows/ntdll.dll | cut -d' ' -f1)"
  print "src x87sidecar $(shasum -a 256 sidecar/build/bin/x87sidecar | cut -d' ' -f1)"
} > MANIFEST
echo "MANIFEST: built for CrossOver $cxv"
