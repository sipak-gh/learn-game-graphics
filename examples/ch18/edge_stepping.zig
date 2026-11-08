//! The edge function is linear: one pixel right or down adds a constant.
//! Stepping from pixel to pixel gives exactly the values a direct
//! evaluation gives, because everything is an integer.
const std = @import("std");

const one = 16; // one pixel in fixed point: 4 bits after the binary point
const Point = struct { x: i32, y: i32 };

fn toFixed(x: f32, y: f32) Point {
    return .{ .x = @intFromFloat(@round(x * one)), .y = @intFromFloat(@round(y * one)) };
}

fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

pub fn main() void {
    const a = toFixed(3.3, 1.7);
    const b = toFixed(36.81, 9.25);
    const c = toFixed(11.06, 22.4);
    std.debug.print("corners in 1/16 pixel: ({d},{d}) ({d},{d}) ({d},{d})\n", .{ a.x, a.y, b.x, b.y, c.x, c.y });
    std.debug.print("b.x = 36.81 is stored as {d}/16 = {d} pixels\n", .{ b.x, @as(f32, @floatFromInt(b.x)) / one });

    // Edge a->b at the pixel centers of a 40 x 25 screen.
    const step_x = -(b.y - a.y) * one;
    const step_y = (b.x - a.x) * one;
    std.debug.print("one pixel right adds {d}, one pixel down adds {d}\n", .{ step_x, step_y });
    var row = edge(a, b, .{ .x = one / 2, .y = one / 2 });
    var differ: usize = 0;
    var inside: usize = 0;
    for (0..25) |y| {
        var e = row;
        for (0..40) |x| {
            const center: Point = .{ .x = @intCast(x * one + one / 2), .y = @intCast(y * one + one / 2) };
            if (e != edge(a, b, center)) differ += 1;
            const all: @Vector(3, i32) = .{ e, edge(b, c, center), edge(c, a, center) };
            // All three >= 0 exactly when no sign bit is set in any of them.
            const by_or = @reduce(.Or, all) >= 0;
            const by_and = all[0] >= 0 and all[1] >= 0 and all[2] >= 0;
            if (by_or != by_and) differ += 1;
            if (by_or) inside += 1;
            e += step_x;
        }
        row += step_y;
    }
    std.debug.print("1000 pixels: {d} stepped values differ, {d} pixel centers inside\n", .{ differ, inside });
    // E(a, b, c) is twice the area, in square 1/16 pixels.
    const area = @as(f32, @floatFromInt(edge(a, b, c))) / (one * one) / 2;
    std.debug.print("E(a, b, c) = {d}: an area of {d} square pixels\n", .{ edge(a, b, c), area });

    // How far apart can the corners be before E overflows an i32?
    for ([_]i32{ 1000, 2000, 3000 }) |size| {
        const p: Point = .{ .x = 0, .y = 0 };
        const q: Point = .{ .x = size * one, .y = 0 };
        const r: Point = .{ .x = 0, .y = size * one };
        const wide = @as(i64, q.x - p.x) * (r.y - p.y) - @as(i64, q.y - p.y) * (r.x - p.x);
        std.debug.print("corners {d} px apart: E = {d}, fits in i32: {}\n", .{ size, wide, wide <= std.math.maxInt(i32) });
    }
}
