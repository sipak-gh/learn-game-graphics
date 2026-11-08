//! The world: the maze turned into meshes once, when the map is loaded.
//! Only surfaces that can be seen are built: the floor and the ceiling of
//! every floor cell, and each side of a wall cell that faces a floor cell.
//! They are cut into square chunks of cells, with one mesh per surface
//! kind in each chunk, so the whole maze takes a few hundred draw calls,
//! and a chunk out of sight can be skipped as a whole (see visibility.zig).
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const map_zig = @import("map.zig");
const Map = map_zig.Map;
const Tile = map_zig.Tile;
const mesh = @import("mesh.zig");
const Mesh = mesh.Mesh;
const Vertex = mesh.Vertex;
const obj = @import("obj.zig");
const render3d = @import("render3d.zig");
const raycast = @import("raycast.zig");
const light = @import("light.zig");
const texture = @import("texture.zig");
const maze3d = @import("maze3d.zig");
const ChunkState = @import("visibility.zig").ChunkState;

/// A chunk is chunk_size x chunk_size cells.
pub const chunk_size = 4;

/// The kinds of surface, one mesh each per chunk.
pub const Surface = enum {
    brick,
    stone,
    floor,
    ceiling,

    fn ofWall(tile: Tile) Surface {
        return switch (tile) {
            .floor => unreachable,
            .brick => .brick,
            .stone => .stone,
        };
    }

    fn material(surface: Surface, paint: maze3d.Paint) light.Material {
        return switch (surface) {
            .brick => paint.material(raycast.wallColor(.brick), .brick),
            .stone => paint.material(raycast.wallColor(.stone), .stone),
            .floor => paint.material(raycast.floor_color, .floor),
            .ceiling => paint.material(raycast.ceiling_color, .ceiling),
        };
    }
};

pub const Chunk = struct {
    /// The box everything in the chunk is inside: lowest and highest corner.
    box: [2]Vec3,
    parts: std.EnumArray(Surface, Mesh),
    /// The things standing in the chunk's cells.
    lamps: []const Vec2,
    barrels: []const Barrel,
};

/// A barrel standing in the maze, turned so that not all look the same.
const Barrel = struct { pos: Vec2, angle: f32 };

