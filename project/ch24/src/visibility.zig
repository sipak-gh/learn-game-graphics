//! Visibility: deciding which chunks of the world can be seen before
//! drawing any of them. Two tests, the cheap one first: is a chunk's box
//! inside the view frustum at all, and can any line of sight from the eye
//! through the maze grid reach it, or is it hidden behind walls?
const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const clip = @import("clip.zig");
const camera = @import("camera.zig");
const Map = @import("map.zig").Map;
const raycast = @import("raycast.zig");
const World = @import("world.zig").World;
const Color = @import("canvas.zig").Color;
const chunk_size = @import("world.zig").chunk_size;

/// The six planes of the view volume, in the world.
pub const Frustum = struct {
    /// Each plane as (a, b, c, d): a point p is on the inside if
    /// a x + b y + c z + d >= 0.
    planes: [6]Vec4,

    /// The planes that `view_proj` maps onto the six planes of clip space.
    /// A plane's distance in clip space is linear in the clip point, and
    /// the clip point is `view_proj` times the world point: the sum of the
    /// matrix columns times x, y, z, and 1. So the distance is the sum of
    /// the columns' distances times x, y, z, and 1.
    pub fn init(view_proj: Mat4) Frustum {
        var f: Frustum = undefined;
        for (&f.planes, std.enums.values(clip.Plane)) |*plane, which| {
            inline for (0..4) |j| plane[j] = which.distance(view_proj.cols[j]);
        }
        return f;
    }

    /// True if the box from `box[0]` to `box[1]` is entirely outside one
    /// of the planes, so nothing in it can be seen. False does not prove
    /// it can: a box near a corner of the frustum may be outside two
    /// planes, each with a part of it, and still be kept.
    pub fn excludes(f: Frustum, box: [2]Vec3) bool {
        for (f.planes) |plane| {
            const normal: Vec3 = .{ plane[0], plane[1], plane[2] };
            // The corner farthest along the normal: if even that one is
            // outside, all eight are.
            const corner = @select(f32, normal >= @as(Vec3, @splat(0)), box[1], box[0]);
            if (math.dot(normal, corner) + plane[3] < 0) return true;
        }
        return false;
    }
};

/// How half the view looks from above: the angle between the view
/// direction and the farthest view ray, both seen on the floor, for a
/// screen with this `aspect`. Null if the view reaches all around, which
/// happens when looking steeply up or down.
pub fn groundSpan(pitch: f32, aspect: f32) ?f32 {
    // A view ray is forward + a right + b up, with |a| <= tan_h and |b| <=
    // tan_v. Seen from above, forward is cos(pitch) long and up is
    // -sin(pitch) long along the view direction, and right is 1 long
    // across it. The ray turns farthest from the view direction with a at
    // its largest and the part along the view direction at its smallest.
    const tan_v = @tan(camera.vfov / 2);
    const tan_h = tan_v * aspect;
    const ahead = @cos(pitch) - tan_v * @abs(@sin(pitch));
    if (ahead <= 0) return null;
    return std.math.atan(tan_h / ahead);
}

/// How densely rays are cast: more than one per pixel column. Looking
/// level, column x of a screen W pixels wide looks along atan(a), with
/// a = tan_h (2x / W - 1), so there are W / (2 tan_h) (1 + a^2) columns
/// per radian: 400 in the middle of a 640 pixel screen, 656 at the edges.
pub const rays_per_radian = 1024;
/// Enough rays for all the way around.
pub const max_rays: usize = @as(usize, @intFromFloat(@ceil(std.math.tau * rays_per_radian))) + 1;

/// Which chunks are drawn, and which are not.
pub const Culling = enum {
    /// All of them.
    off,
    /// Those whose box is not outside the view frustum.
    frustum,
    /// Those inside the frustum that a ray through the grid can reach.
    grid,
};

pub const ChunkState = enum { drawn, outside, hidden };

