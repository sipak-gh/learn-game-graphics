# delve 1.0

A first-person maze game drawn by a software 3D renderer: every pixel is computed
by our own Zig code, on the CPU. [raylib](https://www.raylib.com/) only opens the
window, reads the keyboard and mouse, and shows the finished picture.

This is the final project of Part II of *Learn Game Graphics*: triangles, clipping,
a depth buffer, perspective-correct textures with mipmaps, Phong lighting with fog,
a chunked world built from a text map, visibility culling with the ray caster, and
rendering on several threads.

## Build and run

You need Zig 0.17.1. The first build downloads and compiles raylib.

```console
zig build --release=fast run              # play (the labyrinth)
zig build --release=fast run -- --map cellar
zig build --release=fast run -- --demo tour   # watch the guided tour
zig build test                             # the unit tests
zig build bench --release=fast             # time the tour without a window
```

Build with `--release=fast`: a debug build works, but runs about 10 times slower.
The binary ends up in `zig-out/bin/delve`.

## Controls

| Key | Action |
|---|---|
| W / S | walk forward / back |
| A / D | step left / right |
| Mouse | look around and up and down |
| ← / → | turn |
| ↑ / ↓ | look up / down |
| Esc | quit |

The mouse is captured while the window is open. A recorded demo (`--demo`) plays
first; when it ends, you have control.

Things to switch while playing:

| Key | Switches |
|---|---|
| Tab | the view: solid, depth, levels (mipmap levels), chunks, overdraw, overhead, raycast, wireframe, cube, map_fixed, map_follow |
| L | the lighting: unlit, flat, gouraud, phong |
| N | the texture filter: nearest, bilinear, mipmap, trilinear |
| T | textures on / off |
| H | the torch on / off |
| G | fog on / off |
| V | chunk culling: off, frustum, grid |
| R | drawing the chunks nearest first on / off |
| X | freeze visibility: walk away and see what was not drawn |
| J | drawing on several threads on / off |
| K | show the threads' bands and how long each took |
| M | the minimap |
| I | the numbers at the bottom |
| B | back-face culling on / off |
| C | near-plane clipping on / off |
| Z | the depth test on / off |
| P | perspective-correct interpolation on / off |
| F | fisheye in the ray caster view |
| O | wall corners projected over the ray caster view |

The numbers at the bottom say where the time went (visibility, world, overlays), how
many chunks and triangles were drawn or skipped, how often each pixel was covered and
shaded, and where you are.

## Command line

`delve --help` lists every option. The ones you will use most:

```console
delve --map maps/mine.txt                 # play your own map
delve --record run.txt                    # record your input...
delve --demo run.txt                      # ...and replay it, exactly
delve --threads 1 --demo tour --headless --bench
delve --headless --demo tour --frames 700 --view overhead --out shot.png
```

`--headless` renders without a window, and `--frames N` stops after N frames (one
tick of 1/60 s each), so the same command always draws the same picture.

## Maps

A map is a text file, one character per cell:

| Char | Cell |
|---|---|
| `#` | brick wall |
| `%` | stone wall |
| `.` | floor |
| `>` `v` `<` `^` | the start, facing east, south, west, north |
| `*` | a lamp |
| `o` | a barrel |

All rows must be the same length; keep walls all around the edge. See `src/maps/`.

## How it works

One frame, in `App.render`:

1. **Visibility** (`visibility.zig`): the world's chunks of 4×4 cells outside the view
   frustum are skipped, and so are those no ray through the grid reaches. The rest are
   sorted nearest first.
2. **World** (`world.zig`, `render3d.zig`, `raster.zig`): the screen is split into one
   band of rows per thread. Each band transforms and clips the visible chunks'
   triangles, then fills only its own rows: an edge-function rasterizer with a depth
   test, perspective-correct varyings, trilinear texture filtering, and per-pixel
   lighting with fog (`light.zig`, `texture.zig`).
3. **Overlays**: the crosshair, the minimap, and the numbers.

The player (`player.zig`) is a circle of radius 0.25 that slides along walls, moved in
fixed ticks of 1/60 s, which is what makes recorded demos replay exactly.

## Where to go next

Everything this renderer does by hand, a GPU does in hardware, thousands of pixels at a
time: vertex shaders transform, the rasterizer interpolates, fragment shaders light and
texture. raylib's own 3D API, OpenGL, Vulkan, WebGPU or Metal are the next step. The ideas
carry over unchanged.
