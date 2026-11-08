//! The program's state and drawing, independent of any window. main.zig
//! calls `update` once per tick and `render` once per frame.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const font = @import("font.zig");
const Map = @import("map.zig").Map;
const Player = @import("player.zig").Player;
const Input = @import("input.zig").Input;
const mapview = @import("mapview.zig");
const raycast = @import("raycast.zig");

const default_map = @embedFile("maps/cellar.txt");

/// What fills the screen. Tab cycles through them.
pub const View = enum { first_person, map_fixed, map_follow };

pub const App = struct {
    map: Map,
    player: Player,
    view: View = .first_person,
    raycast_options: raycast.Options = .{},
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
        if (input.pressed.contains(.next_view)) {
            const views = std.enums.values(View);
            app.view = views[(@backingInt(app.view) + 1) % views.len];
        }
        if (input.pressed.contains(.toggle_fisheye)) {
            app.raycast_options.fisheye = !app.raycast_options.fisheye;
        }
        app.player.update(input, app.map, dt);
        app.time += dt;
        app.ticks += 1;
    }

    pub fn render(app: App, canvas: Canvas) void {
        const p = app.player;
        switch (app.view) {
            .first_person => raycast.render(canvas, app.map, .init(p.pos, p.yaw), app.raycast_options),
            .map_fixed, .map_follow => {
                canvas.clear(.hex(0x101018));
                const style: mapview.Style = if (app.view == .map_fixed) .fixed else .follow;
                _ = mapview.drawMap(canvas, app.map, p, mapview.transform(style, p, canvas));
            },
        }

        var buffer: [96]u8 = undefined;
        const status = std.fmt.bufPrint(&buffer, "pos {d:.2},{d:.2}  yaw {d:.0}{s}", .{
            p.pos[0],
            p.pos[1],
            std.math.radiansToDegrees(p.yaw),
            if (app.raycast_options.fisheye) "  fisheye" else "",
        }) catch unreachable;
        const h: i32 = @intCast(canvas.height);
        _ = font.drawText(canvas, 8, h - 12, status, 1, Color.white);
    }
};
