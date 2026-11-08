# Chapter 11 — Vectors and the Maze

From here on, everything `delve` does is geometry: where the player stands, which way they
face, how far a wall is, whether a thing is in front or behind. The language for all of that is
the *vector*. This chapter builds `math.zig` on Zig's built-in SIMD vectors, `@Vector(2, f32)`
and `@Vector(3, f32)`, and derives each operation before writing it: length and
normalization, the dot product and what its sign means, the cross product and its right-hand
rule, and rotation by an angle. Every function gets a test, and you will see why those tests
must not compare floats with `==`. To use the math right away, `delve` gets a maze: a text map
embedded in the binary, a player who walks with WASD and turns with the arrow keys, collision
that slides along walls, and a top-down view showing where the player looks.

Previous: [Chapter 10 — Drawing in 2D by Hand](10-drawing-in-2d.md). Next:
[Chapter 12 — Matrices and Transforms](12-matrices-and-transforms.md).

## Points and directions

A vector in this course is a short list of numbers, `(x, y)` or `(x, y, z)`. The same list can
mean two different things, and keeping them apart avoids most mistakes:

- A **point** is a place: "the player is at (2, 1)".
- A **direction** (or displacement) is a way to move: "three right and four down", (3, 4). It
  has no place of its own. Draw it as an arrow anywhere you like; it is the same arrow.

The arithmetic follows from the meaning:

| Expression          | Result    | Meaning                                    |
|---------------------|-----------|--------------------------------------------|
| point + direction   | point     | start at p, move by d                      |
| point − point       | direction | the arrow from p to q is q − p             |
| direction + direction | direction | move by one, then the other            |
| direction · number  | direction | the same arrow, longer, shorter or flipped |
| point + point       | (nothing) | "Paris + Rome" is not a place             |

One combination of points is fine: a weighted average whose weights add up to 1. The point a
fraction `t` of the way from `a` to `b` is `a + t·(b − a) = (1 − t)·a + t·b`. This is called
linear interpolation, `lerp`. Chapter 12 gives points and directions a fourth number that makes
this bookkeeping automatic.

On `delve`'s map, x grows to the right and y grows *down*, like rows of text and like the pixels
of the canvas from [Chapter 9](09-framebuffers.md). One unit is one map cell. Remember the
y-down part: it decides which way "positive angle" turns.

## Zig's vectors: @Vector

Zig has a vector type built into the language: `@Vector(n, T)` holds `n` values of type `T`,
called *lanes*, and the arithmetic operators work on all lanes at once.

`examples/ch11/vector_basics.zig`

```zig
//! @Vector arithmetic: points, directions, and lane-wise operators.
const std = @import("std");

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

pub fn main() void {
    const p: Vec2 = .{ 2, 1 }; // a point: where something is
    const q: Vec2 = .{ 5, 5 };
    const d = q - p; // a direction: how to get from p to q

    std.debug.print("p = {any}, q = {any}\n", .{ p, q });
    std.debug.print("q - p = {any}\n", .{d});
    std.debug.print("p + d = {any} (back at q)\n", .{p + d});
    std.debug.print("p + d * 0.5 = {any} (half way)\n", .{p + d * @as(Vec2, @splat(0.5))});

    // Operators work lane by lane. `*` is NOT a dot product.
    const a: Vec3 = .{ 1, 2, 3 };
    const b: Vec3 = .{ 4, 5, 6 };
    std.debug.print("a * b = {any}\n", .{a * b});
    std.debug.print("@reduce(.Add, a * b) = {d}\n", .{@reduce(.Add, a * b)});
    const c: Vec3 = .{ 3, 0, 9 };
    std.debug.print("@min(a, c) = {any}, @max(a, c) = {any}\n", .{ @min(a, c), @max(a, c) });
    std.debug.print("@floor(.{{ 2.7, -0.5 }}) = {any}\n", .{@floor(Vec2{ 2.7, -0.5 })});

    // Lanes by index, and destructuring into named values.
    const x, const y, const z = a;
    std.debug.print("a[0] = {d}, x y z = {d} {d} {d}\n", .{ a[0], x, y, z });

    // A vector and an array of the same length coerce into each other.
    const arr: [3]f32 = a;
    const back: Vec3 = arr;
    std.debug.print("as array {any}, back {any}\n", .{ arr, back });

    // Comparisons give a vector of bools; @reduce turns it into one bool.
    const less = a < c;
    std.debug.print("a < c = {any}, all: {}, any: {}\n", .{ less, @reduce(.And, less), @reduce(.Or, less) });
}
```

```console
$ zig run examples/ch11/vector_basics.zig
p = { 2, 1 }, q = { 5, 5 }
q - p = { 3, 4 }
p + d = { 5, 5 } (back at q)
p + d * 0.5 = { 3.5, 3 } (half way)
a * b = { 4, 10, 18 }
@reduce(.Add, a * b) = 32
@min(a, c) = { 1, 0, 3 }, @max(a, c) = { 3, 2, 9 }
@floor(.{ 2.7, -0.5 }) = { 2, -1 }
a[0] = 1, x y z = 1 2 3
as array { 1, 2, 3 }, back { 1, 2, 3 }
a < c = { true, false, true }, all: false, any: true
```

- `q - p` is the arrow from p to q, (3, 4). Adding it back to p lands on q; adding half of it
  lands half way. This is the table above, in code.
- There is no "vector times number" operator. `@splat(0.5)` makes a vector with 0.5 in every
  lane (the result type comes from the `@as`), and then `*` is lane by lane.
- `a * b` multiplies lane by lane: (1·4, 2·5, 3·6). It is *not* the dot product, but summing
  its lanes with `@reduce(.Add, ...)` is: 4 + 10 + 18 = 32. That one line will be our `dot`.
- `@min`, `@max`, `@floor`, `@sqrt`, `@abs` and most math builtins work per lane. Note
  `@floor(-0.5) = -1`: floor rounds *down*, not toward zero. The map code relies on that.
- Lanes are read with `a[0]` or by destructuring. A vector coerces to an array of the same
  length and back.
- `a < c` gives a `@Vector(3, bool)`; `@reduce(.And, ...)` asks "all lanes?", `.Or` "any?".

Why not `struct { x: f32, y: f32 }`? Three reasons. Operators: `p + d * s` reads like the math,
while a struct needs `p.add(d.scale(s))`. Code generation: the compiler maps `@Vector`
operations to SIMD instructions where the CPU has them. And generic code: one `dot` written for
`@Vector(n, f32)` works for 2, 3 and (next chapter) 4 lanes, where structs would need one
function per type.

The price is that the lanes have no names. `p.x` does not exist:

```zig
const std = @import("std");

pub fn main() void {
    const p: @Vector(2, f32) = .{ 3, 4 };
    std.debug.print("{d}\n", .{p.x});
}
```

```console
$ zig run field_bad.zig
field_bad.zig:5:33: error: type '@Vector(2, f32)' does not support field access
    std.debug.print("{d}\n", .{p.x});
                               ~^~
```

(Here and below, the `referenced by:` lines after an error are trimmed.) We write `p[0]` and
`p[1]` and say "x" and "y" in comments.

The second surprise is indexing. A vector lives in a SIMD register, not in memory, so reading
lane `i` of a run-time vector needs `i` to be known at compile time:

```zig
const std = @import("std");

fn lane(v: @Vector(4, f32), i: usize) f32 {
    return v[i];
}

pub fn main() void {
    const v: @Vector(4, f32) = .{ 3, -1, 8, 2 };
    for (0..4) |i| std.debug.print("{d}\n", .{lane(v, i)});
}
```

```console
$ zig run lane_bad.zig
lane_bad.zig:4:14: error: vector index not comptime known
    return v[i];
             ^
```

There are two ways around it: unroll the loop at compile time so every index is a constant, or
copy the vector into an array, which can be indexed with anything.

`examples/ch11/vector_index.zig`

```zig
//! Reading vector lanes in a loop. `v[i]` needs a comptime-known `i` when
//! `v` is a runtime vector; these are the two ways around that.
const std = @import("std");

const Vec4 = @Vector(4, f32);

/// The largest lane, with the loop unrolled at compile time: every `i`
/// is a comptime constant, so `v[i]` is allowed.
fn maxLaneInline(v: Vec4) f32 {
    var best = v[0];
    inline for (1..4) |i| best = @max(best, v[i]);
    return best;
}

/// The same with a runtime loop over an array copy: array elements can be
/// indexed by runtime values.
fn maxLaneArray(v: Vec4) f32 {
    const lanes: [4]f32 = v;
    var best = lanes[0];
    for (lanes[1..]) |x| best = @max(best, x);
    return best;
}

/// Lane `i`, where `i` is only known at run time.
fn lane(v: Vec4, i: usize) f32 {
    const lanes: [4]f32 = v;
    return lanes[i];
}

pub fn main() void {
    var v: Vec4 = .{ 3, -1, 8, 2 };
    v[1] = 5; // a comptime index works for writing too
    std.debug.print("v = {any}\n", .{v});
    std.debug.print("maxLaneInline = {d}\n", .{maxLaneInline(v)});
    std.debug.print("maxLaneArray  = {d}\n", .{maxLaneArray(v)});
    for (0..4) |i| std.debug.print("lane({d}) = {d}\n", .{ i, lane(v, i) });
    // For the common "largest lane" there is a builtin as well.
    std.debug.print("@reduce(.Max, v) = {d}\n", .{@reduce(.Max, v)});
}
```

