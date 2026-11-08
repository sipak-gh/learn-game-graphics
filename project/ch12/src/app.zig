//! The program's state and drawing, independent of any window. main.zig
//! calls `update` once per tick and `render` once per frame.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");
const font = @import("font.zig");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Map = @import("map.zig").Map;
const Tile = @import("map.zig").Tile;
const Player = @import("player.zig").Player;
const Input = @import("input.zig").Input;

const default_map = @embedFile("maps/cellar.txt");

pub const App = struct {
    map: Map,
    player: Player,
    /// Tab switches between the whole map and a view that follows the player.
    map_view: enum { fixed, follow } = .fixed,
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
        if (input.pressed.contains(.toggle_map)) {
            app.map_view = if (app.map_view == .fixed) .follow else .fixed;
        }
        app.player.update(input, app.map, dt);
        app.time += dt;
        app.ticks += 1;
    }

    pub fn render(app: App, canvas: Canvas) void {
        canvas.clear(.hex(0x101018));
        const to_screen = app.mapTransform(canvas);
        const drawn = drawMap(canvas, app.map, app.player, to_screen);

        var buffer: [96]u8 = undefined;
        const p = app.player;
        const status = std.fmt.bufPrint(&buffer, "pos {d:.2},{d:.2}  yaw {d:.0}  cells drawn {d}/{d}", .{
            p.pos[0],                         p.pos[1],
            std.math.radiansToDegrees(p.yaw), drawn,
            app.map.width * app.map.height,
        }) catch unreachable;
        const h: i32 = @intCast(canvas.height);
        _ = font.drawText(canvas, 8, h - 12, status, 1, Color.white);
    }

    /// The matrix that takes map coordinates to canvas pixels. Read each
    /// product right to left: that is the order the steps apply to a point.
    fn mapTransform(app: App, canvas: Canvas) Mat4 {
        switch (app.map_view) {
            // Scale cells to 16 pixels, then move the map's corner to (64, 8).
            .fixed => return Mat4.translation(.{ 64, 8, 0 }).mul(Mat4.scaling(.{ 16, 16, 1 })),
            // Move the player to the origin, turn so the player faces up
            // (angle -90 degrees), scale up, and move to the screen center.
            .follow => {
                const center: Vec3 = .{ @floatFromInt(canvas.width / 2), @floatFromInt(canvas.height / 2), 0 };
                const p = app.player;
                return Mat4.translation(center)
                    .mul(Mat4.scaling(.{ 32, 32, 1 }))
                    .mul(Mat4.rotationZ(-std.math.pi / 2.0 - p.yaw))
                    .mul(Mat4.translation(.{ -p.pos[0], -p.pos[1], 0 }));
            },
        }
    }
};

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
fn drawMap(canvas: Canvas, map: Map, player: Player, to_screen: Mat4) usize {
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

    const dir = player.dir();
    // The edges of the view: the facing direction plus or minus a sideways
    // vector. Chapter 13 explains the 0.8.
    const side = math.scale(math.perp(dir), 0.8);
    const eye = toScreen(to_screen, player.pos);
    draw.line(canvas, eye, toScreen(to_screen, player.pos + math.scale(dir + side, 3)), .hex(0x707040));
    draw.line(canvas, eye, toScreen(to_screen, player.pos + math.scale(dir - side, 3)), .hex(0x707040));
    draw.line(canvas, eye, toScreen(to_screen, player.pos + dir), .hex(0xffe060));
    draw.fillCircle(canvas, eye, 4, .hex(0xffe060));
    return drawn;
}
