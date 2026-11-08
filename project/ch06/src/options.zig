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
    help: bool = false,
};

pub const Error = error{ UnknownOption, MissingValue, InvalidValue };

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
        } else if (std.mem.eql(u8, arg, "--seed")) {
            const value = try nextValue(args, &i);
            opts.seed = std.fmt.parseInt(u64, value, 10) catch return error.InvalidValue;
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
