# Rosetta 2: reclaim dead translations in small steps

## What it does

Rosetta 2 translates x86-64 code into ARM code and keeps the translations in a cache. When a program rewrites code it has already run, the old translations die. Rosetta frees them later, in one batch, every 30 to 40 seconds. During that batch it holds its global translation lock, and every thread that needs a translation waits.

A program that rewrites a lot of code makes a lot of dead translations. Age of Empires II: DE does: its copy protection rewrites code all the time. Each batch freed about 450,000 fragments and held the lock for 210 to 333 ms. The game's main thread waited behind it, and the game froze for a moment every 30 to 40 seconds.

This patch to x87sidecar gives every reclaim pass a time budget. When the budget runs out, the pass stops, and the next pass continues where it stopped. The total work stays the same; it is spread out in small steps.

x87sidecar already attaches to the game process to extend Rosetta. The patch adds three branches in Rosetta's runtime, in that process only, plus a small stub in unused padding of the runtime's code. It does not touch the program's code or memory, and it does not change the Rosetta files on disk.

Nothing here is specific to Age of Empires II. Any x86-64 program under x87sidecar that rewrites code often should see the same effect.

## Measured result

Test machine: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0, offline replays. Budget 2 ms per pass. The waits were measured with a lock-wait trace of the main thread on a diagnostic build; these are not frame-rate readings.

| | Stock Rosetta | With the budget |
|---|---|---|
| Lock hold per reclaim pass (calm scene) | 245 ms | 2.4 ms |
| Main thread's longest wait, replays of two recorded multiplayer team fights | 148–229 ms | 4.31 ms and 3.99 ms |
| Main-thread stalls of 50 ms or more in those replays | one every 30–40 s | 0 |
| Total reclaim work (calm scene) | 6.6 ms per second | 6.6 ms per second |

Start-up time in the calm pair was 27.0 s and 26.5 s, about the same. The frame rate stays the same. The freezes go.

## How to apply

Base: x87sidecar commit `c407ddf` (https://github.com/NerRobDog/x87sidecar).

```sh
git clone https://github.com/NerRobDog/x87sidecar && cd x87sidecar
git checkout c407ddf
git apply ../x87sidecar-c407ddf-reclaim-budget.patch
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --target x87sidecar
```

The budget is off unless you set it. Set these for the process that x87sidecar starts:

- `AOE_RECLAIM_BUDGET_US=2000`: time budget per reclaim pass in microseconds (2 ms is the tested value).
- `AOE_RECLAIM_LOG=<file>` (optional): the sidecar writes one status line there, `[reclaimcap] installed: …` or `[reclaimcap] not installed: <reason>`.

`AOE_RECLAIM_TEST_MUTATE` is a test switch for the fail-closed checks. Never set it in normal use.

This patch applies on its own, and it also applies together with the translation-substitution patch in `sidecar-stack-check-rule` and `sidecar-healthbar-reorder`, in either order.

## Limits and multiplayer

- Tied to the Rosetta runtime of macOS 27.2 (`/usr/libexec/rosetta/runtime`, SHA-256 `5d0e8f9a10093a8af1fbae31b59917be2ad1b248c4a71bf570982ba5966c41c4`).
- It fails closed. The sidecar finds every patch site by instruction signature, checks that the runtime file is the one loaded in the process (LC_UUID), checks that the code in memory equals the file, and writes all three branches or none. If any check fails, it logs `not installed` and Rosetta reclaims as before.
- After a macOS update, the signatures may no longer match. The patch then stays off until someone checks the new runtime.
- No root, no sudo, no change to System Integrity Protection, no Developer Mode.
- Multiplayer: the patch changes only when Rosetta frees its own memory, not what the program computes. Replay checksums matched in both team-fight replays with no desync. We have not tested live matches.

## Licence

x87sidecar is MIT-licensed. This patch is under the same MIT licence. Licence text: [`../../LICENSES/x87sidecar-MIT.txt`](../../LICENSES/x87sidecar-MIT.txt).
