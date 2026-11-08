//! Rotating a square about its own center with T(c) R T(-c), drawn into
//! rotate.ppm: five squares, each smaller and turned 15 degrees further.
const std = @import("std");

const Vec4 = @Vector(4, f32);

const Mat4 = struct {
    cols: [4]Vec4,

    fn fromRows(rows: [4][4]f32) Mat4 {
        var m: Mat4 = undefined;
        for (0..4) |c| m.cols[c] = .{ rows[0][c], rows[1][c], rows[2][c], rows[3][c] };
        return m;
    }

    fn mulVec(m: Mat4, v: Vec4) Vec4 {
        var result: Vec4 = @splat(0);
        inline for (0..4) |i| result += m.cols[i] * @as(Vec4, @splat(v[i]));
        return result;
    }

    fn mul(a: Mat4, b: Mat4) Mat4 {
        var m: Mat4 = undefined;
        for (&m.cols, b.cols) |*col, b_col| col.* = a.mulVec(b_col);
        return m;
    }
};

fn translation(x: f32, y: f32) Mat4 {
    return .fromRows(.{ .{ 1, 0, 0, x }, .{ 0, 1, 0, y }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

fn rotationZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .fromRows(.{ .{ c, -s, 0, 0 }, .{ s, c, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

const size = 200;
var pixels: [size][size][3]u8 = @splat(@splat(.{ 24, 24, 32 }));

/// Twice the signed area of (a, b, p): which side of a->b the point p is on.
fn edge(a: Vec4, b: Vec4, p: Vec4) f32 {
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
}

/// Fills a convex quad by testing every pixel center against its edges.
fn fillQuad(q: [4]Vec4, color: [3]u8) void {
    for (0..size) |y| for (0..size) |x| {
        const p: Vec4 = .{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5, 0, 1 };
        var inside = true;
        for (0..4) |i| inside = inside and edge(q[i], q[(i + 1) % 4], p) >= 0;
        if (inside) pixels[y][x] = color;
    };
}

pub fn main(init: std.process.Init) !void {
    const c: Vec4 = .{ 100, 100, 0, 1 };
    for (0..5) |i| {
        const k: f32 = @floatFromInt(i);
        const h = 80 - 15 * k; // half the side
        const angle = std.math.degreesToRadians(15 * k);
        // Read right to left: move c to the origin, rotate, move back.
        const m = translation(c[0], c[1]).mul(rotationZ(angle)).mul(translation(-c[0], -c[1]));
        const corners = [4]Vec4{ .{ 100 - h, 100 - h, 0, 1 }, .{ 100 + h, 100 - h, 0, 1 }, .{ 100 + h, 100 + h, 0, 1 }, .{ 100 - h, 100 + h, 0, 1 } };
        var q: [4]Vec4 = undefined;
        for (&q, corners) |*out, corner| out.* = m.mulVec(corner);
        const shade: u8 = @intCast(70 + 45 * i);
        fillQuad(q, .{ shade, shade / 2, 255 - shade });
        std.debug.print("square {d}: {d:>2} deg, first corner ({d:.1}, {d:.1}), center stays at ({d:.1}, {d:.1})\n", .{
            i, 15 * i, q[0][0], q[0][1], m.mulVec(c)[0], m.mulVec(c)[1],
        });
    }
    // Rotating about the origin instead swings the center away.
    const swung = rotationZ(std.math.degreesToRadians(45)).mulVec(c);
    std.debug.print("R alone moves the center to ({d:.1}, {d:.1})\n", .{ swung[0], swung[1] });

    const file = try std.Io.Dir.cwd().createFile(init.io, "rotate.ppm", .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var w = file.writer(init.io, &buffer);
    try w.interface.print("P6\n{d} {d}\n255\n", .{ size, size });
    try w.interface.writeAll(std.mem.asBytes(&pixels));
    try w.interface.flush();
    std.debug.print("wrote rotate.ppm\n", .{});
}
