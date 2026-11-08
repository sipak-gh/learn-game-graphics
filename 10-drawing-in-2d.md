# Chapter 10 — Drawing in 2D by Hand

With a canvas to draw on, we write the primitives every renderer is built from: horizontal
spans, rectangles, lines, circles, and filled triangles, plus a tiny bitmap font for a
heads-up display. Each algorithm uses only integers (one `@sqrt` aside), and each is tested on
the exact pixels it covers. The filled triangle introduces *edge functions*, the idea the real
3D rasterizer in Chapter 18 is built on. By the end, `delve` draws an animated test card that
uses every primitive, with a HUD written in our own font.

Previous: [Chapter 9 — Framebuffers: Pixels in Memory](09-framebuffers.md). Next:
[Chapter 11 — Vectors and the Maze](11-vectors.md).

## A canvas you can print

A drawing algorithm is easiest to understand when you can see every pixel it chooses. A
640 x 400 PNG is too big for that, so the examples in this chapter draw into a canvas of
characters and print it: `.` is an empty pixel, `#` a set one.

`examples/ch10/ascii_canvas.zig`

```zig
//! A canvas of characters, so drawing algorithms can show their pixels in
//! the terminal. The other ch10 examples import it:
//! `const Ascii = @import("ascii_canvas.zig").Ascii;`
const std = @import("std");

pub const Ascii = struct {
    pub const width = 32;
    pub const height = 13;

    cells: [height][width]u8 = @splat(@splat('.')),

    /// Sets one cell. Like the project's Canvas.set, it ignores
    /// coordinates outside the canvas.
    pub fn set(canvas: *Ascii, x: i32, y: i32, char: u8) void {
        if (x < 0 or y < 0 or x >= width or y >= height) return;
        canvas.cells[@intCast(y)][@intCast(x)] = char;
    }

    pub fn get(canvas: Ascii, x: i32, y: i32) u8 {
        return canvas.cells[@intCast(y)][@intCast(x)];
    }

    /// Prints the canvas with a row number at the start of each line.
    pub fn print(canvas: Ascii) void {
        for (canvas.cells, 0..) |row, y| std.debug.print("{d:>2} {s}\n", .{ y, &row });
    }

    /// Prints two canvases next to each other, to compare algorithms.
    pub fn printPair(a: Ascii, b: Ascii) void {
        for (a.cells, b.cells, 0..) |left, right, y| {
            std.debug.print("{d:>2} {s}   {s}\n", .{ y, &left, &right });
        }
    }

    pub fn count(canvas: Ascii, char: u8) usize {
        var n: usize = 0;
        for (canvas.cells) |row| n += std.mem.countScalar(u8, &row, char);
        return n;
    }
};

pub fn main() void {
    var canvas: Ascii = .{};
    // A span from x = -3 to 5 on row 1: the part left of x = 0 is clipped.
    var x: i32 = -3;
    while (x <= 5) : (x += 1) canvas.set(x, 1, '#');
    canvas.set(0, 0, 'A'); // top-left corner
    canvas.set(Ascii.width - 1, Ascii.height - 1, 'Z'); // bottom-right corner
    canvas.set(40, 3, '!'); // off the canvas: ignored
    canvas.print();
    std.debug.print("{d} cells set\n", .{canvas.count('#') + canvas.count('A') + canvas.count('Z')});
}
```

```console
$ zig run examples/ch10/ascii_canvas.zig
 0 A...............................
 1 ######..........................
 2 ................................
 3 ................................
 4 ................................
 5 ................................
 6 ................................
 7 ................................
 8 ................................
 9 ................................
10 ................................
11 ................................
12 ...............................Z
8 cells set
```

- `@splat(@splat('.'))` fills a two-dimensional array: the inner `@splat` makes a row of
  `'.'`, the outer one repeats that row. The result type comes from the field's declared type.
- `{s}` prints a byte array when given a pointer to it, `&row`.
- The span from x = -3 to 5 sets six cells, 0 to 5; the three to the left are dropped. The
  `!` at x = 40 is dropped too. 6 + `A` + `Z` = 8.
- The other examples import this file with `@import("ascii_canvas.zig")`, a path relative to
  the importing file. Run them from the repository root with `zig run examples/ch10/NAME.zig`.

## Clipping first

Every primitive in `delve` takes `i32` coordinates, and any of them may be partly or entirely
off the canvas: a line to a point behind the left edge, a circle half off the bottom. Someone
has to cut the shape at the edges. That is *clipping*.

There are two places to do it. Every caller could check its coordinates before drawing, or
each primitive could clip its own output. The second is the only one that stays correct:
there are a handful of primitives and an unbounded number of callers. In `delve`, clipping
happens at the bottom, in two functions everything else is built on: `Canvas.set` from
Chapter 9, for single pixels, and `span`, for runs of pixels in one row.

The new file `src/draw.zig` begins with a point type and `span`:

`project/ch10/src/draw.zig` (lines 1–20)

```zig
//! 2D drawing on a Canvas: lines, rectangles, circles, and triangles.
//! Coordinates are integer pixels; shapes may extend past the edges.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;

pub const Point = struct { x: i32, y: i32 };

/// Fills pixels x0..x1 (inclusive) of row y, clipped to the canvas. Every
/// filled shape is made of these spans, so clipping happens in one place.
pub fn span(canvas: Canvas, x0: i32, x1: i32, y: i32, color: Color) void {
    const w: i32 = @intCast(canvas.width);
    const h: i32 = @intCast(canvas.height);
    if (y < 0 or y >= h) return;
    const left = @max(x0, 0);
    const right = @min(x1, w - 1);
    if (left > right) return;
    const row = canvas.row(@intCast(y));
    @memset(row[@intCast(left)..@intCast(right + 1)], color);
}
```

- `Point` is two `i32`s. Chapter 11 brings real vectors; for pixels, a plain struct is enough.
- A row outside the canvas draws nothing. Otherwise the span is cut to `[0, w - 1]`, and if
  nothing is left (the whole span is off one side), it draws nothing.
- After clipping, `left` and `right` are known to be inside the row, so the `@intCast`s to
  `usize` cannot fail. `@memset` then fills the slice. It is the fastest way to set many
  pixels, and filled shapes in this chapter are all made of spans.
- Both ends are *inclusive*: `span(c, 3, 3, y, color)` sets one pixel. Pixel coordinates name
  pixels, not the gaps between them, so inclusive ranges read naturally.

What if the clamp were missing? Change `const left = @max(x0, 0);` to `const left = x0;` and
render the test card from later in this chapter, which has a rectangle at x = -30:

```console
$ ./zig-out/bin/delve --headless
thread 177628 panic: integer does not fit in destination type
.../src/draw.zig:19:17: 0x1266733 in span (main.zig)
    @memset(row[@intCast(left)..@intCast(right + 1)], color);
                ^
.../src/draw.zig:49:42: 0x1268481 in fillRect (main.zig)
    while (row < y + h) : (row += 1) span(canvas, x, x + w - 1, row, color);
                                         ^
.../src/app.zig:35:22: 0x125b3a4 in render (main.zig)
        draw.fillRect(canvas, -30, 330, 80, 50, .hex(0xc04040));
                     ^
...
```

-30 does not fit in a `usize`. In Debug, the cast stops the program with the whole chain of
callers. In a ReleaseFast build there is no check, and `@memset` would write far outside the
canvas. Clipping is not a nicety in a software renderer: it is what keeps the writes inside
the array.

## Rectangles

With `span`, a filled rectangle is one span per row, and an outline is two spans and two
one-pixel-wide columns:

`project/ch10/src/draw.zig` (lines 47–57)

```zig
pub fn fillRect(canvas: Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
    var row = y;
    while (row < y + h) : (row += 1) span(canvas, x, x + w - 1, row, color);
}

pub fn rect(canvas: Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
    span(canvas, x, x + w - 1, y, color);
    span(canvas, x, x + w - 1, y + h - 1, color);
    fillRect(canvas, x, y + 1, 1, h - 2, color);
    fillRect(canvas, x + w - 1, y + 1, 1, h - 2, color);
}
```

- Rectangles are given as position and size, like raylib's `DrawRectangle`. A `w` x `h`
  rectangle at (x, y) covers columns `x` to `x + w - 1` and rows `y` to `y + h - 1`.
- `fillRect` does no clipping of its own. Rows off the canvas are dropped by `span`, columns
  off the canvas are cut by `span`. The loop still runs once per row, even for rows that are
  dropped; for the sizes in this book that costs nothing worth measuring.
- `rect` draws the top and bottom rows, then the two side columns *between* them (`y + 1`,
  `h - 2` rows), so no corner pixel is drawn twice. With a solid color that would not show,
  but it would with a translucent one.

The test for clipping fills a 20 x 20 rectangle at (-5, 8) on a 10 x 10 canvas. Only rows 8
and 9 and columns 0 to 9 are on the canvas:

`project/ch10/src/draw.zig` (lines 122–126 and 143–149)

