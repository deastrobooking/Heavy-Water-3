//! Party progression that saves with the world: suit upgrades bought from the tinker, the armor
//! suits owned for the wardrobe, and story flags set by conversations and world events.
//! Everything is bought with the shared wallet; nothing changes when a purchase fails.
const std = @import("std");
const Market = @import("../city/Market.zig");
const Profile = @import("Profile.zig");
const Player = @import("Player.zig");
const Collectibles = @import("Collectibles.zig");
const Designs = @import("../vehicle/Designs.zig");
const WeaponKind = @import("../combat/Weapon.zig").WeaponKind;
const Progress = @This();

pub const Upgrade = enum { fuel_tank, jet_efficiency, sprint_servos, stamina_weave, grapple_reel, salvage_kit };
pub const upgrade_count = @typeInfo(Upgrade).@"enum".fields.len;
pub const max_level = 3;
/// Nests, carriers, caves, conversations and quests each set flags; 48 overflowed once caves
/// arrived (later flags were silently dropped and not saved).
pub const max_flags = 96;
pub const flag_capacity = 24;
pub const Cost = struct { scrap: u32, parts: u32 };
pub const KestrelUpgrade = enum { armor, missile_rack, engine, gun_cooling };
pub const kestrel_upgrade_count = @typeInfo(KestrelUpgrade).@"enum".fields.len;
pub const Paint = enum { ivory, azure, ember, moss };
pub const paint_count = @typeInfo(Paint).@"enum".fields.len;
pub const Error = error{ MaxLevel, NotEnoughScrap, NotEnoughParts, AlreadyOwned, NotOwned };

pub const Info = struct { name: []const u8, summary: []const u8 };
pub const info = [upgrade_count]Info{
    .{ .name = "FUEL TANK", .summary = "Larger heavy-water cell: +30 jet fuel per level." },
    .{ .name = "JET EFFICIENCY", .summary = "Cooler injectors: every jet, glide and dash burns 15% less fuel per level." },
    .{ .name = "SPRINT SERVOS", .summary = "Leg servos: +1.2 m/s sprint speed per level." },
    .{ .name = "STAMINA WEAVE", .summary = "Sap-fibre lining: stamina recovers 40% faster per level." },
    .{ .name = "GRAPPLE REEL", .summary = "Longer line: +32 m grapple reach per level." },
    .{ .name = "SALVAGE KIT", .summary = "Finer tools: one more part from every relic per level." },
};
const base_scrap = [upgrade_count]u32{ 40, 50, 30, 30, 45, 35 };

levels: [upgrade_count]u8 = @splat(0),
/// Owned clothing, one bit per `Profile.Clothing`; the undersuit and field jacket are free.
suits: u8 = free_suits,
/// Collected pickups held (vital cells count as installed health upgrades).
inventory: [Collectibles.kind_count]u32 = @splat(0),
/// World pickups already collected, by ID.
picked: Collectibles.Picked = .initEmpty(),
/// Fabricated hover car designs, armor accents and weapons (bit per enum value).
vehicles: u8 = 0,
armors: u8 = free_armors,
weapons: u16 = 0,
/// Installed weapon tiers beyond Mk I, indexed by `WeaponKind` (0..2).
weapon_upgrades: [@typeInfo(WeaponKind).@"enum".fields.len]u8 = @splat(0),
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

pub const free_suits: u8 = bit(.undersuit) | bit(.field_jacket);
pub const free_armors: u8 = armorBit(.none) | armorBit(.scout);
pub const health_per_cell: f32 = 20;

pub fn armorBit(a: Profile.Armor) u8 {
    return @as(u8, 1) << @intCast(@intFromEnum(a));
}

