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
const Thing = @import("map.zig").Thing;
const Sprite = @import("map.zig").Sprite;
const texture = @import("texture.zig");

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
    /// Paint walls, floor, and ceiling with textures instead of flat colors.
    textured: bool = true,
};

pub const ceiling_color: Color = .hex(0x383840);
pub const floor_color: Color = .hex(0x585048);

pub fn wallColor(tile: Tile) Color {
    return switch (tile) {
        .floor => unreachable,
        .brick => .hex(0xa05a3c),
        .stone => .hex(0x8a8a96),
    };
}

fn wallTexture(tile: Tile) texture.Kind {
    return switch (tile) {
        .floor => unreachable,
        .brick => .brick,
        .stone => .stone,
    };
}

fn spriteTexture(thing: Thing) texture.Kind {
    return switch (thing) {
        .lamp => .lamp,
        .barrel => .barrel,
    };
}

/// Faces of constant y are drawn darker: a cheap way to tell walls apart.
pub const y_side_shade = 0.75;

/// The height in pixels of a wall one unit tall at distance `dist`, on a
/// screen `height` pixels tall. The wall's middle is at eye level.
pub fn wallHeight(height: usize, dist: f32) f32 {
    return @as(f32, @floatFromInt(height)) / dist;
}

/// Everything the ray caster draws.
pub const Scene = struct {
    map: Map,
    textures: *const texture.Set,
};

/// Draws the first-person view. Needs scratch memory, so it is a struct
/// that is created once and reused every frame.
pub const Renderer = struct {
    /// For each column, the distance to the wall drawn there. Sprites
    /// behind the wall are hidden column by column.
    depth: []f32,
    /// The map's sprites, sorted far to near each frame.
    sprites: []Sprite,

    pub fn init(gpa: std.mem.Allocator, width: usize, sprite_count: usize) !Renderer {
        const depth = try gpa.alloc(f32, width);
        errdefer gpa.free(depth);
        return .{ .depth = depth, .sprites = try gpa.alloc(Sprite, sprite_count) };
    }

    pub fn deinit(r: *Renderer, gpa: std.mem.Allocator) void {
        gpa.free(r.depth);
        gpa.free(r.sprites);
        r.* = undefined;
    }

    pub fn render(r: Renderer, canvas: Canvas, scene: Scene, cam: Camera, opts: Options) void {
        std.debug.assert(r.depth.len == canvas.width);
        if (opts.textured) {
            drawFloorAndCeiling(canvas, scene.textures, cam);
        } else {
            const horizon = canvas.height / 2;
            for (0..canvas.height) |y| @memset(canvas.row(y), if (y < horizon) ceiling_color else floor_color);
        }
        for (0..canvas.width) |x| r.depth[x] = drawWall(canvas, scene, cam, x, opts);
        r.drawSprites(canvas, scene, cam);
    }

    /// Draws each sprite as a 1x1 unit picture standing on the floor and
    /// always facing the camera (a billboard). Sorted far to near, so near
    /// sprites paint over far ones (the painter's algorithm).
    fn drawSprites(r: Renderer, canvas: Canvas, scene: Scene, cam: Camera) void {
        @memcpy(r.sprites, scene.map.sprites);
        std.mem.sort(Sprite, r.sprites, cam, fartherFirst);

        const w: f32 = @floatFromInt(canvas.width);
        const h: f32 = @floatFromInt(canvas.height);
        const plane_len2 = math.dot(cam.plane, cam.plane);
        for (r.sprites) |sprite| {
            // The sprite in camera coordinates: how far in front of the
            // camera (depth), and where across the camera plane (-1 at the
            // left edge, 1 at the right) its center appears.
            const rel = sprite.pos - cam.pos;
            const depth = math.dot(rel, cam.dir);
            if (depth < near) continue;
            const camera_x = math.dot(rel, cam.plane) / (plane_len2 * depth);
            const center_x = (camera_x + 1) / 2 * w;
            const size = wallHeight(canvas.height, depth);
            const left = center_x - size / 2;
            const top = h / 2 - size / 2;

            const tex = scene.textures.get(spriteTexture(sprite.thing));
            const x0 = pixelRow(left, canvas.width);
            const x1 = pixelRow(left + size, canvas.width);
            const y0 = pixelRow(top, canvas.height);
            const y1 = pixelRow(top + size, canvas.height);
            for (x0..x1) |x| {
                if (depth >= r.depth[x]) continue; // behind the wall in this column
                const u = (@as(f32, @floatFromInt(x)) + 0.5 - left) / size;
                for (y0..y1) |y| {
                    const v = (@as(f32, @floatFromInt(y)) + 0.5 - top) / size;
                    const color = tex.sample(u, v);
                    if (color.a != 0) canvas.pixels[y * canvas.width + x] = color;
                }
            }
        }
    }
};

