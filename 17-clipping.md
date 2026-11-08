# Chapter 17 — Clipping

A triangle that starts behind the eye and reaches into view can't simply be divided by w.
Behind the eye w is negative, and the divide throws that corner to the wrong side of the
screen. Chapter 16 dropped such triangles whole, which leaves holes next to the camera, and it
drew lines thousands of pixels long for triangles beside the view. This chapter cuts every
triangle down to the part that is inside the view volume. The cut happens *before* the divide,
in homogeneous clip space, where the view volume is six simple inequalities and every straight
edge is still straight. Outcodes reject most triangles with a few comparisons. The
Sutherland–Hodgman algorithm cuts the rest, one plane at a time, and carries the values a
vertex brings along (its *varyings*) through the same cuts. One small detail keeps the edges
that two triangles share free of cracks: always cut an edge starting from its inside end. In
`delve` the near walls are now cut instead of lost, the cut is drawn in magenta, and the
wireframe gets about 17 times faster.

Previous: [Chapter 16 — Wireframe 3D](16-wireframe-3d.md). Next:
[Chapter 18 — Rasterizing Triangles](18-rasterizing-triangles.md).

## What goes wrong behind the eye

[Chapter 15](15-cameras-and-projection.md) built the projection in two steps. A matrix takes a
point to *clip coordinates* (x, y, z, w), with w equal to the point's distance in front of the
eye. Then the *perspective divide* gives normalized device coordinates (NDC): x/w, y/w, z/w.
The divide is where perspective happens. Twice as far away means half as far from the center
of the screen.

Watch what the divide does as w shrinks. Take a point with clip x = 1 and let it approach the
plane of the eye (w = 0), then pass behind it:

`examples/ch17/divide_by_w.zig`

```zig
//! What the perspective divide does to a point as it approaches the eye
//! plane (w = 0) and passes behind it (w < 0).
const std = @import("std");

/// NDC x to a pixel column on a 640-pixel-wide screen.
fn column(ndc_x: f32) f32 {
    return (ndc_x + 1) / 2 * 640;
}

pub fn main() void {
    // A point with clip x = 1, at shrinking w. On screen it is x / w.
    std.debug.print("   w      x/w      column\n", .{});
    for ([_]f32{ 1, 0.5, 0.1, 0.01, -0.01, -0.1, -1 }) |w| {
        const ndc = 1 / w;
        std.debug.print("{d:>6.2} {d:>8.1} {d:>10.0}\n", .{ w, ndc, column(ndc) });
    }

    // An edge from a = (x 0.5, w 2), in front, to b = (x 0.5, w -1), behind.
    // The points along it in clip space, and where each one lands.
    std.debug.print("\nalong the edge a -> b (a in front, b behind):\n", .{});
    std.debug.print("   t      w      x/w      column\n", .{});
    const a = [2]f32{ 0.5, 2 }; // x, w
    const b = [2]f32{ 0.5, -1 };
    for ([_]f32{ 0, 0.25, 0.5, 0.6, 0.66, 0.67, 0.7, 0.8, 1 }) |t| {
        const x = a[0] + (b[0] - a[0]) * t;
        const w = a[1] + (b[1] - a[1]) * t;
        std.debug.print("{d:>5.2} {d:>6.2} {d:>8.2} {d:>10.0}\n", .{ t, w, x / w, column(x / w) });
    }
}
```

```console
$ zig run examples/ch17/divide_by_w.zig
   w      x/w      column
  1.00      1.0        640
  0.50      2.0        960
  0.10     10.0       3520
  0.01    100.0      32320
 -0.01   -100.0     -31680
 -0.10    -10.0      -2880
 -1.00     -1.0          0

along the edge a -> b (a in front, b behind):
   t      w      x/w      column
 0.00   2.00     0.25        400
 0.25   1.25     0.40        448
 0.50   0.50     1.00        640
 0.60   0.20     2.50       1120
 0.66   0.02    25.00       8320
 0.67  -0.01   -50.00     -15680
 0.70  -0.10    -5.00      -1280
 0.80  -0.40    -1.25        -80
 1.00  -1.00    -0.50        160
```

- At w = 1 the point is on the right edge of the screen (column 640). Closer to the eye it
  moves right, off the screen, faster and faster: column 32320 at w = 0.01.
- Just behind the eye it reappears far to the *left*, at column −31680, and creeps back toward
  the screen as w becomes more negative. At w = −1 it sits on the left edge, column 0. A point
  behind you shows up mirrored, on the wrong side.
- The second table follows an edge from a, in front of the eye, to b, behind it. Its two ends
  land at columns 400 and 160. A line routine handed those two ends would draw the 240 pixels
  between them. But the points of the edge go 400, 448, 640, 1120, 8320, off to the right
  forever, and come back from the far left: −15680, −1280, −80, 160. The visible part of the
  edge starts at column 400 and runs off the *right* side of the screen. The segment between
  the projected ends is exactly the part that does *not* belong to the edge.

So an edge that crosses w = 0 does not project to the segment between its projected ends. It
wraps around through infinity. The divide is a perfectly good map for points in front of the
eye, and garbage for the rest.

Chapter 16 dealt with this the blunt way: if any corner of a triangle has `w < near`, drop the
triangle. That is safe, but it loses every triangle that starts behind the eye and reaches into
view. When the player stands next to a wall, that is the wall right beside them. In a wireframe
the loss is a line or two. Filled, which is the next chapter, it is a hole the size of a wall
([Chapter 18](18-rasterizing-triangles.md) shows the picture). The fix is to cut the triangle
at the near plane and keep the part in front. The rest of this chapter is about where to do
that cutting and how.

## The view volume in clip space

What the camera can see is a box in NDC: x and y from −1 to 1 and depth from 0 at the near
plane to 1 at the far plane. A point is visible when, after the divide,

```text
−1 ≤ x/w ≤ 1,    −1 ≤ y/w ≤ 1,    0 ≤ z/w ≤ 1.
```

Everything we can see is in front of the eye, so w > 0 there. Multiplying the inequalities by
a positive w doesn't flip them, and the divide disappears:

```text
−w ≤ x ≤ w,      −w ≤ y ≤ w,      0 ≤ z ≤ w.
```

These are six conditions on clip coordinates, with no division anywhere. Each one is a plane
of the view volume. Write each as a *distance* that is zero on the plane, positive inside, and
negative outside:

| Plane | Inside when | Distance d(p) |
|---|---|---|
| near | 0 ≤ z | z |
| far | z ≤ w | w − z |
| left | −w ≤ x | w + x |
| right | x ≤ w | w − x |
| bottom | −w ≤ y | w + y |
| top | y ≤ w | w − y |

These are not distances in world units. They are scaled by w, so "how far" means different
things at different depths. Only the sign and the zero matter, and both are exact.

Why is `z ≥ 0` the near plane? Chapter 15 built the depth row of the projection matrix so
that a point at distance d in front of the eye (view-space z = −d) gets

```text
z_clip = far/(n − far) · z + n·far/(n − far)
       = far · (d − n) / (far − n),          with w = d.
```

That is 0 exactly when d = n and negative when d < n, so `z ≥ 0` is the same as "at least
`near` in front of the eye". The far plane works the same way:

```text
w − z_clip = d − far·(d − n)/(far − n) = n · (far − d) / (far − n),
```

which is ≥ 0 exactly when d ≤ far. Notice what the near plane does for the divide. Everything
inside the volume has w = d ≥ near = 0.05. After clipping, no vertex can have w = 0 or w < 0,
and dividing is safe.

What about a point behind the eye, with w < 0? It can't satisfy −w ≤ x ≤ w at all, since that
needs w ≥ |x| ≥ 0. So it is outside left or right (or both), and outside bottom or top, in
addition to near. A small example prints the six distances for a few clip-space points:

`examples/ch17/clip_planes.zig`

```zig
//! The six planes of the view volume as signed distances in clip space,
//! and the outcode of a point: the set of planes it is outside of.
const std = @import("std");

const Vec4 = @Vector(4, f32);

const Plane = enum {
    near,
    far,
    left,
    right,
    bottom,
    top,

    /// >= 0 inside the plane, < 0 outside.
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

const Outcode = std.EnumSet(Plane);

fn outcode(p: Vec4) Outcode {
    var code: Outcode = .empty;
    for (std.enums.values(Plane)) |plane| {
        if (plane.distance(p) < 0) code.insert(plane);
    }
    return code;
}

pub fn main() void {
    const points = [_]struct { name: []const u8, p: Vec4 }{
        .{ .name = "inside", .p = .{ 0.2, -0.3, 0.5, 1 } },
        .{ .name = "left", .p = .{ -3, 0, 0.9, 2 } },
        .{ .name = "too close", .p = .{ 0, 0, -0.03, 0.02 } },
        .{ .name = "behind", .p = .{ -2, 0, -1.05, -1 } },
        .{ .name = "beyond far", .p = .{ 0, 0, 70, 65 } },
        .{ .name = "on the edge", .p = .{ 1, 1, 0.5, 1 } },
    };
    std.debug.print("{s:<13} {s:>6} {s:>6} {s:>6} {s:>6} {s:>6} {s:>6}  outside of\n", .{
        "point", "near", "far", "left", "right", "bottom", "top",
    });
    for (points) |pt| {
        std.debug.print("{s:<13}", .{pt.name});
        for (std.enums.values(Plane)) |plane| std.debug.print(" {d:>6.2}", .{plane.distance(pt.p)});
        const code = outcode(pt.p);
        std.debug.print("  {{", .{});
        var it = code.iterator();
        while (it.next()) |plane| std.debug.print(" {t}", .{plane});
        std.debug.print(" }}\n", .{});
    }

    // A triangle is rejected when all its corners are outside one plane:
    // the intersection of their outcodes is not empty.
    const tri = [3]Vec4{ .{ -3, 0, 0.9, 2 }, .{ -2, 1, 0.5, 1 }, .{ -5, -4, 0.7, 3 } };
    var any: Outcode = .empty;
    var all: Outcode = .full;
    for (tri) |p| {
        any = any.unionWith(outcode(p));
        all = all.intersectWith(outcode(p));
    }
    std.debug.print("triangle: union {d} plane(s), intersection {d} plane(s) -> {s}\n", .{
        any.count(), all.count(), if (all.count() > 0) "reject" else if (any.count() == 0) "accept" else "clip",
    });
}
```