pub fn ownsArmor(self: *const Progress, a: Profile.Armor) bool {
    return self.armors & armorBit(a) != 0;
}
pub fn ownsVehicle(self: *const Progress, d: Designs.Design) bool {
    return self.vehicles & (@as(u8, 1) << @intCast(@intFromEnum(d))) != 0;
}
pub fn ownsWeapon(self: *const Progress, w: WeaponKind) bool {
    return self.weapons & (@as(u16, 1) << @intCast(@intFromEnum(w))) != 0;
}
pub fn weaponLevel(self: *const Progress, w: WeaponKind) u8 {
    return 1 + self.weapon_upgrades[@intFromEnum(w)];
}
pub fn count(self: *const Progress, k: Collectibles.Kind) u32 {
    return self.inventory[@intFromEnum(k)];
}
/// Maximum health with every collected vital cell installed.
pub fn maxHealth(self: *const Progress) f32 {
    return 100 + health_per_cell * @as(f32, @floatFromInt(self.count(.vital_cell)));
}

pub fn bit(c: Profile.Clothing) u8 {
    return @as(u8, 1) << @intCast(@intFromEnum(c));
}

pub fn level(self: *const Progress, u: Upgrade) u8 {
    return self.levels[@intFromEnum(u)];
}

/// Price of the next level of `u` (scrap rises 1×, 2×, 3.5×; later levels also take parts).
pub fn cost(self: *const Progress, u: Upgrade) Cost {
    const l = self.level(u);
    const factor = [max_level]u32{ 10, 20, 35 };
    return .{ .scrap = base_scrap[@intFromEnum(u)] * factor[@min(l, max_level - 1)] / 10, .parts = @as(u32, @min(l, max_level - 1)) * 2 };
}

fn pay(wallet: *Market.Wallet, price: Cost) Error!void {
    if (wallet.scrap < price.scrap) return error.NotEnoughScrap;
    if (wallet.parts < price.parts) return error.NotEnoughParts;
    wallet.scrap -= price.scrap;
    wallet.parts -= price.parts;
}

pub fn buy(self: *Progress, u: Upgrade, wallet: *Market.Wallet) Error!void {
    if (self.level(u) >= max_level) return error.MaxLevel;
    try pay(wallet, self.cost(u));
    self.levels[@intFromEnum(u)] += 1;
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
    try pay(wallet, self.kestrelUpgradeCost(upgrade));
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
    try pay(wallet, kestrelPaintCost(paint));
    self.kestrel_paints |= @as(u8, 1) << @intCast(@intFromEnum(paint));
    self.kestrel_paint = paint;
}

pub fn selectKestrelPaint(self: *Progress, paint: Paint) Error!void {
    if (!self.ownsKestrelPaint(paint)) return error.NotOwned;
    self.kestrel_paint = paint;
}

/// The suit tuning every player wears.
pub fn suit(self: *const Progress) Player.Suit {
    const l = struct {
        fn f(p: *const Progress, u: Upgrade) f32 {
            return @floatFromInt(p.level(u));
        }
    }.f;
    return .{
        .fuel_max = 100 + 30 * l(self, .fuel_tank),
        .burn = 1 - 0.15 * l(self, .jet_efficiency),
        .sprint = Player.sprint_speed + 1.2 * l(self, .sprint_servos),
        .stamina_regen = 20 * (1 + 0.4 * l(self, .stamina_weave)),
        .grapple_range = 96 + 32 * l(self, .grapple_reel),
    };
}

pub fn partsPerSalvage(self: *const Progress) u32 {
    return 1 + @as(u32, self.level(.salvage_kit));
}

/// Wardrobe price of a clothing type (free ones cost nothing).
pub fn suitPrice(c: Profile.Clothing) Cost {
    return switch (c) {
        .undersuit, .field_jacket => .{ .scrap = 0, .parts = 0 },
        .exo_rig => .{ .scrap = 60, .parts = 2 },
        .hardsuit => .{ .scrap = 150, .parts = 5 },
        .vanguard => .{ .scrap = 260, .parts = 8 },
    };
}

pub fn owns(self: *const Progress, c: Profile.Clothing) bool {
    return self.suits & bit(c) != 0;
}

