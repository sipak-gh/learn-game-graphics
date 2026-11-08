const std = @import("std");
const rl = @import("rl");
const core = @import("core");
const draw = @import("draw.zig");
const options = @import("options.zig");

/// A stack to move pieces around until they can fall and lock (Chapter 5).
const demo_board: core.Board = .parse(
    \\.........I
    \\.T.......I
    \\TTT....OOI
    \\JSS..LLOOI
    \\JJSSZZL###
    \\#.#ZZ#L###
);

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var bad: []const u8 = "";
    const opts = options.parse(args[1..], &bad) catch |err| {
        std.log.err("{t}: {s}", .{ err, bad });
        std.debug.print("{s}", .{options.usage});
        return 2;
    };
    if (opts.help) {
        std.debug.print("{s}", .{options.usage});
        return 0;
    }
    var script: ?core.Script = null;
    if (opts.script) |text| {
        core.Script.validate(text) catch |err| {
            std.log.err("--script: {t}", .{err});
            return 2;
        };
        script = .init(text);
    }

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(draw.screen_width, draw.screen_height, "quadfall");
    defer rl.CloseWindow();
    // A scripted run (--frames) goes as fast as it can and pretends that
    // every frame took exactly 1/60 s, so it gives the same result every time.
    if (opts.frames == null) rl.SetTargetFPS(60);

    var game: core.Game = .init(demo_board, .t);
    var frame: u32 = 0;
    while (!rl.WindowShouldClose()) : (frame += 1) {
        if (opts.frames) |n| if (frame == n) break;
        // One game tick per frame, at 60 frames per second (until Chapter 5).
        // The script was validated above, so next() cannot fail here.
        const input: core.Input = if (script) |*s| (s.next() catch unreachable) orelse .none else readKeyboard();
        game.tick(input);

        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(draw.background);
        draw.drawBoard(&game.board);
        draw.drawPiece(game.piece);
        rl.DrawText("QUADFALL", 40, 40, 30, rl.RAYWHITE);
    }

    if (opts.screenshot) |path| {
        rl.TakeScreenshot(path);
        std.log.info("saved {s}", .{path});
    }
    return 0;
}

/// The buttons held right now. Keys are a platform detail: the game only
/// ever sees `core.Input`.
fn readKeyboard() core.Input {
    return .{
        .left = rl.IsKeyDown(rl.KEY_LEFT),
        .right = rl.IsKeyDown(rl.KEY_RIGHT),
        .down = rl.IsKeyDown(rl.KEY_DOWN),
        .cw = rl.IsKeyDown(rl.KEY_UP) or rl.IsKeyDown(rl.KEY_X),
        .ccw = rl.IsKeyDown(rl.KEY_Z) or rl.IsKeyDown(rl.KEY_LEFT_CONTROL),
    };
}