```console
$ zig run examples/ch17/clip_planes.zig
point           near    far   left  right bottom    top  outside of
inside          0.50   0.50   1.20   0.80   0.70   1.30  { }
left            0.90   1.10  -1.00   5.00   2.00   2.00  { left }
too close      -0.03   0.05   0.02   0.02   0.02   0.02  { near }
behind         -1.05   0.05  -3.00   1.00  -1.00  -1.00  { near left bottom top }
beyond far     70.00  -5.00  65.00  65.00  65.00  65.00  { far }
on the edge     0.50   0.50   2.00   0.00   2.00   0.00  { }
triangle: union 2 plane(s), intersection 1 plane(s) -> reject
```

- "too close" is in front of the eye (w = 0.02 > 0) but nearer than the near plane, so only
  `near` is negative. Its divide would work, but its depth would be negative.
- "behind" has w = −1. It is outside four planes at once, as the argument above says it must
  be: no x and y can satisfy both −w ≤ x ≤ w and −w ≤ y ≤ w.
- "on the edge" has distance exactly 0 for right and top. Zero counts as inside, so it is
  outside of nothing: a point on the boundary is visible.
- Each row costs a handful of additions and subtractions. No division.

### Why clip here and not after the divide

There are three places one could cut a triangle: in the world, in clip space, or on the
screen after the divide. The screen is out, as the first example showed: an edge through
w = 0 has no sensible screen image, and points behind the eye get mirrored. Clip space is
better than it looks at first, for one reason: *the projection matrix is linear*.

Take an edge in the world from point a to point b. Its points are

```text
p(t) = a + t·(b − a),     0 ≤ t ≤ 1.
```

The matrix M takes each to clip space. Matrix multiplication distributes over sums and
scalar factors, so

```text
M·p(t) = M·a + t·(M·b − M·a) = A + t·(B − A),
```

where A and B are the clip coordinates of the ends. Two things follow.

1. The edge is still a straight segment in clip space. Nothing has been divided, so nothing
   can wrap around through infinity.
2. The point at fraction t along the edge in the world is at the *same* fraction t in clip
   space. Interpolating in clip space is interpolating in the world.

Each plane distance is linear in the clip coordinates too (a sum of x, y, z, w with fixed
signs), so along the edge it is a linear function of t:

```text
d(t) = d(A) + t·(d(B) − d(A)).
```

If d(A) ≥ 0 and d(B) < 0, the edge crosses the plane where d(t) = 0:

```text
t = d(A) / (d(A) − d(B)).
```

The denominator can't be zero, because d(A) and d(B) have different signs. One subtraction and
one division per crossing.

After the divide, neither of the two facts holds. The screen position is a ratio
x(t)/w(t) of two linear functions of t, which is not linear in t. An edge entirely in front of
the eye still maps to a straight segment on the screen, so a screen-space clipper could cut
it at the screen edge. But the fraction t it finds would be wrong for anything else the
triangle carries, such as a color or a texture coordinate. An example works an edge through
delve's real projection:

`examples/ch17/edge_crossing.zig`

```zig
//! Where an edge crosses a plane of the view volume, computed in clip
//! space: t = d(a) / (d(a) - d(b)). The same t is the right fraction for
//! the world position and for any value carried along the edge.
const std = @import("std");

const Vec4 = @Vector(4, f32);

/// delve's projection: vertical FOV 2 atan(0.5), aspect 640/400,
/// near 0.05, far 64. Clip = M * (x, y, z, 1) for a point in view space.
fn project(p: [3]f32) Vec4 {
    const n = 0.05;
    const f = 64.0;
    const x, const y, const z = p;
    return .{ 2.0 / 1.6 * x, 2 * y, f / (n - f) * z + n * f / (n - f), -z };
}

fn lerp(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    return a + (b - a) * @as(@TypeOf(a), @splat(t));
}

fn lerp3(a: [3]f32, b: [3]f32, t: f32) [3]f32 {
    const v = lerp(@as(@Vector(3, f32), a), @as(@Vector(3, f32), b), t);
    return v;
}

pub fn main() void {
    // View space: the eye at the origin, looking down -z.
    // a is 2 units ahead, b is 1 unit behind the eye.
    const a_view = [3]f32{ 0.4, 0.1, -2 };
    const b_view = [3]f32{ -0.6, 0.3, 1 };
    const a = project(a_view);
    const b = project(b_view);
    std.debug.print("a clip = {any}\nb clip = {any}\n", .{ a, b });

    // The near plane's distance is z; find where it is zero.
    const t = a[2] / (a[2] - b[2]);
    const cut = lerp(a, b, t);
    std.debug.print("near: t = {d:.6}, crossing = {any}\n", .{ t, cut });

    // The same fraction of the way along the edge *in the world*, projected:
    const cut_world = project(lerp3(a_view, b_view, t));
    std.debug.print("world point at t, projected = {any}\n", .{cut_world});

    // A value carried along the edge (say a brightness 0 at a, 1 at b)
    // is linear in the world, so at the crossing it is t as well.
    const value = lerp(@as(@Vector(1, f32), .{0}), .{1}, t)[0];
    std.debug.print("value at the crossing = {d:.6}\n\n", .{value});

    // Now an edge entirely in front of the eye that leaves the screen on
    // the right. Its t in clip space vs the "same" t taken from the
    // projected (divided) positions.
    const c_view = [3]f32{ 0.5, 0, -1 };
    const d_view = [3]f32{ 6, 0, -5 };
    const c = project(c_view);
    const d = project(d_view);
    const dc = c[3] - c[0]; // right plane: w - x
    const dd = d[3] - d[0];
    const t_clip = dc / (dc - dd);
    const ndc_c = c[0] / c[3];
    const ndc_d = d[0] / d[3];
    const t_screen = (1 - ndc_c) / (ndc_d - ndc_c);
    std.debug.print("right edge: ndc x from {d:.4} to {d:.4}\n", .{ ndc_c, ndc_d });
    std.debug.print("t in clip space   = {d:.4}\n", .{t_clip});
    std.debug.print("t on the screen   = {d:.4}\n", .{t_screen});
    for ([_]f32{ t_clip, t_screen }) |tt| {
        const p = project(lerp3(c_view, d_view, tt));
        std.debug.print("world point at t = {d:.4} lands at ndc x = {d:.4}\n", .{ tt, p[0] / p[3] });
    }
}
```

```console
$ zig run examples/ch17/edge_crossing.zig
a clip = { 0.5, 0.2, 1.9515247, 2 }
b clip = { -0.75, 0.6, -1.050821, -1 }
near: t = 0.650000, crossing = { -0.31250006, 0.46000004, 0, 0.049999952 }
world point at t, projected = { -0.31250003, 0.46000004, -0.000000048428774, 0.049999952 }
value at the crossing = 0.650000

right edge: ndc x from 0.6250 to 1.5000
t in clip space   = 0.1304
t on the screen   = 0.4286
world point at t = 0.1304 lands at ndc x = 1.0000
world point at t = 0.4286 lands at ndc x = 1.3158
```

- `project` is delve's matrix written out by hand: x scaled by f/aspect = 2/1.6, y by f = 2,
  the depth row from Chapter 15, and w = −z, the distance in front of the eye.
- b is behind the eye: its w is −1 and its depth is negative. The near crossing is at
  t = 0.65, where z comes out exactly 0 and w = 0.05, the near distance. The crossing is on
  the near plane, at the near distance, as the derivation said.
- Projecting the world point 65% of the way from a to b gives the same clip coordinates, up to
  the last bit or two of rounding. Clip-space t *is* world t.
- A value carried along the edge is linear in the world too, so it is cut with the same t.
- The second edge is entirely in front of the eye. In clip space it crosses the right plane
  at t = 0.1304, and the world point there does land on the screen's right edge, NDC x = 1.
  Measured on the screen, after the divide, the edge reaches x = 1 at "t = 0.4286". That t is
  meaningless in the world: the point 42.86% of the way along the edge lands at x = 1.3158,
  well off the screen. The screen fraction and the world fraction disagree, because the far
  part of the edge is squeezed on the screen.

Clipping in the world, before the projection, would be possible too. The view volume is a
frustum there, a pyramid with its tip cut off. Its four side planes depend on the camera's
position, direction, and field of view, so they would have to be computed every frame. In clip
space the same six planes are always the same six simple formulas. That is why every GPU clips
here, and why the space has the name.

