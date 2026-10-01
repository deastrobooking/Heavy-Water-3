//! Rootdeep shrines: seed vaults built from the machine kit. A shrine is a chain of rooms
//! separated by powered doors. Each door opens on logic over latches (toggled by wall
//! buttons) and weight plates (pressed only by crates, so the player cannot hold a door open
//! by standing on one). The last room holds the vault button.
//!
//! Generation is generate-and-verify: seeded candidate puzzles are solved exhaustively by a
//! breadth-first search over (room, latches, crate places). Only a solvable, non-trivial
//! candidate is built; the search's plan is kept as the verifier's witness. The puzzle then
//! compiles into an ordinary validated blueprint (walls and roof as structure parts, doors as
//! actuators) plus crate start positions, so the world runs it with the same machine
//! simulation as everything else.
const std = @import("std");
const Seed = @import("Seed.zig");
const Blueprint = @import("../machine/Blueprint.zig");
const Node = @import("../machine/Node.zig").Node;
const Shrine = @This();

pub const generator_version: u32 = 1;
pub const max_rooms = 4;
pub const max_latches = 3;
pub const max_plates = 2;
/// Candidates need at least this many actions (excluding the vault) to be accepted.
pub const min_plan = 6;
pub const max_plan = 48;
const max_attempts = 400;

pub const Term = struct { plate: bool = false, index: u8 = 0, negated: bool = false };
pub const Door = struct { terms: [2]Term = @splat(.{}), count: u8 = 1 };
pub const Puzzle = struct {
    rooms: u8,
    doors: [max_rooms - 1]Door = @splat(.{}),
    latches: u8,
    button_room: [max_latches]u8 = @splat(0),
    /// One crate per plate.
    plates: u8,
    plate_room: [max_plates]u8 = @splat(0),
    crate_room: [max_plates]u8 = @splat(0),
};

/// Where a crate is: on the floor of room 0..3, on plate 0..1 (4 + p), or carried (6).
const on_plate: u8 = 4;
const carried: u8 = 6;
pub const State = struct {
    room: u8 = 0,
    latches: u8 = 0,
    crates: [max_plates]u8 = @splat(0),

    fn encode(self: State) u16 {
        return @as(u16, self.room) | @as(u16, self.latches) << 2 | @as(u16, self.crates[0]) << 5 | @as(u16, self.crates[1]) << 8;
    }
    fn decode(bits: u16) State {
        return .{ .room = @intCast(bits & 3), .latches = @intCast(bits >> 2 & 7), .crates = .{ @intCast(bits >> 5 & 7), @intCast(bits >> 8 & 7) } };
    }
    fn carrying(self: State, plates: u8) ?u8 {
        for (0..plates) |c| if (self.crates[c] == carried) return @intCast(c);
        return null;
    }
};
const state_count = 1 << 11;

pub const Action = union(enum) {
    press: u8,
    pick: u8,
    drop_floor,
    drop_plate: u8,
    move: u8,
    vault,
};
pub const Plan = struct {
    actions: [max_plan]Action = undefined,
    len: usize = 0,
    pub fn slice(self: *const Plan) []const Action {
        return self.actions[0..self.len];
    }
};

pub fn initial(p: Puzzle) State {
    var s: State = .{};
    for (0..p.plates) |c| s.crates[c] = p.crate_room[c];
    return s;
}

pub fn plateLoaded(p: Puzzle, s: State, plate: u8) bool {
    for (0..p.plates) |c| if (s.crates[c] == on_plate + plate) return true;
    return false;
}

pub fn doorOpen(p: Puzzle, s: State, door: usize) bool {
    const d = p.doors[door];
    for (d.terms[0..d.count]) |t| {
        const on = if (t.plate) plateLoaded(p, s, t.index) else s.latches >> @intCast(t.index) & 1 == 1;
        if (on == t.negated) return false;
    }
    return true;
}

