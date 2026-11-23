# Wine (CrossOver 26.3.0): QueryPerformanceCounter without a syscall

## What it does

In Wine, `RtlQueryPerformanceCounter` (and with it `QueryPerformanceCounter`) enters the full syscall dispatcher to reach a Unix function, `monotonic_counter()`, that reads the Mac's clock. The syscall frame costs more than the clock read.

With this patch, the Windows side of `ntdll` asks the Unix side once for the address of a small function that calls `monotonic_counter()`, and from then on calls it directly with the System V calling convention. It is the same function `NtQueryPerformanceCounter` uses, so both paths return the same clock and the same frequency.

The fast path is off unless the variable `AOE2_FASTQPC=1` is set. Without it, `ntdll` behaves as in stock CrossOver.

## Measured result

Test machine: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0.

- Cost per `QueryPerformanceCounter` call, test program: 80.8 ns stock, 26.2 ns with the patch. A second run on the release build: 82.3 ns and 26.9 ns.
- Ordering, test program: 0 order violations in 10 million interleaved triples of reads; same frequency as the stock path.

What that means for Age of Empires II: DE is an **estimate**, not measured in the game. Loading is one busy main thread, and about 12 % of its time goes to clock reads, so loading should get about 0.6 s faster. During play the game reads the clock about 2,200 times per frame in one replay, which would save about 0.12 ms per frame there and close to nothing in another.

## How to apply

Base: the CrossOver 26.3.0 source tarball, `crossover-sources-26.3.0.tar.gz` from https://www.codeweavers.com/crossover/source (SHA-256 `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`).

There are two versions of the same change:

- `crossover-26.3.0-ntdll-fast-qpc.patch` applies to the stock tarball on its own.
- `crossover-26.3.0-ntdll-fast-qpc-after-fast-exception-delivery.patch` applies after the patch in [`../wine-fast-exception-delivery-aoe2`](../wine-fast-exception-delivery-aoe2). This is the version we built and tested.

```sh
mkdir work && cd work
tar -xzf ../crossover-sources-26.3.0.tar.gz sources/wine
(cd sources/wine && patch -p1 < ../../../crossover-26.3.0-ntdll-fast-qpc.patch)
mkdir build && cd build
CC="$(xcrun -f clang) -arch x86_64 -isysroot $(xcrun --show-sdk-path)" ../sources/wine/configure \
  --host=x86_64-apple-darwin --enable-win64 --without-x --without-vulkan \
  --without-gstreamer --without-freetype
make dlls/ntdll/all
install_name_tool -add_rpath @loader_path/../../../lib64 dlls/ntdll/ntdll.so
```

The build needs an x86-64 compiler from Xcode, an llvm-mingw toolchain on `PATH` and bison 3 or newer. Use the resulting `dlls/ntdll/ntdll.so` and `dlls/ntdll/x86_64-windows/ntdll.dll` in place of the two `ntdll` files in a copy of CrossOver 26.3.0, then start the program with `AOE2_FASTQPC=1`.

## Limits and multiplayer

- Off by default. It is newer and less tested than the other fixes in this folder.
- x86-64 only.
- While a thread runs the fast clock call, it runs Unix code without a syscall frame. If another thread reads that thread's register state at that instant, it sees a Unix address instead of the usual syscall stub. We did not see this happen, but we checked only one replay.
- Multiplayer: the clock values are the same as on the stock path. One offline replay played to the end with matching checksums. That is not enough to call it safe online, so leave it off for multiplayer until it has been tested there.
- Tied to CrossOver 26.3.0. A newer CrossOver needs the patch rebased: the Unix function `aoe_fastqpc_query` and the Windows-side `RtlQueryPerformanceCounter`.

## Licence

Wine is licensed under the GNU Lesser General Public License 2.1 or later; this patch is under the same licence. Licence text: [`../../LICENSES/LGPL-2.1.txt`](../../LICENSES/LGPL-2.1.txt).
