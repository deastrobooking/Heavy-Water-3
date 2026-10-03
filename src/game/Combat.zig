//! Every local player's arsenal and health. The weapons are the combat module's (`combat/`);
//! this connects them to the world. The party's fabricated weapons are carried by everyone,
//! each player with an own arsenal (selection, charge, cooldowns). P1's weapon tool (5) fires
//! the selected one with the primary button and its alternate with the secondary, and Tab
//! cycles; guests fire with the right trigger and switch with the D-pad. Shots sweep through Hive units and nests before they meet the world (so they hit
//! what they pass), missiles home on the nearest unit, charged shots and missiles burst on
//! impact, a warp arrow carries the archer to where it lands, and the giant blast is a beam.
//!
//! The beam saber is a melee weapon with timed swings: the primary cuts (a three-cut combo, a
//! dash cut while dashing, a spinning cut in the air; a press during a cut queues the next), a
//! held primary charges a wave cut, and the alternate guards (the first 0.3 s parries bolts back
//! at the Hive). Each cut sweeps the blade segment from the player's rig, so it hits what the
//! drawn blade passes through, once per unit per cut, with knockback and stun; it also cuts
//! bolts out of the air, and a cut started near a unit lunges toward it.
//!
//! The energy firearms (`combat/Firearms.zig`) fire instant pierce beams (sniper rifle, scoped
//! with the alternate), heat-limited bolt streams (machine gun), piercing heavy bolts (heavy
//! rifle, alternate charges) and arcing orbs that burst (energy bazooka, alternate detonates).
//!
//! Players take Hive bolts. The raised shield absorbs (a timely raise parries). Health
//! recovers after five quiet seconds; a downed player is restored at the spawn (P1) or beside
//! P1 (guests).
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const CombatSystem = @import("../combat/CombatSystem.zig");
const Weapon = @import("../combat/Weapon.zig");
const Projectile = @import("../combat/Projectile.zig");
const Firearms = @import("../combat/Firearms.zig");
const Enemies = @import("Enemies.zig");
const Rig = @import("Rig.zig");
const Ranger = @import("../character/Ranger.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Combat = @This();

pub const WeaponKind = Weapon.WeaponKind;
pub const max_players = 4;
pub const max_effects = 40;
pub const regen_delay: f32 = 5;
pub const regen_rate: f32 = 10;

/// `shield` is an overshield over health (a Ranger special) that lasts `shield_time`.
pub const Vitals = struct { health: f32 = 100, max: f32 = 100, quiet: f32 = 0, hurt: f32 = 0, shield: f32 = 0, shield_time: f32 = 0 };
pub const EffectKind = enum { slash, beam, burst, spark, muzzle, trail };
/// `length` is a beam's or trail's length (0: the default long beam).
pub const Effect = struct { kind: EffectKind, position: V, dir: V = .{ 0, 0, 1 }, age: f32 = 0, life: f32, size: f32 = 1, length: f32 = 0, color: [3]f32 };

pub const blade_length: f32 = 1.35;
pub const blade_radius: f32 = 0.4;
/// The saber guard parries for this long after it is raised.
pub const parry_window: f32 = 0.3;


/// What an arsenal needs from its player this step.
pub const Aim = struct {
    eye: V,
    forward: V,
    feet: V,
    /// Body facing (radians about +Y; 0 faces +Z).
    yaw: f32 = 0,
    /// The player's skeleton, for where the blade is. Without one an approximate arm is used.
    rig: ?*Rig = null,
    /// The weapon is out (P1's weapon tool, a guest on foot): the body takes weapon poses.
    armed: bool = true,
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
    /// A cut started near a unit: the player's new horizontal velocity toward it.
    lunge: V,
    /// A cut or a bolt that landed on a unit (or a blade that cut a bolt).
    cut: V,
    /// A bazooka orb burst.
    blast: V,
};

/// One saber cut in progress.
pub const Swing = struct {
    arc: Ranger.Arc,
    /// Progress 0–1.
    t: f32 = 0,
    duration: f32,
    damage: f32,
    knock: f32,
    stun: f32,
    units_hit: u32 = 0,
    nests_hit: u8 = 0,
};

pub const Melee = struct {
    swing: ?Swing = null,
    queued: bool = false,
    /// Seconds the guard has been up, while the alternate is held.
    guard: ?f32 = null,
};

/// What the body is doing with the weapon, for the drawn pose and the rig.
pub const Stance = struct {
    action: Ranger.Action = .none,
    t: f32 = 0,
    arc: Ranger.Arc = .forehand,
    pitch: f32 = 0,

    /// `pose` with the weapon's action on its arms.
    pub fn apply(self: Stance, pose: Ranger.Pose) Ranger.Pose {
        var p = pose;
        p.action = self.action;
        p.action_t = self.t;
        p.arc = self.arc;
        p.aim_pitch = self.pitch;
        return p;
    }
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
    melee: Melee = .{},
    firearm: Firearms.State = .{},
    /// The last bazooka orb, for the alternate to detonate.
    orb: ?usize = null,
    /// Field-of-view factor (1, or less while a sniper scope is up), eased.
    zoom: f32 = 1,
    armed: bool = false,
    /// Saber damage factor (the synthetic class cuts harder).
    melee_scale: f32 = 1,
    /// Aim elevation (radians), for the arms.
    pitch: f32 = 0,
    /// Where the weapon is held (right hand) and which way it points, for drawing and muzzles;
    /// null while unarmed.
    grip: ?Grip = null,

    /// Keeps the selection valid: the next owned weapon after `active` (or the first).
    pub fn select(self: *Arsenal, owned: u16, next: bool) void {
        const count = @typeInfo(WeaponKind).@"enum".fields.len;
        if (owned == 0) {
            self.active = null;
            return;
        }
        var i: usize = if (self.active) |a| @intFromEnum(a) else count - 1;
        if (self.active != null and !next and owned & (@as(u16, 1) << @intCast(i)) != 0) return;
        for (0..count) |_| {
            i = (i + 1) % count;
            if (owned & (@as(u16, 1) << @intCast(i)) != 0) {
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
        self.system.saber.charge_time = 0;
        self.melee = .{};
        self.firearm.hold = 0;
    }

    /// The pose the weapon puts the body in.
    pub fn stance(self: *const Arsenal) Stance {
        const k = self.active orelse return .{};
        if (!self.armed) return .{};
        if (self.melee.swing) |sw| return .{ .action = .swing, .t = sw.t, .arc = sw.arc };
        return .{ .pitch = self.pitch, .action = switch (k) {
            .beam_saber => if (self.melee.guard != null) .guard else .none,
            .protective_shield => if (self.system.shield.active) .guard else .none,
            .giant_blast => .cast,
            else => .aim,
        } };
    }

    /// The guard the Hive's bolts meet: a saber guard raised (parrying at first).
    pub fn guard(self: *const Arsenal) Enemies.Guard {
        if (self.active != .beam_saber or !self.armed) return .none;
        const g = self.melee.guard orelse return .none;
        return if (g < parry_window) .parry else .guard;
    }

    /// The active weapon's charge (0–1) for the HUD.
    pub fn charge(self: *const Arsenal) f32 {
        const s = &self.system;
        const k = self.active orelse return 0;
        return switch (k) {
            .blaster => if (s.blaster.is_charging) @min(1, s.blaster.charge_time / 1.6) else 0,
            .energy_bow => s.bow.draw,
            .beam_saber => if (s.saber.is_charging) @min(1, s.saber.charge_time / 1.2) else 0,
            .sniper_rifle, .machine_gun, .heavy_rifle, .energy_bazooka => self.firearm.meter(Firearms.of(k).?),
            .giant_blast => if (self.beam != null) 1 else @min(1, s.giant_blast.charge / 1.5),
            .protective_shield => s.shield.health / s.shield.max_health,
            .tracking_missile => 0,
        };
    }
};

arsenals: [max_players]Arsenal = @splat(.{}),
vitals: [max_players]Vitals = @splat(.{}),
effects: [max_effects]?Effect = @splat(null),
/// Firearm spread.
rng: std.Random.DefaultPrng = .init(0x5ab3e),

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
        v.shield_time = @max(0, v.shield_time - dt);
        if (v.shield_time == 0) v.shield = 0;
        v.quiet += dt;
        if (v.quiet > regen_delay) v.health = @min(v.max, v.health + regen_rate * dt);
    }
}

/// One fixed step of player `p`'s arsenal: weapon timers, triggers, projectiles and the beam.
pub fn step(self: *Combat, player: u8, physics: *const Physics, enemies: *Enemies, owned: u16, aim: Aim, dt: f32, out: []Event) usize {
    var n: usize = 0;
    var hive: [16]Enemies.Event = undefined;
    var hn: usize = 0;
    const arsenal = &self.arsenals[player];
    arsenal.select(owned, aim.cycle);
    arsenal.armed = aim.armed;
    arsenal.pitch = std.math.asin(std.math.clamp(aim.forward[1], -1, 1));
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
    // Shots leave the held weapon (its grip last step) along the aim.
    const muzzle = if (arsenal.grip) |g| R.add(g.base, R.scale(aim.forward, 0.6)) else R.add(aim.eye, R.add(R.scale(aim.forward, 0.8), .{ 0, -0.25, 0 }));
    if (kind) |k| switch (k) {
        .blaster => {
            if (pressed) s.chargeBlaster(true);
            if (released) if (s.fireBlaster(muzzle, aim.forward) != null) {
                push(out, &n, .{ .fired = .blaster });
                self.effect(.{ .kind = .muzzle, .position = muzzle, .life = 0.08, .size = 0.5, .color = .{ 0.4, 0.9, 1 } });
            };
        },
        .beam_saber => self.stepSaber(arsenal, enemies, aim, pressed, released, dt, out, &n, &hive, &hn),
        .sniper_rifle, .machine_gun, .heavy_rifle, .energy_bazooka => self.fireArm(arsenal, k, physics, enemies, aim, muzzle, dt, out, &n, &hive, &hn),
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

    arsenal.grip = if (aim.armed and arsenal.active != null) blk: {
        const g = blade(aim, arsenal.stance());
        // Guns point where the eyes aim; the saber follows the forearm.
        break :blk if (arsenal.active == .beam_saber) g else .{ .base = g.base, .dir = aim.forward };
    } else null;

    // A sniper scope narrows the view.
    const scoped = kind != null and Firearms.of(kind.?) == .sniper_rifle and arsenal.firearm.scoped(.sniper_rifle);
    arsenal.zoom += ((if (scoped) @as(f32, 0.3) else 1) - arsenal.zoom) * @min(1, dt * 12);

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
        if (enemies.strikeThrough(p.position, dir, speed * dt, p.radius, p.damage, 1, &p.hit_units, &hive, &hn)) |t| {
            const at = R.add(p.position, R.scale(dir, t));
            if (p.kind == .bazooka_orb) {
                self.burstOrb(enemies, at, p.damage, out, &n, &hive, &hn);
                p.active = false;
                s.projectiles.active_count -|= 1;
                continue;
            }
            if (p.pierce > 0) {
                // Through it and on, still flying.
                p.pierce -= 1;
                self.effect(.{ .kind = .spark, .position = at, .life = 0.25, .size = 0.7, .color = Weapon.Element.color(p.element)[0..3].* });
                push(out, &n, .{ .cut = at });
                continue;
            }
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
        if (h.kind == .bazooka_orb) {
            self.burstOrb(enemies, h.position, h.damage, out, &n, &hive, &hn);
            continue;
        }
        if (h.kind == .charged_plasma or h.kind == .tracking_missile) _ = enemies.strikeArea(h.position, 3, h.damage * 0.5, null, &hive, &hn);
        self.effect(.{ .kind = if (h.kind == .tracking_missile) .burst else .spark, .position = h.position, .life = 0.3, .size = if (h.kind == .tracking_missile) 2.5 else 0.6, .color = Weapon.Element.color(h.element)[0..3].* });
        push(out, &n, .{ .impact = h.position });
        if (h.is_warp) push(out, &n, .{ .warp = R.add(h.position, R.scale(h.normal, 1.2)) });
    }

    relay(out, &n, hive[0..@min(hn, hive.len)]);
    return n;
}

/// The saber: guard, cuts, the queued next cut, the charged wave, and the blade's sweep.
fn stepSaber(self: *Combat, arsenal: *Arsenal, enemies: *Enemies, aim: Aim, pressed: bool, released: bool, dt: f32, out: []Event, n: *usize, hive: []Enemies.Event, hn: *usize) void {
    const s = &arsenal.system;
    const mel = &arsenal.melee;
    // The alternate raises the guard between cuts.
    mel.guard = if (aim.alt and mel.swing == null) (if (mel.guard) |g| g + dt else 0) else null;
    if (pressed) {
        if (mel.swing) |sw| {
            if (sw.t > 0.3) mel.queued = true;
        } else cut(arsenal, enemies, aim, out, n);
    }
    // Holding the primary after a cut charges the wave cut; releasing it full unleashes it.
    if (released) {
        if (mel.swing == null and s.saber.charge_time >= 1.2) cut(arsenal, enemies, aim, out, n);
        s.saber.charge_time = 0;
        s.saber.is_charging = false;
    } else s.saber.is_charging = aim.fire and mel.swing == null and mel.guard == null;

    if (mel.swing == null) return;
    const sw = &mel.swing.?;
    const before = sw.t;
    sw.t = @min(1, sw.t + dt / sw.duration);
    const fwd = flat(aim);
    const knock = R.add(R.scale(fwd, sw.knock), .{ 0, sw.knock * 0.25, 0 });
    // Three samples along the step, so a fast blade does not skip a unit.
    var b: Blade = undefined;
    for (1..4) |k| {
        const t = before + (sw.t - before) * @as(f32, @floatFromInt(k)) / 3;
        b = blade(aim, .{ .action = .swing, .t = t, .arc = sw.arc });
        const tip = R.add(b.base, R.scale(b.dir, blade_length));
        if (enemies.strikeBlade(b.base, b.dir, blade_length, blade_radius, sw.damage, knock, sw.stun, &sw.units_hit, &sw.nests_hit, hive, hn) > 0) {
            push(out, n, .{ .cut = tip });
            self.effect(.{ .kind = .spark, .position = tip, .life = 0.2, .size = 0.9, .color = .{ 1, 0.85, 0.4 } });
        }
        if (enemies.cutBolts(b.base, b.dir, blade_length, blade_radius + 0.15) > 0) push(out, n, .{ .cut = tip });
    }
    self.effect(.{ .kind = .trail, .position = R.add(b.base, R.scale(b.dir, blade_length / 2)), .dir = b.dir, .life = 0.12, .size = 0.08, .length = blade_length, .color = .{ 1, 0.8, 0.3 } });
    if (sw.t >= 1) {
        mel.swing = null;
        if (mel.queued) {
            mel.queued = false;
            cut(arsenal, enemies, aim, out, n);
        }
    }
}

/// Starts a cut: the combo step (or dash, aerial or charged cut) sets the arc and its weight.
fn cut(arsenal: *Arsenal, enemies: *const Enemies, aim: Aim, out: []Event, n: *usize) void {
    const s = &arsenal.system;
    const c = s.attackSaber(aim.dashing, aim.airborne);
    const arc: Ranger.Arc = switch (c.combo) {
        2 => .backhand,
        3 => .overhead,
        4 => .charged,
        10 => .dash,
        11 => .aerial,
        else => .forehand,
    };
    const heavy = arc == .overhead or arc == .charged or arc == .dash;
    arsenal.melee.swing = .{
        .arc = arc,
        .duration = switch (arc) {
            .forehand, .backhand => 0.26,
            .overhead => 0.38,
            .dash => 0.22,
            .aerial, .charged => 0.34,
        },
        .damage = c.damage * arsenal.melee_scale,
        .knock = if (heavy) 14 else 6,
        .stun = if (heavy) 1.5 else 0.4,
    };
    push(out, n, .slash);
    const fwd = flat(aim);
    if (arc == .charged) {
        // A crescent of light that flies on through everything in its path.
        if (s.projectiles.spawn(.saber_wave, R.add(aim.feet, R.add(R.scale(fwd, 1), .{ 0, 1.1, 0 })), fwd, 40, c.damage * 0.6, .solar_lumen, 0.6, null)) |i| s.projectiles.items[i].pierce = 8;
        push(out, n, .{ .fired = .beam_saber });
    }
    // A unit just ahead pulls the cut toward it.
    if (aim.airborne) return;
    const target = enemies.nearestUnit(R.add(aim.feet, R.add(R.scale(fwd, 3.5), .{ 0, 1.2, 0 })), 4.5) orelse return;
    const d = R.sub(target, aim.feet);
    const h: V = .{ d[0], 0, d[2] };
    const dist = R.length(h);
    if (dist > 1.6 and dist < 7.5 and R.dot(R.scale(h, 1 / dist), fwd) > 0.5) push(out, n, .{ .lunge = R.scale(h, @min(16, (dist - 1.2) * 5) / dist) });
}

pub const Grip = struct { base: V, dir: V };
const Blade = Grip;

/// The blade for a stance: from the rig's hand along the forearm, or (without a rig) from an
/// approximate right shoulder along the poser's swing direction.
fn blade(aim: Aim, stance: Stance) Blade {
    if (aim.rig) |rig| {
        const h = rig.hand(.{ .feet = aim.feet, .yaw = aim.yaw, .action = stance.action, .action_t = stance.t, .arc = stance.arc, .aim_pitch = std.math.asin(std.math.clamp(aim.forward[1], -1, 1)) });
        return .{ .base = h.position, .dir = h.blade };
    }
    const q = R.axisAngle(.{ 0, 1, 0 }, aim.yaw);
    const shoulder = R.add(aim.feet, R.rotate(q, .{ -0.2, 1.4, 0 }));
    if (stance.action != .swing) return .{ .base = R.add(shoulder, R.scale(aim.forward, 0.55)), .dir = aim.forward };
    const d = Ranger.swingDirection(stance.arc, stance.t);
    const dir = R.rotate(q, .{ d.x, d.y, d.z });
    return .{ .base = R.add(shoulder, R.scale(dir, 0.6)), .dir = dir };
}

/// The aim's horizontal direction (the body's facing when looking straight up or down).
fn flat(aim: Aim) V {
    const h: V = .{ aim.forward[0], 0, aim.forward[2] };
    const l = R.length(h);
    return if (l > 0.05) R.scale(h, 1 / l) else .{ @sin(aim.yaw), 0, @cos(aim.yaw) };
}

/// The energy firearms: beams are instant, bolts and orbs join the projectile pool.
fn fireArm(self: *Combat, arsenal: *Arsenal, kind: WeaponKind, physics: *const Physics, enemies: *Enemies, aim: Aim, muzzle: V, dt: f32, out: []Event, n: *usize, hive: []Enemies.Event, hn: *usize) void {
    const s = &arsenal.system;
    const slot = slotFor(arsenal, kind);
    const color = Weapon.Element.color(slot.element)[0..3].*;
    var shots: [2]Firearms.Shot = undefined;
    for (arsenal.firearm.step(Firearms.of(kind).?, slot, aim.fire, aim.alt, dt, &shots)) |shot| switch (shot) {
        .beam => |b| {
            // Stops at the world; pierces `pierce` units on the way.
            const reach = if (physics.castRay(aim.eye, aim.forward, b.range, .none)) |hit| hit.distance else b.range;
            var done: u32 = 0;
            var end = R.add(aim.eye, R.scale(aim.forward, reach));
            if (enemies.strikeThrough(aim.eye, aim.forward, reach, 0.1, b.damage, b.pierce + 1, &done, hive, hn)) |t| {
                const at = R.add(aim.eye, R.scale(aim.forward, t));
                push(out, n, .{ .cut = at });
                self.effect(.{ .kind = .spark, .position = at, .life = 0.3, .size = 1, .color = color });
                // A beam that spent its pierce ends in the last unit.
                if (@popCount(done) == b.pierce + 1) end = at;
            }
            const span = R.sub(end, muzzle);
            const length = @max(0.1, R.length(span));
            self.effect(.{ .kind = .beam, .position = muzzle, .dir = R.scale(span, 1 / length), .life = 0.15, .size = 0.15, .length = length, .color = color });
            push(out, n, .{ .fired = kind });
        },
        .bolt => |b| {
            const dir = self.spread(aim.forward, b.spread);
            if (s.projectiles.spawn(b.kind, muzzle, dir, b.speed, b.damage, slot.element, b.life, null)) |i| {
                s.projectiles.items[i].pierce = b.pierce;
                s.projectiles.items[i].gravity = b.gravity;
                if (b.kind == .bazooka_orb) arsenal.orb = i;
            }
            self.effect(.{ .kind = .muzzle, .position = muzzle, .life = 0.06, .size = if (b.kind == .bazooka_orb) 1 else 0.45, .color = color });
            push(out, n, .{ .fired = kind });
        },
        .detonate => if (arsenal.orb) |i| {
            const p = &s.projectiles.items[i];
            if (p.active and p.kind == .bazooka_orb) {
                self.burstOrb(enemies, p.position, p.damage, out, n, hive, hn);
                p.active = false;
                s.projectiles.active_count -|= 1;
            }
            arsenal.orb = null;
        },
    };
}

/// A bazooka orb bursts: area damage, a shockwave that stuns and throws, a big flash.
fn burstOrb(self: *Combat, enemies: *Enemies, at: V, damage: f32, out: []Event, n: *usize, hive: []Enemies.Event, hn: *usize) void {
    _ = enemies.strikeArea(at, 6, damage, null, hive, hn);
    _ = enemies.shock(at, 6, 0.8, 9);
    self.effect(.{ .kind = .burst, .position = at, .life = 0.5, .size = 6, .color = .{ 1, 0.5, 0.95 } });
    push(out, n, .{ .blast = at });
}

/// `dir` deviated randomly within a cone of `angle` radians.
fn spread(self: *Combat, dir: V, angle: f32) V {
    if (angle <= 0) return dir;
    const random = self.rng.random();
    const side = if (@abs(dir[1]) > 0.95) R.normalize(R.cross(dir, .{ 1, 0, 0 })) else R.normalize(R.cross(dir, .{ 0, 1, 0 }));
    const up = R.cross(side, dir);
    const a = random.float(f32) * 2 * std.math.pi;
    const r = angle * @sqrt(random.float(f32));
    return R.normalize(R.add(dir, R.add(R.scale(side, @cos(a) * r), R.scale(up, @sin(a) * r))));
}

/// A parried Hive bolt flies back as player `p`'s shot.
pub fn deflect(self: *Combat, p: u8, position: V, velocity: V) void {
    const s = &self.arsenals[p].system;
    const speed = @max(1, R.length(velocity));
    _ = s.projectiles.spawn(.blaster_bolt, position, velocity, speed, 30, .solar_lumen, 2, null);
    self.effect(.{ .kind = .spark, .position = position, .life = 0.2, .size = 0.8, .color = .{ 1, 0.85, 0.4 } });
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
    const soaked = @min(v.shield, @max(0, amount));
    v.shield -= soaked;
    amount -= soaked;
    if (amount <= 0) return false;
    v.health -= amount;
    v.hurt = 0.35;
    if (v.health > 0) return false;
    v.health = v.max;
    push(out, n, .{ .downed = p });
    return true;
}

pub fn setMaxHealth(self: *Combat, max: f32) void {
    for (0..max_players) |p| self.setPlayerMax(p, max);
}

/// One player's maximum health; a raise heals by the difference.
pub fn setPlayerMax(self: *Combat, p: usize, max: f32) void {
    const v = &self.vitals[p];
    if (v.max != max) v.health = @max(1, @min(max, v.health + (max - v.max)));
    v.max = max;
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
    const owned: u16 = (1 << @intFromEnum(WeaponKind.blaster)) | (1 << @intFromEnum(WeaponKind.energy_bow));
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
    const owned: u16 = 1 << @intFromEnum(WeaponKind.blaster);
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
    const saber: u16 = 1 << @intFromEnum(WeaponKind.beam_saber);
    c.arsenals[2].active = null;
    aim.fire = true;
    _ = c.step(2, &physics, &enemies, saber, aim, 1.0 / 60.0, &events);
    aim.fire = false;
    for (0..30) |_| _ = c.step(2, &physics, &enemies, saber, aim, 1.0 / 60.0, &events);
    try std.testing.expect(enemies.units[1].?.health < 500);
    try std.testing.expectEqual(@as(f32, 500), enemies.units[2].?.health);
}

test "saber cuts land once per swing, chain through a queued press, charge a wave, and guard" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    enemies.units[0] = .{ .kind = .trooper, .nest = 0, .position = .{ 0, 0, 1.6 }, .health = 2000, .orbit = 0 };
    var c: Combat = .{};
    const owned: u16 = 1 << @intFromEnum(WeaponKind.beam_saber);
    var events: [32]Event = undefined;
    const dt = 1.0 / 60.0;
    var aim: Aim = .{ .eye = .{ 0, 1.6, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 0, 0 }, .fire = true };
    _ = c.step(0, &physics, &enemies, owned, aim, dt, &events);
    const first = c.arsenals[0].melee.swing.?;
    try std.testing.expectEqual(Ranger.Arc.forehand, first.arc);
    try std.testing.expectEqual(Ranger.Action.swing, c.arsenals[0].stance().action);
    // Mid-cut, a second press queues the backhand.
    aim.fire = false;
    var arcs: [3]bool = @splat(false);
    var stunned = false;
    for (0..50) |i| {
        aim.fire = i == 10;
        _ = c.step(0, &physics, &enemies, owned, aim, dt, &events);
        if (c.arsenals[0].melee.swing) |sw| arcs[@intFromEnum(sw.arc)] = true;
        if (enemies.units[0]) |u| stunned = stunned or u.stun > 0;
    }
    try std.testing.expect(arcs[@intFromEnum(Ranger.Arc.backhand)] and stunned);
    // Each cut hits the trooper once, however many samples overlap it.
    const second = Weapon.WeaponSlot{ .kind = .beam_saber, .element = .solar_lumen, .core = .plasma_edge, .level = 1 };
    const one = second.baseDamage();
    try std.testing.expectApproxEqAbs(@as(f32, 2000) - one - one * 1.35, enemies.units[0].?.health, 0.01);

    // Holding the primary charges; releasing it full cuts a wave that flies on.
    aim.fire = true;
    for (0..100) |_| _ = c.step(0, &physics, &enemies, owned, aim, dt, &events);
    try std.testing.expect(c.arsenals[0].charge() > 0.99);
    aim.fire = false;
    _ = c.step(0, &physics, &enemies, owned, aim, dt, &events);
    try std.testing.expectEqual(Ranger.Arc.charged, c.arsenals[0].melee.swing.?.arc);
    var waves: usize = 0;
    for (c.arsenals[0].system.projectiles.items) |p| waves += @intFromBool(p.active and p.kind == .saber_wave and p.pierce >= 7);
    try std.testing.expectEqual(@as(usize, 1), waves);
    for (0..30) |_| _ = c.step(0, &physics, &enemies, owned, aim, dt, &events);

    // The guard parries for its first moments, then blocks.
    aim.alt = true;
    _ = c.step(0, &physics, &enemies, owned, aim, dt, &events);
    try std.testing.expectEqual(Enemies.Guard.parry, c.arsenals[0].guard());
    for (0..30) |_| _ = c.step(0, &physics, &enemies, owned, aim, dt, &events);
    try std.testing.expectEqual(Enemies.Guard.guard, c.arsenals[0].guard());
    try std.testing.expectEqual(Ranger.Action.guard, c.arsenals[0].stance().action);
}

test "the sniper beam pierces one unit, the scope zooms, and a bazooka orb bursts and stuns" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    for (0..3) |i| enemies.units[i] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 1.6, 40 + 25 * @as(f32, @floatFromInt(i)) }, .health = 1000, .orbit = 0 };
    var c: Combat = .{};
    var events: [32]Event = undefined;
    const dt = 1.0 / 60.0;
    const sniper: u16 = 1 << @intFromEnum(WeaponKind.sniper_rifle);
    var aim: Aim = .{ .eye = .{ 0, 1.6, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 0, 0 }, .alt = true };
    for (0..40) |_| _ = c.step(0, &physics, &enemies, sniper, aim, dt, &events);
    try std.testing.expect(c.arsenals[0].zoom < 0.4);
    try std.testing.expectEqual(Ranger.Action.aim, c.arsenals[0].stance().action);
    aim.fire = true;
    _ = c.step(0, &physics, &enemies, sniper, aim, dt, &events);
    try std.testing.expect(enemies.units[0].?.health < 1000 and enemies.units[1].?.health < 1000);
    try std.testing.expectEqual(@as(f32, 1000), enemies.units[2].?.health);

    const bazooka: u16 = 1 << @intFromEnum(WeaponKind.energy_bazooka);
    enemies = .{};
    enemies.units[0] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 1.4, 15 }, .health = 1000, .orbit = 0 };
    enemies.units[1] = .{ .kind = .drone, .nest = 0, .position = .{ 3, 1.4, 17 }, .health = 1000, .orbit = 0 };
    aim = .{ .eye = .{ 0, 1.6, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 0, 0 }, .fire = true };
    var blasts: usize = 0;
    for (0..60) |i| {
        aim.fire = i == 0;
        const count = c.step(1, &physics, &enemies, bazooka, aim, dt, &events);
        for (events[0..@min(count, events.len)]) |e| blasts += @intFromBool(e == .blast);
    }
    try std.testing.expectEqual(@as(usize, 1), blasts);
    // The burst reaches the drone beside the one it struck.
    try std.testing.expect(enemies.units[1].?.health < 1000 and enemies.units[1].?.stun > 0);
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
