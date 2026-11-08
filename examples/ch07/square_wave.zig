//! Synthesizing a square wave into 16-bit samples: a pitch that may slide
//! from one frequency to another, and a volume that fades to zero.
const std = @import("std");

const sample_rate = 22050;

const Note = struct { from_hz: f32, to_hz: f32, seconds: f32, volume: f32 = 0.25 };

/// Writes the note's samples into `out`; returns how many.
fn synth(note: Note, out: []i16) usize {
    const count: usize = @min(out.len, @as(usize, @intFromFloat(note.seconds * sample_rate)));
    var phase: f32 = 0; // where we are in one cycle, 0 to 1
    for (out[0..count], 0..) |*sample, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
        phase += std.math.lerp(note.from_hz, note.to_hz, t) / sample_rate;
        phase -= @floor(phase);
        const square: f32 = if (phase < 0.5) 1 else -1;
        sample.* = @intFromFloat(square * note.volume * (1 - t) * std.math.maxInt(i16));
    }
    return count;
}

/// Counts the cycles by counting the jumps from low to high.
fn cycles(samples: []const i16) usize {
    var n: usize = 0;
    for (samples[1..], samples[0 .. samples.len - 1]) |now, before| {
        if (before <= 0 and now > 0) n += 1;
    }
    return n;
}

pub fn main() void {
    var buf: [sample_rate]i16 = undefined;

    // 441 Hz: one cycle is 22050 / 441 = 50 samples, half high, half low.
    const n = synth(.{ .from_hz = 441, .to_hz = 441, .seconds = 0.1 }, &buf);
    const s = buf[0..n];
    std.debug.print("{d} samples ({d} ms)\n", .{ n, n * 1000 / sample_rate });
    std.debug.print("samples 20..30: {any}\n", .{s[20..30]});
    std.debug.print("peak {d}, last {d}, cycles {d}\n", .{ std.mem.max(i16, s), s[n - 1], cycles(s) });

    // A slide from 300 Hz down to 80 Hz: fewer cycles in the same time.
    const m = synth(.{ .from_hz = 300, .to_hz = 80, .seconds = 0.1 }, &buf);
    std.debug.print("slide: {d} samples, cycles {d}\n", .{ m, cycles(buf[0..m]) });
}
