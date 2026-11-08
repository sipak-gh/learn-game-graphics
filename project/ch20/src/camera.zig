//! The 3D camera: where the eye is, where it looks, and the matrices that
//! take a point in the world to a pixel on the screen.
//!
//! The world is right-handed with y up. A map point (x, y) is the world
//! point (x, height, y): the map's y becomes the world's z. Walls stand
//! from height 0 to 1, and the eye is at height 0.5.
const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Player = @import("player.zig").Player;

pub const eye_height = 0.5;
pub const world_up: Vec3 = .{ 0, 1, 0 };

/// The vertical field of view: 2 atan(0.5) = 53.13 degrees. On a 640x400
/// screen this shows exactly what the ray caster shows (1 / tan(vfov / 2)
/// is 2, and 2 / aspect = 1.25 = 1 / raycast.plane_scale).
pub const vfov = 2 * std.math.atan(@as(f32, 0.5));
/// Points closer to the eye than `near` or farther than `far` are not
/// drawn. The depth buffer's precision depends on far / near.
pub const near = 0.05;
pub const far = 64.0;

pub const Camera = struct {
    pos: Vec3,
    /// Radians from +x toward +z (the map's east toward south), as for the player.
    yaw: f32,
    /// Radians above the horizon (negative: looking down).
    pitch: f32 = 0,

    /// The camera at the player's eyes.
    pub fn fromPlayer(player: Player) Camera {
        return .{
            .pos = .{ player.pos[0], eye_height, player.pos[1] },
            .yaw = player.yaw,
            .pitch = player.pitch,
        };
    }

    /// The unit vector the camera looks along.
    pub fn forward(cam: Camera) Vec3 {
        const c = @cos(cam.pitch);
        return .{ @cos(cam.yaw) * c, @sin(cam.pitch), @sin(cam.yaw) * c };
    }

    /// The unit vector to the camera's right, level with the floor.
    pub fn right(cam: Camera) Vec3 {
        return math.normalize(math.cross(cam.forward(), world_up));
    }

    /// The world-to-camera matrix: the eye moves to the origin and looks
    /// down -z.
    pub fn view(cam: Camera) Mat4 {
        return Mat4.lookAt(cam.pos, cam.pos + cam.forward(), world_up);
    }

    /// The camera-to-clip matrix for a screen `width` x `height` pixels.
    pub fn projection(width: usize, height: usize) Mat4 {
        const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        return Mat4.perspective(vfov, aspect, near, far);
    }

    /// World to clip space in one matrix: view first, then projection.
    pub fn viewProjection(cam: Camera, width: usize, height: usize) Mat4 {
        return projection(width, height).mul(cam.view());
    }
};

/// The viewport transform: a clip-space point to screen pixels. Dividing by
/// w gives normalized device coordinates (NDC), -1 to 1 across the screen
/// with y up; the screen's y grows down, so y is flipped. z is the depth,
/// 0 at the near plane and 1 at the far plane.
pub fn toScreen(clip: Vec4, width: usize, height: usize) Vec3 {
    const ndc = math.xyz(clip) / @as(Vec3, @splat(clip[3]));
    const w: f32 = @floatFromInt(width);
    const h: f32 = @floatFromInt(height);
    return .{ (ndc[0] + 1) / 2 * w, (1 - ndc[1]) / 2 * h, ndc[2] };
}

/// Projects the world point `p` to the screen, or returns null if it is
/// not in front of the near plane (dividing by its w would be wrong).
pub fn project(view_proj: Mat4, p: Vec3, width: usize, height: usize) ?Vec3 {
    const clip = view_proj.mulVec(math.vec4(p, 1));
    if (clip[3] < near) return null;
    return toScreen(clip, width, height);
}

const testing = std.testing;
const raycast = @import("raycast.zig");

test "right is the map's perp(dir), lifted into the world" {
    for ([_]f32{ 0, 0.5, 2, 4 }) |yaw| {
        const cam: Camera = .{ .pos = .{ 0, 0, 0 }, .yaw = yaw };
        const p = math.perp(math.fromAngle(yaw));
        try testing.expect(math.approxEq(cam.right(), Vec3{ p[0], 0, p[1] }));
    }
}

test "the point straight ahead lands at the screen center" {
    const cam: Camera = .{ .pos = .{ 3.5, 0.5, 7.5 }, .yaw = 1.2, .pitch = 0.3 };
    const vp = cam.viewProjection(640, 400);
    const s = project(vp, cam.pos + math.scale(cam.forward(), 5), 640, 400).?;
    try testing.expectApproxEqAbs(320, s[0], 1e-3);
    try testing.expectApproxEqAbs(200, s[1], 1e-3);
    // Behind the eye: nothing to draw.
    try testing.expectEqual(null, project(vp, cam.pos - cam.forward(), 640, 400));
}

test "the projection agrees with the ray caster" {
    const player: Player = .{ .pos = .{ 2.5, 3.5 }, .yaw = 0.7 };
    const vp = Camera.fromPlayer(player).viewProjection(640, 400);
    const dir = player.dir();
    const plane = math.scale(math.perp(dir), raycast.plane_scale);
    for ([_]f32{ 0.5, 1, 3, 10 }) |d| {
        // The top of a wall d units ahead is at the ray caster's wall top.
        const ahead = player.pos + math.scale(dir, d);
        const top = project(vp, .{ ahead[0], 1, ahead[1] }, 640, 400).?;
        const wall_h = raycast.wallHeight(400, d);
        try testing.expectApproxEqAbs(200 - wall_h / 2, top[1], 1e-3);
        // A floor point at the end of the camera plane, scaled by d, is at
        // the right edge of the screen.
        const edge = player.pos + math.scale(dir + plane, d);
        const s = project(vp, .{ edge[0], 0, edge[1] }, 640, 400).?;
        try testing.expectApproxEqAbs(640, s[0], 1e-2);
        try testing.expectApproxEqAbs(200 + wall_h / 2, s[1], 1e-3);
    }
}