```zig
fn countLit(canvas: Canvas) usize {
    var n: usize = 0;
    for (canvas.pixels) |p| n += @intFromBool(p.r != 0);
    return n;
}

test "fillRect is clipped to the canvas" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 10, 10);
    defer canvas.deinit(gpa);
    fillRect(canvas, -5, 8, 20, 20, Color.white);
    try std.testing.expectEqual(20, countLit(canvas)); // rows 8 and 9
}
```

`countLit` counts pixels with any red in them, which for a black canvas drawn in white is
every pixel that was drawn. `@intFromBool` turns `true` into 1, which makes counting a sum.

## Lines: Bresenham

A line from (x0, y0) to (x1, y1) is a set of pixels, and the question is which ones. For a
line that is wider than tall, the answer everyone agrees on is: one pixel in every column, the
one nearest to the ideal line in that column. For a line taller than wide, one pixel in every
row. The longer axis, where every step moves exactly one pixel, is the *major axis*.

### The obvious way: DDA

The direct approach is the *digital differential analyzer*, or DDA. Step one pixel at a time
along the major axis, add the slope to the other coordinate as a float, and round:

`examples/ch10/dda_line.zig`

```zig
//! The DDA line: step along the longer axis one pixel at a time and add a
//! fractional increment to the other coordinate, rounding to plot.
const std = @import("std");
const Ascii = @import("ascii_canvas.zig").Ascii;

pub fn ddaLine(canvas: *Ascii, x0: i32, y0: i32, x1: i32, y1: i32, char: u8) void {
    const dx: f32 = @floatFromInt(x1 - x0);
    const dy: f32 = @floatFromInt(y1 - y0);
    const steps = @max(@abs(dx), @abs(dy)); // pixels along the longer axis
    if (steps == 0) return canvas.set(x0, y0, char);
    const x_step = dx / steps; // one of the two steps is exactly +1 or -1
    const y_step = dy / steps;
    var x: f32 = @floatFromInt(x0);
    var y: f32 = @floatFromInt(y0);
    for (0..@as(usize, @intFromFloat(steps)) + 1) |_| {
        canvas.set(@intFromFloat(@round(x)), @intFromFloat(@round(y)), char);
        x += x_step;
        y += y_step;
    }
}

pub fn main() void {
    var canvas: Ascii = .{};
    ddaLine(&canvas, 1, 1, 30, 11, '#'); // shallow: x steps by 1, y by 10/29
    ddaLine(&canvas, 3, 12, 8, 0, '*'); // steep and upward: y steps by -1
    canvas.print();
    std.debug.print("shallow line: {d} pixels, steep line: {d} pixels\n", .{ canvas.count('#'), canvas.count('*') });
}
```

```console
$ zig run examples/ch10/dda_line.zig
 0 ........*.......................
 1 .##.....*.......................
 2 ...###.*........................
 3 ......#*#.......................
 4 ......*..###....................
 5 ......*.....###.................
 6 .....*.........##...............
 7 .....*...........###............
 8 .....*..............###.........
 9 ....*..................###......
10 ....*.....................###...
11 ...*.........................##.
12 ...*............................
```

```console
shallow line: 29 pixels, steep line: 13 pixels
```

(The last line of output is shown on its own to keep the picture readable.) The shallow line
spans 30 columns and has 30 pixels, but one of them was overwritten by the steep line where
they cross at (7, 3), so 29 `#` remain. The steep line spans 13 rows and has 13 pixels, one
per row.

DDA is correct and easy to read. It was not what people used for decades, for two reasons. On
the machines where line drawing was invented, floating point was slow or missing. And floats
accumulate error: after many additions of `y_step`, `y` is not exactly where it should be, and
the rounding can tip the wrong way. An integer method has neither problem.

### Deriving Bresenham's algorithm

Take the shallow case first: x1 > x0 and 0 ≤ dy ≤ dx, where `dx = x1 - x0` and
`dy = y1 - y0` (y down, so the line goes right and down). Every step moves x by one. The only
question is whether y moves too.

Write the line as a function that is zero on it:

```text
f(x, y) = dy·(x − x0) − dx·(y − y0)
```

f is 0 at both endpoints and on every point between them. It grows with x and shrinks with y,
so at a point *above* the line on screen (smaller y) it is positive, and *below* it is
negative.

Suppose the last pixel plotted was (x, y). The next one is either (x + 1, y) or
(x + 1, y + 1). Look at the point halfway between them, the *midpoint* (x + 1, y + ½). If
f there is positive, the midpoint is above the line, so the line passes closer to the lower
pixel: step y. Otherwise keep y.

Evaluating f from scratch every column would need multiplications. But f changes by fixed
amounts:

- Moving one column right adds `dy` to f.
- Moving one row down subtracts `dx`.

So keep a running value `d = 2·f(midpoint)`. The factor 2 removes the ½: the first midpoint
is (x0 + 1, y0 + ½), and `2·f = 2·dy − dx`, an integer. After that, every column adds `2·dy`,
and every step down subtracts `2·dx`. No multiplication, no division, no float: an add and a
compare per pixel. That is Bresenham's algorithm, published by Jack Bresenham at IBM in 1965
for a pen plotter.

The other seven octants are the same idea with x and y swapped or negated. Rather than eight
copies, the usual form tracks the error for both axes at once:

```zig
    const dx: i32 = @intCast(@abs(b.x - a.x));
    const dy: i32 = -@as(i32, @intCast(@abs(b.y - a.y)));
    var err = dx + dy;
    // each step:
    const e2 = 2 * err;
    if (e2 >= dy) { err += dy; x += sx; } // step in x
    if (e2 <= dx) { err += dx; y += sy; } // step in y
```

Here `dy` is *negative* (minus the height), `sx` and `sy` are the step directions, ±1, and
`err` is the error of the diagonal step, scaled the same way as `d`. Comparing `2·err` with
`dy` asks "is stepping in x still closer to the line than not?", and comparing it with `dx`
asks the same for y. For a shallow line the first test always passes and the second passes
now and then; for a steep line it is the other way round; for a 45° line both pass every time.
This compact form is the one Alois Zingl derives in "A Rasterizing Algorithm for Drawing
Curves" (see the sources).

`examples/ch10/bresenham.zig` has both versions and compares them with DDA:

`examples/ch10/bresenham.zig` (excerpt: the first-octant version)

```zig
/// Only for 0 <= dy <= dx (x steps right, y steps down or not at all).
/// `d` is 2 * (how far the line is above the midpoint, times dx).
fn lineFirstOctant(canvas: *Ascii, x0: i32, y0: i32, x1: i32, y1: i32, char: u8) void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    var d = 2 * dy - dx;
    var y = y0;
    var x = x0;
    while (x <= x1) : (x += 1) {
        canvas.set(x, y, char);
        if (d > 0) {
            y += 1;
            d -= 2 * dx;
        }
        d += 2 * dy;
    }
}
```

Its `line` function is the all-octant form, exactly as in `draw.zig` below, and `main` draws
the same line three ways, then compares all 416 lines from (0, 0) to every cell of the
canvas, drawn with DDA, with Bresenham, and with Bresenham backwards:

```console
$ zig run examples/ch10/bresenham.zig
one octant vs all octants, (1,1) to (30,11):
 0 ................................   ................................
 1 .##.............................   .##.............................
 2 ...###..........................   ...###..........................
 3 ......###.......................   ......###.......................
 4 .........###....................   .........###....................
 5 ............###.................   ............###.................
 6 ...............##...............   ...............##...............
 7 .................###............   .................###............
 8 ....................###.........   ....................###.........
 9 .......................###......   .......................###......
10 ..........................###...   ..........................###...
11 .............................##.   .............................##.
12 ................................   ................................
same pixels: true, same as DDA: true
416 lines: DDA differs from Bresenham in 21, Bresenham a->b differs from b->a in 127
first difference, (0,0) to (2,12): Bresenham, then DDA
 0 #...............................   #...............................
 1 #...............................   #...............................
 2 #...............................   #...............................
 3 .#..............................   .#..............................
 4 .#..............................   .#..............................
 5 .#..............................   .#..............................
 6 .#..............................   .#..............................
 7 .#..............................   .#..............................
 8 .#..............................   .#..............................
 9 ..#.............................   .#..............................
10 ..#.............................   ..#.............................
11 ..#.............................   ..#.............................
12 ..#.............................   ..#.............................
```

The two Bresenham versions agree, and for this line they agree with DDA. The two counts are
more interesting. Look at the first difference, in row 9. The ideal line from (0, 0) to
(2, 12) passes row 9 at x = 9 · 2 / 12 = 1.5, *exactly* halfway between pixels 1 and 2. Both
pixels are equally close, so both answers are right. Bresenham's `e2 >= dy` takes the step on
a tie. DDA has added 1/6 nine times in `f32`, got slightly less than 1.5, and rounded down.

A small extra program checked every one of the 21 DDA differences and the 127 backwards
differences: in all of them, the differing pixels sit at exact ties like this one. So on this
canvas, neither DDA's floats nor the direction ever chose a *wrong* pixel, only the other of
two equally right ones. That still matters in two ways:

