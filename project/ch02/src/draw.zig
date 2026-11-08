//! Drawing the game with raylib. Positions and colors live here, not in core.
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
