//! Connects the frontier systems to the session: hover cars (`Garage`), pickups
//! (`Collectibles`), the fabricator kiosk, the Hive (`Enemies`) and the arsenal (`Combat`). The
//! Sandbox owns the state; these functions run inside its step, publish and restore.
const std = @import("std");
const mach = @import("mach");
const math = @import("mach").math;
const Physics = @import("../physics/Physics.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Chunk = @import("../procedural/Chunk.zig");
const Cloudwater = @import("../procedural/Cloudwater.zig");
const Region = @import("../world/Region.zig");
const District = @import("../procedural/District.zig");
const Market = @import("../city/Market.zig");
const Material = @import("../render/Material.zig");
const Input = @import("../engine/Input.zig");
const Sandbox = @import("Sandbox.zig");
const Garage = @import("Garage.zig");
const Shrine = @import("../procedural/Shrine.zig");
const WildsMeshes = @import("../vehicle/WildsMeshes.zig");
const Collectibles = @import("Collectibles.zig");
const Enemies = @import("Enemies.zig");
const Loot = @import("Loot.zig");
const EnemyDesign = @import("EnemyDesign.zig");
const Corruption = @import("Corruption.zig");
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
const Heroes = @import("Heroes.zig");
const Encounters = @import("Encounters.zig");
const Pets = @import("Pets.zig");
const DroidCompanion = @import("DroidCompanion.zig");
const Arena = @import("Arena.zig");
const QuestLog = @import("QuestLog.zig");
const FoundryCase = @import("FoundryCase.zig");
const WindsorCase = @import("WindsorCase.zig");
const BileCase = @import("BileCase.zig");
const CityContent = @import("CityContent.zig");
const R = Physics.Rotation;
/// Character ids: troopers take 16–23, Wildkin heroes met in the world 24–31.
pub const hero_first_id: u8 = 32;
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
    // A distant bio-titan foreshadows the Scalari's engineered ground war; the practice patrol
    // near the spawn is deliberately much weaker.
    if (sb.enemies.nest_count > 0) {
        const nest = sb.enemies.nests[0].position;
        _ = sb.enemies.spawnAt(.scalari_titan, 0, R.add(nest, .{ 18, 0, 14 }), 1);
        _ = sb.enemies.spawnAt(.scalari_miner, 0, R.add(nest, .{ -15, 0, -16 }), 1);
        _ = sb.enemies.spawnAt(.scalari_hybrid, 0, R.add(nest, .{ 22, 0, -12 }), 1);
    }
    const surface = sb.enemies.nest_count;
    var nest_sites: [Enemies.max_nests]V = undefined;
    for (sb.enemies.nests[0..surface], 0..) |nest, i| nest_sites[i] = nest.position;
    sb.skies = Skies.init(sb.seed, Sandbox.spawn, nest_sites[0..surface]);
    sb.skies.attachDecks(&sb.physics) catch |err| std.log.warn("could not create carrier landing decks: {s}", .{@errorName(err)});
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
    // The Wildkin heroes' spots: plazas, the meadow ring, cave caches.
    var hero_plazas: [District.node_count]Encounters.Plaza = undefined;
    for (sb.catalog.district.nodes, &hero_plazas) |node, *p| p.* = .{ .position = node.position, .arbor = node.kind == .arbor };
    sb.encounters = Encounters.place(.{ .seed = sb.seed, .spawn = spawn, .plazas = &hero_plazas, .caves = &sb.caves });
    sb.pets.place(sb.seed, spawn);
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

/// Takes the party (P1 and every active guest) into the Starbowl.
pub fn enterArena(sb: *Sandbox, camera: *Camera) void {
    if (sb.arena.active) return;
    if (sb.garage.piloting != null) _ = sb.garage.leave(&sb.physics);
    if (sb.hangar.piloting) leaveJet(sb, camera);
    if (sb.seated != null) sb.exitVehicle(camera);
    // Start the drop-in arena over the current landscape so a pause-menu launch keeps the
    // surrounding biome or city in view. The Starbowl itself stays a safe, bounded platform.
    const at = Arena.siteFor(sb.seed, sb.player.feet, sb.arena.venue);
    sb.arena.open(sb.allocator, &sb.physics, at, Sandbox.world_flag) catch |err| return sb.say("the arena would not open: {s}", .{@errorName(err)});
    _ = sb.enemies.addArenaNest(at);
    sb.arena.returns[0] = sb.player.feet;
    sb.player.mode = .walk;
    sb.player.feet = sb.arena.standing(0);
    sb.player.velocity = @splat(0);
    camera.position = sb.player.eye();
    for (&sb.guests, 1..) |*g, p| {
        sb.arena.returns[p] = if (g.active) g.player.feet else null;
        if (!g.active) continue;
        g.player.feet = sb.arena.standing(p);
        g.player.velocity = @splat(0);
    }
    for (&sb.combat.vitals) |*v| v.health = v.max;
    sb.cue(.vault, null);
    sb.say("THE STARBOWL: hold out against the Hive waves!", .{});
}

/// Leaves the Starbowl: its bots vanish and everyone returns to where they were.
pub fn leaveArena(sb: *Sandbox, camera: *Camera) void {
    if (!sb.arena.active) return;
    for (&sb.enemies.units) |*slot| if (slot.*) |u| if (u.nest == Enemies.arena_nest) {
        slot.* = null;
    };
    sb.enemies.bolts = @splat(null);
    sb.arena.close(&sb.physics);
    if (sb.arena.returns[0]) |back| sb.player.feet = back;
    sb.player.velocity = @splat(0);
    camera.position = sb.player.eye();
    for (&sb.guests, 1..) |*g, p| if (sb.arena.returns[p]) |back| if (g.active) {
        g.player.feet = back;
        g.player.velocity = @splat(0);
    };
    sb.say("left the Starbowl (best wave {d})", .{sb.progress.arena_best});
}

/// Waves, rewards and champions in the Starbowl, and catching anyone who falls off.
fn stepArena(sb: *Sandbox, camera: *Camera, dt: f32) void {
    if (!sb.arena.active) return;
    var party: u8 = 1;
    for (sb.guests) |g| party += @intFromBool(g.active);
    var events: [4]Arena.Event = undefined;
    const n = sb.arena.step(&sb.enemies, Enemies.arena_nest, party, sb.enemies.unitCount(Enemies.arena_nest), dt, &events);
    for (events[0..@min(n, events.len)]) |e| switch (e) {
        .wave_started => |w| {
            sb.cue(.hive_zap, sb.arena.center);
            sb.say("WAVE {d}!", .{w});
        },
        .wave_cleared => |c| {
            sb.cue(.vault, null);
            // Every player in the bowl is paid.
            for (0..Sandbox.max_players) |p| if (sb.present(p)) {
                sb.kits[p].wallet.scrap += c.reward.scrap;
            };
            const center = R.add(sb.arena.center, .{ 0, 1, 0 });
            const loot = [_]struct { kind: Collectibles.Kind, count: u8 }{ .{ .kind = .lumen_shard, .count = c.reward.lumen }, .{ .kind = .hive_alloy, .count = c.reward.alloy }, .{ .kind = .rotor_core, .count = c.reward.rotor }, .{ .kind = .vital_cell, .count = c.reward.vital } };
            var k: usize = 0;
            for (loot) |item| for (0..item.count) |_| {
                const a = @as(f32, @floatFromInt(k)) * 0.9;
                sb.collectibles.drop(item.kind, R.add(center, .{ @sin(a) * (3 + 0.3 * @as(f32, @floatFromInt(k))), 0, @cos(a) * (3 + 0.3 * @as(f32, @floatFromInt(k))) }));
                k += 1;
            };
            if (c.wave > sb.progress.arena_best) sb.progress.arena_best = c.wave;
            sb.say("wave {d} cleared! +{d} scrap and loot in the bowl", .{ c.wave, c.reward.scrap });
            // An arena champion, impressed, joins the roster.
            for (0..Heroes.count) |h| if (Encounters.arenaWave(@intCast(h))) |w| if (w == c.wave) recruit(sb, @intCast(h));
        },
    };
    // Off the edge: set back on the floor.
    if (sb.arena.fallen(sb.player.feet)) {
        sb.player.feet = sb.arena.standing(0);
        sb.player.velocity = @splat(0);
        camera.position = sb.player.eye();
    }
    for (&sb.guests, 1..) |*g, p| if (g.active and sb.arena.fallen(g.player.feet)) {
        g.player.feet = sb.arena.standing(p);
        g.player.velocity = @splat(0);
    };
}

/// Meeting a Wildkin hero: they join the roster (their form opens in the creator, and the
/// Heroes menu lets any player become them).
pub fn recruit(sb: *Sandbox, hero: u8) void {
    if (!sb.progress.addHero(hero)) return;
    const h = Heroes.roster[hero];
    sb.cue(.vault, null);
    sb.say("{s} joined your heroes! Pause > HEROES to play as them", .{h.name});
    sb.progress.setFlag("met_wildkin");
}

/// Player `p` catches a weakened, snared wild animal. Each teammate keeps their own catch record.
pub fn freePet(sb: *Sandbox, p: usize, species: Pets.Species) void {
    if (!sb.pets.canCaptureWild(species)) {
        sb.say("Weaken {s} with the energy net, then get close to catch it", .{Pets.info(species).name});
        return;
    }
    if (!sb.kits[p].freePet(species)) return;
    const kit = &sb.kits[p];
    const capture_xp: u32 = 100;
    const pet_xp: u32 = 60;
    kit.wallet.scrap +|= 15;
    kit.wallet.parts +|= 2;
    kit.inventory[@intFromEnum(Collectibles.Kind.lumen_shard)] +|= 2;
    kit.pet_xp[@intFromEnum(species)] +|= pet_xp;
    const leveled = kit.awardCombatXP(capture_xp);
    const spot = sb.pets.spots[@intFromEnum(species)];
    sb.pets.summon(p, species, spot.position, kit.petLevel(species));
    sb.pets.cheer(p);
    const i = Pets.info(species);
    burst(sb, R.add(spot.position, .{ 0, 1, 0 }), 2.5, i.glow);
    sb.cue(.vault, spot.position);
    sb.say("P{d}: {s} captured! +{d} XP, +15 scrap, +2 parts, +2 lumen; {s} starts at level {d}", .{ p + 1, i.name, capture_xp, i.name, kit.petLevel(species) });
    if (leveled) sb.say("P{d} combat level {d}! (+2 max health)", .{ p + 1, kit.combatLevel() });
    sb.progress.setFlag("freed_pet");
}

/// Player `p` pets `owner`'s pet: a happy trick, or (their own, with more freed) the next one
/// comes out.
pub fn petPet(sb: *Sandbox, p: usize, owner: usize) void {
    const pet = sb.pets.out[owner] orelse return;
    const kit = &sb.kits[owner];
    if (p == owner) if (kit.nextPet()) |next| if (next != pet.species) {
        kit.pet_active = next;
        sb.pets.summon(owner, next, sb.feetOf(owner), kit.petLevel(next));
        sb.pets.cheer(owner);
        sb.cuePitch(.pickup, pet.position, 0.8);
        sb.say("{s} heads home; {s} the {s} comes out (level {d})", .{ Pets.info(pet.species).name, Pets.info(next).name, Pets.info(next).kind, kit.petLevel(next) });
        return;
    };
    sb.pets.cheer(owner);
    sb.cuePitch(.pickup, pet.position, 1.3);
    sb.say("{s} loves that! (level {d})", .{ Pets.info(pet.species).name, kit.petLevel(pet.species) });
}

/// Every present player's pet: bring it out after a load or a join (in step with their kit),
/// let it follow and fight, and apply what it did. Pets of players who left go home.
fn stepPet(sb: *Sandbox, camera: *Camera, dt: f32) void {
    for (0..Sandbox.max_players) |owner| {
        const want = if (sb.present(owner)) sb.kits[owner].pet_active else null;
        const species = want orelse {
            sb.pets.out[owner] = null;
            continue;
        };
        if (sb.pets.out[owner] == null or sb.pets.out[owner].?.species != species) sb.pets.summon(owner, species, sb.feetOf(owner), sb.kits[owner].petLevel(species));
        var hive_events: [16]Enemies.Event = undefined;
        var hn: usize = 0;
        var events: [4]Pets.Event = undefined;
        const n = sb.pets.step(owner, .{ .owner = sb.feetOf(owner), .owner_yaw = sb.yawOf(owner), .level = sb.kits[owner].petLevel(species), .seed = sb.seed, .physics = &sb.physics, .skies = &sb.skies }, &sb.enemies, dt, &hive_events, &hn, &events);
        for (events[0..@min(n, events.len)]) |e| switch (e) {
            .attack => |a| sb.cuePitch(switch (a.species) {
                .hound, .golem => .impact,
                .falcon, .moth => .zap,
            }, a.at, if (a.species == .golem) 0.7 else 1.2),
            .air_attack => |a| {
                sb.cuePitch(.zap, a.at, 1.3);
                if (a.downed) {
                    burst(sb, a.at, 3.5, Pets.info(a.species).glow);
                    dropBelow(sb, .hive_alloy, a.at);
                    sb.progress.setFlag("wasp_down");
                    petLearns(sb, a.at);
                    if (a.raid_repelled) {
                        sb.progress.setFlag("bomber_raid_defended");
                        sb.say("{s} drove off the market bomber!", .{Pets.info(a.species).name});
                    }
                }
            },
            .hurt => |h| sb.cuePitch(.hurt, h.at, 0.8),
            .mend => |m_| {
                var mended = false;
                for (0..Sandbox.max_players) |p| {
                    if (!sb.present(p)) continue;
                    if (R.length(R.sub(sb.feetOf(p), m_.at)) > m_.radius + 2.5) continue;
                    const v = &sb.combat.vitals[p];
                    if (v.health >= v.max or v.health <= 0) continue;
                    v.health = @min(v.max, v.health + m_.amount);
                    mended = true;
                }
                if (mended) burst(sb, m_.at, 1.2, Pets.info(.moth).glow);
            },
        };
        for (hive_events[0..@min(hn, hive_events.len)]) |e| hive(sb, e, camera);
    }
}

/// A Hive unit downed near a pet teaches it something.
fn petLearns(sb: *Sandbox, at: V) void {
    for (sb.pets.out, 0..) |maybe, owner| {
        const pet = maybe orelse continue;
        if (R.length(R.sub(pet.position, at)) > Pets.share_radius) continue;
        const k = @intFromEnum(pet.species);
        const xp = &sb.kits[owner].pet_xp[k];
        const before = Pets.levelFor(xp.*);
        xp.* +|= Pets.xp_per_unit;
        const after = Pets.levelFor(xp.*);
        if (after > before) {
            sb.pets.cheer(owner);
            sb.say("P{d}'s {s} grew to level {d}!", .{ owner + 1, Pets.info(pet.species).name, after });
        }
    }
}

/// A field droid learns from local takedowns and keeps its levels with its owner.
fn robotLearns(sb: *Sandbox, at: V) void {
    for (sb.droid_companions.out, 0..) |maybe, owner| {
        const droid = maybe orelse continue;
        if (!sb.kits[owner].robot_built or R.length(R.sub(droid.position, at)) > DroidCompanion.share_radius) continue;
        if (sb.kits[owner].awardRobotXP(DroidCompanion.xp_per_unit)) {
            const level = sb.kits[owner].robotLevel();
            sb.say("P{d}'s field droid upgraded to level {d}!", .{ owner + 1, level });
            if (sb.droid_companions.out[owner]) |*robot| robot.max_health = DroidCompanion.maxHealth(level);
        }
    }
}

/// Whether some present player has yet to free `species` (so its wild one still waits).
fn petWaiting(sb: *const Sandbox, species: Pets.Species) bool {
    for (0..Sandbox.max_players) |p| if (sb.present(p) and !sb.kits[p].hasPet(species)) return true;
    return false;
}

/// Wild pets near P1 (collared at their spots, with a beam to find them by) while a present
/// player has yet to catch them, and every player's pet in their accent, as puppets.
fn publishPets(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    var n = start;
    const c = &sb.catalog.content;
    const parts: Pets.Parts = .{ .orb = c.orb, .block = c.block, .spike = c.spike };
    const accentOf = struct {
        fn f(profile: Profile) [3]f32 {
            const lumen = Profile.accent_colors[profile.accent];
            return .{ lumen[0], lumen[1], lumen[2] };
        }
    }.f;
    if (sb.pets.placed) for (sb.pets.spots, 0..) |spot, k| {
        const sp: Pets.Species = @enumFromInt(k);
        if (!petWaiting(sb, sp) and !sb.pets.showcase_free) continue;
        const d = R.length(R.sub(spot.position, sb.player.feet));
        if (d > 400) continue;
        if (n < out.len and !sb.pets.showcase_free) {
            const beam: [4]f32 = if (sb.pets.canCaptureWild(sp)) .{ 0.25, 0.9, 1, 1 } else .{ 1.0, 0.25, 0.4, 1 };
            out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(spot.position, .{ 0, 18, 0 }) }, .tint = Material.emissive(beam, 0.45 + 0.2 * @sin(t * 3)), .size = .{ 0.14, 32, 0.14 } };
            n += 1;
        }
        if (d > 90) continue;
        const flies = Pets.info(sp).flies;
        const at = if (flies) R.add(spot.position, .{ 0, Pets.hover + 0.15 * @sin(t * 2), 0 }) else spot.position;
        n = Pets.draw(sp, .{ .position = at, .yaw = spot.yaw + 0.3 * @sin(t * 0.7 + @as(f32, @floatFromInt(k))), .time = t + @as(f32, @floatFromInt(k)), .wild = !sb.pets.showcase_free, .collar = accentOf(sb.profile) }, parts, out, n);
    };
    for (sb.pets.out, 0..) |maybe, owner| if (maybe) |pet| {
        n = Pets.draw(pet.species, .{ .position = pet.position, .yaw = pet.yaw, .gait = pet.gait, .stride = pet.stride, .action = pet.action, .trick = pet.trick, .engaged = pet.engaged, .time = t + @as(f32, @floatFromInt(owner)) * 0.37, .collar = accentOf(sb.profileOf(owner).*) }, parts, out, n);
    };
    for (sb.droid_companions.out, 0..) |maybe, owner| if (maybe) |droid| {
        if (out.len - n < 8) break;
        const c0 = accentOf(sb.profileOf(owner).*);
        const tint: [4]f32 = if (droid.flash > 0) .{ 1.5, 1.2, 1.2, 1 } else .{ 0.23, 0.29, 0.34, 1 };
        const at = droid.position;
        const body = R.add(at, .{ 0, 0.64, 0 });
        const head = R.add(at, .{ 0, 1.16, 0.08 });
        out[n] = .{ .mesh = c.block, .transform = .{ .position = body }, .tint = tint, .size = .{ 0.72, 0.62, 0.62 }, .rotation = yawQuat(droid.yaw) };
        out[n + 1] = .{ .mesh = c.gem, .transform = .{ .position = head }, .tint = .{ 0.31, 0.38, 0.43, 1 }, .size = .{ 0.48, 0.37, 0.44 }, .rotation = yawQuat(droid.yaw) };
        out[n + 2] = .{ .mesh = c.gem, .transform = .{ .position = R.add(head, .{ 0, 0, 0.24 }) }, .tint = Material.emissive(.{ c0[0], c0[1], c0[2], 1 }, if (droid.engaged) @as(f32, 1.25) else 0.75), .size = .{ 0.23, 0.14, 0.06 } };
        out[n + 3] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ -0.47, 0.62, 0 }) }, .tint = tint, .size = .{ 0.22, 0.64, 0.25 }, .rotation = yawQuat(droid.yaw) };
        out[n + 4] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0.47, 0.62, 0 }) }, .tint = tint, .size = .{ 0.22, 0.64, 0.25 }, .rotation = yawQuat(droid.yaw) };
        out[n + 5] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ -0.22, 0.16, 0 }) }, .tint = .{ 0.15, 0.19, 0.22, 1 }, .size = .{ 0.18, 0.28, 0.2 } };
        out[n + 6] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0.22, 0.16, 0 }) }, .tint = .{ 0.15, 0.19, 0.22, 1 }, .size = .{ 0.18, 0.28, 0.2 } };
        out[n + 7] = .{ .mesh = c.gem, .transform = .{ .position = R.add(at, .{ 0, 0.66, -0.34 }) }, .tint = Material.emissive(.{ 1, 0.48, 0.12, 1 }, if (droid.health > 0) @as(f32, 0.9) else 0.15), .size = .{ 0.19, 0.19, 0.12 } };
        n += 8;
    };
    return n;
}

/// The art-led K2 stop: a small marble-and-ice hamlet, golden sheltered grove, natural arch,
/// distant floating ice-rocks and a marked cascade route. These are visual props; the streamed
/// K2 heightmap remains the walkable/collidable ground and the custom water mesh carries the falls.
fn publishCloudwater(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const center = Cloudwater.arrival;
    const eye = sb.player.feet;
    const dx = center[0] - eye[0];
    const dz = center[1] - eye[2];
    if (dx * dx + dz * dz > 2400 * 2400) return start;

    const c = &sb.catalog.content;
    var n = start;
    const town: [2]f32 = .{ center[0] - 72, center[1] + 52 };
    if (n + 9 <= out.len) {
        // Five staggered terraces make a readable arrival plaza, with two low shelters set into
        // the hill and a blue-lit stone arch facing the waterfall path.
        const decks = [_]struct { x: f32, z: f32, w: f32, d: f32, tint: [4]f32 }{
            .{ .x = 0, .z = 0, .w = 30, .d = 22, .tint = .{ 0.72, 0.82, 0.83, 1 } },
            .{ .x = -23, .z = 12, .w = 16, .d = 11, .tint = .{ 0.84, 0.86, 0.81, 1 } },
            .{ .x = 22, .z = 11, .w = 15, .d = 10, .tint = .{ 0.59, 0.70, 0.73, 1 } },
            .{ .x = -17, .z = -17, .w = 13, .d = 9, .tint = .{ 0.78, 0.80, 0.74, 1 } },
            .{ .x = 18, .z = -18, .w = 12, .d = 10, .tint = .{ 0.73, 0.81, 0.82, 1 } },
        };
        for (decks) |deck| {
            const x = town[0] + deck.x;
            const z = town[1] + deck.z;
            const ground = Terrain.surface(sb.seed, x, z).height;
            out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ x, ground + 0.55, z } }, .size = .{ deck.w, 1.1, deck.d }, .tint = deck.tint };
            n += 1;
        }
        const sanctuary_ground = Terrain.surface(sb.seed, town[0], town[1]).height;
        out[n] = .{ .mesh = c.cave_temple, .transform = .{ .position = .{ town[0], sanctuary_ground + 0.8, town[1] } }, .size = .{ 0.74, 0.74, 0.74 }, .tint = .{ 0.94, 0.91, 0.78, 1 } };
        n += 1;
        const cabin_a: V = .{ town[0] - 35, Terrain.surface(sb.seed, town[0] - 35, town[1] + 22).height, town[1] + 22 };
        const cabin_b: V = .{ town[0] + 32, Terrain.surface(sb.seed, town[0] + 32, town[1] - 24).height, town[1] - 24 };
        out[n] = .{ .mesh = c.wilds_cabin, .transform = .{ .position = cabin_a }, .size = .{ 0.8, 0.8, 0.8 }, .tint = .{ 0.82, 0.90, 0.91, 1 } };
        out[n + 1] = .{ .mesh = c.wilds_cabin, .transform = .{ .position = cabin_b }, .size = .{ 0.72, 0.72, 0.72 }, .rotation = yawQuat(0.8), .tint = .{ 0.77, 0.82, 0.77, 1 } };
        n += 2;
        const signal = Material.emissive(.{ 0.26, 0.79, 1, 1 }, 1.0 + 0.18 * @sin(t * 1.6));
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ town[0], sanctuary_ground + 1.35, town[1] - 15 } }, .size = .{ 18, 0.16, 0.26 }, .tint = signal };
        n += 1;
    }

    // A tall arch of blue ice frames the first cascade. Its base follows the same carved terrain
    // sample used by collision; the river itself is streamed through the water shader.
    const arch_x = Region.k2.arrival[0] + 840;
    const arch_z = Cloudwater.streamCenterZ(Chunk.regionalSeedAt(sb.seed, arch_x, center[1]), arch_x);
    const arch_ground = Terrain.surface(sb.seed, arch_x, arch_z).height;
    if (n < out.len) {
        out[n] = .{ .mesh = c.cave_arch, .transform = .{ .position = .{ arch_x, arch_ground, arch_z } }, .size = .{ 1.8, 2.25, 1.5 }, .rotation = yawQuat(@as(f32, std.math.pi) * 0.5), .tint = .{ 0.41, 0.72, 0.87, 1 } };
        n += 1;
    }

    // Six lightweight islands echo the floating landforms in the clay scene. They deliberately
    // have no collision so they cannot become invisible platforms or block the mountain route.
    const islands = [_]struct { x: f32, z: f32, up: f32, scale: f32, turn: f32 }{
        .{ .x = -185, .z = -72, .up = 115, .scale = 24, .turn = 0.3 },
        .{ .x = 45, .z = -115, .up = 172, .scale = 30, .turn = 1.2 },
        .{ .x = 245, .z = 25, .up = 128, .scale = 21, .turn = 2.1 },
        .{ .x = 410, .z = 105, .up = 205, .scale = 34, .turn = 0.8 },
        .{ .x = 635, .z = -50, .up = 148, .scale = 25, .turn = 2.6 },
        .{ .x = -470, .z = 145, .up = 188, .scale = 28, .turn = 1.8 },
    };
    for (islands, 0..) |island, i| {
        if (n + 2 > out.len) return n;
        const x = center[0] + island.x;
        const z = center[1] + island.z;
        const ground = Terrain.surface(sb.seed, x, z).height;
        out[n] = .{ .mesh = c.boulders[i % c.boulders.len], .transform = .{ .position = .{ x, ground + island.up, z }, .scale = island.scale }, .rotation = yawQuat(island.turn), .tint = if (i % 2 == 0) .{ 0.63, 0.81, 0.92, 1 } else .{ 0.78, 0.86, 0.88, 1 } };
        out[n + 1] = .{ .mesh = c.spike, .transform = .{ .position = .{ x + 1.8, ground + island.up - island.scale * 0.72, z - 2 }, .scale = island.scale * 0.17 }, .rotation = yawQuat(island.turn + 0.6), .tint = .{ 0.46, 0.68, 0.78, 1 } };
        n += 2;
    }

    // The sheltered grove mixes dark alpine pines with amber copper-fan crowns.
    for (0..9) |i| {
        if (n == out.len) return n;
        const angle = @as(f32, @floatFromInt(i)) * (@as(f32, 2) * std.math.pi / 9.0);
        const radius = 26 + @as(f32, @floatFromInt(i % 3)) * 15;
        const x = Cloudwater.grove_center[0] + @cos(angle) * radius;
        const z = Cloudwater.grove_center[1] + @sin(angle) * radius;
        const ground = Terrain.surface(sb.seed, x, z).height;
        const golden = i % 3 == 0;
        out[n] = .{
            .mesh = c.flora[if (golden) 11 else 14],
            .transform = .{ .position = .{ x, ground, z }, .scale = if (golden) 42 else 38 },
            .rotation = yawQuat(angle),
            .tint = if (golden) .{ 1.8, 1.1, 0.55, 1 } else .{ 0.84, 0.94, 1.04, 1 },
        };
        n += 1;
    }
    return n;
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

