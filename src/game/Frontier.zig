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
const Market = @import("../city/Market.zig");
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
const Hangar = @import("Hangar.zig");
const Skies = @import("Skies.zig");
const ShipMeshes = @import("../vehicle/ShipMeshes.zig");
const HiveMeshes = @import("../vehicle/HiveMeshes.zig");
const m = @import("../character/math.zig");
const Rig = @import("Rig.zig");
const Profile = @import("Profile.zig");
const Specials = @import("Specials.zig");
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
    const surface = sb.enemies.nest_count;
    var nest_sites: [Enemies.max_nests]V = undefined;
    for (sb.enemies.nests[0..surface], 0..) |nest, i| nest_sites[i] = nest.position;
    sb.skies = Skies.init(sb.seed, Sandbox.spawn, nest_sites[0..surface]);
    for (&sb.skies.market_plazas, 0..) |*plaza, i| plaza.* = sb.catalog.district.nodes[Market.stall_plazas[i]].position;

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
    for (sb.enemies.nests[0..surface], 0..) |n, i| nests[i] = n.position;
    const spawn: V = .{ Sandbox.spawn[0], Terrain.surface(sb.seed, Sandbox.spawn[0], Sandbox.spawn[2]).height, Sandbox.spawn[2] };
    sb.collectibles = Collectibles.generate(.{ .seed = sb.seed, .spawn = spawn, .plazas = &plazas, .roads = &roads, .roofs = roofs[0..r], .shrines = &shrines, .nests = nests[0..surface] });
    placeDungeons(sb);
    // Settle every pickup onto what is really there: above the terrain (not inside a cave),
    // onto any deck, roof or cave floor.
    for (sb.collectibles.items[0..sb.collectibles.count]) |*item| {
        const p = &item.position;
        if (sb.groundBelow(p.*)) |ground| if (p[1] < ground + 0.5) {
            p[1] = ground + 0.9;
        };
        if (sb.physics.castRay(R.add(p.*, .{ 0, 2.5, 0 }), .{ 0, -1, 0 }, 8, .none)) |hit| p[1] = hit.point[1] + 0.9;
    }
    refresh(sb);
}

/// The cave dungeons: a Hive nest in each heart chamber, and loot through the chambers (lumen
/// in halls, shards and a rotor core in dead-end caches, a vital cell and alloy in the heart).
fn placeDungeons(sb: *Sandbox) void {
    const Caves = Sandbox.Caves;
    for (sb.caves.systems[0..sb.caves.count]) |*sys| {
        const heart = sys.heart();
        sb.enemies.addCaveNest(.{ heart.center[0], heart.floor, heart.center[2] });
        for (sys.rooms[0..sys.room_count], 0..) |room, i| {
            const at = struct {
                fn spot(s: *const Caves.System, r: usize, k: usize, n: usize) V {
                    const p = Caves.floorSpot(s, @intCast(r), k, n, 0.45);
                    return .{ p[0], p[1] + 0.9, p[2] };
                }
            }.spot;
            switch (room.role) {
                .mouth => {},
                .hall => sb.collectibles.add(.lumen_shard, at(sys, i, 0, 1)),
                .cache => {
                    sb.collectibles.add(.lumen_shard, at(sys, i, 0, 3));
                    sb.collectibles.add(.lumen_shard, at(sys, i, 1, 3));
                    sb.collectibles.add(.rotor_core, at(sys, i, 2, 3));
                },
                .heart => {
                    sb.collectibles.add(.vital_cell, at(sys, i, 0, 3));
                    sb.collectibles.add(.hive_alloy, at(sys, i, 1, 3));
                    sb.collectibles.add(.hive_alloy, at(sys, i, 2, 3));
                },
            }
        }
    }
}

/// Cave colliders are built the first time a player comes within 150 m of a system (a few
/// milliseconds each in release builds), and stay. Entering a system is announced once.
fn stepCaves(sb: *Sandbox) void {
    const Caves = Sandbox.Caves;
    var feet: [Sandbox.max_players]?V = @splat(null);
    feet[0] = sb.player.feet;
    for (sb.guests, 1..) |g, i| if (g.active) {
        feet[i] = g.player.feet;
    };
    for (sb.caves.systems[0..sb.caves.count], 0..) |*sys, i| {
        if (!sb.cave_colliders[i].eql(.none)) continue;
        for (feet) |maybe| if (maybe) |f| {
            var near = true;
            for ([_]usize{ 0, 2 }) |a| if (f[a] < sys.lo[a] - 150 or f[a] > sys.hi[a] + 150) {
                near = false;
            };
            if (!near) continue;
            sb.cave_colliders[i] = Caves.collider(sb.allocator, &sb.physics, &sb.caves, @intCast(i), Sandbox.world_flag) catch |err| blk: {
                std.log.err("cave {d} collider: {s}", .{ i, @errorName(err) });
                break :blk .none;
            };
            break;
        };
    }
    for (feet, 0..) |maybe, p| {
        const f = maybe orelse continue;
        const inside = Caves.systemAt(&sb.caves, R.add(f, .{ 0, 1, 0 }));
        if (inside != null and inside != sb.cave_inside[p]) {
            var flag: [20]u8 = undefined;
            const first = !sb.progress.hasFlag(std.fmt.bufPrint(&flag, "cave_{d}_found", .{inside.?}) catch unreachable);
            sb.progress.setFlag(std.fmt.bufPrint(&flag, "cave_{d}_found", .{inside.?}) catch unreachable);
            if (p == 0) sb.say("{s}{s}", .{ Caves.name(inside.?), if (first) ": a new cave" else "" });
            if (first) sb.cue(.vault, null);
        }
        sb.cave_inside[p] = inside;
    }
}

