//! The platform layer: the only file that talks to raylib. It opens a
//! window, shows the canvas on it, and reads the keyboard and mouse.
const rl = @import("rl");
const Canvas = @import("canvas.zig").Canvas;
const Input = @import("input.zig").Input;
const Action = @import("input.zig").Action;

/// Which key triggers which action.
const bindings = [_]struct { key: c_int, action: Action }{
    .{ .key = rl.KEY_TAB, .action = .next_view },
    .{ .key = rl.KEY_F, .action = .toggle_fisheye },
    .{ .key = rl.KEY_T, .action = .toggle_textures },
    .{ .key = rl.KEY_M, .action = .toggle_minimap },
    .{ .key = rl.KEY_O, .action = .toggle_overlay },
    .{ .key = rl.KEY_C, .action = .toggle_clipping },
    .{ .key = rl.KEY_B, .action = .toggle_culling },
    .{ .key = rl.KEY_Z, .action = .toggle_depth_test },
    .{ .key = rl.KEY_L, .action = .next_shading },
    .{ .key = rl.KEY_H, .action = .toggle_torch },
    .{ .key = rl.KEY_G, .action = .toggle_fog },
    .{ .key = rl.KEY_N, .action = .next_filter },
    .{ .key = rl.KEY_P, .action = .toggle_perspective },
    .{ .key = rl.KEY_I, .action = .toggle_info },
};

pub const Window = struct {
    texture: rl.Texture2D,
    /// False until the first frame has passed. Hiding the cursor moves it
    /// to the window center, and raylib reports that jump as mouse
    /// movement on the first frame; it must not turn the view.
    mouse_settled: bool = false,

    /// Opens a window `scale` times the canvas size, with a GPU texture
    /// the size of the canvas to copy our pixels into.
    pub fn open(title: [:0]const u8, canvas: Canvas, scale: u32) Window {
        rl.SetTraceLogLevel(rl.LOG_WARNING); // keep raylib's INFO lines quiet
        const w: c_int = @intCast(canvas.width * scale);
        const h: c_int = @intCast(canvas.height * scale);
        rl.InitWindow(w, h, title);
        rl.SetTargetFPS(60);
        // Hide the mouse cursor and keep it in the window, so the mouse
        // can turn the view forever without hitting the screen edge.
        rl.DisableCursor();

        const image: rl.Image = .{
            .data = canvas.pixels.ptr,
            .width = @intCast(canvas.width),
            .height = @intCast(canvas.height),
            .mipmaps = 1,
            .format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
        };
        const texture = rl.LoadTextureFromImage(image);
        // Scale up with hard pixel edges, not a blur.
        rl.SetTextureFilter(texture, rl.TEXTURE_FILTER_POINT);
        return .{ .texture = texture };
    }

    pub fn close(window: *Window) void {
        rl.UnloadTexture(window.texture);
        rl.CloseWindow();
    }

    /// True once the user closed the window or pressed Escape.
    pub fn shouldClose(_: Window) bool {
        return rl.WindowShouldClose();
    }

    /// Seconds since the previous frame.
    pub fn frameTime(_: Window) f32 {
        return rl.GetFrameTime();
    }

    /// Reads the keyboard and mouse: W/S move, A/D strafe, the arrow keys
    /// and the mouse turn and look up and down, and the keys in `bindings`
    /// trigger actions.
    pub fn input(window: *Window) Input {
        defer window.mouse_settled = true;
        const mouse: rl.Vector2 = if (window.mouse_settled) rl.GetMouseDelta() else .{ .x = 0, .y = 0 };
        var result: Input = .{
            .forward = axis(rl.KEY_S, rl.KEY_W),
            .strafe = axis(rl.KEY_A, rl.KEY_D),
            .turn = axis(rl.KEY_LEFT, rl.KEY_RIGHT),
            .tilt = axis(rl.KEY_DOWN, rl.KEY_UP),
            .look = mouse.x,
            .look_y = mouse.y,
        };
        for (bindings) |binding| {
            if (rl.IsKeyPressed(binding.key)) result.pressed.insert(binding.action);
        }
        return result;
    }

    /// Uploads the canvas to the texture and draws it to fill the window.
    pub fn present(window: Window, canvas: Canvas) void {
        rl.UpdateTexture(window.texture, canvas.pixels.ptr);
        rl.BeginDrawing();
        const source: rl.Rectangle = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(canvas.width),
            .height = @floatFromInt(canvas.height),
        };
        const dest: rl.Rectangle = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(rl.GetScreenWidth()),
            .height = @floatFromInt(rl.GetScreenHeight()),
        };
        rl.DrawTexturePro(window.texture, source, dest, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
        rl.EndDrawing();
    }

    /// Saves what is on screen (after scaling) as a PNG.
    pub fn screenshot(_: Window, path: [:0]const u8) void {
        rl.TakeScreenshot(path);
    }
};

/// -1 while `minus` is held, 1 while `plus` is held, 0 for neither or both.
fn axis(minus: c_int, plus: c_int) f32 {
    return @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(plus)))) -
        @as(f32, @floatFromInt(@intFromBool(rl.IsKeyDown(minus))));
}