/// Sprites closer than this are not drawn: they would fill the screen.
const near = 0.1;

fn fartherFirst(cam: Camera, a: Sprite, b: Sprite) bool {
    const da = a.pos - cam.pos;
    const db = b.pos - cam.pos;
    return math.dot(da, da) > math.dot(db, db);
}

/// Draws the wall in column `x` and returns its distance.
fn drawWall(canvas: Canvas, scene: Scene, cam: Camera, x: usize, opts: Options) f32 {
    const h: f32 = @floatFromInt(canvas.height);
    const ray = cam.ray(x, canvas.width);
    const hit = cast(scene.map, cam.pos, ray);
    const dist = if (opts.fisheye) hit.t * math.length(ray) else hit.t;
    const wall_h = wallHeight(canvas.height, dist);
    const top = h / 2 - wall_h / 2;
    // Fill the rows whose pixel centers lie between top and bottom.
    const y0 = pixelRow(top, canvas.height);
    const y1 = pixelRow(top + wall_h, canvas.height);
    const shade: f32 = if (hit.side == .y) y_side_shade else 1;

    if (!opts.textured) {
        const color = wallColor(hit.tile).scale(shade);
        for (y0..y1) |y| canvas.pixels[y * canvas.width + x] = color;
        return hit.t;
    }

    // Where along the wall face the ray hit, 0 to 1: the texture column.
    const p = cam.pos + math.scale(ray, hit.t);
    const along = if (hit.side == .x) p[1] else p[0];
    var u = along - @floor(along);
    // Flip faces seen from the other side, so no texture is mirrored.
    if ((hit.side == .x and ray[0] < 0) or (hit.side == .y and ray[1] > 0)) u = 1 - u;

    const tex = scene.textures.get(wallTexture(hit.tile));
    const tx: i32 = @intFromFloat(@floor(u * texture.size));
    for (y0..y1) |y| {
        const v = (@as(f32, @floatFromInt(y)) + 0.5 - top) / wall_h;
        const ty: i32 = @intFromFloat(@floor(v * texture.size));
        canvas.pixels[y * canvas.width + x] = tex.texel(tx, ty).scale(shade);
    }
    return hit.t;
}

/// Floor casting: every row below the horizon shows the floor at one
/// distance, so walk across the row in equal steps over the floor.
/// The ceiling is the same picture mirrored about the horizon.
fn drawFloorAndCeiling(canvas: Canvas, textures: *const texture.Set, cam: Camera) void {
    const floor_tex = textures.get(.floor);
    const ceiling_tex = textures.get(.ceiling);
    const w: f32 = @floatFromInt(canvas.width);
    const h: f32 = @floatFromInt(canvas.height);
    for (canvas.height / 2..canvas.height) |y| {
        // The eye is half a unit above the floor. A floor point at
        // distance d appears (h / d) / 2 pixels below the horizon (like the
        // bottom of a wall), so this row's pixel center sees distance:
        const below = @as(f32, @floatFromInt(y)) + 0.5 - h / 2;
        const d = (h / 2) / below;
        // The floor points under the left and right edges of the screen,
        // and the step from one pixel center to the next.
        const left = cam.pos + math.scale(cam.dir - cam.plane, d);
        const step = math.scale(cam.plane, 2 * d / w);
        var p = left + math.scale(step, 0.5);
        const floor_row = canvas.row(y);
        const ceiling_row = canvas.row(canvas.height - 1 - y);
        for (floor_row, ceiling_row) |*f, *c| {
            f.* = floor_tex.sample(p[0], p[1]);
            c.* = ceiling_tex.sample(p[0], p[1]);
            p += step;
        }
    }
}

/// The first row (or column) whose pixel center (y + 0.5) is at or below
/// `y`, clamped to the screen.
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