```console
$ zig run examples/ch11/vector_index.zig
v = { 3, 5, 8, 2 }
maxLaneInline = 8
maxLaneArray  = 8
lane(0) = 3
lane(1) = 5
lane(2) = 8
lane(3) = 2
@reduce(.Max, v) = 8
```

- `inline for` repeats its body once per index at compile time, so inside it `i` is a
  `comptime` value and `v[i]` compiles. Use it for short fixed loops over lanes.
- `const lanes: [4]f32 = v;` is the coercion from the previous example. The copy is cheap (16
  bytes) and the compiler often removes it.
- In practice `delve` rarely needs either: it writes `v[0]` and `v[1]` with literal indexes, and
  `@reduce` covers "sum", "largest" and "all".

## Length, distance, and normalize

The length of (3, 4) is the hypotenuse of a right triangle with legs 3 and 4: by Pythagoras,
√(3² + 4²) = 5. In 3D, apply Pythagoras twice. The vector (x, y, z) is the hypotenuse of a right
triangle whose legs are (x, y, 0), with length √(x² + y²), and (0, 0, z):

```
|v|² = (√(x² + y²))² + z² = x² + y² + z²
```

So in any number of dimensions the squared length is the sum of the squared lanes. That is
`@reduce(.Add, v * v)`, the dot product of `v` with itself (next section): `|v|² = v·v`. For
v = (3, 4, 12), v·v = 9 + 16 + 144 = 169 and |v| = 13, which is the first test in `math.zig`.

The distance between two points is the length of the arrow between them, `length(q - p)`.

A *unit vector* has length 1. It is a pure direction: "east" rather than "three cells east".
Normalizing divides by the length: (3, 4) / 5 = (0.6, 0.8). Most formulas below are simpler
with unit vectors, and the player's movement uses one so that speed is controlled separately.

There is one vector with no direction: (0, 0). Its length is 0, and dividing by 0 gives NaN
("not a number") in every lane. In `delve` that is not an edge case, it is the common case:
the player standing still. Here is what a naive `normalize` does to them:

```zig
const std = @import("std");

const Vec2 = @Vector(2, f32);

fn naiveNormalize(v: Vec2) Vec2 {
    const len = @sqrt(@reduce(.Add, v * v));
    return v / @as(Vec2, @splat(len));
}

pub fn main() void {
    var pos: Vec2 = .{ 1.5, 1.5 };
    var wish: Vec2 = .{ 0, 0 }; // no movement keys held
    _ = &wish;
    pos += naiveNormalize(wish) * @as(Vec2, @splat(0.05));
    std.debug.print("pos = {any}\n", .{pos});
}
```

```console
$ zig run naive_normalize.zig
pos = { -nan, -nan }
```

0 / 0 is NaN, NaN times anything is NaN, and position + NaN is NaN. Every later frame
stays NaN, and nothing crashes: the player simply vanishes. So `math.zig`'s `normalize` returns
the zero vector unchanged. The caller multiplies it by a speed and gets a zero step.

`delve`'s helpers are generic. `dot(a: anytype, b: @TypeOf(a))` accepts any vector for `a`, and
then requires `b` to have exactly the same type. Mixing a 2D and a 3D vector is a compile error,
which is what we want, because it is always a bug:

```zig
const std = @import("std");

fn dot(a: anytype, b: @TypeOf(a)) f32 {
    return @reduce(.Add, a * b);
}

pub fn main() void {
    const a: @Vector(2, f32) = .{ 1, 2 };
    const b: @Vector(3, f32) = .{ 3, 4, 5 };
    std.debug.print("{d}\n", .{dot(a, b)});
}
```

```console
$ zig run mixed_dot.zig
mixed_dot.zig:10:39: error: expected type '@Vector(2, f32)', found '@Vector(3, f32)'
    std.debug.print("{d}\n", .{dot(a, b)});
                                      ^
mixed_dot.zig:10:39: note: destination has length 2
mixed_dot.zig:10:39: note: source has length 3
```

## The dot product

The dot product of two vectors is the sum of the products of their lanes:

```
a·b = a₀b₀ + a₁b₁ (+ a₂b₂ in 3D)
```

That definition says nothing about geometry. Its geometric meaning comes from the law of
cosines. Draw `a` and `b` from the same point with angle θ between them; the third side of the
triangle is `a − b`. The law of cosines says

```
|a − b|² = |a|² + |b|² − 2|a||b| cos θ
```

Now expand the left side with the lane definition. The dot product distributes like ordinary
multiplication (each lane is ordinary multiplication), so

```
|a − b|² = (a − b)·(a − b) = a·a − 2 a·b + b·b = |a|² − 2 a·b + |b|²
```

The two right-hand sides are equal. Cancel |a|² and |b|² and divide by −2:

```
a·b = |a| |b| cos θ
```

A worked example: a = (3, 4), b = (4, 3). By lanes, a·b = 12 + 12 = 24. Both lengths are 5, so
cos θ = 24 / 25 = 0.96 and θ = acos(0.96) ≈ 16.3°. The program below checks that and a few more
pairs.

`examples/ch11/dot_angle.zig`

```zig
//! The dot product: angles between vectors, and "in front or behind".
const std = @import("std");

const Vec2 = @Vector(2, f32);

fn dot(a: Vec2, b: Vec2) f32 {
    return @reduce(.Add, a * b);
}

fn length(v: Vec2) f32 {
    return @sqrt(dot(v, v));
}

/// The angle between `a` and `b` in degrees, from a.b = |a| |b| cos(angle).
fn angleDeg(a: Vec2, b: Vec2) f32 {
    const c = dot(a, b) / (length(a) * length(b));
    // Rounding can push c a hair past 1 (or -1); acos would return NaN.
    return std.math.radiansToDegrees(std.math.acos(std.math.clamp(c, -1, 1)));
}

pub fn main() void {
    const east: Vec2 = .{ 1, 0 };
    const pairs = [_][2]Vec2{
        .{ east, .{ 3, 0 } },
        .{ east, .{ 1, 1 } },
        .{ east, .{ 0, 2 } },
        .{ east, .{ -1, 1 } },
        .{ east, .{ -4, 0 } },
        .{ .{ 3, 4 }, .{ 4, 3 } },
    };
    for (pairs) |pair| {
        const a, const b = pair;
        std.debug.print("a ({d:>2},{d:>2})  b ({d:>2},{d:>2})  a.b {d:>5.1}  angle {d:>5.1}\n", .{
            a[0], a[1], b[0], b[1], dot(a, b), angleDeg(a, b),
        });
    }

    // Only the sign is needed to tell front from back: no square roots,
    // no acos. The player stands at (2, 2) and faces east.
    const eye: Vec2 = .{ 2, 2 };
    const facing = east;
    const things = [_]Vec2{ .{ 6, 3 }, .{ 2, 5 }, .{ 0, 1 } };
    for (things) |t| {
        const d = dot(facing, t - eye);
        const where = if (d > 0) "in front" else if (d < 0) "behind" else "level with us";
        std.debug.print("thing at {any}: dot {d:>4} -> {s}\n", .{ t, d, where });
    }
}
```

```console
$ zig run examples/ch11/dot_angle.zig
a ( 1, 0)  b ( 3, 0)  a.b   3.0  angle   0.0
a ( 1, 0)  b ( 1, 1)  a.b   1.0  angle  45.0
a ( 1, 0)  b ( 0, 2)  a.b   0.0  angle  90.0
a ( 1, 0)  b (-1, 1)  a.b  -1.0  angle 135.0
a ( 1, 0)  b (-4, 0)  a.b  -4.0  angle 180.0
a ( 3, 4)  b ( 4, 3)  a.b  24.0  angle  16.3
thing at { 6, 3 }: dot    4 -> in front
thing at { 2, 5 }: dot    0 -> level with us
thing at { 0, 1 }: dot   -2 -> behind
```

- The angle never exceeds 180°: the dot product measures *how far apart* two directions are, not
  which way you turn to get from one to the other. The cross product below gives the "which
  way".
- The sign of the dot product follows the sign of cos θ: positive under 90°, zero at exactly
  90° (the vectors are *perpendicular*), negative over 90°. The lengths only scale it.
- So "is this thing in front of me?" is one dot product of the facing direction with the arrow
  to the thing, with no square root and no `acos`. Chapter 14 uses it to skip sprites behind
  the camera.
- The `clamp` matters. For two nearly parallel vectors, rounding can make the quotient
  1.0000001, and `acos` of that is NaN.

