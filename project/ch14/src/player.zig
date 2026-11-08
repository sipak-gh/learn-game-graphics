const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Map = @import("map.zig").Map;
const Input = @import("input.zig").Input;

pub const move_speed = 3.0; // cells per second
pub const turn_speed = 2.5; // radians per second
pub const mouse_sensitivity = 0.003; // radians per pixel of mouse movement

pub const Player = struct {
    pos: Vec2,
    /// The direction the player faces, in radians from east (+x) toward
    /// south (+y): clockwise on the top-down map.
    yaw: f32,

    /// The unit vector the player faces.
    pub fn dir(player: Player) Vec2 {
        return math.fromAngle(player.yaw);
    }

    pub fn update(player: *Player, input: Input, map: Map, dt: f32) void {
        const turn = input.turn * turn_speed * dt + input.look * mouse_sensitivity;
        player.yaw = @mod(player.yaw + turn, std.math.tau);

        // Forward and strafe combine into one direction, normalized so
        // that moving diagonally is not faster.
        const forward = player.dir();
        const right = math.perp(forward);
        const wish = math.scale(forward, input.forward) + math.scale(right, input.strafe);
        const step = math.scale(math.normalize(wish), move_speed * dt);

        // Move along x and y separately: when one axis is blocked by a
        // wall, the other still moves, so the player slides along it.
        const try_x = player.pos + Vec2{ step[0], 0 };
        if (!map.isWallAt(try_x)) player.pos = try_x;
        const try_y = player.pos + Vec2{ 0, step[1] };
        if (!map.isWallAt(try_y)) player.pos = try_y;
    }
};

test "moving forward and sliding along a wall" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa,
        \\#####
        \\#>..#
        \\#####
    );
    defer map.deinit(gpa);
    var player: Player = .{ .pos = map.start, .yaw = map.start_yaw };

    // One second forward: 3 cells, but the wall at x = 4 stops us.
    for (0..60) |_| player.update(.{ .forward = 1 }, map, 1.0 / 60.0);
    try std.testing.expect(player.pos[0] < 4);
    try std.testing.expect(player.pos[0] > 3.9);
    try std.testing.expectApproxEqAbs(1.5, player.pos[1], 1e-6);

    // Pushing diagonally into the wall still slides along it.
    player = .{ .pos = map.start, .yaw = std.math.pi / 4.0 };
    player.update(.{ .forward = 1 }, map, 0.1);
    try std.testing.expect(player.pos[0] > map.start[0]);
}

test "turning wraps around" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa, "#>#");
    defer map.deinit(gpa);
    var player: Player = .{ .pos = map.start, .yaw = 0 };
    player.update(.{ .turn = -1 }, map, 0.1);
    try std.testing.expectApproxEqAbs(std.math.tau - 0.25, player.yaw, 1e-5);
}
