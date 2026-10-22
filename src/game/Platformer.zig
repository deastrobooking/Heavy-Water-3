//! What the platformer blocks do. The kind of a block is its material in the platformer style:
//! springs launch, boost strips fling you along their facing, crumbling blocks fall away a moment
//! after you land and come back, hazards hurt, checkpoints become your recovery point, pressure
//! plates open the gates within 16 m and hold them open 8 s after you step off, and movers slide back and forth carrying you.
const std = @import("std");
const Sandbox = @import("Sandbox.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Player = @import("Player.zig");
const Physics = @import("../physics/Physics.zig");
const Blocks = @import("../build/Blocks.zig");
const Materials = @import("../build/Materials.zig");
const Mesher = @import("../build/Mesher.zig");

pub const Kind = enum { none, spring, boost, crumble, hazard, checkpoint, plate, gate, mover };

pub const spring_speed: f32 = 15;
pub const boost_speed: f32 = 16;
pub const crumble_delay: f32 = 0.6;
pub const crumble_return: f32 = 4;
pub const hazard_damage: f32 = 20;
pub const hazard_interval: f32 = 0.6;
/// A plate keeps the gates within `Mesher.Hide.gate_reach` of it open this long after the last
/// player steps off: long enough to run from a course's last plate to the gate it opens.
pub const plate_hold: f32 = 8;
pub const mover_travel: f32 = 4;
pub const mover_speed: f32 = 1.6;
pub const max_movers = 16;
pub const max_crumbles = 32;

pub fn kindOf(cell: Blocks.Cell) Kind {
    if (cell.isEmpty()) return .none;
    const r = Materials.roleOf(cell.material);
    if (r.style != .platformer) return .none;
    return @enumFromInt(r.role + 1);
}

const Crumble = struct { cell: [3]i32, time: f32 = 0, gone: bool = false };
const Plate = struct { cell: [3]i32, time: f32 };
const BlockWorld = @import("../build/BlockWorld.zig");
const Mover = struct { start: [3]f32, dir: [3]f32, body: Physics.Body, sign: f32 = 1, color: [3]f32 };

pub const State = struct {
    checkpoints: [Sandbox.max_players]?[3]f32 = @splat(null),
    hazard_cool: [Sandbox.max_players]f32 = @splat(0),
    boost_cool: [Sandbox.max_players]f32 = @splat(0),
    crumbles: [max_crumbles]Crumble = undefined,
    crumble_len: usize = 0,
    plates: [BlockWorld.max_plates]Plate = undefined,
    plate_len: usize = 0,
    movers: [max_movers]Mover = undefined,
    mover_len: usize = 0,
};

fn floorCell(p: [3]f32) [3]i32 {
    return .{ @intFromFloat(@floor(p[0])), @intFromFloat(@floor(p[1])), @intFromFloat(@floor(p[2])) };
}

/// The block a player is standing on (null in the air, or on anything else).
fn under(sb: *const Sandbox, feet: [3]f32) ?struct { cell: Blocks.Cell, at: [3]i32 } {
    const c = floorCell(.{ feet[0], feet[1] - 0.05, feet[2] });
    if (@abs(feet[1] - @as(f32, @floatFromInt(c[1] + 1))) > 0.2) return null;
    const hide = sb.block_world.hide();
    const cell = sb.block_world.blocks.get(c[0], c[1], c[2]);
    if (cell.isEmpty() or hide.hides(cell, c[0], c[1], c[2])) return null;
    return .{ .cell = cell, .at = c };
}

/// Run the blocks for every player. Call after the players have moved this step.
pub fn step(sb: *Sandbox, camera: *Camera, dt: f32) !void {
    const st = &sb.platform;
    var changed = false;
    var plates_changed = false;
    for (0..Sandbox.max_players) |slot| {
        const p: *Player = if (slot == 0) &sb.player else if (sb.guests[slot - 1].active) &sb.guests[slot - 1].player else continue;
        st.hazard_cool[slot] = @max(0, st.hazard_cool[slot] - dt);
        st.boost_cool[slot] = @max(0, st.boost_cool[slot] - dt);
        // A hazard hurts whether you stand on it or walk into it.
        const body = sb.block_world.blocks.get(@intFromFloat(@floor(p.feet[0])), @intFromFloat(@floor(p.feet[1] + 0.4)), @intFromFloat(@floor(p.feet[2])));
        const on = under(sb, p.feet);
        const kind = if (on) |o| kindOf(o.cell) else .none;
        if ((kind == .hazard or kindOf(body) == .hazard) and st.hazard_cool[slot] == 0) {
            st.hazard_cool[slot] = hazard_interval;
            var events: [4]@import("Combat.zig").Event = undefined;
            var n: usize = 0;
            if (sb.combat.hurt(@intCast(slot), hazard_damage, &events, &n)) recover(sb, slot, camera);
        }
        const o = on orelse continue;
        switch (kind) {
            .spring => if (p.velocity[1] <= 0.5) {
                p.velocity[1] = spring_speed;
                p.grounded = false;
                p.feet[1] += 0.05;
            },
            .boost => if (st.boost_cool[slot] == 0) {
                const d = Mesher.Dir.pz.turned(o.cell.rot).vector();
                p.velocity[0] = @as(f32, @floatFromInt(d[0])) * boost_speed;
                p.velocity[2] = @as(f32, @floatFromInt(d[2])) * boost_speed;
                st.boost_cool[slot] = 0.4;
            },
            .crumble => {
                for (st.crumbles[0..st.crumble_len]) |c| {
                    if (std.meta.eql(c.cell, o.at)) break;
                } else if (st.crumble_len < max_crumbles) {
                    st.crumbles[st.crumble_len] = .{ .cell = o.at };
                    st.crumble_len += 1;
                }
            },
            .checkpoint => {
                const point: [3]f32 = .{ @as(f32, @floatFromInt(o.at[0])) + 0.5, @floatFromInt(o.at[1] + 1), @as(f32, @floatFromInt(o.at[2])) + 0.5 };
                const old = st.checkpoints[slot];
                if (old == null or !std.meta.eql(old.?, point)) {
                    st.checkpoints[slot] = point;
                    sb.sayTo(slot, "checkpoint", .{});
                }
            },
            .plate => {
                for (st.plates[0..st.plate_len]) |*held| {
                    if (std.meta.eql(held.cell, o.at)) {
                        held.time = plate_hold;
                        break;
                    }
                } else if (st.plate_len < BlockWorld.max_plates) {
                    st.plates[st.plate_len] = .{ .cell = o.at, .time = plate_hold };
                    st.plate_len += 1;
                    plates_changed = true;
                }
            },
            else => {},
        }
    }
    // Crumbling blocks fall a moment after a landing and return a few seconds later.
    var i: usize = 0;
    while (i < st.crumble_len) {
        const c = &st.crumbles[i];
        c.time += dt;
        if (!c.gone and c.time >= crumble_delay) {
            c.gone = true;
            sb.block_world.setHidden(c.cell, true);
            changed = true;
        }
        if (c.gone and c.time >= crumble_delay + crumble_return) {
            sb.block_world.setHidden(c.cell, false);
            changed = true;
            st.crumbles[i] = st.crumbles[st.crumble_len - 1];
            st.crumble_len -= 1;
            continue;
        }
        i += 1;
    }
    // Plates count down once nobody stands on them; the gates near each close when it runs out.
    var p: usize = 0;
    while (p < st.plate_len) {
        st.plates[p].time -= dt;
        if (st.plates[p].time <= 0) {
            st.plates[p] = st.plates[st.plate_len - 1];
            st.plate_len -= 1;
            plates_changed = true;
            continue;
        }
        p += 1;
    }
    if (plates_changed) {
        for (st.plates[0..st.plate_len], 0..) |held, k| sb.block_world.plates[k] = .{ @as(f32, @floatFromInt(held.cell[0])) + 0.5, @as(f32, @floatFromInt(held.cell[1])) + 0.5, @as(f32, @floatFromInt(held.cell[2])) + 0.5 };
        sb.block_world.plate_len = st.plate_len;
        sb.block_world.rebuildAll();
        changed = true;
    }
    if (changed) try sb.block_world.sync(sb.allocator, &sb.physics);
    // Movers turn around at the ends of their run.
    for (st.movers[0..st.mover_len]) |*m| {
        const at = sb.physics.position(m.body) orelse continue;
        const along = (at[0] - m.start[0]) * m.dir[0] + (at[1] - m.start[1]) * m.dir[1] + (at[2] - m.start[2]) * m.dir[2];
        if (along >= mover_travel) m.sign = -1;
        if (along <= 0) m.sign = 1;
        sb.physics.setVelocity(m.body, .{ m.dir[0] * mover_speed * m.sign, m.dir[1] * mover_speed * m.sign, m.dir[2] * mover_speed * m.sign });
    }
}

/// Hold a plate pressed as if someone had just stepped off it (its gates open for `plate_hold`).
pub fn press(sb: *Sandbox, cell: [3]i32) !void {
    const st = &sb.platform;
    for (st.plates[0..st.plate_len]) |*held| if (std.meta.eql(held.cell, cell)) {
        held.time = plate_hold;
        return;
    };
    if (st.plate_len == BlockWorld.max_plates) return;
    st.plates[st.plate_len] = .{ .cell = cell, .time = plate_hold };
    st.plate_len += 1;
    for (st.plates[0..st.plate_len], 0..) |held, k| sb.block_world.plates[k] = .{ @as(f32, @floatFromInt(held.cell[0])) + 0.5, @as(f32, @floatFromInt(held.cell[1])) + 0.5, @as(f32, @floatFromInt(held.cell[2])) + 0.5 };
    sb.block_world.plate_len = st.plate_len;
    sb.block_world.rebuildAll();
    try sb.syncBlocks();
}

/// Back on your feet at your checkpoint, healed; without one, the usual recovery.
pub fn recover(sb: *Sandbox, slot: usize, camera: *Camera) void {
    if (recoverAtCheckpoint(sb, slot, camera)) return;
    if (slot == 0) sb.resetPlayer(camera) else sb.respawnGuest(slot - 1);
    sb.combat.vitals[slot].health = sb.combat.vitals[slot].max;
}

/// Puts a downed player at their checkpoint; false if they have none.
pub fn recoverAtCheckpoint(sb: *Sandbox, slot: usize, camera: *Camera) bool {
    const point = sb.platform.checkpoints[slot] orelse return false;
    const p: *Player = if (slot == 0) &sb.player else &sb.guests[slot - 1].player;
    p.feet = point;
    p.velocity = @splat(0);
    sb.combat.vitals[slot].health = sb.combat.vitals[slot].max;
    if (slot == 0) camera.position = sb.player.eye();
    sb.sayTo(slot, "back at your checkpoint", .{});
    return true;
}

/// Rebuild the moving bodies from the grid's mover blocks (after any block edit or a load).
pub fn refreshMovers(sb: *Sandbox) !void {
    const st = &sb.platform;
    for (st.movers[0..st.mover_len]) |m| sb.physics.destroyBody(m.body);
    st.mover_len = 0;
    const blocks = sb.block_world.blocks;
    const mover = Materials.ofRole(.platformer, .color);
    for (0..blocks.count) |i| {
        const section = blocks.sectionAt(i);
        for (section.cells, 0..) |cell, n| {
            if (cell.isEmpty() or cell.material != mover) continue;
            if (st.mover_len == max_movers) return sb.say("only {d} movers run at once", .{max_movers});
            const x = section.key.x * Blocks.side + @as(i32, @intCast(n % Blocks.side));
            const z = section.key.z * Blocks.side + @as(i32, @intCast(n / Blocks.side % Blocks.side));
            const y = section.key.y * Blocks.side + @as(i32, @intCast(n / (Blocks.side * Blocks.side)));
            const d = Mesher.Dir.pz.turned(cell.rot).vector();
            const start: [3]f32 = .{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5, @as(f32, @floatFromInt(z)) + 0.5 };
            const body = try sb.physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = start, .motion = .kinematic, .user = Sandbox.world_flag });
            st.movers[st.mover_len] = .{ .start = start, .dir = .{ @floatFromInt(d[0]), @floatFromInt(d[1]), @floatFromInt(d[2]) }, .body = body, .color = Materials.all[mover].color };
            st.mover_len += 1;
        }
    }
}

