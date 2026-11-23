# CrossOver 26.3.0 settings for Age of Empires II: DE

## What it does

There is no patch here. This page lists the two stock CrossOver settings we use for Age of Empires II: DE and what we measured with them:

- **Graphics: DXMT.** CrossOver can draw the game through DXVK, wined3d, D3DMetal or DXMT. DXMT draws D3D11 directly through Apple's Metal.
- **MSync (`WINEMSYNC=1`).** Wine's events, mutexes and semaphores then use Mach semaphores in shared memory, so waits and signals no longer go to the wineserver.

## Measured result

Test machine: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0, offline replays.

### Graphics backend

One replay at the 20:01 mark, 1366×768 window, single runs per backend. FPS are Metal HUD readings. Nothing captured the game window during these runs; see the note on screenshots below.

| Backend | FPS, playing with a selection | CPU time per frame | Periodic stalls seen |
|---|---|---|---|
| DXMT | 196 | 10.2 ms | about 1 per minute, ~130 ms |
| D3DMetal | 199 | 10.1 ms | none seen |
| wined3d | 168–180 | 14.1 ms | about 2 per minute, ~150 ms |
| DXVK (bottle default) | 130 | 14.6 ms | none |

The clearest difference is processor time: DXMT needs about 25–28 % less game CPU per frame than wined3d. The frame rates are single runs and too close to rank DXMT, D3DMetal and wined3d against each other. In a second set of single runs (nothing selected / box selection / playing with a selection) we read wined3d 192 / 200 / 180, DXMT 208 / 191 / 196, D3DMetal 215 / 203 / 199 and DXVK 176 / 124 / 130.

We later traced the stalls seen on DXMT and wined3d to Rosetta's reclaim pass, not to the backend. [`../rosetta-reclaim-budget`](../rosetta-reclaim-budget) removes them.

DXMT and D3DMetal use the least CPU. DXMT is open source (MIT), so it can be patched and rebuilt; D3DMetal is Apple's. DXMT v0.72 garbles the game's menu labels; [`../dxmt-initdata-row-pitch`](../dxmt-initdata-row-pitch) fixes that.

### MSync

Counted per frame on the game's main thread, one run per setting:

| | MSync off | MSync on |
|---|---|---|
| Wineserver round trips per frame | 25.3 | 11.6 |
| of which for sync objects | about 11 (separate count) | 0 |
| Time in single-object waits per frame | 0.079 ms | 0.002 ms |

Main-thread time per frame fell by 0.26 ms. Frame rate: +16 % in one idle scene, no change in two play scenes, where the main thread waits for rendering anyway. These are single runs; we do not yet claim a frame-rate gain for MSync.

### A note on screenshots

Do not take screenshots of the game window while you measure. In our tests, one window screenshot per second lowered the Metal HUD frame rate by 23–37 %, and by a different amount for each backend (wined3d 205 → 139, D3DMetal 184 → 115, DXVK 124 → 96, paused scene with a box selection). A backend comparison made that way is wrong.

## How to apply

- **Graphics:** in CrossOver, open the bottle's settings and choose DXMT as the graphics backend.
- **MSync:** turn on MSync in the bottle's settings, or start the bottle with `WINEMSYNC=1`. Every process in the bottle, Steam included, must use the same setting, so quit Steam (and the bottle's wineserver) after you change it.

## Limits and multiplayer

- Both are stock CrossOver features. Neither touches the game's code or memory.
- Graphics affects only drawing, not the game's simulation.
- MSync keeps Wine's own synchronisation rules. A replay played back with MSync on stayed in sync with no stalls. If MSync cannot start, Wine falls back to the wineserver.
- Measured on one machine with single runs, as stated above. Your Mac may differ.

## Licence

This page has no code. DXMT v0.72 is MIT-licensed ([`../../LICENSES/DXMT-MIT.txt`](../../LICENSES/DXMT-MIT.txt)); CrossOver is CodeWeavers' product, and Wine is under the LGPL 2.1 ([`../../LICENSES/LGPL-2.1.txt`](../../LICENSES/LGPL-2.1.txt)).
