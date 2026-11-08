//! The ray caster again, now into a 320x200 image file, raycast.ppm, with
//! the colors delve uses: brick and stone walls, faces of constant y darker.
const std = @import("std");

const map = [_][]const u8{
    "################",
    "#..............#",
    "#..##......%%..#",
    "#..##......%%..#",
    "#..............#",
    "#.......#......#",
    "#.......#......#",
    "#..............#",
    "################",
};

fn tileAt(x: i32, y: i32) u8 {
    if (x < 0 or y < 0 or y >= map.len or x >= map[0].len) return '#';
    return map[@intCast(y)][@intCast(x)];
}

const Hit = struct { t: f32, tile: u8, y_side: bool };

fn cast(origin: [2]f32, dir: [2]f32) Hit {
    var cell = [2]i32{ @intFromFloat(@floor(origin[0])), @intFromFloat(@floor(origin[1])) };
    var step: [2]i32 = undefined;
    var delta: [2]f32 = undefined;
    var next: [2]f32 = undefined;
    for (0..2) |i| {
        delta[i] = if (dir[i] == 0) std.math.inf(f32) else @abs(1 / dir[i]);
        const fc: f32 = @floatFromInt(cell[i]);
        step[i] = if (dir[i] < 0) -1 else 1;
        next[i] = if (dir[i] < 0) (origin[i] - fc) * delta[i] else (fc + 1 - origin[i]) * delta[i];
    }
    while (true) {
        const i: usize = if (next[0] < next[1]) 0 else 1;
        const t = next[i];
        next[i] += delta[i];
        cell[i] += step[i];
        const tile = tileAt(cell[0], cell[1]);
        if (tile != '.') return .{ .t = t, .tile = tile, .y_side = i == 1 };
    }
}

pub fn main(init: std.process.Init) !void {
    const w = 320;
    const h = 200;
    var pixels: [w * h][3]u8 = undefined;

    const pos = [2]f32{ 6.0, 4.0 };
    const yaw: f32 = std.math.degreesToRadians(-10.0);
    const dir = [2]f32{ @cos(yaw), @sin(yaw) };
    const plane = [2]f32{ -dir[1] * 0.8, dir[0] * 0.8 }; // 320 / (2 * 0.8) = 200 = h: square pixels

    for (0..w) |x| {
        const camera_x = 2 * (@as(f32, @floatFromInt(x)) + 0.5) / w - 1;
        const hit = cast(pos, .{ dir[0] + plane[0] * camera_x, dir[1] + plane[1] * camera_x });
        const half = h / hit.t / 2;
        var wall: [3]u8 = if (hit.tile == '#') .{ 0xa0, 0x5a, 0x3c } else .{ 0x8a, 0x8a, 0x96 };
        if (hit.y_side) for (&wall) |*c| {
            c.* = c.* / 4 * 3;
        };
        for (0..h) |y| {
            const center = @as(f32, @floatFromInt(y)) + 0.5 - h / 2.0;
            pixels[y * w + x] = if (@abs(center) < half) wall else if (center > 0) .{ 0x58, 0x50, 0x48 } else .{ 0x38, 0x38, 0x40 };
        }
    }

    // PPM: a text header, then the RGB bytes row by row.
    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "raycast.ppm", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.print("P6\n{d} {d}\n255\n", .{ w, h });
    try writer.interface.writeAll(std.mem.sliceAsBytes(&pixels));
    try writer.interface.flush();
    std.debug.print("wrote raycast.ppm, {d}x{d}\n", .{ w, h });
}