/// After a load (or a new game): nests follow their flags, owned cars park on their pads, and
/// the party's health follows its vital cells.
pub fn refresh(sb: *Sandbox) void {
    for (sb.enemies.nests[0..sb.enemies.nest_count], 0..) |*nest, i| {
        var flag: [16]u8 = undefined;
        const destroyed = sb.progress.hasFlag(nestFlag(&flag, @intCast(i)));
        nest.alive = !destroyed;
        nest.health = if (destroyed) 0 else if (nest.cave) Enemies.nest_health * 0.7 else Enemies.nest_health;
    }
    sb.enemies.units = @splat(null);
    sb.enemies.bolts = @splat(null);
    for (&sb.skies.carriers, 0..) |*c, i| {
        var flag: [20]u8 = undefined;
        c.alive = !sb.progress.hasFlag(std.fmt.bufPrint(&flag, "carrier_{d}_down", .{i}) catch unreachable);
        c.health = Skies.carrier_health;
        c.turret_health = @splat(Skies.tuning.carrier_turret_health);
        c.bay_health = @splat(Skies.tuning.carrier_bay_health);
        c.crashing = false;
        c.crash_time = 0;
    }
    sb.skies.wasps = @splat(null);
    sb.skies.shots = @splat(null);
    sb.skies.guns = .{};
    sb.hangar = .{};
    if (sb.progress.fighter) sb.hangar.placeWithLevels(sb.seed, Sandbox.spawn, null, 0, sb.progress.kestrel_levels);
    sb.skies.configureKestrel(sb.progress.kestrel_levels);
    sb.garage = .{};
    for (0..Designs.count) |d| if (sb.progress.ownsVehicle(@enumFromInt(d))) sb.garage.park(sb.seed, Sandbox.spawn, sb.catalog, @enumFromInt(d));
    sb.collectibles.drops = @splat(null);
    sb.specials = .{};
    sb.combat.setMaxHealth(sb.progress.maxHealth());
    sb.combat.setPlayerMax(0, sb.progress.maxHealth() + Specials.healthBonus(sb.profile.class));
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
    if (sb.hangar.pick(eye, dir, nearest)) |d| {
        nearest = d;
        result = .jet;
    }
    const kiosk = kioskPosition(sb);
    if (Physics.rayBox(eye, dir, R.add(kiosk, .{ 0, 1.2, 0 }), .{ 0.8, 1.2, 0.6 })) |hit| if (hit.distance < nearest) {
        result = .fabricator;
    };
    return result;
}

/// Chest positions the Hive aims at: P1 (or P1's car) and active guests.
fn targets(sb: *const Sandbox, out: *[Sandbox.max_players]Enemies.Target) []const Enemies.Target {
    var p1: Enemies.Target = .{ .chest = R.add(sb.player.feet, .{ 0, 1.3, 0 }), .velocity = sb.player.velocity, .guard = sb.combat.arsenals[0].guard(), .facing = facingOf(sb.body_yaw) };
    if (sb.garage.piloting) |i| {
        const car = sb.garage.cars[i].?.flyer.body;
        p1 = .{ .chest = .{ car.pos.x, car.pos.y, car.pos.z }, .velocity = .{ car.vel.x, car.vel.y, car.vel.z } };
    }
    out[0] = p1;
    var n: usize = 1;
    for (sb.guests) |g| {
        out[n] = .{ .chest = R.add(g.player.feet, .{ 0, 1.3, 0 }), .velocity = g.player.velocity, .alive = g.active, .guard = sb.combat.arsenals[n].guard(), .facing = facingOf(g.body_yaw) };
        n += 1;
    }
    return out[0..n];
}

fn facingOf(yaw: f32) V {
    return .{ @sin(yaw), 0, @cos(yaw) };
}

