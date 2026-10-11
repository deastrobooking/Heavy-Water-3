//! What the team shares, saved with the world: story flags set by conversations and world
//! events, the Wildkin heroes on the roster (anyone can play as them), world pickups already
//! taken, the hover cars and the Kestrel in the garage with its upgrades and paint, and the
//! arena record. Each player's own upgrades, gear, pickups, pets and wallet are their `Kit`.
const std = @import("std");
const Kit = @import("Kit.zig");
const Market = @import("../city/Market.zig");
const Profile = @import("Profile.zig");
const Collectibles = @import("Collectibles.zig");
const Designs = @import("../vehicle/Designs.zig");
const WeaponKind = @import("../combat/Weapon.zig").WeaponKind;
const Progress = @This();

pub const Upgrade = Kit.Upgrade;
pub const upgrade_count = Kit.upgrade_count;
pub const max_level = Kit.max_level;
pub const Cost = Kit.Cost;
pub const Error = Kit.Error;
pub const info = Kit.info;
pub const bit = Kit.bit;
pub const armorBit = Kit.armorBit;
pub const suitPrice = Kit.suitPrice;
/// Nests, carriers, caves, conversations and quests each set flags; 48 overflowed once caves
/// arrived (later flags were silently dropped and not saved).
pub const max_flags = 96;
pub const flag_capacity = 24;
pub const KestrelUpgrade = enum { armor, missile_rack, engine, gun_cooling };
pub const kestrel_upgrade_count = @typeInfo(KestrelUpgrade).@"enum".fields.len;
pub const Paint = enum { ivory, azure, ember, moss };
pub const paint_count = @typeInfo(Paint).@"enum".fields.len;

/// World pickups already collected, by ID.
picked: Collectibles.Picked = .initEmpty(),
/// Fabricated hover car designs (bit per design).
vehicles: u8 = 0,
/// The Kestrel fighter has been fabricated.
fighter: bool = false,
kestrel_levels: [kestrel_upgrade_count]u8 = @splat(0),
kestrel_paints: u8 = 1,
kestrel_paint: Paint = .ivory,
/// Wildkin heroes who have joined the roster (bit per `Heroes.roster` index); the starters
/// begin joined.
heroes: u32 = @import("Heroes.zig").starters(),
/// The furthest arena wave the party has cleared.
arena_best: u16 = 0,
flag_names: [max_flags][flag_capacity]u8 = undefined,
flag_lens: [max_flags]u8 = @splat(0),
flag_count: usize = 0,

pub fn ownsVehicle(self: *const Progress, d: Designs.Design) bool {
    return self.vehicles & (@as(u8, 1) << @intCast(@intFromEnum(d))) != 0;
}
pub fn kestrelLevel(self: *const Progress, upgrade: KestrelUpgrade) u8 {
    return self.kestrel_levels[@intFromEnum(upgrade)];
}

pub fn kestrelUpgradeCost(self: *const Progress, upgrade: KestrelUpgrade) Cost {
    const base = ([_]Cost{ .{ .scrap = 60, .parts = 2 }, .{ .scrap = 70, .parts = 2 }, .{ .scrap = 80, .parts = 3 }, .{ .scrap = 60, .parts = 2 } })[@intFromEnum(upgrade)];
    const scale = ([_]u32{ 1, 2, 3 })[@min(self.kestrelLevel(upgrade), 2)];
    return .{ .scrap = base.scrap * scale, .parts = base.parts * scale };
}

pub fn buyKestrelUpgrade(self: *Progress, upgrade: KestrelUpgrade, wallet: *Market.Wallet) Error!void {
    const current_level = self.kestrelLevel(upgrade);
    if (current_level >= max_level) return error.MaxLevel;
    try Kit.pay(wallet, self.kestrelUpgradeCost(upgrade));
    self.kestrel_levels[@intFromEnum(upgrade)] += 1;
}

pub fn ownsKestrelPaint(self: *const Progress, paint: Paint) bool {
    return (self.kestrel_paints & (@as(u8, 1) << @intCast(@intFromEnum(paint)))) != 0;
}

pub fn kestrelPaintCost(paint: Paint) Cost {
    return switch (paint) {
        .ivory => .{ .scrap = 0, .parts = 0 },
        .azure => .{ .scrap = 45, .parts = 0 },
        .ember => .{ .scrap = 65, .parts = 1 },
        .moss => .{ .scrap = 55, .parts = 1 },
    };
}

pub fn buyKestrelPaint(self: *Progress, paint: Paint, wallet: *Market.Wallet) Error!void {
    if (self.ownsKestrelPaint(paint)) return error.AlreadyOwned;
    try Kit.pay(wallet, kestrelPaintCost(paint));
    self.kestrel_paints |= @as(u8, 1) << @intCast(@intFromEnum(paint));
    self.kestrel_paint = paint;
}

pub fn selectKestrelPaint(self: *Progress, paint: Paint) Error!void {
    if (!self.ownsKestrelPaint(paint)) return error.NotOwned;
    self.kestrel_paint = paint;
}

