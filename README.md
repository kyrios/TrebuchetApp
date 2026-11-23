# Trebuchet

**Trebuchet. Bringing a classic to modern silicon.**

Website: [trebuchetapp.com](https://trebuchetapp.com)


Makes **Age of Empires II: Definitive Edition** fast again under CrossOver on Apple Silicon. One app: press **Launch**, or open **Settings** to switch single fixes on or off.

Since the game patch of 2 June 2026, AoE2 DE runs very slowly in CrossOver as soon as health bars are on screen (selected units, or bars always shown). In a busy paused scene with 37 units selected, FPS goes from **22 to 150** with Trebuchet. **No game file and no byte of the game's code is ever changed.**

> **Use at your own risk.** Trebuchet changes how the game runs under Rosetta. It is not affiliated with or approved by Microsoft, World's Edge, Forgotten Empires or CodeWeavers, and it comes with no warranty (see `LICENSE`). Online play could, in the worst case, put your account at risk.
>
> **Status: tested offline.** Every number below was measured (unless marked as an estimate) by one user on a Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, AoE2 DE 101.103.57257.0, in offline replays. Each release passes full-length replays to the end with the game's own out-of-sync detection silent. Multiplayer was tested in one online game by the author; try unranked lobbies first. If you want zero difference from a standard CrossOver setup online, switch the marked fixes off (see the legend below).

## Download

**[Download Trebuchet.dmg](https://github.com/kyrios/TrebuchetApp/releases/latest)**, open it and drag Trebuchet to Applications. Then start it and press **Launch**. The first Launch prepares Trebuchet for your CrossOver in a few seconds.

Requirements: Apple Silicon Mac, Rosetta, CrossOver **26.3.0**, AoE2 DE installed through Steam in a CrossOver bottle.

Your CrossOver app and your bottle are never changed: Trebuchet works from its own copy of CrossOver in `~/Library/Application Support/Trebuchet/`. To uninstall, choose **Settings → Game → Reset Trebuchet**, then move Trebuchet to the Trash. Trebuchet updates itself; it checks for a new version once a day.

Prefer the Terminal? This installs the same app:

```sh
curl -fsSL https://raw.githubusercontent.com/kyrios/TrebuchetApp/main/scripts/get.sh | zsh
```

Other CrossOver versions: build from source (see [Build from source](#build-from-source)).

## The fixes

| Fix | Default | Measured gain |
|---|---|---|
| Quick Traps ◆ | always on | 60 units selected: 10–12 → 22 FPS (Metal HUD reading) |
| Swift Health Bars ◆ | on | worst case, 37 units selected, health bars on: 22 → 150 FPS (Metal HUD reading) |
| Renderer Guard | always on | keeps the chosen graphics path |
| Metal Renderer (DXMT) | on | about 25 % less CPU per frame than wined3d, no periodic 150 ms stall |
| Clear Menu Text | on | fixes the garbled menu buttons with DXMT |
| Hitch Guard | on | freezes of 0.15–0.23 s every 30–40 s → under 5 ms |
| Fast Clock | off (optional) | about 0.6 s faster loading (estimate, not measured in the game) |
| Lean Stack Check ◆ | on | none measured yet |
| Fast Sync (MSync) | on | big-fight replay: about 4 % more frames (frame counter, 105.7 → 110.0 per second) |

◆ **Legend:** marked fixes change how a few parts of the game's code run, in ways no standard CrossOver setup does. No game file and no byte of the game's code is changed, and results are proven identical. Tested offline only. If you want zero difference from a standard CrossOver setup online, switch them off. The unmarked fixes work on Wine, DXMT or Rosetta's side.

Swift Health Bars and Lean Stack Check are tied to the game version: after a game update they don't recognise, they switch themselves off and the app tells you. Hitch Guard is tied to the macOS version of Rosetta in the same way. Each fix's ⓘ in Settings explains what it does.

## The problem

Since the 2 June 2026 patch, the game's copy protection deliberately trips the processor thousands of times per second (about 15,000 in a busy scene) and handles each trip itself. The code behind per-unit overlays (health bars, selection) runs through protected parts of the game, so the number of trips grows with the number of units on screen.

On a Windows PC a trip costs a few microseconds. On an Apple Silicon Mac, where Rosetta 2 translates the game's Intel code, every trip took a long detour: out of the game, through macOS and Rosetta's single exception-handling thread, through Wine, and back to the game. We measured 20–50 µs per trip in a minimal test and over 100 µs in the game. With 60 units selected, the game's main thread spent almost the whole frame on that detour.

The analysis, at the same level, is in [docs/analysis.md](docs/analysis.md).

## How it works

- Trebuchet starts the game in its **own copy of CrossOver**, with a patched part of Wine (`ntdll`), a Rosetta helper (x87sidecar) and the Metal renderer DXMT. Your CrossOver app and your bottle stay as they are.
- **Quick Traps** shortens the route that the game's own checks take through Rosetta and Wine on a Mac. The game's handler gets exactly the same information as on the normal route; only the detour through macOS is gone.
- **Swift Health Bars** has Rosetta translate one small game function with its two checks in the cheaper order. Every answer is the same; the game's memory keeps its original bytes. After a game update it finds the function again, or switches itself off and tells you.
- **The game's code and memory are never modified**, and every check in the game runs as designed.
- Each fix's ⓘ in Settings explains what it does. The full analysis is in [docs/analysis.md](docs/analysis.md), and every patch is in [`patches/`](patches/) with build steps in [SOURCE.md](SOURCE.md).

## Results

| | Stock CrossOver 26.3 | With this patch |
|---|---|---|
| Test program (`test/softtest.c`), cost per trip | 53.5 µs | **0.62 µs** |
| Game: trips taking the slow route through macOS | about 15,000/s | **0** |
| Game: paused busy scene, 60 units selected | about 10–12 FPS | about 22 FPS |
| Game: same scene, nothing selected | — | about 120 FPS |

With the health-bar speed-up (same paused replay, classic health bars, Metal HUD):

| | Quick Traps only | Quick Traps + Swift Health Bars |
|---|---|---|
| Nothing selected | 100–120 FPS | **150 FPS** |
| 37 units selected | 22 FPS | **150 FPS** |
| Health bars "always show", 150 units on screen | about 20 FPS | **90 FPS** |

**What the game's handler sees:** the same exception, registers and processor state as on the slow route, compared field by field. The only extra is that the context also declares the AVX state, as real Windows does.

**What remains:** Rosetta still re-translates some of the game's code very often, independent of what is on screen. See [docs/analysis.md](docs/analysis.md).

## Build from source

Requirements:
- Apple Silicon Mac
- CrossOver 26.3 in `/Applications`, with AoE2 DE installed via Steam in a CrossOver bottle (found automatically; override with `AOE2_BOTTLE`)
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

What `install.sh` sets up (the app does the same on its first Launch, from the files inside it):
- `SoftFault-CrossOver.app`: an APFS clone of your CrossOver with the patched ntdll, in the install folder. Your `/Applications/CrossOver.app` is not modified.
- The sidecar, `run-aoe2.sh` and `mk_reorder.py` in the same folder.
- Run as `./scripts/install.sh`, it also puts the app into `~/Applications`; `launcher/build-app.sh` builds the app on its own.

## Use
- Start **Trebuchet** and press **Launch**. It starts the game directly, not through Steam's Play button, and skips the intro video. If the game was started some other way (for example with Steam's Play button), the app tells you it runs without the fixes.
- **Settings:** switch single fixes on or off, choose the graphics path (DXMT, D3DMetal, wined3d) and the CrossOver bottle, show the Metal HUD. "Use Trebuchet's fixes" off starts the game like Steam's Play button.
- **Fail-safe:** if CrossOver, the copy, or any of our files is not exactly the version this release was built for, the app starts AoE2 the normal CrossOver way and tells you so; it never changes `/Applications/CrossOver.app` or your bottle. Trebuchet prepares its copy only for the CrossOver build it was made for (it checks the version and the file hashes listed in `MANIFEST`).
- If Steam is not running, the app starts it first (in your normal CrossOver) and waits until you are signed in (up to 10 minutes). If Steam is in offline mode you get a notice, because multiplayer will not connect.
- **"Trebuchet would like to find devices on your local network"**: macOS may ask this once when Trebuchet starts Steam. It is Steam looking for other computers for LAN games and Remote Play. Allow is fine; Don't Allow only affects LAN games and Remote Play, not online multiplayer.
- Game updates: the launcher reads the game's code range at every start, so no rebuild is needed. Version-bound fixes switch themselves off when they don't recognise the new build.
- CrossOver updates: the patched copy stays on the version it was built from. A new CrossOver needs a new release.
- Command line (for tests): `run-aoe2.sh soft|stock` in `~/Library/Application Support/Trebuchet/`; `AOE2_NO_<FIX>=1` or `AOE2_<FIX>=1` switch single fixes (`REORDER`, `F54A`, `TEXTFIX`, `T13`, `FASTQPC`, `MSYNC`); `AOE2_DRYRUN=1` runs only the checks.
- Logs: **Show Log** in the app, or `~/Library/Application Support/Trebuchet/logs`.

## Credits and license

- **Soft-fault delivery design and code:** Marc Ibrahim (GameToMac 0.1.5-alpha), published under LGPL with his app and carried in [NerRobDog/wine-aoe4](https://github.com/NerRobDog/wine-aoe4). The decoder hook is in [NerRobDog/x87sidecar](https://github.com/NerRobDog/x87sidecar) (commit `4b6bad8`, MIT), a fork of athei/x87sidecar.
- **Health-bar reorder idea and layout:** GameToMac's AoE II build (Marc Ibrahim), which patches the same function in memory. The translation-time variant, `mk_reorder.py` and the sidecar change (`patches/x87sidecar-c407ddf-trebuchet.patch`) are from this repository.
- **This repository:** the port to AoE2 DE and CrossOver 26.3, the gating, the launcher, the test programs and the analysis.
- **License:** the Wine patches are derivatives of Wine and are licensed under the **LGPL 2.1** (see `LICENSE`). The sidecar patch is under the sidecar's MIT license; DXMT is MIT. Scripts, the app, test programs and docs are under the LGPL 2.1. All licence texts are in `LICENSES/` and inside the app. How every shipped binary is built, from which source and with which patches: [SOURCE.md](SOURCE.md).
- Not affiliated with CodeWeavers, Microsoft, World's Edge or Forgotten Empires.
