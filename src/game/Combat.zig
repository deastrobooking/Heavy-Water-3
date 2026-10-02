//! Every local player's arsenal and health. The weapons are the combat module's (`combat/`);
//! this connects them to the world. The party's fabricated weapons are carried by everyone,
//! each player with an own arsenal (selection, charge, cooldowns). P1's weapon tool (5) fires
//! the selected one with the primary button and its alternate with the secondary, and Tab
//! cycles; guests fire with the right trigger and switch with the D-pad. Shots sweep through Hive units and nests before they meet the world (so they hit
//! what they pass), missiles home on the nearest unit, charged shots and missiles burst on
//! impact, a warp arrow carries the archer to where it lands, and the giant blast is a beam.
//!
//! Players take Hive bolts. The raised shield absorbs (a timely raise parries). Health
//! recovers after five quiet seconds; a downed player is restored at the spawn (P1) or beside
//! P1 (guests).
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const CombatSystem = @import("../combat/CombatSystem.zig");
const Weapon = @import("../combat/Weapon.zig");
const Projectile = @import("../combat/Projectile.zig");
const Enemies = @import("Enemies.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Combat = @This();

pub const WeaponKind = Weapon.WeaponKind;
pub const max_players = 4;
pub const max_effects = 40;
pub const regen_delay: f32 = 5;
pub const regen_rate: f32 = 10;

pub const Vitals = struct { health: f32 = 100, max: f32 = 100, quiet: f32 = 0, hurt: f32 = 0 };
pub const EffectKind = enum { slash, beam, burst, spark, muzzle };
pub const Effect = struct { kind: EffectKind, position: V, dir: V = .{ 0, 0, 1 }, age: f32 = 0, life: f32, size: f32 = 1, color: [3]f32 };

/// What an arsenal needs from its player this step.
pub const Aim = struct {
    eye: V,
    forward: V,
    feet: V,
    dashing: bool = false,
    airborne: bool = false,
    /// Held state of the primary (fire) and secondary (alternate) buttons with the weapon tool.
    fire: bool = false,
    alt: bool = false,
    cycle: bool = false,
};

pub const Event = union(enum) {
    fired: WeaponKind,
    slash: void,
    impact: V,
    warp: V,
    parried: void,
    downed: u8,
    hive: Enemies.Event,
};

/// One player's weapons: the combat system's timers and projectiles, the selection, and the
/// trigger edges.
pub const Arsenal = struct {
    system: CombatSystem = .{},
    /// Selected weapon (one the party has fabricated), if any.
    active: ?WeaponKind = null,
    was_fire: bool = false,
    was_alt: bool = false,
    beam: ?struct { left: f32, dps: f32, width: f32, length: f32 } = null,

    /// Keeps the selection valid: the next owned weapon after `active` (or the first).
    pub fn select(self: *Arsenal, owned: u8, next: bool) void {
        const count = @typeInfo(WeaponKind).@"enum".fields.len;
        if (owned == 0) {
            self.active = null;
            return;
        }
        var i: usize = if (self.active) |a| @intFromEnum(a) else count - 1;
        if (self.active != null and !next and owned & (@as(u8, 1) << @intCast(i)) != 0) return;
        for (0..count) |_| {
            i = (i + 1) % count;
            if (owned & (@as(u8, 1) << @intCast(i)) != 0) {
                self.lowerAll();
                self.active = @enumFromInt(i);
                return;
            }
        }
    }

    fn lowerAll(self: *Arsenal) void {
        self.system.shield.lower();
        self.system.blaster.is_charging = false;
        self.system.bow.is_drawing = false;
        self.system.saber.is_charging = false;
    }

    /// The active weapon's charge (0–1) for the HUD.
    pub fn charge(self: *const Arsenal) f32 {
        const s = &self.system;
        const k = self.active orelse return 0;
        return switch (k) {
            .blaster => if (s.blaster.is_charging) @min(1, s.blaster.charge_time / 1.6) else 0,
            .energy_bow => s.bow.draw,
            .beam_saber => if (s.saber.is_charging) @min(1, s.saber.charge_time / 1.2) else 0,
            .giant_blast => if (self.beam != null) 1 else @min(1, s.giant_blast.charge / 1.5),
            .protective_shield => s.shield.health / s.shield.max_health,
            .tracking_missile => 0,
        };
    }
};

arsenals: [max_players]Arsenal = @splat(.{}),
vitals: [max_players]Vitals = @splat(.{}),
effects: [max_effects]?Effect = @splat(null),

fn slotFor(self: *const Arsenal, kind: WeaponKind) Weapon.WeaponSlot {
    for (self.system.slots) |s| if (s.kind == kind) return s;
    return .{ .kind = kind, .element = .solar_lumen, .core = if (kind == .protective_shield) .aegis_reflector else .overdrive_core };
}

fn effect(self: *Combat, e: Effect) void {
    var oldest: usize = 0;
    for (&self.effects, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = e;
            return;
        }
        if (slot.*.?.age > self.effects[oldest].?.age) oldest = i;
    }
    self.effects[oldest] = e;
}

