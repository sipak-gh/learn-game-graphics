//! Pushing a circle out of square walls, the way delve's player.zig does:
//! find the point of each square closest to the circle's center, and if it
//! is closer than the radius, move the center straight away from it.
//! Prints where a circle of radius 0.25 ends up at a few spots around a
//! wall, and in the inside corner of two walls.
const std = @import("std");

const Vec2 = @Vector(2, f32);
const radius = 0.25;

/// The point of the unit square with lowest corner `low` closest to `p`:
/// a clamp of each coordinate.
fn closest(low: Vec2, p: Vec2) Vec2 {
    return @max(low, @min(low + Vec2{ 1, 1 }, p));
}

fn length(v: Vec2) f32 {
    return @sqrt(@reduce(.Add, v * v));
}

/// Moves `p` away from `point` until it is `radius` away, if closer.
fn pushOut(p: Vec2, point: Vec2) Vec2 {
    const d = p - point;
    const len = length(d);
    if (len >= radius or len == 0) return p;
    return point + d * @as(Vec2, @splat(radius / len));
}

fn collide(walls: []const Vec2, p: Vec2) Vec2 {
    var q = p;
    for (walls) |low| q = pushOut(q, closest(low, q));
    return q;
}

pub fn main() void {
    // One wall: the square from (1, 1) to (2, 2).
    const one = [_]Vec2{.{ 1, 1 }};
    const spots = [_]struct { name: []const u8, p: Vec2 }{
        .{ .name = "left of the face", .p = .{ 0.9, 1.5 } },
        .{ .name = "far from it", .p = .{ 0.5, 1.5 } },
        .{ .name = "above the face", .p = .{ 1.3, 0.8 } },
        .{ .name = "off the corner", .p = .{ 0.85, 0.85 } },
        .{ .name = "off the corner, skew", .p = .{ 0.95, 0.8 } },
    };
    std.debug.print("one wall, (1,1) to (2,2):\n", .{});
    for (spots) |s| show(&one, s.name, s.p);

    // Two walls meeting in an inside corner: one from (1,1) to (2,2) and
    // one from (2,0) to (3,1). The circle in the corner touches both.
    const two = [_]Vec2{ .{ 1, 1 }, .{ 2, 0 } };
    std.debug.print("two walls, an inside corner at (2,1):\n", .{});
    show(&two, "in the corner", .{ 1.9, 0.9 });
    show(&two, "near the corner", .{ 1.6, 0.8 });

    // Sliding: a step that goes into the wall at 45 degrees keeps only
    // the part along the wall.
    std.debug.print("sliding along the face x = 1:\n", .{});
    var p: Vec2 = .{ 0.75, 1.2 };
    for (0..4) |_| {
        const step: Vec2 = .{ 0.05, 0.05 };
        const moved = collide(&one, p + step);
        std.debug.print("  ({d:.3}, {d:.3}) + step -> ({d:.3}, {d:.3})\n", .{ p[0], p[1], moved[0], moved[1] });
        p = moved;
    }
}

fn show(walls: []const Vec2, name: []const u8, p: Vec2) void {
    const q = collide(walls, p);
    var nearest: f32 = std.math.inf(f32);
    for (walls) |low| nearest = @min(nearest, length(q - closest(low, q)));
    std.debug.print("  {s:<22} ({d:.3}, {d:.3}) -> ({d:.3}, {d:.3})  gap {d:.3}\n", .{ name, p[0], p[1], q[0], q[1], nearest });
}
