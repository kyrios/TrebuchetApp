# AoE2 DE on Apple Silicon: what we did, what we found, where it stands

As of 2026-11-18. Mac Studio M2 Max, macOS 27.2, CrossOver 26.3, AoE2 DE build 101.103.57257.0.

This page describes the problem at the level of behaviour and cost. It deliberately leaves out how the game's copy protection works inside.

## 1. Summary

- **Cause:** since the game patch of 2 June 2026, the game's copy protection deliberately trips the processor about 15,000 times per second in a busy scene and handles each trip itself. On Windows this costs almost nothing. Under Rosetta 2 and Wine each trip is very expensive.
- **What triggers it:** the per-unit overlays (health bars, selection). Every selected or bar-carrying unit adds trips every frame, so FPS collapses with the number of units.
- **What we built (Part A):** the fast route from the community Age of Empires IV patch, ported to AoE2. Trips no longer take the slow route through macOS and Rosetta's exception thread. Slow-route trips dropped from about 15,000/s to **0**, and FPS with 60 selected units roughly doubled (about 10–12 → 22).
- **Then (section 6):** the remaining cost was Rosetta re-translating code, not Wine. The trips that grow with the number of health bars all come from one small game function behind every health bar. Showing Rosetta that function with its two checks swapped (game memory untouched) took 37 selected units from 22 to **150 FPS**.

## 2. What we did, in order

| Step | Result |
|---|---|
| In-game benchmark, backends, settings | 853–986 instead of about 1200 in February. DXVK/DXMT/D3DMetal, frame cap, vsync, presets and CrossOver 25 vs 26 make no difference |
| System tracing (`top`, DTrace) | About 15,000 trips per second through macOS's exception path in a busy scene, plus very frequent code-page changes that Rosetta has to follow |
| Wine exception trace | About 1.27 million such trips while the menu loads, all handled inside the game |
| Microbenchmarks | One trip round trip costs 20–50 µs under Rosetta/Wine. About 80 % of that is Rosetta/macOS, about 20 % Wine |
| Paused replay scenes | The 3D scene is cheap (about 7 ms). Modern health bars: 49 ms. Selected units: about 1.4 ms per unit per frame |
| D3DMetal comparison, HUD | Same per-unit cost; only 324 draw calls and 3 ms GPU. The graphics are not the cause |
| Per-thread sampling | Main thread: about 11 extra trips per selected unit per frame. With a selection the thread is almost 100 % inside Rosetta's runtime, and Rosetta's exception thread is permanently busy |
| Workaround | Classic health bars: benchmark 1270 (above February). Does not help with large selections |
| CodeWeavers ticket | Sent |
| Internet research | CodeWeavers forum: many users since 2 June 2026; CodeWeavers is "aware and working on it". The same slowdown in AoE IV was fixed by a community Wine patch |
| Part A built and tested | See section 4 |

## 3. Why it is so slow on the Mac

- **The detour:** on Windows a trip goes straight to the game's handler. Under Rosetta and Wine it goes through Rosetta, the macOS kernel, a message to Rosetta's single exception thread, a signal into Wine, Wine's exception dispatch, and only then to the game. Measured at 20–50 µs in a minimal test and more than 100 µs in the game. All of the game's threads queue on the one exception thread.
- **Re-translation:** Rosetta translates Intel code into Arm code ahead of time. The protected code changes some of the game's code while it runs, and each change makes Rosetta discard and re-translate the affected page.
- **Why units matter:** the overlay code for each unit runs through protected parts of the game. More units with bars or a selection means more trips and more re-translation per frame.

## 4. Part A: the fast route (built and in use)

**Origin:** the AoE IV patch by Marc Ibrahim (GameToMac), published as source by NerRobDog. Wine parts LGPL, sidecar MIT.

**How it works:**
- **Rosetta side:** a helper (x87sidecar) hooks into Rosetta's translator inside the game process only. When Rosetta translates one of the game's deliberate trips, it turns it into a direct call into Wine instead of a hardware fault.
- **Wine side (`ntdll`):** that call builds exactly the same exception, with the same registers and processor state, that the slow route would have delivered, and hands it to the game's own handler.
- The game's handler runs unchanged and sees exactly what it would see on the slow route. The game's code and memory are not modified; the protection runs every check as designed.

