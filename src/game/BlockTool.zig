//! The block tool, for any of the four players: aim at a surface and place the chosen shape in the
//! 1 m grid beside it, or remove the aimed block. Every block comes from the builder's own `Kit`
//! and a removed block goes back to whoever removed it. Holding the modifier (Shift, or the
//! sprint button on a pad) turns a click into a box corner: the second click fills or clears the
//! whole box.
//!
//! Player 1 on keyboard: click place, right click remove, Tab shape, [ ] material, T turn, P pick
//! the aimed block. On a pad (any player): hold RB and press D-pad left to enter or leave building;
//! then RT place, LT remove, D-pad up shape, left/right material, down turn, RB + up pick.
const std = @import("std");
const Sandbox = @import("Sandbox.zig");
const World = @import("../world/World.zig");
const Blocks = @import("../build/Blocks.zig");
const Materials = @import("../build/Materials.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Kit = @import("Kit.zig");
const Prefabs = @import("../build/Prefabs.zig");
const Farm = @import("Farm.zig");

pub const reach: f32 = 14;
/// Largest box one fill may cover.
pub const max_box_cells = 512;

pub const State = struct {
    shape: u8 = 0,
    material: u8 = 0,
    rot: u2 = 0,
    style: Materials.Style = .castle,
    /// The empty cell a click would fill, and whether it may be filled there.
    place: ?[3]i32 = null,
    valid: bool = false,
    /// The block under the crosshair, which remove takes.
    remove: ?[3]i32 = null,
    /// First corner of a box operation, waiting for the second click.
    corner: ?[3]i32 = null,
    corner_mode: CornerMode = .fill,
};

/// What a two-corner box does: fill with the block, clear it, re-skin it into the current style,
/// or copy it to the player's clipboard.
pub const CornerMode = enum { fill, clear, restyle, capture };

/// One step's requests, from the keyboard or a pad.
pub const Command = struct {
    place: bool = false,
    remove: bool = false,
    next_shape: bool = false,
    /// -1 or +1 steps through the style's materials.
    material_step: i2 = 0,
    rotate: bool = false,
    pick: bool = false,
    /// Held: clicks mark box corners (and Tab changes style instead of shape).
    box: bool = false,
    next_style: bool = false,
};

/// The palette position: one of the four shapes, a starter prefab of the style, or the clipboard.
pub const Entry = union(enum) { shape: Blocks.Shape, seed, prefab: Prefabs.Prefab };

/// The farm style also offers seeds, right after the shapes.
fn seeds(st: State) usize {
    return @intFromBool(st.style == .farm);
}

pub fn entryCount(sb: *const Sandbox, slot: usize, st: State) usize {
    return Blocks.placeable_shapes.len + seeds(st) + Prefabs.starters(st.style).len + @intFromBool(sb.block_clips[slot].len > 0);
}

pub fn entry(sb: *const Sandbox, slot: usize, st: State) Entry {
    const i = st.shape % entryCount(sb, slot, st);
    if (i < Blocks.placeable_shapes.len) return .{ .shape = Blocks.placeable_shapes[i] };
    if (seeds(st) == 1 and i == Blocks.placeable_shapes.len) return .seed;
    const starters = Prefabs.starters(st.style);
    const p = i - Blocks.placeable_shapes.len - seeds(st);
    return .{ .prefab = if (p < starters.len) starters[p] else sb.block_clips[slot].prefab() };
}

pub fn entryName(sb: *const Sandbox, slot: usize, st: State) []const u8 {
    return switch (entry(sb, slot, st)) {
        .shape => |shape| switch (shape) {
            .cube => "CUBE",
            .slab => "SLAB",
            .ramp => "RAMP",
            .stair => "STAIR",
            else => "",
        },
        .seed => "SEEDS",
        .prefab => |p| p.name,
    };
}

pub fn cell(st: State) Blocks.Cell {
    const palette = Materials.ofStyle(st.style);
    // Prefab entries sit after the shapes; a single block for them is a cube.
    const shape = if (st.shape < Blocks.placeable_shapes.len) Blocks.placeable_shapes[st.shape] else .cube;
    return .{ .shape = shape, .rot = st.rot, .material = palette[st.material % palette.len] };
}

fn floorCell(p: [3]f32) [3]i32 {
    return .{ @intFromFloat(@floor(p[0])), @intFromFloat(@floor(p[1])), @intFromFloat(@floor(p[2])) };
}

/// Why `c` cannot take a block, or null when it can. `alone` asks for ground or a neighbour.
pub fn refusal(sb: *const Sandbox, c: [3]i32, alone: bool) ?[]const u8 {
    const blocks = sb.block_world.blocks;
    if (!blocks.get(c[0], c[1], c[2]).isEmpty()) return "occupied";
    if (sb.farm.find(c) != null) return "a crop grows there";
    if (!sb.block_world.hasRoom(Blocks.chunkOf(c[0], c[2]))) return "block budget full: build near your other blocks";
    const lo: [3]f32 = .{ @floatFromInt(c[0]), @floatFromInt(c[1]), @floatFromInt(c[2]) };
    // Never build into a player.
    var feet: [Sandbox.max_players]?[3]f32 = .{ sb.player.feet, null, null, null };
    for (sb.guests, 1..) |g, i| if (g.active) {
        feet[i] = g.player.feet;
    };
    for (feet) |maybe| if (maybe) |f| {
        if (f[0] + 0.35 > lo[0] and f[0] - 0.35 < lo[0] + 1 and f[2] + 0.35 > lo[2] and f[2] - 0.35 < lo[2] + 1 and f[1] + 1.8 > lo[1] and f[1] < lo[1] + 1) return "a player is standing there";
    };
    // Machines, crates and other solid bodies.
    if (sb.physics.overlapsBox(.{ lo[0] + 0.5, lo[1] + 0.5, lo[2] + 0.5 }, .{ 0.45, 0.45, 0.45 })) return "something is in the way";
    if (!alone) return null;
    // Supported by the ground or by another block (platformer pieces may float later).
    if (supported(sb, c)) return null;
    return "needs ground or another block beside it";
}

fn supported(sb: *const Sandbox, c: [3]i32) bool {
    const ground = Terrain.surface(sb.seed, @as(f32, @floatFromInt(c[0])) + 0.5, @as(f32, @floatFromInt(c[2])) + 0.5).height;
    if (@as(f32, @floatFromInt(c[1])) <= ground + 1) return true;
    for ([_][3]i32{ .{ 1, 0, 0 }, .{ -1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, -1, 0 }, .{ 0, 0, 1 }, .{ 0, 0, -1 } }) |o| {
        if (!sb.block_world.blocks.get(c[0] + o[0], c[1] + o[1], c[2] + o[2]).isEmpty()) return true;
    }
    return false;
}

/// Aim, then carry out `cmd` for player `slot` (0 is P1) from `eye` along `forward`.
pub fn step(sb: *Sandbox, slot: usize, st: *State, eye: [3]f32, forward: [3]f32, cmd: Command) !void {
    const kit = &sb.kits[slot];
    if (cmd.next_style) {
        st.style = @enumFromInt((@as(usize, @intFromEnum(st.style)) + 1) % Materials.style_count);
        if (st.shape >= entryCount(sb, slot, st.*)) st.shape = 0;
        sb.sayTo(slot, "style: {s}", .{Materials.styleName(st.style)});
    } else if (cmd.next_shape) {
        st.shape = @intCast((st.shape + 1) % entryCount(sb, slot, st.*));
        sb.sayTo(slot, "{s}", .{entryName(sb, slot, st.*)});
    }
    const palette = Materials.ofStyle(st.style);
    if (cmd.material_step != 0) {
        const n: u8 = @intCast(palette.len);
        st.material = if (cmd.material_step > 0) (st.material + 1) % n else (st.material + n - 1) % n;
        const m = cell(st.*).material;
        sb.sayTo(slot, "material: {s} ({d} held)", .{ Materials.all[m].name, kit.blocks[m] });
    }
    if (cmd.rotate and !cmd.box) st.rot +%= 1;

    st.place = null;
    st.remove = null;
    st.valid = false;
    if (sb.physics.castRay(eye, forward, reach, .none)) |hit| {
        const n = hit.normal;
        const outside = floorCell(.{ hit.point[0] + n[0] * 0.25, hit.point[1] + n[1] * 0.25, hit.point[2] + n[2] * 0.25 });
        const inside = floorCell(.{ hit.point[0] - n[0] * 0.25, hit.point[1] - n[1] * 0.25, hit.point[2] - n[2] * 0.25 });
        if (!sb.block_world.blocks.get(inside[0], inside[1], inside[2]).isEmpty()) st.remove = inside;
        st.place = outside;
        st.valid = refusal(sb, outside, true) == null and kit.blocks[cell(st.*).material] > 0;
    }
    // Box operations: the modifier marks the first corner; the same operation again finishes it.
    const op: ?CornerMode = if (cmd.place) .fill else if (cmd.remove) .clear else if (cmd.rotate and cmd.box) .restyle else if (cmd.pick and cmd.box) .capture else null;
    if (op) |mode| if (cmd.box or (st.corner != null and st.corner_mode == mode)) {
        const at = (if (mode == .fill) st.place else st.remove orelse st.place) orelse return sb.sayTo(slot, "aim at the ground or a block within {d:.0} m", .{reach});
        if (st.corner) |a| if (st.corner_mode == mode) {
            st.corner = null;
            return switch (mode) {
                .fill => fillBox(sb, slot, st.*, a, at),
                .clear => clearBox(sb, slot, a, at),
                .restyle => restyleBox(sb, slot, a, at, st.style),
                .capture => captureBox(sb, slot, st, a, at),
            };
        };
        st.corner = at;
        st.corner_mode = mode;
        return sb.sayTo(slot, "{s} corner set: mark the opposite corner", .{@tagName(mode)});
    };
    if (cmd.pick) if (st.remove) |c| {
        const aimed = sb.block_world.blocks.get(c[0], c[1], c[2]);
        for (Blocks.placeable_shapes, 0..) |s, i| if (s == aimed.shape) {
            st.shape = @intCast(i);
        };
        for (palette, 0..) |m, i| if (m == aimed.material) {
            st.material = @intCast(i);
        };
        st.rot = aimed.rot;
        sb.sayTo(slot, "picked {s} {s}", .{ Materials.all[aimed.material].name, @tagName(aimed.shape) });
    };
    if (cmd.place) {
        const c = st.place orelse return sb.sayTo(slot, "aim at the ground or a block within {d:.0} m", .{reach});
        switch (entry(sb, slot, st.*)) {
            .prefab => |p| return stamp(sb, slot, p, st.rot, c),
            .seed => return Farm.plant(sb, slot, c),
            .shape => {},
        }
        if (refusal(sb, c, true)) |why| return sb.sayTo(slot, "blocked: {s}", .{why});
        const want = cell(st.*);
        if (kit.blocks[want.material] == 0) return sb.sayTo(slot, "no {s} blocks left", .{Materials.all[want.material].name});
        sb.block_world.blocks.set(c[0], c[1], c[2], want) catch return sb.sayTo(slot, "block budget full", .{});
        kit.blocks[want.material] -= 1;
        try sb.syncBlocks();
    }
    if (cmd.remove) {
        const c = st.remove orelse return;
        // Aiming at a field's soil takes the crop growing on it first.
        if (Farm.harvest(sb, slot, .{ c[0], c[1] + 1, c[2] })) return;
        const old = sb.block_world.blocks.get(c[0], c[1], c[2]);
        try sb.block_world.blocks.set(c[0], c[1], c[2], .empty);
        kit.blocks[old.material] +|= 1;
        try sb.syncBlocks();
    }
}

const Box = struct {
    lo: [3]i32,
    hi: [3]i32,
    cells: usize,

    const Iterator = struct {
        bx: Box,
        at: ?[3]i32,
        fn next(self: *Iterator) ?[3]i32 {
            const c = self.at orelse return null;
            var n = c;
            n[0] += 1;
            if (n[0] > self.bx.hi[0]) {
                n[0] = self.bx.lo[0];
                n[2] += 1;
                if (n[2] > self.bx.hi[2]) {
                    n[2] = self.bx.lo[2];
                    n[1] += 1;
                }
            }
            self.at = if (n[1] > self.bx.hi[1]) null else n;
            return c;
        }
    };
    fn iterate(self: Box) Iterator {
        return .{ .bx = self, .at = self.lo };
    }
};
fn box(a: [3]i32, b: [3]i32) Box {
    var result: Box = .{ .lo = undefined, .hi = undefined, .cells = 1 };
    for (0..3) |i| {
        result.lo[i] = @min(a[i], b[i]);
        result.hi[i] = @max(a[i], b[i]);
        result.cells *= @intCast(result.hi[i] - result.lo[i] + 1);
    }
    return result;
}

/// Fill every empty cell of the box with the current block. Checked in full first: the builder
/// must hold enough blocks, no cell may be blocked, and some cell must rest on something.
pub fn fillBox(sb: *Sandbox, slot: usize, st: State, a: [3]i32, b: [3]i32) !void {
    const bx = box(a, b);
    if (bx.cells > max_box_cells) return sb.sayTo(slot, "box too large: {d} cells, at most {d}", .{ bx.cells, max_box_cells });
    const want = cell(st);
    var needed: u32 = 0;
    var rests = false;
    var y = bx.lo[1];
    while (y <= bx.hi[1]) : (y += 1) {
        var z = bx.lo[2];
        while (z <= bx.hi[2]) : (z += 1) {
            var x = bx.lo[0];
            while (x <= bx.hi[0]) : (x += 1) {
                const c: [3]i32 = .{ x, y, z };
                if (!sb.block_world.blocks.get(x, y, z).isEmpty()) continue;
                if (refusal(sb, c, false)) |why| return sb.sayTo(slot, "box blocked: {s}", .{why});
                if (!rests and supported(sb, c)) rests = true;
                needed += 1;
            }
        }
    }
    if (needed == 0) return sb.sayTo(slot, "the box is already full", .{});
    if (!rests) return sb.sayTo(slot, "box needs ground or another block beside it", .{});
    const kit = &sb.kits[slot];
    if (kit.blocks[want.material] < needed) return sb.sayTo(slot, "box needs {d} {s} blocks, you hold {d}", .{ needed, Materials.all[want.material].name, kit.blocks[want.material] });
    y = bx.lo[1];
    while (y <= bx.hi[1]) : (y += 1) {
        var z = bx.lo[2];
        while (z <= bx.hi[2]) : (z += 1) {
            var x = bx.lo[0];
            while (x <= bx.hi[0]) : (x += 1) {
                if (!sb.block_world.blocks.get(x, y, z).isEmpty()) continue;
                // Sections were not reserved up front; a full pool stops the fill where it is
                // and charges only what was placed.
                sb.block_world.blocks.set(x, y, z, want) catch {
                    try sb.syncBlocks();
                    return sb.sayTo(slot, "block budget full", .{});
                };
                kit.blocks[want.material] -= 1;
            }
        }
    }
    try sb.syncBlocks();
    sb.sayTo(slot, "filled {d} blocks", .{needed});
}

/// Where a prefab's turned footprint starts so that it is centred on `at`.
pub fn stampOrigin(prefab: Prefabs.Prefab, rot: u2, at: [3]i32) [3]i32 {
    const size = Prefabs.turnedSize(prefab.size, rot);
    return .{ at[0] - @divFloor(@as(i32, size[0]), 2), at[1], at[2] - @divFloor(@as(i32, size[2]), 2) };
}

/// Lay a prefab centred on `at`, turned `rot` times. Every cell must be free and the builder must
/// hold every block before anything is placed.
pub fn stamp(sb: *Sandbox, slot: usize, prefab: Prefabs.Prefab, rot: u2, at: [3]i32) !void {
    const origin = stampOrigin(prefab, rot, at);
    var rests = false;
    for (prefab.cells) |p| {
        const t = Prefabs.turned(p, prefab.size, rot);
        const c: [3]i32 = .{ origin[0] + t.x, origin[1] + t.y, origin[2] + t.z };
        if (refusal(sb, c, false)) |why| return sb.sayTo(slot, "{s} blocked: {s}", .{ prefab.name, why });
        if (!rests and t.y == 0 and supported(sb, c)) rests = true;
    }
    if (!rests) return sb.sayTo(slot, "{s} needs ground under it", .{prefab.name});
    const need = Prefabs.cost(prefab);
    const kit = &sb.kits[slot];
    for (need, kit.blocks, 0..) |n, held, m| if (n > held) return sb.sayTo(slot, "{s} needs {d} {s}, you hold {d}", .{ prefab.name, n, Materials.all[m].name, held });
    for (prefab.cells) |p| {
        const t = Prefabs.turned(p, prefab.size, rot);
        sb.block_world.blocks.set(origin[0] + t.x, origin[1] + t.y, origin[2] + t.z, t.cell) catch {
            try sb.syncBlocks();
            return sb.sayTo(slot, "block budget full", .{});
        };
        kit.blocks[t.cell.material] -= 1;
    }
    try sb.syncBlocks();
    sb.sayTo(slot, "built {s}", .{prefab.name});
}

/// Re-skin every block in the box into `style`, role for role. The builder pays the new blocks and
/// gets the old ones back; checked in full first.
pub fn restyleBox(sb: *Sandbox, slot: usize, a: [3]i32, b: [3]i32, style: Materials.Style) !void {
    const bx = box(a, b);
    if (bx.cells > max_box_cells) return sb.sayTo(slot, "box too large: {d} cells, at most {d}", .{ bx.cells, max_box_cells });
    var need: [Materials.count]u32 = @splat(0);
    var back: [Materials.count]u32 = @splat(0);
    var changed: u32 = 0;
    var it = bx.iterate();
    while (it.next()) |c| {
        const old = sb.block_world.blocks.get(c[0], c[1], c[2]);
        if (old.isEmpty()) continue;
        const new = Materials.restyle(old.material, style);
        if (new == old.material) continue;
        need[new] += 1;
        back[old.material] += 1;
        changed += 1;
    }
    if (changed == 0) return sb.sayTo(slot, "nothing to restyle", .{});
    const kit = &sb.kits[slot];
    for (need, back, kit.blocks, 0..) |n, r, held, m| if (n > held + r) return sb.sayTo(slot, "restyle needs {d} {s}, you hold {d}", .{ n, Materials.all[m].name, held });
    it = bx.iterate();
    while (it.next()) |c| {
        var cell_now = sb.block_world.blocks.get(c[0], c[1], c[2]);
        if (cell_now.isEmpty()) continue;
        cell_now.material = Materials.restyle(cell_now.material, style);
        try sb.block_world.blocks.set(c[0], c[1], c[2], cell_now);
    }
    for (&kit.blocks, need, back) |*held, n, r| held.* = held.* + r - n;
    try sb.syncBlocks();
    sb.sayTo(slot, "restyled {d} blocks as {s}", .{ changed, Materials.styleName(style) });
}

/// Copy the blocks in the box to the player's clipboard and select it.
pub fn captureBox(sb: *Sandbox, slot: usize, st: *State, a: [3]i32, b: [3]i32) !void {
    const bx = box(a, b);
    for (0..3) |i| if (bx.hi[i] - bx.lo[i] + 1 > Prefabs.max_side) return sb.sayTo(slot, "copy at most {d} blocks on a side", .{Prefabs.max_side});
    var clip: Prefabs.Clip = .{};
    var it = bx.iterate();
    while (it.next()) |c| {
        const found = sb.block_world.blocks.get(c[0], c[1], c[2]);
        if (found.isEmpty()) continue;
        if (clip.len == Prefabs.max_cells) return sb.sayTo(slot, "copy at most {d} blocks", .{Prefabs.max_cells});
        clip.cells[clip.len] = .{ .x = @intCast(c[0] - bx.lo[0]), .y = @intCast(c[1] - bx.lo[1]), .z = @intCast(c[2] - bx.lo[2]), .cell = found };
        clip.len += 1;
    }
    if (clip.len == 0) return sb.sayTo(slot, "nothing to copy", .{});
    for (0..3) |i| clip.size[i] = @intCast(bx.hi[i] - bx.lo[i] + 1);
    sb.block_clips[slot] = clip;
    st.shape = @intCast(entryCount(sb, slot, st.*) - 1);
    st.rot = 0;
    sb.sayTo(slot, "copied {d} blocks: click to paste", .{clip.len});
}

/// Remove every block in the box; each returns to the remover's kit.
pub fn clearBox(sb: *Sandbox, slot: usize, a: [3]i32, b: [3]i32) !void {
    const bx = box(a, b);
    if (bx.cells > max_box_cells) return sb.sayTo(slot, "box too large: {d} cells, at most {d}", .{ bx.cells, max_box_cells });
    var removed: u32 = 0;
    var y = bx.lo[1];
    while (y <= bx.hi[1]) : (y += 1) {
        var z = bx.lo[2];
        while (z <= bx.hi[2]) : (z += 1) {
            var x = bx.lo[0];
            while (x <= bx.hi[0]) : (x += 1) {
                const old = sb.block_world.blocks.get(x, y, z);
                if (old.isEmpty()) continue;
                try sb.block_world.blocks.set(x, y, z, .empty);
                sb.kits[slot].blocks[old.material] +|= 1;
                removed += 1;
            }
        }
    }
    try sb.syncBlocks();
    sb.sayTo(slot, "cleared {d} blocks", .{removed});
}

/// Player 1's keyboard and mouse.
pub fn update(sb: *Sandbox, aim: @import("../world/Camera.zig"), primary: bool, actions: Sandbox.Actions, modifier: bool) !void {
    const f = aim.forward();
    try step(sb, 0, &sb.tools.blocks, .{ aim.position.x(), aim.position.y(), aim.position.z() }, .{ f.x(), f.y(), f.z() }, .{
        .place = primary,
        .remove = actions.secondary,
        .next_shape = actions.next_item and !modifier,
        .material_step = if (actions.channel_up) 1 else if (actions.channel_down) -1 else 0,
        .rotate = actions.rotate,
        .pick = actions.capture,
        .box = modifier,
        .next_style = actions.next_item and modifier,
    });
}

pub fn hint(sb: *const Sandbox, buffer: []u8) []const u8 {
    const st = sb.tools.blocks;
    const c = cell(st);
    if (st.corner != null) return std.fmt.bufPrint(buffer, "BOX {s}: MARK THE OPPOSITE CORNER THE SAME WAY", .{@tagName(st.corner_mode)}) catch buffer;
    return std.fmt.bufPrint(buffer, "{s} {s} {s} x{d}  CLICK PLACE  RMB REMOVE  TAB PIECE  SHIFT+TAB STYLE  [ ] MATERIAL  T TURN  P PICK  SHIFT: BOX FILL/CLEAR, SHIFT+T RESTYLE, SHIFT+P COPY", .{ Materials.styleName(st.style), entryName(sb, 0, st), Materials.all[c.material].name, sb.kits[0].blocks[c.material] }) catch buffer;
}

/// The ghost of the next block: tinted by its material where it fits, red where it does not;
/// with a box corner set, the corner shows as well.
pub fn ghost(sb: *const Sandbox, slot: usize, st: State, out: []World.Prop, start: usize) usize {
    var n = start;
    const c = st.place orelse return n;
    if (n == out.len) return n;
    if (entry(sb, slot, st) == .seed) {
        out[n] = .{
            .mesh = sb.catalog.content.block,
            .transform = .{ .position = .{ @as(f32, @floatFromInt(c[0])) + 0.5, @as(f32, @floatFromInt(c[1])) + 0.15, @as(f32, @floatFromInt(c[2])) + 0.5 } },
            .tint = if (Farm.refusal(sb, slot, c) == null) .{ 0.45, 0.95, 0.4, 1 } else .{ 1.0, 0.3, 0.25, 1 },
            .size = .{ 0.3, 0.3, 0.3 },
        };
        return n + 1;
    }
    if (entry(sb, slot, st) == .prefab) {
        const prefab = entry(sb, slot, st).prefab;
        const size = Prefabs.turnedSize(prefab.size, st.rot);
        const o = stampOrigin(prefab, st.rot, c);
        const f: [3]f32 = .{ @floatFromInt(size[0]), @floatFromInt(size[1]), @floatFromInt(size[2]) };
        out[n] = .{
            .mesh = sb.catalog.content.block,
            .transform = .{ .position = .{ @as(f32, @floatFromInt(o[0])) + f[0] / 2, @as(f32, @floatFromInt(o[1])) + 0.05, @as(f32, @floatFromInt(o[2])) + f[2] / 2 } },
            .tint = .{ 0.4, 0.85, 1.0, 1 },
            .size = .{ f[0], 0.1, f[2] },
        };
        return n + 1;
    }
    const shape = cell(st).shape;
    const height: f32 = if (shape == .slab) 0.5 else 1;
    const color = Materials.all[cell(st).material].color;
    const tint: [4]f32 = if (st.valid) .{ color[0] * 0.6 + 0.3, color[1] * 0.6 + 0.4, color[2] * 0.6 + 0.3, 1 } else .{ 1.0, 0.3, 0.25, 1 };
    out[n] = .{
        .mesh = sb.catalog.content.block,
        .transform = .{ .position = .{ @as(f32, @floatFromInt(c[0])) + 0.5, @as(f32, @floatFromInt(c[1])) + height / 2, @as(f32, @floatFromInt(c[2])) + 0.5 } },
        .tint = tint,
        .size = .{ 1.02, height + 0.02, 1.02 },
    };
    n += 1;
    if (st.corner) |a| if (n < out.len) {
        out[n] = .{
            .mesh = sb.catalog.content.block,
            .transform = .{ .position = .{ @as(f32, @floatFromInt(a[0])) + 0.5, @as(f32, @floatFromInt(a[1])) + 0.5, @as(f32, @floatFromInt(a[2])) + 0.5 } },
            .tint = switch (st.corner_mode) {
                .fill => .{ 0.3, 0.8, 1.0, 1 },
                .clear => .{ 1.0, 0.45, 0.2, 1 },
                .restyle => .{ 0.85, 0.5, 1.0, 1 },
                .capture => .{ 1.0, 0.9, 0.3, 1 },
            },
            .size = .{ 1.08, 1.08, 1.08 },
        };
        n += 1;
    };
    return n;
}

pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    return publishGuests(sb, out, ghost(sb, 0, sb.tools.blocks, out, start));
}