## Outcodes: accept or reject at once

Most triangles of a scene are nowhere near the view. Before cutting anything, it pays to sort
the easy cases out. The tool is the *outcode*: the set of planes a corner is outside of. In
Zig this is a set over an enum, `std.EnumSet(Plane)`, a bit set with one bit per plane:

```zig
/// The set of planes a point is outside of.
pub const Outcode = std.EnumSet(Plane);

pub fn outcode(p: Vec4) Outcode {
    var code: Outcode = .empty;
    for (std.enums.values(Plane)) |plane| {
        if (plane.distance(p) < 0) code.insert(plane);
    }
    return code;
}
```

`std.enums.values(Plane)` is the array of the six tags, so the loop visits each plane. A
triangle's three outcodes give two quick decisions.

- **Accept**: the *union* of the three codes is empty. Every corner is inside every plane. A
  half-space is convex: the segment between two points inside it stays inside. So the whole
  triangle is inside every plane, and it is drawn as it is.
- **Reject**: the *intersection* of the three codes is not empty. All three corners are
  outside the *same* plane. By the same convexity argument, the whole triangle is outside that
  plane, and nothing of it can be visible. Skip it.
- Otherwise the triangle is clipped, but only against the planes in the union. A plane that
  every corner is inside of can't cut anything.

The last line of the `clip_planes.zig` output is the reject case. The three corners are all
left of the view, and one of them is below it too: the union is {left, bottom}, the
intersection is {left}, and the triangle is rejected without any arithmetic beyond the
outcodes.

The reject test is not complete. A triangle can have one corner outside left, one outside top,
and one outside right, with no plane shared by all three, and still miss the view: picture a
thin triangle passing above the top-left corner of the screen. The outcodes can't tell, so it
goes to the clipper, which cuts it down to nothing. That's fine. The quick test only needs to
be right when it says "reject", and it is.

The idea comes from line clipping. The Cohen–Sutherland algorithm, from the 1960s, gives each
end of a 2D segment a 4-bit code (left, right, above, below a rectangle) and decides most
segments with one OR and one AND. The rest it cuts at one side at a time and tries again:

`examples/ch17/cohen_sutherland.zig`

```zig
//! Cohen-Sutherland line clipping: 4-bit outcodes decide most segments at
//! once; the rest are cut at one rectangle side at a time.
const std = @import("std");

const xmin = 0.0;
const xmax = 20.0;
const ymin = 0.0;
const ymax = 10.0;

const left: u4 = 0b0001;
const right: u4 = 0b0010;
const top: u4 = 0b0100; // y < ymin (screen y grows down)
const bottom: u4 = 0b1000;

const Point = struct { x: f32, y: f32 };

fn outcode(p: Point) u4 {
    var code: u4 = 0;
    if (p.x < xmin) code |= left else if (p.x > xmax) code |= right;
    if (p.y < ymin) code |= top else if (p.y > ymax) code |= bottom;
    return code;
}

/// The visible part of the segment, or null.
fn clipLine(a_in: Point, b_in: Point, rounds: *u32) ?[2]Point {
    var a = a_in;
    var b = b_in;
    var ca = outcode(a);
    var cb = outcode(b);
    while (true) {
        if (ca | cb == 0) return .{ a, b }; // both inside: accept
        if (ca & cb != 0) return null; // both outside one side: reject
        rounds.* += 1;
        // Move an outside end onto the side it is outside of.
        const code = if (ca != 0) ca else cb;
        var p: Point = undefined;
        if (code & left != 0) {
            p = .{ .x = xmin, .y = a.y + (b.y - a.y) * (xmin - a.x) / (b.x - a.x) };
        } else if (code & right != 0) {
            p = .{ .x = xmax, .y = a.y + (b.y - a.y) * (xmax - a.x) / (b.x - a.x) };
        } else if (code & top != 0) {
            p = .{ .x = a.x + (b.x - a.x) * (ymin - a.y) / (b.y - a.y), .y = ymin };
        } else {
            p = .{ .x = a.x + (b.x - a.x) * (ymax - a.y) / (b.y - a.y), .y = ymax };
        }
        if (code == ca) {
            a = p;
            ca = outcode(a);
        } else {
            b = p;
            cb = outcode(b);
        }
    }
}

pub fn main() void {
    const segments = [_][2]Point{
        .{ .{ .x = 2, .y = 2 }, .{ .x = 18, .y = 8 } }, // inside
        .{ .{ .x = -5, .y = 1 }, .{ .x = -1, .y = 9 } }, // left of the box
        .{ .{ .x = 3, .y = -4 }, .{ .x = 30, .y = -1 } }, // above it
        .{ .{ .x = -5, .y = 5 }, .{ .x = 10, .y = 5 } }, // enters from the left
        .{ .{ .x = -4, .y = -6 }, .{ .x = 26, .y = 14 } }, // through two corners' regions
        .{ .{ .x = -6, .y = 4 }, .{ .x = 4, .y = -6 } }, // misses the corner
    };
    for (segments) |s| {
        var rounds: u32 = 0;
        const ca = outcode(s[0]);
        const cb = outcode(s[1]);
        std.debug.print("({d},{d})-({d},{d})  codes {b:0>4} {b:0>4}: ", .{ s[0].x, s[0].y, s[1].x, s[1].y, ca, cb });
        if (clipLine(s[0], s[1], &rounds)) |c| {
            std.debug.print("visible ({d:.2},{d:.2})-({d:.2},{d:.2}) after {d} cut(s)\n", .{ c[0].x, c[0].y, c[1].x, c[1].y, rounds });
        } else {
            std.debug.print("rejected after {d} cut(s)\n", .{rounds});
        }
    }
}
```

```console
$ zig run examples/ch17/cohen_sutherland.zig
(2,2)-(18,8)  codes 0000 0000: visible (2.00,2.00)-(18.00,8.00) after 0 cut(s)
(-5,1)-(-1,9)  codes 0001 0001: rejected after 0 cut(s)
(3,-4)-(30,-1)  codes 0100 0110: rejected after 0 cut(s)
(-5,5)-(10,5)  codes 0001 0000: visible (0.00,5.00)-(10.00,5.00) after 1 cut(s)
(-4,-6)-(26,14)  codes 0101 1010: visible (5.00,0.00)-(20.00,10.00) after 3 cut(s)
(-6,4)-(4,-6)  codes 0001 0100: rejected after 1 cut(s)
```

- The first three segments are decided by the codes alone: `0000 | 0000` is zero (accept),
  and `0001 & 0001` and `0100 & 0110` are not zero (reject).
- The diagonal through the whole box needs three cuts, at the left, the top, and the right
  sides, before both ends are inside.
- The last segment passes the top-left corner outside the box. Its codes, `0001` and `0100`,
  share no bit, so it isn't rejected at once. After one cut its end moves to x = 0, still
  above the box, and then the codes share the "top" bit and it is rejected. This is the
  incomplete-reject case from above, in 2D.

`delve` uses only the decision part of Cohen–Sutherland. For the cutting it uses a method that
works on whole polygons.

## Sutherland–Hodgman, one plane at a time

Ivan Sutherland and Gary Hodgman's polygon clipper (1974) is short enough to fit on an index
card. It cuts a polygon against one plane by walking around it once, looking at each edge
a→b and the two ends' sides:

| a | b | Output |
|---|---|---|
| inside | inside | a |
| inside | outside | a, then the crossing |
| outside | inside | the crossing |
| outside | outside | nothing |

Every edge contributes its starting corner if that corner is inside, plus a crossing if the edge
crosses the plane. The output is again a polygon, in the same order. To clip against several
planes, feed the output of one plane into the next. The order of the planes doesn't change the
result (up to rounding), because the result is just the part of the polygon inside all of them.

Here it is in 2D, a triangle against a rectangle:

`examples/ch17/polygon_clip_2d.zig`

