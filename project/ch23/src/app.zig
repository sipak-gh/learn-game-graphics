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
const World = @import("world.zig").World;
const mesh = @import("mesh.zig");
const Vec3 = @import("math.zig").Vec3;
const light = @import("light.zig");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const visibility = @import("visibility.zig");

/// What fills the screen. Tab cycles through them.
pub const View = enum { solid, depth, levels, chunks, overdraw, overhead, raycast, wireframe, cube, map_fixed, map_follow };

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
    /// The map as meshes, built once.
    world: World,
    player: Player,
    textures: texture.Set,
    renderer: raycast.Renderer,
    renderer3d: render3d.Renderer,
    /// The minimap is drawn on its own small canvas, then copied into the
    /// corner of the screen.
    minimap: Canvas,
    /// The light of every lamp in the map.
    lamps: []light.Light,
    /// Which chunks the player can see, worked out once per frame.
    visibility: visibility.Visibility,
    culling: visibility.Culling = .grid,
    /// Draw the chunks nearest first.
    sort: bool = true,
    /// Keep the visibility of the moment the freeze began, wherever the
    /// player goes.
    frozen: bool = false,
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
    /// The two lines of numbers at the bottom of the screen.
    show_info: bool = true,
    /// How long the last `render` took, if someone measured it.
    render_ms: ?f32 = null,
    /// Seconds of simulated time.
    time: f32 = 0,
    ticks: u32 = 0,

    /// Starts the game in `map`, which the app owns from now on.
    pub fn init(gpa: std.mem.Allocator, map_to_own: Map, width: usize, height: usize) !App {
        var map = map_to_own;
        errdefer map.deinit(gpa);
        var world: World = try .build(gpa, map);
        errdefer world.deinit(gpa);
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
        var vis: visibility.Visibility = try .init(gpa, map, world);
        errdefer vis.deinit(gpa);
        return .{
            .map = map,
            .world = world,
            .player = .{ .pos = map.start, .yaw = map.start_yaw },
            .textures = textures,
            .renderer = renderer,
            .renderer3d = renderer3d,
            .minimap = try Canvas.init(gpa, minimap_width, minimap_height),
            .lamps = lamp_slice,
            .visibility = vis,
        };
    }

    pub fn deinit(app: *App, gpa: std.mem.Allocator) void {
        app.visibility.deinit(gpa);
        gpa.free(app.lamps);
        app.minimap.deinit(gpa);
        app.renderer3d.deinit(gpa);
        app.renderer.deinit(gpa);
        app.textures.deinit(gpa);
        app.world.deinit(gpa);
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
        if (input.pressed.contains(.toggle_info)) app.show_info = !app.show_info;
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
        if (input.pressed.contains(.next_culling)) {
            const all = std.enums.values(visibility.Culling);
            app.culling = all[(@backingInt(app.culling) + 1) % all.len];
        }
        if (input.pressed.contains(.toggle_sorting)) app.sort = !app.sort;
        if (input.pressed.contains(.toggle_freeze)) app.frozen = !app.frozen;
        app.player.update(input, app.map, dt);
        app.time += dt;
        app.ticks += 1;
    }

    pub fn render(app: *App, canvas: Canvas) void {
        const p = app.player;
        var stats: ?render3d.Stats = null;
        const cam = camera.Camera.fromPlayer(p);
        const view_proj = cam.viewProjection(canvas.width, canvas.height);
        const sees_world = switch (app.view) {
            .solid, .depth, .levels, .chunks, .overdraw, .overhead, .wireframe => true,
            else => false,
        };
        // Frozen, the visibility stays as it was last worked out.
        if (sees_world and (!app.frozen or !app.visibility.valid)) {
            const aspect = @as(f32, @floatFromInt(canvas.width)) / @as(f32, @floatFromInt(canvas.height));
            app.visibility.update(app.map, app.world, cam, view_proj, aspect, app.culling, app.sort);
        }
        // T turns textures off in the 3D views as in the ray caster.
        const paint: maze3d.Paint = .{
            .textures = if (app.raycast_options.textured) &app.textures else null,
            .filter = app.filter,
            .show_levels = app.view == .levels,
            .chunk_colors = app.view == .chunks,
        };
        switch (app.view) {
            .solid, .depth, .levels, .chunks, .overdraw => {
                canvas.clear(.hex(0x101018));
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
                app.renderer3d.clearDepth();
                stats = .{};
                // Chunk colors read best flat, without light or fog.
                const shading: light.Shading = if (app.view == .chunks) .unlit else app.shading;
                var options = app.render_options;
                options.count_overdraw = app.view == .overdraw;
                app.world.draw(app.renderer3d, canvas, view_proj, app.visibility.chunks(), paint, shading, scene, options, &stats.?);
                if (app.view == .depth) app.renderer3d.drawDepth(canvas);
                if (app.view == .overdraw) {
                    app.renderer3d.drawOverdraw(canvas);
                    drawOverdrawKey(canvas);
                }
                drawCrosshair(canvas);
                if (app.show_minimap) app.drawMinimap(canvas);
            },
            .overhead => {
                canvas.clear(.hex(0x101018));
                // Above and behind the player, looking down past the
                // player to where the player looks.
                const dir = math.fromAngle(p.yaw);
                const above: camera.Camera = .{
                    .pos = .{ p.pos[0] - 6 * dir[0], 12, p.pos[1] - 6 * dir[1] },
                    .yaw = p.yaw,
                    .pitch = -std.math.atan(@as(f32, 12.0 / 11.0)),
                };
                const above_proj = above.viewProjection(canvas.width, canvas.height);
                app.renderer3d.clearDepth();
                var overhead_stats: render3d.Stats = .{};
                app.world.drawOverhead(app.renderer3d, canvas, above_proj, app.visibility.states, paint, app.render_options, &overhead_stats);
                app.drawSightLines(canvas, above_proj);
            },
            .raycast => {
                const scene: raycast.Scene = .{ .map = app.map, .textures = &app.textures };
                app.renderer.render(canvas, scene, .init(p.pos, p.yaw), app.raycast_options);
                if (app.show_overlay) drawCorners(canvas, app.map, view_proj);
                if (app.show_minimap) app.drawMinimap(canvas);
            },
            .wireframe => {
                canvas.clear(.hex(0x101018));
                stats = .{};
                app.world.drawWireframe(app.renderer3d, canvas, view_proj, app.visibility.chunks(), app.render_options, &stats.?);
                drawCrosshair(canvas);
                if (app.show_minimap) app.drawMinimap(canvas);
            },
            .cube => {
                canvas.clear(.hex(0x101018));
                // A fixed camera looking at two cubes that cut through each
                // other, one of them spinning about its center.
                const view = Mat4.lookAt(.{ 1.2, 1.0, 2.4 }, .{ 0, 0, 0 }, camera.world_up);
                const cube_proj = camera.Camera.projection(canvas.width, canvas.height).mul(view);
                const center = Mat4.translation(.{ -0.5, -0.5, -0.5 });
                const spinning = Mat4.rotationY(app.time).mul(Mat4.rotationX(0.6 * app.time)).mul(center);
                const still = Mat4.translation(.{ 0.4, 0.2, -0.3 }).mul(Mat4.rotationY(0.5)).mul(center);
                app.renderer3d.clearDepth();
                stats = .{};
                const r = app.renderer3d;
                r.drawMesh(canvas, mesh.cube, spinning, cube_proj, PositionShader{}, app.render_options, &stats.?);
                r.drawMesh(canvas, mesh.cube, still, cube_proj, PositionShader{ .invert = true }, app.render_options, &stats.?);
            },
            .map_fixed, .map_follow => {
                canvas.clear(.hex(0x101018));
                const style: mapview.Style = if (app.view == .map_fixed) .fixed else .follow;
                _ = mapview.drawMap(canvas, app.map, p, mapview.transform(style, p, canvas));
            },
        }

        if (app.show_info) app.drawInfo(canvas, stats, sees_world);
    }

    /// The numbers at the bottom of the screen: where the player is, what
    /// the renderer is set to, and what it did.
    fn drawInfo(app: App, canvas: Canvas, stats: ?render3d.Stats, sees_world: bool) void {
        const p = app.player;
        var buffer: [128]u8 = undefined;
        const o = app.render_options;
        const status = std.fmt.bufPrint(&buffer, "pos {d:.2},{d:.2}  yaw {d:.0}  pitch {d:.0}  {t}  {t}{s}{s}{s}{s}{s}{s}{s}{s}", .{
            p.pos[0],
            p.pos[1],
            degrees(p.yaw),
            degrees(p.pitch),
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
        var y = h - 36;
        if (sees_world) {
            const v = app.visibility;
            var line = std.fmt.bufPrint(&buffer, "chunks {d}/{d}  outside {d}  hidden {d}  culling {t}{s}{s}", .{
                v.drawn,
                v.states.len,
                v.count(.outside),
                v.count(.hidden),
                app.culling,
                if (app.sort) "  sorted" else "",
                if (app.frozen) "  frozen" else "",
            }) catch unreachable;
            if (stats) |s| {
                // Overdraw: how often each pixel was covered, and shaded,
                // on average.
                const screen: f32 = @floatFromInt(canvas.width * canvas.height);
                const tail = std.fmt.bufPrint(buffer[line.len..], "  covered {d:.2}x  shaded {d:.2}x", .{
                    @as(f32, @floatFromInt(s.tested)) / screen,
                    @as(f32, @floatFromInt(s.pixels)) / screen,
                }) catch unreachable;
                line = buffer[0 .. line.len + tail.len];
            }
            _ = font.drawText(canvas, 8, y, line, 1, Color.white);
            y -= 12;
        }
        if (app.render_ms) |ms| {
            const line = std.fmt.bufPrint(&buffer, "{d:.1} ms", .{ms}) catch unreachable;
            _ = font.drawText(canvas, 8, y, line, 1, Color.white);
        }
    }

    /// For the overhead view: the outline of what the rays saw, the two
    /// outermost rays, and a dot where the player is. When frozen, the
    /// rays start where the player was.
    fn drawSightLines(app: App, canvas: Canvas, view_proj: Mat4) void {
        const v = app.visibility;
        const color: Color = .hex(0xffe040);
        if (v.ray_count > 0) {
            const ends = v.ray_ends[0..v.ray_count];
            floorLine(canvas, view_proj, v.eye, ends[0], color);
            floorLine(canvas, view_proj, v.eye, ends[ends.len - 1], color);
            for (ends[1..], ends[0 .. ends.len - 1]) |b, a| floorLine(canvas, view_proj, a, b, color);
        }
        const p = app.player.pos;
        const eye = camera.project(view_proj, .{ p[0], 0, p[1] }, canvas.width, canvas.height) orelse return;
        if (@abs(eye[0]) > 4096 or @abs(eye[1]) > 4096) return;
        const x: i32 = @intFromFloat(@floor(eye[0]));
        const y: i32 = @intFromFloat(@floor(eye[1]));
        draw.fillRect(canvas, x - 3, y - 3, 7, 7, .hex(0x000000));
        draw.fillRect(canvas, x - 2, y - 2, 5, 5, .hex(0x40ff40));
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

/// A line on the floor between map points `a` and `b`, seen through
/// `view_proj`, on top of whatever is drawn.
fn floorLine(canvas: Canvas, view_proj: Mat4, a: Vec2, b: Vec2, color: Color) void {
    var points: [2]draw.Point = undefined;
    for (&points, [_]Vec2{ a, b }) |*point, m| {
        const s = camera.project(view_proj, .{ m[0], 0, m[1] }, canvas.width, canvas.height) orelse return;
        if (@abs(s[0]) > 4096 or @abs(s[1]) > 4096) return;
        point.* = .{ .x = @intFromFloat(@floor(s[0])), .y = @intFromFloat(@floor(s[1])) };
    }
    draw.line(canvas, points[0], points[1], color);
}

/// Which color means how many times a pixel was covered.
fn drawOverdrawKey(canvas: Canvas) void {
    for (render3d.overdraw_colors[1..], 1..) |color, n| {
        const x: i32 = @intCast(8 + (n - 1) * 24);
        draw.fillRect(canvas, x - 1, 7, 24, 16, Color.black);
        draw.fillRect(canvas, x, 8, 22, 14, color);
        var buffer: [4]u8 = undefined;
        const last = n == render3d.overdraw_colors.len - 1;
        const label = std.fmt.bufPrint(&buffer, "{d}{s}", .{ n, if (last) "+" else "" }) catch unreachable;
        _ = font.drawText(canvas, x + 4, 11, label, 1, if (n >= 4) Color.black else Color.white);
    }
}

/// Whole degrees, for showing. Adding 0 turns -0 (from a tiny negative
/// angle) into 0.
fn degrees(radians: f32) f32 {
    return @round(std.math.radiansToDegrees(radians)) + 0;
}

/// A small cross where the view direction meets the screen. That is the
/// corner between the four center pixels, so the cross is 2 pixels wide,
/// with a dark outline to show on light walls.
fn drawCrosshair(canvas: Canvas) void {
    const cx: i32 = @intCast(canvas.width / 2);
    const cy: i32 = @intCast(canvas.height / 2);
    const arms = [_][4]i32{
        .{ cx - 7, cy - 1, 5, 2 }, .{ cx + 2, cy - 1, 5, 2 }, // left, right
        .{ cx - 1, cy - 7, 2, 5 }, .{ cx - 1, cy + 2, 2, 5 }, // up, down
    };
    for (arms) |a| draw.fillRect(canvas, a[0] - 1, a[1] - 1, a[2] + 2, a[3] + 2, .hex(0x000000));
    for (arms) |a| draw.fillRect(canvas, a[0], a[1], a[2], a[3], .hex(0xf0f0f0));
}

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
