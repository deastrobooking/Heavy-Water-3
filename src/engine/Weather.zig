//! A small deterministic cosmetic weather cycle. Full seasonal climate and gameplay effects
//! remain in docs/plans/weather-seasons.md; this supplies stable rain and overcast visuals now.
const Weather = @This();

pub const window_ticks: u64 = 10_800; // three minutes at 60 Hz
pub const fade_ticks: u64 = 900; // fifteen-second transition

pub const State = struct {
    precipitation: f32,
    cloud: f32,
};

const samples = [6]State{
    .{ .precipitation = 0, .cloud = 0.1 }, // clear
    .{ .precipitation = 0, .cloud = 0.6 }, // cloudy
    .{ .precipitation = 0.25, .cloud = 0.8 }, // light rain
    .{ .precipitation = 0.7, .cloud = 0.9 }, // rain
    .{ .precipitation = 1.0, .cloud = 1.0 }, // storm
    .{ .precipitation = 0, .cloud = 0.7 }, // foggy overcast
};

fn mix64(x: u64) u64 {
    var z = x +% 0x9e3779b97f4a7c15;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

fn sample(seed: u64, window: u64) State {
    const roll = mix64(seed ^ mix64(window)) % 100;
    const index: usize = if (roll < 42) 0 else if (roll < 63) 1 else if (roll < 79) 2 else if (roll < 92) 3 else if (roll < 97) 4 else 5;
    return samples[index];
}

/// World-wide visual weather derived only from the saved simulation tick and seed.
pub fn at(seed: u64, tick: u64) State {
    const window = tick / window_ticks;
    const into = tick % window_ticks;
    const current = sample(seed, window);
    if (into + fade_ticks < window_ticks) return current;
    const next = sample(seed, window +| 1);
    const t = @as(f32, @floatFromInt(into + fade_ticks - window_ticks)) / @as(f32, @floatFromInt(fade_ticks));
    const s = t * t * (3 - 2 * t);
    return .{
        .precipitation = current.precipitation + (next.precipitation - current.precipitation) * s,
        .cloud = current.cloud + (next.cloud - current.cloud) * s,
    };
}
