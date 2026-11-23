# Fixes for Age of Empires II: DE on Apple Silicon

Each folder holds one fix: a patch cut down to that fix (or a note, where there is nothing to patch) and a README with what it does, what we measured, how to apply it, its limits and its licence. Every patch applies on its own to the base named in its README.

All measurements: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0, offline replays. FPS figures are Metal HUD readings. Estimates are marked as estimates.

| Folder | Applies to | What it fixes |
|---|---|---|
| [`dxmt-initdata-row-pitch`](dxmt-initdata-row-pitch) | DXMT v0.72 (`3d8d2aa`) | Texture rows cut short when `SysMemPitch` is smaller than a row; garbled menu labels in the game |
| [`rosetta-reclaim-budget`](rosetta-reclaim-budget) | x87sidecar `c407ddf` | Freezes every 30–40 s while Rosetta frees dead translations; works for any program that rewrites code often |
| [`wine-fast-exception-delivery-aoe2`](wine-fast-exception-delivery-aoe2) | CrossOver 26.3.0 source (Wine `ntdll`) | The game's own processor exceptions take a slow path through the kernel; delivers them as a direct call instead |
| [`wine-fast-qpc`](wine-fast-qpc) | CrossOver 26.3.0 source (Wine `ntdll`) | `QueryPerformanceCounter` without a syscall; off by default |
| [`sidecar-stack-check-rule`](sidecar-stack-check-rule) | x87sidecar `c407ddf` | MSVC's `/GS` stack-cookie check shown to Rosetta in a shorter, identical form |
| [`sidecar-healthbar-reorder`](sidecar-healthbar-reorder) | x87sidecar `c407ddf` | A health-bar check shown to Rosetta with its cheap part first |
| [`crossover-settings-aoe2`](crossover-settings-aoe2) | CrossOver 26.3.0 settings | Which graphics backend, and MSync, with measurements |
| [`crossover-ucrt-note`](crossover-ucrt-note) | CrossOver bottles with vcrun2015 | The bottle loads a 2015 pre-release C runtime |

The two x87sidecar rule folders share one patch (translation-time substitution). It applies together with the reclaim-budget patch, in either order.

## Credits

- **NerRobDog**: [x87sidecar](https://github.com/NerRobDog/x87sidecar), which all the Rosetta-side fixes build on, and [wine-aoe4](https://github.com/NerRobDog/wine-aoe4), which carries the soft-fault delivery code that `wine-fast-exception-delivery-aoe2` ports.
- **3Shain**: [DXMT](https://github.com/3Shain/dxmt), the Metal-based D3D11 implementation.
- **CodeWeavers and the Wine project**: CrossOver and Wine, and the published CrossOver sources these patches apply to.
- **GameToMac**: the original soft-fault delivery design, and the idea of reordering the health-bar check.

## Licences

- Wine patches: GNU LGPL 2.1 or later, [`../LICENSES/LGPL-2.1.txt`](../LICENSES/LGPL-2.1.txt).
- DXMT v0.72 patch: MIT, [`../LICENSES/DXMT-MIT.txt`](../LICENSES/DXMT-MIT.txt).
- x87sidecar patches: MIT, [`../LICENSES/x87sidecar-MIT.txt`](../LICENSES/x87sidecar-MIT.txt).
- The two rule-finder scripts (`mk_rules.py`, `mk_reorder.py`): this repository's licence, LGPL 2.1, [`../LICENSE`](../LICENSE).

Age of Empires is a trademark of Microsoft. These fixes are not affiliated with or endorsed by Microsoft, World's Edge, Forgotten Empires, CodeWeavers or Apple.
