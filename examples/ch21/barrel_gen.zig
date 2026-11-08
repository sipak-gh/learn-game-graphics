//! The generator of delve's src/models/barrel.obj. A barrel is a profile
//! curve (radius by height) turned around the y axis: rings of `sides`
//! corners at a few heights, joined by quads, with a lid on top. Writes
//! the OBJ text to standard output; an argument changes the number of
//! sides.
//!
//!   zig run examples/ch21/barrel_gen.zig > barrel.obj
//!   zig run examples/ch21/barrel_gen.zig -- 6 > barrel6.obj
const std = @import("std");

const height = 0.45;
/// Rings at these fractions of the height: more where the curve bends.
const rings = [_]f64{ 0, 0.2, 0.5, 0.8, 1 };
/// The lid's texture coordinates: the top ring, scaled into the middle of
/// the texture.
const lid_scale = 0.6;

/// The radius at height h: 0.19 at the ends, 0.23 in the middle.
fn radius(h: f64) f64 {
    return 0.19 + 0.04 * @sin(std.math.pi * h / height);
}

/// How fast the radius grows with the height: the derivative of `radius`.
fn slope(h: f64) f64 {
    return 0.04 * std.math.pi / height * @cos(std.math.pi * h / height);
}

/// Rounded to 4 decimals, and never "-0".
fn r4(x: f64) f64 {
    return @round(x * 10000) / 10000 + 0.0;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const sides: usize = if (args.len > 1) try std.fmt.parseInt(usize, args[1], 10) else 12;
    const n: f64 = @floatFromInt(sides);

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &writer.interface;
    try out.print(
        \\# A barrel for delve: {d} staves around, bulging in the middle, with a lid.
        \\# Bottom at y = 0, height 0.45, centered on x = z = 0. The bottom is
        \\# never seen (it stands on the floor), so it has no face.
        \\# Texture: u goes once around, v from the bottom (0) to the top (1).
        \\o barrel
        \\
    , .{sides});

    // Positions: ring by ring, `sides` corners each.
    for (rings) |f| {
        const h = f * height;
        for (0..sides) |k| {
            const angle = 2 * std.math.pi * @as(f64, @floatFromInt(k)) / n;
            try out.print("v {d} {d} {d}\n", .{ r4(radius(h) * @cos(angle)), r4(h), r4(radius(h) * @sin(angle)) });
        }
    }
    // Texture coordinates: one more per ring than there are corners. The
    // seam where u wraps from 1 back to 0 needs both u = 0 and u = 1.
    for (rings) |f| {
        for (0..sides + 1) |k| try out.print("vt {d} {d}\n", .{ r4(@as(f64, @floatFromInt(k)) / n), r4(f) });
    }
    // The lid's: a circle in the middle of the texture.
    const top = radius(height);
    for (0..sides + 1) |k| {
        const angle = 2 * std.math.pi * @as(f64, @floatFromInt(k)) / n;
        try out.print("vt {d} {d}\n", .{ r4(0.5 + lid_scale * top * @cos(angle)), r4(0.5 + lid_scale * top * @sin(angle)) });
    }
    // Normals: the profile's tangent is (r', 1) in the (out, up) plane,
    // so the normal in that plane is (1, -r'), turned around by the angle.
    for (rings) |f| {
        const h = f * height;
        for (0..sides) |k| {
            const angle = 2 * std.math.pi * @as(f64, @floatFromInt(k)) / n;
            const nx = @cos(angle);
            const ny = -slope(h);
            const nz = @sin(angle);
            const len = @sqrt(nx * nx + ny * ny + nz * nz);
            try out.print("vn {d} {d} {d}\n", .{ r4(nx / len), r4(ny / len), r4(nz / len) });
        }
    }
    try out.writeAll("vn 0 1 0\n");

    // Sides: a quad between ring j and ring j + 1 for every k, going up,
    // around, and down: counter-clockwise seen from outside. Numbers in
    // OBJ count from 1.
    for (0..rings.len - 1) |j| {
        for (0..sides) |k| {
            const quad = [4][2]usize{ .{ j, k }, .{ j + 1, k }, .{ j + 1, k + 1 }, .{ j, k + 1 } };
            try out.writeAll("f");
            for (quad) |c| {
                const p = c[0] * sides + c[1] % sides + 1;
                const t = c[0] * (sides + 1) + c[1] + 1;
                try out.print(" {d}/{d}/{d}", .{ p, t, p });
            }
            try out.writeAll("\n");
        }
    }
    // The lid: one face with all the corners of the top ring, backwards so
    // it is counter-clockwise seen from above.
    try out.writeAll("f");
    const top_ring = (rings.len - 1) * sides;
    const lid_uvs = rings.len * (sides + 1);
    for (0..sides) |i| {
        const k = sides - 1 - i;
        try out.print(" {d}/{d}/{d}", .{ top_ring + k + 1, lid_uvs + k + 1, rings.len * sides + 1 });
    }
    try out.writeAll("\n");
    try out.flush();
}