fn push(out: []Event, n: *usize, e: Event) void {
    if (n.* < out.len) out[n.*] = e;
    n.* += 1;
}

/// Hive events produced by strikes, copied out as `hive` events.
fn relay(out: []Event, n: *usize, hive: []const Enemies.Event) void {
    for (hive) |e| push(out, n, .{ .hive = e });
}

/// Ages effects and recovers health: once per fixed step, before the arsenals.
pub fn tick(self: *Combat, dt: f32) void {
    for (&self.effects) |*slot| if (slot.*) |*e| {
        e.age += dt;
        if (e.age >= e.life) slot.* = null;
    };
    for (&self.vitals) |*v| {
        v.hurt = @max(0, v.hurt - dt);
        v.quiet += dt;
        if (v.quiet > regen_delay) v.health = @min(v.max, v.health + regen_rate * dt);
    }
}

/// One fixed step of player `p`'s arsenal: weapon timers, triggers, projectiles and the beam.
pub fn step(self: *Combat, player: u8, physics: *const Physics, enemies: *Enemies, owned: u8, aim: Aim, dt: f32, out: []Event) usize {
    var n: usize = 0;
    var hive: [16]Enemies.Event = undefined;
    var hn: usize = 0;
    const arsenal = &self.arsenals[player];
    arsenal.select(owned, aim.cycle);
    const s = &arsenal.system;
    const kind = arsenal.active;
    const blaster_slot = s.slots[1];
    s.saber.update(dt);
    s.blaster.update(dt, blaster_slot);
    s.bow.update(dt);
    s.shield.update(dt);
    s.giant_blast.update(dt, slotFor(arsenal, .giant_blast));

    const pressed = aim.fire and !arsenal.was_fire;
    const released = !aim.fire and arsenal.was_fire;
    const alt_pressed = aim.alt and !arsenal.was_alt;
    const alt_released = !aim.alt and arsenal.was_alt;
    arsenal.was_fire = aim.fire;
    arsenal.was_alt = aim.alt;
    const muzzle = R.add(aim.eye, R.add(R.scale(aim.forward, 0.8), .{ 0, -0.25, 0 }));
    if (kind) |k| switch (k) {
        .blaster => {
            if (pressed) s.chargeBlaster(true);
            if (released) if (s.fireBlaster(muzzle, aim.forward) != null) {
                push(out, &n, .{ .fired = .blaster });
                self.effect(.{ .kind = .muzzle, .position = muzzle, .life = 0.08, .size = 0.5, .color = .{ 0.4, 0.9, 1 } });
            };
        },
        .beam_saber => {
            if (alt_pressed) s.saber.is_charging = true;
            if (pressed or alt_released) {
                const cut = s.attackSaber(aim.dashing, aim.airborne);
                const center = R.add(aim.feet, R.add(R.scale(aim.forward, 1.2), .{ 0, 1.1, 0 }));
                _ = enemies.strikeArea(center, cut.radius, cut.damage, aim.forward, &hive, &hn);
                push(out, &n, .slash);
                self.effect(.{ .kind = .slash, .position = center, .dir = aim.forward, .life = 0.18, .size = cut.radius, .color = .{ 1, 0.8, 0.3 } });
            }
        },
        .energy_bow => {
            if (pressed or alt_pressed) s.drawBow(true);
            if (released or alt_released) if (s.fireBow(muzzle, aim.forward, alt_released) != null) push(out, &n, .{ .fired = .energy_bow });
        },
        .tracking_missile => if (pressed) {
            const target = enemies.nearestUnit(R.add(aim.eye, R.scale(aim.forward, 25)), 90);
            if (s.fireMissiles(muzzle, aim.forward, target) > 0) push(out, &n, .{ .fired = .tracking_missile });
        },
        .protective_shield => {
            if (pressed or alt_pressed) s.shield.raise();
            if (!aim.fire and !aim.alt) s.shield.lower();
        },
        .giant_blast => {
            if (pressed) s.giant_blast.startCharge();
            if (released and s.giant_blast.ready) if (s.giant_blast.fire(slotFor(arsenal, .giant_blast))) |b| {
                arsenal.beam = .{ .left = s.giant_blast.duration, .dps = b.dps, .width = b.beam_width, .length = b.beam_length };
                push(out, &n, .{ .fired = .giant_blast });
            };
        },
    };

    // The beam burns along the aim while it lasts.
    if (arsenal.beam) |*b| {
        b.left -= dt;
        _ = enemies.strikeCapsule(aim.eye, aim.forward, b.length, b.width / 2, b.dps * dt, &hive, &hn);
        self.effect(.{ .kind = .beam, .position = aim.eye, .dir = aim.forward, .life = dt * 1.5, .size = b.width, .color = .{ 1, 0.85, 0.35 } });
        if (b.left <= 0) arsenal.beam = null;
    }

    // Projectiles: sweep through the Hive first, then the world.
    for (&s.projectiles.items) |*p| {
        if (!p.active) continue;
        if (p.kind == .tracking_missile) p.homing_target = enemies.nearestUnit(p.position, 60) orelse p.homing_target;
        const speed = R.length(p.velocity);
        if (speed < 1e-3) continue;
        const dir = R.scale(p.velocity, 1 / speed);
        if (enemies.strikeAlong(p.position, dir, speed * dt, p.radius, p.damage, &hive, &hn)) |t| {
            const at = R.add(p.position, R.scale(dir, t));
            if (p.kind == .charged_plasma or p.kind == .tracking_missile) _ = enemies.strikeArea(at, 3, p.damage * 0.5, null, &hive, &hn);
            self.effect(.{ .kind = if (p.kind == .tracking_missile) .burst else .spark, .position = at, .life = 0.35, .size = if (p.kind == .tracking_missile) 2.5 else 0.8, .color = Weapon.Element.color(p.element)[0..3].* });
            push(out, &n, .{ .impact = at });
            if (p.kind == .warp_arrow) push(out, &n, .{ .warp = R.sub(at, R.scale(dir, 2)) });
            p.active = false;
            s.projectiles.active_count -|= 1;
        }
    }
    var hits: [32]Projectile.HitEvent = undefined;
    const world_hits = s.projectiles.step(physics, dt, &hits);
    for (hits[0..@min(world_hits, hits.len)]) |h| {
        if (h.kind == .charged_plasma or h.kind == .tracking_missile) _ = enemies.strikeArea(h.position, 3, h.damage * 0.5, null, &hive, &hn);
        self.effect(.{ .kind = if (h.kind == .tracking_missile) .burst else .spark, .position = h.position, .life = 0.3, .size = if (h.kind == .tracking_missile) 2.5 else 0.6, .color = Weapon.Element.color(h.element)[0..3].* });
        push(out, &n, .{ .impact = h.position });
        if (h.is_warp) push(out, &n, .{ .warp = R.add(h.position, R.scale(h.normal, 1.2)) });
    }

    relay(out, &n, hive[0..@min(hn, hive.len)]);
    return n;
}