```zig
//! Sutherland-Hodgman in 2D: clip a triangle to a rectangle, one side at a
//! time, printing the polygon after each side and a picture at the end.
const std = @import("std");

const Vec2 = @Vector(2, f32);

/// A polygon with room for the 3 + 4 vertices a triangle can grow to.
const Polygon = struct {
    buffer: [7]Vec2 = undefined,
    len: usize = 0,

    fn append(p: *Polygon, v: Vec2) void {
        p.buffer[p.len] = v;
        p.len += 1;
    }

    fn vertices(p: *const Polygon) []const Vec2 {
        return p.buffer[0..p.len];
    }
};

/// A side of the rectangle as a signed distance, >= 0 inside.
const Side = enum {
    left,
    right,
    top,
    bottom,

    fn distance(side: Side, p: Vec2) f32 {
        return switch (side) {
            .left => p[0] - 0,
            .right => 20 - p[0],
            .top => p[1] - 0,
            .bottom => 10 - p[1],
        };
    }
};

fn clip(in: Polygon, side: Side) Polygon {
    var out: Polygon = .{};
    const vs = in.vertices();
    for (vs, 0..) |a, i| {
        const b = vs[(i + 1) % vs.len];
        const da = side.distance(a);
        const db = side.distance(b);
        if (da >= 0) out.append(a);
        // The edge crosses the side: add the crossing, interpolated from
        // the inside end.
        if ((da >= 0) != (db >= 0)) {
            const in_v, const out_v, const d_in, const d_out = if (da >= 0) .{ a, b, da, db } else .{ b, a, db, da };
            const t = d_in / (d_in - d_out);
            out.append(in_v + (out_v - in_v) * @as(Vec2, @splat(t)));
        }
    }
    return out;
}

fn print(label: []const u8, p: Polygon) void {
    std.debug.print("{s:<14} {d} vertices:", .{ label, p.len });
    for (p.vertices()) |v| std.debug.print(" ({d:.1},{d:.1})", .{ v[0], v[1] });
    std.debug.print("\n", .{});
}

/// Inside a convex polygon whose corners go clockwise on a y-down grid.
fn inside(p: Polygon, q: Vec2) bool {
    const vs = p.vertices();
    for (vs, 0..) |a, i| {
        const b = vs[(i + 1) % vs.len];
        if ((b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0]) < 0) return false;
    }
    return vs.len >= 3;
}

pub fn main() void {
    var tri: Polygon = .{};
    for ([_]Vec2{ .{ -6, 4 }, .{ 14, -4 }, .{ 26, 13 } }) |v| tri.append(v);
    print("triangle", tri);
    var poly = tri;
    for (std.enums.values(Side)) |side| {
        poly = clip(poly, side);
        var label: [16]u8 = undefined;
        print(std.fmt.bufPrint(&label, "after {t}", .{side}) catch unreachable, poly);
    }

    // '#' kept, 'o' clipped away, ':' in the rectangle but not in the
    // triangle, '.' in neither. The rectangle is x 0..20, y 0..10, and y
    // grows downward as on a screen.
    var y: f32 = -5;
    while (y < 14) : (y += 1) {
        var x: f32 = -7;
        while (x < 27) : (x += 1) {
            const q: Vec2 = .{ x + 0.5, y + 0.5 };
            const ch: u8 = if (inside(poly, q)) '#' else if (inside(tri, q)) 'o' else if (Side.left.distance(q) >= 0 and
                Side.right.distance(q) >= 0 and Side.top.distance(q) >= 0 and Side.bottom.distance(q) >= 0) ':' else '.';
            std.debug.print("{c}", .{ch});
        }
        std.debug.print("\n", .{});
    }
}
```

```console
$ zig run examples/ch17/polygon_clip_2d.zig
triangle       3 vertices: (-6.0,4.0) (14.0,-4.0) (26.0,13.0)
after left     4 vertices: (0.0,1.6) (14.0,-4.0) (26.0,13.0) (0.0,5.7)
after right    5 vertices: (0.0,1.6) (14.0,-4.0) (20.0,4.5) (20.0,11.3) (0.0,5.7)
after top      6 vertices: (0.0,1.6) (4.0,0.0) (16.8,0.0) (20.0,4.5) (20.0,11.3) (0.0,5.7)
after bottom   7 vertices: (0.0,1.6) (4.0,0.0) (16.8,0.0) (20.0,4.5) (20.0,10.0) (15.3,10.0) (0.0,5.7)
..................................
....................o.............
.................ooooo............
...............oooooooo...........
............ooooooooooo...........
.......:::##############:::.......
.......##################::.......
.....oo###################:.......
..ooooo###################:.......
...oooo####################.......
......o####################o......
.......:::#################o......
.......::::::##############oo.....
.......::::::::::##########ooo....
.......::::::::::::::######oooo...
........................ooooooo...
............................oooo..
...............................oo.
..................................
```

- Each side cuts off one corner and adds one vertex: 3, 4, 5, 6, 7. The triangle pokes out of
  all four sides, so it grows by four.
- Against the left side, the first corner (−6, 4) is outside. The walk keeps (14, −4) and
  (26, 13), and adds the two crossings (0, 1.6) and (0, 5.7) where the edges leave and enter.
  The crossings appear in the right places in the order: the polygon is still a closed loop,
  and the new edge from (0, 5.7) to (0, 1.6) runs along the left side.
- `clip` interpolates from the inside end of each edge, whichever of a or b that is. A later
  section explains why that matters.
- In the picture, the triangle's three corners stick out at the top, the left, and the bottom
  right, and they are cut off (`o`). The kept polygon (`#`) has seven corners. Two of the
  `:` regions are corners of the rectangle the triangle doesn't reach.

Why is one added vertex per plane the most there can be? The polygon is convex, and a triangle
is, and cutting a convex polygon with a plane gives a convex polygon again. A line meets the
boundary of a convex polygon in at most two points, so the corners outside the plane form one
unbroken run. Say k corners are outside. The walk drops those k and adds the two crossings at
the ends of the run, so n corners become n − k + 2. With k ≥ 1 that is at most n + 1. (With
k = 0 the plane cuts nothing, and the output is the input.) A triangle against six planes has
at most 3 + 6 = 9 corners.

That bound is what lets `delve`'s clipper work without a heap. The polygon is a fixed array of
nine vertices on the stack.

And why may a triangle be clipped only against the planes in its outcode union? If all three
corners are inside a plane, the triangle is too (convexity again). Every vertex the other
planes add lies on a segment between two points of the triangle, so it's inside that plane as
well. A plane that no corner is outside of never cuts anything, at any step.

## The clipper in delve

The new file `src/clip.zig` starts with what a vertex is and the planes:

```zig
/// Values that travel with a vertex and are interpolated across the
/// triangle, such as a color or a texture coordinate. Clipping cuts them
/// exactly like the position.
pub const Varyings = @Vector(8, f32);

pub const Plane = enum {
    near,
    far,
    left,
    right,
    bottom,
    top,

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
};
```

`const x, const y, const z, const w = p;` destructures the four lanes of the vector into four
constants. Making `Plane` an enum pays off twice. The switch must cover every tag, so a plane
added later (see the exercises) can't be forgotten in `distance`. And `std.EnumSet(Plane)`
gives the outcode for free, sized to the number of tags.

A clipped vertex carries more than a position:

```zig
pub const Vertex = struct {
    pos: Vec4,
    vary: Varyings = @splat(0),
    /// The plane that made the edge from this vertex to the next one, or
    /// null if that edge is (part of) an edge of the original triangle.
    edge: ?Plane = null,
};

/// Each plane cuts at most one corner off a convex polygon, adding at
/// most one vertex: a triangle clipped by six planes has at most 9.
pub const max_vertices = 3 + 6;

/// A convex polygon, its vertices in the order of the triangle's.
pub const Polygon = struct {
    buffer: [max_vertices]Vertex = undefined,
    len: usize = 0,

    pub fn vertices(poly: *const Polygon) []const Vertex {
        return poly.buffer[0..poly.len];
    }

    fn append(poly: *Polygon, v: Vertex) void {
        poly.buffer[poly.len] = v;
        poly.len += 1;
    }
};
```

`vary` holds the varyings, which the next section is about. `edge` is for the wireframe: it
remembers which edges the clipper made. `Polygon` is a value type, 9 vertices of 64 bytes (16
for the position, 32 for the varyings, and the optional plane padded out to the 32-byte
alignment of the varyings) in a fixed buffer, 576 bytes in all.
Clipping a triangle copies such a polygon a few times, all on the stack, with no allocation per
triangle. `vertices` takes `*const Polygon`, so the slice it returns points into the caller's
polygon, not into a copy that dies with the call.

Then the algorithm itself:

```zig
/// Clips the triangle against each plane in `planes`, one after another
/// (the Sutherland-Hodgman algorithm). Planes no corner is outside of
/// cannot cut anything, so pass the union of the corners' outcodes. The
/// result is empty, or a convex polygon of 3 to 9 vertices.
pub fn clipTriangle(tri: [3]Vertex, planes: Outcode) Polygon {
    var poly: Polygon = .{};
    for (tri) |v| poly.append(v);
    var it = planes.iterator();
    while (it.next()) |plane| {
        poly = clipPolygon(poly, plane);
        if (poly.len < 3) return .{};
    }
    return poly;
}

/// Walks around the polygon once, keeping what is inside `plane`. For
/// each edge a->b:
///   a inside,  b inside:  keep a
///   a inside,  b outside: keep a, then the crossing (the edge from it
///                         to the next vertex runs along the plane)
///   a outside, b inside:  the crossing
///   both outside:         nothing
fn clipPolygon(in: Polygon, plane: Plane) Polygon {
    var out: Polygon = .{};
    const vs = in.vertices();
    for (vs, 0..) |a, i| {
        const b = vs[(i + 1) % vs.len];
        const a_in = plane.distance(a.pos) >= 0;
        const b_in = plane.distance(b.pos) >= 0;
        if (a_in) out.append(a);
        if (a_in and !b_in) {
            var v = crossing(a, b, plane);
            v.edge = plane;
            out.append(v);
        } else if (!a_in and b_in) {
            var v = crossing(b, a, plane);
            v.edge = a.edge;
            out.append(v);
        }
    }
    return out;
}
```

- `planes.iterator()` visits the planes in the set in enum order: near first, then far, the
  sides. The order makes no difference to the result.
- A polygon with fewer than 3 corners has no area. Once that happens the triangle is gone, so
  the loop stops early.
