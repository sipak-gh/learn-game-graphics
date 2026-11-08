//! The 3D pipeline: a mesh and its matrices go in, pixels come out.
//! Every vertex is transformed once into clip space, then every triangle
//! is clipped to the view volume, projected to the screen, and drawn, for
//! now as lines.
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
    drawn: u32 = 0,
};

pub const Options = struct {
    /// Clip triangles against the near plane. Without it, a triangle with
    /// a corner behind the near plane is dropped whole, as in chapter 16.
    clip_near: bool = true,
};

/// The color of edges made by the near plane in the wireframe.
pub const near_edge_color: Color = .hex(0xff40ff);

pub const Renderer = struct {
    /// Scratch memory: the vertices of the mesh being drawn, in clip space.
    clip: []Vec4,

    pub fn init(gpa: std.mem.Allocator, max_vertices: usize) !Renderer {
        return .{ .clip = try gpa.alloc(Vec4, max_vertices) };
    }

    pub fn deinit(r: *Renderer, gpa: std.mem.Allocator) void {
        gpa.free(r.clip);
        r.* = undefined;
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
        std.debug.assert(mesh.vertices.len <= r.clip.len);
        // Transform each vertex once, however many triangles share it.
        // Going through the world position first (instead of multiplying
        // the two matrices) means a corner shared by two meshes gets
        // exactly the same clip coordinates from both.
        for (mesh.vertices, r.clip[0..mesh.vertices.len]) |v, *pos| {
            const world = model.transformPoint(v.pos);
            pos.* = view_proj.mulVec(math.vec4(world, 1));
        }

        var i: usize = 0;
        while (i < mesh.indices.len) : (i += 3) {
            stats.triangles += 1;
            var tri: [3]clip.Vertex = undefined;
            var any: clip.Outcode = .empty; // outside of some corner
            var all: clip.Outcode = .full; // outside of every corner
            for (&tri, mesh.indices[i..][0..3]) |*v, index| {
                v.* = .{ .pos = r.clip[index] };
                const code = clip.outcode(v.pos);
                any = any.unionWith(code);
                all = all.intersectWith(code);
            }
            if (all.count() > 0) {
                stats.outside += 1;
                continue;
            }
            if (any.contains(.near) and !options.clip_near) {
                stats.behind += 1;
                continue;
            }
            if (any.count() > 0) stats.clipped += 1;
            const poly = clip.clipTriangle(tri, any);
            if (poly.len == 0) continue;

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
};

test "a cube in front is drawn, a cube behind is not" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 64, 40);
    defer canvas.deinit(gpa);
    var r = try Renderer.init(gpa, 24);
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
    var r = try Renderer.init(gpa, 24);
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