**Results:**

| | Stock CrossOver | Part A |
|---|---|---|
| Test program, cost per trip | 53.5 µs | **0.62 µs** |
| Game: trips taking the slow route | about 15,000/s | **0** |
| Game: FPS with 60 selected units (in-game HUD) | about 10–12 | **about 22** |
| Game: FPS with nothing selected | — | about 120 |

**What the handler sees, compared field by field:** identical, except that the context also declares the AVX state, as real Windows does.

**What it is made of:** about 180 lines in CrossOver 26.3's `ntdll` (`patches/` in this repository) plus the x87sidecar.

## 5. What we did not build

The AoE IV patch has a second part that runs some of the game's code from a different place in memory and hides that from the game. It gave AoE IV a further few FPS on top of Part A. We left it out on purpose: it changes what the game's copy protection can see, which was the boundary for this work from the start, and it depends on internal details that any game update can break.

A clean alternative would be the same effect inside Rosetta itself: when code is changed back to something Rosetta has already translated, reuse the old translation. That needs Apple.

## 6. After Part A: where the rest went

Measured 2026-11-18 with an instrumented ntdll and DTrace.

- **Not Wine.** In the paused scene the game asks Wine to change code-page protection only once every few seconds.
- **Rosetta's self-modifying-code handling.** Rosetta guards every page it has translated. When the game changes a byte on such a page, Rosetta drops all translations on that page and translates it again on the next run. About 21 µs per change plus about 0.7 µs per re-translated block (test program).
- **Where:** with nothing selected, most of this cost is constant and independent of what is on screen. With 37 units selected, one hot page dominates, at about 8,000 re-translations per second, roughly 100 µs each, which matches the 22 FPS.
- **Which function:** a small game function that every health bar on screen calls about ten times per frame. It answers "is this graphics option on?" with two checks: an expensive protected check first, then a cheap settings read. (GameToMac's AoE II build found the same function.)
- **Which display element calls it:** the health bar drawn on screen. Selected units scrolled off screen cost nothing; houses, villagers and soldiers cost the same per bar; health bars on "always show" cost as much with nothing selected. No game setting turns the bars off.
- **Fix used:** the translation-time reorder (README, "The health-bar speed-up"): Rosetta sees the cheap check first. Same result for every input; when the setting is on, the protected check still runs and decides.

| Paused replay, classic bars | Part A only | Part A + reorder |
|---|---|---|
| Nothing selected | 100–120 FPS | 150 FPS |
| 37 units selected | 22 FPS | 150 FPS |
| Bars "always show", 150 units on screen | about 20 FPS | 90 FPS |

Tried and not used: changing how Wine handles page-protection calls (the game hardly makes them), and keeping Rosetta's translations of the hot page alive (worked in a test program, not in the game).

## 7. Current state

| Item | State |
|---|---|
| Recommended setup | Part A + health-bar speed-up (installer default). Not tested online; try unranked lobbies first |
| Official fix | Reported to CodeWeavers |
| Native alternative | AoE2 DE has a native Apple Silicon version since 28 May 2026 (Feral). Its announcement mentions Mac multiplayer only |
| Open work | Online test; the constant re-translation that remains after the reorder |

## 8. Sources

- CodeWeavers forum, "Major stuttering – Unplayable": https://www.codeweavers.com/compatibility/crossover/forum/age-of-empires-ii-definitive-edition?msg=353618
- Age of Empires forum, "BUG: PERFORMANCE ISSUE WRT 2026-JUNE-02 PATCH": https://forums.ageofempires.com/t/bug-performance-issue-wrt-2026-june-02-patch/286862
- AoE IV Rosetta patch: https://github.com/NerRobDog/wine-aoe4, https://github.com/NerRobDog/dxmt-aoe4-pack, https://github.com/NerRobDog/x87sidecar
- Highball AoE IV integration: https://github.com/gauthierpiarrette/highball-engine/pull/49, https://github.com/himbeles/highball-engine-aoe4