/// The state after `a`, or null when `a` is not possible in `s`.
pub fn apply(p: Puzzle, s: State, a: Action) ?State {
    var n = s;
    switch (a) {
        .press => |l| {
            if (l >= p.latches or p.button_room[l] != s.room) return null;
            n.latches ^= @as(u8, 1) << @intCast(l);
        },
        .pick => |c| {
            if (c >= p.plates or s.carrying(p.plates) != null) return null;
            const place = s.crates[c];
            const here = place == s.room or (place >= on_plate and place < carried and p.plate_room[place - on_plate] == s.room);
            if (!here) return null;
            n.crates[c] = carried;
        },
        .drop_floor => n.crates[s.carrying(p.plates) orelse return null] = s.room,
        .drop_plate => |plate| {
            const c = s.carrying(p.plates) orelse return null;
            if (plate >= p.plates or p.plate_room[plate] != s.room or plateLoaded(p, s, plate)) return null;
            n.crates[c] = on_plate + plate;
        },
        .move => |room| {
            if (room >= p.rooms) return null;
            if (room == s.room + 1 and doorOpen(p, s, s.room)) {
                n.room = room;
            } else if (room + 1 == s.room and doorOpen(p, s, room)) {
                n.room = room;
            } else return null;
        },
        .vault => if (s.room != p.rooms - 1) return null,
    }
    return n;
}

/// Shortest plan from the initial state into the vault room, ending with `.vault`, or null
/// if the vault cannot be reached.
pub fn solve(p: Puzzle) ?Plan {
    var seen: [state_count]bool = @splat(false);
    var parent: [state_count]u16 = undefined;
    var via: [state_count]Action = undefined;
    var queue: [state_count]u16 = undefined;
    var head: usize = 0;
    var tail: usize = 0;
    const start = initial(p).encode();
    seen[start] = true;
    queue[tail] = start;
    tail += 1;
    var candidates: [max_latches + max_plates * 2 + 3]Action = undefined;
    while (head < tail) {
        const bits = queue[head];
        head += 1;
        const s = State.decode(bits);
        if (s.room == p.rooms - 1) {
            var reversed: Plan = .{};
            reversed.actions[0] = .vault;
            reversed.len = 1;
            var at = bits;
            while (at != start) : (at = parent[at]) {
                if (reversed.len == max_plan) return null;
                reversed.actions[reversed.len] = via[at];
                reversed.len += 1;
            }
            var plan: Plan = .{ .len = reversed.len };
            for (0..reversed.len) |i| plan.actions[i] = reversed.actions[reversed.len - 1 - i];
            return plan;
        }
        var n: usize = 0;
        for (0..p.latches) |l| {
            candidates[n] = .{ .press = @intCast(l) };
            n += 1;
        }
        for (0..p.plates) |c| {
            candidates[n] = .{ .pick = @intCast(c) };
            candidates[n + 1] = .{ .drop_plate = @intCast(c) };
            n += 2;
        }
        candidates[n] = .drop_floor;
        candidates[n + 1] = .{ .move = s.room + 1 };
        n += 2;
        if (s.room > 0) {
            candidates[n] = .{ .move = s.room - 1 };
            n += 1;
        }
        for (candidates[0..n]) |a| {
            const next = apply(p, s, a) orelse continue;
            const code = next.encode();
            if (seen[code]) continue;
            seen[code] = true;
            parent[code] = bits;
            via[code] = a;
            queue[tail] = code;
            tail += 1;
        }
    }
    return null;
}

pub const Generated = struct { puzzle: Puzzle, plan: Plan, attempts: u32 };

/// A verified shrine for `seed`. Candidates must be solvable, start with the first door shut,
/// use every latch and plate, and need at least `min_plan` actions; of the first
/// `choices` accepted, the one with the longest shortest solution is built.
pub const choices = 6;
pub fn generate(seed: u64) Generated {
    var h = Seed.mix(seed ^ 0x53485249);
    var attempt: u32 = 0;
    var best: ?Generated = null;
    var accepted: usize = 0;
    while (attempt < max_attempts and accepted < choices) : (attempt += 1) {
        const p = candidate(&h);
        const plan = accept(p) orelse continue;
        accepted += 1;
        if (best == null or plan.len > best.?.plan.len) best = .{ .puzzle = p, .plan = plan, .attempts = attempt + 1 };
    }
    if (best) |b| return b;
    // A fixed, verified fallback: a button opens the first door, a crate on a plate the second.
    const fallback: Puzzle = .{ .rooms = 3, .latches = 1, .plates = 1, .doors = .{ .{ .terms = .{ .{ .index = 0 }, .{} } }, .{ .terms = .{ .{ .plate = true, .index = 0 }, .{} } }, .{} }, .plate_room = .{ 1, 0 }, .crate_room = .{ 0, 0 } };
    return .{ .puzzle = fallback, .plan = solve(fallback).?, .attempts = attempt };
}

