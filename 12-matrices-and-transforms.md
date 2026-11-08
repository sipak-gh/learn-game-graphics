# Chapter 12 — Matrices and Transforms

A matrix packs a whole transform into sixteen numbers: a move, a rotation, a scale, or any chain
of them. One multiply applies it to a point, and one multiply combines it with another
transform. This chapter derives where those sixteen numbers come from, writes `Mat4` with
homogeneous coordinates, composition, and a Gauss–Jordan inverse, and tests all of it. `delve`
puts them to work right away. The top-down map is now drawn through a matrix, Tab switches to a
view that follows the player and turns with them, and the inverse matrix tells us which cells
can be on screen so the rest are skipped. Input also gains one-shot *actions* (key presses), and
they have to work correctly with the fixed timestep.

Previous: [Chapter 11 — Vectors and the Maze](11-vectors.md). Next:
[Chapter 13 — Ray Casting: The Maze in 2.5D](13-ray-casting.md).

## Transforms as functions

A *transform* is a function from points to points. Chapter 11 already has one. The top-down view
turns a map position into a pixel:

```zig
const cell_px = 16;
const origin: Vec2 = .{ 64, 8 };

fn toScreen(p: Vec2) draw.Point {
    const s = origin + math.scale(p, cell_px);
    return .{ .x = @intFromFloat(@round(s[0])), .y = @intFromFloat(@round(s[1])) };
}
```

That is two steps: *scale* by 16, then *translate* by (64, 8). This chapter adds a view that
follows the player, with the player in the middle of the screen and facing up. Written by hand,
it needs four steps for every point:

1. translate by −pos, so the player is at the origin,
2. rotate so that the facing direction points up the screen,
3. scale by 32 pixels per cell,
4. translate by the screen center.

That is four nested calls per point, with the angle and the sines recomputed each time. Later
chapters chain even more steps (object to world, world to camera, camera to screen). We also need
to run the chain *backward*, from a pixel to a map position, which means writing every step's
undo and calling them in reverse order. Matrices solve both problems: a chain of any length
collapses into one matrix, and undoing it is one function, `inverse`.

## Linear maps are matrices

Start with transforms that keep the origin in place: rotating about the origin, scaling from it,
shearing. They share a property that makes them simple. Call one of them f. Then for all vectors
a and b and every number k:

```
f(a + b) = f(a) + f(b)        f(k a) = k f(a)
```

Turning a whole picture is the same as turning each piece of it and putting the pieces back
together, and the same holds for stretching it. A transform with these two properties is
*linear*. Now take any v = (x, y) and write it in terms of the two *basis vectors* (1, 0) and
(0, 1):

```
f(v) = f(x (1, 0) + y (0, 1)) = x f(1, 0) + y f(0, 1)
```

So **a linear map is completely determined by where it sends the basis vectors.** Write f(1, 0)
and f(0, 1) side by side as the columns of a grid, and the grid *is* the transform:

```
        | a  b |                 | a  b | | x |     | a |     | b |   | a x + b y |
    M = | c  d |      M v   =    | c  d | | y | = x | c | + y | d | = | c x + d y |
```

The first column (a, c) is where (1, 0) goes. The second column (b, d) is where (0, 1) goes. M v
means "x of the first column plus y of the second". The same result read row by row is a dot
product: each output lane is one *row* of M dotted with v. Both views are useful. The column view
explains what the matrix does, and the row view is how you compute one lane by hand.

`examples/ch12/basis_columns.zig`

```zig
//! A 2x2 matrix is "where the basis vectors go". Its columns are the
//! images of (1, 0) and (0, 1); every other point follows from those two.
const std = @import("std");

const Vec2 = @Vector(2, f32);

/// A 2x2 matrix as two columns.
const Mat2 = struct {
    cols: [2]Vec2,

    /// M v = v.x * (first column) + v.y * (second column).
    fn apply(m: Mat2, v: Vec2) Vec2 {
        return m.cols[0] * @as(Vec2, @splat(v[0])) + m.cols[1] * @as(Vec2, @splat(v[1]));
    }
};

fn show(name: []const u8, m: Mat2) void {
    std.debug.print("{s}:\n", .{name});
    // Print row by row: row r holds lane r of every column.
    inline for (0..2) |r| {
        std.debug.print("  | {d:>6.3} {d:>6.3} |\n", .{ m.cols[0][r], m.cols[1][r] });
    }
    const points = [_]Vec2{ .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 3, 2 } };
    for (points) |p| {
        const q = m.apply(p);
        std.debug.print("  ({d}, {d}) -> ({d:.3}, {d:.3})\n", .{ p[0], p[1], q[0], q[1] });
    }
}

pub fn main() void {
    // Send (1, 0) to (2, 0) and (0, 1) to (1, 1): a stretch plus a shear.
    show("stretch and shear", .{ .cols = .{ .{ 2, 0 }, .{ 1, 1 } } });

    // Scaling: each axis is stretched by its own factor.
    show("scale (3, 0.5)", .{ .cols = .{ .{ 3, 0 }, .{ 0, 0.5 } } });

    // Rotation by 30 degrees: (1, 0) goes to (cos, sin), and (0, 1), a
    // quarter turn ahead of it, goes to a quarter turn ahead of that.
    const a = std.math.degreesToRadians(30.0);
    show("rotate 30 deg", .{ .cols = .{ .{ @cos(a), @sin(a) }, .{ -@sin(a), @cos(a) } } });
}
```

```console
$ zig run examples/ch12/basis_columns.zig
stretch and shear:
  |  2.000  1.000 |
  |  0.000  1.000 |
  (1, 0) -> (2.000, 0.000)
  (0, 1) -> (1.000, 1.000)
  (1, 1) -> (3.000, 1.000)
  (3, 2) -> (8.000, 2.000)
scale (3, 0.5):
  |  3.000  0.000 |
  |  0.000  0.500 |
  (1, 0) -> (3.000, 0.000)
  (0, 1) -> (0.000, 0.500)
  (1, 1) -> (3.000, 0.500)
  (3, 2) -> (9.000, 1.000)
rotate 30 deg:
  |  0.866 -0.500 |
  |  0.500  0.866 |
  (1, 0) -> (0.866, 0.500)
  (0, 1) -> (-0.500, 0.866)
  (1, 1) -> (0.366, 1.366)
  (3, 2) -> (1.598, 3.232)
```

- **Stretch and shear.** The columns say that (1, 0) goes to (2, 0) and (0, 1) goes to (1, 1).
  Then (3, 2) goes to 3·(2, 0) + 2·(1, 1) = (8, 2). The unit square becomes a parallelogram
  leaning right. Lines stay lines and parallel lines stay parallel under every linear map,
  because each point on the line a + t d lands on f(a) + t f(d).
- **Scale.** Scaling puts the factors on the diagonal and zeros elsewhere: each axis is stretched
  by its own amount, and neither leaks into the other.
- **Rotation.** Chapter 11 derived rotation by θ as (x cos θ − y sin θ, x sin θ + y cos θ),
  and also noted that (1, 0) goes to (cos θ, sin θ) and (0, 1) to (−sin θ, cos θ). Those are the
  columns:

  ```
         | cos θ  −sin θ |
  R(θ) = | sin θ   cos θ |
  ```

  For 30°, (1, 1) goes to (0.366, 1.366), the same answer Chapter 11 worked out by hand.

Doing one linear map after another is again linear, so it is again a matrix. Apply B first and
then A: A(B v). Because A is linear, A applied to "x of B's first column plus y of its second" is
"x of A(first column of B) plus y of A(second column of B)". So **the product AB is the matrix
whose columns are A applied to the columns of B.** Row by row, element (r, c) of AB is row r of
A dotted with column c of B, which is the rule usually given in textbooks. As a check, multiply
two rotations. The first column of R(α)R(β) is R(α) applied to (cos β, sin β):

```
(cos α cos β − sin α sin β,  sin α cos β + cos α sin β) = (cos(α + β), sin(α + β))
```

These are the angle-sum identities again, so R(α)R(β) = R(α + β): turning by β and then by α is
turning by α + β, as it should be.

## Translation and homogeneous coordinates

Moving everything by t is f(v) = v + t, and that is *not* linear: f(0) = t, but every matrix
sends 0 to 0. No 2x2 matrix can translate, and no 3x3 matrix can translate in 3D.

The standard fix is to add one more coordinate, w. A 3D point becomes (x, y, z, 1) and a
direction becomes (x, y, z, 0). Now use a 4x4 matrix whose last column is (tx, ty, tz, 1):

```
    | 1  0  0  tx | | x |   | x + tx·w |
    | 0  1  0  ty | | y |   | y + ty·w |
    | 0  0  1  tz | | z | = | z + tz·w |
    | 0  0  0  1  | | w |   |    w     |
```

By the column view, the result is x, y, z times the first three columns (which are the identity)
plus *w times the last column*. For a point, w = 1 and the shift is added. For a direction,
w = 0 and the shift is multiplied away. This is what we want, since "three steps east" means the
same thing wherever you stand. These four-number coordinates are called *homogeneous
coordinates*. The matrix is linear in 4D, and in the 3D slice where w = 1 it acts as a
translation.