pub fn buySuit(self: *Progress, c: Profile.Clothing, wallet: *Market.Wallet) Error!void {
    if (self.owns(c)) return error.AlreadyOwned;
    try pay(wallet, suitPrice(c));
    self.suits |= bit(c);
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

/// JSON shape stored in saves; older saves without it load as a fresh start.
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
};

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
    var suits: std.ArrayList(Profile.Clothing) = .empty;
    inline for (@typeInfo(Profile.Clothing).@"enum".fields) |f| if (self.owns(@enumFromInt(f.value))) try suits.append(arena, @enumFromInt(f.value));
    const flags = try arena.alloc([]const u8, self.flag_count);
    for (flags, 0..) |*out, i| out.* = try arena.dupe(u8, self.flag(i));
    var picked: std.ArrayList(u16) = .empty;
    var it = self.picked.iterator(.{});
    while (it.next()) |i| try picked.append(arena, @intCast(i));
    var vehicles: std.ArrayList(Designs.Design) = .empty;
    inline for (@typeInfo(Designs.Design).@"enum".fields) |f| if (self.ownsVehicle(@enumFromInt(f.value))) try vehicles.append(arena, @enumFromInt(f.value));
    var armors: std.ArrayList(Profile.Armor) = .empty;
    inline for (@typeInfo(Profile.Armor).@"enum".fields) |f| if (self.ownsArmor(@enumFromInt(f.value))) try armors.append(arena, @enumFromInt(f.value));
    var weapons: std.ArrayList(WeaponKind) = .empty;
    inline for (@typeInfo(WeaponKind).@"enum".fields) |f| if (self.ownsWeapon(@enumFromInt(f.value))) try weapons.append(arena, @enumFromInt(f.value));
    const Heroes = @import("Heroes.zig");
    var heroes: std.ArrayList([]const u8) = .empty;
    for (Heroes.roster, 0..) |h, i| if (self.hasHero(@intCast(i))) try heroes.append(arena, h.name);
    return .{ .heroes = heroes.items, .arena_best = self.arena_best, .levels = try arena.dupe(u8, &self.levels), .suits = suits.items, .flags = flags, .inventory = try arena.dupe(u32, &self.inventory), .picked = picked.items, .vehicles = vehicles.items, .armors = armors.items, .weapons = weapons.items, .weapon_upgrades = try arena.dupe(u8, &self.weapon_upgrades), .fighter = self.fighter, .kestrel_levels = try arena.dupe(u8, &self.kestrel_levels), .kestrel_paints = self.kestrel_paints, .kestrel_paint = self.kestrel_paint };
}

