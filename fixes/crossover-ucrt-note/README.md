# CrossOver: the bottle loads a 2015 pre-release C runtime

## What it does

This is a note, not a patch.

In our CrossOver 26.3.0 bottle for Age of Empires II: DE (from Steam, with the Visual C++ 2015 runtime package installed), `drive_c/windows/system32/ucrtbase.dll` is Microsoft's Universal C Runtime **10.0.10137.0**, a 2015 pre-release build. The bottle also has the DLL override `ucrtbase = native, builtin`, so every program in the bottle loads that file. Windows players get the runtime of their Windows version (10.0.19041 or later).

A current copy, **10.0.22000.194**, is already in the same bottle as the app-local copy of .NET 6. The override makes programs load the old one instead.

We have not checked whether a freshly created bottle ends up the same way.

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

What the newer runtime would mean for the game's frame rate is an **estimate**: about 3 % of the main thread's time, or 0.05–0.09 ms per frame in one scene. We have not measured it in the game.

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