fn startK2Encounter(sb: *Sandbox, cave_index: u8) void {
    if (cave_index >= sb.caves.count or sb.caves.systems[cave_index].range != @import("../procedural/Mountains.zig").count or sb.progress.hasFlag("k2_black_summit_down")) return;
    var nest_index: ?u8 = null;
    var cave_ordinal: usize = 0;
    for (sb.enemies.nests[0..sb.enemies.nest_count], 0..) |nest, i| if (nest.cave) {
        if (cave_ordinal == cave_index) {
            nest_index = @intCast(i);
            break;
        }
        cave_ordinal += 1;
    };
    const nest = nest_index orelse return;
    const heart = sb.caves.systems[cave_index].heart();
    for (sb.enemies.units) |maybe| if (maybe) |unit| if (unit.kind == .scalari_titan and unit.nest == nest) return;
    _ = sb.enemies.spawnAt(.scalari_titan, nest, .{ heart.center[0] - 8, heart.floor, heart.center[2] - 6 }, 1);
    _ = sb.enemies.spawnAt(.scalari_stinger, nest, .{ heart.center[0] + 8, heart.floor, heart.center[2] + 4 }, 1);
    _ = sb.enemies.spawnAt(.scalari_hybrid, nest, .{ heart.center[0] + 2, heart.floor, heart.center[2] + 10 }, 1);
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
        if (p == 0) if (inside) |cave_index| startK2Encounter(sb, cave_index);
        if (inside != null and inside != sb.cave_inside[p]) {
            var flag: [20]u8 = undefined;
            const first = !sb.progress.hasFlag(std.fmt.bufPrint(&flag, "cave_{d}_found", .{inside.?}) catch unreachable);
            sb.progress.setFlag(std.fmt.bufPrint(&flag, "cave_{d}_found", .{inside.?}) catch unreachable);
            if (p == 0) sb.say("{s}{s}", .{ Caves.systemName(&sb.caves, inside.?), if (first) ": a new cave" else "" });
            if (first) sb.cue(.vault, null);
        }
        sb.cave_inside[p] = inside;
    }
}

/// After a load (or a new game): nests follow their flags, owned cars park on their pads, and
/// the party's health follows its vital cells.
pub fn refresh(sb: *Sandbox) void {
    restoreSeededNests(sb);
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
        if (!c.alive and sb.physics.valid(c.deck_body)) {
            sb.physics.destroyBody(c.deck_body);
            c.deck_body = .none;
        }
    }
    sb.skies.attachDecks(&sb.physics) catch |err| std.log.warn("could not restore carrier landing decks: {s}", .{@errorName(err)});
    sb.skies.wasps = @splat(null);
    sb.skies.shots = @splat(null);
    sb.skies.guns = .{};
    sb.hangar = .{};
    if (sb.progress.fighter) sb.hangar.placeWithFrame(sb.seed, Sandbox.spawn, null, 0, sb.progress.kestrel_levels, sb.progress.space_frame);
    sb.skies.configureKestrel(sb.progress.kestrel_levels);
    sb.garage = .{};
    // A vehicle is a core traversal tool, not a late-game reward. Grant the starter aircar to
    // fresh worlds and older saves that have never fabricated a ride.
    if (sb.progress.vehicles == 0) {
        sb.progress.vehicles |= @as(u8, 1) << @intCast(@intFromEnum(Designs.Design.skimmer));
        sb.say("prototype SKIMMER unlocked: board the blue-lit car at the garage to drive and fly", .{});
    }
    for (0..Designs.count) |d| if (sb.progress.ownsVehicle(@enumFromInt(d))) sb.garage.park(sb.seed, Sandbox.spawn, sb.catalog, @enumFromInt(d));
    sb.collectibles.drops = @splat(null);
    sb.specials = .{};
    for (0..Sandbox.max_players) |p| sb.combat.setPlayerMax(p, sb.kits[p].maxHealth() + Specials.loadout(sb.profileOf(p).*).health);
    for (&sb.combat.vitals) |*v| v.health = v.max;
    // Whatever each loaded ranger already wears stays available to them.
    for (0..Sandbox.max_players) |p| {
        sb.kits[p].suits |= Progress.bit(sb.profileOf(p).clothing);
        sb.kits[p].armors |= Progress.armorBit(sb.profileOf(p).armor);
    }
}

/// First campaign beat: corruption advances once the frontier reaches its first new market day.
pub const MarketBeat = struct { corruption_started: bool = false, seeded_nest: ?u8 = null };
pub fn marketDay(sb: *Sandbox) MarketBeat {
    var beat: MarketBeat = .{};
    if (sb.market.day >= 1 and !sb.progress.hasFlag("corruption_seen")) {
        sb.progress.setFlag("corruption_seen");
        sb.cue(.hive_zap, null);
        beat.corruption_started = true;
    }
    beat.seeded_nest = seedNestAtMarketDay(sb);
    return beat;
}

fn seedFlag(buffer: []u8, serial: u8, parent: u8) []const u8 {
    return std.fmt.bufPrint(buffer, "bloom_{d}_from_{d}", .{ serial, parent }) catch unreachable;
}

fn seededCount(sb: *const Sandbox) u8 {
    var count: u8 = 0;
    for (sb.enemies.nests[0..sb.enemies.nest_count]) |nest| count += @intFromBool(nest.seeded);
    return count;
}

fn savedSeedParent(sb: *const Sandbox, serial: u8) ?u8 {
    var flag: [24]u8 = undefined;
    for (0..sb.enemies.nest_count) |parent| if (sb.progress.hasFlag(seedFlag(&flag, serial, @intCast(parent)))) return @intCast(parent);
    return null;
}

/// Rebuild campaign spires from the saved parent flags before applying each nest's destroyed
/// flag. The same parent and seed always give the same surface position.
fn restoreSeededNests(sb: *Sandbox) void {
    var serial = seededCount(sb);
    while (serial < Enemies.max_seeded_nests) : (serial += 1) {
        const parent = savedSeedParent(sb, serial) orelse break;
        const spread_day = (@as(u64, serial) + 1) * 2;
        if (sb.enemies.addSeededNest(parent, serial, spread_day) == null) break;
    }
}

fn seedNestAtMarketDay(sb: *Sandbox) ?u8 {
    const serial = seededCount(sb);
    if (serial >= Enemies.max_seeded_nests or sb.market.day < (@as(u64, serial) + 1) * 2) return null;
    var parent: ?u8 = null;
    var i = sb.enemies.nest_count;
    while (i > 0) {
        i -= 1;
        const nest = sb.enemies.nests[i];
        if (!nest.cave and nest.alive) {
            parent = @intCast(i);
            break;
        }
    }
    const source = parent orelse return null;
    const spread_day = (@as(u64, serial) + 1) * 2;
    const child = sb.enemies.addSeededNest(source, serial, spread_day) orelse return null;
    var flag: [24]u8 = undefined;
    sb.progress.setFlag(seedFlag(&flag, serial, source));
    sb.cue(.hive_zap, sb.enemies.nests[child].position);
    return child;
}

/// Hover car, fabricator or nothing, along the hands' aim.
pub fn pick(sb: *const Sandbox, eye: V, dir: V, reach: f32, best: f32, player_slot: usize) ?Sandbox.Target {
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
        nearest = hit.distance;
        result = .fabricator;
    };
    // Wild pets in their collars, and the party's own pet.
    if (sb.pets.placed) for (sb.pets.spots, 0..) |spot, k| {
        const sp: Pets.Species = @enumFromInt(k);
        if (!petWaiting(sb, sp)) continue;
        const lift: f32 = if (Pets.info(sp).flies) Pets.hover else 0.7;
        if (Enemies.segmentSphere(eye, dir, nearest, R.add(spot.position, .{ 0, lift, 0 }), 0.9)) |t| {
            nearest = t;
            result = .{ .wild_pet = sp };
        }
    };
    for (sb.pets.out, 0..) |maybe, owner| if (maybe) |pet| {
        const lift: f32 = if (Pets.info(pet.species).flies) 0 else 0.6;
        if (Enemies.segmentSphere(eye, dir, nearest, R.add(pet.position, .{ 0, lift, 0 }), 0.8)) |t| {
            nearest = t;
            result = .{ .pet = @intCast(owner) };
        }
    };
    // Wildkin waiting to be met.
    for (sb.encounters) |maybe| if (maybe) |spot| if (!sb.progress.hasHero(spot.hero)) {
        if (Enemies.segmentSphere(eye, dir, nearest, R.add(spot.position, .{ 0, 1.1, 0 }), 0.9)) |t| {
            nearest = t;
            result = .{ .hero = spot.hero };
        }
    };
    if (sb.progress.hasFlag("foundry_started") and !sb.progress.hasFlag("foundry_exposed")) {
        var points: [FoundryCase.checkpoint_count]V = undefined;
        const count = FoundryCase.positions(&sb.catalog.district, &points);
        for (points[0..count], 0..) |point, index| {
            if (FoundryCase.collected(&sb.progress, index)) continue;
            if (Physics.rayBox(eye, dir, point, .{ 0.7, 0.9, 0.7 })) |hit| if (hit.distance < nearest) {
                nearest = hit.distance;
                result = .{ .evidence = @intCast(index) };
            };
        }
    }
    if (sb.progress.hasFlag(WindsorCase.started_flag) and !sb.progress.hasFlag(WindsorCase.exposed_flag)) {
        var points: [WindsorCase.checkpoint_count]V = undefined;
        const count = WindsorCase.positions(&sb.catalog.district, &points);
        for (points[0..count], 0..) |point, index| {
            if (WindsorCase.collected(&sb.progress, index)) continue;
            if (Physics.rayBox(eye, dir, point, .{ 0.85, 1.0, 0.85 })) |hit| if (hit.distance < nearest) {
                nearest = hit.distance;
                result = .{ .windsor_evidence = @intCast(index) };
            };
        }
    }
    if (sb.progress.hasFlag(BileCase.started_flag) and !sb.progress.hasFlag(BileCase.exposed_flag)) {
        if (!sb.progress.hasFlag(BileCase.traces_complete_flag)) {
            var points: [BileCase.trace_count]V = undefined;
            const count = BileCase.tracePositions(sb.seed, &points);
            for (points[0..count], 0..) |point, index| {
                if (BileCase.collected(&sb.progress, index)) continue;
                if (Physics.rayBox(eye, dir, point, .{ 0.8, 0.9, 0.8 })) |hit| if (hit.distance < nearest) {
                    nearest = hit.distance;
                    result = .{ .bile_trace = @intCast(index) };
                };
            }
        } else if (!sb.progress.hasFlag(BileCase.vault_open_flag)) {
            for (0..BileCase.relay_count) |index| {
                const point = BileCase.relayPosition(sb.seed, index) orelse continue;
                if (Physics.rayBox(eye, dir, point, .{ 0.8, 1.3, 0.8 })) |hit| if (hit.distance < nearest) {
                    nearest = hit.distance;
                    result = .{ .bile_relay = @intCast(index) };
                };
            }
        } else if (!sb.progress.hasFlag(BileCase.notes_read_flag)) {
            const point = BileCase.notesPosition(sb.seed);
            if (Physics.rayBox(eye, dir, point, .{ 0.85, 0.9, 0.85 })) |hit| if (hit.distance < nearest) {
                nearest = hit.distance;
                result = .bile_notes;
            };
        }
    }
    if (sb.progress.hasFlag(FoundryCase.reported_flag) and !sb.progress.hasFlag(FoundryCase.confrontation_flag)) {
        if (FoundryCase.consolePosition(&sb.catalog.district)) |console| {
            if (Physics.rayBox(eye, dir, console, .{ 0.8, 0.9, 0.75 })) |hit| if (hit.distance < nearest) {
                nearest = hit.distance;
                result = .foundry_terminal;
            };
        }
    }
    for (sb.city_discovery_positions, 0..) |point, index| {
        if (!cityDiscoveryAvailable(sb, player_slot, index)) continue;
        if (Physics.rayBox(eye, dir, point, .{ 1.0, 1.05, 1.0 })) |hit| if (hit.distance < nearest) {
            // A closed challenge cage (or any wall) between the eye and the keepsake hides it.
            if (sb.physics.castRay(eye, dir, @max(0, hit.distance - 0.05), .none) == null) {
                nearest = hit.distance;
                result = .{ .city_discovery = @intCast(index) };
            }
        };
    }
    return result;
}

fn cityDiscoveryAvailable(sb: *const Sandbox, owner: usize, index: usize) bool {
    if (owner >= Sandbox.max_players or index >= CityContent.discovery_count or !sb.present(owner)) return false;
    return switch (CityContent.detroit.discoveries[index].reward) {
        .shared => |flag| !sb.progress.hasFlag(flag),
        .personal => !sb.kits[owner].hasCityDiscovery(index),
    };
}

fn anyPlayerNeedsDiscovery(sb: *const Sandbox, index: usize) bool {
    if (index >= CityContent.discovery_count) return false;
    return switch (CityContent.detroit.discoveries[index].reward) {
        .shared => |flag| !sb.progress.hasFlag(flag),
        .personal => for (0..Sandbox.max_players) |owner| {
            if (sb.present(owner) and !sb.kits[owner].hasCityDiscovery(index)) break true;
        } else false,
    };
}

fn anyPlayerNear(sb: *const Sandbox, point: V, radius: f32) bool {
    for (0..Sandbox.max_players) |owner| {
        if (sb.present(owner) and R.length(R.sub(point, sb.feetOf(owner))) <= radius) return true;
    }
    return false;
}

fn awardDiscoveryUpgrade(sb: *Sandbox, owner: usize, upgrade: Sandbox.Kit.Upgrade) bool {
    const kit = &sb.kits[owner];
    const level = kit.level(upgrade);
    if (level >= Sandbox.Kit.max_level) return false;
    kit.levels[@intFromEnum(upgrade)] = level + 1;
    return true;
}

/// A personal discovery is claimed and rewarded by the interacting ranger only.
pub fn collectCityDiscovery(sb: *Sandbox, owner: usize, index: u8) void {
    const i: usize = index;
    if (owner >= Sandbox.max_players or !sb.present(owner) or i >= CityContent.discovery_count) return;
    const discovery = CityContent.detroit.discoveries[i];
    switch (discovery.reward) {
        .shared => |flag| {
            if (sb.progress.hasFlag(flag)) return;
            sb.progress.setFlag(flag);
            sb.say("{s} recovered; shared city record updated", .{discovery.name});
        },
        .personal => |reward| {
            if (!sb.kits[owner].claimCityDiscovery(i)) return;
            const kit = &sb.kits[owner];
            const message: []const u8 = switch (reward) {
                .flight_cell => if (awardDiscoveryUpgrade(sb, owner, .fuel_tank)) "flight cell installed: Fuel Tank +1" else blk: {
                    kit.wallet.scrap +|= 60;
                    break :blk "flight cell converted to 60 scrap; Fuel Tank is full";
                },
                .suit_upgrade => if (awardDiscoveryUpgrade(sb, owner, .sprint_servos)) "suit servo installed: Sprint Servos +1" else blk: {
                    kit.wallet.scrap +|= 60;
                    break :blk "servo converted to 60 scrap; Sprint Servos are full";
                },
                .energy_upgrade => if (awardDiscoveryUpgrade(sb, owner, .jet_efficiency)) "energy regulator installed: Jet Efficiency +1" else blk: {
                    kit.wallet.scrap +|= 60;
                    break :blk "regulator converted to 60 scrap; Jet Efficiency is full";
                },
                .grapple_upgrade => if (awardDiscoveryUpgrade(sb, owner, .grapple_reel)) "pylon reel installed: Grapple Reel +1" else blk: {
                    kit.wallet.scrap +|= 60;
                    break :blk "pylon reel converted to 60 scrap; Grapple Reel is full";
                },
                .travel_item => blk: {
                    kit.wallet.scrap +|= 60;
                    break :blk "transit voucher added: 60 scrap";
                },
                .armor_gem => if (!kit.ownsArmor(.gem_aegis)) blk: {
                    kit.armors |= Sandbox.Kit.armorBit(.gem_aegis);
                    break :blk "Rootway Gem unlocked: Gem Aegis armor";
                } else blk: {
                    kit.wallet.scrap +|= 80;
                    break :blk "duplicate Rootway Gem converted to 80 scrap";
                },
                .pet_freed => if (kit.freePet(.moth)) "Lumi freed; the Lumen Moth is yours" else blk: {
                    kit.wallet.scrap +|= 80;
                    break :blk "duplicate pet collar converted to 80 scrap";
                },
                .growth_item => "growth sample recovered",
            };
            sb.say("P{d}: {s}", .{ owner + 1, message });
        },
    }
    sb.cue(.pickup, sb.city_discovery_positions[i]);
}

/// Recover one manifest page from a generated industrial checkpoint. Story state is shared.
pub fn collectFoundryEvidence(sb: *Sandbox, index: u8) void {
    if (!FoundryCase.collect(&sb.progress, index)) return;
    const recovered = FoundryCase.count(&sb.progress);
    sb.say("manifest page recovered: {d}/{d}", .{ recovered, FoundryCase.checkpoint_count });
    sb.cue(.pickup, foundryCasePosition(sb, index));
}

/// File a bridge toll log or closed-session recording into the shared Windsor case.
pub fn collectWindsorEvidence(sb: *Sandbox, index: u8) void {
    if (!WindsorCase.collect(&sb.progress, index)) return;
    const recovered = WindsorCase.count(&sb.progress);
    const label: []const u8 = if (index < 2) "toll-gate log" else "council recording";
    sb.say("{s} recovered: {d}/{d}", .{ label, recovered, WindsorCase.checkpoint_count });
    var points: [WindsorCase.checkpoint_count]V = undefined;
    const count = WindsorCase.positions(&sb.catalog.district, &points);
    sb.cue(.pickup, if (index < count) points[index] else sb.player.feet);
}

/// Recover one institute trace; story state is shared across the party.
pub fn collectBileTrace(sb: *Sandbox, index: u8) void {
    if (!BileCase.collectTrace(&sb.progress, index)) return;
    const relay = sb.bile_sequence[index] + 1;
    sb.say("trace {d}/3: press archive relay {d} in slot {d}", .{ index + 1, relay, index + 1 });
    var points: [BileCase.trace_count]V = undefined;
    const n = BileCase.tracePositions(sb.seed, &points);
    sb.cue(.pickup, if (index < n) points[index] else sb.player.feet);
}

/// Press one archive relay; a wrong input restarts the sequence from its first symbol.
pub fn pressBileRelay(sb: *Sandbox, index: u8) void {
    const result = BileCase.pressRelay(&sb.progress, sb.bile_sequence, &sb.bile_relay_step, index);
    switch (result) {
        .unavailable => {},
        .wrong => {
            const first = sb.bile_sequence[0] + 1;
            sb.say("wrong relay; begin with relay {d}", .{first});
            sb.cue(.hive_zap, BileCase.relayPosition(sb.seed, index));
        },
        .progress => sb.say("relay accepted: {d}/{d}", .{ sb.bile_relay_step, BileCase.relay_count }),
        .opened => {
            sb.say("archive vault opened; recover Dr. Bile's notes inside", .{});
            sb.cue(.vault, BileCase.institutePosition(sb.seed));
        },
    }
}

/// Read the notes left in the opened archive. Reporting them to Tavi exposes the case.
pub fn readBileNotes(sb: *Sandbox) void {
    if (!BileCase.readNotes(&sb.progress)) return;
    sb.say("Dr. Bile's notes copied; take the archive record to Tavi", .{});
    sb.cue(.pickup, BileCase.notesPosition(sb.seed));
}

/// Publish the case at the loading dock terminal and draw the steward and brood scavengers out.
pub fn startFoundryDockEncounter(sb: *Sandbox) void {
    if (!FoundryCase.beginDockConfrontation(&sb.progress)) return;
    ensureFoundryDockEncounter(sb);
    sb.say("ledger published: the foundry steward and brood scavengers are at the yard gate", .{});
    sb.cue(.hive_zap, FoundryCase.gatePosition(&sb.catalog.district));
}

fn awardFoundrySuitUpgrade(sb: *Sandbox) u8 {
    var rewarded: u8 = @intFromBool(FoundryCase.awardSuitUpgrade(&sb.kits[0]));
    for (&sb.guests, 1..) |*guest, slot| if (guest.active) {
        rewarded += @intFromBool(FoundryCase.awardSuitUpgrade(&sb.kits[slot]));
    };
    return rewarded;
}

/// The dock group: the steward (a bulwark frame) and two guards, each with a shared flag set when
/// it goes down, so a load brings back only the ones still standing.
const dock_group = [_]struct { kind: Enemies.Kind, offset: V, down_flag: []const u8 }{
    .{ .kind = .bulwark, .offset = .{ 0, 0, -2 }, .down_flag = "foundry_steward_down" },
    .{ .kind = .trooper, .offset = .{ -3.4, 0, -2.6 }, .down_flag = "foundry_trooper_down" },
    .{ .kind = .skirmisher, .offset = .{ 3.4, 0, -2.6 }, .down_flag = "foundry_skirmisher_down" },
};

pub fn dockDownFlag(kind: Enemies.Kind) ?[]const u8 {
    for (dock_group) |member| if (member.kind == kind) return member.down_flag;
    return null;
}

pub fn dockEncounterActive(p: *const Progress) bool {
    return p.hasFlag(FoundryCase.confrontation_flag) and !p.hasFlag(FoundryCase.exposed_flag) and !CityContent.bossStarted(&CityContent.detroit, p);
}

fn ensureFoundryDockEncounter(sb: *Sandbox) void {
    if (!dockEncounterActive(&sb.progress)) return;
    const gate = FoundryCase.gatePosition(&sb.catalog.district) orelse return;
    sb.enemies.nests[Enemies.foundry_nest] = .{ .position = gate, .alive = false, .health = 0 };
    if (sb.enemies.unitCount(Enemies.foundry_nest) > 0) return;
    var standing: usize = 0;
    for (dock_group) |member| standing += @intFromBool(!sb.progress.hasFlag(member.down_flag));
    // Everyone was already down before a load: the fight is won.
    if (standing == 0) {
        if (FoundryCase.finishDockConfrontation(&sb.progress)) _ = awardFoundrySuitUpgrade(sb);
        return;
    }
    if (freeEnemySlots(&sb.enemies) < standing) return;
    // Stage them on the approach side so the gate panel cannot hide their legs or trap them.
    for (dock_group) |member| if (!sb.progress.hasFlag(member.down_flag)) {
        _ = sb.enemies.spawnAt(member.kind, Enemies.foundry_nest, R.add(gate, member.offset), 1);
    };
}