pub const Visibility = struct {
    /// Per map cell, row by row: did a line of sight pass through it, or
    /// through a neighbor?
    cells: []bool,
    /// Per chunk of the world.
    states: []ChunkState,
    /// The chunks to draw, in the order to draw them.
    order: []u32,
    drawn: usize = 0,
    /// Where each ray stopped, from left to right.
    ray_ends: []Vec2,
    ray_count: usize = 0,
    /// Where the eye was, on the map.
    eye: Vec2 = .{ 0, 0 },
    /// False until the first `update`.
    valid: bool = false,

    pub fn init(gpa: std.mem.Allocator, map: Map, world: World) !Visibility {
        const cells = try gpa.alloc(bool, map.width * map.height);
        errdefer gpa.free(cells);
        const states = try gpa.alloc(ChunkState, world.chunks.len);
        errdefer gpa.free(states);
        const order = try gpa.alloc(u32, world.chunks.len);
        errdefer gpa.free(order);
        return .{ .cells = cells, .states = states, .order = order, .ray_ends = try gpa.alloc(Vec2, max_rays) };
    }

    pub fn deinit(v: *Visibility, gpa: std.mem.Allocator) void {
        gpa.free(v.ray_ends);
        gpa.free(v.order);
        gpa.free(v.states);
        gpa.free(v.cells);
        v.* = undefined;
    }

    /// The chunks to draw.
    pub fn chunks(v: Visibility) []const u32 {
        return v.order[0..v.drawn];
    }

    pub fn count(v: Visibility, state: ChunkState) usize {
        return std.mem.count(ChunkState, v.states, &.{state});
    }

    /// Decides what `cam` can see of `world` (built from `map`) on a
    /// screen with this `aspect`. With `sort`, the chunks are drawn
    /// nearest first, so that the depth test rejects more pixels before
    /// they are shaded.
    pub fn update(v: *Visibility, map: Map, world: World, cam: camera.Camera, view_proj: Mat4, aspect: f32, culling: Culling, sort: bool) void {
        v.eye = .{ cam.pos[0], cam.pos[2] };
        v.valid = true;
        @memset(v.cells, false);
        v.ray_count = 0;
        if (culling == .grid) v.castRays(map, cam, aspect);

        const frustum: Frustum = .init(view_proj);
        v.drawn = 0;
        for (world.chunks, v.states, 0..) |chunk, *state, i| {
            state.* = if (culling == .off)
                .drawn
            else if (frustum.excludes(chunk.box))
                .outside
            else if (culling == .grid and !v.anySeen(map, world, i))
                .hidden
            else
                .drawn;
            if (state.* != .drawn) continue;
            v.order[v.drawn] = @intCast(i);
            v.drawn += 1;
        }
        if (sort) std.mem.sort(u32, v.order[0..v.drawn], Nearest{ .eye = v.eye, .world = world }, Nearest.lessThan);
    }

    /// Casts rays across everything the camera can see, as seen from
    /// above, and marks the cells they pass through and their neighbors.
    fn castRays(v: *Visibility, map: Map, cam: camera.Camera, aspect: f32) void {
        const half = groundSpan(cam.pitch, aspect) orelse std.math.pi;
        const n: usize = @intFromFloat(@ceil(2 * half * rays_per_radian));
        const marker: Marker = .{ .map = map, .cells = v.cells };
        for (0..n + 1) |k| {
            const t = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n));
            const dir = math.fromAngle(cam.yaw - half + 2 * half * t);
            const hit = raycast.castVisiting(map, v.eye, dir, marker);
            v.ray_ends[k] = v.eye + math.scale(dir, hit.t);
        }
        v.ray_count = n + 1;
    }

    /// True if any cell of chunk `i` was marked.
    fn anySeen(v: Visibility, map: Map, world: World, i: usize) bool {
        const x0 = (i % world.columns) * chunk_size;
        const y0 = (i / world.columns) * chunk_size;
        for (y0..@min(y0 + chunk_size, map.height)) |y| {
            for (x0..@min(x0 + chunk_size, map.width)) |x| {
                if (v.cells[y * map.width + x]) return true;
            }
        }
        return false;
    }
};

/// Marks a cell and its eight neighbors. The neighbors make up for the
/// gaps between rays: a cell seen only between two rays is next to one
/// that a ray went through.
const Marker = struct {
    map: Map,
    cells: []bool,

    pub fn visit(m: Marker, cell: [2]i32) void {
        for (0..3) |dy| {
            for (0..3) |dx| {
                const x = cell[0] + @as(i32, @intCast(dx)) - 1;
                const y = cell[1] + @as(i32, @intCast(dy)) - 1;
                if (x < 0 or y < 0 or x >= m.map.width or y >= m.map.height) continue;
                m.cells[@as(usize, @intCast(y)) * m.map.width + @as(usize, @intCast(x))] = true;
            }
        }
    }
};

