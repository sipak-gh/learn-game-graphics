//! Delayed auto shift (DAS) and auto repeat rate (ARR), as in quadfall's
//! core/input.zig. Prints when a held direction actually moves the piece.
const std = @import("std");

const Input = packed struct { left: bool = false, right: bool = false };

const AutoRepeat = struct {
    const delay = 10;
    const rate = 2;

    dir: i32 = 0,
    held: u32 = 0,

    fn update(r: *AutoRepeat, now: Input, before: Input) i32 {
        if (now.left and !before.left) return r.start(-1);
        if (now.right and !before.right) return r.start(1);
        const still_held = (r.dir < 0 and now.left) or (r.dir > 0 and now.right);
        if (!still_held) {
            if (now.left) return r.start(-1);
            if (now.right) return r.start(1);
            r.dir = 0;
            return 0;
        }
        r.held += 1;
        if (r.held >= delay and (r.held - delay) % rate == 0) return r.dir;
        return 0;
    }

    fn start(r: *AutoRepeat, dir: i32) i32 {
        r.* = .{ .dir = dir };
        return dir;
    }
};

/// `keys` has one character per tick: L, R, B (both) or '.'.
/// Prints '<' or '>' on ticks that move, '.' on ticks that do not.
fn timeline(label: []const u8, keys: []const u8) void {
    var r: AutoRepeat = .{};
    var before: Input = .{};
    std.debug.print("{s}\n  keys  {s}\n  moves ", .{ label, keys });
    for (keys) |k| {
        const now: Input = .{ .left = k == 'L' or k == 'B', .right = k == 'R' or k == 'B' };
        const c: u8 = switch (r.update(now, before)) {
            -1 => '<',
            1 => '>',
            else => '.',
        };
        std.debug.print("{c}", .{c});
        before = now;
    }
    std.debug.print("\n", .{});
}

pub fn main() void {
    timeline("hold Right for 20 ticks:", "RRRRRRRRRRRRRRRRRRRR");
    timeline("tap Right four times:", "R.R.R.R.");
    timeline("hold Left, press Right too, let go of Right:", "LLLLLLBBBBBBBBBBLLLLLLLLLLLLL");
}
