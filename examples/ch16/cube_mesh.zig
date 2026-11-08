//! The unit cube as delve's mesh.zig builds it, at compile time: six faces,
//! each with its own four vertices (24 in all) and two triangles.
const std = @import("std");

const Vec3 = @Vector(3, f32);
const Vertex = struct { pos: Vec3, normal: Vec3 };
const Mesh = struct { vertices: []const Vertex, indices: []const u16 };

fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn scale(v: Vec3, s: f32) Vec3 {
    return v * @as(Vec3, @splat(s));
}

/// Each face: outward normal n, then u and v across it with u x v = n.
const faces = [6][3]Vec3{
    .{ .{ 1, 0, 0 }, .{ 0, 0, -1 }, .{ 0, 1, 0 } },
    .{ .{ -1, 0, 0 }, .{ 0, 0, 1 }, .{ 0, 1, 0 } },
    .{ .{ 0, 1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, -1 } },
    .{ .{ 0, -1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 } },
    .{ .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } },
    .{ .{ 0, 0, -1 }, .{ -1, 0, 0 }, .{ 0, 1, 0 } },
};

const cube: Mesh = blk: {
    // -u-v, +u-v, +u+v, -u+v: counter-clockwise seen from outside.
    const corners = [4][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 } };
    var vertices: [24]Vertex = undefined;
    var indices: [36]u16 = undefined;
    for (faces, 0..) |face, f| {
        const n, const u, const v = face;
        const center = Vec3{ 0.5, 0.5, 0.5 } + scale(n, 0.5);
        for (corners, 0..) |c, k| {
            vertices[f * 4 + k] = .{ .pos = center + scale(u, c[0] / 2) + scale(v, c[1] / 2), .normal = n };
        }
        const first: u16 = f * 4;
        indices[f * 6 ..][0..6].* = .{ first, first + 1, first + 2, first, first + 2, first + 3 };
    }
    const final_vertices = vertices;
    const final_indices = indices;
    break :blk .{ .vertices = &final_vertices, .indices = &final_indices };
};

pub fn main() void {
    std.debug.print("{d} vertices, {d} indices, {d} triangles\n", .{ cube.vertices.len, cube.indices.len, cube.indices.len / 3 });
    for (faces, 0..) |face, f| {
        const n, const u, const v = face;
        const ok = @reduce(.And, cross(u, v) == n);
        std.debug.print("face {d}: n = {any:>2}  u x v = n: {}  corners:", .{ f, n, ok });
        for (cube.vertices[f * 4 ..][0..4]) |vert| std.debug.print(" {any}", .{vert.pos});
        std.debug.print("\n        triangles {any}\n", .{cube.indices[f * 6 ..][0..6]});
    }
}