/// Where a city fight is going on (the dock ambush or the Titan), for civilians to keep away from.
pub fn cityDanger(sb: *const Sandbox) ?V {
    if (dockEncounterActive(&sb.progress)) return FoundryCase.gatePosition(&sb.catalog.district);
    const city = &CityContent.detroit;
    if (CityContent.bossStarted(city, &sb.progress) and !CityContent.bossDefeated(city, &sb.progress)) return WindsorCase.titanPosition(sb.seed);
    return null;
}

fn cityFrontierClear(sb: *const Sandbox) bool {
    return QuestLog.remainingNests(&sb.enemies) == 0 and QuestLog.remainingCarriers(&sb.skies) == 0;
}

fn freeEnemySlots(enemies: *const Enemies) usize {
    var count: usize = 0;
    for (enemies.units) |unit| count += @intFromBool(unit == null);
    return count;
}

/// The Titan wakes when the cleared campaign reaches the west Windsor bridge. Its saved
/// encounter flag survives; live enemies and phase are rebuilt after a load or a long retreat.
fn ensureCityTitanEncounter(sb: *Sandbox) void {
    const city = &CityContent.detroit;
    if (!CityContent.bossReady(city, &sb.progress) or !cityFrontierClear(sb) or CityContent.bossDefeated(city, &sb.progress)) return;
    const arena = WindsorCase.titanPosition(sb.seed);
    var nearby = false;
    for (0..Sandbox.max_players) |player| if (sb.present(player)) {
        nearby = nearby or R.length(R.sub(sb.feetOf(player), arena)) <= Enemies.wake_distance;
    };
    if (!nearby) return;
    if (!CityContent.bossStarted(city, &sb.progress)) {
        sb.progress.setFlag(city.boss.started_flag);
        sb.say("THE COLLABORATORS' TITAN: cross the bridge and engage the siege frame", .{});
        sb.cue(.hive_zap, arena);
    }
    sb.enemies.nests[Enemies.foundry_nest] = .{ .position = arena, .alive = false, .health = 0 };
    if (sb.enemies.unitCount(Enemies.foundry_nest) == 0) {
        if (!sb.enemies.spawnAt(.scalari_titan, Enemies.foundry_nest, arena, 2.5)) return;
        sb.city_titan_phase = 1;
        sb.say("PHASE 1: the Titan guards the crossing", .{});
        return;
    }

    var titan: ?*Enemies.Unit = null;
    for (&sb.enemies.units) |*slot| if (slot.*) |*unit| if (unit.nest == Enemies.foundry_nest and unit.kind == .scalari_titan) {
        titan = unit;
        break;
    };
    const boss = titan orelse return;
    if (sb.city_titan_phase < 2 and boss.health <= Enemies.stats(.scalari_titan).health * 2.5 * 0.66) {
        if (freeEnemySlots(&sb.enemies) < 3) return;
        sb.city_titan_phase = 2;
        _ = sb.enemies.spawnAt(.drone, Enemies.foundry_nest, R.add(arena, .{ -7, 0, -2 }), 1.4);
        _ = sb.enemies.spawnAt(.drone, Enemies.foundry_nest, R.add(arena, .{ 7, 0, 2 }), 1.4);
        _ = sb.enemies.spawnAt(.bulwark, Enemies.foundry_nest, R.add(arena, .{ 0, 0, 10 }), 1.15);
        sb.say("PHASE 2: Hive reinforcements hit the bridge", .{});
    } else if (sb.city_titan_phase < 3 and boss.health <= Enemies.stats(.scalari_titan).health * 2.5 * 0.34) {
        sb.city_titan_phase = 3;
        boss.stun = 2.8;
        boss.flash = 2.8;
        sb.say("PHASE 3: the three weakened modules fail; strike the exposed core", .{});
        sb.cue(.vault, boss.position);
    }
}

fn finishCityTitan(sb: *Sandbox) void {
    const city = &CityContent.detroit;
    if (CityContent.bossDefeated(city, &sb.progress)) return;
    sb.progress.setFlag(city.boss.defeated_flag);
    for (0..Sandbox.max_players) |player| if (sb.present(player)) {
        const kit = &sb.kits[player];
        const leveled = kit.awardCombatXP(1200);
        kit.wallet.scrap +|= 120;
        kit.wallet.parts +|= 18;
        kit.inventory[@intFromEnum(Collectibles.Kind.rotor_core)] +|= 2;
        sb.say("P{d}: Titan reward +1200 XP, +120 scrap, +18 parts, +2 rotor cores", .{player + 1});
        if (leveled) sb.say("P{d} combat level {d}! (+2 max health)", .{ player + 1, kit.combatLevel() });
    };
    sb.cue(.vault, WindsorCase.titanPosition(sb.seed));
    if (CityContent.updateLiberation(city, &sb.progress, cityFrontierClear(sb))) {
        sb.say("DETROIT IS FREE: the Hive's allies and bridge Titan have fallen", .{});
        sb.cue(.vault, sb.catalog.district.nodes[0].position);
    }
}

fn foundryCasePosition(sb: *const Sandbox, index: usize) V {
    var points: [FoundryCase.checkpoint_count]V = undefined;
    const count = FoundryCase.positions(&sb.catalog.district, &points);
    return if (index < count) points[index] else sb.player.feet;
}

