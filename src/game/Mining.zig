//! Ore veins and the work that turns them into the colony's stockpile: glowing veins seeded around
//! the spawn, hand mining (hands tool, interact) and the plasma cutter (key 8, hold fire, overheats)
//! into each player's own `Kit`, depositing at a store structure, and what the placed structures
//! add up to each settlement hour for `Colony`. Bounded, no allocation, runs in the fixed step.
//! See docs/plans/colony-mining-research.md.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Time = @import("../engine/Time.zig");
const Camera = @import("../world/Camera.zig");
const Structures = @import("../build/Structures.zig");
const Colony = @import("Colony.zig");
const Defense = @import("Defense.zig");
const Specials = @import("Specials.zig");
const Sandbox = @import("Sandbox.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;

pub const vein_count = 24;
/// Veins lie in a ring around the spawn, this near and far.
pub const ring_inner: f32 = 30;
pub const ring_outer: f32 = 420;
/// How close a vein's centre must be to a ray to be aimed at.
pub const vein_radius: f32 = 1.3;
pub const hand_reach: f32 = 4.5;
pub const cutter_reach: f32 = 14;
/// Seconds between ore by hand, and ore per second from the cutter.
pub const hand_cooldown: f32 = 0.6;
pub const cutter_rate: f32 = 4;
/// Cutter heat gained per second of firing and lost per second at rest; at 1 it locks out until
/// it cools below `cutter_vented`.
pub const cutter_heating: f32 = 0.22;
pub const cutter_cooling: f32 = 0.35;
pub const cutter_vented: f32 = 0.3;
/// How near a store a player stands to deposit.
pub const deposit_reach: f32 = 7;

pub const Vein = struct { position: V, ore: Colony.Ore };

pub const State = struct {
    /// The home field around the spawn, then the field of the landing the team is visiting
    /// (`local`). The home field never moves, so drill stations built on it keep their veins
    /// wherever the players are.
    veins: [2 * vein_count]Vein = undefined,
    local: bool = false,
    colony: Colony.State = .{},
    cooldown: [Sandbox.max_players]f32 = @splat(0),
    heat: [Sandbox.max_players]f32 = @splat(0),
    overheated: [Sandbox.max_players]bool = @splat(false),
    cutting: [Sandbox.max_players]f32 = @splat(0),
    /// Whether the cutter fired this step (for the beam and the hint).
    firing: [Sandbox.max_players]bool = @splat(false),
    beam_tick: u32 = 0,

    /// The veins in play: home, then the visited landing's.
    pub fn active(self: *const State) []const Vein {
        return self.veins[0 .. if (self.local) 2 * vein_count else vein_count];
    }

    /// Players arrived at `center`: far from home, its landing gets its own field beside home's.
    pub fn land(self: *State, seed: u64, center: [2]f32) void {
        const dx = center[0] - Sandbox.spawn[0];
        const dz = center[1] - Sandbox.spawn[2];
        self.local = dx * dx + dz * dz > 4 * ring_outer * ring_outer;
        if (self.local) generateAround(seed, center, self.veins[vein_count..]);
    }
};

/// The seeded veins: half iron, a third copper, the rest lumen crystal, which lies farther out.
/// The home field keeps the seeding it shipped with: saved drill stations stand on these veins.
pub fn generate(seed: u64, out: *[vein_count]Vein) void {
    field(seed, seed ^ 0x6f72_6576_6569_6e73, .{ Sandbox.spawn[0], Sandbox.spawn[2] }, out);
}

/// Stable local ore field for a landing region. Each visit produces the same deposits so
/// fast travel can keep the ore in the player's immediate terrain rather than at Earth's base.
pub fn generateAround(seed: u64, center: [2]f32, out: *[vein_count]Vein) void {
    const center_x: u32 = @bitCast(center[0]);
    const center_z: u32 = @bitCast(center[1]);
    const location_seed = seed ^ @as(u64, center_x) ^ (@as(u64, center_z) << 32);
    field(seed, location_seed ^ 0x6f72_6576_6569_6e73, center, out);
}

fn field(seed: u64, field_seed: u64, center: [2]f32, out: *[vein_count]Vein) void {
    var prng = std.Random.DefaultPrng.init(field_seed);
    const rand = prng.random();
    for (out, 0..) |*v, i| {
        const ore: Colony.Ore = if (i % 6 < 3) .iron else if (i % 6 < 5) .copper else .crystal;
        const lo: f32 = if (ore == .crystal) 180 else ring_inner;
        const angle = (@as(f32, @floatFromInt(i)) + rand.float(f32) * 0.8) * (2 * std.math.pi / @as(f32, vein_count));
        const dist = lo + rand.float(f32) * (ring_outer - lo);
        const x = center[0] + @cos(angle) * dist;
        const z = center[1] + @sin(angle) * dist;
        v.* = .{ .position = .{ x, Terrain.surface(seed, x, z).height, z }, .ore = ore };
    }
}

/// The vein a ray from `origin` along `dir` (unit) meets within `reach`, nearest first.
pub fn aimed(veins: []const Vein, origin: V, dir: V, reach: f32) ?usize {
    var best: ?usize = null;
    var best_t = reach;
    for (veins, 0..) |v, i| {
        const c = R.add(v.position, .{ 0, 0.6, 0 });
        const t = R.dot(R.sub(c, origin), dir);
        if (t < 0 or t > best_t) continue;
        const off = R.sub(c, R.add(origin, R.scale(dir, t)));
        if (R.dot(off, off) > vein_radius * vein_radius) continue;
        best = i;
        best_t = t;
    }
    return best;
}

fn eyeRay(camera: Camera) [2]V {
    const f = camera.forward();
    return .{ .{ camera.position.x(), camera.position.y(), camera.position.z() }, .{ f.x(), f.y(), f.z() } };
}

fn give(sb: *Sandbox, slot: usize, vein: Vein) void {
    sb.kits[slot].ore[@intFromEnum(vein.ore)] += 1;
    sb.sayTo(slot, "+1 {s} ore ({d} held)", .{ Colony.oreName(vein.ore), sb.kits[slot].ore[@intFromEnum(vein.ore)] });
}

/// Hands tool, interact with nothing else aimed: mine the aimed vein, else deposit at a near store,
/// else pick the next research at a near lab. Returns whether it did any.
pub fn interact(sb: *Sandbox, slot: usize, camera: Camera) bool {
    return mineAimed(sb, slot, camera) or depositNear(sb, slot) or chooseResearch(sb, slot);
}

/// Mine the vein aimed at within hand reach. Veins have no collider, so the caller asks this
/// before acting on whatever the aim ray hit behind the vein.
pub fn mineAimed(sb: *Sandbox, slot: usize, camera: Camera) bool {
    const s = &sb.mining;
    const ray = eyeRay(camera);
    const i = aimed(s.active(), ray[0], ray[1], hand_reach) orelse return false;
    if (s.cooldown[slot] > 0) return true;
    s.cooldown[slot] = hand_cooldown;
    give(sb, slot, s.veins[i]);
    return true;
}

/// Standing by a research lab, interact cycles what the colony researches.
pub fn chooseResearch(sb: *Sandbox, slot: usize) bool {
    if (!nearModule(sb, slot, .lab)) return false;
    const colony = &sb.mining.colony;
    colony.nextTarget();
    if (colony.current()) |t| {
        const need = Colony.info(t);
        sb.sayTo(slot, "researching {s} ({d} points, {d} iron {d} copper {d} crystal): {s}", .{ need.name, need.points, need.ore[0], need.ore[1], need.ore[2], need.gives });
    } else sb.sayTo(slot, "all research is done", .{});
    return true;
}

fn nearModule(sb: *const Sandbox, slot: usize, kind: Structures.Kind) bool {
    const feet = sb.feetOf(slot);
    for (sb.outpost.slice()) |*inst| {
        const def = Defense.defOf(sb, inst) orelse continue;
        if (def.find(kind) == null) continue;
        const d = R.sub(Defense.centre(Defense.boxOf(inst, def)), feet);
        if (d[0] * d[0] + d[2] * d[2] <= deposit_reach * deposit_reach) return true;
    }
    return false;
}

/// Put everything the player holds into the stockpile when they stand by a store.
pub fn depositNear(sb: *Sandbox, slot: usize) bool {
    const feet = sb.feetOf(slot);
    for (sb.outpost.slice()) |*inst| {
        const def = Defense.defOf(sb, inst) orelse continue;
        if (def.find(.store) == null) continue;
        const c = Defense.centre(Defense.boxOf(inst, def));
        const d = R.sub(c, feet);
        if (d[0] * d[0] + d[2] * d[2] > deposit_reach * deposit_reach) continue;
        const moved = Colony.deposit(&st(sb).colony, &sb.kits[slot].ore);
        if (moved == 0) {
            sb.sayTo(slot, "{s}: nothing to deposit; mine ore veins first", .{def.name()});
        } else sb.sayTo(slot, "deposited {d} ore at the {s}", .{ moved, def.name() });
        return true;
    }
    return false;
}

fn st(sb: *Sandbox) *State {
    return &sb.mining;
}

/// The plasma cutter tool (P1): a beam while fire is held, mining what it touches; heat locks it.
pub fn cutterUpdate(sb: *Sandbox, camera: Camera, _: bool, _: Sandbox.Actions) anyerror!void {
    const s = st(sb);
    const slot: usize = 0;
    s.firing[slot] = false;
    if (!s.colony.has(.plasma_cutter)) {
        if (sb.trigger.fire and s.cooldown[slot] <= 0) {
            s.cooldown[slot] = 2;
            sb.sayTo(slot, "the plasma cutter needs PLASMA CUTTING research (build a research lab)", .{});
        }
        return;
    }
    if (!sb.trigger.fire or s.overheated[slot]) return;
    s.firing[slot] = true;
    const ray = eyeRay(camera);
    const muzzle = R.add(ray[0], R.add(R.scale(ray[1], 0.6), .{ 0, -0.25, 0 }));
    var length = cutter_reach;
    if (aimed(s.active(), ray[0], ray[1], cutter_reach)) |i| {
        const v = s.veins[i];
        length = R.length(R.sub(R.add(v.position, .{ 0, 0.6, 0 }), muzzle));
        s.cutting[slot] += Time.fixed_dt * cutter_rate;
        if (s.cutting[slot] >= 1) {
            s.cutting[slot] -= 1;
            give(sb, slot, v);
        }
    }
    s.beam_tick +%= 1;
    if (s.beam_tick % 3 == 0) Specials.effect(&sb.combat, .{ .kind = .beam, .position = muzzle, .dir = ray[1], .life = 0.06, .size = 0.12, .length = length, .color = .{ 1, 0.55, 0.2 } });
}

/// Timers, heat and the colony's hour; call once per fixed step.
pub fn step(sb: *Sandbox, dt: f32) void {
    const s = st(sb);
    for (0..Sandbox.max_players) |p| {
        s.cooldown[p] = @max(0, s.cooldown[p] - dt);
        if (s.firing[p]) {
            s.heat[p] = @min(1, s.heat[p] + cutter_heating * dt);
            if (s.heat[p] >= 1) {
                s.overheated[p] = true;
                sb.sayTo(p, "plasma cutter overheated: venting", .{});
            }
        } else s.heat[p] = @max(0, s.heat[p] - cutter_cooling * dt);
        if (s.overheated[p] and s.heat[p] < cutter_vented) s.overheated[p] = false;
        s.firing[p] = false;
    }
    var report: Colony.Report = .{};
    if (Colony.advance(&s.colony, dt, colonyInputs(sb), &report) > 0) {
        if (report.finished) |t| sb.say("research complete: {s}, {s}", .{ Colony.info(t).name, Colony.info(t).gives });
        if (report.left > 0) sb.say("{d} settlers left the colony (no food or beds)", .{report.left});
    }
}

/// The vein a drill at `at` reaches with `range` metres of search, if any.
pub fn veinUnder(veins: []const Vein, at: V, range: f32) ?usize {
    var best: ?usize = null;
    var best_d = range * range;
    for (veins, 0..) |v, i| {
        const d = R.sub(v.position, at);
        if (@abs(d[1]) > 8) continue;
        const flat = d[0] * d[0] + d[2] * d[2];
        if (flat <= best_d) {
            best = i;
            best_d = flat;
        }
    }
    return best;
}

/// Field food per hour per square metre of radius and growth multiplier.
pub const field_food_per: f32 = 0.2;

/// What the placed structures add up to this hour, scaled by power.
pub fn colonyInputs(sb: *const Sandbox) Colony.Inputs {
    var in: Colony.Inputs = .{};
    const satisfaction = Defense.powerSatisfaction(sb);
    for (sb.outpost.slice()) |*inst| {
        const def = Defense.defOf(sb, inst) orelse continue;
        const box = Defense.boxOf(inst, def);
        for (def.moduleSlice()) |m| {
            const work: f32 = if (m.power > 0) satisfaction else 1;
            switch (m.kind) {
                .drill => {
                    const base: V = .{ (box.lo[0] + box.hi[0]) / 2, box.lo[1], (box.lo[2] + box.hi[2]) / 2 };
                    const reach = m.range + @max(box.hi[0] - box.lo[0], box.hi[2] - box.lo[2]) / 2;
                    if (veinUnder(sb.mining.active(), base, reach)) |i| in.drilled[@intFromEnum(sb.mining.veins[i].ore)] += m.rate * work;
                },
                .field => in.food += m.range * m.rate * field_food_per * work,
                .housing => in.beds += @intFromFloat(m.amount),
                .lab => in.research += m.rate * work,
                .launch => if (work >= 0.5) {
                    in.pads += 1;
                },
                else => {},
            }
        }
    }
    return in;
}

/// The drill's status for its builder: which vein it reaches.
pub fn drillVein(sb: *const Sandbox, inst: *const @import("Outpost.zig").Instance) ?Vein {
    const def = Defense.defOf(sb, inst) orelse return null;
    const m = def.find(.drill) orelse return null;
    const box = Defense.boxOf(inst, def);
    const base: V = .{ (box.lo[0] + box.hi[0]) / 2, box.lo[1], (box.lo[2] + box.hi[2]) / 2 };
    const reach = m.range + @max(box.hi[0] - box.lo[0], box.hi[2] - box.lo[2]) / 2;
    const i = veinUnder(sb.mining.active(), base, reach) orelse return null;
    return sb.mining.veins[i];
}

/// The cutter's hint line.
pub fn cutterHint(sb: *const Sandbox, buf: []u8) []const u8 {
    const s = &sb.mining;
    if (!s.colony.has(.plasma_cutter)) return "PLASMA CUTTER: research PLASMA CUTTING at a research lab first";
    const heat: u32 = @intFromFloat(@round(s.heat[0] * 100));
    if (s.overheated[0]) return std.fmt.bufPrint(buf, "PLASMA CUTTER VENTING {d}%", .{heat}) catch "";
    return std.fmt.bufPrint(buf, "PLASMA CUTTER heat {d}%  hold fire on an ore vein", .{heat}) catch "";
}

test "veins are seeded, deterministic, inside the ring, and crystal lies farther out" {
    var a: [vein_count]Vein = undefined;
    var b: [vein_count]Vein = undefined;
    generate(42, &a);
    generate(42, &b);
    var kinds: [Colony.ore_count]u32 = @splat(0);
    for (a, b) |va, vb| {
        try std.testing.expectEqual(va.position, vb.position);
        const dx = va.position[0] - Sandbox.spawn[0];
        const dz = va.position[2] - Sandbox.spawn[2];
        const d = @sqrt(dx * dx + dz * dz);
        try std.testing.expect(d >= ring_inner - 0.01 and d <= ring_outer + 0.01);
        if (va.ore == .crystal) try std.testing.expect(d >= 180 - 0.01);
        kinds[@intFromEnum(va.ore)] += 1;
    }
    try std.testing.expectEqual([Colony.ore_count]u32{ 12, 8, 4 }, kinds);
}

test "each landing gets a stable local ore field centered on its terrain" {
    const Region = @import("../world/Region.zig");
    var a: [vein_count]Vein = undefined;
    var b: [vein_count]Vein = undefined;
    generateAround(42, Region.moon.arrival, &a);
    generateAround(42, Region.moon.arrival, &b);
    for (a, b) |va, vb| {
        try std.testing.expectEqual(va.position, vb.position);
        const dx = va.position[0] - Region.moon.arrival[0];
        const dz = va.position[2] - Region.moon.arrival[1];
        const distance = @sqrt(dx * dx + dz * dz);
        try std.testing.expect(distance >= ring_inner and distance <= ring_outer);
        try std.testing.expectApproxEqAbs(Terrain.surface(42, va.position[0], va.position[2]).height, va.position[1], 0.001);
    }
}

test "landing far away adds a local field and leaves the home veins, and their drills, where they were" {
    const Region = @import("../world/Region.zig");
    var s: State = .{};
    generate(42, s.veins[0..vein_count]);
    const home = s.veins[0..vein_count].*;
    try std.testing.expectEqual(@as(usize, vein_count), s.active().len);
    s.land(42, Region.moon.arrival);
    try std.testing.expect(s.local);
    try std.testing.expectEqual(@as(usize, 2 * vein_count), s.active().len);
    try std.testing.expectEqualSlices(Vein, &home, s.active()[0..vein_count]);
    // A drill on a home vein still reaches it while the team is on the Moon.
    try std.testing.expectEqual(@as(?usize, 3), veinUnder(s.active(), home[3].position, 2));
    // Back home (or a load near the spawn): only the home field.
    s.land(42, .{ Sandbox.spawn[0] + 50, Sandbox.spawn[2] });
    try std.testing.expect(!s.local);
    try std.testing.expectEqualSlices(Vein, &home, s.active());
}

test "a ray picks the nearest vein it passes close to, within reach" {
    const veins = [_]Vein{
        .{ .position = .{ 0, 0, 10 }, .ore = .iron },
        .{ .position = .{ 0, 0, 5 }, .ore = .copper },
        .{ .position = .{ 5, 0, 5 }, .ore = .crystal },
    };
    try std.testing.expectEqual(@as(?usize, 1), aimed(&veins, .{ 0, 0.6, 0 }, .{ 0, 0, 1 }, 20));
    try std.testing.expectEqual(@as(?usize, null), aimed(&veins, .{ 0, 0.6, 0 }, .{ 0, 0, 1 }, 4));
    try std.testing.expectEqual(@as(?usize, null), aimed(&veins, .{ 0, 0.6, 0 }, .{ 0, 0, -1 }, 20));
    try std.testing.expectEqual(@as(?usize, 2), veinUnder(&veins, .{ 5, 0, 7 }, 3));
    try std.testing.expectEqual(@as(?usize, null), veinUnder(&veins, .{ 5, 20, 5 }, 3));
}
