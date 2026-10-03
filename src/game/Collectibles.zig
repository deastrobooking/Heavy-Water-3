//! Things to find. Four kinds of pickups, placed deterministically from the seed and the world's
//! landmarks, plus temporary drops from defeated Hive units:
//!
//! - **Lumen shards** (common): on plazas, along bridge roads, around the spawn meadow.
//! - **Rotor cores** (rare): on tower roofs, beside the Rootdeep shrines, guarded at Hive nests.
//!   Hover cars need them.
//! - **Hive alloy**: dropped by Hive units and cached at nests. Weapons and armor need it.
//! - **Vital cells**: upgrade items, each adding to the party's maximum health. One on the
//!   tallest roof, one at each shrine, one at the largest nest.
//!
//! World pickups have stable IDs, so collecting one is remembered in the save; drops are not
//! saved. Walking within `radius` of a pickup collects it (any local player).
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Seed = @import("../procedural/Seed.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Collectibles = @This();

pub const Kind = enum { lumen_shard, rotor_core, hive_alloy, vital_cell };
pub const kind_count = @typeInfo(Kind).@"enum".fields.len;
pub const max_items = 128;
pub const max_drops = 32;
pub const radius: f32 = 1.6;
/// Seconds a drop lies before fading.
pub const drop_lifetime: f32 = 90;

pub const Item = struct { kind: Kind, position: V };
pub const Drop = struct { kind: Kind, position: V, age: f32 = 0 };

pub fn label(k: Kind) []const u8 {
    return switch (k) {
        .lumen_shard => "LUMEN SHARD",
        .rotor_core => "ROTOR CORE",
        .hive_alloy => "HIVE ALLOY",
        .vital_cell => "VITAL CELL",
    };
}

/// Emissive tint per kind.
pub fn tint(k: Kind) [3]f32 {
    return switch (k) {
        .lumen_shard => .{ 0.35, 1, 0.8 },
        .rotor_core => .{ 1, 0.6, 0.15 },
        .hive_alloy => .{ 1, 0.18, 0.2 },
        .vital_cell => .{ 1, 0.55, 0.85 },
    };
}

pub const Plaza = struct { position: V, arbor: bool };
pub const Roof = struct { position: V, half: [2]f32 };
/// Where the landmarks are; the Sandbox fills this after building the world.
pub const Sites = struct {
    seed: u64,
    spawn: V,
    /// Plaza centres (deck height) and whether each wraps an Arbor trunk.
    plazas: []const Plaza,
    /// Points along bridge road decks.
    roads: []const V,
    /// Tower roofs: centre at roof height, and the roof's half size.
    roofs: []const Roof,
    shrines: []const V,
    nests: []const V,
};

items: [max_items]Item = undefined,
count: usize = 0,
drops: [max_drops]?Drop = @splat(null),

/// Appends a world pickup (cave loot is added after `generate`, so earlier IDs stay put).
pub fn add(self: *Collectibles, kind: Kind, position: V) void {
    if (self.count == max_items) return;
    self.items[self.count] = .{ .kind = kind, .position = position };
    self.count += 1;
}

/// Places every world pickup. IDs are indices, stable for a seed and generator version.
pub fn generate(sites: Sites) Collectibles {
    var self: Collectibles = .{};
    var rng = std.Random.DefaultPrng.init(Seed.mix(sites.seed ^ 0x434f4c4c454354));
    const random = rng.random();
    // Lumen shards: three per plaza away from the trunk or tower, two per road, a meadow ring.
    for (sites.plazas) |p| for (0..3) |k| {
        const angle = (@as(f32, @floatFromInt(k)) + random.float(f32) * 0.6) * 2 * std.math.pi / 3;
        const r: f32 = if (p.arbor) 15 else 11;
        self.add(.lumen_shard, R.add(p.position, .{ @sin(angle) * r, 1, @cos(angle) * r }));
    };
    for (sites.roads) |p| self.add(.lumen_shard, R.add(p, .{ 0, 1, 0 }));
    for (0..10) |k| {
        const angle = @as(f32, @floatFromInt(k)) * 0.63 + random.float(f32) * 0.4;
        const r = 22 + random.float(f32) * 45;
        self.add(.lumen_shard, R.add(sites.spawn, .{ @sin(angle) * r, 1, @cos(angle) * r }));
    }
    // Rotor cores on the four tallest roofs, by the shrines, and at the nests.
    var tallest: [4]?usize = @splat(null);
    for (sites.roofs, 0..) |roof, i| {
        for (&tallest, 0..) |*slot, s| if (slot.* == null or roof.position[1] > sites.roofs[slot.*.?].position[1]) {
            var k = tallest.len - 1;
            while (k > s) : (k -= 1) tallest[k] = tallest[k - 1];
            slot.* = i;
            break;
        };
    }
    for (tallest) |slot| if (slot) |i| {
        const roof = sites.roofs[i];
        self.add(.rotor_core, R.add(roof.position, .{ roof.half[0] * 0.5, 1, -roof.half[1] * 0.5 }));
    };
    for (sites.shrines) |s| self.add(.rotor_core, R.add(s, .{ 6, 1, 0 }));
    for (sites.nests) |n| self.add(.rotor_core, R.add(n, .{ 0, 1, 7 }));
    // Hive alloy caches at the nests.
    for (sites.nests) |n| for (0..3) |k| {
        const angle = @as(f32, @floatFromInt(k)) * 2.1;
        self.add(.hive_alloy, R.add(n, .{ @sin(angle) * 9, 1, @cos(angle) * 9 }));
    };
    // Vital cells: the tallest roof, every shrine, the first nest.
    if (tallest[0]) |i| self.add(.vital_cell, R.add(sites.roofs[i].position, .{ -sites.roofs[i].half[0] * 0.5, 1, sites.roofs[i].half[1] * 0.5 }));
    for (sites.shrines) |s| self.add(.vital_cell, R.add(s, .{ -6, 1, 3 }));
    if (sites.nests.len > 0) self.add(.vital_cell, R.add(sites.nests[0], .{ 0, 1, -8 }));
    return self;
}

/// A defeated Hive unit drops `kind` at `position` (the oldest drop gives way when full).
pub fn drop(self: *Collectibles, kind: Kind, position: V) void {
    var oldest: usize = 0;
    for (&self.drops, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = .{ .kind = kind, .position = position };
            return;
        }
        if (slot.*.?.age > self.drops[oldest].?.age) oldest = i;
    }
    self.drops[oldest] = .{ .kind = kind, .position = position };
}

