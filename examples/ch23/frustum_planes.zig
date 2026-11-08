//! The six planes of the view frustum, pulled out of a view-projection
//! matrix. A clip-space plane's distance (w + x for the left plane, w - z
//! for the far plane, and so on) is linear in the clip point, and the clip
//! point is col0 x + col1 y + col2 z + col3. So each plane's world-space
//! (a, b, c, d) is that same distance taken of the four columns.
const std = @import("std");

const Vec3 = @Vector(3, f32);
const Vec4 = @Vector(4, f32);

/// A 4x4 matrix stored as four columns.
const Mat4 = struct {
    cols: [4]Vec4,

    fn mulVec(m: Mat4, v: Vec4) Vec4 {
        var r: Vec4 = @splat(0);
        inline for (0..4) |j| r += m.cols[j] * @as(Vec4, @splat(v[j]));
        return r;
    }

    fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = undefined;
        for (&r.cols, b.cols) |*col, bc| col.* = a.mulVec(bc);
        return r;
    }

    /// delve's projection: looking down -z, depth 0 at `near` and 1 at `far`.
    fn perspective(vfov: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1 / @tan(vfov / 2);
        return .{ .cols = .{
            .{ f / aspect, 0, 0, 0 },
            .{ 0, f, 0, 0 },
            .{ 0, 0, far / (near - far), -1 },
            .{ 0, 0, near * far / (near - far), 0 },
        } };
    }

    fn translation(t: Vec3) Mat4 {
        return .{ .cols = .{ .{ 1, 0, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 0, 1, 0 }, .{ t[0], t[1], t[2], 1 } } };
    }
};

/// The clipper's planes, as in delve's clip.zig.
const Plane = enum {
    near,
    far,
    left,
    right,
    bottom,
    top,

    fn distance(plane: Plane, p: Vec4) f32 {
        const x, const y, const z, const w = p;
        return switch (plane) {
            .near => z,
            .far => w - z,
            .left => w + x,
            .right => w - x,
            .bottom => w + y,
            .top => w - y,
        };
    }
};

fn planes(view_proj: Mat4) [6]Vec4 {
    var result: [6]Vec4 = undefined;
    for (&result, std.enums.values(Plane)) |*plane, which| {
        inline for (0..4) |j| plane[j] = which.distance(view_proj.cols[j]);
    }
    return result;
}

fn show(name: []const u8, view_proj: Mat4) [6]Vec4 {
    const ps = planes(view_proj);
    std.debug.print("{s}, normalized (a, b, c, d):\n", .{name});
    for (ps, std.enums.values(Plane)) |p, which| {
        const n = @sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
        std.debug.print("  {s:<6} {d:>7.3} {d:>7.3} {d:>7.3} {d:>8.3}\n", .{ @tagName(which), p[0] / n, p[1] / n, p[2] / n, p[3] / n });
    }
    return ps;
}

pub fn main() void {
    // delve's camera: vertical fov 2 atan(0.5), 640 x 400, near 0.05, far 64.
    const proj = Mat4.perspective(2 * std.math.atan(@as(f32, 0.5)), 1.6, 0.05, 64);
    const at_origin = show("camera at the origin looking down -z", proj);

    // Moving the camera to (2, 0.5, 3) moves the world by the opposite.
    const moved = proj.mul(.translation(.{ -2, -0.5, -3 }));
    _ = show("the same camera at (2, 0.5, 3)", moved);

    // Ten points: the planes and the clipper's outcodes must agree.
    const points = [_]Vec3{
        .{ 0, 0, -1 },    .{ 0, 0, -0.01 }, .{ 0, 0, 1 },     .{ 0, 0, -70 },  .{ -0.7, 0, -1 },
        .{ -0.9, 0, -1 }, .{ 0, 0.45, -1 }, .{ 0, 0.55, -1 }, .{ 5, -6, -10 }, .{ 30, 0, -40 },
    };
    std.debug.print("point                outside of (planes)              outside of (outcode)\n", .{});
    var agree: usize = 0;
    for (points) |p| {
        var by_planes: std.EnumSet(Plane) = .empty;
        var by_clip: std.EnumSet(Plane) = .empty;
        const c = proj.mulVec(.{ p[0], p[1], p[2], 1 });
        for (at_origin, std.enums.values(Plane)) |plane, which| {
            if (plane[0] * p[0] + plane[1] * p[1] + plane[2] * p[2] + plane[3] < 0) by_planes.insert(which);
            if (which.distance(c) < 0) by_clip.insert(which);
        }
        std.debug.print("({d:>5},{d:>5},{d:>5})    ", .{ p[0], p[1], p[2] });
        printSet(by_planes, true);
        printSet(by_clip, false);
        std.debug.print("\n", .{});
        agree += @intFromBool(by_planes.eql(by_clip));
    }
    std.debug.print("agree on {d} of {d}\n", .{ agree, points.len });
}

fn printSet(set: std.EnumSet(Plane), pad: bool) void {
    var buffer: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    var it = set.iterator();
    while (it.next()) |plane| w.print("{s}{t}", .{ if (w.end > 0) " " else "", plane }) catch {};
    if (set.count() == 0) w.writeAll("inside") catch {};
    if (pad) std.debug.print("{s:<33}", .{w.buffered()}) else std.debug.print("{s}", .{w.buffered()});
}
