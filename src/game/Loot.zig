//! What a defeated unit drops. One table for every enemy kind, so tuning "how easy are scrap and
//! parts to get" is a data edit here, not a search through combat code. Robots (the Scalari)
//! pay the most scrap and parts; Hive insects pay a little scrap and sometimes a part, plus the
//! alloy and lumen they always dropped. Drops go to the killer's own wallet and kit (a personal
//! reward, per AGENTS.md), never to a shared stockpile.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Enemies = @import("Enemies.zig");

pub const Reward = struct { scrap: u32 = 0, parts: u32 = 0, alloy: u32 = 0, lumen: u32 = 0 };

const Entry = struct {
    scrap_min: u32,
    scrap_max: u32,
    /// Parts always dropped, plus one more with probability `extra_part`.
    parts: u32 = 0,
    extra_part: f32 = 0,
    /// Hive alloy dropped (insects); lumen with probability `lumen_chance`.
    alloy: u32 = 0,
    lumen_chance: f32 = 0,
};

fn entry(kind: Enemies.Kind) Entry {
    return switch (kind) {
        // Robots: reliable scrap and parts, more for the bigger frames.
        .scalari_scout => .{ .scrap_min = 6, .scrap_max = 10, .parts = 1, .extra_part = 0.25 },
        .scalari_stinger => .{ .scrap_min = 10, .scrap_max = 16, .parts = 2, .extra_part = 0.25 },
        .scalari_miner => .{ .scrap_min = 8, .scrap_max = 14, .parts = 2, .extra_part = 0.25 },
        .scalari_hybrid => .{ .scrap_min = 14, .scrap_max = 22, .parts = 2, .extra_part = 0.5 },
        .scalari_titan => .{ .scrap_min = 80, .scrap_max = 120, .parts = 10, .extra_part = 1 },
        // Hive insects: a little scrap from what they carry, a part now and then.
        .drone => .{ .scrap_min = 2, .scrap_max = 4, .extra_part = 0.2, .alloy = 1, .lumen_chance = 0.35 },
        .skirmisher => .{ .scrap_min = 3, .scrap_max = 6, .extra_part = 0.25, .alloy = 1, .lumen_chance = 0.35 },
        .trooper => .{ .scrap_min = 5, .scrap_max = 9, .extra_part = 0.4, .alloy = 1, .lumen_chance = 0.35 },
        .sentinel, .bulwark => .{ .scrap_min = 8, .scrap_max = 14, .parts = 1, .extra_part = 0.3, .alloy = 3, .lumen_chance = 0.35 },
    };
}

/// Rolls a kill's drops with the world's enemy random source (so a seeded run repeats).
pub fn roll(kind: Enemies.Kind, random: std.Random) Reward {
    const e = entry(kind);
    return .{
        .scrap = e.scrap_min + random.uintLessThan(u32, e.scrap_max - e.scrap_min + 1),
        .parts = e.parts + @intFromBool(e.extra_part > 0 and random.float(f32) < e.extra_part),
        .alloy = e.alloy,
        .lumen = @intFromBool(e.lumen_chance > 0 and random.float(f32) < e.lumen_chance),
    };
}

/// The expected scrap and parts of one kill, for balance tests and the strategy panel.
pub fn expected(kind: Enemies.Kind) struct { scrap: f32, parts: f32 } {
    const e = entry(kind);
    return .{ .scrap = @as(f32, @floatFromInt(e.scrap_min + e.scrap_max)) / 2, .parts = @as(f32, @floatFromInt(e.parts)) + e.extra_part };
}

test "every enemy kind drops scrap, robots pay more than insects, and a roll stays in range" {
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();
    inline for (enum_compat.fields(Enemies.Kind)) |f| {
        const kind: Enemies.Kind = @enumFromInt(f.value);
        const e = entry(kind);
        try std.testing.expect(e.scrap_min >= 1 and e.scrap_max >= e.scrap_min);
        for (0..200) |_| {
            const r = roll(kind, random);
            try std.testing.expect(r.scrap >= e.scrap_min and r.scrap <= e.scrap_max);
            try std.testing.expect(r.parts >= e.parts and r.parts <= e.parts + 1);
            try std.testing.expect(r.lumen <= 1);
        }
        // Only Hive insects drop alloy and lumen; robots drop none.
        try std.testing.expectEqual(Enemies.isScalari(kind), e.alloy == 0 and e.lumen_chance == 0);
    }
    try std.testing.expect(expected(.scalari_scout).scrap > expected(.drone).scrap);
    try std.testing.expect(expected(.scalari_stinger).parts > expected(.trooper).parts);
    // A turret-sized purchase (about 60 scrap and 6 parts) takes a handful of robot kills.
    const kills_for_scrap = 60 / expected(.scalari_stinger).scrap;
    try std.testing.expect(kills_for_scrap <= 6);
}