pub fn fromDoc(doc: Doc) error{InvalidProgress}!Progress {
    var result: Progress = .{};
    if (doc.levels.len > upgrade_count) return error.InvalidProgress;
    for (doc.levels) |l| if (l > max_level) return error.InvalidProgress;
    @memcpy(result.levels[0..doc.levels.len], doc.levels);
    for (doc.suits) |c| result.suits |= bit(c);
    if (doc.inventory.len > Collectibles.kind_count) return error.InvalidProgress;
    @memcpy(result.inventory[0..doc.inventory.len], doc.inventory);
    for (doc.picked) |i| {
        if (i >= Collectibles.max_items) return error.InvalidProgress;
        result.picked.set(i);
    }
    for (doc.vehicles) |d| result.vehicles |= @as(u8, 1) << @intCast(@intFromEnum(d));
    for (doc.armors) |a| result.armors |= armorBit(a);
    for (doc.weapons) |w| result.weapons |= @as(u16, 1) << @intCast(@intFromEnum(w));
    if (doc.weapon_upgrades.len > result.weapon_upgrades.len) return error.InvalidProgress;
    for (doc.weapon_upgrades, 0..) |tier, i| {
        if (tier > 2) return error.InvalidProgress;
        if (tier > 0 and result.weapons & (@as(u16, 1) << @intCast(i)) == 0) return error.InvalidProgress;
    }
    @memcpy(result.weapon_upgrades[0..doc.weapon_upgrades.len], doc.weapon_upgrades);
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

test "upgrades charge the wallet, cap at max level, and tune the suit" {
    var p: Progress = .{};
    var wallet: Market.Wallet = .{ .scrap = 39 };
    try std.testing.expectError(error.NotEnoughScrap, p.buy(.fuel_tank, &wallet));
    try std.testing.expectEqual(@as(u32, 39), wallet.scrap);
    wallet.scrap = 1000;
    try p.buy(.fuel_tank, &wallet);
    try std.testing.expectEqual(@as(u32, 960), wallet.scrap);
    // Level 2 also takes parts; nothing is charged when they are missing.
    try std.testing.expectEqual(Cost{ .scrap = 80, .parts = 2 }, p.cost(.fuel_tank));
    try std.testing.expectError(error.NotEnoughParts, p.buy(.fuel_tank, &wallet));
    try std.testing.expectEqual(@as(u32, 960), wallet.scrap);
    wallet.parts = 10;
    try p.buy(.fuel_tank, &wallet);
    try p.buy(.fuel_tank, &wallet);
    try std.testing.expectError(error.MaxLevel, p.buy(.fuel_tank, &wallet));
    try std.testing.expectApproxEqAbs(@as(f32, 190), p.suit().fuel_max, 1e-4);
    try p.buy(.jet_efficiency, &wallet);
    try std.testing.expectApproxEqAbs(@as(f32, 0.85), p.suit().burn, 1e-4);
    try std.testing.expectEqual(@as(u32, 1), p.partsPerSalvage());
}

test "suits are bought once, and progress round-trips through its save shape" {
    var p: Progress = .{};
    var wallet: Market.Wallet = .{ .scrap = 100, .parts = 3 };
    try std.testing.expect(p.owns(.field_jacket) and !p.owns(.exo_rig));
    try std.testing.expectError(error.AlreadyOwned, p.buySuit(.undersuit, &wallet));
    try std.testing.expectError(error.NotEnoughScrap, p.buySuit(.hardsuit, &wallet));
    try p.buySuit(.exo_rig, &wallet);
    try std.testing.expectEqual(Market.Wallet{ .scrap = 40, .parts = 1 }, wallet);
    p.setFlag("met_maro");
    p.setFlag("met_maro");
    p.setFlag("x" ** 30);
    try std.testing.expectEqual(@as(usize, 1), p.flag_count);
    p.levels[4] = 2;

    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const doc = try p.toDoc(arena.allocator());
    const json = try std.json.Stringify.valueAlloc(arena.allocator(), doc, .{});
    const parsed = try std.json.parseFromSliceLeaky(Doc, arena.allocator(), json, .{});
    const back = try fromDoc(parsed);
    try std.testing.expect(back.owns(.exo_rig) and back.hasFlag("met_maro") and back.level(.grapple_reel) == 2);
    {
        var more: Progress = .{};
        more.inventory = .{ 5, 1, 7, 2 };
        more.picked.set(3);
        more.picked.set(90);
        more.vehicles = 0b101;
        more.weapons = 0b11;
        more.weapon_upgrades[@intFromEnum(WeaponKind.beam_saber)] = 2;
        more.armors |= armorBit(.skyguard);
        const d2 = try more.toDoc(arena.allocator());
        const j2 = try std.json.Stringify.valueAlloc(arena.allocator(), d2, .{});
        const r2 = try fromDoc(try std.json.parseFromSliceLeaky(Doc, arena.allocator(), j2, .{}));
        try std.testing.expectEqual(more.inventory, r2.inventory);
        try std.testing.expectEqual(more.weapon_upgrades, r2.weapon_upgrades);
        try std.testing.expect(r2.picked.isSet(90) and r2.picked.isSet(3) and r2.picked.count() == 2);
        try std.testing.expect(r2.ownsVehicle(.courier) and !r2.ownsVehicle(.dart) and r2.ownsArmor(.skyguard) and r2.ownsArmor(.scout));
        try std.testing.expectEqual(@as(f32, 140), r2.maxHealth());
        try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .picked = &.{999} }));
    }
    try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .levels = &.{ 0, 0, 9 } }));
    try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .levels = &(.{0} ** (upgrade_count + 1)) }));
    try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .weapon_upgrades = &.{3} }));
    try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .weapon_upgrades = &.{1} }));
    // Saves made before later upgrades existed list fewer levels; the rest start at 0.
    try std.testing.expectEqual(@as(u8, 2), (try fromDoc(.{ .levels = &.{ 0, 2 } })).level(.jet_efficiency));
    // A save without progress starts fresh with the free suits.
    try std.testing.expectEqual(free_suits, (try fromDoc(.{})).suits);
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
