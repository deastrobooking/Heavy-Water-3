//! The block grid as the game uses it: the cells, plus one drawn mesh and one static collider per
//! terrain chunk column that holds blocks. Edits mark chunks dirty; `sync` rebuilds exactly those.
//! The renderer copies a chunk's mesh when its `revision` changes.
const std = @import("std");
const Blocks = @import("Blocks.zig");
const Mesher = @import("Mesher.zig");
const ChunkKey = @import("../world/ChunkKey.zig");
const Physics = @import("../physics/Physics.zig");
const BlockWorld = @This();

/// Chunk columns that may hold blocks at once (each costs one collider and one catalog mesh).
pub const max_chunks = 16;

pub const Slot = struct {
    active: bool = false,
    key: ChunkKey = .{ .x = 0, .z = 0 },
    collider: Physics.MeshCollider = .none,
    mesh: Mesher.Output = .{},
    /// Bumped whenever `mesh` changes.
    revision: u64 = 0,
};

blocks: *Blocks,
slots: [max_chunks]Slot = @splat(.{}),
/// Physics user value for block colliders (occludes picking, never a removable target).
user: u32,

pub fn init(allocator: std.mem.Allocator, user: u32) !BlockWorld {
    return .{ .blocks = try Blocks.create(allocator), .user = user };
}

pub fn deinit(self: *BlockWorld, allocator: std.mem.Allocator, physics: *Physics) void {
    for (&self.slots) |*slot| {
        if (!slot.collider.eql(.none)) physics.destroyMesh(slot.collider);
        slot.mesh.deinit(allocator);
    }
    self.blocks.destroy();
}

pub fn slotOf(self: *const BlockWorld, key: ChunkKey) ?usize {
    for (self.slots, 0..) |slot, i| if (slot.active and slot.key.x == key.x and slot.key.z == key.z) return i;
    return null;
}

/// Whether a block may go in chunk `key`: it already holds blocks, or a chunk slot is free.
pub fn hasRoom(self: *const BlockWorld, key: ChunkKey) bool {
    if (self.slotOf(key) != null) return true;
    for (self.slots) |slot| if (!slot.active) return true;
    return false;
}

/// Rebuild the meshes and colliders of every chunk the grid marked dirty.
pub fn sync(self: *BlockWorld, allocator: std.mem.Allocator, physics: *Physics) !void {
    var keys: [Blocks.dirty_capacity]ChunkKey = undefined;
    const dirty = self.blocks.takeDirty(&keys);
    if (dirty.all) {
        // Rebuild everything: drop every slot, then mesh each chunk that holds blocks.
        for (&self.slots) |*slot| if (slot.active) try self.rebuild(allocator, physics, slot.key);
        var held: [max_chunks + 1]ChunkKey = undefined;
        for (self.blocks.chunks(&held)) |key| try self.rebuild(allocator, physics, key);
        return;
    }
    for (dirty.keys) |key| try self.rebuild(allocator, physics, key);
}

fn rebuild(self: *BlockWorld, allocator: std.mem.Allocator, physics: *Physics, key: ChunkKey) !void {
    var section_buffer: [Blocks.section_capacity]usize = undefined;
    const has_blocks = self.blocks.sectionsIn(key, &section_buffer).len > 0;
    const existing = self.slotOf(key);
    if (!has_blocks) {
        const i = existing orelse return;
        const slot = &self.slots[i];
        if (!slot.collider.eql(.none)) physics.destroyMesh(slot.collider);
        slot.collider = .none;
        slot.mesh.vertices.clearRetainingCapacity();
        slot.mesh.indices.clearRetainingCapacity();
        slot.active = false;
        slot.revision += 1;
        return;
    }
    const i = existing orelse for (self.slots, 0..) |slot, n| {
        if (!slot.active) break n;
    } else return error.BlockChunksFull;
    const slot = &self.slots[i];
    try Mesher.meshChunk(allocator, self.blocks, key, .draw, &slot.mesh);
    // The collider uses world positions and the walkable stair ramp.
    var shape: Mesher.Output = .{};
    defer shape.deinit(allocator);
    try Mesher.meshChunk(allocator, self.blocks, key, .collide, &shape);
    const o = Mesher.origin(key);
    const positions = try allocator.alloc(Physics.Vec3, shape.vertices.items.len);
    defer allocator.free(positions);
    for (shape.vertices.items, positions) |v, *p| p.* = .{ v.position[0] + o[0], v.position[1], v.position[2] + o[2] };
    const collider = try physics.createMesh(allocator, positions, shape.indices.items, self.user);
    if (!slot.collider.eql(.none)) physics.destroyMesh(slot.collider);
    slot.* = .{ .active = true, .key = key, .collider = collider, .mesh = slot.mesh, .revision = slot.revision + 1 };
}

test "placing blocks builds a walkable collider and clearing them frees the chunk" {
    const a = std.testing.allocator;
    var physics: Physics = .init(.{ .context = null, .sample = flat });
    defer physics.deinit();
    var world = try init(a, 7);
    defer world.deinit(a, &physics);
    for (0..4) |x| try world.blocks.set(@intCast(x), 0, 0, .{ .shape = .cube });
    try world.blocks.set(0, 0, 1, .{ .shape = .stair });
    try world.sync(a, &physics);
    const i = world.slotOf(.{ .x = 0, .z = 0 }).?;
    try std.testing.expect(world.slots[i].mesh.indices.items.len > 0);
    // A ray from above lands on the cube tops at y = 1.
    const hit = physics.castRay(.{ 2.5, 5, 0.5 }, .{ 0, -1, 0 }, 10, .none).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1), hit.point[1], 1e-4);
    // The stair collides as a ramp: halfway along it the surface is half a metre up.
    const stair = physics.castRay(.{ 0.5, 5, 1.5 }, .{ 0, -1, 0 }, 10, .none).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), stair.point[1], 1e-3);
    for (0..4) |x| try world.blocks.set(@intCast(x), 0, 0, .empty);
    try world.blocks.set(0, 0, 1, .empty);
    try world.sync(a, &physics);
    try std.testing.expect(world.slotOf(.{ .x = 0, .z = 0 }) == null);
    try std.testing.expect(physics.castRay(.{ 2.5, 5, 0.5 }, .{ 0, -1, 0 }, 4, .none) == null);
}

fn flat(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
    return .{ .height = -100, .normal = .{ 0, 1, 0 } };
}
