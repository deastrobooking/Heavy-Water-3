//! One player's own progression, saved with them: their wallet (scrap, parts, build kits), suit
//! upgrades bought from the tinker, the suits, armor accents and weapons they own (and weapon
//! tiers installed), the pickups they hold (vital cells raise their health), and the bio-synth
//! pets they freed with each pet's experience. In co-op every player has a kit of their own; the
//! team shares only the world and its story (`Progress`). Nothing changes when a purchase fails.
const std = @import("std");
const Pets = @import("Pets.zig");
const Market = @import("../city/Market.zig");
const Profile = @import("Profile.zig");
const Player = @import("Player.zig");
const Collectibles = @import("Collectibles.zig");
const WeaponKind = @import("../combat/Weapon.zig").WeaponKind;
const Kit = @This();

pub const Upgrade = enum { fuel_tank, jet_efficiency, sprint_servos, stamina_weave, grapple_reel, salvage_kit };
pub const upgrade_count = @typeInfo(Upgrade).@"enum".fields.len;
pub const max_level = 3;
pub const Cost = struct { scrap: u32, parts: u32 };
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

pub const starter_weapons: u16 = (1 << @intFromEnum(WeaponKind.machine_gun)) | (1 << @intFromEnum(WeaponKind.beam_saber));
pub const free_suits: u8 = bit(.undersuit) | bit(.field_jacket);
pub const free_armors: u8 = armorBit(.none) | armorBit(.scout);
pub const health_per_cell: f32 = 20;

wallet: Market.Wallet = .{},
levels: [upgrade_count]u8 = @splat(0),
/// Owned clothing, one bit per `Profile.Clothing`; the undersuit and field jacket are free.
suits: u8 = free_suits,
/// Collected pickups held (vital cells count as installed health upgrades).
inventory: [Collectibles.kind_count]u32 = @splat(0),
/// Armor accents and weapons owned (bit per enum value).
armors: u8 = free_armors,
weapons: u16 = starter_weapons,
/// Installed weapon tiers beyond Mk I, indexed by `WeaponKind`.
weapon_upgrades: [@typeInfo(WeaponKind).@"enum".fields.len]u8 = @splat(0),
/// Bio-synth pets freed (bit per `Pets.Species`), each one's experience, and the one out.
pets: u8 = 0,
pet_xp: [Pets.count]u32 = @splat(0),
pet_active: ?Pets.Species = null,

pub fn bit(c: Profile.Clothing) u8 {
    return @as(u8, 1) << @intCast(@intFromEnum(c));
}

pub fn armorBit(a: Profile.Armor) u8 {
    return @as(u8, 1) << @intCast(@intFromEnum(a));
}

fn petBit(s: Pets.Species) u8 {
    return @as(u8, 1) << @as(u3, @intCast(@intFromEnum(s)));
}

pub fn ownsArmor(self: *const Kit, a: Profile.Armor) bool {
    return self.armors & armorBit(a) != 0;
}
pub fn ownsWeapon(self: *const Kit, w: WeaponKind) bool {
    return self.weapons & (@as(u16, 1) << @intCast(@intFromEnum(w))) != 0;
}
pub fn weaponLevel(self: *const Kit, w: WeaponKind) u8 {
    return 1 + self.weapon_upgrades[@intFromEnum(w)];
}
pub fn count(self: *const Kit, k: Collectibles.Kind) u32 {
    return self.inventory[@intFromEnum(k)];
}
/// Maximum health with every collected vital cell installed.
pub fn maxHealth(self: *const Kit) f32 {
    return 100 + health_per_cell * @as(f32, @floatFromInt(self.count(.vital_cell)));
}

pub fn level(self: *const Kit, u: Upgrade) u8 {
    return self.levels[@intFromEnum(u)];
}

