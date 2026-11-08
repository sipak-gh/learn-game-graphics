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

pub const Varyings = clip.Varyings;

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
    /// Pixels that passed the depth test and were written.
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
};

/// The color of edges made by the near plane in the wireframe.
pub const near_edge_color: Color = .hex(0xff40ff);

/// A color as varyings: red, green, and blue, 0 to 255, in lanes 0 to 2.
pub fn fromColor(c: Color) Varyings {
    return .{ @floatFromInt(c.r), @floatFromInt(c.g), @floatFromInt(c.b), 0, 0, 0, 0, 0 };
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

    fn init(v: clip.Vertex, width: usize, height: usize) ScreenVertex {
        const s = camera.toScreen(v.pos, width, height);
        const inv_w = 1 / v.pos[3];
        return .{
            .point = raster.toFixed(s[0], s[1]),
            .z = s[2],
            .inv_w = inv_w,
            .vary_w = math.scale(v.vary, inv_w),
        };
    }
};

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
        pixels: u32 = 0,

        pub fn pixel(f: *@This(), x: usize, y: usize, weights: Vec3) void {
            const i = y * f.canvas.width + x;
            // Depth (z/w) is linear on the screen: plain weights are right.
            const z = math.dot(weights, f.z);
            if (f.depth_test and z >= f.depth[i]) return;
            f.depth[i] = z;
            f.canvas.pixels[i] = f.shader.pixel(interpolate(weights, f.inv_w, f.vary_w));
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
    width: usize,
    height: usize,

    pub fn init(gpa: std.mem.Allocator, max_vertices: usize, width: usize, height: usize) !Renderer {
        const world = try gpa.alloc(Vec3, max_vertices);
        errdefer gpa.free(world);
        const clip_pos = try gpa.alloc(Vec4, max_vertices);
        errdefer gpa.free(clip_pos);
        const vary = try gpa.alloc(Varyings, max_vertices);
        errdefer gpa.free(vary);
        return .{
            .world = world,
            .clip = clip_pos,
            .vary = vary,
            .depth = try gpa.alloc(f32, width * height),
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(r: *Renderer, gpa: std.mem.Allocator) void {
        gpa.free(r.depth);
        gpa.free(r.vary);
        gpa.free(r.clip);
        gpa.free(r.world);
        r.* = undefined;
    }

    /// Starts a frame: nothing drawn yet, everything is at the far plane.
    pub fn clearDepth(r: Renderer) void {
        @memset(r.depth, 1);
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
            for (&tri) |*v| v.vary = average;
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
            for (poly.vertices(), screen[0..poly.len]) |v, *s| s.* = .init(v, r.width, r.height);

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
                };
                raster.fillTriangle(.{ tri[0].point, tri[1].point, tri[2].point }, r.width, r.height, &fragment);
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
        return .{ 255 * v.pos[0], 0, 0, 0, 0, 0, 0, 0 };
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
