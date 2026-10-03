//! Energy firearms: trigger logic for the sniper rifle, machine gun, heavy rifle and energy
//! bazooka. Each step takes the trigger edges and held state and returns the shots to make;
//! the caller turns them into hitscan beams or projectiles in the world.
//!
//! - **Sniper rifle:** the alternate scopes in, and the steadier the scope (up to 1.5 s), the
//!   harder the shot (+50%). Fire sends an instant beam 450 m that pierces one target. One
//!   shot per 1.1 s.
//! - **Machine gun:** 14 rounds a second while held. Spread grows with heat; at 100 heat it
//!   locks until it cools to 30.
//! - **Heavy rifle:** two shots a second of slow, heavy bolts that pierce up to two targets.
//!   Holding the alternate charges a shot to 2.5× damage, fired on release.
//! - **Energy bazooka:** an arcing plasma orb that bursts on contact (area damage and
//!   knockback). The alternate detonates the last orb early. 2.2 s between shots.
const std = @import("std");
const Weapon = @import("Weapon.zig");
const ProjectileKind = @import("Projectile.zig").ProjectileKind;

pub const Kind = enum { sniper_rifle, machine_gun, heavy_rifle, energy_bazooka };

pub fn of(w: Weapon.WeaponKind) ?Kind {
    return switch (w) {
        .sniper_rifle => .sniper_rifle,
        .machine_gun => .machine_gun,
        .heavy_rifle => .heavy_rifle,
        .energy_bazooka => .energy_bazooka,
        else => null,
    };
}

pub const Shot = union(enum) {
    /// An instant beam along the aim (spread already applied by the caller from `spread`).
    beam: struct { damage: f32, range: f32, pierce: u8 },
    /// A projectile along the aim, `spread` radians of random deviation.
    bolt: struct { kind: ProjectileKind, speed: f32, damage: f32, life: f32, pierce: u8 = 0, gravity: f32 = 0, spread: f32 = 0 },
    /// Burst the last bazooka orb now.
    detonate,
};

pub const State = struct {
    cooldown: f32 = 0,
    heat: f32 = 0,
    overheated: bool = false,
    /// Seconds scoped in (sniper) or charged (heavy rifle alternate).
    hold: f32 = 0,
    was_fire: bool = false,
    was_alt: bool = false,

    /// Sniper: scoped in now.
    pub fn scoped(self: State, kind: Kind) bool {
        return kind == .sniper_rifle and self.was_alt;
    }

    /// Charge or steadiness for the HUD (0–1), or heat for the machine gun.
    pub fn meter(self: State, kind: Kind) f32 {
        return switch (kind) {
            .sniper_rifle => @min(1, self.hold / 1.5),
            .heavy_rifle => @min(1, self.hold / 0.8),
            .machine_gun => self.heat / 100,
            .energy_bazooka => 1 - @min(1, self.cooldown / 2.2),
        };
    }

    /// One step: up to two shots written to `out`.
    pub fn step(self: *State, kind: Kind, slot: Weapon.WeaponSlot, fire: bool, alt: bool, dt: f32, out: *[2]Shot) []const Shot {
        var n: usize = 0;
        const pressed = fire and !self.was_fire;
        const alt_released = !alt and self.was_alt;
        // The cooldown runs below zero within a step so held fire keeps an exact rate.
        self.cooldown -= dt;
        self.heat = @max(0, self.heat - 30 * dt);
        if (self.overheated and self.heat < 30) self.overheated = false;
        const base = slot.baseDamage();
        switch (kind) {
            .sniper_rifle => {
                self.hold = if (alt) @min(1.5, self.hold + dt) else 0;
                if (pressed and self.cooldown <= 0) {
                    self.cooldown = 1.1;
                    out[n] = .{ .beam = .{ .damage = base * (1 + self.hold / 3), .range = 450, .pierce = 1 } };
                    n += 1;
                }
            },
            .machine_gun => if (fire and !self.overheated and self.cooldown <= 0) {
                self.cooldown = @max(self.cooldown, -dt) + 1.0 / 14.0;
                self.heat += 3.5;
                if (self.heat >= 100) self.overheated = true;
                out[n] = .{ .bolt = .{ .kind = .mg_bolt, .speed = 140, .damage = base, .life = 1.6, .spread = 0.008 + 0.045 * self.heat / 100 } };
                n += 1;
            },
            .heavy_rifle => {
                if (alt) self.hold = @min(0.8, self.hold + dt);
                if (alt_released and self.cooldown <= 0) {
                    const full = self.hold >= 0.8;
                    self.cooldown = 0.9;
                    out[n] = .{ .bolt = .{ .kind = .heavy_bolt, .speed = 95, .damage = base * (if (full) @as(f32, 2.5) else 1.2), .life = 2.5, .pierce = if (full) 4 else 2 } };
                    n += 1;
                    self.hold = 0;
                } else if (pressed and !alt and self.cooldown <= 0) {
                    self.cooldown = 0.5;
                    out[n] = .{ .bolt = .{ .kind = .heavy_bolt, .speed = 95, .damage = base, .life = 2.5, .pierce = 2 } };
                    n += 1;
                }
                if (!alt) self.hold = 0;
            },
            .energy_bazooka => {
                if (pressed and self.cooldown <= 0) {
                    self.cooldown = 2.2;
                    out[n] = .{ .bolt = .{ .kind = .bazooka_orb, .speed = 48, .damage = base, .life = 4, .gravity = 6 } };
                    n += 1;
                }
                if (alt and !self.was_alt) {
                    out[n] = .detonate;
                    n += 1;
                }
            },
        }
        self.cooldown = @max(self.cooldown, if (kind == .machine_gun and fire) -dt else 0);
        self.was_fire = fire;
        self.was_alt = alt;
        return out[0..n];
    }
};

