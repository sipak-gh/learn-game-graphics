# Appendix C — delve Reference

This appendix documents the finished `delve` from Part II, the snapshot in
[`project/ch24/`](project/ch24/): 6637 lines of Zig in 27 files, with 85 tests. It covers
building and running, every command-line option and key, the views, the file formats, the
architecture, what happens in one tick and one frame, where each chapter's concepts live in the
code, the measured numbers, and how each stage maps onto a GPU. For a player's summary, see
[`project/ch24/README.md`](project/ch24/README.md).

Previous: [Appendix B — quadfall Reference](appendix-b-quadfall-reference.md). Next:
[References](REFERENCES.md).

## Build, run, test

```console
$ cd project/ch24
$ zig build --release=fast run                 # play the labyrinth
$ zig build --release=fast run -- --map cellar # arguments after -- go to delve
$ zig build --release=fast run -- --demo tour  # watch the tour, then play
$ zig build test --summary all                 # 85/85 tests
$ zig build bench --release=fast               # time the tour headless (see ch24)
$ ./zig-out/bin/delve --help
```

Debug builds are about 9–10× slower than ReleaseFast for this program (tour, 300 frames:
Debug 122.7 ms/frame on one thread vs 14.03 ReleaseFast; 25.5 vs 2.40 on 8); always say
`--release=fast`.
ReleaseFast at 640×400 runs the tour at a mean 3.31 ms/frame (~300 fps) on 8 threads and
14.94 ms (~67 fps) on one, on the 32-core build machine.

## Command-line options

```console
$ ./zig-out/bin/delve --help
delve 1.0.0
usage: delve [OPTIONS]

  --frames N         stop after N frames (each frame advances exactly one tick)
  --headless         render without opening a window
  --out FILE         save the last frame as FILE (.png or .ppm)
  --screenshot FILE  save a screenshot of the window as FILE (.png)
  --scale N          window pixels per canvas pixel (default 2)
  --pos X,Y          start at map position X,Y instead of the map's start
  --yaw DEG          start facing DEG degrees (0 east, 90 south)
  --pitch DEG        start looking DEG degrees up (negative: down), -85 to 85
  --hold F,S,T[,U]   hold forward, strafe, turn, look-up input (-1 to 1) all run long
  --press ACTION     perform ACTION (for example next_view) on the first tick
  --view NAME        start in view NAME: solid, depth, levels, chunks, overdraw,
                     overhead, raycast, wireframe, cube, map_fixed, map_follow
  --shading NAME     light the 3D views with NAME: unlit, flat, gouraud, phong
  --filter NAME      read textures with NAME: nearest, bilinear, mipmap, trilinear
  --culling NAME     skip chunks with NAME: off, frustum, grid (the default)
  --map NAME         play map NAME: labyrinth (the default), cellar, or a file
  --record FILE      save every tick's input to FILE, to replay it with --demo
  --demo NAME        replay demo NAME: tour, or a file from --record
  --threads N        draw the 3D views on N threads (default: one per core, up to 8)
  --bench            print how long the frames took, and where the time went
  -h, --help         show this help
```

Each option, and the chapter that added it:

| Option | Since | Meaning |
|---|---|---|
| `--frames N` | ch09 | stop after N frames; each frame is exactly one tick (reproducible) |
| `--headless` | ch09 | no window, no X server; render to memory |
| `--out FILE` | ch09 | save the last frame as `.png` or `.ppm` (headless) |
| `--screenshot FILE` | ch09 | save the window (raylib `TakeScreenshot`) after the last frame |
| `--scale N` | ch09 | window pixels per canvas pixel (default 2: 1280×800) |
| `--pos X,Y`, `--yaw DEG` | ch11 | start pose in map cells and degrees (0 east, 90 south) |
| `--hold F,S,T[,U]` | ch11 (4th value ch22) | hold forward, strafe, turn, look-up input all run long |
| `--press ACTION` | ch12 | fire an action on the first tick (a set: repeats fire once) |
| `--pitch DEG` | ch15 | start looking up/down (±85 from ch22; ±89 in ch15–21) |
| `--view NAME` | ch16 | start in a view (see [Views](#views)) |
| `--shading NAME` | ch19 | unlit, flat, gouraud, phong (default) |
| `--filter NAME` | ch20 | nearest, bilinear, mipmap, trilinear (default) |
| `--map NAME\|FILE` | ch21 | `labyrinth` (default from ch24), `cellar`, or a map file |
| `--record FILE` | ch22 | save every tick's input as a demo |
| `--demo NAME\|FILE` | ch22 | replay `tour` or a recorded demo; then the keyboard takes over |
| `--culling NAME` | ch23 | off, frustum, grid (default) |
| `--threads N` | ch24 | bands/threads for the 3D views (default min(cores, 8)) |
| `--bench` | ch24 | print frame-time statistics and per-stage means to stdout |
| `-h`, `--help` | ch09 | usage (ch24 prints `delve 1.0.0` first) |

Errors: a bad option prints `delve: InvalidValue` (or the error name) and the usage,
exit status 2. A bad map or demo file prints `path:line:col: error: Name` (map) or
`path:line: error: Name` (demo), like a compiler, and exits 1 (Chapters
[21](21-building-the-world.md) and [22](22-the-first-person-client.md) show real outputs).

## Keys

Movement (held): W/S forward/back, A/D strafe, mouse look (x yaw, y pitch), ←/→ turn,
↑/↓ look up/down (ch22). Esc quits (raylib's default exit key). One-shot toggles, in the
order of `input.Action`:

| Key | Action | Since |
|---|---|---|
| Tab | `next_view` | ch13 |
| F | `toggle_fisheye` (ray caster) | ch13 |
| T | `toggle_textures` | ch14 |
| M | `toggle_minimap` | ch14 |
| O | `toggle_overlay` (3D corners over the ray caster) | ch15 |
| C | `toggle_clipping` | ch17 |
| B | `toggle_culling` (back faces) | ch18 |
| Z | `toggle_depth_test` | ch18 |
| L | `next_shading` | ch19 |
| H | `toggle_torch` | ch19 |
| G | `toggle_fog` | ch19 |
| N | `next_filter` | ch20 |
| P | `toggle_perspective` | ch20 |
| I | `toggle_info` | ch22 |
| V | `next_culling` (chunks) | ch23 |
| R | `toggle_sorting` | ch23 |
| X | `toggle_freeze` | ch23 |
| J | `toggle_threads` | ch24 |
| K | `toggle_bands` | ch24 |

(ch12's `toggle_map` became `next_view` in ch13.) Every action name works with
`--press NAME`, which is how the screenshots in `images/` were made.

## Views

| View | Since | Shows |
|---|---|---|
| `solid` | ch18 | the game: the world through the polygon pipeline |
| `depth` | ch18 | the depth buffer as gray levels |
| `levels` | ch20 | the mip level each pixel reads, red (0) to magenta (6) |
| `chunks` | ch21 | each world chunk in a flat color, unlit |
| `overdraw` | ch23 | how often each pixel was covered (heat map with key) |
| `overhead` | ch23 | the world from above and behind: drawn / outside / hidden chunks, ray fan |
| `raycast` | ch13 | the ch13–14 ray caster (the reference image) |
| `wireframe` | ch16 | the visible chunks' triangles as lines |
| `cube` | ch16 | the spinning cube (ch16) and two intersecting cubes (ch18) |
| `map_fixed` | ch12 (a view from ch13) | top-down map |
| `map_follow` | ch12 (a view from ch13) | top-down map rotating with the player |

## File formats

- **Map** (`src/maps/*.txt`, ch11; files at run time from ch21): one character per cell,
  all rows the same length (`RaggedRows` otherwise). `#` brick wall, `%` stone wall, `.`
  floor, `>` `v` `<` `^` the start facing east/south/west/north (exactly one: `NoStart`,
  `TwoStarts`), `*` a lamp, `o` a barrel (both on floor). Outside the map counts as brick
  wall. CRLF line ends are accepted. Built in: `cellar` (32×24), `labyrinth` (63×63).
- **Demo** (`src/demos/tour.txt`, ch22): text. `# comment`, `map NAME`, `start X Y YAW
  PITCH` (radians), then one line per run of ticks with the same input: `COUNT forward
  strafe turn tilt look look_y [actions...]`. Floats are written with `{d}` so they read
  back bit-exactly. The tour is 281 lines, 1983 ticks (33 s).
- **OBJ** (`src/models/barrel.obj`, ch21): the subset `v x y z`, `vt u v`, `vn x y z`,
  `f a/b/c ...` (polygons fanned into triangles; 1-based and negative indices); other
  lines are skipped. Errors carry the line number.

## Architecture

Three layers, the rule of Part I kept to the end:

```text
main.zig ──── owns the loop, the canvas, the App; options, demos, bench, files
   │
   ├── platform.zig ── the only file importing raylib: window, input → Input, present
   │
   └── app.zig ─────── pure core: update(input) once per tick, render(canvas) per frame
         ├── player, map, input, demo                  (simulation)
         ├── world, visibility, maze3d, light, texture (what to draw)
         ├── render3d, clip, raster, camera, mesh      (the pipeline)
         ├── raycast, mapview, draw, font              (other views, 2D, HUD)
         └── canvas, math, image, obj, profile         (foundations)
```

The files of `project/ch24/src` (lines, tests, chapter introduced):

| File | Lines | Tests | From | Role |
|---|---|---|---|---|
| `main.zig` | 207 | 1 (refs) | ch09 | entry, loop, headless/windowed, demo ticker, bench output |
| `options.zig` | 213 | 2 | ch09 | command-line parsing |
| `platform.zig` | 128 | 0 | ch09 | raylib: window, keys, mouse, texture upload, screenshot |
| `app.zig` | 609 | 0 | ch09 | state, `update`, `render`, views, HUD, threads |
| `canvas.zig` | 106 | 3 | ch09 | `Color`, `Canvas` |
| `image.zig` | 114 | 2 | ch09 | PPM and PNG writers |
| `draw.zig` | 163 | 3 | ch10 | lines, rectangles, circles, 2D triangles |
| `font.zig` | 135 | 2 | ch10 | 5×7 bitmap font |
| `math.zig` | 382 | 9 | ch11 | `@Vector` types, `Mat4` |
| `map.zig` | 195 | 4 | ch11 | the grid, parsing, built-in maps |
| `input.zig` | 106 | 2 | ch11 | `Input`, `Action`, accumulate/take |
| `player.zig` | 210 | 5 | ch11 | movement, circle collision, pitch |
| `mapview.zig` | 111 | 0 | ch13 | top-down maps through a matrix |
| `raycast.zig` | 366 | 3 | ch13 | DDA, ray-cast renderer, `castVisiting` (ch23) |
| `texture.zig` | 384 | 5 | ch14 | procedural textures, mips, filters |
| `camera.zig` | 129 | 3 | ch15 | 3D camera, view and projection |
| `mesh.zig` | 105 | 1 | ch16 | `Vertex`, `Mesh`, the cube |
| `render3d.zig` | 725 | 9 | ch16 | `Renderer`: transform, clip, rasterize, depth, stats, bands |
| `maze3d.zig` | 119 | 0 | ch16 | shaders' paint, `drawPart`, lamps |
| `clip.zig` | 232 | 5 | ch17 | `Varyings`, planes, outcodes, Sutherland–Hodgman |
| `raster.zig` | 221 | 5 | ch18 | fixed-point edge functions, top-left rule, row ranges |
| `light.zig` | 281 | 5 | ch19 | lights, falloff, fog, `Material`, `Shader` |
| `world.zig` | 514 | 4 | ch21 | chunked world meshes, draw, overhead, the cracks and band tests |
| `obj.zig` | 197 | 3 | ch21 | OBJ parser |
| `demo.zig` | 210 | 3 | ch22 | demo format, playback, recorder |
| `visibility.zig` | 370 | 5 | ch23 | frustum, grid rays, chunk order |
| `profile.zig` | 105 | 1 | ch24 | stopwatch, stage times, bench report |

## One tick and one frame, start to finish

A **tick** (1/60 s, `main.Ticker.step` → `App.update`): the demo (if any) or the
platform supplies an `Input`; one-shot actions flip state (view, toggles); the player
turns and tilts (mouse and arrows, pitch clamped to ±85°), moves along its yaw, and
`player.collide` pushes the circle (radius 0.25) out of nearby wall cells and barrels,
so it slides along them. Windowed without `--frames`, a lag accumulator runs as many
ticks as real time asks for; with `--frames` or headless, exactly one per frame.

A **frame** (`App.render(canvas)`), for the solid view:

1. Camera from the player: `view_proj = projection · lookAt(eye, eye + forward, up)`.
2. Visibility (`Visibility.update`): each chunk's box against the six frustum planes
   (taken from `view_proj`); then the ch13 DDA rays across the view mark the grid cells
   a line of sight reaches; chunks with no seen cell are hidden. The rest are sorted
   nearest first.
3. Scene: ambient, the torch at the eye, the lamps, fog.
4. World (`drawWorld`): one `std.Io.Group` task per band of rows (8 bands of 50 rows by
   default), each running `World.draw` over all visible chunks with its own
   `Renderer.band` and `Stats`; the main thread waits, then sums the stats.
5. Per chunk part (`maze3d.drawPart` → `Renderer.drawMesh`): the lights that reach the
   part's box; each vertex to world and clip space, the shader's `vertex()` fills the
   varyings; each triangle: outcodes → trivially reject or clip (Sutherland–Hodgman) →
   divide by w → viewport → back-face test → `raster.fillTriangleRows` (only this band's
   rows) → per pixel: depth test, perspective-correct varyings, texel footprint → mip
   level, trilinear sample, Phong lighting, fog → the canvas.
6. Overlays: the crosshair, minimap, band lines (K), and the HUD lines (times, chunk and
   triangle counts, pose and settings). `main` then hands the canvas to
   `platform.Window.present` (one `UpdateTexture` + `DrawTexturePro`).

## Concept → code

| Ch | Concepts | Code |
|---|---|---|
| [9](09-framebuffers.md) | framebuffer, pixels as memory, RGBA, image files, the platform layer | `canvas.zig`, `image.zig`, `platform.zig` |
| [10](10-drawing-in-2d.md) | Bresenham lines, rectangles, circles, edge-function triangles, bitmap text | `draw.zig`, `font.zig` |
| [11](11-vectors.md) | vectors, dot/cross, grid maps, movement and collision | `math.zig`, `map.zig`, `player.zig`, `input.zig` |
| [12](12-matrices-and-transforms.md) | matrices, transforms, composition, the inverse | `math.Mat4`, `mapview.zig` |
| [13](13-ray-casting.md) | ray casting, DDA, perpendicular distance, fisheye | `raycast.zig` |
| [14](14-textures-and-sprites.md) | texture coordinates on walls, floor casting, sprites, mouse look | `texture.zig`, `raycast.zig` |
| [15](15-cameras-and-projection.md) | camera space, perspective projection, clip space, the frustum | `camera.zig` |
| [16](16-wireframe-3d.md) | meshes, indices, the vertex pipeline, wireframes | `mesh.zig`, `render3d.zig`, `maze3d.zig` |
| [17](17-clipping.md) | outcodes, Sutherland–Hodgman clipping, homogeneous clipping | `clip.zig` |
| [18](18-rasterizing-triangles.md) | fixed-point rasterization, top-left rule, z-buffer, back-face culling, perspective-correct interpolation | `raster.zig`, `render3d.zig` |
| [19](19-shading-and-lighting.md) | Lambert, flat/Gouraud/Phong, attenuation, fog | `light.zig` |
| [20](20-texture-mapping.md) | UVs, perspective-correct texturing, wrapping, bilinear, mipmaps, LOD | `texture.zig`, `render3d.Gradients`, `light.Material` |
| [21](21-building-the-world.md) | building meshes from data, hidden-face removal, chunks, file formats, OBJ | `world.zig`, `map.zig`, `obj.zig` |
| [22](22-the-first-person-client.md) | first-person controls, pitch, circle collision, fixed timestep, record/replay | `player.zig`, `demo.zig`, `main.Ticker` |
| [23](23-visibility-and-occlusion.md) | bounding boxes, frustum culling, grid visibility, front-to-back order, overdraw | `visibility.zig`, `render3d` overdraw |
| [24](24-performance-and-finishing.md) | profiling, Amdahl's law, SIMD (and when it loses), threads, release modes | `profile.zig`, `raster.fillTriangleRows`, `Renderer.band`, `app.drawWorld` |

## The numbers of Part II

| Where | What | Number |
|---|---|---|
| ch14 | ray caster, ReleaseFast | ~1.1 ms/frame |
| ch19 | Phong corridor, one core | 10.9 ms/frame |
| ch20 | + trilinear textures, one core | 22.8 ms/frame |
| ch22 | the tour, Phong trilinear | 17.1 ms/frame |
| ch23 | tour CPU time, culling off → grid culling + sorting | 20.8 → 16.0 ms/frame; overdraw 1.46× → 1.20× |
| ch24 | tour, `--bench` wall clock, 1 thread / 8 threads | 14.94 / 3.31 ms/frame (4.5×) |

Numbers from different rows were taken on a shared machine at different loads; compare
within a row. Readers should rerun them.

## From delve to a GPU

| delve (CPU) | GPU pipeline |
|---|---|
| `Renderer.transform`, the shader's `vertex()` | vertex shader |
| `clip.clipTriangle` | fixed-function clipping (guard bands) |
| divide by w, `camera.toScreen` | perspective divide, viewport transform |
| back-face test by signed area | rasterizer culling state |
| `raster.fillTriangle`, top-left rule | fixed-function rasterizer (same rule in D3D) |
| `render3d.interpolate` | perspective-correct varyings (`noperspective` to opt out) |
| `pixel()` | fragment/pixel shader |
| depth buffer, `z < depth` | depth test state (`LESS`) |
| `Texture.filtered`, mips, `levelOfDetail` | samplers, mipmaps, derivatives from 2×2 quads |
| `Renderer.band` on threads | thousands of cores, tiles |
| `Visibility`, chunk sorting | still on the CPU: culling, draw order, draw calls |

Next steps for readers: raylib's own 3D API (`DrawModel`, shaders) on the same map;
then OpenGL, Vulkan, WebGPU or Metal, where every row of this table becomes an API.

---

Sources for this appendix: [REFERENCES.md](REFERENCES.md#primary-references)