pub const Picked = std.StaticBitSet(max_items);
pub const Event = struct { kind: Kind, position: V };

/// Collects everything within reach of any of `players`; returns how many events were written.
pub fn collect(self: *Collectibles, picked: *Picked, players: []const V, dt: f32, out: []Event) usize {
    var n: usize = 0;
    for (self.items[0..self.count], 0..) |item, i| {
        if (picked.isSet(i)) continue;
        for (players) |p| if (near(p, item.position)) {
            picked.set(i);
            if (n < out.len) {
                out[n] = .{ .kind = item.kind, .position = item.position };
                n += 1;
            }
            break;
        };
    }
    for (&self.drops) |*slot| {
        const d = &(slot.* orelse continue);
        d.age += dt;
        if (d.age > drop_lifetime) {
            slot.* = null;
            continue;
        }
        for (players) |p| if (near(p, d.position)) {
            if (n < out.len) {
                out[n] = .{ .kind = d.kind, .position = d.position };
                n += 1;
            }
            slot.* = null;
            break;
        };
    }
    return n;
}

fn near(feet: V, item: V) bool {
    // From the feet to chest height, so a jump or a step up still picks it up.
    const d = R.sub(item, R.add(feet, .{ 0, 0.9, 0 }));
    return d[0] * d[0] + d[2] * d[2] < radius * radius and @abs(d[1]) < 1.8;
}

/// Uncollected world pickups of `kind` (for the HUD and tests).
pub fn remaining(self: *const Collectibles, picked: *const Picked, kind: Kind) usize {
    var n: usize = 0;
    for (self.items[0..self.count], 0..) |item, i| n += @intFromBool(item.kind == kind and !picked.isSet(i));
    return n;
}

test "placement is deterministic and covers every kind" {
    const plazas = [_]Plaza{ .{ .position = .{ 0, 40, 0 }, .arbor = true }, .{ .position = .{ 100, 30, 0 }, .arbor = false } };
    const roofs = [_]Roof{ .{ .position = .{ 50, 120, 50 }, .half = .{ 10, 12 } }, .{ .position = .{ -50, 90, 50 }, .half = .{ 8, 8 } } };
    const sites: Sites = .{ .seed = 7, .spawn = .{ 0, 0, -58 }, .plazas = &plazas, .roads = &.{ .{ 50, 35, 0 }, .{ 60, 35, 0 } }, .roofs = &roofs, .shrines = &.{ .{ -80, 0, -120 }, .{ -100, 0, -20 } }, .nests = &.{ .{ 300, 0, 300 } } };
    const a = generate(sites);
    const b = generate(sites);
    try std.testing.expectEqual(a.count, b.count);
    for (a.items[0..a.count], b.items[0..b.count]) |x, y| try std.testing.expectEqual(x, y);
    var picked: Picked = .initEmpty();
    for (0..kind_count) |k| try std.testing.expect(a.remaining(&picked, @enumFromInt(k)) > 0);
    // The vital cell on the tallest roof sits on the 120 m roof.
    var roof_cell = false;
    for (a.items[0..a.count]) |item| roof_cell = roof_cell or (item.kind == .vital_cell and item.position[1] > 115);
    try std.testing.expect(roof_cell);
}

test "walking over pickups collects each once; drops expire" {
    var c: Collectibles = .{};
    c.add(.lumen_shard, .{ 0, 1, 0 });
    c.add(.rotor_core, .{ 10, 1, 0 });
    var picked: Picked = .initEmpty();
    var events: [8]Event = undefined;
    try std.testing.expectEqual(@as(usize, 1), c.collect(&picked, &.{.{ 0.5, 0, 0 }}, 0.1, &events));
    try std.testing.expectEqual(Kind.lumen_shard, events[0].kind);
    try std.testing.expectEqual(@as(usize, 0), c.collect(&picked, &.{.{ 0.5, 0, 0 }}, 0.1, &events));
    // Out of reach overhead.
    try std.testing.expectEqual(@as(usize, 0), c.collect(&picked, &.{.{ 10, 8, 0 }}, 0.1, &events));
    c.drop(.hive_alloy, .{ 20, 1, 0 });
    try std.testing.expectEqual(@as(usize, 1), c.collect(&picked, &.{.{ 20, 0, 0 }}, 0.1, &events));
    c.drop(.hive_alloy, .{ 30, 1, 0 });
    _ = c.collect(&picked, &.{}, drop_lifetime + 1, &events);
    try std.testing.expectEqual(@as(usize, 0), c.collect(&picked, &.{.{ 30, 0, 0 }}, 0.1, &events));
}
