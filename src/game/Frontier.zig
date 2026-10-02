//! Connects the frontier systems to the session: hover cars (`Garage`), pickups
//! (`Collectibles`), the fabricator kiosk, the Hive (`Enemies`) and the arsenal (`Combat`). The
//! Sandbox owns the state; these functions run inside its step, publish and restore.
const std = @import("std");
const math = @import("mach").math;
const Physics = @import("../physics/Physics.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Terrain = @import("../procedural/Terrain.zig");
const District = @import("../procedural/District.zig");
const Material = @import("../render/Material.zig");
const Input = @import("../engine/Input.zig");
const Sandbox = @import("Sandbox.zig");
const Garage = @import("Garage.zig");
const Collectibles = @import("Collectibles.zig");
const Enemies = @import("Enemies.zig");
const Combat = @import("Combat.zig");
const Fabricator = @import("Fabricator.zig");
const Progress = @import("Progress.zig");
const Designs = @import("../vehicle/Designs.zig");
const HiveMeshes = @import("../vehicle/HiveMeshes.zig");
const m = @import("../character/math.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;

/// The fabricator kiosk stands at the head of the garage pads.
pub fn kioskPosition(sb: *const Sandbox) V {
    const pad = Garage.padPosition(sb.seed, Sandbox.spawn, .skimmer);
    const x = pad[0] - 7;
    const z = pad[2];
    return .{ x, Terrain.surface(sb.seed, x, z).height, z };
}

/// Places nests and pickups and parks owned cars. Runs once the world is built.
pub fn init(sb: *Sandbox) void {
    // Nests keep away from the grove, the city, the shrines and the spawn.
    var avoid: [16]V = undefined;
    var a: usize = 0;
    for (0..3) |i| {
        avoid[a] = sb.treeOrigin(i);
        a += 1;
    }
    for (sb.catalog.district.nodes) |node| {
        avoid[a] = node.position;
        a += 1;
    }
    for (sb.shrines) |s| {
        avoid[a] = s.origin;
        a += 1;
    }
    avoid[a] = Sandbox.spawn;
    a += 1;
    sb.enemies = Enemies.init(sb.seed, Sandbox.spawn, avoid[0..a], 140);

    var plazas: [District.node_count]Collectibles.Plaza = undefined;
    for (sb.catalog.district.nodes, &plazas) |node, *p| p.* = .{ .position = node.position, .arbor = node.kind == .arbor };
    var roads: [District.base_edge_count * 2]V = undefined;
    for (sb.catalog.district.edges, 0..) |edge, i| {
        const span = District.span(&sb.catalog.district, edge);
        roads[i * 2] = span.point(0.3);
        roads[i * 2 + 1] = span.point(0.7);
    }
    var roofs: [64]Collectibles.Roof = undefined;
    var r: usize = 0;
    for (sb.catalog.district.buildings[0..sb.catalog.district.building_count]) |b| if (r < roofs.len) {
        roofs[r] = .{ .position = .{ b.base[0], b.roof, b.base[2] }, .half = b.half };
        r += 1;
    };
    var shrines: [Sandbox.shrine_count]V = undefined;
    for (sb.shrines, &shrines) |s, *o| o.* = s.origin;
    var nests: [Enemies.max_nests]V = undefined;
    for (sb.enemies.nests[0..sb.enemies.nest_count], 0..) |n, i| nests[i] = n.position;
    const spawn: V = .{ Sandbox.spawn[0], Terrain.surface(sb.seed, Sandbox.spawn[0], Sandbox.spawn[2]).height, Sandbox.spawn[2] };
    sb.collectibles = Collectibles.generate(.{ .seed = sb.seed, .spawn = spawn, .plazas = &plazas, .roads = &roads, .roofs = roofs[0..r], .shrines = &shrines, .nests = nests[0..sb.enemies.nest_count] });
    // Settle every pickup onto what is really there: above the terrain, onto any deck or roof.
    for (sb.collectibles.items[0..sb.collectibles.count]) |*item| {
        const p = &item.position;
        const ground = Terrain.surface(sb.seed, p[0], p[2]).height;
        if (p[1] < ground + 0.5) p[1] = ground + 0.9;
        if (sb.physics.castRay(R.add(p.*, .{ 0, 2.5, 0 }), .{ 0, -1, 0 }, 8, .none)) |hit| p[1] = hit.point[1] + 0.9;
    }
    refresh(sb);
}

/// After a load (or a new game): nests follow their flags, owned cars park on their pads, and
/// the party's health follows its vital cells.
pub fn refresh(sb: *Sandbox) void {
    for (sb.enemies.nests[0..sb.enemies.nest_count], 0..) |*nest, i| {
        var flag: [16]u8 = undefined;
        const destroyed = sb.progress.hasFlag(nestFlag(&flag, @intCast(i)));
        nest.alive = !destroyed;
        nest.health = if (destroyed) 0 else Enemies.nest_health;
    }
    sb.enemies.units = @splat(null);
    sb.enemies.bolts = @splat(null);
    sb.garage = .{};
    for (0..Designs.count) |d| if (sb.progress.ownsVehicle(@enumFromInt(d))) sb.garage.park(sb.seed, Sandbox.spawn, sb.catalog, @enumFromInt(d));
    sb.collectibles.drops = @splat(null);
    sb.combat.setMaxHealth(sb.progress.maxHealth());
    for (&sb.combat.vitals) |*v| v.health = v.max;
    // Whatever the loaded ranger already wears stays available.
    sb.progress.suits |= Progress.bit(sb.profile.clothing);
    sb.progress.armors |= Progress.armorBit(sb.profile.armor);
}

/// Hover car, fabricator or nothing, along the hands' aim.
pub fn pick(sb: *const Sandbox, eye: V, dir: V, reach: f32, best: f32) ?Sandbox.Target {
    var nearest = @min(best, reach);
    var result: ?Sandbox.Target = null;
    if (sb.garage.pick(eye, dir, nearest)) |hit| {
        nearest = hit.distance;
        result = .{ .car = hit.car };
    }
    const kiosk = kioskPosition(sb);
    if (Physics.rayBox(eye, dir, R.add(kiosk, .{ 0, 1.2, 0 }), .{ 0.8, 1.2, 0.6 })) |hit| if (hit.distance < nearest) {
        result = .fabricator;
    };
    return result;
}

/// Chest positions the Hive aims at: P1 (or P1's car) and active guests.
fn targets(sb: *const Sandbox, out: *[Sandbox.max_players]Enemies.Target) []const Enemies.Target {
    var p1: Enemies.Target = .{ .chest = R.add(sb.player.feet, .{ 0, 1.3, 0 }), .velocity = sb.player.velocity };
    if (sb.garage.piloting) |i| {
        const car = sb.garage.cars[i].?.flyer.body;
        p1 = .{ .chest = .{ car.pos.x, car.pos.y, car.pos.z }, .velocity = .{ car.vel.x, car.vel.y, car.vel.z } };
    }
    out[0] = p1;
    var n: usize = 1;
    for (sb.guests) |g| {
        out[n] = .{ .chest = R.add(g.player.feet, .{ 0, 1.3, 0 }), .velocity = g.player.velocity, .alive = g.active };
        n += 1;
    }
    return out[0..n];
}

fn nestFlag(buffer: []u8, nest: u8) []const u8 {
    return std.fmt.bufPrint(buffer, "nest_{d}_down", .{nest}) catch unreachable;
}

/// Hive outcomes: drops, flags, and hits on players.
fn hive(sb: *Sandbox, e: Enemies.Event, camera: *Camera) void {
    switch (e) {
        .shot => |at| sb.cue(.hive_zap, at),
        .player_hit => |hit| {
            var events: [4]Combat.Event = undefined;
            var n: usize = 0;
            sb.cue(.hurt, if (hit.player == 0) null else R.add(sb.guests[hit.player - 1].player.feet, .{ 0, 1, 0 }));
            if (sb.combat.hurt(hit.player, hit.damage, &events, &n)) down(sb, hit.player, camera);
            for (events[0..@min(n, events.len)]) |ev| if (ev == .parried) sb.say("parried!", .{});
        },
        .unit_down => |u| {
            const random = sb.enemies.rng.random();
            sb.collectibles.drop(.hive_alloy, u.position);
            if (u.kind == .sentinel) {
                sb.collectibles.drop(.hive_alloy, R.add(u.position, .{ 1.2, 0, 0 }));
                sb.collectibles.drop(.hive_alloy, R.add(u.position, .{ -1.2, 0, 0.6 }));
            } else if (random.float(f32) < 0.35) sb.collectibles.drop(.lumen_shard, R.add(u.position, .{ 0.8, 0, 0 }));
            // Drops fall to the floor below.
            for (&sb.collectibles.drops) |*slot| if (slot.*) |*d| {
                if (d.age == 0) if (sb.physics.castRay(d.position, .{ 0, -1, 0 }, 80, .none)) |floor| {
                    d.position[1] = floor.point[1] + 0.9;
                };
            };
            sb.cue(.boom, u.position);
            sb.progress.setFlag("hive_fought");
            sb.say("hive {s} down", .{@tagName(u.kind)});
        },
        .nest_down => |n| {
            var flag: [16]u8 = undefined;
            sb.progress.setFlag(nestFlag(&flag, n.nest));
            sb.progress.setFlag("nest_destroyed");
            sb.cue(.boom, n.position);
            sb.cue(.vault, null);
            for (0..4) |k| sb.collectibles.drop(.hive_alloy, R.add(n.position, .{ @as(f32, @floatFromInt(k)) * 1.5 - 2, 1, 5 }));
            sb.collectibles.drop(.rotor_core, R.add(n.position, .{ 0, 1, 6.5 }));
            sb.say("hive nest destroyed", .{});
        },
    }
}

fn down(sb: *Sandbox, player: u8, camera: *Camera) void {
    if (player == 0) {
        if (sb.garage.piloting != null) _ = sb.garage.leave(&sb.physics);
        sb.resetPlayer(camera);
        sb.say("suit failure: recovered at the spawn", .{});
    } else {
        sb.respawnGuest(player - 1);
        sb.say("P{d} recovered beside P1", .{player + 1});
    }
}

/// The frontier part of a fixed step. `frozen` (menus, talks) pauses triggers, not the world.
pub fn step(sb: *Sandbox, camera: *Camera, input: Input, actions: Sandbox.Actions, frozen: bool, dt: f32) void {
    // Hover cars: the piloted one takes P1's movement keys; parked ones idle.
    sb.garage.step(&sb.physics, if (frozen) .{} else Garage.controls(input), dt);

    // Pickups for every local player.
    var feet: [Sandbox.max_players]V = undefined;
    var fn_count: usize = 0;
    if (sb.garage.piloting == null and sb.seated == null) {
        feet[0] = sb.player.feet;
        fn_count = 1;
    }
    for (sb.guests) |g| if (g.active) {
        feet[fn_count] = g.player.feet;
        fn_count += 1;
    };
    var picked: [8]Collectibles.Event = undefined;
    const got = sb.collectibles.collect(&sb.progress.picked, feet[0..fn_count], dt, &picked);
    for (picked[0..@min(got, picked.len)]) |p| {
        sb.progress.inventory[@intFromEnum(p.kind)] += 1;
        sb.cue(.pickup, p.position);
        if (p.kind == .vital_cell) {
            sb.combat.setMaxHealth(sb.progress.maxHealth());
            sb.say("vital cell: max health {d:.0}", .{sb.progress.maxHealth()});
        } else sb.say("+1 {s} ({d})", .{ Collectibles.label(p.kind), sb.progress.count(p.kind) });
        sb.progress.setFlag("collected");
    }

    // The Hive.
    var who: [Sandbox.max_players]Enemies.Target = undefined;
    var events: [32]Enemies.Event = undefined;
    const count = sb.enemies.step(&sb.physics, targets(sb, &who), dt, &events);
    for (events[0..@min(count, events.len)]) |e| hive(sb, e, camera);

    // The arsenal (weapon tool, on foot).
    const armed = !frozen and sb.tools.tool == .weapon and sb.garage.piloting == null and sb.seated == null;
    const aim_camera = sb.aimCameraPublic(camera.*);
    const f = aim_camera.forward();
    var out: [32]Combat.Event = undefined;
    const fought = sb.combat.step(&sb.physics, &sb.enemies, sb.progress.weapons, .{
        .eye = .{ aim_camera.position.x(), aim_camera.position.y(), aim_camera.position.z() },
        .forward = .{ f.x(), f.y(), f.z() },
        .feet = sb.player.feet,
        .dashing = sb.player.motion == .dash or sb.player.motion == .roll,
        .airborne = !sb.player.grounded,
        .fire = armed and sb.trigger.fire,
        .alt = armed and sb.trigger.alt,
        .cycle = armed and actions.next_item,
    }, dt, &out);
    for (out[0..@min(fought, out.len)]) |e| switch (e) {
        .fired => |w| sb.cue(switch (w) {
            .blaster, .energy_bow => .zap,
            .tracking_missile => .dash,
            .giant_blast => .boom,
            else => .zap,
        }, null),
        .slash => sb.cue(.slash, null),
        .impact => |at| sb.cue(.impact, at),
        .parried => sb.cue(.ui_confirm, null),
        .warp => |at| {
            sb.cue(.grapple, null);
            // The warp arrow carries the archer to where it struck.
            sb.player.feet = .{ at[0], at[1] - 0.9, at[2] };
            sb.player.velocity = .{ 0, 0, 0 };
            sb.say("warp strike", .{});
        },
        .hive => |h| hive(sb, h, camera),
        else => {},
    };
}

/// Board or leave a hover car (hands, P1).
pub fn board(sb: *Sandbox, car: u8, camera: *Camera) void {
    sb.release();
    sb.garage.board(car, camera);
}

pub fn leave(sb: *Sandbox, camera: *Camera) void {
    const feet = sb.garage.leave(&sb.physics) orelse return;
    sb.player = .{ .feet = feet, .mode = .walk };
    camera.pitch = -0.2;
    camera.position = sb.player.eye();
}

fn quat(q: m.Quat) [4]f32 {
    return .{ q.x, q.y, q.z, q.w };
}

/// Rotation taking +Z onto `dir`.
fn facing(dir: V) [4]f32 {
    const d = m.Vec3.init(dir[0], dir[1], dir[2]).normalizeOr(m.Vec3.unit_z);
    return quat(m.Quat.fromTo(m.Vec3.unit_z, d));
}

fn yawQuat(yaw: f32) [4]f32 {
    return quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, yaw));
}

pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    var n = start;
    const c = &sb.catalog.content;
    const t: f32 = @as(f32, @floatFromInt(sb.tick)) / 60;
    const room = struct {
        fn ok(o: []World.Prop, k: usize, need: usize) bool {
            return k + need <= o.len;
        }
    }.ok;
    n += sb.garage.publish(sb.catalog, out[n..]);
    // Fabricator kiosk: a pedestal, a slanted console and a glowing screen.
    const kiosk = kioskPosition(sb);
    if (room(out, n, 3)) {
        out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(kiosk, .{ 0, 0.6, 0 }) }, .tint = .{ 0.25, 0.27, 0.3, 1 }, .size = .{ 1.2, 1.2, 0.9 } };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(kiosk, .{ 0, 1.55, -0.1 }) }, .tint = .{ 0.2, 0.22, 0.25, 1 }, .size = .{ 1.5, 0.8, 0.18 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_x, -0.35)) };
        out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = R.add(kiosk, .{ 0, 1.56, -0.01 }) }, .tint = Material.emissive(.{ 0.3, 0.95, 0.85, 1 }, 0.6 + 0.3 * @sin(t * 2)), .size = .{ 1.3, 0.62, 0.04 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_x, -0.35)) };
        n += 3;
    }
    // Pickups: gems that bob and spin.
    for (sb.collectibles.items[0..sb.collectibles.count], 0..) |item, i| {
        if (sb.progress.picked.isSet(i) or !room(out, n, 1)) continue;
        n += gem(out[n..], item.kind, item.position, t + @as(f32, @floatFromInt(i)), c.gem);
    }
    for (sb.collectibles.drops) |slot| if (slot) |d| if (room(out, n, 1)) {
        n += gem(out[n..], d.kind, d.position, t * 1.5, c.gem);
    };
    // The Hive: nests, units, bolts.
    for (sb.enemies.nests[0..sb.enemies.nest_count]) |nest| {
        if (!room(out, n, 2)) break;
        const pulse = 0.5 + 0.4 * @sin(t * 1.7) + nest.flash * 3;
        if (nest.alive) {
            out[n] = .{ .mesh = c.spire, .transform = .{ .position = nest.position }, .tint = .{ 1, 1, 1, 1 } };
            out[n + 1] = .{ .mesh = c.spire_glow, .transform = .{ .position = nest.position }, .tint = Material.emissive(.{ 1, 1, 1, 1 }, pulse) };
            n += 2;
        } else {
            // A broken stump.
            out[n] = .{ .mesh = c.spire, .transform = .{ .position = R.sub(nest.position, .{ 0, 1, 0 }) }, .tint = .{ 0.45, 0.4, 0.4, 1 }, .size = .{ 1, 0.22, 1 } };
            n += 1;
        }
    }
    for (sb.enemies.units) |slot| if (slot) |u| {
        if (!room(out, n, 2)) break;
        const shell = if (u.kind == .drone) c.drone else c.sentinel;
        const glow = if (u.kind == .drone) c.drone_glow else c.sentinel_glow;
        const hot: f32 = if (u.flash > 0) 1 else if (u.state == .hunt) 0.9 else 0.45;
        const bank = quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, u.yaw).mul(m.Quat.fromAxisAngle(m.Vec3.unit_z, std.math.clamp(-u.velocity[0] * 0.02, -0.3, 0.3))));
        out[n] = .{ .mesh = shell, .transform = .{ .position = u.position }, .tint = if (u.flash > 0) .{ 1.6, 1.4, 1.4, 1 } else .{ 1, 1, 1, 1 }, .rotation = bank };
        out[n + 1] = .{ .mesh = glow, .transform = .{ .position = u.position }, .tint = Material.emissive(.{ 1, 1, 1, 1 }, hot), .rotation = bank };
        n += 2;
    };
    for (sb.enemies.bolts) |slot| if (slot) |b| if (room(out, n, 1)) {
        out[n] = .{ .mesh = c.block, .transform = .{ .position = b.position }, .tint = Material.emissive(.{ 1, 0.15, 0.1, 1 }, 1), .size = .{ 0.12, 0.12, 0.9 }, .rotation = facing(b.velocity) };
        n += 1;
    };
    // Player shots and effects.
    for (sb.combat.system.projectiles.items) |p| if (p.active and room(out, n, 1)) {
        const color = @import("../combat/Weapon.zig").Element.color(p.element);
        const s = p.radius * 0.8;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = p.position }, .tint = Material.emissive(.{ color[0], color[1], color[2], 1 }, 1), .size = .{ s, s, @max(0.6, s * 3) }, .rotation = facing(p.velocity) };
        n += 1;
    };
    for (sb.combat.effects) |slot| if (slot) |e| if (room(out, n, 1)) {
        const k = 1 - e.age / e.life;
        const tint = Material.emissive(.{ e.color[0], e.color[1], e.color[2], 1 }, k);
        out[n] = switch (e.kind) {
            .slash => .{ .mesh = c.block, .transform = .{ .position = e.position }, .tint = tint, .size = .{ e.size * 1.6, 0.08, 0.35 }, .rotation = facing(e.dir) },
            .beam => .{ .mesh = c.block, .transform = .{ .position = R.add(e.position, R.scale(e.dir, 40)) }, .tint = tint, .size = .{ e.size * 0.4, e.size * 0.4, 80 }, .rotation = facing(e.dir) },
            .burst, .spark, .muzzle => .{ .mesh = c.gem, .transform = .{ .position = e.position }, .tint = tint, .size = @splat(e.size * (1.5 - k * 0.5)) },
        };
        n += 1;
    };
    return n;
}

fn gem(out: []World.Prop, kind: Collectibles.Kind, at: V, t: f32, mesh: @import("../asset/Catalog.zig").MeshHandle) usize {
    const color = Collectibles.tint(kind);
    const scale: f32 = switch (kind) {
        .lumen_shard => 0.9,
        .rotor_core => 1.4,
        .hive_alloy => 1,
        .vital_cell => 1.6,
    };
    out[0] = .{ .mesh = mesh, .transform = .{ .position = R.add(at, .{ 0, 0.15 * @sin(t * 2.2), 0 }) }, .tint = Material.emissive(.{ color[0], color[1], color[2], 1 }, 0.75), .size = @splat(scale), .rotation = yawQuat(t * 1.3) };
    return 1;
}
