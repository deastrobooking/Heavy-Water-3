//! The fabricator at the garage turns collectibles (and some scrap) into hover cars, armor suits,
//! armor accents and weapons. Recipes are grouped in tabs; each makes one thing once. The first
//! weapons need no Hive alloy, since alloy only comes from beating Hive units. Nothing changes
//! when a recipe cannot be paid.
const std = @import("std");
const Progress = @import("Progress.zig");
const Profile = @import("Profile.zig");
const Collectibles = @import("Collectibles.zig");
const Market = @import("../city/Market.zig");
const Designs = @import("../vehicle/Designs.zig");
const WeaponKind = @import("../combat/Weapon.zig").WeaponKind;

pub const Tab = enum { vehicles, suits, armor, weapons };
pub const tab_count = @typeInfo(Tab).@"enum".fields.len;
pub const Output = union(enum) { vehicle: Designs.Design, suit: Profile.Clothing, armor: Profile.Armor, weapon: WeaponKind };
/// Pickups by kind (lumen, rotor, alloy; vital cells are never spent) plus scrap.
pub const Cost = struct { lumen: u32 = 0, rotor: u32 = 0, alloy: u32 = 0, scrap: u32 = 0 };
pub const Recipe = struct { tab: Tab, output: Output, cost: Cost, about: []const u8 };
pub const Error = error{ AlreadyMade, NotEnoughLumen, NotEnoughRotors, NotEnoughAlloy, NotEnoughScrap };

pub const recipes = [_]Recipe{
    .{ .tab = .vehicles, .output = .{ .vehicle = .skimmer }, .cost = .{ .lumen = 8, .rotor = 2, .scrap = 30 }, .about = "Balanced wedge hover car with a downforce wing." },
    .{ .tab = .vehicles, .output = .{ .vehicle = .dart }, .cost = .{ .lumen = 6, .rotor = 3, .alloy = 6 }, .about = "Light and fierce, with a huge boost." },
    .{ .tab = .vehicles, .output = .{ .vehicle = .courier }, .cost = .{ .rotor = 4, .alloy = 10, .scrap = 60 }, .about = "Big fans and a high ride for rough ground." },
    .{ .tab = .suits, .output = .{ .suit = .exo_rig }, .cost = .{ .lumen = 6, .alloy = 3 }, .about = "Segmented limb plates for climbers." },
    .{ .tab = .suits, .output = .{ .suit = .hardsuit }, .cost = .{ .lumen = 10, .alloy = 10 }, .about = "Full white plate, cuirass to greaves." },
    .{ .tab = .suits, .output = .{ .suit = .vanguard }, .cost = .{ .rotor = 1, .alloy = 18 }, .about = "The heavy dark set." },
    .{ .tab = .armor, .output = .{ .armor = .sentinel }, .cost = .{ .lumen = 4, .alloy = 5 }, .about = "Shoulder and shin guards with lumen trim." },
    .{ .tab = .armor, .output = .{ .armor = .rootweave }, .cost = .{ .lumen = 12 }, .about = "Living bark weave grown from Arbor sap." },
    .{ .tab = .armor, .output = .{ .armor = .skyguard }, .cost = .{ .rotor = 1, .alloy = 6 }, .about = "Wind-cut plates for high flyers." },
    .{ .tab = .weapons, .output = .{ .weapon = .blaster }, .cost = .{ .lumen = 6, .scrap = 20 }, .about = "Buster blaster. Charges while the trigger is held." },
    .{ .tab = .weapons, .output = .{ .weapon = .beam_saber }, .cost = .{ .lumen = 4, .scrap = 15 }, .about = "Lumen blade: a three-hit combo, stronger while dashing." },
    .{ .tab = .weapons, .output = .{ .weapon = .energy_bow }, .cost = .{ .lumen = 8, .alloy = 6 }, .about = "Draw to power up. Alternate fire shoots a warp arrow." },
    .{ .tab = .weapons, .output = .{ .weapon = .tracking_missile }, .cost = .{ .rotor = 1, .alloy = 10 }, .about = "A salvo of homing missiles at the nearest Hive unit." },
    .{ .tab = .weapons, .output = .{ .weapon = .protective_shield }, .cost = .{ .lumen = 4, .alloy = 8 }, .about = "Hold to block; a timed raise parries." },
    .{ .tab = .weapons, .output = .{ .weapon = .giant_blast }, .cost = .{ .lumen = 10, .rotor = 2, .alloy = 16 }, .about = "Charge a beam that cuts through anything." },
};

