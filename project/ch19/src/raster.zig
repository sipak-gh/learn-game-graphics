//! Rasterization: finding the pixels a triangle covers.
//!
//! A pixel is covered when its center is inside the triangle: on the inner
//! side of all three edges. The side is the sign of the edge function
//!     E_ab(p) = (b.x - a.x)(p.y - a.y) - (b.y - a.y)(p.x - a.x),
//! twice the signed area of triangle a, b, p. E is linear in p, so moving
//! one pixel right or down adds a constant: no multiplications per pixel.
//!
//! Positions are fixed-point integers with 4 bits after the binary point
//! (1/16 pixel), so every edge function is computed exactly, and a pixel
//! center on an edge shared by two triangles is decided the same way for
//! both of them.
const std = @import("std");

pub const subpixel_bits = 4;
/// One pixel in fixed-point units.
pub const one = 1 << subpixel_bits;

/// A point on the screen in fixed point: pixels times 16.
pub const Point = struct { x: i32, y: i32 };

/// The fixed-point point nearest to (x, y) in pixels.
pub fn toFixed(x: f32, y: f32) Point {
    return .{ .x = @intFromFloat(@round(x * one)), .y = @intFromFloat(@round(y * one)) };
}

/// Twice the signed area of triangle (a, b, p). With y pointing down it is
/// positive when p lies to the right of the edge a->b: then a, b, p go
/// clockwise on the screen.
pub fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

/// The top-left fill rule. A pixel center exactly on an edge belongs to
/// the triangle only if the edge is a top edge (horizontal, with the
/// triangle below it) or a left edge (the triangle to its right). Two
/// triangles sharing an edge see it as top-left from one side only, so
/// the pixel is drawn exactly once. In a clockwise triangle, top edges run
/// to the right and left edges run up.
pub fn isTopLeft(a: Point, b: Point) bool {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    return dy < 0 or (dy == 0 and dx > 0);
}

const Vec3i = @Vector(3, i32);
const Vec3 = @Vector(3, f32);

/// Calls `visitor.pixel(x, y, weights)` for every pixel of the `width` x
/// `height` screen whose center is in triangle `v`. The corners must go
/// clockwise on the screen (edge(v[0], v[1], v[2]) > 0) and lie less
/// than 1024 pixels from the screen's corner, which clipping guarantees:
/// then no edge function overflows an i32 (|E| < 2 * (2048 * 16)^2 = 2^31). `weights` are
/// the barycentric coordinates of the pixel center: how much of each
/// corner is in the point, adding up to 1.
pub fn fillTriangle(v: [3]Point, width: usize, height: usize, visitor: anytype) void {
    const a, const b, const c = v;
    for (v) |p| std.debug.assert(@abs(p.x) < 1024 * one and @abs(p.y) < 1024 * one);
    const area = edge(a, b, c);
    std.debug.assert(area > 0);

    // The bounding box of the triangle, in whole pixels, cut to the screen.
    const min_x = @max(@divFloor(@min(a.x, b.x, c.x), one), 0);
    const min_y = @max(@divFloor(@min(a.y, b.y, c.y), one), 0);
    const max_x = @min(@divFloor(@max(a.x, b.x, c.x), one), @as(i32, @intCast(width)) - 1);
    const max_y = @min(@divFloor(@max(a.y, b.y, c.y), one), @as(i32, @intCast(height)) - 1);
    if (min_x > max_x or min_y > max_y) return;

    // The edge opposite each corner: its function is that corner's weight
    // (times the area). Pixels exactly on an edge that is not top-left
    // must not count, so 1 is subtracted from that edge's function.
    const bias: Vec3i = .{
        if (isTopLeft(b, c)) 0 else -1,
        if (isTopLeft(c, a)) 0 else -1,
        if (isTopLeft(a, b)) 0 else -1,
    };
    const start: Point = .{ .x = min_x * one + one / 2, .y = min_y * one + one / 2 };
    var row: Vec3i = Vec3i{ edge(b, c, start), edge(c, a, start), edge(a, b, start) } + bias;
    // One pixel right adds -(b.y - a.y) to E_ab; one pixel down adds b.x - a.x.
    const step_x: Vec3i = .{ (b.y - c.y) * one, (c.y - a.y) * one, (a.y - b.y) * one };
    const step_y: Vec3i = .{ (c.x - b.x) * one, (a.x - c.x) * one, (b.x - a.x) * one };
    const inv_area: Vec3 = @splat(1 / @as(f32, @floatFromInt(area)));

    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var e = row;
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            // Inside when all three are >= 0: when no sign bit is set.
            if (@reduce(.Or, e) >= 0) {
                const weights = @as(Vec3, @floatFromInt(e - bias)) * inv_area;
                visitor.pixel(@intCast(x), @intCast(y), weights);
            }
            e += step_x;
        }
        row += step_y;
    }
}

