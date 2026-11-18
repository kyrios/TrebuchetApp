# aoe2-mac-softfault

Faster exception delivery for **Age of Empires II: Definitive Edition** under CrossOver on Apple Silicon.

Since the game patch of 2 June 2026, AoE2 DE runs very slowly in CrossOver, especially with many units on screen or selected. This repository contains a CrossOver 26.3 `ntdll` patch that roughly doubles FPS in busy scenes. It is a port of the "soft-fault delivery" part of the community Age of Empires IV Rosetta patch.

> **Status: experimental.** Tested by one user on a Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, AoE2 DE 101.103.57257.0. Use it for single player and replays. Nobody has tested how the game's protection reacts online with this build. For ranked or online games, start the game normally through Steam.

## The problem

AoE2 DE's anti-tamper code uses deliberately invalid x86 instructions as traps, e.g. `0x16` (PUSH SS, invalid in 64-bit mode). The game's own vectored exception handler catches each one, decrypts the code page and continues. Per-unit overlays (health bars, selection) run through this code, so the number of exceptions grows with the number of units: about 15,000 per second in a busy scene.

On Windows each exception costs a few microseconds. Under Rosetta 2 + Wine, each one goes through:
1. a hardware trap,
2. the kernel and a Mach exception message,
3. Rosetta's **single** exception-server thread,
4. a signal into Wine,
5. Wine's exception dispatch,
6. the game's handler.

We measured 20–50 µs in a minimal test and over 100 µs in the game. With 60 units selected, the main game thread spends almost the whole frame inside Rosetta.

The full analysis is in [docs/analysis.md](docs/analysis.md).

## What this patch does

- **Rosetta side:** [x87sidecar](https://github.com/NerRobDog/x87sidecar) (MIT) hooks Rosetta's x86 opcode decoder **inside the game process only**. When Rosetta meets one of the trap opcodes in the game's `.text`, it translates it as an ordinary `call` into ntdll instead of a hardware trap.
- **Wine side** (this patch, about 180 lines in CrossOver 26.3 `ntdll`):
  - A bridge page at `0x180000000` jumps to two new ntdll entry points.
  - These save all registers and XSAVE state, build the same `CONTEXT` the normal path would build, and raise the same `EXCEPTION_ILLEGAL_INSTRUCTION` through `NtRaiseException`.
  - The game's handler runs unchanged and sees the same address and registers.
- **The game's code is never modified.** Only the way Rosetta delivers the trap changes.
- **Opt-in:** the patch is active only with `AOE2_SOFTFAULT=1`, `AOELAB_SIDECAR_PATH` and `WINELOADER` set, and only for `AoE2DE_s.exe`. Otherwise the patched ntdll behaves like stock.

The AoE IV patch also contains a second part, a generated-code cache. It is **not** included here; see [docs/analysis.md](docs/analysis.md#6-what-part-b-should-do).

## Results

| | Stock CrossOver 26.3 | With this patch |
|---|---|---|
| Test program (`test/softtest.c`), cost per trap | 53.5 µs | **0.62 µs** |
| Game: SIGILL via the kernel (DTrace) | about 15,000/s | **0** |
| Game: paused busy scene, 60 units selected | about 10–12 FPS | **about 22 FPS** |
| Game: same scene, nothing selected | — | about 120 FPS |

**Exception details compared:** exception code, flags, parameters, segments, EFlags, MXCSR, XMM registers and stack alignment are identical to the stock path. `ContextFlags` additionally contains `CONTEXT_XSTATE`, as on real Windows with AVX.

**What remains:** the game's handler still toggles about 30,000–50,000 code pages per second (RWX ↔ RX). Rosetta then appears to re-translate the same code again and again. That cost is not addressed here.

## Install

Requirements:
- Apple Silicon Mac
- CrossOver 26.3 in `/Applications`, with AoE2 DE installed via Steam in a bottle named "Age of Empires II Definitive Edition" (override with `AOE2_BOTTLE`)
- Xcode command line tools and python3
- [llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases)
- bison ≥ 3 (e.g. Homebrew)
- the CrossOver 26.3.0 source tarball from <https://www.codeweavers.com/crossover/source>

```sh
CX_SOURCES=~/Downloads/crossover-sources-26.3.0.tar.gz \
LLVM_MINGW=~/Downloads/llvm-mingw-20260616-ucrt-macos-universal \
BISON_BIN=/opt/homebrew/opt/bison/bin \
./scripts/build.sh
```

```sh
./scripts/install.sh
```

What `install.sh` sets up:
- `~/Library/Application Support/aoe2-mac-softfault/SoftFault-CrossOver.app`: an APFS clone of your CrossOver with the patched ntdll. Your `/Applications/CrossOver.app` is not modified.
- The sidecar and `run-aoe2.sh` in the same folder.
- `~/Applications/AoE2 DE (Part A).app`: a launcher that Spotlight finds.

## Use

- Start **"AoE2 DE (Part A)"** from Spotlight. It starts the game directly, not through Steam's Play button.
- For A/B tests:
  - `run-aoe2.sh stock` starts the same way with unmodified CrossOver.
  - `AOE_HUD=1` shows the Metal HUD.
- Game updates: the launcher reads the `.text` range of `AoE2DE_s.exe` at every start, so no rebuild is needed.
- Safety: the launcher starts the game **without** Part A and shows a notification when:
  - the bottle was upgraded by a different CrossOver version than the one Part A was built for,
  - Steam or another Wine program is running under a different CrossOver version,
  - the game's code range can't be read,
  - the patched start fails early (bridge address taken, sidecar not starting).
- CrossOver updates: the patched copy stays on the version it was built from. To use Part A with a new CrossOver, run `build.sh` with the new source tarball and `install.sh` again. The patch may need small adjustments.
- Logs: `~/Library/Application Support/aoe2-mac-softfault/logs`. `AOE2_DRYRUN=1 run-aoe2.sh soft` runs only the checks.
- To uninstall, delete that folder and the launcher app.

## Credits and license

- **Soft-fault delivery design and code:** Marc Ibrahim (GameToMac 0.1.5-alpha), published under LGPL with his app and carried in [NerRobDog/wine-aoe4](https://github.com/NerRobDog/wine-aoe4). The decoder hook is in [NerRobDog/x87sidecar](https://github.com/NerRobDog/x87sidecar) (commit `4b6bad8`, MIT), a fork of athei/x87sidecar.
- **This repository:** the port to AoE2 DE and CrossOver 26.3, the gating, the launcher, the test program and the analysis.
- **License:** the ntdll patch is a derivative of Wine and is licensed under the **LGPL 2.1** (see `LICENSE`). Scripts, the test program and the docs are under the same license.
- Not affiliated with CodeWeavers, Microsoft, World's Edge or Forgotten Empires.
