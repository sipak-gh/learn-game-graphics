# Appendix A — Cheat Sheet

This is a quick reference to the course, one section per topic: the commands, the Zig 0.17.1
idioms, the raylib 6.2 calls, and the graphics math that `quadfall` and `delve` use. Each
snippet is a fragment from the course's code or its examples, and all of it was compiled with
Zig 0.17.1. The chapter links point to the full explanation.

Previous: [Chapter 24 — Performance and Finishing](24-performance-and-finishing.md). Next:
[Appendix B — quadfall Reference](appendix-b-quadfall-reference.md).

## Commands

| What | Command |
|---|---|
| New project with only `build.zig` and `build.zig.zon` | `zig init --minimal` |
| Add raylib 6.2, pinned to its commit | `zig fetch --save "git+https://github.com/raysan5/raylib?ref=6.2#02566453880e06bec97f5b8160fa6fe1e98397ca"` |
| Build, run, pass arguments | `zig build`, `zig build run`, `zig build run -- --seed 7` |
| Tests with counts | `zig build test --summary all` (a cached run prints no counts; delete `.zig-cache` for fresh ones) |
| One test file, filtered | `zig test file.zig --test-filter name` |
| Optimized `delve` | `zig build --release=fast run` (Debug is about 10× slower) |
| `delve` benchmark | `zig build bench --release=fast -- --threads 1` |
| Release builds of `quadfall` | `zig build release` (this machine plus a Windows `.exe`) |
| Windows `.exe` from Linux | `zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSmall` |
| Run an example | `cd examples && zig build run -Dexample=ch01/window` |
| Run a pure-Zig example | `zig run examples/ch11/vector_basics.zig` |
| Headless `quadfall` | `xvfb-run -a -s "-screen 0 1280x720x24" ./zig-out/bin/quadfall --frames 120 --screenshot shot.png` |
| Headless `delve` (no X needed) | `./zig-out/bin/delve --headless --frames 60 --out frame.png` |
| Pin a run to one CPU | `taskset -c 3 ./zig-out/bin/delve ...` |
| Has the compiler vectorized? | `objdump -d --no-show-raw-insn -C bin \| grep -c ymm` |

Chapters [1](01-getting-started.md), [8](08-organizing-a-game.md) and
[24](24-performance-and-finishing.md) explain these.

## Zig 0.17.1 idioms

### Program and build

```zig
pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    // init.io is the std.Io instance for files, time and threads
    return 0;
}
```

```zig
// build.zig: a module, an import, and a test of the module
const core = b.createModule(.{ .root_source_file = b.path("src/core/root.zig"), .target = target, .optimize = optimize });
const exe = b.addExecutable(.{ .name = "quadfall", .root_module = b.createModule(.{
    .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize,
    .imports = &.{ .{ .name = "core", .module = core } },
}) });
const tests = b.addTest(.{ .root_module = core });
test_step.dependOn(&b.addRunArtifact(tests).step);

// raylib as a C library plus a translated header, imported as "rl"
const raylib_dep = b.dependency("raylib", .{ .target = target, .optimize = optimize });
const rl = b.addTranslateC(.{ .root_source_file = raylib_dep.path("src/raylib.h"), .target = target, .optimize = optimize }).createModule();

// another target: .{} is the host
const t = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows });
```

- `builtin.mode` is the optimize mode the program was built with. `{t}` prints its tag in
  short form, such as `safe` for `.ReleaseSafe`. `std.builtin` is an alias of `std.lang`.
- `exe.subsystem = .windows` gives a Windows program with no console. `exe.root_module.strip =
  true` drops the debug info, and with it the stack traces.
- `zig build --release=fast` works only when `build.zig` sets no preferred optimize mode. A
  preferred mode overrides `--release=...`, so check `builtin.mode`
  ([Chapter 24](24-performance-and-finishing.md)).

### Types and data

