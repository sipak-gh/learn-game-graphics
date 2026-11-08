//! The maze in 3D: every wall cell is a unit cube standing on the floor.
//! A map cell (x, y) becomes the cube from (x, 0, y) to (x + 1, 1, y + 1).
//! Every floor cell gets a square of floor at height 0 and of ceiling at
//! height 1. Every lamp of the map is a pole with a glowing globe on top,
//! and a light.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Map = @import("map.zig").Map;
const Tile = @import("map.zig").Tile;
const mesh = @import("mesh.zig");
const cube = mesh.cube;
const render3d = @import("render3d.zig");
const raycast = @import("raycast.zig");
const light = @import("light.zig");
const texture = @import("texture.zig");

fn wireColor(tile: Tile) Color {
    return switch (tile) {
        .floor => unreachable,
        .brick => .hex(0xe08050),
        .stone => .hex(0xb0b0c0),
    };
}

/// True if wall cell (x, y) has a floor cell next to it. Walls buried
/// among other walls can never be seen, so they are not drawn.
pub fn touchesFloor(map: Map, x: i32, y: i32) bool {
    for ([_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |d| {
        if (!map.at(x + d[0], y + d[1]).isWall()) return true;
    }
    return false;
}

/// Draws the edges of every visible wall cube.
pub fn drawWireframe(
    r: render3d.Renderer,
    canvas: Canvas,
    map: Map,
    view_proj: Mat4,
    options: render3d.Options,
    stats: *render3d.Stats,
) void {
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const tile = map.at(@intCast(x), @intCast(y));
            if (!tile.isWall() or !touchesFloor(map, @intCast(x), @intCast(y))) continue;
            const model = Mat4.translation(.{ @floatFromInt(x), 0, @floatFromInt(y) });
            r.drawWireframe(canvas, cube, model, view_proj, wireColor(tile), options, stats);
        }
    }
}

/// Paints each face in its material without light, the way the ray
/// caster does: faces across the map's y (along the world's z) are darker.
pub const FlatShader = struct {
    material: light.Material,

    pub const wants_footprint = true;

    pub fn vertex(_: FlatShader, v: mesh.Vertex, _: Vec3) render3d.Varyings {
        var vary: render3d.Varyings = @splat(0);
        vary[0] = if (v.normal[2] != 0) raycast.y_side_shade else 1;
        return light.withUv(vary, v);
    }

    pub fn pixel(s: FlatShader, vary: render3d.Varyings) Color {
        const rgb = math.scale(s.material.at(vary), vary[0]);
        return render3d.toColor(.{ rgb[0], rgb[1], rgb[2], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    }
};

/// How the surfaces are painted: in flat colors, or with textures read
/// through `filter`.
pub const Paint = struct {
    textures: ?*const texture.Set = null,
    filter: texture.Filter = .trilinear,
    show_levels: bool = false,

    /// The material of a surface whose flat color is `color` and whose
    /// texture is `kind`.
    pub fn material(p: Paint, color: Color, kind: texture.Kind) light.Material {
        const set = p.textures orelse return .{ .color = color };
        return .{ .color = color, .texture = set.ptr(kind), .filter = p.filter, .show_levels = p.show_levels };
    }
};

const floor_face = mesh.cubeFace(2); // the top of a cube, facing up
const ceiling_face = mesh.cubeFace(3); // the bottom, facing down

/// The center of a lamp's globe, above the floor.
pub const lamp_height = 0.72;
const globe_size = 0.12;
const pole_width = 0.03;
const globe_color: Color = .hex(0xfff0c0);
const pole_color: Color = .hex(0x484040);

/// The light of the lamp standing at map position `pos`: warm, like a
/// flame.
pub fn lampLight(pos: Vec2) light.Light {
    return .{ .pos = .{ pos[0], lamp_height, pos[1] }, .color = .{ 2.8, 2.0, 1.1 }, .radius = 5 };
}

/// The most lights that may reach one cell.
const max_cell_lights = 8;

/// Draws one mesh, either unlit with a flat color per face or lit by the
/// lights of `scene` that reach the box from `min` to `max`.
fn drawPart(
    r: render3d.Renderer,
    canvas: Canvas,
    part: mesh.Mesh,
    model: Mat4,
    view_proj: Mat4,
    material: light.Material,
    shading: light.Shading,
    scene: light.Scene,
    box: [2]Vec3,
    options: render3d.Options,
    stats: *render3d.Stats,
) void {
    if (shading == .unlit) {
        r.drawMesh(canvas, part, model, view_proj, FlatShader{ .material = material }, options, stats);
    } else {
        var buffer: [max_cell_lights]light.Light = undefined;
        const near = scene.reaching(box[0], box[1], &buffer);
        const shader: light.Shader = .init(near, material, shading, model);
        r.drawMesh(canvas, part, model, view_proj, shader, options, stats);
    }
}

/// Draws the maze filled: the visible wall cubes, the floor and ceiling
/// over every floor cell, and the lamps, painted as `paint` says, shaded
/// as `shading` says, and lit by `scene`.
pub fn drawSolid(
    r: render3d.Renderer,
    canvas: Canvas,
    map: Map,
    view_proj: Mat4,
    paint: Paint,
    shading: light.Shading,
    scene: light.Scene,
    render_options: render3d.Options,
    stats: *render3d.Stats,
) void {
    var options = render_options;
    options.flat_shading = shading == .flat;
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const tile = map.at(@intCast(x), @intCast(y));
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);
            const box = [2]Vec3{ .{ fx, 0, fy }, .{ fx + 1, 1, fy + 1 } };
            if (tile.isWall()) {
                if (!touchesFloor(map, @intCast(x), @intCast(y))) continue;
                const model: Mat4 = .translation(box[0]);
                const wall = paint.material(raycast.wallColor(tile), raycast.wallTexture(tile));
                drawPart(r, canvas, cube, model, view_proj, wall, shading, scene, box, options, stats);
            } else {
                const floor: Mat4 = .translation(.{ fx, -1, fy });
                drawPart(r, canvas, floor_face, floor, view_proj, paint.material(raycast.floor_color, .floor), shading, scene, box, options, stats);
                const ceiling: Mat4 = .translation(.{ fx, 1, fy });
                drawPart(r, canvas, ceiling_face, ceiling, view_proj, paint.material(raycast.ceiling_color, .ceiling), shading, scene, box, options, stats);
            }
        }
    }
    for (map.sprites) |sprite| {
        if (sprite.thing != .lamp) continue;
        const base: Vec3 = .{ sprite.pos[0], 0, sprite.pos[1] };
        // The pole: the unit cube, squeezed thin and stretched up to the
        // globe. Its box is tight, so only lights close by are used.
        const pole_size: Vec3 = .{ pole_width, lamp_height - globe_size / 2.0, pole_width };
        const pole_corner = base - Vec3{ pole_width / 2.0, 0, pole_width / 2.0 };
        const pole = Mat4.translation(pole_corner).mul(.scaling(pole_size));
        drawPart(r, canvas, cube, pole, view_proj, .{ .color = pole_color }, shading, scene, .{ pole_corner, pole_corner + pole_size }, options, stats);
        // The globe gives light and gets none: always drawn unlit.
        const globe = Mat4.translation(base + Vec3{ -globe_size / 2.0, lamp_height - globe_size / 2.0, -globe_size / 2.0 })
            .mul(.scaling(@splat(globe_size)));
        r.drawMesh(canvas, cube, globe, view_proj, FlatShader{ .material = .{ .color = globe_color } }, options, stats);
    }
}

