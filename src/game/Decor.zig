//! Player-placed living-sap plants. Decorations are shared world objects; their cost is charged
//! to the builder's own kit, and removing one refunds the player who removes it.
const std = @import("std");
const Sandbox = @import("Sandbox.zig");
const World = @import("../world/World.zig");
const SapFlora = @import("../procedural/SapFlora.zig");
const Materials = @import("../build/Materials.zig");
const Terrain = @import("../procedural/Terrain.zig");

pub const capacity = 512;
pub const per_chunk = 64;
pub const glow_alpha: f32 = 2.5;
const leaf_material = Materials.ofRole(.eco_city, .nature);
const bloom_material = Materials.ofRole(.eco_city, .color);

pub const Plant = struct { cell: [3]i32, species: SapFlora.Species, turn: u2 = 0, builder: u3 = 0 };
pub const State = struct {
    plants: [capacity]Plant = undefined,
    len: usize = 0,

    pub fn find(self: *const State, c: [3]i32) ?usize {
        for (self.plants[0..self.len], 0..) |existing_plant, i| if (std.meta.eql(existing_plant.cell, c)) return i;
        return null;
    }

    pub fn remove(self: *State, i: usize) void {
        self.plants[i] = self.plants[self.len - 1];
        self.len -= 1;
    }
};

pub fn costMaterial(species: SapFlora.Species) u6 {
    return switch (SapFlora.info(species).family) {
        .grass, .bush, .tree => leaf_material,
        .flower => bloom_material,
    };
}

fn supported(sb: *const Sandbox, c: [3]i32) bool {
    if (!sb.block_world.blocks.get(c[0], c[1] - 1, c[2]).isEmpty()) return true;
    const ground = Terrain.surface(sb.seed, @as(f32, @floatFromInt(c[0])) + 0.5, @as(f32, @floatFromInt(c[2])) + 0.5).height;
    return @as(f32, @floatFromInt(c[1])) <= @ceil(ground);
}

pub fn groundedCell(sb: *const Sandbox, c: [3]i32) [3]i32 {
    var result = c;
    if (sb.block_world.blocks.get(c[0], c[1] - 1, c[2]).isEmpty()) {
        const ground = Terrain.surface(sb.seed, @as(f32, @floatFromInt(c[0])) + 0.5, @as(f32, @floatFromInt(c[2])) + 0.5).height;
        result[1] = @intFromFloat(@ceil(ground));
    }
    return result;
}

pub fn refusal(sb: *const Sandbox, slot: usize, species: SapFlora.Species, c: [3]i32) ?[]const u8 {
    if (sb.decor.len == capacity) return "plant limit reached";
    if (sb.decor.find(c) != null) return "a plant is already there";
    if (sb.block_world.blocks.get(c[0], c[1], c[2]).isAuthored()) return "that block is part of the city";
    if (!sb.block_world.blocks.get(c[0], c[1], c[2]).isEmpty()) return "occupied";
    if (sb.farm.find(c) != null) return "a crop grows there";
    if (!supported(sb, c)) return "plants need ground or a block below";
    const Blocks = @import("../build/Blocks.zig");
    const chunk = Blocks.chunkOf(c[0], c[2]);
    var count: usize = 0;
    for (sb.decor.plants[0..sb.decor.len]) |existing_plant| {
        const other = Blocks.chunkOf(existing_plant.cell[0], existing_plant.cell[2]);
        if (other.x == chunk.x and other.z == chunk.z) count += 1;
    }
    if (count >= per_chunk) return "plant limit reached for this area";
    const material = costMaterial(species);
    if (sb.kits[slot].blocks[material] == 0) return "no nature material left";
    return null;
}

pub fn plant(sb: *Sandbox, slot: usize, species: SapFlora.Species, turn: u2, c: [3]i32) void {
    if (refusal(sb, slot, species, c)) |why| return sb.sayTo(slot, "cannot plant: {s}", .{why});
    const material = costMaterial(species);
    sb.kits[slot].blocks[material] -= 1;
    sb.decor.plants[sb.decor.len] = .{ .cell = c, .species = species, .turn = turn, .builder = @intCast(slot) };
    sb.decor.len += 1;
    sb.sayTo(slot, "planted {s}", .{SapFlora.info(species).name});
}

/// Remove a plant at the aimed cell or immediately above/below a block face.
pub fn harvest(sb: *Sandbox, slot: usize, c: [3]i32) bool {
    for ([_][3]i32{ c, .{ c[0], c[1] + 1, c[2] }, .{ c[0], c[1] - 1, c[2] } }) |candidate| {
        const i = sb.decor.find(candidate) orelse continue;
        const plant_entry = sb.decor.plants[i];
        sb.kits[slot].blocks[costMaterial(plant_entry.species)] +|= 1;
        sb.decor.remove(i);
        sb.sayTo(slot, "removed {s}; material returned", .{SapFlora.info(plant_entry.species).name});
        return true;
    }
    return false;
}

pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    var n = start;
    for (sb.decor.plants[0..sb.decor.len]) |plant_entry| {
        const species = plant_entry.species;
        const info = SapFlora.info(species);
        const q = @import("../physics/Physics.zig").Rotation.axisAngle(.{ 0, 1, 0 }, @as(f32, @floatFromInt(plant_entry.turn)) * (@as(f32, std.math.pi) / 2.0));
        const position: [3]f32 = .{ @as(f32, @floatFromInt(plant_entry.cell[0])) + 0.5, @floatFromInt(plant_entry.cell[1]), @as(f32, @floatFromInt(plant_entry.cell[2])) + 0.5 };
        if (n < out.len) {
            out[n] = .{ .mesh = sb.catalog.content.sap_body[@intFromEnum(species)], .transform = .{ .position = position, .scale = info.height }, .tint = .{ 1, 1, 1, 1 }, .rotation = q };
            n += 1;
        }
        if (n < out.len) {
            out[n] = .{ .mesh = sb.catalog.content.sap_glow[@intFromEnum(species)], .transform = .{ .position = position, .scale = info.height }, .tint = .{ 1, 1, 1, glow_alpha }, .rotation = q };
            n += 1;
        }
    }
    return n;
}

pub const Doc = struct { x: i32, y: i32, z: i32, species: SapFlora.Species, turn: u2 = 0, builder: u3 = 0 };

pub fn toDocs(state: *const State, allocator: std.mem.Allocator) ![]const Doc {
    const docs = try allocator.alloc(Doc, state.len);
    for (docs, state.plants[0..state.len]) |*doc, p| doc.* = .{ .x = p.cell[0], .y = p.cell[1], .z = p.cell[2], .species = p.species, .turn = p.turn, .builder = p.builder };
    return docs;
}
