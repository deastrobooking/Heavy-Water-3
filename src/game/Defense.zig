//! What placed structures do (`game/Outpost.zig`): turrets and launchers shoot the Hive, shield
//! domes soak up its bolts, power modules feed them, the Hive can see and hit structures, and a
//! raid comes to a defended outpost. Everything is bounded and runs in the fixed step with no
//! allocation. Power is one team-wide supply and demand ratio (a light simulation, not a wiring
//! puzzle): a module that draws power works at the fraction the supply covers. Launcher ammo
//! refills slowly for free until stores and workshops arrive (docs/plans/automation-and-defense.md).
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Prefabs = @import("../build/Prefabs.zig");
const Structures = @import("../build/Structures.zig");
const Enemies = @import("Enemies.zig");
const Outpost = @import("Outpost.zig");
const Specials = @import("Specials.zig");
const Sandbox = @import("Sandbox.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;

/// Structures farther than this from every player are not simulated or seen by the Hive.
pub const active_radius: f32 = 160;
/// Seconds after a hit before a shield recharges.
pub const shield_quiet_time: f32 = 3;
/// Missiles a launcher rebuilds per second at full power, until stores exist.
pub const missile_refill: f32 = 1.0 / 12.0;
/// The share of a destroyed structure's scrap and parts its builder gets back.
pub const wreck_refund_percent = 25;

pub const Box = struct { lo: V, hi: V };

pub fn defOf(sb: *const Sandbox, inst: *const Outpost.Instance) ?*const Structures.Def {
    const found = sb.outpost.library.find(inst.id()) orelse return null;
    return sb.outpost.library.get(found);
}

pub fn boxOf(inst: *const Outpost.Instance, def: *const Structures.Def) Box {
    const size = Prefabs.turnedSize(def.size, inst.rot);
    const lo: V = .{ @floatFromInt(inst.origin[0]), @floatFromInt(inst.origin[1]), @floatFromInt(inst.origin[2]) };
    return .{ .lo = lo, .hi = .{ lo[0] + @as(f32, @floatFromInt(size[0])), lo[1] + @as(f32, @floatFromInt(size[1])), lo[2] + @as(f32, @floatFromInt(size[2])) } };
}

/// The middle of the structure's top face, a little above it: where a gun muzzle is, and what the
/// Hive aims at (blocks would hide anything lower from its line of sight).
fn crown(b: Box) V {
    return .{ (b.lo[0] + b.hi[0]) / 2, b.hi[1] + 0.6, (b.lo[2] + b.hi[2]) / 2 };
}

pub fn centre(b: Box) V {
    return .{ (b.lo[0] + b.hi[0]) / 2, (b.lo[1] + b.hi[1]) / 2, (b.lo[2] + b.hi[2]) / 2 };
}

fn near(sb: *const Sandbox, p: V, radius: f32) bool {
    for (0..Sandbox.max_players) |slot| if (sb.present(slot)) {
        const d = R.sub(sb.feetOf(slot), p);
        if (d[0] * d[0] + d[2] * d[2] < radius * radius) return true;
    };
    return false;
}

/// Supply over demand across every structure, 1 when nothing draws power or supply covers it.
pub fn powerSatisfaction(sb: *const Sandbox) f32 {
    var supply: f32 = 0;
    var demand: f32 = 0;
    for (sb.outpost.slice()) |*inst| {
        const def = defOf(sb, inst) orelse continue;
        for (def.moduleSlice()) |m| switch (m.kind) {
            .power => supply += m.power,
            else => demand += m.power,
        };
    }
    if (demand <= 0) return 1;
    if (sb.mining.colony.has(.fusion_cells)) supply *= 1.5;
    return std.math.clamp(supply / demand, 0, 1);
}

/// A module's working fraction: full when it draws nothing, otherwise what the supply covers.
fn working(m: Structures.Module, satisfaction: f32) f32 {
    return if (m.power > 0) satisfaction else 1;
}

fn push(out: []Enemies.Event, n: *usize, e: Enemies.Event) void {
    if (n.* < out.len) out[n.*] = e;
    n.* += 1;
}

/// Whether `p` is inside a live shield dome: its structure index and the dome's radius.
fn coveringShield(sb: *const Sandbox, p: V, satisfaction: f32) ?usize {
    if (satisfaction <= 0) return null;
    for (sb.outpost.slice(), 0..) |*inst, i| {
        if (inst.shield <= 0) continue;
        const def = defOf(sb, inst) orelse continue;
        const m = def.find(.shield) orelse continue;
        const c = centre(boxOf(inst, def));
        if (R.length(R.sub(p, c)) <= m.range) return i;
    }
    return null;
}

fn pulse(sb: *Sandbox, at: V, size: f32, color: [3]f32) void {
    Specials.effect(&sb.combat, .{ .kind = .burst, .position = at, .life = 0.35, .size = size, .color = color });
}

/// Damage to structure `i`: a shield dome over it takes the hit first. A structure at zero is
/// destroyed (its blocks go, its builder gets a quarter of the scrap and parts back).
pub fn hurt(sb: *Sandbox, i: usize, damage: f32) void {
    const out = &sb.outpost;
    if (i >= out.len or damage <= 0) return;
    const inst = &out.placed[i];
    const def = defOf(sb, inst) orelse return;
    const box = boxOf(inst, def);
    var left = damage;
    if (coveringShield(sb, centre(box), powerSatisfaction(sb))) |s| {
        const shield = &out.placed[s];
        const taken = @min(shield.shield, left);
        shield.shield -= taken;
        shield.shield_quiet = 0;
        left -= taken;
        pulse(sb, centre(boxOf(shield, defOf(sb, shield).?)), 2, .{ 0.4, 0.8, 1 });
    }
    if (left <= 0) return;
    inst.health -= left;
    inst.flash = 0.25;
    if (inst.health <= 0) wreck(sb, i);
}

fn wreck(sb: *Sandbox, i: usize) void {
    const out = &sb.outpost;
    const inst = out.placed[i];
    const def = defOf(sb, &inst) orelse return;
    const cost = def.cost();
    const wallet = &sb.kits[@min(inst.owner, Sandbox.max_players - 1)].wallet;
    wallet.scrap +|= cost.scrap * wreck_refund_percent / 100;
    wallet.parts +|= cost.parts * wreck_refund_percent / 100;
    pulse(sb, crown(boxOf(&inst, def)), 5, .{ 1, 0.5, 0.2 });
    sb.say("{s} was destroyed", .{def.name()});
    Outpost.removeCells(sb, i) catch {};
}

/// Before the Hive moves: its bolts meet shield domes and structures. A bolt inside a live dome is
/// absorbed (the dome pays its damage); a bolt inside a structure's box hurts that structure.
pub fn absorbBolts(sb: *Sandbox) void {
    const out = &sb.outpost;
    if (out.len == 0) return;
    const satisfaction = powerSatisfaction(sb);
    for (&sb.enemies.bolts) |*slot| {
        const b = slot.* orelse continue;
        const next = R.add(b.position, R.scale(b.velocity, 1.0 / 60.0));
        if (coveringShield(sb, next, satisfaction)) |s| {
            const shield = &out.placed[s];
            if (shield.shield > 0) {
                shield.shield = @max(0, shield.shield - b.damage);
                shield.shield_quiet = 0;
                pulse(sb, next, 1.2, .{ 0.4, 0.8, 1 });
                slot.* = null;
                continue;
            }
        }
        for (out.slice(), 0..) |*inst, i| {
            const def = defOf(sb, inst) orelse continue;
            const box = boxOf(inst, def);
            const pad = 0.25;
            if (next[0] >= box.lo[0] - pad and next[0] <= box.hi[0] + pad and next[1] >= box.lo[1] - pad and next[1] <= box.hi[1] + pad and next[2] >= box.lo[2] - pad and next[2] <= box.hi[2] + pad) {
                slot.* = null;
                hurt(sb, i, b.damage);
                break;
            }
        }
    }
}

/// Places the structures the Hive can see (within reach of a player) in `out` after the players,
/// aimed at their crowns; returns the new length. `Outpost.State.target_map` maps each back.
pub fn fillTargets(sb: *Sandbox, out: []Enemies.Target, start: usize) usize {
    const state = &sb.outpost;
    state.target_len = 0;
    var n = start;
    for (state.slice(), 0..) |*inst, i| {
        if (n == out.len) break;
        const def = defOf(sb, inst) orelse continue;
        const c = crown(boxOf(inst, def));
        if (!near(sb, c, active_radius)) continue;
        out[n] = .{ .chest = c, .velocity = @splat(0), .alive = inst.health > 0 };
        state.target_map[state.target_len] = @intCast(i);
        state.target_len += 1;
        n += 1;
    }
    return n;
}

/// The structure a Hive target index (past the players) stands for.
pub fn structureOf(sb: *const Sandbox, target: usize, players: usize) ?usize {
    if (target < players) return null;
    const k = target - players;
    if (k >= sb.outpost.target_len) return null;
    return sb.outpost.target_map[k];
}

/// One fixed step of every structure: guns, launchers and shields, then the raid timer. Hive
/// events from kills (units down) go to `out` for the caller to relay; returns how many.
pub fn step(sb: *Sandbox, dt: f32, out: []Enemies.Event) usize {
    var n: usize = 0;
    const state = &sb.outpost;
    if (state.len == 0) return 0;
    const satisfaction = powerSatisfaction(sb);
    var i: usize = 0;
    while (i < state.len) : (i += 1) {
        const inst = &state.placed[i];
        const def = defOf(sb, inst) orelse continue;
        const box = boxOf(inst, def);
        const muzzle = crown(box);
        inst.flash = @max(0, inst.flash - dt);
        inst.cooldown = @max(0, inst.cooldown - dt);
        if (!near(sb, muzzle, active_radius)) continue;
        for (def.moduleSlice()) |m| {
            const work = working(m, satisfaction);
            switch (m.kind) {
                .turret => {
                    inst.cooldown = @max(0, inst.cooldown - dt * (work - 1)); // slower when starved
                    if (inst.cooldown > 0 or work <= 0) continue;
                    const target = sb.enemies.nearestUnit(muzzle, m.range) orelse continue;
                    const to = R.sub(target, muzzle);
                    const dist = R.length(to);
                    if (dist < 0.5) continue;
                    const dir = R.scale(to, 1 / dist);
                    if (sb.physics.castRay(muzzle, dir, dist, .none)) |hit| if (hit.distance < dist - 1.5) continue;
                    inst.cooldown = 1 / m.rate;
                    var hn: usize = 0;
                    var hive: [8]Enemies.Event = undefined;
                    _ = sb.enemies.strikeAlong(muzzle, dir, dist + 1, 0.1, m.damage, &hive, &hn);
                    Specials.effect(&sb.combat, .{ .kind = .beam, .position = muzzle, .dir = dir, .life = 0.08, .size = 0.3, .length = dist, .color = .{ 0.4, 0.95, 1 } });
                    for (hive[0..@min(hn, hive.len)]) |e| push(out, &n, e);
                },
                .launcher => {
                    inst.ammo = @min(m.amount, inst.ammo + dt * missile_refill * work);
                    if (inst.cooldown > 0 or work <= 0 or inst.ammo < 1) continue;
                    const target = sb.enemies.nearestUnit(muzzle, m.range) orelse continue;
                    const to = R.sub(target, muzzle);
                    const dist = R.length(to);
                    if (dist < 6) continue; // too close to fire safely at ourselves
                    const dir = R.scale(to, 1 / dist);
                    if (sb.physics.castRay(muzzle, dir, dist, .none)) |hit| if (hit.distance < dist - 2) continue;
                    inst.ammo -= 1;
                    inst.cooldown = 1 / m.rate;
                    var hn: usize = 0;
                    var hive: [8]Enemies.Event = undefined;
                    _ = sb.enemies.strikeArea(target, 5, m.damage, null, &hive, &hn);
                    Specials.effect(&sb.combat, .{ .kind = .beam, .position = muzzle, .dir = dir, .life = 0.3, .size = 0.5, .length = dist, .color = .{ 1, 0.6, 0.25 } });
                    pulse(sb, target, 5, .{ 1, 0.6, 0.25 });
                    for (hive[0..@min(hn, hive.len)]) |e| push(out, &n, e);
                },
                .shield => {
                    inst.shield_quiet += dt;
                    if (inst.shield_quiet >= shield_quiet_time and work > 0) inst.shield = @min(m.amount, inst.shield + m.rate * work * dt);
                },
                else => {},
            }
        }
    }
    stepRaid(sb, dt);
    return n;
}

// ---------------------------------------------------------------- raids

/// The middle of every structure, for placing a raid around the outpost.
fn outpostCentre(sb: *const Sandbox) V {
    var sum: V = @splat(0);
    var count: f32 = 0;
    for (sb.outpost.slice()) |*inst| {
        const def = defOf(sb, inst) orelse continue;
        sum = R.add(sum, centre(boxOf(inst, def)));
        count += 1;
    }
    return if (count == 0) sum else R.scale(sum, 1 / count);
}

/// The raid timer only runs while a player is at the outpost and no arena is open.
fn stepRaid(sb: *Sandbox, dt: f32) void {
    const state = &sb.outpost;
    if (state.len == 0 or sb.arena.active) return;
    const at = outpostCentre(sb);
    if (!near(sb, at, active_radius)) return;
    state.raid_timer -= dt;
    if (state.raid_timer <= 10 and !state.raid_warned) {
        state.raid_warned = true;
        sb.say("HIVE RAID INCOMING: defend the outpost!", .{});
    }
    if (state.raid_timer > 0) return;
    _ = raid(sb);
    state.raid_timer = Outpost.raid_every;
    state.raid_warned = false;
}

/// Send a raid at the outpost now: a handful of Hive units around it, two plus one for every two
/// structures (at most six). Returns how many arrived (zero if the arena holds the Hive's attention
/// or no unit slot is free).
pub fn raid(sb: *Sandbox) usize {
    const state = &sb.outpost;
    if (state.len == 0 or sb.arena.active) return 0;
    const at = outpostCentre(sb);
    const nest = sb.enemies.addArenaNest(at);
    const random = sb.enemies.rng.random();
    const count = std.math.clamp(2 + state.len / 2, 2, 6);
    const kinds = [_]Enemies.Kind{ .drone, .trooper, .skirmisher, .trooper, .sentinel, .drone };
    const base = random.float(f32) * 2 * std.math.pi;
    var arrived: usize = 0;
    for (0..count) |k| {
        const angle = base + @as(f32, @floatFromInt(k)) * 0.6;
        const x = at[0] + @sin(angle) * 70;
        const z = at[2] + @cos(angle) * 70;
        const ground = Terrain.surface(sb.seed, x, z).height;
        const kind = kinds[k % kinds.len];
        const y = if (Enemies.isGround(kind)) ground + 0.5 else ground + 14;
        if (sb.enemies.spawnAt(kind, nest, .{ x, y, z }, 1)) arrived += 1;
    }
    if (arrived > 0) sb.say("{d} Hive units are attacking the outpost", .{arrived});
    return arrived;
}