/// Ghosts of the guests who are building.
pub fn publishGuests(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    var n = start;
    for (sb.guests, 1..) |g, slot| if (g.active) if (g.building) |st| {
        n = ghost(sb, slot, st, out, n);
    };
    return n;
}

/// One pad's buttons this step (edges for the D-pad, levels for the triggers and modifier).
pub const Pad = struct { fire: bool = false, alt: bool = false, up: bool = false, down: bool = false, left: bool = false, right: bool = false, modifier: bool = false };
pub const PadRequest = struct { toggle: bool, cmd: Command };

/// Block-tool requests from a pad: the sprint button (the modifier) held with D-pad left toggles
/// building; while building, RT places, RB removes, D-pad up cycles shape (with the modifier it
/// picks the aimed block), left and right step the material, down turns, and the modifier held
/// marks box corners. `before` is last step's fire and alternate, so a held trigger is one click.
pub fn fromPad(pad: Pad, before: [2]bool) PadRequest {
    return .{
        .toggle = pad.modifier and pad.left,
        .cmd = .{
            .place = pad.fire and !before[0],
            .remove = pad.alt and !before[1],
            .next_shape = pad.up and !pad.modifier,
            .pick = pad.up and pad.modifier,
            .material_step = if (pad.right and !pad.modifier) 1 else if (pad.left and !pad.modifier) -1 else 0,
            .next_style = pad.right and pad.modifier,
            .rotate = pad.down,
            .box = pad.modifier,
        },
    };
}