pub const World = struct {
    /// Row by row, `columns` chunks to a row.
    chunks: []Chunk,
    columns: usize,
    rows: usize,
    /// The vertices and indices of every chunk's meshes, one after another.
    vertices: []Vertex,
    indices: []u16,
    /// Every chunk's things, one chunk after another.
    lamps: []Vec2,
    barrels: []Barrel,
    barrel_model: obj.Model,

    pub fn build(gpa: std.mem.Allocator, map: Map) !World {
        const columns = (map.width + chunk_size - 1) / chunk_size;
        const rows = (map.height + chunk_size - 1) / chunk_size;
        var vertices: std.ArrayList(Vertex) = .empty;
        defer vertices.deinit(gpa);
        var indices: std.ArrayList(u16) = .empty;
        defer indices.deinit(gpa);
        // Where each part's vertices and indices start and end, until all
        // are built and the lists stop moving in memory.
        const Range = struct { vertices: [2]usize, indices: [2]usize };
        const ranges = try gpa.alloc(std.EnumArray(Surface, Range), columns * rows);
        defer gpa.free(ranges);

        for (ranges, 0..) |*chunk_ranges, i| {
            const cx = (i % columns) * chunk_size;
            const cy = (i / columns) * chunk_size;
            for (std.enums.values(Surface)) |surface| {
                var builder: Builder = .{ .gpa = gpa, .vertices = &vertices, .indices = &indices, .first = vertices.items.len };
                const first_index = indices.items.len;
                for (cy..@min(cy + chunk_size, map.height)) |y| {
                    for (cx..@min(cx + chunk_size, map.width)) |x| {
                        try builder.addCell(map, @intCast(x), @intCast(y), surface);
                    }
                }
                chunk_ranges.set(surface, .{
                    .vertices = .{ builder.first, vertices.items.len },
                    .indices = .{ first_index, indices.items.len },
                });
            }
        }

        const all_vertices = try vertices.toOwnedSlice(gpa);
        errdefer gpa.free(all_vertices);
        const all_indices = try indices.toOwnedSlice(gpa);
        errdefer gpa.free(all_indices);
        const chunks = try gpa.alloc(Chunk, columns * rows);
        errdefer gpa.free(chunks);
        for (chunks, ranges, 0..) |*chunk, chunk_ranges, i| {
            const x: f32 = @floatFromInt((i % columns) * chunk_size);
            const y: f32 = @floatFromInt((i / columns) * chunk_size);
            const w: f32 = @floatFromInt(map.width);
            const h: f32 = @floatFromInt(map.height);
            chunk.box = .{ .{ x, 0, y }, .{ @min(x + chunk_size, w), 1, @min(y + chunk_size, h) } };
            for (std.enums.values(Surface)) |surface| {
                const range = chunk_ranges.get(surface);
                chunk.parts.set(surface, .{
                    .vertices = all_vertices[range.vertices[0]..range.vertices[1]],
                    .indices = all_indices[range.indices[0]..range.indices[1]],
                });
            }
        }

        var lamps: std.ArrayList(Vec2) = .empty;
        defer lamps.deinit(gpa);
        var barrels: std.ArrayList(Barrel) = .empty;
        defer barrels.deinit(gpa);
        for (map.sprites) |sprite| switch (sprite.thing) {
            .lamp => try lamps.append(gpa, sprite.pos),
            .barrel => {
                const turn = @as(u32, @intFromFloat(sprite.pos[0] * 7 + sprite.pos[1] * 13)) % 17;
                try barrels.append(gpa, .{ .pos = sprite.pos, .angle = @as(f32, @floatFromInt(turn)) * 0.37 });
            },
        };
        // Sorted by chunk, each chunk's things are next to each other.
        sortByChunk(Vec2, lamps.items, columns);
        sortByChunk(Barrel, barrels.items, columns);
        const lamp_slice = try lamps.toOwnedSlice(gpa);
        errdefer gpa.free(lamp_slice);
        const barrel_slice = try barrels.toOwnedSlice(gpa);
        errdefer gpa.free(barrel_slice);
        var lamp_end: usize = 0;
        var barrel_end: usize = 0;
        for (chunks, 0..) |*chunk, i| {
            const first_lamp = lamp_end;
            while (lamp_end < lamp_slice.len and chunkOf(lamp_slice[lamp_end], columns) == i) lamp_end += 1;
            chunk.lamps = lamp_slice[first_lamp..lamp_end];
            const first_barrel = barrel_end;
            while (barrel_end < barrel_slice.len and chunkOf(barrel_slice[barrel_end].pos, columns) == i) barrel_end += 1;
            chunk.barrels = barrel_slice[first_barrel..barrel_end];
        }
        var line: usize = undefined;
        const barrel_model = try obj.parse(gpa, @embedFile("models/barrel.obj"), &line);
        return .{
            .chunks = chunks,
            .columns = columns,
            .rows = rows,
            .vertices = all_vertices,
            .indices = all_indices,
            .lamps = lamp_slice,
            .barrels = barrel_slice,
            .barrel_model = barrel_model,
        };
    }

    pub fn deinit(world: *World, gpa: std.mem.Allocator) void {
        world.barrel_model.deinit(gpa);
        gpa.free(world.barrels);
        gpa.free(world.lamps);
        gpa.free(world.chunks);
        gpa.free(world.indices);
        gpa.free(world.vertices);
        world.* = undefined;
    }

    pub fn triangleCount(world: World) usize {
        return world.indices.len / 3;
    }

    /// Draws the chunks listed in `chunks`, in that order: their surfaces,
    /// painted as `paint` says, shaded as `shading` says, and lit by
    /// `scene`, and the things standing in them.
    pub fn draw(
        world: World,
        r: render3d.Renderer,
        canvas: Canvas,
        view_proj: Mat4,
        chunks: []const u32,
        paint: maze3d.Paint,
        shading: light.Shading,
        scene: light.Scene,
        render_options: render3d.Options,
        stats: *render3d.Stats,
    ) void {
        var options = render_options;
        options.flat_shading = shading == .flat;
        const barrel = paint.material(barrel_color, .staves);
        for (chunks) |i| {
            const chunk = world.chunks[i];
            for (std.enums.values(Surface)) |surface| {
                const part = chunk.parts.get(surface);
                if (part.indices.len == 0) continue;
                const material: light.Material = if (paint.chunk_colors)
                    .{ .color = chunkColor(i % world.columns, i / world.columns) }
                else
                    surface.material(paint);
                maze3d.drawPart(r, canvas, part, .identity, view_proj, material, shading, scene, chunk.box, options, stats);
            }
            for (chunk.lamps) |pos| maze3d.drawLamp(r, canvas, pos, view_proj, shading, scene, options, stats);
            for (chunk.barrels) |b| world.drawBarrel(r, canvas, b, view_proj, barrel, shading, scene, options, stats);
        }
    }

    fn drawBarrel(
        world: World,
        r: render3d.Renderer,
        canvas: Canvas,
        b: Barrel,
        view_proj: Mat4,
        material: light.Material,
        shading: light.Shading,
        scene: light.Scene,
        options: render3d.Options,
        stats: *render3d.Stats,
    ) void {
        const base: Vec3 = .{ b.pos[0], 0, b.pos[1] };
        const model = Mat4.translation(base).mul(.rotationY(b.angle));
        const box = [2]Vec3{ base - Vec3{ 0.25, 0, 0.25 }, base + Vec3{ 0.25, 0.5, 0.25 } };
        maze3d.drawPart(r, canvas, world.barrel_model.mesh(), model, view_proj, material, shading, scene, box, options, stats);
    }

    /// Draws the edges of the wall triangles of the chunks in `chunks`.
    pub fn drawWireframe(
        world: World,
        r: render3d.Renderer,
        canvas: Canvas,
        view_proj: Mat4,
        chunks: []const u32,
        options: render3d.Options,
        stats: *render3d.Stats,
    ) void {
        for (chunks) |i| {
            for ([_]Surface{ .brick, .stone }, [_]Color{ .hex(0xe08050), .hex(0xb0b0c0) }) |surface, color| {
                r.drawWireframe(canvas, world.chunks[i].parts.get(surface), .identity, view_proj, color, options, stats);
            }
        }
    }

    /// Draws every chunk without its ceiling, to be seen from above, and
    /// without light. A chunk's state says how: `.drawn` chunks look as
    /// usual, `.outside` ones (outside the view) dim blue, and `.hidden`
    /// ones (behind walls) dim red.
    pub fn drawOverhead(
        world: World,
        r: render3d.Renderer,
        canvas: Canvas,
        view_proj: Mat4,
        states: []const ChunkState,
        paint: maze3d.Paint,
        options: render3d.Options,
        stats: *render3d.Stats,
    ) void {
        const dark: light.Scene = .{ .ambient = @splat(1), .lights = &.{}, .eye = @splat(0) };
        const barrel = paint.material(barrel_color, .staves);
        for (world.chunks, states) |chunk, state| {
            for ([_]Surface{ .brick, .stone, .floor }) |surface| {
                const material: light.Material = switch (state) {
                    .drawn => surface.material(paint),
                    .outside => .{ .color = .hex(0x404c70) },
                    .hidden => .{ .color = .hex(0x803838) },
                };
                r.drawMesh(canvas, chunk.parts.get(surface), .identity, view_proj, maze3d.FlatShader{ .material = material }, options, stats);
            }
            if (state != .drawn) continue;
            for (chunk.lamps) |pos| maze3d.drawLamp(r, canvas, pos, view_proj, .unlit, dark, options, stats);
            for (chunk.barrels) |b| world.drawBarrel(r, canvas, b, view_proj, barrel, .unlit, dark, options, stats);
        }
    }
};