fn roll(h: *u64, bound: u64) u8 {
    h.* = Seed.mix(h.* +% 0x9E3779B97F4A7C15);
    return @intCast(h.* % bound);
}

fn candidate(h: *u64) Puzzle {
    var p: Puzzle = .{ .rooms = 3 + roll(h, 2), .latches = 1 + roll(h, max_latches), .plates = roll(h, max_plates + 1) };
    for (p.button_room[0..p.latches]) |*r| r.* = roll(h, p.rooms - 1);
    for (p.plate_room[0..p.plates]) |*r| r.* = roll(h, p.rooms - 1);
    for (p.crate_room[0..p.plates]) |*r| r.* = roll(h, p.rooms - 1);
    for (p.doors[0 .. p.rooms - 1]) |*d| {
        d.count = 1 + roll(h, 2);
        for (d.terms[0..d.count]) |*t| {
            t.plate = p.plates > 0 and roll(h, 3) == 0;
            t.index = roll(h, if (t.plate) p.plates else p.latches);
            t.negated = roll(h, 4) == 0;
        }
        if (d.count == 2 and d.terms[0].plate == d.terms[1].plate and d.terms[0].index == d.terms[1].index) d.count = 1;
    }
    return p;
}

fn accept(p: Puzzle) ?Plan {
    if (doorOpen(p, initial(p), 0)) return null;
    // Room layout capacity: two buttons, two plates, and two crates per room.
    for (0..p.rooms) |r| {
        var buttons: u8 = 0;
        var plates: u8 = 0;
        var crates: u8 = 0;
        for (p.button_room[0..p.latches]) |b| buttons += @intFromBool(b == r);
        for (p.plate_room[0..p.plates], p.crate_room[0..p.plates]) |pl, c| {
            plates += @intFromBool(pl == r);
            crates += @intFromBool(c == r);
        }
        if (buttons > 2 or plates > 2 or crates > 2) return null;
    }
    var used_latch: u8 = 0;
    var used_plate: u8 = 0;
    for (p.doors[0 .. p.rooms - 1]) |d| for (d.terms[0..d.count]) |t| {
        if (t.plate) used_plate |= @as(u8, 1) << @intCast(t.index) else used_latch |= @as(u8, 1) << @intCast(t.index);
    };
    if (@popCount(used_latch) != p.latches or @popCount(used_plate) != p.plates) return null;
    const plan = solve(p) orelse return null;
    if (plan.len - 1 < min_plan) return null;
    return plan;
}

// ---- World layout (shrine-local metres; origin at the entrance, floor top at y = 0, +Z in).
pub const room_length: f32 = 10;
pub const width: f32 = 10;
pub const height: f32 = 4.5;
pub const opening: f32 = 3;

pub fn roomCenter(room: usize) [3]f32 {
    return .{ 0, 0, (@as(f32, @floatFromInt(room)) + 0.5) * room_length };
}

/// Index of `item` among the items before it in the same room (its slot along the room).
fn slotIn(rooms: []const u8, item: usize) usize {
    var n: usize = 0;
    for (rooms[0..item]) |r| n += @intFromBool(r == rooms[item]);
    return n;
}

// Room layout: a clear walkway along x = 0 through every doorway; buttons on the left wall
// and plates on the right, both on the rows z = centre ± 2.5; crates start on the left at
// x = −1.5 between those rows, so every button, plate, and crate is reached by walking the
// walkway and then straight across a row that nothing else occupies.
pub const row_offset: f32 = 2.5;

fn row(room: u8, slot: usize) f32 {
    return roomCenter(room)[2] - row_offset + @as(f32, @floatFromInt(slot)) * 2 * row_offset;
}

