//! The 3D pipeline: a mesh and its matrices go in, pixels come out.
//! Every vertex is transformed once into clip space, then every triangle
//! is clipped to the view volume, projected to the screen, and drawn:
//! as lines, or filled pixel by pixel with a depth test.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Mesh = @import("mesh.zig").Mesh;
const camera = @import("camera.zig");
const clip = @import("clip.zig");
const raster = @import("raster.zig");

/// What a shader carries from the vertices to the pixels. Lanes 0 to 7
/// are the shader's own (light, color, position, fog...). Lanes 8 and 9
/// are texture coordinates u and v, and lane 10 is filled in per pixel
/// for shaders that want the footprint (see `Fragment`).
pub const Varyings = clip.Varyings;
pub const uv_lane = 8;
pub const footprint_lane = 10;
/// The lanes that flat shading averages: the texture still moves across a
/// flat-shaded triangle.
const shading_lanes = blk: {
    var mask: @Vector(16, bool) = @splat(false);
    for (0..uv_lane) |i| mask[i] = true;
    break :blk mask;
};

/// Counts of what happened to the triangles of a frame.
pub const Stats = struct {
    triangles: u32 = 0,
    /// Entirely outside one plane of the view volume: skipped at once.
    outside: u32 = 0,
    /// Partly outside: cut down to the part inside.
    clipped: u32 = 0,
    /// Thrown away because a corner was behind the near plane (only
    /// without near clipping).
    behind: u32 = 0,
    /// Facing away from the camera.
    culled: u32 = 0,
    drawn: u32 = 0,
    /// Pixels of drawn triangles: each one is depth tested.
    tested: u32 = 0,
    /// Pixels that passed the depth test and were shaded and written.
    pixels: u32 = 0,
};

pub const Options = struct {
    /// Clip triangles against the near plane. Without it, a triangle with
    /// a corner behind the near plane is dropped whole, as in chapter 16.
    clip_near: bool = true,
    /// Skip triangles whose back is turned to the camera.
    cull_back_faces: bool = true,
    /// Draw a pixel only if it is nearer than what is already there.
    depth_test: bool = true,
    /// Give each triangle one set of varyings, the average of its
    /// corners', so it comes out in one color.
    flat_shading: bool = false,
    /// Interpolate varyings with perspective. Without it they are blended
    /// straight across the screen (affine), as on the first PlayStation.
    perspective_correct: bool = true,
    /// Count, for each pixel of the screen, how many times a triangle
    /// covered it (see `drawOverdraw`).
    count_overdraw: bool = false,
};

/// The color of edges made by the near plane in the wireframe.
pub const near_edge_color: Color = .hex(0xff40ff);

