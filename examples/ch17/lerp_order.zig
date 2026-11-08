//! Is lerp(a, b, t) the same float as lerp(b, a, 1 - t)? Mathematically
//! yes. In f32, often not, and that is how cracks open between triangles.
const std = @import("std");

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

const Vec4 = @Vector(4, f32);

fn lerp4(a: Vec4, b: Vec4, t: f32) Vec4 {
    return a + (b - a) * @as(Vec4, @splat(t));
}

/// Where the edge from p to q crosses the near plane z = 0, computed
/// starting from p.
fn crossingFrom(p: Vec4, q: Vec4) Vec4 {
    const t = p[2] / (p[2] - q[2]);
    return lerp4(p, q, t);
}

pub fn main() void {
    var prng: std.Random.DefaultPrng = .init(17);
    const random = prng.random();
    const n = 1_000_000;

    var scalar_differ: u32 = 0;
    for (0..n) |_| {
        const a = random.float(f32) * 20 - 10;
        const b = random.float(f32) * 20 - 10;
        const t = random.float(f32);
        if (lerp(a, b, t) != lerp(b, a, 1 - t)) scalar_differ += 1;
    }
    std.debug.print("lerp(a, b, t) != lerp(b, a, 1 - t): {d} of {d}\n", .{ scalar_differ, n });

    // Edges with one end in front of the near plane (z > 0) and one
    // behind (z < 0), cut from either end.
    var cut_differ: u32 = 0;
    var max_gap: f32 = 0;
    for (0..n) |_| {
        var inside: Vec4 = undefined;
        var outside: Vec4 = undefined;
        inline for (0..4) |i| {
            inside[i] = random.float(f32) * 4 - 2;
            outside[i] = random.float(f32) * 4 - 2;
        }
        inside[2] = random.float(f32) * 2 + 0.001;
        outside[2] = -(random.float(f32) * 2 + 0.001);
        const u = crossingFrom(inside, outside);
        const v = crossingFrom(outside, inside);
        if (!@reduce(.And, u == v)) {
            cut_differ += 1;
            max_gap = @max(max_gap, @reduce(.Max, @abs(u - v)));
        }
    }
    std.debug.print("crossing from one end != from the other: {d} of {d} (largest gap {e})\n", .{ cut_differ, n, max_gap });
    std.debug.print("crossing always from the inside end: 0 of {d}, by construction\n", .{n});
}
