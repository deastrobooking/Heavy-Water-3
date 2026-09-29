const std = @import("std");
const mach = @import("../main.zig");
const Timer = @import("Timer.zig");

pub const Frequency = @This();

/// The target frequency (e.g. 60hz) or zero for unlimited
target: u32 = 0,

/// The estimated delay that is needed to achieve the target frequency. Updated during tick()
delay_ns: u64 = 0,

/// The actual measured frequency. This is updated after intervals of at least one second.
rate: u32 = 0,

delta_time: ?*f32 = null,
delta_time_ns: *u64 = undefined,

/// Internal fields, this must be initialized via a call to start().
internal: struct {
    // The frame number in this second's cycle. e.g. zero to 59
    count: u32,
    timer: Timer,
    last_time: u64,
} = undefined,

/// Starts the timer used for frequency calculation. Must be called once before anything else.
pub fn start(f: *Frequency, io: std.Io) void {
    f.internal = .{
        .count = 0,
        .timer = Timer.start(io),
        .last_time = 0,
    };
}

/// Tick should be called at each occurrence (e.g. frame)
pub inline fn tick(f: *Frequency) void {
    var current_time = f.internal.timer.readPrecise();

    if (f.delta_time) |delta_time| {
        f.delta_time_ns.* = current_time -| f.internal.last_time;
        delta_time.* = @as(f32, @floatFromInt(f.delta_time_ns.*)) / @as(f32, @floatFromInt(mach.time.ns_per_s));
    }

    if (current_time >= mach.time.ns_per_s) {
        const elapsed_ns = f.internal.timer.lapPrecise();
        f.rate = rateForInterval(f.internal.count, elapsed_ns);
        f.internal.count = 0;
        current_time = 0;
    }
    f.internal.last_time = current_time;
    f.internal.count += 1;

    if (f.target != 0) {
        const limited_count = @min(f.target, f.internal.count);
        const target_time_per_tick: u64 = (mach.time.ns_per_s / f.target);
        const target_time = target_time_per_tick * limited_count;
        if (current_time > target_time) {
            f.delay_ns = 0;
        } else {
            f.delay_ns = target_time - current_time;
        }
    } else {
        f.delay_ns = 0;
    }
}

fn rateForInterval(count: u32, elapsed_ns: u64) u32 {
    if (elapsed_ns == 0) return 0;

    const elapsed: u128 = elapsed_ns;
    const scaled_count = @as(u128, count) * mach.time.ns_per_s;
    const rounded_rate = (scaled_count + elapsed / 2) / elapsed;
    return @intCast(@min(rounded_rate, @as(u128, std.math.maxInt(u32))));
}

test "rate uses the exact elapsed interval" {
    try std.testing.expectEqual(120, rateForInterval(120, mach.time.ns_per_s));
    try std.testing.expectEqual(
        120,
        rateForInterval(121, mach.time.ns_per_s + mach.time.ns_per_s / 120),
    );
}

test "rate rounds to the nearest whole frequency" {
    try std.testing.expectEqual(120, rateForInterval(120, mach.time.ns_per_s + 1));
    try std.testing.expectEqual(119, rateForInterval(119, mach.time.ns_per_s + 1));
}

test "rollover restarts pacing at the timer reset" {
    var f: Frequency = .{ .target = 120 };
    f.start(std.testing.io);
    f.internal.count = 120;
    f.internal.timer.timestamp = std.Io.Timestamp.now(std.testing.io, .awake).subDuration(.{
        .nanoseconds = mach.time.ns_per_s + 4 * std.time.ns_per_ms,
    });

    f.tick();

    try std.testing.expectEqual(120, f.rate);
    try std.testing.expectEqual(1, f.internal.count);
    try std.testing.expectEqual(0, f.internal.last_time);
    try std.testing.expectEqual(mach.time.ns_per_s / f.target, f.delay_ns);
}
