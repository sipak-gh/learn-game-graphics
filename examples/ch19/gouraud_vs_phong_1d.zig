//! A row of floor from x = -2.5 to 2.5 with a lamp above its middle, at
//! delve's lamp height and radius, lit three ways: at the two ends of one
//! long face and blended between them (Gouraud), the same with the floor
//! cut into five faces one unit wide like the maze's floor cells, and at
//! every sample (Phong).
const std = @import("std");

const lamp_height = 0.72;
const radius = 5.0;
const half_distance = 1.5;

/// The light on the floor at x: Lambert times delve's falloff. The floor
/// faces up, so the cosine is the lamp's height over its distance.
fn lightAt(x: f32) f32 {
    const d = @sqrt(x * x + lamp_height * lamp_height);
    const lambert = lamp_height / d;
    const w = @max(0, 1 - (d / radius) * (d / radius));
    const h = d / half_distance;
    return lambert * w * w / (1 + h * h);
}

/// Gouraud: light the corners of faces `size` wide, blend in between.
fn gouraud(x: f32, size: f32) f32 {
    const left = @min(2.5 - size, -2.5 + size * @floor((x + 2.5) / size));
    const t = (x - left) / size;
    return std.math.lerp(lightAt(left), lightAt(left + size), t);
}

fn phong(x: f32, _: f32) f32 {
    return lightAt(x);
}

/// One row of characters, darkest to brightest, sampled every 0.1.
fn picture(name: []const u8, f: fn (f32, f32) f32, size: f32) void {
    const ramp = " .:-=+*#%@";
    var row: [51]u8 = undefined;
    for (&row, 0..) |*c, i| {
        const v = f(-2.5 + 0.1 * @as(f32, @floatFromInt(i)), size);
        c.* = ramp[@min(ramp.len - 1, @as(usize, @intFromFloat(v * ramp.len)))];
    }
    std.debug.print("{s:<10}|{s}|\n", .{ name, &row });
}

pub fn main() void {
    std.debug.print("    x   1 face  5 faces  per pixel\n", .{});
    for (0..11) |i| {
        const x = -2.5 + 0.5 * @as(f32, @floatFromInt(i));
        std.debug.print("{d:>5.1}  {d:>6.3}  {d:>7.3}  {d:>9.3}\n", .{ x, gouraud(x, 5), gouraud(x, 1), phong(x, 0) });
    }
    picture("1 face", gouraud, 5);
    picture("5 faces", gouraud, 1);
    picture("per pixel", phong, 0);
}