- **Direction.** Drawing a→b and b→a can light different pixels when a line has ties. For a
  single line nobody can tell. For a wireframe, where two triangles share an edge and each
  draws it in its own direction, the shared edge can come out with a doubled pixel here and
  there. The usual cure is to always draw from the same end, for example the one with the
  smaller y, by swapping the endpoints first.
- **Drift.** DDA's error grows with the length of the line and with the number of additions.
  On a 32-pixel canvas it only broke ties; integer Bresenham is exact at any length.

### draw.line

`project/ch10/src/draw.zig` (lines 22–45)

```zig
/// Bresenham's line algorithm: integer-only, every octant, both endpoints
/// drawn. `err` tracks how far the ideal line is from the current pixel.
pub fn line(canvas: Canvas, a: Point, b: Point, color: Color) void {
    const dx: i32 = @intCast(@abs(b.x - a.x));
    const dy: i32 = -@as(i32, @intCast(@abs(b.y - a.y)));
    const sx: i32 = if (a.x < b.x) 1 else -1;
    const sy: i32 = if (a.y < b.y) 1 else -1;
    var err = dx + dy;
    var x = a.x;
    var y = a.y;
    while (true) {
        canvas.set(x, y, color);
        if (x == b.x and y == b.y) break;
        const e2 = 2 * err;
        if (e2 >= dy) { // step in x
            err += dy;
            x += sx;
        }
        if (e2 <= dx) { // step in y
            err += dx;
            y += sy;
        }
    }
}
```

- `@abs` of an `i32` returns a `u32`, because the absolute value of the smallest `i32` does
  not fit an `i32`. `@intCast` brings it back; for pixel coordinates it always fits.
- The loop stops *after* plotting `b`, so both endpoints are drawn. A line from a point to
  itself plots one pixel.
- Pixels go through `canvas.set`, so a line may start or end anywhere, even far off the
  canvas. That is simple and correct, but not efficient: a line from (-10000, 0) to (5, 5)
  walks 10,000 invisible pixels. A real clipper would cut the line to the canvas first
  (Cohen–Sutherland is the classic). `delve`'s lines are short, so this one does not.

The test checks the endpoints and the pixel count, both ways round:

`project/ch10/src/draw.zig` (lines 128–141)

```zig
test "a line includes both endpoints and is the same in both directions" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 10, 10);
    defer canvas.deinit(gpa);
    line(canvas, .{ .x = 1, .y = 2 }, .{ .x = 8, .y = 5 }, Color.white);
    try std.testing.expectEqual(8, countLit(canvas)); // one pixel per column
    try std.testing.expectEqual(Color.white, canvas.get(1, 2));
    try std.testing.expectEqual(Color.white, canvas.get(8, 5));

    var back = try Canvas.init(gpa, 10, 10);
    defer back.deinit(gpa);
    line(back, .{ .x = 8, .y = 5 }, .{ .x = 1, .y = 2 }, Color.white);
    try std.testing.expectEqual(8, countLit(back));
}
```

Read the name with the example's numbers in mind. The test compares *counts*, not pixels, so
it would pass even if a tie broke differently. For this particular line the pixels are in fact
identical: with dx = 7 and dy = 3, the ideal line is never exactly halfway between two pixels
(that would need 2 · 3 · k to equal 7 plus a multiple of 14, and an even number never does).
A stricter test would compare the two canvases pixel by pixel, and would have to pick a line
without ties to pass.

## Circles: the midpoint algorithm

A circle of radius r around the origin is every point where

```text
f(x, y) = x² + y² − r²
```

is zero. f is negative inside the circle and positive outside. The midpoint idea from lines
carries over unchanged: step one pixel along the major axis, evaluate f halfway between the two
candidates for the other axis, and let the sign decide.

**Eight-way symmetry.** A circle looks the same mirrored in the x axis, the y axis, and the
two diagonals. If (x, y) is on the circle, so are (y, x), (−y, x), (−x, y), (−x, −y),
(−y, −x), (y, −x) and (x, −y). So the algorithm only walks one eighth of the circle, the
*octant* from (r, 0) to the diagonal where x = y, and plots each point eight times. In that
octant the circle is steep: y is the major axis, rising by one each step, and x either stays
or moves one pixel inward.

**The decision.** From the pixel (x, y), the next one is (x, y + 1) or (x − 1, y + 1). The
midpoint between them is (x − ½, y + 1). If f is negative there, the midpoint is inside the
circle, so the circle passes outside it, closer to (x, y + 1): keep x. Otherwise step x
inward.

**Keeping it integer.** Again f changes by simple amounts between neighbouring midpoints:

- At the start, f(r − ½, 1) = r² − r + ¼ + 1 − r² = 5/4 − r. Only the sign matters and
  every later change is an integer, so start from 1 − r.
- If x stays, the next midpoint is (x − ½, y + 2): f grows by (y + 2)² − (y + 1)² = 2y + 3.
- If x steps, it is (x − 3/2, y + 2): f grows by 2y + 3, plus (x − 3/2)² − (x − ½)² = −2x + 2.
  That is 2(y − x) + 5 in total.

`examples/ch10/midpoint_circle.zig`

```zig
//! The midpoint circle algorithm: walk one eighth of the circle with an
//! integer decision variable and mirror each point into all eight octants.
const std = @import("std");
const Ascii = @import("ascii_canvas.zig").Ascii;

fn circle(canvas: *Ascii, cx: i32, cy: i32, radius: i32, char: u8) void {
    var x = radius;
    var y: i32 = 0;
    var err = 1 - radius; // f at the first midpoint, (r - 1/2, 1), times 1, rounded
    while (x >= y) : (y += 1) {
        std.debug.print("x={d} y={d} err={d}\n", .{ x, y, err });
        const points = [8][2]i32{
            .{ x, y }, .{ y, x }, .{ -y, x }, .{ -x, y }, .{ -x, -y }, .{ -y, -x }, .{ y, -x }, .{ x, -y },
        };
        for (points) |d| canvas.set(cx + d[0], cy + d[1], char);
        if (err < 0) {
            err += 2 * y + 3; // the midpoint was inside: keep x
        } else {
            err += 2 * (y - x) + 5; // outside: step x inward too
            x -= 1;
        }
    }
}

pub fn main() void {
    var canvas: Ascii = .{};
    circle(&canvas, 15, 6, 6, '#');
    canvas.set(15, 6, '+'); // the center
    canvas.print();
    std.debug.print("{d} pixels\n", .{canvas.count('#')});
}
```

```console
$ zig run examples/ch10/midpoint_circle.zig
x=6 y=0 err=-5
x=6 y=1 err=-2
x=6 y=2 err=3
x=5 y=3 err=0
x=4 y=4 err=1
 0 .............#####..............
 1 ............#.....#.............
 2 ...........#.......#............
 3 ..........#.........#...........
 4 .........#...........#..........
 5 .........#...........#..........
 6 .........#.....+.....#..........
 7 .........#...........#..........
 8 .........#...........#..........
 9 ..........#.........#...........
10 ...........#.......#............
11 ............#.....#.............
12 .............#####..............
32 pixels
```

- Follow the trace. Start at (6, 0) with err = 1 − 6 = −5: inside, keep x, add 2·0 + 3 → −2.
  Still inside: add 2·1 + 3 → 3. Now outside: add 2·(2 − 6) + 5 = −3 → 0 and step x to 5.
  At err = 0, the midpoint is exactly on the circle; the code counts that as outside: add
  2·(3 − 5) + 5 = 1, x = 4. At (4, 4) the walk reaches the diagonal and stops.
- Five steps times eight mirrors is 40 points, but the circle has 32 pixels. The first step
  (y = 0) and the last (x = y) sit on symmetry axes, where pairs of mirrors land on the same
  pixel: 4 duplicates each.
- The circle is round in the terminal only if the font's characters are square, which they
  are not. On a pixel canvas it is round.

### circle and fillCircle

`project/ch10/src/draw.zig` (lines 59–87)

```zig
/// The midpoint circle algorithm: walk one eighth of the circle and mirror
/// each point into the other seven octants.
pub fn circle(canvas: Canvas, center: Point, radius: i32, color: Color) void {
    var x = radius;
    var y: i32 = 0;
    var err = 1 - radius;
    while (x >= y) : (y += 1) {
        const cx = center.x;
        const cy = center.y;
        inline for (.{ .{ x, y }, .{ y, x }, .{ -y, x }, .{ -x, y }, .{ -x, -y }, .{ -y, -x }, .{ y, -x }, .{ x, -y } }) |d| {
            canvas.set(cx + d[0], cy + d[1], color);
        }
        if (err < 0) {
            err += 2 * y + 3;
        } else {
            err += 2 * (y - x) + 5;
            x -= 1;
        }
    }
}

/// A filled circle: one span per row, as wide as the circle at that row.
pub fn fillCircle(canvas: Canvas, center: Point, radius: i32, color: Color) void {
    var dy = -radius;
    while (dy <= radius) : (dy += 1) {
        const half: i32 = @intFromFloat(@sqrt(@as(f32, @floatFromInt(radius * radius - dy * dy))));
        span(canvas, center.x - half, center.x + half, center.y + dy, color);
    }
}
```