- The `edge` bookkeeping follows the walk. When the walk leaves the inside (a in, b out), the
  crossing starts the new edge that runs along the plane, so it gets `edge = plane`. When the
  walk comes back in (a out, b in), the crossing starts the rest of the old edge a→b, so it
  inherits whatever a's edge was. A kept corner keeps its own `edge`.
- `crossing(b, a, plane)` passes the inside end first in both branches. The next sections
  explain the varyings it cuts and why the order matters.

Two of the five tests in `clip.zig` check the shapes. A triangle with one corner behind the near
plane becomes a quad, with two new corners on the plane and one new edge:

```zig
test "one corner behind the near plane turns the triangle into a quad" {
    const tri = [3]Vertex{
        .{ .pos = .{ 0, 0, -1, 0.5 } }, // behind
        .{ .pos = .{ 0.5, 0, 1, 2 } },
        .{ .pos = .{ -0.5, 0, 1, 2 } },
    };
    const poly = clipTriangle(tri, .initOne(.near));
    try testing.expectEqual(4, poly.len);
    var on_plane: usize = 0;
    var near_edges: usize = 0;
    for (poly.vertices()) |v| {
        try testing.expect(v.pos[2] >= 0);
        if (v.pos[2] == 0) on_plane += 1;
        if (v.edge == .near) near_edges += 1;
    }
    // The cut leaves two new corners on the plane, joined by one new edge.
    try testing.expectEqual(2, on_plane);
    try testing.expectEqual(1, near_edges);
}
```

With two corners behind, the cut leaves a smaller triangle. In this test the numbers are chosen
so that both crossings are exactly halfway, t = 1/(1 − (−1)) = 0.5, which floats represent
exactly, so the test can compare with `expectEqual` instead of a tolerance:

```zig
test "two corners behind the near plane leave a smaller triangle" {
    const tri = [3]Vertex{
        .{ .pos = .{ 0, 0, 1, 2 } },
        .{ .pos = .{ 1, 0, -1, 0.5 } },
        .{ .pos = .{ -1, 0, -1, 0.5 } },
    };
    const poly = clipTriangle(tri, .initOne(.near));
    try testing.expectEqual(3, poly.len);
    // The first corner is kept, the other two are halfway down their edges.
    try testing.expectEqual(tri[0].pos, poly.vertices()[0].pos);
    try testing.expectEqual(Vec4{ 0.5, 0, 0, 1.25 }, poly.vertices()[1].pos);
    try testing.expectEqual(Vec4{ -0.5, 0, 0, 1.25 }, poly.vertices()[2].pos);
}
```

A third tests the outcodes: a triangle inside comes back unchanged, and a triangle right of the
view is rejected even though each corner is inside the other five planes.

## Varyings ride along

A vertex will soon carry more than its position: a color in Chapter 18, a normal and a world
position for lighting in Chapter 19, texture coordinates in Chapter 20. These values are
specified at the corners and blended across the triangle, so they *vary* over it. That is the
name graphics APIs use, *varyings*. `delve` gives each vertex eight lanes of them, one
`@Vector(8, f32)`, enough for everything the later chapters need.

When the clipper makes a new vertex, it needs varyings for it too. The values at the corners
describe something linear across the triangle *in the world*: a color that fades evenly along
a wall, a texture coordinate that grows by one per unit. The crossing is at fraction t along
the edge in the world (that was the point of clipping in clip space), so its varyings are at
the same fraction t:

```zig
/// Where the edge from `inside` to `outside` crosses the plane. Always
/// going from the inside corner means that two triangles sharing an edge
/// get exactly the same crossing, whatever order their corners are in,
/// and no crack opens between them.
fn crossing(inside: Vertex, outside: Vertex, plane: Plane) Vertex {
    const d_in = plane.distance(inside.pos);
    const d_out = plane.distance(outside.pos);
    const t = d_in / (d_in - d_out);
    return .{
        .pos = math.lerp(inside.pos, outside.pos, t),
        .vary = math.lerp(inside.vary, outside.vary, t),
    };
}
```

`math.lerp` is generic over vector types (Chapter 11), so the same function blends a `Vec4`
and an eight-lane `Varyings`. The test for this is neat: give each vertex its own clip
position as its varyings. Whatever the clipper does to the position, it must do to the
varyings, so they must still agree afterward:

```zig
test "varyings are cut exactly like the position" {
    // Each vertex carries its own position as varyings, so after clipping
    // the two must still agree.
    var tri: [3]Vertex = .{
        .{ .pos = .{ -3, 0.2, 0.5, 1 } },
        .{ .pos = .{ 2, -2, -0.4, 1.5 } },
        .{ .pos = .{ 0.3, 4, 0.9, 1 } },
    };
    for (&tri) |*v| v.vary = .{ v.pos[0], v.pos[1], v.pos[2], v.pos[3], 0, 0, 0, 0 };
    const any, _ = allOutcodes(tri);
    const poly = clipTriangle(tri, any);
    try testing.expect(poly.len >= 3);
    for (poly.vertices()) |v| {
        const pos: Vec4 = .{ v.vary[0], v.vary[1], v.vary[2], v.vary[3] };
        try testing.expect(math.approxEq(pos, v.pos));
        try testing.expectEqual(Outcode.empty, outcode(v.pos + Vec4{ 0, 0, 1e-5, 1e-5 }));
    }
}
```

The triangle pokes out of the left, near, and top planes. The last line checks that every
output vertex is inside every plane. The tiny nudge of 1e-5 to z and w is there because a
crossing that should be exactly on the plane can come out a rounding error outside it, and
the test is about the geometry, not about the last bit.

That "linear in the world" is the right assumption is something to keep in mind. It's what
makes clipping in clip space correct. Chapter 18 shows that the same values are *not* linear
on the screen, and what to do about it.

### Vectors are not arrays

`@Vector(8, f32)` is a SIMD vector: the eight lanes are added, multiplied, and blended all at
once, which is why `lerp` on it is one line. The price is that it can't be indexed with a
number known only at run time. Try to loop over some of the lanes:

```zig
const Varyings = @Vector(8, f32);

/// Sums the first `n` lanes.
fn sumFirst(v: Varyings, n: usize) f32 {
    var total: f32 = 0;
    for (0..n) |i| total += v[i];
    return total;
}
```

```console
$ zig run varying_index.zig
varying_index.zig:8:31: error: vector index not comptime known
    for (0..n) |i| total += v[i];
                              ^
referenced by:
    main: varying_index.zig:15:40
```

Zig prints a few more lines of the reference trace after these, left out here.

A vector lives in a SIMD register, and picking a lane by a run-time number isn't something
those registers can do directly. Zig wants the lane known at compile time (`v[3]`, or inside an
`inline for`). When a run-time index is really needed, coerce the vector to an array first. An
array lives in memory, and memory can be indexed:

```zig
fn sumFirst(v: Varyings, n: usize) f32 {
    var total: f32 = 0;
    const lanes: [8]f32 = v; // an array may be indexed at run time
    for (lanes[0..n]) |x| total += x;
    return total;
}
```

The coercion goes both ways, and it costs at most a store to memory. In `delve` the varyings
are always processed whole, so the problem doesn't come up. It will when a shader in a later
chapter wants "lane i".

## No cracks: cut from the inside

Two triangles that share an edge list its corners in opposite orders. The front of a mesh goes
counter-clockwise (Chapter 16), so if one triangle walks the edge from p to q, its neighbor walks
it from q to p. Suppose the shared edge crosses the near plane. Each triangle computes a
crossing on it. Mathematically the two crossings are the same point. In floating point,
"the same" depends on *how* it is computed:

```text
lerp(p, q, t)      = p + (q − p) · t
lerp(q, p, 1 − t)  = q + (p − q) · (1 − t)
```

These are equal on paper. In f32 every operation rounds, and the two expressions round
differently. If the two triangles' crossings differ in the last bit, the edge they share is no
longer quite shared, and a pixel can fall between them: a *crack*, a hairline gap through
which the background shows. How often do they differ?

`examples/ch17/lerp_order.zig`

```zig
//! Is lerp(a, b, t) the same float as lerp(b, a, 1 - t)? Mathematically
//! yes. In f32, often not, and that is how cracks open between triangles.
const std = @import("std");

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

const Vec4 = @Vector(4, f32);

fn lerp4(a: Vec4, b: Vec4, t: f32) Vec4 {
    return a + (b - a) * @as(Vec4, @splat(t));
}

/// Where the edge from p to q crosses the near plane z = 0, computed
/// starting from p.
fn crossingFrom(p: Vec4, q: Vec4) Vec4 {
    const t = p[2] / (p[2] - q[2]);
    return lerp4(p, q, t);
}

pub fn main() void {
    var prng: std.Random.DefaultPrng = .init(17);
    const random = prng.random();
    const n = 1_000_000;

    var scalar_differ: u32 = 0;
    for (0..n) |_| {
        const a = random.float(f32) * 20 - 10;
        const b = random.float(f32) * 20 - 10;
        const t = random.float(f32);
        if (lerp(a, b, t) != lerp(b, a, 1 - t)) scalar_differ += 1;
    }
    std.debug.print("lerp(a, b, t) != lerp(b, a, 1 - t): {d} of {d}\n", .{ scalar_differ, n });

    // Edges with one end in front of the near plane (z > 0) and one
    // behind (z < 0), cut from either end.
    var cut_differ: u32 = 0;
    var max_gap: f32 = 0;
    for (0..n) |_| {
        var inside: Vec4 = undefined;
        var outside: Vec4 = undefined;
        inline for (0..4) |i| {
            inside[i] = random.float(f32) * 4 - 2;
            outside[i] = random.float(f32) * 4 - 2;
        }
        inside[2] = random.float(f32) * 2 + 0.001;
        outside[2] = -(random.float(f32) * 2 + 0.001);
        const u = crossingFrom(inside, outside);
        const v = crossingFrom(outside, inside);
        if (!@reduce(.And, u == v)) {
            cut_differ += 1;
            max_gap = @max(max_gap, @reduce(.Max, @abs(u - v)));
        }
    }
    std.debug.print("crossing from one end != from the other: {d} of {d} (largest gap {e})\n", .{ cut_differ, n, max_gap });
    std.debug.print("crossing always from the inside end: 0 of {d}, by construction\n", .{n});
}
```