/// A color as varyings: red, green, and blue, 0 to 255, in lanes 0 to 2.
pub fn fromColor(c: Color) Varyings {
    return .{ @floatFromInt(c.r), @floatFromInt(c.g), @floatFromInt(c.b), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
}

/// The color in lanes 0 to 2, rounded and limited to 0..255.
pub fn toColor(vary: Varyings) Color {
    const rgb = @round(std.math.clamp(Vec3{ vary[0], vary[1], vary[2] }, @as(Vec3, @splat(0)), @as(Vec3, @splat(255))));
    return .{ .r = @intFromFloat(rgb[0]), .g = @intFromFloat(rgb[1]), .b = @intFromFloat(rgb[2]) };
}

/// The varyings at a pixel with barycentric `weights`, from the corners'
/// 1/w and varyings/w. A value that is linear across the triangle in the
/// world is not linear on the screen, but value/w and 1/w are; so those
/// are interpolated, and divided at the end.
pub fn interpolate(weights: Vec3, inv_w: Vec3, vary_w: [3]Varyings) Varyings {
    const sum = math.scale(vary_w[0], weights[0]) + math.scale(vary_w[1], weights[1]) +
        math.scale(vary_w[2], weights[2]);
    return math.scale(sum, 1 / math.dot(weights, inv_w));
}

/// A corner after the divide by w, ready for the rasterizer.
const ScreenVertex = struct {
    point: raster.Point,
    /// Depth, 0 at the near plane to 1 at the far plane.
    z: f32,
    inv_w: f32,
    vary_w: Varyings,

    fn init(v: clip.Vertex, width: usize, height: usize, perspective_correct: bool) ScreenVertex {
        const s = camera.toScreen(v.pos, width, height);
        // With 1/w = 1 at every corner, interpolate() is a plain blend.
        const inv_w = if (perspective_correct) 1 / v.pos[3] else 1;
        return .{
            .point = raster.toFixed(s[0], s[1]),
            .z = s[2],
            .inv_w = inv_w,
            .vary_w = math.scale(v.vary, inv_w),
        };
    }
};

/// How fast u/w, v/w, and 1/w change from one pixel to the next across a
/// triangle. They are linear on the screen, so this is the same
/// everywhere on it.
const Gradients = struct {
    /// d(u/w)/dx, d(v/w)/dx, d(u/w)/dy, d(v/w)/dy.
    uv_w: Vec4,
    /// d(1/w)/dx twice, then d(1/w)/dy twice.
    inv_w: Vec4,

    fn init(tri: [3]ScreenVertex) Gradients {
        const a, const b, const c = .{ tri[0].point, tri[1].point, tri[2].point };
        // Each weight is an edge function divided by the area (see
        // raster.zig), so it changes by the edge's step per pixel over the
        // area. In fixed point, a step is in units of 1/16 pixel and the
        // area in units of 1/256 pixel^2: one more factor of 16.
        const area: f32 = @floatFromInt(raster.edge(a, b, c));
        const scale = raster.one / area;
        const dx = math.scale(@as(Vec3, @floatFromInt(@Vector(3, i32){ b.y - c.y, c.y - a.y, a.y - b.y })), scale);
        const dy = math.scale(@as(Vec3, @floatFromInt(@Vector(3, i32){ c.x - b.x, a.x - c.x, b.x - a.x })), scale);
        const inv_w: Vec3 = .{ tri[0].inv_w, tri[1].inv_w, tri[2].inv_w };
        const u_w: Vec3 = .{ tri[0].vary_w[uv_lane], tri[1].vary_w[uv_lane], tri[2].vary_w[uv_lane] };
        const v_w: Vec3 = .{ tri[0].vary_w[uv_lane + 1], tri[1].vary_w[uv_lane + 1], tri[2].vary_w[uv_lane + 1] };
        return .{
            .uv_w = .{ math.dot(dx, u_w), math.dot(dx, v_w), math.dot(dy, u_w), math.dot(dy, v_w) },
            .inv_w = .{ math.dot(dx, inv_w), math.dot(dx, inv_w), math.dot(dy, inv_w), math.dot(dy, inv_w) },
        };
    }

    /// How far (u, v) moves for one pixel across or down the screen, at a
    /// pixel where 1/w is `inv_w` and the texture coordinates are `uv`:
    /// the longer of the two. u = (u/w) / (1/w), so by the quotient rule
    /// du/dx = (d(u/w)/dx - u d(1/w)/dx) / (1/w), and the same for v and y.
    fn footprint(g: Gradients, inv_w: f32, u: f32, v: f32) f32 {
        const d = math.scale(g.uv_w - Vec4{ u, v, u, v } * g.inv_w, 1 / inv_w);
        const across = d[0] * d[0] + d[1] * d[1];
        const down = d[2] * d[2] + d[3] * d[3];
        return @sqrt(@max(across, down));
    }
};

/// True if `Shader` declares `wants_footprint = true`: it reads textures
/// and needs to know how big a pixel is on them.
fn wantsFootprint(comptime Shader: type) bool {
    return @hasDecl(Shader, "wants_footprint") and Shader.wants_footprint;
}

/// What the rasterizer calls for each pixel of a triangle: the depth test,
/// then the shader's color.
fn Fragment(comptime Shader: type) type {
    return struct {
        canvas: Canvas,
        depth: []f32,
        depth_test: bool,
        shader: Shader,
        z: Vec3,
        inv_w: Vec3,
        vary_w: [3]Varyings,
        gradients: if (wantsFootprint(Shader)) Gradients else void,
        /// Empty unless overdraw is being counted.
        overdraw: []u8,
        tested: u32 = 0,
        pixels: u32 = 0,

        pub fn pixel(f: *@This(), x: usize, y: usize, weights: Vec3) void {
            const i = y * f.canvas.width + x;
            f.tested += 1;
            if (f.overdraw.len > 0) f.overdraw[i] +|= 1;
            // Depth (z/w) is linear on the screen: plain weights are right.
            const z = math.dot(weights, f.z);
            if (f.depth_test and z >= f.depth[i]) return;
            f.depth[i] = z;
            var vary = interpolate(weights, f.inv_w, f.vary_w);
            if (comptime wantsFootprint(Shader)) {
                vary[footprint_lane] = f.gradients.footprint(math.dot(weights, f.inv_w), vary[uv_lane], vary[uv_lane + 1]);
            }
            f.canvas.pixels[i] = f.shader.pixel(vary);
            f.pixels += 1;
        }
    };
}

pub const Renderer = struct {
    /// Scratch memory for the vertices of the mesh being drawn: where they
    /// are in the world and in clip space, and their varyings.
    world: []Vec3,
    clip: []Vec4,
    vary: []Varyings,
    /// The depth of the nearest thing drawn so far, per pixel of the screen.
    depth: []f32,
    /// How many times each pixel was covered, with `count_overdraw`.
    overdraw: []u8,
    width: usize,
    height: usize,

    pub fn init(gpa: std.mem.Allocator, max_vertices: usize, width: usize, height: usize) !Renderer {
        const world = try gpa.alloc(Vec3, max_vertices);
        errdefer gpa.free(world);
        const clip_pos = try gpa.alloc(Vec4, max_vertices);
        errdefer gpa.free(clip_pos);
        const vary = try gpa.alloc(Varyings, max_vertices);
        errdefer gpa.free(vary);
        const overdraw = try gpa.alloc(u8, width * height);
        errdefer gpa.free(overdraw);
        return .{
            .world = world,
            .clip = clip_pos,
            .vary = vary,
            .overdraw = overdraw,
            .depth = try gpa.alloc(f32, width * height),
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(r: *Renderer, gpa: std.mem.Allocator) void {
        gpa.free(r.depth);
        gpa.free(r.overdraw);
        gpa.free(r.vary);
        gpa.free(r.clip);
        gpa.free(r.world);
        r.* = undefined;
    }

    /// Starts a frame: nothing drawn yet, everything is at the far plane.
    pub fn clearDepth(r: Renderer) void {
        @memset(r.depth, 1);
        @memset(r.overdraw, 0);
    }

    /// Transforms each vertex once, however many triangles share it.
    /// Going through the world position first (instead of multiplying the
    /// two matrices) means a corner shared by two meshes gets exactly the
    /// same clip coordinates from both.
    fn transform(r: Renderer, mesh: Mesh, model: Mat4, view_proj: Mat4) void {
        std.debug.assert(mesh.vertices.len <= r.clip.len);
        for (mesh.vertices, r.world[0..mesh.vertices.len], r.clip[0..mesh.vertices.len]) |v, *world, *pos| {
            world.* = model.transformPoint(v.pos);
            pos.* = view_proj.mulVec(math.vec4(world.*, 1));
        }
    }

    /// The triangle whose indices start at `mesh.indices[i]`, cut to the
    /// view volume, or null if nothing of it is left to draw.
    fn clipTriangle(r: Renderer, mesh: Mesh, i: usize, options: Options, stats: *Stats) ?clip.Polygon {
        stats.triangles += 1;
        var tri: [3]clip.Vertex = undefined;
        var any: clip.Outcode = .empty; // outside of some corner
        var all: clip.Outcode = .full; // outside of every corner
        for (&tri, mesh.indices[i..][0..3]) |*v, index| {
            v.* = .{ .pos = r.clip[index], .vary = r.vary[index] };
            const code = clip.outcode(v.pos);
            any = any.unionWith(code);
            all = all.intersectWith(code);
        }
        if (all.count() > 0) {
            stats.outside += 1;
            return null;
        }
        if (any.contains(.near) and !options.clip_near) {
            stats.behind += 1;
            return null;
        }
        if (options.flat_shading) {
            const average = math.scale(tri[0].vary + tri[1].vary + tri[2].vary, 1.0 / 3.0);
            for (&tri) |*v| v.vary = @select(f32, shading_lanes, average, v.vary);
        }
        if (any.count() > 0) stats.clipped += 1;
        const poly = clip.clipTriangle(tri, any);
        if (poly.len == 0) return null;
        return poly;
    }

    /// Draws the edges of every triangle of `mesh`, placed in the world by
    /// `model` and seen through `view_proj`.
    pub fn drawWireframe(
        r: Renderer,
        canvas: Canvas,
        mesh: Mesh,
        model: Mat4,
        view_proj: Mat4,
        color: Color,
        options: Options,
        stats: *Stats,
    ) void {
        r.transform(mesh, model, view_proj);
        @memset(r.vary[0..mesh.vertices.len], @splat(0));
        var i: usize = 0;
        while (i < mesh.indices.len) : (i += 3) {
            const poly = r.clipTriangle(mesh, i, options, stats) orelse continue;
            var p: [clip.max_vertices]draw.Point = undefined;
            for (poly.vertices(), p[0..poly.len]) |v, *point| {
                const s = camera.toScreen(v.pos, canvas.width, canvas.height);
                point.* = .{ .x = @intFromFloat(@floor(s[0])), .y = @intFromFloat(@floor(s[1])) };
            }
            for (poly.vertices(), 0..) |v, k| {
                const edge_color = if (v.edge) |plane| switch (plane) {
                    .near => near_edge_color,
                    // Edges along the sides of the view volume run
                    // along the edges of the screen: not worth drawing.
                    else => continue,
                } else color;
                draw.line(canvas, p[k], p[(k + 1) % poly.len], edge_color);
            }
            stats.drawn += 1;
        }
    }

    /// Draws `mesh` filled, placed in the world by `model` and seen through
    /// `view_proj`. The `shader` decides the colors: its `vertex(vertex,
    /// world_pos)` returns the varyings of a vertex, and its
    /// `pixel(varyings)` the color of a pixel. The canvas must be the
    /// renderer's size.
    pub fn drawMesh(
        r: Renderer,
        canvas: Canvas,
        mesh: Mesh,
        model: Mat4,
        view_proj: Mat4,
        shader: anytype,
        options: Options,
        stats: *Stats,
    ) void {
        std.debug.assert(canvas.width == r.width and canvas.height == r.height);
        r.transform(mesh, model, view_proj);
        const n = mesh.vertices.len;
        for (mesh.vertices, r.world[0..n], r.vary[0..n]) |v, world, *vary| vary.* = shader.vertex(v, world);

        var i: usize = 0;
        while (i < mesh.indices.len) : (i += 3) {
            const poly = r.clipTriangle(mesh, i, options, stats) orelse continue;
            var screen: [clip.max_vertices]ScreenVertex = undefined;
            for (poly.vertices(), screen[0..poly.len]) |v, *s| s.* = .init(v, r.width, r.height, options.perspective_correct);

            // The polygon is convex: cut it into a fan of triangles around
            // its first corner. They all face the same way.
            var drawn = false;
            var culled = false;
            for (1..poly.len - 1) |k| {
                var tri = [3]ScreenVertex{ screen[0], screen[k], screen[k + 1] };
                const area = raster.edge(tri[0].point, tri[1].point, tri[2].point);
                if (area == 0) continue; // too thin to cover any pixel center
                // The corners of a front face go counter-clockwise as we
                // see them (see mesh.zig), and the picture on the screen
                // looks the same. But `edge` measures with y pointing
                // down, where counter-clockwise is negative. A positive
                // area means we see the triangle's back.
                if (area > 0) {
                    if (options.cull_back_faces) {
                        culled = true;
                        continue;
                    }
                } else {
                    std.mem.swap(ScreenVertex, &tri[1], &tri[2]);
                }
                var fragment: Fragment(@TypeOf(shader)) = .{
                    .canvas = canvas,
                    .depth = r.depth,
                    .depth_test = options.depth_test,
                    .shader = shader,
                    .z = .{ tri[0].z, tri[1].z, tri[2].z },
                    .inv_w = .{ tri[0].inv_w, tri[1].inv_w, tri[2].inv_w },
                    .vary_w = .{ tri[0].vary_w, tri[1].vary_w, tri[2].vary_w },
                    .gradients = if (comptime wantsFootprint(@TypeOf(shader))) .init(tri) else {},
                    .overdraw = if (options.count_overdraw) r.overdraw else &.{},
                };
                raster.fillTriangle(.{ tri[0].point, tri[1].point, tri[2].point }, r.width, r.height, &fragment);
                stats.tested += fragment.tested;
                stats.pixels += fragment.pixels;
                drawn = true;
            }
            if (drawn) stats.drawn += 1 else if (culled) stats.culled += 1;
        }
    }

    /// Paints the depth buffer: black at the eye, fading to white 16 units
    /// away. Depth is not proportional to distance, so it is turned back
    /// into the distance first.
    pub fn drawDepth(r: Renderer, canvas: Canvas) void {
        for (r.depth, canvas.pixels) |z, *pixel| {
            const dist = camera.near * camera.far / (camera.far - z * (camera.far - camera.near));
            const level: u8 = @intFromFloat(255 * std.math.clamp(dist / 16, 0, 1));
            pixel.* = .{ .r = level, .g = level, .b = level };
        }
    }

    /// Paints how many times each pixel was covered, counted with
    /// `count_overdraw`: black for none, blue for once, through green and
    /// yellow to red for `overdraw_colors.len - 1` times or more.
    pub fn drawOverdraw(r: Renderer, canvas: Canvas) void {
        for (r.overdraw, canvas.pixels) |n, *pixel| {
            pixel.* = overdraw_colors[@min(n, overdraw_colors.len - 1)];
        }
    }
};

pub const overdraw_colors = [_]Color{
    .hex(0x000000), .hex(0x2040a0), .hex(0x2090b0), .hex(0x30a040), .hex(0xa0c030),
    .hex(0xe0c020), .hex(0xe08020), .hex(0xd03020), .hex(0xffffff),
};

test "a cube in front is drawn, a cube behind is not" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 40);
    defer r.deinit(gpa);
    const cube = @import("mesh.zig").cube;

    // The default camera at the origin looks down -z.
    const vp = camera.Camera.projection(64, 40);
    var stats: Stats = .{};
    r.drawWireframe(canvas, cube, Mat4.translation(.{ -0.5, -0.5, -3 }), vp, Color.white, .{}, &stats);
    try std.testing.expectEqual(Stats{ .triangles = 12, .drawn = 12 }, stats);
    // The diagonals of the front and back faces cross the screen center.
    try std.testing.expectEqual(Color.white, canvas.get(32, 20));

    stats = .{};
    r.drawWireframe(canvas, cube, Mat4.translation(.{ -0.5, -0.5, 2 }), vp, Color.white, .{}, &stats);
    try std.testing.expectEqual(Stats{ .triangles = 12, .outside = 12 }, stats);
}

test "overdraw counts every triangle that covers a pixel" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 40);
    defer r.deinit(gpa);
    const cube = @import("mesh.zig").cube;
    const vp = camera.Camera.projection(64, 40);
    const model = Mat4.translation(.{ -0.5, -0.5, -3 });
    const white: Flat = .{ .color = Color.white };

    // Without culling, the front face and the back face cover the middle.
    r.clearDepth();
    var stats: Stats = .{};
    r.drawMesh(canvas, cube, model, vp, white, .{ .cull_back_faces = false, .count_overdraw = true }, &stats);
    try std.testing.expectEqual(2, r.overdraw[20 * 64 + 32]);
    var covered: u32 = 0;
    for (r.overdraw) |n| covered += n;
    try std.testing.expectEqual(stats.tested, covered);
    try std.testing.expect(stats.pixels < stats.tested);

    r.drawOverdraw(canvas);
    try std.testing.expectEqual(overdraw_colors[2], canvas.get(32, 20));
    try std.testing.expectEqual(overdraw_colors[0], canvas.get(0, 0));
}

