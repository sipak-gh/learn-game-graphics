//! The maze in 3D: every wall cell is a unit cube standing on the floor.
//! A map cell (x, y) becomes the cube from (x, 0, y) to (x + 1, 1, y + 1).
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const Mat4 = @import("math.zig").Mat4;
const Map = @import("map.zig").Map;
const Tile = @import("map.zig").Tile;
const cube = @import("mesh.zig").cube;
const render3d = @import("render3d.zig");

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
pub fn drawWireframe(r: render3d.Renderer, canvas: Canvas, map: Map, view_proj: Mat4, stats: *render3d.Stats) void {
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const tile = map.at(@intCast(x), @intCast(y));
            if (!tile.isWall() or !touchesFloor(map, @intCast(x), @intCast(y))) continue;
            const model = Mat4.translation(.{ @floatFromInt(x), 0, @floatFromInt(y) });
            r.drawWireframe(canvas, cube, model, view_proj, wireColor(tile), stats);
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
