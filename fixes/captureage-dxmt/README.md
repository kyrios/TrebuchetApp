# CaptureAge on DXMT

## What it does

[CaptureAge](https://captureage.com/) is the spectator and replay tool for Age of Empires II: DE. It runs next to the game and draws the game world with Direct3D 11. On top of that it draws its overlay (player panels, the minimap frame, the timeline) with Direct2D, on the same D3D11 textures. DXMT v0.72 does not support that.

The patch holds three changes:

1. **A DXGI surface on 2D textures, only inside `CaptureAge.exe`.** CaptureAge asks a D3D11 texture for its `IDXGISurface` and hands it to `ID2D1Factory::CreateDxgiSurfaceRenderTarget`. DXMT v0.72 answers `E_NOINTERFACE`. With the patch, a `Texture2D` also carries an `IDXGISurface2`, but only when the process is `CaptureAge.exe`. Every other program, the game included, gets the same answer as before.
2. **`ID3D11DeviceContext1::SwapDeviceContextState`.** Wine's `d2d1` calls it when it draws on a D3D11 device. DXMT v0.72 does not implement it.
3. **A build fix: the Metal library for macOS 14.** DXMT compiles `dxmt_command.metallib` (inside `d3d11.dll`) without a Metal target. With Xcode 27's toolchain, it is built for macOS 27 only, and Metal on macOS 26 and older cannot load it: the game crashes at start on those systems. The patch builds it for macOS 14 / Metal 3.1, as DXMT's shader converter already does. Without this change, a build made with Xcode 27 runs only on macOS 27.

The game's own output is byte-identical with and without changes 1 and 2. Our test programs read back texture uploads, executable output, text rendering and sampling, with the same results before and after.

## Measured result

- Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0: the game, then CaptureAge on a replay. CaptureAge picks up the replay and draws the game world and its overlay. In one reading, the Metal HUD in CaptureAge's view showed 51.8 FPS.
- MacBook Pro M1 Pro, macOS 26.7.3, CrossOver 26.3.0: the same test passes; the game menu and CaptureAge's view render.

Trebuchet 2.2.0 ships exactly this build: DXMT v0.72 plus the patches below give its `d3d11.dll`.

## How to apply

Base: DXMT v0.72, commit `3d8d2aa` (https://github.com/3Shain/dxmt), with upstream commit `0606575` and the patch from [`../dxmt-initdata-row-pitch`](../dxmt-initdata-row-pitch) applied first.

```sh
git clone https://github.com/3Shain/dxmt && cd dxmt
git checkout 3d8d2aa
git cherry-pick 0606575
git apply ../dxmt-initdata-row-pitch/dxmt-v0.72-initdata-full-rows.patch && git commit -qam "initdata full rows"
git am ../captureage-dxmt/dxmt-v0.72-captureage.patch
```

`git apply` or `patch -p1` work as well. Then build DXMT as its own README describes (meson and ninja, a mingw-w64 cross compiler, LLVM 15, and Apple's Metal toolchain).

## How to use it

1. Run the bottle that has the game and CaptureAge on DXMT (CrossOver 26.3.0: graphics backend DXMT), with this build's `d3d11.dll`, `dxgi.dll` and `winemetal` files in place of DXMT v0.72's.
2. Start the game.
3. Start CaptureAge with `--in-process-gpu` (next section).

**Trebuchet 2.2 does all of this for you.** If CaptureAge is installed in the game's bottle, **Launch CaptureAge** starts the game with Trebuchet's fixes, then CaptureAge with this DXMT build and the flag. It needs Clear Menu Text on (Settings > Fixes).

## Starting CaptureAge under CrossOver: `--in-process-gpu`

The patch fixes the drawing. CaptureAge also needs one launch flag. CaptureAge is an Electron app, and Chromium's separate GPU process cannot create a surface on a window that belongs to another Wine process. Without the flag, the window crash-loops before the interface appears. Start CaptureAge with `--in-process-gpu`; nothing else needs changing. `--disable-gpu` also starts, but the window stays white.

CaptureAge updates itself at start and then restarts without the flag. Trebuchet's [`scripts/run-captureage.sh`](../../scripts/run-captureage.sh) watches for that and starts it again with the flag. It does not change or redistribute CaptureAge; install CaptureAge yourself.

## Limits and multiplayer

- CaptureAge reads the game; it does not play. The patch changes nothing in the game's process (change 1 is limited to `CaptureAge.exe`), so it has no effect on multiplayer sync.
- Tested with DXMT v0.72 only, the version CrossOver 26.3.0 ships, and only with the game running on DXMT.
- Tested on macOS 26 and macOS 27. The macOS 14 Metal target is what the build asks for; we have not run it on macOS 14 or 15.

## Licence

DXMT v0.72 is MIT-licensed (© Feifan He). This patch is under the same MIT licence. Licence text: [`../../LICENSES/DXMT-MIT.txt`](../../LICENSES/DXMT-MIT.txt). DXMT changed to the LGPL after v0.74; this patch is for v0.72.