pub fn buttonPosition(p: Puzzle, latch: usize) [3]f32 {
    return .{ -width / 2 + 0.05, 1.3, row(p.button_room[latch], slotIn(p.button_room[0..p.latches], latch)) };
}

pub fn platePosition(p: Puzzle, plate: usize) [3]f32 {
    return .{ 2.5, 0.06, row(p.plate_room[plate], slotIn(p.plate_room[0..p.plates], plate)) };
}

/// Crate centre height is added by the caller (it depends on the crate model).
pub fn crateStart(p: Puzzle, crate: usize) [3]f32 {
    const c = roomCenter(p.crate_room[crate]);
    return .{ -1.5, 0, c[2] + 0.5 - @as(f32, @floatFromInt(slotIn(p.crate_room[0..p.plates], crate))) * 1.5 };
}

pub fn vaultPosition(p: Puzzle) [3]f32 {
    return .{ 0, 1.3, @as(f32, @floatFromInt(p.rooms)) * room_length - 0.3 };
}

pub fn resetPosition() [3]f32 {
    return .{ width / 2 - 0.05, 1.3, 5 };
}

pub fn doorZ(door: usize) f32 {
    return @as(f32, @floatFromInt(door + 1)) * room_length;
}

pub fn length(p: Puzzle) f32 {
    return @as(f32, @floatFromInt(p.rooms)) * room_length;
}

const stone = [4]f32{ 0.36, 0.40, 0.33, 1 };
const moss = [4]f32{ 0.26, 0.38, 0.27, 1 };

