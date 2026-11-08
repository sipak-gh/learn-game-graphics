//! A tiny Wavefront OBJ reader: `v x y z` lines are vertices, `f a b c`
//! lines are triangles whose corners are 1-based vertex numbers. Everything
//! else is skipped. The result is a vertex list and a u16 index list, the
//! shape of delve's Mesh.
const std = @import("std");

const Vec3 = @Vector(3, f32);

const tetrahedron =
    \\# a tetrahedron: four corners, four faces, counter-clockwise from outside
    \\v 0 0 0
    \\v 1 0 0
    \\v 0 1 0
    \\v 0 0 1
    \\f 1 3 2
    \\f 1 2 4
    \\f 1 4 3
    \\f 2 3 4
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var vertices: std.ArrayList(Vec3) = .empty;
    defer vertices.deinit(gpa);
    var indices: std.ArrayList(u16) = .empty;
    defer indices.deinit(gpa);

    var lines = std.mem.tokenizeScalar(u8, tetrahedron, '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeScalar(u8, line, ' ');
        const kind = words.next() orelse continue;
        if (std.mem.eql(u8, kind, "v")) {
            var v: [3]f32 = undefined;
            for (&v) |*c| c.* = try std.fmt.parseFloat(f32, words.next() orelse return error.BadObj);
            try vertices.append(gpa, v);
        } else if (std.mem.eql(u8, kind, "f")) {
            for (0..3) |_| {
                const n = try std.fmt.parseInt(u16, words.next() orelse return error.BadObj, 10);
                if (n == 0 or n > vertices.items.len) return error.BadObj;
                try indices.append(gpa, n - 1); // OBJ counts from 1
            }
        }
    }
    std.debug.print("{d} vertices, {d} indices, {d} triangles\n", .{ vertices.items.len, indices.items.len, indices.items.len / 3 });
    var i: usize = 0;
    while (i < indices.items.len) : (i += 3) {
        const a = vertices.items[indices.items[i]];
        const b = vertices.items[indices.items[i + 1]];
        const c = vertices.items[indices.items[i + 2]];
        const e1 = b - a;
        const e2 = c - a;
        const n: Vec3 = .{ e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
        std.debug.print("triangle {any}: cross product {any}\n", .{ indices.items[i..][0..3].*, n });
    }
}
