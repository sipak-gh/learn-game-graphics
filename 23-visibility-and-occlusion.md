# Chapter 23 — Visibility and Occlusion

At the end of Chapter 22, every frame sends all 256 chunks of the labyrinth to the renderer. At
frame 700 of the tour that is 18,410 triangles. The outcode test throws out 17,646 of them, one
at a time, and 575 reach the screen. This chapter stops sending what cannot be seen, in two
stages, the cheap one first.

The first stage is frustum culling of whole chunks: six planes pulled out of the
view-projection matrix, and one test of each chunk's box against them. The second is occlusion,
and for it the ray caster of Chapter 13 comes back, this time as a visibility system. A fan of
rays across the view marks the grid cells that a line of sight reaches, and a chunk with no
marked cell is hidden behind walls. The chunks that are left are drawn nearest first, so the
depth test rejects more pixels before Phong shading pays for them.

Then come the tools to *see* what the culling saves: a HUD line with chunk counts and overdraw,
an overdraw heat map, an overhead camera that paints each chunk by what happened to it and
draws the fan of rays, and a key that freezes the visibility so you can walk out of it and
watch the world end where the rays stopped. The picture itself never changes, and a test
checks that pixel for pixel. Only the work does: at the labyrinth's start, 106 triangles are
sent instead of 18,410.

Previous: [Chapter 22 — The First-Person Client](22-the-first-person-client.md). Next:
[Chapter 24 — Performance and Finishing](24-performance-and-finishing.md).

## What gets thrown away, and when

Here are Chapter 22's numbers at frame 700 of the tour, the stone room with the barrel:

```text
TRIANGLES 18410  OUTSIDE 17646  CLIPPED 143  BEHIND NEAR 0  CULLED 184  DRAWN 575  PIXELS 344095
```

Every one of the 17,646 triangles outside the view had its vertices transformed by the
view-projection matrix and given outcodes (Chapter 17) before the renderer could find out that
it was not needed: 96% of the triangles of this frame were work spent on nothing.

There are three levels at which the renderer can refuse work, from cheapest to dearest:

| Level | Test | Chapter | What one refusal saves |
|---|---|---|---|
| A chunk | its box against the view, and lines of sight | this one | every triangle and pixel in it |
| A triangle | outcodes, back faces | 16–17 | its pixels |
| A pixel | the depth test | 18 | the shading of one pixel |

The earlier a refusal, the more it saves. So far everything has been refused at the triangle
level or later. This chapter adds the first level.

To see the third level at work, the renderer needs one more count. `PIXELS` counts the pixels
that passed the depth test and were shaded. Before the depth test, every pixel a triangle
covers is *tested*, so `src/render3d.zig` gets a counter for that too:

```zig
    drawn: u32 = 0,
    /// Pixels of drawn triangles: each one is depth tested.
    tested: u32 = 0,
    /// Pixels that passed the depth test and were shaded and written.
    pixels: u32 = 0,
```

`Fragment.pixel` counts it first thing, before the test:

```zig
        pub fn pixel(f: *@This(), x: usize, y: usize, weights: Vec3) void {
            const i = y * f.canvas.width + x;
            f.tested += 1;
            if (f.overdraw.len > 0) f.overdraw[i] +|= 1;
            // Depth (z/w) is linear on the screen: plain weights are right.
            const z = math.dot(weights, f.z);
            if (f.depth_test and z >= f.depth[i]) return;
```

(The `overdraw` line is for later, in "Seeing overdraw".) Divided by the number of pixels on
the screen, the two counts say how many times each pixel was covered and how many times it was
shaded, on average. A new HUD line shows both:

```text
COVERED 1.46X  SHADED 1.34X
```

At frame 700, with everything drawn and in no particular order, each pixel is covered 1.46
times and shaded 1.34 times. Shading costs most of a frame (Chapter 22 measured it as three
quarters), and a quarter of that shading is painted over. By the end of the chapter it is 1.20 and
1.05.

## Six planes from one matrix

To refuse a whole chunk, we need to know if its box is inside the view volume, the *frustum*.
The frustum is bounded by six planes, and the clipper already knows them, in clip space
(`src/clip.zig`, Chapter 17):

```zig
    /// How far inside the plane `p` is (in clip-space units): negative
    /// means outside.
    pub fn distance(plane: Plane, p: Vec4) f32 {
        const x, const y, const z, const w = p;
        return switch (plane) {
            .near => z,
            .far => w - z,
            .left => w + x,
            .right => w - x,
            .bottom => w + y,
            .top => w - y,
        };
    }
```

To test a box in the world, we want the same planes in world coordinates: four numbers
(a, b, c, d) per plane, so that a world point p is inside when a·x + b·y + c·z + d ≥ 0. We could
work them out from the field of view, the aspect ratio and the camera's position and
orientation, with some trigonometry per plane. There is a much shorter way.

Every `distance` above is *linear* in the clip point: a sum of its coordinates times constants.
And the clip point of a world point p = (x, y, z, 1) is the view-projection matrix times p,
which is the matrix's columns times p's coordinates, added up:

```text
clip(p) = col0·x + col1·y + col2·z + col3·1
```

A linear function of a sum is the sum of the function's values, so

```text
distance(clip(p)) = distance(col0)·x + distance(col1)·y + distance(col2)·z + distance(col3)
```

That is a plane in the world, with a = distance(col0), b = distance(col1), c = distance(col2)
and d = distance(col3). No inverse matrix, no trigonometry: each plane is the clip-space
distance function applied to the four columns. This is Gil Gribb and Klaus Hartmann's trick,
usually written as "add and subtract rows of the matrix" (our matrices are stored by columns,
and `distance` does the adding and subtracting). A new file, `src/visibility.zig`, starts with
it:

```zig
/// The six planes of the view volume, in the world.
pub const Frustum = struct {
    /// Each plane as (a, b, c, d): a point p is on the inside if
    /// a x + b y + c z + d >= 0.
    planes: [6]Vec4,

    /// The planes that `view_proj` maps onto the six planes of clip space.
    /// A plane's distance in clip space is linear in the clip point, and
    /// the clip point is `view_proj` times the world point: the sum of the
    /// matrix columns times x, y, z, and 1. So the distance is the sum of
    /// the columns' distances times x, y, z, and 1.
    pub fn init(view_proj: Mat4) Frustum {
        var f: Frustum = undefined;
        for (&f.planes, std.enums.values(clip.Plane)) |*plane, which| {
            inline for (0..4) |j| plane[j] = which.distance(view_proj.cols[j]);
        }
        return f;
    }
```

- Six planes, 24 calls to `distance`. `std.enums.values(clip.Plane)` gives the planes in
  declaration order, so `planes[0]` is the near plane, as in the clipper.
- `plane[j] = ...` sets one lane of a `Vec4`: vectors can be indexed with a comptime-known
  index, and `inline for` makes `j` one.
- The planes are not normalized: (a, b, c) is not a unit vector, so a·x + b·y + c·z + d is not
  the distance in world units. Only its sign matters for culling, and scaling a plane's four
  numbers by a positive factor does not change the sign.

Here is the trick on its own, with delve's projection and with a moved camera, printing the
planes normalized so that they can be read:

`examples/ch23/frustum_planes.zig`:

```zig
//! The six planes of the view frustum, pulled out of a view-projection
//! matrix. A clip-space plane's distance (w + x for the left plane, w - z
//! for the far plane, and so on) is linear in the clip point, and the clip
//! point is col0 x + col1 y + col2 z + col3. So each plane's world-space
//! (a, b, c, d) is that same distance taken of the four columns.
const std = @import("std");

const Vec3 = @Vector(3, f32);
const Vec4 = @Vector(4, f32);

/// A 4x4 matrix stored as four columns.
const Mat4 = struct {
    cols: [4]Vec4,

    fn mulVec(m: Mat4, v: Vec4) Vec4 {
        var r: Vec4 = @splat(0);
        inline for (0..4) |j| r += m.cols[j] * @as(Vec4, @splat(v[j]));
        return r;
    }

    fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = undefined;
        for (&r.cols, b.cols) |*col, bc| col.* = a.mulVec(bc);
        return r;
    }

    /// delve's projection: looking down -z, depth 0 at `near` and 1 at `far`.
    fn perspective(vfov: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1 / @tan(vfov / 2);
        return .{ .cols = .{
            .{ f / aspect, 0, 0, 0 },
            .{ 0, f, 0, 0 },
            .{ 0, 0, far / (near - far), -1 },
            .{ 0, 0, near * far / (near - far), 0 },
        } };
    }

    fn translation(t: Vec3) Mat4 {
        return .{ .cols = .{ .{ 1, 0, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 0, 1, 0 }, .{ t[0], t[1], t[2], 1 } } };
    }
};

/// The clipper's planes, as in delve's clip.zig.
const Plane = enum {
    near,
    far,
    left,
    right,
    bottom,
    top,

    fn distance(plane: Plane, p: Vec4) f32 {
        const x, const y, const z, const w = p;
        return switch (plane) {
            .near => z,
            .far => w - z,
            .left => w + x,
            .right => w - x,
            .bottom => w + y,
            .top => w - y,
        };
    }
};

fn planes(view_proj: Mat4) [6]Vec4 {
    var result: [6]Vec4 = undefined;
    for (&result, std.enums.values(Plane)) |*plane, which| {
        inline for (0..4) |j| plane[j] = which.distance(view_proj.cols[j]);
    }
    return result;
}

fn show(name: []const u8, view_proj: Mat4) [6]Vec4 {
    const ps = planes(view_proj);
    std.debug.print("{s}, normalized (a, b, c, d):\n", .{name});
    for (ps, std.enums.values(Plane)) |p, which| {
        const n = @sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
        std.debug.print("  {s:<6} {d:>7.3} {d:>7.3} {d:>7.3} {d:>8.3}\n", .{ @tagName(which), p[0] / n, p[1] / n, p[2] / n, p[3] / n });
    }
    return ps;
}

pub fn main() void {
    // delve's camera: vertical fov 2 atan(0.5), 640 x 400, near 0.05, far 64.
    const proj = Mat4.perspective(2 * std.math.atan(@as(f32, 0.5)), 1.6, 0.05, 64);
    const at_origin = show("camera at the origin looking down -z", proj);

    // Moving the camera to (2, 0.5, 3) moves the world by the opposite.
    const moved = proj.mul(.translation(.{ -2, -0.5, -3 }));
    _ = show("the same camera at (2, 0.5, 3)", moved);

    // Ten points: the planes and the clipper's outcodes must agree.
    const points = [_]Vec3{
        .{ 0, 0, -1 },    .{ 0, 0, -0.01 }, .{ 0, 0, 1 },     .{ 0, 0, -70 },  .{ -0.7, 0, -1 },
        .{ -0.9, 0, -1 }, .{ 0, 0.45, -1 }, .{ 0, 0.55, -1 }, .{ 5, -6, -10 }, .{ 30, 0, -40 },
    };
    std.debug.print("point                outside of (planes)              outside of (outcode)\n", .{});
    var agree: usize = 0;
    for (points) |p| {
        var by_planes: std.EnumSet(Plane) = .empty;
        var by_clip: std.EnumSet(Plane) = .empty;
        const c = proj.mulVec(.{ p[0], p[1], p[2], 1 });
        for (at_origin, std.enums.values(Plane)) |plane, which| {
            if (plane[0] * p[0] + plane[1] * p[1] + plane[2] * p[2] + plane[3] < 0) by_planes.insert(which);
            if (which.distance(c) < 0) by_clip.insert(which);
        }
        std.debug.print("({d:>5},{d:>5},{d:>5})    ", .{ p[0], p[1], p[2] });
        printSet(by_planes, true);
        printSet(by_clip, false);
        std.debug.print("\n", .{});
        agree += @intFromBool(by_planes.eql(by_clip));
    }
    std.debug.print("agree on {d} of {d}\n", .{ agree, points.len });
}

fn printSet(set: std.EnumSet(Plane), pad: bool) void {
    var buffer: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    var it = set.iterator();
    while (it.next()) |plane| w.print("{s}{t}", .{ if (w.end > 0) " " else "", plane }) catch {};
    if (set.count() == 0) w.writeAll("inside") catch {};
    if (pad) std.debug.print("{s:<33}", .{w.buffered()}) else std.debug.print("{s}", .{w.buffered()});
}
```