/// Orders chunks by the distance from the eye to their centers.
const Nearest = struct {
    eye: Vec2,
    world: World,

    fn distance(n: Nearest, i: u32) f32 {
        const box = n.world.chunks[i].box;
        const center = math.scale(box[0] + box[1], 0.5);
        const d = Vec2{ center[0], center[2] } - n.eye;
        return math.dot(d, d);
    }

    fn lessThan(n: Nearest, a: u32, b: u32) bool {
        return n.distance(a) < n.distance(b);
    }
};

const testing = std.testing;

test "a box is excluded exactly when all its corners are outside one plane" {
    const cam: camera.Camera = .{ .pos = .{ 2, 0.5, 3 }, .yaw = 0.7, .pitch = 0.3 };
    const view_proj = cam.viewProjection(640, 400);
    const frustum: Frustum = .init(view_proj);
    var prng: std.Random.DefaultPrng = .init(23);
    const random = prng.random();
    var excluded: usize = 0;
    for (0..2000) |_| {
        var lo: Vec3 = undefined;
        var size: Vec3 = undefined;
        inline for (0..3) |k| {
            lo[k] = random.float(f32) * 40 - 20;
            size[k] = random.float(f32) * 4;
        }
        const box = [2]Vec3{ lo, lo + size };
        // What the clipper would say about the box's corners.
        var all: clip.Outcode = .full;
        for (0..8) |c| {
            const corner = @select(f32, @Vector(3, bool){ c & 1 != 0, c & 2 != 0, c & 4 != 0 }, box[1], box[0]);
            all = all.intersectWith(clip.outcode(view_proj.mulVec(math.vec4(corner, 1))));
        }
        try testing.expectEqual(all.count() > 0, frustum.excludes(box));
        excluded += @intFromBool(all.count() > 0);
    }
    // Both answers came up plenty of times.
    try testing.expect(excluded > 500 and excluded < 1900);
}

test "the view reaches farther around when looking up or down" {
    const level = groundSpan(0, 1.6).?;
    try testing.expectApproxEqAbs(std.math.atan(@as(f32, 0.8)), level, 1e-6);
    try testing.expect(groundSpan(0.5, 1.6).? > level);
    try testing.expectEqual(groundSpan(0.5, 1.6), groundSpan(-0.5, 1.6));
    // tan(pitch) = 1 / tan_v = 2: the top of the screen looks straight up.
    try testing.expect(groundSpan(std.math.atan(@as(f32, 1.99)), 1.6) != null);
    try testing.expectEqual(null, groundSpan(std.math.atan(@as(f32, 2.01)), 1.6));
}

test "walls hide the cells behind them" {
    const gpa = testing.allocator;
    var map: Map = try .parse(gpa,
        \\##########
        \\#>.......#
        \\#.########
        \\#........#
        \\##########
    );
    defer map.deinit(gpa);
    var world: World = try .build(gpa, map);
    defer world.deinit(gpa);
    var v: Visibility = try .init(gpa, map, world);
    defer v.deinit(gpa);
    const at = struct {
        fn at(vis: Visibility, x: usize, y: usize) bool {
            return vis.cells[y * 10 + x];
        }
    }.at;

    // Looking east along the top corridor: all of it is seen, the bottom
    // corridor is not, except next to the opening at x = 1.
    var cam: camera.Camera = .{ .pos = .{ 1.5, 0.5, 1.5 }, .yaw = 0 };
    v.update(map, world, cam, cam.viewProjection(640, 400), 1.6, .grid, true);
    for (1..9) |x| try testing.expect(at(v, x, 1));
    for (3..9) |x| try testing.expect(!at(v, x, 3));

    // Looking south from the same spot, down into the bottom corridor.
    cam.yaw = std.math.pi / 2.0;
    v.update(map, world, cam, cam.viewProjection(640, 400), 1.6, .grid, true);
    try testing.expect(at(v, 1, 3) and at(v, 2, 3));
    try testing.expect(!at(v, 8, 1) and !at(v, 8, 3));
}