- `circle` is the example without the printing. The eight offsets are a tuple of tuples, and
  `inline for` unrolls the loop into eight `set` calls.
- `fillCircle` takes a different route: for each row `dy` from the top of the circle to the
  bottom, the half-width at that row is `√(r² − dy²)` (Pythagoras), and one `span` fills it.
  One square root per row is cheap, and spans clip for free. It is the chapter's one float.
- The two do not agree exactly at the edge: `fillCircle` truncates the half-width, so the
  disc's edge sits on the midpoint circle or just inside it. A quick check of every
  radius from 1 to 79 found no row where the disc reaches past the ring and no gap between
  them, so a ring drawn around a disc of the same radius makes a clean outline.

## Filled triangles with edge functions

Filled triangles are the shape that matters most. Every 3D model in Part II is made of them,
and Chapter 18's rasterizer fills millions. There are two classic ways to fill one. The
*scanline* way sorts the vertices by y, walks the two edges on the left and right of each row
with Bresenham-like steps, and fills a span between them. The *edge-function* way asks, for
every pixel in the triangle's bounding box: is this pixel inside? It sounds wasteful, and on a
1980s CPU it was. On modern hardware it is what GPUs do, because every pixel's question is
independent of every other's, and that suits parallel hardware. It is also far simpler to get
right, so that is the way `delve` takes.

### Which side of a line?

For an edge from a to b and a point p, define

```text
E(a, b, p) = (b.x − a.x)·(p.y − a.y) − (b.y − a.y)·(p.x − a.x)
```

This is the 2D cross product of the edge vector b − a and the vector p − a. Geometrically it
is twice the *signed* area of the triangle (a, b, p): its size is the area, and its sign says
on which side of the line through a and b the point p lies. On the line, E is zero.

`examples/ch10/edge_function.zig`

```zig
//! The edge function E(a, b, p): twice the signed area of the triangle
//! (a, b, p). Its sign tells which side of the line a->b the point p is on.
const std = @import("std");

const Point = struct { x: i32, y: i32 };

fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

pub fn main() void {
    // An edge pointing right (east). On screen, y grows downward.
    const a: Point = .{ .x = 0, .y = 0 };
    const b: Point = .{ .x = 10, .y = 0 };
    const tests = [_]struct { name: []const u8, p: Point }{
        .{ .name = "below the edge (screen)", .p = .{ .x = 5, .y = 3 } },
        .{ .name = "above the edge (screen)", .p = .{ .x = 5, .y = -3 } },
        .{ .name = "on the line", .p = .{ .x = 7, .y = 0 } },
        .{ .name = "on the line, past b", .p = .{ .x = 15, .y = 0 } },
        .{ .name = "twice as far below", .p = .{ .x = 5, .y = 6 } },
    };
    for (tests) |t| {
        std.debug.print("{s:<24} p = ({d},{d}), E(a, b, p) = {d}\n", .{ t.name, t.p.x, t.p.y, edge(a, b, t.p) });
    }

    // For a whole triangle, E(a, b, c) is twice its area, and its sign is
    // the winding: positive means clockwise on a y-down screen.
    const c: Point = .{ .x = 0, .y = 6 };
    std.debug.print("E(a, b, c) = {d} for a, b, c (clockwise on screen)\n", .{edge(a, b, c)});
    std.debug.print("E(a, c, b) = {d} for a, c, b (counter-clockwise)\n", .{edge(a, c, b)});
    std.debug.print("area of the 10 x 6 right triangle = {d}\n", .{@divExact(edge(a, b, c), 2)});
}
```

```console
$ zig run examples/ch10/edge_function.zig
below the edge (screen)  p = (5,3), E(a, b, p) = 30
above the edge (screen)  p = (5,-3), E(a, b, p) = -30
on the line              p = (7,0), E(a, b, p) = 0
on the line, past b      p = (15,0), E(a, b, p) = 0
twice as far below       p = (5,6), E(a, b, p) = 60
E(a, b, c) = 60 for a, b, c (clockwise on screen)
E(a, c, b) = -60 for a, c, b (counter-clockwise)
area of the 10 x 6 right triangle = 30
```

- The value grows linearly with the distance from the line: twice as far below, twice the
  value. E is a distance times the edge's length.
- "On the line" means on the infinite line, not the segment: (15, 0) is past b and still
  gives 0.
- The sign of E(a, b, c) for the triangle's own third vertex is its *winding*. Here is the
  triangle on screen:

```text
  a (0,0) ----------> b (10,0)
   |              _/
   |          _/
   |      _/
   v   _/
  c (0,6)
```

Going a → b → c → a turns right at every corner: clockwise *as you see it on the screen*. In
math, with y up, the same numbers would be counter-clockwise, and the textbook rule "positive
area means counter-clockwise" would hold. The y-down screen flips it. Chapter 9 promised this
would come up; here it is. In `delve`, **E > 0 means p is to the right of the edge, and a
positive triangle is clockwise on screen.**

### The inside test

Walk around a clockwise triangle and the interior is always on your right. So a point p is
inside when it is on the right of all three edges:

```text
E(b, c, p) ≥ 0  and  E(c, a, p) ≥ 0  and  E(a, b, p) ≥ 0
```

For a counter-clockwise triangle all three signs flip, and the same test finds nothing. The
fix is one line: if E(a, b, c) < 0, swap b and c, which reverses the winding.

`examples/ch10/triangle_ascii.zig` (excerpt)

```zig
/// Tests every cell of the canvas; inside means all three E >= 0, which is
/// right only for triangles that are clockwise on screen.
fn fillNaive(canvas: *Ascii, a: Point, b: Point, c: Point, char: u8) void {
    for (0..Ascii.height) |uy| for (0..Ascii.width) |ux| {
        const p: Point = .{ .x = @intCast(ux), .y = @intCast(uy) };
        if (edge(b, c, p) >= 0 and edge(c, a, p) >= 0 and edge(a, b, p) >= 0) canvas.set(p.x, p.y, char);
    };
}

/// Makes the triangle clockwise first, so either winding works.
fn fill(canvas: *Ascii, a: Point, b_in: Point, c_in: Point, char: u8) void {
    var b = b_in;
    var c = c_in;
    if (edge(a, b, c) < 0) std.mem.swap(Point, &b, &c);
    fillNaive(canvas, a, b, c, char);
}
```

`main` fills the triangle (2, 1), (29, 4), (9, 11) in both vertex orders, with and without the
swap:

```console
$ zig run examples/ch10/triangle_ascii.zig
E(a, b, c) = 249: a, b, c is clockwise on screen
naive fill: a, b, c (128 cells) and a, c, b (0 cells)
 0 ................................   ................................
 1 ..#.............................   ................................
 2 ...#########....................   ................................
 3 ....#################...........   ................................
 4 .....#########################..   ................................
 5 .....######################.....   ................................
 6 ......##################........   ................................
 7 .......##############...........   ................................
 8 .......###########..............   ................................
 9 ........#######.................   ................................
10 .........###....................   ................................
11 .........#......................   ................................
12 ................................   ................................
with the swap, a, c, b covers 128 cells, the same ones: true
```

- The counter-clockwise order fills nothing at all: no pixel is on the right of all three
  edges when "right" faces outward. The swap fixes it, and the two orders give the same
  cells.
- The triangle's area is E / 2 = 124.5, but 128 cells were filled. With `>=`, a pixel whose
  center lies exactly on an edge counts as inside. The vertex pixels a, b and c are always
  filled, and so are any other pixels exactly on an edge.
- `for (...) |uy| for (...) |ux| { ... };` nests two loops without an extra pair of braces.
  The trailing `;` ends the outer loop's statement.

### draw.fillTriangle

`project/ch10/src/draw.zig` (lines 89–120)

```zig
/// Twice the signed area of triangle (a, b, p). With y pointing down it is
/// positive when p lies to the right of the edge a->b (clockwise on screen).
pub fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

/// A filled triangle, either winding. A pixel is inside when it is on the
/// inner side of all three edges. Only the bounding box is tested.
pub fn fillTriangle(canvas: Canvas, a: Point, b_in: Point, c_in: Point, color: Color) void {
    var b = b_in;
    var c = c_in;
    if (edge(a, b, c) < 0) std.mem.swap(Point, &b, &c); // make it clockwise
    if (edge(a, b, c) == 0) return; // degenerate: no area

    const w: i32 = @intCast(canvas.width);
    const h: i32 = @intCast(canvas.height);
    const min_x = @max(@min(a.x, b.x, c.x), 0);
    const max_x = @min(@max(a.x, b.x, c.x), w - 1);
    const min_y = @max(@min(a.y, b.y, c.y), 0);
    const max_y = @min(@max(a.y, b.y, c.y), h - 1);

    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            const p: Point = .{ .x = x, .y = y };
            if (edge(b, c, p) >= 0 and edge(c, a, p) >= 0 and edge(a, b, p) >= 0) {
                canvas.set(x, y, color);
            }
        }
    }
}
```

