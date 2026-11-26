# Corresponding source (LGPL)

Our Wine binaries (`ntdll.so`, `ntdll.dll`, and `win32u.so` if shipped) are built from CodeWeavers' published CrossOver Wine sources plus our patches. This file names everything needed to rebuild them.

## Upstream source
- **CrossOver 26.3.0 source tarball**: `crossover-sources-26.3.0.tar.gz` from https://www.codeweavers.com/crossover/source
- SHA-256: `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872` (149054023 bytes)

## Our patches (in `patches/`, applied in this order)
1. `crossover-26.3.0-ntdll-aoe2-softfault.patch`: Part A (fast trap delivery), ntdll.
2. `crossover-26.3.0-ntdll-f59-release.patch`: the release ntdll changes on top of Part A (faster clock F59 only, 84 lines).
3. `crossover-26.3.0-ntdll-envstrip-release.patch`: removes our switch variables (AOE_, AOE2_, AOELAB_, X87_) from the game's Windows environment; only for AoE2DE_s.exe, the Unix side still reads them.
4. `crossover-26.3.0-win32u-t4.patch` (only if `win32u.so` ships): caret/cursor answered in the client (T4).
The library path (rpath) is added after the build: `install_name_tool -add_rpath @loader_path/../../../lib64 ntdll.so`.

**Running your own build:** put your `ntdll.so` (and `ntdll.dll`) into Trebuchet's CrossOver copy, `~/Library/Application Support/Trebuchet/SoftFault-CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/`, and start the game from that copy (or run `run-aoe2.sh` there with your own checks). Trebuchet's Launch button runs only the files it shipped: with a changed file it starts the game the normal CrossOver way and says why.

## Build
`scripts/build.sh` (needs the tarball above, llvm-mingw, bison ≥ 3, the Xcode command line tools). The release ntdll is built from exactly tarball + patches 1, 2 and 3 (no extra defines); the faster clock is active only when the launcher sets `AOE2_FASTQPC=1`. See `docs/` and `fixes/release-process` in the project notes.

## Other parts we ship (not LGPL)
- x87sidecar (MIT): https://github.com/NerRobDog/x87sidecar at c407ddf + `patches/x87sidecar-c407ddf-trebuchet.patch` (Part A as upstream, code substitution list, stutter fix). Built with `cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0`. Our patch adds no diagnostics; upstream's own optional debug paths stay in the build and do nothing unless their switches are set. The build is reproducible.
- DXMT v0.72 (MIT): https://github.com/3Shain/dxmt at 3d8d2aa + `patches/dxmt-v0.72-label-fix.patch`.
- Since 2.2.0, also `patches/dxmt-v0.72-captureage.patch` on top: Direct2D surfaces for CaptureAge only, SwapDeviceContextState, and the Metal library built for macOS 14. With both patches the result is the shipped d3d11.dll (sha256 4fb2e55b…).
Notices: `LICENSES/`.
