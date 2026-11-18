# AoE2 DE on Apple Silicon: what we did, what we found, where it stands

As of 2026-11-18. Mac Studio M2 Max, macOS 27.2, CrossOver 26.3, AoE2 DE build 101.103.57257.0.

## 1. Summary

- **Cause:** since the game patch of 2 June 2026, AoE2 DE uses anti-tamper code that works with deliberately invalid instructions. These are "illegal instruction" exceptions, about 15,000 per second, which the game handles itself. On Windows this costs almost nothing. Under Rosetta 2 and Wine each exception is very expensive.
- **What triggers it:** the per-unit overlays (health bars, selection). Every selected or bar-carrying unit adds exceptions every frame. FPS therefore collapses with the number of units.
- **What we built (Part A):** the fast delivery path from the community Age of Empires IV patch, ported to AoE2. Exceptions no longer go through the kernel and Rosetta's exception server. Traps via the kernel dropped from about 15,000/s to **0**, and FPS with 60 selected units roughly doubled (about 10–12 → 22).
- **What remains:** the game's handler decrypts and re-encrypts code pages, about 30,000–50,000 times per second. Rosetta then appears to translate the same code again and again. That is what Part B of the AoE IV patch addresses. We did not build it.

## 2. What we did, in order

| Step | Result |
|---|---|
| In-game benchmark, backends, settings | 853–986 instead of about 1200 in February. DXVK/DXMT/D3DMetal, frame cap, vsync, presets and CrossOver 25 vs 26 make no difference |
| `top`, DTrace (SIP off) | about 300k Mach messages/s, about 15k SIGILL/s, 20–40k `mprotect`/s on single code pages of the game |
| Wine `+seh` trace | about 1.27 M "illegal instruction" exceptions while the menu loads, all handled by a handler inside the game (`0x142BFA4D8`) |
| Microbenchmarks (`vehbench`, `sigfloor`) | One exception round trip costs 20–50 µs under Rosetta/Wine. About 80% of that is Rosetta/macOS, about 20% Wine |
| Paused replay scenes | The 3D scene is cheap (about 7 ms). Modern health bars: 49 ms. Selected units: about 1.4 ms per unit per frame |
| D3DMetal comparison, HUD | Same per-unit cost; only 324 draw calls and 3 ms GPU. The graphics are not the cause |
| DTrace per thread, `sample` | Main thread: about 11 extra exceptions per selected unit per frame. With a selection the thread is almost 100% inside Rosetta's runtime, and Rosetta's exception-server thread is permanently busy |
| Workaround | Classic health bars: benchmark 1270 (above February). Does not help with large selections |
| CodeWeavers ticket | Sent with the full analysis |
| Internet research | CodeWeavers forum: many users since 2 June 2026. One user independently found about 21k illegal-instruction exceptions/s after the patch. CodeWeavers is "aware and working on it". The same scheme in AoE IV was fixed by a community Wine patch |
| Part A built and tested | See section 4 |

## 3. Findings in detail

### The mechanism

1. The game's protected code contains invalid instructions as traps, e.g. byte `0x16` (PUSH SS, invalid in 64-bit mode).
2. The CPU (here Rosetta) raises an exception. The game's own handler catches it, decrypts the code page (page writable → write bytes → executable again), and continues execution, partly in generated code outside the main code area.
3. Later the page is encrypted again.

### Why it is so slow on the Mac

- **Delivery:** each trap travels Rosetta → kernel → Mach exception message → Rosetta's single exception-server thread → signal → Wine → game handler. Measured at 20–50 µs in a minimal test and more than 100 µs in the game. All threads of the game queue on the one exception-server thread.
- **Re-translation:** Rosetta translates x86 code ahead of time into ARM code. When the game rewrites a code page, Rosetta has to discard and re-translate that page's translation. With tens of thousands of rewrites per second, Rosetta keeps translating the same code.

### Why units and health bars matter

The overlay code for each unit runs through protected functions. More units with bars or a selection means more traps and more page rewrites per frame.

## 4. Part A: fast exception delivery (built and in use)

**Origin:** the AoE IV patch by Marc Ibrahim (GameToMac), published as source by NerRobDog. Wine parts LGPL, sidecar MIT.

