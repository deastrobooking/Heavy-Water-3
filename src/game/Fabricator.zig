//! The fabricator at the garage turns collectibles (and some scrap) into hover cars, armor suits,
//! armor accents and weapons. Recipes are grouped in tabs; each makes one thing once. The first
//! weapons need no Hive alloy, since alloy only comes from beating Hive units. Nothing changes
//! when a recipe cannot be paid. Cars and the Kestrel join the team's garage (`Progress`);
//! suits, armor and weapons are the maker's own, paid from their kit's pickups and wallet.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Progress = @import("Progress.zig");
const Kit = @import("Kit.zig");
const Profile = @import("Profile.zig");
const Collectibles = @import("Collectibles.zig");
const Market = @import("../city/Market.zig");
const Designs = @import("../vehicle/Designs.zig");
const WeaponKind = @import("../combat/Weapon.zig").WeaponKind;

pub const Tab = enum { vehicles, suits, armor, weapons, aircraft };
pub const tab_count = enum_compat.fields(Tab).len;
pub const WeaponUpgrade = struct { weapon: WeaponKind, tier: u8 };
pub const Output = union(enum) { vehicle: Designs.Design, fighter, suit: Profile.Clothing, armor: Profile.Armor, weapon: WeaponKind, weapon_upgrade: WeaponUpgrade, kestrel_upgrade: Progress.KestrelUpgrade, kestrel_paint: Progress.Paint };
/// Pickups by kind (lumen, rotor, alloy; vital cells are never spent) plus scrap.
pub const Cost = struct { lumen: u32 = 0, rotor: u32 = 0, alloy: u32 = 0, scrap: u32 = 0 };
pub const Recipe = struct { tab: Tab, output: Output, cost: Cost, about: []const u8 };
pub const Error = error{ AlreadyMade, NotEnoughLumen, NotEnoughRotors, NotEnoughAlloy, NotEnoughScrap, NotEnoughParts, MaxLevel, AlreadyOwned, NotOwned, WeaponRequired, PreviousTierRequired, NoFighter, NoBlueprint };

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
    .{ .tab = .armor, .output = .{ .armor = .gem_aegis }, .cost = .{ .lumen = 10, .alloy = 8 }, .about = "Fitted pearl armor with a hand-cut chest crystal." },
    .{ .tab = .armor, .output = .{ .armor = .starforge }, .cost = .{ .rotor = 2, .alloy = 12 }, .about = "Celestial plates, jeweled shoulder guards and a star-cut core." },
    .{ .tab = .armor, .output = .{ .armor = .deep_prism }, .cost = .{ .lumen = 14, .alloy = 14 }, .about = "Deep-sea ceramic armor with a luminous prism setting." },
    .{ .tab = .armor, .output = .{ .armor = .mobile_suit }, .cost = .{ .rotor = 2, .alloy = 16 }, .about = "Mobile-suit plate: angular shoulders, twin-eye visor, V-fin crest and thruster pack." },
    .{ .tab = .armor, .output = .{ .armor = .buster }, .cost = .{ .lumen = 10, .alloy = 12 }, .about = "Round blue battle armor with a forearm buster cannon." },
    .{ .tab = .armor, .output = .{ .armor = .iron_titan }, .cost = .{ .rotor = 3, .alloy = 18 }, .about = "Sharp-edged titan plate with finned greaves, calf thrusters and a winged pack." },
    .{ .tab = .armor, .output = .{ .armor = .battle_plate }, .cost = .{ .lumen = 12, .alloy = 14 }, .about = "Flared cream battle plate with gold cuffs and a scouter lens." },
    .{ .tab = .weapons, .output = .{ .weapon = .blaster }, .cost = .{ .lumen = 6, .scrap = 20 }, .about = "Buster blaster. Charges while the trigger is held." },
    .{ .tab = .weapons, .output = .{ .weapon = .beam_saber }, .cost = .{ .lumen = 4, .scrap = 15 }, .about = "Lumen blade: a three-cut combo, a dash cut, a held wave cut; alternate guards and parries." },
    .{ .tab = .weapons, .output = .{ .weapon = .energy_bow }, .cost = .{ .lumen = 8, .alloy = 6 }, .about = "Draw to power up. Alternate fire shoots a warp arrow." },
    .{ .tab = .weapons, .output = .{ .weapon = .tracking_missile }, .cost = .{ .rotor = 1, .alloy = 10 }, .about = "A salvo of homing missiles at the nearest Hive unit." },
    .{ .tab = .weapons, .output = .{ .weapon = .protective_shield }, .cost = .{ .lumen = 4, .alloy = 8 }, .about = "Hold to block; a timed raise parries." },
    .{ .tab = .weapons, .output = .{ .weapon = .machine_gun }, .cost = .{ .lumen = 6, .scrap = 30, .alloy = 4 }, .about = "Fourteen bolts a second. Spread grows with heat; it locks when it overheats." },
    .{ .tab = .weapons, .output = .{ .weapon = .heavy_rifle }, .cost = .{ .lumen = 8, .alloy = 10 }, .about = "Heavy bolts that pierce two. Hold the alternate to charge one through four." },
    .{ .tab = .weapons, .output = .{ .weapon = .sniper_rifle }, .cost = .{ .lumen = 12, .rotor = 1, .alloy = 8 }, .about = "Instant beam that pierces one. The alternate scopes; a steady scope hits harder." },
    .{ .tab = .weapons, .output = .{ .weapon = .energy_bazooka }, .cost = .{ .lumen = 10, .rotor = 2, .alloy = 12 }, .about = "Arcing plasma orb that bursts, stuns and throws. The alternate detonates it." },
    .{ .tab = .weapons, .output = .{ .weapon = .energy_net }, .cost = .{ .lumen = 8, .rotor = 2, .alloy = 5 }, .about = "Fast, wide energy net briefly snares and damages multiple Hive flyers." },
    .{ .tab = .weapons, .output = .{ .weapon = .giant_blast }, .cost = .{ .lumen = 10, .rotor = 2, .alloy = 16 }, .about = "Charge a beam that cuts through anything." },
    .{ .tab = .weapons, .output = .{ .weapon_upgrade = .{ .weapon = .beam_saber, .tier = 2 } }, .cost = .{ .lumen = 8, .alloy = 3, .scrap = 35 }, .about = "Mk II: wider plasma edge and a finisher shockwave." },
    .{ .tab = .weapons, .output = .{ .weapon_upgrade = .{ .weapon = .beam_saber, .tier = 3 } }, .cost = .{ .lumen = 14, .rotor = 1, .alloy = 8, .scrap = 75 }, .about = "Mk III: heavier combo finishers and a stronger saber wave." },
    .{ .tab = .weapons, .output = .{ .weapon_upgrade = .{ .weapon = .blaster, .tier = 2 } }, .cost = .{ .lumen = 8, .alloy = 3, .scrap = 35 }, .about = "Mk II: larger charged plasma burst and faster charging." },
    .{ .tab = .weapons, .output = .{ .weapon_upgrade = .{ .weapon = .blaster, .tier = 3 } }, .cost = .{ .lumen = 14, .rotor = 1, .alloy = 8, .scrap = 75 }, .about = "Mk III: maximum charge hits harder and detonates wider." },
    .{ .tab = .weapons, .output = .{ .weapon_upgrade = .{ .weapon = .giant_blast, .tier = 2 } }, .cost = .{ .lumen = 10, .rotor = 1, .alloy = 8, .scrap = 55 }, .about = "Mk II: charge to a stronger, wider beam tier." },
    .{ .tab = .weapons, .output = .{ .weapon_upgrade = .{ .weapon = .giant_blast, .tier = 3 } }, .cost = .{ .lumen = 16, .rotor = 2, .alloy = 14, .scrap = 100 }, .about = "Mk III: full charge doubles beam duration and pierces longer." },
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
        .weapon_upgrade => |u| return switch (u.weapon) {
            .beam_saber => if (u.tier == 2) "PLASMA EDGE II" else "PLASMA EDGE III",
            .blaster => if (u.tier == 2) "BUSTER CORE II" else "BUSTER CORE III",
            .giant_blast => if (u.tier == 2) "OVERDRIVE CORE II" else "OVERDRIVE CORE III",
            else => "WEAPON UPGRADE",
        },
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