test "clipping keeps what dropping whole triangles loses" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 40);
    defer r.deinit(gpa);
    const cube = @import("mesh.zig").cube;
    const vp = camera.Camera.projection(64, 40);

    // The eye is inside the cube, near its back face. The side faces
    // reach behind the eye, and their far ends are in view.
    const model = Mat4.translation(.{ -0.5, -0.5, -0.9 });
    var stats: Stats = .{};
    r.drawWireframe(canvas, cube, model, vp, Color.white, .{}, &stats);
    try std.testing.expect(stats.clipped > 0 and stats.behind == 0);
    const drawn = stats.drawn;

    stats = .{};
    r.drawWireframe(canvas, cube, model, vp, Color.white, .{ .clip_near = false }, &stats);
    try std.testing.expect(stats.behind > 0 and stats.drawn < drawn);
}

/// One flat color for everything.
const Flat = struct {
    color: Color,

    pub fn vertex(f: Flat, _: @import("mesh.zig").Vertex, _: Vec3) Varyings {
        return fromColor(f.color);
    }

    pub fn pixel(_: Flat, vary: Varyings) Color {
        return toColor(vary);
    }
};

test "only the faces turned toward the camera are drawn" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 40);
    defer r.deinit(gpa);
    const cube = @import("mesh.zig").cube;
    const vp = camera.Camera.projection(64, 40);
    const model = Mat4.translation(.{ -0.5, -0.5, -3 });
    const white: Flat = .{ .color = Color.white };

    // Straight ahead, only the face toward +z faces the camera.
    r.clearDepth();
    var stats: Stats = .{};
    r.drawMesh(canvas, cube, model, vp, white, .{}, &stats);
    try std.testing.expectEqual(10, stats.culled);
    try std.testing.expectEqual(2, stats.drawn);
    const front_pixels = stats.pixels;
    try std.testing.expect(front_pixels > 0);
    try std.testing.expectEqual(Color.white, canvas.get(32, 20));

    // Without culling the back faces are drawn first or last: either way
    // the depth test keeps the front face's pixels, at extra cost.
    r.clearDepth();
    stats = .{};
    r.drawMesh(canvas, cube, model, vp, white, .{ .cull_back_faces = false }, &stats);
    try std.testing.expect(stats.culled == 0 and stats.drawn > 2 and stats.pixels > front_pixels);
}