| Idiom | Meaning |
|---|---|
| `enum(u8)`, `@backingInt(e)`, `@fromBackingInt(n)` | enum ↔ integer (`@intFromEnum`/`@enumFromInt` still work) |
| `std.enums.values(E)`, `std.meta.tags(E)` | every tag in declaration order |
| `std.enums.EnumArray(K, V)`: `.init(.{...})`, `.initFill(v)`, `.get`, `.set`, `.getPtr` | a table indexed by an enum |
| `std.enums.EnumSet(E)`: `.empty`, `.insert`, `.contains`, `.count`, `.unionWith` | a set of enum values |
| `const all = std.enums.values(E); e = all[(@backingInt(e) + 1) % all.len];` | cycle through an enum |
| `packed struct { left: bool = false, ... }`, `const bits: u9 = @bitCast(input);` | flags with `==`, and an integer for printing |
| `union(enum) { falling, clearing: struct {...}, over }` | a state with data; `switch (p) { .clearing => \|*c\| ... }` captures by pointer |
| `p.phase == .over` | compare a tagged union with a tag |
| `?T`, `if (o) \|v\|`, `o orelse x`, `o.?` | optionals; `@sizeOf(?Kind)` is one byte more than `@sizeOf(Kind)` |
| `const Color = extern struct { r: u8, g: u8, b: u8, a: u8 = 255 };` | a C-compatible layout, the same bytes as raylib's `Color` |
| `std.bit_set.IntegerBitSet(22)`, `std.DynamicBitSet` | fixed-size and run-time-size bit sets |
| `std.StaticStringMap(V).initComptime(.{ .{ "key", v } })` | a name → value map built at compile time |
| `@Int(.unsigned, n)` | an n-bit integer type (`std.meta.Int` is gone in 0.17) |
| `std.meta.eql(a, b)` | struct equality (`==` on structs is a compile error) |

### Comptime

```zig
pub const gravity_table: [20]u32 = blk: {      // at container level this runs at compile time
    @setEvalBranchQuota(10_000);              // raise the 1000-branch limit
    var table: [20]u32 = undefined;
    for (&table, 1..) |*g, level| g.* = f(level);
    break :blk table;
};
const x = comptime f();                        // inside a function
comptime { std.debug.assert(cond); }           // a build-time check at container level
inline for (comptime std.meta.tags(Kind)) |kind| { ... }   // unrolled, `kind` is comptime
inline for (@typeInfo(T).@"struct".field_names) |f| @field(value, f) = true;
```

- `@compileLog(x)` prints at compile time, and the build fails while it is there.
- `comptime_int / comptime_float` with a remainder is "ambiguous coercion of division
  operands". Type one operand: `const k: f32 = 0.8;` or write `2.0`.
- An `if` with untyped float branches depends on run-time control flow. Give it a type:
  `const s: f32 = if (c) 0.5 else 1;`.
- `std.math.atan(0.5)` at comptime hits `unreachable`. Use `std.math.atan(@as(f32, 0.5))`.

### Memory, lists, sorting

```zig
var list: std.ArrayList(T) = .empty;          // 0.17 lists take the allocator per call
defer list.deinit(gpa);
try list.append(gpa, x);
const owned = try list.toOwnedSlice(gpa);
```

- A slice into an `ArrayList`'s items dangles after the list grows. Keep offsets and slice at
  the end.
- `@memcpy` needs slices that do not overlap. Use `std.mem.copyForwards` or `copyBackwards`.
- `std.mem.sort(T, items, ctx, lessThan)` with `fn lessThan(ctx: Ctx, a: T, b: T) bool`. With
  no context, pass `{}` and take `_: void`. The sort is stable, and `std.sort.asc(T)` sorts
  plain values in ascending order.
- `var prng: std.Random.DefaultPrng = .init(seed); const r = prng.random();` (it must be
  `var`). Use `r.intRangeLessThan(u8, 0, 7)`, `r.float(f32)`, `r.int(u64)`, or
  `r.shuffleWithIndex(T, items, u32)`.

### Text and formatting

