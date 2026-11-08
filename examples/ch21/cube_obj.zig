//! Writes delve's unit cube (mesh.cube, chapter 20's version with texture
//! coordinates) as a Wavefront OBJ file, cube.obj. The 24 vertices share
//! 8 positions, 4 texture coordinates, and 6 normals, so the file lists
//! each of those once and every face corner names one of each.
//! Read it back with obj_dump.zig to check the round trip.
const std = @import("std");

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

const Vertex = struct { pos: Vec3, normal: Vec3, uv: Vec2 };

/// The cube's faces as in src/mesh.zig: normal n and directions u, v
/// across the face with u x v = n.
const faces = [6][3]Vec3{
    .{ .{ 1, 0, 0 }, .{ 0, 0, -1 }, .{ 0, 1, 0 } },
    .{ .{ -1, 0, 0 }, .{ 0, 0, 1 }, .{ 0, 1, 0 } },
    .{ .{ 0, 1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, -1 } },
    .{ .{ 0, -1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 } },
    .{ .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } },
    .{ .{ 0, 0, -1 }, .{ -1, 0, 0 }, .{ 0, 1, 0 } },
};
const corners = [4][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 } };

fn cubeVertex(f: usize, k: usize) Vertex {
    const n, const u, const v = faces[f];
    const c = corners[k];
    const half: Vec3 = @splat(0.5);
    const pos = half + n * half + u * @as(Vec3, @splat(c[0] / 2)) + v * @as(Vec3, @splat(c[1] / 2));
    const down = if (n[1] < 0) c[1] else -c[1];
    return .{ .pos = pos, .normal = n, .uv = .{ (c[0] + 1) / 2, (down + 1) / 2 } };
}

/// Index of `x` in `list`, appending it if it is new. OBJ numbers count
/// from 1, so the caller adds 1.
fn find(comptime T: type, list: *std.ArrayList(T), gpa: std.mem.Allocator, x: T) !usize {
    for (list.items, 0..) |y, i| if (@reduce(.And, x == y)) return i;
    try list.append(gpa, x);
    return list.items.len - 1;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var positions: std.ArrayList(Vec3) = .empty;
    defer positions.deinit(gpa);
    var uvs: std.ArrayList(Vec2) = .empty;
    defer uvs.deinit(gpa);
    var normals: std.ArrayList(Vec3) = .empty;
    defer normals.deinit(gpa);
    var face_corners: [6][4][3]usize = undefined;
    for (0..6) |f| {
        for (0..4) |k| {
            const vertex = cubeVertex(f, k);
            // OBJ's texture v runs up from the bottom of the image.
            const obj_uv: Vec2 = .{ vertex.uv[0], 1 - vertex.uv[1] };
            face_corners[f][k] = .{
                try find(Vec3, &positions, gpa, vertex.pos) + 1,
                try find(Vec2, &uvs, gpa, obj_uv) + 1,
                try find(Vec3, &normals, gpa, vertex.normal) + 1,
            };
        }
    }

    var buffer: [4096]u8 = undefined;
    const file = try std.Io.Dir.cwd().createFile(io, "cube.obj", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);
    const out = &writer.interface;
    try out.writeAll("# delve's unit cube, from (0, 0, 0) to (1, 1, 1)\no cube\n");
    for (positions.items) |p| try out.print("v {d} {d} {d}\n", .{ p[0], p[1], p[2] });
    for (uvs.items) |t| try out.print("vt {d} {d}\n", .{ t[0], t[1] });
    for (normals.items) |n| try out.print("vn {d} {d} {d}\n", .{ n[0], n[1], n[2] });
    for (face_corners) |face| {
        try out.writeAll("f");
        for (face) |c| try out.print(" {d}/{d}/{d}", .{ c[0], c[1], c[2] });
        try out.writeAll("\n");
    }
    try out.flush();
    std.debug.print("wrote cube.obj: {d} positions, {d} texture coordinates, {d} normals, 6 faces\n", .{
        positions.items.len, uvs.items.len, normals.items.len,
    });
}