test "with a depth test the drawing order does not matter" {
    const gpa = std.testing.allocator;
    const cube = @import("mesh.zig").cube;
    const vp = camera.Camera.projection(64, 40);
    // Two cubes, one partly in front of the other.
    const near_cube = Mat4.translation(.{ -0.8, -0.5, -3 });
    const far_cube = Mat4.translation(.{ -0.3, -0.7, -4 });
    var canvases: [2]Canvas = .{ try Canvas.init(gpa, 64, 40), try Canvas.init(gpa, 64, 40) };
    defer for (&canvases) |*canvas| canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 40);
    defer r.deinit(gpa);
    const red: Flat = .{ .color = .hex(0xff0000) };
    const green: Flat = .{ .color = .hex(0x00ff00) };
    var stats: Stats = .{};

    r.clearDepth();
    r.drawMesh(canvases[0], cube, near_cube, vp, red, .{}, &stats);
    r.drawMesh(canvases[0], cube, far_cube, vp, green, .{}, &stats);
    r.clearDepth();
    r.drawMesh(canvases[1], cube, far_cube, vp, green, .{}, &stats);
    r.drawMesh(canvases[1], cube, near_cube, vp, red, .{}, &stats);
    try std.testing.expectEqualSlices(Color, canvases[0].pixels, canvases[1].pixels);
    // Both cubes are partly visible.
    var seen: [2]bool = .{ false, false };
    for (canvases[0].pixels) |p| {
        if (p.r == 255) seen[0] = true;
        if (p.g == 255) seen[1] = true;
    }
    try std.testing.expect(seen[0] and seen[1]);
}

