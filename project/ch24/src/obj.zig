//! Wavefront OBJ files: the simplest common format for 3D models, plain
//! text, one item per line. delve reads the four kinds of line it needs
//! and skips the rest (object and group names, smoothing, materials):
//!
//!     v x y z          a position
//!     vt u v           a texture coordinate (v goes up, from the bottom)
//!     vn x y z         a normal
//!     f a/b/c d/e/f …  a face: three or more corners, each a position,
//!                      texture coordinate, and normal, by number
//!
//! Numbers count from 1 in the order the items appear; negative numbers
//! count back from the last one so far. A face with more than three
//! corners is cut into a fan of triangles.
const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mesh = @import("mesh.zig").Mesh;
const Vertex = @import("mesh.zig").Vertex;

/// A mesh read from a file, which owns its memory.
pub const Model = struct {
    vertices: []Vertex,
    indices: []u16,

    pub fn mesh(m: Model) Mesh {
        return .{ .vertices = m.vertices, .indices = m.indices };
    }

    pub fn deinit(m: *Model, gpa: std.mem.Allocator) void {
        gpa.free(m.indices);
        gpa.free(m.vertices);
        m.* = undefined;
    }
};

pub const Error = error{
    BadNumber,
    BadIndex,
    /// A face corner without a normal: delve does not make up normals.
    MissingNormal,
    /// A face with fewer than three corners.
    ShortFace,
    /// More vertices than 16-bit indices can number.
    TooManyVertices,
} || std.mem.Allocator.Error;

/// Reads a model from the text of an OBJ file. On an error, `line` is the
/// number of the line it was found on.
pub fn parse(gpa: std.mem.Allocator, text: []const u8, line: *usize) Error!Model {
    var positions: std.ArrayList(Vec3) = .empty;
    defer positions.deinit(gpa);
    var uvs: std.ArrayList(Vec2) = .empty;
    defer uvs.deinit(gpa);
    var normals: std.ArrayList(Vec3) = .empty;
    defer normals.deinit(gpa);
    var vertices: std.ArrayList(Vertex) = .empty;
    errdefer vertices.deinit(gpa);
    var indices: std.ArrayList(u16) = .empty;
    errdefer indices.deinit(gpa);
    // A corner used by several faces becomes one vertex: the vertex made
    // for each (position, texture coordinate, normal) triple so far.
    var known: std.AutoHashMapUnmanaged([3]usize, u16) = .empty;
    defer known.deinit(gpa);

    var lines = std.mem.splitScalar(u8, text, '\n');
    line.* = 0;
    while (lines.next()) |full| {
        line.* += 1;
        const content = full[0 .. std.mem.indexOfScalar(u8, full, '#') orelse full.len];
        var words = std.mem.tokenizeAny(u8, content, " \t\r");
        const keyword = words.next() orelse continue;
        if (std.mem.eql(u8, keyword, "v")) {
            try positions.append(gpa, try numbers(3, &words));
        } else if (std.mem.eql(u8, keyword, "vt")) {
            const uv = try numbers(2, &words);
            // OBJ's v goes up from the bottom of the image; ours goes down
            // from the top.
            try uvs.append(gpa, .{ uv[0], 1 - uv[1] });
        } else if (std.mem.eql(u8, keyword, "vn")) {
            try normals.append(gpa, math.normalize(try numbers(3, &words)));
        } else if (std.mem.eql(u8, keyword, "f")) {
            var corners: [3]u16 = undefined;
            var n: usize = 0;
            while (words.next()) |word| : (n += 1) {
                const key = try corner(word, positions.items.len, uvs.items.len, normals.items.len);
                const entry = try known.getOrPut(gpa, key);
                if (!entry.found_existing) {
                    if (vertices.items.len > std.math.maxInt(u16)) return error.TooManyVertices;
                    entry.value_ptr.* = @intCast(vertices.items.len);
                    try vertices.append(gpa, .{
                        .pos = positions.items[key[0]],
                        .uv = if (key[1] == none) .{ 0, 0 } else uvs.items[key[1]],
                        .normal = normals.items[key[2]],
                    });
                }
                // A fan: the first corner, the previous one, and this one.
                if (n == 0) corners[0] = entry.value_ptr.*;
                corners[1] = corners[2];
                corners[2] = entry.value_ptr.*;
                if (n >= 2) try indices.appendSlice(gpa, &corners);
            }
            if (n < 3) return error.ShortFace;
        }
    }
    const final_vertices = try vertices.toOwnedSlice(gpa);
    errdefer gpa.free(final_vertices);
    return .{ .vertices = final_vertices, .indices = try indices.toOwnedSlice(gpa) };
}