pub fn made(p: *const Progress, k: *const Kit, output: Output) bool {
    return switch (output) {
        .vehicle => |d| p.ownsVehicle(d),
        .fighter => p.fighter,
        .suit => |c| k.owns(c),
        .armor => |a| k.ownsArmor(a),
        .weapon => |w| k.ownsWeapon(w),
        .weapon_upgrade => |u| k.weaponLevel(u.weapon) >= u.tier,
        .kestrel_upgrade => |u| p.kestrelLevel(u) >= Progress.max_level,
        .kestrel_paint => |paint| p.ownsKestrelPaint(paint),
    };
}

pub fn status(p: *const Progress, k: *const Kit, output: Output) ?[]const u8 {
    return switch (output) {
        .fighter => if (p.fighter) "MADE" else if (!p.hasFlag("kestrel_blueprint")) "BLUEPRINT REQUIRED" else null,
        .weapon_upgrade => |u| if (!k.ownsWeapon(u.weapon)) "FABRICATE WEAPON FIRST" else if (k.weaponLevel(u.weapon) >= u.tier) "INSTALLED" else if (k.weaponLevel(u.weapon) + 1 < u.tier) "PREVIOUS TIER FIRST" else null,
        .kestrel_upgrade, .kestrel_paint => if (!p.fighter) "FABRICATE KESTREL FIRST" else switch (output) {
            .kestrel_upgrade => |u| if (p.kestrelLevel(u) >= Progress.max_level) "MAX LEVEL" else null,
            .kestrel_paint => |paint| if (p.ownsKestrelPaint(paint)) (if (p.kestrel_paint == paint) "EQUIPPED" else "OWNED") else null,
            else => unreachable,
        },
        else => if (made(p, k, output)) "MADE" else null,
    };
}

