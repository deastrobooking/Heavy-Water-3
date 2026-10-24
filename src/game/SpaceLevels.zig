//! The orbital campaign's level design, as data: four sectors on one route (Luna, Mars, the
//! Asteroid Belt, the Kuiper Belt), ten levels each, three waves a level. Every level teaches or
//! mixes one formation; level 5 is a sector's battleship midboss and level 10 its phased boss.
//! Each sector has its own faction look and a difficulty tier, and opens once the previous
//! sector's midboss falls. Pure: `SpaceBattle` turns these into enemies. Clears are shared story
//! flags (`sp_<sector><level>`). See docs/plans/space-combat.md.
const std = @import("std");
const Progress = @import("Progress.zig");

pub const Location = enum { moon, mars, asteroid_belt, kuiper_belt };
pub const location_count = 4;
pub const levels = 10;
pub const waves = 3;
/// The level whose clear opens the next sector.
pub const gate_level = 5;
pub const boss_level = 10;

/// Enemy roles. Each faction draws them with its own meshes (`SpaceBattle.look`).
pub const Kind = enum { drone, fighter, transformer, battleship, mother_ship };
/// How a group enters: a row across the top, two wings from the sides, a ring closing on the
/// player, a single file, or a heavy ship flanked by wings.
pub const Pattern = enum { line, pincer, ring, column, escort };
pub const Group = struct { kind: Kind, count: u8, pattern: Pattern };
pub const Wave = struct { groups: [2]?Group = .{ null, null } };
pub const Faction = enum { brood, armada, mixed };

pub fn name(location: Location) []const u8 {
    return switch (location) {
        .moon => "LUNA ORBIT",
        .mars => "MARS ORBIT",
        .asteroid_belt => "ASTEROID BELT",
        .kuiper_belt => "KUIPER BELT",
    };
}

pub fn faction(location: Location) Faction {
    return switch (location) {
        .moon => .brood,
        .mars => .armada,
        .asteroid_belt => .mixed,
        .kuiper_belt => .brood,
    };
}

/// 0 for Luna up to 3 for the Kuiper Belt: health, fire rate and numbers grow with it.
pub fn tier(location: Location) u8 {
    return @intFromEnum(location);
}

/// The flag a level's clear sets.
pub fn flag(location: Location, level: u8, out: *[24]u8) []const u8 {
    const loc: []const u8 = switch (location) {
        .moon => "lu",
        .mars => "ma",
        .asteroid_belt => "ab",
        .kuiper_belt => "kb",
    };
    return std.fmt.bufPrint(out, "sp_{s}{d}", .{ loc, level }) catch unreachable;
}

pub fn cleared(progress: *const Progress, location: Location, level: u8) bool {
    var buf: [24]u8 = undefined;
    return progress.hasFlag(flag(location, level, &buf));
}

/// Levels cleared in a row from level 1.
pub fn clearedCount(progress: *const Progress, location: Location) u8 {
    var n: u8 = 0;
    while (n < levels and cleared(progress, location, n + 1)) n += 1;
    return n;
}

/// The first level not yet cleared, or the boss again once all are.
pub fn nextLevel(progress: *const Progress, location: Location) u8 {
    return @min(levels, clearedCount(progress, location) + 1);
}

/// Luna is always open; each later sector opens when the previous one's midboss is cleared.
pub fn unlocked(progress: *const Progress, location: Location) bool {
    if (location == .moon) return true;
    return cleared(progress, @enumFromInt(@intFromEnum(location) - 1), gate_level);
}

/// The ten levels' formations. Waves 1 and 2 build up; wave 3 is the level's point.
const table = [levels][waves]Wave{
    // 1: drones in a line, then a second line, then a pincer.
    .{ w(.drone, 4, .line), w(.drone, 5, .line), w(.drone, 6, .pincer) },
    // 2: pincers and a ring.
    .{ w(.drone, 6, .pincer), w(.drone, 6, .ring), w2(.drone, 4, .line, .drone, 4, .pincer) },
    // 3: fighters arrive.
    .{ w(.fighter, 2, .line), w2(.fighter, 2, .pincer, .drone, 4, .line), w(.fighter, 4, .ring) },
    // 4: a mixed push.
    .{ w2(.drone, 6, .column, .fighter, 1, .line), w2(.fighter, 3, .pincer, .drone, 4, .ring), w2(.fighter, 4, .line, .drone, 6, .pincer) },
    // 5: the battleship midboss.
    .{ w(.fighter, 4, .pincer), w2(.drone, 8, .ring, .fighter, 2, .line), w2(.battleship, 1, .escort, .drone, 4, .pincer) },
    // 6: transformers arrive.
    .{ w(.transformer, 2, .line), w2(.transformer, 2, .pincer, .drone, 4, .ring), w2(.transformer, 3, .ring, .fighter, 2, .line) },
    // 7: everything in a ring.
    .{ w2(.fighter, 4, .ring, .drone, 6, .column), w2(.transformer, 3, .pincer, .fighter, 3, .line), w2(.transformer, 4, .ring, .drone, 8, .pincer) },
    // 8: two battleships.
    .{ w2(.fighter, 4, .line, .transformer, 2, .pincer), w2(.battleship, 1, .escort, .fighter, 3, .pincer), w2(.battleship, 2, .escort, .drone, 6, .ring) },
    // 9: the elite swarm.
    .{ w2(.drone, 10, .ring, .fighter, 4, .pincer), w2(.transformer, 5, .ring, .drone, 6, .line), w2(.transformer, 4, .pincer, .fighter, 5, .ring) },
    // 10: escorts, then the mother ship.
    .{ w2(.fighter, 5, .pincer, .drone, 6, .ring), w2(.battleship, 1, .escort, .transformer, 3, .pincer), w2(.mother_ship, 1, .escort, .drone, 4, .pincer) },
};

