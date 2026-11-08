//! Light and fog: how bright a surface is from the lights that reach it,
//! and how much of it is still seen through the air between it and the
//! eye. Colors here are vectors of red, green, and blue, 0 to 255, like
//! the varyings; light is a factor per channel, 1 meaning full strength.
const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Color = @import("canvas.zig").Color;
const mesh = @import("mesh.zig");
const render3d = @import("render3d.zig");

/// How often the light on a surface is worked out, from least to most.
pub const Shading = enum {
    /// Not at all: each face keeps its own flat color, as in chapter 18.
    unlit,
    /// Once per triangle.
    flat,
    /// At each corner, with the colors blended across the triangle
    /// (Gouraud shading).
    gouraud,
    /// At each pixel, from the position and normal blended across the
    /// triangle (Phong shading).
    phong,
};

/// A point light: it shines the same way in every direction.
pub const Light = struct {
    pos: Vec3,
    /// Color and strength, per channel.
    color: Vec3,
    /// Beyond this distance the light adds nothing.
    radius: f32,
};

/// Lambert's cosine law: a surface facing the light gets all of it, a
/// surface tilted by an angle gets cos(angle) of it (the same light
/// spread over more area), and a surface facing away gets none. Both
/// directions have length 1, so the cosine is their dot product.
pub fn lambert(normal: Vec3, to_light: Vec3) f32 {
    return @max(0, math.dot(normal, to_light));
}

/// The distance at which a light is down to half its strength (before the
/// window): a cell and a half. The 1 + of the falloff stands for the size
/// of the flame or bulb, which is not a point; this sets that size.
pub const half_distance = 1.5;

/// How much of a light reaches `dist` away. Light spreads over a sphere
/// whose area grows with the square of the distance, so it fades as
/// 1/dist^2; the 1 + keeps that finite at the light itself. The window
/// (1 - (dist/radius)^2)^2 brings it smoothly down to exactly 0 at
/// `radius`, so lights farther away can be skipped without a visible edge.
pub fn attenuation(dist: f32, radius: f32) f32 {
    const x = dist / radius;
    const window = @max(0, 1 - x * x);
    const d = dist / half_distance;
    return window * window / (1 + d * d);
}

pub const Fog = struct {
    color: Vec3,
    /// How much of the light the air takes away per unit of distance.
    density: f32,
};

/// The share of a surface's light that comes through `dist` of fog. Each
/// bit of air takes away the same share of what passes through it, so
/// what is left falls off exponentially: exp(-density * dist).
pub fn visibility(dist: f32, density: f32) f32 {
    return @exp(-density * dist);
}

pub const Scene = struct {
    /// Light that is everywhere, from every direction: the light bounced
    /// around by all the walls, which is too costly to work out.
    ambient: Vec3,
    lights: []const Light,
    eye: Vec3,
    fog: ?Fog = null,

    /// The light falling on a surface at `pos` facing `normal`.
    pub fn lightAt(scene: Scene, pos: Vec3, normal: Vec3) Vec3 {
        var sum = scene.ambient;
        for (scene.lights) |light| {
            const to_light = light.pos - pos;
            // Two cheap tests first: out of reach, or lit from behind.
            const dist_squared = math.dot(to_light, to_light);
            if (dist_squared >= light.radius * light.radius) continue;
            if (math.dot(normal, to_light) <= 0) continue;
            const dist = @sqrt(dist_squared);
            const strength = lambert(normal, math.scale(to_light, 1 / dist)) * attenuation(dist, light.radius);
            sum += math.scale(light.color, strength);
        }
        return sum;
    }

    /// The share of the light from `pos` that reaches the eye.
    pub fn fogAt(scene: Scene, pos: Vec3) f32 {
        const fog = scene.fog orelse return 1;
        return visibility(math.length(pos - scene.eye), fog.density);
    }

    /// `color`, with the share `seen` of it reaching the eye and the fog's
    /// color making up the rest.
    pub fn applyFog(scene: Scene, color: Vec3, seen: f32) Vec3 {
        const fog = scene.fog orelse return color;
        return math.lerp(fog.color, color, seen);
    }

    /// The scene with only the lights that reach some point of the box
    /// from `min` to `max`, kept in `buffer`. Everything drawn inside the
    /// box then loops over fewer lights.
    pub fn reaching(scene: Scene, min: Vec3, max: Vec3, buffer: []Light) Scene {
        var n: usize = 0;
        for (scene.lights) |light| {
            // The point of the box nearest to the light.
            const nearest = std.math.clamp(light.pos, min, max);
            if (math.length(light.pos - nearest) >= light.radius) continue;
            if (n == buffer.len) break;
            buffer[n] = light;
            n += 1;
        }
        var near = scene;
        near.lights = buffer[0..n];
        return near;
    }
};

/// A color as a vector, for lighting.
pub fn fromColor(c: Color) Vec3 {
    return .{ @floatFromInt(c.r), @floatFromInt(c.g), @floatFromInt(c.b) };
}