/// Player `p`'s simulation skeleton, built or rebuilt for its body; null if memory runs out
/// (blades then follow an approximate arm).
pub fn rigFor(sb: *Sandbox, p: usize, profile: Profile) ?*Rig {
    if (sb.rigs[p]) |*r| {
        r.refresh(sb.allocator, profile) catch {};
        return r;
    }
    sb.rigs[p] = Rig.init(sb.allocator, profile) catch return null;
    return &sb.rigs[p].?;
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
        .deflected => |d| {
            sb.combat.deflect(d.player, d.position, d.velocity);
            sb.cuePitch(.slash, d.position, 1.5);
            if (d.player == 0) sb.say("parried!", .{});
        },
        .nest_down => |n| {
            var flag: [16]u8 = undefined;
            sb.progress.setFlag(nestFlag(&flag, n.nest));
            sb.progress.setFlag("nest_destroyed");
            sb.cue(.boom, n.position);
            sb.cue(.vault, null);
            if (n.nest >= Enemies.surface_nests) {
                // A cave's heart nest: the cave is cleared.
                const cave = n.nest - Enemies.surface_nests;
                var cleared: [20]u8 = undefined;
                sb.progress.setFlag(std.fmt.bufPrint(&cleared, "cave_{d}_cleared", .{cave}) catch unreachable);
                sb.progress.setFlag("cave_cleared");
                for (0..2) |k| sb.collectibles.drop(.hive_alloy, R.add(n.position, .{ @as(f32, @floatFromInt(k)) * 1.5 - 0.75, 1, 3 }));
                sb.collectibles.drop(.rotor_core, R.add(n.position, .{ 0, 1, -3 }));
                sb.say("{s} cleared: the hive heart is broken", .{Sandbox.Caves.name(cave)});
            } else {
                for (0..4) |k| sb.collectibles.drop(.hive_alloy, R.add(n.position, .{ @as(f32, @floatFromInt(k)) * 1.5 - 2, 1, 5 }));
                sb.collectibles.drop(.rotor_core, R.add(n.position, .{ 0, 1, 6.5 }));
                sb.say("hive nest destroyed", .{});
            }
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
    stepCaves(sb);
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

    // The Kestrel and the air war.
    sb.hangar.step(&sb.physics, if (sb.hangar.piloting and !frozen) Hangar.controls(input, camera.*) else .{}, dt);
    stepSkies(sb, camera, frozen, dt);

    // The Hive.
    var who: [Sandbox.max_players]Enemies.Target = undefined;
    var events: [32]Enemies.Event = undefined;
    const count = sb.enemies.step(&sb.physics, targets(sb, &who), dt, &events);
    for (events[0..@min(count, events.len)]) |e| hive(sb, e, camera);

    // Arsenals: P1 with the weapon tool on foot, guests with the right trigger.
    sb.combat.tick(dt);
    const armed = !frozen and sb.tools.tool == .weapon and sb.garage.piloting == null and sb.seated == null;
    const aim_camera = sb.aimCameraPublic(camera.*);
    const f = aim_camera.forward();
    var out: [32]Combat.Event = undefined;
    const fought = sb.combat.step(0, &sb.physics, &sb.enemies, sb.progress.weapons, .{
        .eye = .{ aim_camera.position.x(), aim_camera.position.y(), aim_camera.position.z() },
        .forward = .{ f.x(), f.y(), f.z() },
        .feet = sb.player.feet,
        .yaw = sb.body_yaw,
        .rig = rigFor(sb, 0, sb.profile),
        .armed = armed,
        .dashing = sb.player.motion == .dash or sb.player.motion == .roll,
        .airborne = !sb.player.grounded,
        .fire = armed and sb.trigger.fire,
        .alt = armed and sb.trigger.alt,
        .cycle = armed and actions.next_item,
    }, dt, &out);
    rangerAirShots(sb, .{ aim_camera.position.x(), aim_camera.position.y(), aim_camera.position.z() }, .{ f.x(), f.y(), f.z() }, out[0..@min(fought, out.len)]);
    arsenalEvents(sb, 0, out[0..@min(fought, out.len)], camera);
    for (&sb.guests, 1..) |*g, p| {
        defer g.next_weapon = false;
        if (!g.active) continue;
        const eye = g.player.eye();
        const gf = g.camera.forward();
        const n = sb.combat.step(@intCast(p), &sb.physics, &sb.enemies, sb.progress.weapons, .{
            .eye = .{ eye.x(), eye.y(), eye.z() },
            .forward = .{ gf.x(), gf.y(), gf.z() },
            .feet = g.player.feet,
            .yaw = g.body_yaw,
            .rig = rigFor(sb, p, g.profile),
            .armed = g.trading == null,
            .dashing = g.player.motion == .dash or g.player.motion == .roll,
            .airborne = !g.player.grounded,
            .fire = g.fire and g.trading == null,
            .alt = g.alt and g.trading == null,
            .cycle = g.next_weapon and g.trading == null,
        }, dt, &out);
        rangerAirShots(sb, .{ eye.x(), eye.y(), eye.z() }, .{ gf.x(), gf.y(), gf.z() }, out[0..@min(n, out.len)]);
        arsenalEvents(sb, @intCast(p), out[0..@min(n, out.len)], camera);
    }
    stepSpecials(sb, camera, actions, frozen, dt);
}

fn rangerAirShots(sb: *Sandbox, origin: V, direction: V, events: []const Combat.Event) void {
    for (events) |event| if (event == .fired) switch (event.fired) {
        .blaster => sb.skies.fireRanger(origin, direction, 22),
        .sniper_rifle => sb.skies.fireRanger(origin, direction, 95),
        .machine_gun => sb.skies.fireRanger(origin, direction, 9),
        .heavy_rifle => sb.skies.fireRanger(origin, direction, 55),
        .energy_bazooka => sb.skies.fireRanger(origin, direction, 90),
        else => {},
    };
}

/// Class specials for every local player (P1 on foot, active guests), then grenades and
/// sentries. Class passives (health, saber weight) are applied here too.
fn stepSpecials(sb: *Sandbox, camera: *Camera, actions: Sandbox.Actions, frozen: bool, dt: f32) void {
    var events: [32]Specials.Event = undefined;
    const on_foot = !frozen and sb.garage.piloting == null and sb.seated == null and !sb.hangar.piloting;
    const f = sb.aimCameraPublic(camera.*).forward();
    const eye = sb.player.eye();
    sb.combat.arsenals[0].melee_scale = Specials.meleeScale(sb.profile.class);
    sb.combat.setPlayerMax(0, sb.progress.maxHealth() + Specials.healthBonus(sb.profile.class));
    const pressed: [3]bool = if (on_foot) .{ actions.special_1, actions.special_2, actions.special_3 } else @splat(false);
    var n = sb.specials.step(0, sb.profile.class, &sb.physics, &sb.enemies, &sb.combat, .{ .eye = .{ eye.x(), eye.y(), eye.z() }, .forward = .{ f.x(), f.y(), f.z() }, .feet = sb.player.feet, .pressed = pressed }, dt, &events);
    specialEvents(sb, events[0..@min(n, events.len)], camera);
    for (&sb.guests, 1..) |*g, p| {
        defer g.special = @splat(false);
        if (!g.active) continue;
        sb.combat.arsenals[p].melee_scale = Specials.meleeScale(g.profile.class);
        sb.combat.setPlayerMax(p, sb.progress.maxHealth() + Specials.healthBonus(g.profile.class));
        const ge = g.player.eye();
        const gf = g.camera.forward();
        n = sb.specials.step(@intCast(p), g.profile.class, &sb.physics, &sb.enemies, &sb.combat, .{ .eye = .{ ge.x(), ge.y(), ge.z() }, .forward = .{ gf.x(), gf.y(), gf.z() }, .feet = g.player.feet, .pressed = if (frozen) @splat(false) else g.special }, dt, &events);
        specialEvents(sb, events[0..@min(n, events.len)], camera);
    }
    n = sb.specials.stepWorld(&sb.physics, &sb.enemies, &sb.combat, dt, &events);
    specialEvents(sb, events[0..@min(n, events.len)], camera);
}

fn specialEvents(sb: *Sandbox, events: []const Specials.Event, camera: *Camera) void {
    for (events) |e| switch (e) {
        .used => |u| {
            const at: ?V = if (u.player == 0) null else R.add(sb.guests[u.player - 1].player.feet, .{ 0, 1.2, 0 });
            switch (u.kind) {
                .arc_grenade, .sentry => sb.cuePitch(.grapple, at, 1.3),
                .overshield => sb.cuePitch(.restock, at, 1.2),
                .phase_dash => sb.cuePitch(.dash, at, 1.5),
                .kinetic_slam => sb.cuePitch(.boom, at, 0.7),
                .lumen_lance => sb.cuePitch(.zap, at, 0.45),
            }
            if (u.player == 0) sb.say("{s}", .{Specials.info(u.kind).label});
        },
        .denied => |p| if (p == 0) sb.cue(.ui_error, null),
        .burst => |at| sb.cue(.boom, at),
        .zap => |at| sb.cuePitch(.zap, at, 1.8),
        .blink => |b| {
            const player = if (b.player == 0) &sb.player else &sb.guests[b.player - 1].player;
            player.feet = b.to;
            player.velocity = .{ 0, 0, 0 };
            if (b.player == 0) camera.position = sb.player.eye();
        },
        .hive => |h| hive(sb, h, camera),
    };
}

fn stepSkies(sb: *Sandbox, camera: *Camera, frozen: bool, dt: f32) void {
    var jet: ?Skies.Jet = null;
    if (sb.hangar.fighter) |f| if (sb.hangar.piloting) {
        jet = .{ .position = .{ f.body.pos.x, f.body.pos.y, f.body.pos.z }, .velocity = .{ f.body.vel.x, f.body.vel.y, f.body.vel.z }, .forward = .{ f.forward().x, f.forward().y, f.forward().z }, .airborne = !f.grounded };
    };
    var on_foot: [Sandbox.max_players]Enemies.Target = undefined;
    on_foot[0] = .{ .chest = R.add(sb.player.feet, .{ 0, 1.3, 0 }), .velocity = sb.player.velocity, .alive = !sb.hangar.piloting };
    for (sb.guests, 1..) |g, i| on_foot[i] = .{ .chest = R.add(g.player.feet, .{ 0, 1.3, 0 }), .velocity = g.player.velocity, .alive = g.active };
    var events: [64]Skies.Event = undefined;
    var n: usize = 0;
    if (jet) |j| if (!frozen) sb.skies.fireJetUpgraded(&sb.enemies, j, sb.hangar.guns(), sb.trigger.fire, sb.trigger.alt, dt, sb.progress.kestrel_levels, &events, &n);
    const fired = @min(n, events.len);
    const count = sb.skies.step(&sb.physics, &sb.enemies, jet, &on_foot, dt, events[fired..]);
    for (events[0..@min(fired + count, events.len)]) |e| switch (e) {
        .sound => |s| switch (s.kind) {
            .cannon => sb.cuePitch(.zap, null, 1.7),
            .missile => sb.cue(.dash, null),
            .flak => sb.cuePitch(.impact, s.position, 0.6),
            .sting => sb.cuePitch(.hive_zap, s.position, 1.4),
        },
        .burst => |at| {
            burst(sb, at, 4, .{ 1, 0.55, 0.2 });
            sb.cue(.boom, at);
        },
        .jet_hit => |d| if (sb.hangar.fighter) |*f| {
            f.hull -= d;
            sb.combat.vitals[0].hurt = 0.25;
            sb.cuePitch(.hurt, null, 0.8);
            if (f.hull <= 0) wreck(sb, camera);
        },
        .jet_collision => |hit| if (sb.hangar.fighter) |*f| {
            f.resolveCollision(.{ .x = hit.normal[0], .y = hit.normal[1], .z = hit.normal[2] }, hit.penetration, .{ .x = hit.other_velocity[0], .y = hit.other_velocity[1], .z = hit.other_velocity[2] }, hit.damage);
            if (hit.damage > 0) {
                sb.combat.vitals[0].hurt = 0.25;
                sb.cuePitch(.impact, null, 0.8);
                if (f.hull <= 0) wreck(sb, camera);
            }
        },
        .player_hit => |hit| hive(sb, .{ .player_hit = .{ .player = hit.player, .damage = hit.damage, .from = sb.player.feet } }, camera),
        .wasp_down => |at| {
            burst(sb, at, 5, .{ 1, 0.3, 0.15 });
            sb.cue(.boom, at);
            dropBelow(sb, .hive_alloy, at);
            sb.progress.setFlag("wasp_down");
        },
        .raid_started => |raid| sb.say("beetle bomber inbound: market plaza {d} — defend it", .{raid.plaza + 1}),
        .raid_bomb => |raid| {
            burst(sb, raid.position, 4 + @as(f32, @floatFromInt(raid.hit)), .{ 0.7, 0.32, 0.08 });
            sb.cue(.boom, raid.position);
            sb.say("market plaza {d} hit ({d}/3)", .{ raid.plaza + 1, raid.hit });
        },
        .raid_repelled => |plaza| {
            sb.progress.setFlag("bomber_raid_defended");
            sb.say("market plaza {d} defended — bomber destroyed", .{plaza + 1});
            sb.cue(.vault, null);
        },
        .raid_lost => |plaza| {
            sb.progress.setFlag("bomber_raid_lost");
            if (plaza < sb.market.stalls.len) sb.market.stalls[plaza].stock = @splat(0);
            sb.say("market plaza {d} damaged — stock lost until dawn", .{plaza + 1});
        },
        .carrier_stage => |change| switch (change.stage) {
            .bays => sb.say("carrier {d}: flak turrets down — destroy the launch bays", .{change.carrier + 1}),
            .core => sb.say("carrier {d}: launch bays destroyed — core exposed", .{change.carrier + 1}),
            .crashing => {
                sb.say("carrier {d}: core breached — impact imminent", .{change.carrier + 1});
                sb.cue(.boom, sb.skies.carriers[change.carrier].position());
            },
            .turrets => {},
        },
        .carrier_debris => |at| burst(sb, at, 2.2, .{ 1, 0.38, 0.08 }),
        .carrier_down => |c| {
            var flag: [20]u8 = undefined;
            sb.progress.setFlag(std.fmt.bufPrint(&flag, "carrier_{d}_down", .{c.carrier}) catch unreachable);
            sb.progress.setFlag("carrier_down");
            for (0..6) |k| burst(sb, R.add(c.position, .{ (@as(f32, @floatFromInt(k)) - 2.5) * 12, 0, @as(f32, @floatFromInt(k % 3)) * 15 - 15 }), 18, .{ 1, 0.45, 0.15 });
            sb.cue(.boom, c.position);
            sb.cue(.vault, null);
            for (0..6) |k| dropBelow(sb, .hive_alloy, R.add(c.position, .{ @as(f32, @floatFromInt(k)) * 3 - 8, 0, 0 }));
            dropBelow(sb, .rotor_core, R.add(c.position, .{ 0, 0, 6 }));
            dropBelow(sb, .rotor_core, R.add(c.position, .{ 3, 0, 9 }));
            dropBelow(sb, .vital_cell, R.add(c.position, .{ -3, 0, 9 }));
            sb.say("brood carrier destroyed! its cache fell to the ground", .{});
        },
        .hive => |h| hive(sb, h, camera),
    };
}

fn burst(sb: *Sandbox, at: V, size: f32, color: [3]f32) void {
    var oldest: usize = 0;
    for (&sb.combat.effects, 0..) |*slot, i| {
        if (slot.* == null) {
            oldest = i;
            break;
        }
        if (slot.*.?.age > sb.combat.effects[oldest].?.age) oldest = i;
    }
    sb.combat.effects[oldest] = .{ .kind = .burst, .position = at, .life = 0.6, .size = size, .color = color };
}

/// Drops a pickup onto whatever floor is under `at` (from the sky, too).
fn dropBelow(sb: *Sandbox, kind: Collectibles.Kind, at: V) void {
    var p = at;
    if (sb.physics.castRay(at, .{ 0, -1, 0 }, 800, .none)) |floor| {
        p[1] = floor.point[1] + 0.9;
    } else p[1] = Terrain.surface(sb.seed, at[0], at[2]).height + 0.9;
    sb.collectibles.drop(kind, p);
}

/// The Kestrel is shot down: the pilot is thrown clear (hurt) and the jet rebuilt on its pad.
fn wreck(sb: *Sandbox, camera: *Camera) void {
    const f = sb.hangar.fighter.?;
    const at: V = .{ f.body.pos.x, f.body.pos.y, f.body.pos.z };
    burst(sb, at, 8, .{ 1, 0.5, 0.2 });
    sb.cue(.boom, at);
    leaveJet(sb, camera);
    // The pilot's harness lowers them to the floor below.
    if (sb.physics.castRay(at, .{ 0, -1, 0 }, 1000, .none)) |floor| sb.player.feet = .{ at[0], floor.point[1] + 0.05, at[2] };
    camera.position = sb.player.eye();
    var events: [4]Combat.Event = undefined;
    var n: usize = 0;
    if (sb.combat.hurt(0, 40, &events, &n)) down(sb, 0, camera);
    sb.hangar.placeWithLevels(sb.seed, Sandbox.spawn, null, 0, sb.progress.kestrel_levels);
    sb.say("the kestrel went down: a new one waits on its pad", .{});
}

/// Sounds, warps and Hive outcomes from player `p`'s arsenal.
fn arsenalEvents(sb: *Sandbox, p: u8, events: []const Combat.Event, camera: *Camera) void {
    const at: ?V = if (p == 0) null else R.add(sb.guests[p - 1].player.feet, .{ 0, 1.2, 0 });
    for (events) |e| switch (e) {
        .fired => |w| sb.cuePitch(switch (w) {
            .blaster, .energy_bow => .zap,
            .tracking_missile => .dash,
            .giant_blast => .boom,
            .energy_bazooka => .dash,
            else => .zap,
        }, at, switch (w) {
            .sniper_rifle => 0.55,
            .machine_gun => 1.6,
            .heavy_rifle => 0.8,
            .beam_saber => 0.7,
            else => 1,
        }),
        .slash => sb.cue(.slash, at),
        .cut => |spot| sb.cuePitch(.impact, spot, 1.3),
        .blast => |spot| sb.cue(.boom, spot),
        .lunge => |v| {
            const player = if (p == 0) &sb.player else &sb.guests[p - 1].player;
            player.velocity[0] = v[0];
            player.velocity[2] = v[2];
        },
        .impact => |spot| sb.cue(.impact, spot),
        .parried => sb.cue(.ui_confirm, null),
        .warp => |to| {
            sb.cue(.grapple, at);
            // The warp arrow carries the archer to where it struck.
            const player = if (p == 0) &sb.player else &sb.guests[p - 1].player;
            player.feet = .{ to[0], to[1] - 0.9, to[2] };
            player.velocity = .{ 0, 0, 0 };
            if (p == 0) sb.say("warp strike", .{});
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

pub fn boardJet(sb: *Sandbox, camera: *Camera) void {
    sb.release();
    sb.hangar.board(camera);
    sb.say("kestrel: mouse aims, W/S throttle, A/D roll, space lifts, shift burns, F climbs out", .{});
}

pub fn leaveJet(sb: *Sandbox, camera: *Camera) void {
    const feet = sb.hangar.leave(&sb.physics) orelse return;
    sb.player = .{ .feet = feet, .mode = .walk };
    camera.pitch = -0.2;
    camera.position = sb.player.eye();
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
    n = publishMountains(sb, out, n, t);
    // Fabricator kiosk: a pedestal, a slanted console and a glowing screen.
    const kiosk = kioskPosition(sb);
    if (room(out, n, 3)) {
        out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(kiosk, .{ 0, 0.6, 0 }) }, .tint = .{ 0.25, 0.27, 0.3, 1 }, .size = .{ 1.2, 1.2, 0.9 } };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(kiosk, .{ 0, 1.55, -0.1 }) }, .tint = .{ 0.2, 0.22, 0.25, 1 }, .size = .{ 1.5, 0.8, 0.18 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_x, -0.35)) };
        out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = R.add(kiosk, .{ 0, 1.56, -0.01 }) }, .tint = Material.emissive(.{ 0.3, 0.95, 0.85, 1 }, 0.6 + 0.3 * @sin(t * 2)), .size = .{ 1.3, 0.62, 0.04 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_x, -0.35)) };
        n += 3;
    }
    // Tower roof pads sit on the existing plaza decks: their wide, lit H-marking identifies
    // flat landing and boarding surfaces for the Kestrel at all three market towers.
    for (sb.catalog.district.nodes) |node| if (node.kind == .tower and room(out, n, 4)) {
        const at = node.position;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, 0.08, 0 }) }, .tint = .{ 0.12, 0.17, 0.2, 1 }, .size = .{ 15, 0.12, 15 } };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ -3.4, 0.16, 0 }) }, .tint = Material.emissive(.{ 0.25, 0.85, 0.78, 1 }, 0.8), .size = .{ 0.75, 0.05, 8 } };
        out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 3.4, 0.16, 0 }) }, .tint = Material.emissive(.{ 0.25, 0.85, 0.78, 1 }, 0.8), .size = .{ 0.75, 0.05, 8 } };
        out[n + 3] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, 0.16, 0 }) }, .tint = Material.emissive(.{ 0.25, 0.85, 0.78, 1 }, 0.8), .size = .{ 7.5, 0.05, 0.75 } };
        n += 4;
    };
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
        // Cave nests grow smaller, under the chamber's roof.
        const size: [3]f32 = if (nest.cave) @splat(0.45) else @splat(1);
        if (nest.alive) {
            out[n] = .{ .mesh = c.spire, .transform = .{ .position = nest.position }, .tint = .{ 1, 1, 1, 1 }, .size = size };
            out[n + 1] = .{ .mesh = c.spire_glow, .transform = .{ .position = nest.position }, .tint = Material.emissive(.{ 1, 1, 1, 1 }, pulse), .size = size };
            n += 2;
        } else {
            // A broken stump.
            out[n] = .{ .mesh = c.spire, .transform = .{ .position = R.sub(nest.position, .{ 0, 1, 0 }) }, .tint = .{ 0.45, 0.4, 0.4, 1 }, .size = .{ size[0], 0.22 * size[1], size[2] } };
            n += 1;
        }
    }
    // Troopers are skinned characters (ids 16–23), drawn only near P1 to bound skinning cost.
    var trooper_id: u8 = 16;
    for (sb.enemies.units) |slot| if (slot) |u| if (u.kind == .trooper) {
        if (trooper_id >= @import("../character/Ranger.zig").capacity or !room(out, n, 1)) break;
        const d = R.sub(u.position, sb.player.feet);
        if (d[0] * d[0] + d[2] * d[2] > 120 * 120) continue;
        out[n] = .{ .mesh = .none, .transform = .{ .position = u.position }, .tint = .{ 1, 1, 1, 1 }, .character = .{
            .profile = trooper_profile,
            .pose = .{ .feet = u.position, .yaw = u.yaw, .walk_phase = u.walk_phase, .walk_amount = u.walk_amount, .motion = if (u.walk_amount > 0.2) .run else .idle, .time = t },
            .id = trooper_id,
        } };
        trooper_id += 1;
        n += 1;
    };
    for (sb.enemies.units) |slot| if (slot) |u| {
        if (u.kind == .trooper) continue;
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
        out[n] = .{ .mesh = c.block, .transform = .{ .position = b.position }, .tint = Material.emissive(.{ 1, 0.15, 0.1, 1 }, 1), .size = .{ 0.07, 0.07, 0.6 }, .rotation = facing(b.velocity) };
        n += 1;
    };
    // The Kestrel, Hive wasps (wings flapping), Brood carriers, and air shots.
    if (sb.hangar.fighter) |f| if (room(out, n, 2)) {
        const rot = quat(f.body.rot);
        const at: V = .{ f.body.pos.x, f.body.pos.y, f.body.pos.z };
        const paint: [4]f32 = switch (sb.progress.kestrel_paint) {
            .ivory => .{ 1, 1, 1, 1 },
            .azure => .{ 0.42, 0.72, 1, 1 },
            .ember => .{ 1, 0.48, 0.16, 1 },
            .moss => .{ 0.48, 0.82, 0.38, 1 },
        };
        out[n] = .{ .mesh = c.kestrel, .transform = .{ .position = at }, .tint = paint, .rotation = rot };
        out[n + 1] = .{ .mesh = c.kestrel_glow, .transform = .{ .position = at }, .tint = Material.emissive(paint, 0.25 + 0.75 * f.burn), .rotation = rot };
        n += 2;
    };
    for (sb.skies.wasps) |slot| if (slot) |w| {
        if (!room(out, n, 6)) break;
        const q = m.Quat.fromTo(m.Vec3.unit_z, m.Vec3.init(w.forward[0], w.forward[1], w.forward[2]).normalizeOr(m.Vec3.unit_z));
        const wing_tint: [4]f32 = if (w.flash > 0) .{ 1.6, 1.4, 1.4, 1 } else switch (w.kind) {
            .wasp => .{ 1, 1, 1, 1 },
            .dragonfly => .{ 0.45, 1.1, 1.5, 1 },
            .beetle_bomber => .{ 1.45, 0.78, 0.35, 1 },
        };
        const tint = wing_tint;
        const hull = switch (w.kind) {
            .wasp => c.wasp,
            .dragonfly => c.dragonfly,
            .beetle_bomber => c.beetle_bomber,
        };
        const lights = switch (w.kind) {
            .wasp => c.wasp_glow,
            .dragonfly => c.dragonfly_glow,
            .beetle_bomber => c.beetle_bomber_glow,
        };
        out[n] = .{ .mesh = hull, .transform = .{ .position = w.position }, .tint = tint, .rotation = quat(q) };
        out[n + 1] = .{ .mesh = lights, .transform = .{ .position = w.position }, .tint = Material.emissive(if (w.kind == .dragonfly) .{ 0.2, 0.75, 1, 1 } else if (w.kind == .beetle_bomber) .{ 1, 0.32, 0.08, 1 } else .{ 1, 1, 1, 1 }, if (w.state == .attack) 1 else 0.6), .rotation = quat(q) };
        n += 2;
        for (ShipMeshes.wasp_wings, 0..) |root, k| {
            const side: f32 = if (root.x > 0) 1 else -1;
            // Fore and hind pairs beat out of phase; a mirrored wing points along -X.
            const beat = @sin(w.flap + @as(f32, @floatFromInt(k / 2)) * 1.4) * 0.7;
            const local = m.Quat.fromAxisAngle(m.Vec3.unit_y, if (side > 0) 0 else std.math.pi).mul(m.Quat.fromAxisAngle(m.Vec3.unit_z, beat * side * side));
            const p = q.rotate(root);
            out[n] = .{ .mesh = c.wasp_wing, .transform = .{ .position = R.add(w.position, .{ p.x, p.y, p.z }) }, .tint = .{ 1, 1, 1, 1 }, .rotation = quat(q.mul(local)) };
            n += 1;
        }
    };
    for (sb.skies.carriers) |carrier| if (carrier.alive and room(out, n, 2)) {
        const q = quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, carrier.yaw()));
        const at = carrier.position();
        out[n] = .{ .mesh = c.carrier, .transform = .{ .position = at }, .tint = if (carrier.flash > 0) .{ 1.4, 1.2, 1.2, 1 } else .{ 1, 1, 1, 1 }, .rotation = q };
        const glow = if (carrier.crashing) 1.2 else switch (carrier.stage()) {
            .turrets => @as(f32, 0.35),
            .bays => 0.65,
            .core => 0.95,
            .crashing => 1.2,
        };
        out[n + 1] = .{ .mesh = c.carrier_glow, .transform = .{ .position = at }, .tint = Material.emissive(.{ 1, 1, 1, 1 }, glow + 0.2 * @sin(t * 1.3)), .rotation = q };
        n += 2;
        if (!carrier.crashing) switch (carrier.stage()) {
            .turrets => for (ShipMeshes.carrier_turrets, carrier.turret_health) |p, health| if (health > 0 and room(out, n, 1)) {
                const target = carrier.point(p);
                out[n] = .{ .mesh = c.gem, .transform = .{ .position = target }, .tint = Material.emissive(.{ 1, 0.12, 0.06, 1 }, 1.4), .size = @splat(3.4) };
                n += 1;
            },
            .bays => for (ShipMeshes.carrier_bays, carrier.bay_health) |p, health| if (health > 0 and room(out, n, 1)) {
                const target = carrier.point(p);
                out[n] = .{ .mesh = c.gem, .transform = .{ .position = target }, .tint = Material.emissive(.{ 1, 0.55, 0.08, 1 }, 1.5), .size = @splat(4.2) };
                n += 1;
            },
            .core => if (room(out, n, 1)) {
                const target = carrier.point(m.Vec3.init(0, -10, -4));
                out[n] = .{ .mesh = c.gem, .transform = .{ .position = .{ target[0], target[1], target[2] } }, .tint = Material.emissive(.{ 0.1, 0.9, 1, 1 }, 1.7), .size = @splat(8) };
                n += 1;
            },
            .crashing => {},
        };
    };
    for (sb.skies.shots) |slot| if (slot) |s| if (room(out, n, 1)) {
        out[n] = switch (s.kind) {
            .cannon => .{ .mesh = c.block, .transform = .{ .position = s.position }, .tint = Material.emissive(.{ 0.4, 0.95, 1, 1 }, 1), .size = .{ 0.12, 0.12, 2.2 }, .rotation = facing(s.velocity) },
            .sting => .{ .mesh = c.block, .transform = .{ .position = s.position }, .tint = Material.emissive(.{ 1, 0.2, 0.1, 1 }, 1), .size = .{ 0.14, 0.14, 1.6 }, .rotation = facing(s.velocity) },
            .missile => .{ .mesh = c.block, .transform = .{ .position = s.position }, .tint = Material.emissive(.{ 1, 0.95, 0.85, 1 }, 1), .size = .{ 0.3, 0.3, 1.8 }, .rotation = facing(s.velocity) },
            .flak => .{ .mesh = c.gem, .transform = .{ .position = s.position }, .tint = Material.emissive(.{ 1, 0.6, 0.2, 1 }, 1), .size = @splat(0.8) },
        };
        n += 1;
    };
    // Held weapons, at each armed player's right hand.
    for (&sb.combat.arsenals) |*arsenal| if (arsenal.grip) |g| if (arsenal.active) |kind| if (room(out, n, max_weapon_parts)) {
        n += heldWeapon(out[n..], c.block, kind, g, arsenal, t);
    };
    // Ranger sentries (a squat body, a head turned toward its target) and arc grenades.
    for (sb.specials.sentries) |slot| if (slot) |s| if (room(out, n, 3)) {
        const head = facing(s.aim);
        out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(s.position, .{ 0, 0.35, 0 }) }, .tint = .{ 0.55, 0.58, 0.62, 1 }, .size = .{ 0.55, 0.7, 0.55 } };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(s.position, .{ 0, 1.0, 0 }) }, .tint = .{ 0.3, 0.33, 0.37, 1 }, .size = .{ 0.32, 0.26, 0.6 }, .rotation = head };
        out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = R.add(R.add(s.position, .{ 0, 1.0, 0 }), R.scale(s.aim, 0.31)) }, .tint = Material.emissive(.{ 0.4, 0.95, 1, 1 }, 0.6 + 0.4 * @min(1, s.life)), .size = .{ 0.12, 0.12, 0.03 }, .rotation = head };
        n += 3;
    };
    for (sb.specials.grenades) |slot| if (slot) |g| if (room(out, n, 1)) {
        out[n] = .{ .mesh = c.gem, .transform = .{ .position = g.position }, .tint = Material.emissive(.{ 0.45, 0.8, 1, 1 }, 0.5 + 0.5 * @abs(@sin(g.fuse * 20))), .size = @splat(0.3), .rotation = yawQuat(g.fuse * 9) };
        n += 1;
    };
    // Player shots and effects.
    for (sb.combat.arsenals) |arsenal| for (arsenal.system.projectiles.items) |p| if (p.active and room(out, n, 1)) {
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
            .beam => blk: {
                const length = if (e.length > 0) e.length else 80;
                break :blk .{ .mesh = c.block, .transform = .{ .position = R.add(e.position, R.scale(e.dir, length / 2)) }, .tint = tint, .size = .{ e.size * 0.4 * k, e.size * 0.4 * k, length }, .rotation = facing(e.dir) };
            },
            .trail => .{ .mesh = c.block, .transform = .{ .position = e.position }, .tint = tint, .size = .{ e.size, e.size, e.length }, .rotation = facing(e.dir) },
            .burst, .spark, .muzzle => .{ .mesh = c.gem, .transform = .{ .position = e.position }, .tint = tint, .size = @splat(e.size * (1.5 - k * 0.5)) },
        };
        n += 1;
    };
    return n;
}

