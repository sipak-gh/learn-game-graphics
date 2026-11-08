//! The program's state and drawing, independent of any window. main.zig
//! calls `update` once per tick and `render` once per frame.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const font = @import("font.zig");
const draw = @import("draw.zig");
const Map = @import("map.zig").Map;
const Player = @import("player.zig").Player;
const Input = @import("input.zig").Input;
const mapview = @import("mapview.zig");
const raycast = @import("raycast.zig");
const texture = @import("texture.zig");
const camera = @import("camera.zig");
const Mat4 = @import("math.zig").Mat4;

const default_map = @embedFile("maps/cellar.txt");

/// What fills the screen. Tab cycles through them.
pub const View = enum { first_person, map_fixed, map_follow };

const minimap_width = 160;
const minimap_height = 112;

pub const App = struct {
    map: Map,
    player: Player,
    textures: texture.Set,
    renderer: raycast.Renderer,
    /// The minimap is drawn on its own small canvas, then copied into the
    /// corner of the screen.
    minimap: Canvas,
    view: View = .first_person,
    raycast_options: raycast.Options = .{},
    show_minimap: bool = true,
    /// Draw the wall corners through the 3D camera on top of the ray caster.
    show_overlay: bool = false,
    /// Seconds of simulated time.
    time: f32 = 0,
    ticks: u32 = 0,

    pub fn init(gpa: std.mem.Allocator, width: usize) !App {
        var map = try Map.parse(gpa, default_map);
        errdefer map.deinit(gpa);
        var textures = try texture.Set.generate(gpa);
        errdefer textures.deinit(gpa);
        var renderer = try raycast.Renderer.init(gpa, width, map.sprites.len);
        errdefer renderer.deinit(gpa);
        return .{
            .map = map,
            .player = .{ .pos = map.start, .yaw = map.start_yaw },
            .textures = textures,
            .renderer = renderer,
            .minimap = try Canvas.init(gpa, minimap_width, minimap_height),
        };
    }

    pub fn deinit(app: *App, gpa: std.mem.Allocator) void {
        app.minimap.deinit(gpa);
        app.renderer.deinit(gpa);
        app.textures.deinit(gpa);
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
        if (input.pressed.contains(.toggle_textures)) {
            app.raycast_options.textured = !app.raycast_options.textured;
        }
        if (input.pressed.contains(.toggle_minimap)) app.show_minimap = !app.show_minimap;
        if (input.pressed.contains(.toggle_overlay)) app.show_overlay = !app.show_overlay;
        app.player.update(input, app.map, dt);
        app.time += dt;
        app.ticks += 1;
    }

    pub fn render(app: App, canvas: Canvas) void {
        const p = app.player;
        switch (app.view) {
            .first_person => {
                const scene: raycast.Scene = .{ .map = app.map, .textures = &app.textures };
                app.renderer.render(canvas, scene, .init(p.pos, p.yaw), app.raycast_options);
                if (app.show_overlay) {
                    const view_proj = camera.Camera.fromPlayer(p).viewProjection(canvas.width, canvas.height);
                    drawCorners(canvas, app.map, view_proj);
                }
                if (app.show_minimap) app.drawMinimap(canvas);
            },
            .map_fixed, .map_follow => {
                canvas.clear(.hex(0x101018));
                const style: mapview.Style = if (app.view == .map_fixed) .fixed else .follow;
                _ = mapview.drawMap(canvas, app.map, p, mapview.transform(style, p, canvas));
            },
        }

        var buffer: [96]u8 = undefined;
        const status = std.fmt.bufPrint(&buffer, "pos {d:.2},{d:.2}  yaw {d:.0}  pitch {d:.0}{s}", .{
            p.pos[0],
            p.pos[1],
            std.math.radiansToDegrees(p.yaw),
            std.math.radiansToDegrees(p.pitch),
            if (app.raycast_options.fisheye) "  fisheye" else "",
        }) catch unreachable;
        const h: i32 = @intCast(canvas.height);
        _ = font.drawText(canvas, 8, h - 12, status, 1, Color.white);
    }

    /// The map around the player, turned so the player faces up, in the
    /// top-right corner.
    fn drawMinimap(app: App, canvas: Canvas) void {
        const mini = app.minimap;
        mini.clear(.hex(0x101018));
        _ = mapview.drawMap(mini, app.map, app.player, mapview.transform(.minimap, app.player, mini));
        draw.rect(mini, 0, 0, minimap_width, minimap_height, .hex(0x808080));
        canvas.blit(mini, @intCast(canvas.width - minimap_width - 8), 8);
    }
};

/// Projects every grid corner where wall meets floor through the 3D camera,
/// at floor height (yellow) and ceiling height (cyan). Where the ray caster
/// drew the walls right, the dots sit exactly on their edges. Corners
/// hidden behind walls are drawn too: projecting a point says where it is
/// on screen, not whether something is in front of it.
fn drawCorners(canvas: Canvas, map: Map, view_proj: Mat4) void {
    for (0..map.height + 1) |y| {
        for (0..map.width + 1) |x| {
            const cx: i32 = @intCast(x);
            const cy: i32 = @intCast(y);
            // The four cells that meet at this corner.
            var walls: u32 = 0;
            for ([_][2]i32{ .{ -1, -1 }, .{ 0, -1 }, .{ -1, 0 }, .{ 0, 0 } }) |d| {
                walls += @intFromBool(map.at(cx + d[0], cy + d[1]).isWall());
            }
            if (walls == 0 or walls == 4) continue;
            const fx: f32 = @floatFromInt(x);
            const fz: f32 = @floatFromInt(y);
            for ([_]f32{ 0, 1 }, [_]Color{ .hex(0xffe040), .hex(0x40e0ff) }) |height, color| {
                const s = camera.project(view_proj, .{ fx, height, fz }, canvas.width, canvas.height) orelse continue;
                // Skip points far off screen before converting to integers.
                if (@abs(s[0]) > 4096 or @abs(s[1]) > 4096) continue;
                // The pixel that contains the point, as a 3x3 dot.
                const px: i32 = @intFromFloat(@floor(s[0]));
                const py: i32 = @intFromFloat(@floor(s[1]));
                draw.fillRect(canvas, px - 1, py - 1, 3, 3, color);
            }
        }
    }
}
