# Notices

This project ships binaries built from, and patches to, the following works:

- **Wine** (as published by CodeWeavers with CrossOver 26.3.0): GNU Lesser General Public License 2.1 or later, `LGPL-2.1.txt`. Our changes to Wine (`ntdll`, `win32u`) are in `patches/`; they apply to the CrossOver 26.3.0 source tarball from https://www.codeweavers.com/crossover/source. `scripts/build.sh` rebuilds them.
- **Soft-fault delivery** design and code: Marc Ibrahim (GameToMac), published under the LGPL and carried in https://github.com/NerRobDog/wine-aoe4.
- **x87sidecar**: https://github.com/NerRobDog/x87sidecar (fork of athei/x87sidecar), MIT licence, `x87sidecar-MIT.txt`. Our changes (code substitution list, stutter fix) are in `patches/x87sidecar-c407ddf-trebuchet.patch`; it rebuilds the shipped sidecar exactly.
- **DXMT v0.72** by Feifan He: https://github.com/3Shain/dxmt, MIT licence, `DXMT-MIT.txt`. Our menu-text fix and the upstream Xcode 27 shader-compile fix (0606575) are in `patches/dxmt-v0.72-label-fix.patch`.

Not included and never redistributed: CrossOver (CodeWeavers; you use your own licensed copy, cloned on your Mac at install), Apple's D3DMetal, Microsoft's C runtime, Steam and the game.

Age of Empires is a trademark of Microsoft. This project is not affiliated with or endorsed by Microsoft, World's Edge, Forgotten Empires, CodeWeavers or Apple.
