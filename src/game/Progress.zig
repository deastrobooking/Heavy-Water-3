//! Party progression that saves with the world: suit upgrades bought from the tinker, the armor
//! suits owned for the wardrobe, and story flags set by conversations and world events.
//! Everything is bought with the shared wallet; nothing changes when a purchase fails.
const std = @import("std");
const Market = @import("../city/Market.zig");
const Profile = @import("Profile.zig");
const Player = @import("Player.zig");
const Progress = @This();

pub const Upgrade = enum { fuel_tank, jet_efficiency, sprint_servos, stamina_weave, grapple_reel, salvage_kit };
pub const upgrade_count = @typeInfo(Upgrade).@"enum".fields.len;
pub const max_level = 3;
pub const max_flags = 48;
pub const flag_capacity = 24;
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

levels: [upgrade_count]u8 = @splat(0),
/// Owned clothing, one bit per `Profile.Clothing`; the undersuit and field jacket are free.
suits: u8 = free_suits,
flag_names: [max_flags][flag_capacity]u8 = undefined,
flag_lens: [max_flags]u8 = @splat(0),
flag_count: usize = 0,

pub const free_suits: u8 = bit(.undersuit) | bit(.field_jacket);

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
    suits: []const Profile.Clothing = &.{},
    flags: []const []const u8 = &.{},
};

pub fn toDoc(self: *const Progress, arena: std.mem.Allocator) !Doc {
    var suits: std.ArrayList(Profile.Clothing) = .empty;
    inline for (@typeInfo(Profile.Clothing).@"enum".fields) |f| if (self.owns(@enumFromInt(f.value))) try suits.append(arena, @enumFromInt(f.value));
    const flags = try arena.alloc([]const u8, self.flag_count);
    for (flags, 0..) |*out, i| out.* = try arena.dupe(u8, self.flag(i));
    return .{ .levels = try arena.dupe(u8, &self.levels), .suits = suits.items, .flags = flags };
}

pub fn fromDoc(doc: Doc) error{InvalidProgress}!Progress {
    var result: Progress = .{};
    if (doc.levels.len > upgrade_count) return error.InvalidProgress;
    for (doc.levels) |l| if (l > max_level) return error.InvalidProgress;
    @memcpy(result.levels[0..doc.levels.len], doc.levels);
    for (doc.suits) |c| result.suits |= bit(c);
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
    try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .levels = &.{ 0, 0, 9 } }));
    try std.testing.expectError(error.InvalidProgress, fromDoc(.{ .levels = &(.{0} ** (upgrade_count + 1)) }));
    // Saves made before later upgrades existed list fewer levels; the rest start at 0.
    try std.testing.expectEqual(@as(u8, 2), (try fromDoc(.{ .levels = &.{ 0, 2 } })).level(.jet_efficiency));
    // A save without progress starts fresh with the free suits.
    try std.testing.expectEqual(free_suits, (try fromDoc(.{})).suits);
}
