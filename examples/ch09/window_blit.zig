//! The smallest "canvas to window" program: our own pixel array, copied
//! into a GPU texture every frame and drawn once. No other raylib drawing.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const width = 320;
const height = 200;
const scale = 2;

/// One pixel, laid out as raylib's PIXELFORMAT_UNCOMPRESSED_R8G8B8A8.
const Color = extern struct { r: u8, g: u8, b: u8, a: u8 = 255 };

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));
    const pixels = try init.gpa.alloc(Color, width * height);
    defer init.gpa.free(pixels);

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(width * scale, height * scale, "window blit");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    // A texture the size of the canvas, created from an Image that points
    // at our pixels. After this, only UpdateTexture moves pixels to the GPU.
    const image: rl.Image = .{
        .data = pixels.ptr,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
    const texture = rl.LoadTextureFromImage(image);
    defer rl.UnloadTexture(texture);
    rl.SetTextureFilter(texture, rl.TEXTURE_FILTER_POINT);

    var frame: usize = 0;
    while (demo.running()) : (frame += 1) {
        // Software rendering: compute every pixel ourselves.
        for (pixels, 0..) |*p, i| {
            const x = i % width;
            const y = i / width;
            p.* = .{ .r = @truncate((x + frame) ^ y), .g = @truncate(y), .b = 96 };
        }
        rl.UpdateTexture(texture, pixels.ptr);

        rl.BeginDrawing();
        defer rl.EndDrawing();
        // Draw the 320x200 texture scaled up to fill the 640x400 window.
        rl.DrawTextureEx(texture, .{ .x = 0, .y = 0 }, 0, scale, rl.WHITE);
    }
    std.debug.print("ran {d} frames, {d} bytes uploaded per frame\n", .{ frame, @sizeOf(Color) * pixels.len });
}
