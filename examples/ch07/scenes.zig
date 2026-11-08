//! Scenes as a state machine: one enum, one switch, driven by one input
//! per tick. Prints the scene after every tick.
const std = @import("std");

const Scene = enum { title, play, pause, over };

const Input = packed struct {
    start: bool = false,
    pause: bool = false,
    /// Stands in for "the stack reached the top".
    lose: bool = false,
};

const App = struct {
    scene: Scene = .title,
    before: Input = .{},

    fn tick(app: *App, input: Input) void {
        defer app.before = input;
        // A button counts once, on the tick it goes down.
        const start = input.start and !app.before.start;
        const pause = input.pause and !app.before.pause;
        app.scene = switch (app.scene) {
            .title, .over => if (start) .play else app.scene,
            .play => if (pause) .pause else if (input.lose) .over else .play,
            .pause => if (pause or start) .play else .pause,
        };
    }
};

pub fn main() void {
    const ticks = [_]Input{
        .{},                .{ .start = true }, .{ .start = true }, .{},
        .{ .pause = true }, .{ .pause = true }, .{ .pause = true }, .{},
        .{ .pause = true }, .{ .lose = true },  .{ .start = true },
    };
    var app: App = .{};
    for (ticks, 0..) |input, i| {
        const was = app.scene;
        app.tick(input);
        const mark = if (app.scene != was) "*" else " ";
        std.debug.print("tick {d:>2}  start={d} pause={d} lose={d}  {s} {t}\n", .{
            i, @intFromBool(input.start), @intFromBool(input.pause), @intFromBool(input.lose), mark, app.scene,
        });
    }
}