### Projection: how much of v points along n

If `n` is a unit vector, |n| = 1 and the formula becomes `v·n = |v| cos θ`. That is the length
of the shadow `v` casts on the line through `n`: the *component* of `v` along `n`. Scaling `n`
by it gives the part of `v` along `n`, and what is left over is the part across `n`:

```
along  = (v·n) n
across = v − along
```

`examples/ch11/projection.zig`

```zig
//! Projection: split a vector into a part along a direction and a part
//! across it. dot(v, n) with a unit n is "how much of v points along n".
const std = @import("std");

const Vec2 = @Vector(2, f32);

fn dot(a: Vec2, b: Vec2) f32 {
    return @reduce(.Add, a * b);
}

fn scale(v: Vec2, s: f32) Vec2 {
    return v * @as(Vec2, @splat(s));
}

fn normalize(v: Vec2) Vec2 {
    return scale(v, 1 / @sqrt(dot(v, v)));
}

fn show(name: []const u8, v: Vec2) void {
    std.debug.print("{s:<8} ({d:>6.3}, {d:>6.3})\n", .{ name, v[0], v[1] });
}

pub fn main() void {
    const v: Vec2 = .{ 3, 1 };
    const n = normalize(.{ 1, 1 });
    const along = scale(n, dot(v, n));
    const across = v - along;
    show("v", v);
    show("n", n);
    std.debug.print("dot(v,n) {d:.3}\n", .{dot(v, n)});
    show("along", along);
    show("across", across);
    show("sum", along + across);
    std.debug.print("along . across = {d:.3}\n\n", .{dot(along, across)});

    // Sliding along a wall: remove the part of the motion that goes into
    // the wall. The wall's normal points out of it, toward us.
    const wall_normal: Vec2 = .{ -1, 0 }; // a wall on our east side
    const motion: Vec2 = .{ 0.6, 0.8 }; // walking south-east into it
    const into = dot(motion, wall_normal); // negative: moving into the wall
    const slide = motion - scale(wall_normal, into);
    std.debug.print("into wall {d:.2}\n", .{into});
    show("slide", slide);

    // Distance from a point to a line through `a` with unit normal `m`.
    const a: Vec2 = .{ 0, 2 };
    const m = normalize(.{ 1, -1 }); // normal of the line y = x + 2
    for ([_]Vec2{ .{ 0, 2 }, .{ 2, 0 }, .{ -1, 3 } }) |p| {
        std.debug.print("point ({d}, {d}) signed distance {d:>6.3}\n", .{ p[0], p[1], dot(p - a, m) });
    }
}
```

```console
$ zig run examples/ch11/projection.zig
v        ( 3.000,  1.000)
n        ( 0.707,  0.707)
dot(v,n) 2.828
along    ( 2.000,  2.000)
across   ( 1.000, -1.000)
sum      ( 3.000,  1.000)
along . across = 0.000

into wall -0.60
slide    ( 0.000,  0.800)
point (0, 2) signed distance  0.000
point (2, 0) signed distance  2.828
point (-1, 3) signed distance -1.414
```

Check the first block by hand. n = (1, 1)/√2 ≈ (0.707, 0.707). v·n = (3 + 1)/√2 = 4/√2 = 2√2 ≈
2.828. The part along n is 2√2 · (1, 1)/√2 = (2, 2), and the rest is (3, 1) − (2, 2) = (1, −1).
The two parts add back up to v and are perpendicular: (2, 2)·(1, −1) = 0.

- **Sliding along a wall** is the same split. Remove the part of the motion that goes into the
  wall and keep the rest. Walking (0.6, 0.8) into a wall whose normal is (−1, 0) leaves (0, 0.8):
  the player slides south at 80% speed. `delve`'s first collision code (below) gets this effect
  more cheaply for walls that line up with the grid; Chapter 22 needs the general form.
- **Distance to a line.** A line can be described by one point `a` on it and a unit *normal*
  `m`, perpendicular to the line. For any point p, `(p − a)·m` is the component of p − a across
  the line: the signed distance. Zero means on the line, and the sign tells the side. (2, 0) is
  2√2 ≈ 2.828 from the line y = x + 2. The same formula with a 3D plane normal clips triangles
  in Chapter 17 and culls rooms in Chapter 23.

## The cross product

In 3D there is a second product of two vectors, and its result is a vector:

```
a × b = (a₁b₂ − a₂b₁,  a₂b₀ − a₀b₂,  a₀b₁ − a₁b₀)
```

The pattern: lane 0 of the result uses lanes 1 and 2, lane 1 uses 2 and 0, lane 2 uses 0 and 1,
each time "next times the one after, minus the reverse". Three facts make it useful.

**It is perpendicular to both inputs.** Dot it with `a`:

```
a·(a × b) = a₀(a₁b₂ − a₂b₁) + a₁(a₂b₀ − a₀b₂) + a₂(a₀b₁ − a₁b₀)
          = a₀a₁b₂ − a₀a₂b₁ + a₁a₂b₀ − a₀a₁b₂ + a₀a₂b₁ − a₁a₂b₀ = 0
```

Every term appears once with each sign. The same happens with `b`. So `a × b` is a *normal* of
the plane that contains `a` and `b`, which is how Chapter 18 finds which way a triangle faces.

**Its length is |a| |b| sin θ.** Multiplying out |a × b|² and comparing it with |a|²|b|² gives
Lagrange's identity, |a × b|² = |a|²|b|² − (a·b)². With a·b = |a||b| cos θ, the right side is
|a|²|b|²(1 − cos²θ) = |a|²|b|² sin²θ. Now look at the parallelogram with sides `a` and `b`: its
base is |a| and its height is |b| sin θ. So **the length of a × b is the area of that
parallelogram**, and half of it is the area of the triangle with edges a and b. Parallel vectors
(θ = 0 or 180°) give the zero vector.

**Its direction follows the right-hand rule.** Point the fingers of your right hand along `a`
and curl them toward `b`; your thumb points along `a × b`. With the unit axes x = (1, 0, 0), y =
(0, 1, 0), z = (0, 0, 1), the formula gives x × y = z, y × z = x, z × x = y. Swapping the inputs
flips every sign: b × a = −(a × b). Order matters.

Worked example, a = (1, 2, 3), b = (−4, 0.5, 2):

```
lane 0: a₁b₂ − a₂b₁ = 2·2   − 3·0.5    = 4   − 1.5 =  2.5
lane 1: a₂b₀ − a₀b₂ = 3·(−4) − 1·2     = −12 − 2   = −14
lane 2: a₀b₁ − a₁b₀ = 1·0.5 − 2·(−4)   = 0.5 + 8   =  8.5
```

The lane pattern is exactly what `@shuffle` is for. `@shuffle(f32, a, undefined, mask)` builds
a new vector whose lane i is `a[mask[i]]`. With the mask (1, 2, 0), lane 0 gets y, lane 1 gets
z, lane 2 gets x: "yzx". With (2, 0, 1) it is "zxy". Then

```
a × b = a.yzx * b.zxy − a.zxy * b.yzx
```

Check lane 0: a.yzx[0] = a₁, b.zxy[0] = b₂, a.zxy[0] = a₂, b.yzx[0] = b₁, so a₁b₂ − a₂b₁. Four
shuffles, two lane-wise multiplies and one subtract, with no lane indexing at all.

`examples/ch11/cross_shuffle.zig`

```zig
//! The cross product with two lane shuffles, its right-hand rule, and the
//! area of a triangle.
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

/// (a.y b.z - a.z b.y, a.z b.x - a.x b.z, a.x b.y - a.y b.x)
fn cross(a: Vec3, b: Vec3) Vec3 {
    const yzx: @Vector(3, i32) = .{ 1, 2, 0 };
    const zxy: @Vector(3, i32) = .{ 2, 0, 1 };
    const a_yzx = @shuffle(f32, a, undefined, yzx);
    const a_zxy = @shuffle(f32, a, undefined, zxy);
    const b_yzx = @shuffle(f32, b, undefined, yzx);
    const b_zxy = @shuffle(f32, b, undefined, zxy);
    return a_yzx * b_zxy - a_zxy * b_yzx;
}

pub fn main() void {
    const x: Vec3 = .{ 1, 0, 0 };
    const y: Vec3 = .{ 0, 1, 0 };
    const z: Vec3 = .{ 0, 0, 1 };
    std.debug.print("shuffle yzx of (1,2,3) = {any}\n", .{@shuffle(f32, Vec3{ 1, 2, 3 }, undefined, @Vector(3, i32){ 1, 2, 0 })});
    std.debug.print("x cross y = {any}\n", .{cross(x, y)});
    std.debug.print("y cross z = {any}\n", .{cross(y, z)});
    std.debug.print("z cross x = {any}\n", .{cross(z, x)});
    std.debug.print("y cross x = {any}\n", .{cross(y, x)});
    std.debug.print("x cross x = {any}\n", .{cross(x, x)});

    const a: Vec3 = .{ 1, 2, 3 };
    const b: Vec3 = .{ -4, 0.5, 2 };
    const c = cross(a, b);
    std.debug.print("a cross b = {any}\n", .{c});
    std.debug.print("dot with a = {d}, dot with b = {d}\n", .{ dot(c, a), dot(c, b) });

    // Triangle area: half the length of the cross product of two edges.
    const p0: Vec3 = .{ 0, 0, 0 };
    const p1: Vec3 = .{ 4, 0, 0 };
    const p2: Vec3 = .{ 1, 3, 0 };
    const n = cross(p1 - p0, p2 - p0);
    std.debug.print("edges cross = {any}, area = {d}\n", .{ n, @sqrt(dot(n, n)) / 2 });
    // The same triangle tilted out of the xy plane: still works in 3D.
    const q2: Vec3 = .{ 1, 3, 4 };
    const m = cross(p1 - p0, q2 - p0);
    std.debug.print("tilted cross = {any}, area = {d}\n", .{ m, @sqrt(dot(m, m)) / 2 });
}
```

