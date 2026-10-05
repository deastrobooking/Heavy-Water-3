//! Central combat coordinator linking player actions, weapons, projectiles,
//! shields, homing tracking missiles, and warp-strike executions.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Weapon = @import("Weapon.zig");
const Projectile = @import("Projectile.zig");
const V = Physics.Vec3;
const R = Physics.Rotation;

pub const CombatSystem = @This();

pub const MaxSlots = 4;

slots: [MaxSlots]Weapon.WeaponSlot = .{
    .{ .kind = .beam_saber, .element = .solar_lumen, .core = .plasma_edge, .level = 1 },
    .{ .kind = .blaster, .element = .kinetic, .core = .accelerator, .level = 1 },
    .{ .kind = .energy_bow, .element = .cryo_deuterium, .core = .quantum_warp, .level = 1 },
    .{ .kind = .tracking_missile, .element = .rootsong, .core = .hydra_swarm, .level = 1 },
},
active_slot_idx: usize = 0,

saber: Weapon.BeamSaber = .{},
blaster: Weapon.Blaster = .{},
bow: Weapon.EnergyBow = .{},
shield: Weapon.ProtectiveShield = .{},
giant_blast: Weapon.GiantBlast = .{},
projectiles: Projectile.ProjectilePool = .{},

/// Pending warp strike target: if set, player can teleport instantly to this location!
warp_strike_pending: ?V = null,
warp_strike_timer: f32 = 0,

pub fn activeSlot(self: *CombatSystem) *Weapon.WeaponSlot {
    return &self.slots[self.active_slot_idx];
}

pub fn cycleWeapon(self: *CombatSystem) void {
    self.active_slot_idx = (self.active_slot_idx + 1) % MaxSlots;
}

pub fn update(self: *CombatSystem, physics: *const Physics, dt: f32) void {
    const slot = self.activeSlot().*;
    self.saber.update(dt);
    self.blaster.update(dt, slot);
    self.bow.update(dt);
    self.shield.update(dt);
    self.giant_blast.update(dt, slot, self.giant_blast.charging);

    if (self.warp_strike_pending != null) {
        self.warp_strike_timer = @max(0, self.warp_strike_timer - dt);
        if (self.warp_strike_timer == 0) {
            self.warp_strike_pending = null;
        }
    }

    var hits: [32]Projectile.HitEvent = undefined;
    const hit_count = self.projectiles.step(physics, dt, &hits);
    for (hits[0..hit_count]) |hit| {
        if (hit.is_warp) {
            // Warp arrow landed! Set target for teleport strike
            self.warp_strike_pending = hit.position;
            self.warp_strike_timer = 3.0; // 3 seconds to take the warp strike
        }
    }
}

/// Execute Zero-style saber slash
pub fn attackSaber(self: *CombatSystem, is_dashing: bool, is_airborne: bool) Weapon.SlashResult {
    return self.saber.slash(is_dashing, is_airborne, self.slots[0]);
}

/// Start / release Blaster Buster charge
pub fn chargeBlaster(self: *CombatSystem, charging: bool) void {
    self.blaster.is_charging = charging;
}

pub fn fireBlaster(self: *CombatSystem, origin: V, dir: V) ?usize {
    const shot = self.blaster.releaseShot(self.slots[1]) orelse return null;
    const kind: Projectile.ProjectileKind = if (shot.level >= 2) .charged_plasma else .blaster_bolt;
    const spawned = self.projectiles.spawn(
        kind,
        origin,
        dir,
        shot.speed,
        shot.damage,
        self.slots[1].element,
        2.5,
        null,
    );
    if (spawned) |i| self.projectiles.items[i].radius = shot.size;
    return spawned;
}

/// Draw and fire Energy Bow
pub fn drawBow(self: *CombatSystem, drawing: bool) void {
    self.bow.is_drawing = drawing;
}

