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

pub const Tab = enum { vehicles, suits, armor, weapons, aircraft };
pub const tab_count = @typeInfo(Tab).@"enum".fields.len;
pub const Output = union(enum) { vehicle: Designs.Design, fighter, suit: Profile.Clothing, armor: Profile.Armor, weapon: WeaponKind, kestrel_upgrade: Progress.KestrelUpgrade, kestrel_paint: Progress.Paint };
/// Pickups by kind (lumen, rotor, alloy; vital cells are never spent) plus scrap.
pub const Cost = struct { lumen: u32 = 0, rotor: u32 = 0, alloy: u32 = 0, scrap: u32 = 0 };
pub const Recipe = struct { tab: Tab, output: Output, cost: Cost, about: []const u8 };
pub const Error = error{ AlreadyMade, NotEnoughLumen, NotEnoughRotors, NotEnoughAlloy, NotEnoughScrap, NotEnoughParts, MaxLevel, AlreadyOwned, NotOwned, NoFighter, NoBlueprint };

pub const recipes = [_]Recipe{
    .{ .tab = .vehicles, .output = .{ .vehicle = .skimmer }, .cost = .{ .lumen = 8, .rotor = 2, .scrap = 30 }, .about = "Balanced wedge hover car with a downforce wing." },
    .{ .tab = .vehicles, .output = .{ .vehicle = .dart }, .cost = .{ .lumen = 6, .rotor = 3, .alloy = 6 }, .about = "Light and fierce, with a huge boost." },
    .{ .tab = .vehicles, .output = .{ .vehicle = .courier }, .cost = .{ .rotor = 4, .alloy = 10, .scrap = 60 }, .about = "Big fans and a high ride for rough ground." },
    .{ .tab = .vehicles, .output = .fighter, .cost = .{ .lumen = 12, .rotor = 5, .alloy = 14, .scrap = 80 }, .about = "Kestrel VTOL fighter: cannons and missiles to take the war to the Hive's skies." },
    .{ .tab = .suits, .output = .{ .suit = .exo_rig }, .cost = .{ .lumen = 6, .alloy = 3 }, .about = "Segmented limb plates for climbers." },
    .{ .tab = .suits, .output = .{ .suit = .hardsuit }, .cost = .{ .lumen = 10, .alloy = 10 }, .about = "Full white plate, cuirass to greaves." },
    .{ .tab = .suits, .output = .{ .suit = .vanguard }, .cost = .{ .rotor = 1, .alloy = 18 }, .about = "The heavy dark set." },
    .{ .tab = .armor, .output = .{ .armor = .sentinel }, .cost = .{ .lumen = 4, .alloy = 5 }, .about = "Shoulder and shin guards with lumen trim." },
    .{ .tab = .armor, .output = .{ .armor = .rootweave }, .cost = .{ .lumen = 12 }, .about = "Living bark weave grown from Arbor sap." },
    .{ .tab = .armor, .output = .{ .armor = .skyguard }, .cost = .{ .rotor = 1, .alloy = 6 }, .about = "Wind-cut plates for high flyers." },
    .{ .tab = .weapons, .output = .{ .weapon = .blaster }, .cost = .{ .lumen = 6, .scrap = 20 }, .about = "Buster blaster. Charges while the trigger is held." },
    .{ .tab = .weapons, .output = .{ .weapon = .beam_saber }, .cost = .{ .lumen = 4, .scrap = 15 }, .about = "Lumen blade: a three-cut combo, a dash cut, a held wave cut; alternate guards and parries." },
    .{ .tab = .weapons, .output = .{ .weapon = .energy_bow }, .cost = .{ .lumen = 8, .alloy = 6 }, .about = "Draw to power up. Alternate fire shoots a warp arrow." },
    .{ .tab = .weapons, .output = .{ .weapon = .tracking_missile }, .cost = .{ .rotor = 1, .alloy = 10 }, .about = "A salvo of homing missiles at the nearest Hive unit." },
    .{ .tab = .weapons, .output = .{ .weapon = .protective_shield }, .cost = .{ .lumen = 4, .alloy = 8 }, .about = "Hold to block; a timed raise parries." },
    .{ .tab = .weapons, .output = .{ .weapon = .machine_gun }, .cost = .{ .lumen = 6, .scrap = 30, .alloy = 4 }, .about = "Fourteen bolts a second. Spread grows with heat; it locks when it overheats." },
    .{ .tab = .weapons, .output = .{ .weapon = .heavy_rifle }, .cost = .{ .lumen = 8, .alloy = 10 }, .about = "Heavy bolts that pierce two. Hold the alternate to charge one through four." },
    .{ .tab = .weapons, .output = .{ .weapon = .sniper_rifle }, .cost = .{ .lumen = 12, .rotor = 1, .alloy = 8 }, .about = "Instant beam that pierces one. The alternate scopes; a steady scope hits harder." },
    .{ .tab = .weapons, .output = .{ .weapon = .energy_bazooka }, .cost = .{ .lumen = 10, .rotor = 2, .alloy = 12 }, .about = "Arcing plasma orb that bursts, stuns and throws. The alternate detonates it." },
    .{ .tab = .weapons, .output = .{ .weapon = .giant_blast }, .cost = .{ .lumen = 10, .rotor = 2, .alloy = 16 }, .about = "Charge a beam that cuts through anything." },
    .{ .tab = .aircraft, .output = .{ .kestrel_upgrade = .armor }, .cost = .{}, .about = "Layered plating increases the Kestrel's maximum hull." },
    .{ .tab = .aircraft, .output = .{ .kestrel_upgrade = .missile_rack }, .cost = .{}, .about = "Expand the rack by two missiles per level." },
    .{ .tab = .aircraft, .output = .{ .kestrel_upgrade = .engine }, .cost = .{}, .about = "Increase engine and afterburner thrust." },
    .{ .tab = .aircraft, .output = .{ .kestrel_upgrade = .gun_cooling }, .cost = .{}, .about = "Cool the cannon assembly faster and delay overheat." },
    .{ .tab = .aircraft, .output = .{ .kestrel_paint = .ivory }, .cost = .{}, .about = "Standard ceramic-white service finish." },
    .{ .tab = .aircraft, .output = .{ .kestrel_paint = .azure }, .cost = .{}, .about = "Deep ocean-blue flightline finish." },
    .{ .tab = .aircraft, .output = .{ .kestrel_paint = .ember }, .cost = .{}, .about = "High-visibility ember-orange finish." },
    .{ .tab = .aircraft, .output = .{ .kestrel_paint = .moss }, .cost = .{}, .about = "Arbor-green field camouflage." },
};