test "only walls next to the floor are drawn" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa,
        \\#####
        \\#>..#
        \\#####
    );
    defer map.deinit(gpa);
    try std.testing.expect(touchesFloor(map, 0, 1));
    try std.testing.expect(touchesFloor(map, 2, 0));
    try std.testing.expect(!touchesFloor(map, 0, 0)); // a corner: walls all around
    try std.testing.expect(!touchesFloor(map, -1, 1)); // outside the map
}

test "the maze has no cracks" {
    // Everywhere the eye looks inside the maze there is a wall, the floor,
    // or the ceiling. Any pixel left in the clear color is a crack.
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa, @embedFile("maps/cellar.txt"));
    defer map.deinit(gpa);
    var canvas = try Canvas.init(gpa, 160, 100);
    defer canvas.deinit(gpa);
    var r = try render3d.Renderer.init(gpa, 24, 160, 100);
    defer r.deinit(gpa);
    const camera = @import("camera.zig");
    const crack: Color = .hex(0xff00ff);
    var lights: [16]light.Light = undefined;
    var n: usize = 0;
    for (map.sprites) |sprite| {
        if (sprite.thing != .lamp) continue;
        lights[n] = lampLight(sprite.pos);
        n += 1;
    }
    var textures = try texture.Set.generate(gpa);
    defer textures.deinit(gpa);
    for ([_][3]f32{ .{ 9.5, 10.5, -1 }, .{ 1.5, 1.5, 0.6 }, .{ 20.3, 13.7, 2.5 }, .{ 12.5, 18.5, 3.1 } }) |pose| {
        const cam: camera.Camera = .{ .pos = .{ pose[0], camera.eye_height, pose[1] }, .yaw = pose[2], .pitch = 0.3 * pose[2] };
        const scene: light.Scene = .{ .ambient = @splat(0.1), .lights = lights[0..n], .eye = cam.pos };
        for (std.enums.values(light.Shading)) |shading| for ([_]Paint{ .{}, .{ .textures = &textures } }) |paint| {
            canvas.clear(crack);
            r.clearDepth();
            var stats: render3d.Stats = .{};
            drawSolid(r, canvas, map, cam.viewProjection(160, 100), paint, shading, scene, .{}, &stats);
            for (canvas.pixels) |p| try std.testing.expect(!std.meta.eql(p, crack));
            try std.testing.expect(stats.pixels >= 160 * 100);
        };
    }
}