const testing = std.testing;

/// Counts how often each pixel of a small screen is visited.
const Counter = struct {
    const size = 32;
    counts: [size][size]u8 = @splat(@splat(0)),

    pub fn pixel(c: *Counter, x: usize, y: usize, weights: Vec3) void {
        c.counts[y][x] += 1;
        std.debug.assert(@abs(@reduce(.Add, weights) - 1) < 1e-5);
    }

    fn fan(c: *Counter, points: []const Point, center: usize) void {
        for (0..points.len) |i| {
            var t = [3]Point{ points[center], points[i], points[(i + 1) % points.len] };
            if (i == center or (i + 1) % points.len == center) continue;
            if (edge(t[0], t[1], t[2]) < 0) std.mem.swap(Point, &t[1], &t[2]);
            fillTriangle(t, size, size, c);
        }
    }
};

fn px(x: f32, y: f32) Point {
    return toFixed(x, y);
}

test "a clockwise triangle has a positive area" {
    // (0, 0) -> (4, 0) -> (0, 4) goes right, then down-left: clockwise
    // on a screen whose y points down.
    try testing.expectEqual(16 * one * one, edge(px(0, 0), px(4, 0), px(0, 4)));
    try testing.expectEqual(-16 * one * one, edge(px(0, 0), px(0, 4), px(4, 0)));
}

test "triangles sharing edges cover every pixel exactly once" {
    // A convex polygon whose corners and edges pass through many pixel
    // centers (x.5): cut into triangles two different ways, it must
    // cover the same pixels, each exactly once.
    const polygon = [_]Point{
        px(2.5, 2.5),   px(16.5, 2.5), px(28.5, 8.5), px(28.5, 20.5),
        px(20.5, 28.5), px(6.5, 28.5), px(2.5, 16.5),
    };
    var from_corner: Counter = .{};
    from_corner.fan(&polygon, 0);
    var from_other: Counter = .{};
    from_other.fan(&polygon, 3);
    var covered: usize = 0;
    for (from_corner.counts, from_other.counts) |row_a, row_b| {
        for (row_a, row_b) |a, b| {
            try testing.expect(a <= 1);
            try testing.expectEqual(a, b);
            covered += a;
        }
    }
    try testing.expect(covered > 400);
}

test "the top-left rule: a pixel center on an edge goes to one side" {
    // Two triangles meeting along the vertical line x = 4.5, through the
    // centers of column 4. The column belongs to the triangle on its right.
    const top = px(4.5, 0);
    const bottom = px(4.5, 8);
    var left: Counter = .{};
    fillTriangle(.{ top, bottom, px(0, 4) }, Counter.size, Counter.size, &left);
    var right: Counter = .{};
    fillTriangle(.{ top, px(9, 4), bottom }, Counter.size, Counter.size, &right);
    for (0..8) |y| {
        try testing.expectEqual(0, left.counts[y][4]);
        try testing.expectEqual(1, right.counts[y][4]);
    }
}

/// Records the weights at one pixel.
const Probe = struct {
    x: usize,
    y: usize,
    weights: ?Vec3 = null,

    pub fn pixel(p: *Probe, x: usize, y: usize, weights: Vec3) void {
        if (x == p.x and y == p.y) p.weights = weights;
    }
};

fn expectWeights(expected: Vec3, actual: Vec3) !void {
    inline for (0..3) |i| try testing.expectApproxEqAbs(expected[i], actual[i], 1e-6);
}

test "barycentric weights are 1 at a corner and 1/3 at the centroid" {
    var corner: Probe = .{ .x = 1, .y = 1 };
    const tri = [3]Point{ px(1.5, 1.5), px(13.5, 1.5), px(1.5, 13.5) };
    fillTriangle(tri, 32, 32, &corner);
    try expectWeights(.{ 1, 0, 0 }, corner.weights.?);

    var centroid: Probe = .{ .x = 5, .y = 5 };
    fillTriangle(tri, 32, 32, &centroid);
    try expectWeights(@splat(1.0 / 3.0), centroid.weights.?);
}