const barrel_color: Color = .hex(0x8a5a2c);

/// The chunk that map position `pos` is in.
fn chunkOf(pos: Vec2, columns: usize) usize {
    const x: usize = @intFromFloat(pos[0]);
    const y: usize = @intFromFloat(pos[1]);
    return y / chunk_size * columns + x / chunk_size;
}

/// Sorts lamps (positions) or barrels by the chunk they are in, keeping
/// the order of those in the same chunk.
fn sortByChunk(comptime T: type, things: []T, columns: usize) void {
    const ByChunk = struct {
        columns: usize,
        fn chunk(c: @This(), thing: T) usize {
            return chunkOf(if (T == Vec2) thing else thing.pos, c.columns);
        }
        fn lessThan(c: @This(), a: T, b: T) bool {
            return c.chunk(a) < c.chunk(b);
        }
    };
    std.mem.sort(T, things, ByChunk{ .columns = columns }, ByChunk.lessThan);
}

/// A color per chunk, different from all eight neighbors' colors:
/// x + 3y mod 8 changes by 1, 2, 3, 4, or 7 from one chunk to the next.
fn chunkColor(x: usize, y: usize) Color {
    const colors = [8]Color{
        .hex(0xe05050), .hex(0xe0a040), .hex(0xd0d050), .hex(0x60c060),
        .hex(0x50c0c0), .hex(0x5070e0), .hex(0xa060e0), .hex(0xe070b0),
    };
    return colors[(x + 3 * y) % colors.len];
}