pub fn fireBow(self: *CombatSystem, origin: V, dir: V, as_warp_arrow: bool) ?usize {
    const release = self.bow.release(as_warp_arrow, self.slots[2]) orelse return null;
    const kind: Projectile.ProjectileKind = if (release.is_warp) .warp_arrow else .energy_arrow;
    return self.projectiles.spawn(
        kind,
        origin,
        dir,
        release.speed,
        release.damage,
        self.slots[2].element,
        3.5,
        null,
    );
}

/// Fire homing tracking missiles
pub fn fireMissiles(self: *CombatSystem, origin: V, forward_dir: V, target_pos: ?V) usize {
    const slot = self.slots[3];
    const count: usize = if (slot.core == .hydra_swarm) 4 else 2;
    var spawned: usize = 0;
    const up: V = .{ 0, 1, 0 };
    const right = R.normalize(R.cross(forward_dir, up));

    for (0..count) |i| {
        const spread_offset = (@as(f32, @floatFromInt(i)) - (@as(f32, @floatFromInt(count)) - 1.0) / 2.0) * 0.8;
        const launch_dir = R.normalize(R.add(forward_dir, R.add(R.scale(up, 0.4), R.scale(right, spread_offset))));
        if (self.projectiles.spawn(
            .tracking_missile,
            origin,
            launch_dir,
            38.0,
            slot.baseDamage(),
            slot.element,
            4.0,
            target_pos,
        ) != null) {
            spawned += 1;
        }
    }
    return spawned;
}

/// Consume warp strike: returns the destination point to teleport player to!
pub fn consumeWarpStrike(self: *CombatSystem) ?V {
    const dest = self.warp_strike_pending;
    self.warp_strike_pending = null;
    self.warp_strike_timer = 0;
    return dest;
}

test "Zero-style beam saber combo chain, dash slash, and charge slash" {
    var combat: CombatSystem = .{};
    const slot = combat.slots[0];
    try std.testing.expectEqual(Weapon.WeaponKind.beam_saber, slot.kind);

    // Normal 3-hit combo
    const hit1 = combat.attackSaber(false, false);
    try std.testing.expectEqual(@as(u8, 1), hit1.combo);
    try std.testing.expect(hit1.damage > 0);

    const hit2 = combat.attackSaber(false, false);
    try std.testing.expectEqual(@as(u8, 2), hit2.combo);
    try std.testing.expect(hit2.damage > hit1.damage);

    const hit3 = combat.attackSaber(false, false);
    try std.testing.expectEqual(@as(u8, 3), hit3.combo);
    try std.testing.expect(hit3.damage > hit2.damage);

    // Dash slash
    const dash_hit = combat.attackSaber(true, false);
    try std.testing.expectEqual(@as(u8, 10), dash_hit.combo);
    try std.testing.expect(dash_hit.damage > hit1.damage);

    // Charge slash
    combat.saber.is_charging = true;
    combat.saber.update(1.5);
    const charge_hit = combat.attackSaber(false, false);
    try std.testing.expectEqual(@as(u8, 4), charge_hit.combo);
    try std.testing.expect(charge_hit.damage > hit3.damage);
}

test "blaster charge levels and projectile firing" {
    var combat: CombatSystem = .{};
    combat.chargeBlaster(true);
    combat.blaster.update(0.1, combat.slots[1]);
    try std.testing.expectEqual(@as(u8, 0), combat.blaster.charge_level);

    combat.blaster.update(0.8, combat.slots[1]);
    try std.testing.expect(combat.blaster.charge_level >= 2);

    combat.blaster.update(1.0, combat.slots[1]);
    try std.testing.expectEqual(@as(u8, 3), combat.blaster.charge_level);

    const shot_idx = combat.fireBlaster(.{ 0, 10, 0 }, .{ 0, 0, 1 });
    try std.testing.expect(shot_idx != null);
    try std.testing.expectEqual(Projectile.ProjectileKind.charged_plasma, combat.projectiles.items[shot_idx.?].kind);
}

