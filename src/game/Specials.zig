//! Class specials, paid from each player's energy (0–100, regenerating). Rangers use tech:
//!
//! - **Arc grenade:** a thrown charge that bursts on contact or after 1.2 s: 60 damage and a
//!   two-second stun within 5 m.
//! - **Sentry turret:** a turret set down ahead that zaps the nearest Hive unit in sight four
//!   times a second for 20 s (one per player).
//! - **Overshield:** 80 points of shield over health for 8 s.
//!
//! Synthetics have powers:
//!
//! - **Phase dash:** a blink up to 14 m ahead (stopping short of walls) that cuts and stuns
//!   everything along the path.
//! - **Kinetic slam:** a shockwave around the body: 70 damage within 8 m, thrown back and
//!   stunned.
//! - **Lumen lance:** a 2.5 s channelled beam along the aim, 90 damage a second; a second press
//!   ends it early.
//!
//! Rangers regenerate energy faster; synthetics carry more health and cut harder (applied by
//! the caller through `healthBonus` and `meleeScale`).
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Profile = @import("Profile.zig");
const Enemies = @import("Enemies.zig");
const Combat = @import("Combat.zig");
const Ranger = @import("../character/Ranger.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Specials = @This();

pub const max_players = 4;
pub const max_energy: f32 = 100;
pub const max_grenades = 8;

pub const Kind = enum { arc_grenade, sentry, overshield, phase_dash, kinetic_slam, lumen_lance };
pub const Info = struct { cost: f32, cooldown: f32, label: []const u8 };

pub fn info(kind: Kind) Info {
    return switch (kind) {
        .arc_grenade => .{ .cost = 30, .cooldown = 4, .label = "ARC GRENADE" },
        .sentry => .{ .cost = 50, .cooldown = 15, .label = "SENTRY" },
        .overshield => .{ .cost = 40, .cooldown = 12, .label = "OVERSHIELD" },
        .phase_dash => .{ .cost = 25, .cooldown = 2.5, .label = "PHASE DASH" },
        .kinetic_slam => .{ .cost = 40, .cooldown = 6, .label = "KINETIC SLAM" },
        .lumen_lance => .{ .cost = 60, .cooldown = 10, .label = "LUMEN LANCE" },
    };
}

/// The three specials of a class, in key order (special 1–3).
pub fn kit(class: Profile.Class) [3]Kind {
    return switch (class) {
        .ranger => .{ .arc_grenade, .sentry, .overshield },
        .synthetic => .{ .phase_dash, .kinetic_slam, .lumen_lance },
    };
}

/// Energy per second.
pub fn regen(class: Profile.Class) f32 {
    return switch (class) {
        .ranger => 10,
        .synthetic => 7,
    };
}

/// Extra maximum health.
pub fn healthBonus(class: Profile.Class) f32 {
    return switch (class) {
        .ranger => 0,
        .synthetic => 30,
    };
}

/// Saber damage factor.
pub fn meleeScale(class: Profile.Class) f32 {
    return switch (class) {
        .ranger => 1,
        .synthetic => 1.25,
    };
}

/// What a special needs from its player this step.
pub const Use = struct {
    eye: V,
    forward: V,
    feet: V,
    /// Press edges of special 1–3.
    pressed: [3]bool = @splat(false),
};

pub const Player = struct {
    energy: f32 = max_energy,
    cooldowns: [3]f32 = @splat(0),
    /// Lumen lance channel time left.
    lance: f32 = 0,
    /// The body's cast or throw pose, and how long it holds.
    pose: Ranger.Action = .none,
    pose_left: f32 = 0,
};

pub const Grenade = struct { owner: u8, position: V, velocity: V, fuse: f32 };
pub const Sentry = struct { position: V, life: f32, cooldown: f32 = 0, aim: V = .{ 0, 0, 1 } };

pub const Event = union(enum) {
    used: struct { player: u8, kind: Kind },
    /// Pressed without the energy, or still cooling down.
    denied: u8,
    burst: V,
    blink: struct { player: u8, to: V },
    zap: V,
    hive: Enemies.Event,
};

players: [max_players]Player = @splat(.{}),
grenades: [max_grenades]?Grenade = @splat(null),
sentries: [max_players]?Sentry = @splat(null),

fn push(out: []Event, n: *usize, e: Event) void {
    if (n.* < out.len) out[n.*] = e;
    n.* += 1;
}

fn relay(out: []Event, n: *usize, hive: []const Enemies.Event) void {
    for (hive) |e| push(out, n, .{ .hive = e });
}

fn flat(v: V) V {
    const h: V = .{ v[0], 0, v[2] };
    const l = R.length(h);
    return if (l > 0.05) R.scale(h, 1 / l) else .{ 0, 0, 1 };
}

/// The pose a special holds the body in, if any (it overrides the weapon's).
pub fn stance(self: *const Specials, p: usize) ?Combat.Stance {
    const s = self.players[p];
    if (s.lance > 0) return .{ .action = .cast };
    if (s.pose_left > 0) return .{ .action = s.pose, .t = 1 - s.pose_left / 0.35 };
    return null;
}

/// One fixed step of player `p`'s specials: energy, cooldowns, presses and the lance channel.
pub fn step(self: *Specials, p: u8, class: Profile.Class, physics: *const Physics, enemies: *Enemies, combat: *Combat, use: Use, dt: f32, out: []Event) usize {
    var n: usize = 0;
    var hive: [16]Enemies.Event = undefined;
    var hn: usize = 0;
    const s = &self.players[p];
    s.energy = @min(max_energy, s.energy + regen(class) * dt);
    for (&s.cooldowns) |*c| c.* = @max(0, c.* - dt);
    s.pose_left = @max(0, s.pose_left - dt);
    const kinds = kit(class);
    for (use.pressed, 0..) |pressed, i| if (pressed) {
        const kind = kinds[i];
        // A second press ends the lance early.
        if (kind == .lumen_lance and s.lance > 0) {
            s.lance = 0;
            continue;
        }
        const about = info(kind);
        if (s.cooldowns[i] > 0 or s.energy < about.cost) {
            push(out, &n, .{ .denied = p });
            continue;
        }
        s.energy -= about.cost;
        s.cooldowns[i] = about.cooldown;
        push(out, &n, .{ .used = .{ .player = p, .kind = kind } });
        self.activate(p, kind, physics, enemies, combat, use, out, &n, &hive, &hn);
    };
    if (s.lance > 0) {
        s.lance = @max(0, s.lance - dt);
        const reach = if (physics.castRay(use.eye, use.forward, 60, .none)) |hit| hit.distance else 60;
        _ = enemies.strikeCapsule(use.eye, use.forward, reach, 0.6, 90 * dt, &hive, &hn);
        // From the hands, toward where the eyes aim.
        const from = if (combat.arsenals[p].grip) |g| g.base else R.add(use.eye, R.add(R.scale(use.forward, 0.9), .{ 0, -0.4, 0 }));
        const end = R.add(use.eye, R.scale(use.forward, reach));
        const span = R.sub(end, from);
        const length = @max(0.1, R.length(span));
        combat.effects[effectSlot(combat)] = .{ .kind = .beam, .position = from, .dir = R.scale(span, 1 / length), .life = dt * 1.5, .size = 0.55, .length = length, .color = .{ 0.95, 0.9, 1 } };
    }
    relay(out, &n, hive[0..@min(hn, hive.len)]);
    return n;
}

fn effectSlot(combat: *const Combat) usize {
    var oldest: usize = 0;
    for (combat.effects, 0..) |slot, i| {
        const e = slot orelse return i;
        if (e.age > combat.effects[oldest].?.age) oldest = i;
    }
    return oldest;
}

fn effect(combat: *Combat, e: Combat.Effect) void {
    combat.effects[effectSlot(combat)] = e;
}

fn activate(self: *Specials, p: u8, kind: Kind, physics: *const Physics, enemies: *Enemies, combat: *Combat, use: Use, out: []Event, n: *usize, hive: []Enemies.Event, hn: *usize) void {
    const s = &self.players[p];
    const fwd = flat(use.forward);
    switch (kind) {
        .arc_grenade => {
            s.pose = .throw;
            s.pose_left = 0.35;
            const g: Grenade = .{ .owner = p, .position = R.add(use.eye, R.add(R.scale(fwd, 0.6), .{ 0, -0.2, 0 })), .velocity = R.add(R.scale(use.forward, 16), .{ 0, 4, 0 }), .fuse = 1.2 };
            for (&self.grenades) |*slot| if (slot.* == null) {
                slot.* = g;
                break;
            };
        },
        .sentry => {
            s.pose = .throw;
            s.pose_left = 0.35;
            var at = R.add(use.feet, R.scale(fwd, 1.6));
            if (physics.castRay(R.add(at, .{ 0, 1.5, 0 }), .{ 0, -1, 0 }, 6, .none)) |hit| at = hit.point;
            self.sentries[p] = .{ .position = at, .life = 20, .aim = fwd };
        },
        .overshield => {
            combat.vitals[p].shield = 80;
            combat.vitals[p].shield_time = 8;
            effect(combat, .{ .kind = .burst, .position = R.add(use.feet, .{ 0, 1, 0 }), .life = 0.5, .size = 2, .color = .{ 0.4, 0.85, 1 } });
        },
        .phase_dash => {
            s.pose = .cast;
            s.pose_left = 0.2;
            const chest = R.add(use.feet, .{ 0, 1.0, 0 });
            var reach: f32 = 14;
            if (physics.castRay(chest, fwd, reach + 0.6, .none)) |hit| reach = @max(0, hit.distance - 0.6);
            var units: u32 = 0;
            var nests: u16 = 0;
            _ = enemies.strikeBlade(chest, fwd, reach, 1.2, 45, R.add(R.scale(fwd, 4), .{ 0, 2, 0 }), 1.0, &units, &nests, hive, hn);
            effect(combat, .{ .kind = .trail, .position = R.add(chest, R.scale(fwd, reach / 2)), .dir = fwd, .life = 0.3, .size = 0.5, .length = reach, .color = .{ 0.75, 0.9, 1 } });
            push(out, n, .{ .blink = .{ .player = p, .to = R.add(use.feet, R.scale(fwd, reach)) } });
        },
        .kinetic_slam => {
            s.pose = .cast;
            s.pose_left = 0.35;
            const center = R.add(use.feet, .{ 0, 0.8, 0 });
            _ = enemies.strikeArea(center, 8, 70, null, hive, hn);
            _ = enemies.shock(center, 8, 1.5, 14);
            effect(combat, .{ .kind = .burst, .position = center, .life = 0.45, .size = 8, .color = .{ 0.85, 0.75, 1 } });
            push(out, n, .{ .burst = center });
        },
        .lumen_lance => s.lance = 2.5,
    }
}

/// Grenades and sentries: once per fixed step, after the players.
pub fn stepWorld(self: *Specials, physics: *const Physics, enemies: *Enemies, combat: *Combat, dt: f32, out: []Event) usize {
    var n: usize = 0;
    var hive: [16]Enemies.Event = undefined;
    var hn: usize = 0;
    for (&self.grenades) |*slot| if (slot.*) |*g| {
        g.fuse -= dt;
        g.velocity[1] -= 9.81 * dt;
        const travel = R.scale(g.velocity, dt);
        const length = R.length(travel);
        var burst = g.fuse <= 0 or enemies.nearestUnit(g.position, 1.6) != null;
        if (!burst and length > 1e-4) {
            if (physics.castRay(g.position, R.scale(travel, 1 / length), length, .none)) |hit| {
                g.position = hit.point;
                burst = true;
            } else g.position = R.add(g.position, travel);
        }
        if (burst) {
            _ = enemies.strikeArea(g.position, 5, 60, null, &hive, &hn);
            _ = enemies.shock(g.position, 5, 2, 3);
            effect(combat, .{ .kind = .burst, .position = g.position, .life = 0.4, .size = 5, .color = .{ 0.45, 0.8, 1 } });
            push(out, &n, .{ .burst = g.position });
            slot.* = null;
        }
    };
    for (&self.sentries) |*slot| if (slot.*) |*t| {
        t.life -= dt;
        if (t.life <= 0) {
            slot.* = null;
            continue;
        }
        t.cooldown = @max(0, t.cooldown - dt);
        if (t.cooldown > 0) continue;
        const muzzle = R.add(t.position, .{ 0, 1.1, 0 });
        const target = enemies.nearestUnit(muzzle, 40) orelse continue;
        const to = R.sub(target, muzzle);
        const dist = R.length(to);
        if (dist < 0.1) continue;
        const dir = R.scale(to, 1 / dist);
        // Only what the turret can see.
        if (physics.castRay(muzzle, dir, dist, .none)) |hit| if (hit.distance < dist - 1.5) continue;
        t.aim = dir;
        t.cooldown = 0.25;
        _ = enemies.strikeAlong(muzzle, dir, dist + 1, 0.1, 8, &hive, &hn);
        effect(combat, .{ .kind = .beam, .position = muzzle, .dir = dir, .life = 0.08, .size = 0.25, .length = dist, .color = .{ 0.4, 0.95, 1 } });
        push(out, &n, .{ .zap = muzzle });
    };
    relay(out, &n, hive[0..@min(hn, hive.len)]);
    return n;
}

fn testPhysics() Physics {
    return Physics.init(.{ .sample = struct {
        fn f(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
            return .{ .height = 0, .normal = .{ 0, 1, 0 } };
        }
    }.f });
}

test "each class has its own specials, paid in energy and gated by cooldowns" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    var combat: Combat = .{};
    var specials: Specials = .{};
    var events: [32]Event = undefined;
    const dt = 1.0 / 60.0;
    const use: Use = .{ .eye = .{ 0, 1.6, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 0, 0 } };

    // Ranger: the overshield soaks a hit before health.
    var press = use;
    press.pressed = .{ false, false, true };
    _ = specials.step(0, .ranger, &physics, &enemies, &combat, press, dt, &events);
    try std.testing.expect(specials.players[0].energy < 61);
    var hurt: [4]Combat.Event = undefined;
    var hn: usize = 0;
    _ = combat.hurt(0, 50, &hurt, &hn);
    try std.testing.expectEqual(@as(f32, 100), combat.vitals[0].health);
    try std.testing.expectEqual(@as(f32, 30), combat.vitals[0].shield);
    // Pressed again while cooling down: refused, no energy spent.
    const before = specials.players[0].energy;
    const count = specials.step(0, .ranger, &physics, &enemies, &combat, press, dt, &events);
    try std.testing.expect(count >= 1 and events[0] == .denied);
    try std.testing.expect(specials.players[0].energy > before);

    // An arc grenade thrown at a trooper bursts on it and stuns it.
    enemies.units[0] = .{ .kind = .trooper, .nest = 0, .position = .{ 0, 0, 7 }, .health = 500, .orbit = 0 };
    press.pressed = .{ true, false, false };
    _ = specials.step(1, .ranger, &physics, &enemies, &combat, press, dt, &events);
    var bursts: usize = 0;
    for (0..90) |_| {
        const k = specials.stepWorld(&physics, &enemies, &combat, dt, &events);
        for (events[0..@min(k, events.len)]) |e| bursts += @intFromBool(e == .burst);
    }
    try std.testing.expectEqual(@as(usize, 1), bursts);
    try std.testing.expect(enemies.units[0].?.health < 500 and enemies.units[0].?.stun > 1);

    // A sentry zaps the unit in sight.
    press.pressed = .{ false, true, false };
    _ = specials.step(2, .ranger, &physics, &enemies, &combat, press, dt, &events);
    const health = enemies.units[0].?.health;
    for (0..30) |_| _ = specials.stepWorld(&physics, &enemies, &combat, dt, &events);
    try std.testing.expect(enemies.units[0].?.health < health);

    // Synthetic: the phase dash blinks ahead through the trooper and stuns it.
    enemies.units[0].?.stun = 0;
    press.pressed = .{ true, false, false };
    const k = specials.step(3, .synthetic, &physics, &enemies, &combat, press, dt, &events);
    var blinked = false;
    for (events[0..@min(k, events.len)]) |e| if (e == .blink) {
        blinked = e.blink.to[2] > 13;
    };
    try std.testing.expect(blinked and enemies.units[0].?.stun > 0);
    // Kinetic slam throws everything nearby away.
    specials.players[3].energy = max_energy;
    enemies.units[1] = .{ .kind = .drone, .nest = 0, .position = .{ 3, 1, 0 }, .health = 500, .orbit = 0 };
    press.pressed = .{ false, true, false };
    _ = specials.step(3, .synthetic, &physics, &enemies, &combat, press, dt, &events);
    try std.testing.expect(enemies.units[1].?.velocity[0] > 3 and enemies.units[1].?.health < 500);
    // The lumen lance channels a beam; the body holds the cast pose meanwhile.
    press.pressed = .{ false, false, true };
    specials.players[3].energy = max_energy;
    const lance_health = enemies.units[0].?.health;
    _ = specials.step(3, .synthetic, &physics, &enemies, &combat, press, dt, &events);
    for (0..60) |_| _ = specials.step(3, .synthetic, &physics, &enemies, &combat, use, dt, &events);
    try std.testing.expect(enemies.units[0].?.health < lance_health - 80);
    try std.testing.expectEqual(Ranger.Action.cast, specials.stance(3).?.action);
    try std.testing.expectEqual(@as(f32, 1.25), meleeScale(.synthetic));
}
