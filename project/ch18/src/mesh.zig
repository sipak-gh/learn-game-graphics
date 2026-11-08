//! Meshes: shapes made of triangles. A mesh is a list of vertices and a
//! list of indices into it, three per triangle, so a vertex shared by
//! several triangles is stored (and later transformed) once.
const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;

pub const Vertex = struct {
    pos: Vec3,
    /// The direction the surface faces at this vertex, length 1.
    normal: Vec3,
};

pub const Mesh = struct {
    vertices: []const Vertex,
    /// Three per triangle. Seen from the side the normals point to (the
    /// outside), every triangle's corners go counter-clockwise.
    indices: []const u16,

    pub fn triangleCount(mesh: Mesh) usize {
        return mesh.indices.len / 3;
    }
};

/// A square as two triangles: corners 0, 1, 2 and 0, 2, 3.
const quad_indices = [6]u16{ 0, 1, 2, 0, 2, 3 };

/// The unit cube from (0, 0, 0) to (1, 1, 1): six faces of two triangles.
/// A corner is shared by three faces that face different ways, so each
/// face has its own four vertices: 24 vertices, not 8.
pub const cube: Mesh = blk: {
    // Each face: its outward normal n, and two directions u and v across
    // it, chosen so that u x v = n. Going -u-v, +u-v, +u+v, -u+v around
    // the face center is then counter-clockwise seen from outside.
    const faces = [6][3]Vec3{
        .{ .{ 1, 0, 0 }, .{ 0, 0, -1 }, .{ 0, 1, 0 } },
        .{ .{ -1, 0, 0 }, .{ 0, 0, 1 }, .{ 0, 1, 0 } },
        .{ .{ 0, 1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, -1 } },
        .{ .{ 0, -1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 } },
        .{ .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } },
        .{ .{ 0, 0, -1 }, .{ -1, 0, 0 }, .{ 0, 1, 0 } },
    };
    const corners = [4][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 } };
    var vertices: [24]Vertex = undefined;
    var indices: [36]u16 = undefined;
    for (faces, 0..) |face, f| {
        const n, const u, const v = face;
        const center = Vec3{ 0.5, 0.5, 0.5 } + math.scale(n, 0.5);
        for (corners, 0..) |c, k| {
            const pos = center + math.scale(u, c[0] / 2) + math.scale(v, c[1] / 2);
            vertices[f * 4 + k] = .{ .pos = pos, .normal = n };
        }
        for (quad_indices, indices[f * 6 ..][0..6]) |q, *index| index.* = f * 4 + q;
    }
    const final_vertices = vertices;
    const final_indices = indices;
    break :blk .{ .vertices = &final_vertices, .indices = &final_indices };
};

/// One face of the cube as a mesh of its own: 0 is the face toward +x,
/// then -x, +y (the top), -y (the bottom), +z, -z.
pub fn cubeFace(face: usize) Mesh {
    return .{ .vertices = cube.vertices[face * 4 ..][0..4], .indices = &quad_indices };
}

test "the cube's triangles wind counter-clockwise seen from outside" {
    try std.testing.expectEqual(24, cube.vertices.len);
    try std.testing.expectEqual(12, cube.triangleCount());
    const center: Vec3 = .{ 0.5, 0.5, 0.5 };
    var i: usize = 0;
    while (i < cube.indices.len) : (i += 3) {
        const a = cube.vertices[cube.indices[i]];
        const b = cube.vertices[cube.indices[i + 1]];
        const c = cube.vertices[cube.indices[i + 2]];
        // Counter-clockwise seen from outside: by the right-hand rule the
        // cross product of two edges points out, along the normal...
        const n = math.cross(b.pos - a.pos, c.pos - a.pos);
        try std.testing.expect(math.approxEq(math.normalize(n), a.normal));
        // ...and the normal points away from the cube's center.
        try std.testing.expect(math.dot(a.normal, a.pos - center) > 0);
        for ([_]Vec3{ a.pos, b.pos, c.pos }) |p| {
            try std.testing.expect(@reduce(.And, p >= Vec3{ 0, 0, 0 }) and @reduce(.And, p <= Vec3{ 1, 1, 1 }));
        }
    }
}