/// Compiles a puzzle into a validated blueprint named `name`: floor, roof, walls, and door
/// frames as parts; a generator powering doors and the seed lamp; buttons → latches; one logic
/// device per door; crate plates; and the vault button → sealed latch → seed lamp.
pub fn blueprint(p: Puzzle, name: []const u8) !Blueprint {
    const L = length(p);
    var parts: [Blueprint.max_parts]Blueprint.DocPart = undefined;
    var np: usize = 0;
    const Add = struct {
        fn part(list: []Blueprint.DocPart, n: *usize, center: [3]f32, size: [3]f32, color: [4]f32) void {
            list[n.*] = .{ .offset = center, .size = size, .color = color };
            n.* += 1;
        }
    };
    Add.part(&parts, &np, .{ 0, -1, L / 2 }, .{ width + 1, 2, L + 1 }, moss);
    Add.part(&parts, &np, .{ 0, height + 0.25, L / 2 }, .{ width + 1, 0.5, L + 1 }, moss);
    for ([_]f32{ -1, 1 }) |side| Add.part(&parts, &np, .{ side * (width / 2 + 0.25), height / 2, L / 2 }, .{ 0.5, height, L + 1 }, stone);
    Add.part(&parts, &np, .{ 0, height / 2, L + 0.25 }, .{ width + 1, height, 0.5 }, stone);
    const piece = (width + 1 - opening) / 2;
    for (0..p.rooms) |i| {
        // The entrance wall (i = 0) and each divider have a doorway in the middle.
        const z = @as(f32, @floatFromInt(i)) * room_length - if (i == 0) @as(f32, 0.25) else 0;
        for ([_]f32{ -1, 1 }) |side| Add.part(&parts, &np, .{ side * (opening / 2 + piece / 2), height / 2, z }, .{ piece, height, 0.5 }, stone);
    }

    var devices: [Blueprint.max_devices]Blueprint.DocDevice = undefined;
    var nd: usize = 0;
    var wires: [Blueprint.max_wires][2][]const u8 = undefined;
    var nw: usize = 0;
    var names: [Blueprint.max_devices][8]u8 = undefined;
    var nodes: [max_rooms - 1][7]Node = undefined;
    var ports: [Blueprint.max_wires][2][16]u8 = undefined;
    const Build = struct {
        fn id(buf: *[Blueprint.max_devices][8]u8, i: usize, comptime fmt: []const u8, args: anytype) []const u8 {
            return std.fmt.bufPrint(&buf[i], fmt, args) catch unreachable;
        }
        fn wire(list: *[Blueprint.max_wires][2][]const u8, store: *[Blueprint.max_wires][2][16]u8, n: *usize, from: []const u8, from_port: []const u8, to: []const u8, to_port: []const u8) void {
            list[n.*] = .{ std.fmt.bufPrint(&store[n.*][0], "{s}.{s}", .{ from, from_port }) catch unreachable, std.fmt.bufPrint(&store[n.*][1], "{s}.{s}", .{ to, to_port }) catch unreachable };
            n.* += 1;
        }
    };
    devices[nd] = .{ .id = "cell", .kind = .generator, .offset = .{ width / 2 - 0.8, 0.5, 0.9 }, .size = .{ 0.8, 1, 0.8 }, .color = .{ 0.85, 0.7, 0.2, 1 }, .watts = 200 * @as(f32, @floatFromInt(p.rooms)) };
    nd += 1;
    for (0..p.latches) |l| {
        const b = Build.id(&names, nd, "b{d}", .{l});
        devices[nd] = .{ .id = b, .kind = .button, .offset = buttonPosition(p, l), .size = .{ 0.12, 0.4, 0.4 }, .color = .{ 0.9, 0.35, 0.25, 1 } };
        nd += 1;
        const latch = Build.id(&names, nd, "l{d}", .{l});
        devices[nd] = .{ .id = latch, .kind = .latch };
        nd += 1;
        Build.wire(&wires, &ports, &nw, b, "pressed", latch, "toggle");
    }
    for (0..p.plates) |i| {
        devices[nd] = .{ .id = Build.id(&names, nd, "p{d}", .{i}), .kind = .plate, .offset = platePosition(p, i), .size = .{ 1.8, 0.12, 1.8 }, .color = .{ 0.55, 0.7, 0.9, 1 } };
        nd += 1;
    }
    for (p.doors[0 .. p.rooms - 1], 0..) |d, i| {
        // Terms read logic inputs a, b; each becomes 0/1 (negated: 0.5 > x); two are ANDed.
        var k: usize = 0;
        var term_node: [2]u16 = undefined;
        for (d.terms[0..d.count], 0..) |t, j| {
            nodes[i][k] = .{ .input = @intCast(j) };
            nodes[i][k + 1] = .{ .constant = 0.5 };
            nodes[i][k + 2] = if (t.negated) .{ .greater = .{ .a = @intCast(k + 1), .b = @intCast(k) } } else .{ .greater = .{ .a = @intCast(k), .b = @intCast(k + 1) } };
            term_node[j] = @intCast(k + 2);
            k += 3;
        }
        if (d.count == 2) {
            // AND: both terms are 0/1, so their product is the conjunction.
            nodes[i][k] = .{ .multiply = .{ .a = term_node[0], .b = term_node[1] } };
            k += 1;
        }
        const logic = Build.id(&names, nd, "o{d}", .{i});
        devices[nd] = .{ .id = logic, .kind = .logic, .nodes = nodes[i][0..k] };
        nd += 1;
        for (d.terms[0..d.count], 0..) |t, j| {
            var source: [8]u8 = undefined;
            const src = std.fmt.bufPrint(&source, "{s}{d}", .{ if (t.plate) "p" else "l", t.index }) catch unreachable;
            const src_name = for (devices[0..nd]) |dev| {
                if (std.mem.eql(u8, dev.id, src)) break dev.id;
            } else unreachable;
            Build.wire(&wires, &ports, &nw, src_name, if (t.plate) "pressed" else "state", logic, if (j == 0) "a" else "b");
        }
        const door = Build.id(&names, nd, "d{d}", .{i});
        devices[nd] = .{ .id = door, .kind = .actuator, .offset = .{ 0, height / 2, doorZ(i) }, .size = .{ opening, height, 0.3 }, .color = .{ 0.62, 0.52, 0.34, 1 }, .travel = .{ opening + 0.3, 0, 0 }, .speed = 2.5, .watts = 150 };
        nd += 1;
        Build.wire(&wires, &ports, &nw, "cell", "power", door, "power");
        Build.wire(&wires, &ports, &nw, logic, "out", door, "target");
    }
    // Unwired: the world resets crates and latches when it is pressed.
    devices[nd] = .{ .id = "reset", .kind = .button, .offset = resetPosition(), .size = .{ 0.12, 0.4, 0.4 }, .color = .{ 0.4, 0.75, 0.95, 1 } };
    nd += 1;
    devices[nd] = .{ .id = "vault", .kind = .button, .offset = vaultPosition(p), .size = .{ 0.5, 0.5, 0.12 }, .color = .{ 0.95, 0.85, 0.4, 1 } };
    devices[nd + 1] = .{ .id = "sealed", .kind = .latch };
    devices[nd + 2] = .{ .id = "seed", .kind = .lamp, .offset = .{ 0, 2.6, length(p) - 0.6 }, .size = .{ 0.7, 0.7, 0.7 }, .color = .{ 0.4, 1.0, 0.7, 1 }, .watts = 50 };
    nd += 3;
    Build.wire(&wires, &ports, &nw, "vault", "pressed", "sealed", "toggle");
    Build.wire(&wires, &ports, &nw, "sealed", "state", "seed", "on");
    Build.wire(&wires, &ports, &nw, "cell", "power", "seed", "power");
    return Blueprint.fromDoc(.{ .format = 1, .name = name, .parts = parts[0..np], .devices = devices[0..nd], .wires = wires[0..nw] });
}