pub fn name(output: Output, buffer: []u8) []const u8 {
    const tag = switch (output) {
        .vehicle => |d| return Designs.name(d),
        .suit => |c| @tagName(c),
        .armor => |a| @tagName(a),
        .weapon => |w| @tagName(w),
    };
    const n = @min(buffer.len, tag.len);
    for (buffer[0..n], tag[0..n]) |*o, ch| o.* = if (ch == '_') ' ' else std.ascii.toUpper(ch);
    return buffer[0..n];
}

/// The recipes on a tab, in order (indices into `recipes`).
pub fn onTab(tab: Tab, out: *[recipes.len]u8) []const u8 {
    var n: usize = 0;
    for (recipes, 0..) |r, i| if (r.tab == tab) {
        out[n] = @intCast(i);
        n += 1;
    };
    return out[0..n];
}

pub fn made(p: *const Progress, output: Output) bool {
    return switch (output) {
        .vehicle => |d| p.ownsVehicle(d),
        .suit => |c| p.owns(c),
        .armor => |a| p.ownsArmor(a),
        .weapon => |w| p.ownsWeapon(w),
    };
}

pub fn affordable(p: *const Progress, wallet: Market.Wallet, c: Cost) ?Error {
    if (p.count(.lumen_shard) < c.lumen) return error.NotEnoughLumen;
    if (p.count(.rotor_core) < c.rotor) return error.NotEnoughRotors;
    if (p.count(.hive_alloy) < c.alloy) return error.NotEnoughAlloy;
    if (wallet.scrap < c.scrap) return error.NotEnoughScrap;
    return null;
}

/// Pays for and makes recipe `index`.
pub fn make(p: *Progress, wallet: *Market.Wallet, index: usize) Error!Output {
    const r = recipes[index];
    if (made(p, r.output)) return error.AlreadyMade;
    if (affordable(p, wallet.*, r.cost)) |err| return err;
    p.inventory[@intFromEnum(Collectibles.Kind.lumen_shard)] -= r.cost.lumen;
    p.inventory[@intFromEnum(Collectibles.Kind.rotor_core)] -= r.cost.rotor;
    p.inventory[@intFromEnum(Collectibles.Kind.hive_alloy)] -= r.cost.alloy;
    wallet.scrap -= r.cost.scrap;
    switch (r.output) {
        .vehicle => |d| p.vehicles |= @as(u8, 1) << @intCast(@intFromEnum(d)),
        .suit => |c| p.suits |= Progress.bit(c),
        .armor => |a| p.armors |= Progress.armorBit(a),
        .weapon => |w| p.weapons |= @as(u8, 1) << @intCast(@intFromEnum(w)),
    }
    return r.output;
}

test "recipes pay exactly, make once, and refuse what cannot be paid" {
    var p: Progress = .{};
    var wallet: Market.Wallet = .{ .scrap = 100 };
    var tab: [recipes.len]u8 = undefined;
    const vehicles = onTab(.vehicles, &tab);
    try std.testing.expectEqual(@as(usize, 3), vehicles.len);
    try std.testing.expectError(error.NotEnoughLumen, make(&p, &wallet, vehicles[0]));
    p.inventory = .{ 10, 2, 0, 0 };
    const out = try make(&p, &wallet, vehicles[0]);
    try std.testing.expectEqual(Designs.Design.skimmer, out.vehicle);
    try std.testing.expect(p.ownsVehicle(.skimmer));
    try std.testing.expectEqual([4]u32{ 2, 0, 0, 0 }, p.inventory);
    try std.testing.expectEqual(@as(u32, 70), wallet.scrap);
    try std.testing.expectError(error.AlreadyMade, make(&p, &wallet, vehicles[0]));
    // The first two weapons need no alloy: they are reachable before the first fight.
    var weapons_tab: [recipes.len]u8 = undefined;
    for (onTab(.weapons, &weapons_tab)[0..2]) |i| try std.testing.expectEqual(@as(u32, 0), recipes[i].cost.alloy);
    var buffer: [24]u8 = undefined;
    try std.testing.expectEqualStrings("TRACKING MISSILE", name(.{ .weapon = .tracking_missile }, &buffer));
}
