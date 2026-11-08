//! Reads an OBJ file with a copy of delve's parser (src/obj.zig) and
//! prints what is in it: vertices, triangles, the bounding box, and how
//! many face corners the dedupe merged into shared vertices.
//!
//!   zig run examples/ch21/obj_dump.zig -- project/ch21/src/models/barrel.obj
const std = @import("std");

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

const Vertex = struct { pos: Vec3, uv: Vec2, normal: Vec3 };

const Model = struct {
    vertices: []Vertex,
    indices: []u16,
    /// Face corners in the file, before the dedupe.
    corners: usize,
};

const Error = error{ BadNumber, BadIndex, MissingNormal, ShortFace, TooManyVertices } || std.mem.Allocator.Error;

fn normalize(v: Vec3) Vec3 {
    return v / @as(Vec3, @splat(@sqrt(@reduce(.Add, v * v))));
}

fn parse(gpa: std.mem.Allocator, text: []const u8, line: *usize) Error!Model {
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
    var known: std.AutoHashMapUnmanaged([3]usize, u16) = .empty;
    defer known.deinit(gpa);
    var corner_count: usize = 0;

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
            try uvs.append(gpa, .{ uv[0], 1 - uv[1] });
        } else if (std.mem.eql(u8, keyword, "vn")) {
            try normals.append(gpa, normalize(try numbers(3, &words)));
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
                if (n == 0) corners[0] = entry.value_ptr.*;
                corners[1] = corners[2];
                corners[2] = entry.value_ptr.*;
                if (n >= 2) try indices.appendSlice(gpa, &corners);
            }
            if (n < 3) return error.ShortFace;
            corner_count += n;
        }
    }
    const final_vertices = try vertices.toOwnedSlice(gpa);
    errdefer gpa.free(final_vertices);
    return .{ .vertices = final_vertices, .indices = try indices.toOwnedSlice(gpa), .corners = corner_count };
}

const none = std.math.maxInt(usize);

fn numbers(comptime n: usize, words: *std.mem.TokenIterator(u8, .any)) Error!@Vector(n, f32) {
    var result: [n]f32 = undefined;
    for (&result) |*x| {
        const word = words.next() orelse return error.BadNumber;
        x.* = std.fmt.parseFloat(f32, word) catch return error.BadNumber;
    }
    return result;
}

fn corner(word: []const u8, positions: usize, uvs: usize, normals: usize) Error![3]usize {
    var parts = std.mem.splitScalar(u8, word, '/');
    const p = try index(parts.next().?, positions);
    const t_text = parts.next() orelse "";
    const t = if (t_text.len == 0) none else try index(t_text, uvs);
    const n_text = parts.next() orelse return error.MissingNormal;
    if (parts.next() != null) return error.BadIndex;
    return .{ p, t, try index(n_text, normals) };
}

fn index(text: []const u8, count: usize) Error!usize {
    const i = std.fmt.parseInt(isize, text, 10) catch return error.BadIndex;
    const from_zero = if (i < 0) @as(isize, @intCast(count)) + i else i - 1;
    if (from_zero < 0 or from_zero >= count) return error.BadIndex;
    return @intCast(from_zero);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const path = if (args.len > 1) args[1] else "project/ch21/src/models/barrel.obj";
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.arena.allocator(), .limited(16 << 20));

    var line: usize = undefined;
    const model = parse(gpa, text, &line) catch |err| {
        std.debug.print("{s}:{d}: error: {t}\n", .{ path, line, err });
        std.process.exit(1);
    };
    defer gpa.free(model.vertices);
    defer gpa.free(model.indices);

    var low: Vec3 = @splat(std.math.inf(f32));
    var high: Vec3 = @splat(-std.math.inf(f32));
    for (model.vertices) |v| {
        low = @min(low, v.pos);
        high = @max(high, v.pos);
    }
    std.debug.print("{s}\n", .{path});
    std.debug.print("  {d} vertices, {d} triangles\n", .{ model.vertices.len, model.indices.len / 3 });
    std.debug.print("  {d} face corners, {d} merged into shared vertices\n", .{ model.corners, model.corners - model.vertices.len });
    std.debug.print("  box ({d:.3}, {d:.3}, {d:.3}) to ({d:.3}, {d:.3}, {d:.3})\n", .{ low[0], low[1], low[2], high[0], high[1], high[2] });
}
