const std = @import("std");
const rl = @import("rl");
const core = @import("core");
const draw = @import("draw.zig");
const options = @import("options.zig");

/// A board to look at until pieces can move (Chapter 4).
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

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(draw.screen_width, draw.screen_height, "quadfall");
    defer rl.CloseWindow();
    // A scripted run (--frames) goes as fast as it can and pretends that
    // every frame took exactly 1/60 s, so it gives the same result every time.
    if (opts.frames == null) rl.SetTargetFPS(60);

    // A showcase: each piece turns clockwise twice a second, then the next
    // kind spawns after a full turn.
    var piece: core.Piece = .spawn(.i);
    var frame: u32 = 0;
    while (!rl.WindowShouldClose()) : (frame += 1) {
        if (opts.frames) |n| if (frame == n) break;
        if (frame > 0 and frame % 30 == 0) {
            piece.rot = piece.rot.cw();
            if (piece.rot == .spawn) {
                const next: core.Kind = @fromBackingInt((@backingInt(piece.kind) + 1) % 7);
                piece = .spawn(next);
            }
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(draw.background);
        draw.drawBoard(&demo_board);
        draw.drawPiece(piece);
        rl.DrawText("QUADFALL", 40, 40, 30, rl.RAYWHITE);
        var buf: [32]u8 = undefined;
        const label = std.mem.printSentinel(&buf, "{t} {t}", .{ piece.kind, piece.rot }, 0) catch unreachable;
        rl.DrawText(label, 40, 90, 20, rl.LIGHTGRAY);
    }

    if (opts.screenshot) |path| {
        rl.TakeScreenshot(path);
        std.log.info("saved {s}", .{path});
    }
    return 0;
}
