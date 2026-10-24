//! The space fighter's four weapon systems and the six native frames that carry them. Each frame
//! is a distinct design: its handling, hull and a weapon profile that leans on one system.
//!
//! - **Energy machine guns** (fire, held): twin bolts along the aim, limited by heat.
//! - **Energy charge blast** (alternate, hold and release): charges while held, guns silent; a
//!   released blast pierces and grows with the charge.
//! - **Tracking missiles** (special 1): lock the hostile nearest the aim and home; the rack
//!   reloads one at a time.
//! - **Tracking energy bombs** (special 2): a slow homing orb that bursts over an area and wipes
//!   hostile shots inside it; a few per level, one back per wave cleared.
//!
//! The shared Kestrel upgrades (engine, missile rack, gun cooling; armor through `Hangar`) apply
//! to every frame. Pure: `SpaceBattle` spawns what `Weapons.step` fires.
const std = @import("std");
const Progress = @import("Progress.zig");

pub const Frame = Progress.SpaceFrame;

pub const Profile = struct {
    name: []const u8,
    role: []const u8,
    about: []const u8,
    /// Acceleration, top speed and boost speed (m/s², m/s).
    accel: f32,
    top: f32,
    boost: f32,
    gun_damage: f32,
    /// Seconds between shots, heat per shot (overheats at 1) and heat shed per second.
    gun_interval: f32,
    gun_heat: f32,
    gun_cool: f32,
    /// Seconds to full charge, damage and burst radius at full charge.
    charge_time: f32,
    charge_damage: f32,
    charge_radius: f32,
    missiles: u8,
    missile_reload: f32,
    missile_damage: f32,
    bombs: u8,
    bomb_damage: f32,
    bomb_radius: f32,
};

pub fn base(frame: Frame) Profile {
    return switch (frame) {
        .kestrel => .{ .name = "KESTREL", .role = "BALANCED", .about = "The rangers' all-round fighter: steady guns, a full rack, two bombs.", .accel = 92, .top = 150, .boost = 245, .gun_damage = 9, .gun_interval = 0.09, .gun_heat = 0.045, .gun_cool = 0.5, .charge_time = 1.2, .charge_damage = 120, .charge_radius = 2.5, .missiles = 4, .missile_reload = 6, .missile_damage = 60, .bombs = 2, .bomb_damage = 220, .bomb_radius = 22 },
        .ember_wyrm => .{ .name = "EMBER WYRM", .role = "GUN INTERCEPTOR", .about = "Light and fast, with the quickest guns. Few missiles, one bomb.", .accel = 120, .top = 175, .boost = 280, .gun_damage = 8, .gun_interval = 0.06, .gun_heat = 0.04, .gun_cool = 0.65, .charge_time = 1.4, .charge_damage = 100, .charge_radius = 2, .missiles = 2, .missile_reload = 7, .missile_damage = 55, .bombs = 1, .bomb_damage = 200, .bomb_radius = 20 },
        .void_lance => .{ .name = "VOID LANCE", .role = "CHARGE LANCER", .about = "Built around its lance: the fastest, hardest charge blast.", .accel = 95, .top = 155, .boost = 250, .gun_damage = 8, .gun_interval = 0.1, .gun_heat = 0.045, .gun_cool = 0.5, .charge_time = 0.8, .charge_damage = 220, .charge_radius = 3.5, .missiles = 4, .missile_reload = 6, .missile_damage = 60, .bombs = 2, .bomb_damage = 220, .bomb_radius = 22 },
        .dreadclaw => .{ .name = "DREADCLAW", .role = "MISSILE GUNSHIP", .about = "Slow and tough, with a deep missile rack that reloads quickly.", .accel = 75, .top = 130, .boost = 210, .gun_damage = 11, .gun_interval = 0.11, .gun_heat = 0.04, .gun_cool = 0.45, .charge_time = 1.4, .charge_damage = 140, .charge_radius = 3, .missiles = 8, .missile_reload = 3.5, .missile_damage = 70, .bombs = 2, .bomb_damage = 220, .bomb_radius = 22 },
        .starwing => .{ .name = "STARWING", .role = "ION INTERCEPTOR", .about = "The most agile frame: hard-hitting ion guns that cool fast.", .accel = 130, .top = 190, .boost = 300, .gun_damage = 12, .gun_interval = 0.075, .gun_heat = 0.04, .gun_cool = 0.75, .charge_time = 1.0, .charge_damage = 150, .charge_radius = 2.5, .missiles = 4, .missile_reload = 5, .missile_damage = 60, .bombs = 2, .bomb_damage = 220, .bomb_radius = 22 },
        .bulwark => .{ .name = "BULWARK", .role = "ARMORED BOMBER", .about = "Heavy armor and four big energy bombs; holds a line under fire.", .accel = 70, .top = 120, .boost = 200, .gun_damage = 10, .gun_interval = 0.1, .gun_heat = 0.04, .gun_cool = 0.5, .charge_time = 1.3, .charge_damage = 160, .charge_radius = 4, .missiles = 6, .missile_reload = 5, .missile_damage = 65, .bombs = 4, .bomb_damage = 300, .bomb_radius = 28 },
    };
}

