//! Ray casting: for every column of the screen, follow one ray through the
//! map grid until it hits a wall, and draw that wall as a vertical strip
//! whose height shrinks with distance.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Map = @import("map.zig").Map;
const Tile = @import("map.zig").Tile;

/// Which kind of grid line a ray crossed into the wall: `.x` is a line of
/// constant x (an east or west face), `.y` a line of constant y.
pub const Side = enum { x, y };

pub const Hit = struct {
    /// How far along the ray the wall is, in units of the ray's length.
    /// For camera rays this is the distance measured along the view
    /// direction (see `Camera.ray`).
    t: f32,
    /// The wall cell that was hit.
    cell: [2]i32,
    side: Side,
    tile: Tile,
};

/// Follows the ray `origin + t * dir` through the grid with a DDA (digital
/// differential analyzer): step to whichever grid line, x or y, comes next,
/// until the cell entered is a wall. Outside the map counts as wall, so
/// every ray ends.
pub fn cast(map: Map, origin: Vec2, dir: Vec2) Hit {
    // t needed to cross one whole cell in x, and in y. A ray parallel to an
    // axis never crosses that axis's lines: infinity.
    const inf = std.math.inf(f32);
    const delta: Vec2 = .{
        if (dir[0] == 0) inf else @abs(1 / dir[0]),
        if (dir[1] == 0) inf else @abs(1 / dir[1]),
    };
    var cell: [2]i32 = .{ @intFromFloat(@floor(origin[0])), @intFromFloat(@floor(origin[1])) };
    var step: [2]i32 = undefined;
    // t at which the ray crosses the next x line and the next y line.
    var next: Vec2 = undefined;
    inline for (0..2) |i| {
        const fc: f32 = @floatFromInt(cell[i]);
        if (dir[i] < 0) {
            step[i] = -1;
            next[i] = (origin[i] - fc) * delta[i];
        } else {
            step[i] = 1;
            next[i] = (fc + 1 - origin[i]) * delta[i];
        }
    }

    while (true) {
        var side: Side = undefined;
        var t: f32 = undefined;
        if (next[0] < next[1]) {
            t = next[0];
            next[0] += delta[0];
            cell[0] += step[0];
            side = .x;
        } else {
            t = next[1];
            next[1] += delta[1];
            cell[1] += step[1];
            side = .y;
        }
        const tile = map.at(cell[0], cell[1]);
        if (tile.isWall()) return .{ .t = t, .cell = cell, .side = side, .tile = tile };
    }
}

/// The camera plane's half-width, relative to the view direction's length
/// of 1. It sets the field of view: 2 atan(0.8) = 77.3 degrees across. With
/// 640x400 pixels it also makes pixels square (see `wallHeight`).
pub const plane_scale = 0.8;

pub const Camera = struct {
    pos: Vec2,
    /// The view direction, length 1.
    dir: Vec2,
    /// From the center of the screen to its right edge, in the plane one
    /// unit in front of the camera.
    plane: Vec2,

    pub fn init(pos: Vec2, yaw: f32) Camera {
        const dir = math.fromAngle(yaw);
        return .{ .pos = pos, .dir = dir, .plane = math.scale(math.perp(dir), plane_scale) };
    }

    /// The ray through the center of column `x` of a `width`-pixel screen.
    /// Its component along `dir` is always 1, so the `t` of a hit is the
    /// hit's distance in front of the camera plane, not from the eye.
    pub fn ray(cam: Camera, x: usize, width: usize) Vec2 {
        const fx: f32 = @floatFromInt(x);
        const fw: f32 = @floatFromInt(width);
        const camera_x = 2 * (fx + 0.5) / fw - 1; // -1 at the left edge, 1 at the right
        return cam.dir + math.scale(cam.plane, camera_x);
    }
};

pub const Options = struct {
    /// Use the distance from the eye instead of the distance in front of
    /// the camera: walls bulge like through a fisheye lens.
    fisheye: bool = false,
};