pub fn progressCost(p: *const Progress, output: Output) ?Progress.Cost {
    return switch (output) {
        .kestrel_upgrade => |u| p.kestrelUpgradeCost(u),
        .kestrel_paint => |paint| Progress.kestrelPaintCost(paint),
        else => null,
    };
}

pub fn affordable(k: *const Kit, c: Cost) ?Error {
    if (k.count(.lumen_shard) < c.lumen) return error.NotEnoughLumen;
    if (k.count(.rotor_core) < c.rotor) return error.NotEnoughRotors;
    if (k.count(.hive_alloy) < c.alloy) return error.NotEnoughAlloy;
    if (k.wallet.scrap < c.scrap) return error.NotEnoughScrap;
    return null;
}

/// Pays for and makes recipe `index` for the player holding kit `k`.
pub fn make(p: *Progress, k: *Kit, index: usize) Error!Output {
    const wallet = &k.wallet;
    const r = recipes[index];
    if (r.output == .fighter and !p.fighter and !p.hasFlag("kestrel_blueprint")) return error.NoBlueprint;
    if ((r.output == .kestrel_upgrade or r.output == .kestrel_paint) and !p.fighter) return error.NoFighter;
    if (r.output == .kestrel_upgrade and p.kestrelLevel(r.output.kestrel_upgrade) >= Progress.max_level) return error.MaxLevel;
    if (r.output == .weapon_upgrade) {
        const u = r.output.weapon_upgrade;
        if (!k.ownsWeapon(u.weapon)) return error.WeaponRequired;
        if (k.weaponLevel(u.weapon) >= u.tier) return error.AlreadyMade;
        if (k.weaponLevel(u.weapon) + 1 < u.tier) return error.PreviousTierRequired;
    }
    if (r.output == .kestrel_paint) {
        const paint = r.output.kestrel_paint;
        if (p.ownsKestrelPaint(paint)) {
            p.selectKestrelPaint(paint) catch return error.NotOwned;
            return r.output;
        }
    }
    if (made(p, k, r.output)) return error.AlreadyMade;
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
    if (affordable(k, r.cost)) |err| return err;
    k.inventory[@intFromEnum(Collectibles.Kind.lumen_shard)] -= r.cost.lumen;
    k.inventory[@intFromEnum(Collectibles.Kind.rotor_core)] -= r.cost.rotor;
    k.inventory[@intFromEnum(Collectibles.Kind.hive_alloy)] -= r.cost.alloy;
    wallet.scrap -= r.cost.scrap;
    switch (r.output) {
        .vehicle => |d| p.vehicles |= @as(u8, 1) << @intCast(@intFromEnum(d)),
        .fighter => p.fighter = true,
        .suit => |c| k.suits |= Kit.bit(c),
        .armor => |a| k.armors |= Kit.armorBit(a),
        .weapon => |w| k.weapons |= @as(u16, 1) << @intCast(@intFromEnum(w)),
        .weapon_upgrade => |u| k.weapon_upgrades[@intFromEnum(u.weapon)] = u.tier - 1,
        .kestrel_upgrade, .kestrel_paint => unreachable,
    }
    return r.output;
}