/// Lights a mesh of one color. The varyings are the lit color in lanes 0
/// to 2 and how much of it gets through the fog in lane 6. For Phong
/// shading, lanes 0 to 2 hold the normal instead, and lanes 3 to 5 the
/// position in the world, to light each pixel. Flat shading also needs
/// `Options.flat_shading`, which gives each triangle the average of its
/// corners' varyings.
///
/// The fog is worked out per vertex too, even for Phong shading: an
/// exponential per pixel costs more than all the rest of the fog, and
/// across one cell of the maze it is nearly a straight line anyway.
pub const Shader = struct {
    scene: Scene,
    color: Vec3,
    shading: Shading,
    /// Turns the mesh's normals into the world's.
    normal_matrix: Mat4,

    pub fn init(scene: Scene, color: Color, shading: Shading, model: Mat4) Shader {
        std.debug.assert(shading != .unlit);
        return .{ .scene = scene, .color = fromColor(color), .shading = shading, .normal_matrix = model.normalMatrix() };
    }

    pub fn vertex(s: Shader, v: mesh.Vertex, world: Vec3) render3d.Varyings {
        const normal = math.normalize(s.normal_matrix.transformDir(v.normal));
        const first = if (s.shading == .phong) normal else s.color * s.scene.lightAt(world, normal);
        return .{ first[0], first[1], first[2], world[0], world[1], world[2], s.scene.fogAt(world), 0 };
    }

    pub fn pixel(s: Shader, vary: render3d.Varyings) Color {
        var rgb: Vec3 = .{ vary[0], vary[1], vary[2] };
        if (s.shading == .phong) {
            const world: Vec3 = .{ vary[3], vary[4], vary[5] };
            // Blending unit normals shortens them: normalize again.
            rgb = s.color * s.scene.lightAt(world, math.normalize(rgb));
        }
        rgb = s.scene.applyFog(rgb, vary[6]);
        return render3d.toColor(.{ rgb[0], rgb[1], rgb[2], 0, 0, 0, 0, 0 });
    }
};

const expectApprox = std.testing.expectApproxEqAbs;

test "Lambert: light falls off with the cosine of the angle" {
    const up: Vec3 = .{ 0, 1, 0 };
    try expectApprox(1, lambert(up, up), 1e-6);
    // 60 degrees away from the normal: half the light.
    const angle = std.math.degreesToRadians(60.0);
    try expectApprox(0.5, lambert(up, .{ @sin(angle), @cos(angle), 0 }), 1e-6);
    // From behind: none at all, not a negative amount.
    try std.testing.expectEqual(0, lambert(up, .{ 0, -1, 0 }));
}

test "attenuation fades to exactly zero at the radius" {
    try expectApprox(1, attenuation(0, 5), 1e-6);
    var last: f32 = 1;
    for (1..50) |i| {
        const a = attenuation(0.1 * @as(f32, @floatFromInt(i)), 5);
        try std.testing.expect(a < last);
        last = a;
    }
    try std.testing.expectEqual(0, attenuation(5, 5));
    try std.testing.expectEqual(0, attenuation(7, 5));
    // Well inside the radius it is nearly the inverse square law: half
    // at `half_distance`, a fifth at twice that.
    try expectApprox(0.5, attenuation(half_distance, 1000), 1e-5);
    try expectApprox(0.2, attenuation(2 * half_distance, 1000), 1e-5);
}

test "fog takes the same share of the light per unit of distance" {
    try expectApprox(1, visibility(0, 0.2), 1e-6);
    try expectApprox(1.0 / std.math.e, visibility(5, 0.2), 1e-6);
    try expectApprox(visibility(3, 0.2) * visibility(4, 0.2), visibility(7, 0.2), 1e-6);
    const scene: Scene = .{ .ambient = @splat(0), .lights = &.{}, .eye = @splat(0), .fog = .{ .color = .{ 10, 20, 30 }, .density = 0.2 } };
    const seen = scene.fogAt(.{ 0, 0, -1000 });
    try std.testing.expect(math.approxEq(scene.applyFog(.{ 200, 200, 200 }, seen), Vec3{ 10, 20, 30 }));
    try std.testing.expect(math.approxEq(scene.applyFog(.{ 200, 200, 200 }, 1), Vec3{ 200, 200, 200 }));
}

test "only lights within their radius of a box reach it" {
    const lights = [_]Light{
        .{ .pos = .{ 3, 0.5, 0.5 }, .color = @splat(1), .radius = 2.5 }, // 2 from the box: reaches
        .{ .pos = .{ 3, 0.5, 0.5 }, .color = @splat(1), .radius = 1.5 }, // too short
        .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = @splat(1), .radius = 0.1 }, // inside
    };
    const scene: Scene = .{ .ambient = @splat(0), .lights = &lights, .eye = @splat(0) };
    var buffer: [4]Light = undefined;
    const near = scene.reaching(.{ 0, 0, 0 }, .{ 1, 1, 1 }, &buffer);
    try std.testing.expectEqual(2, near.lights.len);
    try std.testing.expectEqual(2.5, near.lights[0].radius);
    try std.testing.expectEqual(0.1, near.lights[1].radius);
}

test "Gouraud shading misses a light over the middle of a face" {
    // A floor from (-2, 0, -2) to (2, 0, 2) with a light just above its
    // center. Its four corners are far from the light and get little;
    // blending them can never be brighter than the brightest corner.
    const light: Light = .{ .pos = .{ 0, 0.5, 0 }, .color = @splat(1), .radius = 4 };
    const scene: Scene = .{ .ambient = @splat(0), .lights = &.{light}, .eye = .{ 0, 1, 3 } };
    const corners = [4]Vec3{ .{ -2, 0, -2 }, .{ 2, 0, -2 }, .{ 2, 0, 2 }, .{ -2, 0, 2 } };
    const up: Vec3 = .{ 0, 1, 0 };
    var results: [2]Color = undefined;
    for ([_]Shading{ .gouraud, .phong }, &results) |shading, *result| {
        const s = Shader.init(scene, Color.white, shading, Mat4.identity);
        // The varyings at the center are the average of the corners'.
        var sum: render3d.Varyings = @splat(0);
        for (corners) |pos| sum += s.vertex(.{ .pos = pos, .normal = up }, pos);
        result.* = s.pixel(math.scale(sum, 0.25));
    }
    try std.testing.expect(results[0].r < 10);
    // Lit at the pixel itself, the center is close to the light.
    try std.testing.expect(results[1].r > 150);
}
