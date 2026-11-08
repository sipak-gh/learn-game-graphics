//! Three triangles sharing edges that run through pixel centers, filled
//! with three rules for a center that lies exactly on an edge.
const std = @import("std");

const one = 16;
const Point = struct { x: i32, y: i32 };

fn px(x: f32, y: f32) Point {
    return .{ .x = @intFromFloat(@round(x * one)), .y = @intFromFloat(@round(y * one)) };
}

fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

/// Top edges run right (in a clockwise triangle), left edges run up.
fn isTopLeft(a: Point, b: Point) bool {
    return b.y < a.y or (b.y == a.y and b.x > a.x);
}

const Rule = enum { at_least_zero, above_zero, top_left };

/// Does pixel center p belong to the clockwise triangle t?
fn covers(rule: Rule, t: [3]Point, p: Point) bool {
    for (0..3) |i| {
        const a = t[i];
        const b = t[(i + 1) % 3];
        const e = edge(a, b, p);
        const ok = switch (rule) {
            .at_least_zero => e >= 0,
            .above_zero => e > 0,
            .top_left => e > 0 or (e == 0 and isTopLeft(a, b)),
        };
        if (!ok) return false;
    }
    return true;
}

pub fn main() void {
    // A square cut along its diagonal, and a third triangle on its right.
    const triangles = [_][3]Point{
        .{ px(1.5, 1.5), px(9.5, 1.5), px(9.5, 9.5) },
        .{ px(1.5, 1.5), px(9.5, 9.5), px(1.5, 9.5) },
        .{ px(9.5, 1.5), px(14.5, 5.5), px(9.5, 9.5) },
    };
    for ([_]Rule{ .at_least_zero, .above_zero, .top_left }) |rule| {
        var counts: [3]usize = .{ 0, 0, 0 }; // pixels hit 0, 1, 2+ times
        std.debug.print("{t}:\n", .{rule});
        for (0..11) |y| {
            var line: [16]u8 = undefined;
            for (&line, 0..) |*ch, x| {
                const center: Point = .{ .x = @intCast(x * one + one / 2), .y = @intCast(y * one + one / 2) };
                var hits: usize = 0;
                var last: usize = 0;
                for (triangles, 0..) |t, i| {
                    if (covers(rule, t, center)) {
                        hits += 1;
                        last = i;
                    }
                }
                counts[@min(hits, 2)] += 1;
                ch.* = switch (hits) {
                    0 => '.',
                    1 => "abc"[last],
                    else => '0' + @as(u8, @intCast(hits)),
                };
            }
            std.debug.print("  {s}\n", .{&line});
        }
        std.debug.print("  covered once: {d}, more than once: {d}\n\n", .{ counts[1], counts[2] });
    }
}