test "energy bow draw, warp arrow firing, and teleport warp strike" {
    var combat: CombatSystem = .{};
    combat.drawBow(true);
    combat.bow.update(0.6);
    try std.testing.expect(combat.bow.draw > 0.5);

    const arrow_idx = combat.fireBow(.{ 10, 5, 20 }, .{ 0, 0, 1 }, true);
    try std.testing.expect(arrow_idx != null);
    try std.testing.expectEqual(Projectile.ProjectileKind.warp_arrow, combat.projectiles.items[arrow_idx.?].kind);

    // Simulate arrow landing and triggering warp strike
    combat.warp_strike_pending = .{ 50, 10, 80 };
    combat.warp_strike_timer = 3.0;

    const teleport_dest = combat.consumeWarpStrike();
    try std.testing.expect(teleport_dest != null);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), teleport_dest.?[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), teleport_dest.?[2], 0.001);
    try std.testing.expect(combat.warp_strike_pending == null);
}

test "homing tracking missiles steering and multi-launch" {
    var combat: CombatSystem = .{};
    const target: V = .{ 100, 20, 100 };
    const fired = combat.fireMissiles(.{ 0, 10, 0 }, .{ 0, 0, 1 }, target);
    try std.testing.expectEqual(@as(usize, 4), fired); // Hydra swarm core fires 4
    try std.testing.expectEqual(Projectile.ProjectileKind.tracking_missile, combat.projectiles.items[0].kind);
    try std.testing.expect(combat.projectiles.items[0].homing_target != null);
}

test "protective shield absorption, break cooldown, and parry window" {
    var combat: CombatSystem = .{};
    combat.shield.raise();
    try std.testing.expect(combat.shield.active);

    // Immediate attack within parry window:
    const parry_res = combat.shield.absorb(50.0, combat.slots[0]);
    try std.testing.expect(parry_res.parried);
    try std.testing.expectEqual(@as(f32, 0), parry_res.leftover);

    // Expire parry window and take heavy damage
    combat.shield.update(0.3);
    const hit_res = combat.shield.absorb(60.0, combat.slots[0]);
    try std.testing.expect(!hit_res.parried);
    try std.testing.expectEqual(@as(f32, 0), hit_res.leftover);
    try std.testing.expectEqual(@as(f32, 60.0), combat.shield.health);
}

test "giant energy blast charge, duration, and damage beam" {
    var combat: CombatSystem = .{};
    combat.giant_blast.startCharge();
    combat.giant_blast.update(1.8, combat.slots[0], true);
    try std.testing.expect(combat.giant_blast.ready);

    const beam = combat.giant_blast.fire(combat.slots[0]);
    try std.testing.expect(beam != null);
    try std.testing.expect(beam.?.dps > 100.0);
    try std.testing.expect(beam.?.beam_length >= 80.0);
    try std.testing.expect(combat.giant_blast.firing);
}

test "giant blast charge tiers require a held trigger and scale the released beam" {
    var quick: Weapon.GiantBlast = .{};
    const base_slot: Weapon.WeaponSlot = .{ .kind = .giant_blast, .core = .overdrive_core, .level = 1 };
    const upgraded_slot: Weapon.WeaponSlot = .{ .kind = .giant_blast, .core = .overdrive_core, .level = 3 };
    quick.startCharge();
    quick.update(0.9, base_slot, true);
    try std.testing.expect(!quick.ready);
    quick.update(0.2, base_slot, true);
    try std.testing.expect(quick.ready);
    const base = quick.fire(base_slot).?;

    var full: Weapon.GiantBlast = .{};
    full.startCharge();
    full.update(2.1, upgraded_slot, true);
    try std.testing.expect(full.ready);
    const charged = full.fire(upgraded_slot).?;
    try std.testing.expect(charged.dps > base.dps);
    try std.testing.expect(charged.beam_width > base.beam_width);
    try std.testing.expect(full.duration > quick.duration);

    var released_early: Weapon.GiantBlast = .{};
    released_early.startCharge();
    released_early.update(0.6, upgraded_slot, false);
    try std.testing.expect(!released_early.ready);
    try std.testing.expect(released_early.fire(upgraded_slot) == null);
}
