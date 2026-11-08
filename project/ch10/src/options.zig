const std = @import("std");

pub const usage =
    \\usage: delve [OPTIONS]
    \\
    \\  --frames N         stop after N frames (each frame advances exactly one tick)
    \\  --headless         render without opening a window
    \\  --out FILE         save the last frame as FILE (.png or .ppm)
    \\  --screenshot FILE  save a screenshot of the window as FILE (.png)
    \\  --scale N          window pixels per canvas pixel (default 2)
    \\  -h, --help         show this help
    \\
;

pub const Options = struct {
    frames: ?u32 = null,
    headless: bool = false,
    out: ?[]const u8 = null,
    screenshot: ?[:0]const u8 = null,
    scale: u32 = 2,
    help: bool = false,

    pub const Error = error{ UnknownFlag, MissingValue, InvalidValue };

    /// Parses the arguments after the program name.
    pub fn parse(args: []const [:0]const u8) Error!Options {
        var opts: Options = .{};
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (eql(arg, "--headless")) {
                opts.headless = true;
            } else if (eql(arg, "-h") or eql(arg, "--help")) {
                opts.help = true;
            } else if (eql(arg, "--frames")) {
                opts.frames = try parseInt(try value(args, &i));
            } else if (eql(arg, "--out")) {
                opts.out = try value(args, &i);
            } else if (eql(arg, "--screenshot")) {
                opts.screenshot = try value(args, &i);
            } else if (eql(arg, "--scale")) {
                opts.scale = try parseInt(try value(args, &i));
                if (opts.scale == 0) return error.InvalidValue;
            } else {
                return error.UnknownFlag;
            }
        }
        return opts;
    }
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Returns the argument after flag `args[i.*]` and moves `i` past it.
fn value(args: []const [:0]const u8, i: *usize) Options.Error![:0]const u8 {
    i.* += 1;
    if (i.* >= args.len) return error.MissingValue;
    return args[i.*];
}

fn parseInt(text: []const u8) Options.Error!u32 {
    return std.fmt.parseInt(u32, text, 10) catch error.InvalidValue;
}

test "parse flags and values" {
    const opts = try Options.parse(&.{ "--headless", "--frames", "3", "--out", "a.png" });
    try std.testing.expect(opts.headless);
    try std.testing.expectEqual(3, opts.frames);
    try std.testing.expectEqualStrings("a.png", opts.out.?);
    try std.testing.expectEqual(2, opts.scale);
}

test "bad arguments" {
    try std.testing.expectError(error.UnknownFlag, Options.parse(&.{"--nope"}));
    try std.testing.expectError(error.MissingValue, Options.parse(&.{"--frames"}));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--scale", "0" }));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--frames", "x" }));
}