`examples/ch12/homogeneous.zig`

```zig
//! Homogeneous coordinates: one 4x4 matrix moves points (w = 1) but leaves
//! directions (w = 0) alone.
const std = @import("std");

const Vec4 = @Vector(4, f32);

/// A 4x4 matrix as four columns: M v = sum of the columns weighted by v.
const Mat4 = struct {
    cols: [4]Vec4,

    fn mulVec(m: Mat4, v: Vec4) Vec4 {
        var result: Vec4 = @splat(0);
        inline for (0..4) |i| result += m.cols[i] * @as(Vec4, @splat(v[i]));
        return result;
    }
};

pub fn main() void {
    // Translation by (10, 20, 30): the identity with the shift in the last
    // column. That column gets multiplied by w.
    const t: Mat4 = .{ .cols = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 10, 20, 30, 1 },
    } };

    const point: Vec4 = .{ 1, 2, 3, 1 };
    const direction: Vec4 = .{ 1, 2, 3, 0 };
    std.debug.print("point     {any} -> {any}\n", .{ point, t.mulVec(point) });
    std.debug.print("direction {any} -> {any}\n", .{ direction, t.mulVec(direction) });

    // The difference of two points is a direction: the w's cancel.
    const p: Vec4 = .{ 4, 4, 4, 1 };
    const q: Vec4 = .{ 1, 2, 3, 1 };
    std.debug.print("p - q = {any}\n", .{p - q});
    std.debug.print("T(p) - T(q) = {any} (unchanged by the move)\n", .{t.mulVec(p) - t.mulVec(q)});
    // The sum of two points has w = 2: neither a point nor a direction.
    // Their average (the midpoint) has w = 1 again.
    std.debug.print("p + q = {any}, (p + q) / 2 = {any}\n", .{ p + q, (p + q) / @as(Vec4, @splat(2)) });
}
```

```console
$ zig run examples/ch12/homogeneous.zig
point     { 1, 2, 3, 1 } -> { 11, 22, 33, 1 }
direction { 1, 2, 3, 0 } -> { 1, 2, 3, 0 }
p - q = { 3, 2, 1, 0 }
T(p) - T(q) = { 3, 2, 1, 0 } (unchanged by the move)
p + q = { 5, 6, 7, 2 }, (p + q) / 2 = { 2.5, 3, 3.5, 1 }
```

The w lane tracks Chapter 11's point and direction rules for free. A point minus a point has
w = 1 − 1 = 0: a direction, which translation leaves unchanged, as the fourth line shows. A point
plus a point has w = 2, which is neither. But (p + q) / 2, the midpoint, has w = 1 again.

There is another way to read (5, 6, 7, 2): divide everything by w and you get (2.5, 3, 3.5),
the midpoint. In Chapter 15 that becomes the rule. A homogeneous point (x, y, z, w) with any
nonzero w stands for the 3D point (x/w, y/w, z/w), and a projection matrix puts the depth into w
so that the divide shrinks far things. Until then every point has w = 1 and the divide does
nothing.

`delve` gets two helpers for moving between the two forms:

```zig
/// The homogeneous form of `v`: a point when w = 1, a direction when w = 0.
pub fn vec4(v: Vec3, w: f32) Vec4 {
    return .{ v[0], v[1], v[2], w };
}

/// The first three lanes of `v`.
pub fn xyz(v: Vec4) Vec3 {
    return .{ v[0], v[1], v[2] };
}
```

## Mat4 in Zig

A 4x4 matrix has sixteen numbers, and two separate choices decide how they are used. It helps
to keep them apart, because both are called "row-major" or "column-major" and are easy to mix
up.

1. **The vector convention.** Is a vector a column multiplied on the right (M v), or a row
   multiplied on the left (v M)? The two conventions give matrices that are transposes of each
   other (rows and columns swapped), and products written in the opposite order. `delve` uses
   column vectors, like OpenGL, LearnOpenGL, and most math books. With column vectors the
   translation sits in the last *column*. Books that use row vectors (classic DirectX code, for
   example) put it in the last row.
2. **The storage order.** In memory, do the sixteen numbers go row after row, or column after
   column? This is invisible in the math and matters only to code that reads the raw floats.

`delve` stores the matrix as four column vectors, `cols: [4]Vec4`. The column view of M v is
"the columns weighted by v's lanes", so each column is one `@Vector(4, f32)`, and a
multiplication is four SIMD multiply-adds. The price is that a matrix written as a literal reads
sideways, so `fromRows` lets code write matrices the way they look on paper:

`examples/ch12/mat4_print.zig`

```zig
//! A Mat4 that prints itself the way books write matrices, and the order
//! its sixteen numbers really have in memory.
const std = @import("std");

const Vec4 = @Vector(4, f32);

const Mat4 = struct {
    cols: [4]Vec4,

    /// Rows in, columns stored: element (r, c) goes to cols[c][r].
    fn fromRows(rows: [4][4]f32) Mat4 {
        var m: Mat4 = undefined;
        for (0..4) |c| m.cols[c] = .{ rows[0][c], rows[1][c], rows[2][c], rows[3][c] };
        return m;
    }

    fn at(m: Mat4, r: usize, c: usize) f32 {
        const col: [4]f32 = m.cols[c];
        return col[r];
    }

    /// Used by `{f}`: one line per row.
    pub fn format(m: Mat4, w: *std.Io.Writer) std.Io.Writer.Error!void {
        for (0..4) |r| {
            try w.writeAll("| ");
            for (0..4) |c| try w.print("{d:>4} ", .{m.at(r, c)});
            try w.writeAll("|\n");
        }
    }
};

pub fn main() void {
    // Written as on paper: a translation by (7, 8, 9) in the last column,
    // a scale of 2, 3, 4 on the diagonal.
    const m: Mat4 = .fromRows(.{
        .{ 2, 0, 0, 7 },
        .{ 0, 3, 0, 8 },
        .{ 0, 0, 4, 9 },
        .{ 0, 0, 0, 1 },
    });
    std.debug.print("m =\n{f}", .{m});
    std.debug.print("m.at(0, 3) = {d} (row 0, column 3)\n", .{m.at(0, 3)});

    // In memory the columns come one after another: column-major order.
    const flat: *const [16]f32 = @ptrCast(&m.cols);
    std.debug.print("memory: {any}\n", .{flat.*});
    std.debug.print("@sizeOf(Mat4) = {d} bytes\n", .{@sizeOf(Mat4)});
}
```

```console
$ zig run examples/ch12/mat4_print.zig
m =
|    2    0    0    7 |
|    0    3    0    8 |
|    0    0    4    9 |
|    0    0    0    1 |
m.at(0, 3) = 7 (row 0, column 3)
memory: { 2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 7, 8, 9, 1 }
@sizeOf(Mat4) = 64 bytes
```

The matrix is written and printed in rows, with the translation (7, 8, 9) in the last column. In
memory, the first four floats are the first column (2, 0, 0, 0) and the translation comes last.
That is *column-major* storage, which is also how OpenGL expects a matrix uploaded. `at(r, c)`
copies column `c` into an array before indexing it. As Chapter 11 showed, a vector lane needs an
index known at compile time, while an array element does not. The `format` method is what
`{f}` calls, as in Chapter 2.

Here is `delve`'s `Mat4`, the core of `math.zig`:

```zig
/// A 4x4 matrix stored as four columns. A matrix transforms a column vector
/// on its right: `m.mulVec(v)`. In `a.mul(b)`, `b` is applied first.
pub const Mat4 = struct {
    cols: [4]Vec4,

    pub const identity: Mat4 = .{ .cols = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    } };

    /// Builds a matrix from rows, so code can be written the way matrices
    /// are printed in books.
    pub fn fromRows(rows: [4][4]f32) Mat4 {
        var m: Mat4 = undefined;
        for (0..4) |c| m.cols[c] = .{ rows[0][c], rows[1][c], rows[2][c], rows[3][c] };
        return m;
    }

    /// The element in row `r`, column `c`.
    pub fn at(m: Mat4, r: usize, c: usize) f32 {
        // A vector lane needs a comptime-known index; an array element
        // does not, so coerce the column to an array first.
        const col: [4]f32 = m.cols[c];
        return col[r];
    }

    /// m v: the columns weighted by the components of v.
    pub fn mulVec(m: Mat4, v: Vec4) Vec4 {
        return scale(m.cols[0], v[0]) + scale(m.cols[1], v[1]) +
            scale(m.cols[2], v[2]) + scale(m.cols[3], v[3]);
    }

    /// The product a b: the transform that applies b, then a.
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var m: Mat4 = undefined;
        for (&m.cols, b.cols) |*col, b_col| col.* = a.mulVec(b_col);
        return m;
    }

    /// Transforms a point (w = 1): translation applies.
    pub fn transformPoint(m: Mat4, p: Vec3) Vec3 {
        return xyz(m.mulVec(vec4(p, 1)));
    }

    /// Transforms a direction (w = 0): translation does not apply.
    pub fn transformDir(m: Mat4, d: Vec3) Vec3 {
        return xyz(m.mulVec(vec4(d, 0)));
    }

    pub fn transpose(m: Mat4) Mat4 {
        var t: Mat4 = undefined;
        inline for (0..4) |r| t.cols[r] = .{ m.cols[0][r], m.cols[1][r], m.cols[2][r], m.cols[3][r] };
        return t;
    }

    pub fn translation(t: Vec3) Mat4 {
        var m = identity;
        m.cols[3] = vec4(t, 1);
        return m;
    }

    pub fn scaling(s: Vec3) Mat4 {
        return fromRows(.{
            .{ s[0], 0, 0, 0 },
            .{ 0, s[1], 0, 0 },
            .{ 0, 0, s[2], 0 },
            .{ 0, 0, 0, 1 },
        });
    }
    // rotationX, rotationY, rotationZ, inverse, approxEq: below
};
```

