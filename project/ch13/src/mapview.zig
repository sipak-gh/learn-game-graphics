//! The map seen from above, drawn through a matrix.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Map = @import("map.zig").Map;
const Tile = @import("map.zig").Tile;
const Player = @import("player.zig").Player;
const raycast = @import("raycast.zig");

pub const Style = enum { fixed, follow };

/// The matrix that takes map coordinates to canvas pixels. Read each
/// product right to left: that is the order the steps apply to a point.
pub fn transform(style: Style, player: Player, canvas: Canvas) Mat4 {
    switch (style) {
        // Scale cells to 16 pixels, then move the map's corner to (64, 8).
        .fixed => return Mat4.translation(.{ 64, 8, 0 }).mul(Mat4.scaling(.{ 16, 16, 1 })),
        // Move the player to the origin, turn so the player faces up
        // (angle -90 degrees), scale up, and move to the screen center.
        .follow => {
            const center: Vec3 = .{ @floatFromInt(canvas.width / 2), @floatFromInt(canvas.height / 2), 0 };
            return Mat4.translation(center)
                .mul(Mat4.scaling(.{ 32, 32, 1 }))
                .mul(Mat4.rotationZ(-std.math.pi / 2.0 - player.yaw))
                .mul(Mat4.translation(.{ -player.pos[0], -player.pos[1], 0 }));
        },
    }
}

/// Applies `m` to a point on the map (z = 0) and rounds to a pixel.
fn toScreen(m: Mat4, p: Vec2) draw.Point {
    const s = m.transformPoint(.{ p[0], p[1], 0 });
    return .{ .x = @intFromFloat(@round(s[0])), .y = @intFromFloat(@round(s[1])) };
}

fn tileColor(tile: Tile) Color {
    return switch (tile) {
        .floor => .hex(0x2a2a30),
        .brick => .hex(0x8c4a32),
        .stone => .hex(0x6e6e78),
    };
}

/// The map from above, through the matrix `to_screen`, and the player as a
/// dot with its facing direction and field of view. Returns how many cells
/// it drew.
pub fn drawMap(canvas: Canvas, map: Map, player: Player, to_screen: Mat4) usize {
    // Only draw cells that can be on screen: run the canvas corners through
    // the inverse matrix to find which part of the map they cover.
    const to_map = to_screen.inverse() orelse return 0;
    const w: f32 = @floatFromInt(canvas.width);
    const h: f32 = @floatFromInt(canvas.height);
    var lo: Vec2 = @splat(std.math.inf(f32));
    var hi: Vec2 = @splat(-std.math.inf(f32));
    for ([_]Vec3{ .{ 0, 0, 0 }, .{ w, 0, 0 }, .{ 0, h, 0 }, .{ w, h, 0 } }) |corner| {
        const m = to_map.transformPoint(corner);
        lo = @min(lo, Vec2{ m[0], m[1] });
        hi = @max(hi, Vec2{ m[0], m[1] });
    }
    const map_size: Vec2 = .{ @floatFromInt(map.width), @floatFromInt(map.height) };
    const first: @Vector(2, usize) = @intFromFloat(@max(@floor(lo), Vec2{ 0, 0 }));
    const last: @Vector(2, usize) = @intFromFloat(@min(@ceil(hi), map_size));

    var drawn: usize = 0;
    for (first[1]..last[1]) |y| {
        for (first[0]..last[0]) |x| {
            // A rotated square is no longer a rectangle: draw it as two
            // triangles, inset a little so the grid shows between cells.
            const corner: Vec2 = .{ @floatFromInt(x), @floatFromInt(y) };
            const a = toScreen(to_screen, corner + Vec2{ 0.05, 0.05 });
            const b = toScreen(to_screen, corner + Vec2{ 0.95, 0.05 });
            const c = toScreen(to_screen, corner + Vec2{ 0.95, 0.95 });
            const d = toScreen(to_screen, corner + Vec2{ 0.05, 0.95 });
            const color = tileColor(map.at(@intCast(x), @intCast(y)));
            draw.fillTriangle(canvas, a, b, c, color);
            draw.fillTriangle(canvas, a, c, d, color);
            drawn += 1;
        }
    }

    // Every 16th camera ray, from the eye to the wall it hits.
    const cam = raycast.Camera.init(player.pos, player.yaw);
    const eye = toScreen(to_screen, player.pos);
    var x: usize = 8;
    while (x < canvas.width) : (x += 16) {
        const ray = cam.ray(x, canvas.width);
        const hit = raycast.cast(map, cam.pos, ray);
        draw.line(canvas, eye, toScreen(to_screen, cam.pos + math.scale(ray, hit.t)), .hex(0x908040));
    }
    // The camera plane, one unit in front of the eye.
    const plane_left = toScreen(to_screen, cam.pos + cam.dir - cam.plane);
    const plane_right = toScreen(to_screen, cam.pos + cam.dir + cam.plane);
    draw.line(canvas, plane_left, plane_right, .hex(0x60c0ff));
    draw.line(canvas, eye, toScreen(to_screen, player.pos + cam.dir), .hex(0xffe060));
    draw.fillCircle(canvas, eye, 4, .hex(0xffe060));
    return drawn;
}
