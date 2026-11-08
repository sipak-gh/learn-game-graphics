//! Scripted input, for demos, screenshots and tests. A script is a list of
//! steps separated by spaces. Each step names the buttons to hold (joined
//! with `+`, or `_` for none) and how long:
//!
//!   left        hold Left for one tick
//!   left:20     hold Left for 20 ticks
//!   left*3      tap Left three times (one tick down, one tick up, each)
//!   right+cw:2  hold Right and Rotate-clockwise for two ticks
//!   _:30        hold nothing for 30 ticks
//!
//! Button names are the field names of `Input`.
const std = @import("std");
const Input = @import("input.zig").Input;

pub const Error = error{ UnknownButton, BadCount };

pub const Script = struct {
    steps: std.mem.TokenIterator(u8, .scalar),
    /// The step being played and how many of its ticks are left.
    input: Input = .none,
    left: u32 = 0,
    /// Taps alternate between `input` and nothing.
    tapping: bool = false,

    pub fn init(text: []const u8) Script {
        return .{ .steps = std.mem.tokenizeScalar(u8, text, ' ') };
    }

    /// Checks a whole script up front, so that mistakes are reported
    /// before the game starts.
    pub fn validate(text: []const u8) Error!void {
        var s: Script = .init(text);
        while (try s.next()) |_| {}
    }

    /// The input for the next tick, or null at the end of the script.
    pub fn next(s: *Script) Error!?Input {
        while (s.left == 0) {
            const step = s.steps.next() orelse return null;
            try s.begin(step);
        }
        s.left -= 1;
        // While tapping, odd ticks (counting down to 0) release the buttons.
        if (s.tapping and s.left % 2 == 0) return .none;
        return s.input;
    }

    fn begin(s: *Script, step: []const u8) Error!void {
        const end = std.mem.findAny(u8, step, ":*") orelse step.len;
        s.input = try parseButtons(step[0..end]);
        s.tapping = end < step.len and step[end] == '*';
        const count: u32 = if (end == step.len)
            1
        else
            std.fmt.parseInt(u32, step[end + 1 ..], 10) catch return error.BadCount;
        s.left = if (s.tapping) 2 * count else count;
    }
};

fn parseButtons(names: []const u8) Error!Input {
    var input: Input = .none;
    if (std.mem.eql(u8, names, "_")) return input;
    var it = std.mem.splitScalar(u8, names, '+');
    next_name: while (it.next()) |name| {
        inline for (@typeInfo(Input).@"struct".field_names) |field| {
            if (std.mem.eql(u8, name, field)) {
                @field(input, field) = true;
                continue :next_name;
            }
        }
        return error.UnknownButton;
    }
    return input;
}

/// The other direction: writes inputs, one per tick, as a script. Runs of
/// the same input become one step, so a long game stays short.
pub const Recorder = struct {
    out: *std.Io.Writer,
    input: Input = .none,
    /// Ticks of `input` not yet written.
    count: u32 = 0,
    started: bool = false,

    pub fn add(r: *Recorder, input: Input) std.Io.Writer.Error!void {
        if (r.count > 0 and input == r.input) {
            r.count += 1;
            return;
        }
        try r.flush();
        r.input = input;
        r.count = 1;
    }

    /// Writes the last step. Call once, after the last `add`.
    pub fn flush(r: *Recorder) std.Io.Writer.Error!void {
        if (r.count == 0) return;
        if (r.started) try r.out.writeByte(' ');
        r.started = true;
        try writeButtons(r.out, r.input);
        if (r.count > 1) try r.out.print(":{d}", .{r.count});
        r.count = 0;
    }
};

fn writeButtons(out: *std.Io.Writer, input: Input) std.Io.Writer.Error!void {
    if (input == Input.none) return out.writeByte('_');
    var first = true;
    inline for (@typeInfo(Input).@"struct".field_names) |field| {
        if (@field(input, field)) {
            if (!first) try out.writeByte('+');
            try out.writeAll(field);
            first = false;
        }
    }
}

fn expectTicks(text: []const u8, expected: []const Input) !void {
    var s: Script = .init(text);
    for (expected) |want| try std.testing.expectEqual(want, (try s.next()).?);
    try std.testing.expectEqual(null, try s.next());
}

test "holds, taps, waits and combinations" {
    const l: Input = .{ .left = true };
    try expectTicks("left", &.{l});
    try expectTicks("left:3", &.{ l, l, l });
    try expectTicks("left*2", &.{ l, .none, l, .none });
    try expectTicks("_:2 right+cw", &.{ .none, .none, .{ .right = true, .cw = true } });
    try expectTicks("  ", &.{});
}

test "mistakes are reported" {
    try std.testing.expectError(error.UnknownButton, Script.validate("left jump"));
    try std.testing.expectError(error.BadCount, Script.validate("left:x"));
    try std.testing.expectError(error.BadCount, Script.validate("left*"));
}

test "recording merges repeats and plays back the same ticks" {
    const ticks = [_]Input{ .none, .none, .none, .{ .left = true }, .{ .left = true, .cw = true }, .{ .drop = true } };
    var buf: [100]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    var r: Recorder = .{ .out = &out };
    for (ticks) |input| try r.add(input);
    try r.flush();
    try std.testing.expectEqualStrings("_:3 left left+cw drop", out.buffered());
    try expectTicks(out.buffered(), &ticks);
}