/// Colors a mesh by where each point is in it: red grows along x.
const Ramp = struct {
    pub fn vertex(_: Ramp, v: @import("mesh.zig").Vertex, _: Vec3) Varyings {
        return .{ 255 * v.pos[0], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    }

    pub fn pixel(_: Ramp, vary: Varyings) Color {
        return toColor(vary);
    }
};

test "flat shading gives each triangle one color" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 40);
    defer r.deinit(gpa);
    const front = @import("mesh.zig").cubeFace(4);
    const vp = camera.Camera.projection(64, 40);
    const model = Mat4.translation(.{ -0.5, -0.5, -2 });
    var stats: Stats = .{};
    for ([_]bool{ false, true }) |flat| {
        canvas.clear(Color.black);
        r.clearDepth();
        r.drawMesh(canvas, front, model, vp, Ramp{}, .{ .flat_shading = flat }, &stats);
        // Count the different reds on the screen.
        var seen: std.StaticBitSet(256) = .empty;
        for (canvas.pixels) |p| if (p.r != 0) seen.set(p.r);
        if (flat) {
            // The face's two triangles: corners 0, 1, 2 (x = 0, 1, 1) and
            // 0, 2, 3 (x = 0, 1, 0) average to 2/3 and 1/3 of 255.
            try std.testing.expectEqual(2, seen.count());
            try std.testing.expect(seen.isSet(170) and seen.isSet(85));
        } else {
            try std.testing.expect(seen.count() > 20);
        }
    }
}