test "every generated shrine is verified solvable, non-trivial, and its plan replays" {
    var fallbacks: usize = 0;
    var longest: usize = 0;
    for (0..300) |i| {
        const g = generate(Seed.mix(i));
        const p = g.puzzle;
        fallbacks += @intFromBool(g.attempts == max_attempts and g.plan.len - 1 < min_plan);
        // Replay the verifier's plan through the rules: every step legal, ending in the vault.
        var s = initial(p);
        try std.testing.expect(!doorOpen(p, s, 0));
        for (g.plan.slice()) |a| s = apply(p, s, a) orelse return error.IllegalPlanStep;
        try std.testing.expectEqual(p.rooms - 1, s.room);
        try std.testing.expect(g.plan.slice()[g.plan.len - 1] == .vault);
        if (g.attempts < max_attempts) try std.testing.expect(g.plan.len - 1 >= min_plan);
        longest = @max(longest, g.plan.len);
        // Every shrine compiles into a blueprint the ordinary validator accepts.
        _ = try blueprint(p, "shrine");
    }
    try std.testing.expect(fallbacks < 10);
    try std.testing.expect(longest >= 10);
    // Generation is deterministic.
    try std.testing.expectEqual(generate(7).plan.len, generate(7).plan.len);
    try std.testing.expectEqual(generate(7).puzzle, generate(7).puzzle);
}

test "the solver rejects impossible shrines and needs crates on plates, not people" {
    // Door 0 wants plate 0, but its only crate starts beyond that door.
    const locked: Puzzle = .{ .rooms = 3, .latches = 1, .plates = 1, .doors = .{ .{ .terms = .{ .{ .plate = true }, .{} } }, .{}, .{} }, .plate_room = .{ 0, 0 }, .crate_room = .{ 1, 0 } };
    try std.testing.expect(solve(locked) == null);
    // A negated latch starts open: the solver walks straight through.
    const open: Puzzle = .{ .rooms = 2, .latches = 1, .plates = 0, .doors = .{ .{ .terms = .{ .{ .negated = true }, .{} } }, .{}, .{} } };
    try std.testing.expectEqual(@as(usize, 2), solve(open).?.len);
    // Carrying a crate does not press a plate; it must be dropped on it.
    const carry: Puzzle = .{ .rooms = 2, .latches = 1, .plates = 1, .doors = .{ .{ .terms = .{ .{ .plate = true }, .{} } }, .{}, .{} }, .plate_room = .{ 0, 0 }, .crate_room = .{ 0, 0 } };
    const plan = solve(carry).?;
    try std.testing.expectEqualSlices(Action, &.{ .{ .pick = 0 }, .{ .drop_plate = 0 }, .{ .move = 1 }, .vault }, plan.slice());
}
