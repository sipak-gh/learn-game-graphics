//! What an index buffer saves. Without one, every triangle stores its own
//! three vertices; with one, a shared corner is stored and transformed once
//! and triangles name their corners by number.
const std = @import("std");

const Vec3 = @Vector(3, f32);
const Vertex = struct { pos: Vec3, normal: Vec3 };

fn report(name: []const u8, triangles: usize, unique: usize) void {
    const plain = triangles * 3 * @sizeOf(Vertex);
    const indexed = unique * @sizeOf(Vertex) + triangles * 3 * @sizeOf(u16);
    std.debug.print("{s:<22} {d:>4} triangles | plain: {d:>5} vertices {d:>6} bytes | indexed: {d:>5} vertices + {d:>5} indices = {d:>6} bytes\n", .{
        name, triangles, triangles * 3, plain, unique, triangles * 3, indexed,
    });
}

pub fn main() void {
    std.debug.print("@sizeOf(Vec3) = {d}, @sizeOf(Vertex) = {d}, @sizeOf(u16) = {d}\n\n", .{
        @sizeOf(Vec3), @sizeOf(Vertex), @sizeOf(u16),
    });
    // A square: two triangles share the diagonal's two corners.
    report("square", 2, 4);
    // A cube has 8 corners, used 36 times by its 12 triangles. But each
    // corner touches three faces that face three ways: one normal won't do.
    report("cube, 8 corners", 12, 8);
    report("cube, with normals", 12, 24);
    // delve's maze: one cube mesh drawn at 218 places; what counts here is
    // the number of vertex transforms per frame.
    report("maze (218 cubes)", 218 * 12, 218 * 24);

    // The square, spelled out: four corners and two index triples.
    const square = [4]Vec3{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 0 } };
    const indices = [6]u16{ 0, 1, 2, 0, 2, 3 };
    var i: usize = 0;
    while (i < indices.len) : (i += 3) {
        std.debug.print("triangle {d}: {any} {any} {any}\n", .{
            i / 3, square[indices[i]], square[indices[i + 1]], square[indices[i + 2]],
        });
    }
    std.debug.print("largest u16 index: {d}\n", .{std.math.maxInt(u16)});
}