```console
$ zig run examples/ch23/frustum_planes.zig
camera at the origin looking down -z, normalized (a, b, c, d):
  near     0.000   0.000  -1.000   -0.050
  far      0.000   0.000   1.000   63.997
  left     0.781   0.000  -0.625    0.000
  right   -0.781   0.000  -0.625    0.000
  bottom   0.000   0.894  -0.447    0.000
  top      0.000  -0.894  -0.447    0.000
the same camera at (2, 0.5, 3), normalized (a, b, c, d):
  near     0.000   0.000  -1.000    2.950
  far      0.000   0.000   1.000   60.997
  left     0.781   0.000  -0.625    0.312
  right   -0.781   0.000  -0.625    3.436
  bottom   0.000   0.894  -0.447    0.894
  top      0.000  -0.894  -0.447    1.789
point                outside of (planes)              outside of (outcode)
(    0,    0,   -1)    inside                           inside
(    0,    0,-0.01)    near                             near
(    0,    0,    1)    near left right bottom top       near left right bottom top
(    0,    0,  -70)    far                              far
( -0.7,    0,   -1)    inside                           inside
( -0.9,    0,   -1)    left                             left
(    0, 0.45,   -1)    inside                           inside
(    0, 0.55,   -1)    top                              top
(    5,   -6,  -10)    bottom                           bottom
(   30,    0,  -40)    inside                           inside
agree on 10 of 10
```

- `Mat4` and `Plane` are small copies of delve's, so that the example runs on its own.
- The left plane at the origin is (0.781, 0, −0.625, 0). Its normal points right and forward,
  into the view, at 51.3° from the view direction: 90° minus half the horizontal field of
  view, atan(0.8) = 38.7°. The top and bottom planes are at 90° − atan(0.5) = 63.4°. The four
  side planes pass through the eye, so their d is 0.
- The near plane reads −z − 0.05 ≥ 0, that is, z ≤ −0.05: 0.05 in front of the eye, which looks
  down −z. The far plane's 63.997 instead of 64 is f32 rounding in the matrix.
- Moving the camera changes only the d's: a translation does not turn anything.
- The point (0, 0, 1) is behind the eye, and it is outside five planes, all but the far one.
  The four side planes meet at the eye like the faces of a pyramid at its tip, and behind the
  tip, a point is on the outside of all four.
- The two methods agree on all ten points. They must: they compute the same numbers, once by
  transforming the point and once by transforming the planes.

## Is the box outside?

A chunk's box is outside the frustum if all eight of its corners are outside one plane. Testing
eight corners against six planes is 48 dot products. There is a shortcut: for each plane, only
one corner matters, the one farthest along the plane's normal, called the *positive vertex*.
If even that corner is outside, every other corner is farther out still.

Finding the positive vertex is a choice per axis. Where the normal's coordinate is positive,
the box's high coordinate is farther along it; where it is negative, the low one. Zig's
`@select` makes that choice for all three axes at once:

```zig
    /// True if the box from `box[0]` to `box[1]` is entirely outside one
    /// of the planes, so nothing in it can be seen. False does not prove
    /// it can: a box near a corner of the frustum may be outside two
    /// planes, each with a part of it, and still be kept.
    pub fn excludes(f: Frustum, box: [2]Vec3) bool {
        for (f.planes) |plane| {
            const normal: Vec3 = .{ plane[0], plane[1], plane[2] };
            // The corner farthest along the normal: if even that one is
            // outside, all eight are.
            const corner = @select(f32, normal >= @as(Vec3, @splat(0)), box[1], box[0]);
            if (math.dot(normal, corner) + plane[3] < 0) return true;
        }
        return false;
    }
};
```

- `normal >= @as(Vec3, @splat(0))` compares lane by lane and gives a `@Vector(3, bool)`.
  `@select(f32, pred, a, b)` takes each lane from `a` where `pred` is true and from `b` where
  it is false. The `@as` is needed because `@splat` must know what to splat into.
- A zero normal coordinate picks the high corner, which is as good as the low one: along that
  axis, both are equally far.
- Six dot products at most, and fewer for a box that is outside the first plane tested.

The example prints all eight corners of a box against delve's left plane, then slides the box
left until the test says it is outside:

`examples/ch23/positive_vertex.zig`:

```zig
//! Is a box outside a plane? Only if its corner farthest along the plane's
//! normal (the "positive vertex") is outside, because every other corner
//! is farther out still. One @select per plane picks that corner: the
//! box's high coordinate where the normal is positive, its low one where
//! it is negative. Prints all eight corners' distances for one box, then
//! slides a box left out of the view until the test says "outside".
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

/// The corner of `box` farthest along `normal`.
fn positiveVertex(normal: Vec3, box: [2]Vec3) Vec3 {
    return @select(f32, normal >= @as(Vec3, @splat(0)), box[1], box[0]);
}

fn corner(box: [2]Vec3, c: usize) Vec3 {
    return @select(f32, @Vector(3, bool){ c & 1 != 0, c & 2 != 0, c & 4 != 0 }, box[1], box[0]);
}

pub fn main() void {
    // delve's left frustum plane for a camera at the origin looking down
    // -z (see frustum_planes.zig): 0.781 x - 0.625 z >= 0 is inside.
    const normal: Vec3 = .{ 0.781, 0, -0.625 };
    const d: f32 = 0;

    var box = [2]Vec3{ .{ -2, 0, -4 }, .{ -1, 1, -3 } };
    std.debug.print("box ({d}, {d}, {d}) to ({d}, {d}, {d}), the left plane:\n", .{ box[0][0], box[0][1], box[0][2], box[1][0], box[1][1], box[1][2] });
    for (0..8) |c| {
        const p = corner(box, c);
        std.debug.print("  corner ({d:>2}, {d}, {d:>2})  distance {d:>6.3}\n", .{ p[0], p[1], p[2], dot(normal, p) + d });
    }
    const pv = positiveVertex(normal, box);
    std.debug.print("  @select picks ({d}, {d}, {d}): the largest distance\n\n", .{ pv[0], pv[1], pv[2] });

    std.debug.print("sliding the box left, 0.25 at a time:\n", .{});
    while (true) {
        var lowest: f32 = std.math.inf(f32);
        var highest: f32 = -std.math.inf(f32);
        for (0..8) |c| {
            const dist = dot(normal, corner(box, c)) + d;
            lowest = @min(lowest, dist);
            highest = @max(highest, dist);
        }
        const picked = dot(normal, positiveVertex(normal, box)) + d;
        const outside = picked < 0;
        std.debug.print("  x {d:>5.2} to {d:>5.2}: corners {d:>6.3} .. {d:>6.3}, picked {d:>6.3}  {s}\n", .{
            box[0][0], box[1][0], lowest, highest, picked, if (outside) "outside" else "kept",
        });
        if (outside) break;
        box[0][0] -= 0.25;
        box[1][0] -= 0.25;
    }
}
```

```console
$ zig run examples/ch23/positive_vertex.zig
box (-2, 0, -4) to (-1, 1, -3), the left plane:
  corner (-2, 0, -4)  distance  0.938
  corner (-1, 0, -4)  distance  1.719
  corner (-2, 1, -4)  distance  0.938
  corner (-1, 1, -4)  distance  1.719
  corner (-2, 0, -3)  distance  0.313
  corner (-1, 0, -3)  distance  1.094
  corner (-2, 1, -3)  distance  0.313
  corner (-1, 1, -3)  distance  1.094
  @select picks (-1, 1, -4): the largest distance

sliding the box left, 0.25 at a time:
  x -2.00 to -1.00: corners  0.313 ..  1.719, picked  1.719  kept
  x -2.25 to -1.25: corners  0.118 ..  1.524, picked  1.524  kept
  x -2.50 to -1.50: corners -0.078 ..  1.329, picked  1.329  kept
  x -2.75 to -1.75: corners -0.273 ..  1.133, picked  1.133  kept
  x -3.00 to -2.00: corners -0.468 ..  0.938, picked  0.938  kept
  x -3.25 to -2.25: corners -0.663 ..  0.743, picked  0.743  kept
  x -3.50 to -2.50: corners -0.859 ..  0.547, picked  0.547  kept
  x -3.75 to -2.75: corners -1.054 ..  0.352, picked  0.352  kept
  x -4.00 to -3.00: corners -1.249 ..  0.157, picked  0.157  kept
  x -4.25 to -3.25: corners -1.444 .. -0.038, picked -0.038  outside
```

- The normal (0.781, 0, −0.625) is positive in x, zero in y and negative in z, so `@select`
  takes the high x, the high y and the low z: (−1, 1, −4), the corner with the largest
  distance. Corners that differ only in y have the same distance, because the plane is
  vertical.
- From x = −2.5 on, some corners are outside the plane (negative), but the box is still kept,
  rightly: part of it is inside. Only at x = −4.25 is the farthest corner outside too.

The test is *conservative*: when it says "outside", the box is outside, but when it says
"keep", the box may still be outside. Seen from above, a box near a corner of the frustum can
be outside two planes, each holding part of it, while no part is inside both:

```text
                 \ left plane, extended
      +-----------\---+
      |   box      \  |
 - - -|- - - - - - -\-|- - - - - - - - - - - - - - - - far plane, extended
      +--------------\+                          /
                      \                         /
                       \       frustum         /
                        \                     /
                         \                   /
                          \                 /
                           \               /
                            \_____________/
                                 near
```

The part of the box above the far plane's line is beyond the far plane, and the part below it
is left of the left plane, so the box is out of view. But no single plane has the whole box
outside it, so `excludes` keeps it. That costs a little drawing that the triangle tests then
throw away; it never loses anything. An exact test (separating axes) is much dearer than a
false "keep" now and then.

How do we know `excludes` is right? The clipper's outcodes (Chapter 17) are the ground truth:
transform the box's eight corners, and the box is outside a plane exactly when all eight
outcodes contain that plane, when their intersection is not empty. The first test of the new
file compares the two on 2000 random boxes:

```zig
test "a box is excluded exactly when all its corners are outside one plane" {
    const cam: camera.Camera = .{ .pos = .{ 2, 0.5, 3 }, .yaw = 0.7, .pitch = 0.3 };
    const view_proj = cam.viewProjection(640, 400);
    const frustum: Frustum = .init(view_proj);
    var prng: std.Random.DefaultPrng = .init(23);
    const random = prng.random();
    var excluded: usize = 0;
    for (0..2000) |_| {
        var lo: Vec3 = undefined;
        var size: Vec3 = undefined;
        inline for (0..3) |k| {
            lo[k] = random.float(f32) * 40 - 20;
            size[k] = random.float(f32) * 4;
        }
        const box = [2]Vec3{ lo, lo + size };
        // What the clipper would say about the box's corners.
        var all: clip.Outcode = .full;
        for (0..8) |c| {
            const corner = @select(f32, @Vector(3, bool){ c & 1 != 0, c & 2 != 0, c & 4 != 0 }, box[1], box[0]);
            all = all.intersectWith(clip.outcode(view_proj.mulVec(math.vec4(corner, 1))));
        }
        try testing.expectEqual(all.count() > 0, frustum.excludes(box));
        excluded += @intFromBool(all.count() > 0);
    }
    // Both answers came up plenty of times.
    try testing.expect(excluded > 500 and excluded < 1900);
}
```

- The bits of `c`, 0 to 7, choose low or high per axis: another `@select`, with a predicate
  built from three `bool`s, makes the eight corners.
- `clip.Outcode` is a `std.EnumSet(Plane)`. Starting from `.full` and intersecting with each
  corner's set leaves the planes that all eight corners are outside of.
- The last check makes sure the test tests something: if nearly every random box were outside
  (or none), the two methods could agree without either being right about the other case.
- The camera is turned and tilted (yaw 0.7, pitch 0.3) and away from the origin, so that every
  plane has a d and all three normal coordinates are in play.

### The boxes and what is in them

The chunks have had boxes since Chapter 21 (`Chunk.box`, from the chunk's corner cell to the
opposite one, 0 to 1 high), used then to pick the lights that reach each chunk.
What they did not have is their things. The world drew all lamps and barrels in one loop after
the chunks, so a culled chunk would leave its barrels standing. Now each chunk gets slices of
its own things:

