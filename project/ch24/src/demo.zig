//! Recording and replaying input. The simulation depends only on the
//! input of each tick and the fixed tick length, so a list of inputs is
//! all it takes to play a game again exactly as it went.
//!
//! A demo is text, one line per run of ticks with the same input:
//!
//!     # delve demo
//!     map labyrinth
//!     start 1.5 1.5 0 0
//!     90 1 0 0 0 0 0
//!     1 0 0 0 0 0 0 toggle_torch
//!
//! `map` names the map and `start` gives x, y, yaw and pitch (radians).
//! Each run is: how many ticks, then forward, strafe, turn, tilt, look and
//! look_y, then the actions pressed on each of those ticks.
const std = @import("std");
const Vec2 = @import("math.zig").Vec2;
const Input = @import("input.zig").Input;
const Action = @import("input.zig").Action;

/// Demos built into the program, by name.
pub const builtin: std.StaticStringMap([]const u8) = .initComptime(.{
    .{ "tour", @embedFile("demos/tour.txt") },
});

pub const Start = struct { pos: Vec2, yaw: f32, pitch: f32 };

/// `ticks` ticks in a row with the same input.
pub const Run = struct { ticks: u32, input: Input };

pub const Demo = struct {
    /// The map's name, pointing into the text the demo was parsed from.
    map: ?[]const u8 = null,
    start: ?Start = null,
    runs: []Run,

    pub const Error = error{ OutOfMemory, BadNumber, BadLine, UnknownAction };

    /// Parses a demo. On error, `line` is the line (from 1) at fault.
    pub fn parse(gpa: std.mem.Allocator, text: []const u8, line: *usize) Error!Demo {
        var demo: Demo = .{ .runs = &.{} };
        var runs: std.ArrayList(Run) = .empty;
        errdefer runs.deinit(gpa);
        var lines = std.mem.splitScalar(u8, text, '\n');
        line.* = 0;
        while (lines.next()) |raw| {
            line.* += 1;
            const content = std.mem.trim(u8, raw[0 .. std.mem.indexOfScalar(u8, raw, '#') orelse raw.len], " \t\r");
            if (content.len == 0) continue;
            var words = std.mem.tokenizeAny(u8, content, " \t");
            const first = words.next().?;
            if (std.mem.eql(u8, first, "map")) {
                demo.map = words.next() orelse return error.BadLine;
            } else if (std.mem.eql(u8, first, "start")) {
                const f = try floats(4, &words);
                demo.start = .{ .pos = .{ f[0], f[1] }, .yaw = f[2], .pitch = f[3] };
            } else {
                const ticks = std.fmt.parseInt(u32, first, 10) catch return error.BadNumber;
                const f = try floats(6, &words);
                var input: Input = .{ .forward = f[0], .strafe = f[1], .turn = f[2], .tilt = f[3], .look = f[4], .look_y = f[5] };
                while (words.next()) |name| {
                    input.pressed.insert(std.meta.stringToEnum(Action, name) orelse return error.UnknownAction);
                }
                try runs.append(gpa, .{ .ticks = ticks, .input = input });
            }
        }
        demo.runs = try runs.toOwnedSlice(gpa);
        return demo;
    }

    pub fn deinit(demo: *Demo, gpa: std.mem.Allocator) void {
        gpa.free(demo.runs);
    }

    /// How many ticks the demo lasts.
    pub fn tickCount(demo: Demo) u32 {
        var n: u32 = 0;
        for (demo.runs) |run| n += run.ticks;
        return n;
    }

    /// Writes the demo in the format `parse` reads.
    pub fn write(demo: Demo, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll("# delve demo\n");
        if (demo.map) |name| try w.print("map {s}\n", .{name});
        if (demo.start) |s| try w.print("start {d} {d} {d} {d}\n", .{ s.pos[0], s.pos[1], s.yaw, s.pitch });
        for (demo.runs) |run| {
            const i = run.input;
            // {d} prints the shortest text that reads back as the same
            // f32, so a replay sees exactly the recorded numbers.
            try w.print("{d} {d} {d} {d} {d} {d} {d}", .{ run.ticks, i.forward, i.strafe, i.turn, i.tilt, i.look, i.look_y });
            var actions = i.pressed.iterator();
            while (actions.next()) |action| try w.print(" {t}", .{action});
            try w.writeByte('\n');
        }
    }
};

fn floats(comptime n: usize, words: *std.mem.TokenIterator(u8, .any)) Demo.Error![n]f32 {
    var result: [n]f32 = undefined;
    for (&result) |*x| {
        const word = words.next() orelse return error.BadLine;
        x.* = std.fmt.parseFloat(f32, word) catch return error.BadNumber;
    }
    return result;
}