- `identity` has ones on the diagonal: every basis vector goes to itself.
- `mulVec` is the column view written out: `scale` (from Chapter 11) multiplies a whole column
  by one lane of `v`.
- `mul` is the rule from the previous section: column i of `a.mul(b)` is `a` applied to column i
  of `b`.
- `transformPoint` and `transformDir` hide the w lane from callers, who work in `Vec3`. One
  matrix serves both: the w they add decides whether the translation applies.
- `transpose` swaps rows and columns: column r of the result is row r of `m`. The loop is
  `inline for` because `m.cols[0][r]` indexes vector lanes.
- `translation` is the identity with a new last column. `scaling` puts the factors on the
  diagonal.

## Composition and order

`a.mul(b)` is the transform that applies `b` first and then `a`, because (AB) v = A(B v): B is
next to the vector. **Read a product right to left** to get the order its steps happen to a
point. Order matters. Take T = translate by (5, 0) and R = a quarter turn about z, and the point
(1, 0):

`examples/ch12/order_matters.zig`

```zig
//! Matrix products apply right to left, and the order changes the result.
const std = @import("std");

const Vec4 = @Vector(4, f32);

const Mat4 = struct {
    cols: [4]Vec4,

    fn fromRows(rows: [4][4]f32) Mat4 {
        var m: Mat4 = undefined;
        for (0..4) |c| m.cols[c] = .{ rows[0][c], rows[1][c], rows[2][c], rows[3][c] };
        return m;
    }

    fn mulVec(m: Mat4, v: Vec4) Vec4 {
        var result: Vec4 = @splat(0);
        inline for (0..4) |i| result += m.cols[i] * @as(Vec4, @splat(v[i]));
        return result;
    }

    /// a.mul(b): each column of b transformed by a. Applies b first.
    fn mul(a: Mat4, b: Mat4) Mat4 {
        var m: Mat4 = undefined;
        for (&m.cols, b.cols) |*col, b_col| col.* = a.mulVec(b_col);
        return m;
    }

    pub fn format(m: Mat4, w: *std.Io.Writer) std.Io.Writer.Error!void {
        inline for (0..4) |r| {
            try w.writeAll("  |");
            inline for (0..4) |c| try w.print(" {d:>3}", .{m.cols[c][r]});
            try w.writeAll(" |\n");
        }
    }
};

fn translation(x: f32, y: f32) Mat4 {
    return .fromRows(.{ .{ 1, 0, 0, x }, .{ 0, 1, 0, y }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

/// A quarter turn about z: x goes to y, y goes to -x. (cos 90 = 0 and
/// sin 90 = 1 are written exactly, to keep the printout clean.)
const quarter_turn: Mat4 = .fromRows(.{ .{ 0, -1, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });

pub fn main() void {
    const t = translation(5, 0);
    const r = quarter_turn;
    const p: Vec4 = .{ 1, 0, 0, 1 };

    std.debug.print("T R (rotate first, then translate):\n{f}", .{t.mul(r)});
    std.debug.print("T R p = {any}\n", .{t.mul(r).mulVec(p)});
    std.debug.print("step by step: R p = {any}, then T = {any}\n\n", .{ r.mulVec(p), t.mulVec(r.mulVec(p)) });

    std.debug.print("R T (translate first, then rotate):\n{f}", .{r.mul(t)});
    std.debug.print("R T p = {any}\n", .{r.mul(t).mulVec(p)});
    std.debug.print("step by step: T p = {any}, then R = {any}\n", .{ t.mulVec(p), r.mulVec(t.mulVec(p)) });
}
```

```console
$ zig run examples/ch12/order_matters.zig
T R (rotate first, then translate):
  |   0  -1   0   5 |
  |   1   0   0   0 |
  |   0   0   1   0 |
  |   0   0   0   1 |
T R p = { 5, 1, 0, 1 }
step by step: R p = { 0, 1, 0, 1 }, then T = { 5, 1, 0, 1 }

R T (translate first, then rotate):
  |   0  -1   0   0 |
  |   1   0   0   5 |
  |   0   0   1   0 |
  |   0   0   0   1 |
R T p = { 0, 6, 0, 1 }
step by step: T p = { 6, 0, 0, 1 }, then R = { 0, 6, 0, 1 }
```

In TR, the point turns first, (1, 0) → (0, 1), and then moves, → (5, 1). In RT it moves first,
→ (6, 0), and then the turn swings it around the origin, → (0, 6). You can also predict the
printed matrices with the column rule. The last column of TR is T applied to R's last column
(0, 0, 0, 1), which is (5, 0, 0, 1): R doesn't move the origin, so the translation shows through
unchanged. The last column of RT is R applied to (5, 0, 0, 1), which is (0, 5, 0, 1): the shift
itself got rotated. Matrix multiplication is *associative*, so A(BC) = (AB)C and parentheses
never matter. It is not *commutative*: AB and BA differ in general.

One chain is used so often that it gets a name. A rotation matrix turns about the origin. To turn
about some other point c, move c to the origin, rotate, and move back:

```
T(c) R T(−c) p = c + R (p − c)
```

The point c itself maps to c + R·0 = c. Every other point keeps its distance from c, since R
doesn't change lengths. The next program uses this chain to draw five squares about the center
(100, 100), each turned 15° more than the last. It fills them with the edge function from
Chapter 10.

`examples/ch12/rotate_about_point.zig`

```zig
//! Rotating a square about its own center with T(c) R T(-c), drawn into
//! rotate.ppm: five squares, each smaller and turned 15 degrees further.
const std = @import("std");

const Vec4 = @Vector(4, f32);

// Mat4 with fromRows, mulVec, and mul, as in order_matters.zig.

fn translation(x: f32, y: f32) Mat4 {
    return .fromRows(.{ .{ 1, 0, 0, x }, .{ 0, 1, 0, y }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

fn rotationZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .fromRows(.{ .{ c, -s, 0, 0 }, .{ s, c, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

const size = 200;
var pixels: [size][size][3]u8 = @splat(@splat(.{ 24, 24, 32 }));

/// Twice the signed area of (a, b, p): which side of a->b the point p is on.
fn edge(a: Vec4, b: Vec4, p: Vec4) f32 {
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
}

/// Fills a convex quad by testing every pixel center against its edges.
fn fillQuad(q: [4]Vec4, color: [3]u8) void {
    for (0..size) |y| for (0..size) |x| {
        const p: Vec4 = .{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5, 0, 1 };
        var inside = true;
        for (0..4) |i| inside = inside and edge(q[i], q[(i + 1) % 4], p) >= 0;
        if (inside) pixels[y][x] = color;
    };
}

pub fn main(init: std.process.Init) !void {
    const c: Vec4 = .{ 100, 100, 0, 1 };
    for (0..5) |i| {
        const k: f32 = @floatFromInt(i);
        const h = 80 - 15 * k; // half the side
        const angle = std.math.degreesToRadians(15 * k);
        // Read right to left: move c to the origin, rotate, move back.
        const m = translation(c[0], c[1]).mul(rotationZ(angle)).mul(translation(-c[0], -c[1]));
        const corners = [4]Vec4{ .{ 100 - h, 100 - h, 0, 1 }, .{ 100 + h, 100 - h, 0, 1 }, .{ 100 + h, 100 + h, 0, 1 }, .{ 100 - h, 100 + h, 0, 1 } };
        var q: [4]Vec4 = undefined;
        for (&q, corners) |*out, corner| out.* = m.mulVec(corner);
        const shade: u8 = @intCast(70 + 45 * i);
        fillQuad(q, .{ shade, shade / 2, 255 - shade });
        std.debug.print("square {d}: {d:>2} deg, first corner ({d:.1}, {d:.1}), center stays at ({d:.1}, {d:.1})\n", .{
            i, 15 * i, q[0][0], q[0][1], m.mulVec(c)[0], m.mulVec(c)[1],
        });
    }
    // Rotating about the origin instead swings the center away.
    const swung = rotationZ(std.math.degreesToRadians(45)).mulVec(c);
    std.debug.print("R alone moves the center to ({d:.1}, {d:.1})\n", .{ swung[0], swung[1] });

    const file = try std.Io.Dir.cwd().createFile(init.io, "rotate.ppm", .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var w = file.writer(init.io, &buffer);
    try w.interface.print("P6\n{d} {d}\n255\n", .{ size, size });
    try w.interface.writeAll(std.mem.asBytes(&pixels));
    try w.interface.flush();
    std.debug.print("wrote rotate.ppm\n", .{});
}
```