const ceiling_color: Color = .hex(0x383840);
const floor_color: Color = .hex(0x585048);

fn wallColor(tile: Tile, side: Side) Color {
    const c: Color = switch (tile) {
        .floor => unreachable,
        .brick => .hex(0xa05a3c),
        .stone => .hex(0x8a8a96),
    };
    // Faces of constant y are darker: a cheap way to tell walls apart.
    if (side == .y) return .{ .r = c.r / 4 * 3, .g = c.g / 4 * 3, .b = c.b / 4 * 3 };
    return c;
}

/// The height in pixels of a wall one unit tall at distance `dist`, on a
/// screen `height` pixels tall. The wall's middle is at eye level.
pub fn wallHeight(height: usize, dist: f32) f32 {
    return @as(f32, @floatFromInt(height)) / dist;
}

/// Draws the first-person view: ceiling, floor, and one wall strip per column.
pub fn render(canvas: Canvas, map: Map, cam: Camera, opts: Options) void {
    const h: f32 = @floatFromInt(canvas.height);
    for (0..canvas.width) |x| {
        const ray = cam.ray(x, canvas.width);
        const hit = cast(map, cam.pos, ray);
        const dist = if (opts.fisheye) hit.t * math.length(ray) else hit.t;
        const half = wallHeight(canvas.height, dist) / 2;
        // Fill the rows whose pixel centers lie between top and bottom.
        const top = pixelRow(h / 2 - half, canvas.height);
        const bottom = pixelRow(h / 2 + half, canvas.height);
        for (0..canvas.height) |y| {
            const color = if (y < top) ceiling_color else if (y < bottom) wallColor(hit.tile, hit.side) else floor_color;
            canvas.pixels[y * canvas.width + x] = color;
        }
    }
}

/// The first row whose pixel center (y + 0.5) is at or below `y`, clamped
/// to the screen.
pub fn pixelRow(y: f32, height: usize) usize {
    const row = @ceil(y - 0.5);
    if (row <= 0) return 0;
    return @min(height, @as(usize, @intFromFloat(row)));
}

const testing = std.testing;

test "a ray down a corridor hits the far wall" {
    const gpa = testing.allocator;
    var map = try Map.parse(gpa,
        \\######
        \\#>...%
        \\######
    );
    defer map.deinit(gpa);
    const hit = cast(map, .{ 1.5, 1.5 }, .{ 1, 0 });
    try testing.expectEqual(.x, hit.side);
    try testing.expectEqual([2]i32{ 5, 1 }, hit.cell);
    try testing.expectEqual(.stone, hit.tile);
    try testing.expectApproxEqAbs(3.5, hit.t, 1e-6);

    // Straight up: the wall above, a y-side 0.5 away.
    const up = cast(map, .{ 1.5, 1.5 }, .{ 0, -1 });
    try testing.expectEqual(.y, up.side);
    try testing.expectApproxEqAbs(0.5, up.t, 1e-6);
}

test "t measures distance along the view direction" {
    const gpa = testing.allocator;
    var map = try Map.parse(gpa,
        \\#######
        \\#.....#
        \\#..>..#
        \\#.....#
        \\#######
    );
    defer map.deinit(gpa);
    const cam = Camera.init(map.start, 0);
    // Every ray hits the east wall (x = 6), 2.5 units ahead of the camera,
    // whatever its angle: that is what makes walls straight.
    for ([_]usize{ 200, 320, 440 }) |x| {
        const hit = cast(map, cam.pos, cam.ray(x, 640));
        try testing.expectApproxEqAbs(2.5, hit.t, 1e-5);
    }
}

test "pixelRow rounds to pixel centers and clamps" {
    try testing.expectEqual(0, pixelRow(-10, 400));
    try testing.expectEqual(99, pixelRow(99.5, 400));
    try testing.expectEqual(100, pixelRow(99.6, 400));
    try testing.expectEqual(400, pixelRow(1000, 400));
}
