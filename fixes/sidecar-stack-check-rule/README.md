# x87sidecar: a shorter, identical stack-cookie check for Rosetta

## What it does

Programs built with Microsoft's compiler and the `/GS` option check a stack cookie on most function returns. The check is a standard compiler routine, `__security_check_cookie`, not part of any copy protection. Its hot path is six x86 instructions:

```
cmp  rcx, [rip+__security_cookie]
jne  fail
rol  rcx, 16
test cx, 0xffff
jne  fail
ret
```

Rosetta 2 translates that into 19 ARM instructions. This rule shows Rosetta's decoder an equivalent encoding of the same length:

- `rol rcx,16` (`48 c1 c1 10`) becomes `ror rcx,48` (`48 c1 c9 30`): rotating 64 bits left by 16 is the same as rotating right by 48.
- `test cx,0xffff` (`66 f7 c1 ff ff`) becomes `test cx,cx` plus a two-byte `nop` (`66 85 c9 66 90`): the same 16-bit AND, so the same flags. The rotate's flags are dead, because `test` overwrites them before anything reads them.

Rosetta then emits 16 ARM instructions instead of 19. The program's bytes and memory are never written: x87sidecar only changes what the decoder reads, and only while the live bytes at that address still equal the original bytes.

The folder has two parts:

- `x87sidecar-c407ddf-translation-substitution.patch` adds translation-time substitution to x87sidecar: a list of `address:original-bytes:new-bytes` entries in the variable `AOE_SUBST_LIST` (up to 16 entries).
- `mk_rules.py` finds the cookie check in a Windows executable by a byte pattern with wildcards, checks that the cookie lives in a writable data section and that the failure branch leads into code, and prints the list entry.

## Measured result

Test machine: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0, offline replays.

- Translated size, from Rosetta's translation dump: 19 → 16 ARM instructions per check. The rotate goes from 3 instructions to 1, the 16-bit test from 4 to 3.
- Same results, test program: 600 repetitions of 330,000 calls each, with all 65,536 values of the checked 16 bits, 200,000 random pairs and 49 edge cases, both failure paths included. The checksums of registers and flags (AF included) were identical for stock, the rule, and the case where the gate refuses the rule.
- In Age of Empires II: DE, a replay with the rule on matched the stock checksums at every one of 225 checkpoints.
- Gain in the game: an **estimate** of about 0.4 % of the main thread's time. That is too small for us to measure as frame rate.

## How to apply

Base: x87sidecar commit `c407ddf` (https://github.com/NerRobDog/x87sidecar).

```sh
git clone https://github.com/NerRobDog/x87sidecar && cd x87sidecar
git checkout c407ddf
git apply ../x87sidecar-c407ddf-translation-substitution.patch
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --target x87sidecar
```

Then, before each start, find the check and export the list:

```sh
python3 -I mk_rules.py /path/to/AoE2DE_s.exe T13
# AOE_SUBST_LIST=0x<address>:<original bytes>:<new bytes>
# RULESET <hash of mk_rules.py>
```

Set `AOE_SUBST_LIST` to the printed value for the process x87sidecar starts. If the pattern is not found exactly once, `mk_rules.py` prints a `WARN rule T13: …` line instead, and the program should run without the rule. The address and bytes depend on the program and its build.

The substitution runs inside x87sidecar's soft-fault decoder hook, so the hook must be active. For Age of Empires II: DE that means the setup in [`../wine-fast-exception-delivery-aoe2`](../wine-fast-exception-delivery-aoe2).

With `AOE_SUBST_COUNT=1` (a test switch, off by default), the sidecar counts how often each entry was applied and writes `[subst] applied: entry <i> …` lines to the file in `AOE_RECLAIM_LOG`, or to stdout.

The same substitution patch is in [`../sidecar-healthbar-reorder`](../sidecar-healthbar-reorder); both rules can share one list. The patch also applies together with [`../rosetta-reclaim-budget`](../rosetta-reclaim-budget), in either order.

## Limits and multiplayer

- Tied to the executable's build. `mk_rules.py` finds the routine by pattern, so it should survive most game updates, but a compiler change to the routine's shape needs a new pattern.
- Fails closed: if the live bytes differ from the original bytes at decode time, Rosetta decodes the stock bytes.
- The rule needs `python3`. On macOS, `/usr/bin/python3` needs the Command Line Tools.
- Multiplayer: the rule gives identical results by construction, and the test program and the replay checksums agree. We have not tested live matches. If you want no difference at all from a standard CrossOver setup online, leave it off.

## Licence

x87sidecar is MIT-licensed, and the patch is under the same MIT licence: [`../../LICENSES/x87sidecar-MIT.txt`](../../LICENSES/x87sidecar-MIT.txt). `mk_rules.py` is under this repository's licence, the LGPL 2.1: [`../../LICENSE`](../../LICENSE).
