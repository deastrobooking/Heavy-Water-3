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
    /// First corner of a box fill (or clear), waiting for the second click.
    corner: ?[3]i32 = null,
    corner_clears: bool = false,
};

/// One step's requests, from the keyboard or a pad.
pub const Command = struct {
    place: bool = false,
    remove: bool = false,
    next_shape: bool = false,
    /// -1 or +1 steps through the style's materials.
    material_step: i2 = 0,
    rotate: bool = false,
    pick: bool = false,
    /// Held: clicks mark box corners.
    box: bool = false,
};

pub fn cell(st: State) Blocks.Cell {
    const palette = Materials.ofStyle(st.style);
    return .{ .shape = Blocks.placeable_shapes[st.shape % Blocks.placeable_shapes.len], .rot = st.rot, .material = palette[st.material % palette.len] };
}

fn floorCell(p: [3]f32) [3]i32 {
    return .{ @intFromFloat(@floor(p[0])), @intFromFloat(@floor(p[1])), @intFromFloat(@floor(p[2])) };
}

/// Why `c` cannot take a block, or null when it can. `alone` asks for ground or a neighbour.
pub fn refusal(sb: *const Sandbox, c: [3]i32, alone: bool) ?[]const u8 {
    const blocks = sb.block_world.blocks;
    if (!blocks.get(c[0], c[1], c[2]).isEmpty()) return "occupied";
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
    const palette = Materials.ofStyle(st.style);
    const kit = &sb.kits[slot];
    if (cmd.next_shape) {
        st.shape = @intCast((st.shape + 1) % Blocks.placeable_shapes.len);
        sb.sayTo(slot, "shape: {s}", .{@tagName(cell(st.*).shape)});
    }
    if (cmd.material_step != 0) {
        const n: u8 = @intCast(palette.len);
        st.material = if (cmd.material_step > 0) (st.material + 1) % n else (st.material + n - 1) % n;
        const m = cell(st.*).material;
        sb.sayTo(slot, "material: {s} ({d} held)", .{ Materials.all[m].name, kit.blocks[m] });
    }
    if (cmd.rotate) st.rot +%= 1;

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
        if (cmd.box or (st.corner != null and !st.corner_clears)) {
            if (st.corner) |a| {
                st.corner = null;
                return fillBox(sb, slot, st.*, a, c);
            }
            st.corner = c;
            st.corner_clears = false;
            return sb.sayTo(slot, "box corner set: click the opposite corner", .{});
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
        if (cmd.box or (st.corner != null and st.corner_clears)) {
            if (st.corner) |a| {
                st.corner = null;
                return clearBox(sb, slot, a, c);
            }
            st.corner = c;
            st.corner_clears = true;
            return sb.sayTo(slot, "clear corner set: aim at the opposite corner", .{});
        }
        const old = sb.block_world.blocks.get(c[0], c[1], c[2]);
        try sb.block_world.blocks.set(c[0], c[1], c[2], .empty);
        kit.blocks[old.material] +|= 1;
        try sb.syncBlocks();
    }
}

const Box = struct { lo: [3]i32, hi: [3]i32, cells: usize };
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
        .next_shape = actions.next_item,
        .material_step = if (actions.channel_up) 1 else if (actions.channel_down) -1 else 0,
        .rotate = actions.rotate,
        .pick = actions.capture,
        .box = modifier,
    });
}

pub fn hint(sb: *const Sandbox, buffer: []u8) []const u8 {
    const st = sb.tools.blocks;
    const c = cell(st);
    if (st.corner != null) return std.fmt.bufPrint(buffer, "BOX: CLICK THE OPPOSITE CORNER TO {s}", .{if (st.corner_clears) "CLEAR" else "FILL"}) catch buffer;
    return std.fmt.bufPrint(buffer, "BLOCK {s} {s} x{d}  CLICK PLACE  RMB REMOVE  SHIFT+CLICK BOX  TAB SHAPE  [ ] MATERIAL  T TURN  P PICK", .{ @tagName(c.shape), Materials.all[c.material].name, sb.kits[0].blocks[c.material] }) catch buffer;
}

/// The ghost of the next block: tinted by its material where it fits, red where it does not;
/// with a box corner set, the corner shows as well.
pub fn ghost(sb: *const Sandbox, st: State, out: []World.Prop, start: usize) usize {
    var n = start;
    const c = st.place orelse return n;
    if (n == out.len) return n;
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
            .tint = if (st.corner_clears) .{ 1.0, 0.45, 0.2, 1 } else .{ 0.3, 0.8, 1.0, 1 },
            .size = .{ 1.08, 1.08, 1.08 },
        };
        n += 1;
    };
    return n;
}

pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    return publishGuests(sb, out, ghost(sb, sb.tools.blocks, out, start));
}

/// Ghosts of the guests who are building.
pub fn publishGuests(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    var n = start;
    for (sb.guests) |g| if (g.active) if (g.building) |st| {
        n = ghost(sb, st, out, n);
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
            .material_step = if (pad.right) 1 else if (pad.left and !pad.modifier) -1 else 0,
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
}

test "a box counts every cell between two corners in any order" {
    try std.testing.expectEqual(@as(usize, 4), box(.{ 0, 0, 0 }, .{ 1, 0, 1 }).cells);
    try std.testing.expectEqual(@as(usize, 24), box(.{ 3, 2, 1 }, .{ 0, 0, 0 }).cells);
    try std.testing.expectEqual(Kit.starter_blocks, (Kit{}).blocks[0]);
}