pub fn hasFlag(self: *const Progress, name: []const u8) bool {
    for (0..self.flag_count) |i| if (std.mem.eql(u8, self.flag_names[i][0..self.flag_lens[i]], name)) return true;
    return false;
}

/// Sets a story flag. Names longer than `flag_capacity` or beyond `max_flags` are ignored
/// (dialogue validation rejects such names before they reach here).
pub fn setFlag(self: *Progress, name: []const u8) void {
    if (name.len == 0 or name.len > flag_capacity or self.hasFlag(name) or self.flag_count == max_flags) return;
    @memcpy(self.flag_names[self.flag_count][0..name.len], name);
    self.flag_lens[self.flag_count] = @intCast(name.len);
    self.flag_count += 1;
}

pub fn flag(self: *const Progress, i: usize) []const u8 {
    return self.flag_names[i][0..self.flag_lens[i]];
}

/// JSON shape stored in saves; older saves without it load as a fresh start. Format 12 saves
/// also kept P1's personal progression here (levels through weapon tiers, suits, pets); those
/// fields are read only to migrate them into P1's kit (`legacyKit`) and are no longer written.
pub const Doc = struct {
    /// One level per upgrade, in `Upgrade` order; a save from before an upgrade existed is shorter.
    levels: []const u8 = &.{},
    /// Held pickups in `Collectibles.Kind` order (shorter in older saves).
    inventory: []const u32 = &.{},
    /// IDs of collected world pickups.
    picked: []const u16 = &.{},
    vehicles: []const Designs.Design = &.{},
    armors: []const Profile.Armor = &.{},
    weapons: []const WeaponKind = &.{},
    /// Installed Mk II/Mk III weapon tiers; older saves omit this field.
    weapon_upgrades: []const u8 = &.{},
    fighter: bool = false,
    kestrel_levels: []const u8 = &.{},
    kestrel_paints: u8 = 1,
    kestrel_paint: Paint = .ivory,
    suits: []const Profile.Clothing = &.{},
    flags: []const []const u8 = &.{},
    /// Joined heroes by name (stable if the roster grows); older saves omit it (starters only).
    heroes: ?[]const []const u8 = null,
    arena_best: u16 = 0,
    pets: []const Kit.PetDoc = &.{},
    pet_active: ?[]const u8 = null,
};

/// P1's kit as a format 12 save kept it (personal fields inside the shared progress), with the
/// save's one wallet.
pub fn legacyKit(doc: Doc, wallet: Market.Wallet) error{InvalidKit}!Kit {
    return Kit.fromDoc(.{ .wallet = wallet, .levels = doc.levels, .inventory = doc.inventory, .armors = doc.armors, .weapons = doc.weapons, .weapon_upgrades = doc.weapon_upgrades, .suits = doc.suits, .pets = doc.pets, .pet_active = doc.pet_active });
}

pub fn hasHero(self: *const Progress, index: u8) bool {
    return self.heroes & (@as(u32, 1) << @intCast(index)) != 0;
}

/// A hero joins the roster; false if they already had.
pub fn addHero(self: *Progress, index: u8) bool {
    if (self.hasHero(index)) return false;
    self.heroes |= @as(u32, 1) << @intCast(index);
    return true;
}

pub fn toDoc(self: *const Progress, arena: std.mem.Allocator) !Doc {
    const flags = try arena.alloc([]const u8, self.flag_count);
    for (flags, 0..) |*out, i| out.* = try arena.dupe(u8, self.flag(i));
    var picked: std.ArrayList(u16) = .empty;
    var it = self.picked.iterator(.{});
    while (it.next()) |i| try picked.append(arena, @intCast(i));
    var vehicles: std.ArrayList(Designs.Design) = .empty;
    inline for (@typeInfo(Designs.Design).@"enum".fields) |f| if (self.ownsVehicle(@enumFromInt(f.value))) try vehicles.append(arena, @enumFromInt(f.value));
    const Heroes = @import("Heroes.zig");
    var heroes: std.ArrayList([]const u8) = .empty;
    for (Heroes.roster, 0..) |h, i| if (self.hasHero(@intCast(i))) try heroes.append(arena, h.name);
    return .{ .heroes = heroes.items, .arena_best = self.arena_best, .flags = flags, .picked = picked.items, .vehicles = vehicles.items, .fighter = self.fighter, .kestrel_levels = try arena.dupe(u8, &self.kestrel_levels), .kestrel_paints = self.kestrel_paints, .kestrel_paint = self.kestrel_paint };
}

