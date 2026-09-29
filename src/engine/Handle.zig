const std = @import("std");

/// A typed generational reference. The tag type keeps mesh, material, and body handles distinct.
/// Generation 0 is never issued, so a zero-initialized handle is always invalid.
pub fn Handle(comptime Tag: type) type {
    return struct {
        index: u16 = 0,
        generation: u16 = 0,
        pub const tag = Tag;
        pub const none: @This() = .{};

        pub fn eql(a: @This(), b: @This()) bool {
            return a.index == b.index and a.generation == b.generation;
        }
    };
}

/// Fixed-capacity storage addressed by generational handles. Removal invalidates old handles.
pub fn Pool(comptime Tag: type, comptime T: type, comptime capacity: u16) type {
    return struct {
        const Self = @This();
        pub const Id = Handle(Tag);
        items: [capacity]T = undefined,
        generations: [capacity]u16 = @splat(0),
        live: std.StaticBitSet(capacity) = .initEmpty(),

        pub fn add(self: *Self, value: T) error{PoolFull}!Id {
            var free = self.live.complement().iterator(.{});
            const i = free.next() orelse return error.PoolFull;
            // Skip generation 0 on wrap so stale zero handles never validate.
            self.generations[i] +%= 1;
            if (self.generations[i] == 0) self.generations[i] = 1;
            self.items[i] = value;
            self.live.set(i);
            return .{ .index = @intCast(i), .generation = self.generations[i] };
        }

        pub fn remove(self: *Self, id: Id) bool {
            if (!self.valid(id)) return false;
            self.live.unset(id.index);
            return true;
        }

        pub fn valid(self: *const Self, id: Id) bool {
            return id.index < capacity and id.generation != 0 and self.live.isSet(id.index) and self.generations[id.index] == id.generation;
        }

        pub fn get(self: *Self, id: Id) ?*T {
            return if (self.valid(id)) &self.items[id.index] else null;
        }

        pub fn getConst(self: *const Self, id: Id) ?*const T {
            return if (self.valid(id)) &self.items[id.index] else null;
        }

        pub fn count(self: *const Self) usize {
            return self.live.count();
        }

        /// Handle for a live slot; used by batch iteration over `live`.
        pub fn idAt(self: *const Self, index: usize) Id {
            return .{ .index = @intCast(index), .generation = self.generations[index] };
        }
    };
}

test "pool handles are typed, reject stale generations, and report capacity" {
    const Mesh = struct {};
    var pool: Pool(Mesh, u32, 2) = .{};
    try std.testing.expect(!pool.valid(.none));
    const a = try pool.add(1);
    const b = try pool.add(2);
    try std.testing.expectError(error.PoolFull, pool.add(3));
    try std.testing.expect(pool.remove(a));
    try std.testing.expect(!pool.remove(a));
    try std.testing.expect(pool.get(a) == null);
    const c = try pool.add(4);
    try std.testing.expectEqual(a.index, c.index);
    try std.testing.expect(!c.eql(a));
    try std.testing.expectEqual(@as(u32, 4), pool.get(c).?.*);
    try std.testing.expectEqual(@as(u32, 2), pool.get(b).?.*);
    try std.testing.expectEqual(@as(usize, 2), pool.count());
}