```console
$ zig run examples/ch12/rotate_about_point.zig
square 0:  0 deg, first corner (20.0, 20.0), center stays at (100.0, 100.0)
square 1: 15 deg, first corner (54.0, 20.4), center stays at (100.0, 100.0)
square 2: 30 deg, first corner (81.7, 31.7), center stays at (100.0, 100.0)
square 3: 45 deg, first corner (100.0, 50.5), center stays at (100.0, 100.0)
square 4: 60 deg, first corner (107.3, 72.7), center stays at (100.0, 100.0)
R alone moves the center to (0.0, 141.4)
wrote rotate.ppm
$ ls -l rotate.ppm
-rw-r--r-- 1 tbangma tbangma 120015 Nov  7 21:17 rotate.ppm
```

![Five nested squares on a dark background, each smaller than the last and turned 15 degrees
further clockwise, all centered on the same point](images/ch12-rotate.png)

(`images/ch12-rotate.png` is `rotate.ppm` converted to PNG.) Check square 1 by hand: half-side
h = 65, so its first corner is (35, 35), and p − c = (−65, −65). Rotating by 15° (cos 0.9659,
sin 0.2588) gives (−65·0.9659 + 65·0.2588, −65·0.2588 − 65·0.9659) = (−45.96, −79.61). Adding c
back gives (54.0, 20.4), as printed. Without the two translations, R alone turns (100, 100) by 45°
about the canvas corner, to (100 cos 45° − 100 sin 45°, 100 sin 45° + 100 cos 45°) = (0, 141.4).
The square swings away.

Undoing a chain reverses its order. If M = AB, then M⁻¹ = B⁻¹A⁻¹: to undo "B, then A", first undo
A, then undo B. Think of putting on socks and then shoes, and taking them off in the opposite
order. We use this later to check `delve`'s culling by hand.

## Rotations in 3D

In 3D a rotation turns about an *axis*. Turning about z changes x and y and leaves z alone, so it
is the 2D rotation with an extra row and column of the identity. The other two follow by
renaming the axes in the cyclic order x → y → z → x. About x, the pair (y, z) plays the role of
(x, y). About y, the pair (z, x) does:

```
about z:  x' = x cos θ − y sin θ     y' = x sin θ + y cos θ     z' = z
about x:  y' = y cos θ − z sin θ     z' = y sin θ + z cos θ     x' = x
about y:  z' = z cos θ − x sin θ     x' = z sin θ + x cos θ     y' = y
```