| Idiom | Meaning |
|---|---|
| `std.mem.printSentinel(&buf, fmt, args, 0)` | a formatted `[:0]u8` for raylib's `DrawText` |
| `{t}`, `{d}`, `{f}`, `{?}`, `{{`/`}}` | tag name, number, call `format`, optional, literal brace |
| `{d}` on a float | the shortest decimal that reads back to the same bits, never an exponent |
| `{d:>4}` on a signed integer | a width prints a `+` sign in 0.17 |
| `pub fn format(self: T, w: *std.Io.Writer) std.Io.Writer.Error!void` | make a type printable with `{f}` |
| `var w: std.Io.Writer = .fixed(&buf);` … `w.buffered()` | write into a buffer (`error.WriteFailed` when full) |
| `var out: std.Io.Writer.Allocating = .init(gpa);` … `out.written()` | write into growing memory |
| `std.Io.Writer.Discarding` | count bytes without storing them |
| `std.mem.findScalar`, `findAny`, `countScalar` | search (`indexOfScalar` was renamed) |
| `std.mem.splitScalar` / `tokenizeScalar`, `tokenizeAny(u8, text, "\r\n")` | split (keeps empty pieces) / tokenize (skips them) |
| `std.fmt.parseInt(u32, s, 10)`, `std.fmt.parseFloat(f32, s)` | parse numbers (`"-1"` as `u32` is `error.Overflow`) |

### Files, ZON, time, threads

```zig
const text = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20));
const src = try std.Io.Dir.cwd().readFileAllocOptions(io, path, gpa, .limited(4096), .of(u8), 0); // 0-terminated, for ZON
try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });

var diagnostics: std.zon.parse.Diagnostics = undefined;
const save = std.zon.parse.fromSlice(Save, .{ .gpa = gpa, .arena = arena, .source = src, .diagnostics = &diagnostics }) catch |err| {
    if (err == error.ParseZon) diagnostics.log(path);
    return err;
};
try std.zon.stringify.serialize(save, .{}, &writer);

const start = std.Io.Timestamp.now(io, .awake);          // monotonic clock
const ns = start.durationTo(.now(io, .awake)).nanoseconds;

var group: std.Io.Group = .init;                          // run tasks, then wait
for (bands) |band| group.async(io, drawBand, .{ io, band });
try group.await(io);              // fails only if this thread is canceled
```

- `std.testing.io` gives a test an `Io`.
- `std.compress.flate.Compress` with `.zlib` writes the image data of a PNG.
  `std.hash.Crc32.hash` gives the chunk checksums ([Chapter 9](09-framebuffers.md)).

### Vectors (`@Vector`)

```zig
const Vec3 = @Vector(3, f32);
const half: Vec3 = @splat(0.5);                 // broadcast
const d = @reduce(.Add, a * b);                 // dot product
const same = @reduce(.And, a == b);             // compare all lanes
const pick = @select(f32, mask, a, b);          // per-lane choice
const c: @Vector(3, u8) = @intFromFloat(v + half); // convert all lanes
inline for (0..3) |i| sum += v[i];              // a run-time vector index must be comptime
```

- `@min`, `@max`, `@floor`, `@ceil`, `@abs`, `@sqrt` and `std.math.clamp` work lane by lane.
- `@bitCast` refuses an `extern struct`. Cast a pointer instead:
  `@as(*const [4]u8, @ptrCast(&c)).*`.
- To shift by a run-time amount, the left side needs a fixed width:
  `@as(usize, 64) >> @intCast(level)`.
- `+|=` is a saturating add, so a `u8` counter stops at 255.

### Testing

| Call | Use |
|---|---|
| `expect(cond)`, `expectEqual(expected, actual)` | the basics; the two values must have peer types |
| `expectEqualDeep`, `expectEqualStrings`, `expectError(error.X, expr)` | follow pointers, compare text, expect an error |
| `expectApproxEqAbs(expected, actual, 1e-6)` | floats |
| `expectFmt(expected, "{f}", .{value})` | golden text; `␃` marks where each string ends in a failure |

## raylib 6.2 calls used

From Zig every call takes the `rl.` prefix, and constants look like `rl.KEY_LEFT`.

