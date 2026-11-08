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
