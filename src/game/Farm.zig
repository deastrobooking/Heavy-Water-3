//! Crops. Plant a seed on tilled soil with the block tool (farm style, SEEDS), wait while it grows
//! through three stages, and harvest it ripe for hay blocks in your own kit: farming pays for
//! building. A seed costs one hay; a ripe crop returns four. Crops are shared world state and are
//! saved; the harvest is personal.
const std = @import("std");
const Sandbox = @import("Sandbox.zig");
const World = @import("../world/World.zig");
const Blocks = @import("../build/Blocks.zig");
const Materials = @import("../build/Materials.zig");

pub const capacity = 256;
/// Seconds from seed to ripe.
pub const grow_seconds: f32 = 180;
pub const seed_cost: u32 = 1;
pub const harvest_yield: u32 = 4;

pub const Crop = struct { cell: [3]i32, growth: f32 = 0 };

pub const State = struct {
    crops: [capacity]Crop = undefined,
    len: usize = 0,

    pub fn find(self: *const State, c: [3]i32) ?usize {
        for (self.crops[0..self.len], 0..) |crop, i| if (std.meta.eql(crop.cell, c)) return i;
        return null;
    }

    pub fn ripe(crop: Crop) bool {
        return crop.growth >= 1;
    }

    /// 0, 1 or 2 while growing; 3 when ripe.
    pub fn stage(crop: Crop) u2 {
        return if (crop.growth >= 1) 3 else @intFromFloat(@floor(crop.growth * 3));
    }

    fn remove(self: *State, i: usize) void {
        self.crops[i] = self.crops[self.len - 1];
        self.len -= 1;
    }
};

pub fn hay() u6 {
    return Materials.ofRole(.farm, .accent);
}

pub fn soil() u6 {
    return Materials.ofRole(.farm, .nature);
}

/// Why a seed cannot go in cell `c`, or null.
pub fn refusal(sb: *const Sandbox, slot: usize, c: [3]i32) ?[]const u8 {
    const below = sb.block_world.blocks.get(c[0], c[1] - 1, c[2]);
    if (below.isEmpty() or below.material != soil()) return "seeds need tilled soil";
    if (!sb.block_world.blocks.get(c[0], c[1], c[2]).isEmpty()) return "occupied";
    if (sb.farm.find(c) != null) return "something already grows there";
    if (sb.farm.len == capacity) return "the fields are full";
    if (sb.kits[slot].blocks[hay()] < seed_cost) return "a seed costs one hay";
    return null;
}

pub fn plant(sb: *Sandbox, slot: usize, c: [3]i32) void {
    if (refusal(sb, slot, c)) |why| return sb.sayTo(slot, "{s}", .{why});
    sb.kits[slot].blocks[hay()] -= seed_cost;
    sb.farm.crops[sb.farm.len] = .{ .cell = c };
    sb.farm.len += 1;
    sb.sayTo(slot, "planted", .{});
}

/// Harvest the crop in `c`. A ripe crop pays the harvester; an unripe one is just pulled up.
pub fn harvest(sb: *Sandbox, slot: usize, c: [3]i32) bool {
    const i = sb.farm.find(c) orelse return false;
    if (State.ripe(sb.farm.crops[i])) {
        sb.kits[slot].blocks[hay()] +|= harvest_yield;
        sb.sayTo(slot, "harvested {d} hay", .{harvest_yield});
    } else sb.sayTo(slot, "pulled up an unripe crop", .{});
    sb.farm.remove(i);
    return true;
}

pub fn step(sb: *Sandbox, dt: f32) void {
    var i: usize = 0;
    while (i < sb.farm.len) {
        const crop = &sb.farm.crops[i];
        // A crop whose soil was dug out dies.
        const below = sb.block_world.blocks.get(crop.cell[0], crop.cell[1] - 1, crop.cell[2]);
        if (below.isEmpty() or below.material != soil()) {
            sb.farm.remove(i);
            continue;
        }
        crop.growth = @min(1, crop.growth + dt / grow_seconds);
        i += 1;
    }
}

pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    var n = start;
    for (sb.farm.crops[0..sb.farm.len]) |crop| {
        if (n == out.len) break;
        const ripe = State.ripe(crop);
        // The scatter plant mesh is authored small (scatter draws it at 2.2).
        const scale = (0.35 + 0.65 * crop.growth) * 2.4;
        const tint: [4]f32 = if (ripe) .{ 1.0, 0.82, 0.32, 1 } else .{ 0.45, 0.85 - 0.2 * crop.growth, 0.35, 1 };
        out[n] = .{
            .mesh = sb.catalog.content.plant,
            .transform = .{ .position = .{ @as(f32, @floatFromInt(crop.cell[0])) + 0.5, @floatFromInt(crop.cell[1]), @as(f32, @floatFromInt(crop.cell[2])) + 0.5 }, .scale = scale },
            .tint = tint,
        };
        n += 1;
    }
    return n;
}

pub const Doc = struct { x: i32, y: i32, z: i32, growth: f32 };

test "stages follow growth and a crop is ripe at the end" {
    try std.testing.expectEqual(@as(u2, 0), State.stage(.{ .cell = .{ 0, 0, 0 }, .growth = 0.2 }));
    try std.testing.expectEqual(@as(u2, 2), State.stage(.{ .cell = .{ 0, 0, 0 }, .growth = 0.9 }));
    try std.testing.expectEqual(@as(u2, 3), State.stage(.{ .cell = .{ 0, 0, 0 }, .growth = 1 }));
    try std.testing.expect(harvest_yield > seed_cost);
}