| Area | Calls |
|---|---|
| Window and loop | `InitWindow`, `CloseWindow`, `WindowShouldClose`, `SetTargetFPS`, `GetFrameTime`, `GetTime`, `GetScreenWidth`, `GetScreenHeight`, `SetTraceLogLevel(rl.LOG_WARNING)`, `SetExitKey(rl.KEY_NULL)` |
| Drawing | `BeginDrawing`, `EndDrawing`, `ClearBackground`, `DrawRectangle`, `DrawRectangleRec`, `DrawRectangleLines`, `DrawRectangleLinesEx`, `DrawLine`, `DrawCircle`, `DrawTriangle`, `BeginMode2D`/`EndMode2D` (screen shake) |
| Text | `DrawText`, `MeasureText` (needs a `[:0]const u8`) |
| Color | `Fade`, `ColorBrightness`, `ColorFromHSV` |
| Input | `IsKeyDown`, `IsKeyPressed`, `IsKeyReleased`, `GetMousePosition`, `GetMouseDelta`, `DisableCursor` |
| Textures (`delve`'s canvas) | `LoadTextureFromImage`, `UpdateTexture`, `SetTextureFilter`, `DrawTexturePro`, `DrawTextureEx`, `UnloadTexture` |
| Sound | `InitAudioDevice`, `IsAudioDeviceReady`, `LoadSoundFromWave`, `PlaySound`, `IsSoundPlaying`, `UnloadSound`, `CloseAudioDevice` |
| Files | `TakeScreenshot` (raylib saves the PNG) |

- `GetMouseDelta` is the current position minus the previous one. raylib updates the previous
  position in `PollInputEvents`, at the end of the frame.
- `LoadSoundFromWave` copies the samples, so the wave can be a stack array.
- When there is no audio device, run with `--mute` (or `PULSE_SERVER=unix:/nonexistent`).

## Graphics math

### Pixels, lines, triangles in 2D ([Chapters 9](09-framebuffers.md) and [10](10-drawing-in-2d.md))

- Pixel `(x, y)` of a `w`-wide RGBA canvas is at `pixels[y * w + x]`. y grows downward.
- **Bresenham:** set `err = dx + dy` with `dx = |x1 − x0|` and `dy = −|y1 − y0|`. Each step,
  `e2 = 2·err`; if `e2 ≥ dy` then `err += dy, x += sx`; if `e2 ≤ dx` then `err += dx, y += sy`.
- **Edge function:** `E(a, b, p) = (b.x − a.x)(p.y − a.y) − (b.y − a.y)(p.x − a.x)`. Its sign
  tells you which side of the line ab the point p lies on. `E(a, b, c)` is twice the
  triangle's signed area.

### Vectors ([Chapter 11](11-vectors.md))

- `a · b = Σ aᵢbᵢ = |a||b| cos θ`. It is the length of a projection, and it is 0 when a and b
  are perpendicular.
- 2D cross product: `a × b = a.x·b.y − a.y·b.x`, the signed area. In 3D,
  `a × b = (a.y b.z − a.z b.y, a.z b.x − a.x b.z, a.x b.y − a.y b.x)` is perpendicular to both.
- `normalize(v) = v / |v|`. A direction from an angle is `(cos θ, sin θ)`. In `delve`, yaw 0
  is east (+x) and 90° is south (+y). `perp(x, y) = (−y, x)`.

### Matrices ([Chapter 12](12-matrices-and-transforms.md))

- Homogeneous coordinates: points are `(x, y, z, 1)` and directions are `(x, y, z, 0)`, so
  translation is a matrix too.
- 2D rotation: `[cos θ −sin θ; sin θ cos θ]`. Compose transforms right to left:
  `M = T · R · S` scales first.
- `(AB)⁻¹ = B⁻¹A⁻¹`. The inverse comes from Gauss–Jordan elimination, and it is null when the
  determinant is 0.
- **Normal matrix** = the inverse transpose of the model matrix's 3×3 part. For rotations and
  uniform scales, the matrix itself does the job.

### Ray casting ([Chapters 13](13-ray-casting.md) and [14](14-textures-and-sprites.md))

- Ray for column x: `dir = forward + plane · (2(x + 0.5)/W − 1)`. The plane is perpendicular
  to `forward`, and delve's is 0.8 long: a 77.3° horizontal and 53.13° vertical field of view
  at 640×400.
- **DDA:** `deltaDist = |1/dir|` per axis. Step along whichever side distance is smaller, and
  stop at a wall cell.
- Use the perpendicular distance `d = sideDist − deltaDist` along the axis of the last step,
  not the Euclidean distance, which bends walls (fisheye). A 1-unit-tall wall is
  `W/(2·0.8)/d` pixels tall, which is `H/d` at 640×400.
- Wall texture column: `u = frac(hit point along the wall)`.
- **Floor casting:** row y below the horizon sees the floor at `d = (H/2) / (y + 0.5 − H/2)`.
- **Sprites:** for `rel = sprite − eye`, the depth is `rel · dir` and the position across the
  screen is `camera_x = (rel · plane) / (|plane|² · depth)`. Screen x is `(camera_x + 1)/2 · W`.
  Draw sprites far to near, and skip columns where the wall's depth is nearer.

### Camera and projection ([Chapter 15](15-cameras-and-projection.md))

- **lookAt** (right-handed, looking down −z), with rows
  `[r, −r·eye]`, `[u, −u·eye]`, `[−fwd, fwd·eye]`, `[0, 0, 0, 1]`.
- **Perspective** (depth 0 to 1), with `f = 1/tan(vfov/2)`:
  ```text
  [ f/aspect  0   0   0 ]
  [ 0         f   0   0 ]      A = far / (near − far)
  [ 0         0   A   B ]      B = near·far / (near − far)
  [ 0         0  −1   0 ]
  ```
  delve uses vfov = 2·atan(0.5) = 53.13°, f = 2, near = 0.05, far = 64, so A = −1.000782 and
  B = −0.050039.
- Clip space → NDC: divide x, y, z by w (w = distance in front of the eye). Viewport:
  `sx = (x+1)/2 · W`, `sy = (1−y)/2 · H`.
- Depth from NDC z: `d = n·f / (f − z·(f − n))`. Most of the precision sits near the near
  plane.

### Clipping ([Chapter 17](17-clipping.md))

- The frustum in clip space is `−w ≤ x ≤ w`, `−w ≤ y ≤ w`, `0 ≤ z ≤ w`.
- **Outcodes:** one bit per plane a vertex is outside of. If all three vertices share a bit,
  reject the triangle; if no vertex has any bit, accept it.
- For signed distances `d(a)`, `d(b)` of an edge's endpoints to a plane, the crossing is at
  `t = d(a) / (d(a) − d(b))`. Interpolate every varying with the same t.
- **Sutherland–Hodgman:** clip the polygon against one plane at a time. A triangle can grow to
  9 vertices; fan it back into triangles.

### Rasterization ([Chapter 18](18-rasterizing-triangles.md))

- Use fixed-point screen coordinates with 4 sub-pixel bits (`x·16`). Sample at pixel centers
  `(x + 0.5, y + 0.5)`.
- The rasterizer takes the corners clockwise on the screen (y down), so the area
  `E(a, b, c)` is positive. A pixel is inside if all three edge functions are ≥ 0. The
  **top-left rule** subtracts 1 from each edge that is neither a top nor a left edge, so a
  pixel center on an edge shared by two triangles is drawn exactly once.
- **Incremental:** E grows by `(a.y − b.y)` per pixel to the right and by `(b.x − a.x)` per row
  down.
- **Barycentrics:** `λᵢ = Eᵢ / area`, and `λ₀ + λ₁ + λ₂ = 1`. Any attribute is
  `Σ λᵢ attrᵢ`.
- **Back-face culling:** front faces go counter-clockwise as seen, which is a negative
  `E(a, b, c)` with y down. A positive area means you see the back, so drop the triangle;
  otherwise swap two corners to make it clockwise for the rasterizer.
- **Depth buffer:** draw the pixel only if `z < depth[p]`, then store z.

### Perspective-correct interpolation ([Chapters 18](18-rasterizing-triangles.md) and [20](20-texture-mapping.md))

- `1/w` and `attr/w` are linear in screen space; `attr` itself is not. Interpolate them with
  the barycentrics, then `attr = (Σ λᵢ attrᵢ/wᵢ) / (Σ λᵢ /wᵢ)`.
- Affine texturing (`P` off) interpolates `attr` directly, and textures swim on walls seen at
  an angle.

### Lighting and fog ([Chapter 19](19-shading-and-lighting.md))

- **Lambert:** `diffuse = max(0, n · l)` with unit normal n and unit direction l to the light.
- **Shading models:** *flat* uses one normal per triangle, *Gouraud* lights the vertices and
  interpolates colors, and *Phong* interpolates normals and lights every pixel.
- **Attenuation** with `x = d/radius`: `window = max(0, 1 − x²)` and
  `a = window² / (1 + (d/1.5)²)`. It reaches exactly 0 at `radius`, so farther lights are
  skipped.
- Light = `ambient + Σ color · lambert · attenuation`. The surface color is
  `albedo · light`, clamped to 255.
- **Fog:** `seen = e^(−density · d)`, so `color = lerp(fog, color, seen)`.
- Integer powers by squaring: `inline for (0..5) |_| x *= x` computes x³².

### Textures and mipmaps ([Chapter 20](20-texture-mapping.md))

- Wrapping on a power-of-two texture is `i & (size − 1)`. Take `@floor` first, so negative
  coordinates wrap correctly.
- **Bilinear:** subtract 0.5 (texel centers), split into integer and fraction, then blend the
  4 texels by the fractions.
- Mip level k is `size >> k` wide, and each texel averages 2×2 texels of level k−1. 64×64
  textures have 7 levels.
- **Footprint:** `u = (u/w)/(1/w)`. By the quotient rule, `du/dx = (d(u/w)/dx − u·d(1/w)/dx)
  / (1/w)`, and the same for v and y. The footprint is
  `max(|(du/dx, dv/dx)|, |(du/dy, dv/dy)|)`.
- **Level of detail:** `λ = log₂(footprint · size)`. Below 0 the texture is magnified, so use
  level 0. *Mipmap* rounds λ to the nearest level. *Trilinear* blends bilinear samples of
  levels ⌊λ⌋ and ⌊λ⌋+1.

### Visibility ([Chapter 23](23-visibility-and-occlusion.md))

- **Frustum planes from `M = proj · view`** (Gribb–Hartmann), with rows `m₀..m₃`: left
  `m₃ + m₀`, right `m₃ − m₀`, bottom `m₃ + m₁`, top `m₃ − m₁`, near `m₂` (depth 0 to 1), far
  `m₃ − m₂`. A point is inside a plane when `plane · (x, y, z, 1) ≥ 0`.
- **Box against plane:** test only the *positive vertex*, the box corner furthest along the
  plane's normal (`@select` per lane). If it is outside, the whole box is.
- **Grid visibility:** cast the DDA rays of Chapter 13 across the view, mark every cell they
  pass, and skip chunks with no marked cell.
- Draw front to back so the depth test rejects hidden pixels early. Overdraw is the number of
  times each pixel was covered (1.46× → 1.20× in the tour).

### Performance ([Chapter 24](24-performance-and-finishing.md))

- **Amdahl's law:** if a share p of the work is spread over s threads, the time is
  `T = (1 − p) + p/s`, the speedup is `1/T`, and the speedup is never more than `1/(1 − p)`.
- Measure before changing anything. Take the best of several runs on a pinned core, and
  compare numbers only within one session on a shared machine.
- `@round` costs four instructions. `+ 0.5` then truncate costs two, for non-negative values.

---

Sources for this appendix: [REFERENCES.md](REFERENCES.md#primary-references)