/// Forget crumbles, open gates and checkpoints (a load); movers are rebuilt by the caller.
pub fn reset(sb: *Sandbox) void {
    const movers = sb.platform.movers;
    const mover_len = sb.platform.mover_len;
    sb.platform = .{ .movers = movers, .mover_len = mover_len };
    sb.block_world.hidden_len = 0;
    sb.block_world.plate_len = 0;
    sb.block_world.rebuildAll();
}

/// The moving blocks, drawn where their bodies are.
pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    var n = start;
    for (sb.platform.movers[0..sb.platform.mover_len]) |m| {
        if (n == out.len) break;
        const at = sb.physics.position(m.body) orelse continue;
        out[n] = .{ .mesh = sb.catalog.content.block, .transform = .{ .position = at }, .tint = .{ m.color[0], m.color[1], m.color[2], 1 }, .size = .{ 1, 1, 1 } };
        n += 1;
    }
    return n;
}

test "platformer kinds follow the platformer style's roles and nothing else" {
    try std.testing.expectEqual(Kind.spring, kindOf(.{ .shape = .cube, .material = Materials.ofRole(.platformer, .main) }));
    try std.testing.expectEqual(Kind.mover, kindOf(.{ .shape = .cube, .material = Materials.ofRole(.platformer, .color) }));
    try std.testing.expectEqual(Kind.none, kindOf(.{ .shape = .cube, .material = Materials.ofRole(.castle, .main) }));
    try std.testing.expectEqual(Kind.none, kindOf(.empty));
}
