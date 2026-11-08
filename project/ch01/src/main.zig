const std = @import("std");
const rl = @import("rl");
const options = @import("options.zig");

const screen_width = 800;
const screen_height = 720;

// The playfield: 10 columns by 20 rows of 32-pixel cells.
const cell_size = 32;
const board_x = 240;
const board_y = 40;
const board_width = 10 * cell_size;
const board_height = 20 * cell_size;

const background: rl.Color = .{ .r = 24, .g = 24, .b = 32, .a = 255 };

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
    rl.InitWindow(screen_width, screen_height, "quadfall");
    defer rl.CloseWindow();
    // A scripted run (--frames) goes as fast as it can and pretends that
    // every frame took exactly 1/60 s, so it gives the same result every time.
    if (opts.frames == null) rl.SetTargetFPS(60);

    var smooth_y: f32 = 0; // pixels below the board top
    var step_row: i32 = 0; // whole rows below the board top
    var step_timer: f32 = 0;
    var frame: u32 = 0;

    while (!rl.WindowShouldClose()) : (frame += 1) {
        if (opts.frames) |n| if (frame == n) break;
        const dt: f32 = if (opts.frames != null) 1.0 / 60.0 else rl.GetFrameTime();

        // Smooth motion: speed times elapsed time, 96 pixels per second.
        smooth_y += 96 * dt;
        if (smooth_y >= board_height) smooth_y -= board_height;

        // Stepped motion: one whole row every 1/3 s, like a falling piece.
        step_timer += dt;
        while (step_timer >= 1.0 / 3.0) {
            step_timer -= 1.0 / 3.0;
            step_row = @mod(step_row + 1, 20);
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(background);

        rl.DrawRectangle(board_x, board_y, board_width, board_height, rl.BLACK);
        rl.DrawRectangleLines(board_x - 1, board_y - 1, board_width + 2, board_height + 2, rl.GRAY);
        rl.DrawRectangle(board_x + 3 * cell_size, board_y + @as(i32, @intFromFloat(smooth_y)), cell_size, cell_size, rl.SKYBLUE);
        rl.DrawRectangle(board_x + 6 * cell_size, board_y + step_row * cell_size, cell_size, cell_size, rl.ORANGE);

        rl.DrawText("QUADFALL", 40, 40, 30, rl.RAYWHITE);
        var buf: [64]u8 = undefined;
        const info = std.mem.printSentinel(&buf, "frame {d}\ndt {d:.1} ms", .{ frame, dt * 1000 }, 0) catch unreachable;
        rl.DrawText(info, 40, 90, 20, rl.LIGHTGRAY);
    }

    if (opts.screenshot) |path| {
        rl.TakeScreenshot(path);
        std.log.info("saved {s}", .{path});
    }
    return 0;
}