```zig
    /// The things standing in the chunk's cells.
    lamps: []const Vec2,
    barrels: []const Barrel,
```

`World.build` sorts the things by chunk, after which each chunk's things are next to each
other, and one pass hands out the slices:

```zig
        // Sorted by chunk, each chunk's things are next to each other.
        sortByChunk(Vec2, lamps.items, columns);
        sortByChunk(Barrel, barrels.items, columns);
        const lamp_slice = try lamps.toOwnedSlice(gpa);
        errdefer gpa.free(lamp_slice);
        const barrel_slice = try barrels.toOwnedSlice(gpa);
        errdefer gpa.free(barrel_slice);
        var lamp_end: usize = 0;
        var barrel_end: usize = 0;
        for (chunks, 0..) |*chunk, i| {
            const first_lamp = lamp_end;
            while (lamp_end < lamp_slice.len and chunkOf(lamp_slice[lamp_end], columns) == i) lamp_end += 1;
            chunk.lamps = lamp_slice[first_lamp..lamp_end];
            const first_barrel = barrel_end;
            while (barrel_end < barrel_slice.len and chunkOf(barrel_slice[barrel_end].pos, columns) == i) barrel_end += 1;
            chunk.barrels = barrel_slice[first_barrel..barrel_end];
        }
```

```zig
/// The chunk that map position `pos` is in.
fn chunkOf(pos: Vec2, columns: usize) usize {
    const x: usize = @intFromFloat(pos[0]);
    const y: usize = @intFromFloat(pos[1]);
    return y / chunk_size * columns + x / chunk_size;
}

/// Sorts lamps (positions) or barrels by the chunk they are in, keeping
/// the order of those in the same chunk.
fn sortByChunk(comptime T: type, things: []T, columns: usize) void {
    const ByChunk = struct {
        columns: usize,
        fn chunk(c: @This(), thing: T) usize {
            return chunkOf(if (T == Vec2) thing else thing.pos, c.columns);
        }
        fn lessThan(c: @This(), a: T, b: T) bool {
            return c.chunk(a) < c.chunk(b);
        }
    };
    std.mem.sort(T, things, ByChunk{ .columns = columns }, ByChunk.lessThan);
}
```

- `std.mem.sort` is stable (it is a block sort): things in the same chunk keep their order,
  so the picture does not depend on how the sort shuffles equal keys.
- `if (T == Vec2) thing else thing.pos` is decided at compile time. For `Vec2`, the `else`
  branch, which would not compile (a vector has no `.pos`), is never analyzed.
- One `World.lamps` slice still holds all the lamps, now in chunk order. The lights are not
  culled: a lamp in a hidden chunk still lights the walls around the corner.
- Things stand inside their cell (a barrel's radius is 0.25 around the cell's center), so a
  thing is inside its chunk's box.

## Culling chunks

With a frustum and boxes, each chunk gets a verdict, and the world draws a list of chunks
instead of all of them. There are three ways to make the list, and a key to switch between
them so they can be compared:

```zig
/// Which chunks are drawn, and which are not.
pub const Culling = enum {
    /// All of them.
    off,
    /// Those whose box is not outside the view frustum.
    frustum,
    /// Those inside the frustum that a ray through the grid can reach.
    grid,
};

pub const ChunkState = enum { drawn, outside, hidden };
```

`Visibility` holds the verdicts and the list. It is worked out once per frame, before drawing:

```zig
pub const Visibility = struct {
    /// Per map cell, row by row: did a line of sight pass through it, or
    /// through a neighbor?
    cells: []bool,
    /// Per chunk of the world.
    states: []ChunkState,
    /// The chunks to draw, in the order to draw them.
    order: []u32,
    drawn: usize = 0,
    /// Where each ray stopped, from left to right.
    ray_ends: []Vec2,
    ray_count: usize = 0,
    /// Where the eye was, on the map.
    eye: Vec2 = .{ 0, 0 },
    /// False until the first `update`.
    valid: bool = false,
```

`init` allocates the four slices once, for the map's cells, the world's chunks and the most
rays a fan can have; `deinit` frees them. Two small functions read the results:

```zig
    /// The chunks to draw.
    pub fn chunks(v: Visibility) []const u32 {
        return v.order[0..v.drawn];
    }

    pub fn count(v: Visibility, state: ChunkState) usize {
        return std.mem.count(ChunkState, v.states, &.{state});
    }
```

And `update` decides:

```zig
    /// Decides what `cam` can see of `world` (built from `map`) on a
    /// screen with this `aspect`. With `sort`, the chunks are drawn
    /// nearest first, so that the depth test rejects more pixels before
    /// they are shaded.
    pub fn update(v: *Visibility, map: Map, world: World, cam: camera.Camera, view_proj: Mat4, aspect: f32, culling: Culling, sort: bool) void {
        v.eye = .{ cam.pos[0], cam.pos[2] };
        v.valid = true;
        @memset(v.cells, false);
        v.ray_count = 0;
        if (culling == .grid) v.castRays(map, cam, aspect);

        const frustum: Frustum = .init(view_proj);
        v.drawn = 0;
        for (world.chunks, v.states, 0..) |chunk, *state, i| {
            state.* = if (culling == .off)
                .drawn
            else if (frustum.excludes(chunk.box))
                .outside
            else if (culling == .grid and !v.anySeen(map, world, i))
                .hidden
            else
                .drawn;
            if (state.* != .drawn) continue;
            v.order[v.drawn] = @intCast(i);
            v.drawn += 1;
        }
        if (sort) std.mem.sort(u32, v.order[0..v.drawn], Nearest{ .eye = v.eye, .world = world }, Nearest.lessThan);
    }
```

- The cheap test first: a chunk outside the frustum is `outside` even if a ray reached it,
  which can happen, since the rays are cast on the floor plan and know nothing of pitch.
- `castRays`, `anySeen` and `Nearest` are the next sections' topics. With `.frustum`, the cells
  stay unmarked and only the planes decide.
- `std.mem.count` counts the occurrences of a sequence, here one state long, in a slice.

`World.draw` and `World.drawWireframe` take the list as a new parameter, `chunks: []const u32`,
and loop over it instead of over all chunks. Each chunk's things are drawn with it:

```zig
        const barrel = paint.material(barrel_color, .staves);
        for (chunks) |i| {
            const chunk = world.chunks[i];
            for (std.enums.values(Surface)) |surface| {
                const part = chunk.parts.get(surface);
                if (part.indices.len == 0) continue;
                const material: light.Material = if (paint.chunk_colors)
                    .{ .color = chunkColor(i % world.columns, i / world.columns) }
                else
                    surface.material(paint);
                maze3d.drawPart(r, canvas, part, .identity, view_proj, material, shading, scene, chunk.box, options, stats);
            }
            for (chunk.lamps) |pos| maze3d.drawLamp(r, canvas, pos, view_proj, shading, scene, options, stats);
            for (chunk.barrels) |b| world.drawBarrel(r, canvas, b, view_proj, barrel, shading, scene, options, stats);
        }
```

(`drawBarrel` is the old loop body, moved into a function because the overhead view will need
it too.) In `App.render`, the visibility is updated once, before the views that show the world:

```zig
        const cam = camera.Camera.fromPlayer(p);
        const view_proj = cam.viewProjection(canvas.width, canvas.height);
        const sees_world = switch (app.view) {
            .solid, .depth, .levels, .chunks, .overdraw, .overhead, .wireframe => true,
            else => false,
        };
        // Frozen, the visibility stays as it was last worked out.
        if (sees_world and (!app.frozen or !app.visibility.valid)) {
            const aspect = @as(f32, @floatFromInt(canvas.width)) / @as(f32, @floatFromInt(canvas.height));
            app.visibility.update(app.map, app.world, cam, view_proj, aspect, app.culling, app.sort);
        }
```

`render` now changes the app, so it takes `app: *App` instead of `app: App`. The new
`App` fields are `visibility`, `culling = .grid`, `sort = true` and `frozen = false`; the V key
cycles `culling`, R toggles `sort`, and X `frozen` (the last section). `--culling NAME` sets the
culling from the command line, and the HUD gets a line for it:

```zig
        var y = h - 36;
        if (sees_world) {
            const v = app.visibility;
            var line = std.fmt.bufPrint(&buffer, "chunks {d}/{d}  outside {d}  hidden {d}  culling {t}{s}{s}", .{
                v.drawn,
                v.states.len,
                v.count(.outside),
                v.count(.hidden),
                app.culling,
                if (app.sort) "  sorted" else "",
                if (app.frozen) "  frozen" else "",
            }) catch unreachable;
            if (stats) |s| {
                // Overdraw: how often each pixel was covered, and shaded,
                // on average.
                const screen: f32 = @floatFromInt(canvas.width * canvas.height);
                const tail = std.fmt.bufPrint(buffer[line.len..], "  covered {d:.2}x  shaded {d:.2}x", .{
                    @as(f32, @floatFromInt(s.tested)) / screen,
                    @as(f32, @floatFromInt(s.pixels)) / screen,
                }) catch unreachable;
                line = buffer[0 .. line.len + tail.len];
            }
            _ = font.drawText(canvas, 8, y, line, 1, Color.white);
            y -= 12;
        }
```

- The second `bufPrint` writes into the rest of the same buffer, right after the first line,
  and the two slices are then one: `buffer[0 .. line.len + tail.len]`.
- `{t}` prints an enum's tag name, as in Chapter 19.
- The render time of Chapter 22 moves up a line when this one is shown.

Here is the start of the labyrinth with culling off, and then by the frustum alone (the HUD's
font prints everything in capitals):

```console
$ ./zig-out/bin/delve --headless --map labyrinth --culling off --out off.png
$ ./zig-out/bin/delve --headless --map labyrinth --culling frustum --out frustum.png
```

```text
CHUNKS 256/256  OUTSIDE 0  HIDDEN 0  CULLING OFF  SORTED  COVERED 1.78X  SHADED 1.00X
TRIANGLES 18410  OUTSIDE 11129  CLIPPED 309  BEHIND NEAR 0  CULLED 1663  DRAWN 5436  PIXELS 256000

CHUNKS 118/256  OUTSIDE 138  HIDDEN 0  CULLING FRUSTUM  SORTED  COVERED 1.78X  SHADED 1.00X
TRIANGLES 8266  OUTSIDE 985  CLIPPED 309  BEHIND NEAR 0  CULLED 1663  DRAWN 5436  PIXELS 256000
```

- 138 of the 256 chunks are outside the frustum, and with them go 10,144 triangles. That is
  exactly the difference in `OUTSIDE`, 11,129 − 985: every triangle the chunk test skipped
  would have been thrown out by the outcodes anyway, and the rest of the line is the same.
- 985 triangles are still outside: they are in chunks that are partly in view, or in chunks
  that are kept although outside, as in the diagram above.
- `DRAWN 5436`. The view at the start is a short corridor ending in a brick wall 2.5 cells
  away. 5436 triangles are rasterized for that, and all but a few dozen are behind the wall:
  their pixels, if they cover any, fail the depth test one by one.

That last number is why frustum culling is not enough for a maze. The frustum is 64 units deep
and widens to 102 units at the far end. In open country, most of it would be visible; in a
maze, almost everything in it is behind a wall. To refuse those chunks, we need to know what
is in the way.

## Lines of sight through the grid

The maze is a grid, and Chapter 13 already answered "what does the eye see in a grid?" exactly:
cast a ray per column, walk it cell by cell with the DDA, and stop at the first wall. Every cell
a ray passes through is visible, and a cell no ray passes through is hidden. That is the
occlusion test we need. The ray caster only has to report the cells it passes, not just the
wall at the end.

`src/raycast.zig` gets a second version of `cast` that takes a *visitor*, and `cast` becomes
that version with a visitor that does nothing:

```zig
pub fn cast(map: Map, origin: Vec2, dir: Vec2) Hit {
    return castVisiting(map, origin, dir, struct {
        fn visit(_: @This(), _: [2]i32) void {}
    }{});
}

/// `cast`, also calling `visitor.visit(cell)` for each cell the ray passes
/// through before the wall, the one it starts in first.
pub fn castVisiting(map: Map, origin: Vec2, dir: Vec2, visitor: anytype) Hit {
```