```console
$ zig run examples/ch11/cross_shuffle.zig
shuffle yzx of (1,2,3) = { 2, 3, 1 }
x cross y = { 0, 0, 1 }
y cross z = { 1, 0, 0 }
z cross x = { 0, 1, 0 }
y cross x = { 0, 0, -1 }
x cross x = { 0, 0, 0 }
a cross b = { 2.5, -14, 8.5 }
dot with a = 0, dot with b = 0
edges cross = { 0, 0, 12 }, area = 6
tilted cross = { 0, -16, 12 }, area = 10
```

- The axes follow the right-hand rule, `y × x` is `−z`, and a vector crossed with itself is
  zero (θ = 0).
- `a × b` matches the hand calculation and is perpendicular to both inputs.
- The flat triangle (0,0,0), (4,0,0), (1,3,0) has base 4 and height 3, area 6. Its cross product
  points straight along z, out of its plane. Tilting the third corner to (1, 3, 4) keeps the base
  and raises the height to √(3² + 4²) = 5, area 10, and the normal (0, −16, 12) tilts with it.

### The 2D cross product, and Chapter 10's edge function

For two vectors in the xy plane, (a₀, a₁, 0) and (b₀, b₁, 0), lanes 0 and 1 of the cross
product are zero and only lane 2 is left:

```
cross2(a, b) = a₀b₁ − a₁b₀
```

It is a single number: |a| |b| sin θ, with a *sign*. Positive means b is turned from a toward +y;
negative, toward −y. On our y-down map, turning from +x toward +y looks **clockwise**. This
"which way" is what the dot product could not tell us.

You have seen this formula before. Chapter 10's `edge(a, b, p)` filled triangles by testing
which side of each edge a pixel lies on:

```zig
pub fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}
```

That is `cross2(b − a, p − a)`: twice the signed area of the triangle (a, b, p). Now you know
why it works: the sign of the cross product says whether `p` is clockwise from the edge
direction, and its size is the parallelogram area.

One more 2D operation: the perpendicular `perp(v) = (−v₁, v₀)`. Check it: v·perp(v) = −v₀v₁ +
v₁v₀ = 0, so it is perpendicular, and it has the same length. Which of the two perpendiculars is
it? perp((1, 0)) = (0, 1): east turns to south. On the y-down map that is a quarter turn
clockwise, so if you face `v`, `perp(v)` points to your **right**. `delve` uses it for strafing
and for the edges of the view.

## Angles and rotation

A unit vector at angle θ from +x is `fromAngle(θ) = (cos θ, sin θ)`: that is the definition of
cos and sin on the unit circle. A vector of length r at angle α is r(cos α, sin α).

To rotate a vector by θ, add θ to its angle. Start from v = (x, y) = r(cos α, sin α), and use the
angle-sum identities cos(α + θ) = cos α cos θ − sin α sin θ and sin(α + θ) = sin α cos θ +
cos α sin θ:

```
rotated = r(cos(α + θ), sin(α + θ))
        = (r cos α · cos θ − r sin α · sin θ,  r sin α · cos θ + r cos α · sin θ)
        = (x cos θ − y sin θ,  x sin θ + y cos θ)
```

The angle α and the length r have disappeared: the rotation needs only x, y, cos θ and sin θ.
There is a second way to see the same formula, which Chapter 12 builds on. Write v as x steps
along (1, 0) plus y steps along (0, 1). Rotating by θ turns (1, 0) into (cos θ, sin θ), and
turns (0, 1) into its perpendicular, (−sin θ, cos θ). Rotation keeps sums and multiples (turning
a whole picture turns each piece of it), so

```
rotated = x (cos θ, sin θ) + y (−sin θ, cos θ)
```

which is the same formula, lane by lane. Worked example: rotate (1, 1) by 30°. With cos 30° ≈
0.866 and sin 30° = 0.5, the result is (0.866 − 0.5, 0.5 + 0.866) = (0.366, 1.366). Its length is
√(0.134 + 1.866) = √2, the same as before: rotations never change lengths.

In `delve` an angle grows from +x toward +y. The next program rotates (1, 0) in 30° steps and
plots each tip as a letter on a character grid whose rows grow downward, like the screen.

`examples/ch11/rotate2d.zig`

```zig
//! Rotating (1, 0) in 30-degree steps. With y pointing down the screen,
//! a positive angle turns clockwise.
const std = @import("std");

const Vec2 = @Vector(2, f32);

/// `v` rotated by `angle` radians, turning from +x toward +y.
fn rotate(v: Vec2, angle: f32) Vec2 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{ c * v[0] - s * v[1], s * v[0] + c * v[1] };
}

pub fn main() void {
    const step = std.math.degreesToRadians(30.0);
    var v: Vec2 = .{ 1, 0 };
    // Plot the tip of each step as a letter on a y-down character grid.
    var grid: [13][27]u8 = @splat(@splat(' '));
    grid[6][13] = '+';
    for (0..12) |i| {
        const deg = i * 30;
        std.debug.print("{c} {d:>3} deg: ({d:>6.3}, {d:>6.3})\n", .{ 'a' + @as(u8, @intCast(i)), deg, v[0], v[1] });
        // Column = x (two characters per unit so the circle looks round),
        // row = y, growing downward like the screen.
        const col: usize = @intFromFloat(@round(13 + 12 * v[0]));
        const row: usize = @intFromFloat(@round(6 + 6 * v[1]));
        grid[row][col] = 'a' + @as(u8, @intCast(i));
        v = rotate(v, step); // rotate the previous result: errors add up
    }
    for (grid) |row| std.debug.print("|{s}|\n", .{&row});
    std.debug.print("after 12 steps: ({d}, {d})\n", .{ v[0], v[1] });

    // Rotating step by step lets rounding errors pile up. Computing each
    // direction from its angle does not.
    var w: Vec2 = .{ 1, 0 };
    const tiny = std.math.degreesToRadians(0.1);
    for (0..36_000) |_| w = rotate(w, tiny);
    std.debug.print("after 36000 steps of 0.1 deg: ({d}, {d}), length {d}\n", .{ w[0], w[1], @sqrt(w[0] * w[0] + w[1] * w[1]) });
}
```

```console
$ zig run examples/ch11/rotate2d.zig
a   0 deg: ( 1.000,  0.000)
b  30 deg: ( 0.866,  0.500)
c  60 deg: ( 0.500,  0.866)
d  90 deg: ( 0.000,  1.000)
e 120 deg: (-0.500,  0.866)
f 150 deg: (-0.866,  0.500)
g 180 deg: (-1.000,  0.000)
h 210 deg: (-0.866, -0.500)
i 240 deg: (-0.500, -0.866)
j 270 deg: ( 0.000, -1.000)
k 300 deg: ( 0.500, -0.866)
l 330 deg: ( 0.866, -0.500)
|             j             |
|       i           k       |
|                           |
|   h                   l   |
|                           |
|                           |
| g           +           a |
|                           |
|                           |
|   f                   b   |
|                           |
|       e           c       |
|             d             |
after 12 steps: (1, 0)
after 36000 steps of 0.1 deg: (0.998994, -0.0000041447347), length 0.998994
```

- The letters go a, b, c, d *down* the right side: on a y-down grid, a positive angle turns
  clockwise. 90° (`d`) points down the screen, which on the map is south. This is the reason for
  `delve`'s convention: **yaw 0 faces east (+x), and yaw grows toward south (+y), clockwise on
  the top-down map.** `fromAngle(yaw)` is then the facing direction with no sign flips anywhere.
- After 12 steps of 30° the rounding errors happen to cancel and the vector is back at exactly
  (1, 0). After 36 000 steps of 0.1° (ten full turns) they have not: the vector has shrunk by
  0.1% and points a little off. Each rotation is off by a tiny amount, and the next rotation
  starts from the wrong vector.