/// A frame with the team's upgrades fitted.
pub fn profile(frame: Frame, levels: [Progress.kestrel_upgrade_count]u8) Profile {
    var p = base(frame);
    const engine: f32 = @floatFromInt(levels[@intFromEnum(Progress.KestrelUpgrade.engine)]);
    const rack = levels[@intFromEnum(Progress.KestrelUpgrade.missile_rack)];
    const cooling: f32 = @floatFromInt(levels[@intFromEnum(Progress.KestrelUpgrade.gun_cooling)]);
    p.accel *= 1 + engine * 0.08;
    p.top *= 1 + engine * 0.05;
    p.boost *= 1 + engine * 0.05;
    p.missiles += rack * 2;
    p.gun_cool *= 1 + cooling * 0.25;
    return p;
}

/// Below this share of a full charge, releasing the alternate fires nothing.
pub const min_charge: f32 = 0.25;
/// Heat must fall below this before overheated guns fire again.
pub const vented: f32 = 0.35;

pub const Fired = struct {
    /// A gun bolt from this muzzle side (0 left, 1 right), if one fired.
    gun: ?u1 = null,
    /// A charge blast, with its share of a full charge (`min_charge`..1).
    blast: ?f32 = null,
};

pub const Weapons = struct {
    heat: f32 = 0,
    overheated: bool = false,
    gun_cooldown: f32 = 0,
    side: u1 = 0,
    /// Seconds the alternate has been held.
    charge: f32 = 0,
    missiles: u8 = 0,
    missile_clock: f32 = 0,
    bombs: u8 = 0,

    pub fn init(p: Profile) Weapons {
        return .{ .missiles = p.missiles, .bombs = p.bombs };
    }

    pub fn chargeShare(self: Weapons, p: Profile) f32 {
        return std.math.clamp(self.charge / p.charge_time, 0, 1);
    }

    /// One fixed step of the guns, charge and rack. `fire` and `alt` are the held triggers.
    pub fn step(self: *Weapons, p: Profile, fire: bool, alt: bool, dt: f32) Fired {
        var out: Fired = .{};
        self.gun_cooldown = @max(0, self.gun_cooldown - dt);
        if (self.missiles < p.missiles) {
            self.missile_clock += dt;
            if (self.missile_clock >= p.missile_reload) {
                self.missile_clock = 0;
                self.missiles += 1;
            }
        } else self.missile_clock = 0;

        if (alt) {
            self.charge = @min(p.charge_time, self.charge + dt);
        } else if (self.charge > 0) {
            const share = self.chargeShare(p);
            if (share >= min_charge) out.blast = share;
            self.charge = 0;
        }
        // Charging routes the power away from the guns.
        const shooting = fire and !alt and !self.overheated;
        if (shooting and self.gun_cooldown <= 0) {
            self.gun_cooldown = p.gun_interval;
            self.heat += p.gun_heat;
            out.gun = self.side;
            self.side +%= 1;
            if (self.heat >= 1) {
                self.heat = 1;
                self.overheated = true;
            }
        } else if (!shooting) self.heat = @max(0, self.heat - p.gun_cool * dt);
        if (self.overheated and self.heat < vented) self.overheated = false;
        return out;
    }

    pub fn takeMissile(self: *Weapons) bool {
        if (self.missiles == 0) return false;
        self.missiles -= 1;
        return true;
    }

    pub fn takeBomb(self: *Weapons) bool {
        if (self.bombs == 0) return false;
        self.bombs -= 1;
        return true;
    }

    /// A cleared wave gives one bomb back, up to the frame's load.
    pub fn waveCleared(self: *Weapons, p: Profile) void {
        self.bombs = @min(p.bombs, self.bombs + 1);
    }
};