test "each firearm fires at its own rhythm and charge" {
    var out: [2]Shot = undefined;
    const slot: Weapon.WeaponSlot = .{ .kind = .machine_gun };
    // Machine gun: about 14 shots a second while held, until it overheats.
    var mg: State = .{};
    var shots: usize = 0;
    for (0..60) |_| shots += mg.step(.machine_gun, slot, true, false, 1.0 / 60.0, &out).len;
    try std.testing.expect(shots >= 13 and shots <= 15);
    for (0..300) |_| _ = mg.step(.machine_gun, slot, true, false, 1.0 / 60.0, &out);
    try std.testing.expect(mg.overheated);
    try std.testing.expectEqual(@as(usize, 0), mg.step(.machine_gun, slot, true, false, 1.0 / 60.0, &out).len);

    // Sniper: a steady scope adds damage; one shot per press.
    var sniper: State = .{};
    const sniper_slot: Weapon.WeaponSlot = .{ .kind = .sniper_rifle };
    const quick = sniper.step(.sniper_rifle, sniper_slot, true, false, 1.0 / 60.0, &out)[0].beam.damage;
    sniper = .{};
    for (0..90) |_| _ = sniper.step(.sniper_rifle, sniper_slot, false, true, 1.0 / 60.0, &out);
    try std.testing.expect(sniper.scoped(.sniper_rifle));
    const steady = sniper.step(.sniper_rifle, sniper_slot, true, true, 1.0 / 60.0, &out)[0].beam.damage;
    try std.testing.expect(steady > quick * 1.4);
    try std.testing.expectEqual(@as(usize, 0), sniper.step(.sniper_rifle, sniper_slot, true, true, 1.0 / 60.0, &out).len);

    // Heavy rifle: a full alternate charge pierces more and hits harder.
    var heavy: State = .{};
    const heavy_slot: Weapon.WeaponSlot = .{ .kind = .heavy_rifle };
    for (0..60) |_| _ = heavy.step(.heavy_rifle, heavy_slot, false, true, 1.0 / 60.0, &out);
    const charged = heavy.step(.heavy_rifle, heavy_slot, false, false, 1.0 / 60.0, &out)[0].bolt;
    try std.testing.expect(charged.pierce == 4 and charged.damage > 2 * heavy_slot.baseDamage());

    // Bazooka: an arcing orb, then the alternate detonates it.
    var bazooka: State = .{};
    const bazooka_slot: Weapon.WeaponSlot = .{ .kind = .energy_bazooka };
    const orb = bazooka.step(.energy_bazooka, bazooka_slot, true, false, 1.0 / 60.0, &out)[0].bolt;
    try std.testing.expect(orb.kind == .bazooka_orb and orb.gravity > 0);
    try std.testing.expect(bazooka.step(.energy_bazooka, bazooka_slot, false, true, 1.0 / 60.0, &out)[0] == .detonate);
}