- That is why the player stores an **angle** (`yaw`) and computes the direction from it with
  `fromAngle` when needed, instead of storing a direction and rotating it every tick. Adding to
  an angle also has rounding error, but it never changes the length of the direction.

Turning left from yaw 0 gives a negative angle. To keep yaw in [0, 2π), wrap it with `@mod`,
whose result has the sign of the divisor: `@mod(-0.25, τ) = τ − 0.25` (τ = 2π, `std.math.tau`).
`@rem` would keep −0.25, because its result has the sign of the dividend.

## Comparing floats

The rotation by 90° in the table printed `( 0.000,  1.000)`, rounded to three digits. Is it
exactly (0, 1)? A test that asks with `expectEqual`:

```zig
// exact_eq.zig: std, Vec2 and rotate as in rotate2d.zig above
test "a quarter turn" {
    var angle: f32 = std.math.pi / 2.0;
    _ = &angle;
    try std.testing.expectEqual(Vec2{ 0, 1 }, rotate(.{ 1, 0 }, angle));
}
```

```console
$ zig test exact_eq.zig
1/1 exact_eq.test.a quarter turn...slices differ. first difference occurs at index 0 (0x0)

============ expected this output: =============  len: 2 (0x2)

[0]: 0
[1]: 1

============= instead found this: ==============  len: 2 (0x2)

[0]: -0.00000004371139
[1]: 1

================================================

FAIL (TestExpectedEqual)
...
0 passed; 0 skipped; 1 failed.
error: the following test command failed with exit code 1:
```

(The stack trace is replaced by `...`.) The result is not wrong; the *input* is. π/2 has
infinitely many digits, and the nearest `f32` is 1.57079637, about 4.37 × 10⁻⁸ more than the true
π/2. Near 90°, cos falls with slope −1, so cos of that number is about −4.37 × 10⁻⁸, exactly the
value printed. Almost every computed float carries an error of this kind. Exact comparison
is right for values that are copied or counted, and wrong for values that are computed.

The fix is to compare with a tolerance. `std.testing.expectApproxEqAbs(expected, actual,
tolerance)` does it for one number. For vectors, `math.zig` has `approxEq`, which checks that
every lane differs by at most 1e-5.

`examples/ch11/approx_eq.zig`

```zig
//! Comparing computed floats: == is almost never what you want.
//! Run with `zig test`.
const std = @import("std");

const Vec2 = @Vector(2, f32);

/// True when every lane of `a` and `b` differs by at most 1e-5.
fn approxEq(a: anytype, b: @TypeOf(a)) bool {
    return @reduce(.And, @abs(a - b) <= @as(@TypeOf(a), @splat(1e-5)));
}

fn rotate(v: Vec2, angle: f32) Vec2 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{ c * v[0] - s * v[1], s * v[0] + c * v[1] };
}

test "0.1 + 0.2 is not 0.3 in f64" {
    // `var` keeps the sum a run-time f64; constants would be computed at
    // compile time with more precision.
    var a: f64 = 0.1;
    var b: f64 = 0.2;
    _ = .{ &a, &b };
    std.debug.print("\n0.1 + 0.2 = {d}\n", .{a + b});
    try std.testing.expect(a + b != 0.3);
    try std.testing.expectApproxEqAbs(0.3, a + b, 1e-12);
}

test "a quarter turn is not exactly (0, 1)" {
    var angle: f32 = std.math.pi / 2.0;
    _ = &angle;
    const v = rotate(.{ 1, 0 }, angle);
    std.debug.print("\nrotate((1, 0), 90 deg) = ({e}, {d})\n", .{ v[0], v[1] });
    try std.testing.expect(v[0] != 0);
    try std.testing.expect(approxEq(v, Vec2{ 0, 1 }));
}

test "approxEq works for any vector length" {
    try std.testing.expect(approxEq(@Vector(3, f32){ 1, 2, 3 }, .{ 1, 2, 3.000001 }));
    try std.testing.expect(!approxEq(@Vector(3, f32){ 1, 2, 3 }, .{ 1, 2, 3.001 }));
}
```

```console
$ zig test examples/ch11/approx_eq.zig
1/3 approx_eq.test.0.1 + 0.2 is not 0.3 in f64...
0.1 + 0.2 = 0.30000000000000004
OK
2/3 approx_eq.test.a quarter turn is not exactly (0, 1)...
rotate((1, 0), 90 deg) = (-4.371139e-8, 1)
OK
3/3 approx_eq.test.approxEq works for any vector length...OK
All 3 tests passed.
```

- 0.1, 0.2 and 0.3 cannot be written exactly in binary, so their rounding errors do not line up.
  This is true of every language that uses IEEE floats, not a Zig quirk.
- `@abs(a - b) <= @splat(1e-5)` is a lane-wise comparison giving a vector of bools, and
  `@reduce(.And, ...)` requires all of them. Since `a` is `anytype`, one function covers 2, 3 and 4
  lanes.
- The tolerance is *absolute*. That suits `delve`: positions are a few dozen cells, directions
  have length 1, and an error of 1e-5 is far below anything visible. For values that span many
  orders of magnitude a *relative* tolerance (`std.math.approxEqRel`) is the better choice.

## Building delve: math.zig

Chapter 10 left `delve` drawing a test card. This chapter replaces it with a maze. The first
new file, `src/math.zig`, collects the vector math above in one place. It starts with the types
and the generic helpers:

`src/math.zig` (beginning)

```zig
//! Vectors for delve. A vector is a `@Vector` of f32, so `+`, `-`, `*` and
//! `/` work lane by lane, and the compiler can use SIMD instructions.
const std = @import("std");

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);

/// `v` with every lane multiplied by `s`.
pub fn scale(v: anytype, s: f32) @TypeOf(v) {
    return v * @as(@TypeOf(v), @splat(s));
}

/// The dot product: |a| |b| cos(angle between a and b).
pub fn dot(a: anytype, b: @TypeOf(a)) f32 {
    return @reduce(.Add, a * b);
}

pub fn length(v: anytype) f32 {
    return @sqrt(dot(v, v));
}

/// `v` scaled to length 1. The zero vector has no direction; it is
/// returned unchanged.
pub fn normalize(v: anytype) @TypeOf(v) {
    const len = length(v);
    if (len == 0) return v;
    return scale(v, 1 / len);
}

/// The point a fraction `t` of the way from `a` to `b`.
pub fn lerp(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    return a + scale(b - a, t);
}
```

The rest of the file holds functions whose bodies you have already seen, each with a doc
comment that says which way it turns (on a y-down map, "positive" is clockwise):

- `cross(a: Vec3, b: Vec3) Vec3`, the four-shuffle version from `cross_shuffle.zig`.
- `cross2(a: Vec2, b: Vec2) f32`, `a[0] * b[1] - a[1] * b[0]`.
- `perp(v: Vec2) Vec2`, `.{ -v[1], v[0] }`: a quarter turn clockwise on the map.
- `fromAngle(angle: f32) Vec2`, `.{ @cos(angle), @sin(angle) }`, and `rotate(v, angle)` from
  `rotate2d.zig`.
- `approxEq(a, b)` from `approx_eq.zig`, for tests.

Three tests check the facts derived above: v = (3, 4, 12) has v·v = 169 and length 13, its
normalized version has length 1, `normalize` of zero is zero, and v·perp(v) = 0; the axes obey
the right-hand rule and `cross(a, b)` is perpendicular to `a` and `b`; a quarter turn of (1, 0)
is (0, 1) within 1e-5, `fromAngle(π)` is (−1, 0), and `lerp((0, 0), (10, −2), 0.25)` is
(2.5, −0.5).

`scale`, `dot`, `length`, `normalize` and `lerp` are generic the way the `mixed_dot` example
showed, so Chapter 12 can call them on 4-lane vectors without changing them.

## A maze in a text file

A maze is a grid of cells, and the easiest way to draw a grid is as text: one character per
cell, one line per row. Before `delve`'s parser, here is the idea on a fixed 5x4 grid that
returns an array, with an error for each way the text can be wrong.

`examples/ch11/parse_grid.zig`

```zig
//! Parsing a small text map into a grid of tiles, with errors for bad input.
const std = @import("std");

const Tile = enum { floor, wall };

const width = 5;
const height = 4;

const ParseError = error{ WrongSize, RaggedRows, UnknownTile };

fn parse(text: []const u8) ParseError![height][width]Tile {
    var grid: [height][width]Tile = undefined;
    var rows = std.mem.tokenizeScalar(u8, text, '\n');
    var y: usize = 0;
    while (rows.next()) |row| : (y += 1) {
        if (y == height) return error.WrongSize;
        if (row.len != width) return error.RaggedRows;
        for (row, &grid[y]) |char, *tile| {
            tile.* = switch (char) {
                '.' => .floor,
                '#' => .wall,
                else => return error.UnknownTile,
            };
        }
    }
    if (y != height) return error.WrongSize;
    return grid;
}

fn report(name: []const u8, text: []const u8) void {
    const grid = parse(text) catch |err| {
        std.debug.print("{s}: error.{t}\n", .{ name, err });
        return;
    };
    var walls: usize = 0;
    for (grid) |row| {
        for (row) |tile| walls += @intFromBool(tile == .wall);
    }
    std.debug.print("{s}: ok, {d} walls, grid[1][2] = .{t}\n", .{ name, walls, grid[1][2] });
}

pub fn main() void {
    report("good",
        \\#####
        \\#.#.#
        \\#...#
        \\#####
    );
    report("ragged", "#####\n#..#\n#...#\n#####");
    report("unknown", "#####\n#.x.#\n#...#\n#####");
    report("short", "#####\n#...#\n#####");
    // tokenizeScalar skips empty lines, so a trailing newline is harmless.
    report("trailing newline", "#####\n#...#\n#...#\n#####\n");
}
```

