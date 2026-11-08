//! The 3D pipeline: a mesh and its matrices go in, pixels come out.
//! Every vertex is transformed once into clip space, then every triangle
//! is projected to the screen and drawn, for now as three lines.
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

/// Counts of what happened to the triangles of a frame.
pub const Stats = struct {
    triangles: u32 = 0,
    /// Thrown away because a corner was behind the near plane.
    behind: u32 = 0,
    drawn: u32 = 0,
};

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
        stats: *Stats,
    ) void {
        std.debug.assert(mesh.vertices.len <= r.clip.len);
        // Transform each vertex once, however many triangles share it.
        // Going through the world position first (instead of multiplying
        // the two matrices) means a corner shared by two meshes gets
        // exactly the same clip coordinates from both.
        for (mesh.vertices, r.clip[0..mesh.vertices.len]) |v, *clip| {
            const world = model.transformPoint(v.pos);
            clip.* = view_proj.mulVec(math.vec4(world, 1));
        }

        var i: usize = 0;
        while (i < mesh.indices.len) : (i += 3) {
            stats.triangles += 1;
            const tri = [3]Vec4{
                r.clip[mesh.indices[i]],
                r.clip[mesh.indices[i + 1]],
                r.clip[mesh.indices[i + 2]],
            };
            // The naive way to deal with points behind the eye: drop the
            // whole triangle. Chapter 17 does better.
            if (tri[0][3] < camera.near or tri[1][3] < camera.near or tri[2][3] < camera.near) {
                stats.behind += 1;
                continue;
            }
            var p: [3]draw.Point = undefined;
            for (tri, &p) |clip, *point| {
                const s = camera.toScreen(clip, canvas.width, canvas.height);
                point.* = .{ .x = @intFromFloat(@floor(s[0])), .y = @intFromFloat(@floor(s[1])) };
            }
            draw.line(canvas, p[0], p[1], color);
            draw.line(canvas, p[1], p[2], color);
            draw.line(canvas, p[2], p[0], color);
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
    r.drawWireframe(canvas, cube, Mat4.translation(.{ -0.5, -0.5, -3 }), vp, Color.white, &stats);
    try std.testing.expectEqual(Stats{ .triangles = 12, .behind = 0, .drawn = 12 }, stats);
    // The diagonals of the front and back faces cross the screen center.
    try std.testing.expectEqual(Color.white, canvas.get(32, 20));

    stats = .{};
    r.drawWireframe(canvas, cube, Mat4.translation(.{ -0.5, -0.5, 2 }), vp, Color.white, &stats);
    try std.testing.expectEqual(Stats{ .triangles = 12, .behind = 12, .drawn = 0 }, stats);

    // Half in front of the eye, half behind: the triangles that reach
    // behind the near plane are lost.
    stats = .{};
    r.drawWireframe(canvas, cube, Mat4.translation(.{ -0.5, -0.5, -0.5 }), vp, Color.white, &stats);
    try std.testing.expect(stats.behind > 0 and stats.drawn > 0);
}