test "varyings are interpolated with perspective" {
    // An edge from a corner at w = 1 to one at w = 4, with a value going
    // from 0 to 1. Halfway across the screen is not halfway along the
    // edge: the far half looks smaller. Points on the edge are
    // (-1 + 5t, 1 + 3t) in (x, w); the screen x is x / w, which is 0
    // (halfway between -1 and 1) at t = 0.2.
    const v = interpolate(.{ 0.5, 0.5, 0 }, .{ 1, 0.25, 1 }, .{ @splat(0), @splat(0.25), @splat(0) });
    try std.testing.expectApproxEqAbs(0.2, v[0], 1e-6);
}

/// Shows one varying as the red channel, times `scale`; the texture
/// coordinates are the mesh's.
const Show = struct {
    lane: usize,
    scale: f32,
    pub const wants_footprint = true;

    pub fn vertex(_: Show, v: @import("mesh.zig").Vertex, _: Vec3) Varyings {
        var vary: Varyings = @splat(0);
        vary[uv_lane] = v.uv[0];
        vary[uv_lane + 1] = v.uv[1];
        return vary;
    }

    pub fn pixel(s: Show, vary: Varyings) Color {
        var red: Varyings = @splat(0);
        const lanes: [16]f32 = vary;
        red[0] = lanes[s.lane] * s.scale;
        return toColor(red);
    }
};