/// Chest positions the Hive aims at: P1 (or P1's car) and active guests.
fn targets(sb: *const Sandbox, out: *[Sandbox.max_players]Enemies.Target) []const Enemies.Target {
    var p1: Enemies.Target = .{ .chest = R.add(sb.player.feet, .{ 0, 1.3, 0 }), .velocity = sb.player.velocity, .guard = sb.combat.arsenals[0].guard(), .facing = facingOf(sb.body_yaw) };
    if (sb.garage.piloting) |i| {
        const car = sb.garage.cars[i].?.flyer.body;
        p1 = .{ .chest = .{ car.pos.x, car.pos.y, car.pos.z }, .velocity = .{ car.vel.x, car.vel.y, car.vel.z } };
    }
    // A player under a vanish power is not seen.
    p1.alive = p1.alive and !sb.specials.hidden(0);
    out[0] = p1;
    var n: usize = 1;
    for (sb.guests) |g| {
        out[n] = .{ .chest = R.add(g.player.feet, .{ 0, 1.3, 0 }), .velocity = g.player.velocity, .alive = g.active and !sb.specials.hidden(n), .guard = sb.combat.arsenals[n].guard(), .facing = facingOf(g.body_yaw) };
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

fn caveSystemForNest(sb: *const Sandbox, nest_index: u8) ?u8 {
    if (nest_index >= sb.enemies.nest_count or !sb.enemies.nests[nest_index].cave) return null;
    var cave: u8 = 0;
    for (sb.enemies.nests[0..nest_index]) |nest| if (nest.cave) {
        cave += 1;
    };
    return if (cave < sb.caves.count) cave else null;
}

/// Hive outcomes: drops, flags, and hits on players.
fn hive(sb: *Sandbox, e: Enemies.Event, camera: *Camera) void {
    switch (e) {
        .shot => |at| sb.cue(.hive_zap, at),
        .grenade_thrown => |at| sb.cue(.hive_zap, at),
        .grenade_blast => |at| {
            burst(sb, at, 4.2, .{ 0.72, 0.22, 0.9 });
            sb.cue(.boom, at);
        },
        .player_hit => |hit| {
            var events: [4]Combat.Event = undefined;
            var n: usize = 0;
            sb.cue(.hurt, if (hit.player == 0) null else R.add(sb.guests[hit.player - 1].player.feet, .{ 0, 1, 0 }));
            if (sb.combat.hurt(hit.player, hit.damage, &events, &n)) down(sb, hit.player, camera);
            for (events[0..@min(n, events.len)]) |ev| if (ev == .parried) sb.say("parried!", .{});
        },
        .unit_down => |u| {
            const random = sb.enemies.rng.random();
            const scalari = Enemies.isScalari(u.kind);
            const city_titan = u.kind == .scalari_titan and u.nest == Enemies.foundry_nest and CityContent.bossStarted(&CityContent.detroit, &sb.progress);
            const k2_boss = blk: {
                if (u.kind != .scalari_titan) break :blk false;
                const cave = caveSystemForNest(sb, u.nest) orelse break :blk false;
                break :blk sb.caves.systems[cave].range == @import("../procedural/Mountains.zig").count;
            };
            const xp: u32 = if (k2_boss) 1200 else if (city_titan) 0 else switch (u.kind) {
                .scalari_scout => 30,
                .scalari_stinger => 55,
                .scalari_titan => 300,
                .scalari_miner => 20,
                .scalari_hybrid => 75,
                .drone, .skirmisher => 40,
                .trooper => 65,
                .sentinel, .bulwark => 100,
            };
            // What the unit drops comes from one table (`Loot.zig`); the Foundry titan's reward is its case's.
            const loot: Loot.Reward = if (city_titan) .{} else Loot.roll(u.kind, random);
            var winner: ?usize = null;
            var winner_distance = std.math.inf(f32);
            for (0..Sandbox.max_players) |p| if (sb.present(p)) {
                const delta = R.sub(sb.feetOf(p), u.position);
                const distance = delta[0] * delta[0] + delta[2] * delta[2];
                if (distance < winner_distance) {
                    winner = p;
                    winner_distance = distance;
                }
            };
            if (winner) |player_index| {
                if (!city_titan) {
                    const kit = &sb.kits[player_index];
                    const leveled = kit.awardCombatXP(xp);
                    kit.wallet.scrap +|= loot.scrap;
                    kit.wallet.parts +|= loot.parts;
                    kit.inventory[@intFromEnum(Collectibles.Kind.hive_alloy)] +|= loot.alloy;
                    kit.inventory[@intFromEnum(Collectibles.Kind.lumen_shard)] +|= loot.lumen;
                    if (scalari) {
                        sb.say("P{d}: +{d} combat XP, +{d} scrap, +{d} parts", .{ player_index + 1, xp, loot.scrap, loot.parts });
                    } else {
                        sb.say("P{d}: +{d} combat XP, +{d} scrap, +{d} parts, +{d} Hive alloy, +{d} lumen", .{ player_index + 1, xp, loot.scrap, loot.parts, loot.alloy, loot.lumen });
                    }
                    if (leveled) sb.say("P{d} combat level {d}! (+2 max health)", .{ player_index + 1, kit.combatLevel() });
                }
            } else if (!city_titan) {
                sb.collectibles.drop(.hive_alloy, u.position);
            }
            robotLearns(sb, u.position);
            sb.cue(.boom, u.position);
            if (k2_boss) {
                sb.progress.setFlag("k2_black_summit_down");
                sb.say("BLACK-SUMMIT TITAN disabled: K2 mechworks cleared", .{});
            }
            if (scalari) {
                sb.progress.setFlag("scalari_fought");
                if (city_titan) sb.say("the Titan core is down; clear the remaining Hive units", .{}) else sb.say("scalari {s} down: +{d} XP", .{ @tagName(u.kind), xp });
            } else {
                sb.progress.setFlag("hive_fought");
                sb.say("hive {s} down: +{d} XP", .{ @tagName(u.kind), xp });
            }
            petLearns(sb, u.position);
            if (u.nest == Enemies.foundry_nest and dockEncounterActive(&sb.progress)) if (dockDownFlag(u.kind)) |flag| sb.progress.setFlag(flag);
            if (u.nest == Enemies.foundry_nest and sb.enemies.unitCount(Enemies.foundry_nest) == 0) {
                if (CityContent.bossStarted(&CityContent.detroit, &sb.progress) and !CityContent.bossDefeated(&CityContent.detroit, &sb.progress)) {
                    finishCityTitan(sb);
                } else if (FoundryCase.finishDockConfrontation(&sb.progress)) {
                    const rewarded = awardFoundrySuitUpgrade(sb);
                    sb.say("steward defeated; foundry yard gate open; Sprint Servos for {d} active ranger(s)", .{rewarded});
                    sb.cue(.vault, FoundryCase.gatePosition(&sb.catalog.district));
                }
            }
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
            if (sb.enemies.nests[n.nest].cave) {
                // A cave's heart nest: the cave is cleared.
                var cave: usize = 0;
                for (sb.enemies.nests[0..n.nest]) |previous| cave += @intFromBool(previous.cave);
                var cleared: [20]u8 = undefined;
                sb.progress.setFlag(std.fmt.bufPrint(&cleared, "cave_{d}_cleared", .{cave}) catch unreachable);
                sb.progress.setFlag("cave_cleared");
                for (0..2) |k| sb.collectibles.drop(.hive_alloy, R.add(n.position, .{ @as(f32, @floatFromInt(k)) * 1.5 - 0.75, 1, 3 }));
                sb.collectibles.drop(.rotor_core, R.add(n.position, .{ 0, 1, -3 }));
                sb.say("{s} cleared: the hive heart is broken", .{Sandbox.Caves.systemName(&sb.caves, @intCast(cave))});
            } else {
                for (0..4) |k| sb.collectibles.drop(.hive_alloy, R.add(n.position, .{ @as(f32, @floatFromInt(k)) * 1.5 - 2, 1, 5 }));
                sb.collectibles.drop(.rotor_core, R.add(n.position, .{ 0, 1, 6.5 }));
                sb.say("hive nest destroyed", .{});
            }
            if (sb.progress.hasFlag("tavi_scouted") and !sb.enemies.nests[n.nest].cave and !sb.progress.hasFlag("nest_0_down") and !sb.progress.hasFlag("nest_1_down") and !sb.progress.hasFlag("nest_2_down")) {
                // A non-default seeded spire may be the first one the scout marked.
                sb.progress.setFlag("first_spire_broken");
            }
            checkCampaignComplete(sb);
        },
    }
}

fn checkCampaignComplete(sb: *Sandbox) void {
    if (sb.progress.hasFlag("campaign_complete")) return;
    for (sb.enemies.nests[0..sb.enemies.nest_count]) |nest| if (nest.alive) return;
    for (sb.skies.carriers) |carrier| if (carrier.alive) return;
    sb.progress.setFlag("campaign_complete");
    sb.say("frontier secure: every Hive nest and Brood carrier has fallen", .{});
    sb.cue(.vault, null);
}

fn down(sb: *Sandbox, player: u8, camera: *Camera) void {
    // Knocked out in the arena: back up at the centre of the bowl, healed.
    if (sb.arena.active) {
        const p = if (player == 0) &sb.player else &sb.guests[player - 1].player;
        if (sb.arena.inside(p.feet)) {
            p.feet = sb.arena.standing(player);
            p.velocity = @splat(0);
            sb.combat.vitals[player].health = sb.combat.vitals[player].max;
            if (player == 0) camera.position = sb.player.eye();
            sb.say("P{d} is back on their feet", .{player + 1});
            return;
        }
    }
    if (@import("Platformer.zig").recoverAtCheckpoint(sb, player, camera)) return;
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
pub fn step(sb: *Sandbox, camera: *Camera, input: Input, actions: Sandbox.Actions, frozen: bool, dt: f32, timing: ?Sandbox.BenchmarkTiming) void {
    var phase_timer = if (timing) |profile| mach.time.Timer.start(profile.io) else undefined;
    stepCaves(sb);
    stepArena(sb, camera, dt);
    // Hover cars: the piloted one takes P1's movement keys; parked ones idle.
    sb.garage.step(&sb.physics, if (frozen) .{} else Garage.controls(input), dt);

    // Pickups for every local player: whoever reaches one keeps it.
    var feet: [Sandbox.max_players]V = undefined;
    var slots: [Sandbox.max_players]usize = undefined;
    var fn_count: usize = 0;
    if (sb.garage.piloting == null and sb.seated == null) {
        feet[0] = sb.player.feet;
        slots[0] = 0;
        fn_count = 1;
    }
    for (sb.guests, 1..) |g, slot| if (g.active) {
        feet[fn_count] = g.player.feet;
        slots[fn_count] = slot;
        fn_count += 1;
    };
    var picked: [8]Collectibles.Event = undefined;
    const got = sb.collectibles.collect(&sb.progress.picked, feet[0..fn_count], dt, &picked);
    for (picked[0..@min(got, picked.len)]) |p| {
        const who = slots[p.player];
        const kit = &sb.kits[who];
        kit.inventory[@intFromEnum(p.kind)] += 1;
        sb.cue(.pickup, p.position);
        if (p.kind == .vital_cell) {
            sb.combat.setPlayerMax(who, kit.maxHealth() + Specials.loadout(sb.profileOf(who).*).health);
            sb.say("P{d} vital cell: max health {d:.0}", .{ who + 1, kit.maxHealth() });
        } else sb.say("P{d} +1 {s} ({d})", .{ who + 1, Collectibles.label(p.kind), kit.count(p.kind) });
        sb.progress.setFlag("collected");
    }
    if (timing) |profile| profile.metrics.record(.frontier_setup, phase_timer.lap() * 1000);

    // The Kestrel and the air war.
    if (timing != null) phase_timer.reset();
    sb.hangar.step(&sb.physics, if (sb.hangar.piloting and !frozen) Hangar.controls(input, camera.*) else .{}, dt);
    stepSkies(sb, camera, frozen, dt, timing);
    if (timing) |profile| profile.metrics.record(.air_war, phase_timer.lap() * 1000);

    // The Hive.
    if (timing != null) phase_timer.reset();
    ensureCityTitanEncounter(sb);
    ensureFoundryDockEncounter(sb);
    var who: [Sandbox.max_players]Enemies.Target = undefined;
    var events: [32]Enemies.Event = undefined;
    const count = sb.enemies.step(&sb.physics, targets(sb, &who), dt, &events);
    for (events[0..@min(count, events.len)]) |e| hive(sb, e, camera);
    if (timing) |profile| profile.metrics.record(.hive_ai, phase_timer.lap() * 1000);

    // Arsenals: P1 with the weapon tool on foot, guests with the right trigger.
    if (timing != null) phase_timer.reset();
    sb.combat.tick(dt);
    for (&sb.combat.arsenals, &sb.kits) |*arsenal, *kit| arsenal.weapon_upgrades = kit.weapon_upgrades;
    const armed = !frozen and sb.tools.tool == .weapon and sb.garage.piloting == null and sb.seated == null;
    const aim_camera = sb.aimCameraPublic(camera.*);
    const f = aim_camera.forward();
    var out: [32]Combat.Event = undefined;
    const fought = sb.combat.step(0, &sb.physics, &sb.enemies, sb.kits[0].weapons, .{
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
        .martial_fire = !armed and sb.tools.tool == .hands and sb.trigger.fire and sb.target == .none,
        .martial_guard = !armed and sb.tools.tool == .hands and (sb.trigger.alt or sb.trigger.saber),
        .energy_kick = sb.player.energy_kick_timer > 0,
        .saber_down = input.stomp or sb.player.motion == .stomp,
        .vertical_speed = sb.player.velocity[1],
        .throw_saber = input.dodge and sb.trigger.saber,
        .saber = armed and sb.trigger.saber,
        .weapon_accent = rgb3(Profile.accent_colors[sb.profile.accent]),
        .direct = sb.trigger.direct,
        .cycle = armed and actions.next_item,
    }, dt, &out);
    rangerAirShots(sb, .{ aim_camera.position.x(), aim_camera.position.y(), aim_camera.position.z() }, .{ f.x(), f.y(), f.z() }, out[0..@min(fought, out.len)]);
    arsenalEvents(sb, 0, out[0..@min(fought, out.len)], camera);
    for (&sb.guests, 1..) |*g, p| {
        defer g.next_weapon = false;
        if (!g.active) continue;
        const eye = g.player.eye();
        const gf = g.camera.forward();
        const n = sb.combat.step(@intCast(p), &sb.physics, &sb.enemies, sb.kits[p].weapons, .{
            .eye = .{ eye.x(), eye.y(), eye.z() },
            .forward = .{ gf.x(), gf.y(), gf.z() },
            .feet = g.player.feet,
            .yaw = g.body_yaw,
            .rig = rigFor(sb, p, g.profile),
            .armed = !frozen and g.trading == null,
            .dashing = g.player.motion == .dash or g.player.motion == .roll,
            .airborne = !g.player.grounded,
            .fire = !frozen and g.fire and g.trading == null,
            .saber = !frozen and g.alt and g.trading == null,
            .energy_kick = g.player.energy_kick_timer > 0,
            .saber_down = g.input.stomp or g.player.motion == .stomp,
            .vertical_speed = g.player.velocity[1],
            .throw_saber = g.input.dodge and g.alt,
            .weapon_accent = rgb3(Profile.accent_colors[g.profile.accent]),
            .direct = true,
            .cycle = !frozen and g.next_weapon and g.trading == null,
        }, dt, &out);
        rangerAirShots(sb, .{ eye.x(), eye.y(), eye.z() }, .{ gf.x(), gf.y(), gf.z() }, out[0..@min(n, out.len)]);
        arsenalEvents(sb, @intCast(p), out[0..@min(n, out.len)], camera);
    }
    stepSpecials(sb, camera, actions, frozen, dt);
    if (!frozen) stepPet(sb, camera, dt);
    if (!frozen) stepDroidCompanions(sb, camera, dt);
    if (!frozen) stepWildlife(sb, camera, dt);
    if (timing) |profile| profile.metrics.record(.arsenal, phase_timer.lap() * 1000);
}

fn stepDroidCompanions(sb: *Sandbox, camera: *Camera, dt: f32) void {
    for (0..Sandbox.max_players) |owner| {
        if (!sb.present(owner) or !sb.kits[owner].robot_built) {
            sb.droid_companions.out[owner] = null;
            continue;
        }
        const level = sb.kits[owner].robotLevel();
        if (sb.droid_companions.out[owner] == null) sb.droid_companions.summonFor(owner, sb.feetOf(owner), sb.yawOf(owner), level, sb.seed);
        var hive_events: [16]Enemies.Event = undefined;
        var hn: usize = 0;
        var events: [4]DroidCompanion.Event = undefined;
        const n = sb.droid_companions.step(owner, .{ .owner = sb.feetOf(owner), .owner_yaw = sb.yawOf(owner), .level = level, .seed = sb.seed, .physics = &sb.physics }, &sb.enemies, dt, &hive_events, &hn, &events);
        for (events[0..@min(n, events.len)]) |event| switch (event) {
            .attack => |at| sb.cuePitch(.zap, at, 0.72),
            .hurt => |at| sb.cuePitch(.impact, at, 0.8),
        };
        for (hive_events[0..@min(hn, hive_events.len)]) |event| hive(sb, event, camera);
    }
}

fn rangerAirShots(sb: *Sandbox, origin: V, direction: V, events: []const Combat.Event) void {
    for (events) |event| if (event == .fired) switch (event.fired) {
        .blaster => sb.skies.fireRanger(origin, direction, 22),
        .sniper_rifle => sb.skies.fireRanger(origin, direction, 95),
        .machine_gun => sb.skies.fireRanger(origin, direction, 9),
        .heavy_rifle => sb.skies.fireRanger(origin, direction, 55),
        .energy_bazooka => sb.skies.fireRanger(origin, direction, 90),
        .energy_net => {
            sb.skies.fireRangerNet(origin, direction, 38);
            if (netWildHit(sb, origin, direction)) |species| sb.say("Net hit {s}: {d}% vitality", .{ Pets.info(species).name, @as(u32, @intFromFloat(sb.pets.wild_health[@intFromEnum(species)])) });
        },
        else => {},
    };
}

fn netWildHit(sb: *Sandbox, origin: V, direction: V) ?Pets.Species {
    var best = std.math.inf(f32);
    var result: ?Pets.Species = null;
    for (sb.pets.spots, 0..) |spot, k| {
        const species: Pets.Species = @enumFromInt(k);
        if (!petWaiting(sb, species) or sb.pets.wild_health[k] <= 0) continue;
        const lift: f32 = if (Pets.info(species).flies) Pets.hover else 0.7;
        if (Enemies.segmentSphere(origin, direction, @min(best, 120), R.add(spot.position, .{ 0, lift, 0 }), 1.15)) |distance| {
            best = distance;
            result = species;
        }
    }
    if (result) |species| {
        if (sb.physics.castRay(origin, direction, best, .none)) |blocker| if (blocker.distance < best) return null;
        _ = sb.pets.netHitWild(species, 38);
        return species;
    }
    return null;
}

fn stepWildlife(sb: *Sandbox, camera: *Camera, dt: f32) void {
    var active: [Sandbox.max_players]bool = undefined;
    var owners: [Sandbox.max_players]V = undefined;
    for (0..Sandbox.max_players) |p| {
        active[p] = sb.present(p);
        owners[p] = sb.feetOf(p);
    }
    var events: [Pets.max_owners]Enemies.Event = undefined;
    const n = sb.pets.stepWild(dt, active, owners, &events);
    for (events[0..@min(n, events.len)]) |event| hive(sb, event, camera);
}

/// Class specials for every local player (P1 on foot, active guests), then grenades and
/// sentries. Class passives (health, saber weight) are applied here too.
fn stepSpecials(sb: *Sandbox, camera: *Camera, actions: Sandbox.Actions, frozen: bool, dt: f32) void {
    var events: [32]Specials.Event = undefined;
    const on_foot = !frozen and sb.garage.piloting == null and sb.seated == null and !sb.hangar.piloting;
    const f = sb.aimCameraPublic(camera.*).forward();
    const eye = sb.player.eye();
    const own = Specials.loadout(sb.profile);
    sb.combat.arsenals[0].melee_scale = own.melee;
    sb.combat.setPlayerMax(0, sb.kits[0].maxHealth() + own.health);
    const pressed: [3]bool = if (on_foot) .{ actions.special_1, actions.special_2, actions.special_3 } else @splat(false);
    var n = sb.specials.step(0, sb.profile, &sb.physics, &sb.enemies, &sb.combat, .{ .eye = .{ eye.x(), eye.y(), eye.z() }, .forward = .{ f.x(), f.y(), f.z() }, .feet = sb.player.feet, .pressed = pressed }, dt, &events);
    specialEvents(sb, events[0..@min(n, events.len)], camera);
    for (&sb.guests, 1..) |*g, p| {
        defer g.special = @splat(false);
        if (!g.active) continue;
        const theirs = Specials.loadout(g.profile);
        sb.combat.arsenals[p].melee_scale = theirs.melee;
        sb.combat.setPlayerMax(p, sb.kits[p].maxHealth() + theirs.health);
        const ge = g.player.eye();
        const gf = g.camera.forward();
        n = sb.specials.step(@intCast(p), g.profile, &sb.physics, &sb.enemies, &sb.combat, .{ .eye = .{ ge.x(), ge.y(), ge.z() }, .forward = .{ gf.x(), gf.y(), gf.z() }, .feet = g.player.feet, .pressed = if (frozen) @splat(false) else g.special }, dt, &events);
        specialEvents(sb, events[0..@min(n, events.len)], camera);
    }
    n = sb.specials.stepWorld(&sb.physics, &sb.enemies, &sb.combat, dt, &events);
    specialEvents(sb, events[0..@min(n, events.len)], camera);
}

fn specialEvents(sb: *Sandbox, events: []const Specials.Event, camera: *Camera) void {
    for (events) |e| switch (e) {
        .used => |u| {
            const at: ?V = if (u.player == 0) null else R.add(sb.guests[u.player - 1].player.feet, .{ 0, 1.2, 0 });
            switch (Specials.info(u.kind).mechanic) {
                .grenade, .sentry, .field => sb.cuePitch(.grapple, at, 1.3),
                .shield, .heal => sb.cuePitch(.restock, at, 1.2),
                .blink, .launch => sb.cuePitch(.dash, at, 1.5),
                .slam, .aura => sb.cuePitch(.boom, at, 0.7),
                .cone => sb.cuePitch(.slash, at, 0.8),
                .chain => sb.cuePitch(.zap, at, 1.4),
                .lance => sb.cuePitch(.zap, at, 0.45),
                .vanish => sb.cuePitch(.vault, at, 1.6),
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
        .launch => |l| {
            const player = if (l.player == 0) &sb.player else &sb.guests[l.player - 1].player;
            player.velocity = l.velocity;
            if (l.velocity[1] > 0) player.grounded = false;
        },
        .heal => |h| for (0..Sandbox.max_players) |p| {
            const feet = if (p == 0) sb.player.feet else if (sb.guests[p - 1].active) sb.guests[p - 1].player.feet else continue;
            const d = R.sub(feet, h.center);
            if (p != h.player and (h.radius == 0 or R.dot(d, d) > h.radius * h.radius)) continue;
            const v = &sb.combat.vitals[p];
            v.health = @min(v.max, v.health + h.amount);
        },
        .hive => |h| hive(sb, h, camera),
    };
}

fn stepSkies(sb: *Sandbox, camera: *Camera, frozen: bool, dt: f32, timing: ?Sandbox.BenchmarkTiming) void {
    var jet: ?Skies.Jet = null;
    if (sb.hangar.fighter) |f| if (sb.hangar.piloting) {
        jet = .{ .position = .{ f.body.pos.x, f.body.pos.y, f.body.pos.z }, .velocity = .{ f.body.vel.x, f.body.vel.y, f.body.vel.z }, .forward = .{ f.forward().x, f.forward().y, f.forward().z }, .airborne = !f.grounded, .evasive = f.barrel_roll_timer > 0 };
    };
    var on_foot: [Sandbox.max_players]Enemies.Target = undefined;
    on_foot[0] = .{ .chest = R.add(sb.player.feet, .{ 0, 1.3, 0 }), .velocity = sb.player.velocity, .alive = !sb.hangar.piloting and !sb.specials.hidden(0) };
    for (sb.guests, 1..) |g, i| on_foot[i] = .{ .chest = R.add(g.player.feet, .{ 0, 1.3, 0 }), .velocity = g.player.velocity, .alive = g.active and !sb.specials.hidden(i) };
    var events: [64]Skies.Event = undefined;
    var n: usize = 0;
    if (jet) |j| if (!frozen) sb.skies.fireJetUpgraded(&sb.enemies, j, sb.hangar.guns(), sb.trigger.fire, sb.trigger.alt, dt, sb.progress.kestrel_levels, &events, &n);
    const fired = @min(n, events.len);
    var count: usize = 0;
    if (timing) |profile| {
        const measured = sb.skies.stepProfiled(&sb.physics, &sb.enemies, jet, &on_foot, dt, events[fired..], profile.io);
        count = measured.events;
        profile.metrics.record(.carriers, measured.timing.carriers_ms);
        profile.metrics.record(.wasps, measured.timing.wasps_ms);
        profile.metrics.record(.air_projectiles, measured.timing.projectiles_ms);
    } else {
        count = sb.skies.step(&sb.physics, &sb.enemies, jet, &on_foot, dt, events[fired..]);
    }
    for (events[0..@min(fired + count, events.len)]) |e| switch (e) {
        .sound => |s| switch (s.kind) {
            .cannon => sb.cuePitch(.zap, null, 1.7),
            .missile => sb.cue(.dash, null),
            .flak => sb.cuePitch(.impact, s.position, 0.6),
            .sting => sb.cuePitch(.hive_zap, s.position, 1.4),
            .energy_net => sb.cuePitch(.impact, s.position, 1.4),
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
        .raid_started => |raid| {
            cityInvasion(sb, raid.position);
            sb.say("market plaza {d} under Hive air attack — Scalari siege frame detected", .{raid.plaza + 1});
        },
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
            checkCampaignComplete(sb);
        },
        .hive => |h| hive(sb, h, camera),
    };
    if (!frozen and !sb.progress.hasFlag("carrier_seen")) {
        const sight_range_sq: f32 = 1200 * 1200;
        var sighted = false;
        for (sb.skies.carriers) |carrier| {
            if (!carrier.alive) continue;
            const at = carrier.position();
            if (jet) |j| {
                const d = R.sub(j.position, at);
                if (R.dot(d, d) <= sight_range_sq) {
                    sighted = true;
                    break;
                }
            }
            for (on_foot) |player| if (player.alive) {
                const d = R.sub(player.chest, at);
                if (R.dot(d, d) <= sight_range_sq) {
                    sighted = true;
                    break;
                }
            };
            if (sighted) break;
        }
        if (sighted) {
            sb.progress.setFlag("carrier_seen");
            sb.say("Brood carrier sighted above the frontier", .{});
            sb.cue(.vault, null);
        }
    }
}

/// The bomber's insect escort signals a Scalari ground team to the same plaza. Reuse the private
/// renewable encounter anchor so the assault adds no new save IDs or persistent world sites.
fn cityInvasion(sb: *Sandbox, plaza: V) void {
    const anchor = Enemies.training_nest;
    for (&sb.enemies.units) |*slot| if (slot.*) |unit| {
        if (unit.nest == anchor) slot.* = null;
    };
    const ground = Terrain.surface(sb.seed, plaza[0], plaza[2]).height;
    const center: V = .{ plaza[0], ground, plaza[2] };
    sb.enemies.nests[anchor] = .{ .position = center, .alive = false, .health = 0 };
    _ = sb.enemies.spawnAt(.scalari_titan, anchor, R.add(center, .{ -12, 0, -10 }), 1);
    _ = sb.enemies.spawnAt(.scalari_stinger, anchor, R.add(center, .{ 11, 0, -7 }), 1);
    _ = sb.enemies.spawnAt(.scalari_hybrid, anchor, R.add(center, .{ 2, 0, 13 }), 1);
    _ = sb.enemies.spawnAt(.scalari_stinger, anchor, R.add(center, .{ -18, 0, 9 }), 1);
    _ = sb.enemies.spawnAt(.scalari_hybrid, anchor, R.add(center, .{ 17, 0, 12 }), 1);
    _ = sb.enemies.spawnAt(.scalari_miner, anchor, R.add(center, .{ 0, 0, -19 }), 1);
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
    sb.hangar.placeWithFrame(sb.seed, Sandbox.spawn, null, 0, sb.progress.kestrel_levels, sb.progress.space_frame);
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
            .energy_net => 1.25,
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
    sb.say("{s}: W/S drive, A/D steer, SPACE or E ascend, Q descend, SHIFT boost, click / controller interact to exit", .{Designs.name(@enumFromInt(car))});
}

pub fn boardJet(sb: *Sandbox, camera: *Camera) void {
    sb.release();
    sb.hangar.board(camera);
    sb.say("kestrel: mouse aim, W accelerate, S brake, A/D bank-steer, Q/E pitch, space lift, shift boost, CTRL barrel roll, click fire, RMB lock/release missile, F exit", .{});
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
    n = publishWildkin(sb, out, n, t);
    n = publishPets(sb, out, n, t);
    n = publishArena(sb, out, n, t);
    n = publishShrines(sb, out, n, t);
    n = publishObjectiveBeacon(sb, out, n, t);
    n = publishFoundryEvidence(sb, out, n, t);
    n = publishFoundryDock(sb, out, n, t);
    n = publishWindsorEvidence(sb, out, n, t);
    n = publishWindsorGates(sb, out, n, t);
    n = publishBileArchive(sb, out, n, t);
    n = publishCityDiscoveries(sb, out, n, t);
    n = publishCityTitanArena(sb, out, n, t);
    n = publishCityHiveBases(sb, out, n, t);
    n = publishCityGardenFoliage(sb, out, n);
    n = publishAntarcticPerimeter(sb, out, n, t);
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
    // The Hive stains the ground around every living surface nest. These low, terrain-following
    // tiles expand with market days and disappear from the source when its nest is destroyed.
    const stain_radius = Corruption.radius(sb.market.day);
    if (stain_radius > 0) for (sb.enemies.nests[0..sb.enemies.nest_count]) |nest| {
        if (!nest.alive or nest.cave) continue;
        var dz: f32 = -stain_radius;
        while (dz <= stain_radius) : (dz += Corruption.tuning.patch_spacing) {
            var dx: f32 = -stain_radius;
            while (dx <= stain_radius) : (dx += Corruption.tuning.patch_spacing) {
                if (!room(out, n, 1)) break;
                if (!Corruption.covers(sb.market.day, dx, dz)) continue;
                const x = nest.position[0] + dx;
                const z = nest.position[2] + dz;
                const surface = Terrain.surface(sb.seed, x, z);
                const fleck = @mod(@floor((x + z) * 0.07), 3);
                const tint: [4]f32 = if (fleck == 0) .{ 0.22, 0.09, 0.25, 1 } else if (fleck == 1) .{ 0.28, 0.10, 0.22, 1 } else .{ 0.19, 0.12, 0.29, 1 };
                out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ x, surface.height + Corruption.tuning.patch_depth, z } }, .tint = tint, .size = .{ Corruption.tuning.patch_spacing * 0.94, Corruption.tuning.patch_depth, Corruption.tuning.patch_spacing * 0.94 } };
                n += 1;
            }
        }
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
            const shell = if (nest.cave) c.spire else c.hive_base;
            const glow = if (nest.cave) c.spire_glow else c.hive_base_glow;
            const base_size: [3]f32 = if (nest.cave) size else @splat(0.78);
            out[n] = .{ .mesh = shell, .transform = .{ .position = nest.position }, .tint = .{ 1, 1, 1, 1 }, .size = base_size };
            out[n + 1] = .{ .mesh = glow, .transform = .{ .position = nest.position }, .tint = Material.emissive(.{ 1, 1, 1, 1 }, pulse), .size = base_size };
            n += 2;
        } else {
            // A broken stump.
            out[n] = .{ .mesh = c.spire, .transform = .{ .position = R.sub(nest.position, .{ 0, 1, 0 }) }, .tint = .{ 0.45, 0.4, 0.4, 1 }, .size = .{ size[0], 0.22 * size[1], size[2] } };
            n += 1;
        }
    }
    // Ground Hive units use ids 16–31, leaving the final eight slots for nearby Wildkin.
    var trooper_id: u8 = 16;
    for (sb.enemies.units) |slot| if (slot) |u| if (Enemies.isGround(u.kind)) {
        if (u.kind == .scalari_scout or u.kind == .scalari_miner) continue;
        if (u.kind == .scalari_titan) {
            if (!room(out, n, 40)) break;
            n += scalariTitan(out[n..], c.block, c.orb, c.spike, c.gem, u.position, u.yaw, t, u.flash, sb.creator.enemy_design);
            continue;
        }
        const d = R.sub(u.position, sb.player.feet);
        if (d[0] * d[0] + d[2] * d[2] > 120 * 120) continue;
        if (trooper_id >= hero_first_id or !room(out, n, 1)) break;
        const Ranger = @import("../character/Ranger.zig");
        const action: Ranger.Action = if (u.throw_anim > 0) .throw else if (u.melee_anim > 0) .strike else if (u.tactic == .cover) .cover else .none;
        const action_t: f32 = switch (action) {
            .throw => 1 - u.throw_anim / 0.72,
            .strike => 1 - u.melee_anim / 0.62,
            else => 0,
        };
        const profile: Profile = if (u.nest == Enemies.foundry_nest and u.kind == .bulwark)
            foundry_steward_profile
        else switch (u.kind) {
            .trooper => trooper_profile,
            .skirmisher => skirmisher_profile,
            .bulwark => bulwark_profile,
            .scalari_scout => scalari_scout_profile,
            .scalari_stinger => scalari_stinger_profile,
            .scalari_titan => scalari_titan_profile,
            .scalari_hybrid => scalari_hybrid_profile,
            else => trooper_profile,
        };
        const role_design = EnemyDesign.encounter(sb.seed, u.generation, null);
        const tint: [4]f32 = if (u.flash > 0) .{ 1.6, 1.2, 1.2, 1 } else if (Enemies.isScalari(u.kind)) EnemyDesign.colors[@intFromEnum(role_design.palette)].accent else .{ 1, 1, 1, 1 };
        out[n] = .{ .mesh = .none, .transform = .{ .position = u.position }, .tint = tint, .character = .{
            .profile = profile,
            .pose = .{ .feet = u.position, .yaw = u.yaw, .walk_phase = u.walk_phase, .walk_amount = u.walk_amount, .motion = if (u.walk_amount > 0.2) .run else .idle, .time = t, .action = action, .action_t = action_t },
            .id = trooper_id,
        } };
        trooper_id += 1;
        n += 1;
    };
    // Prospector droids use a compact, readable drill silhouette rather than the ranger rig.
    for (sb.enemies.units) |slot| if (slot) |u| if (u.kind == .scalari_miner and room(out, n, 6)) {
        const at = u.position;
        const heading = yawQuat(u.yaw);
        const pulse = 0.7 + 0.3 * @sin(t * 8 + u.orbit);
        out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, 0.62, 0 }) }, .tint = .{ 0.22, 0.24, 0.28, 1 }, .size = .{ 0.9, 0.72, 0.72 }, .rotation = heading };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, 1.16, 0.08 }) }, .tint = .{ 0.48, 0.38, 0.22, 1 }, .size = .{ 0.57, 0.34, 0.46 }, .rotation = heading };
        out[n + 2] = .{ .mesh = c.gem, .transform = .{ .position = R.add(at, .{ 0, 1.48, 0.12 }) }, .tint = Material.emissive(.{ 0.95, 0.62, 0.16, 1 }, pulse), .size = @splat(0.22), .rotation = yawQuat(t * 0.8) };
        out[n + 3] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ -0.62, 0.62, 0.18 }) }, .tint = .{ 0.35, 0.3, 0.24, 1 }, .size = .{ 0.62, 0.18, 0.22 }, .rotation = heading };
        out[n + 4] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0.62, 0.62, 0.18 }) }, .tint = .{ 0.35, 0.3, 0.24, 1 }, .size = .{ 0.62, 0.18, 0.22 }, .rotation = heading };
        out[n + 5] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, 0.37, 0.42 }) }, .tint = Material.emissive(.{ 1, 0.47, 0.08, 1 }, pulse * 1.2), .size = .{ 0.5, 0.09, 0.14 }, .rotation = yawQuat(t * 3 + u.orbit) };
        n += 6;
    };
    // Scalari scout drones are low, four-footed machines rather than scaled-down Hive people.
    for (sb.enemies.units) |slot| if (slot) |u| if (u.kind == .scalari_scout and room(out, n, 2)) {
        const p = R.add(u.position, .{ 0, 0.48, 0 });
        const body_tint: [4]f32 = if (u.flash > 0) .{ 1.6, 1.2, 1.2, 1 } else .{ 0.26, 0.92, 1.18, 1 };
        const orientation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, u.yaw));
        out[n] = .{ .mesh = c.drone, .transform = .{ .position = p }, .tint = body_tint, .size = .{ 0.82, 0.48, 1.08 }, .rotation = orientation };
        out[n + 1] = .{ .mesh = c.drone_glow, .transform = .{ .position = p }, .tint = Material.emissive(.{ 0.12, 0.95, 1, 1 }, if (u.state == .hunt) @as(f32, 0.95) else 0.3), .size = .{ 0.82, 0.48, 1.08 }, .rotation = orientation };
        n += 2;
    };
    for (sb.enemies.units) |slot| if (slot) |u| {
        if (Enemies.isGround(u.kind)) continue;
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
    for (sb.enemies.grenades) |slot| if (slot) |g| if (room(out, n, 1)) {
        out[n] = .{ .mesh = c.gem, .transform = .{ .position = g.position }, .tint = Material.emissive(.{ 0.75, 0.2, 0.95, 1 }, 0.7 + 0.3 * @abs(@sin(g.fuse * 16))), .size = @splat(0.28) };
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
        const frame_mesh, const frame_glow = switch (sb.hangar.frame) {
            .kestrel => .{ c.kestrel, c.kestrel_glow },
            .ember_wyrm => .{ c.scalari_ember_wyrm, c.scalari_ember_wyrm_glow },
            .void_lance => .{ c.scalari_void_lance, c.scalari_void_lance_glow },
            .dreadclaw => .{ c.scalari_dreadclaw, c.scalari_dreadclaw_glow },
            .starwing => .{ c.player_starwing, c.player_starwing_glow },
            .bulwark => .{ c.player_bulwark, c.player_bulwark_glow },
        };
        out[n] = .{ .mesh = frame_mesh, .transform = .{ .position = at }, .tint = paint, .rotation = rot };
        out[n + 1] = .{ .mesh = frame_glow, .transform = .{ .position = at }, .tint = Material.emissive(paint, 0.25 + 0.75 * f.burn), .rotation = rot };
        n += 2;
    };
    for (sb.skies.wasps) |slot| if (slot) |w| {
        if (!room(out, n, 6)) break;
        const q = m.Quat.fromTo(m.Vec3.unit_z, m.Vec3.init(w.forward[0], w.forward[1], w.forward[2]).normalizeOr(m.Vec3.unit_z));
        const wing_tint: [4]f32 = if (w.flash > 0) .{ 1.6, 1.4, 1.4, 1 } else switch (w.kind) {
            .wasp => .{ 1, 1, 1, 1 },
            .dragonfly => .{ 0.45, 1.1, 1.5, 1 },
            .beetle_bomber => .{ 1.45, 0.78, 0.35, 1 },
            .robot_fighter => .{ 0.48, 0.63, 0.78, 1 },
            .robot_lancer => .{ 0.7, 0.84, 1.0, 1 },
        };
        const tint = wing_tint;
        const hull = switch (w.kind) {
            .wasp => c.wasp,
            .dragonfly => c.dragonfly,
            .beetle_bomber => c.beetle_bomber,
            .robot_fighter => c.robot_fighter,
            .robot_lancer => c.robot_lancer,
        };
        const lights = switch (w.kind) {
            .wasp => c.wasp_glow,
            .dragonfly => c.dragonfly_glow,
            .beetle_bomber => c.beetle_bomber_glow,
            .robot_fighter => c.robot_fighter_glow,
            .robot_lancer => c.robot_lancer_glow,
        };
        out[n] = .{ .mesh = hull, .transform = .{ .position = w.position }, .tint = tint, .rotation = quat(q) };
        out[n + 1] = .{ .mesh = lights, .transform = .{ .position = w.position }, .tint = Material.emissive(if (w.kind == .dragonfly) .{ 0.2, 0.75, 1, 1 } else if (w.kind == .beetle_bomber) .{ 1, 0.32, 0.08, 1 } else if (w.kind == .robot_fighter or w.kind == .robot_lancer) .{ 0.18, 0.62, 1, 1 } else .{ 1, 1, 1, 1 }, if (w.state == .attack) 1 else 0.6), .rotation = quat(q) };
        n += 2;
        if (w.kind != .robot_fighter and w.kind != .robot_lancer) for (ShipMeshes.wasp_wings, 0..) |root, k| {
            const side: f32 = if (root.x > 0) 1 else -1;
            // Fore and hind pairs beat out of phase; a mirrored wing points along -X.
            const beat = @sin(w.flap + @as(f32, @floatFromInt(k / 2)) * 1.4) * 0.7;
            const local = m.Quat.fromAxisAngle(m.Vec3.unit_y, if (side > 0) 0 else std.math.pi).mul(m.Quat.fromAxisAngle(m.Vec3.unit_z, beat * side * side));
            const p = q.rotate(root);
            out[n] = .{ .mesh = c.wasp_wing, .transform = .{ .position = R.add(w.position, .{ p.x, p.y, p.z }) }, .tint = .{ 1, 1, 1, 1 }, .rotation = quat(q.mul(local)) };
            n += 1;
        };
    };
    for (sb.skies.carriers) |carrier| if (carrier.alive and room(out, n, 6)) {
        const q = quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, carrier.yaw()));
        const at = carrier.position();
        const deck = carrier.point(m.Vec3.init(0, 12.75, -5));
        const left = carrier.point(m.Vec3.init(-5.2, 12.84, -5));
        const right = carrier.point(m.Vec3.init(5.2, 12.84, -5));
        const cross = carrier.point(m.Vec3.init(0, 12.84, -5));
        out[n] = .{ .mesh = c.block, .transform = .{ .position = deck }, .tint = .{ 0.08, 0.16, 0.2, 1 }, .size = .{ 17, 0.12, 20 }, .rotation = q };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = left }, .tint = Material.emissive(.{ 0.2, 0.9, 0.85, 1 }, 0.7), .size = .{ 0.45, 0.05, 15 }, .rotation = q };
        out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = right }, .tint = Material.emissive(.{ 0.2, 0.9, 0.85, 1 }, 0.7), .size = .{ 0.45, 0.05, 15 }, .rotation = q };
        out[n + 3] = .{ .mesh = c.block, .transform = .{ .position = cross }, .tint = Material.emissive(.{ 0.2, 0.9, 0.85, 1 }, 0.7), .size = .{ 10.5, 0.05, 0.45 }, .rotation = q };
        n += 4;
        out[n] = .{ .mesh = c.carrier, .transform = .{ .position = at }, .tint = if (carrier.flash > 0) .{ 1.4, 1.2, 1.2, 1 } else if (carrier.robotic) .{ 0.42, 0.55, 0.72, 1 } else .{ 1, 1, 1, 1 }, .rotation = q };
        const glow = if (carrier.crashing) 1.2 else switch (carrier.stage()) {
            .turrets => @as(f32, 0.35),
            .bays => 0.65,
            .core => 0.95,
            .crashing => 1.2,
        };
        out[n + 1] = .{ .mesh = c.carrier_glow, .transform = .{ .position = at }, .tint = Material.emissive(if (carrier.robotic) .{ 0.12, 0.52, 1, 1 } else .{ 1, 1, 1, 1 }, glow + 0.2 * @sin(t * 1.3)), .rotation = q };
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
    for (sb.skies.shots) |slot| if (slot) |s| {
        if (s.kind == .energy_net) {
            if (room(out, n, 14)) n += energyNet(out[n..], c.block, s.position, s.velocity);
            continue;
        }
        if (!room(out, n, 1)) continue;
        out[n] = switch (s.kind) {
            .cannon => .{ .mesh = c.block, .transform = .{ .position = s.position }, .tint = Material.emissive(.{ 0.4, 0.95, 1, 1 }, 1), .size = .{ 0.12, 0.12, 2.2 }, .rotation = facing(s.velocity) },
            .sting => .{ .mesh = c.block, .transform = .{ .position = s.position }, .tint = Material.emissive(.{ 1, 0.2, 0.1, 1 }, 1), .size = .{ 0.14, 0.14, 1.6 }, .rotation = facing(s.velocity) },
            .missile => .{ .mesh = c.block, .transform = .{ .position = s.position }, .tint = Material.emissive(.{ 1, 0.95, 0.85, 1 }, 1), .size = .{ 0.3, 0.3, 1.8 }, .rotation = facing(s.velocity) },
            .flak => .{ .mesh = c.gem, .transform = .{ .position = s.position }, .tint = Material.emissive(.{ 1, 0.6, 0.2, 1 }, 1), .size = @splat(0.8) },
            .energy_net => unreachable,
        };
        n += 1;
    };
    // Held weapons, at each armed player's right hand.
    for (&sb.combat.arsenals, 0..) |*arsenal, player| if (arsenal.grip) |g| if (arsenal.active) |kind| if (room(out, n, max_weapon_parts)) {
        n += heldWeapon(out[n..], c.block, c.gem, c.spike, c.saber_blade, c.saber_core, kind, g, arsenal, t, rgb3(Profile.accent_colors[sb.profileOf(player).accent]));
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
    for (sb.combat.arsenals) |arsenal| for (arsenal.system.projectiles.items) |p| if (p.active) {
        if (p.kind == .saber_wave or p.kind == .saber_boomerang) {
            if (p.kind == .saber_wave and room(out, n, 2)) n += saberWave(out[n..], c.saber_wave, c.saber_wave_core, p.position, p.velocity, p.visual_tint orelse .{ 0.3, 0.95, 1 }, p.radius, t);
            if (p.kind == .saber_boomerang and room(out, n, 2)) {
                const tint: [3]f32 = p.visual_tint orelse .{ 0.3, 0.95, 1 };
                const rotation = facing(p.velocity);
                out[n] = .{ .mesh = c.saber_blade, .transform = .{ .position = p.position }, .tint = Material.emissive(.{ tint[0], tint[1], tint[2], 1 }, 1.4), .size = .{ 0.9, 0.9, 0.9 }, .rotation = rotation };
                out[n + 1] = .{ .mesh = c.saber_core, .transform = .{ .position = p.position }, .tint = Material.emissive(.{ 0.95, 0.99, 1, 1 }, 1.8), .size = .{ 0.9, 0.9, 0.9 }, .rotation = rotation };
                n += 2;
            }
            continue;
        }
        if (p.kind == .homing_energy_blast) {
            if (!room(out, n, 3)) continue;
            const tint = p.visual_tint orelse .{ 0.16, 0.64, 1.0 };
            const age = p.max_lifetime - p.lifetime;
            const pulse = 0.88 + 0.12 * @sin(t * 20 + age * 11);
            const charged = @as(f32, @floatFromInt(p.charge_level));
            const diameter = (1.2 + 0.42 * charged + p.radius * 0.5) * pulse;
            const direction = facing(p.velocity);
            const shell = Material.emissive(.{ tint[0] * 0.52, tint[1] * 0.76, tint[2], 1 }, 0.72);
            const core = Material.emissive(.{ 0.88, 0.97, 1, 1 }, 1.8 + charged * 0.3);
            out[n] = .{ .mesh = c.orb, .transform = .{ .position = p.position }, .tint = shell, .size = @splat(diameter) };
            out[n + 1] = .{ .mesh = c.orb, .transform = .{ .position = p.position }, .tint = core, .size = @splat(diameter * 0.46), .rotation = yawQuat(age * 7) };
            out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = R.add(p.position, R.scale(R.normalize(p.velocity), -diameter * 0.72)) }, .tint = Material.emissive(.{ tint[0] * 0.68, tint[1] * 0.9, tint[2], 1 }, 0.85), .size = .{ diameter * 0.32, diameter * 0.32, diameter * (1.4 + charged * 0.35) }, .rotation = direction };
            n += 3;
            continue;
        }
        if (!room(out, n, 1)) continue;
        const color = @import("../combat/Weapon.zig").Element.color(p.element);
        const s = p.radius * 0.8;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = p.position }, .tint = Material.emissive(.{ color[0], color[1], color[2], 1 }, 1), .size = .{ s, s, @max(0.6, s * 3) }, .rotation = facing(p.velocity) };
        n += 1;
    };
    for (sb.combat.effects) |slot| if (slot) |e| {
        const k = 1 - e.age / e.life;
        const tint = Material.emissive(.{ e.color[0], e.color[1], e.color[2], 1 }, k);
        if ((e.kind == .slash or e.kind == .trail) and room(out, n, 2)) {
            const scale = @max(0.2, e.size * (1.4 + k));
            const rotation = facing(e.dir);
            out[n] = .{ .mesh = c.saber_wave, .transform = .{ .position = e.position }, .tint = Material.emissive(.{ e.color[0], e.color[1], e.color[2], 1 }, 1.2 * k), .size = .{ scale, scale, scale }, .rotation = rotation };
            out[n + 1] = .{ .mesh = c.saber_wave_core, .transform = .{ .position = e.position }, .tint = Material.emissive(.{ 0.94, 0.98, 1, 1 }, 1.45 * k), .size = .{ scale, scale, scale }, .rotation = rotation };
            n += 2;
            continue;
        }
        if (!room(out, n, 1)) continue;
        out[n] = switch (e.kind) {
            .slash => unreachable,
            .beam => blk: {
                const length = if (e.length > 0) e.length else 80;
                break :blk .{ .mesh = c.block, .transform = .{ .position = R.add(e.position, R.scale(e.dir, length / 2)) }, .tint = tint, .size = .{ e.size * 0.4 * k, e.size * 0.4 * k, length }, .rotation = facing(e.dir) };
            },
            .trail => unreachable,
            .burst, .spark, .muzzle => .{ .mesh = c.gem, .transform = .{ .position = e.position }, .tint = tint, .size = @splat(e.size * (1.5 - k * 0.5)) },
        };
        n += 1;
    };
    return n;
}