/// A Hive bolt reaches player `p` (P1 is 0). The raised shield absorbs P1's hits first.
/// Returns true when the hit downs the player (health is then restored by the caller's respawn).
pub fn hurt(self: *Combat, p: u8, damage: f32, out: []Event, n: *usize) bool {
    var amount = damage;
    const arsenal = &self.arsenals[p];
    if (arsenal.active == .protective_shield and arsenal.system.shield.active) {
        const result = arsenal.system.shield.absorb(damage, slotFor(arsenal, .protective_shield));
        if (result.parried) push(out, n, .parried);
        amount = result.leftover;
    }
    const v = &self.vitals[p];
    v.quiet = 0;
    if (amount <= 0) return false;
    v.health -= amount;
    v.hurt = 0.35;
    if (v.health > 0) return false;
    v.health = v.max;
    push(out, n, .{ .downed = p });
    return true;
}

pub fn setMaxHealth(self: *Combat, max: f32) void {
    for (&self.vitals) |*v| {
        if (v.max != max) v.health = @min(max, v.health + (max - v.max));
        v.max = max;
    }
}

fn testPhysics() Physics {
    return Physics.init(.{ .sample = struct {
        fn f(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
            return .{ .height = -100, .normal = .{ 0, 1, 0 } };
        }
    }.f });
}