/// Stands for "no texture coordinate" in a corner.
const none = std.math.maxInt(usize);

/// The next `n` words as numbers.
fn numbers(comptime n: usize, words: *std.mem.TokenIterator(u8, .any)) Error!@Vector(n, f32) {
    var result: [n]f32 = undefined;
    for (&result) |*x| {
        const word = words.next() orelse return error.BadNumber;
        x.* = std.fmt.parseFloat(f32, word) catch return error.BadNumber;
    }
    return result;
}

/// A face corner "p/t/n", "p//n", or "p/t" as indices from 0 into the
/// positions, texture coordinates, and normals read so far.
fn corner(word: []const u8, positions: usize, uvs: usize, normals: usize) Error![3]usize {
    var parts = std.mem.splitScalar(u8, word, '/');
    const p = try index(parts.next().?, positions);
    const t_text = parts.next() orelse "";
    const t = if (t_text.len == 0) none else try index(t_text, uvs);
    const n_text = parts.next() orelse return error.MissingNormal;
    if (parts.next() != null) return error.BadIndex;
    return .{ p, t, try index(n_text, normals) };
}

/// An OBJ number (from 1, or from -1 back from the end) as an index from 0
/// into a list of `count` items.
fn index(text: []const u8, count: usize) Error!usize {
    const i = std.fmt.parseInt(isize, text, 10) catch return error.BadIndex;
    const from_zero = if (i < 0) @as(isize, @intCast(count)) + i else i - 1;
    if (from_zero < 0 or from_zero >= count) return error.BadIndex;
    return @intCast(from_zero);
}

test "a square becomes two triangles that share two corners" {
    const gpa = std.testing.allocator;
    var line: usize = undefined;
    var model = try parse(gpa,
        \\# a unit square facing +z
        \\v 0 0 0
        \\v 1 0 0
        \\v 1 1 0
        \\v 0 1 0
        \\vt 0 0
        \\vt 1 0
        \\vt 1 1
        \\vt 0 1
        \\vn 0 0 2
        \\f 1/1/1 2/2/1 3/3/1 -1/-1/-1
    , &line);
    defer model.deinit(gpa);
    try std.testing.expectEqual(4, model.vertices.len);
    try std.testing.expectEqualSlices(u16, &.{ 0, 1, 2, 0, 2, 3 }, model.indices);
    // Texture v is turned upside down, normals made length 1.
    try std.testing.expectEqual(Vec2{ 1, 0 }, model.vertices[2].uv);
    try std.testing.expectEqual(Vec3{ 0, 0, 1 }, model.vertices[0].normal);
}

test "errors say which line they are on" {
    const gpa = std.testing.allocator;
    var line: usize = undefined;
    try std.testing.expectError(error.BadIndex, parse(gpa, "v 0 0 0\nvn 0 1 0\n\nf 1//1 2//1 3//1", &line));
    try std.testing.expectEqual(4, line);
    try std.testing.expectError(error.MissingNormal, parse(gpa, "v 0 0 0\nf 1 1 1", &line));
    try std.testing.expectEqual(2, line);
    try std.testing.expectError(error.BadNumber, parse(gpa, "v 0 zero 0", &line));
    try std.testing.expectError(error.ShortFace, parse(gpa, "v 0 0 0\nvn 0 1 0\nf 1//1 1//1", &line));
}

test "the barrel is wound counter-clockwise seen from outside" {
    const gpa = std.testing.allocator;
    var line: usize = undefined;
    var model = try parse(gpa, @embedFile("models/barrel.obj"), &line);
    defer model.deinit(gpa);
    // 12 staves of 4 quads each, and a lid of 12 corners: 10 triangles.
    try std.testing.expectEqual(12 * 4 * 2 + 10, model.mesh().triangleCount());
    var i: usize = 0;
    while (i < model.indices.len) : (i += 3) {
        const a = model.vertices[model.indices[i]];
        const b = model.vertices[model.indices[i + 1]];
        const c = model.vertices[model.indices[i + 2]];
        // The triangle's own normal and the smooth normals at its corners
        // point the same way.
        const n = math.cross(b.pos - a.pos, c.pos - a.pos);
        for ([_]Vertex{ a, b, c }) |v| try std.testing.expect(math.dot(n, v.normal) > 0);
    }
}
