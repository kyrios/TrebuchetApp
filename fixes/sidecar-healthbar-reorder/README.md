# x87sidecar: health-bar check with its cheap part first (Age of Empires II: DE)

## What it does

Every health bar in Age of Empires II: DE calls a small function about ten times per frame. The function asks whether a graphics option is on, in two parts joined by "and":

```
bool f() { return dlc_owned(8) && setting(14) == 1; }
```

The first part is expensive under Rosetta in this game build. The second part is a cheap settings read. On our test install that setting is off.

This rule shows Rosetta the same function with the two parts swapped:

```
bool f() { return setting(14) == 1 && dlc_owned(8); }
```

The answer is the same for every input, but the expensive part now runs only when the setting is on. The new code has the same length (59 bytes) and keeps the call to the first part at its original address, so that call has the same return address as before.

The game's memory keeps its original bytes. x87sidecar only changes what Rosetta's decoder reads, and only while the game's 59 bytes still equal the expected original bytes.

The idea of reordering this check comes from GameToMac.

The folder has two parts:

- `x87sidecar-c407ddf-translation-substitution.patch` adds translation-time substitution to x87sidecar (variables `AOE_SUBST_PC`, `AOE_SUBST_ORIG`, `AOE_SUBST_NEW`, or the list form `AOE_SUBST_LIST`).
- `mk_reorder.py` finds the function in `AoE2DE_s.exe` by a byte pattern and prints the three variables.

## Measured result

Test machine: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0, offline replays, paused scenes. All figures are Metal HUD readings, with the fix in [`../wine-fast-exception-delivery-aoe2`](../wine-fast-exception-delivery-aoe2) on in both columns.

| Scene | Without the rule | With the rule |
|---|---|---|
| 37 units selected, health bars on | 22 FPS | 150 FPS |
| Nothing selected | 100–120 FPS | 150 FPS |
| Health bars set to "always show", 150 units | about 20 FPS | about 90 FPS |

The first row is the worst case we found.

## How to apply

Base: x87sidecar commit `c407ddf` (https://github.com/NerRobDog/x87sidecar).

```sh
git clone https://github.com/NerRobDog/x87sidecar && cd x87sidecar
git checkout c407ddf
git apply ../x87sidecar-c407ddf-translation-substitution.patch
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --target x87sidecar
```

Before each start, find the function and export the variables:

```sh
eval "$(python3 -I mk_reorder.py exe /path/to/AoE2DE_s.exe)"
```

If the pattern is not found exactly once, `mk_reorder.py` exits with `wrapper not found exactly once`, and the game should start without the rule.

The substitution runs inside x87sidecar's soft-fault decoder hook, so that hook must be active: use the setup in [`../wine-fast-exception-delivery-aoe2`](../wine-fast-exception-delivery-aoe2).

The same patch is in [`../sidecar-stack-check-rule`](../sidecar-stack-check-rule). If you use both rules, set `AOE_SUBST_LIST` for the stack-check rule as well; the three single variables then become the first entry of the list. The patch also applies together with [`../rosetta-reclaim-budget`](../rosetta-reclaim-budget), in either order.

## Limits and multiplayer

- Tied to the game build. `mk_reorder.py` finds the function by pattern; after a game update that changes the function, the pattern no longer matches and the rule stays off.
- Fails closed: if the game's bytes differ from the expected original bytes at decode time, Rosetta decodes the stock bytes.
- No effect with the game's Enhanced/UHD graphics option on.
- Multiplayer: the function returns the same answer for every input. The expensive first part now runs only when the setting is on, so it runs less often than in the unmodified game. Replay checksums matched in every offline run. We have not tested live matches. If you want no difference at all from a standard CrossOver setup online, leave it off.

## Licence

x87sidecar is MIT-licensed, and the patch is under the same MIT licence: [`../../LICENSES/x87sidecar-MIT.txt`](../../LICENSES/x87sidecar-MIT.txt). `mk_reorder.py` is under this repository's licence, the LGPL 2.1: [`../../LICENSE`](../../LICENSE).