test "selection follows the fabricated weapons and cycles among them" {
    var c: Arsenal = .{};
    c.select(0, false);
    try std.testing.expect(c.active == null);
    const owned: u8 = (1 << @intFromEnum(WeaponKind.blaster)) | (1 << @intFromEnum(WeaponKind.energy_bow));
    c.select(owned, false);
    try std.testing.expectEqual(@as(?WeaponKind, .blaster), c.active);
    c.select(owned, true);
    try std.testing.expectEqual(@as(?WeaponKind, .energy_bow), c.active);
    c.select(owned, true);
    try std.testing.expectEqual(@as(?WeaponKind, .blaster), c.active);
}

test "a blaster shot flies into a drone and destroys it; the saber cuts in front only" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    enemies.units[0] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 1.5, 20 }, .health = 10, .orbit = 0 };
    var c: Combat = .{};
    const owned: u8 = 1 << @intFromEnum(WeaponKind.blaster);
    var events: [32]Event = undefined;
    var aim: Aim = .{ .eye = .{ 0, 1.5, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 0, 0 }, .fire = true };
    _ = c.step(2, &physics, &enemies, owned, aim, 1.0 / 60.0, &events);
    aim.fire = false;
    var downed = false;
    for (0..60) |_| {
        const count = c.step(2, &physics, &enemies, owned, aim, 1.0 / 60.0, &events);
        for (events[0..@min(count, events.len)]) |e| if (e == .hive and e.hive == .unit_down) {
            downed = true;
        };
    }
    try std.testing.expect(downed and enemies.units[0] == null);

    enemies.units[1] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 1.1, 1.8 }, .health = 500, .orbit = 0 };
    enemies.units[2] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 1.1, -1.8 }, .health = 500, .orbit = 0 };
    const saber: u8 = 1 << @intFromEnum(WeaponKind.beam_saber);
    c.arsenals[2].active = null;
    aim.fire = true;
    _ = c.step(2, &physics, &enemies, saber, aim, 1.0 / 60.0, &events);
    try std.testing.expect(enemies.units[1].?.health < 500);
    try std.testing.expectEqual(@as(f32, 500), enemies.units[2].?.health);
}

test "the shield absorbs, health regenerates, and a downed player is restored" {
    var c: Combat = .{};
    var events: [8]Event = undefined;
    var n: usize = 0;
    try std.testing.expect(!c.hurt(1, 30, &events, &n));
    try std.testing.expectEqual(@as(f32, 70), c.vitals[1].health);
    for (0..60 * 7) |_| c.tick(1.0 / 60.0);
    try std.testing.expect(c.vitals[1].health > 75);
    try std.testing.expect(c.hurt(1, 500, &events, &n));
    try std.testing.expectEqual(c.vitals[1].max, c.vitals[1].health);
    // A raised shield takes the hit, for any player.
    c.arsenals[3].active = .protective_shield;
    c.arsenals[3].system.shield.raise();
    c.arsenals[3].system.shield.parry_window = 0;
    try std.testing.expect(!c.hurt(3, 20, &events, &n));
    try std.testing.expectEqual(@as(f32, 100), c.vitals[3].health);
    c.setMaxHealth(140);
    try std.testing.expectEqual(@as(f32, 140), c.vitals[0].health);
}
