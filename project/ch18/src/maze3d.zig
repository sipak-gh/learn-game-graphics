//! The maze in 3D: every wall cell is a unit cube standing on the floor.
//! A map cell (x, y) becomes the cube from (x, 0, y) to (x + 1, 1, y + 1).
//! Every floor cell gets a square of floor at height 0 and of ceiling at
//! height 1.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Map = @import("map.zig").Map;
const Tile = @import("map.zig").Tile;
const mesh = @import("mesh.zig");
const cube = mesh.cube;
const render3d = @import("render3d.zig");
const raycast = @import("raycast.zig");

fn wireColor(tile: Tile) Color {
    return switch (tile) {
        .floor => unreachable,
        .brick => .hex(0xe08050),
        .stone => .hex(0xb0b0c0),
    };
}

/// True if wall cell (x, y) has a floor cell next to it. Walls buried
/// among other walls can never be seen, so they are not drawn.
pub fn touchesFloor(map: Map, x: i32, y: i32) bool {
    for ([_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |d| {
        if (!map.at(x + d[0], y + d[1]).isWall()) return true;
    }
    return false;
}

/// Draws the edges of every visible wall cube.
pub fn drawWireframe(
    r: render3d.Renderer,
    canvas: Canvas,
    map: Map,
    view_proj: Mat4,
    options: render3d.Options,
    stats: *render3d.Stats,
) void {
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const tile = map.at(@intCast(x), @intCast(y));
            if (!tile.isWall() or !touchesFloor(map, @intCast(x), @intCast(y))) continue;
            const model = Mat4.translation(.{ @floatFromInt(x), 0, @floatFromInt(y) });
            r.drawWireframe(canvas, cube, model, view_proj, wireColor(tile), options, stats);
        }
    }
}

/// Paints each face one flat color, the way the ray caster does without
/// textures: faces across the map's y (along the world's z) are darker.
pub const FlatShader = struct {
    color: Color,

    pub fn vertex(s: FlatShader, v: mesh.Vertex, _: Vec3) render3d.Varyings {
        const shade: f32 = if (v.normal[2] != 0) raycast.y_side_shade else 1;
        return render3d.fromColor(s.color.scale(shade));
    }

    pub fn pixel(_: FlatShader, vary: render3d.Varyings) Color {
        return render3d.toColor(vary);
    }
};

const floor_face = mesh.cubeFace(2); // the top of a cube, facing up
const ceiling_face = mesh.cubeFace(3); // the bottom, facing down

/// Draws the maze with flat colors: the visible wall cubes, and the floor
/// and ceiling over every floor cell.
pub fn drawSolid(
    r: render3d.Renderer,
    canvas: Canvas,
    map: Map,
    view_proj: Mat4,
    options: render3d.Options,
    stats: *render3d.Stats,
) void {
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const tile = map.at(@intCast(x), @intCast(y));
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);
            if (tile.isWall()) {
                if (!touchesFloor(map, @intCast(x), @intCast(y))) continue;
                const shader: FlatShader = .{ .color = raycast.wallColor(tile) };
                r.drawMesh(canvas, cube, .translation(.{ fx, 0, fy }), view_proj, shader, options, stats);
            } else {
                const floor: FlatShader = .{ .color = raycast.floor_color };
                r.drawMesh(canvas, floor_face, .translation(.{ fx, -1, fy }), view_proj, floor, options, stats);
                const ceiling: FlatShader = .{ .color = raycast.ceiling_color };
                r.drawMesh(canvas, ceiling_face, .translation(.{ fx, 1, fy }), view_proj, ceiling, options, stats);
            }
        }
    }
}

test "only walls next to the floor are drawn" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa,
        \\#####
        \\#>..#
        \\#####
    );
    defer map.deinit(gpa);
    try std.testing.expect(touchesFloor(map, 0, 1));
    try std.testing.expect(touchesFloor(map, 2, 0));
    try std.testing.expect(!touchesFloor(map, 0, 0)); // a corner: walls all around
    try std.testing.expect(!touchesFloor(map, -1, 1)); // outside the map
}

test "the maze has no cracks" {
    // Everywhere the eye looks inside the maze there is a wall, the floor,
    // or the ceiling. Any pixel left in the clear color is a crack.
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa, @embedFile("maps/cellar.txt"));
    defer map.deinit(gpa);
    var canvas = try Canvas.init(gpa, 160, 100);
    defer canvas.deinit(gpa);
    var r = try render3d.Renderer.init(gpa, 24, 160, 100);
    defer r.deinit(gpa);
    const camera = @import("camera.zig");
    const crack: Color = .hex(0xff00ff);
    for ([_][3]f32{ .{ 9.5, 10.5, -1 }, .{ 1.5, 1.5, 0.6 }, .{ 20.3, 13.7, 2.5 }, .{ 12.5, 18.5, 3.1 } }) |pose| {
        const cam: camera.Camera = .{ .pos = .{ pose[0], camera.eye_height, pose[1] }, .yaw = pose[2], .pitch = 0.3 * pose[2] };
        canvas.clear(crack);
        r.clearDepth();
        var stats: render3d.Stats = .{};
        drawSolid(r, canvas, map, cam.viewProjection(160, 100), .{}, &stats);
        for (canvas.pixels) |p| try std.testing.expect(!std.meta.eql(p, crack));
        try std.testing.expect(stats.pixels >= 160 * 100);
    }
}
