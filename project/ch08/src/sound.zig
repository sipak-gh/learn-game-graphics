//! Sound effects, made from square waves when the program starts: no files
//! to ship. Without an audio device every sound is silently skipped.
const std = @import("std");
const rl = @import("rl");

pub const Effect = enum { move, turn, hold, drop, lock, clear, four, level_up, game_over };

/// One beep that slides from one pitch to another and fades out.
const Note = struct { from_hz: f32, to_hz: f32, seconds: f32, volume: f32 = 0.25 };

fn notes(effect: Effect) []const Note {
    return switch (effect) {
        .move => &.{.{ .from_hz = 600, .to_hz = 600, .seconds = 0.02, .volume = 0.1 }},
        .turn => &.{.{ .from_hz = 800, .to_hz = 1000, .seconds = 0.04, .volume = 0.12 }},
        .hold => &.{.{ .from_hz = 500, .to_hz = 700, .seconds = 0.06 }},
        .drop => &.{.{ .from_hz = 300, .to_hz = 80, .seconds = 0.08 }},
        .lock => &.{.{ .from_hz = 150, .to_hz = 120, .seconds = 0.05 }},
        .clear => &.{ .{ .from_hz = 523, .to_hz = 523, .seconds = 0.06 }, .{ .from_hz = 784, .to_hz = 784, .seconds = 0.1 } },
        .four => &.{
            .{ .from_hz = 523, .to_hz = 523, .seconds = 0.06 }, .{ .from_hz = 659, .to_hz = 659, .seconds = 0.06 },
            .{ .from_hz = 784, .to_hz = 784, .seconds = 0.06 }, .{ .from_hz = 1047, .to_hz = 1047, .seconds = 0.2 },
        },
        .level_up => &.{ .{ .from_hz = 400, .to_hz = 800, .seconds = 0.15 }, .{ .from_hz = 800, .to_hz = 1200, .seconds = 0.15 } },
        .game_over => &.{ .{ .from_hz = 400, .to_hz = 300, .seconds = 0.3 }, .{ .from_hz = 300, .to_hz = 100, .seconds = 0.6 } },
    };
}

const sample_rate = 22050;

/// Writes square-wave samples for `list` into `out`; returns how many.
fn synth(list: []const Note, out: []i16) usize {
    var n: usize = 0;
    for (list) |note| {
        const count: usize = @intFromFloat(note.seconds * sample_rate);
        var phase: f32 = 0;
        for (0..count) |i| {
            if (n == out.len) return n;
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
            phase += std.math.lerp(note.from_hz, note.to_hz, t) / sample_rate;
            phase -= @floor(phase);
            const square: f32 = if (phase < 0.5) 1 else -1;
            out[n] = @intFromFloat(square * note.volume * (1 - t) * std.math.maxInt(i16));
            n += 1;
        }
    }
    return n;
}

pub const Sounds = struct {
    /// Empty when there is no audio: then `play` does nothing.
    loaded: ?std.EnumArray(Effect, rl.Sound) = null,

    /// Opens the audio device and makes every sound. Call after InitWindow.
    pub fn init() Sounds {
        rl.InitAudioDevice();
        if (!rl.IsAudioDeviceReady()) {
            std.log.warn("no audio device: sound is off", .{});
            return .{};
        }
        var buf: [sample_rate]i16 = undefined;
        var list: std.EnumArray(Effect, rl.Sound) = .initUndefined();
        for (std.meta.tags(Effect)) |effect| {
            const len = synth(notes(effect), &buf);
            const wave: rl.Wave = .{
                .frameCount = @intCast(len),
                .sampleRate = sample_rate,
                .sampleSize = 16,
                .channels = 1,
                .data = &buf,
            };
            // raylib copies the samples, so `buf` can be reused.
            list.set(effect, rl.LoadSoundFromWave(wave));
        }
        return .{ .loaded = list };
    }

    pub fn deinit(s: *Sounds) void {
        if (s.loaded) |list| {
            for (list.values) |sound| rl.UnloadSound(sound);
            rl.CloseAudioDevice();
        }
    }

    pub fn play(s: *const Sounds, effect: Effect) void {
        if (s.loaded) |list| rl.PlaySound(list.get(effect));
    }
};