fn w(kind: Kind, count: u8, pattern: Pattern) Wave {
    return .{ .groups = .{ .{ .kind = kind, .count = count, .pattern = pattern }, null } };
}

fn w2(a: Kind, an: u8, ap: Pattern, b: Kind, bn: u8, bp: Pattern) Wave {
    return .{ .groups = .{ .{ .kind = a, .count = an, .pattern = ap }, .{ .kind = b, .count = bn, .pattern = bp } } };
}

/// Wave `index` (1-based) of a level, with the sector's extra numbers: one more of each small
/// group per tier. Heavy ships are never multiplied.
pub fn wave(location: Location, level: u8, index: u8) Wave {
    const l = std.math.clamp(level, 1, levels);
    const i = std.math.clamp(index, 1, waves);
    var out = table[l - 1][i - 1];
    for (&out.groups) |*g| if (g.*) |*group| {
        if (group.kind == .drone or group.kind == .fighter) group.count += tier(location);
    };
    return out;
}

pub const Scale = struct { health: f32, fire: f32, damage: f32 };

/// How much tougher a sector's enemies are, and a little within it by level.
pub fn scale(location: Location, level: u8) Scale {
    const t: f32 = @floatFromInt(tier(location));
    const l: f32 = @floatFromInt(@max(level, 1) - 1);
    return .{ .health = 1 + t * 0.3 + l * 0.04, .fire = 1 + t * 0.15 + l * 0.03, .damage = 1 + t * 0.2 };
}

/// Scrap paid to each present player for a level clear; the boss pays gold too.
pub const Reward = struct { scrap: u32, gold: u32 };

pub fn reward(location: Location, level: u8) Reward {
    const t: u32 = tier(location);
    return .{ .scrap = 15 + @as(u32, level) * 3 + t * 10, .gold = if (level == boss_level) 3 + t * 2 else if (level == gate_level) 1 + t else 0 };
}

/// The flag a sector's boss clear sets for the solar story.
pub fn bossFlag(location: Location) []const u8 {
    return switch (location) {
        .moon => "luna_rescued",
        .mars => "mars_rescued",
        .asteroid_belt => "belt_secured",
        .kuiper_belt => "kuiper_secured",
    };
}

test "sectors open along the route when the previous midboss falls, and levels run in order" {
    var p: Progress = .{};
    try std.testing.expect(unlocked(&p, .moon));
    try std.testing.expect(!unlocked(&p, .mars));
    try std.testing.expectEqual(@as(u8, 1), nextLevel(&p, .moon));
    var f: [24]u8 = undefined;
    for (1..gate_level + 1) |l| p.setFlag(flag(.moon, @intCast(l), &f));
    try std.testing.expect(unlocked(&p, .mars));
    try std.testing.expect(!unlocked(&p, .asteroid_belt));
    try std.testing.expectEqual(@as(u8, gate_level + 1), nextLevel(&p, .moon));
    for (1..levels + 1) |l| p.setFlag(flag(.moon, @intCast(l), &f));
    // All cleared: the boss can be replayed.
    try std.testing.expectEqual(@as(u8, boss_level), nextLevel(&p, .moon));
    // The clears survive a save.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const restored = try Progress.fromDoc(try p.toDoc(arena.allocator()));
    try std.testing.expect(unlocked(&restored, .mars));
}

test "every level has three waves, the midboss and boss are where they belong, and tiers add numbers" {
    for (0..location_count) |s| for (1..levels + 1) |l| for (1..waves + 1) |i| {
        const wv = wave(@enumFromInt(s), @intCast(l), @intCast(i));
        try std.testing.expect(wv.groups[0] != null);
        for (wv.groups) |g| if (g) |group| try std.testing.expect(group.count >= 1);
    };
    const mid = wave(.moon, gate_level, waves).groups[0].?;
    try std.testing.expectEqual(Kind.battleship, mid.kind);
    const boss = wave(.moon, boss_level, waves).groups[0].?;
    try std.testing.expectEqual(Kind.mother_ship, boss.kind);
    try std.testing.expectEqual(@as(u8, 1), wave(.kuiper_belt, boss_level, waves).groups[0].?.count);
    try std.testing.expectEqual(wave(.moon, 1, 1).groups[0].?.count + 3, wave(.kuiper_belt, 1, 1).groups[0].?.count);
    try std.testing.expect(scale(.kuiper_belt, 1).health > scale(.moon, 10).health);
    try std.testing.expect(reward(.moon, boss_level).gold > 0 and reward(.moon, 1).gold == 0);
}
