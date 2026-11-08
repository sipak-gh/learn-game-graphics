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
