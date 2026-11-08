//! Filling a triangle with edge functions: a pixel is inside when it is on
//! the inner side of all three edges. Shows why the winding matters.
const std = @import("std");
const Ascii = @import("ascii_canvas.zig").Ascii;

const Point = struct { x: i32, y: i32 };

fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

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

pub fn main() void {
    const a: Point = .{ .x = 2, .y = 1 };
    const b: Point = .{ .x = 29, .y = 4 };
    const c: Point = .{ .x = 9, .y = 11 };
    std.debug.print("E(a, b, c) = {d}: a, b, c is clockwise on screen\n", .{edge(a, b, c)});

    var cw: Ascii = .{};
    var ccw: Ascii = .{};
    fillNaive(&cw, a, b, c, '#');
    fillNaive(&ccw, a, c, b, '#');
    std.debug.print("naive fill: a, b, c ({d} cells) and a, c, b ({d} cells)\n", .{ cw.count('#'), ccw.count('#') });
    cw.printPair(ccw);

    var swapped: Ascii = .{};
    fill(&swapped, a, c, b, '#');
    std.debug.print("with the swap, a, c, b covers {d} cells, the same ones: {}\n", .{
        swapped.count('#'), std.meta.eql(swapped, cw),
    });
}