**How it works:**
- **Rosetta side:** a helper program (x87sidecar) hooks into Rosetta's instruction decoder inside the game process only. When Rosetta meets one of the trap opcodes in the game's main code area, it translates it into an ordinary call into Wine instead of a hardware trap.
- **Wine side (`ntdll`):** a small stub saves all registers, builds the exact same exception context the normal path would build, and raises the same "illegal instruction" exception.
- The game's handler runs unchanged and sees the same address and registers. The game's code is not modified. Only the way Rosetta delivers the trap changes.

**Results:**

| | Stock CrossOver | Part A |
|---|---|---|
| Test program, cost per trap | 53.5 µs | **0.62 µs** |
| Game: traps via the kernel | about 15,000/s | **0** |
| Game: FPS with 60 selected units (read from the in-game HUD) | about 10–12 | **about 22** |
| Game: FPS with nothing selected | — | about 120 |

**Handler view compared:** exception code, flags, parameters, segments, flags register, MXCSR, XMM registers and stack alignment are identical. The only difference is that the context also declares the AVX state, as real Windows does.

**What it is made of:** about 180 lines in CrossOver 26.3's `ntdll` (`patches/` in this repository) plus the x87sidecar.

## 5. What remains after Part A

| Measurement (Part A, paused scene) | Nothing selected | 60 units selected |
|---|---|---|
| SIGILL via kernel | 0 | 0 |
| `mprotect` per second | about 30,000 | about 50,000 |
| Main thread in Rosetta's runtime | — | about 100% |

The exception-server thread is still busy even without any SIGILL. The most likely remaining cost is Rosetta invalidating and re-translating the code pages the handler rewrites. Rosetta may also be handling write-protection faults on translated pages through the same server thread. This was not measured further.

## 6. What Part B should do

The AoE IV patch has a second part, a "code cache".

- **Where it starts:** after the game's handler decrypts code, the anti-tamper writes small code fragments into a ring buffer (in AoE IV a 16 MB area, located through a hard-coded internal pointer) and continues execution there. Because those fragments are rewritten constantly, Rosetta re-translates them constantly.
- **What it does:**
  - When the handler resumes at an address inside that ring, Wine disassembles the fragment, makes a relocated copy in its own, never-changing memory, and resumes execution in the copy instead.
  - Copies are kept by content, so identical fragments are translated by Rosetta only once and then reused.
  - When an exception later happens inside a copy, Wine reports the original address to the game, so the game does not see that its code is running elsewhere.
- **Measured benefit in AoE IV** (M2 Max, with Part A already active): about 55 → 59 FPS, CPU load 228% → 163%, fewer frame-time spikes. The bulk of the AoE IV improvement came from Part A.

**Why we did not build it:**
- It replaces where the protection's code runs and hides that from the game. That interferes with what the anti-tamper can observe, which was the boundary for this work from the start.
- It depends on a hard-coded internal address of the protection, so any game update can break it.
- AoE2 might behave differently. Its handler rewrites pages inside the main code area as well, and a ring-only cache would not cover those rewrites.

**A clean alternative** would be the same effect inside Rosetta itself: when a code page is rewritten with bytes Rosetta has already translated before, reuse the old translation. The game's code would keep running at its original place. That needs either Apple or deep work on Rosetta's internals.

## 7. Current state

| Item | State |
|---|---|
| Recommended setup | Part A, plus classic health bars. Single player and replays only until online behaviour is known |
| Official fix | Reported to CodeWeavers with the full analysis and this patch |
| Native alternative | AoE2 DE has a native Apple Silicon version since 28 May 2026 (Feral). Mac-only multiplayer |
| Open work | Measure whether the `mprotect` calls themselves trigger Rosetta's re-translation. A Rosetta-side translation reuse would be the larger, clean solution |

## 8. Sources

- CodeWeavers forum, "Major stuttering – Unplayable": https://www.codeweavers.com/compatibility/crossover/forum/age-of-empires-ii-definitive-edition?msg=353618
- Age of Empires forum bug report: https://forums.ageofempires.com/t/bug-performance-issue-wrt-2026-june-02-patch/286862
- AoE IV Rosetta patch: https://github.com/NerRobDog/wine-aoe4, https://github.com/NerRobDog/dxmt-aoe4-pack, https://github.com/NerRobDog/x87sidecar
- Highball AoE IV integration: https://github.com/gauthierpiarrette/highball-engine/pull/49, https://github.com/himbeles/highball-engine-aoe4
