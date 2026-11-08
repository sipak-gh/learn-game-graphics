const std = @import("std");
const Vec2 = @import("math.zig").Vec2;
const Input = @import("input.zig").Input;
const Action = @import("input.zig").Action;
const View = @import("app.zig").View;

pub const usage =
    \\usage: delve [OPTIONS]
    \\
    \\  --frames N         stop after N frames (each frame advances exactly one tick)
    \\  --headless         render without opening a window
    \\  --out FILE         save the last frame as FILE (.png or .ppm)
    \\  --screenshot FILE  save a screenshot of the window as FILE (.png)
    \\  --scale N          window pixels per canvas pixel (default 2)
    \\  --pos X,Y          start at map position X,Y instead of the map's start
    \\  --yaw DEG          start facing DEG degrees (0 east, 90 south)
    \\  --pitch DEG        start looking DEG degrees up (negative: down), -89 to 89
    \\  --hold F,S,T       hold forward, strafe, and turn input (-1 to 1) all run long
    \\  --press ACTION     perform ACTION (for example next_view) on the first tick
    \\  --view NAME        start in view NAME: raycast, wireframe, cube, map_fixed, map_follow
    \\  -h, --help         show this help
    \\
;

pub const Options = struct {
    frames: ?u32 = null,
    headless: bool = false,
    out: ?[]const u8 = null,
    screenshot: ?[:0]const u8 = null,
    scale: u32 = 2,
    pos: ?Vec2 = null,
    yaw: ?f32 = null,
    pitch: ?f32 = null,
    /// Input held down for the whole run, on top of the keyboard.
    hold: Input = .{},
    /// Actions to perform once, on the first tick.
    press: std.EnumSet(Action) = .empty,
    view: ?View = null,
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
            } else if (eql(arg, "--pos")) {
                opts.pos = try parseFloats(2, try value(args, &i));
            } else if (eql(arg, "--hold")) {
                const f = try parseFloats(3, try value(args, &i));
                opts.hold = .{ .forward = f[0], .strafe = f[1], .turn = f[2] };
            } else if (eql(arg, "--press")) {
                const name = try value(args, &i);
                opts.press.insert(std.meta.stringToEnum(Action, name) orelse return error.InvalidValue);
            } else if (eql(arg, "--view")) {
                const name = try value(args, &i);
                opts.view = std.meta.stringToEnum(View, name) orelse return error.InvalidValue;
            } else if (eql(arg, "--yaw")) {
                opts.yaw = try parseFloat(try value(args, &i));
            } else if (eql(arg, "--pitch")) {
                const pitch = try parseFloat(try value(args, &i));
                // Straight up or down, "up" and "forward" are the same
                // direction and the camera has no well-defined right.
                if (!(@abs(pitch) < 90)) return error.InvalidValue;
                opts.pitch = pitch;
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

fn parseFloat(text: []const u8) Options.Error!f32 {
    return std.fmt.parseFloat(f32, text) catch error.InvalidValue;
}

/// Parses `n` comma-separated numbers, for example "3.5,1.5".
fn parseFloats(comptime n: usize, text: []const u8) Options.Error![n]f32 {
    var result: [n]f32 = undefined;
    var parts = std.mem.splitScalar(u8, text, ',');
    for (&result) |*x| x.* = try parseFloat(parts.next() orelse return error.InvalidValue);
    if (parts.next() != null) return error.InvalidValue;
    return result;
}

test "parse flags and values" {
    const opts = try Options.parse(&.{ "--headless", "--frames", "3", "--out", "a.png" });
    try std.testing.expect(opts.headless);
    try std.testing.expectEqual(3, opts.frames);
    try std.testing.expectEqualStrings("a.png", opts.out.?);
    try std.testing.expectEqual(2, opts.scale);

    const pose = try Options.parse(&.{ "--pos", "3.5,-1", "--yaw", "90", "--pitch", "-20" });
    try std.testing.expectEqual(Vec2{ 3.5, -1 }, pose.pos.?);
    try std.testing.expectEqual(90, pose.yaw.?);
    try std.testing.expectEqual(-20, pose.pitch.?);

    const held = try Options.parse(&.{ "--hold", "1,0,-0.5" });
    try std.testing.expectEqual(Input{ .forward = 1, .strafe = 0, .turn = -0.5 }, held.hold);

    const pressed = try Options.parse(&.{ "--press", "next_view" });
    try std.testing.expect(pressed.press.contains(.next_view));

    const view = try Options.parse(&.{ "--view", "cube" });
    try std.testing.expectEqual(.cube, view.view.?);
}

test "bad arguments" {
    try std.testing.expectError(error.UnknownFlag, Options.parse(&.{"--nope"}));
    try std.testing.expectError(error.MissingValue, Options.parse(&.{"--frames"}));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--scale", "0" }));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--frames", "x" }));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--pos", "3" }));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--pos", "1,2,3" }));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--press", "jump" }));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--pitch", "90" }));
    try std.testing.expectError(error.InvalidValue, Options.parse(&.{ "--view", "top" }));
}
