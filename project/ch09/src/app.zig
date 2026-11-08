//! The program's state and drawing, independent of any window. main.zig
//! calls `update` once per tick and `render` once per frame.
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;

pub const App = struct {
    /// Seconds of simulated time.
    time: f32 = 0,

    pub fn update(app: *App, dt: f32) void {
        app.time += dt;
    }

    /// Fills every pixel: red grows to the right, green grows downward, and
    /// blue is an XOR pattern that scrolls left at 60 pixels per second.
    pub fn render(app: App, canvas: Canvas) void {
        const shift: usize = @intFromFloat(app.time * 60);
        for (0..canvas.height) |y| {
            for (canvas.row(y), 0..) |*pixel, x| {
                pixel.* = .{
                    .r = @intCast(x * 255 / (canvas.width - 1)),
                    .g = @intCast(y * 255 / (canvas.height - 1)),
                    .b = @truncate((x + shift) ^ y),
                };
            }
        }
        // A one-pixel frame shows that the canvas edges land on the window edges.
        const w: i32 = @intCast(canvas.width);
        const h: i32 = @intCast(canvas.height);
        var i: i32 = 0;
        while (i < w) : (i += 1) {
            canvas.set(i, 0, Color.white);
            canvas.set(i, h - 1, Color.white);
        }
        i = 0;
        while (i < h) : (i += 1) {
            canvas.set(0, i, Color.white);
            canvas.set(w - 1, i, Color.white);
        }
    }
};