test "the six frames are distinct designs, each best at something" {
    const all = std.enums.values(Frame);
    try std.testing.expectEqual(@as(usize, 6), all.len);
    var best_gun = all[0];
    var best_charge = all[0];
    var best_rack = all[0];
    var best_bombs = all[0];
    var fastest = all[0];
    for (all) |f| {
        const p = base(f);
        if (p.gun_damage / p.gun_interval > base(best_gun).gun_damage / base(best_gun).gun_interval) best_gun = f;
        if (p.charge_damage / p.charge_time > base(best_charge).charge_damage / base(best_charge).charge_time) best_charge = f;
        if (p.missiles > base(best_rack).missiles) best_rack = f;
        if (p.bombs > base(best_bombs).bombs) best_bombs = f;
        if (p.top > base(fastest).top) fastest = f;
    }
    try std.testing.expectEqual(Frame.starwing, best_gun);
    try std.testing.expectEqual(Frame.void_lance, best_charge);
    try std.testing.expectEqual(Frame.dreadclaw, best_rack);
    try std.testing.expectEqual(Frame.bulwark, best_bombs);
    try std.testing.expectEqual(Frame.starwing, fastest);
}

test "guns heat up and vent, charging silences them and a release fires a blast" {
    const p = base(.kestrel);
    var wpn = Weapons.init(p);
    var shots: u32 = 0;
    for (0..600) |_| {
        if (wpn.step(p, true, false, 1.0 / 60.0).gun != null) shots += 1;
        if (wpn.overheated) break;
    }
    try std.testing.expect(wpn.overheated);
    try std.testing.expectEqual(@as(u32, @intFromFloat(@ceil(1 / p.gun_heat))), shots);
    // Overheated: held fire does nothing until it vents.
    try std.testing.expect(wpn.step(p, true, false, 1.0 / 60.0).gun == null);
    for (0..240) |_| _ = wpn.step(p, false, false, 1.0 / 60.0);
    try std.testing.expect(!wpn.overheated);
    // A tap of the alternate is too short; a full hold fires a full blast, with no gun shots.
    _ = wpn.step(p, false, true, 0.1);
    try std.testing.expect(wpn.step(p, false, false, 1.0 / 60.0).blast == null);
    var gun_while_charging = false;
    for (0..120) |_| gun_while_charging = gun_while_charging or wpn.step(p, true, true, 1.0 / 60.0).gun != null;
    try std.testing.expect(!gun_while_charging);
    try std.testing.expectEqual(@as(?f32, 1), wpn.step(p, false, false, 1.0 / 60.0).blast);
}

test "missiles reload one at a time, bombs come back per wave, and upgrades fit every frame" {
    const p = base(.dreadclaw);
    var wpn = Weapons.init(p);
    while (wpn.takeMissile()) {}
    try std.testing.expectEqual(@as(u8, 0), wpn.missiles);
    _ = wpn.step(p, false, false, p.missile_reload + 0.01);
    try std.testing.expectEqual(@as(u8, 1), wpn.missiles);
    while (wpn.takeBomb()) {}
    wpn.waveCleared(p);
    wpn.waveCleared(p);
    wpn.waveCleared(p);
    try std.testing.expectEqual(p.bombs, wpn.bombs);
    var levels: [Progress.kestrel_upgrade_count]u8 = @splat(0);
    levels[@intFromEnum(Progress.KestrelUpgrade.missile_rack)] = 2;
    levels[@intFromEnum(Progress.KestrelUpgrade.engine)] = 3;
    for (std.enums.values(Frame)) |f| {
        try std.testing.expectEqual(base(f).missiles + 4, profile(f, levels).missiles);
        try std.testing.expect(profile(f, levels).accel > base(f).accel);
    }
}
