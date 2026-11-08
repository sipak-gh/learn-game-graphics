//! Command-line options. Plain Zig, no raylib: easy to read and to test.
const std = @import("std");

pub const usage =
    \\usage: quadfall [OPTIONS]
    \\
    \\options:
    \\  --frames N         run N frames with a fixed 1/60 s frame time, then exit
    \\  --screenshot PATH  save the last frame as a PNG before exiting
    \\  --script STEPS     play scripted input instead of the keyboard
    \\  --seed N           deal pieces from seed N instead of a random seed
    \\  --save PATH        keep the high score in PATH (default: quadfall-save.zon)
    \\  --mute             play no sound
    \\  --record PATH      save the seed and every input to PATH on exit
    \\  --replay PATH      play a recorded session from PATH
    \\  --help             show this help
    \\
;

pub const Options = struct {
    /// Stop after this many frames. Used for scripted, headless runs.
    frames: ?u32 = null,
    /// Save a PNG of the last frame here before exiting.
    screenshot: ?[:0]const u8 = null,
    /// Scripted input, such as "left*3 cw _:30" (see core/script.zig).
    script: ?[]const u8 = null,
    /// Seed for the piece randomizer. The same seed deals the same pieces.
    seed: ?u64 = null,
    /// Where the high score is kept. Null means the default file.
    save: ?[]const u8 = null,
    mute: bool = false,
    /// Record the session to this file.
    record: ?[]const u8 = null,
    /// Play the session recorded in this file.
    replay: ?[]const u8 = null,
    help: bool = false,
};

pub const Error = error{ UnknownOption, MissingValue, InvalidValue, Conflict };

/// Parses the arguments after the program name. On error, `bad` is set to
/// the argument that caused it.
pub fn parse(args: []const [:0]const u8, bad: *[]const u8) Error!Options {
    var opts: Options = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        bad.* = arg;
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = try nextValue(args, &i);
            opts.frames = std.fmt.parseInt(u32, value, 10) catch return error.InvalidValue;
        } else if (std.mem.eql(u8, arg, "--screenshot")) {
            opts.screenshot = try nextValue(args, &i);
        } else if (std.mem.eql(u8, arg, "--script")) {
            opts.script = try nextValue(args, &i);
            if (opts.replay != null) return error.Conflict;
        } else if (std.mem.eql(u8, arg, "--seed")) {
            const value = try nextValue(args, &i);
            opts.seed = std.fmt.parseInt(u64, value, 10) catch return error.InvalidValue;
            if (opts.replay != null) return error.Conflict;
        } else if (std.mem.eql(u8, arg, "--save")) {
            opts.save = try nextValue(args, &i);
        } else if (std.mem.eql(u8, arg, "--mute")) {
            opts.mute = true;
        } else if (std.mem.eql(u8, arg, "--record")) {
            opts.record = try nextValue(args, &i);
        } else if (std.mem.eql(u8, arg, "--replay")) {
            opts.replay = try nextValue(args, &i);
            // A replay brings its own input and seed.
            if (opts.script != null or opts.seed != null) return error.Conflict;
        } else if (std.mem.eql(u8, arg, "--help")) {
            opts.help = true;
        } else {
            return error.UnknownOption;
        }
    }
    return opts;
}

fn nextValue(args: []const [:0]const u8, i: *usize) Error![:0]const u8 {
    i.* += 1;
    if (i.* == args.len) return error.MissingValue;
    return args[i.*];
}

fn expectParse(args: []const [:0]const u8, expected: Options) !void {
    var bad: []const u8 = "";
    try std.testing.expectEqualDeep(expected, try parse(args, &bad));
}

fn expectFail(args: []const [:0]const u8, err: Error, culprit: []const u8) !void {
    var bad: []const u8 = "";
    try std.testing.expectError(err, parse(args, &bad));
    try std.testing.expectEqualStrings(culprit, bad);
}

test "options" {
    try expectParse(&.{}, .{});
    try expectParse(&.{ "--frames", "60", "--seed", "7", "--mute" }, .{ .frames = 60, .seed = 7, .mute = true });
    try expectParse(&.{ "--replay", "a.zon", "--screenshot", "a.png" }, .{ .replay = "a.zon", .screenshot = "a.png" });
}

test "bad options name the culprit" {
    try expectFail(&.{"--fast"}, error.UnknownOption, "--fast");
    try expectFail(&.{ "--mute", "--frames" }, error.MissingValue, "--frames");
    try expectFail(&.{ "--frames", "-1" }, error.InvalidValue, "--frames");
    try expectFail(&.{ "--seed", "1", "--replay", "a.zon" }, error.Conflict, "--replay");
}