```console
$ zig run examples/ch17/lerp_order.zig
lerp(a, b, t) != lerp(b, a, 1 - t): 353994 of 1000000
crossing from one end != from the other: 846922 of 1000000 (largest gap 5.9604645e-7)
crossing always from the inside end: 0 of 1000000, by construction
```

- A third of random scalar lerps differ depending on direction.
- For whole crossings, four lanes each with its own rounding, plus a t that is itself rounded
  differently from each end, 85% differ in at least one lane. The gaps are tiny, at most
  6e-7 here, but tiny is enough. A pixel center can sit exactly where one triangle's edge says
  "inside" and the other's says "outside".
- `inline for (0..4)` is the compile-time loop that the previous section's error asked for:
  `inside[i]` with an `i` known at compile time is allowed on a vector.
- The fix is not to compute more precisely. It's to compute *the same thing*. If both triangles
  always start from the end that is inside the plane, they do the exact same operations on
  the exact same inputs and get the exact same bits. That is what `crossing(inside, outside,
  plane)` does: `clipPolygon` passes `(a, b)` when a is inside and `(b, a)` when b is.

The last test in `clip.zig` checks it. Two triangles share the edge a–b, which crosses the
near plane, and list it in opposite orders:

```zig
test "two triangles sharing an edge are cut at the same point" {
    const a: Vertex = .{ .pos = .{ 0.3, 0.1, -0.7, 0.2 } }; // behind
    const b: Vertex = .{ .pos = .{ -0.2, 0.4, 0.9, 3.1 } };
    const left = clipTriangle(.{ a, b, .{ .pos = .{ -1, 0, 0.5, 2 } } }, .initOne(.near));
    const right = clipTriangle(.{ b, a, .{ .pos = .{ 1, 0, 0.5, 2 } } }, .initOne(.near));
    // The corners the two polygons have in common, bit for bit: b, and
    // the crossing on edge a-b.
    var shared: usize = 0;
    for (left.vertices()) |u| {
        for (right.vertices()) |v| shared += @intFromBool(@reduce(.And, u.pos == v.pos));
    }
    try testing.expectEqual(2, shared);
}
```

`u.pos == v.pos` on two vectors gives a vector of four bools, and `@reduce(.And, ...)` is true
when all four are. The test counts corners that are equal bit for bit, not approximately.

This is one of three things that together make a mesh *watertight*, so that no pixel ever
falls between two triangles that share an edge:

1. A corner shared by two meshes gets the same clip coordinates in both. Chapter 16 made sure
   of that by transforming every vertex to the world first, instead of multiplying the model
   matrix into the view-projection matrix.
2. A shared edge is cut at the same point by both triangles: this chapter, by cutting from the
   inside end.
3. A pixel center exactly on a shared edge goes to exactly one of the two triangles. That is
   the *fill rule*, in Chapter 18.

Leave out any one, and the solid maze of the next chapter gets sparkling cracks.

## Drawing what is left

`render3d.Renderer.drawWireframe` gains the outcode tests and the clipper. The loop over
triangles builds a `clip.Vertex` per corner and folds the three outcodes into a union (`any`)
and an intersection (`all`):

```zig
        var i: usize = 0;
        while (i < mesh.indices.len) : (i += 3) {
            stats.triangles += 1;
            var tri: [3]clip.Vertex = undefined;
            var any: clip.Outcode = .empty; // outside of some corner
            var all: clip.Outcode = .full; // outside of every corner
            for (&tri, mesh.indices[i..][0..3]) |*v, index| {
                v.* = .{ .pos = r.clip[index] };
                const code = clip.outcode(v.pos);
                any = any.unionWith(code);
                all = all.intersectWith(code);
            }
            if (all.count() > 0) {
                stats.outside += 1;
                continue;
            }
            if (any.contains(.near) and !options.clip_near) {
                stats.behind += 1;
                continue;
            }
            if (any.count() > 0) stats.clipped += 1;
            const poly = clip.clipTriangle(tri, any);
            if (poly.len == 0) continue;
```

- `mesh.indices[i..][0..3]` is a slice of length 3 known at compile time, so the `for` can
  zip it with the three-element array `&tri`.
- `.full` is the set of all six planes, the right start for an intersection, as `.empty` is
  for a union.
- `options.clip_near` is new. Turned off, a triangle reaching behind the near plane is dropped
  whole, Chapter 16's rule, so the two can be compared side by side.

Then the polygon's corners are divided by w and turned into pixels, and its edges drawn:

```zig
            var p: [clip.max_vertices]draw.Point = undefined;
            for (poly.vertices(), p[0..poly.len]) |v, *point| {
                const s = camera.toScreen(v.pos, canvas.width, canvas.height);
                point.* = .{ .x = @intFromFloat(@floor(s[0])), .y = @intFromFloat(@floor(s[1])) };
            }
            for (poly.vertices(), 0..) |v, k| {
                const edge_color = if (v.edge) |plane| switch (plane) {
                    .near => near_edge_color,
                    // Edges along the sides of the view volume run
                    // along the edges of the screen: not worth drawing.
                    else => continue,
                } else color;
                draw.line(canvas, p[k], p[(k + 1) % poly.len], edge_color);
            }
            stats.drawn += 1;
        }
```

- `camera.toScreen` is Chapter 15's divide and viewport. Every vertex it sees now has
  w ≥ 0.05, so the divide is always safe.
- The edge colors use the `edge` field. An original edge gets the mesh's color. An edge the
  near plane made is drawn in magenta (`near_edge_color`, `0xff40ff`), so the cut is visible.
  An edge made by a side plane lies along the border of the screen. Drawing it would frame the
  screen with lines, so `continue` skips it. The `continue` inside the `switch` inside the
  `if` expression jumps straight to the next iteration of the `for`.
- Without clipping, `drawWireframe` drew three lines per triangle. Now it draws the polygon's
  edges, so a shared edge between two triangles is still drawn twice, as before.

`Stats` grows two counters, `outside` and `clipped`, and `render3d.Options` is new:

```zig
pub const Options = struct {
    /// Clip triangles against the near plane. Without it, a triangle with
    /// a corner behind the near plane is dropped whole, as in chapter 16.
    clip_near: bool = true,
};
```

The last test in `render3d.zig` puts the eye inside a cube, near its back face. The four side
faces reach from in front of the eye to behind it:

```zig
test "clipping keeps what dropping whole triangles loses" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24);
    defer r.deinit(gpa);
    const cube = @import("mesh.zig").cube;
    const vp = camera.Camera.projection(64, 40);

    // The eye is inside the cube, near its back face. The side faces
    // reach behind the eye, and their far ends are in view.
    const model = Mat4.translation(.{ -0.5, -0.5, -0.9 });
    var stats: Stats = .{};
    r.drawWireframe(canvas, cube, model, vp, Color.white, .{}, &stats);
    try std.testing.expect(stats.clipped > 0 and stats.behind == 0);
    const drawn = stats.drawn;

    stats = .{};
    r.drawWireframe(canvas, cube, model, vp, Color.white, .{ .clip_near = false }, &stats);
    try std.testing.expect(stats.behind > 0 and stats.drawn < drawn);
}
```

With clipping some triangles are clipped and none dropped. Without it, some are dropped as
"behind", and fewer are drawn.

## Faster, too

Chapter 16's wireframe was slow, and not because of the triangles in view. A triangle beside
the player, with every corner in front of the eye but far outside the screen, projected to
lines tens of thousands of pixels long, and `draw.line` stepped through every one of their
pixels, checking each against the canvas and drawing none. Now that triangle is either
rejected by its outcodes, which costs six comparisons per corner, or clipped, so no line it
draws is longer than the screen.

Timing 600 frames of the wireframe from the pose Chapter 13 used, in a release build:

```console
$ cd project/ch16
$ zig build --release=fast
$ /usr/bin/time -f "%e s" ./zig-out/bin/delve --headless --frames 600 --view wireframe --pos 9.5,10.5 --yaw -60
2.38 s
$ cd ../ch17
$ zig build --release=fast
$ /usr/bin/time -f "%e s" ./zig-out/bin/delve --headless --frames 600 --view wireframe --pos 9.5,10.5 --yaw -60
0.14 s
```

(The best of three runs each. The machine was shared, and the slowest Chapter 16 run took
2.89 s, the slowest Chapter 17 run 0.15 s.) About 17 times faster: from 4 ms per frame to a
quarter of a millisecond.

