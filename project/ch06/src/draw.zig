//! Drawing the game with raylib. Positions and colors live here, not in core.
const std = @import("std");
const rl = @import("rl");
const core = @import("core");
const board = core.board;

pub const screen_width = 800;
pub const screen_height = 720;

pub const cell_size = 32;
/// Top-left corner of the visible playfield, in pixels.
pub const board_x = 240;
pub const board_y = 40;
pub const board_width = board.cols * cell_size;
pub const board_height = board.visible_rows * cell_size;

pub const background: rl.Color = .{ .r = 24, .g = 24, .b = 32, .a = 255 };
const well: rl.Color = .{ .r = 8, .g = 8, .b = 12, .a = 255 };
const grid_line: rl.Color = .{ .r = 32, .g = 32, .b = 44, .a = 255 };

pub fn cellColor(cell: core.Cell) rl.Color {
    return switch (cell) {
        .empty => well,
        .i => .{ .r = 0, .g = 200, .b = 230, .a = 255 },
        .o => .{ .r = 240, .g = 210, .b = 0, .a = 255 },
        .t => .{ .r = 170, .g = 60, .b = 220, .a = 255 },
        .s => .{ .r = 60, .g = 200, .b = 70, .a = 255 },
        .z => .{ .r = 230, .g = 50, .b = 60, .a = 255 },
        .j => .{ .r = 40, .g = 90, .b = 230, .a = 255 },
        .l => .{ .r = 240, .g = 140, .b = 20, .a = 255 },
        .garbage => .{ .r = 110, .g = 110, .b = 120, .a = 255 },
    };
}

/// Pixel x of the left edge of a board column.
pub fn cellX(col: i32) i32 {
    return board_x + col * cell_size;
}

/// Pixel y of the top edge of a board row. Board rows count up from the
/// floor but screen y counts down from the top, so the row is flipped.
pub fn cellY(row: i32) i32 {
    return board_y + (board.visible_rows - 1 - row) * cell_size;
}

/// One block with a light top-left edge and a dark bottom-right edge.
pub fn block(x: i32, y: i32, size: i32, color: rl.Color) void {
    const edge = @divTrunc(size, 8);
    rl.DrawRectangle(x, y, size, size, rl.ColorBrightness(color, -0.35));
    rl.DrawRectangle(x, y, size - edge, size - edge, rl.ColorBrightness(color, 0.35));
    rl.DrawRectangle(x + edge, y + edge, size - 2 * edge, size - 2 * edge, color);
}

pub fn drawBoard(b: *const core.Board) void {
    rl.DrawRectangle(board_x, board_y, board_width, board_height, well);
    for (1..board.cols) |col| {
        const x = cellX(@intCast(col));
        rl.DrawLine(x, board_y, x, board_y + board_height, grid_line);
    }
    for (1..board.visible_rows) |row| {
        const y = board_y + @as(i32, @intCast(row)) * cell_size;
        rl.DrawLine(board_x, y, board_x + board_width, y, grid_line);
    }
    rl.DrawRectangleLines(board_x - 1, board_y - 1, board_width + 2, board_height + 2, rl.GRAY);

    for (0..board.visible_rows) |row| {
        for (0..board.cols) |col| {
            const pos: core.Pos = .{ .col = @intCast(col), .row = @intCast(row) };
            const cell = b.get(pos);
            if (cell != .empty) block(cellX(pos.col), cellY(pos.row), cell_size, cellColor(cell));
        }
    }
}

/// Draws a piece on the board. Cells in the first hidden row show above the
/// playfield; higher ones are not drawn.
pub fn drawPiece(p: core.Piece) void {
    for (p.cells()) |pos| {
        if (pos.row > board.visible_rows) continue;
        block(cellX(pos.col), cellY(pos.row), cell_size, cellColor(p.kind.cell()));
    }
}