```console
$ zig run examples/ch11/parse_grid.zig
good: ok, 15 walls, grid[1][2] = .wall
ragged: error.RaggedRows
unknown: error.UnknownTile
short: error.WrongSize
trailing newline: ok, 14 walls, grid[1][2] = .floor
```

- `std.mem.tokenizeScalar(u8, text, '\n')` splits at newlines and *skips empty pieces*, so the
  trailing newline that every text editor adds does not count as an empty last row.
- `for (row, &grid[y]) |char, *tile|` walks the characters of a line and the tiles of a grid row
  together; Zig checks that both have the same length, which `RaggedRows` guaranteed first.
- `{t}` prints the name of an enum value or error.
- `grid[1][2]` is row 1, column 2: the array is indexed `[y][x]`, the way the text is laid out.

`delve`'s map has a size known only after reading the text, so it counts first and allocates
after. Here is the map it ships with, `src/maps/cellar.txt`, 32 cells wide and 24 high: `#` is
brick, `%` is stone, `.` is floor, and `>` is where the player starts, facing east (`v`, `<` and
`^` face south, west and north).

`src/maps/cellar.txt` (the first 8 of 24 rows)

```
################################
#>.....#.......%%%%%%%%%.......#
#......#.......%.......%.......#
#..##..#.......%.......%.......#
#..##..........%.......%.......#
#......#.......%%%%.%%%%.......#
#......#.......#...............#
####.#####.#####...............#
```

`src/map.zig`

```zig
//! The maze: a grid of square cells, each one unit wide. Cell (x, y)
//! covers the square from (x, y) to (x + 1, y + 1); y grows downward on
//! the map, like rows of text.
const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;

pub const Tile = enum {
    floor,
    brick,
    stone,

    pub fn isWall(tile: Tile) bool {
        return tile != .floor;
    }
};

pub const Map = struct {
    width: usize,
    height: usize,
    tiles: []Tile,
    /// Where the player starts: a cell center, and an angle in radians.
    start: Vec2,
    start_yaw: f32,

    pub const ParseError = error{ RaggedRows, UnknownTile, NoStart, TwoStarts, Empty } || std.mem.Allocator.Error;

    /// Parses a map drawn as text, one row per line:
    /// `#` brick wall, `%` stone wall, `.` floor, and one of `>` `v` `<` `^`
    /// for the player start, pointing east, south, west, or north.
    pub fn parse(gpa: std.mem.Allocator, text: []const u8) ParseError!Map {
        var width: usize = 0;
        var height: usize = 0;
        var rows = std.mem.tokenizeScalar(u8, text, '\n');
        while (rows.next()) |row| : (height += 1) {
            if (height == 0) width = row.len;
            if (row.len != width) return error.RaggedRows;
        }
        if (width == 0) return error.Empty;

        const tiles = try gpa.alloc(Tile, width * height);
        errdefer gpa.free(tiles);
        var start: ?Vec2 = null;
        var start_yaw: f32 = 0;

        rows.reset();
        var y: usize = 0;
        while (rows.next()) |row| : (y += 1) {
            for (row, 0..) |char, x| {
                tiles[y * width + x] = switch (char) {
                    '.' => .floor,
                    '#' => .brick,
                    '%' => .stone,
                    '>', 'v', '<', '^' => blk: {
                        if (start != null) return error.TwoStarts;
                        start = .{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5 };
                        // Angles turn from east (+x) toward south (+y).
                        const quarter = std.math.pi / 2.0;
                        start_yaw = switch (char) {
                            '>' => 0,
                            'v' => quarter,
                            '<' => 2 * quarter,
                            else => 3 * quarter,
                        };
                        break :blk .floor;
                    },
                    else => return error.UnknownTile,
                };
            }
        }
        return .{
            .width = width,
            .height = height,
            .tiles = tiles,
            .start = start orelse return error.NoStart,
            .start_yaw = start_yaw,
        };
    }

    pub fn deinit(map: *Map, gpa: std.mem.Allocator) void {
        gpa.free(map.tiles);
        map.* = undefined;
    }

    /// The tile at cell (x, y). Everything outside the map is solid brick,
    /// so nothing can walk or look out of it.
    pub fn at(map: Map, x: i32, y: i32) Tile {
        if (x < 0 or y < 0 or x >= map.width or y >= map.height) return .brick;
        return map.tiles[@as(usize, @intCast(y)) * map.width + @as(usize, @intCast(x))];
    }

    /// True if point `p` is inside a wall cell.
    pub fn isWallAt(map: Map, p: Vec2) bool {
        const cell = @floor(p);
        return map.at(@intFromFloat(cell[0]), @intFromFloat(cell[1])).isWall();
    }
};

// Tests: "parse a small map" checks the size, tiles, the start and
// isWallAt; "parse errors" expects each error from a tiny bad map, such as
// error.TwoStarts from "#>>#".
```

- **Cells are unit squares.** Cell (x, y) covers the square from (x, y) to (x + 1, y + 1), so the
  cell under a point p is `@floor(p)`, lane by lane. Floor, not `@intFromFloat` alone: that
  truncates toward zero, so a point at x = −0.5 would land in cell 0 instead of cell −1, and
  the player could stand half a cell outside the map.
- **The world is closed.** `at` returns `.brick` for every cell outside the map, so neither
  collision nor (in Chapter 13) a ray can leave it, even if the map's border has a gap.
- **Two passes.** The first counts rows and checks that they have the same length; the second
  fills the tiles. `rows.reset()` rewinds the tokenizer, so the text is not split twice by hand.
- **`errdefer gpa.free(tiles)`** frees the tiles if anything after the allocation fails:
  an unknown character, a second start, or no start at all. The `parse errors` test runs with
  `std.testing.allocator`, which fails the test if anything leaks, so it checks this too.
- **`ParseError`** lists the map errors and merges in `Allocator.Error` with `||`, so callers can
  `switch` over every way parsing can fail.
- The start character becomes floor, plus a position at the cell center and a yaw: 0 for east,
  π/2 for south, π for west, 3π/2 for north, following the yaw convention.

The map is built into the program with `@embedFile("maps/cellar.txt")`, which makes the file's
contents a `[]const u8` constant at compile time. There is no file to lose, and no I/O at
startup. A broken map is still possible, though. With an `x` typed into row 5:

```console
$ ./zig-out/bin/delve --headless
error: UnknownTile
src/map.zig:67:29: 0x1269d7a in parse (main.zig)
                    else => return error.UnknownTile,
                            ^
...
$ echo $?
1
```

(The paths are shortened, and the trace through `App.init` and `main` is cut.) The
error return trace shows how the error travelled, but not *where
in the map* the bad character is. Exercise 3 adds that.

## Input

The player is controlled with three axes: forward/backward, strafe left/right, and turn. Each is
a number from −1 to 1, so a script, a gamepad stick or two keys can all produce it. `delve`'s
core never sees a key code; it sees this struct. Create `src/input.zig`:

`src/input.zig`

```zig
//! What the player wants to do during one tick. The platform layer fills
//! it in from the keyboard; the game only ever sees this struct.

pub const Input = struct {
    /// -1 (backward) to 1 (forward).
    forward: f32 = 0,
    /// -1 (left) to 1 (right).
    strafe: f32 = 0,
    /// -1 (turn left) to 1 (turn right).
    turn: f32 = 0,
};

/// Both inputs at once, as if two sets of keys were held.
pub fn combine(a: Input, b: Input) Input {
    return .{
        .forward = @max(-1, @min(1, a.forward + b.forward)),
        .strafe = @max(-1, @min(1, a.strafe + b.strafe)),
        .turn = @max(-1, @min(1, a.turn + b.turn)),
    };
}
```

`combine` adds two inputs and clamps each axis to [−1, 1]: holding W while a script also pushes
forward is still full speed, not double. The keyboard side lives in `src/platform.zig`, the only
file that imports raylib:

```zig
    /// Reads the keyboard: W/S move, A/D strafe, the arrow keys turn.
    pub fn input(_: Window) Input {
        return .{
            .forward = axis(rl.KEY_S, rl.KEY_W),
            .strafe = axis(rl.KEY_A, rl.KEY_D),
            .turn = axis(rl.KEY_LEFT, rl.KEY_RIGHT),
        };
    }