- **The bounding box, clipped.** Only pixels between the smallest and largest x and y of the
  three vertices can be inside, and only those on the canvas matter. `@min` and `@max` take
  any number of arguments. Clipping the box *is* clipping the triangle: a triangle mostly off
  the canvas tests only its visible part. A triangle entirely off the canvas gets an empty
  box (`min_x > max_x`) and the loops do not run.
- **Degenerate triangles.** If the three points are on one line, E(a, b, c) is 0 and the
  triangle has no inside; the function returns before testing anything. Without that check,
  the `>=` test would still draw the pixels exactly on the line, which is a line drawn badly.
- **Why integers.** E multiplies two coordinate differences. For a 640 x 400 canvas they are at
  most about a thousand, so E stays far below the `i32` limit of about two billion. Integer
  arithmetic is exact, so a pixel exactly on an edge gives exactly 0, and two triangles that
  share an edge compute the same values for it (with opposite signs).

The test checks the winding swap:

`project/ch10/src/draw.zig` (lines 151–163)

```zig
test "fillTriangle covers the same pixels in either winding" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 10, 10);
    defer canvas.deinit(gpa);
    const a: Point = .{ .x = 0, .y = 0 };
    const b: Point = .{ .x = 3, .y = 0 };
    const c: Point = .{ .x = 0, .y = 3 };
    fillTriangle(canvas, a, b, c, Color.white);
    try std.testing.expectEqual(10, countLit(canvas)); // 4 + 3 + 2 + 1
    canvas.clear(Color.black);
    fillTriangle(canvas, a, c, b, Color.white);
    try std.testing.expectEqual(10, countLit(canvas));
}
```

The right triangle with legs of 3 covers 4 + 3 + 2 + 1 = 10 pixels, including both legs and
the diagonal, because `>=` counts pixels on the edges.

### Shared edges, and what Chapter 18 will fix

That inclusive `>=` has a consequence. When two triangles share an edge, pixels exactly on the
edge pass the test for *both*, and are drawn twice. The test card below has a hexagon made of
six triangles around a center point. Exercise 2 counts the writes: 144 pixels are drawn twice
and the center pixel six times. With opaque colors nothing shows, because the second write
covers the first with a color that is just as right. With transparency, a doubled pixel would
be blended twice and show as a visible seam; with an exclusive `>` instead, pixels on shared
edges would be drawn by neither triangle and leave a crack.

The exact answer is a *fill rule*: a tie-breaker that gives every edge pixel to exactly one of
the triangles that share it. GPUs and Direct3D use the *top-left rule*. Chapter 18 builds the
real rasterizer with that rule, and with sub-pixel precision, so vertices need not sit on
whole pixels. It will also use the three E values for more than a yes-or-no test. Divided by
E(a, b, c), they are the pixel's *barycentric coordinates*: three weights that say how close
the pixel is to each vertex and always add up to 1. Exercise 3 uses them to blend colors
across a triangle, which is how textures and lighting are spread over triangles later.

### All of it in an image

Before moving these primitives into `delve`, here they are together in a small, stand-alone
program that writes a PPM, as in Chapter 9. It repeats `line`, `circle` and `fillTriangle`
on its own 160 x 100 array of `[3]u8`:

`examples/ch10/shapes_ppm.zig` (excerpt: `main`)

```zig
pub fn main(init: std.process.Init) !void {
    fillTriangle(.{ .x = 100, .y = 10 }, .{ .x = 150, .y = 90 }, .{ .x = 70, .y = 80 }, .{ 160, 80, 224 });
    circle(.{ .x = 40, .y = 50 }, 30, .{ 96, 224, 96 });
    var i: i32 = 0;
    while (i <= 8) : (i += 1) line(.{ .x = 40, .y = 50 }, .{ .x = 10 + i * 15, .y = 95 }, .{ 240, 192, 64 });

    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "shapes.ppm", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const w = &file_writer.interface;
    try w.print("P6\n{d} {d}\n255\n", .{ width, height });
    try w.writeAll(std.mem.sliceAsBytes(&pixels));
    try w.flush();
    std.debug.print("wrote shapes.ppm ({d} x {d})\n", .{ width, height });
}
```

```console
$ zig run examples/ch10/shapes_ppm.zig
wrote shapes.ppm (160 x 100)
$ file shapes.ppm
shapes.ppm: Netpbm image data, size = 160 x 100, rawbits, pixmap
$ convert shapes.ppm -scale 300% shapes.png
```

![shapes.ppm scaled up 3x: a purple triangle, a green circle, and nine yellow lines fanning
out from the circle's center, some of them crossing the triangle](images/ch10-shapes.png)

- The pixels are a global `var pixels: [height][width]Rgb`, with `Rgb = [3]u8`. A
  two-dimensional array of byte triples is already exactly a PPM's pixel data, row by row, so
  `std.mem.sliceAsBytes(&pixels)` writes it in one call.
- `convert -scale 300%` enlarges by copying pixels, without blurring, so every pixel of the
  algorithms stays visible.
- Drawing order is painting order. The lines come last and cross over everything; the
  triangle is first and is covered where the lines pass.

## A bitmap font

The test card needs text, and raylib's `DrawText` is off limits. So `delve` gets its own font:
5 x 7 pixel glyphs, the size of an old terminal or LED sign. A *bitmap font* stores each
character as a small grid of on and off pixels; drawing text means copying those grids to the
canvas.

The glyphs have to be written down somewhere. As numbers, a `T` is
`{ 0b11111, 0b00100, 0b00100, ... }`, which is exact and unreadable. Instead, we draw each
glyph as text, one per line: the character, a space, then its 7 rows of 5 pixels, `#` for on
and `.` for off, separated by spaces. Then we let the compiler turn the text into numbers.

`examples/ch10/comptime_font.zig`

```zig
//! A three-glyph bitmap font, written as text and turned into bit masks at
//! compile time. The program only prints the table the compiler built.
const std = @import("std");

/// One glyph per line: the character, then 7 rows of 5 pixels.
const source =
    \\H #...# #...# #...# ##### #...# #...# #...#
    \\I .###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.
    \\! ..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..
    // A mistyped glyph: its last row is missing. Uncomment it to see the
    // compiler catch the mistake.
    // \\X #...# #...# .#.#. ..#.. .#.#. #...#
;

const Glyph = [7]u5; // one 5-bit mask per row, leftmost pixel in bit 4

const glyphs: [128]Glyph = blk: {
    @setEvalBranchQuota(10_000);
    var table: [128]Glyph = @splat(@splat(0));
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |text| {
        // A character, a space, and 7 groups of 5 separated by spaces.
        if (text.len != 2 + 7 * 6 - 1) {
            @compileError(std.fmt.comptimePrint("glyph '{c}': {d} characters, expected 43", .{ text[0], text.len }));
        }
        var glyph: Glyph = undefined;
        for (&glyph, 0..) |*bits, row| {
            bits.* = 0;
            for (text[2 + row * 6 ..][0..5]) |c| bits.* = (bits.* << 1) | @intFromBool(c == '#');
        }
        table[text[0]] = glyph;
    }
    break :blk table;
};

pub fn main() void {
    for ("HI!") |char| {
        std.debug.print("'{c}':", .{char});
        for (glyphs[char]) |bits| std.debug.print(" {b:0>5}", .{bits});
        std.debug.print("\n", .{});
    }
    // Draw the same masks as text: each set bit is a '#'.
    for (0..7) |row| {
        for ("HI!") |char| {
            const bits = glyphs[char][row];
            for (0..5) |col| {
                const set = bits & (@as(u5, 1) << @intCast(4 - col)) != 0;
                std.debug.print("{c}", .{@as(u8, if (set) '#' else '.')});
            }
            std.debug.print(" ", .{});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("the table is {d} bytes of constant data\n", .{@sizeOf(@TypeOf(glyphs))});
}
```

```console
$ zig run examples/ch10/comptime_font.zig
'H': 10001 10001 10001 11111 10001 10001 10001
'I': 01110 00100 00100 00100 00100 00100 01110
'!': 00100 00100 00100 00100 00100 00000 00100
#...# .###. ..#.. 
#...# ..#.. ..#.. 
#...# ..#.. ..#.. 
##### ..#.. ..#.. 
#...# ..#.. ..#.. 
#...# ..#.. ..... 
#...# .###. ..#.. 
the table is 896 bytes of constant data
```

- **A multiline string literal.** Each line starting with `\\` is one line of the string, with
  no escapes: `\\H #...#` is the text `H #...#`. Lines are joined with `\n`, without a final
  newline. Comment lines may sit between them, which is how the mistyped `X` can be switched
  off.
- **`const glyphs = blk: { ... };`** is a labeled block. A container-level `const` is
  evaluated at compile time, so the whole block runs inside the compiler: `splitScalar`
  iterates the lines, the inner loops shift the bits in, and `break :blk table` makes the
  finished table the constant's value. The program contains only the 896-byte table (128
  glyphs, 7 rows, one byte per `u5`), not the text and not the parsing code.
- `@splat(@splat(0))` starts every glyph blank, so characters without a line, like the space,
  draw nothing.
- **Bits.** For each row, the loop takes the 5 characters at offset `2 + row * 6` (skip the
  character and its space, then 6 per group including the separating space) and shifts each
  one in: `bits << 1 | 1` for `#`. The leftmost pixel ends up in bit 4.
