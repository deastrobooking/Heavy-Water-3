//! The block tool: aim at a surface and click to place the chosen shape in the 1 m grid beside
//! it; right click removes the block under the crosshair. Tab picks the shape, [ and ] the
//! material, T turns it.
const std = @import("std");
const Sandbox = @import("Sandbox.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Blocks = @import("../build/Blocks.zig");
const Materials = @import("../build/Materials.zig");
const Terrain = @import("../procedural/Terrain.zig");

pub const reach: f32 = 14;

pub const State = struct {
    shape: u8 = 0,
    material: u8 = 0,
    rot: u2 = 0,
    style: Materials.Style = .castle,
    /// The empty cell a click would fill, and whether it may be filled there.
    place: ?[3]i32 = null,
    valid: bool = false,
    /// The block under the crosshair, which right click removes.
    remove: ?[3]i32 = null,
};

pub fn cell(st: State) Blocks.Cell {
    const palette = Materials.ofStyle(st.style);
    return .{ .shape = Blocks.placeable_shapes[st.shape % Blocks.placeable_shapes.len], .rot = st.rot, .material = palette[st.material % palette.len] };
}

fn floorCell(p: [3]f32) [3]i32 {
    return .{ @intFromFloat(@floor(p[0])), @intFromFloat(@floor(p[1])), @intFromFloat(@floor(p[2])) };
}

/// Why `c` cannot take a block, or null when it can.
pub fn refusal(sb: *const Sandbox, c: [3]i32) ?[]const u8 {
    const blocks = sb.block_world.blocks;
    if (!blocks.get(c[0], c[1], c[2]).isEmpty()) return "occupied";
    if (!sb.block_world.hasRoom(Blocks.chunkOf(c[0], c[2]))) return "block budget full: build near your other blocks";
    const lo: [3]f32 = .{ @floatFromInt(c[0]), @floatFromInt(c[1]), @floatFromInt(c[2]) };
    // Never build into a player.
    var feet: [4]?[3]f32 = .{ sb.player.feet, null, null, null };
    for (sb.guests, 1..) |g, i| if (g.active) {
        feet[i] = g.player.feet;
    };
    for (feet) |maybe| if (maybe) |f| {
        if (f[0] + 0.35 > lo[0] and f[0] - 0.35 < lo[0] + 1 and f[2] + 0.35 > lo[2] and f[2] - 0.35 < lo[2] + 1 and f[1] + 1.8 > lo[1] and f[1] < lo[1] + 1) return "a player is standing there";
    };
    // Machines, crates and other solid bodies.
    if (sb.physics.overlapsBox(.{ lo[0] + 0.5, lo[1] + 0.5, lo[2] + 0.5 }, .{ 0.45, 0.45, 0.45 })) return "something is in the way";
    // Supported by the ground or by another block (platformer pieces may float later).
    const ground = Terrain.surface(sb.seed, lo[0] + 0.5, lo[2] + 0.5).height;
    if (lo[1] <= ground + 1) return null;
    for ([_][3]i32{ .{ 1, 0, 0 }, .{ -1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, -1, 0 }, .{ 0, 0, 1 }, .{ 0, 0, -1 } }) |o| {
        if (!blocks.get(c[0] + o[0], c[1] + o[1], c[2] + o[2]).isEmpty()) return null;
    }
    return "needs ground or another block beside it";
}

pub fn update(sb: *Sandbox, camera: Camera, primary: bool, actions: Sandbox.Actions) !void {
    const st = &sb.tools.blocks;
    const palette = Materials.ofStyle(st.style);
    if (actions.next_item) {
        st.shape = @intCast((st.shape + 1) % Blocks.placeable_shapes.len);
        sb.say("shape: {s}", .{@tagName(cell(st.*).shape)});
    }
    if (actions.channel_up or actions.channel_down) {
        const n: u8 = @intCast(palette.len);
        st.material = if (actions.channel_up) (st.material + 1) % n else (st.material + n - 1) % n;
        sb.say("material: {s}", .{Materials.all[cell(st.*).material].name});
    }
    if (actions.rotate) st.rot +%= 1;

    const f = camera.forward();
    const eye: [3]f32 = .{ camera.position.x(), camera.position.y(), camera.position.z() };
    st.place = null;
    st.remove = null;
    st.valid = false;
    if (sb.physics.castRay(eye, .{ f.x(), f.y(), f.z() }, reach, .none)) |hit| {
        const n = hit.normal;
        const outside = floorCell(.{ hit.point[0] + n[0] * 0.25, hit.point[1] + n[1] * 0.25, hit.point[2] + n[2] * 0.25 });
        const inside = floorCell(.{ hit.point[0] - n[0] * 0.25, hit.point[1] - n[1] * 0.25, hit.point[2] - n[2] * 0.25 });
        if (!sb.block_world.blocks.get(inside[0], inside[1], inside[2]).isEmpty()) st.remove = inside;
        st.place = outside;
        st.valid = refusal(sb, outside) == null;
    }
    if (primary) {
        const c = st.place orelse return sb.say("aim at the ground or a block within {d:.0} m", .{reach});
        if (refusal(sb, c)) |why| return sb.say("blocked: {s}", .{why});
        sb.block_world.blocks.set(c[0], c[1], c[2], cell(st.*)) catch return sb.say("block budget full", .{});
        try sb.syncBlocks();
    }
    if (actions.secondary) if (st.remove) |c| {
        try sb.block_world.blocks.set(c[0], c[1], c[2], .empty);
        try sb.syncBlocks();
    };
}

pub fn hint(sb: *const Sandbox, buffer: []u8) []const u8 {
    const c = cell(sb.tools.blocks);
    return std.fmt.bufPrint(buffer, "BLOCK {s} {s}  CLICK PLACE  RMB REMOVE  TAB SHAPE  [ ] MATERIAL  T TURN", .{ @tagName(c.shape), Materials.all[c.material].name }) catch buffer;
}

/// The ghost of the next block: green where it fits, red where it does not.
pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    const st = sb.tools.blocks;
    const c = st.place orelse return start;
    if (start == out.len) return start;
    const shape = cell(st).shape;
    const height: f32 = if (shape == .slab) 0.5 else 1;
    const color = Materials.all[cell(st).material].color;
    const tint: [4]f32 = if (st.valid) .{ color[0] * 0.6 + 0.3, color[1] * 0.6 + 0.4, color[2] * 0.6 + 0.3, 1 } else .{ 1.0, 0.3, 0.25, 1 };
    out[start] = .{
        .mesh = sb.catalog.content.block,
        .transform = .{ .position = .{ @as(f32, @floatFromInt(c[0])) + 0.5, @as(f32, @floatFromInt(c[1])) + height / 2, @as(f32, @floatFromInt(c[2])) + 0.5 } },
        .tint = tint,
        .size = .{ 1.02, height + 0.02, 1.02 },
    };
    return start + 1;
}
