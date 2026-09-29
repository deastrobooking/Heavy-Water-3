const std = @import("std");
const Key = @import("ChunkKey.zig");
const Modifications = @This();

/// Deltas applied on top of regenerated procedural content. A scatter object is addressed by
/// its stable chunk-local identity, so removals survive unload/regenerate and save/load.
pub const capacity = 4096;
pub const ObjectRef = struct {
    x: i32,
    z: i32,
    id: u16,

    fn order(_: void, a: ObjectRef, b: ObjectRef) std.math.Order {
        if (a.x != b.x) return std.math.order(a.x, b.x);
        if (a.z != b.z) return std.math.order(a.z, b.z);
        return std.math.order(a.id, b.id);
    }

    pub fn of(key: Key, id: u16) ObjectRef {
        return .{ .x = key.x, .z = key.z, .id = id };
    }
};

/// Sorted and unique; binary-searched per scatter object during render gathering.
removed: [capacity]ObjectRef = undefined,
len: usize = 0,
/// Increments on every change so the renderer copies only when needed.
revision: u64 = 0,

pub fn contains(self: *const Modifications, ref: ObjectRef) bool {
    return self.find(ref) != null;
}

fn find(self: *const Modifications, ref: ObjectRef) ?usize {
    return std.sort.binarySearch(ObjectRef, self.removed[0..self.len], ref, struct {
        fn compare(r: ObjectRef, item: ObjectRef) std.math.Order {
            return ObjectRef.order({}, r, item);
        }
    }.compare);
}

pub fn remove(self: *Modifications, ref: ObjectRef) error{ModificationsFull}!bool {
    if (self.contains(ref)) return false;
    if (self.len == capacity) return error.ModificationsFull;
    var at = self.len;
    while (at > 0 and ObjectRef.order({}, self.removed[at - 1], ref) == .gt) : (at -= 1) self.removed[at] = self.removed[at - 1];
    self.removed[at] = ref;
    self.len += 1;
    self.revision += 1;
    return true;
}

pub fn clear(self: *Modifications) void {
    self.len = 0;
    self.revision += 1;
}

pub fn slice(self: *const Modifications) []const ObjectRef {
    return self.removed[0..self.len];
}

test "removals stay sorted, unique, and bounded" {
    var mods: Modifications = .{};
    try std.testing.expect(try mods.remove(.{ .x = 2, .z = 0, .id = 5 }));
    try std.testing.expect(try mods.remove(.{ .x = -1, .z = 9, .id = 1 }));
    try std.testing.expect(try mods.remove(.{ .x = 2, .z = 0, .id = 3 }));
    try std.testing.expect(!try mods.remove(.{ .x = 2, .z = 0, .id = 3 }));
    try std.testing.expectEqual(@as(usize, 3), mods.len);
    try std.testing.expectEqual(@as(i32, -1), mods.removed[0].x);
    try std.testing.expectEqual(@as(u16, 3), mods.removed[1].id);
    try std.testing.expect(mods.contains(.{ .x = 2, .z = 0, .id = 5 }));
    try std.testing.expect(!mods.contains(.{ .x = 2, .z = 1, .id = 5 }));
    for (&mods.removed, 0..) |*r, i| r.* = .{ .x = -100, .z = 0, .id = @intCast(i) };
    mods.len = capacity;
    try std.testing.expectError(error.ModificationsFull, mods.remove(.{ .x = 99, .z = 0, .id = 0 }));
}