const max_weapon_parts = 5;
/// A part of a held weapon: offset along the weapon's frame (+Z along the barrel or blade), size,
/// colour, and glow (0 for plain metal).
const Part = struct { at: [3]f32, size: [3]f32, color: [3]f32, glow: f32 = 0 };
const gunmetal: [3]f32 = .{ 0.16, 0.17, 0.2 };
const plate: [3]f32 = .{ 0.62, 0.64, 0.68 };

/// A held weapon built from blocks: hilt and blade, or a gun's body, barrel and lumen strips.
fn heldWeapon(out: []World.Prop, block: @import("../asset/Catalog.zig").MeshHandle, kind: Combat.WeaponKind, grip: Combat.Grip, arsenal: *const Combat.Arsenal, t: f32) usize {
    const hum = 0.85 + 0.15 * @sin(t * 30);
    const heat = arsenal.charge();
    const parts: []const Part = switch (kind) {
        .beam_saber => &.{
            .{ .at = .{ 0, 0, -0.02 }, .size = .{ 0.06, 0.06, 0.26 }, .color = gunmetal },
            .{ .at = .{ 0, 0, 0.13 }, .size = .{ 0.09, 0.09, 0.04 }, .color = plate },
            .{ .at = .{ 0, 0, 0.15 + 0.675 }, .size = .{ 0.055, 0.055, 1.35 }, .color = .{ 1, 0.82, 0.35 }, .glow = hum },
        },
        .blaster => &.{
            .{ .at = .{ 0, 0.03, 0.05 }, .size = .{ 0.08, 0.13, 0.32 }, .color = plate },
            .{ .at = .{ 0, 0.05, 0.28 }, .size = .{ 0.045, 0.045, 0.2 }, .color = gunmetal },
            .{ .at = .{ 0.042, 0.05, 0.05 }, .size = .{ 0.01, 0.03, 0.24 }, .color = .{ 0.4, 0.9, 1 }, .glow = 0.8 },
        },
        .sniper_rifle => &.{
            .{ .at = .{ 0, 0.03, 0.1 }, .size = .{ 0.07, 0.12, 0.55 }, .color = gunmetal },
            .{ .at = .{ 0, 0.05, 0.75 }, .size = .{ 0.035, 0.035, 0.8 }, .color = plate },
            .{ .at = .{ 0, 0.14, 0.12 }, .size = .{ 0.05, 0.05, 0.3 }, .color = gunmetal },
            .{ .at = .{ 0, 0.14, 0.275 }, .size = .{ 0.04, 0.04, 0.01 }, .color = .{ 0.35, 1, 0.6 }, .glow = 0.6 + heat * 0.4 },
            .{ .at = .{ 0, 0.05, 1.16 }, .size = .{ 0.05, 0.05, 0.04 }, .color = .{ 0.35, 1, 0.6 }, .glow = 0.8 },
        },
        .machine_gun => &.{
            .{ .at = .{ 0, 0.02, 0.12 }, .size = .{ 0.12, 0.15, 0.6 }, .color = gunmetal },
            .{ .at = .{ 0, 0.04, 0.6 }, .size = .{ 0.06, 0.06, 0.4 }, .color = plate },
            .{ .at = .{ 0, -0.12, 0.1 }, .size = .{ 0.1, 0.14, 0.18 }, .color = plate },
            // The barrel shroud glows hotter as the gun heats.
            .{ .at = .{ 0, 0.04, 0.62 }, .size = .{ 0.075, 0.075, 0.3 }, .color = .{ 1, 0.45 + 0.3 * (1 - heat), 0.15 }, .glow = heat },
        },
        .heavy_rifle => &.{
            .{ .at = .{ 0, 0.03, 0.12 }, .size = .{ 0.13, 0.17, 0.7 }, .color = plate },
            .{ .at = .{ 0, 0.05, 0.7 }, .size = .{ 0.08, 0.08, 0.5 }, .color = gunmetal },
            .{ .at = .{ 0.07, 0.05, 0.3 }, .size = .{ 0.012, 0.06, 0.4 }, .color = .{ 0.75, 0.45, 1 }, .glow = 0.5 + heat * 0.5 },
            .{ .at = .{ -0.07, 0.05, 0.3 }, .size = .{ 0.012, 0.06, 0.4 }, .color = .{ 0.75, 0.45, 1 }, .glow = 0.5 + heat * 0.5 },
        },
        .energy_bazooka => &.{
            .{ .at = .{ 0, 0.12, 0.05 }, .size = .{ 0.2, 0.2, 1.1 }, .color = plate },
            .{ .at = .{ 0, 0.12, 0.62 }, .size = .{ 0.24, 0.24, 0.06 }, .color = .{ 1, 0.4, 0.9 }, .glow = 0.4 + 0.6 * heat },
            .{ .at = .{ 0, -0.02, 0 }, .size = .{ 0.05, 0.14, 0.06 }, .color = gunmetal },
        },
        .energy_bow => &.{
            .{ .at = .{ 0, 0, 0.1 }, .size = .{ 0.035, 1.1, 0.04 }, .color = .{ 0.5, 0.85, 1 }, .glow = 0.6 + 0.4 * heat },
            .{ .at = .{ 0, 0, 0.08 }, .size = .{ 0.06, 0.16, 0.06 }, .color = gunmetal },
        },
        .tracking_missile => &.{
            .{ .at = .{ 0, 0.1, 0.05 }, .size = .{ 0.24, 0.2, 0.45 }, .color = plate },
            .{ .at = .{ -0.06, 0.15, 0.28 }, .size = .{ 0.06, 0.06, 0.02 }, .color = .{ 0.6, 1, 0.5 }, .glow = 0.8 },
            .{ .at = .{ 0.06, 0.15, 0.28 }, .size = .{ 0.06, 0.06, 0.02 }, .color = .{ 0.6, 1, 0.5 }, .glow = 0.8 },
            .{ .at = .{ 0, 0.05, 0.28 }, .size = .{ 0.06, 0.06, 0.02 }, .color = .{ 0.6, 1, 0.5 }, .glow = 0.8 },
        },
        .protective_shield => if (arsenal.system.shield.active) &.{
            .{ .at = .{ 0, 0, 0.35 }, .size = .{ 0.9, 1.1, 0.03 }, .color = .{ 0.4, 0.8, 1 }, .glow = 0.45 },
            .{ .at = .{ 0, 0, 0.3 }, .size = .{ 0.12, 0.12, 0.08 }, .color = plate },
        } else &.{
            .{ .at = .{ 0, 0, 0.05 }, .size = .{ 0.12, 0.12, 0.08 }, .color = plate },
        },
        .giant_blast => &.{
            .{ .at = .{ 0, 0, 0.25 }, .size = .{ 0.18, 0.18, 0.18 }, .color = .{ 1, 0.85, 0.35 }, .glow = 0.4 + 0.6 * heat },
        },
    };
    // The weapon frame: +Z along `dir`, kept upright about it.
    const z = R.normalize(grip.dir);
    const side = if (@abs(z[1]) > 0.98) @as(V, .{ 1, 0, 0 }) else R.normalize(R.cross(.{ 0, 1, 0 }, z));
    const up = R.cross(z, side);
    const aim = m.Quat.fromTo(m.Vec3.unit_z, m.Vec3.init(z[0], z[1], z[2]));
    // fromTo leaves the roll free; turn about the barrel so the weapon's +Y is up.
    const rolled = aim.rotate(m.Vec3.unit_y);
    const rolled_y: V = .{ rolled.x, rolled.y, rolled.z };
    const roll = std.math.atan2(R.dot(R.cross(rolled_y, up), z), R.dot(rolled_y, up));
    const rotation = quat(aim.mul(m.Quat.fromAxisAngle(m.Vec3.unit_z, roll)));
    for (parts, 0..) |part, i| {
        const at = R.add(grip.base, R.add(R.add(R.scale(side, part.at[0]), R.scale(up, part.at[1])), R.scale(z, part.at[2])));
        const color: [4]f32 = .{ part.color[0], part.color[1], part.color[2], 1 };
        out[i] = .{ .mesh = block, .transform = .{ .position = at }, .tint = if (part.glow > 0) Material.emissive(color, part.glow) else color, .size = part.size, .rotation = rotation };
    }
    return parts.len;
}