test "affine interpolation is wrong on a face seen at an angle" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 64);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 64);
    defer r.deinit(gpa);
    // A floor 0.5 below the eye from z = -1 to z = -5, texture v going
    // from 0 at the far edge to 1 at the near one. On the screen a floor
    // point appears 0.5/d below the horizon; the near edge is at 0.5,
    // the far one at 0.1, and the row halfway, at 0.3, sees the floor at
    // d = 5/3. That is 1/6 of the way from the near edge, so v = 5/6.
    const floor = @import("mesh.zig").cubeFace(2);
    const model = Mat4.translation(.{ -0.5, -0.5, -5 }).mul(.scaling(.{ 1, 1, 4 })).mul(.translation(.{ 0, -1, 0 }));
    const vp = camera.Camera.projection(64, 64);
    // vfov is 2 atan(0.5): 0.5 below the horizon is the bottom of the
    // screen, so 0.3 is 32 + 32 * 0.3 / 0.5 = 51.2 pixels down.
    const show: Show = .{ .lane = uv_lane + 1, .scale = 255 };
    var stats: Stats = .{};
    for ([_]bool{ true, false }, [_]f32{ 5.0 / 6.0, 0.5 }) |perspective, v| {
        r.clearDepth();
        r.drawMesh(canvas, floor, model, vp, show, .{ .perspective_correct = perspective }, &stats);
        // Row 51, pixel center at 51.5: close to halfway.
        try std.testing.expectApproxEqAbs(255 * v, @as(f32, @floatFromInt(canvas.get(32, 51).r)), 255 * 0.02);
    }
}

test "the footprint is the size of a pixel on the texture" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24, 64, 40);
    defer r.deinit(gpa);
    const front = @import("mesh.zig").cubeFace(4);
    const vp = camera.Camera.projection(64, 40);
    // The face is the cube's side at z = 1, moved to z = -2. The screen
    // is 40 pixels high, and at distance 2 it shows 2 units:
    // a face 1 wide covers 20 pixels, so one pixel covers 1/20 of the
    // texture, wherever it is on the face.
    const show: Show = .{ .lane = footprint_lane, .scale = 1000 };
    var stats: Stats = .{};
    for ([_]bool{ true, false }) |perspective| {
        r.clearDepth();
        r.drawMesh(canvas, front, .translation(.{ -0.5, -0.5, -3 }), vp, show, .{ .perspective_correct = perspective }, &stats);
        for ([_][2]usize{ .{ 32, 20 }, .{ 25, 13 }, .{ 40, 28 } }) |p| {
            try std.testing.expectEqual(50, canvas.get(p[0], p[1]).r);
        }
    }
    // Twice as far, twice the footprint.
    r.clearDepth();
    r.drawMesh(canvas, front, .translation(.{ -0.5, -0.5, -5 }), vp, show, .{}, &stats);
    try std.testing.expectEqual(100, canvas.get(32, 20).r);
}
