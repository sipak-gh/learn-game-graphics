//! Which map cells can the follow view show? Run the canvas corners back
//! through the inverse transform. The inverse of a product is the product
//! of the inverses in reverse order, so no general inverse is needed here.
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

fn scaling(s: f32) Mat4 {
    return .fromRows(.{ .{ s, 0, 0, 0 }, .{ 0, s, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

fn rotationZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .fromRows(.{ .{ c, -s, 0, 0 }, .{ s, c, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

pub fn main() void {
    const pos: [2]f32 = .{ 19.5, 13.5 };
    const yaw = std.math.degreesToRadians(30.0);
    const turn = -std.math.pi / 2.0 - yaw;

    // map -> screen: T(center) S(32) R(turn) T(-pos)
    const to_screen = translation(320, 200).mul(scaling(32)).mul(rotationZ(turn)).mul(translation(-pos[0], -pos[1]));
    // screen -> map: T(pos) R(-turn) S(1/32) T(-center)
    const to_map = translation(pos[0], pos[1]).mul(rotationZ(-turn)).mul(scaling(1.0 / 32.0)).mul(translation(-320, -200));

    const check = to_screen.mul(to_map).mulVec(.{ 123, 45, 0, 1 });
    std.debug.print("round trip of (123, 45): ({d:.3}, {d:.3})\n", .{ check[0], check[1] });

    var lo: [2]f32 = .{ std.math.inf(f32), std.math.inf(f32) };
    var hi: [2]f32 = .{ -std.math.inf(f32), -std.math.inf(f32) };
    for ([_][2]f32{ .{ 0, 0 }, .{ 640, 0 }, .{ 0, 400 }, .{ 640, 400 } }) |corner| {
        const m = to_map.mulVec(.{ corner[0], corner[1], 0, 1 });
        std.debug.print("canvas ({d:>3}, {d:>3}) -> map ({d:>5.2}, {d:>5.2})\n", .{ corner[0], corner[1], m[0], m[1] });
        inline for (0..2) |i| {
            lo[i] = @min(lo[i], m[i]);
            hi[i] = @max(hi[i], m[i]);
        }
    }
    // Whole cells, clamped to the 32x24 map.
    const x0 = @max(@floor(lo[0]), 0);
    const y0 = @max(@floor(lo[1]), 0);
    const x1 = @min(@ceil(hi[0]), 32);
    const y1 = @min(@ceil(hi[1]), 24);
    std.debug.print("cells x {d}..{d}, y {d}..{d}: {d} of 768\n", .{ x0, x1, y0, y1, (x1 - x0) * (y1 - y0) });
}
