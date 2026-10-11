const mach = @import("../main.zig");
const std = @import("std");

const Timer = @This();

// TODO: support a WASM-based timer as well, which is the primary reason this abstraction exists.

io: std.Io,
timestamp: std.Io.Timestamp,

/// Initialize the timer.
pub fn start(io: std.Io) Timer {
    return .{ .io = io, .timestamp = std.Io.Timestamp.now(io, .awake) };
}

/// Reads the timer value since start or the last reset in nanoseconds.
pub inline fn readPrecise(timer: *Timer) u64 {
    const now = std.Io.Timestamp.now(timer.io, .awake);
    const ns = timer.timestamp.durationTo(now).nanoseconds;
    return @intCast(@max(0, ns));
}

/// Reads the timer value since start or the last reset in seconds.
pub inline fn read(timer: *Timer) f32 {
    return @as(f32, @floatFromInt(timer.readPrecise())) / @as(f32, @floatFromInt(mach.time.ns_per_s));
}

/// Resets the timer value to 0/now.
pub inline fn reset(timer: *Timer) void {
    timer.timestamp = std.Io.Timestamp.now(timer.io, .awake);
}

/// Returns the current value of the timer in nanoseconds, then resets it.
pub inline fn lapPrecise(timer: *Timer) u64 {
    const now = std.Io.Timestamp.now(timer.io, .awake);
    const ns = timer.timestamp.durationTo(now).nanoseconds;
    timer.timestamp = now;
    return @intCast(@max(0, ns));
}

/// Returns the current value of the timer in seconds, then resets it.
pub inline fn lap(timer: *Timer) f32 {
    return @as(f32, @floatFromInt(timer.lapPrecise())) / @as(f32, @floatFromInt(mach.time.ns_per_s));
}
