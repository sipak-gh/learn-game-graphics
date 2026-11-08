const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Map = @import("map.zig").Map;
const Thing = @import("map.zig").Thing;
const Input = @import("input.zig").Input;
const camera = @import("camera.zig");

pub const move_speed = 3.0; // cells per second
pub const turn_speed = 2.5; // radians per second
pub const tilt_speed = 1.5; // radians per second, for the arrow keys
pub const mouse_sensitivity = 0.003; // radians per pixel of mouse movement

/// The player is a circle this big (in cells) on the map.
pub const radius = 0.25;
/// How far the player can look up or down: 85 degrees. Straight up, the
/// camera would have no well-defined right (gotcha 24).
pub const max_pitch = std.math.degreesToRadians(85.0);

// The farthest point of the near plane that is in view, a corner, is
// near * sqrt(1 + tan²(hfov/2) + tan²(vfov/2)) from the eye. Anything the
// player can touch must stay farther away than that, or the near plane
// cuts it open and we see through it (ch21-window.png).
comptime {
    const tan_v = @tan(camera.vfov / 2.0);
    const tan_h = tan_v * 640.0 / 400.0;
    std.debug.assert(radius > camera.near * @sqrt(1 + tan_h * tan_h + tan_v * tan_v));
}

/// How big each kind of thing is, if the player bumps into it. Lamps
/// are thin poles, and the player walks past them.
pub fn thingRadius(thing: Thing) ?f32 {
    return switch (thing) {
        .barrel => 0.23,
        .lamp => null,
    };
}

pub const Player = struct {
    pos: Vec2,
    /// The direction the player faces, in radians from east (+x) toward
    /// south (+y): clockwise on the top-down map.
    yaw: f32,
    /// How far the player looks up (positive) or down, in radians. Only
    /// the 3D camera uses it; the ray caster cannot look up or down.
    pitch: f32 = 0,

    /// The unit vector the player faces.
    pub fn dir(player: Player) Vec2 {
        return math.fromAngle(player.yaw);
    }

    pub fn update(player: *Player, input: Input, map: Map, dt: f32) void {
        const turn = input.turn * turn_speed * dt + input.look * mouse_sensitivity;
        player.yaw = @mod(player.yaw + turn, std.math.tau);
        // Moving the mouse down (+y on screen) looks down.
        const tilt = input.tilt * tilt_speed * dt - input.look_y * mouse_sensitivity;
        player.pitch = std.math.clamp(player.pitch + tilt, -max_pitch, max_pitch);

        // Forward and strafe combine into one direction, normalized so
        // that moving diagonally is not faster.
        const forward = player.dir();
        const right = math.perp(forward);
        const wish = math.scale(forward, input.forward) + math.scale(right, input.strafe);
        const step = math.scale(math.normalize(wish), move_speed * dt);

        // Move, then push the circle back out of whatever it overlaps.
        // Between a barrel and a wall there may be no room at all; then
        // the player stays where it was.
        const moved = collide(map, player.pos + step);
        if (!bumpsThing(map, moved)) player.pos = moved;
    }
};

/// Pushes a circle of `radius` at `pos` out of the things and walls it
/// overlaps. Each push goes straight away from the closest point, so only
/// the part of a move that goes into a wall is undone: the player slides.
pub fn collide(map: Map, pos: Vec2) Vec2 {
    var p = pos;
    for (map.sprites) |sprite| {
        const r = thingRadius(sprite.thing) orelse continue;
        p = pushOut(p, sprite.pos, radius + r);
    }
    // A circle smaller than a cell can only touch the 3x3 cells around
    // the one it is in. Walls go last: never end up inside one.
    const cell = @floor(p);
    const cx: i32 = @intFromFloat(cell[0]);
    const cy: i32 = @intFromFloat(cell[1]);
    var y = cy - 1;
    while (y <= cy + 1) : (y += 1) {
        var x = cx - 1;
        while (x <= cx + 1) : (x += 1) {
            if (!map.at(x, y).isWall()) continue;
            // The closest point of the wall's square to the center.
            const low: Vec2 = .{ @floatFromInt(x), @floatFromInt(y) };
            const closest = @max(low, @min(low + Vec2{ 1, 1 }, p));
            p = pushOut(p, closest, radius);
        }
    }
    return p;
}