```

`axis(minus, plus)` is 1 while `plus` is held, −1 while `minus` is held, and 0 for neither or
both: `@intFromBool(rl.IsKeyDown(plus)) - @intFromBool(rl.IsKeyDown(minus))`, converted to
`f32`. The right arrow gives turn = +1, which increases yaw: clockwise on the map, a right turn.

## Moving the player

`src/player.zig`

```zig
const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Map = @import("map.zig").Map;
const Input = @import("input.zig").Input;

pub const move_speed = 3.0; // cells per second
pub const turn_speed = 2.5; // radians per second

pub const Player = struct {
    pos: Vec2,
    /// The direction the player faces, in radians from east (+x) toward
    /// south (+y): clockwise on the top-down map.
    yaw: f32,

    /// The unit vector the player faces.
    pub fn dir(player: Player) Vec2 {
        return math.fromAngle(player.yaw);
    }

    pub fn update(player: *Player, input: Input, map: Map, dt: f32) void {
        player.yaw = @mod(player.yaw + input.turn * turn_speed * dt, std.math.tau);

        // Forward and strafe combine into one direction, normalized so
        // that moving diagonally is not faster.
        const forward = player.dir();
        const right = math.perp(forward);
        const wish = math.scale(forward, input.forward) + math.scale(right, input.strafe);
        const step = math.scale(math.normalize(wish), move_speed * dt);

        // Move along x and y separately: when one axis is blocked by a
        // wall, the other still moves, so the player slides along it.
        const try_x = player.pos + Vec2{ step[0], 0 };
        if (!map.isWallAt(try_x)) player.pos = try_x;
        const try_y = player.pos + Vec2{ 0, step[1] };
        if (!map.isWallAt(try_y)) player.pos = try_y;
    }
};

// "moving forward and sliding along a wall": on the map "#####\n#>..#\n#####",
// 60 ticks forward end between x = 3.9 and 4; a step at 45 degrees into the
// wall still moves x.
// "turning wraps around": turn left for 0.1 s from yaw 0, expect tau - 0.25.
```

- **Turn first, then move.** The yaw changes by `turn · 2.5 rad/s · dt` and is wrapped with
  `@mod`. The "turning wraps around" test turns left from 0 and expects τ − 0.25.
- **The wish direction.** `forward = fromAngle(yaw)` and `right = perp(forward)` are two
  perpendicular unit vectors. Forward input scales one, strafe input the other, and the sum is
  where the player wants to go. Holding W and D gives forward + right, whose length is
  √(1² + 1²) ≈ 1.414: without `normalize`, walking diagonally would be 41% faster. After
  `normalize` the step is exactly `move_speed · dt` in any direction, and with no keys held,
  `normalize` returns the zero vector and the step is zero, not NaN.
- **Axis-separated collision.** The step is tried in two parts: x first, then y. Each part is
  kept only if the new position is not inside a wall cell. Walking diagonally into a wall on the
  east blocks the x part, but the y part still moves: the player slides along the wall, the
  same result as the projection in `projection.zig`, for free. The test pushes into a wall at
  45° and checks the player still moved.
- **Known limits.** The player is a point, so it can stand exactly on the edge of a wall, and
  at a corner it can slip through the gap between two diagonal walls. Chapter 22 gives the
  player a radius and fixes both.

A worked check of `update`, which the screenshot below will confirm: hold forward and half a
right turn (`turn = 0.5`) for 40 ticks of 1/60 s from (1.5, 1.5), facing east. The turn rate is
0.5 · 2.5 = 1.25 rad/s, so the final yaw is 1.25 · 40/60 = 0.833 rad = 47.7°. Moving at speed v
while turning at rate ω follows a circle of radius r = v / ω = 3 / 1.25 = 2.4 cells, whose
center is r to the player's right at the start, (1.5, 3.9). On that circle the position after
turning by θ is (1.5 + r sin θ, 1.5 + r(1 − cos θ)) = (3.28, 2.29). The ticks move in short straight
steps instead of along the curve, and end within 0.01 of it, at (3.27, 2.30).

## The top-down view

`src/app.zig` loses the test card and gains a map and a player. Its `init` parses the map, so
it can fail now, and `deinit` frees it:

```zig
const default_map = @embedFile("maps/cellar.txt");

pub const App = struct {
    map: Map,
    player: Player,
    /// Seconds of simulated time.
    time: f32 = 0,
    ticks: u32 = 0,

    pub fn init(gpa: std.mem.Allocator) !App {
        const map = try Map.parse(gpa, default_map);
        return .{ .map = map, .player = .{ .pos = map.start, .yaw = map.start_yaw } };
    }

    pub fn deinit(app: *App, gpa: std.mem.Allocator) void {
        app.map.deinit(gpa);
    }

    pub fn update(app: *App, input: Input, dt: f32) void {
        app.player.update(input, app.map, dt);
        app.time += dt;
        app.ticks += 1;
    }

    // render: below
};
```

`render` clears the canvas, calls `drawMap`, and prints a HUD line at the bottom with
`std.fmt.bufPrint(&buffer, "pos {d:.2},{d:.2}  yaw {d:.0}", ...)`, the yaw converted with
`std.math.radiansToDegrees`.

Drawing needs one conversion: from map units (cells) to canvas pixels. Each cell is 16 pixels,
and the map starts at pixel (64, 8), so a map point p is at `origin + 16·p` on the canvas. The
32x24 map then covers pixels 64 to 576 across and 8 to 392 down, centered in the 640x400 canvas.

```zig
/// Pixels per map cell in the top-down view, and where the map starts.
const cell_px = 16;
const origin: Vec2 = .{ 64, 8 };

fn toScreen(p: Vec2) draw.Point {
    const s = origin + math.scale(p, cell_px);
    return .{ .x = @intFromFloat(@round(s[0])), .y = @intFromFloat(@round(s[1])) };
}
```

```zig
/// The map from above: one square per cell, and the player as a dot with
/// its facing direction and field of view.
fn drawMap(canvas: Canvas, map: Map, player: Player) void {
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const tile = map.at(@intCast(x), @intCast(y));
            const corner = toScreen(.{ @floatFromInt(x), @floatFromInt(y) });
            draw.fillRect(canvas, corner.x, corner.y, cell_px - 1, cell_px - 1, tileColor(tile));
        }
    }

    const dir = player.dir();
    // The edges of the view: the facing direction plus or minus a sideways
    // vector. Chapter 13 explains the 0.8.
    const side = math.scale(math.perp(dir), 0.8);
    const eye = toScreen(player.pos);
    draw.line(canvas, eye, toScreen(player.pos + math.scale(dir + side, 3)), .hex(0x707040));
    draw.line(canvas, eye, toScreen(player.pos + math.scale(dir - side, 3)), .hex(0x707040));
    draw.line(canvas, eye, toScreen(player.pos + dir), .hex(0xffe060));
    draw.fillCircle(canvas, eye, 4, .hex(0xffe060));
}
```

- Cells are drawn 15 pixels wide in 16-pixel steps, so a dark one-pixel grid line shows between
  them. `tileColor` (not shown) maps floor, brick and stone to three colors.
- The bright line is one cell long in the facing direction: `pos + dir`.
- The two dim lines are the edges of the field of view. `dir + 0.8·perp(dir)` is the forward
  direction pushed 0.8 to the right, and `dir − 0.8·perp(dir)` the same to the left. Each makes
  the angle atan(0.8) ≈ 38.7° with `dir`, so the view is about 77° wide. Chapter 13 casts one ray
  per screen column between exactly these two edges. They are scaled by 3 so they are long
  enough to see.
- `toScreen` is a scale followed by a move, written by hand. Chapter 12 replaces it with a
  matrix, and then the same drawing code can also rotate the map.

## Scripted runs: --pos, --yaw, --hold

Screenshots and tests need runs that do the same thing every time, so `src/options.zig` gets
three flags. `--pos X,Y` and `--yaw DEG` override the start; `--hold F,S,T` holds an input for the
whole run. `--pos` is parsed with `parseFloats(2, ...)`, `--hold` with `parseFloats(3, ...)`:

```zig
/// Parses `n` comma-separated numbers, for example "3.5,1.5".
fn parseFloats(comptime n: usize, text: []const u8) Options.Error![n]f32 {
    var result: [n]f32 = undefined;
    var parts = std.mem.splitScalar(u8, text, ',');
    for (&result) |*x| x.* = try parseFloat(parts.next() orelse return error.InvalidValue);
    if (parts.next() != null) return error.InvalidValue;
    return result;
}
```

`parseFloats` returns `[n]f32` with a `comptime n`, so the caller gets an array of the right size
and `opts.pos = ...` coerces it to a `Vec2`. Too few or too many numbers is `InvalidValue`. In
`src/main.zig` the overrides are applied after `init`, and every tick gets the keyboard
combined with the held input (in a headless run there is no keyboard, only `opts.hold`):

```zig
    var app: App = try .init(gpa);
    defer app.deinit(gpa);
    if (opts.pos) |pos| app.player.pos = pos;
    if (opts.yaw) |deg| app.player.yaw = std.math.degreesToRadians(deg);
