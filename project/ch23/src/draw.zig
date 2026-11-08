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

fn countLit(canvas: Canvas) usize {
    var n: usize = 0;
    for (canvas.pixels) |p| n += @intFromBool(p.r != 0);
    return n;
}

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

test "fillRect is clipped to the canvas" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 10, 10);
    defer canvas.deinit(gpa);
    fillRect(canvas, -5, 8, 20, 20, Color.white);
    try std.testing.expectEqual(20, countLit(canvas)); // rows 8 and 9
}

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