- **`@setEvalBranchQuota`.** The compiler counts loop iterations at compile time and stops at
  1000 by default, so that an endless loop in comptime code is an error, not a hung build.
  Parsing a font is a lot of honest iterations, so we raise the limit. The project's full font
  sets it to 100,000.

Now uncomment the `X`. Its line is missing the last row: 37 characters instead of 43. The
explicit check catches it with a message we wrote:

```console
$ zig run examples/ch10/comptime_font.zig
comptime_font.zig:24:13: error: glyph 'X': 37 characters, expected 43
            @compileError(std.fmt.comptimePrint("glyph '{c}': {d} characters, expected 43", .{ text[0], text.len }));
            ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
referenced by:
    main: comptime_font.zig:39:20
...
```

`@compileError` stops compilation with a message, and `std.fmt.comptimePrint` formats one at
compile time. Without the check (delete the `if` and its body), the compiler still refuses:

```console
$ zig run comptime_font.zig
comptime_font.zig:26:42: error: end index 43 out of bounds for slice of length 37
            for (text[2 + row * 6 ..][0..5]) |c| bits.* = (bits.* << 1) | @intFromBool(c == '#');
                                         ^
referenced by:
    main: comptime_font.zig:36:20
...
```

At run time, slicing past the end of a slice is a panic. At compile time it is a compile
error. That is the real benefit of parsing at comptime: a typo in the font cannot reach a
running program. The explicit check only gives a better message. (`comptime_font.zig` here
is a copy with the check deleted, so the line numbers moved.)

### font.zig

The project's font has the 26 letters, the 10 digits, and the punctuation the HUD needs.

`project/ch10/src/font.zig` (most glyph lines left out)

```zig
//! A tiny 5x7 bitmap font for the HUD. The glyphs are drawn as text below
//! and turned into bit masks at compile time.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");

pub const glyph_width = 5;
pub const glyph_height = 7;
/// Distance from one character to the next, including a 1-pixel gap.
pub const advance = glyph_width + 1;

/// One line per glyph: the character, a space, then 7 rows of 5 pixels.
const source =
    \\A .###. #...# #...# ##### #...# #...# #...#
    \\B ####. #...# #...# ####. #...# #...# ####.
    \\C .###. #...# #.... #.... #.... #...# .###.
    // ... D to Z, 0 to 9, and ! " # % ' ( ) * + , - . / : ; < = > ? [ ] _ ...
    \\| ..#.. ..#.. ..#.. ..#.. ..#.. ..#.. ..#..
;

/// One glyph: 7 rows, each a 5-bit mask with the leftmost pixel in bit 4.
const Glyph = [glyph_height]u5;

/// Glyphs indexed by ASCII code; characters without a glyph stay blank.
const glyphs: [128]Glyph = blk: {
    @setEvalBranchQuota(100_000);
    var table: [128]Glyph = @splat(@splat(0));
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |text| {
        var glyph: Glyph = undefined;
        for (&glyph, 0..) |*bits, row| {
            bits.* = 0;
            for (text[2 + row * 6 ..][0..glyph_width]) |c| bits.* = (bits.* << 1) | @intFromBool(c == '#');
        }
        table[text[0]] = glyph;
    }
    break :blk table;
};

/// Draws `text` with its top-left corner at (x, y), each font pixel a
/// `scale` x `scale` square. Lowercase letters use the uppercase glyphs.
/// Returns the x coordinate just past the last character.
pub fn drawText(canvas: Canvas, x: i32, y: i32, text: []const u8, scale: i32, color: Color) i32 {
    var pen = x;
    for (text) |char| {
        const glyph = glyphs[std.ascii.toUpper(char) & 0x7f];
        for (glyph, 0..) |bits, row| {
            for (0..glyph_width) |col| {
                const bit = @as(u5, 1) << @intCast(glyph_width - 1 - col);
                if (bits & bit == 0) continue;
                const px = pen + @as(i32, @intCast(col)) * scale;
                const py = y + @as(i32, @intCast(row)) * scale;
                draw.fillRect(canvas, px, py, scale, scale, color);
            }
        }
        pen += advance * scale;
    }
    return pen;
}

/// The width in pixels of `text` drawn at `scale`, without the final gap.
pub fn textWidth(text: []const u8, scale: i32) i32 {
    if (text.len == 0) return 0;
    return (@as(i32, @intCast(text.len)) * advance - 1) * scale;
}

test "glyphs are parsed at compile time" {
    // The letter T: a full top row, then the middle column.
    try std.testing.expectEqual(0b11111, glyphs['T'][0]);
    try std.testing.expectEqual(0b00100, glyphs['T'][6]);
    try std.testing.expectEqual(@as(Glyph, @splat(0)), glyphs[' ']);
}

test "drawText returns the pen position" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 40, 10);
    defer canvas.deinit(gpa);
    try std.testing.expectEqual(2 + 3 * advance, drawText(canvas, 2, 1, "abc", 1, Color.white));
    try std.testing.expectEqual(17, textWidth("abc", 1));
}
```

- **Each font pixel is a `fillRect`** of `scale` x `scale`, so text can be drawn at 1x, 2x or
  any whole size, and it is clipped like any other shape.
- **`drawText` returns the pen position**, the x where the next character would go. Text in
  different colors can be chained:
  `const x2 = font.drawText(c, x, y, "HP ", 1, .hex(0xc0c0c0));` and then
  `_ = font.drawText(c, x2, y, "37", 1, .hex(0xff4040));`.
  Callers that do not need it write `_ = font.drawText(...)`, since Zig does not let a return
  value be ignored silently.
- **`textWidth`** measures without drawing: n characters take `n * advance` pixels, minus the
  gap after the last one. It is what right-aligning needs: draw at `right_edge - width`.
- **Lowercase as uppercase.** `std.ascii.toUpper` maps `a` to `A`, so the HUD can be written in
  normal case and only one set of letters is drawn. `& 0x7f` keeps a byte above 127 (part of a
  UTF-8 character) inside the table; it shows up as some ASCII glyph or a blank, not a crash.
- **Our own font**, drawn for this book, so there are no license questions about shipping it.

The same two mistakes as in the example, in the project. Delete the last row from the `|`
line, the last glyph in the table:

```console
$ zig build
...
src/font.zig:88:42: error: end index 43 out of bounds for slice of length 37
            for (text[2 + row * 6 ..][0..glyph_width]) |c| bits.* = (bits.* << 1) | @intFromBool(c == '#');
                                         ^~~~~~~~~~~
referenced by:
    drawText: src/font.zig:101:29
    render: src/app.zig:62:26
...
```

The trace says why `glyphs` was evaluated at all: `render` called `drawText`, which uses the
table. And with the `@setEvalBranchQuota` line removed:

```console
$ zig build
...
.../lib/std/mem.zig:1365:5: error: evaluation exceeded 1000 backwards branches
    for (slice[i..], i..) |c, j| {
    ^~~
.../lib/std/mem.zig:1365:5: note: use @setEvalBranchQuota() to raise the branch limit from 1000
...
src/font.zig:83:22: note: called at comptime here
    while (lines.next()) |text| {
           ~~~~~~~~~~^~
...
```

The limit ran out inside the standard library, while `splitScalar` was searching for the next
newline, and the notes walk back to our loop. The quota covers everything evaluated in the
block, including the library code it calls.

## The test card

A *test card* is the picture a TV station broadcast to check the equipment: known shapes in
known places, so any fault is visible at a glance. `delve`'s test card uses every primitive
from this chapter, animates some of them, and writes a HUD with the font. `app.zig` replaces
Chapter 9's gradient:

`project/ch10/src/app.zig`

