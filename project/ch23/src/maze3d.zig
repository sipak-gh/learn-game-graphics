//! How the maze in 3D is painted and lit: the shader for unlit surfaces,
//! the materials of each surface, and the lamps, each a pole with a
//! glowing globe on top, and a light. world.zig builds the meshes.
//! A map cell (x, y) is the square from (x, 0, y) to (x + 1, 1, y + 1).
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const mesh = @import("mesh.zig");
const cube = mesh.cube;
const render3d = @import("render3d.zig");
const raycast = @import("raycast.zig");
const light = @import("light.zig");
const texture = @import("texture.zig");

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
    /// Paint each chunk of the world in a color of its own instead.
    chunk_colors: bool = false,

    /// The material of a surface whose flat color is `color` and whose
    /// texture is `kind`.
    pub fn material(p: Paint, color: Color, kind: texture.Kind) light.Material {
        const set = p.textures orelse return .{ .color = color };
        return .{ .color = color, .texture = set.ptr(kind), .filter = p.filter, .show_levels = p.show_levels };
    }
};

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

/// The most lights that may reach one part.
const max_part_lights = 16;

/// Draws one mesh, either unlit with a flat color per face or lit by the
/// lights of `scene` that reach `box`, the lowest and highest corner of a
/// box the mesh is inside.
pub fn drawPart(
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
        var buffer: [max_part_lights]light.Light = undefined;
        const near = scene.reaching(box[0], box[1], &buffer);
        const shader: light.Shader = .init(near, material, shading, model);
        r.drawMesh(canvas, part, model, view_proj, shader, options, stats);
    }
}

/// Draws the lamp standing at map position `pos`.
pub fn drawLamp(
    r: render3d.Renderer,
    canvas: Canvas,
    pos: Vec2,
    view_proj: Mat4,
    shading: light.Shading,
    scene: light.Scene,
    options: render3d.Options,
    stats: *render3d.Stats,
) void {
    const base: Vec3 = .{ pos[0], 0, pos[1] };
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
