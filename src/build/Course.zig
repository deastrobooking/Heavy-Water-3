//! Can a player get from one block to another? A conservative check for built courses: from a
//! block you stand on you can reach another within a 4.5 m jump that rises at most 3 m (a spring
//! lifts you 11 m), and you can always drop. It ignores timing, so crumbling blocks count as
//! solid, gates count as closed, and a mover is a block you can ride its full run. Allocation-free; refuses searches larger than its capacity.
const std = @import("std");
const Blocks = @import("Blocks.zig");
const Materials = @import("Materials.zig");

pub const max_nodes = 4096;
pub const jump_rise = 3;
pub const spring_rise = 11;
pub const jump_reach: f32 = 4.5;
pub const max_drop = 24;
/// How far a mover carries a rider (`Platformer.mover_travel`).
pub const mover_run: f32 = 4;

pub const Error = error{CourseTooLarge};

fn kind(cell: Blocks.Cell) ?Materials.Role {
    if (cell.isEmpty()) return null;
    const r = Materials.roleOf(cell.material);
    return if (r.style == .platformer) @enumFromInt(r.role) else null;
}

/// Solid to stand on, with room for a player (two empty cells) above.
pub fn standable(blocks: *const Blocks, c: [3]i32) bool {
    const cell = blocks.get(c[0], c[1], c[2]);
    if (cell.isEmpty()) return false;
    if (kind(cell)) |k| if (k == .wood) return false; // hazards
    return blocks.get(c[0], c[1] + 1, c[2]).isEmpty() and blocks.get(c[0], c[1] + 2, c[2]).isEmpty();
}

pub fn reachable(blocks: *const Blocks, start: [3]i32, goal: [3]i32) Error!bool {
    if (!standable(blocks, start) or !standable(blocks, goal)) return false;
    var nodes: [max_nodes][3]i32 = undefined;
    nodes[0] = start;
    var len: usize = 1;
    var head: usize = 0;
    while (head < len) : (head += 1) {
        const a = nodes[head];
        if (std.meta.eql(a, goal)) return true;
        const here = kind(blocks.get(a[0], a[1], a[2]));
        const spring = if (here) |k| k == .main else false;
        // A mover carries you up to its run before you jump off.
        const reach = jump_reach + if (here != null and here.? == .color) mover_run else 0;
        const span: i32 = @intFromFloat(@ceil(reach));
        const rise: i32 = if (spring) spring_rise else jump_rise;
        var dy: i32 = -max_drop;
        while (dy <= rise) : (dy += 1) {
            var dz: i32 = -span;
            while (dz <= span) : (dz += 1) {
                var dx: i32 = -span;
                while (dx <= span) : (dx += 1) {
                    if (@sqrt(@as(f32, @floatFromInt(dx * dx + dz * dz))) > reach) continue;
                    const b: [3]i32 = .{ a[0] + dx, a[1] + dy, a[2] + dz };
                    if (!standable(blocks, b)) continue;
                    for (nodes[0..len]) |seen| {
                        if (std.meta.eql(seen, b)) break;
                    } else {
                        if (len == max_nodes) return error.CourseTooLarge;
                        nodes[len] = b;
                        len += 1;
                    }
                }
            }
        }
    }
    return false;
}

test "the jump course prefab is reachable end to end, and not without its spring" {
    const Prefabs = @import("Prefabs.zig");
    const b = try Blocks.create(std.testing.allocator);
    defer b.destroy();
    const course = Prefabs.starters(.platformer)[0];
    for (course.cells) |p| try b.set(p.x, p.y, p.z, p.cell);
    try std.testing.expect(try reachable(b, .{ 1, 0, 1 }, .{ 2, 6, 14 }));
    // Swap the spring for plain stone: the ledge is 6 m up, out of a plain jump.
    try b.set(1, 0, 10, .{ .shape = .cube, .material = Materials.ofRole(.castle, .main) });
    try std.testing.expect(!try reachable(b, .{ 1, 0, 1 }, .{ 2, 6, 14 }));
}

test "a gap wider than a jump cuts the course and a stepping stone joins it" {
    const b = try Blocks.create(std.testing.allocator);
    defer b.destroy();
    const stone: Blocks.Cell = .{ .shape = .cube };
    try b.set(0, 0, 0, stone);
    try b.set(0, 0, 8, stone);
    try std.testing.expect(!try reachable(b, .{ 0, 0, 0 }, .{ 0, 0, 8 }));
    try b.set(0, 0, 4, stone);
    try std.testing.expect(try reachable(b, .{ 0, 0, 0 }, .{ 0, 0, 8 }));
}