The body is the old `cast` with one new line at the top of the loop:

```zig
    while (true) {
        visitor.visit(cell);
        var side: Side = undefined;
```

- `visitor: anytype` makes `castVisiting` generic: for each visitor type it is called with,
  the compiler makes a separate copy, with `visitor.visit` a direct call that it can inline.
  The do-nothing visitor of `cast` costs nothing at all, so the ray caster is as fast as
  before. Chapter 18's `fillTriangle` calls its pixel visitor the same way.
- `struct { fn visit(...) void {} }{}` declares a struct type with one function and no
  fields, and makes a value of it on the spot.
- The visit comes before the step to the next cell, and the loop ends when the step enters a
  wall. So the wall cell itself is *not* visited. That is right for delve: a wall's faces
  belong to the floor cells in front of them (Chapter 21's `addCell`), and those were visited.

`anytype` means "anything", but the body decides what "anything" must be able to do. A visitor
without a `visit` function is caught when `castVisiting` is compiled for it:

```zig
const std = @import("std");
fn castVisiting(visitor: anytype) void {
    for (0..3) |i| visitor.visit(.{ @intCast(i), 0 });
}
const Counter = struct {
    n: *usize,
    fn mark(c: Counter, cell: [2]i32) void {
        _ = cell;
        c.n.* += 1;
    }
};
pub fn main() void {
    var n: usize = 0;
    castVisiting(Counter{ .n = &n });
    std.debug.print("{d}\n", .{n});
}
```

```console
$ zig run wrong_visitor.zig
wrong_visitor.zig:3:27: error: no field or member function named 'visit' in 'wrong_visitor.Counter'
    for (0..3) |i| visitor.visit(.{ @intCast(i), 0 });
                   ~~~~~~~^~~~~~
wrong_visitor.zig:5:17: note: struct declared here
const Counter = struct {
                ^~~~~~
```

(The "referenced by" lines that follow are left out.) The error points into the generic
function, not at the call in `main` that passed the wrong type; the note says which type it
was. That is the price of `anytype` against an interface written down in a type: the contract
is the body.

### Marking the cells

The visibility's visitor marks the cell and its eight neighbors in `Visibility.cells`:

```zig
/// Marks a cell and its eight neighbors. The neighbors make up for the
/// gaps between rays: a cell seen only between two rays is next to one
/// that a ray went through.
const Marker = struct {
    map: Map,
    cells: []bool,

    pub fn visit(m: Marker, cell: [2]i32) void {
        for (0..3) |dy| {
            for (0..3) |dx| {
                const x = cell[0] + @as(i32, @intCast(dx)) - 1;
                const y = cell[1] + @as(i32, @intCast(dy)) - 1;
                if (x < 0 or y < 0 or x >= m.map.width or y >= m.map.height) continue;
                m.cells[@as(usize, @intCast(y)) * m.map.width + @as(usize, @intCast(x))] = true;
            }
        }
    }
};
```

- `Marker` holds a slice, and a slice is a pointer and a length. Passed by value, the marker
  still writes into the visibility's `cells`.
- A finite number of rays can slip past a cell that is visible between two of them: a corner
  of a floor cell peeking out from behind a wall, say. Its neighbor, on the same line of
  sight a little closer, was visited. Marking neighbors is cheap insurance, and it can only
  add cells: it errs toward drawing too much.

How many rays? Enough that no pixel column is skipped. Looking level, column x of a W pixel
screen looks along the angle atan(a) from the view direction, with a = tan_h·(2x/W − 1), so a
radian holds W/(2·tan_h)·(1 + a²) columns: 400 in the middle of delve's 640 pixel screen
(tan_h = 0.8) and 656 at the edges, where the columns are packed closer in angle. 1024 rays per
radian is more than one per column everywhere:

```zig
/// How densely rays are cast: more than one per pixel column. Looking
/// level, column x of a screen W pixels wide looks along atan(a), with
/// a = tan_h (2x / W - 1), so there are W / (2 tan_h) (1 + a^2) columns
/// per radian: 400 in the middle of a 640 pixel screen, 656 at the edges.
pub const rays_per_radian = 1024;
/// Enough rays for all the way around.
pub const max_rays: usize = @as(usize, @intFromFloat(@ceil(std.math.tau * rays_per_radian))) + 1;
```

Looking level, the view is 2·atan(0.8) = 1.349 radians wide: 1383 rays. The fan goes from one
edge of the view to the other, and each ray's end is kept for the overhead view:

```zig
    /// Casts rays across everything the camera can see, as seen from
    /// above, and marks the cells they pass through and their neighbors.
    fn castRays(v: *Visibility, map: Map, cam: camera.Camera, aspect: f32) void {
        const half = groundSpan(cam.pitch, aspect) orelse std.math.pi;
        const n: usize = @intFromFloat(@ceil(2 * half * rays_per_radian));
        const marker: Marker = .{ .map = map, .cells = v.cells };
        for (0..n + 1) |k| {
            const t = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n));
            const dir = math.fromAngle(cam.yaw - half + 2 * half * t);
            const hit = raycast.castVisiting(map, v.eye, dir, marker);
            v.ray_ends[k] = v.eye + math.scale(dir, hit.t);
        }
        v.ray_count = n + 1;
    }
```

- `groundSpan` is half the view's angle as seen from above, `atan(0.8)` when looking level. The
  next section works it out for looking up and down.
- n + 1 rays for n gaps, so both edges of the view get a ray.
- Unlike Chapter 13's rays, these are spaced evenly in angle, not across the screen. That is
  simpler and puts more rays in the middle than needed, which is harmless.

A chunk is hidden if none of its cells was marked:

```zig
    /// True if any cell of chunk `i` was marked.
    fn anySeen(v: Visibility, map: Map, world: World, i: usize) bool {
        const x0 = (i % world.columns) * chunk_size;
        const y0 = (i / world.columns) * chunk_size;
        for (y0..@min(y0 + chunk_size, map.height)) |y| {
            for (x0..@min(x0 + chunk_size, map.width)) |x| {
                if (v.cells[y * map.width + x]) return true;
            }
        }
        return false;
    }
```

The `@min`s are for the chunks along the right and bottom edges, which are cut short when the
map's size is not a multiple of 4.

The example does the same on a small map, printing what the rays crossed (`*`) and what they
marked as a neighbor (`+`), with delve's 1024 rays per radian and with only 4:

`examples/ch23/ray_fan.zig`:

```zig
//! Which cells of a grid map can the eye see? Cast a fan of rays across
//! the view, as seen from above, and follow each through the grid with a
//! DDA until it enters a wall. Mark every cell a ray passes through (*) and
//! the eight cells around it (+). Prints the map for a dense fan (1024 rays
//! per radian, as delve casts) and a sparse one, and how many rays a fan
//! needs when looking up.
const std = @import("std");

const map_text = [_][]const u8{
    "########################",
    "#......#...............#",
    "#......#....######.....#",
    "#..........#.....#.....#",
    "#......#...#.....#.....#",
    "####.###...#.....#######",
    "#......#...###.###.....#",
    "#......................#",
    "#......#...............#",
    "########################",
};
const width = map_text[0].len;
const height = map_text.len;

const Mark = enum { none, near, crossed };

fn isWall(x: i32, y: i32) bool {
    if (x < 0 or y < 0 or x >= width or y >= height) return true;
    return map_text[@intCast(y)][@intCast(x)] == '#';
}

/// Follows the ray from `origin` along `dir`, calling `visit` for each
/// cell before the wall it stops at.
fn cast(origin: [2]f32, dir: [2]f32, marks: *[height][width]Mark) void {
    const inf = std.math.inf(f32);
    const delta = [2]f32{
        if (dir[0] == 0) inf else @abs(1 / dir[0]),
        if (dir[1] == 0) inf else @abs(1 / dir[1]),
    };
    var cell = [2]i32{ @intFromFloat(@floor(origin[0])), @intFromFloat(@floor(origin[1])) };
    var step: [2]i32 = undefined;
    var next: [2]f32 = undefined;
    for (0..2) |i| {
        const fc: f32 = @floatFromInt(cell[i]);
        step[i] = if (dir[i] < 0) -1 else 1;
        next[i] = if (dir[i] < 0) (origin[i] - fc) * delta[i] else (fc + 1 - origin[i]) * delta[i];
    }
    while (true) {
        visit(marks, cell);
        const i: usize = if (next[0] < next[1]) 0 else 1;
        next[i] += delta[i];
        cell[i] += step[i];
        if (isWall(cell[0], cell[1])) return;
    }
}

/// Marks `cell` as crossed and its neighbors as near.
fn visit(marks: *[height][width]Mark, cell: [2]i32) void {
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            const x = cell[0] + dx;
            const y = cell[1] + dy;
            if (x < 0 or y < 0 or x >= width or y >= height) continue;
            const m = &marks[@intCast(y)][@intCast(x)];
            if (dx == 0 and dy == 0) m.* = .crossed else if (m.* == .none) m.* = .near;
        }
    }
}

/// Half the angle the view covers on the floor (see visibility.zig), or
/// null when it covers all the way around.
fn groundSpan(pitch: f32) ?f32 {
    const tan_v = 0.5;
    const tan_h = 0.8;
    const ahead = @cos(pitch) - tan_v * @abs(@sin(pitch));
    if (ahead <= 0) return null;
    return std.math.atan(tan_h / ahead);
}

fn fan(eye: [2]f32, yaw: f32, pitch: f32, rays_per_radian: f32) void {
    var marks: [height][width]Mark = @splat(@splat(.none));
    const half = groundSpan(pitch) orelse std.math.pi;
    const n: usize = @intFromFloat(@ceil(2 * half * rays_per_radian));
    for (0..n + 1) |k| {
        const a = yaw - half + 2 * half * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n));
        cast(eye, .{ @cos(a), @sin(a) }, &marks);
    }
    var crossed: usize = 0;
    var near: usize = 0;
    std.debug.print("{d} rays per radian: {d} rays\n", .{ rays_per_radian, n + 1 });
    for (map_text, marks, 0..) |row, mark_row, y| {
        std.debug.print("  ", .{});
        for (row, mark_row, 0..) |c, m, x| {
            const at_eye = x == @as(usize, @intFromFloat(eye[0])) and y == @as(usize, @intFromFloat(eye[1]));
            const shown: u8 = if (at_eye) '@' else switch (m) {
                .crossed => '*',
                .near => '+',
                .none => c,
            };
            crossed += @intFromBool(m == .crossed);
            near += @intFromBool(m == .near);
            std.debug.print("{c}", .{shown});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("  crossed {d}, near {d}\n", .{ crossed, near });
}

pub fn main() void {
    // Standing in the west room, looking east (yaw 0, x right, y down).
    const eye = [2]f32{ 2.5, 3.5 };
    fan(eye, 0, 0, 1024);
    fan(eye, 0, 0, 4);

    std.debug.print("rays for the whole view, 1024 per radian:\n", .{});
    for ([_]f32{ 0, 0.5, 1.0, 1.2 }) |pitch| {
        if (groundSpan(pitch)) |half| {
            const n: usize = @intFromFloat(@ceil(2 * half * 1024));
            std.debug.print("  pitch {d:.1}: half span {d:.3} rad, {d} rays\n", .{ pitch, half, n + 1 });
        } else {
            std.debug.print("  pitch {d:.1}: all around, {d} rays\n", .{ pitch, @as(usize, @intFromFloat(@ceil(std.math.tau * 1024.0))) + 1 });
        }
    }
}
```

```console
$ zig run examples/ch23/ray_fan.zig
1024 rays per radian: 1383 rays
  ###+++++################
  #.++***++++++..........#
  #++****+****+#####.....#
  #+@********++....#.....#
  #++****+***+.....#.....#
  ##++*+++++++.....#######
  #..+++.#...###.###.....#
  #......................#
  #......#...............#
  ########################
  crossed 28, near 36
4 rays per radian: 7 rays
  ###+++++################
  #.++***+...............#
  #++****+++++######.....#
  #+@********+.....#.....#
  #++****+++++.....#.....#
  ##++*+++...#.....#######
  #..+++.#...###.###.....#
  #......................#
  #......#...............#
  ########################
  crossed 21, near 32
rays for the whole view, 1024 per radian:
  pitch 0.0: half span 0.675 rad, 1383 rays
  pitch 0.5: half span 0.898 rad, 1840 rays
  pitch 1.0: half span 1.422 rad, 2915 rays
  pitch 1.2: all around, 6435 rays
```

- The eye (`@`) is in the west room, looking east. The rays cross the room, go through the gap
  at x = 7 in row 3, and fan out into the middle area beyond it. The `+`s include walls: a wall
  next to a crossed cell is marked too, which does no harm, since walls have no faces of their
  own.
- The marks are conservative. Row 1 from x = 8 to 12 is marked, because the cells below it
  were crossed, but it is not visible: a line from the eye to row 1 there would have to pass
  the wall at x = 7 above the gap. Marked-but-hidden costs some drawing; hidden-but-marked
  would cost a hole in the picture, and the neighbors make that much less likely.
- Seven rays mark 21 cells crossed and 32 near, against 28 and 36 for 1383 rays. In a room this
  small, the neighbors fill most of the gaps. They would not across the labyrinth: at 4 rays
  per radian, two rays 10 cells out are 2.5 cells apart, while at 1024 per radian, two rays
  64 cells out are 0.06 cells apart.
- Looking up or down takes more rays, all the way around at pitch 1.2. That is the next
  section.

Back in delve, a test on a small map checks that walls hide what is behind them:

```zig
test "walls hide the cells behind them" {
    const gpa = testing.allocator;
    var map: Map = try .parse(gpa,
        \\##########
        \\#>.......#
        \\#.########
        \\#........#
        \\##########
    );
    defer map.deinit(gpa);
    var world: World = try .build(gpa, map);
    defer world.deinit(gpa);
    var v: Visibility = try .init(gpa, map, world);
    defer v.deinit(gpa);
    const at = struct {
        fn at(vis: Visibility, x: usize, y: usize) bool {
            return vis.cells[y * 10 + x];
        }
    }.at;

    // Looking east along the top corridor: all of it is seen, the bottom
    // corridor is not, except next to the opening at x = 1.
    var cam: camera.Camera = .{ .pos = .{ 1.5, 0.5, 1.5 }, .yaw = 0 };
    v.update(map, world, cam, cam.viewProjection(640, 400), 1.6, .grid, true);
    for (1..9) |x| try testing.expect(at(v, x, 1));
    for (3..9) |x| try testing.expect(!at(v, x, 3));

    // Looking south from the same spot, down into the bottom corridor.
    cam.yaw = std.math.pi / 2.0;
    v.update(map, world, cam, cam.viewProjection(640, 400), 1.6, .grid, true);
    try testing.expect(at(v, 1, 3) and at(v, 2, 3));
    try testing.expect(!at(v, 8, 1) and !at(v, 8, 3));
}
```

- Two corridors joined at the west end by the opening at (1, 2). Looking east from (1.5, 1.5),
  the top corridor is marked to the end and the bottom one from x = 3 on is not.
- Looking south, the rays go down through the opening into the bottom corridor, but not along
  either corridor to x = 8.
- `struct { fn at(...) ... }.at` is the way to write a local function in Zig: a function can
  only be declared in a container, so the test declares a struct with one and takes it out.

With all this, the start of the labyrinth by `--culling grid`, the default:

```console
$ ./zig-out/bin/delve --headless --map labyrinth --out grid.png
```

```text
CHUNKS 2/256  OUTSIDE 138  HIDDEN 116  CULLING GRID  SORTED  COVERED 1.31X  SHADED 1.00X
TRIANGLES 106  OUTSIDE 23  CLIPPED 18  BEHIND NEAR 0  CULLED 12  DRAWN 71  PIXELS 256000
```

Two chunks out of 256, 106 triangles instead of 18,410, and the picture is the one Chapter 22
drew: the corridor with the stone wall on the left, the brick on the right and straight ahead,
and on the minimap a short fan of sight lines stopping at the walls close by. Of the 118
chunks in the frustum, 116 are behind the walls of this corridor. Each pixel is still covered
1.31 times, because a chunk is all or nothing: the two chunks drawn also hold walls and floor
around the corner from the eye, which face it and are drawn, and fail the depth test.

## Looking up and down

The rays are cast on the floor plan, so the fan has to cover the view as seen from above. Looking
level, that is the horizontal field of view, ±atan(0.8). Looking up or down, it is wider. Tilt
your head down toward your feet and you see the floor beside them, well to the left and right
of where you face: the view's footprint on the floor spreads sideways.

How wide is it? Every view ray is the camera's forward vector plus some of its right and up
vectors: forward + a·right + b·up, with |a| ≤ tan_h = 0.8 and |b| ≤ tan_v = 0.5 for the edges of
the screen. Now look at the three vectors from above, with the camera pitched by angle p:

- `forward` points along the view direction, tilted up by p, so from above it is cos(p) long.
- `up` is tilted back by p. From above it points *against* the view direction, sin(p) long.
- `right` is level, 1 long, across the view direction.

So from above, the ray goes cos(p) − b·sin(p) along the view direction and a across it, and its
angle from the view direction is atan(a / (cos(p) − b·sin(p))). That is largest for the largest
a, tan_h, and the smallest distance ahead, which is at the screen edge where b·sin(p) is
largest: b = tan_v with the sign of p. The half-width of the fan is

```text
atan(tan_h / (cos(p) − tan_v·|sin(p)|))
```

When the distance ahead reaches 0, the edge of the screen looks straight up (or down), and the
view reaches all the way around: some rays near that edge go backward, seen from above. That
happens at tan(p) = 1/tan_v = 2, a pitch of 63.4°.

```zig
/// How half the view looks from above: the angle between the view
/// direction and the farthest view ray, both seen on the floor, for a
/// screen with this `aspect`. Null if the view reaches all around, which
/// happens when looking steeply up or down.
pub fn groundSpan(pitch: f32, aspect: f32) ?f32 {
    // A view ray is forward + a right + b up, with |a| <= tan_h and |b| <=
    // tan_v. Seen from above, forward is cos(pitch) long and up is
    // -sin(pitch) long along the view direction, and right is 1 long
    // across it. The ray turns farthest from the view direction with a at
    // its largest and the part along the view direction at its smallest.
    const tan_v = @tan(camera.vfov / 2);
    const tan_h = tan_v * aspect;
    const ahead = @cos(pitch) - tan_v * @abs(@sin(pitch));
    if (ahead <= 0) return null;
    return std.math.atan(tan_h / ahead);
}
```

`castRays` turns `null` into π, a full circle, with `orelse std.math.pi`. The example printed the
ray counts: 1383 rays looking level, 1840 at pitch 0.5, 2915 at 1.0, and 6435, all the way
around, at 1.2. A test pins the formula down:

```zig
test "the view reaches farther around when looking up or down" {
    const level = groundSpan(0, 1.6).?;
    try testing.expectApproxEqAbs(std.math.atan(@as(f32, 0.8)), level, 1e-6);
    try testing.expect(groundSpan(0.5, 1.6).? > level);
    try testing.expectEqual(groundSpan(0.5, 1.6), groundSpan(-0.5, 1.6));
    // tan(pitch) = 1 / tan_v = 2: the top of the screen looks straight up.
    try testing.expect(groundSpan(std.math.atan(@as(f32, 1.99)), 1.6) != null);
    try testing.expectEqual(null, groundSpan(std.math.atan(@as(f32, 2.01)), 1.6));
}
```

- Level, the fan is exactly the horizontal field of view.
- Looking down by 0.5 is the same as looking up by 0.5. Looking up, the top edge of the screen
  leans back; looking down, the bottom edge does.
- The switch to "all around" is between tan(p) = 1.99 and 2.01, on either side of 1/tan_v.

Why not always cast all the way around, to be safe? It would be correct, but 6435 rays instead
of 1383, and every cell in all directions would be marked, so the frustum would have to do all
the culling behind the player. Casting only the view's footprint keeps the two tests
independent: either one can refuse a chunk.

## Is it safe?

Culling may only remove work. If it ever removes a chunk that has a visible pixel, there is a
hole in the world. The final test of `visibility.zig` draws six poses on both maps twice, once
with every chunk and once with grid culling, and demands identical pictures and depth buffers:

```zig
test "culling never changes the picture" {
    const gpa = testing.allocator;
    const maze3d = @import("maze3d.zig");
    const render3d = @import("render3d.zig");
    const Canvas = @import("canvas.zig").Canvas;
    var all_canvas = try Canvas.init(gpa, 640, 400);
    defer all_canvas.deinit(gpa);
    var culled_canvas = try Canvas.init(gpa, 640, 400);
    defer culled_canvas.deinit(gpa);
    var r = try render3d.Renderer.init(gpa, 1024, 640, 400);
    defer r.deinit(gpa);
    const all_depth = try gpa.alloc(f32, 640 * 400);
    defer gpa.free(all_depth);
    const poses = [_]struct { map: []const u8, x: f32, y: f32, yaw: f32, pitch: f32 }{
        .{ .map = "cellar", .x = 9.5, .y = 10.5, .yaw = -1, .pitch = 0 },
        .{ .map = "cellar", .x = 1.3, .y = 1.3, .yaw = 0.8, .pitch = 1.0 },
        .{ .map = "labyrinth", .x = 2.5, .y = 1.5, .yaw = 1.57, .pitch = 0 },
        .{ .map = "labyrinth", .x = 12.5, .y = 15.5, .yaw = 0, .pitch = 0.2 },
        .{ .map = "labyrinth", .x = 40.5, .y = 9.5, .yaw = 2.2, .pitch = -0.8 },
        .{ .map = "labyrinth", .x = 36.5, .y = 12.5, .yaw = -0.7, .pitch = 1.3 },
    };
    for (poses) |pose| {
        var map = try Map.parse(gpa, @import("map.zig").builtin.get(pose.map).?);
        defer map.deinit(gpa);
        var world: World = try .build(gpa, map);
        defer world.deinit(gpa);
        var v: Visibility = try .init(gpa, map, world);
        defer v.deinit(gpa);
        const cam: camera.Camera = .{ .pos = .{ pose.x, camera.eye_height, pose.y }, .yaw = pose.yaw, .pitch = pose.pitch };
        const view_proj = cam.viewProjection(640, 400);
        const scene: @import("light.zig").Scene = .{ .ambient = @splat(1), .lights = &.{}, .eye = cam.pos };
        const paint: maze3d.Paint = .{ .chunk_colors = true };
        for ([_]Culling{ .off, .grid }, [_]Canvas{ all_canvas, culled_canvas }) |culling, canvas| {
            v.update(map, world, cam, view_proj, 1.6, culling, culling != .off);
            canvas.clear(.hex(0xff00ff));
            r.clearDepth();
            var stats: render3d.Stats = .{};
            world.draw(r, canvas, view_proj, v.chunks(), paint, .unlit, scene, .{}, &stats);
            if (culling == .off) @memcpy(all_depth, r.depth);
        }
        try testing.expect(v.drawn < world.chunks.len);
        try testing.expectEqualSlices(f32, all_depth, r.depth);
        try testing.expectEqualSlices(Color, all_canvas.pixels, culled_canvas.pixels);
    }
}
```

- The poses include looking steeply up (1.3, beyond 63.4°, so the fan goes all around) and down
  (−0.8), a corner of the cellar, and the big room.
- Chunk colors, unlit: if a wrong chunk were drawn in place of a culled one, a different color
  would show, and magenta would show through a hole.
- The depth buffers are compared too. Depth is the stricter check: a surface drawn with the
  same color but in a different place would show up there.
- The off pass is drawn in map order, the grid pass sorted, so the test also shows that the
  order does not change the picture.
- `v.drawn < world.chunks.len` makes sure each pose culls something, or the test would be
  comparing the picture with itself.

The test's six poses, and the pictures of this chapter (the same, pixel for pixel above the
HUD, as Chapter 22's at the labyrinth's start and at tour frame 700), are evidence, not a
proof. Grid culling assumes three things
that are true of delve and could stop being true:

- Nothing is taller than a wall. A tower sticking up above the walls would be visible over
  them, but the rays stop at the walls.
- The world is a grid, and walls fill whole cells. A world of arbitrary polygons needs another
  method, such as portals (exercise 1) or a precomputed table (exercise 2).
- Things stay inside their cell, so they are inside their chunk's box.

### Exact or conservative

Visibility methods split into two camps. An *exact* method finds precisely what is visible,
like the ray caster drawing walls or a depth buffer finding pixels. A *conservative* method
finds a superset: it may keep something hidden, but it never drops something visible. Culling
can afford to be conservative, because the depth test after it is exact: whatever culling keeps
by mistake is drawn and then hidden, at some cost, but the picture stays right. Every culling
scheme in games works this way. Quake's precomputed sets, for instance, were generous by
design: each place in a level was given a list of everything visible from *anywhere* in it.

## Nearest first

Culling decides *which* chunks are drawn. The order they are drawn in matters too, because of
where the depth test sits. Since Chapter 18 it runs in `Fragment.pixel` before the shader: a
pixel behind something already drawn is rejected before any lighting or texture work. So if
the near walls are drawn first, the far ones fail the test cheaply. Drawn the other way round,
every far wall is shaded and then painted over.

`update` sorts the chunks to draw by the distance from the eye to their centers, seen from
above:

```zig
/// Orders chunks by the distance from the eye to their centers.
const Nearest = struct {
    eye: Vec2,
    world: World,

    fn distance(n: Nearest, i: u32) f32 {
        const box = n.world.chunks[i].box;
        const center = math.scale(box[0] + box[1], 0.5);
        const d = Vec2{ center[0], center[2] } - n.eye;
        return math.dot(d, d);
    }

    fn lessThan(n: Nearest, a: u32, b: u32) bool {
        return n.distance(a) < n.distance(b);
    }
};
```

- The squared distance orders the same as the distance, without a square root.
- The sort is over chunk numbers, and the context, a `Nearest`, is what lets `lessThan` look
  up their boxes. `std.mem.sort` passes it to every comparison.
- Distances are worked out again in every comparison, about n·log₂(n) times. For a few dozen
  chunks that is nothing; for thousands, it would pay to compute them once into an array.

The chunk centers are only an approximation of "nearer": chunks are 4 cells wide, and one can
be nearer by its center and still be partly behind another. That is fine. The order only affects how much work
the depth test saves, never the picture, as the safety test showed.

The R key toggles the sorting. A test checks the order, and the counts while it is at it:

```zig
test "chunks are drawn nearest first" {
    const gpa = testing.allocator;
    var map = try Map.parse(gpa, @import("map.zig").builtin.get("labyrinth").?);
    defer map.deinit(gpa);
    var world: World = try .build(gpa, map);
    defer world.deinit(gpa);
    var v: Visibility = try .init(gpa, map, world);
    defer v.deinit(gpa);
    const cam: camera.Camera = .fromPlayer(.{ .pos = map.start, .yaw = map.start_yaw });
    const view_proj = cam.viewProjection(640, 400);

    v.update(map, world, cam, view_proj, 1.6, .off, false);
    try testing.expectEqual(world.chunks.len, v.drawn);
    v.update(map, world, cam, view_proj, 1.6, .frustum, false);
    const in_frustum = v.drawn;
    v.update(map, world, cam, view_proj, 1.6, .grid, true);
    try testing.expect(v.drawn < in_frustum and in_frustum < world.chunks.len);
    try testing.expectEqual(world.chunks.len, v.drawn + v.count(.outside) + v.count(.hidden));
    const nearest: Nearest = .{ .eye = v.eye, .world = world };
    for (v.chunks()[1..], v.chunks()[0 .. v.drawn - 1]) |b, a| {
        try testing.expect(nearest.distance(a) <= nearest.distance(b));
    }
}
```

- Each culling method draws fewer chunks than the one before, and every chunk is in exactly one
  state.
- The loop pairs each chunk with the one before it, by iterating over two overlapping slices of
  the same list.

How much can the order save? The example draws 200 random rectangles at random depths into a
small depth buffer, in three orders, and counts what the depth test lets through:

`examples/ch23/overdraw_sort.zig`:

```zig
//! Why draw nearest first? The depth test runs before the shader: a pixel
//! behind something already drawn is rejected before it costs any shading.
//! Draws 200 random rectangles, each at one random depth, into a small
//! depth buffer three times: in random order, far to near, and near to
//! far. Counts the pixels covered (depth tested) and the pixels shaded
//! (passed the test), per pixel of the screen.
const std = @import("std");

const w = 160;
const h = 100;

const Rect = struct { x: usize, y: usize, rw: usize, rh: usize, depth: f32 };

fn draw(rects: []const Rect, name: []const u8) void {
    var depth: [w * h]f32 = @splat(1);
    var covered: usize = 0;
    var shaded: usize = 0;
    for (rects) |r| {
        for (r.y..r.y + r.rh) |y| {
            for (r.x..r.x + r.rw) |x| {
                covered += 1;
                const i = y * w + x;
                if (r.depth >= depth[i]) continue;
                depth[i] = r.depth;
                shaded += 1; // here a shader would run
            }
        }
    }
    // Pixels no rectangle covers stay at depth 1.
    var seen: usize = 0;
    for (depth) |z| seen += @intFromBool(z < 1);
    const screen: f32 = w * h;
    std.debug.print("{s:<14} covered {d:.2}x  shaded {d:.2}x  shaded per pixel seen {d:.2}x\n", .{
        name,
        @as(f32, @floatFromInt(covered)) / screen,
        @as(f32, @floatFromInt(shaded)) / screen,
        @as(f32, @floatFromInt(shaded)) / @as(f32, @floatFromInt(seen)),
    });
}

fn nearer(_: void, a: Rect, b: Rect) bool {
    return a.depth < b.depth;
}

fn farther(_: void, a: Rect, b: Rect) bool {
    return a.depth > b.depth;
}

pub fn main() void {
    var prng: std.Random.DefaultPrng = .init(23);
    const random = prng.random();
    var rects: [200]Rect = undefined;
    for (&rects) |*r| {
        const rw = random.intRangeAtMost(usize, 10, 60);
        const rh = random.intRangeAtMost(usize, 6, 40);
        r.* = .{
            .x = random.uintLessThan(usize, w - rw + 1),
            .y = random.uintLessThan(usize, h - rh + 1),
            .rw = rw,
            .rh = rh,
            .depth = random.float(f32),
        };
    }
    draw(&rects, "random order");
    std.mem.sort(Rect, &rects, {}, farther);
    draw(&rects, "far to near");
    std.mem.sort(Rect, &rects, {}, nearer);
    draw(&rects, "near to far");
}
```

```console
$ zig run examples/ch23/overdraw_sort.zig
random order   covered 9.77x  shaded 2.18x  shaded per pixel seen 2.30x
far to near    covered 9.77x  shaded 9.77x  shaded per pixel seen 10.30x
near to far    covered 9.77x  shaded 0.95x  shaded per pixel seen 1.00x
```

- Each rectangle covers the same pixels whatever the order, so `covered` is 9.77 every time.
- Far to near is the worst case: every rectangle is nearer than everything before it, so every
  pixel covered is shaded. That is the painter's algorithm of Chapter 18, which draws back to
  front on purpose.
- Near to far is the best case: each pixel is shaded exactly once, by the rectangle that ends
  up visible. (0.95 per pixel of the screen, because 5% of it is not covered at all.)
- Random order lands in between, 2.30 per pixel. A pixel covered by k layers in random order is
  shaded each time a layer nearer than all before it arrives, which happens 1 + 1/2 + ... + 1/k
  times on average: the harmonic number, which grows only like ln(k).

In delve, at frame 700 of the tour with culling off, the R key gives:

```console
$ ./zig-out/bin/delve --headless --demo tour --frames 700 --culling off --press toggle_sorting --out unsorted.png
$ ./zig-out/bin/delve --headless --demo tour --frames 700 --culling off --out sorted.png
```

```text
CHUNKS 256/256  OUTSIDE 0  HIDDEN 0  CULLING OFF  COVERED 1.46X  SHADED 1.34X
TRIANGLES 18410  OUTSIDE 17646  CLIPPED 143  BEHIND NEAR 0  CULLED 184  DRAWN 575  PIXELS 344095

CHUNKS 256/256  OUTSIDE 0  HIDDEN 0  CULLING OFF  SORTED  COVERED 1.46X  SHADED 1.05X
TRIANGLES 18410  OUTSIDE 17646  CLIPPED 143  BEHIND NEAR 0  CULLED 184  DRAWN 575  PIXELS 268695
```

The same triangles cover the same pixels, 1.46 times each, but sorted, 75,400 fewer of them are
shaded: 22% of the frame's shading, for sorting a list of numbers. It does not reach 1.00
because only chunks are sorted, not the triangles inside a chunk, and things are drawn after
their chunk's walls and floor.

## Seeing overdraw

Averages hide where the overdraw is. A new view, `overdraw`, paints each pixel by how many
times it was covered. The renderer gets a byte per pixel to count in, cleared with the depth
buffer:

```zig
    /// How many times each pixel was covered, with `count_overdraw`.
    overdraw: []u8,
```

```zig
    /// Starts a frame: nothing drawn yet, everything is at the far plane.
    pub fn clearDepth(r: Renderer) void {
        @memset(r.depth, 1);
        @memset(r.overdraw, 0);
    }
```

Counting is switched on by a new field of `render3d.Options`, `count_overdraw`. `drawMesh`
hands the fragment the counts, or an empty slice when the option is off:

```zig
                    .overdraw = if (options.count_overdraw) r.overdraw else &.{},
```

and `Fragment.pixel`, as shown at the start of the chapter, adds one with
`if (f.overdraw.len > 0) f.overdraw[i] +|= 1;`, before the depth test.

- `+|=` is saturating addition: at 255 it stays 255 instead of wrapping to 0 (which would
  panic in a safe build). No pixel in delve gets near 255, but a view that counts must not
  crash on a weird scene.
- The empty slice is the off switch: one length check per pixel, instead of a pointer that may
  be null.

The counts become colors with a fixed palette:

```zig
    /// Paints how many times each pixel was covered, counted with
    /// `count_overdraw`: black for none, blue for once, through green and
    /// yellow to red for `overdraw_colors.len - 1` times or more.
    pub fn drawOverdraw(r: Renderer, canvas: Canvas) void {
        for (r.overdraw, canvas.pixels) |n, *pixel| {
            pixel.* = overdraw_colors[@min(n, overdraw_colors.len - 1)];
        }
    }
};

pub const overdraw_colors = [_]Color{
    .hex(0x000000), .hex(0x2040a0), .hex(0x2090b0), .hex(0x30a040), .hex(0xa0c030),
    .hex(0xe0c020), .hex(0xe08020), .hex(0xd03020), .hex(0xffffff),
};
```

The last color, white, means 8 or more. In `App.render`, the `overdraw` view draws the world as
the solid view does, with `options.count_overdraw = app.view == .overdraw`, then paints over
the picture with `drawOverdraw` and a key of the colors along the top (`drawOverdrawKey`, small
rectangles with numbers in them). The test draws a cube with back faces kept, so that the front
and back faces both cover its middle:

```zig
test "overdraw counts every triangle that covers a pixel" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 40);
    defer r.deinit(gpa);
    const cube = @import("mesh.zig").cube;
    const vp = camera.Camera.projection(64, 40);
    const model = Mat4.translation(.{ -0.5, -0.5, -3 });
    const white: Flat = .{ .color = Color.white };

    // Without culling, the front face and the back face cover the middle.
    r.clearDepth();
    var stats: Stats = .{};
    r.drawMesh(canvas, cube, model, vp, white, .{ .cull_back_faces = false, .count_overdraw = true }, &stats);
    try std.testing.expectEqual(2, r.overdraw[20 * 64 + 32]);
    var covered: u32 = 0;
    for (r.overdraw) |n| covered += n;
    try std.testing.expectEqual(stats.tested, covered);
    try std.testing.expect(stats.pixels < stats.tested);

    r.drawOverdraw(canvas);
    try std.testing.expectEqual(overdraw_colors[2], canvas.get(32, 20));
    try std.testing.expectEqual(overdraw_colors[0], canvas.get(0, 0));
}
```