/// The Subglacial Hive's first surface approach is ringed by high ice ramparts and
/// autonomous Scalari scorpion sentries. Their orbital patrol stays legible on arrival.
fn publishAntarcticPerimeter(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const center = Region.antarctica.arrival;
    const dx = sb.player.feet[0] - center[0];
    const dz = sb.player.feet[2] - center[1];
    if (dx * dx + dz * dz > 900 * 900) return start;

    const c = &sb.catalog.content;
    var n = start;
    const wall_tint = Material.ice(.{ 0.60, 0.80, 0.97, 1 });
    const wall_top = Material.ice(.{ 0.82, 0.91, 1.0, 1 });
    for (0..4) |face| {
        for (0..8) |segment| {
            // Leave a 153 m north gate through the visual-only landing ramparts.
            if (face == 0 and segment >= 2 and segment <= 5) continue;
            if (n + 4 > out.len) return n;
            const along = (@as(f32, @floatFromInt(segment)) - 3.5) * 38;
            const along_axis: V = if (face < 2) .{ along, 0, 0 } else .{ 0, 0, along };
            const side_offset: V = switch (face) {
                0 => .{ 0, 0, -152 },
                1 => .{ 0, 0, 152 },
                2 => .{ -152, 0, 0 },
                else => .{ 152, 0, 0 },
            };
            const x = center[0] + along_axis[0] + side_offset[0];
            const z = center[1] + along_axis[2] + side_offset[2];
            const ground = Terrain.surface(sb.seed, x, z).height;
            const wall_yaw = yawQuat(if (face >= 2) std.math.pi * 0.5 else 0);
            out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ x, ground + 23, z } }, .tint = wall_tint, .size = .{ 37, 46, 11 }, .rotation = wall_yaw };
            out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ x, ground + 44, z } }, .tint = wall_top, .size = .{ 37, 2.2, 11.5 }, .rotation = wall_yaw };
            out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = .{ x, ground + 13, z } }, .tint = Material.emissive(.{ 0.15, 0.70, 1.0, 1 }, 0.3 + 0.18 * @sin(t * 1.2 + @as(f32, @floatFromInt(segment)))), .size = .{ 35, 0.32, 11.7 }, .rotation = wall_yaw };
            n += 3;
            if (segment % 2 == 0) {
                out[n] = .{ .mesh = c.spike, .transform = .{ .position = .{ x, ground + 49, z } }, .tint = wall_top, .size = .{ 7, 13, 7 }, .rotation = wall_yaw };
                n += 1;
            }
        }
    }

    // Lit ice markers guide the player from the landing pad through the gate and out onto the
    // open glacier instead of making the square look like a sealed spawn pen.
    for (0..10) |tile| {
        if (n == out.len) return n;
        const distance = 20 + @as(f32, @floatFromInt(tile)) * 13;
        const z = center[1] - distance;
        const ground = Terrain.surface(sb.seed, center[0], z).height;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ center[0], ground + 0.18, z } }, .tint = Material.emissive(.{ 0.16, 0.76, 1.0, 1 }, 0.42), .size = .{ 9, 0.18, 7 } };
        n += 1;
    }
    for (0..2) |side| {
        if (n + 2 > out.len) return n;
        const x = center[0] + (if (side == 0) @as(f32, -80) else 80);
        const z = center[1] - 152;
        const ground = Terrain.surface(sb.seed, x, z).height;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ x, ground + 8, z } }, .tint = wall_tint, .size = .{ 4, 16, 4 } };
        out[n + 1] = .{ .mesh = c.spike, .transform = .{ .position = .{ x, ground + 18, z } }, .tint = wall_top, .size = .{ 5, 6, 5 } };
        n += 2;
    }

    const local = struct {
        fn at(origin: V, q: [4]f32, p: V) V {
            return R.add(origin, R.rotate(q, p));
        }
    }.at;
    for (0..2) |patrol| {
        if (n + 24 > out.len) return n;
        const phase = t * 0.13 + @as(f32, @floatFromInt(patrol)) * std.math.pi;
        const px = center[0] + @cos(phase) * 116;
        const pz = center[1] + @sin(phase) * 116;
        const ground = Terrain.surface(sb.seed, px, pz).height;
        const yaw = phase + std.math.pi * 0.5;
        const orientation = yawQuat(yaw);
        const base: V = .{ px, ground, pz };
        const dark: [4]f32 = if (patrol == 0) .{ 0.12, 0.16, 0.23, 1 } else .{ 0.18, 0.22, 0.28, 1 };
        out[n] = .{ .mesh = c.orb, .transform = .{ .position = local(base, orientation, .{ 0, 2.0, 0 }) }, .tint = dark, .size = .{ 7.4, 2.7, 10.5 }, .rotation = orientation };
        out[n + 1] = .{ .mesh = c.orb, .transform = .{ .position = local(base, orientation, .{ 0, 2.4, 4.8 }) }, .tint = Material.ice(.{ 0.42, 0.64, 0.82, 1 }), .size = .{ 4.4, 2.2, 4.6 }, .rotation = orientation };
        out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = local(base, orientation, .{ 0, 3.05, 0.2 }) }, .tint = Material.emissive(.{ 0.92, 0.13, 0.08, 1 }, 0.8 + 0.16 * @sin(t * 3 + @as(f32, @floatFromInt(patrol)))), .size = .{ 2.8, 0.22, 6.8 }, .rotation = orientation };
        n += 3;
        for (0..6) |leg| {
            const side: f32 = if (leg % 2 == 0) -1 else 1;
            const pair: f32 = @floatFromInt(leg / 2);
            const gait = @sin(t * 6 + pair * std.math.pi + side * std.math.pi) * 0.34;
            const anchor: V = .{ side * 3.0, 1.35 + gait, 2.3 - pair * 2.6 };
            const splay = yaw + side * (0.76 + pair * 0.10);
            out[n] = .{ .mesh = c.block, .transform = .{ .position = local(base, orientation, anchor) }, .tint = dark, .size = .{ 1.0, 1.35, 5.2 }, .rotation = yawQuat(splay) };
            out[n + 1] = .{ .mesh = c.spike, .transform = .{ .position = local(base, orientation, .{ side * 5.0, 0.45 + gait, 2.1 - pair * 2.6 }) }, .tint = dark, .size = .{ 0.9, 1.4, 1.1 }, .rotation = yawQuat(splay) };
            n += 2;
        }
        for (0..3) |joint| {
            const j: f32 = @floatFromInt(joint);
            out[n] = .{ .mesh = c.orb, .transform = .{ .position = local(base, orientation, .{ 0, 3.1 + j * 1.0, -4.0 - j * 1.35 }) }, .tint = if (joint == 2) dark else Material.ice(.{ 0.34, 0.58, 0.78, 1 }), .size = .{ 2.4 - j * 0.38, 1.75, 2.7 - j * 0.35 }, .rotation = orientation };
            n += 1;
        }
        out[n] = .{ .mesh = c.spike, .transform = .{ .position = local(base, orientation, .{ 0, 6.2, -8.0 }) }, .tint = Material.emissive(.{ 1, 0.16, 0.04, 1 }, 0.95 + 0.05 * @sin(t * 4)), .size = .{ 1.15, 3.6, 1.15 }, .rotation = orientation };
        out[n + 1] = .{ .mesh = c.orb, .transform = .{ .position = local(base, orientation, .{ -0.78, 2.55, 6.65 }) }, .tint = Material.emissive(.{ 1, 0.1, 0.06, 1 }, 0.9), .size = .{ 0.65, 0.48, 0.36 }, .rotation = orientation };
        out[n + 2] = .{ .mesh = c.orb, .transform = .{ .position = local(base, orientation, .{ 0.78, 2.55, 6.65 }) }, .tint = Material.emissive(.{ 1, 0.1, 0.06, 1 }, 0.9), .size = .{ 0.65, 0.48, 0.36 }, .rotation = orientation };
        n += 3;
    }
    return n;
}

/// The two occupied cities have Hive strongholds around their outer approaches. These
/// installations are environmental siege landmarks; surface nests remain the combat objectives.
fn publishCityHiveBases(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const c = &sb.catalog.content;
    const room = struct {
        fn ok(o: []World.Prop, k: usize, need: usize) bool {
            return k + need <= o.len;
        }
    }.ok;
    var n = start;
    const pulse = 0.62 + 0.3 * @sin(t * 1.45);
    const detroit_sites = [_][2]f32{ .{ 350, 95 }, .{ -350, 185 }, .{ 0, 445 } };
    const detroit_liberated = CityContent.liberated(&CityContent.detroit, &sb.progress);
    for (detroit_sites) |site| {
        const need: usize = if (detroit_liberated) 4 else 2;
        if (!room(out, n, need)) return n;
        const ground = Terrain.surface(sb.seed, site[0], site[1]).height;
        const at: V = .{ site[0], ground, site[1] };
        if (detroit_liberated) {
            const light = Material.emissive(.{ 0.24, 0.94, 0.72, 1 }, pulse);
            out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ site[0], ground + 1.6, site[1] } }, .tint = .{ 0.64, 0.73, 0.69, 1 }, .size = .{ 1.2, 3.2, 1.2 } };
            out[n + 1] = .{ .mesh = c.gem, .transform = .{ .position = .{ site[0], ground + 3.55, site[1] } }, .tint = light, .size = @splat(1.05) };
            out[n + 2] = .{ .mesh = c.flora[7], .transform = .{ .position = .{ site[0] - 3.1, ground + 0.2, site[1] }, .scale = 2.4 }, .tint = .{ 1, 1, 1, 1 } };
            out[n + 3] = .{ .mesh = c.flora[9], .transform = .{ .position = .{ site[0] + 3.1, ground + 0.2, site[1] + 0.6 }, .scale = 1.55 }, .tint = .{ 1, 1, 1, 1 } };
            n += 4;
        } else {
            out[n] = .{ .mesh = c.hive_base, .transform = .{ .position = at }, .tint = .{ 1, 1, 1, 1 }, .size = @splat(0.78) };
            out[n + 1] = .{ .mesh = c.hive_base_glow, .transform = .{ .position = at }, .tint = Material.emissive(.{ 1, 1, 1, 1 }, pulse), .size = @splat(0.78) };
            n += 2;
        }
    }
    const ny_seed = Region.new_york.seed(sb.seed);
    const ny_sites = [_][2]f32{ .{ 249845, 0 }, .{ 250170, 0 }, .{ 250000, 160 }, .{ 250000, -170 } };
    for (ny_sites) |site| {
        if (!room(out, n, 2)) return n;
        const ground = Terrain.surface(ny_seed, site[0], site[1]).height;
        const at: V = .{ site[0], ground, site[1] };
        out[n] = .{ .mesh = c.hive_base, .transform = .{ .position = at }, .tint = .{ 1, 1, 1, 1 }, .size = @splat(0.78) };
        out[n + 1] = .{ .mesh = c.hive_base_glow, .transform = .{ .position = at }, .tint = Material.emissive(.{ 1, 1, 1, 1 }, pulse), .size = @splat(0.78) };
        n += 2;
    }
    return n;
}

/// Three lit bridge pylons mark the exposed ally modules and frame the open-sky boss stage.
fn publishCityTitanArena(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const city = &CityContent.detroit;
    if (!CityContent.bossStarted(city, &sb.progress) or CityContent.bossDefeated(city, &sb.progress)) return start;
    const center = WindsorCase.titanPosition(sb.seed);
    if (R.length(R.sub(center, sb.player.feet)) > 540 or start + CityContent.mission_count * 2 > out.len) return start;
    const c = &sb.catalog.content;
    const colors = [_][4]f32{ .{ 0.3, 0.82, 0.72, 1 }, .{ 0.95, 0.7, 0.28, 1 }, .{ 0.68, 0.47, 0.93, 1 } };
    var n = start;
    for (city.missions, 0..) |mission, index| {
        const z_offset = (@as(f32, @floatFromInt(index)) - 1) * 15;
        const x_offset: f32 = if (index == 1) -16 else 16;
        const at = R.add(center, .{ x_offset, 0, z_offset });
        const color = colors[index];
        const live = sb.progress.hasFlag(mission.exposed_flag);
        const power = if (live) 0.82 + 0.18 * @sin(t * 2 + @as(f32, @floatFromInt(index))) else 0.12;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, 3.5, 0 }) }, .size = .{ 1.6, 7, 1.6 }, .tint = .{ 0.18, 0.24, 0.27, 1 } };
        out[n + 1] = .{ .mesh = c.gem, .transform = .{ .position = R.add(at, .{ 0, 7.8, 0 }) }, .size = @splat(1.05), .tint = Material.emissive(color, power) };
        n += 2;
    }
    return n;
}

/// Living roof gardens use the same authored flora meshes as the wilds, plus trailing vines
/// generated by Vegetation for ledges and stone facades. Placement follows each seeded tower.
fn publishCityGardenFoliage(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    const c = &sb.catalog.content;
    var n = start;
    for (sb.catalog.district.buildings[0..sb.catalog.district.building_count], 0..) |building, index| {
        if (building.architecture == .industrial) continue;
        for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sz| {
            if (n + 3 > out.len) return n;
            const x = building.base[0] + sx * (building.half[0] + 5.5);
            const z = building.base[2] + sz * (building.half[1] + 5.5);
            const planter_top = building.roof + 2.85;
            out[n] = .{ .mesh = c.flora[7], .transform = .{ .position = .{ x, planter_top, z }, .scale = 4.2 }, .tint = .{ 0.92, 1.05, 0.9, 1 } };
            n += 1;
            for (0..2) |flower| {
                const side: f32 = if (flower == 0) -1 else 1;
                const variety: usize = (index + flower + @intFromBool(sx > 0)) % 3;
                const mesh_index: usize = 8 + variety;
                out[n] = .{ .mesh = c.flora[mesh_index], .transform = .{ .position = .{ x + side * 2.25, planter_top, z }, .scale = 2.2 }, .tint = .{ 0.98, 1, 0.96, 1 } };
                n += 1;
            }
        };
        if (building.palette >= 6) for ([_]f32{ -0.52, 0.52 }) |u| {
            if (n == out.len) return n;
            const length = 26 + @min(30, (building.roof - building.base[1]) * 0.03);
            const x = building.base[0] + u * building.half[0];
            const z = building.base[2] + building.half[1] + 5.5;
            out[n] = .{ .mesh = c.hanging_vine, .transform = .{ .position = .{ x, building.roof + 2.85, z }, .scale = length }, .tint = .{ 1, 1, 1, 1 } };
            n += 1;
        };
    }
    return n;
}

/// The campaign beacon only appears once the active destination is within the local horizon.
/// This restores the old bright sky cue without leaving a permanent marker over distant content.
fn objectiveTarget(sb: *const Sandbox) ?V {
    const p = &sb.progress;
    if (!p.hasFlag("met_tavi")) return sb.keeperPosition(2);
    if (!p.hasFlag("tavi_scouted")) return sb.keeperPosition(2);
    if (!firstSurfaceNestDown(p)) return nearestLiveNest(sb, true);
    if (!p.hasFlag("ines_sap_warned")) return sb.keeperPosition(1);
    if (!p.hasFlag("carrier_seen")) return nearestCarrier(sb);
    if (!p.hasFlag("kestrel_blueprint") and !p.fighter) return sb.keeperPosition(0);
    if (!p.fighter) return kioskPosition(sb);
    if (QuestLog.remainingNests(&sb.enemies) > 0) return nearestLiveNest(sb, false);
    if (QuestLog.remainingCarriers(&sb.skies) > 0) return nearestCarrier(sb);
    if (CityContent.nextMission(&CityContent.detroit, p)) |mission| {
        if (mission == 0) {
            if (!p.hasFlag("foundry_started")) return sb.keeperPosition(0);
            if (p.hasFlag(FoundryCase.reported_flag) and !p.hasFlag(FoundryCase.confrontation_flag)) return FoundryCase.consolePosition(&sb.catalog.district);
            if (p.hasFlag(FoundryCase.confrontation_flag) and !p.hasFlag(FoundryCase.exposed_flag)) return FoundryCase.gatePosition(&sb.catalog.district);
            if (FoundryCase.next(p)) |index| return foundryCasePosition(sb, index);
            return sb.keeperPosition(0);
        }
        if (mission == 1 and sb.progress.hasFlag(WindsorCase.started_flag)) {
            if (WindsorCase.next(p)) |index| {
                var points: [WindsorCase.checkpoint_count]V = undefined;
                if (WindsorCase.positions(&sb.catalog.district, &points) > index) return points[index];
            }
        }
        if (mission == 2 and p.hasFlag(BileCase.started_flag)) {
            if (p.hasFlag(BileCase.notes_read_flag)) return sb.keeperPosition(2);
            if (p.hasFlag(BileCase.vault_open_flag)) return BileCase.notesPosition(sb.seed);
            if (BileCase.nextTrace(p)) |index| {
                var points: [BileCase.trace_count]V = undefined;
                if (BileCase.tracePositions(sb.seed, &points) > index) return points[index];
            }
            const answer = sb.bile_sequence;
            const relay_step = @min(sb.bile_relay_step, BileCase.relay_count - 1);
            return BileCase.relayPosition(sb.seed, answer[relay_step]);
        }
        return sb.keeperPosition(mission);
    }
    if (CityContent.bossReady(&CityContent.detroit, p) and cityFrontierClear(sb) and !CityContent.bossDefeated(&CityContent.detroit, p)) return WindsorCase.titanPosition(sb.seed);
    return null;
}

fn firstSurfaceNestDown(progress: *const Progress) bool {
    if (progress.hasFlag("first_spire_broken")) return true;
    for (0..Enemies.surface_nests) |i| {
        var flag: [16]u8 = undefined;
        if (progress.hasFlag(std.fmt.bufPrint(&flag, "nest_{d}_down", .{i}) catch unreachable)) return true;
    }
    return false;
}

fn nearestLiveNest(sb: *const Sandbox, surface_only: bool) ?V {
    var chosen: ?V = null;
    var best = std.math.inf(f32);
    for (sb.enemies.nests[0..sb.enemies.nest_count]) |nest| {
        if (!nest.alive or (surface_only and nest.cave)) continue;
        const d = R.length(R.sub(nest.position, sb.player.feet));
        if (d < best) {
            best = d;
            chosen = nest.position;
        }
    }
    return chosen;
}

fn nearestCarrier(sb: *const Sandbox) ?V {
    var chosen: ?V = null;
    var best = std.math.inf(f32);
    for (sb.skies.carriers) |carrier| {
        if (!carrier.alive) continue;
        const point = carrier.position();
        const d = R.length(R.sub(point, sb.player.feet));
        if (d < best) {
            best = d;
            chosen = point;
        }
    }
    return chosen;
}

