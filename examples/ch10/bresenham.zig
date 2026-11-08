//! Bresenham's line algorithm, first for one octant (as derived in the
//! chapter), then for all of them, compared with the DDA line.
const std = @import("std");
const Ascii = @import("ascii_canvas.zig").Ascii;
const ddaLine = @import("dda_line.zig").ddaLine;

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

/// Every octant: the same form as the project's draw.line.
fn line(canvas: *Ascii, x0: i32, y0: i32, x1: i32, y1: i32, char: u8) void {
    const dx: i32 = @intCast(@abs(x1 - x0));
    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;
    var x = x0;
    var y = y0;
    while (true) {
        canvas.set(x, y, char);
        if (x == x1 and y == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
}

pub fn main() void {
    var octant: Ascii = .{};
    var general: Ascii = .{};
    var dda: Ascii = .{};
    lineFirstOctant(&octant, 1, 1, 30, 11, '#');
    line(&general, 1, 1, 30, 11, '#');
    ddaLine(&dda, 1, 1, 30, 11, '#');
    std.debug.print("one octant vs all octants, (1,1) to (30,11):\n", .{});
    octant.printPair(general);
    std.debug.print("same pixels: {}, same as DDA: {}\n", .{
        std.meta.eql(octant, general), std.meta.eql(general, dda),
    });

    // Compare every line from (0,0) to (x,y) on the canvas, both ways round.
    var differ: usize = 0;
    var asymmetric: usize = 0;
    var total: usize = 0;
    var first: ?[2]i32 = null;
    for (0..Ascii.width) |ux| for (0..Ascii.height) |uy| {
        const x: i32 = @intCast(ux);
        const y: i32 = @intCast(uy);
        var a: Ascii = .{};
        var b: Ascii = .{};
        var back: Ascii = .{};
        line(&a, 0, 0, x, y, '#');
        ddaLine(&b, 0, 0, x, y, '#');
        line(&back, x, y, 0, 0, '#');
        total += 1;
        if (!std.meta.eql(a, b)) {
            differ += 1;
            if (first == null) first = .{ x, y };
        }
        if (!std.meta.eql(a, back)) asymmetric += 1;
    };
    std.debug.print("{d} lines: DDA differs from Bresenham in {d}, Bresenham a->b differs from b->a in {d}\n", .{ total, differ, asymmetric });

    if (first) |end| {
        var a: Ascii = .{};
        var b: Ascii = .{};
        line(&a, 0, 0, end[0], end[1], '#');
        ddaLine(&b, 0, 0, end[0], end[1], '#');
        std.debug.print("first difference, (0,0) to ({d},{d}): Bresenham, then DDA\n", .{ end[0], end[1] });
        a.printPair(b);
    }
}