- The cube is straight ahead, so the middle pixel is covered by the front face and the back
  face: 2. The four side faces show around the middle on the screen, not over it.
- The counts add up to `Stats.tested`: the two counters count the same thing.
- `pixels < tested`: some of those coverings failed the depth test.

Here is frame 700 of the tour, first as Chapter 22 drew it, everything in map order, then with
grid culling and sorting:

```console
$ ./zig-out/bin/delve --headless --demo tour --frames 700 --culling off --press toggle_sorting \
    --view overdraw --out ../../images/ch23-overdraw-off.png
$ ./zig-out/bin/delve --headless --demo tour --frames 700 --view overdraw --out ../../images/ch23-overdraw.png
```

![The overdraw view at frame 700 of the tour with culling off and no sorting. Most of the screen is dark blue, covered once: floor, ceiling and the near walls. Across the middle runs a horizontal band, where the far walls of the maze line up behind each other: teal and green near the left, yellow through the middle, and orange, red and white at the right. A key of colors numbered 1 to 8+ runs along the top left. The HUD reads CHUNKS 256/256, COVERED 1.46X, SHADED 1.34X, DRAWN 575.](images/ch23-overdraw-off.png)

![The same frame with grid culling and sorting. The screen is mostly dark blue, with a few teal and green patches in the middle where walls and the barrel overlap, and one small yellow-green patch. The band of yellow, red and white is gone. The HUD reads CHUNKS 6/256, COVERED 1.20X, SHADED 1.05X, TRIANGLES 498, DRAWN 230.](images/ch23-overdraw.png)

- The bright band is at eye height, where the vertical walls of the whole maze stack up behind
  each other in a straight line from the eye. Floor and ceiling are covered once: there is
  nothing between them and the eye.
- The white at the right is 8 or more layers deep, a direction in which many walls line up
  behind one another.
- With grid culling, `DRAWN` falls from 575 to 230. The 345 triangles that went are ones that
  the outcodes kept, since they are in view and face the eye, but that are hidden behind
  walls. Only the rays could find that out early.
- What is left, 1.20, is overdraw *inside* the six chunks still drawn: their own walls behind
  their own walls, and the barrel over the floor.

## Seeing what was culled

The HUD counts chunks, but it does not show *which* ones. A second new view, `overhead`, looks
at the maze from above and behind the player and paints every chunk by its state. Its camera is
12 units up and 6 cells behind the player, tilted down to look at a point 5 cells ahead of the
player: down by atan(12/11), since that point is 11 cells away horizontally.

```zig
            .overhead => {
                canvas.clear(.hex(0x101018));
                // Above and behind the player, looking down past the
                // player to where the player looks.
                const dir = math.fromAngle(p.yaw);
                const above: camera.Camera = .{
                    .pos = .{ p.pos[0] - 6 * dir[0], 12, p.pos[1] - 6 * dir[1] },
                    .yaw = p.yaw,
                    .pitch = -std.math.atan(@as(f32, 12.0 / 11.0)),
                };
                const above_proj = above.viewProjection(canvas.width, canvas.height);
                app.renderer3d.clearDepth();
                var overhead_stats: render3d.Stats = .{};
                app.world.drawOverhead(app.renderer3d, canvas, above_proj, app.visibility.states, paint, app.render_options, &overhead_stats);
                app.drawSightLines(canvas, above_proj);
            },
```

The visibility is still the player's, worked out before the switch from the player's camera;
only the picture comes from the camera above. `World.drawOverhead` draws every chunk, without
ceilings (which would hide everything from above) and without light:

```zig
    pub fn drawOverhead(
        world: World,
        r: render3d.Renderer,
        canvas: Canvas,
        view_proj: Mat4,
        states: []const ChunkState,
        paint: maze3d.Paint,
        options: render3d.Options,
        stats: *render3d.Stats,
    ) void {
        const dark: light.Scene = .{ .ambient = @splat(1), .lights = &.{}, .eye = @splat(0) };
        const barrel = paint.material(barrel_color, .staves);
        for (world.chunks, states) |chunk, state| {
            for ([_]Surface{ .brick, .stone, .floor }) |surface| {
                const material: light.Material = switch (state) {
                    .drawn => surface.material(paint),
                    .outside => .{ .color = .hex(0x404c70) },
                    .hidden => .{ .color = .hex(0x803838) },
                };
                r.drawMesh(canvas, chunk.parts.get(surface), .identity, view_proj, maze3d.FlatShader{ .material = material }, options, stats);
            }
            if (state != .drawn) continue;
            for (chunk.lamps) |pos| maze3d.drawLamp(r, canvas, pos, view_proj, .unlit, dark, options, stats);
            for (chunk.barrels) |b| world.drawBarrel(r, canvas, b, view_proj, barrel, .unlit, dark, options, stats);
        }
    }
```

Drawn chunks look as in the game, chunks outside the frustum are dim blue, and hidden ones dim
red. On top, `App.drawSightLines` draws the fan's outline in yellow, from the eye along the
first ray, from ray end to ray end, and back along the last ray, and a green dot where the
player stands. A line on the floor is two points projected with the overhead camera:

```zig
/// A line on the floor between map points `a` and `b`, seen through
/// `view_proj`, on top of whatever is drawn.
fn floorLine(canvas: Canvas, view_proj: Mat4, a: Vec2, b: Vec2, color: Color) void {
    var points: [2]draw.Point = undefined;
    for (&points, [_]Vec2{ a, b }) |*point, m| {
        const s = camera.project(view_proj, .{ m[0], 0, m[1] }, canvas.width, canvas.height) orelse return;
        if (@abs(s[0]) > 4096 or @abs(s[1]) > 4096) return;
        point.* = .{ .x = @intFromFloat(@floor(s[0])), .y = @intFromFloat(@floor(s[1])) };
    }
    draw.line(canvas, points[0], points[1], color);
}
```

- `camera.project` (Chapter 15) returns null for a point behind the camera's near plane, and the
  line is skipped. A point far off to the side can project to a huge screen coordinate, and
  converting that to an `i32` would be illegal behavior, so lines that far out are skipped too.
- `draw.line` (Chapter 10) steps through every pixel of the line, and `canvas.set` skips the
  ones off the canvas. The 4096 limit also keeps a line from taking millions of steps.

```console
$ ./zig-out/bin/delve --headless --demo tour --frames 700 --view overhead --out ../../images/ch23-overhead.png
```

![Frame 700 of the tour seen from above and behind the player. In the middle, a stone room with a barrel and the brick corridors next to it are drawn with their textures. A yellow outline shaped like an arrowhead starts at a green dot, the player, and spreads forward into the room and two corridors leading from it. Beyond the room, a wide band of chunks is painted dim red, and everything to the sides and behind is dim blue. The HUD reads CHUNKS 6/256 OUTSIDE 239 HIDDEN 11.](images/ch23-overhead.png)

- The yellow outline is exactly what the rays reached. Where it is jagged, rays went a few
  cells farther, through the door of the room or down a corridor.
- Six textured chunks: the ones containing a marked cell. They are bigger than the outline,
  because a chunk is all or nothing and marking adds a cell's neighbors.
- The red band behind the room is the frustum's: in view, but blocked by the room's far wall.
  Only 11 chunks are hidden here: most of the maze is outside a 77° view.
- In this view the HUD has no triangle line: `stats` is only set by the views that show the
  player's picture.

### The wireframe again

The wireframe view of Chapter 16 now draws only the visible chunks: `World.drawWireframe` takes
the same chunk list as `World.draw`. In a wireframe nothing hides anything, so it shows the
culling more plainly than the solid view:

```console
$ ./zig-out/bin/delve --headless --map labyrinth --pos 36.5,6.5 --yaw 40 --press toggle_minimap \
    --view wireframe --out ../../images/ch23-wireframe.png
```

![The wireframe view in the labyrinth, white lines on dark blue. A brick corridor runs straight across the middle of the picture, its walls drawn as orange squares with diagonals. Along it stand a few light gray cubes, the stone blocks between rooms, the biggest one just right of the crosshair. Above and below the corridor the screen is empty. The HUD reads CHUNKS 10/256 OUTSIDE 165 HIDDEN 81, TRIANGLES 208, CULLED 0, DRAWN 136, PIXELS 0, COVERED 0.00X.](images/ch23-wireframe.png)

- Chapter 21's wireframe at this pose sent 6944 triangles and drew 2012, a tangle of lines from
  the whole maze. Now 208 are sent and 136 drawn: the walls of 10 chunks.
- Wireframes draw every triangle, facing the camera or not, so `CULLED` stays 0, and they fill
  no pixels, so the overdraw numbers are 0.

### Freezing the visibility

The overhead view shows the state of one moment. To see that visibility really is the world's
edge, the X key freezes it: while `frozen`, `render` skips `update`, and the chunks, states and
ray ends stay as they were (the `valid` flag makes sure there was a first `update` to keep).
Walk or turn and the frozen world goes with you, but nothing is added to it:

```console
$ ./zig-out/bin/delve --headless --map labyrinth --pos 12.5,15.5 --yaw 0 --press toggle_freeze \
    --hold 0,0,-1 --frames 20 --out ../../images/ch23-frozen.png
$ ./zig-out/bin/delve --headless --map labyrinth --pos 12.5,15.5 --yaw 0 --press toggle_freeze \
    --hold 0,0,-1 --frames 20 --view overhead --out ../../images/ch23-frozen-overhead.png
```