fn publishObjectiveBeacon(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const target = objectiveTarget(sb) orelse return start;
    const distance = R.length(R.sub(target, sb.player.feet));
    if (distance < 34 or distance > 1250 or start + 3 > out.len) return start;

    const surface_y = Terrain.surface(sb.seed, target[0], target[2]).height;
    const base = .{ target[0], surface_y, target[2] };
    const pulse = 0.78 + 0.22 * @sin(t * 2.8);
    const core = Material.emissive(.{ 0.72, 0.94, 1, 1 }, 1.5 * pulse);
    const ground = Material.emissive(.{ 0.15, 0.68, 0.9, 1 }, 0.9 * pulse);
    const height: f32 = 175;
    out[start] = .{ .mesh = sb.catalog.content.block, .transform = .{ .position = R.add(base, .{ 0, height * 0.5, 0 }) }, .size = .{ 0.32, height, 0.32 }, .tint = core };
    out[start + 1] = .{ .mesh = sb.catalog.content.block, .transform = .{ .position = R.add(base, .{ 0, 0.12, 0 }) }, .size = .{ 4.2, 0.2, 4.2 }, .tint = ground };
    out[start + 2] = .{ .mesh = sb.catalog.content.gem, .transform = .{ .position = R.add(base, .{ 0, height + 4 + @sin(t * 1.8) * 1.2, 0 }) }, .size = @splat(5.5), .rotation = yawQuat(t * 0.24), .tint = Material.emissive(.{ 0.42, 0.9, 1, 1 }, 1.8 * pulse) };
    return start + 3;
}

/// Manifest pages appear at the industrial checkpoints after Maro starts the draft case.
fn publishFoundryEvidence(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    if (!sb.progress.hasFlag("foundry_started") or sb.progress.hasFlag("foundry_exposed")) return start;
    var points: [FoundryCase.checkpoint_count]V = undefined;
    const count = FoundryCase.positions(&sb.catalog.district, &points);
    var n = start;
    const c = &sb.catalog.content;
    for (points[0..count], 0..) |point, index| {
        if (FoundryCase.collected(&sb.progress, index)) continue;
        if (R.length(R.sub(point, sb.player.feet)) > 520 or n + 4 > out.len) continue;
        const ground = point[1] - 0.9;
        const selected = sb.target == .evidence and sb.target.evidence == @as(u8, @intCast(index));
        const pulse = 0.72 + 0.28 * @sin(t * 2.6 + @as(f32, @floatFromInt(index)));
        const crate_tint: [4]f32 = if (selected) .{ 0.58, 0.68, 0.72, 1 } else .{ 0.24, 0.3, 0.34, 1 };
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], ground + 0.24, point[2] } }, .tint = crate_tint, .size = .{ 1.25, 0.48, 0.92 } };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], ground + 0.52, point[2] } }, .tint = .{ 0.42, 0.48, 0.5, 1 }, .size = .{ 0.98, 0.09, 0.12 } };
        out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], ground + 0.7, point[2] } }, .tint = Material.emissive(.{ 0.92, 0.78, 0.42, 1 }, 0.55 + 0.25 * pulse), .size = .{ 0.56, 0.05, 0.68 }, .rotation = yawQuat(-0.18) };
        out[n + 3] = .{ .mesh = c.gem, .transform = .{ .position = .{ point[0], ground + 1.13 + 0.08 * @sin(t * 2 + @as(f32, @floatFromInt(index))), point[2] } }, .tint = Material.emissive(.{ 0.98, 0.72, 0.28, 1 }, pulse), .size = @splat(0.19), .rotation = yawQuat(t * 0.7) };
        n += 4;
    }
    return n;
}

/// Toll logs and the session recorder appear only while Ines's Windsor investigation is active.
fn publishWindsorEvidence(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    if (!sb.progress.hasFlag(WindsorCase.started_flag) or sb.progress.hasFlag(WindsorCase.exposed_flag)) return start;
    var points: [WindsorCase.checkpoint_count]V = undefined;
    const count = WindsorCase.positions(&sb.catalog.district, &points);
    var n = start;
    const c = &sb.catalog.content;
    for (points[0..count], 0..) |point, index| {
        if (WindsorCase.collected(&sb.progress, index)) continue;
        if (R.length(R.sub(point, sb.player.feet)) > 520 or n + 3 > out.len) continue;
        const floor = point[1] - 1.1;
        const selected = sb.target == .windsor_evidence and sb.target.windsor_evidence == @as(u8, @intCast(index));
        const pulse = 0.72 + 0.28 * @sin(t * 2.4 + @as(f32, @floatFromInt(index)));
        const tint: [4]f32 = if (index == 2) .{ 0.18, 0.66, 0.72, 1 } else .{ 0.3, 0.34, 0.38, 1 };
        const glow = if (selected) Material.emissive(.{ 0.35, 0.98, 0.91, 1 }, 0.85 + pulse * 0.2) else Material.emissive(.{ 0.96, 0.68, 0.28, 1 }, 0.48 + pulse * 0.3);
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], floor + 0.48, point[2] } }, .tint = tint, .size = .{ 0.85, 0.96, 0.7 } };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], floor + 1.04, point[2] - 0.38 } }, .tint = glow, .size = .{ 0.74, 0.36, 0.08 } };
        out[n + 2] = .{ .mesh = c.gem, .transform = .{ .position = .{ point[0], point[1] + 0.18 + @sin(t * 2 + @as(f32, @floatFromInt(index))) * 0.05, point[2] } }, .tint = glow, .size = @splat(0.14), .rotation = yawQuat(t * 0.6) };
        n += 3;
    }
    return n;
}

/// The two Windsor crossing barriers lift as soon as Ines publishes the recorded evidence.
/// Unlike the Foundry yard gate (solid while shut), these are visual only: closing a bridge deck
/// would also stop city traffic and pedestrians, which is an open design question.
fn publishWindsorGates(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    if (!sb.progress.hasFlag(WindsorCase.started_flag) and !sb.progress.hasFlag(WindsorCase.exposed_flag)) return start;
    var n = start;
    const open = sb.progress.hasFlag(WindsorCase.exposed_flag);
    const c = &sb.catalog.content;
    const pulse = 0.75 + 0.25 * @sin(t * 2.2);
    for (0..2) |index| {
        const gate = WindsorCase.gatePosition(sb.catalog.district.seed, index) orelse continue;
        if (R.length(R.sub(gate, sb.player.feet)) > 520) continue;
        if (n + 3 > out.len) break;
        const width: f32 = if (index == 0) 18 else 24;
        const tint = if (open) Material.emissive(.{ 0.16, 0.84, 0.68, 1 }, 0.8 + pulse * 0.2) else Material.emissive(.{ 0.94, 0.18, 0.12, 1 }, 0.75 + pulse * 0.25);
        const lift: f32 = if (open) 3.8 else 0;
        const post = .{ 0.6, 2.3, 0.8 };
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ gate[0] - width * 0.46, gate[1] + 1.15, gate[2] } }, .tint = .{ 0.22, 0.27, 0.29, 1 }, .size = post };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ gate[0] + width * 0.46, gate[1] + 1.15, gate[2] } }, .tint = .{ 0.22, 0.27, 0.29, 1 }, .size = post };
        out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = .{ gate[0], gate[1] + 1.25 + lift, gate[2] } }, .tint = tint, .size = .{ width, 0.5, 0.36 } };
        n += 3;
    }
    return n;
}

/// Belle Isle's former water institute opens into a compact relay archive for Tavi's case.
/// Geometry remains presentation-only; the interact ray and saved case flags own access.
fn publishBileArchive(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const c = &sb.catalog.content;
    const center = BileCase.institutePosition(sb.seed);
    if (R.length(R.sub(center, sb.player.feet)) > 540 or start + 10 > out.len) return start;
    var n = start;
    const stone: [4]f32 = .{ 0.78, 0.82, 0.77, 1 };
    const trim: [4]f32 = .{ 0.3, 0.39, 0.4, 1 };
    const ground = center[1];
    const opened = sb.progress.hasFlag(BileCase.vault_open_flag);
    const door = if (opened) Material.emissive(.{ 0.16, 0.84, 0.75, 1 }, 0.75 + 0.18 * @sin(t * 2)) else Material.emissive(.{ 0.88, 0.28, 0.16, 1 }, 0.8 + 0.2 * @sin(t * 2));
    // Stone plinth, three outer walls and a split facade leave a broad front doorway.
    const walls = [_]struct { at: V, size: V, tint: [4]f32 }{
        .{ .at = .{ center[0], ground + 0.22, center[2] }, .size = .{ 27, 0.44, 23 }, .tint = trim },
        .{ .at = .{ center[0], ground + 4.2, center[2] + 10.8 }, .size = .{ 23, 8, 0.7 }, .tint = stone },
        .{ .at = .{ center[0] - 11.2, ground + 4.2, center[2] }, .size = .{ 0.7, 8, 21 }, .tint = stone },
        .{ .at = .{ center[0] + 11.2, ground + 4.2, center[2] }, .size = .{ 0.7, 8, 21 }, .tint = stone },
        .{ .at = .{ center[0] - 7.25, ground + 4.2, center[2] - 10.8 }, .size = .{ 8.9, 8, 0.7 }, .tint = stone },
        .{ .at = .{ center[0] + 7.25, ground + 4.2, center[2] - 10.8 }, .size = .{ 8.9, 8, 0.7 }, .tint = stone },
        .{ .at = .{ center[0], ground + 8.25, center[2] }, .size = .{ 23, 0.65, 21 }, .tint = trim },
        .{ .at = .{ center[0], ground + 7.2, center[2] - 10.8 }, .size = .{ 5.4, 1.8, 0.8 }, .tint = trim },
        .{ .at = .{ center[0] - 3.8, ground + 3.1, center[2] - 10.75 }, .size = .{ 0.75, 6.2, 0.8 }, .tint = trim },
        .{ .at = .{ center[0] + 3.8, ground + 3.1, center[2] - 10.75 }, .size = .{ 0.75, 6.2, 0.8 }, .tint = trim },
    };
    for (walls) |wall| {
        if (n == out.len) return n;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = wall.at }, .size = wall.size, .tint = wall.tint };
        n += 1;
    }
    if (n < out.len) {
        const lift: f32 = if (opened) 7 else 0;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ center[0], ground + 3.1 + lift, center[2] - 10.72 } }, .size = .{ 6.2, 5.8, 0.34 }, .tint = door };
        n += 1;
    }

    if (sb.progress.hasFlag(BileCase.started_flag) and !sb.progress.hasFlag(BileCase.exposed_flag)) {
        if (!sb.progress.hasFlag(BileCase.traces_complete_flag)) {
            var points: [BileCase.trace_count]V = undefined;
            const count = BileCase.tracePositions(sb.seed, &points);
            for (points[0..count], 0..) |point, index| {
                if (BileCase.collected(&sb.progress, index) or R.length(R.sub(point, sb.player.feet)) > 540 or n + 2 > out.len) continue;
                const selected = sb.target == .bile_trace and sb.target.bile_trace == @as(u8, @intCast(index));
                const glow = Material.emissive(if (selected) .{ 0.32, 1, 0.92, 1 } else .{ 0.9, 0.68, 0.3, 1 }, 0.72 + 0.28 * @sin(t * 2.4 + @as(f32, @floatFromInt(index))));
                out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], point[1] - 0.28, point[2] } }, .size = .{ 0.9, 0.36, 0.8 }, .tint = .{ 0.28, 0.33, 0.34, 1 } };
                out[n + 1] = .{ .mesh = c.gem, .transform = .{ .position = .{ point[0], point[1] + 0.15, point[2] } }, .size = @splat(0.17), .tint = glow };
                n += 2;
            }
        } else if (!opened) {
            for (0..BileCase.relay_count) |index| {
                const point = BileCase.relayPosition(sb.seed, index) orelse continue;
                if (R.length(R.sub(point, sb.player.feet)) > 540 or n + 2 > out.len) continue;
                const selected = sb.target == .bile_relay and sb.target.bile_relay == @as(u8, @intCast(index));
                const relay_color: [4]f32 = if (selected) .{ 0.24, 0.96, 0.82, 1 } else switch (index) {
                    0 => .{ 0.96, 0.62, 0.18, 1 },
                    1 => .{ 0.66, 0.38, 0.96, 1 },
                    else => .{ 0.18, 0.67, 0.96, 1 },
                };
                const glow = Material.emissive(relay_color, 0.8 + 0.2 * @sin(t * 2.8 + @as(f32, @floatFromInt(index))));
                out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], point[1] - 0.48, point[2] } }, .size = .{ 1.05, 0.95, 0.9 }, .tint = trim };
                out[n + 1] = .{ .mesh = c.gem, .transform = .{ .position = .{ point[0], point[1] + 0.05, point[2] } }, .size = @splat(0.27), .tint = glow };
                n += 2;
            }
        } else if (!sb.progress.hasFlag(BileCase.notes_read_flag)) {
            const point = BileCase.notesPosition(sb.seed);
            if (R.length(R.sub(point, sb.player.feet)) <= 540 and n + 3 <= out.len) {
                const glow = Material.emissive(.{ 0.32, 0.92, 0.82, 1 }, 0.8 + 0.2 * @sin(t * 2.1));
                out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], point[1] - 0.18, point[2] } }, .size = .{ 1.2, 0.32, 0.9 }, .tint = trim };
                out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], point[1] + 0.04, point[2] } }, .size = .{ 0.8, 0.08, 0.58 }, .tint = glow };
                out[n + 2] = .{ .mesh = c.gem, .transform = .{ .position = .{ point[0], point[1] + 0.48 + 0.05 * @sin(t * 1.8), point[2] } }, .size = @splat(0.2), .tint = glow };
                n += 3;
            }
        }
    }
    return n;
}

/// Glowing city keepsakes appear near the party until the shared find or every present ranger's
/// personal claim is complete. Their anchors remain fixed to seeded Detroit landmarks.
fn publishCityDiscoveries(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const colors = [CityContent.discovery_count][3]f32{
        .{ 0.28, 0.86, 1.0 },
        .{ 0.75, 0.84, 0.92 },
        .{ 0.3, 1.0, 0.56 },
        .{ 0.3, 0.92, 0.78 },
        .{ 0.6, 1.0, 0.38 },
        .{ 1.0, 0.69, 0.24 },
        .{ 0.25, 0.72, 1.0 },
        .{ 0.35, 0.92, 1.0 },
        .{ 0.67, 0.55, 1.0 },
        .{ 1.0, 0.77, 0.38 },
    };
    var n = start;
    const c = &sb.catalog.content;
    for (sb.city_discovery_positions, 0..) |point, index| {
        if (!anyPlayerNeedsDiscovery(sb, index) or !anyPlayerNear(sb, point, 520) or n + 3 > out.len) continue;
        const rgb = colors[index];
        const selected = sb.target == .city_discovery and sb.target.city_discovery == @as(u8, @intCast(index));
        const pulse = 0.72 + 0.28 * @sin(t * 2.3 + @as(f32, @floatFromInt(index)));
        const glow = Material.emissive(if (selected) .{ 0.46, 1.0, 0.88, 1 } else .{ rgb[0], rgb[1], rgb[2], 1 }, pulse);
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], point[1] - 0.72, point[2] } }, .tint = .{ 0.23, 0.3, 0.31, 1 }, .size = .{ 1.6, 0.3, 1.6 } };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ point[0], point[1] + 2.55, point[2] } }, .tint = Material.emissive(.{ rgb[0], rgb[1], rgb[2], 1 }, 0.48 + pulse * 0.28), .size = .{ 0.28, 5.1, 0.28 } };
        out[n + 2] = .{ .mesh = c.gem, .transform = .{ .position = .{ point[0], point[1] + 0.3 + 0.12 * @sin(t * 2.5 + @as(f32, @floatFromInt(index))), point[2] } }, .tint = glow, .size = @splat(if (selected) 1.15 else 0.92), .rotation = yawQuat(t * 0.55) };
        n += 3;
    }
    return n;
}

/// The dock terminal receives the shared dossier, and the non-blocking yard barrier changes
/// from Hive red to clear cyan once the steward is publicly exposed.
fn publishFoundryDock(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    if (!sb.progress.hasFlag("foundry_started")) return start;
    var points: [FoundryCase.checkpoint_count]V = undefined;
    const count = FoundryCase.positions(&sb.catalog.district, &points);
    if (count == 0 or R.length(R.sub(points[0], sb.player.feet)) > 520 or start + 8 > out.len) return start;

    const dock = points[0];
    const ground = dock[1] - 0.9;
    const gate_z = dock[2] + 8;
    const open = sb.progress.hasFlag(FoundryCase.exposed_flag);
    const pulse = 0.76 + 0.24 * @sin(t * 2.4);
    const metal: [4]f32 = .{ 0.13, 0.19, 0.23, 1 };
    const hostile = Material.emissive(.{ 0.92, 0.18, 0.12, 1 }, 0.82 + 0.2 * pulse);
    const clear = Material.emissive(.{ 0.16, 0.86, 0.77, 1 }, 0.82 + 0.2 * pulse);
    const barrier = if (open) clear else hostile;
    const slide: f32 = if (open) 6 else 0;
    const c = &sb.catalog.content;
    var n = start;

    // Two dock uprights, a cross beam, and a sliding panel make the access state readable from
    // the approach. The gate is presentation geometry; navigation remains on the open road.
    out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ dock[0] - 5.1, ground + 2.3, gate_z } }, .tint = metal, .size = .{ 0.8, 4.6, 0.9 } };
    out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ dock[0] + 5.1, ground + 2.3, gate_z } }, .tint = metal, .size = .{ 0.8, 4.6, 0.9 } };
    out[n + 2] = .{ .mesh = c.block, .transform = .{ .position = .{ dock[0], ground + 4.7, gate_z } }, .tint = metal, .size = .{ 11.5, 0.65, 1 } };
    out[n + 3] = .{ .mesh = c.block, .transform = .{ .position = .{ dock[0] + slide, ground + 1.45, gate_z - 0.18 } }, .tint = barrier, .size = .{ 9.8, 2.5, 0.35 } };
    out[n + 4] = .{ .mesh = c.block, .transform = .{ .position = .{ dock[0], ground + 0.12, gate_z } }, .tint = Material.emissive(if (open) .{ 0.12, 0.55, 0.48, 1 } else .{ 0.58, 0.17, 0.14, 1 }, 0.55), .size = .{ 11, 0.18, 1.4 } };
    n += 5;

    if (sb.progress.hasFlag(FoundryCase.complete_flag)) {
        const screen_color = if (sb.progress.hasFlag(FoundryCase.reported_flag)) clear else Material.emissive(.{ 0.95, 0.67, 0.22, 1 }, 0.55 + pulse * 0.2);
        out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ dock[0], ground + 0.55, dock[2] } }, .tint = metal, .size = .{ 1.15, 1.1, 0.9 } };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ dock[0], ground + 1.25, dock[2] - 0.12 } }, .tint = screen_color, .size = .{ 0.92, 0.42, 0.14 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_x, -0.2)) };
        out[n + 2] = .{ .mesh = c.gem, .transform = .{ .position = .{ dock[0], ground + 1.55 + @sin(t * 2) * 0.04, dock[2] - 0.12 } }, .tint = if (sb.target == .foundry_terminal) screen_color else Material.emissive(.{ 0.88, 0.62, 0.2, 1 }, 0.7), .size = @splat(0.16), .rotation = yawQuat(t * 0.45) };
        n += 3;
    }
    return n;
}

/// Rootdeep vaults grow as a fusion of living rootwork and old machine craft. These exterior
/// pieces are presentation geometry; puzzle rooms and collision stay in the verified blueprint.
/// Lab dressing for a shrine's rooms: wall pilasters and glyph panels, ceiling light strips and a
/// turning hoop per room, inlaid floor lines, and gimbal rings around the seed lamp. All of it is
/// visual only and stays clear of the walkway, buttons, plates and crates (see `Shrine` layout),
/// and it is skipped when the player is far away.
fn dressShrineInterior(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32, k: usize, o: V, l: f32, glow_color: [4]f32) usize {
    const c = &sb.catalog.content;
    const eye = sb.player.feet;
    const centre_z = o[2] + l / 2;
    if (@abs(eye[0] - o[0]) > 90 or @abs(eye[2] - centre_z) > l / 2 + 90) return start;
    const rooms: usize = @intFromFloat(l / Shrine.room_length);
    const stone: [4]f32 = if (k == 0) .{ 0.78, 0.64, 0.44, 1 } else .{ 0.42, 0.7, 0.68, 1 };
    var n = start;
    for (0..rooms) |r| {
        const z0 = @as(f32, @floatFromInt(r)) * Shrine.room_length;
        const zc = z0 + Shrine.room_length / 2;
        const budget: usize = 14;
        if (n + budget > out.len) return n;
        const pulse = 0.8 + 0.2 * @sin(t * 1.8 + @as(f32, @floatFromInt(r)));
        for ([_]f32{ -1, 1 }) |side| {
            for ([_]f32{ -3.9, 3.9 }) |dz| {
                out[n] = .{ .mesh = c.shrine_pilaster, .transform = .{ .position = R.add(o, .{ side * 4.45, 0, zc + dz }) }, .size = .{ 1.1, 4.1, 1.1 }, .tint = stone };
                n += 1;
            }
            // The right wall of the first room carries the reset button at its middle.
            if (!(r == 0 and side > 0)) {
                out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(o, .{ side * 4.93, 2.3, zc }) }, .size = .{ 0.06, 1.7, 2.4 }, .tint = Material.emissive(glow_color, 0.5 * pulse) };
                n += 1;
            }
            out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(o, .{ side * 2.4, 4.38, zc }) }, .size = .{ 0.14, 0.08, 9 }, .tint = Material.emissive(glow_color, 0.9 * pulse) };
            out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(o, .{ side * 1.15, 0.02, zc }) }, .size = .{ 0.08, 0.03, 9.2 }, .tint = Material.emissive(glow_color, 0.55 * pulse) };
            n += 2;
        }
        const spin = t * 0.4 + @as(f32, @floatFromInt(r));
        out[n] = .{ .mesh = c.shrine_hoop, .transform = .{ .position = R.add(o, .{ 0, 3.3, zc }) }, .size = .{ 1.3, 1.3, 1.3 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, spin).mul(m.Quat.fromAxisAngle(m.Vec3.unit_x, 0.9))), .tint = Material.emissive(glow_color, 1.0 * pulse) };
        n += 1;
    }
    // Rings around the seed lamp in the vault room.
    if (n + 2 <= out.len) {
        const lamp = R.add(o, .{ 0, 2.6, l - 0.6 });
        out[n] = .{ .mesh = c.shrine_hoop, .transform = .{ .position = lamp }, .size = .{ 1.15, 1.15, 1.15 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, t * 0.7).mul(m.Quat.fromAxisAngle(m.Vec3.unit_x, 1.2))), .tint = Material.emissive(glow_color, 1.2) };
        out[n + 1] = .{ .mesh = c.shrine_hoop, .transform = .{ .position = lamp }, .size = .{ 0.85, 0.85, 0.85 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_z, -t * 0.9).mul(m.Quat.fromAxisAngle(m.Vec3.unit_x, 0.4))), .tint = Material.emissive(glow_color, 1.0) };
        n += 2;
    }
    return n;
}

