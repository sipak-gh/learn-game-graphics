//! Run-length encoding a recording. Held keys give the same input tick
//! after tick, so storing "how many ticks, then the input" once per run
//! instead of once per tick shrinks a recording a lot. The mouse is the
//! exception: it moves by a different amount almost every tick.
const std = @import("std");

const Input = struct { forward: f32 = 0, turn: f32 = 0, look: f32 = 0 };
const Run = struct { ticks: u32, input: Input };

/// Appends one tick's input, merging it into the last run if equal.
fn add(runs: *std.ArrayList(Run), gpa: std.mem.Allocator, input: Input) !void {
    if (runs.items.len > 0) {
        const last = &runs.items[runs.items.len - 1];
        if (std.meta.eql(last.input, input)) {
            last.ticks += 1;
            return;
        }
    }
    try runs.append(gpa, .{ .ticks = 1, .input = input });
}

/// The size of the text: one line per tick, or one per run.
fn textSize(runs: []const Run, per_tick: bool) !usize {
    var counter: std.Io.Writer.Discarding = .init(&.{});
    const w = &counter.writer;
    for (runs) |run| {
        const lines = if (per_tick) run.ticks else 1;
        for (0..lines) |_| {
            if (!per_tick) try w.print("{d} ", .{run.ticks});
            try w.print("{d} {d} {d}\n", .{ run.input.forward, run.input.turn, run.input.look });
        }
    }
    return @intCast(counter.fullCount());
}

fn report(name: []const u8, ticks: []const Input) !void {
    const gpa = std.heap.page_allocator;
    var runs: std.ArrayList(Run) = .empty;
    defer runs.deinit(gpa);
    for (ticks) |input| try add(&runs, gpa, input);
    const raw = try textSize(runs.items, true);
    const packed_size = try textSize(runs.items, false);
    std.debug.print("{s}: {d} ticks, {d} runs, {d} bytes -> {d} bytes ({d:.1}x)\n", .{
        name, ticks.len, runs.items.len, raw, packed_size, @as(f32, @floatFromInt(raw)) / @as(f32, @floatFromInt(packed_size)),
    });
    if (runs.items.len <= 5) for (runs.items) |run| {
        std.debug.print("    {d} {d} {d} {d}\n", .{ run.ticks, run.input.forward, run.input.turn, run.input.look });
    };
}

pub fn main() !void {
    var ticks: [300]Input = undefined;
    // Hold W for 2 s (120 ticks), turn right with the arrow key for 2/3 s,
    // then hold W for 2 s more.
    for (ticks[0..120]) |*t| t.* = .{ .forward = 1 };
    for (ticks[120..160]) |*t| t.* = .{ .turn = 1 };
    for (ticks[160..280]) |*t| t.* = .{ .forward = 1 };
    for (ticks[280..300]) |*t| t.* = .{};
    try report("keys", &ticks);

    // The same walk, turning with the mouse: a few pixels a tick, never
    // quite the same twice.
    var prng: std.Random.DefaultPrng = .init(1);
    const random = prng.random();
    for (ticks[120..160]) |*t| t.* = .{ .look = @floatFromInt(random.intRangeAtMost(i32, 3, 9)) };
    try report("mouse", &ticks);
}