/// Adds the quads of one part of a chunk to the world's lists.
const Builder = struct {
    gpa: std.mem.Allocator,
    vertices: *std.ArrayList(Vertex),
    indices: *std.ArrayList(u16),
    /// The part's first vertex: its indices count from there.
    first: usize,

    /// Adds a square whose corners `pos` go counter-clockwise seen from
    /// the side `normal` points to.
    fn addQuad(b: *Builder, pos: [4]Vec3, normal: Vec3, uv: [4]Vec2) !void {
        const start = b.vertices.items.len - b.first;
        if (start + 4 > std.math.maxInt(u16)) return error.ChunkTooBig;
        for (pos, uv) |p, t| try b.vertices.append(b.gpa, .{ .pos = p, .normal = normal, .uv = t });
        for ([6]usize{ 0, 1, 2, 0, 2, 3 }) |q| try b.indices.append(b.gpa, @intCast(start + q));
    }

    /// Adds what cell (x, y) has of `surface`. Floor and ceiling take
    /// their texture coordinates from the world's x and z, as the ray
    /// caster does, so the texture runs on across cells. A wall side shows
    /// the whole texture once, upright.
    fn addCell(b: *Builder, map: Map, x: i32, y: i32, surface: Surface) !void {
        if (map.at(x, y).isWall()) return;
        const fx: f32 = @floatFromInt(x);
        const fz: f32 = @floatFromInt(y);
        switch (surface) {
            .floor, .ceiling => {
                // Counter-clockwise seen from above: toward +z, then +x.
                var corners = [4]Vec2{ .{ fx, fz }, .{ fx, fz + 1 }, .{ fx + 1, fz + 1 }, .{ fx + 1, fz } };
                // Seen from below, the same corners go the other way.
                if (surface == .ceiling) std.mem.reverse(Vec2, &corners);
                const height: f32 = if (surface == .floor) 0 else 1;
                var pos: [4]Vec3 = undefined;
                for (corners, &pos) |c, *p| p.* = .{ c[0], height, c[1] };
                try b.addQuad(pos, .{ 0, if (surface == .floor) 1 else -1, 0 }, corners);
            },
            .brick, .stone => for ([_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |d| {
                const tile = map.at(x + d[0], y + d[1]);
                if (!tile.isWall() or Surface.ofWall(tile) != surface) continue;
                // The wall's side facing this cell: it faces back along d.
                const dx: f32 = @floatFromInt(d[0]);
                const dz: f32 = @floatFromInt(d[1]);
                const normal: Vec3 = .{ -dx, 0, -dz };
                const center: Vec3 = .{ fx + 0.5 + dx / 2, 0.5, fz + 0.5 + dz / 2 };
                // Right as seen from the front, and up: right x up = normal.
                const right: Vec3 = .{ normal[2] / 2, 0, -normal[0] / 2 };
                const up: Vec3 = .{ 0, 0.5, 0 };
                try b.addQuad(
                    .{ center - right - up, center + right - up, center + right + up, center - right + up },
                    normal,
                    .{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 }, .{ 0, 0 } },
                );
            },
        }
    }
};

test "the world has only the surfaces that can be seen" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa,
        \\#####
        \\#>.%#
        \\#####
    );
    defer map.deinit(gpa);
    var world: World = try .build(gpa, map);
    defer world.deinit(gpa);
    // Two floor cells: two squares of floor and two of ceiling, and the
    // walls around them: 5 brick sides and 1 stone side. 10 squares.
    try std.testing.expectEqual(10 * 2, world.triangleCount());
    try std.testing.expectEqual(2, world.columns);
    try std.testing.expectEqual(1, world.rows);
    try std.testing.expectEqual(1 * 2, world.chunks[0].parts.get(.stone).triangleCount());
    try std.testing.expectEqual(0, world.chunks[1].parts.get(.brick).triangleCount());
}