fn publishShrines(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const c = &sb.catalog.content;
    var n = start;
    const Add = struct {
        fn piece(props: []World.Prop, count: *usize, mesh: @TypeOf(c.block), at: V, size: V, tint: [4]f32, rotation: [4]f32) bool {
            if (count.* == props.len) return false;
            props[count.*] = .{ .mesh = mesh, .transform = .{ .position = at }, .tint = tint, .size = size, .rotation = rotation };
            count.* += 1;
            return true;
        }
        fn block(props: []World.Prop, count: *usize, mesh: @TypeOf(c.block), at: V, size: V, tint: [4]f32) bool {
            return piece(props, count, mesh, at, size, tint, .{ 0, 0, 0, 1 });
        }
    };
    for (sb.shrines, 0..) |shrine, k| {
        const o = shrine.origin;
        const l = @import("../procedural/Shrine.zig").length(shrine.generated.puzzle);
        const stone: [4]f32 = if (k == 0) .{ 0.24, 0.3, 0.34, 1 } else .{ 0.2, 0.32, 0.36, 1 };
        const rootwood: [4]f32 = if (k == 0) .{ 0.42, 0.25, 0.13, 1 } else .{ 0.28, 0.28, 0.2, 1 };
        const metal: [4]f32 = if (k == 0) .{ 0.7, 0.4, 0.16, 1 } else .{ 0.22, 0.55, 0.58, 1 };
        const glow_color: [4]f32 = if (k == 0) .{ 1, 0.31, 0.12, 1 } else .{ 0.2, 0.95, 0.8, 1 };

        // A narrow basalt-and-bronze threshold leads into the still-clear puzzle doorway.
        if (!Add.block(out, &n, c.block, R.add(o, .{ 0, -0.38, -2.1 }), .{ 12, 0.55, 7 }, stone)) return n;
        if (!Add.block(out, &n, c.block, R.add(o, .{ 0, -0.05, -3.0 }), .{ 9, 0.15, 0.45 }, Material.emissive(glow_color, 0.75 + 0.2 * @sin(t * 2)))) return n;

        // Four flared living ribs form a tall open portal instead of a stepped block pyramid.
        for ([_]f32{ -1, 1 }) |side| for ([_]f32{ 1.5, l - 2.5 }) |z| {
            const angle = side * 0.23;
            const rib = c.tree_trunks[(k + 2) % c.tree_trunks.len];
            const lower = R.add(o, .{ side * 7, 0, z });
            const upper = R.add(o, .{ side * 5.1, 7.6, z });
            if (!Add.piece(out, &n, rib, lower, .{ 16, 8.2, 16 }, rootwood, quat(m.Quat.fromAxisAngle(m.Vec3.unit_z, angle)))) return n;
            if (!Add.piece(out, &n, rib, upper, .{ 13, 7.4, 13 }, stone, quat(m.Quat.fromAxisAngle(m.Vec3.unit_z, angle * 0.72)))) return n;
            if (!Add.block(out, &n, c.block, R.add(o, .{ side * 5.9, 6.3, z }), .{ 0.2, 4.4, 0.22 }, Material.emissive(glow_color, 0.75 + 0.25 * @sin(t * 2.1 + z)))) return n;
        };
        // Short cross-ribs and jewel sockets read as grafted machinery woven into the roots.
        for ([_]f32{ 3.7, l - 4.2 }) |z| {
            if (!Add.block(out, &n, c.block, R.add(o, .{ 0, 10, z }), .{ 8.2, 0.72, 1.0 }, rootwood)) return n;
            if (!Add.block(out, &n, c.block, R.add(o, .{ 0, 10.42, z }), .{ 7.6, 0.12, 0.2 }, Material.emissive(glow_color, 1.0 + 0.2 * @sin(t * 2.4 + z)))) return n;
        }
        const crown_z = l - 4.2;
        for ([_]f32{ -1, 1 }) |side| {
            if (n == out.len) return n;
            out[n] = .{ .mesh = c.gem, .transform = .{ .position = R.add(o, .{ side * 5.8, 5.3, crown_z }) }, .size = .{ 1.7, 2.8, 1.7 }, .rotation = yawQuat(side * 0.45), .tint = Material.emissive(glow_color, 0.9 + 0.2 * @sin(t * 1.9 + side)) };
            n += 1;
        }
        if (n == out.len) return n;
        out[n] = .{ .mesh = c.gem, .transform = .{ .position = R.add(o, .{ 0, 11.1, crown_z }) }, .tint = Material.emissive(glow_color, 1.5 + 0.35 * @sin(t * 2.2)), .size = .{ 2.4, 4.2, 2.4 }, .rotation = yawQuat(t * 0.22) };
        n += 1;
        // Halos hover over the portal: a vertical ring and a tilted gimbal ring turning slowly.
        if (n + 2 > out.len) return n;
        const halo = R.add(o, .{ 0, 9.8, 2.2 });
        out[n] = .{ .mesh = c.shrine_hoop, .transform = .{ .position = halo }, .size = .{ 5.4, 5.4, 5.4 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_x, std.math.pi / 2.0)), .tint = Material.emissive(glow_color, 1.1 + 0.2 * @sin(t * 1.6)) };
        out[n + 1] = .{ .mesh = c.shrine_hoop, .transform = .{ .position = halo }, .size = .{ 4.2, 4.2, 4.2 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, t * 0.3).mul(m.Quat.fromAxisAngle(m.Vec3.unit_x, 1.05))), .tint = Material.emissive(metal, 0.9) };
        n += 2;
        n = dressShrineInterior(sb, out, n, t, k, o, l, glow_color);
        // A low circuit ring binds the architecture to the Rootdeep's powered seed vault.
        if (!Add.block(out, &n, c.block, R.add(o, .{ 0, 0.16, l - 3 }), .{ 13, 0.16, 0.2 }, Material.emissive(metal, 0.7))) return n;
    }
    return n;
}

const max_weapon_parts = 16;
/// A part of a held weapon: offset along the weapon's frame (+Z along the barrel or blade), size,
/// colour, and glow (0 for plain metal).
const Part = struct { at: [3]f32, size: [3]f32, color: [3]f32, glow: f32 = 0, shape: enum { block, gem, spike } = .block };
const gunmetal: [3]f32 = .{ 0.16, 0.17, 0.2 };
const plate: [3]f32 = .{ 0.62, 0.64, 0.68 };

/// A held weapon built from blocks: hilt and blade, or a gun's body, barrel and lumen strips.
fn rgb3(c: [4]f32) [3]f32 {
    return .{ c[0], c[1], c[2] };
}

fn heldWeapon(out: []World.Prop, block: @import("../asset/Catalog.zig").MeshHandle, gem_mesh: @import("../asset/Catalog.zig").MeshHandle, spike: @import("../asset/Catalog.zig").MeshHandle, saber_blade: @import("../asset/Catalog.zig").MeshHandle, saber_core: @import("../asset/Catalog.zig").MeshHandle, kind: Combat.WeaponKind, grip: Combat.Grip, arsenal: *const Combat.Arsenal, t: f32, accent: [3]f32) usize {
    const heat = arsenal.charge();
    // One swept mesh makes the energized edge read as a continuous curved blade at distance.
    if (kind == .beam_saber) {
        for (arsenal.system.projectiles.items) |projectile| if (projectile.active and projectile.kind == .saber_boomerang) return 0;
        const z = R.normalize(grip.dir);
        const side = if (@abs(z[1]) > 0.98) @as(V, .{ 1, 0, 0 }) else R.normalize(R.cross(.{ 0, 1, 0 }, z));
        const up = R.cross(z, side);
        const frame = m.Quat.fromTo(m.Vec3.unit_z, m.Vec3.init(z[0], z[1], z[2]));
        const write = struct {
            fn prop(props: []World.Prop, index: *usize, mesh: @TypeOf(block), base: V, side_v: V, up_v: V, forward: V, local: [3]f32, size: V, tint: [4]f32, rotation: m.Quat) void {
                const at = R.add(base, R.add(R.add(R.scale(side_v, local[0]), R.scale(up_v, local[1])), R.scale(forward, local[2])));
                props[index.*] = .{ .mesh = mesh, .transform = .{ .position = at }, .tint = tint, .size = size, .rotation = quat(rotation) };
                index.* += 1;
            }
        }.prop;
        var count: usize = 0;
        write(out, &count, block, grip.base, side, up, z, .{ 0, 0, -0.03 }, .{ 0.12, 0.12, 0.32 }, .{ gunmetal[0], gunmetal[1], gunmetal[2], 1 }, frame);
        write(out, &count, gem_mesh, grip.base, side, up, z, .{ 0, 0, 0.17 }, .{ 0.22, 0.18, 0.16 }, Material.emissive(.{ accent[0], accent[1], accent[2], 1 }, 1.1), frame);
        write(out, &count, block, grip.base, side, up, z, .{ 0.12, 0, 0.12 }, .{ 0.42, 0.075, 0.11 }, .{ plate[0], plate[1], plate[2], 1 }, frame);
        const blade_at = R.add(grip.base, R.scale(z, 0.36));
        const pulse = 0.92 + 0.08 * @sin(t * 12);
        write(out, &count, saber_blade, blade_at, side, up, z, .{ 0, 0, 0 }, .{ 1, 1, 0.92 }, Material.emissive(.{ accent[0], accent[1], accent[2], 1 }, 0.92 * pulse), frame);
        const normal = frame.rotate(m.Vec3.unit_y);
        const core_base = R.add(blade_at, .{ normal.x * 0.11, normal.y * 0.11, normal.z * 0.11 });
        write(out, &count, saber_core, core_base, side, up, z, .{ 0, 0, 0 }, .{ 1, 1, 0.92 }, Material.emissive(.{ 0.92, 0.98, 1, 1 }, 1.5), frame);
        write(out, &count, gem_mesh, grip.base, side, up, z, .{ 0.99, 0.20, 3.49 }, .{ 0.18, 0.16, 0.22 }, Material.emissive(.{ 0.92, 0.99, 1, 1 }, 1.65), frame.mul(m.Quat.fromAxisAngle(m.Vec3.unit_y, 0.55)));
        return count;
    }
    const parts: []const Part = switch (kind) {
        .beam_saber => unreachable,
        .blaster => &.{
            // A palm-mounted ki focus: tapered wrist bracer, split emitter fins and a charged gem.
            .{ .at = .{ 0, -0.015, -0.04 }, .size = .{ 0.105, 0.14, 0.28 }, .color = gunmetal },
            .{ .at = .{ 0, 0.015, 0.12 }, .size = .{ 0.13, 0.17, 0.27 }, .color = plate, .shape = .spike },
            .{ .at = .{ -0.105, 0.02, 0.18 }, .size = .{ 0.055, 0.08, 0.21 }, .color = .{ 0.35, 0.52, 0.66 }, .shape = .spike },
            .{ .at = .{ 0.105, 0.02, 0.18 }, .size = .{ 0.055, 0.08, 0.21 }, .color = .{ 0.35, 0.52, 0.66 }, .shape = .spike },
            .{ .at = .{ 0, 0.025, 0.235 }, .size = .{ 0.13, 0.13, 0.13 }, .color = .{ 0.3, 0.82, 1 }, .glow = 1.1 + heat * 0.6, .shape = .gem },
            .{ .at = .{ 0, 0.025, 0.32 }, .size = .{ 0.07 + heat * 0.025, 0.07 + heat * 0.025, 0.11 }, .color = .{ 0.78, 0.96, 1 }, .glow = 1.25 + heat, .shape = .gem },
        },
        .sniper_rifle => &.{
            .{ .at = .{ 0, 0.03, 0.1 }, .size = .{ 0.07, 0.12, 0.55 }, .color = gunmetal },
            .{ .at = .{ 0, 0.05, 0.75 }, .size = .{ 0.035, 0.035, 0.8 }, .color = plate, .shape = .spike },
            .{ .at = .{ 0, 0.14, 0.12 }, .size = .{ 0.05, 0.05, 0.3 }, .color = gunmetal },
            .{ .at = .{ 0, 0.14, 0.275 }, .size = .{ 0.04, 0.04, 0.01 }, .color = .{ 0.35, 1, 0.6 }, .glow = 0.6 + heat * 0.4 },
            .{ .at = .{ 0, 0.05, 1.16 }, .size = .{ 0.05, 0.05, 0.04 }, .color = .{ 0.35, 1, 0.6 }, .glow = 0.8, .shape = .gem },
        },
        .machine_gun => &.{
            .{ .at = .{ 0, 0.02, 0.12 }, .size = .{ 0.12, 0.15, 0.6 }, .color = gunmetal },
            .{ .at = .{ 0, 0.04, 0.6 }, .size = .{ 0.06, 0.06, 0.4 }, .color = plate, .shape = .spike },
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
            .{ .at = .{ 0, 0.12, 0.05 }, .size = .{ 0.2, 0.2, 1.1 }, .color = plate, .shape = .spike },
            .{ .at = .{ 0, 0.12, 0.62 }, .size = .{ 0.24, 0.24, 0.06 }, .color = .{ 1, 0.4, 0.9 }, .glow = 0.4 + 0.6 * heat },
            .{ .at = .{ 0, -0.02, 0 }, .size = .{ 0.05, 0.14, 0.06 }, .color = gunmetal },
        },
        .energy_bow => &.{
            .{ .at = .{ 0, 0, 0.1 }, .size = .{ 0.035, 1.1, 0.04 }, .color = .{ 0.5, 0.85, 1 }, .glow = 0.6 + 0.4 * heat },
            .{ .at = .{ 0, 0, 0.08 }, .size = .{ 0.06, 0.16, 0.06 }, .color = gunmetal },
        },
        .tracking_missile => &.{
            .{ .at = .{ 0, 0.1, 0.05 }, .size = .{ 0.24, 0.2, 0.45 }, .color = plate, .shape = .spike },
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
        .energy_net => &.{
            .{ .at = .{ 0, 0.02, 0.08 }, .size = .{ 0.2, 0.22, 0.42 }, .color = gunmetal },
            .{ .at = .{ 0, 0.04, 0.4 }, .size = .{ 0.24, 0.24, 0.32 }, .color = plate, .shape = .spike },
            .{ .at = .{ 0, 0.04, 0.57 }, .size = .{ 0.17, 0.17, 0.12 }, .color = .{ 0.2, 0.95, 0.9 }, .glow = 1.2, .shape = .gem },
            .{ .at = .{ 0, 0.04, 0.68 }, .size = .{ 0.08, 0.08, 0.2 }, .color = .{ 0.64, 1, 0.95 }, .glow = 1.5 },
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
    const weapon_rotation = aim.mul(m.Quat.fromAxisAngle(m.Vec3.unit_z, roll));
    for (parts, 0..) |part, i| {
        const at = R.add(grip.base, R.add(R.add(R.scale(side, part.at[0]), R.scale(up, part.at[1])), R.scale(z, part.at[2])));
        const color: [4]f32 = .{ part.color[0], part.color[1], part.color[2], 1 };
        const mesh = switch (part.shape) {
            .block => block,
            .gem => gem_mesh,
            .spike => spike,
        };
        const shape_rotation = if (part.shape == .spike) weapon_rotation.mul(m.Quat.fromTo(m.Vec3.unit_y, m.Vec3.unit_z)) else weapon_rotation;
        out[i] = .{ .mesh = mesh, .transform = .{ .position = at }, .tint = if (part.glow > 0) Material.emissive(color, part.glow) else color, .size = part.size, .rotation = quat(shape_rotation) };
    }
    return parts.len;
}

/// A luminous capture lattice flies perpendicular to its direction, making the wide hit area
/// legible in the sky and readable against foliage.
fn energyNet(out: []World.Prop, block: @import("../asset/Catalog.zig").MeshHandle, at: V, velocity: V) usize {
    const forward = R.normalize(velocity);
    const side = if (@abs(forward[1]) > 0.95) R.normalize(R.cross(forward, .{ 0, 0, 1 })) else R.normalize(R.cross(forward, .{ 0, 1, 0 }));
    const up = R.normalize(R.cross(side, forward));
    const radius: f32 = 4.5 * 1.15;
    const glow = Material.emissive(.{ 0.12, 0.95, 0.84, 1 }, 1.45);
    var count: usize = 0;
    for (0..5) |i| {
        const offset = -radius + @as(f32, @floatFromInt(i)) * (radius * 0.5);
        out[count] = .{ .mesh = block, .transform = .{ .position = R.add(at, R.scale(side, offset)) }, .tint = glow, .size = .{ 0.045, 0.045, radius * 2 }, .rotation = facing(up) };
        count += 1;
        out[count] = .{ .mesh = block, .transform = .{ .position = R.add(at, R.scale(up, offset)) }, .tint = glow, .size = .{ 0.045, 0.045, radius * 2 }, .rotation = facing(side) };
        count += 1;
    }
    for ([_]f32{ -1, 1 }) |edge| {
        const rail = Material.emissive(.{ 0.36, 1, 0.94, 1 }, 1.7);
        out[count] = .{ .mesh = block, .transform = .{ .position = R.add(at, R.scale(side, edge * radius)) }, .tint = rail, .size = .{ 0.09, 0.09, radius * 2 }, .rotation = facing(up) };
        count += 1;
        out[count] = .{ .mesh = block, .transform = .{ .position = R.add(at, R.scale(up, edge * radius)) }, .tint = rail, .size = .{ 0.09, 0.09, radius * 2 }, .rotation = facing(side) };
        count += 1;
    }
    return count;
}

/// Two layered meshes create a smooth accent corona and white-hot inner edge.
fn saberWave(out: []World.Prop, outer: @import("../asset/Catalog.zig").MeshHandle, core: @import("../asset/Catalog.zig").MeshHandle, at: V, velocity: V, accent: [3]f32, radius: f32, t: f32) usize {
    const rotation = facing(velocity);
    const scale = @max(0.6, radius * (1.15 + 0.035 * @sin(t * 16)));
    out[0] = .{ .mesh = outer, .transform = .{ .position = at }, .tint = Material.emissive(.{ accent[0], accent[1], accent[2], 1 }, 1.65), .size = .{ scale, scale, scale }, .rotation = rotation };
    out[1] = .{ .mesh = core, .transform = .{ .position = at }, .tint = Material.emissive(.{ 0.92, 0.98, 1, 1 }, 1.9), .size = .{ scale, scale, scale }, .rotation = rotation };
    return 2;
}

/// The Starbowl: a floating slab with a lit ring, low walls, four corner pylons with beacons,
/// and a sun emblem at the centre that pulses with the wave.
fn publishArena(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    if (!sb.arena.active) return start;
    var n = start;
    const c = &sb.catalog.content;
    const at = sb.arena.center;
    const h = Arena.half;
    const room = struct {
        fn ok(o: []World.Prop, k: usize, need: usize) bool {
            return k + need <= o.len;
        }
    }.ok;
    if (!room(out, n, 24)) return n;
    const stone: [4]f32 = .{ 0.42, 0.42, 0.5, 1 };
    const trim: [4]f32 = .{ 0.36, 0.32, 0.5, 1 };
    out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, -1, 0 }) }, .tint = stone, .size = .{ h * 2, 2, h * 2 } };
    out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, -5, 0 }) }, .tint = trim, .size = .{ h * 1.7, 6, h * 1.7 } };
    n += 2;
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |side| {
        const pos = R.add(at, .{ side[0] * h, Arena.wall_height / 2, side[1] * h });
        const size: [3]f32 = if (side[0] != 0) .{ 1.2, Arena.wall_height, h * 2 } else .{ h * 2, Arena.wall_height, 1.2 };
        out[n] = .{ .mesh = c.block, .transform = .{ .position = pos }, .tint = trim, .size = size };
        // A lit band along the wall's top.
        const band: [3]f32 = if (side[0] != 0) .{ 1.3, 0.2, h * 2 } else .{ h * 2, 0.2, 1.3 };
        out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(pos, .{ 0, Arena.wall_height / 2, 0 }) }, .tint = Material.emissive(.{ 1, 0.75, 0.3, 1 }, 0.7), .size = band };
        n += 2;
    }
    for ([_][2]f32{ .{ 1, 1 }, .{ -1, 1 }, .{ 1, -1 }, .{ -1, -1 } }) |corner| {
        const base = R.add(at, .{ corner[0] * h, 0, corner[1] * h });
        out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(base, .{ 0, 5, 0 }) }, .tint = trim, .size = .{ 2.2, 10, 2.2 } };
        out[n + 1] = .{ .mesh = c.gem, .transform = .{ .position = R.add(base, .{ 0, 11.5 + 0.3 * @sin(t * 2), 0 }) }, .tint = Material.emissive(.{ 0.4, 0.9, 1, 1 }, 1), .size = @splat(1.6), .rotation = yawQuat(t) };
        n += 2;
    }
    // Rings on the floor: an outer path and the central sun, brighter while a wave is on.
    const fighting: f32 = if (sb.arena.waiting > 0) 0.35 else 0.9;
    for (0..8) |k| {
        const a = @as(f32, @floatFromInt(k)) / 8 * std.math.pi;
        out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(at, .{ 0, 0.01, 0 }) }, .tint = Material.emissive(.{ 1, 0.8, 0.35, 1 }, fighting * (0.5 + 0.3 * @sin(t * 3 + @as(f32, @floatFromInt(k))))), .size = .{ 0.12, 0.02, 7 }, .rotation = yawQuat(a + t * 0.2) };
        n += 1;
    }
    return n;
}

/// Wildkin waiting to be met: the nearest eight within 90 m are drawn as characters (ids 24–31),
/// turning to face P1 as they come close; each one within 400 m also raises a beam of light in
/// its accent colour, with a spinning gem over its head, so heroes can be found from afar.
fn publishWildkin(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    var n = start;
    const c = &sb.catalog.content;
    const me = sb.player.feet;
    // The nearest unmet heroes, by squared distance.
    var near: [8]?struct { hero: u8, d2: f32 } = @splat(null);
    for (sb.encounters) |maybe| if (maybe) |spot| if (!sb.progress.hasHero(spot.hero)) {
        const d = R.sub(spot.position, me);
        const d2 = R.dot(d, d);
        if (d2 > 400 * 400) continue;
        if (n + 2 <= out.len) {
            const accent = Profile.accent_colors[Heroes.roster[spot.hero].accent];
            out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(spot.position, .{ 0, 22, 0 }) }, .tint = Material.emissive(.{ accent[0], accent[1], accent[2], 1 }, 0.55 + 0.2 * @sin(t * 2)), .size = .{ 0.22, 40, 0.22 } };
            out[n + 1] = .{ .mesh = c.gem, .transform = .{ .position = R.add(spot.position, .{ 0, 2.7 + 0.15 * @sin(t * 2.5), 0 }) }, .tint = Material.emissive(.{ accent[0], accent[1], accent[2], 1 }, 0.9), .size = @splat(0.5), .rotation = yawQuat(t * 2) };
            n += 2;
        }
        if (d2 > 90 * 90) continue;
        var slot: ?usize = null;
        for (&near, 0..) |entry, k| {
            if (entry == null) {
                slot = k;
                break;
            }
            if (d2 < entry.?.d2 and (slot == null or near[slot.?].?.d2 < entry.?.d2)) slot = k;
        }
        if (slot) |k| near[k] = .{ .hero = spot.hero, .d2 = d2 };
    };
    for (near, 0..) |entry, k| if (entry) |e| if (n < out.len) {
        const spot = sb.encounters[e.hero].?;
        const d = R.sub(me, spot.position);
        const yaw = if (e.d2 < 25 * 25) std.math.atan2(d[0], d[2]) else spot.yaw;
        out[n] = .{ .mesh = .none, .transform = .{ .position = spot.position }, .tint = .{ 1, 1, 1, 1 }, .character = .{
            .profile = Heroes.profile(e.hero),
            .pose = .{ .feet = spot.position, .yaw = yaw, .time = t + @as(f32, @floatFromInt(e.hero)) },
            .id = hero_first_id + @as(u8, @intCast(k)),
        } };
        n += 1;
    };
    return n;
}