```zig
//! The program's state and drawing, independent of any window. main.zig
//! calls `update` once per tick and `render` once per frame.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");
const font = @import("font.zig");
const Point = draw.Point;

pub const App = struct {
    /// Seconds of simulated time.
    time: f32 = 0,
    ticks: u32 = 0,

    pub fn update(app: *App, dt: f32) void {
        app.time += dt;
        app.ticks += 1;
    }

    /// A test card: every 2D primitive, some of them animated, and a HUD.
    pub fn render(app: App, canvas: Canvas) void {
        canvas.clear(.hex(0x1c1c28));

        // A starburst of lines in every octant, turning slowly.
        const center: Point = .{ .x = 120, .y = 150 };
        for (0..24) |i| {
            const angle = app.time * 0.5 + @as(f32, @floatFromInt(i)) * (std.math.tau / 24.0);
            const tip = polar(center, 90, angle);
            draw.line(canvas, center, tip, if (i % 2 == 0) .hex(0xf0c040) else .hex(0x40c0f0));
        }

        // Rectangles: filled, outlined, and one hanging off the left edge.
        draw.fillRect(canvas, 250, 70, 120, 70, .hex(0x3060c0));
        draw.rect(canvas, 240, 60, 140, 90, Color.white);
        draw.fillRect(canvas, -30, 330, 80, 50, .hex(0xc04040));

        // Circles: outlined rings and a filled disc that pulses.
        draw.circle(canvas, .{ .x = 470, .y = 105 }, 45, .hex(0x60e060));
        draw.circle(canvas, .{ .x = 470, .y = 105 }, 30, .hex(0x60e060));
        const r: i32 = 15 + @as(i32, @intFromFloat(10 * @sin(app.time * 3)));
        draw.fillCircle(canvas, .{ .x = 570, .y = 105 }, r, .hex(0xe08040));

        // A spinning filled triangle.
        const tri: Point = .{ .x = 310, .y = 280 };
        draw.fillTriangle(
            canvas,
            polar(tri, 70, app.time),
            polar(tri, 70, app.time + std.math.tau / 3.0),
            polar(tri, 70, app.time + 2 * std.math.tau / 3.0),
            .hex(0xa050e0),
        );

        // A hexagon made of six triangles with shared edges.
        const hex: Point = .{ .x = 500, .y = 280 };
        for (0..6) |i| {
            const a = @as(f32, @floatFromInt(i)) * (std.math.tau / 6.0);
            const shade: u8 = @intCast(80 + i * 30);
            draw.fillTriangle(canvas, hex, polar(hex, 70, a), polar(hex, 70, a + std.math.tau / 6.0), .{ .r = shade, .g = shade, .b = 255 });
        }

        // The HUD: text drawn with the bitmap font.
        _ = font.drawText(canvas, 8, 8, "delve test card", 2, Color.white);
        var buffer: [64]u8 = undefined;
        const status = std.fmt.bufPrint(&buffer, "tick {d}  time {d:.2}s", .{ app.ticks, app.time }) catch unreachable;
        const w: i32 = @intCast(canvas.width);
        _ = font.drawText(canvas, w - 8 - font.textWidth(status, 1), 12, status, 1, .hex(0xc0c0c0));
        _ = font.drawText(canvas, 120, 372, "abcdefghijklmnopqrstuvwxyz 0123456789 !\"#%'()*+,-./:;<=>?[]_|", 1, .hex(0xc0c0c0));
    }
};

/// The point `radius` pixels from `center` in direction `angle` (radians,
/// clockwise on screen because y points down).
fn polar(center: Point, radius: f32, angle: f32) Point {
    return .{
        .x = center.x + @as(i32, @intFromFloat(@round(radius * @cos(angle)))),
        .y = center.y + @as(i32, @intFromFloat(@round(radius * @sin(angle)))),
    };
}
```

- **`polar`** turns an angle and a distance into a pixel: `(cos θ, sin θ)` scaled by the
  radius, rounded to whole pixels. Angle 0 points right. Because y grows downward, a growing
  angle turns *clockwise* on screen, the opposite of the math-class picture, as Chapter 9
  warned. `std.math.tau` is 2π, one full turn.
- **The starburst** has 24 lines from one center, one every 15°, so it covers all eight
  octants of Bresenham's algorithm at every moment (and at time 0 includes the exactly
  horizontal, vertical and diagonal lines). A sign error in one octant would show as a missing
  or wrong spoke.
- **The rectangles** test filling, outlining (the white frame is 10 pixels outside the blue
  fill on every side), and clipping: the red one starts at x = -30.
- **The circles.** Two rings test `circle`, and the orange disc tests `fillCircle`. Its radius
  goes from 5 to 25 with `sin(time · 3)`, so it pulses about every two seconds.
- **The spinning triangle** has its vertices on a circle of radius 70, 120° apart, and turns at
  one radian per second. Rotation does not change its winding, but its edges take every
  direction in turn, and its bounding box changes every frame.
- **The hexagon** is six triangles that share the center vertex and their side edges, each
  shade 30 brighter than the last.
- **The HUD.** `std.fmt.bufPrint` formats into a stack buffer and returns the slice it wrote,
  with no allocation. It fails only if the text does not fit, which 64 bytes rule out here;
  `catch unreachable` says so (and checks it in Debug builds). `{d:.2}` prints a float with
  two decimals. The status is right-aligned with `textWidth`. The bottom line shows every
  glyph in the font.
- **`ticks`** counts updates. With `--frames 60`, every frame is one tick, so the HUD must read
  `TICK 60` and `TIME 1.00S`: a check on the fixed timestep you can read off the picture.

`main.zig` changes in one place: its `test` block names the two new files, so their tests run.

```zig
test {
    _ = @import("canvas.zig");
    _ = @import("image.zig");
    _ = @import("options.zig");
    _ = @import("draw.zig");
    _ = @import("font.zig");
}
```

The rest of `delve` is unchanged: `canvas.zig`, `image.zig`, `options.zig`, `platform.zig`,
and `build.zig`. The test card is drawn entirely by `app.zig`, `draw.zig` and `font.zig`.

## Checkpoint

From `project/ch10/`:

```console
$ zig build test --summary all
Build Summary: 6/6 steps succeeded; 12/12 tests passed
test success
+- run test 12 pass (12 total) 7ms MaxRSS:7M
...
$ zig build
$ ./zig-out/bin/delve --headless --frames 60 --out card.png
$ file card.png
card.png: PNG image data, 640 x 400, 8-bit/color RGB, non-interlaced
```

Twelve tests: Chapter 9's seven, three in `draw.zig` and two in `font.zig`.

![The delve test card: a turning starburst of yellow and blue lines, a blue rectangle in a
white frame, two green rings and an orange disc, a purple triangle, a six-shaded hexagon, a
red rectangle cut by the left edge, and the HUD reading DELVE TEST CARD and TICK 60 TIME
1.00S](images/ch10-test-card.png)

The window shows the same frame. As in Chapter 9, a windowed run of 60 frames, halved, has
exactly the pixels of the headless one:

```console
$ xvfb-run -a -s "-screen 0 1920x1080x24" ./zig-out/bin/delve --frames 60 --screenshot window.png
$ file window.png
window.png: PNG image data, 1280 x 800, 8-bit/color RGBA, non-interlaced
$ convert window.png -sample 50% rgb:- | cmp - <(convert card.png rgb:-) && echo "same pixels"
same pixels
```

On a desktop, run `./zig-out/bin/delve` without arguments and watch: the starburst turns, the
triangle spins, the disc pulses, and the HUD counts ticks. Escape closes the window.

**Speed.** The same 600-frame measurement as in Chapter 9:

```console
$ time ./zig-out/bin/delve --headless --frames 600
real	0m0.844s
$ zig build --release
$ time ./zig-out/bin/delve --headless --frames 600
real	0m0.037s
```

In Debug the test card costs about what Chapter 9's full-screen pattern did; in ReleaseFast it
takes 0.06 ms per frame, more than 20 times faster than Debug. Drawing 2D shapes in software
at this size is cheap.

## Summary

- Clipping happens at the bottom, in `Canvas.set` and `draw.span`. Every other primitive is
  built on those two and may be drawn partly or entirely off the canvas.
- Filled shapes are made of spans, and a span is one `@memset`.
- Bresenham's line algorithm steps along the major axis and keeps an integer error term, the
  line's implicit function at the midpoint, scaled by 2. The all-octant form tracks both axes
  with `err = dx + dy`, `e2 = 2·err`.
- When the ideal line passes exactly halfway between two pixels, either is right; DDA's
  rounding and Bresenham's direction can pick differently. Integers make the choice exact and
  repeatable.
- The midpoint circle walks one octant from (r, 0) to the diagonal with `f = x² + y² − r²`
  and mirrors each point eight ways. `fillCircle` uses one square root per row instead.
- The edge function `E(a, b, p)` is twice the signed area of (a, b, p). On a y-down screen,
  E > 0 means p is right of a→b, and a triangle with E(a, b, c) > 0 is clockwise. A pixel is
  inside when all three edge functions are ≥ 0; swapping two vertices fixes the winding.
- The inclusive test draws shared edges twice. Chapter 18 replaces it with the top-left rule
  and uses the E values as barycentric weights.
- A font written as text is parsed at comptime into a 896-byte table. A malformed glyph is a
  compile error, and `@setEvalBranchQuota` allows long comptime loops.

## Exercises

1. **Thick lines.** Add `draw.thickLine(canvas, a, b, thickness, color)`, and use it with
   thickness 3 for the starburst.

<details><summary>Solution</summary>

Walk the line with Bresenham and stamp a filled disc at every step:

```zig
/// A line `thickness` pixels wide: a filled disc at every Bresenham step.
pub fn thickLine(canvas: Canvas, a: Point, b: Point, thickness: i32, color: Color) void {
    const radius = @divTrunc(thickness, 2);
    const dx: i32 = @intCast(@abs(b.x - a.x));
    const dy: i32 = -@as(i32, @intCast(@abs(b.y - a.y)));
    const sx: i32 = if (a.x < b.x) 1 else -1;
    const sy: i32 = if (a.y < b.y) 1 else -1;
    var err = dx + dy;
    var p = a;
    while (true) {
        fillCircle(canvas, p, radius, color);
        if (p.x == b.x and p.y == b.y) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            p.x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            p.y += sy;
        }
    }
}

test "a thick horizontal line is a band of rows" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 20, 12);
    defer canvas.deinit(gpa);
    thickLine(canvas, .{ .x = 4, .y = 6 }, .{ .x = 14, .y = 6 }, 4, Color.white);
    // Radius 2: rows 4 to 8 are lit, from x = 2 to 16 on the middle row.
    try std.testing.expectEqual(Color.white, canvas.get(2, 6));
    try std.testing.expectEqual(Color.white, canvas.get(16, 6));
    try std.testing.expectEqual(Color.white, canvas.get(9, 4));
    try std.testing.expectEqual(Color.white, canvas.get(9, 8));
    try std.testing.expectEqual(Color.black, canvas.get(9, 9));
}
```

