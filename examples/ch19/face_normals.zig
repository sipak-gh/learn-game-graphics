//! Where normals come from. A triangle's normal is the cross product of
//! two of its edges; the order of the corners decides which side it points
//! to. A vertex shared by several faces gets one normal per face (a hard
//! edge) or the average of them (a smooth surface).
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn length(v: Vec3) f32 {
    return @sqrt(@reduce(.Add, v * v));
}

fn normalize(v: Vec3) Vec3 {
    return v / @as(Vec3, @splat(length(v)));
}

fn show(name: []const u8, v: Vec3) void {
    std.debug.print("{s:<34} ({d:>6.3}, {d:>6.3}, {d:>6.3})\n", .{ name, v[0], v[1], v[2] });
}

pub fn main() void {
    // A triangle on the floor (y = 0), counter-clockwise seen from above.
    const a: Vec3 = .{ 0, 0, 0 };
    const b: Vec3 = .{ 0, 0, 1 };
    const c: Vec3 = .{ 1, 0, 0 };
    const n = cross(b - a, c - a);
    show("(b - a) x (c - a)", n);
    std.debug.print("{s:<34} {d:.3}\n", .{ "its length = twice the area", length(n) });
    show("corners in the other order", cross(c - a, b - a));

    // A square pyramid: apex above the center of a 2x2 base. Its four
    // sides are triangles that meet at the apex.
    const apex: Vec3 = .{ 0, 1, 0 };
    const base = [4]Vec3{ .{ -1, 0, -1 }, .{ -1, 0, 1 }, .{ 1, 0, 1 }, .{ 1, 0, -1 } };
    var sum: Vec3 = @splat(0);
    for (0..4) |i| {
        const p = base[i];
        const q = base[(i + 1) % 4];
        const side = normalize(cross(q - p, apex - p));
        var buf: [32]u8 = undefined;
        show(std.fmt.bufPrint(&buf, "side {d} normal", .{i}) catch unreachable, side);
        sum += side;
    }
    // One shared apex vertex with the average normal: the pyramid is shaded
    // like a smooth cone. Four apex vertices with their own normals: sharp.
    show("apex, averaged (smooth)", normalize(sum));

    // A sphere has an exact normal at every point: away from its center.
    const center: Vec3 = .{ 0, 0, -3 };
    const radius = 2;
    const on_sphere: Vec3 = .{ 1.2, 1.6, -3 };
    show("sphere: (p - center) / radius", (on_sphere - center) / @as(Vec3, @splat(radius)));
}