/// The ranges' far panorama (not while anyone is underground: it runs under the slopes, through
/// the caves), cave rock near P1, and lumen crystals lighting the chambers.
fn publishMountains(sb: *const Sandbox, out: []World.Prop, start: usize, t: f32) usize {
    const Caves = Sandbox.Caves;
    const c = &sb.catalog.content;
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
    // Four working-looking farmsteads sit on the cityward approach to the mountain paths.
    // Their simple field geometry and outbuildings make the transition from metro to Wilds legible.
    const mountain_count = @import("../procedural/Mountains.zig").count;
    var farm_ranges: [mountain_count]bool = @splat(false);
    for (sb.caves.systems[0..sb.caves.count]) |*sys| {
        if (sys.range >= mountain_count) continue;
        if (farm_ranges[sys.range]) continue;
        const farm: V = R.add(sys.entrance, R.scale(sys.inward, -155));
        const dx = farm[0] - eye[0];
        const dz = farm[2] - eye[2];
        if (dx * dx + dz * dz > 520 * 520) continue;
        farm_ranges[sys.range] = true;
        const yaw = std.math.atan2(-sys.inward[0], -sys.inward[2]);
        const farm_orientation = m.Quat.fromAxisAngle(m.Vec3.unit_y, yaw);
        const rot = quat(farm_orientation);
        const cabin_y = Terrain.surface(sb.seed, farm[0], farm[2]).height;
        if (n < out.len) {
            out[n] = .{ .mesh = c.wilds_cabin, .transform = .{ .position = .{ farm[0], cabin_y, farm[2] } }, .rotation = rot, .tint = .{ 1, 1, 1, 1 } };
            n += 1;
        }
        const barn_offset = farm_orientation.rotate(m.Vec3.init(-24, 0, -7));
        const barn_at = R.add(farm, .{ barn_offset.x, barn_offset.y, barn_offset.z });
        const barn_y = Terrain.surface(sb.seed, barn_at[0], barn_at[2]).height;
        if (n < out.len) {
            out[n] = .{ .mesh = c.wilds_barn, .transform = .{ .position = .{ barn_at[0], barn_y, barn_at[2] } }, .rotation = rot, .tint = .{ 1, 1, 1, 1 } };
            n += 1;
        }
        // Ordered, low crop beds are visible color bands, not collision walls.
        for (0..4) |row| {
            if (n == out.len) break;
            const offset = farm_orientation.rotate(m.Vec3.init(25, 0, -20 + @as(f32, @floatFromInt(row)) * 9));
            const x = farm[0] + offset.x;
            const z = farm[2] + offset.z;
            const y = Terrain.surface(sb.seed, x, z).height;
            out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ x, y + 0.12, z } }, .rotation = rot, .size = .{ 19, 0.24, 5.2 }, .tint = if (row % 2 == 0) .{ 0.22, 0.31, 0.16, 1 } else .{ 0.37, 0.28, 0.13, 1 } };
            n += 1;
        }
    }
    for (sb.caves.systems[0..sb.caves.count], 0..) |*sys, i| {
        var d: f32 = 0;
        for ([_]usize{ 0, 2 }) |a| d = @max(d, @max(sys.lo[a] - eye[a], eye[a] - sys.hi[a]));
        if (d > 320) continue;
        if (n < out.len and i < sb.catalog.cave_meshes.len and !sb.catalog.cave_meshes[i].eql(.none)) {
            out[n] = .{ .mesh = sb.catalog.cave_meshes[i], .transform = .{ .position = .{ 0, 0, 0 } }, .tint = .{ 1, 1, 1, 1 } };
            n += 1;
        }
        // The ancient gate that frames the mouth, visible from afar; its seams glow at dusk.
        if (n < out.len) {
            const yaw = std.math.atan2(sys.inward[0], sys.inward[2]);
            const gate_at = R.add(sys.entrance, R.scale(sys.inward, 1.5));
            // The mouth sits on a flank: lean the gate into the hill by a fraction of the slope: the face is steep,
            // and a full lean lays it along the rock.
            const uphill = Terrain.surface(sb.seed, gate_at[0] + sys.inward[0] * 6, gate_at[2] + sys.inward[2] * 6).height - Terrain.surface(sb.seed, gate_at[0], gate_at[2]).height;
            const lean = std.math.clamp(std.math.atan2(uphill, 6.0) * 0.3, 0, 0.25);
            const gate_facing = m.Quat.fromAxisAngle(m.Vec3.unit_y, yaw).mul(m.Quat.fromAxisAngle(m.Vec3.unit_x, lean));
            const k2 = sys.range == mountain_count;
            out[n] = .{ .mesh = sb.catalog.content.cave_gate, .transform = .{ .position = .{ gate_at[0], gate_at[1] - 0.5, gate_at[2] } }, .rotation = quat(gate_facing), .tint = if (k2) .{ 0.28, 0.46, 0.57, 1 } else .{ 1, 1, 1, 1 } };
            n += 1;
            if (k2 and n + 6 <= out.len) {
                const dark_metal: [4]f32 = .{ 0.12, 0.22, 0.3, 1 };
                const signal = Material.emissive(.{ 0.28, 0.82, 1, 1 }, 1.15);
                for ([_]f32{ -4.4, 4.4 }) |side| {
                    out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(gate_at, .{ side, 4.6, 0 }) }, .size = .{ 0.7, 9.2, 0.8 }, .tint = dark_metal };
                    out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(gate_at, .{ side, 4.6, -0.55 }) }, .size = .{ 0.18, 8.1, 0.12 }, .tint = signal };
                    n += 2;
                }
                out[n] = .{ .mesh = c.block, .transform = .{ .position = R.add(gate_at, .{ 0, 9.1, 0 }) }, .size = .{ 9.4, 0.7, 1 }, .tint = dark_metal };
                out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = R.add(gate_at, .{ 0, 8.5, -0.58 }) }, .size = .{ 7, 0.13, 0.1 }, .tint = signal };
                n += 2;
            }
        }
        if (d > 160) continue;
        // Crystals cluster around each chamber's walls, in the system's hue.
        const hue = Caves.veinHue(@intCast(i));
        for (sys.rooms[0..sys.room_count], 0..) |room, r| {
            if (sys.range == mountain_count and r > 0 and n + 5 <= out.len) {
                const beam_y = room.floor + room.radii[1] * 1.45 - 0.9;
                const post_h = beam_y - room.floor;
                const post_tint: [4]f32 = .{ 0.12, 0.23, 0.31, 1 };
                const signal = Material.emissive(.{ 0.3, 0.78, 1, 1 }, 0.82);
                for ([_]f32{ -room.radii[0] * 0.68, room.radii[0] * 0.68 }) |side| {
                    out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ room.center[0] + side, room.floor + post_h / 2, room.center[2] } }, .size = .{ 0.52, post_h, 0.65 }, .tint = post_tint };
                    out[n + 1] = .{ .mesh = c.block, .transform = .{ .position = .{ room.center[0] + side, room.floor + post_h * 0.55, room.center[2] + 0.38 } }, .size = .{ 0.12, post_h * 0.48, 0.1 }, .tint = signal };
                    n += 2;
                }
                if (n < out.len) {
                    out[n] = .{ .mesh = c.block, .transform = .{ .position = .{ room.center[0], beam_y, room.center[2] } }, .size = .{ room.radii[0] * 1.5, 0.38, 0.7 }, .tint = post_tint };
                    n += 1;
                }
            }
            if (room.role == .cache and n + 2 <= out.len) {
                const parent = sys.rooms[room.parent];
                const toward = R.sub(parent.center, room.center);
                const orientation = m.Quat.fromAxisAngle(m.Vec3.unit_y, std.math.atan2(toward[0], toward[2]));
                const shrine_at: V = .{ room.center[0], room.floor, room.center[2] };
                const temple_scale: f32 = 0.66;
                out[n] = .{ .mesh = sb.catalog.content.cave_temple, .transform = .{ .position = shrine_at }, .size = .{ temple_scale, temple_scale, temple_scale }, .rotation = quat(orientation), .tint = .{ 1, 1, 1, 1 } };
                n += 1;
                // The signal gem hovers over the temple's crown, turning slowly.
                const gem_offset = orientation.rotate(WildsMeshes.temple_crown.scale(temple_scale).add(m.Vec3.init(0, 0.9, 0)));
                const gem_at = R.add(shrine_at, .{ gem_offset.x, gem_offset.y, gem_offset.z });
                out[n] = .{ .mesh = sb.catalog.content.gem, .transform = .{ .position = gem_at }, .size = .{ 0.8, 1.4, 0.8 }, .rotation = quat(m.Quat.fromAxisAngle(m.Vec3.unit_y, t * 0.4)), .tint = Material.emissive(hue ++ [_]f32{1}, 0.9 + 0.1 * @sin(t * 1.3 + @as(f32, @floatFromInt(r)))) };
                n += 1;
            }
            // A carved doorway where the tunnel from the parent chamber opens into this one, and a
            // collapsed lab in each hall.
            if (r > 0 and n + 4 <= out.len) {
                const parent = sys.rooms[room.parent];
                const dx = room.center[0] - parent.center[0];
                const dz = room.center[2] - parent.center[2];
                const dist = @sqrt(dx * dx + dz * dz);
                const dir_x = dx / dist;
                const dir_z = dz / dist;
                // Where the tunnel meets this chamber's wall, along the ellipse's radius that way.
                const reach = 1 / @sqrt((dir_x / room.radii[0]) * (dir_x / room.radii[0]) + (dir_z / room.radii[2]) * (dir_z / room.radii[2]));
                const back = reach * 0.9;
                const floor = room.floor + (parent.floor - room.floor) * std.math.clamp(back / dist, 0, 1);
                out[n] = .{ .mesh = sb.catalog.content.cave_arch, .transform = .{ .position = .{ room.center[0] - dir_x * back, floor, room.center[2] - dir_z * back } }, .rotation = yawQuat(std.math.atan2(dir_x, dir_z)), .tint = .{ 1, 1, 1, 1 } };
                n += 1;
            }
            if (room.role == .hall and n + 3 <= out.len) for (0..2) |k| {
                const spot = Caves.floorSpot(sys, @intCast(r), k, 2, 0.5);
                out[n] = .{ .mesh = sb.catalog.content.cave_ruin, .transform = .{ .position = .{ spot[0], spot[1], spot[2] } }, .rotation = yawQuat(@as(f32, @floatFromInt(r * 3 + k)) * 1.9), .tint = .{ 1, 1, 1, 1 } };
                n += 1;
            };
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
    return publishCloudwater(sb, out, n, t);
}

/// Hive troopers: dark red heavy plate, sealed helmets, magenta lumen.
const trooper_profile: @import("Profile.zig") = .{ .outfit = 3, .clothing = .vanguard, .armor = .sentinel, .helmet = .sealed, .accent = 2, .skin = 7, .build = 1.1, .height = 1.05 };
const skirmisher_profile: @import("Profile.zig") = .{ .outfit = 7, .clothing = .exo_rig, .armor = .scout, .helmet = .visor, .accent = 3, .skin = 7, .build = 0.92, .height = 0.96 };
const bulwark_profile: @import("Profile.zig") = .{ .outfit = 5, .clothing = .vanguard, .armor = .sentinel, .helmet = .sealed, .accent = 1, .skin = 7, .build = 1.18, .height = 1.15 };
const foundry_steward_profile: Profile = .{ .outfit = 5, .clothing = .field_jacket, .armor = .none, .helmet = .open, .accent = 1, .skin = 2, .hair_style = .side_part, .hair_color = 5, .build = 1.08, .height = 1.08 };
const scalari_scout_profile: @import("Profile.zig") = .{ .outfit = 6, .clothing = .exo_rig, .armor = .scout, .helmet = .visor, .accent = 4, .skin = 5, .build = 0.7, .height = 0.78 };
const scalari_stinger_profile: @import("Profile.zig") = .{ .outfit = 4, .clothing = .hardsuit, .armor = .sentinel, .helmet = .sealed, .accent = 4, .skin = 6, .build = 0.95, .height = 1.05 };
const scalari_titan_profile: @import("Profile.zig") = .{ .outfit = 5, .clothing = .vanguard, .armor = .sentinel, .helmet = .sealed, .accent = 4, .skin = 4, .build = 2.7, .height = 4.8 };
const scalari_hybrid_profile: @import("Profile.zig") = .{ .outfit = 6, .clothing = .exo_rig, .armor = .sentinel, .helmet = .sealed, .accent = 3, .skin = 6, .build = 1.15, .height = 1.2 };

/// Transformer-scale Scalari siege frame assembled from independent armor modules. Its palette
/// and part selections are shared with the Character Designer's Hive Forge panel.
fn scalariTitan(out: []World.Prop, block: @import("../asset/Catalog.zig").MeshHandle, orb: @import("../asset/Catalog.zig").MeshHandle, spike: @import("../asset/Catalog.zig").MeshHandle, gem_mesh: @import("../asset/Catalog.zig").MeshHandle, at: V, yaw: f32, t: f32, flash: f32, design: EnemyDesign.Design) usize {
    const palette = EnemyDesign.colors[@intFromEnum(design.palette)];
    const frame = EnemyDesign.module(.frame, design.frame);
    const shoulders = EnemyDesign.module(.shoulders, design.shoulders);
    const arms = EnemyDesign.module(.arms, design.arms);
    const legs = EnemyDesign.module(.legs, design.legs);
    const back = EnemyDesign.module(.back_unit, design.back_unit);
    const head = EnemyDesign.module(.head, design.head);
    const weapon = EnemyDesign.module(.weapon, design.weapon);
    const hot = 0.65 + 0.35 * @sin(t * 3.2);
    const armor = if (flash > 0) [4]f32{ 1.7, 1.3, 1.3, 1 } else palette.armor;
    const accent_color = if (flash > 0) [4]f32{ 1.7, 1.3, 1.3, 1 } else palette.accent;
    const orientation = yawQuat(yaw);
    const scale = frame.scale * 1.2;
    var n: usize = 0;
    out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ 0, 2.45, 0 }) }, .tint = armor, .size = .{ 2.6 * scale, 2.3, 1.6 }, .rotation = orientation };
    n += 1;
    // Heavy armor plates around the shared powered core.
    out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ 0, 3.35, 0.76 }) }, .tint = accent_color, .size = .{ 2.1 * scale, 1.05, 0.18 }, .rotation = orientation };
    n += 1;
    out[n] = .{ .mesh = gem_mesh, .transform = .{ .position = R.add(at, .{ 0, 3.45, 0.91 }) }, .tint = Material.emissive(palette.glow, hot), .size = .{ 0.58, 0.7, 0.16 }, .rotation = orientation };
    n += 1;
    out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ 0, 1.35, 0 }) }, .tint = armor, .size = .{ 1.65 * scale, 0.95, 1.25 }, .rotation = orientation };
    n += 1;
    const leg_w: f32 = if (design.legs == 2) 0.82 else 0.57;
    for ([_]f32{ -1, 1 }) |side| {
        out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ side * 0.67, 0.55, 0 }) }, .tint = armor, .size = .{ leg_w * legs.scale, 1.1, 1.25 * legs.scale }, .rotation = orientation };
        n += 1;
        out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ side * 0.67, 1.35, 0 }) }, .tint = accent_color, .size = .{ 0.68 * legs.scale, 0.64, 0.9 }, .rotation = orientation };
        n += 1;
    }
    const shoulder_w: f32 = if (design.shoulders == 1) 0.95 else if (design.shoulders == 2) 0.78 else 0.68;
    for ([_]f32{ -1, 1 }) |side| {
        out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ side * (1.24 + shoulder_w * (shoulders.scale - 1)), 3.85, 0 }) }, .tint = accent_color, .size = .{ shoulder_w * shoulders.scale, 1.05, 1.35 }, .rotation = orientation };
        n += 1;
        out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ side * 1.47, 2.7, 0.06 }) }, .tint = armor, .size = .{ 0.53 * arms.scale, 1.25, 0.64 * arms.scale }, .rotation = orientation };
        n += 1;
        out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ side * 1.47, 1.95, 0.2 }) }, .tint = accent_color, .size = .{ 0.67 * arms.scale, 0.55 * arms.scale, 0.76 }, .rotation = orientation };
        n += 1;
    }
    out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ 0, 3.2, -0.91 }) }, .tint = armor, .size = .{ 1.25 * back.scale, 1.7, 0.5 }, .rotation = orientation };
    n += 1;
    const wing = design.back_unit == 1;
    for ([_]f32{ -1, 1 }) |side| {
        out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ side * (if (wing) @as(f32, 1.35) else 0.62), 3.25, -1.12 }) }, .tint = accent_color, .size = .{ if (wing) @as(f32, 0.5) else 0.37, if (wing) @as(f32, 1.9) else 0.95, 0.38 }, .rotation = orientation };
        n += 1;
    }
    // Head and sensor crown cap the silhouette; modular variants change its apparent mass.
    out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ 0, 4.75, 0 }) }, .tint = accent_color, .size = .{ 0.85 * head.scale, 1.02 * head.scale, 0.83 }, .rotation = orientation };
    n += 1;
    out[n] = .{ .mesh = gem_mesh, .transform = .{ .position = R.add(at, .{ 0, 4.7, 0.46 }) }, .tint = Material.emissive(palette.glow, hot * 1.2), .size = .{ 0.56, 0.2, 0.12 }, .rotation = orientation };
    n += 1;
    // Distinct heavy armament gives each frame a recognizable attack silhouette.
    const weapon_x: f32 = if (design.arms == 2) 1.72 else 1.48;
    out[n] = .{ .mesh = block, .transform = .{ .position = R.add(at, .{ weapon_x, 2.05, 0.82 }) }, .tint = if (design.weapon == 1) palette.glow else accent_color, .size = .{ if (design.weapon == 2) @as(f32, 0.26) else 0.42, if (design.weapon == 2) @as(f32, 1.45) else 0.5, weapon.scale * 1.2 }, .rotation = orientation };
    n += 1;

    switch (design.layer_style) {
        .brushed_metal => {
            // Dark, rounded bearing housings break up the plate masses; exposed bright struts
            // make the layered shells read as machined armor on a moving frame.
            for ([8]V{
                .{ -1.18, 3.82, 0.18 }, .{ 1.18, 3.82, 0.18 },
                .{ -1.47, 2.52, 0.28 }, .{ 1.47, 2.52, 0.28 },
                .{ -0.67, 1.34, 0.23 }, .{ 0.67, 1.34, 0.23 },
                .{ -0.67, 0.72, 0.24 }, .{ 0.67, 0.72, 0.24 },
            }) |joint| titanLayer(out, &n, orb, at, joint, .{ 0.42, 0.42, 0.42 }, orientation, palette.joint);
            for ([4]struct { at: V, size: V }{
                .{ .at = .{ -1.35, 2.85, 0.35 }, .size = .{ 0.18, 0.62, 0.2 } },
                .{ .at = .{ 1.35, 2.85, 0.35 }, .size = .{ 0.18, 0.62, 0.2 } },
                .{ .at = .{ -0.67, 1.05, 0.38 }, .size = .{ 0.17, 0.52, 0.16 } },
                .{ .at = .{ 0.67, 1.05, 0.38 }, .size = .{ 0.17, 0.52, 0.16 } },
            }) |strut| titanLayer(out, &n, block, at, strut.at, strut.size, orientation, palette.trim);
            titanLayer(out, &n, orb, at, .{ 0, 3.32, 0.83 }, .{ 1.72, 0.72, 0.22 }, orientation, palette.accent);
        },
        .insectoid_carapace => {
            // Smooth overlapping plates, a segmented abdomen, compound optics and tapered
            // antennae give the siege chassis an engineered insect silhouette.
            titanLayer(out, &n, orb, at, .{ 0, 4.18, 0.12 }, .{ 0.56, 0.62, 0.56 }, orientation, palette.joint);
            titanLayer(out, &n, orb, at, .{ 0, 3.30, 1.34 }, .{ 1.48, 1.32, 0.62 }, orientation, palette.accent);
            titanLayer(out, &n, orb, at, .{ -0.63, 3.43, 1.17 }, .{ 0.54, 0.87, 0.46 }, orientation, palette.trim);
            titanLayer(out, &n, orb, at, .{ 0.63, 3.43, 1.17 }, .{ 0.54, 0.87, 0.46 }, orientation, palette.trim);
            for (0..3) |segment| {
                const y = 2.28 - @as(f32, @floatFromInt(segment)) * 0.32;
                const segment_color = if (segment == 1) palette.trim else palette.accent;
                titanLayer(out, &n, orb, at, .{ 0, y, 0.94 }, .{ 1.20 - @as(f32, @floatFromInt(segment)) * 0.12, 0.31, 0.40 }, orientation, segment_color);
            }
            for ([_]f32{ -1, 1 }) |side| {
                titanLayer(out, &n, orb, at, .{ side * 1.15, 3.84, 0.84 }, .{ 0.92, 1.02, 0.68 }, orientation, palette.accent);
                titanLayer(out, &n, orb, at, .{ side * 1.47, 2.53, 0.64 }, .{ 0.68, 0.82, 0.54 }, orientation, palette.accent);
                titanLayer(out, &n, orb, at, .{ side * 0.53, 3.35, -1.26 }, .{ 0.68, 1.28, 0.38 }, orientation, palette.armor);
                titanLayer(out, &n, spike, at, .{ side * 0.30, 5.20, 0.02 }, .{ 0.20, 0.64, 0.20 }, orientation, palette.trim);
                titanLayer(out, &n, spike, at, .{ side * 1.62, 1.82, 0.58 }, .{ 0.20, 0.48, 0.18 }, orientation, palette.trim);
            }
            for ([_]f32{ -0.24, 0, 0.24 }) |eye_x| titanLayer(out, &n, orb, at, .{ eye_x, 4.78, 0.53 }, .{ 0.16, 0.14, 0.11 }, orientation, palette.glow);
        },
    }
    return n;
}

fn titanLayer(out: []World.Prop, count: *usize, mesh: @import("../asset/Catalog.zig").MeshHandle, origin: V, offset: V, size: V, rotation: [4]f32, tint: [4]f32) void {
    if (count.* >= out.len) return;
    out[count.*] = .{ .mesh = mesh, .transform = .{ .position = R.add(origin, offset) }, .tint = tint, .size = size, .rotation = rotation };
    count.* += 1;
}

/// Isolated art-review frame used by the metal and carapace showcases.
pub fn publishTitanPreview(sb: *const Sandbox, out: []World.Prop, at: V, yaw: f32) usize {
    return scalariTitan(out, sb.catalog.content.block, sb.catalog.content.orb, sb.catalog.content.spike, sb.catalog.content.gem, at, yaw, @as(f32, @floatFromInt(sb.tick)) / 60, 0, sb.creator.enemy_design);
}

test "Detroit Titan opens after the frontier, runs three phases, rewards the party, and frees the city" {
    var catalog: @import("../asset/Catalog.zig") = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try Sandbox.testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();

    for (sb.enemies.nests[0..sb.enemies.nest_count]) |*nest| nest.alive = false;
    for (&sb.skies.carriers) |*carrier| carrier.alive = false;
    for ([_][]const u8{ "met_tavi", "tavi_scouted", "first_spire_broken", "ines_sap_warned", "carrier_seen", "kestrel_blueprint" }) |flag| sb.progress.setFlag(flag);
    sb.progress.fighter = true;
    for (CityContent.detroit.missions) |mission| sb.progress.setFlag(mission.exposed_flag);
    sb.joinGuest(0);
    const arena = WindsorCase.titanPosition(sb.seed);
    sb.player.feet = arena;
    sb.guests[0].player.feet = arena;
    sb.enemies.nests[0].alive = true;
    sb.enemies.nests[0].position = R.add(arena, .{ 300, 0, 0 });
    const frontier_target = objectiveTarget(&sb) orelse return error.TestUnexpectedResult;
    try std.testing.expect(R.length(R.sub(frontier_target, arena)) > 100);
    ensureCityTitanEncounter(&sb);
    try std.testing.expect(!CityContent.bossStarted(&CityContent.detroit, &sb.progress));
    sb.enemies.nests[0].alive = false;
    sb.skies.carriers[0].alive = true;
    ensureCityTitanEncounter(&sb);
    try std.testing.expect(!CityContent.bossStarted(&CityContent.detroit, &sb.progress));
    sb.skies.carriers[0].alive = false;
    ensureCityTitanEncounter(&sb);
    try std.testing.expect(CityContent.bossStarted(&CityContent.detroit, &sb.progress));
    try std.testing.expectEqual(@as(usize, 1), sb.enemies.unitCount(Enemies.foundry_nest));

    var titan: ?*Enemies.Unit = null;
    for (&sb.enemies.units) |*slot| if (slot.*) |*unit| if (unit.kind == .scalari_titan and unit.nest == Enemies.foundry_nest) {
        titan = unit;
        break;
    };
    const boss = titan orelse return error.TestUnexpectedResult;
    const max_health = Enemies.stats(.scalari_titan).health * 2.5;
    boss.health = max_health * 0.65;
    ensureCityTitanEncounter(&sb);
    try std.testing.expectEqual(@as(u8, 2), sb.city_titan_phase);
    try std.testing.expectEqual(@as(usize, 4), sb.enemies.unitCount(Enemies.foundry_nest));
    boss.health = max_health * 0.32;
    ensureCityTitanEncounter(&sb);
    try std.testing.expectEqual(@as(u8, 3), sb.city_titan_phase);
    try std.testing.expect(boss.stun > 2.7);

    const p1_xp = sb.kits[0].combat_xp;
    const p2_xp = sb.kits[1].combat_xp;
    const p1_parts = sb.kits[0].wallet.parts;
    const p2_parts = sb.kits[1].wallet.parts;
    var siege_props: [32]World.Prop = undefined;
    const siege_count = publishCityHiveBases(&sb, &siege_props, 0, 0);
    try std.testing.expect(siege_props[0].mesh.eql(sb.catalog.content.hive_base));
    sb.enemies.units = @splat(null);
    hive(&sb, .{ .unit_down = .{ .kind = .scalari_titan, .nest = Enemies.foundry_nest, .position = arena } }, &camera);
    try std.testing.expect(CityContent.bossDefeated(&CityContent.detroit, &sb.progress));
    try std.testing.expect(CityContent.liberated(&CityContent.detroit, &sb.progress));
    var liberated_props: [32]World.Prop = undefined;
    const liberated_count = publishCityHiveBases(&sb, &liberated_props, 0, 0);
    try std.testing.expect(liberated_count > siege_count);
    try std.testing.expect(liberated_props[0].mesh.eql(sb.catalog.content.block));
    try std.testing.expect(liberated_props[1].mesh.eql(sb.catalog.content.gem));
    try std.testing.expect(liberated_props[2].mesh.eql(sb.catalog.content.flora[7]));
    try std.testing.expect(liberated_props[3].mesh.eql(sb.catalog.content.flora[9]));
    try std.testing.expectEqual(p1_xp + 1200, sb.kits[0].combat_xp);
    try std.testing.expectEqual(p2_xp + 1200, sb.kits[1].combat_xp);
    try std.testing.expectEqual(p1_parts + 18, sb.kits[0].wallet.parts);
    try std.testing.expectEqual(p2_parts + 18, sb.kits[1].wallet.parts);
    try std.testing.expectEqual(@as(u32, 2), sb.kits[0].count(.rotor_core));
    try std.testing.expectEqual(@as(u32, 2), sb.kits[1].count(.rotor_core));
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
