//! The program's state and drawing, independent of any window. main.zig
//! calls `update` once per tick and `render` once per frame.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");
const font = @import("font.zig");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Map = @import("map.zig").Map;
const Tile = @import("map.zig").Tile;
const Player = @import("player.zig").Player;
const Input = @import("input.zig").Input;

const default_map = @embedFile("maps/cellar.txt");

pub const App = struct {
    map: Map,
    player: Player,
    /// Seconds of simulated time.
    time: f32 = 0,
    ticks: u32 = 0,

    pub fn init(gpa: std.mem.Allocator) !App {
        const map = try Map.parse(gpa, default_map);
        return .{ .map = map, .player = .{ .pos = map.start, .yaw = map.start_yaw } };
    }

    pub fn deinit(app: *App, gpa: std.mem.Allocator) void {
        app.map.deinit(gpa);
    }

    pub fn update(app: *App, input: Input, dt: f32) void {
        app.player.update(input, app.map, dt);
        app.time += dt;
        app.ticks += 1;
    }

    pub fn render(app: App, canvas: Canvas) void {
        canvas.clear(.hex(0x101018));
        drawMap(canvas, app.map, app.player);

        var buffer: [64]u8 = undefined;
        const p = app.player;
        const status = std.fmt.bufPrint(&buffer, "pos {d:.2},{d:.2}  yaw {d:.0}", .{
            p.pos[0], p.pos[1], std.math.radiansToDegrees(p.yaw),
        }) catch unreachable;
        const h: i32 = @intCast(canvas.height);
        _ = font.drawText(canvas, 8, h - 12, status, 1, Color.white);
    }
};

/// Pixels per map cell in the top-down view, and where the map starts.
const cell_px = 16;
const origin: Vec2 = .{ 64, 8 };

fn toScreen(p: Vec2) draw.Point {
    const s = origin + math.scale(p, cell_px);
    return .{ .x = @intFromFloat(@round(s[0])), .y = @intFromFloat(@round(s[1])) };
}

fn tileColor(tile: Tile) Color {
    return switch (tile) {
        .floor => .hex(0x2a2a30),
        .brick => .hex(0x8c4a32),
        .stone => .hex(0x6e6e78),
    };
}

/// The map from above: one square per cell, and the player as a dot with
/// its facing direction and field of view.
fn drawMap(canvas: Canvas, map: Map, player: Player) void {
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const tile = map.at(@intCast(x), @intCast(y));
            const corner = toScreen(.{ @floatFromInt(x), @floatFromInt(y) });
            draw.fillRect(canvas, corner.x, corner.y, cell_px - 1, cell_px - 1, tileColor(tile));
        }
    }

    const dir = player.dir();
    // The edges of the view: the facing direction plus or minus a sideways
    // vector. Chapter 13 explains the 0.8.
    const side = math.scale(math.perp(dir), 0.8);
    const eye = toScreen(player.pos);
    draw.line(canvas, eye, toScreen(player.pos + math.scale(dir + side, 3)), .hex(0x707040));
    draw.line(canvas, eye, toScreen(player.pos + math.scale(dir - side, 3)), .hex(0x707040));
    draw.line(canvas, eye, toScreen(player.pos + dir), .hex(0xffe060));
    draw.fillCircle(canvas, eye, 4, .hex(0xffe060));
}