/// The ghost: where the piece would land, as a faint outline.
fn drawGhost(p: core.Piece) void {
    const color = rl.Fade(cellColor(p.kind.cell()), 0.5);
    for (p.cells()) |pos| {
        if (pos.row >= board.visible_rows) continue;
        const rect: rl.Rectangle = .{
            .x = @floatFromInt(cellX(pos.col) + 2),
            .y = @floatFromInt(cellY(pos.row) + 2),
            .width = cell_size - 4,
            .height = cell_size - 4,
        };
        rl.DrawRectangleLinesEx(rect, 2, color);
    }
}

const panel_cell = 20;
const panel_width = 5 * panel_cell;
const panel_height = 3 * panel_cell;

/// A small piece in spawn orientation, centered in a panel slot.
fn drawPreview(kind: core.Kind, x: i32, y: i32, color: rl.Color) void {
    const cells = core.Piece.spawn(kind).cells();
    var min_col: i32 = board.cols;
    var max_col: i32 = 0;
    var min_row: i32 = board.rows;
    var max_row: i32 = 0;
    for (cells) |pos| {
        min_col = @min(min_col, pos.col);
        max_col = @max(max_col, pos.col);
        min_row = @min(min_row, pos.row);
        max_row = @max(max_row, pos.row);
    }
    const w = (max_col - min_col + 1) * panel_cell;
    const h = (max_row - min_row + 1) * panel_cell;
    const left = x + @divTrunc(panel_width - w, 2);
    const top = y + @divTrunc(panel_height - h, 2);
    for (cells) |pos| {
        block(left + (pos.col - min_col) * panel_cell, top + (max_row - pos.row) * panel_cell, panel_cell, color);
    }
}

fn label(text: [:0]const u8, x: i32, y: i32) void {
    rl.DrawText(text, x, y, 20, rl.GRAY);
}

/// Formats `fmt` into a small buffer for raylib, which wants a 0-terminated string.
fn value(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    return std.mem.printSentinel(buf, fmt, args, 0) catch "?";
}

pub fn drawGame(g: *const core.Game) void {
    drawBoard(&g.board);
    switch (g.phase) {
        .falling => {
            drawGhost(g.dropped());
            drawPiece(g.piece);
        },
        .clearing => |c| {
            // The full rows flash white, fading as the timer runs out.
            const alpha = @as(f32, @floatFromInt(c.timer)) / core.game.clear_delay;
            var it = c.rows.iterator(.{});
            while (it.next()) |row| {
                const y = cellY(@intCast(row));
                rl.DrawRectangle(board_x, y, board_width, cell_size, rl.Fade(rl.WHITE, alpha));
            }
        },
        .over => {
            rl.DrawRectangle(board_x, board_y, board_width, board_height, rl.Fade(rl.BLACK, 0.6));
            const text = "GAME OVER";
            const width = rl.MeasureText(text, 40);
            rl.DrawText(text, board_x + @divTrunc(board_width - width, 2), board_y + 280, 40, rl.RAYWHITE);
        },
    }

    // Left of the board: hold and the numbers. Right of it: the queue.
    const left_x = 80;
    const right_x = board_x + board_width + 60;
    label("HOLD", left_x, 120);
    if (g.held) |kind| {
        const color = if (g.can_hold) cellColor(kind.cell()) else rl.GRAY;
        drawPreview(kind, left_x, 150, color);
    }
    var buf: [32]u8 = undefined;
    label("SCORE", left_x, 260);
    rl.DrawText(value(&buf, "{d}", .{g.score}), left_x, 285, 30, rl.RAYWHITE);
    label("LEVEL", left_x, 340);
    rl.DrawText(value(&buf, "{d}", .{g.level}), left_x, 365, 30, rl.RAYWHITE);
    label("LINES", left_x, 420);
    rl.DrawText(value(&buf, "{d}", .{g.lines}), left_x, 445, 30, rl.RAYWHITE);

    label("NEXT", right_x, 120);
    for (g.queue, 0..) |kind, i| {
        drawPreview(kind, right_x, 150 + @as(i32, @intCast(i)) * (panel_height + 20), cellColor(kind.cell()));
    }
}