/// Moves `p` away from `point` until it is `distance` from it, if closer.
fn pushOut(p: Vec2, point: Vec2, distance: f32) Vec2 {
    const d = p - point;
    const len = math.length(d);
    // At len = 0 there is no direction to push in. Steps are much
    // shorter than the radius, so a center never gets onto a wall.
    if (len >= distance or len == 0) return p;
    return point + math.scale(d, distance / len);
}

/// True if a circle at `pos` overlaps a solid thing.
fn bumpsThing(map: Map, pos: Vec2) bool {
    for (map.sprites) |sprite| {
        const r = thingRadius(sprite.thing) orelse continue;
        // A little slack for rounding: collide put it exactly at the edge.
        if (math.length(pos - sprite.pos) < radius + r - 1e-4) return true;
    }
    return false;
}

test "the player stays a radius away from walls and slides along them" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa,
        \\#####
        \\#>..#
        \\#####
    );
    defer map.deinit(gpa);
    var player: Player = .{ .pos = map.start, .yaw = map.start_yaw };

    // One second forward: 3 cells, but the wall at x = 4 stops us a
    // radius before it.
    for (0..60) |_| player.update(.{ .forward = 1 }, map, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(4 - radius, player.pos[0], 1e-5);
    try std.testing.expectApproxEqAbs(1.5, player.pos[1], 1e-6);

    // Pushing diagonally into the wall below slides along it.
    player = .{ .pos = map.start, .yaw = std.math.pi / 4.0 };
    for (0..10) |_| player.update(.{ .forward = 1 }, map, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(2 - radius, player.pos[1], 1e-5);
    try std.testing.expect(player.pos[0] > map.start[0] + 0.3);
}

test "in a corner the player stops a radius from both walls" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa,
        \\#####
        \\#>..#
        \\#...#
        \\#...#
        \\#####
    );
    defer map.deinit(gpa);
    var player: Player = .{ .pos = map.start, .yaw = 0.7 };
    for (0..120) |_| player.update(.{ .forward = 1 }, map, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(4 - radius, player.pos[0], 1e-5);
    try std.testing.expectApproxEqAbs(4 - radius, player.pos[1], 1e-5);
}

test "barrels are solid, lamps are not" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa,
        \\#######
        \\#>.o..#
        \\#.....#
        \\#.*...#
        \\#######
    );
    defer map.deinit(gpa);
    // Straight at the barrel: stopped where the two circles touch.
    var player: Player = .{ .pos = map.start, .yaw = 0 };
    for (0..60) |_| player.update(.{ .forward = 1 }, map, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(3.5 - radius - 0.23, player.pos[0], 1e-4);
    // Through the lamp's cell: it is in the way, but only a thin pole.
    player = .{ .pos = .{ 1.5, 3.5 }, .yaw = 0 };
    for (0..40) |_| player.update(.{ .forward = 1 }, map, 1.0 / 60.0);
    try std.testing.expect(player.pos[0] > 3);
    // Between the barrel and the wall above there is no room: sliding
    // along the wall toward the barrel stops at it.
    player = .{ .pos = .{ 1.5, 1 + radius }, .yaw = 0 };
    for (0..60) |_| player.update(.{ .forward = 1 }, map, 1.0 / 60.0);
    try std.testing.expect(player.pos[0] < 3.1);
}

test "looking up and down stops at 85 degrees" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa, "#>#");
    defer map.deinit(gpa);
    var player: Player = .{ .pos = map.start, .yaw = 0 };
    // Arrow keys: 1.5 radians per second.
    player.update(.{ .tilt = 1 }, map, 0.5);
    try std.testing.expectApproxEqAbs(0.75, player.pitch, 1e-6);
    for (0..10) |_| player.update(.{ .tilt = 1 }, map, 0.5);
    try std.testing.expectEqual(max_pitch, player.pitch);
    // The mouse: moving it down 1000 pixels looks down 3 radians, as far
    // as it goes.
    player.update(.{ .look_y = 1000 }, map, 1.0 / 60.0);
    try std.testing.expectEqual(-max_pitch, player.pitch);
}

test "turning wraps around" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa, "#>#");
    defer map.deinit(gpa);
    var player: Player = .{ .pos = map.start, .yaw = 0 };
    player.update(.{ .turn = -1 }, map, 0.1);
    try std.testing.expectApproxEqAbs(std.math.tau - 0.25, player.yaw, 1e-5);
}
