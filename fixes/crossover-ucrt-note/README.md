# CrossOver: the bottle loads a 2015 pre-release C runtime

## What it does

This is a note, not a patch.

In our CrossOver 26.3.0 bottle for Age of Empires II: DE (from Steam, with the Visual C++ 2015 runtime package installed), `drive_c/windows/system32/ucrtbase.dll` is Microsoft's Universal C Runtime **10.0.10137.0**, a 2015 pre-release build. The bottle also has the DLL override `ucrtbase = native, builtin`, so every program in the bottle loads that file. Windows players get the runtime of their Windows version (10.0.19041 or later).

A current copy, **10.0.22000.194**, is already in the same bottle as the app-local copy of .NET 6. The override makes programs load the old one instead.

A freshly created CrossOver 26.3 bottle does not: it uses CrossOver's builtin `ucrtbase`, has no override, and runs the game fine (see the M1 Pro measurement below).

## Measured result

Test machine: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0. Test programs run in a copy of the bottle, at the call shapes the game uses:

| Function | 10.0.10137.0 | 10.0.22000.194 |
|---|---|---|
| `strcmp` | 8.9 ns | 3.8 ns |
| `vsnprintf` | 180 ns | 100 ns |
| `cosf` | 19 ns | 9 ns |
| `tolower` | 3.4 ns per char | 4.7 ns per char |

Results:

- `sinf`, `cosf`, `tanf` and `modff` give bit-identical results in both versions for all 2³² float inputs.
- `printf` with `%f`, `%g`, `%.9g`, `%.17g`, `%e` and `%.3f` gives identical output over 12 million values.
- Parsing: 10137 has the known pre-release rounding bug in `strtof`/`strtod`. Some long or near-halfway decimal strings come out 1 ulp off. 22000.194 rounds them correctly. The game's own 63,740 number literals in its data, and those of the 14 mods we checked, parse identically in both.

What the newer runtime would mean for the game's frame rate is an **estimate**: about 3 % of the main thread's time, or 0.05–0.09 ms per frame in one scene. The in-game measurement below found no clear difference.

### M1 Pro / CrossOver 26.3 in-game measurement

Some macOS guides tell you to put a "patched" `ucrtbase.dll` (the 2015 pre-release runtime) into `system32` and to set `ucrtbase` and `concrt140` to `native, builtin`. We measured what that does in the game.

**Method.** MacBook Pro M1 Pro, macOS 26.7.3, CrossOver 26.3.0, game build 101.103.57257.0, 1366×768 window, 60 Hz, Mac left idle. One recorded multiplayer replay, paused or playing at 32:30, 40 units in the box selection. Four windows: paused with nothing selected (30 s), paused with the box selected (30 s), playing with nothing selected (60 s), playing with the box selected (60 s). FPS from the Metal HUD. Each arm runs in its own APFS clone of a bottle that has Microsoft's Visual C++ 14.51 runtime installed natively, as a bottle set up by such a guide has. For every arm we checked which `ucrtbase.dll` the game actually mapped (`lsof`). Arms interleaved; 12 measured arms, 2 per setup (4 for one setup, where 2 windows were invalid: the game stopped presenting).

Setups:

- **builtin**: no `ucrtbase` step, CrossOver's builtin runtime.
- **10137**: the guides' step, Microsoft's `ucrtbase` 10.0.10137.0, loaded natively.
- **22000**: Microsoft's `ucrtbase` 10.0.22000.194, loaded natively.

Each setup with plain CrossOver 26.3 and DXVK (as the guides use it), and through Trebuchet 2.2.1.

Mean FPS (frames of 150 ms or longer per arm in brackets):

| Window | builtin | 10137 | 22000 | Trebuchet, builtin | Trebuchet, 10137 | Trebuchet, 22000 |
|---|---|---|---|---|---|---|
| Paused, nothing selected | 72.2 (0, 1) | 69.5 (1, 0) | 76.0 (0, 0, 0, 0) | 96.1 (0, 0) | 90.7 (0, 0) | 98.7 (0, 0) |
| Paused, box selected | 11.5 (6, 1) | 10.4 (4, 3) | 11.7 (4, 4, 1, 6) | 88.5 (0, 0) | 86.9 (0, 0) | 91.5 (0, 0) |
| Playing, nothing selected | 9.7 (10, 36) | 13.3 (33, 32) | 11.6 (41, 39, 4, 39) | 84.9 (0, 0) | 84.8 (0, 0) | 87.0 (0, 0) |
| Playing, box selected | 21.2 (8, 9) | 15.4 (11, 2) | 23.2 (3, 6) | 114.8 (0, 0) | 116.5 (0, 0) | 114.8 (0, 0) |

Longest frame: plain CrossOver up to 11.8 s, Trebuchet up to 118 ms.

Results:

- The `ucrtbase` step does not make the game faster. Plain CrossOver is about as slow with every runtime; the spread between arms of the same setup is as large as the differences between setups.
- Every plain CrossOver window had frames of 150 ms or longer, with any runtime. Trebuchet had none, with any runtime.
- In a bottle **without** a native Visual C++ runtime (a fresh CrossOver 26.3 bottle), the native 10137 `ucrtbase` starts the game and shows the menu, but **the replay does not load** (3 of 3 tries; the same bottle without the step loads it).
- A fresh CrossOver 26.3 bottle with no `ucrtbase`/`concrt140` overrides runs the game fine.
- Not yet done: a full-replay sync check with each runtime.
- We did not test the DLL from the download site these guides link to; we used Microsoft's own signed 10.0.10137.0 file from a CrossOver bottle.

## How to apply

There is no patch. The clean fix belongs in CrossOver: the vcrun2015 package (or the bottle template) could install a current runtime, or not override `ucrtbase` with the 2015 pre-release build.

If you want to try the newer runtime in your own bottle:

1. Quit every program in the bottle, Steam included.
2. Back up `drive_c/windows/system32/ucrtbase.dll` and note its SHA-256.
3. Copy the 10.0.22000.194 `ucrtbase.dll` that is already in your bottle over it.
4. To undo, copy the backup back and check its SHA-256.

Use only the Microsoft copy that is already in your bottle, or Microsoft's own installer. Do not download the DLL from elsewhere.

## Limits and multiplayer

- A CrossOver or .NET reinstall may put 10137 back or remove the 22000 copy.
- Multiplayer: the game uses lockstep simulation, so all players must compute the same numbers. The base game's data parses the same in both runtimes. A mod or scenario with a number that 10137 parses 1 ulp off could make a Mac player on 10137 compute something different from Windows players, who all have a current runtime. That is a risk of the stock bottle, not of the swap. We have not seen such a desync, and we have not tested 22000 in live matches.

## Licence

This page has no code. The `ucrtbase.dll` files are Microsoft's; we do not redistribute them.
