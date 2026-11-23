# Wine (CrossOver 26.3.0): fast exception delivery for Age of Empires II: DE

## What it does

Since the 2 June 2026 patch, Age of Empires II: DE raises about 15,000 processor exceptions per second in a busy scene and handles each one itself. On Windows that is cheap. On an Apple Silicon Mac under Rosetta 2 and Wine, every exception goes through the macOS kernel, Rosetta's exception handling and Wine's signal path. In a test program that cost 53.5 µs per exception.

This patch is a port of the AoE IV community patch in [wine-aoe4](https://github.com/NerRobDog/wine-aoe4) (soft-fault delivery, designed by GameToMac). It works with x87sidecar, which extends Rosetta's translator:

1. x87sidecar tells Rosetta to translate each faulting instruction in the game's code into a direct call into Wine's `ntdll`.
2. `ntdll` builds the same exception record and the same register and processor state the kernel path would build, and raises it with `NtRaiseException`.
3. The game's own exception handler runs, unchanged.

The kernel and Rosetta's exception server are no longer involved. The game's code and memory are not changed.

The patch adds the two entry points and the context builder to `ntdll`, the cooperative hand-over that lets x87sidecar attach to the Wine process, and the start-up code that launches the game under x87sidecar when you ask for it.

## Measured result

Test machine: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0, offline replays.

| | Stock CrossOver 26.3.0 | With this patch |
|---|---|---|
| Cost per exception (test program) | 53.5 µs | 0.62 µs |
| Exceptions on the slow kernel path, busy scene (counted with DTrace) | about 15,000 per second | 0 |
| Frame rate, 60 units selected, paused (Metal HUD reading) | 10–12 FPS | 22 FPS |

We compared what the game's handler receives field by field: the exception record, all registers and the processor state are the same. The one addition is the AVX state flag in the context, which Windows also sets.

## How to apply

Base: the CrossOver 26.3.0 source tarball, `crossover-sources-26.3.0.tar.gz` from https://www.codeweavers.com/crossover/source (SHA-256 `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`).

```sh
mkdir work && cd work
tar -xzf ../crossover-sources-26.3.0.tar.gz sources/wine
(cd sources/wine && patch -p1 < ../../../crossover-26.3.0-ntdll-fast-exception-delivery.patch)
```

Build `ntdll` only, with an x86-64 compiler from Xcode, an llvm-mingw toolchain on `PATH` and bison 3 or newer:

```sh
mkdir build && cd build
CC="$(xcrun -f clang) -arch x86_64 -isysroot $(xcrun --show-sdk-path)" ../sources/wine/configure \
  --host=x86_64-apple-darwin --enable-win64 --without-x --without-vulkan \
  --without-gstreamer --without-freetype
make dlls/ntdll/all
install_name_tool -add_rpath @loader_path/../../../lib64 dlls/ntdll/ntdll.so
```

Use the resulting `dlls/ntdll/ntdll.so` and `dlls/ntdll/x86_64-windows/ntdll.dll` in place of the two `ntdll` files in a copy of CrossOver 26.3.0. Do not change the installed CrossOver app.

You also need x87sidecar at commit `c407ddf` (https://github.com/NerRobDog/x87sidecar). That commit already has the decoder hook this patch relies on; no x87sidecar patch is needed for this fix.

The fast path is off unless you set these variables when you start the game:

- `AOE2_SOFTFAULT=1`
- `AOELAB_SIDECAR_PATH=<absolute path to x87sidecar>`
- `WINELOADER` must be set (CrossOver sets it).

The start-up code acts only when the program is `AoE2DE_s.exe`. It uses the start and end of that program's `.text` section in build 101.103.57257.0 by default. For another game build, set `AOE_SOFTFAULT_PC` and `AOE_SOFTFAULT_END` to the new section bounds.

## Limits and multiplayer

- Tied to CrossOver 26.3.0. A newer CrossOver needs a rebuild from its own source tarball, and the patch may need small changes.
- x86-64 only, macOS only.
- Only the game's own exceptions inside its `.text` range take the fast path. All other exceptions go the normal way.
- Multiplayer: the game's handler sees the same exceptions with the same state, so the game computes the same results. Replay checksums matched in every offline run. We have not tested live matches. If you want no difference at all from a standard CrossOver setup online, leave the fast path off.

## Licence

Wine is licensed under the GNU Lesser General Public License 2.1 or later; this patch is under the same licence. The soft-fault delivery design and code come from GameToMac and are carried in [NerRobDog/wine-aoe4](https://github.com/NerRobDog/wine-aoe4) under the LGPL. An Age of Empires II: DE profile for wine-aoe4 is proposed in [wine-aoe4 pull request 1](https://github.com/NerRobDog/wine-aoe4/pull/1). Licence text: [`../../LICENSES/LGPL-2.1.txt`](../../LICENSES/LGPL-2.1.txt).
