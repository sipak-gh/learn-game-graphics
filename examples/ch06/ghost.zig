//! A ghost piece: where the falling piece would land. The landing spot is
//! plain logic (fall while it fits); the look is two raylib calls,
//! DrawRectangleLinesEx for an outline and Fade for transparency.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const cols = 8;
const rows = 12;
const cell = 24;

/// The stack, top row first; '#' is a locked block.
const stack = [rows]*const [cols]u8{
    "........", "........", "........", "........", "........", "........",
    "........", "........", "#.......", "##...#..", "###.###.", "####.###",
};
/// A T piece: four (col, row) cells, row 0 at the top.
const t_cells = [4][2]i32{ .{ 3, 0 }, .{ 2, 1 }, .{ 3, 1 }, .{ 4, 1 } };

fn fits(dy: i32) bool {
    for (t_cells) |c| {
        const r = c[1] + dy;
        if (r >= rows or stack[@intCast(r)][@intCast(c[0])] == '#') return false;
    }
    return true;
}

fn drawWell(x: i32, title: [:0]const u8, landing: i32, outline: bool) void {
    const purple: rl.Color = .{ .r = 170, .g = 60, .b = 220, .a = 255 };
    rl.DrawText(title, x, 20, 20, rl.LIGHTGRAY);
    rl.DrawRectangle(x, 50, cols * cell, rows * cell, .{ .r = 8, .g = 8, .b = 12, .a = 255 });
    for (stack, 0..) |line, r| for (line, 0..) |ch, c| if (ch == '#') {
        rl.DrawRectangle(x + @as(i32, @intCast(c)) * cell + 1, 50 + @as(i32, @intCast(r)) * cell + 1, cell - 2, cell - 2, rl.GRAY);
    };
    for (t_cells) |c| {
        const px = x + c[0] * cell;
        // The ghost first, so the real piece covers it where they overlap.
        const gy = 50 + (c[1] + landing) * cell;
        const rect: rl.Rectangle = .{ .x = @floatFromInt(px + 2), .y = @floatFromInt(gy + 2), .width = cell - 4, .height = cell - 4 };
        if (outline) rl.DrawRectangleLinesEx(rect, 2, rl.Fade(purple, 0.5)) else rl.DrawRectangleRec(rect, rl.Fade(purple, 0.25));
        rl.DrawRectangle(px + 1, 50 + c[1] * cell + 1, cell - 2, cell - 2, purple);
    }
}

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));
    var landing: i32 = 0;
    while (fits(landing + 1)) landing += 1;
    std.debug.print("the T lands {d} rows down\n", .{landing});

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(500, 360, "ghost");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);
    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(.{ .r = 24, .g = 24, .b = 32, .a = 255 });
        drawWell(30, "outline, Fade 0.5", landing, true);
        drawWell(270, "filled, Fade 0.25", landing, false);
    }
}