![The player's view after freezing the visibility and turning left for 20 ticks. The wooden ceiling and the tiled floor of a large room continue across the screen, but the left half, where the walls should be, is an empty dark blue-black void. On the right, a lamp on a pole stands in front of gray stone walls. The HUD reads CHUNKS 9/256 OUTSIDE 140 HIDDEN 107 CULLING GRID SORTED FROZEN, POS 12.50,15.50 YAW 312.](images/ch23-frozen.png)

![The same moment from above. The yellow fan of sight lines starts at the green player dot and points up and to the right, the way the player faced when the visibility was frozen, into a room with a lamp and along a corridor. The overhead camera, behind the player's new direction, looks up the screen: the chunks to the left of the fan, where the player now looks, are dim blue.](images/ch23-frozen-overhead.png)

- `--press toggle_freeze` freezes on the first tick, facing east, and `--hold 0,0,-1` turns
  left for 20 ticks: 20 × 2.5/60 = 0.83 radians, 48°, to `YAW 312`.
- The void on the left of the first picture is the part of the new view that was outside the
  old one. Its chunks were `outside` when the freeze happened, so they are not drawn. The floor
  and ceiling that are there belong to chunks that were drawn.
- From above, the fan still points the old way, about 48° to the right of where the camera now
  looks.
- `HIDDEN 107`: here, in the middle of the maze, hidden chunks outnumber the drawn ones twelve
  to one.

## What it bought

The pictures are the same; the question is how much work each stage saves. The tour from
Chapter 22 is the benchmark: 1983 frames, CPU time per frame (user plus system), ReleaseFast,
pinned to one core. Each configuration ran three times, in turn with the others, and the table
keeps the best of the three:

```console
$ zig build --release=fast
$ /usr/bin/time -f "%U %S" taskset -c 4 ./zig-out/bin/delve --headless --demo tour --frames 1983
$ /usr/bin/time -f "%U %S" taskset -c 4 ./zig-out/bin/delve --headless --demo tour --frames 1983 \
    --culling off --press toggle_sorting
```

| Tour, ms per frame | Phong, trilinear (the default) | `--shading unlit --press toggle_textures` |
|---|---|---|
| Chapter 22 | 17.29 | 4.55 |
| Culling off, unsorted | 17.18 | 4.64 |
| Culling off, sorted | 16.22 | 4.53 |
| Frustum, sorted | 15.76 | 4.29 |
| Grid, unsorted | 15.19 | 3.50 |
| Grid, sorted (the default) | 14.68 | 3.41 |

The machine was shared with other work (load average 2.5 to 2.9), so the last digit is noise.

- With culling off and no sorting, Chapter 23 does what Chapter 22 did, and costs the same. The
  visibility code that is not used costs nothing.
- Sorting saves half a millisecond to a millisecond with Phong shading, and almost nothing
  unlit. What it saves
  is shading, the overdraw view's 1.34 going down to 1.05, and unlit shading is cheap.
- Unlit, culling saves about 1.1 ms: the vertex work and the outcode tests on thousands of
  triangles a frame that were never going to be drawn. With Phong it saves 1.5 ms, because
  some triangles of hidden chunks did reach the screen, and were shaded before nearer walls
  covered them. Most of the saving is the grid's: the frustum alone saves a quarter to a half
  of a millisecond.
- Together the default frame goes from 17.3 to 14.7 ms with Phong, 15% less, and from 4.6 to
  3.4 ms unlit, 25% less.

The rest is pixels that are seen. Every frame shades all 256,000 pixels at least once, and
that is most of the 14.7 ms (unlit, the same frames cost 3.4). No culling can remove it;
Chapter 24 measures where it goes. The
visibility itself, rays and all, is a small part of a frame: Chapter 24 times it at under a
tenth of a millisecond.

The labyrinth is small. Its 256 chunks cost little to test, and drawing all of them costs a
few milliseconds. Culling matters more as worlds grow: double the maze's width and height and
the triangles sent without culling are four times as many, while the ones a player can see from
inside a corridor stay about the same.

## Building delve: seeing only what is there

| File | Change |
|---|---|
| `src/visibility.zig` | New, 370 lines: `Frustum` (`init`, `excludes`), `groundSpan`, `rays_per_radian`, `Culling`, `ChunkState`, `Visibility` (`update`, `castRays`, `anySeen`, `chunks`, `count`), `Marker`, `Nearest`; five tests |
| `src/world.zig` | Lamps and barrels per chunk, `sortByChunk`, `chunkOf`; `draw` and `drawWireframe` take the list of chunks; `drawBarrel`, `drawOverhead` |
| `src/render3d.zig` | `Stats.tested`, `Options.count_overdraw`, `Renderer.overdraw`, `drawOverdraw`, `overdraw_colors`; one test |
| `src/raycast.zig` | `castVisiting`, which `cast` now calls with a visitor that does nothing |
| `src/app.zig` | `visibility`, `culling`, `sort` and `frozen`; the views `overdraw` and `overhead`; the third HUD line; `drawSightLines`, `floorLine`, `drawOverdrawKey`; `render` takes `*App` |
| `src/input.zig`, `src/platform.zig` | The actions `next_culling` (V), `toggle_sorting` (R) and `toggle_freeze` (X) |
| `src/options.zig` | `--culling` |
| `src/main.zig` | Passing `--culling` to the app |

The complete project is in `project/ch23/`, 6225 lines in all.

### Running it

```console
$ zig build test --summary all
Build Summary: 6/6 steps succeeded; 82/82 tests passed
test success
+- run test 82 pass (82 total) 1s MaxRSS:15M
   +- compile test debug native success 648ms MaxRSS:177M
      +- WriteFile raylib.h success
      +- compile lib raylib debug native success 7s MaxRSS:406M
      +- compile lib raylib debug native (reused)
      +- translate-c success 17ms MaxRSS:40M
$ zig build --release=fast
$ ./zig-out/bin/delve --headless --culling portals
delve: InvalidValue
usage: delve [OPTIONS]
...
```

- Six more tests than Chapter 22: five in `visibility.zig` and the overdraw test.
- Portals are an exercise, not an option, so `--culling portals` prints the usage and exits
  with status 2.

`--help` lists the new option and the two new views:

```text
  --view NAME        start in view NAME: solid, depth, levels, chunks, overdraw,
                     overhead, raycast, wireframe, cube, map_fixed, map_follow
  --culling NAME     skip chunks with NAME: off, frustum, grid (the default)
```

`zig build run` opens the cellar as before. V steps through the culling modes (grid, off,
frustum), R turns sorting off and on, X freezes the visibility, and Tab reaches the two new
views. `zig build run -- --demo tour --view overhead` watches the tour from above. The pictures
for this chapter are made with the commands shown with them, and the window with:

```console
$ xvfb-run -a -s "-screen 0 1920x1080x24" ./zig-out/bin/delve --demo tour --frames 1200 \
    --view overhead --scale 1 --screenshot ../../images/ch23-window.png
```

![The window at frame 1200 of the tour in the overhead view. The player, a green dot near the bottom, stands at the north edge of the maze facing east, so the left half of the picture, beyond the edge, is black. A long, narrow yellow outline runs from the dot straight up a textured stone corridor. Right of the corridor, a band of dim red chunks, and beyond them, dim blue ones. The HUD reads 3.2 MS, CHUNKS 6/256 OUTSIDE 207 HIDDEN 43, POS 26.25,1.49 YAW 1.](images/ch23-window.png)

- The overhead camera is behind the player and looks the way the player does, east, so east is
  up the screen and north is to the left. Row 1 is the first open row of the map, and there is
  nothing north of it to draw.
- The fan is long and thin: the corridor's walls stop every ray but those that run along it.
- `3.2 MS` is the time `render` took for this frame: the visibility and the overhead view,
  every chunk unlit and without ceilings.

## Summary

- Work can be refused at three levels: whole chunks before any vertex is touched, single
  triangles by outcodes and facing, and pixels by the depth test. One test at a higher level
  saves many at the levels below it.
- The six planes of the view frustum come straight from the view-projection matrix: each is a
  clip-space distance applied to the matrix's four columns (Gribb and Hartmann's trick, usually
  written as sums and differences of rows). A box is outside if its corner farthest along a plane's normal, the
  positive vertex, picked with `@select`, is behind that plane. The test is conservative: it may
  keep a box that is outside, never drop one that is inside.
- Chunks own the things in them; `sortByChunk`, a stable sort, puts each chunk's lamps and
  barrels in one slice.
- `castVisiting` takes any visitor with a `visit` method (`anytype`) and calls it for every cell
  a ray passes through, but not the wall cell it stops at. The `Marker` marks each such cell and
  its eight neighbors, which covers the gaps between 1024 rays per radian.
- Looking up or down, the floor and ceiling in view reach around the player: `groundSpan` widens
  the fan, all the way around once tan(pitch) reaches 2.
- A test draws poses with culling off and on and compares colors and depths. Grid culling is
  safe here because walls fill whole cells, nothing is taller than a wall, and things stay
  inside their cells. Like the frustum test, it is conservative.
- Drawing the visible chunks nearest first lets the depth test refuse hidden pixels before they
  are shaded: shaded 1.34 times each became 1.05.
- The overdraw view counts how many times each pixel is covered, with `+|=`, a saturating add.
  The overhead view and the freeze show which chunks were refused and why.
- At the labyrinth's start, 106 triangles are sent instead of 18,410, and the tour's frame
  costs 14.7 ms instead of 17.3.

## Exercises

These are sketches: the solutions show the idea and the key code, not every line of the change.

1. **Portals.** Rooms connect to each other through doorways. Split the map into rooms and
   corridors and find what is visible by looking through doorways only, as Luebke and Georges
   describe. Compare the chunk counts with the grid rays' at the same poses.

   <details><summary>Solution</summary>

   Flood fill the open cells, stopping at the cells of a doorway (an open cell between two
   walls), to number the regions. Each doorway becomes a portal: a 2D segment across the
   doorway and the two regions it joins.

   ```zig
   const Portal = struct { a: Vec2, b: Vec2, regions: [2]u16 };
   ```

   Visibility is a recursion from the eye's region. It carries a 2D view cone, two angles,
   starting as the frustum's. For each portal of the region, it narrows the cone to the
   portal's angular extent and, if anything is left, marks the region on the other side and
   recurses into it:

   ```zig
   fn see(eye: Vec2, region: u16, cone: [2]f32, portals: []const Portal, seen: []bool) void {
       seen[region] = true;
       for (portals) |p| {
           const other = if (p.regions[0] == region) p.regions[1] else if (p.regions[1] == region) p.regions[0] else continue;
           const narrowed = intersect(cone, angles(eye, p.a, p.b)) orelse continue;
           see(eye, other, narrowed, portals, seen);
       }
   }
   ```

   A chunk is drawn if one of its cells is in a seen region and it passes the frustum.
   `angles` must handle the cone that crosses ±π, and the recursion must not go back through
   the portal it came in by. Portals see whole regions, so in long corridors they draw more
   chunks than the rays; in rooms with narrow doors, fewer.

   </details>

2. **Precomputed visibility.** Quake did not work out visibility while the game ran: it stored,
   for every leaf of its map, the set of leaves visible from anywhere in it. Do the same for
   the grid: a set of chunks for every open cell. How much memory does the labyrinth need?
   Where does it draw more than the rays?

   <details><summary>Solution</summary>

   At load time, from a few sample points in each open cell (its center and points near its
   corners), cast rays all the way around with `castVisiting` and a visitor that sets the
   chunk's bit:

   ```zig
   const ChunkMarker = struct {
       set: *std.DynamicBitSet,
       columns: usize,

       pub fn visit(m: ChunkMarker, cell: [2]i32) void {
           const x: usize = @intCast(cell[0]);
           const y: usize = @intCast(cell[1]);
           m.set.set((y / chunk_size) * m.columns + x / chunk_size);
       }
   };
   ```

   At run time, a chunk is drawn if it is in the set of the eye's cell and the frustum does not
   exclude it. The labyrinth has 2178 open cells, and each set is 256 bits, so the table is
   about 68 KiB. Since the set holds what is visible in *every* direction, a player facing a
   wall still draws the chunks behind them that the frustum lets through. That is the
   trade Quake made: much more drawn than seen, and nothing to compute but a lookup. The
   samples are the weak point: a chunk seen only from between them is missed, and it pops
   into view.

   </details>

3. **Hierarchical-Z occlusion.** The grid rays only work because walls are whole cells. Make an
   occlusion test that uses the depth buffer instead, and works with any shape.

   <details><summary>Solution</summary>

   Draw the nearest chunks first (the sorted order already does). Then build a pyramid from the
   depth buffer: level 0 is the depth buffer, and each pixel of the next level is the *largest*
   depth of the 2×2 pixels under it, the farthest anything there is.

   Before drawing a chunk, project the eight corners of its box. Take the screen rectangle
   around them and the box's nearest depth. Pick the level where the rectangle covers at most
   2×2 pixels, and read those:

   ```zig
   fn occluded(pyramid: []const []const f32, widths: []const usize, rect: Rect, nearest: f32) bool {
       const level = levelFor(rect);
       const w = widths[level];
       var y = rect.y0 >> level;
       while (y <= rect.y1 >> level) : (y += 1) {
           var x = rect.x0 >> level;
           while (x <= rect.x1 >> level) : (x += 1) {
               if (nearest < pyramid[level][y * w + x]) return false;
           }
       }
       return true;
   }
   ```

   If the box's nearest point is farther than the farthest depth in every pixel it covers, the
   chunk is hidden. A box any of whose corners is behind the camera must be drawn. Rebuild the
   pyramid every few chunks, or once after the nearest ones; count how many chunks this hides
   that the grid did not, and what it costs.

   </details>

4. **The exact 2D visibility polygon.** 1383 rays are many more than the labyrinth needs. Seen
   from above, what the player sees is a polygon whose corners are wall corners. Find it
   exactly, and draw it in the overhead view in place of the fan.

   <details><summary>Solution</summary>

   The polygon only changes direction at wall corners. Collect the corners of the wall cells
   near enough to matter, and for each one, cast three rays: straight at it, and an angle ε to
   either side, to see past it when it is the edge of a wall:

   ```zig
   for (corners) |c| {
       const a = std.math.atan2(c[1] - eye[1], c[0] - eye[0]);
       for ([_]f32{ -1e-4, 0, 1e-4 }) |e| try angles.append(gpa, a + e);
   }
   std.mem.sort(f32, angles.items, {}, std.sort.asc(f32));
   ```

   Cast a ray at each angle in the view, in order, with the `Marker` as visitor, and keep the
   ends: they are the polygon's corners. In `drawSightLines`, draw it with `floorLine` as the
   fan is drawn. It marks the same cells as the fan, or a few more, with a ray count that
   depends on the walls in view rather than on the width of the view. In a wide room, it can be
   more rays than the fan, not fewer.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-23--visibility-and-occlusion)