pub fn fromDoc(doc: Doc) error{InvalidProgress}!Progress {
    var result: Progress = .{};
    for (doc.picked) |i| {
        if (i >= Collectibles.max_items) return error.InvalidProgress;
        result.picked.set(i);
    }
    for (doc.vehicles) |d| result.vehicles |= @as(u8, 1) << @intCast(@intFromEnum(d));
    result.fighter = doc.fighter;
    if (doc.kestrel_levels.len > kestrel_upgrade_count) return error.InvalidProgress;
    for (doc.kestrel_levels) |l| if (l > max_level) return error.InvalidProgress;
    @memcpy(result.kestrel_levels[0..doc.kestrel_levels.len], doc.kestrel_levels);
    if (doc.kestrel_paints == 0 or doc.kestrel_paints >> paint_count != 0 or (doc.kestrel_paints & (@as(u8, 1) << @intCast(@intFromEnum(doc.kestrel_paint)))) == 0) return error.InvalidProgress;
    result.kestrel_paints = doc.kestrel_paints;
    result.kestrel_paint = doc.kestrel_paint;
    if (doc.heroes) |names| {
        const Heroes = @import("Heroes.zig");
        result.heroes = 0;
        for (names) |name| for (Heroes.roster, 0..) |h, i| if (std.mem.eql(u8, h.name, name)) {
            result.heroes |= @as(u32, 1) << @intCast(i);
        };
        // The starters are always on the roster.
        result.heroes |= Heroes.starters();
    }
    result.arena_best = doc.arena_best;
    if (doc.flags.len > max_flags) return error.InvalidProgress;
    for (doc.flags) |name| {
        if (name.len == 0 or name.len > flag_capacity) return error.InvalidProgress;
        result.setFlag(name);
    }
    return result;
}

test "team progress round-trips flags, pickups, the garage and heroes; old personal fields migrate" {
    var p: Progress = .{};
    p.setFlag("met_maro");
    p.setFlag("met_maro");
    p.setFlag("x" ** 30);
    try std.testing.expectEqual(@as(usize, 1), p.flag_count);
    p.picked.set(3);
    p.picked.set(90);
    p.vehicles = 0b101;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const json = try std.json.Stringify.valueAlloc(arena.allocator(), try p.toDoc(arena.allocator()), .{});
    const back = try fromDoc(try std.json.parseFromSliceLeaky(Doc, arena.allocator(), json, .{}));
    try std.testing.expect(back.hasFlag("met_maro"));
    try std.testing.expect(back.picked.isSet(90) and back.picked.isSet(3) and back.picked.count() == 2);
    try std.testing.expect(back.ownsVehicle(.courier) and !back.ownsVehicle(.dart));
    try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .picked = &.{999} }));
    // A format 12 save kept P1's own progression here: it becomes P1's kit.
    const kit = try legacyKit(.{ .levels = &.{ 0, 2 }, .inventory = &.{ 1, 0, 0, 2 }, .suits = &.{.exo_rig}, .pets = &.{.{ .name = "GARU", .xp = 60 }}, .pet_active = "GARU" }, .{ .scrap = 77 });
    try std.testing.expect(kit.level(.jet_efficiency) == 2 and kit.owns(.exo_rig) and kit.maxHealth() == 140);
    try std.testing.expectEqual(@as(u32, 77), kit.wallet.scrap);
    try std.testing.expectEqual(@as(u8, 2), kit.petLevel(.hound));
}

test "Kestrel upgrades change owned loadout and paint selection persists" {
    var p: Progress = .{};
    var wallet: Market.Wallet = .{ .scrap = 10_000, .parts = 100 };
    const first_cost = p.kestrelUpgradeCost(.engine);
    try p.buyKestrelUpgrade(.engine, &wallet);
    try std.testing.expectEqual(@as(u8, 1), p.kestrelLevel(.engine));
    try std.testing.expectEqual(@as(u32, 10_000 - first_cost.scrap), wallet.scrap);
    try p.buyKestrelPaint(.azure, &wallet);
    try std.testing.expectEqual(Paint.azure, p.kestrel_paint);
    try p.selectKestrelPaint(.ivory);
    try std.testing.expectError(error.NotOwned, p.selectKestrelPaint(.ember));

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const doc = try p.toDoc(arena.allocator());
    const restored = try fromDoc(doc);
    try std.testing.expectEqual(p.kestrel_levels, restored.kestrel_levels);
    try std.testing.expectEqual(p.kestrel_paints, restored.kestrel_paints);
    try std.testing.expectEqual(p.kestrel_paint, restored.kestrel_paint);
    try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .kestrel_levels = &.{4} }));
}

test "heroes join once, round-trip by name, and older saves keep the starters" {
    const Heroes = @import("Heroes.zig");
    var p: Progress = .{};
    try std.testing.expectEqual(Heroes.starters(), p.heroes);
    const coil = Heroes.forSpecies(.snake).?;
    try std.testing.expect(p.addHero(coil));
    try std.testing.expect(!p.addHero(coil));
    p.arena_best = 7;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const json = try std.json.Stringify.valueAlloc(arena.allocator(), try p.toDoc(arena.allocator()), .{});
    const back = try fromDoc(try std.json.parseFromSliceLeaky(Doc, arena.allocator(), json, .{}));
    try std.testing.expect(back.hasHero(coil));
    try std.testing.expectEqual(@as(u16, 7), back.arena_best);
    // A save from before heroes: the starters only.
    const old = try fromDoc(.{});
    try std.testing.expectEqual(Heroes.starters(), old.heroes);
    // Up to the flag limit, every flag is kept.
    var many: Progress = .{};
    var name: [12]u8 = undefined;
    for (0..80) |i| many.setFlag(try std.fmt.bufPrint(&name, "flag_{d}", .{i}));
    try std.testing.expect(many.hasFlag("flag_79"));
}