pub fn name(output: Output, buffer: []u8) []const u8 {
    const tag = switch (output) {
        .vehicle => |d| return Designs.name(d),
        .fighter => return "KESTREL FIGHTER",
        .suit => |c| @tagName(c),
        .armor => |a| @tagName(a),
        .weapon => |w| @tagName(w),
        .kestrel_upgrade => |u| return switch (u) {
            .armor => "KESTREL ARMOR",
            .missile_rack => "MISSILE RACK",
            .engine => "ENGINE",
            .gun_cooling => "GUN COOLING",
        },
        .kestrel_paint => |p| return switch (p) {
            .ivory => "IVORY PAINT",
            .azure => "AZURE PAINT",
            .ember => "EMBER PAINT",
            .moss => "MOSS PAINT",
        },
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
        .fighter => p.fighter,
        .suit => |c| p.owns(c),
        .armor => |a| p.ownsArmor(a),
        .weapon => |w| p.ownsWeapon(w),
        .kestrel_upgrade => |u| p.kestrelLevel(u) >= Progress.max_level,
        .kestrel_paint => |paint| p.ownsKestrelPaint(paint),
    };
}

pub fn status(p: *const Progress, output: Output) ?[]const u8 {
    return switch (output) {
        .fighter => if (p.fighter) "MADE" else if (!p.hasFlag("kestrel_blueprint")) "BLUEPRINT REQUIRED" else null,
        .kestrel_upgrade, .kestrel_paint => if (!p.fighter) "FABRICATE KESTREL FIRST" else switch (output) {
            .kestrel_upgrade => |u| if (p.kestrelLevel(u) >= Progress.max_level) "MAX LEVEL" else null,
            .kestrel_paint => |paint| if (p.ownsKestrelPaint(paint)) (if (p.kestrel_paint == paint) "EQUIPPED" else "OWNED") else null,
            else => unreachable,
        },
        else => if (made(p, output)) "MADE" else null,
    };
}