test "every surface faces into a floor cell and winds counter-clockwise" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa, map_zig.builtin.get("cellar").?);
    defer map.deinit(gpa);
    var world: World = try .build(gpa, map);
    defer world.deinit(gpa);
    for (world.chunks) |chunk| for (chunk.parts.values) |part| {
        var i: usize = 0;
        while (i < part.indices.len) : (i += 3) {
            const a = part.vertices[part.indices[i]];
            const b = part.vertices[part.indices[i + 1]];
            const c = part.vertices[part.indices[i + 2]];
            const n = math.cross(b.pos - a.pos, c.pos - a.pos);
            try std.testing.expect(math.approxEq(math.normalize(n), a.normal));
            // Just in front of the triangle's center is open floor...
            const front = math.scale(a.pos + b.pos + c.pos, 1.0 / 3.0) + math.scale(a.normal, 0.01);
            try std.testing.expect(!map.isWallAt(.{ front[0], front[2] }));
            // ...and the triangle is inside its chunk's box.
            for ([_]Vec3{ a.pos, b.pos, c.pos }) |p| {
                try std.testing.expect(@reduce(.And, p >= chunk.box[0]) and @reduce(.And, p <= chunk.box[1]));
            }
        }
    };
}

test "the world has no cracks" {
    // Everywhere the eye looks inside the maze there is a wall, the floor,
    // or the ceiling. Any pixel left in the clear color is a crack.
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 160, 100);
    defer canvas.deinit(gpa);
    var r = try render3d.Renderer.init(gpa, 1024, 160, 100);
    defer r.deinit(gpa);
    const camera = @import("camera.zig");
    const crack: Color = .hex(0xff00ff);
    var textures = try texture.Set.generate(gpa);
    defer textures.deinit(gpa);
    const poses = [_]struct { map: []const u8, x: f32, y: f32, yaw: f32 }{
        .{ .map = "cellar", .x = 9.5, .y = 10.5, .yaw = -1 },
        .{ .map = "cellar", .x = 1.5, .y = 1.5, .yaw = 0.6 },
        .{ .map = "cellar", .x = 20.3, .y = 13.7, .yaw = 2.5 },
        .{ .map = "cellar", .x = 12.5, .y = 18.5, .yaw = 3.1 },
        .{ .map = "labyrinth", .x = 1.5, .y = 1.5, .yaw = 0.3 },
        .{ .map = "labyrinth", .x = 40.5, .y = 9.5, .yaw = 2.2 },
    };
    for (poses) |pose| {
        var map = try Map.parse(gpa, map_zig.builtin.get(pose.map).?);
        defer map.deinit(gpa);
        var world: World = try .build(gpa, map);
        defer world.deinit(gpa);
        const all = try gpa.alloc(u32, world.chunks.len);
        defer gpa.free(all);
        for (all, 0..) |*chunk, i| chunk.* = @intCast(i);
        var lights: [32]light.Light = undefined;
        for (world.lamps, lights[0..world.lamps.len]) |pos, *l| l.* = maze3d.lampLight(pos);
        const cam: camera.Camera = .{ .pos = .{ pose.x, camera.eye_height, pose.y }, .yaw = pose.yaw, .pitch = 0.3 * pose.yaw };
        const scene: light.Scene = .{ .ambient = @splat(0.1), .lights = lights[0..world.lamps.len], .eye = cam.pos };
        for (std.enums.values(light.Shading)) |shading| for ([_]maze3d.Paint{ .{}, .{ .textures = &textures } }) |paint| {
            canvas.clear(crack);
            r.clearDepth();
            var stats: render3d.Stats = .{};
            world.draw(r, canvas, cam.viewProjection(160, 100), all, paint, shading, scene, .{}, &stats);
            for (canvas.pixels) |p| try std.testing.expect(!std.meta.eql(p, crack));
            try std.testing.expect(stats.pixels >= 160 * 100);
        };
    }
}

