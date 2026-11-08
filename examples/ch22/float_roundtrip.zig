//! Does a number written as text read back as the same f32? With `{d}`,
//! Zig prints the shortest decimal that parses back to exactly the same
//! float. With a fixed number of decimals, it rounds, and the value read
//! back is a different float. A demo file must replay exactly, so delve
//! writes its numbers with `{d}`.
const std = @import("std");

fn mismatches(comptime fmt: []const u8, values: []const f32) !usize {
    var buffer: [64]u8 = undefined;
    var wrong: usize = 0;
    for (values) |x| {
        const text = try std.fmt.bufPrint(&buffer, fmt, .{x});
        const back = try std.fmt.parseFloat(f32, text);
        if (@as(u32, @bitCast(back)) != @as(u32, @bitCast(x))) wrong += 1;
    }
    return wrong;
}

fn longest(values: []const f32) !usize {
    var buffer: [64]u8 = undefined;
    var most: usize = 0;
    for (values) |x| most = @max(most, (try std.fmt.bufPrint(&buffer, "{d}", .{x})).len);
    return most;
}

pub fn main() !void {
    const n = 1_000_000;
    const gpa = std.heap.page_allocator;
    const small = try gpa.alloc(f32, n);
    defer gpa.free(small);
    const any = try gpa.alloc(f32, n);
    defer gpa.free(any);
    var prng: std.Random.DefaultPrng = .init(22);
    const random = prng.random();
    // Inputs as a demo has them: turns between -1 and 1.
    for (small) |*x| x.* = random.float(f32) * 2 - 1;
    // Any finite f32 at all, from its bits.
    for (any) |*x| {
        x.* = @bitCast(random.int(u32));
        while (!std.math.isFinite(x.*)) x.* = @bitCast(random.int(u32));
    }

    for ([_][]const f32{ small, any }, [_][]const u8{ "in -1..1", "any f32 " }) |values, name| {
        std.debug.print("{s}: {{d}} wrong {d:>7}   {{d:.3}} wrong {d:>7}   longest {{d}} {d} chars\n", .{
            name, try mismatches("{d}", values), try mismatches("{d:.3}", values), try longest(values),
        });
    }
    std.debug.print("1/3 as {{d}}: {d}   0.1 + 0.2 as {{d}}: {d}\n", .{ @as(f32, 1.0) / 3.0, @as(f32, 0.1) + @as(f32, 0.2) });
}