/// The ranges' far panorama (not while anyone is underground: it runs under the slopes, through
/// the caves), cave rock near P1, and lumen crystals lighting the chambers.
fn publishMountains(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const Caves = Sandbox.Caves;
    var n = start;
    var underground = sb.cave_inside[0] != null;
    for (sb.guests, 1..) |g, i| if (g.active and sb.cave_inside[i] != null) {
        underground = true;
    };
    if (!underground and n < out.len and !sb.catalog.ranges.eql(.none)) {
        out[n] = .{ .mesh = sb.catalog.ranges, .transform = .{ .position = .{ 0, 0, 0 } }, .tint = .{ 1, 1, 1, 1 } };
        n += 1;
    }
    const eye = sb.player.feet;
    for (sb.caves.systems[0..sb.caves.count], 0..) |*sys, i| {
        var d: f32 = 0;
        for ([_]usize{ 0, 2 }) |a| d = @max(d, @max(sys.lo[a] - eye[a], eye[a] - sys.hi[a]));
        if (d > 320) continue;
        if (n < out.len and i < sb.catalog.cave_meshes.len and !sb.catalog.cave_meshes[i].eql(.none)) {
            out[n] = .{ .mesh = sb.catalog.cave_meshes[i], .transform = .{ .position = .{ 0, 0, 0 } }, .tint = .{ 1, 1, 1, 1 } };
            n += 1;
        }
        if (d > 160) continue;
        // Crystals cluster around each chamber's walls, in the system's hue.
        const hues = [_][3]f32{ .{ 0.35, 0.9, 1 }, .{ 0.75, 0.45, 1 }, .{ 0.45, 1, 0.6 }, .{ 1, 0.7, 0.35 } };
        const hue = hues[i % hues.len];
        for (sys.rooms[0..sys.room_count], 0..) |room, r| {
            const count: usize = if (room.role == .heart) 8 else 5;
            for (0..count) |k| {
                if (n == out.len) return n;
                const p = Caves.floorSpot(sys, @intCast(r), k, count, 0.78);
                const tall = 0.9 + @as(f32, @floatFromInt((k * 7 + r * 3) % 5)) * 0.35;
                const lean = m.Quat.fromAxisAngle(m.Vec3.unit_y, @as(f32, @floatFromInt(k)) * 2.4).mul(m.Quat.fromAxisAngle(m.Vec3.unit_x, 0.25));
                const glow = 0.65 + 0.25 * @sin(t * 1.3 + @as(f32, @floatFromInt(k + r)));
                out[n] = .{ .mesh = sb.catalog.content.gem, .transform = .{ .position = .{ p[0], p[1] + tall * 0.6, p[2] } }, .tint = Material.emissive(.{ hue[0], hue[1], hue[2], 1 }, glow), .size = .{ 0.45 * tall, 1.6 * tall, 0.45 * tall }, .rotation = quat(lean) };
                n += 1;
            }
        }
    }
    return n;
}

/// Hive troopers: dark red heavy plate, sealed helmets, magenta lumen.
const trooper_profile: @import("Profile.zig") = .{ .outfit = 3, .clothing = .vanguard, .armor = .sentinel, .helmet = .sealed, .accent = 2, .skin = 7, .build = 1.1, .height = 1.05 };

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