/// Hands out a demo's input one tick at a time.
pub const Playback = struct {
    runs: []const Run,
    run: usize = 0,
    /// Ticks already played of `runs[run]`.
    done: u32 = 0,

    /// The next tick's input, or null once the demo is over.
    pub fn next(p: *Playback) ?Input {
        while (p.run < p.runs.len and p.done == p.runs[p.run].ticks) {
            p.run += 1;
            p.done = 0;
        }
        if (p.run == p.runs.len) return null;
        p.done += 1;
        return p.runs[p.run].input;
    }
};

/// Collects the input of every tick, merging repeats into runs.
pub const Recorder = struct {
    runs: std.ArrayList(Run) = .empty,

    pub fn deinit(rec: *Recorder, gpa: std.mem.Allocator) void {
        rec.runs.deinit(gpa);
    }

    pub fn add(rec: *Recorder, gpa: std.mem.Allocator, input: Input) !void {
        if (rec.runs.items.len > 0) {
            const last = &rec.runs.items[rec.runs.items.len - 1];
            if (std.meta.eql(last.input, input)) {
                last.ticks += 1;
                return;
            }
        }
        try rec.runs.append(gpa, .{ .ticks = 1, .input = input });
    }
};

test "a recording reads back as the same input, tick by tick" {
    const gpa = std.testing.allocator;
    var rec: Recorder = .{};
    defer rec.deinit(gpa);
    var pressed: Input = .{ .look = 0.1 + 0.2, .look_y = -1.0 / 3.0 };
    pressed.pressed.insert(.toggle_torch);
    const ticks = [_]Input{ .{ .forward = 1 }, .{ .forward = 1 }, .{ .forward = 1 }, pressed, .{ .turn = -0.25, .tilt = 1 } };
    for (ticks) |input| try rec.add(gpa, input);
    // Three runs: the first three ticks are the same.
    try std.testing.expectEqual(3, rec.runs.items.len);

    const recorded: Demo = .{ .map = "labyrinth", .start = .{ .pos = .{ 1.5, 2.25 }, .yaw = 0.1, .pitch = -0.2 }, .runs = rec.runs.items };
    var buffer: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    try recorded.write(&w);
    try std.testing.expectEqualStrings(
        \\# delve demo
        \\map labyrinth
        \\start 1.5 2.25 0.1 -0.2
        \\3 1 0 0 0 0 0
        \\1 0 0 0 0 0.3 -0.33333334 toggle_torch
        \\1 0 0 -0.25 1 0 0
        \\
    , w.buffered());

    var line: usize = undefined;
    var demo = try Demo.parse(gpa, w.buffered(), &line);
    defer demo.deinit(gpa);
    try std.testing.expectEqualStrings("labyrinth", demo.map.?);
    try std.testing.expectEqual(recorded.start.?, demo.start.?);
    try std.testing.expectEqual(5, demo.tickCount());
    var playback: Playback = .{ .runs = demo.runs };
    for (ticks) |input| try std.testing.expectEqual(input, playback.next().?);
    try std.testing.expectEqual(null, playback.next());
}

test "demo errors say which line they are on" {
    const gpa = std.testing.allocator;
    var line: usize = undefined;
    try std.testing.expectError(error.BadNumber, Demo.parse(gpa, "# x\n3 1 0 0 0 0 0\nx 1 0 0 0 0 0\n", &line));
    try std.testing.expectEqual(3, line);
    try std.testing.expectError(error.BadLine, Demo.parse(gpa, "start 1 2\n", &line));
    try std.testing.expectEqual(1, line);
    try std.testing.expectError(error.UnknownAction, Demo.parse(gpa, "1 0 0 0 0 0 0 jump\n", &line));
}

test "the tour ends in the big room, where the script that made it ended" {
    const gpa = std.testing.allocator;
    const Map = @import("map.zig").Map;
    const Player = @import("player.zig").Player;
    var line: usize = undefined;
    var demo = try Demo.parse(gpa, builtin.get("tour").?, &line);
    defer demo.deinit(gpa);
    var map = try Map.parse(gpa, @import("map.zig").builtin.get(demo.map.?).?);
    defer map.deinit(gpa);
    const start = demo.start.?;
    var player: Player = .{ .pos = start.pos, .yaw = start.yaw, .pitch = start.pitch };
    var playback: Playback = .{ .runs = demo.runs };
    while (playback.next()) |input| player.update(input, map, 1.0 / 60.0);
    // The script simulated the same rules in 64-bit floats.
    try std.testing.expectEqual(1983, demo.tickCount());
    try std.testing.expectApproxEqAbs(40.4547, player.pos[0], 1e-3);
    try std.testing.expectApproxEqAbs(9.5017, player.pos[1], 1e-3);
}
