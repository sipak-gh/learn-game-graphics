//! The program as a whole: which scene is showing, and how input moves
//! between them. Still no raylib: scenes are rules too, and scripts can
//! drive the menus the same way they drive the game.
const std = @import("std");
const Game = @import("game.zig").Game;
const Input = @import("input.zig").Input;

pub const Scene = enum { title, play, pause, over };

pub const App = struct {
    scene: Scene = .title,
    game: Game,
    /// Seed for the next game. Each new game takes the next seed.
    seed: u64,
    high_score: u32,
    /// True once the last game beat the old high score.
    new_high_score: bool = false,
    /// Ticks since the program started, for animations.
    ticks: u32 = 0,
    before: Input = .none,

    pub fn init(seed: u64, high_score: u32) App {
        return .{ .game = .init(.empty, seed), .seed = seed, .high_score = high_score };
    }

    pub fn tick(app: *App, input: Input) void {
        defer app.before = input;
        app.ticks +%= 1;
        app.game.events = .{};
        const start = input.start and !app.before.start;
        const pause = input.pause and !app.before.pause;
        switch (app.scene) {
            .title, .over => if (start) app.newGame(),
            .play => if (pause) {
                app.scene = .pause;
            } else {
                app.game.tick(input);
                if (app.game.phase == .over) app.gameOver();
            },
            .pause => if (pause or start) {
                app.scene = .play;
            },
        }
    }

    fn newGame(app: *App) void {
        app.game = .init(.empty, app.seed);
        app.seed +%= 1;
        app.new_high_score = false;
        app.scene = .play;
    }

    fn gameOver(app: *App) void {
        app.scene = .over;
        if (app.game.score > app.high_score) {
            app.high_score = app.game.score;
            app.new_high_score = true;
        }
    }
};

const testing = std.testing;

/// Runs `n` ticks of the same input.
fn run(app: *App, n: usize, input: Input) void {
    for (0..n) |_| app.tick(input);
}

test "start, pause and resume" {
    var app: App = .init(1, 0);
    run(&app, 10, .none);
    try testing.expectEqual(.title, app.scene);
    app.tick(.{ .start = true });
    try testing.expectEqual(.play, app.scene);
    run(&app, 30, .none);
    const row = app.game.piece.pos.row;

    // Holding pause pauses once; the game stands still meanwhile.
    run(&app, 100, .{ .pause = true });
    try testing.expectEqual(.pause, app.scene);
    try testing.expectEqual(row, app.game.piece.pos.row);
    app.tick(.none);
    app.tick(.{ .pause = true });
    try testing.expectEqual(.play, app.scene);
}

test "a game over records the high score" {
    var app: App = .init(1, 100);
    app.tick(.{ .start = true });
    // Hard drop every other tick until the stack reaches the top.
    var ticks: usize = 0;
    while (app.scene == .play) : (ticks += 1) {
        app.tick(.{ .drop = ticks % 2 == 0 });
        try testing.expect(ticks < 10_000);
    }
    try testing.expectEqual(.over, app.scene);
    try testing.expect(app.game.score > 100);
    try testing.expectEqual(app.game.score, app.high_score);
    try testing.expect(app.new_high_score);

    // Start again: an empty board and a fresh high-score flag.
    app.tick(.{ .start = true });
    try testing.expectEqual(.play, app.scene);
    try testing.expect(!app.new_high_score);
    try testing.expectEqual(0, app.game.score);
}
