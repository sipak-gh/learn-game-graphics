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
const render3d = @import("render3d.zig");
const maze3d = @import("maze3d.zig");
const mesh = @import("mesh.zig");
const Vec3 = @import("math.zig").Vec3;
const light = @import("light.zig");

const default_map = @embedFile("maps/cellar.txt");

/// What fills the screen. Tab cycles through them.
pub const View = enum { solid, depth, levels, raycast, wireframe, cube, map_fixed, map_follow };

/// The most vertices one mesh may have.
const max_vertices = 1024;

/// The most lamps a map may have.
const max_lamps = 63;

/// Light that reaches everywhere, a little blue, like moonlight.
const ambient: Vec3 = .{ 0.25, 0.25, 0.3 };
/// The player's torch: a little whiter than the lamps, and reaching farther.
const torch_color: Vec3 = .{ 2.5, 2.2, 1.6 };
const torch_radius = 6;
const fog: light.Fog = .{ .color = .{ 16, 16, 24 }, .density = 0.12 };

const minimap_width = 160;
const minimap_height = 112;

pub const App = struct {
    map: Map,
    player: Player,
    textures: texture.Set,
    renderer: raycast.Renderer,
    renderer3d: render3d.Renderer,
    /// The minimap is drawn on its own small canvas, then copied into the
    /// corner of the screen.
    minimap: Canvas,
    /// The light of every lamp in the map.
    lamps: []light.Light,
    view: View = .solid,
    shading: light.Shading = .phong,
    filter: texture.Filter = .trilinear,
    /// A light at the eye, so the player can see where no lamp shines.
    torch: bool = true,
    fog: bool = true,
    raycast_options: raycast.Options = .{},
    render_options: render3d.Options = .{},
    show_minimap: bool = true,
    /// Draw the wall corners through the 3D camera on top of the ray caster.
    show_overlay: bool = false,
    /// Seconds of simulated time.
    time: f32 = 0,
    ticks: u32 = 0,

    pub fn init(gpa: std.mem.Allocator, width: usize, height: usize) !App {
        var map = try Map.parse(gpa, default_map);
        errdefer map.deinit(gpa);
        var textures = try texture.Set.generate(gpa);
        errdefer textures.deinit(gpa);
        var renderer = try raycast.Renderer.init(gpa, width, map.sprites.len);
        errdefer renderer.deinit(gpa);
        var renderer3d = try render3d.Renderer.init(gpa, max_vertices, width, height);
        errdefer renderer3d.deinit(gpa);
        var lamps: std.ArrayList(light.Light) = .empty;
        errdefer lamps.deinit(gpa);
        for (map.sprites) |sprite| {
            if (sprite.thing == .lamp) try lamps.append(gpa, maze3d.lampLight(sprite.pos));
        }
        if (lamps.items.len > max_lamps) return error.TooManyLamps;
        const lamp_slice = try lamps.toOwnedSlice(gpa);
        errdefer gpa.free(lamp_slice);
        return .{
            .map = map,
            .player = .{ .pos = map.start, .yaw = map.start_yaw },
            .textures = textures,
            .renderer = renderer,
            .renderer3d = renderer3d,
            .minimap = try Canvas.init(gpa, minimap_width, minimap_height),
            .lamps = lamp_slice,
        };
    }

    pub fn deinit(app: *App, gpa: std.mem.Allocator) void {
        gpa.free(app.lamps);
        app.minimap.deinit(gpa);
        app.renderer3d.deinit(gpa);
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
        if (input.pressed.contains(.toggle_clipping)) {
            app.render_options.clip_near = !app.render_options.clip_near;
        }
        if (input.pressed.contains(.toggle_culling)) {
            app.render_options.cull_back_faces = !app.render_options.cull_back_faces;
        }
        if (input.pressed.contains(.toggle_depth_test)) {
            app.render_options.depth_test = !app.render_options.depth_test;
        }
        if (input.pressed.contains(.next_shading)) {
            const all = std.enums.values(light.Shading);
            app.shading = all[(@backingInt(app.shading) + 1) % all.len];
        }
        if (input.pressed.contains(.toggle_torch)) app.torch = !app.torch;
        if (input.pressed.contains(.toggle_fog)) app.fog = !app.fog;
        if (input.pressed.contains(.next_filter)) {
            const all = std.enums.values(texture.Filter);
            app.filter = all[(@backingInt(app.filter) + 1) % all.len];
        }
        if (input.pressed.contains(.toggle_perspective)) {
            app.render_options.perspective_correct = !app.render_options.perspective_correct;
        }
        app.player.update(input, app.map, dt);
        app.time += dt;
        app.ticks += 1;
    }

    pub fn render(app: App, canvas: Canvas) void {
        const p = app.player;
        var stats: ?render3d.Stats = null;
        switch (app.view) {
            .solid, .depth, .levels => {
                canvas.clear(.hex(0x101018));
                const cam = camera.Camera.fromPlayer(p);
                const view_proj = cam.viewProjection(canvas.width, canvas.height);
                // The torch first, then the lamps.
                var lights: [max_lamps + 1]light.Light = undefined;
                lights[0] = .{ .pos = cam.pos, .color = torch_color, .radius = torch_radius };
                @memcpy(lights[1..][0..app.lamps.len], app.lamps);
                const scene: light.Scene = .{
                    .ambient = ambient,
                    .lights = lights[@intFromBool(!app.torch) .. app.lamps.len + 1],
                    .eye = cam.pos,
                    .fog = if (app.fog) fog else null,
                };
                // T turns textures off here as in the ray caster.
                const paint: maze3d.Paint = .{
                    .textures = if (app.raycast_options.textured) &app.textures else null,
                    .filter = app.filter,
                    .show_levels = app.view == .levels,
                };
                app.renderer3d.clearDepth();
                stats = .{};
                maze3d.drawSolid(app.renderer3d, canvas, app.map, view_proj, paint, app.shading, scene, app.render_options, &stats.?);
                if (app.view == .depth) app.renderer3d.drawDepth(canvas);
                if (app.show_minimap) app.drawMinimap(canvas);
            },
            .raycast => {
                const scene: raycast.Scene = .{ .map = app.map, .textures = &app.textures };
                app.renderer.render(canvas, scene, .init(p.pos, p.yaw), app.raycast_options);
                if (app.show_overlay) {
                    const view_proj = camera.Camera.fromPlayer(p).viewProjection(canvas.width, canvas.height);
                    drawCorners(canvas, app.map, view_proj);
                }
                if (app.show_minimap) app.drawMinimap(canvas);
            },
            .wireframe => {
                canvas.clear(.hex(0x101018));
                const view_proj = camera.Camera.fromPlayer(p).viewProjection(canvas.width, canvas.height);
                stats = .{};
                maze3d.drawWireframe(app.renderer3d, canvas, app.map, view_proj, app.render_options, &stats.?);
                if (app.show_minimap) app.drawMinimap(canvas);
            },
            .cube => {
                canvas.clear(.hex(0x101018));
                // A fixed camera looking at two cubes that cut through each
                // other, one of them spinning about its center.
                const view = Mat4.lookAt(.{ 1.2, 1.0, 2.4 }, .{ 0, 0, 0 }, camera.world_up);
                const view_proj = camera.Camera.projection(canvas.width, canvas.height).mul(view);
                const center = Mat4.translation(.{ -0.5, -0.5, -0.5 });
                const spinning = Mat4.rotationY(app.time).mul(Mat4.rotationX(0.6 * app.time)).mul(center);
                const still = Mat4.translation(.{ 0.4, 0.2, -0.3 }).mul(Mat4.rotationY(0.5)).mul(center);
                app.renderer3d.clearDepth();
                stats = .{};
                const r = app.renderer3d;
                r.drawMesh(canvas, mesh.cube, spinning, view_proj, PositionShader{}, app.render_options, &stats.?);
                r.drawMesh(canvas, mesh.cube, still, view_proj, PositionShader{ .invert = true }, app.render_options, &stats.?);
            },
            .map_fixed, .map_follow => {
                canvas.clear(.hex(0x101018));
                const style: mapview.Style = if (app.view == .map_fixed) .fixed else .follow;
                _ = mapview.drawMap(canvas, app.map, p, mapview.transform(style, p, canvas));
            },
        }

        var buffer: [128]u8 = undefined;
        const o = app.render_options;
        const status = std.fmt.bufPrint(&buffer, "pos {d:.2},{d:.2}  yaw {d:.0}  pitch {d:.0}  {t}  {t}{s}{s}{s}{s}{s}{s}{s}{s}", .{
            p.pos[0],
            p.pos[1],
            std.math.radiansToDegrees(p.yaw),
            std.math.radiansToDegrees(p.pitch),
            app.shading,
            app.filter,
            if (o.perspective_correct) "" else "  affine",
            if (app.raycast_options.textured) "" else "  no textures",
            if (app.torch) "  torch" else "",
            if (app.fog) "  fog" else "",
            if (app.raycast_options.fisheye) "  fisheye" else "",
            if (o.clip_near) "" else "  no near clipping",
            if (o.cull_back_faces) "" else "  no culling",
            if (o.depth_test) "" else "  no depth test",
        }) catch unreachable;
        const h: i32 = @intCast(canvas.height);
        _ = font.drawText(canvas, 8, h - 12, status, 1, Color.white);
        if (stats) |s| {
            const line = std.fmt.bufPrint(&buffer, "triangles {d}  outside {d}  clipped {d}  behind near {d}  culled {d}  drawn {d}  pixels {d}", .{
                s.triangles, s.outside, s.clipped, s.behind, s.culled, s.drawn, s.pixels,
            }) catch unreachable;
            _ = font.drawText(canvas, 8, h - 24, line, 1, Color.white);
        }
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

/// Colors a mesh by where each point is in it: the unit cube becomes the
/// RGB color cube (or its opposite, with `invert`).
const PositionShader = struct {
    invert: bool = false,

    pub fn vertex(s: PositionShader, v: mesh.Vertex, _: Vec3) render3d.Varyings {
        const c = if (s.invert) @as(Vec3, @splat(1)) - v.pos else v.pos;
        return .{ 255 * c[0], 255 * c[1], 255 * c[2], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    }

    pub fn pixel(_: PositionShader, vary: render3d.Varyings) Color {
        return render3d.toColor(vary);
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