pub fn progressCost(p: *const Progress, output: Output) ?Progress.Cost {
    return switch (output) {
        .kestrel_upgrade => |u| p.kestrelUpgradeCost(u),
        .kestrel_paint => |paint| Progress.kestrelPaintCost(paint),
        else => null,
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
    if (r.output == .fighter and !p.fighter and !p.hasFlag("kestrel_blueprint")) return error.NoBlueprint;
    if ((r.output == .kestrel_upgrade or r.output == .kestrel_paint) and !p.fighter) return error.NoFighter;
    if (r.output == .kestrel_upgrade and p.kestrelLevel(r.output.kestrel_upgrade) >= Progress.max_level) return error.MaxLevel;
    if (r.output == .kestrel_paint) {
        const paint = r.output.kestrel_paint;
        if (p.ownsKestrelPaint(paint)) {
            p.selectKestrelPaint(paint) catch return error.NotOwned;
            return r.output;
        }
    }
    if (made(p, r.output)) return error.AlreadyMade;
    switch (r.output) {
        .kestrel_upgrade => |u| {
            p.buyKestrelUpgrade(u, wallet) catch |err| return switch (err) {
                error.NotEnoughScrap => error.NotEnoughScrap,
                error.NotEnoughParts => error.NotEnoughParts,
                error.MaxLevel => error.MaxLevel,
                else => error.AlreadyMade,
            };
            return r.output;
        },
        .kestrel_paint => |paint| {
            p.buyKestrelPaint(paint, wallet) catch |err| return switch (err) {
                error.NotEnoughScrap => error.NotEnoughScrap,
                error.NotEnoughParts => error.NotEnoughParts,
                error.AlreadyOwned => error.AlreadyOwned,
                else => error.AlreadyMade,
            };
            return r.output;
        },
        else => {},
    }
    if (affordable(p, wallet.*, r.cost)) |err| return err;
    p.inventory[@intFromEnum(Collectibles.Kind.lumen_shard)] -= r.cost.lumen;
    p.inventory[@intFromEnum(Collectibles.Kind.rotor_core)] -= r.cost.rotor;
    p.inventory[@intFromEnum(Collectibles.Kind.hive_alloy)] -= r.cost.alloy;
    wallet.scrap -= r.cost.scrap;
    switch (r.output) {
        .vehicle => |d| p.vehicles |= @as(u8, 1) << @intCast(@intFromEnum(d)),
        .fighter => p.fighter = true,
        .suit => |c| p.suits |= Progress.bit(c),
        .armor => |a| p.armors |= Progress.armorBit(a),
        .weapon => |w| p.weapons |= @as(u16, 1) << @intCast(@intFromEnum(w)),
        .kestrel_upgrade, .kestrel_paint => unreachable,
    }
    return r.output;
}

test "recipes pay exactly, make once, and refuse what cannot be paid" {
    var p: Progress = .{};
    var wallet: Market.Wallet = .{ .scrap = 100 };
    var tab: [recipes.len]u8 = undefined;
    const vehicles = onTab(.vehicles, &tab);
    try std.testing.expectEqual(@as(usize, 4), vehicles.len);
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

test "Maro's Kestrel blueprint gates fabrication until the carrier sighting conversation" {
    var progress: Progress = .{};
    var wallet: Market.Wallet = .{ .scrap = 100 };
    var rows: [recipes.len]u8 = undefined;
    const vehicles = onTab(.vehicles, &rows);
    try std.testing.expectEqualStrings("BLUEPRINT REQUIRED", status(&progress, .fighter).?);
    try std.testing.expectError(error.NoBlueprint, make(&progress, &wallet, vehicles[3]));
    progress.setFlag("carrier_seen");
    try std.testing.expectError(error.NoBlueprint, make(&progress, &wallet, vehicles[3]));
    progress.setFlag("kestrel_blueprint");
    progress.inventory = .{ 12, 5, 14, 0 };
    _ = try make(&progress, &wallet, vehicles[3]);
    try std.testing.expect(progress.fighter);
    try std.testing.expectEqualStrings("MADE", status(&progress, .fighter).?);
}

test "aircraft fabricator tiers change Kestrel upgrades and equip unlocked paint" {
    var progress: Progress = .{};
    var wallet: Market.Wallet = .{ .scrap = 5000, .parts = 100 };
    var rows: [recipes.len]u8 = undefined;
    const aircraft = onTab(.aircraft, &rows);
    try std.testing.expectEqual(@as(usize, 8), aircraft.len);
    try std.testing.expectError(error.NoFighter, make(&progress, &wallet, aircraft[2]));
    progress.fighter = true;
    _ = try make(&progress, &wallet, aircraft[2]); // engine level 1
    try std.testing.expectEqual(@as(u8, 1), progress.kestrelLevel(.engine));
    _ = try make(&progress, &wallet, aircraft[2]); // engine level 2 costs more
    try std.testing.expectEqual(@as(u8, 2), progress.kestrelLevel(.engine));
    _ = try make(&progress, &wallet, aircraft[5]); // buy and equip azure
    try std.testing.expectEqual(Progress.Paint.azure, progress.kestrel_paint);
    _ = try make(&progress, &wallet, aircraft[4]); // reselect the free ivory finish
    try std.testing.expectEqual(Progress.Paint.ivory, progress.kestrel_paint);
    try std.testing.expectEqualStrings("EQUIPPED", status(&progress, recipes[aircraft[4]].output).?);
}