Sorted into rows (x', y', z'), the y rotation puts +sin in row 0 and −sin in row 2. That looks
like the opposite sign from the other two, but it is the same formula with the axes renamed.
Writing the y matrix by symmetry instead of from this cycle is the usual way to get it wrong.

```zig
    /// Rotation by `angle` radians about the x axis: y turns toward z.
    pub fn rotationX(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return fromRows(.{
            .{ 1, 0, 0, 0 },
            .{ 0, c, -s, 0 },
            .{ 0, s, c, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    /// Rotation by `angle` radians about the y axis: z turns toward x.
    pub fn rotationY(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return fromRows(.{
            .{ c, 0, s, 0 },
            .{ 0, 1, 0, 0 },
            .{ -s, 0, c, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    /// Rotation by `angle` radians about the z axis: x turns toward y.
    pub fn rotationZ(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return fromRows(.{
            .{ c, -s, 0, 0 },
            .{ s, c, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        });
    }
```

Which way is positive? With the *right-hand rule* from Chapter 11: point your right thumb along
the positive axis, and your fingers curl the way a positive angle turns. For z, that turns x
toward y. That is also what the cross product says, x × y = z. The project's test checks each
rotation on the basis vector that should move:

```zig
test "transforming points and directions" {
    const m = Mat4.translation(.{ 10, 0, 0 });
    try expect(approxEq(m.transformPoint(.{ 1, 2, 3 }), Vec3{ 11, 2, 3 }));
    try expect(approxEq(m.transformDir(.{ 1, 2, 3 }), Vec3{ 1, 2, 3 }));
    try expect(approxEq(Mat4.rotationZ(std.math.pi / 2.0).transformPoint(.{ 1, 0, 0 }), Vec3{ 0, 1, 0 }));
    try expect(approxEq(Mat4.rotationX(std.math.pi / 2.0).transformPoint(.{ 0, 1, 0 }), Vec3{ 0, 0, 1 }));
    try expect(approxEq(Mat4.rotationY(std.math.pi / 2.0).transformPoint(.{ 0, 0, 1 }), Vec3{ 1, 0, 0 }));
}
```

On the y-down map, x toward y is clockwise, as Chapter 11 found for `rotate`. `rotationZ` is the
same rotation, so it turns the map the same way.

A rotation's columns are the images of the three axes, so they are three unit vectors at right
angles to each other. Columns like these are called *orthonormal*. Now look at RᵀR, using the
row-by-column rule. Row i of Rᵀ is column i of R, so element (i, j) of RᵀR is column i dotted
with column j. That dot product is 1 when i = j (unit length) and 0 otherwise (right angles), so
RᵀR = I. **The inverse of a rotation is its transpose.** Rotating back costs almost nothing to compute.

`examples/ch12/transpose_inverse.zig`

```zig
//! For a rotation, the transpose is the inverse: its columns are unit
//! length and at right angles, so R^T R = I. For a scale it is not.
const std = @import("std");

const Vec4 = @Vector(4, f32);

// Mat4: fromRows, mulVec, mul, transpose, the Gauss-Jordan inverse from delve's math.zig
// (next section), and maxDiff, the largest difference between two elements.

fn rotationX(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .fromRows(.{ .{ 1, 0, 0, 0 }, .{ 0, c, -s, 0 }, .{ 0, s, c, 0 }, .{ 0, 0, 0, 1 } });
}

fn rotationZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .fromRows(.{ .{ c, -s, 0, 0 }, .{ s, c, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

fn dot3(a: Vec4, b: Vec4) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn main() void {
    const r = rotationX(1.1).mul(rotationZ(-0.4));
    std.debug.print("column lengths: {d:.6} {d:.6} {d:.6}\n", .{
        @sqrt(dot3(r.cols[0], r.cols[0])), @sqrt(dot3(r.cols[1], r.cols[1])), @sqrt(dot3(r.cols[2], r.cols[2])),
    });
    std.debug.print("column dots:    {d:.6} {d:.6} {d:.6}\n", .{
        dot3(r.cols[0], r.cols[1]), dot3(r.cols[1], r.cols[2]), dot3(r.cols[0], r.cols[2]),
    });
    const identity = Mat4.fromRows(.{ .{ 1, 0, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
    std.debug.print("rotation: |R^T R - I| = {e}\n", .{r.transpose().mul(r).maxDiff(identity)});
    std.debug.print("rotation: |R^T - inverse(R)| = {e}\n", .{r.transpose().maxDiff(r.inverse().?)});

    const s = Mat4.fromRows(.{ .{ 2, 0, 0, 0 }, .{ 0, 3, 0, 0 }, .{ 0, 0, 4, 0 }, .{ 0, 0, 0, 1 } });
    std.debug.print("scale:    |S^T - inverse(S)| = {d}\n", .{s.transpose().maxDiff(s.inverse().?)});
}
```

```console
$ zig run examples/ch12/transpose_inverse.zig
column lengths: 1.000000 1.000000 1.000000
column dots:    0.000000 -0.000000 0.000000
rotation: |R^T R - I| = 5.9604645e-8
rotation: |R^T - inverse(R)| = 5.9604645e-8
scale:    |S^T - inverse(S)| = 3.75
```

For a rotation built from two turns, the columns are unit length and at right angles, and RᵀR
differs from I by 5.96e-8 = 2⁻²⁴. That is half the gap between 1.0 and the next larger `f32`:
one rounding step. Transpose and inverse agree just as closely. For the scale S(2, 3, 4) the
trick fails: the transpose of a diagonal matrix is the matrix itself, but the inverse is
S(1/2, 1/3, 1/4), so the largest difference is 4 − 0.25 = 3.75. Scaling changes lengths, so its
columns are not unit vectors.

## Inverting a matrix

For a general matrix, such as a chain of moves, turns, and scales, we need a general inverse.
*Gauss–Jordan elimination* computes it with three kinds of *row operation*:

- swap two rows,
- multiply a row by a nonzero number,
- subtract a multiple of one row from another.

Each operation is itself a matrix product: doing it to M gives E M for some simple matrix E. (For
example, the swap of rows 0 and 1 is the identity with its rows 0 and 1 swapped.) Suppose a
sequence of operations turns M into the identity: Eₖ ⋯ E₂E₁ M = I. Then the product Eₖ ⋯ E₁ *is*
M⁻¹. To get that product without forming it, do every operation to the identity at the same time.
Write M and I side by side, as [M | I], and reduce the left half to I. The right half becomes
Eₖ ⋯ E₁ I = M⁻¹.

The recipe works one column at a time. Choose a *pivot* row with a nonzero entry in the column,
swap it into place, divide the row by that entry so it becomes 1, and subtract multiples of it
from every other row to clear the rest of the column. Here it is on a 3x3, printing the
augmented matrix after each column:

`examples/ch12/gauss_jordan.zig`

```zig
//! Gauss-Jordan elimination, step by step: row operations that turn M into
//! the identity turn the identity next to it into M's inverse.
const std = @import("std");

const n = 3;
const Row = [2 * n]f32;

fn printAug(title: []const u8, a: [n]Row) void {
    std.debug.print("{s}\n", .{title});
    for (a) |row| {
        std.debug.print("  [", .{});
        for (row[0..n]) |x| std.debug.print(" {d:>6.3}", .{x});
        std.debug.print(" |", .{});
        for (row[n..]) |x| std.debug.print(" {d:>6.3}", .{x});
        std.debug.print(" ]\n", .{});
    }
}

fn inverse(m: [n][n]f32) ?[n][n]f32 {
    var a: [n]Row = undefined; // [m | identity]
    for (0..n) |r| {
        for (0..n) |c| {
            a[r][c] = m[r][c];
            a[r][c + n] = if (r == c) 1 else 0;
        }
    }
    printAug("start [M | I]:", a);
    for (0..n) |col| {
        // Partial pivoting: use the row with the largest entry in this
        // column, so we never divide by zero or by a tiny number.
        var pivot = col;
        for (col + 1..n) |r| {
            if (@abs(a[r][col]) > @abs(a[pivot][col])) pivot = r;
        }
        if (@abs(a[pivot][col]) < 1e-12) {
            std.debug.print("column {d}: no usable pivot, the matrix is singular\n", .{col});
            return null;
        }
        std.mem.swap(Row, &a[col], &a[pivot]);
        // Scale the pivot row so the pivot becomes 1...
        const inv_pivot = 1 / a[col][col];
        for (&a[col]) |*x| x.* *= inv_pivot;
        // ...then subtract it from every other row to clear the column.
        for (0..n) |r| {
            if (r == col) continue;
            const factor = a[r][col];
            for (&a[r], a[col]) |*x, p| x.* -= factor * p;
        }
        var title: [64]u8 = undefined;
        printAug(std.fmt.bufPrint(&title, "column {d} (pivot from row {d}):", .{ col, pivot }) catch unreachable, a);
    }
    var result: [n][n]f32 = undefined;
    for (&result, a) |*out, row| out.* = row[n..].*;
    return result;
}

pub fn main() void {
    const m: [n][n]f32 = .{ .{ 0, 2, 1 }, .{ 1, 1, 0 }, .{ 2, 0, 1 } };
    const inv = inverse(m).?;

    // Check: M times its inverse should be the identity.
    std.debug.print("M * inverse:\n", .{});
    for (0..n) |r| {
        std.debug.print(" ", .{});
        for (0..n) |c| {
            var sum: f32 = 0;
            for (0..n) |k| sum += m[r][k] * inv[k][c];
            std.debug.print(" {d:>6.3}", .{sum});
        }
        std.debug.print("\n", .{});
    }

    // Row 1 is twice row 0, so this matrix squashes space onto a plane.
    std.debug.print("\n", .{});
    const flat: [n][n]f32 = .{ .{ 1, 2, 3 }, .{ 2, 4, 6 }, .{ 1, 0, 1 } };
    std.debug.print("singular inverse: {any}\n", .{inverse(flat)});
}
```

```console
$ zig run examples/ch12/gauss_jordan.zig
start [M | I]:
  [  0.000  2.000  1.000 |  1.000  0.000  0.000 ]
  [  1.000  1.000  0.000 |  0.000  1.000  0.000 ]
  [  2.000  0.000  1.000 |  0.000  0.000  1.000 ]
column 0 (pivot from row 2):
  [  1.000  0.000  0.500 |  0.000  0.000  0.500 ]
  [  0.000  1.000 -0.500 |  0.000  1.000 -0.500 ]
  [  0.000  2.000  1.000 |  1.000  0.000  0.000 ]
column 1 (pivot from row 2):
  [  1.000  0.000  0.500 |  0.000  0.000  0.500 ]
  [  0.000  1.000  0.500 |  0.500  0.000  0.000 ]
  [  0.000  0.000 -1.000 | -0.500  1.000 -0.500 ]
column 2 (pivot from row 2):
  [  1.000  0.000  0.000 | -0.250  0.500  0.250 ]
  [  0.000  1.000  0.000 |  0.250  0.500 -0.250 ]
  [ -0.000 -0.000  1.000 |  0.500 -1.000  0.500 ]
M * inverse:
   1.000  0.000  0.000
   0.000  1.000  0.000
   0.000  0.000  1.000

start [M | I]:
  [  1.000  2.000  3.000 |  1.000  0.000  0.000 ]
  [  2.000  4.000  6.000 |  0.000  1.000  0.000 ]
  [  1.000  0.000  1.000 |  0.000  0.000  1.000 ]
column 0 (pivot from row 1):
  [  1.000  2.000  3.000 |  0.000  0.500  0.000 ]
  [  0.000  0.000  0.000 |  1.000 -0.500  0.000 ]
  [  0.000 -2.000 -2.000 |  0.000 -0.500  1.000 ]
column 1 (pivot from row 2):
  [  1.000  0.000  1.000 |  0.000  0.000  1.000 ]
  [ -0.000  1.000  1.000 | -0.000  0.250 -0.500 ]
  [  0.000  0.000  0.000 |  1.000 -0.500  0.000 ]
column 2: no usable pivot, the matrix is singular
singular inverse: null
```

Follow the first matrix:

- **Column 0.** Row 0 starts with 0, so we can't divide by it. *Partial pivoting* picks the row
  with the largest entry in the column instead, here row 2 with a 2. Swap it to the top and divide
  it by 2, giving (1, 0, 0.5 | 0, 0, 0.5). Subtract 1× it from the old row 1 to clear that row's
  leading 1. Row 2, the old row 0, already has a 0 in column 0. Choosing the *largest* entry,
  not just any nonzero one, also keeps rounding errors small: dividing by a tiny pivot would blow
  up the errors in every other number in the row.
- **Column 1.** The candidates are rows 1 and 2, with entries 1 and 2. Row 2 wins and is
  swapped up. After the elimination, row 2 holds (0, 0, −1).
- **Column 2.** Dividing row 2 by −1 turns its zeros into `-0.000`. IEEE floats have a signed
  zero: 0 × −1 is −0. It compares equal to 0 and does no harm, but it prints with its sign.

The right half is now the inverse, and M times it gives the identity. Check one entry by hand:
row 0 of M, (0, 2, 1), dotted with column 0 of the inverse, (−0.25, 0.25, 0.5), is
0 + 0.5 + 0.5 = 1.

The second matrix has no inverse. Its row 1 is twice row 0, so after column 0 that row is all
zeros on the left, and column 2 finds no usable pivot. Geometrically, the matrix squashes all of
space onto a plane. Many points land on the same point, so no function can send each one back.
Such a matrix is *singular*.

`Mat4.inverse` in `math.zig` is the same loop on a `[4][8]f32`, without the prints. It reads `m`
with `at(r, c)` and returns `fromRows` of the right half. Its signature is the interesting part:

```zig
    /// The inverse matrix, by Gauss-Jordan elimination: row operations that
    /// turn `m` into the identity turn the identity into the inverse.
    /// Returns null if `m` has no inverse (it squashes space flat).
    pub fn inverse(m: Mat4) ?Mat4 {
```

It returns null when the best pivot is smaller than 1e-12.

The `?` in the return type makes the caller decide what a singular matrix means. Forget to
decide, and the compiler stops you:

```zig
// optional_inverse.zig, the end of main:
    const inv = m.inverse();
    std.debug.print("{d}\n", .{inv.at(0, 0)});
```

```console
$ zig run optional_inverse.zig
optional_inverse.zig:19:35: error: no field or member function named 'at' in '?optional_inverse.Mat4'
    std.debug.print("{d}\n", .{inv.at(0, 0)});
                               ~~~^~~
```

An optional has no methods of its own. Unwrap it first: `.?` when null is a bug, as in a test,
or `orelse` with a fallback. `delve`'s map drawing uses `orelse return 0`. The project's test
inverts a chain of all three kinds of transform and checks both products, `inv·m` and `m·inv`:

```zig
test "inverse undoes a transform" {
    const m = Mat4.translation(.{ 3, -2, 7 }).mul(Mat4.rotationY(0.7)).mul(Mat4.scaling(.{ 2, 3, 0.5 }));
    const inv = m.inverse().?;
    try expect(inv.mul(m).approxEq(Mat4.identity));
    try expect(m.mul(inv).approxEq(Mat4.identity));
    // A rotation's inverse is its transpose.
    const r = Mat4.rotationX(1.1).mul(Mat4.rotationZ(-0.4));
    try expect(r.inverse().?.approxEq(r.transpose()));
    // Scaling by zero flattens space: no inverse.
    try expectEqual(null, Mat4.scaling(.{ 1, 0, 1 }).inverse());
}
```

The cost is a few hundred float operations, so inverting once per frame is nothing. When a
transform is built from known pieces, there is a cheaper option: reverse the chain and invert each
piece, by transposing a rotation, negating a translation, or using 1/s for a scale. The culling
example below does exactly that.

## The map through a matrix

`delve`'s top-down view becomes a single function that returns the map-to-canvas matrix for the
current view:

```zig
    /// The matrix that takes map coordinates to canvas pixels. Read each
    /// product right to left: that is the order the steps apply to a point.
    fn mapTransform(app: App, canvas: Canvas) Mat4 {
        switch (app.map_view) {
            // Scale cells to 16 pixels, then move the map's corner to (64, 8).
            .fixed => return Mat4.translation(.{ 64, 8, 0 }).mul(Mat4.scaling(.{ 16, 16, 1 })),
            // Move the player to the origin, turn so the player faces up
            // (angle -90 degrees), scale up, and move to the screen center.
            .follow => {
                const center: Vec3 = .{ @floatFromInt(canvas.width / 2), @floatFromInt(canvas.height / 2), 0 };
                const p = app.player;
                return Mat4.translation(center)
                    .mul(Mat4.scaling(.{ 32, 32, 1 }))
                    .mul(Mat4.rotationZ(-std.math.pi / 2.0 - p.yaw))
                    .mul(Mat4.translation(.{ -p.pos[0], -p.pos[1], 0 }));
            },
        }
    }
```

The fixed view is Chapter 11's `toScreen` as a product: S(16) first (rightmost), then T(64, 8).
The follow view is the four-step list from the start of the chapter, read right to left:

1. **T(−pos)** moves the player to the origin.
2. **Rz(−π/2 − yaw)** turns the facing direction up. That direction is
   `fromAngle(yaw)` = (cos yaw, sin yaw), at angle yaw. Rotating it by −π/2 − yaw leaves it at
   angle −π/2, which is (0, −1). On a y-down screen, that points up. A rotation cannot mirror, so
   left of the player stays on the left of the screen.
3. **S(32)** zooms to 32 pixels per cell.
4. **T(center)** puts the origin, now the player, in the middle of the 640x400 canvas.

A worked check for the screenshot below, with the player at (19.5, 13.5) and yaw 30°. The point
one cell straight ahead is (19.5 + cos 30°, 13.5 + sin 30°) = (20.366, 14). Step 1 gives
(0.866, 0.5). Step 2 turns it by −120° to (0, −1). Step 3 scales it to (0, −32), and step 4 moves
it to (320, 168), 32 pixels straight above the player's dot at (320, 200).

A rotated grid cell is no longer an axis-aligned rectangle, so `fillRect` can't draw it. A square
is two triangles, though, and Chapter 10's `fillTriangle` draws any triangle. `drawMap` sends a
cell's four corners through the matrix and fills two triangles. The corners are inset by 0.05 of
a cell, so the gaps between cells show as grid lines:

```zig
/// Applies `m` to a point on the map (z = 0) and rounds to a pixel.
fn toScreen(m: Mat4, p: Vec2) draw.Point {
    const s = m.transformPoint(.{ p[0], p[1], 0 });
    return .{ .x = @intFromFloat(@round(s[0])), .y = @intFromFloat(@round(s[1])) };
}

/// The map from above, through the matrix `to_screen`, and the player as a
/// dot with its facing direction and field of view. Returns how many cells
/// it drew.
fn drawMap(canvas: Canvas, map: Map, player: Player, to_screen: Mat4) usize {
    // Only draw cells that can be on screen: run the canvas corners through
    // the inverse matrix to find which part of the map they cover.
    const to_map = to_screen.inverse() orelse return 0;
    const w: f32 = @floatFromInt(canvas.width);
    const h: f32 = @floatFromInt(canvas.height);
    var lo: Vec2 = @splat(std.math.inf(f32));
    var hi: Vec2 = @splat(-std.math.inf(f32));
    for ([_]Vec3{ .{ 0, 0, 0 }, .{ w, 0, 0 }, .{ 0, h, 0 }, .{ w, h, 0 } }) |corner| {
        const m = to_map.transformPoint(corner);
        lo = @min(lo, Vec2{ m[0], m[1] });
        hi = @max(hi, Vec2{ m[0], m[1] });
    }
    const map_size: Vec2 = .{ @floatFromInt(map.width), @floatFromInt(map.height) };
    const first: @Vector(2, usize) = @intFromFloat(@max(@floor(lo), Vec2{ 0, 0 }));
    const last: @Vector(2, usize) = @intFromFloat(@min(@ceil(hi), map_size));

    var drawn: usize = 0;
    for (first[1]..last[1]) |y| {
        for (first[0]..last[0]) |x| {
            // A rotated square is no longer a rectangle: draw it as two
            // triangles, inset a little so the grid shows between cells.
            const corner: Vec2 = .{ @floatFromInt(x), @floatFromInt(y) };
            const a = toScreen(to_screen, corner + Vec2{ 0.05, 0.05 });
            const b = toScreen(to_screen, corner + Vec2{ 0.95, 0.05 });
            const c = toScreen(to_screen, corner + Vec2{ 0.95, 0.95 });
            const d = toScreen(to_screen, corner + Vec2{ 0.05, 0.95 });
            const color = tileColor(map.at(@intCast(x), @intCast(y)));
            draw.fillTriangle(canvas, a, b, c, color);
            draw.fillTriangle(canvas, a, c, d, color);
            drawn += 1;
        }
    }

    const dir = player.dir();
    // The edges of the view: the facing direction plus or minus a sideways
    // vector. Chapter 13 explains the 0.8.
    const side = math.scale(math.perp(dir), 0.8);
    const eye = toScreen(to_screen, player.pos);
    draw.line(canvas, eye, toScreen(to_screen, player.pos + math.scale(dir + side, 3)), .hex(0x707040));
    draw.line(canvas, eye, toScreen(to_screen, player.pos + math.scale(dir - side, 3)), .hex(0x707040));
    draw.line(canvas, eye, toScreen(to_screen, player.pos + dir), .hex(0xffe060));
    draw.fillCircle(canvas, eye, 4, .hex(0xffe060));
    return drawn;
}
```

The view lines use the same matrix as the cells, so they stay attached to the map in both
views. Here is the follow view after pressing Tab, with the player at (19.5, 13.5) facing 30°:

![The cellar map seen from above, rotated so the player, a yellow dot in the middle of the screen,
faces straight up. The grid of cells and the brick walls run diagonally. HUD: "POS 19.50,13.50
YAW 30  CELLS DRAWN 483/768"](images/ch12-follow.png)

The fixed view looks exactly like Chapter 11's picture. The only difference is that every cell is
now two triangles drawn through a matrix:

![The whole cellar map from above, unrotated, with the player near the top-left corner. HUD: "POS
3.27,2.30  YAW 48  CELLS DRAWN 768/768"](images/ch12-fixed.png)

## Drawing only what is on screen

At 32 pixels per cell, the canvas shows only part of the 32x24 map, but a naive loop would still
transform and fill all 768 cells. Most of their triangles would fall off the canvas, and
`fillTriangle` would clip them away one at a time. The inverse matrix answers a better question:
which map positions does the canvas show? Send the four canvas corners from screen space back
into map space, take the bounding box of the results, round outward to whole cells, and clamp to
the map. That is the block at the top of `drawMap`.

The next program does the same calculation for the screenshot above. It builds the inverse by
hand, reversing the chain as in the "socks and shoes" rule, and checks the result with a round
trip:

`examples/ch12/cull_box.zig`

```zig
//! Which map cells can the follow view show? Run the canvas corners back
//! through the inverse transform. The inverse of a product is the product
//! of the inverses in reverse order, so no general inverse is needed here.
const std = @import("std");

const Vec4 = @Vector(4, f32);

// Mat4 with fromRows, mulVec, and mul, as in order_matters.zig.

fn translation(x: f32, y: f32) Mat4 {
    return .fromRows(.{ .{ 1, 0, 0, x }, .{ 0, 1, 0, y }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

fn scaling(s: f32) Mat4 {
    return .fromRows(.{ .{ s, 0, 0, 0 }, .{ 0, s, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

fn rotationZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .fromRows(.{ .{ c, -s, 0, 0 }, .{ s, c, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

pub fn main() void {
    const pos: [2]f32 = .{ 19.5, 13.5 };
    const yaw = std.math.degreesToRadians(30.0);
    const turn = -std.math.pi / 2.0 - yaw;

    // map -> screen: T(center) S(32) R(turn) T(-pos)
    const to_screen = translation(320, 200).mul(scaling(32)).mul(rotationZ(turn)).mul(translation(-pos[0], -pos[1]));
    // screen -> map: T(pos) R(-turn) S(1/32) T(-center)
    const to_map = translation(pos[0], pos[1]).mul(rotationZ(-turn)).mul(scaling(1.0 / 32.0)).mul(translation(-320, -200));

    const check = to_screen.mul(to_map).mulVec(.{ 123, 45, 0, 1 });
    std.debug.print("round trip of (123, 45): ({d:.3}, {d:.3})\n", .{ check[0], check[1] });

    var lo: [2]f32 = .{ std.math.inf(f32), std.math.inf(f32) };
    var hi: [2]f32 = .{ -std.math.inf(f32), -std.math.inf(f32) };
    for ([_][2]f32{ .{ 0, 0 }, .{ 640, 0 }, .{ 0, 400 }, .{ 640, 400 } }) |corner| {
        const m = to_map.mulVec(.{ corner[0], corner[1], 0, 1 });
        std.debug.print("canvas ({d:>3}, {d:>3}) -> map ({d:>5.2}, {d:>5.2})\n", .{ corner[0], corner[1], m[0], m[1] });
        inline for (0..2) |i| {
            lo[i] = @min(lo[i], m[i]);
            hi[i] = @max(hi[i], m[i]);
        }
    }
    // Whole cells, clamped to the 32x24 map.
    const x0 = @max(@floor(lo[0]), 0);
    const y0 = @max(@floor(lo[1]), 0);
    const x1 = @min(@ceil(hi[0]), 32);
    const y1 = @min(@ceil(hi[1]), 24);
    std.debug.print("cells x {d}..{d}, y {d}..{d}: {d} of 768\n", .{ x0, x1, y0, y1, (x1 - x0) * (y1 - y0) });
}
```

```console
$ zig run examples/ch12/cull_box.zig
round trip of (123, 45): (123.000, 45.000)
canvas (  0,   0) -> map (29.91,  7.96)
canvas (640,   0) -> map (19.91, 25.29)
canvas (  0, 400) -> map (19.09,  1.71)
canvas (640, 400) -> map ( 9.09, 19.04)
cells x 9..30, y 1..24: 483 of 768
```

The rotated canvas covers a tilted rectangle on the map, with x from 9.09 to 29.91 and y from 1.71
to 25.29. Rounding outward and clamping y to the map's 24 rows gives cells 9 to 29 by 1 to 23, a
21 × 23 block of 483 cells. That is the number in the screenshot's HUD. The box is
*conservative*: it contains the tilted rectangle plus some corners outside it, so it may draw
a few cells that are not visible. It never skips one that is. This is the first, simplest case
of *visibility culling*: don't draw what can't be seen. Chapter 23 does it for whole rooms.

A note on writing the loop over `lo` and `hi`. The first version was `for (0..2) |i|`, which
indexes a vector with a runtime `i` and fails with Chapter 11's "vector index not comptime known".
`inline for` fixes it here. The project avoids the loop entirely, because `@min`, `@max`,
`@floor`, `@ceil`, and `@intFromFloat` all work on whole vectors.

## Key presses and the fixed timestep

Tab is a different kind of input from W. W is a *state*: while it is down, the player moves every
tick. Tab is an *event*: one press toggles the view once, however long the key stays down.
raylib reports it with `IsKeyPressed`, which is true on the one frame the key went down.

Chapter 5's fixed timestep makes this tricky. A frame can run zero ticks (a fast machine between
ticks), one, or several (catching up after a hitch). Feed every tick the frame's input, and a
press on a frame with two ticks toggles twice (no visible change), while a press on a frame with
no tick is lost. The fix is a small queue. *Accumulate* each frame's presses until a tick
*takes* them, and clear them when taken:

`examples/ch12/press_vs_hold.zig`

```zig
//! Key presses and a fixed timestep. A frame can run zero, one, or several
//! ticks; a press must still act exactly once. Run with `zig test`.
const std = @import("std");

const Action = enum { toggle_map };

const Input = struct {
    forward: f32 = 0,
    pressed: std.EnumSet(Action) = .empty,

    fn accumulate(pending: *Input, fresh: Input) void {
        const presses = pending.pressed.unionWith(fresh.pressed);
        pending.* = fresh;
        pending.pressed = presses;
    }

    fn take(pending: *Input) Input {
        const input = pending.*;
        pending.pressed = .empty;
        return input;
    }
};

/// Ticks per frame for a run where the frame rate stutters: frame 0 runs
/// two ticks, frame 1 none, and so on.
const ticks_per_frame = [_]u32{ 2, 0, 1, 0, 2, 1 };
/// The frames on which the keyboard reports a fresh press of Tab.
const press_on_frame = [_]bool{ true, true, false, false, true, false };

/// Counts how many ticks see the press, feeding each tick the frame's
/// input directly.
fn naive() u32 {
    var acted: u32 = 0;
    for (ticks_per_frame, press_on_frame) |ticks, press| {
        var input: Input = .{};
        if (press) input.pressed.insert(.toggle_map);
        for (0..ticks) |_| acted += @intFromBool(input.pressed.contains(.toggle_map));
    }
    return acted;
}

/// The same run through accumulate and take.
fn queued() u32 {
    var acted: u32 = 0;
    var queue: Input = .{};
    for (ticks_per_frame, press_on_frame) |ticks, press| {
        var input: Input = .{};
        if (press) input.pressed.insert(.toggle_map);
        queue.accumulate(input);
        for (0..ticks) |_| acted += @intFromBool(queue.take().pressed.contains(.toggle_map));
    }
    return acted;
}

test "naive input doubles and drops presses" {
    const n = naive();
    std.debug.print("\n3 presses, naive: acted {d} times\n", .{n});
    // Frames 0 and 4 act twice (two ticks each); frame 1's press is lost
    // (no tick): 2 + 0 + 2.
    try std.testing.expectEqual(4, n);
}

test "accumulate and take act once per press" {
    const n = queued();
    std.debug.print("\n3 presses, accumulate/take: acted {d} times\n", .{n});
    // Frame 1's press waits in the queue until frame 2's tick takes it.
    try std.testing.expectEqual(3, n);
}

test "held state survives take" {
    var queue: Input = .{};
    queue.accumulate(.{ .forward = 1 });
    _ = queue.take();
    try std.testing.expectEqual(1, queue.take().forward);
}
```

```console
$ zig test examples/ch12/press_vs_hold.zig
1/3 press_vs_hold.test.naive input doubles and drops presses...
3 presses, naive: acted 4 times
OK
2/3 press_vs_hold.test.accumulate and take act once per press...
3 presses, accumulate/take: acted 3 times
OK
3/3 press_vs_hold.test.held state survives take...OK
All 3 tests passed.
```

The naive version acts four times for three presses. Frames 0 and 4 each act twice, and frame 1's
press is lost. The queue acts exactly three times. Held state is not a queue: `take` clears only
the presses, so a held W still moves the player on every tick. `delve`'s `input.zig` gets the
same `Action` enum and the same `accumulate` and `take`, word for word, plus the test "a press
acts on exactly one tick". `Input` gains one field, and `combine` unions the presses of its two
inputs:

```zig
    /// Actions whose key went down since the last tick.
    pressed: std.EnumSet(Action) = .empty,
```

`std.EnumSet(Action)` is a set of enum values stored as bits, one per action, so it is cheap to
copy and to union.

`main.zig` keeps a `pending` input in both loops. Here is the windowed one:

```zig
    var pending: Input = .{ .pressed = opts.press };
    while (!window.shouldClose()) : (frame += 1) {
        pending.accumulate(combine(window.input(), opts.hold));
        if (opts.frames) |n| {
            if (frame == n) break;
            // Scripted runs take exactly one tick per frame, so they are
            // reproducible on any machine.
            app.update(pending.take(), tick);
        } else {
            // Real time: run as many ticks as the elapsed time asks for.
            lag += window.frameTime();
            while (lag >= tick) : (lag -= tick) app.update(pending.take(), tick);
        }
```

The headless loop does the same with `pending.accumulate(opts.hold)`. Starting `pending` with
`opts.press` is how scripted runs press keys. The new option `--press toggle_map` turns the
action name into an enum value with `std.meta.stringToEnum`, which returns null for an unknown
name:

```zig
            } else if (eql(arg, "--press")) {
                const name = try value(args, &i);
                opts.press.insert(std.meta.stringToEnum(Action, name) orelse return error.InvalidValue);
```

In `platform.zig`, a table maps keys to actions, so later chapters add a key with one line:

```zig
/// Which key triggers which action.
const bindings = [_]struct { key: c_int, action: Action }{
    .{ .key = rl.KEY_TAB, .action = .toggle_map },
};
```

```zig
        for (bindings) |binding| {
            if (rl.IsKeyPressed(binding.key)) result.pressed.insert(binding.action);
        }
```

## Running it

```console
$ zig build test --summary all
Build Summary: 6/6 steps succeeded; 23/23 tests passed
test success
+- run test 23 pass (23 total) 11ms MaxRSS:7M
   +- compile test debug native success 570ms MaxRSS:181M
      +- WriteFile raylib.h success
      +- compile lib raylib debug native success 3s MaxRSS:458M
      +- compile lib raylib debug native (reused)
      +- translate-c success 17ms MaxRSS:41M
$ zig build --release
$ ./zig-out/bin/delve --headless --frames 40 --hold 1,0,0.5 --out ../../images/ch12-fixed.png
$ ./zig-out/bin/delve --headless --frames 40 --pos 19.5,13.5 --yaw 30 --press toggle_map \
    --out ../../images/ch12-follow.png
$ ./zig-out/bin/delve --press jump
delve: InvalidValue
usage: delve [OPTIONS]
...
  --press ACTION     perform ACTION (for example toggle_map) on the first tick
  -h, --help         show this help
$ echo $?
2
```

(The usage lines for the older flags are cut.) The 23 tests include the 3 new ones in
`math.zig` and the new one in `input.zig`, plus one more check in each `options.zig` test. The
first headless run is Chapter 11's scripted walk, and its HUD still reads `POS 3.27,2.30  YAW 48`.
The second starts the follow view by pressing Tab on the first tick.

Run `zig build run`, walk around, and press Tab. In the follow view the map turns around the
player, and the player always faces up.

## Summary

- A linear map is fixed by where it sends the basis vectors. Those images are its columns, and
  M v is v's lanes weighting the columns. Element (r, c) of AB is row r of A dotted with column
  c of B.
- Rotation by θ has columns (cos θ, sin θ) and (−sin θ, cos θ). Scaling is diagonal. R(α)R(β) =
  R(α + β).
- Translation is not linear. Homogeneous coordinates add w, with points w = 1 and directions
  w = 0, so a 4x4 matrix with (t, 1) as its last column translates points and leaves directions
  alone. Chapter 15 divides by w.
- `delve` uses column vectors and stores `Mat4` as four column `Vec4`s (column-major).
  `fromRows` writes matrices as on paper.
- `a.mul(b)` applies b first. Read products right to left. Order matters: TR ≠ RT. Rotate about
  a point with T(c) R T(−c). (AB)⁻¹ = B⁻¹A⁻¹.
- `rotationX/Y/Z` follow the right-hand rule. A rotation's columns are orthonormal, so its
  inverse is its transpose.
- Gauss–Jordan on [M | I] with partial pivoting gives M⁻¹, or null for a singular matrix.
  `?Mat4` makes callers handle that.
- The map is drawn through a matrix as pairs of triangles. A follow view turns with the player,
  and the inverse matrix limits drawing to the cells that can be on screen.
- Presses are events. Accumulate them across frames and clear them when a tick takes them, so
  each acts exactly once.

## Exercises

1. **Zoom keys.** Make `=` and `-` zoom the follow view in and out.

   <details><summary>Solution</summary>

   Add two actions to `Action` (`zoom_in`, `zoom_out`) and bind them in `platform.zig`:

   ```zig
   const bindings = [_]struct { key: c_int, action: Action }{
       .{ .key = rl.KEY_TAB, .action = .toggle_map },
       .{ .key = rl.KEY_EQUAL, .action = .zoom_in },
       .{ .key = rl.KEY_MINUS, .action = .zoom_out },
   };
   ```

   `App` gets a `zoom: f32 = 32` field, changed by a factor of 1.25 per press and clamped so the
   view stays usable:

   ```zig
   if (input.pressed.contains(.zoom_in)) app.zoom = @min(128, app.zoom * 1.25);
   if (input.pressed.contains(.zoom_out)) app.zoom = @max(8, app.zoom / 1.25);
   ```

   The follow matrix moves into a function that takes the zoom, which exercise 2 reuses. The
   `.follow` case becomes `return followTransform(app.player, center, app.zoom);`:

   ```zig
   /// The player-following view: the player at `center`, facing up.
   fn followTransform(p: Player, center: Vec3, zoom: f32) Mat4 {
       return Mat4.translation(center)
           .mul(Mat4.scaling(.{ zoom, zoom, 1 }))
           .mul(Mat4.rotationZ(-std.math.pi / 2.0 - p.yaw))
           .mul(Mat4.translation(.{ -p.pos[0], -p.pos[1], 0 }));
   }
   ```

   ```zig
   test "zoom keys scale the follow view and stop at the limits" {
       const gpa = std.testing.allocator;
       var app = try App.init(gpa);
       defer app.deinit(gpa);
       var input: Input = .{};
       input.pressed.insert(.zoom_in);
       app.update(input, 1.0 / 60.0);
       try std.testing.expectEqual(40, app.zoom);
       for (0..20) |_| app.update(input, 1.0 / 60.0);
       try std.testing.expectEqual(128, app.zoom);
   }
   ```

   One press goes from 32 to 40. Twenty more would reach 32 · 1.25²¹ ≈ 3500, but the clamp
   holds it at 128. `--press toggle_map --press zoom_in` with the run above shows
   `CELLS DRAWN 323/768`: at 40 pixels per cell, fewer cells fit.
   </details>

2. **Minimap.** In the fixed view, draw a small follow view in the top-right corner: 160x160
   pixels at 8 pixels per cell.

   <details><summary>Solution</summary>

   A follow view centered at (80, 80) at zoom 8 would still fill triangles across the whole
   canvas. Clipping them to the 160x160 square is easiest if the minimap has a canvas of its own:
   a stack array of pixels with a `Canvas` over it. Draw into that, then copy it row by row into
   the corner:

   ```zig
   /// A 160x160 follow view in the top-right corner. It is drawn into its own
   /// small canvas, so its triangles are clipped to that square, then copied.
   fn drawMinimap(canvas: Canvas, map: Map, player: Player) void {
       const size = 160;
       var pixels: [size * size]Color = undefined;
       const mini: Canvas = .{ .width = size, .height = size, .pixels = &pixels };
       mini.clear(.hex(0x000000));
       _ = drawMap(mini, map, player, followTransform(player, .{ size / 2, size / 2, 0 }, 8));
       for (0..size) |y| @memcpy(canvas.row(y + 8)[canvas.width - size - 8 ..][0..size], mini.row(y));
   }
   ```

   Call it in `render` after the main map, `if (app.map_view == .fixed) drawMinimap(canvas,
   app.map, app.player);`. The minimap gets its own culling for free, because `drawMap` runs this
   canvas's corners through the inverse matrix. Chapter 14 adds a general `Canvas.blit` for this
   kind of copy.
   </details>

3. **Determinant.** Add `Mat4.determinant`. Test that a rotation has determinant 1, S(2, 3, 4) has
   24, and a scale with a zero has 0.

   <details><summary>Solution</summary>

   The determinant is the factor by which a matrix scales volumes. It is negative when the matrix
   mirrors, and zero when it squashes space flat, which is exactly when there is no inverse.
   Elimination computes it. Subtracting a multiple of one row from another doesn't change it, a
   swap flips its sign, and for a triangular matrix it is the product of the diagonal. So
   eliminate below each pivot (no scaling needed), multiply the pivots, and flip the sign on
   every swap:

   ```zig
       /// The determinant: how much `m` scales volumes (negative if it
       /// mirrors). Elimination to a triangle; the product of the pivots, with
       /// the sign flipped for every row swap.
       pub fn determinant(m: Mat4) f32 {
           var a: [4][4]f32 = undefined;
           for (0..4) |r| {
               for (0..4) |c| a[r][c] = m.at(r, c);
           }
           var det: f32 = 1;
           for (0..4) |col| {
               var pivot = col;
               for (col + 1..4) |r| {
                   if (@abs(a[r][col]) > @abs(a[pivot][col])) pivot = r;
               }
               if (a[pivot][col] == 0) return 0;
               if (pivot != col) {
                   std.mem.swap([4]f32, &a[col], &a[pivot]);
                   det = -det;
               }
               det *= a[col][col];
               for (col + 1..4) |r| {
                   const factor = a[r][col] / a[col][col];
                   for (&a[r], a[col]) |*x, p| x.* -= factor * p;
               }
           }
           return det;
       }
   ```

   ```zig
   test "determinant" {
       try expectApprox(1, Mat4.rotationX(1.1).mul(Mat4.rotationZ(-0.4)).determinant(), 1e-5);
       try expectApprox(24, Mat4.scaling(.{ 2, 3, 4 }).determinant(), 1e-5);
       try expectApprox(1, Mat4.translation(.{ 5, 6, 7 }).determinant(), 1e-5);
       // Swapping x and y mirrors space.
       const swap_xy = Mat4.fromRows(.{ .{ 0, 1, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
       try expectApprox(-1, swap_xy.determinant(), 1e-5);
       try expectApprox(0, Mat4.scaling(.{ 1, 0, 1 }).determinant(), 1e-5);
   }
   ```

   A rotation keeps volumes and doesn't mirror, so its determinant is 1. Translation has
   determinant 1 too: it moves things without stretching them. With exercise 1 also done, the
   project reports `25/25 tests passed`.
   </details>

4. **Shear.** Draw the fixed map slanted, with x moving a quarter cell right for every cell
   down.

   <details><summary>Solution</summary>

   That is a shear: (0, 1) goes to (0.25, 1), so the second column is (0.25, 1), and row 0
   reads 1, 0.25. It is applied first, before the scale. The map moves left to (16, 8) so the
   slanted right edge still fits on the canvas:

   ```zig
   .fixed => {
       // x moves a quarter cell right for every cell down.
       const shear = Mat4.fromRows(.{
           .{ 1, 0.25, 0, 0 },
           .{ 0, 1, 0, 0 },
           .{ 0, 0, 1, 0 },
           .{ 0, 0, 0, 1 },
       });
       return Mat4.translation(.{ 16, 8, 0 }).mul(Mat4.scaling(.{ 16, 16, 1 })).mul(shear);
   },
   ```

   Every cell becomes a parallelogram and the whole map leans right. The grid lines stay straight
   and parallel, as for every linear map, and `CELLS DRAWN` still reads 768/768, because the
   culling uses the inverse of whatever matrix it is given. The player's dot stays round, because
   `fillCircle` draws it in screen space. The view lines are sheared along with the map.
   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-12--matrices-and-transforms)
