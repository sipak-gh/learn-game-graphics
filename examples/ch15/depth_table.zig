//! The depth that the projection matrix leaves after the divide by w:
//! z_ndc = (A z + B) / (-z) with A = f/(n - f) and B = n f/(n - f), which is
//! f/(f - n) (1 - n/d) at distance d. It is 0 at the near plane, 1 at the
//! far plane, and a 1/d curve in between.
const std = @import("std");

const n: f32 = 0.05;
const f: f32 = 64;

/// Depth after the divide, straight from the matrix's third and fourth rows.
fn depth(d: f32) f32 {
    const z = -d; // in front of the camera, z is negative
    const a = f / (n - f);
    const b = n * f / (n - f);
    return (a * z + b) / -z;
}

/// The inverse: the distance that has depth `z` (in f64, so that the
/// rounding we measure is the depth's, not this function's).
fn distance(z: f32) f64 {
    const n64: f64 = n;
    const f64_: f64 = f;
    return n64 * f64_ / (f64_ - z * (f64_ - n64));
}

pub fn main() void {
    std.debug.print("A = {d:.6}  B = {d:.6}\n\n", .{ f / (n - f), n * f / (n - f) });
    std.debug.print("     d    depth      formula     back to d  one f32 step in depth = this far\n", .{});
    for ([_]f32{ 0.05, 0.075, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 32, 64 }) |d| {
        const z = depth(d);
        const formula = f / (f - n) * (1 - n / d);
        // The smallest step the depth can take in f32 at this distance, and
        // the distance that step stands for.
        const next = std.math.nextAfter(f32, z, 2);
        std.debug.print("{d:6.3}  {d:9.6}  {d:9.6}  {d:9.4}  {e:.2}\n", .{ d, z, formula, distance(z), distance(next) - distance(z) });
    }
    std.debug.print("\nhalf of the depth range is used by d = {d:.4}\n", .{distance(0.5)});
}
