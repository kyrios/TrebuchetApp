# DXMT: copy full texture rows when SysMemPitch is short

## What it does

In D3D11, `D3D11_SUBRESOURCE_DATA::SysMemPitch` and `SysMemSlicePitch` are the distance between rows and slices. They are not the length of a row. Every row is still width × bytes-per-texel long.

DXMT v0.72's `ResourceInitializer::initWithData` copied at most `SysMemPitch` bytes per row (2D textures and arrays) and at most `SysMemSlicePitch` bytes per slice (3D textures). When an application passes a pitch smaller than a row, DXMT uploads only part of each row, and the rest of the texture keeps stale data.

Age of Empires II: DE hits this. Its menu interface creates 256×1 B8G8R8A8 gradient textures with `SysMemPitch = 256`, which is the width, not width × 4. DXMT uploads texels 0 to 63 only, and the menu button labels come out garbled. wined3d, D3DMetal and DXVK copy the full row.

The patch copies the full row and the full slice every time, and keeps the pitch only as the source stride. That is what the 1D path in DXMT already does. Two lines change.

## Measured result

Test machine: Mac Studio M2 Max, macOS 27.2, CrossOver 26.3.0, game build 101.103.57257.0.

A small windowless test program creates textures with initial data and reads them back through a staging copy. Texels that arrived, per case:

| Case | DXMT v0.72 | D3DMetal | wined3d | DXMT v0.72 with this patch |
|---|---|---|---|---|
| 256×1, pitch 1024 (= row) | 256/256 | 256/256 | 256/256 | 256/256 |
| 256×1, pitch 256 | **64/256** | 256/256 | 256/256 | 256/256 |
| 256×1, pitch 256, immutable | **64/256** | 256/256 | 256/256 | 256/256 |
| 64×1, pitch 64 | **16/64** | 64/64 | 64/64 | 64/64 |
| 256×1, pitch 0 | **0/256** | 256/256 | 256/256 | 256/256 |
| 64×4, pitch 512 (padded) | 256/256 | 256/256 | 256/256 | 256/256 |
| UpdateSubresource 256×1, pitch 256 | 256/256 | 256/256 | 256/256 | 256/256 |
| UpdateSubresource 256×1, pitch 1024 | 256/256 | 256/256 | 256/256 | 256/256 |

CrossOver 26.3.0's own DXMT gives the same numbers as upstream v0.72. In the game, the menu labels render the same as with D3DMetal once the patch is in.

We logged the pitch of every texture the game creates in the menu and in a match. Only three interface gradient textures use a short pitch. The patch changes texture creation only, not per-frame work, so we expect no frame-rate change. We have not timed that.

## How to apply

Base: DXMT v0.72, commit `3d8d2aa` (https://github.com/3Shain/dxmt).

```sh
git clone https://github.com/3Shain/dxmt && cd dxmt
git checkout 3d8d2aa
git apply ../dxmt-v0.72-initdata-full-rows.patch
```

Then build DXMT as its own README describes (meson and ninja, a mingw-w64 cross compiler, LLVM 15, and Apple's Metal toolchain). With Xcode 27's Metal toolchain, v0.72 also needs upstream commit `0606575` (a shader compile fix) to build; `git cherry-pick 0606575` before you build.

## Limits and multiplayer

- The patch only changes how texture data is uploaded at creation time. It does not touch game logic, so it has no effect on multiplayer sync.
- When `SysMemPitch` is 0 and the texture has more than one row, D3D11 does not define the result. With the patch, DXMT then reads the first row again for every row, as wined3d and D3DMetal do.
- A padded pitch (larger than a row) behaves as before.
- Tested only with DXMT v0.72, the version CrossOver 26.3.0 ships. Later DXMT versions may already fix this differently.

## Licence

DXMT v0.72 is MIT-licensed (© Feifan He). This patch is under the same MIT licence. Licence text: [`../../LICENSES/DXMT-MIT.txt`](../../LICENSES/DXMT-MIT.txt). DXMT changed to the LGPL after v0.74; this patch is for v0.72.