test "chunks are drawn nearest first" {
    const gpa = testing.allocator;
    var map = try Map.parse(gpa, @import("map.zig").builtin.get("labyrinth").?);
    defer map.deinit(gpa);
    var world: World = try .build(gpa, map);
    defer world.deinit(gpa);
    var v: Visibility = try .init(gpa, map, world);
    defer v.deinit(gpa);
    const cam: camera.Camera = .fromPlayer(.{ .pos = map.start, .yaw = map.start_yaw });
    const view_proj = cam.viewProjection(640, 400);

    v.update(map, world, cam, view_proj, 1.6, .off, false);
    try testing.expectEqual(world.chunks.len, v.drawn);
    v.update(map, world, cam, view_proj, 1.6, .frustum, false);
    const in_frustum = v.drawn;
    v.update(map, world, cam, view_proj, 1.6, .grid, true);
    try testing.expect(v.drawn < in_frustum and in_frustum < world.chunks.len);
    try testing.expectEqual(world.chunks.len, v.drawn + v.count(.outside) + v.count(.hidden));
    const nearest: Nearest = .{ .eye = v.eye, .world = world };
    for (v.chunks()[1..], v.chunks()[0 .. v.drawn - 1]) |b, a| {
        try testing.expect(nearest.distance(a) <= nearest.distance(b));
    }
}

test "culling never changes the picture" {
    const gpa = testing.allocator;
    const maze3d = @import("maze3d.zig");
    const render3d = @import("render3d.zig");
    const Canvas = @import("canvas.zig").Canvas;
    var all_canvas = try Canvas.init(gpa, 640, 400);
    defer all_canvas.deinit(gpa);
    var culled_canvas = try Canvas.init(gpa, 640, 400);
    defer culled_canvas.deinit(gpa);
    var r = try render3d.Renderer.init(gpa, 1024, 640, 400);
    defer r.deinit(gpa);
    const all_depth = try gpa.alloc(f32, 640 * 400);
    defer gpa.free(all_depth);
    const poses = [_]struct { map: []const u8, x: f32, y: f32, yaw: f32, pitch: f32 }{
        .{ .map = "cellar", .x = 9.5, .y = 10.5, .yaw = -1, .pitch = 0 },
        .{ .map = "cellar", .x = 1.3, .y = 1.3, .yaw = 0.8, .pitch = 1.0 },
        .{ .map = "labyrinth", .x = 2.5, .y = 1.5, .yaw = 1.57, .pitch = 0 },
        .{ .map = "labyrinth", .x = 12.5, .y = 15.5, .yaw = 0, .pitch = 0.2 },
        .{ .map = "labyrinth", .x = 40.5, .y = 9.5, .yaw = 2.2, .pitch = -0.8 },
        .{ .map = "labyrinth", .x = 36.5, .y = 12.5, .yaw = -0.7, .pitch = 1.3 },
    };
    for (poses) |pose| {
        var map = try Map.parse(gpa, @import("map.zig").builtin.get(pose.map).?);
        defer map.deinit(gpa);
        var world: World = try .build(gpa, map);
        defer world.deinit(gpa);
        var v: Visibility = try .init(gpa, map, world);
        defer v.deinit(gpa);
        const cam: camera.Camera = .{ .pos = .{ pose.x, camera.eye_height, pose.y }, .yaw = pose.yaw, .pitch = pose.pitch };
        const view_proj = cam.viewProjection(640, 400);
        const scene: @import("light.zig").Scene = .{ .ambient = @splat(1), .lights = &.{}, .eye = cam.pos };
        const paint: maze3d.Paint = .{ .chunk_colors = true };
        for ([_]Culling{ .off, .grid }, [_]Canvas{ all_canvas, culled_canvas }) |culling, canvas| {
            v.update(map, world, cam, view_proj, 1.6, culling, culling != .off);
            canvas.clear(.hex(0xff00ff));
            r.clearDepth();
            var stats: render3d.Stats = .{};
            world.draw(r, canvas, view_proj, v.chunks(), paint, .unlit, scene, .{}, &stats);
            if (culling == .off) @memcpy(all_depth, r.depth);
        }
        try testing.expect(v.drawn < world.chunks.len);
        try testing.expectEqualSlices(f32, all_depth, r.depth);
        try testing.expectEqualSlices(Color, all_canvas.pixels, culled_canvas.pixels);
    }
}
