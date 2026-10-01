//! Glowworks: an example Heavy Water mod. Scripts are pure functions of a script device's four
//! inputs (a..d) and world time in seconds, returning its output. Script API v1: no imports.

/// While `a` is on, a lamp level that breathes between 0.1 and 1 every four seconds.
export fn breathe(a: f32, b: f32, c: f32, d: f32, time: f32) f32 {
    _ = .{ b, c, d };
    if (a < 0.5) return 0;
    return 0.55 + 0.45 * @sin(time * 2 * std.math.pi / 4);
}

/// On when at least two of a, b, c are on; d inverts the vote.
export fn majority(a: f32, b: f32, c: f32, d: f32, time: f32) f32 {
    _ = time;
    var votes: u32 = 0;
    for ([_]f32{ a, b, c }) |v| votes += @intFromBool(v > 0.5);
    const on = votes >= 2;
    return if (on != (d > 0.5)) 1 else 0;
}

const std = @import("std");