GPUs do something cleverer. Clipping against the four side planes is expensive in hardware,
and almost never needed: the rasterizer only visits pixels on the screen anyway. So GPUs clip
against a *guard band*, a much larger rectangle around the screen, and only for triangles
that poke out of even that. The near plane must always be clipped, for the reasons at the top
of this chapter. Fabian Giesen's "A trip through the Graphics Pipeline", part 5, describes how
this works in real hardware. `delve` clips against all six planes because it is simple and
because Chapter 18 needs it: its rasterizer computes with 32-bit integers that would overflow
for corners far off the screen. Exercise 3 tries a guard band anyway.

## Building delve: clipping

At the end of [Chapter 16](16-wireframe-3d.md), the wireframe maze dropped every triangle with
a corner behind the near plane. This chapter clips instead.

| File | Change |
|---|---|
| `src/clip.zig` | new: `Plane`, `Outcode`, `Varyings`, `Vertex`, `Polygon`, `clipTriangle`, five tests |
| `src/render3d.zig` | outcodes and clipping in `drawWireframe`; `Options` with `clip_near`; `Stats.outside` and `Stats.clipped`; near edges in magenta; a test |
| `src/maze3d.zig` | `drawWireframe` takes and passes on the options |
| `src/app.zig` | `render_options`, the `toggle_clipping` action, the HUD line |
| `src/input.zig` | a new action, `toggle_clipping` |
| `src/platform.zig` | C is `toggle_clipping` |
| `src/main.zig` | the test block imports `clip.zig` |

The complete project is in `project/ch17/`, 3040 lines (`cat src/*.zig | wc -l`), up from 2745.

The app keeps the options and flips `clip_near` when C is pressed:

```zig
        if (input.pressed.contains(.toggle_clipping)) {
            app.render_options.clip_near = !app.render_options.clip_near;
        }
```

and passes them to `maze3d.drawWireframe` and to the spinning cube's `drawWireframe`. The HUD's
stats line gains the new counters:

```zig
            const line = std.fmt.bufPrint(&buffer, "triangles {d}  outside {d}  clipped {d}  behind near {d}  drawn {d}", .{
                s.triangles, s.outside, s.clipped, s.behind, s.drawn,
            }) catch unreachable;
```

### Running it

```console
$ cd project/ch17
$ zig build test --summary all
Build Summary: 6/6 steps succeeded; 43/43 tests passed
test success
+- run test 43 pass (43 total) 18ms MaxRSS:7M
   +- compile test debug native success 598ms MaxRSS:187M
      +- WriteFile raylib.h success
      +- compile lib raylib debug native success 3s MaxRSS:481M
      +- compile lib raylib debug native (reused)
      +- translate-c success 20ms MaxRSS:41M
```

Chapter 16 had 37 tests. The new ones are the five in `clip.zig` and "clipping keeps what
dropping whole triangles loses".

`zig build run` opens the window. Tab cycles the views as before; in the wireframe, walk up to
a wall and press C to switch between clipping and Chapter 16's dropping.

First, the pose from Chapter 13, in the wireframe:

```console
$ ./zig-out/bin/delve --headless --view wireframe --pos 9.5,10.5 --yaw -60 --out ch13-pose.png
```

Its HUD reads `TRIANGLES 2616  OUTSIDE 2062  CLIPPED 78  BEHIND NEAR 0  DRAWN 554`. Of the 2616
triangles of the 218 wall cubes that touch the floor, 2062 are rejected by their outcodes alone: four out of five.
Chapter 16 "drew" 1371 triangles at this pose, most of them as lines entirely off the screen;
now 554 are drawn, 78 of them clipped.

Next, standing beside the west wall of the cellar and looking along it:

```console
$ ./zig-out/bin/delve --headless --view wireframe --pos 1.15,12.5 --yaw -105 --out ../../images/ch17-clipped.png
```

![The wireframe maze seen from right next to a wall. Huge orange triangles of the near wall fan out across the left half of the screen, their edges running off the top and bottom. A vertical orange line runs down the middle of the screen. To the right, a corridor of smaller wall cubes recedes into the distance. The HUD reads TRIANGLES 2616  OUTSIDE 2342  CLIPPED 45  BEHIND NEAR 0  DRAWN 273, and POS 1.15,12.50  YAW 255.](images/ch17-clipped.png)

- The player is 0.15 units from the wall on their left. The wall's triangles are so close that
  they fill half the screen. Their edges run off the screen, and the side planes cut them
  there; those cut edges aren't drawn.
- 2342 triangles are outside, 45 clipped, 273 drawn.
- With `--press toggle_clipping` added, the HUD reads `OUTSIDE 2342  CLIPPED 43  BEHIND NEAR 2
  DRAWN 272`: two triangles reach behind the near plane and are dropped. One of them would
  have contributed a drawn polygon (273 versus 272). In the wireframe you can't see the loss
  at all: `compare` finds no differing pixel above the HUD, because the edges of the lost
  triangles are also edges of triangles that are kept. In Chapter 18 the same pose without
  clipping has a hole in the wall.

Finally, the eye right at a wall corner, 0.03 units from the wall:

```console
$ ./zig-out/bin/delve --headless --view wireframe --pos 1.03,12.3 --yaw -135 --out ../../images/ch17-near-cut.png
```

![The wireframe with the eye almost touching a wall. Long orange lines cross the left half of the screen, and a bright magenta vertical line runs from the top of the screen to the bottom just left of the middle. To the right, a corridor of cubes recedes. The HUD reads TRIANGLES 2616  OUTSIDE 2534  CLIPPED 70  BEHIND NEAR 0  DRAWN 81, and POS 1.03,12.30  YAW 225.](images/ch17-near-cut.png)

- The magenta line is where the near plane, 0.05 units in front of the eye, slices through the
  wall the player is facing at an angle. The part of the wall nearer than that is cut away;
  the rest is drawn, starting at the magenta line.
- The near plane is flat, perpendicular to the view direction, so its cut through a flat
  vertical wall is a vertical line on the screen.
- The eye can get this close to a wall because the player is still a point: the movement code
  of Chapter 11 only stops the point itself from entering a wall cell. With the near plane at
  0.05, a player closer than that to a wall would see *through* it, since the whole wall would
  be clipped away. Chapter 22 gives the player a radius of 0.25, which keeps the near plane
  out of the walls.

The timing at the end of the previous section used the release build:

```console
$ zig build --release=fast
$ /usr/bin/time -f "%e s" ./zig-out/bin/delve --headless --frames 600 --view wireframe --pos 9.5,10.5 --yaw -60
0.14 s
```

## Summary

- Dividing by w is wrong for points behind the eye (w < 0 mirrors them) and blows up near
  w = 0. An edge crossing w = 0 does not project to the segment between its projected ends.
- In clip space the view volume is `−w ≤ x ≤ w`, `−w ≤ y ≤ w`, `0 ≤ z ≤ w`: six planes, each a
  signed distance that is ≥ 0 inside. The near plane z = 0 is where w = near, so after
  clipping every vertex has w ≥ near > 0.
- Clip before the divide: the projection is linear, so edges stay straight in clip space,
  fraction t along an edge is the same in the world and in clip space, and every plane is
  crossed at `t = d(a)/(d(a) − d(b))`.
- Outcodes (`std.EnumSet(Plane)`) accept a triangle whose union is empty, reject one whose
  intersection isn't, and say which planes the rest must be clipped against.
- Sutherland–Hodgman clips a polygon against one plane per pass with four cases per edge.
  Each plane adds at most one vertex, so a clipped triangle has at most 9, kept in a fixed
  buffer on the stack.
- Varyings are cut with the same t as the position, which is right because they are linear in
  the world. A `@Vector` can't be indexed at run time; coerce it to an array for that.
- Always computing a crossing from the inside end makes two triangles agree on their shared
  edge bit for bit. It's one of the three parts of a watertight mesh.
- In `delve`, near cuts are drawn magenta, C brings back the old drop rule, and the wireframe
  runs about 17 times faster because rejected triangles cost a few comparisons and clipped
  lines end at the screen.

## Exercises

1. **How big do the polygons get?** A clipped triangle can have up to 9 corners. Count how many
   it really has, over a walk through the maze: 600 frames walking forward and turning
   (`--hold 1,0,0.3`). Is 9 ever reached?

   <details><summary>Solution</summary>

   Add a histogram to `Stats` in `src/render3d.zig`:

   ```zig
       /// How many clipped triangles came out with 0, 1, ... 9 vertices.
       sizes: [clip.max_vertices + 1]u32 = @splat(0),
   ```

   and fill it right after the clipper in `drawWireframe`:

   ```zig
               const poly = clip.clipTriangle(tri, any);
               if (any.count() > 0) stats.sizes[poly.len] += 1;
   ```

   `Stats` is created afresh every frame, so the app has to add up the frames. Give `App` a
   total, `poly_sizes: [10]u32 = @splat(0)`, and in `render` add each frame's histogram to it:

   ```zig
           if (stats) |s| {
               for (&app.poly_sizes, s.sizes) |*total, n| total.* += n;
   ```

   For that, `render` has to take `app: *App` instead of `app: App`. The call sites in
   `main.zig` don't change, because Zig takes the address of `app` automatically when calling a
   method that wants a pointer. After the headless loop in `main.zig`, print the total:

   ```zig
           std.debug.print("clipped polygon sizes: {any}\n", .{app.poly_sizes});
   ```

   ```console
   $ ./zig-out/bin/delve --headless --frames 600 --view wireframe --hold 1,0,0.3
   clipped polygon sizes: { 582, 0, 0, 20989, 22341, 1480, 23, 0, 0, 0 }
   $ ./zig-out/bin/delve --headless --frames 600 --view wireframe --hold 1,0.5,-0.7
   clipped polygon sizes: { 519, 0, 0, 15520, 17405, 1663, 43, 0, 0, 0 }
   ```

   Most clipped triangles come out as triangles or quads: one plane cutting off one or two
   corners. Five and six corners are rare, and in these walks nothing reached seven. Getting
   to nine needs a triangle that sticks out of all six planes at once, a huge triangle seen
   from inside, which a maze of unit cubes doesn't make. The 0s are the incomplete-reject case
   from the outcode section: triangles that the outcodes couldn't reject, but that have no part
   inside the view volume. 1 and 2 never occur, because `clipTriangle` returns an empty
   polygon as soon as fewer than 3 corners are left.

   </details>

