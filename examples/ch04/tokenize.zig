//! Splitting a script like "left:3 cw*2" into steps, names and counts.
const std = @import("std");

const Error = error{ BadCount, MissingCount };

const Step = struct {
    names: []const u8,
    count: u32,
    tap: bool,
};

fn parseStep(step: []const u8) Error!Step {
    // findAny returns the index of the first ':' or '*', or null.
    const end = std.mem.findAny(u8, step, ":*") orelse
        return .{ .names = step, .count = 1, .tap = false };
    const digits = step[end + 1 ..];
    if (digits.len == 0) return error.MissingCount;
    const count = std.fmt.parseInt(u32, digits, 10) catch return error.BadCount;
    return .{ .names = step[0..end], .count = count, .tap = step[end] == '*' };
}

pub fn main() void {
    // tokenizeScalar skips empty tokens, so repeated spaces do not matter.
    var steps = std.mem.tokenizeScalar(u8, "  left:3 cw*2   right+down _:30 left:x cw* ", ' ');
    while (steps.next()) |text| {
        if (parseStep(text)) |step| {
            std.debug.print("{s:<12} names={s} count={d} tap={}\n", .{ text, step.names, step.count, step.tap });
            var names = std.mem.splitScalar(u8, step.names, '+');
            while (names.next()) |name| std.debug.print("{s:<12}   button {s}\n", .{ "", name });
        } else |err| {
            std.debug.print("{s:<12} error.{t}\n", .{ text, err });
        }
    }
    // parseInt reports its own errors too.
    std.debug.print("{any} {any} {any}\n", .{
        std.fmt.parseInt(u32, "30", 10),
        std.fmt.parseInt(u32, "-1", 10),
        std.fmt.parseInt(u32, "99999999999", 10),
    });
}