```

```zig
        const input = combine(window.input(), opts.hold);
```

`main.zig`'s test block also imports `map.zig`, `math.zig` and `player.zig`, so `zig build test`
runs their tests.

## Running it

```console
$ zig build test --summary all
Build Summary: 6/6 steps succeeded; 19/19 tests passed
test success
+- run test 19 pass (19 total) 7ms MaxRSS:7M
   +- compile test debug native success 439ms MaxRSS:181M
      +- WriteFile raylib.h success
      +- compile lib raylib debug native success 2s MaxRSS:455M
      +- compile lib raylib debug native (reused)
      +- translate-c success 17ms MaxRSS:41M
$ zig build --release
$ ./zig-out/bin/delve --headless --frames 40 --hold 1,0,0.5 --out ../../images/ch11-top-down.png
$ ./zig-out/bin/delve --pos 3
delve: InvalidValue
usage: delve [OPTIONS]
...
  --pos X,Y          start at map position X,Y instead of the map's start
  --yaw DEG          start facing DEG degrees (0 east, 90 south)
  --hold F,S,T       hold forward, strafe, and turn input (-1 to 1) all run long
  -h, --help         show this help
$ echo $?
2
```

(The usage lines for the older flags are cut.)

![The cellar map from above after 40 ticks of walking forward while turning right: the player
dot near the top-left corner, its facing line and two field-of-view lines, and the HUD
"POS 3.27,2.30  YAW 48"](images/ch11-top-down.png)

The HUD reads `POS 3.27,2.30  YAW 48` (the bitmap font has only capitals), the numbers the
worked check above predicted. The view lines pass through the bricks: they show where the player
looks, not what they see. Seeing is Chapter 13.

Run `zig build run` for the interactive version: W and S walk, A and D strafe, the arrow keys
turn, Esc quits. Walk into a wall at an angle and the player slides along it.

## Summary

- A point is a place; a direction is a move. q − p is the arrow from p to q, and p + t(q − p)
  is the point a fraction t of the way.
- `@Vector(n, f32)` gives lane-wise operators and SIMD code. Lanes have no names (`v[0]`, not
  `v.x`), and a run-time index needs `inline for` or a copy into an array.
- |v|² = v·v. Normalizing the zero vector divides by zero; return it unchanged instead.
- a·b = Σ aᵢbᵢ = |a||b| cos θ, from the law of cosines. Its sign says in front or behind; with a
  unit n, v·n is the component of v along n, and (p − a)·n the signed distance to a line.
- a × b is perpendicular to a and b, has length |a||b| sin θ (the parallelogram's area), and
  follows the right-hand rule. `cross2` is its z lane: Chapter 10's edge function.
- Rotation by θ maps (x, y) to (x cos θ − y sin θ, x sin θ + y cos θ). On a y-down map positive
  angles turn clockwise. Store the angle, not a repeatedly rotated vector, and wrap it with `@mod`.
- Compare computed floats with a tolerance, never with `==`.
- `delve` now has a parsed text map, a player that moves with normalized input and slides along
  walls, and a top-down view.

## Exercises

1. **Reflect.** Add `reflect(v, n)` to `math.zig`: `v` bounced off a surface with unit normal
   `n`. Test it.

   <details><summary>Solution</summary>

   Split `v` into the part along `n`, `(v·n) n`, and the part across it. A bounce flips the
   first and keeps the second: `across − along = v − 2 (v·n) n`.

   ```zig
   /// `v` bounced off a surface with unit normal `n`: the part of `v` along
   /// `n` is flipped, the part across it is kept.
   pub fn reflect(v: anytype, n: @TypeOf(v)) @TypeOf(v) {
       return v - scale(n, 2 * dot(v, n));
   }
   ```

   ```zig
   test "reflect" {
       try expect(approxEq(reflect(Vec2{ 1, -1 }, Vec2{ 0, 1 }), Vec2{ 1, 1 }));
       try expect(approxEq(reflect(Vec3{ 2, -3, 1 }, Vec3{ 0, 1, 0 }), Vec3{ 2, 3, 1 }));
   }
   ```

   For (1, −1) and the floor normal (0, 1): v·n = −1, so the result is (1, −1) − 2·(−1)·(0, 1) =
   (1, 1). Being generic, the same function works in 3D. With exercises 2 to 4 also done, the
   project reports `23/23 tests passed`.
   </details>

2. **Run key.** Make the player move twice as fast while Left Shift is held.

   <details><summary>Solution</summary>

   Add a field to `Input` and keep `combine` honest about it:

   ```zig
       /// Run at double speed while held.
       run: bool = false,
   ```

   ```zig
           .run = a.run or b.run,
   ```

   In `Window.input`, `.run = rl.IsKeyDown(rl.KEY_LEFT_SHIFT),`. In `Player.update`, choose the
   speed before scaling the step:

   ```zig
           const speed: f32 = if (input.run) 2 * move_speed else move_speed;
           const step = math.scale(math.normalize(wish), speed * dt);
   ```

   A test in `player.zig` updates a walker and a runner for 0.5 s on the map `#>.........#` and
   checks that they moved 1.5 and 3.0 cells.

   Because the speed multiplies a unit vector, running diagonally is exactly as fast as running
   straight.
   </details>

3. **Map errors with positions.** Make an unknown tile report its line and column, so `delve`
   prints `cellar.txt:5:5: unknown tile 'x'`.

   <details><summary>Solution</summary>

   Error values in Zig carry no data, so the details go through an optional out-parameter, the
   way `std.zon` reports parse errors. In `map.zig`:

   ```zig
   /// Where parsing failed: filled in on error.UnknownTile.
   pub const Diagnostic = struct {
       line: usize = 0,
       col: usize = 0,
       char: u8 = 0,
   };
   ```

   Rename `parse` to `parseDiag`, add a parameter `diag: ?*Diagnostic`, and keep `parse` as
   `return parseDiag(gpa, text, null);` so existing callers do not change. The `else` branch
   becomes:

   ```zig
                       else => {
                           if (diag) |d| d.* = .{ .line = y + 1, .col = x + 1, .char = char };
                           return error.UnknownTile;
                       },
   ```

   `App.init` takes the `?*Diagnostic` and passes it on, and `main` prints it:

   ```zig
       var diag: Diagnostic = .{};
       var app: App = App.init(gpa, &diag) catch |err| {
           if (err == error.UnknownTile) {
               std.debug.print("cellar.txt:{d}:{d}: unknown tile '{c}'\n", .{ diag.line, diag.col, diag.char });
           }
           return err;
       };
   ```

   With the `x` in row 5 again:

   ```console
   $ ./zig-out/bin/delve --headless
   cellar.txt:5:5: unknown tile 'x'
   error: UnknownTile
   ```

   (The error return trace that follows is trimmed.) A test can check the message with
   `std.fmt.bufPrint` on a small map such as `"####\n#>x#\n####"`, which gives `map:2:3`.
   </details>

4. **Angle to a target.** Show the signed angle from the player's facing direction to the
   center of the map in the HUD: positive when the center is to the right (clockwise).

   <details><summary>Solution</summary>

   The dot product gives |a||b| cos θ and `cross2` gives |a||b| sin θ with a sign. `atan2(y, x)`
   turns a (cos, sin) pair into an angle in (−π, π], and the common factor |a||b| cancels:

   ```zig
   /// The signed angle from `a` to `b` in radians: positive when `b` is
   /// clockwise from `a` on the y-down map, in (-pi, pi].
   pub fn angleBetween(a: Vec2, b: Vec2) f32 {
       return std.math.atan2(cross2(a, b), dot(a, b));
   }
   ```

   In `App.render`:

   ```zig
           const center: Vec2 = .{ @floatFromInt(app.map.width / 2), @floatFromInt(app.map.height / 2) };
           const to_center = math.angleBetween(p.dir(), center - p.pos);
           const status = std.fmt.bufPrint(&buffer, "pos {d:.2},{d:.2}  yaw {d:.0}  center {d:.0}", .{
               p.pos[0], p.pos[1], std.math.radiansToDegrees(p.yaw), std.math.radiansToDegrees(to_center),
           }) catch unreachable;
   ```

   At the start, (1.5, 1.5) facing east, the HUD reads `CENTER 36`: the arrow to (16, 12) is
   (14.5, 10.5), and atan(10.5 / 14.5) ≈ 35.9°, clockwise. Tests for 90°, −45° and 180°
   (`angleBetween(.{ 1, 0 }, .{ -2, 0 })`, where `cross2` is 0 and the dot product negative)
   pass with a tolerance of 1e-4 degrees.
   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-11--vectors-and-the-maze)
