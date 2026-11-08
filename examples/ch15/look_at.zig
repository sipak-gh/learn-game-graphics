//! The view matrix from a camera's axes. Its rows are right, up, and
//! -forward; its last column is minus each axis dotted with the eye. It
//! takes the target to (0, 0, -distance): straight ahead of an eye at the
//! origin that looks down -z.
const std = @import("std");

const Vec3 = @Vector(3, f32);
const Vec4 = @Vector(4, f32);

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn normalize(v: Vec3) Vec3 {
    return v / @as(Vec3, @splat(@sqrt(dot(v, v))));
}

/// Four rows: row r dotted with (x, y, z, 1) gives lane r of the result.
const Rows = [4]Vec4;

fn lookAt(eye: Vec3, target: Vec3, up: Vec3) Rows {
    const f = normalize(target - eye);
    const r = normalize(cross(f, up));
    const u = cross(r, f);
    return .{
        .{ r[0], r[1], r[2], -dot(r, eye) },
        .{ u[0], u[1], u[2], -dot(u, eye) },
        .{ -f[0], -f[1], -f[2], dot(f, eye) },
        .{ 0, 0, 0, 1 },
    };
}

fn transform(m: Rows, p: Vec3) Vec4 {
    const v: Vec4 = .{ p[0], p[1], p[2], 1 };
    return .{ @reduce(.Add, m[0] * v), @reduce(.Add, m[1] * v), @reduce(.Add, m[2] * v), @reduce(.Add, m[3] * v) };
}

pub fn main() void {
    const up: Vec3 = .{ 0, 1, 0 };
    const cases = [_][2]Vec3{
        .{ .{ 0, 0, 0 }, .{ 0, 0, -5 } }, // already looking down -z
        .{ .{ 0, 1, 0 }, .{ 3, 1, -4 } }, // level, turned: forward (0.6, 0, -0.8)
        .{ .{ 1, 0.5, 1 }, .{ 3, 1.5, 3 } }, // looking up a little
    };
    for (cases) |c| {
        const eye, const target = c;
        const view = lookAt(eye, target, up);
        std.debug.print("eye {any}  target {any}  distance {d:.4}\n", .{ eye, target, @sqrt(dot(target - eye, target - eye)) });
        for (view, [_][]const u8{ "right   ", "up      ", "-forward", "        " }) |row, name| {
            std.debug.print("  {s} [ {d:7.4} {d:7.4} {d:7.4} | {d:7.4} ]\n", .{ name, row[0], row[1], row[2], row[3] });
        }
        const t = transform(view, target);
        std.debug.print("  target -> ({d:.4}, {d:.4}, {d:.4})\n", .{ t[0], t[1], t[2] });
        // Place a point by hand: 2 to the right, 1 down, 3 ahead. The view
        // matrix undoes that placement.
        const r: Vec3 = .{ view[0][0], view[0][1], view[0][2] };
        const u: Vec3 = .{ view[1][0], view[1][1], view[1][2] };
        const f = normalize(target - eye);
        const p = eye + @as(Vec3, @splat(2)) * r - u + @as(Vec3, @splat(3)) * f;
        const s = transform(view, p);
        std.debug.print("  eye + 2 right - up + 3 forward = ({d:.4}, {d:.4}, {d:.4}) -> ({d:.4}, {d:.4}, {d:.4})\n\n", .{
            p[0], p[1], p[2], s[0], s[1], s[2],
        });
    }
}