test "bands on threads draw the same picture and stats as one renderer" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const camera = @import("camera.zig");
    var map = try Map.parse(gpa, map_zig.builtin.get("labyrinth").?);
    defer map.deinit(gpa);
    var world: World = try .build(gpa, map);
    defer world.deinit(gpa);
    var textures = try texture.Set.generate(gpa);
    defer textures.deinit(gpa);
    const all = try gpa.alloc(u32, world.chunks.len);
    defer gpa.free(all);
    for (all, 0..) |*chunk, i| chunk.* = @intCast(i);
    const cam: camera.Camera = .{ .pos = .{ 1.5, camera.eye_height, 1.5 }, .yaw = 0.5, .pitch = 0.1 };
    const view_proj = cam.viewProjection(160, 100);
    const lights = [_]light.Light{.{ .pos = cam.pos, .color = @splat(1), .radius = 6 }};
    const scene: light.Scene = .{ .ambient = @splat(0.1), .lights = &lights, .eye = cam.pos };
    const paint: maze3d.Paint = .{ .textures = &textures };

    var one = try Canvas.init(gpa, 160, 100);
    defer one.deinit(gpa);
    var r = try render3d.Renderer.init(gpa, 1024, 160, 100);
    defer r.deinit(gpa);
    one.clear(.black);
    r.clearDepth();
    var stats: render3d.Stats = .{};
    world.draw(r, one, view_proj, all, paint, .phong, scene, .{}, &stats);

    // Three uneven bands, as 100 rows split three ways are.
    var banded = try Canvas.init(gpa, 160, 100);
    defer banded.deinit(gpa);
    banded.clear(.black);
    r.clearDepth();
    var bands: [3]render3d.Renderer = undefined;
    for (&bands, [_]usize{ 0, 33, 66 }, [_]usize{ 33, 66, 100 }) |*b, first, end| b.* = try r.band(gpa, first, end);
    defer for (&bands) |*b| b.deinit(gpa);
    var band_stats: [3]render3d.Stats = @splat(.{});
    var group: std.Io.Group = .init;
    for (bands, &band_stats) |b, *s| {
        group.async(io, World.draw, .{ world, b, banded, view_proj, all, paint, .phong, scene, render3d.Options{}, s });
    }
    try group.await(io);

    try std.testing.expectEqualSlices(Color, one.pixels, banded.pixels);
    try std.testing.expectEqual(stats, render3d.combineBands(&band_stats));
    try std.testing.expect(stats.pixels > 0);
}