test "recipes pay exactly, make once, and refuse what cannot be paid" {
    var p: Progress = .{};
    var k: Kit = .{ .wallet = .{ .scrap = 100 } };
    var tab: [recipes.len]u8 = undefined;
    const vehicles = onTab(.vehicles, &tab);
    try std.testing.expectEqual(@as(usize, 4), vehicles.len);
    try std.testing.expectError(error.NotEnoughLumen, make(&p, &k, vehicles[0]));
    k.inventory = .{ 10, 2, 0, 0 };
    const out = try make(&p, &k, vehicles[0]);
    try std.testing.expectEqual(Designs.Design.skimmer, out.vehicle);
    try std.testing.expect(p.ownsVehicle(.skimmer));
    try std.testing.expectEqual([4]u32{ 2, 0, 0, 0 }, k.inventory);
    try std.testing.expectEqual(@as(u32, 70), k.wallet.scrap);
    try std.testing.expectError(error.AlreadyMade, make(&p, &k, vehicles[0]));
    // The first two weapons need no alloy: they are reachable before the first fight.
    var weapons_tab: [recipes.len]u8 = undefined;
    for (onTab(.weapons, &weapons_tab)[0..2]) |i| try std.testing.expectEqual(@as(u32, 0), recipes[i].cost.alloy);
    var buffer: [24]u8 = undefined;
    try std.testing.expectEqualStrings("TRACKING MISSILE", name(.{ .weapon = .tracking_missile }, &buffer));
}

test "weapon tiers require ownership and the prior tier, then persist as installed upgrades" {
    var p: Progress = .{};
    var k: Kit = .{ .weapons = 0, .wallet = .{ .scrap = 1_000 } };
    var rows: [recipes.len]u8 = undefined;
    const weapons = onTab(.weapons, &rows);
    const tier2 = weapons[weapons.len - 6];
    const tier3 = weapons[weapons.len - 5];
    try std.testing.expectEqualStrings("FABRICATE WEAPON FIRST", status(&p, &k, recipes[tier2].output).?);
    try std.testing.expectError(error.WeaponRequired, make(&p, &k, tier2));

    k.weapons |= @as(u16, 1) << @intCast(@intFromEnum(WeaponKind.beam_saber));
    try std.testing.expectError(error.PreviousTierRequired, make(&p, &k, tier3));
    k.inventory = .{ 100, 100, 100, 0 };
    _ = try make(&p, &k, tier2);
    try std.testing.expectEqual(@as(u8, 2), k.weaponLevel(.beam_saber));
    _ = try make(&p, &k, tier3);
    try std.testing.expectEqual(@as(u8, 3), k.weaponLevel(.beam_saber));
    try std.testing.expectEqualStrings("INSTALLED", status(&p, &k, recipes[tier3].output).?);
}

test "Maro's Kestrel blueprint gates fabrication until the carrier sighting conversation" {
    var progress: Progress = .{};
    var kit: Kit = .{ .wallet = .{ .scrap = 100 } };
    var rows: [recipes.len]u8 = undefined;
    const vehicles = onTab(.vehicles, &rows);
    try std.testing.expectEqualStrings("BLUEPRINT REQUIRED", status(&progress, &kit, .fighter).?);
    try std.testing.expectError(error.NoBlueprint, make(&progress, &kit, vehicles[3]));
    progress.setFlag("carrier_seen");
    try std.testing.expectError(error.NoBlueprint, make(&progress, &kit, vehicles[3]));
    progress.setFlag("kestrel_blueprint");
    kit.inventory = .{ 12, 5, 14, 0 };
    _ = try make(&progress, &kit, vehicles[3]);
    try std.testing.expect(progress.fighter);
    try std.testing.expectEqualStrings("MADE", status(&progress, &kit, .fighter).?);
}

test "aircraft fabricator tiers change Kestrel upgrades and equip unlocked paint" {
    var progress: Progress = .{};
    var kit: Kit = .{ .wallet = .{ .scrap = 5000, .parts = 100 } };
    var rows: [recipes.len]u8 = undefined;
    const aircraft = onTab(.aircraft, &rows);
    try std.testing.expectEqual(@as(usize, 8), aircraft.len);
    try std.testing.expectError(error.NoFighter, make(&progress, &kit, aircraft[2]));
    progress.fighter = true;
    _ = try make(&progress, &kit, aircraft[2]); // engine level 1
    try std.testing.expectEqual(@as(u8, 1), progress.kestrelLevel(.engine));
    _ = try make(&progress, &kit, aircraft[2]); // engine level 2 costs more
    try std.testing.expectEqual(@as(u8, 2), progress.kestrelLevel(.engine));
    _ = try make(&progress, &kit, aircraft[5]); // buy and equip azure
    try std.testing.expectEqual(Progress.Paint.azure, progress.kestrel_paint);
    _ = try make(&progress, &kit, aircraft[4]); // reselect the free ivory finish
    try std.testing.expectEqual(Progress.Paint.ivory, progress.kestrel_paint);
    try std.testing.expectEqualStrings("EQUIPPED", status(&progress, &kit, recipes[aircraft[4]].output).?);
}