/// Price of the next level of `u` (scrap rises 1×, 2×, 3.5×; later levels also take parts).
pub fn cost(self: *const Kit, u: Upgrade) Cost {
    const l = self.level(u);
    const factor = [max_level]u32{ 10, 20, 35 };
    return .{ .scrap = base_scrap[@intFromEnum(u)] * factor[@min(l, max_level - 1)] / 10, .parts = @as(u32, @min(l, max_level - 1)) * 2 };
}

pub fn pay(wallet: *Market.Wallet, price: Cost) Error!void {
    if (wallet.scrap < price.scrap) return error.NotEnoughScrap;
    if (wallet.parts < price.parts) return error.NotEnoughParts;
    wallet.scrap -= price.scrap;
    wallet.parts -= price.parts;
}

pub fn buy(self: *Kit, u: Upgrade) Error!void {
    if (self.level(u) >= max_level) return error.MaxLevel;
    try pay(&self.wallet, self.cost(u));
    self.levels[@intFromEnum(u)] += 1;
}

/// The suit tuning this player wears.
pub fn suit(self: *const Kit) Player.Suit {
    const l = struct {
        fn f(k: *const Kit, u: Upgrade) f32 {
            return @floatFromInt(k.level(u));
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

pub fn partsPerSalvage(self: *const Kit) u32 {
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

pub fn owns(self: *const Kit, c: Profile.Clothing) bool {
    return self.suits & bit(c) != 0;
}

pub fn buySuit(self: *Kit, c: Profile.Clothing) Error!void {
    if (self.owns(c)) return error.AlreadyOwned;
    try pay(&self.wallet, suitPrice(c));
    self.suits |= bit(c);
}

pub fn hasPet(self: *const Kit, s: Pets.Species) bool {
    return self.pets & petBit(s) != 0;
}

/// A pet is freed (and comes out); false if it already was.
pub fn freePet(self: *Kit, s: Pets.Species) bool {
    const fresh = !self.hasPet(s);
    self.pets |= petBit(s);
    self.pet_active = s;
    return fresh;
}

/// The next freed pet after the active one (wrapping), or null with none freed.
pub fn nextPet(self: *const Kit) ?Pets.Species {
    const from: usize = if (self.pet_active) |a| @intFromEnum(a) + 1 else 0;
    for (0..Pets.count) |k| {
        const s: Pets.Species = @enumFromInt((from + k) % Pets.count);
        if (self.hasPet(s)) return s;
    }
    return null;
}

pub fn petLevel(self: *const Kit, s: Pets.Species) u8 {
    return Pets.levelFor(self.pet_xp[@intFromEnum(s)]);
}

/// JSON shape stored in saves and ranger files.
pub const Doc = struct {
    wallet: Market.Wallet = .{},
    /// One level per upgrade, in `Upgrade` order; shorter in saves from before an upgrade existed.
    levels: []const u8 = &.{},
    /// Held pickups in `Collectibles.Kind` order.
    inventory: []const u32 = &.{},
    armors: []const Profile.Armor = &.{},
    weapons: []const WeaponKind = &.{},
    weapon_upgrades: []const u8 = &.{},
    suits: []const Profile.Clothing = &.{},
    /// Freed pets by name with their experience, and the active pet's name.
    pets: []const PetDoc = &.{},
    pet_active: ?[]const u8 = null,
};

pub const PetDoc = struct { name: []const u8, xp: u32 = 0 };

pub fn toDoc(self: *const Kit, arena: std.mem.Allocator) !Doc {
    var suits: std.ArrayList(Profile.Clothing) = .empty;
    inline for (@typeInfo(Profile.Clothing).@"enum".fields) |f| if (self.owns(@enumFromInt(f.value))) try suits.append(arena, @enumFromInt(f.value));
    var armors: std.ArrayList(Profile.Armor) = .empty;
    inline for (@typeInfo(Profile.Armor).@"enum".fields) |f| if (self.ownsArmor(@enumFromInt(f.value))) try armors.append(arena, @enumFromInt(f.value));
    var weapons: std.ArrayList(WeaponKind) = .empty;
    inline for (@typeInfo(WeaponKind).@"enum".fields) |f| if (self.ownsWeapon(@enumFromInt(f.value))) try weapons.append(arena, @enumFromInt(f.value));
    var pets: std.ArrayList(PetDoc) = .empty;
    for (std.enums.values(Pets.Species)) |sp| if (self.hasPet(sp)) try pets.append(arena, .{ .name = Pets.info(sp).name, .xp = self.pet_xp[@intFromEnum(sp)] });
    return .{
        .wallet = self.wallet,
        .levels = try arena.dupe(u8, &self.levels),
        .inventory = try arena.dupe(u32, &self.inventory),
        .armors = armors.items,
        .weapons = weapons.items,
        .weapon_upgrades = try arena.dupe(u8, &self.weapon_upgrades),
        .suits = suits.items,
        .pets = pets.items,
        .pet_active = if (self.pet_active) |a| Pets.info(a).name else null,
    };
}

fn petNamed(name: []const u8) ?Pets.Species {
    for (std.enums.values(Pets.Species)) |sp| if (std.mem.eql(u8, Pets.info(sp).name, name)) return sp;
    return null;
}

pub fn fromDoc(doc: Doc) error{InvalidKit}!Kit {
    var result: Kit = .{ .wallet = doc.wallet };
    if (doc.levels.len > upgrade_count) return error.InvalidKit;
    for (doc.levels) |l| if (l > max_level) return error.InvalidKit;
    @memcpy(result.levels[0..doc.levels.len], doc.levels);
    for (doc.suits) |c| result.suits |= bit(c);
    if (doc.inventory.len > Collectibles.kind_count) return error.InvalidKit;
    @memcpy(result.inventory[0..doc.inventory.len], doc.inventory);
    for (doc.armors) |a| result.armors |= armorBit(a);
    for (doc.weapons) |w| result.weapons |= @as(u16, 1) << @intCast(@intFromEnum(w));
    if (doc.weapon_upgrades.len > result.weapon_upgrades.len) return error.InvalidKit;
    for (doc.weapon_upgrades, 0..) |tier, i| {
        if (tier > 2) return error.InvalidKit;
        if (tier > 0 and result.weapons & (@as(u16, 1) << @intCast(i)) == 0) return error.InvalidKit;
    }
    @memcpy(result.weapon_upgrades[0..doc.weapon_upgrades.len], doc.weapon_upgrades);
    for (doc.pets) |pet| {
        const sp = petNamed(pet.name) orelse return error.InvalidKit;
        result.pets |= petBit(sp);
        result.pet_xp[@intFromEnum(sp)] = pet.xp;
    }
    if (doc.pet_active) |name| {
        const sp = petNamed(name) orelse return error.InvalidKit;
        if (!result.hasPet(sp)) return error.InvalidKit;
        result.pet_active = sp;
    }
    return result;
}

test "upgrades charge the kit's wallet, cap at max level, and tune the suit" {
    var k: Kit = .{ .wallet = .{ .scrap = 39 } };
    try std.testing.expectError(error.NotEnoughScrap, k.buy(.fuel_tank));
    try std.testing.expectEqual(@as(u32, 39), k.wallet.scrap);
    k.wallet.scrap = 1000;
    try k.buy(.fuel_tank);
    try std.testing.expectEqual(@as(u32, 960), k.wallet.scrap);
    // Level 2 also takes parts; nothing is charged when they are missing.
    try std.testing.expectEqual(Cost{ .scrap = 80, .parts = 2 }, k.cost(.fuel_tank));
    try std.testing.expectError(error.NotEnoughParts, k.buy(.fuel_tank));
    try std.testing.expectEqual(@as(u32, 960), k.wallet.scrap);
    k.wallet.parts = 10;
    try k.buy(.fuel_tank);
    try k.buy(.fuel_tank);
    try std.testing.expectError(error.MaxLevel, k.buy(.fuel_tank));
    try std.testing.expectApproxEqAbs(@as(f32, 190), k.suit().fuel_max, 1e-4);
    try k.buy(.jet_efficiency);
    try std.testing.expectApproxEqAbs(@as(f32, 0.85), k.suit().burn, 1e-4);
    try std.testing.expectEqual(@as(u32, 1), k.partsPerSalvage());
}

test "suits are bought once, and a kit round-trips through its save shape" {
    var k: Kit = .{ .wallet = .{ .scrap = 100, .parts = 3 } };
    try std.testing.expect(k.owns(.field_jacket) and !k.owns(.exo_rig));
    try std.testing.expectError(error.AlreadyOwned, k.buySuit(.undersuit));
    try std.testing.expectError(error.NotEnoughScrap, k.buySuit(.hardsuit));
    try k.buySuit(.exo_rig);
    try std.testing.expectEqual(Market.Wallet{ .scrap = 40, .parts = 1 }, k.wallet);
    k.levels[4] = 2;
    k.inventory = .{ 5, 1, 7, 2 };
    k.weapons = 0b11;
    k.weapon_upgrades[@intFromEnum(WeaponKind.beam_saber)] = 2;
    k.armors |= armorBit(.skyguard);
    _ = k.freePet(.falcon);
    k.pet_xp[@intFromEnum(Pets.Species.falcon)] = 200;

    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const json = try std.json.Stringify.valueAlloc(arena.allocator(), try k.toDoc(arena.allocator()), .{});
    const back = try fromDoc(try std.json.parseFromSliceLeaky(Doc, arena.allocator(), json, .{}));
    try std.testing.expectEqual(k.wallet, back.wallet);
    try std.testing.expect(back.owns(.exo_rig) and back.level(.grapple_reel) == 2);
    try std.testing.expectEqual(k.inventory, back.inventory);
    try std.testing.expectEqual(k.weapon_upgrades, back.weapon_upgrades);
    try std.testing.expect(back.ownsArmor(.skyguard) and back.ownsArmor(.scout));
    try std.testing.expectEqual(@as(f32, 140), back.maxHealth());
    try std.testing.expectEqual(@as(u8, 3), back.petLevel(.falcon));
    try std.testing.expectEqual(Pets.Species.falcon, back.pet_active.?);
    try std.testing.expectError(error.InvalidKit, fromDoc(.{ .levels = &.{ 0, 0, 9 } }));
    try std.testing.expectError(error.InvalidKit, fromDoc(.{ .levels = &(.{0} ** (upgrade_count + 1)) }));
    try std.testing.expectError(error.InvalidKit, fromDoc(.{ .weapon_upgrades = &.{3} }));
    try std.testing.expectEqual(@as(u8, 2), (try fromDoc(.{ .weapon_upgrades = &.{1} })).weaponLevel(.beam_saber));
    try std.testing.expectEqual(@as(u8, 2), (try fromDoc(.{ .levels = &.{ 0, 2 } })).level(.jet_efficiency));
    try std.testing.expectEqual(free_suits, (try fromDoc(.{})).suits);
    // An unknown pet, or an active pet never freed, is rejected.
    try std.testing.expectError(error.InvalidKit, fromDoc(.{ .pets = &.{.{ .name = "NOPE" }} }));
    try std.testing.expectError(error.InvalidKit, fromDoc(.{ .pet_active = "GARU" }));
}

test "a new kit owns level one rapid shot and saber but not missiles; pets cycle" {
    const k: Kit = .{};
    try std.testing.expect(k.ownsWeapon(.machine_gun) and k.ownsWeapon(.beam_saber));
    try std.testing.expectEqual(@as(u8, 1), k.weaponLevel(.machine_gun));
    try std.testing.expect(!k.ownsWeapon(.tracking_missile));
    var p: Kit = .{};
    try std.testing.expect(p.nextPet() == null);
    try std.testing.expect(p.freePet(.falcon));
    try std.testing.expect(!p.freePet(.falcon));
    try std.testing.expect(p.freePet(.hound));
    try std.testing.expectEqual(Pets.Species.hound, p.pet_active.?);
    try std.testing.expectEqual(Pets.Species.falcon, p.nextPet().?);
}
