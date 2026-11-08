//! Is a box outside a plane? Only if its corner farthest along the plane's
//! normal (the "positive vertex") is outside, because every other corner
//! is farther out still. One @select per plane picks that corner: the
//! box's high coordinate where the normal is positive, its low one where
//! it is negative. Prints all eight corners' distances for one box, then
//! slides a box left out of the view until the test says "outside".
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

/// The corner of `box` farthest along `normal`.
fn positiveVertex(normal: Vec3, box: [2]Vec3) Vec3 {
    return @select(f32, normal >= @as(Vec3, @splat(0)), box[1], box[0]);
}

fn corner(box: [2]Vec3, c: usize) Vec3 {
    return @select(f32, @Vector(3, bool){ c & 1 != 0, c & 2 != 0, c & 4 != 0 }, box[1], box[0]);
}

pub fn main() void {
    // delve's left frustum plane for a camera at the origin looking down
    // -z (see frustum_planes.zig): 0.781 x - 0.625 z >= 0 is inside.
    const normal: Vec3 = .{ 0.781, 0, -0.625 };
    const d: f32 = 0;

    var box = [2]Vec3{ .{ -2, 0, -4 }, .{ -1, 1, -3 } };
    std.debug.print("box ({d}, {d}, {d}) to ({d}, {d}, {d}), the left plane:\n", .{ box[0][0], box[0][1], box[0][2], box[1][0], box[1][1], box[1][2] });
    for (0..8) |c| {
        const p = corner(box, c);
        std.debug.print("  corner ({d:>2}, {d}, {d:>2})  distance {d:>6.3}\n", .{ p[0], p[1], p[2], dot(normal, p) + d });
    }
    const pv = positiveVertex(normal, box);
    std.debug.print("  @select picks ({d}, {d}, {d}): the largest distance\n\n", .{ pv[0], pv[1], pv[2] });

    std.debug.print("sliding the box left, 0.25 at a time:\n", .{});
    while (true) {
        var lowest: f32 = std.math.inf(f32);
        var highest: f32 = -std.math.inf(f32);
        for (0..8) |c| {
            const dist = dot(normal, corner(box, c)) + d;
            lowest = @min(lowest, dist);
            highest = @max(highest, dist);
        }
        const picked = dot(normal, positiveVertex(normal, box)) + d;
        const outside = picked < 0;
        std.debug.print("  x {d:>5.2} to {d:>5.2}: corners {d:>6.3} .. {d:>6.3}, picked {d:>6.3}  {s}\n", .{
            box[0][0], box[1][0], lowest, highest, picked, if (outside) "outside" else "kept",
        });
        if (outside) break;
        box[0][0] -= 0.25;
        box[1][0] -= 0.25;
    }
}