test "the pad chord toggles building, and triggers become one click per press" {
    try std.testing.expect(fromPad(.{ .left = true, .modifier = true }, .{ false, false }).toggle);
    const first = fromPad(.{ .fire = true, .alt = true, .up = true }, .{ false, false });
    try std.testing.expect(first.cmd.place and first.cmd.remove and first.cmd.next_shape and !first.toggle);
    const held = fromPad(.{ .fire = true, .alt = true }, .{ true, true });
    try std.testing.expect(!held.cmd.place and !held.cmd.remove);
    const pick = fromPad(.{ .up = true, .modifier = true }, .{ false, false });
    try std.testing.expect(pick.cmd.pick and pick.cmd.box and !pick.cmd.next_shape);
    try std.testing.expectEqual(@as(i2, -1), fromPad(.{ .left = true }, .{ false, false }).cmd.material_step);
    const style = fromPad(.{ .right = true, .modifier = true }, .{ false, false });
    try std.testing.expect(style.cmd.next_style and style.cmd.material_step == 0);
}

test "a box counts every cell between two corners in any order" {
    try std.testing.expectEqual(@as(usize, 4), box(.{ 0, 0, 0 }, .{ 1, 0, 1 }).cells);
    try std.testing.expectEqual(@as(usize, 24), box(.{ 3, 2, 1 }, .{ 0, 0, 0 }).cells);
    try std.testing.expectEqual(Kit.starter_blocks, (Kit{}).blocks[0]);
}
