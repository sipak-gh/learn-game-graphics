//! Barycentric coordinates: the three edge functions, divided by the
//! area, say how much of each corner a point is made of.
const std = @import("std");

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

fn edge(a: Vec2, b: Vec2, p: Vec2) f32 {
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
}

/// The weights of a, b, c in p: the edge opposite each corner, over the area.
fn weights(a: Vec2, b: Vec2, c: Vec2, p: Vec2) Vec3 {
    const area = edge(a, b, c);
    return Vec3{ edge(b, c, p), edge(c, a, p), edge(a, b, p) } / @as(Vec3, @splat(area));
}

pub fn main() void {
    const a: Vec2 = .{ 2, 1 };
    const b: Vec2 = .{ 14, 4 };
    const c: Vec2 = .{ 5, 11 };
    const points = [_]struct { name: []const u8, p: Vec2 }{
        .{ .name = "corner a", .p = a },
        .{ .name = "corner c", .p = c },
        .{ .name = "middle of a-b", .p = (a + b) / @as(Vec2, @splat(2)) },
        .{ .name = "centroid", .p = (a + b + c) / @as(Vec2, @splat(3)) },
        .{ .name = "inside", .p = .{ 7, 6 } },
        .{ .name = "outside, past b-c", .p = .{ 12, 9 } },
    };
    // Each corner has a color: a red, b green, c blue.
    const red: Vec3 = .{ 255, 0, 0 };
    const green: Vec3 = .{ 0, 255, 0 };
    const blue: Vec3 = .{ 0, 0, 255 };

    std.debug.print("{s:<18} {s:>6} {s:>6} {s:>6} {s:>5}  {s:<13} color\n", .{ "point", "a", "b", "c", "sum", "rebuilt" });
    for (points) |t| {
        const w = weights(a, b, c, t.p);
        const rebuilt = a * @as(Vec2, @splat(w[0])) + b * @as(Vec2, @splat(w[1])) + c * @as(Vec2, @splat(w[2]));
        const color = red * @as(Vec3, @splat(w[0])) + green * @as(Vec3, @splat(w[1])) + blue * @as(Vec3, @splat(w[2]));
        std.debug.print("{s:<18} {d:>6.3} {d:>6.3} {d:>6.3} {d:>5.2}  ({d:>4.1},{d:>4.1})  ({d:.0}, {d:.0}, {d:.0})\n", .{
            t.name, w[0], w[1], w[2], @reduce(.Add, w), rebuilt[0], rebuilt[1], color[0], color[1], color[2],
        });
    }
}