2. **See the far plane.** The far plane is 64 units away, farther than anything in the
   cellar, so it never cuts anything. Move it to 6 units and draw the edges it makes in cyan.
   What shape is its cut through the walls?

   <details><summary>Solution</summary>

   In `src/camera.zig`, change `pub const far = 64.0;` to `pub const far = 6.0;`. In
   `src/render3d.zig`, add a color next to the magenta one:

   ```zig
   /// The color of edges made by the far plane.
   pub const far_edge_color: Color = .hex(0x40ffff);
   ```

   and a case to the `switch` in `drawWireframe`:

   ```zig
                       .near => near_edge_color,
                       .far => far_edge_color,
   ```

   The tests still pass (none of them depends on the far distance). At the Chapter 13 pose:

   ```console
   $ ./zig-out/bin/delve --headless --view wireframe --pos 9.5,10.5 --yaw -60 --out far6.png
   ```

   The HUD reads `TRIANGLES 2616  OUTSIDE 2523  CLIPPED 38  BEHIND NEAR 0  DRAWN 93`: everything
   beyond 6 units is rejected now. Down the long corridor on the right, the wireframe stops
   abruptly at a pair of vertical cyan lines. The far plane, like the near plane, is flat and
   faces the camera, so it cuts the vertical walls along vertical lines. It does not cut at a
   fixed *distance* from the eye (that would be a sphere), but at a fixed depth along the view
   direction. Games with a short far plane hide that straight cut with fog, which Chapter 19
   adds.

   </details>

3. **Guard-band clipping.** Clip against the four side planes only when a corner is far outside
   the screen, as GPUs do, and leave the rest to the line routine. Use a guard band of twice
   the screen in each direction, `−2w ≤ x ≤ 2w` and the same for y. How many triangles still
   need clipping at the Chapter 13 pose?

   <details><summary>Solution</summary>

   In `src/clip.zig`, give the planes a band width. `distance` keeps its meaning (band 1, the
   screen), and a new function moves the side planes out:

   ```zig
       /// How far inside the plane `p` is (in clip-space units): negative
       /// means outside.
       pub fn distance(plane: Plane, p: Vec4) f32 {
           return plane.guardDistance(p, 1);
       }

       /// The same, with the four side planes moved `band` times as far
       /// from the screen's center: -band * w <= x <= band * w.
       pub fn guardDistance(plane: Plane, p: Vec4, band: f32) f32 {
           const x, const y, const z, const w = p;
           return switch (plane) {
               .near => z,
               .far => w - z,
               .left => band * w + x,
               .right => band * w - x,
               .bottom => band * w + y,
               .top => band * w - y,
           };
       }
   ```

   Do the same for the outcode, `guardOutcode(p, band)`, with `outcode(p)` calling it with 1.
   Pass `band` down through the clipper: `clipTriangle(tri, planes)` calls a new
   `clipTriangleGuarded(tri, planes, 1)`, and `clipPolygon` and `crossing` take `band` and use
   `guardDistance(…, band)` instead of `distance`. The tests keep calling `clipTriangle` and
   still pass.

   In `drawWireframe`, keep rejecting with the real outcodes, since a triangle outside the
   screen is invisible however wide the band is. Clip with the guard band:

   ```zig
   /// Corners may be up to half a screen past each edge before the side
   /// planes cut: 320 * (1 + 2) = 960 pixels at most on a 640-pixel canvas.
   const guard_band = 2;
   ```

   ```zig
               var guard: clip.Outcode = .empty; // outside the guard band
               for (&tri, mesh.indices[i..][0..3]) |*v, index| {
                   v.* = .{ .pos = r.clip[index] };
                   const code = clip.outcode(v.pos);
                   any = any.unionWith(code);
                   all = all.intersectWith(code);
                   guard = guard.unionWith(clip.guardOutcode(v.pos, guard_band));
               }
   ```

   ```zig
               if (guard.count() > 0) stats.clipped += 1;
               const poly = clip.clipTriangleGuarded(tri, guard, guard_band);
   ```

   At the Chapter 13 pose the HUD now reads `CLIPPED 2` instead of `CLIPPED 78`, and at the
   `ch17-clipped.png` pose `CLIPPED 2` instead of 45, with `DRAWN 274` instead of 273. The extra
   drawn triangle is one that full clipping cut down to nothing: it is in the guard band but
   not on the screen, so its lines are drawn off the canvas. The pictures look the same, but
   `compare` counts a few hundred differing pixels (741 and 549 at the two poses). A line drawn
   from a different starting point, outside the screen instead of on its edge, steps through
   slightly different pixels on its way across. For this renderer the band brings nothing
   measurable, because full clipping was cheap already. On a GPU, where every extra vertex
   costs real hardware, it's a big deal. Keep the bound in mind for Chapter 18: corners up to
   960 pixels out still fit its 1024-pixel limit.

   </details>

4. **Clip lines, not triangles.** For a wireframe, clip each edge on its own with the
   Liang–Barsky method. Instead of making new vertices one plane at a time, it narrows the
   range of t that is inside: each plane the segment enters through raises the start, each
   plane it leaves through lowers the end. Write `clipLine(a, b: Vec4) ?[2]f32`, test it, and
   draw the wireframe with it.

   <details><summary>Solution</summary>

   In `src/clip.zig`:

   ```zig
   /// The part of the segment a->b inside the view volume, as the range of
   /// t (0 at a, 1 at b) it covers, or null if none of it is inside. Each
   /// plane the segment enters through raises the start; each plane it
   /// leaves through lowers the end (the Liang-Barsky algorithm).
   pub fn clipLine(a: Vec4, b: Vec4) ?[2]f32 {
       var t_in: f32 = 0;
       var t_out: f32 = 1;
       for (std.enums.values(Plane)) |plane| {
           const da = plane.distance(a);
           const db = plane.distance(b);
           if (da < 0 and db < 0) return null;
           if (da < 0) t_in = @max(t_in, da / (da - db)); // entering
           if (db < 0) t_out = @min(t_out, da / (da - db)); // leaving
       }
       if (t_in > t_out) return null;
       return .{ t_in, t_out };
   }
   ```

   ```zig
   test "a segment is cut to the part inside every plane" {
       // From behind the eye and left of the view to inside the view.
       const a: Vec4 = .{ -3, 0, -1, 1 };
       const b: Vec4 = .{ 0, 0, 1, 1 };
       const t = clipLine(a, b).?;
       // z = 0 at t = 0.5; x = -w at t = 2/3, so the left plane wins.
       try testing.expectApproxEqAbs(2.0 / 3.0, t[0], 1e-6);
       try testing.expectEqual(1, t[1]);
       // Left of the view at both ends of the part in front: nothing left.
       try testing.expectEqual(null, clipLine(.{ -3, 0, -1, 1 }, .{ -1.5, 0, 1, 1 }));
   }
   ```

   The second case is the one per-plane rejection can't catch: the segment is partly in front
   of the near plane and partly right of the left plane, but the two parts don't overlap, so
   `t_in` (0.75) ends up past `t_out` (0.5).

   In `drawWireframe`, after the outcode tests, draw the three edges instead of clipping the
   triangle:

   ```zig
               for (0..3) |k| {
                   const a = tri[k].pos;
                   const b = tri[(k + 1) % 3].pos;
                   const t = clip.clipLine(a, b) orelse continue;
                   var ends: [2]draw.Point = undefined;
                   for (t, &ends) |tk, *end| {
                       const s = camera.toScreen(math.lerp(a, b, tk), canvas.width, canvas.height);
                       end.* = .{ .x = @intFromFloat(@floor(s[0])), .y = @intFromFloat(@floor(s[1])) };
                   }
                   draw.line(canvas, ends[0], ends[1], color);
               }
               stats.drawn += 1;
   ```

   The tests pass (44 now). The picture at the `ch17-clipped.png` pose looks the same, with 280
   pixels different: there are no near-plane edges any more (a line clipper doesn't make new
   edges), and some line ends land on different pixels. It is slower, 0.26 s for the 600-frame
   timing instead of 0.14 s, because every edge shared by two triangles is clipped and drawn
   twice, and the diagonals of every face are drawn too. Collecting the index pairs of the mesh
   once and drawing each pair only once would fix that, and is how a real line renderer would
   do it.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-17--clipping)