In `app.zig`, change `draw.line(canvas, center, tip, ...)` to
`draw.thickLine(canvas, center, tip, 3, ...)`. `zig build test` reports 13/13. The discs
overlap heavily, so this draws each pixel many times; a faster version fills spans between
two offset edges. The ends come out round, which is often what you want anyway. `@divTrunc`
is needed because `/` on signed integers is a compile error in Zig unless both values are
known to be positive: the rounding direction for negative numbers must be spelled out.

</details>

2. **Counting shared edges.** Count how many pixels of the hexagon are drawn twice. Write a
   variant of `fillTriangle` that increments a counter per pixel instead of setting a color,
   and check the counts in a test.

<details><summary>Solution</summary>

In `app.zig`, next to `polar`, which the test reuses:

```zig
/// fillTriangle's loops, but counting writes instead of setting colors.
fn countTriangle(counts: []u8, width: i32, height: i32, a: Point, b_in: Point, c_in: Point) void {
    var b = b_in;
    var c = c_in;
    if (draw.edge(a, b, c) < 0) std.mem.swap(Point, &b, &c);
    var y = @max(@min(a.y, b.y, c.y), 0);
    while (y <= @min(@max(a.y, b.y, c.y), height - 1)) : (y += 1) {
        var x = @max(@min(a.x, b.x, c.x), 0);
        while (x <= @min(@max(a.x, b.x, c.x), width - 1)) : (x += 1) {
            const p: Point = .{ .x = x, .y = y };
            if (draw.edge(b, c, p) >= 0 and draw.edge(c, a, p) >= 0 and draw.edge(a, b, p) >= 0) {
                counts[@intCast(y * width + x)] += 1;
            }
        }
    }
}

test "the hexagon fan draws its shared edges twice" {
    const width = 640;
    const height = 400;
    var counts: [width * height]u8 = @splat(0);
    const hex: Point = .{ .x = 500, .y = 280 };
    for (0..6) |i| {
        const a = @as(f32, @floatFromInt(i)) * (std.math.tau / 6.0);
        countTriangle(&counts, width, height, hex, polar(hex, 70, a), polar(hex, 70, a + std.math.tau / 6.0));
    }
    var histogram: [8]usize = @splat(0);
    for (counts) |n| histogram[n] += 1;
    try std.testing.expectEqual(12738, histogram[1]);
    try std.testing.expectEqual(144, histogram[2]); // pixels exactly on a shared edge
    try std.testing.expectEqual(1, histogram[6]); // the center
}
```

`app.zig` has no tests yet, so add `_ = @import("app.zig");` to `main.zig`'s `test` block.
The numbers: 12,738 pixels are drawn once, 144 twice, and the center six times. 140 of the
144 are on the two horizontal edges, row 280, where every pixel lies exactly on the edge. On
the four slanted shared edges, pixel centers rarely land exactly on the line; only 4 do. The
`counts` array is 256,000 bytes on the stack, which the test thread handles; for anything
larger, allocate it.

</details>

3. **A gradient triangle.** Write `draw.gradientTriangle(canvas, a, b, c, ca, cb, cc)` that
   colors each pixel by blending the three vertex colors, weighted by the three edge
   functions divided by E(a, b, c). Use it for the spinning triangle.

<details><summary>Solution</summary>

```zig
/// A filled triangle whose color blends from `ca` at a to `cb` at b and `cc`
/// at c. Each weight is an edge function divided by the whole triangle's.
pub fn gradientTriangle(canvas: Canvas, a: Point, b_in: Point, c_in: Point, ca: Color, cb_in: Color, cc_in: Color) void {
    var b = b_in;
    var c = c_in;
    var cb = cb_in;
    var cc = cc_in;
    if (edge(a, b, c) < 0) {
        std.mem.swap(Point, &b, &c);
        std.mem.swap(Color, &cb, &cc);
    }
    const area = edge(a, b, c);
    if (area == 0) return;

    const w: i32 = @intCast(canvas.width);
    const h: i32 = @intCast(canvas.height);
    var y = @max(@min(a.y, b.y, c.y), 0);
    while (y <= @min(@max(a.y, b.y, c.y), h - 1)) : (y += 1) {
        var x = @max(@min(a.x, b.x, c.x), 0);
        while (x <= @min(@max(a.x, b.x, c.x), w - 1)) : (x += 1) {
            const p: Point = .{ .x = x, .y = y };
            const e0 = edge(b, c, p); // opposite a: a's weight
            const e1 = edge(c, a, p);
            const e2 = edge(a, b, p);
            if (e0 < 0 or e1 < 0 or e2 < 0) continue;
            const total: f32 = @floatFromInt(area);
            const w0 = @as(f32, @floatFromInt(e0)) / total;
            const w1 = @as(f32, @floatFromInt(e1)) / total;
            const w2 = @as(f32, @floatFromInt(e2)) / total;
            canvas.set(x, y, .{
                .r = mix(ca.r, cb.r, cc.r, w0, w1, w2),
                .g = mix(ca.g, cb.g, cc.g, w0, w1, w2),
                .b = mix(ca.b, cb.b, cc.b, w0, w1, w2),
            });
        }
    }
}

fn mix(a: u8, b: u8, c: u8, w0: f32, w1: f32, w2: f32) u8 {
    const v = w0 * @as(f32, @floatFromInt(a)) + w1 * @as(f32, @floatFromInt(b)) + w2 * @as(f32, @floatFromInt(c));
    return @intFromFloat(@round(@min(v, 255)));
}
```

- The edge *opposite* a vertex gives that vertex's weight: `E(b, c, p)` is 0 on the edge b–c
  and largest at a, where it equals E(a, b, c). So w0 is 1 at a and 0 on the far edge.
- The three E values always add up to E(a, b, c), so the weights add up to 1, and the blend
  never leaves the range of the colors. `@min(v, 255)` is a cheap guard: if float rounding
  ever pushed a sum past 255.5, `@round` would give 256, and `@intFromFloat` into a `u8`
  would panic.
- The colors swap with the vertices, or the swap would move the colors around the triangle.

A test that the vertices get their own colors:

```zig
test "a gradient triangle has each vertex's own color at that vertex" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 20, 20);
    defer canvas.deinit(gpa);
    const red: Color = .hex(0xff0000);
    const green: Color = .hex(0x00ff00);
    const blue: Color = .hex(0x0000ff);
    gradientTriangle(canvas, .{ .x = 1, .y = 1 }, .{ .x = 18, .y = 1 }, .{ .x = 1, .y = 18 }, red, green, blue);
    try std.testing.expectEqual(red, canvas.get(1, 1));
    try std.testing.expectEqual(green, canvas.get(18, 1));
    try std.testing.expectEqual(blue, canvas.get(1, 18));
}
```

In `app.zig`, call `draw.gradientTriangle` with `.hex(0xff4040)`, `.hex(0x40ff40)` and
`.hex(0x4040ff)` in place of the single purple. The spinning triangle becomes a smooth
red-green-blue blend that turns with it. This is barycentric interpolation; in Chapter 18 the
same weights carry texture coordinates and depth instead of colors.

</details>

4. **Three new glyphs.** Add a heart, an up arrow and a degree sign to the font, on ASCII
   characters the HUD does not otherwise use, and give them names.

<details><summary>Solution</summary>

Add three lines to `source` in `font.zig`, after the `|` line:

```zig
    \\& ..... .#.#. ##### ##### .###. ..#.. .....
    \\^ ..#.. .###. #.#.# ..#.. ..#.. ..#.. ..#..
    \\` .##.. #..#. #..#. .##.. ..... ..... .....
```

and names for them:

```zig
/// Symbols drawn on characters the HUD never prints as themselves.
pub const heart = "&";
pub const arrow_up = "^";
pub const degree = "`";
```

The comptime parser does the rest. Use them with `++`, which joins string literals at
compile time:

```zig
        _ = font.drawText(canvas, 8, 40, font.heart ++ " 3  " ++ font.arrow_up ++ " north  21" ++ font.degree ++ "c", 2, .hex(0xff8080));
```

It draws as ♥ 3 ↑ NORTH 21°C. Two choices are ruled out by the code you already have.
Lowercase letters are free in the table but unreachable, because `drawText` uppercases every
character before the lookup. Control characters such as `\x01` are reachable, but a multiline
string literal cannot contain them, so they cannot start a line of `source`. The punctuation
`&`, `^` and `` ` `` works, and `zig build test` still passes.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-10--drawing-in-2d-by-hand)
