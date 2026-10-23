//! Block prefabs: ready-made pieces per style (towers, cells, greenhouses, barns), and a player's
//! clipboard captured from the world. Cells are stored by role, not material, for the starters,
//! so a starter is laid in whatever style it belongs to; a clipboard keeps exact materials.
const std = @import("std");
const Blocks = @import("Blocks.zig");
const Materials = @import("Materials.zig");

pub const max_cells = 512;
pub const max_side = 16;

pub const Placed = struct { x: u8, y: u8, z: u8, cell: Blocks.Cell };

pub const Prefab = struct {
    name: []const u8,
    size: [3]u8,
    cells: []const Placed,
};

/// A player's captured piece (session only).
pub const Clip = struct {
    size: [3]u8 = .{ 0, 0, 0 },
    cells: [max_cells]Placed = undefined,
    len: usize = 0,

    pub fn prefab(self: *const Clip) Prefab {
        return .{ .name = "CLIPBOARD", .size = self.size, .cells = self.cells[0..self.len] };
    }
};

/// Where a prefab cell lands after `rot` quarter turns, within the turned footprint. Matches the
/// cell turn in `Mesher` ((x, z) to (z, 1 - x) per turn), so turned pieces keep their faces.
pub fn turned(p: Placed, size: [3]u8, rot: u2) Placed {
    var x: i32 = p.x;
    var z: i32 = p.z;
    var sx: i32 = size[0];
    var sz: i32 = size[2];
    for (0..rot) |_| {
        const nx = z;
        const nz = sx - 1 - x;
        x = nx;
        z = nz;
        const t = sx;
        sx = sz;
        sz = t;
    }
    var cell = p.cell;
    cell.rot +%= rot;
    return .{ .x = @intCast(x), .y = p.y, .z = @intCast(z), .cell = cell };
}

pub fn turnedSize(size: [3]u8, rot: u2) [3]u8 {
    return if (rot % 2 == 1) .{ size[2], size[1], size[0] } else size;
}

const Builder = struct {
    style: Materials.Style,
    cells: [max_cells]Placed = undefined,
    len: usize = 0,

    fn put(b: *Builder, x: u8, y: u8, z: u8, shape: Blocks.Shape, rot: u2, role: Materials.Role) void {
        for (b.cells[0..b.len]) |*c| if (c.x == x and c.y == y and c.z == z) {
            c.cell = .{ .shape = shape, .rot = rot, .material = Materials.ofRole(b.style, role) };
            return;
        };
        b.cells[b.len] = .{ .x = x, .y = y, .z = z, .cell = .{ .shape = shape, .rot = rot, .material = Materials.ofRole(b.style, role) } };
        b.len += 1;
    }

    /// A plain stone block, for pieces whose own style has no plain material (the platformer).
    fn stone(b: *Builder, x: u8, y: u8, z: u8) void {
        b.put(x, y, z, .cube, 0, .main);
        b.cells[b.len - 1].cell.material = Materials.ofRole(.castle, .main);
    }

    fn cube(b: *Builder, x: u8, y: u8, z: u8, role: Materials.Role) void {
        b.put(x, y, z, .cube, 0, role);
    }

    fn remove(b: *Builder, x: u8, y: u8, z: u8) void {
        var i: usize = 0;
        while (i < b.len) {
            if (b.cells[i].x == x and b.cells[i].y == y and b.cells[i].z == z) {
                b.cells[i] = b.cells[b.len - 1];
                b.len -= 1;
            } else i += 1;
        }
    }

    /// The outline of a w x d rectangle, h layers tall, from layer y.
    fn ring(b: *Builder, w: u8, d: u8, y: u8, h: u8, role: Materials.Role) void {
        for (y..y + h) |yy| for (0..w) |x| for (0..d) |z| {
            if (x == 0 or z == 0 or x == w - 1 or z == d - 1) b.cube(@intCast(x), @intCast(yy), @intCast(z), role);
        };
    }

    fn layer(b: *Builder, w: u8, d: u8, y: u8, shape: Blocks.Shape, role: Materials.Role) void {
        for (0..w) |x| for (0..d) |z| b.put(@intCast(x), y, @intCast(z), shape, 0, role);
    }
};

fn make(comptime name: []const u8, comptime style: Materials.Style, comptime size: [3]u8, comptime build: fn (*Builder) void) Prefab {
    @setEvalBranchQuota(200_000);
    const cells = comptime blk: {
        var b: Builder = .{ .style = style };
        build(&b);
        var out: [b.len]Placed = undefined;
        @memcpy(&out, b.cells[0..b.len]);
        break :blk out;
    };
    return .{ .name = name, .size = size, .cells = &cells };
}

fn tower(b: *Builder) void {
    b.ring(5, 5, 0, 1, .dark);
    b.ring(5, 5, 1, 5, .main);
    // A door in the front wall and crenellations on the top.
    b.remove(2, 0, 0);
    b.remove(2, 1, 0);
    for ([_][2]u8{ .{ 0, 0 }, .{ 2, 0 }, .{ 4, 0 }, .{ 0, 2 }, .{ 4, 2 }, .{ 0, 4 }, .{ 2, 4 }, .{ 4, 4 } }) |p| b.cube(p[0], 6, p[1], .main);
    b.cube(2, 4, 0, .color);
}

fn wallRun(b: *Builder) void {
    for (0..7) |x| {
        b.cube(@intCast(x), 0, 0, .dark);
        for (1..4) |y| b.cube(@intCast(x), @intCast(y), 0, .main);
        if (x % 2 == 0) b.cube(@intCast(x), 4, 0, .main);
    }
}

fn gatehouse(b: *Builder) void {
    for (0..7) |x| for (0..2) |z| for (0..5) |y| {
        const opening = x >= 2 and x <= 4 and y <= 2;
        if (!opening) b.cube(@intCast(x), @intCast(y), @intCast(z), if (y == 0) .dark else .main);
    };
    for (0..7) |x| if (x % 2 == 0) b.cube(@intCast(x), 5, 0, .main);
    b.cube(3, 3, 0, .color);
    for (2..5) |x| b.put(@intCast(x), 2, 1, .slab, 0, .metal); // the raised portcullis
}

fn prisonCell(b: *Builder) void {
    b.layer(5, 5, 0, .cube, .dark);
    b.ring(5, 5, 1, 3, .main);
    b.layer(5, 5, 4, .cube, .roof);
    // Bars across the front, a torch inside, fungus in a corner.
    for (1..4) |x| for (1..4) |y| b.remove(@intCast(x), @intCast(y), 0);
    for ([_]u8{ 1, 3 }) |x| for (1..4) |y| b.cube(x, @intCast(y), 0, .metal);
    b.cube(3, 3, 4, .color);
    b.put(1, 1, 3, .slab, 0, .nature);
}

fn corridor(b: *Builder) void {
    for (0..7) |z| {
        for (0..5) |x| b.cube(@intCast(x), 0, @intCast(z), .dark);
        for (1..4) |y| {
            b.cube(0, @intCast(y), @intCast(z), .main);
            b.cube(4, @intCast(y), @intCast(z), .main);
        }
        for (0..5) |x| b.cube(@intCast(x), 4, @intCast(z), .roof);
    }
    b.cube(0, 2, 3, .color);
    b.cube(4, 2, 3, .color);
    b.put(1, 1, 5, .slab, 0, .nature);
    b.put(3, 1, 1, .slab, 0, .accent);
}

fn greenhouse(b: *Builder) void {
    b.layer(5, 5, 0, .cube, .main);
    b.ring(5, 5, 1, 3, .accent);
    for ([_][2]u8{ .{ 0, 0 }, .{ 4, 0 }, .{ 0, 4 }, .{ 4, 4 } }) |p| for (1..4) |y| b.cube(p[0], @intCast(y), p[1], .wood);
    b.layer(5, 5, 4, .slab, .roof);
    b.remove(2, 1, 0);
    b.remove(2, 2, 0);
    b.put(1, 1, 2, .slab, 0, .nature);
    b.put(3, 1, 2, .slab, 0, .color);
    b.put(2, 4, 2, .slab, 0, .metal);
}

fn walkway(b: *Builder) void {
    for ([_]u8{ 0, 6 }) |x| for ([_]u8{ 0, 2 }) |z| for (0..3) |y| b.cube(x, @intCast(y), z, .wood);
    for (0..7) |x| for (0..3) |z| b.put(@intCast(x), 3, @intCast(z), .slab, 0, .main);
    for (0..7) |x| b.put(@intCast(x), 4, 0, .slab, 0, .nature);
}

fn barn(b: *Builder) void {
    b.ring(5, 7, 0, 4, .color);
    for (1..4) |x| for (0..3) |y| b.remove(@intCast(x), @intCast(y), 0);
    for (0..7) |z| {
        const zz: u8 = @intCast(z);
        b.put(0, 4, zz, .ramp, 1, .roof);
        b.put(4, 4, zz, .ramp, 3, .roof);
        for (1..4) |x| b.cube(@intCast(x), 4, zz, .roof);
        b.put(1, 5, zz, .ramp, 1, .roof);
        b.put(3, 5, zz, .ramp, 3, .roof);
        b.cube(2, 5, zz, .roof);
        b.put(2, 6, zz, .slab, 0, .roof);
    }
    b.put(1, 0, 5, .slab, 0, .accent);
    b.put(3, 0, 5, .slab, 0, .accent);
}

fn fence(b: *Builder) void {
    for (0..7) |x| {
        if (x % 2 == 0) {
            b.cube(@intCast(x), 0, 0, .wood);
            b.put(@intCast(x), 1, 0, .slab, 0, .wood);
        } else b.put(@intCast(x), 1, 0, .slab, 0, .main);
    }
}

fn planter(b: *Builder) void {
    b.ring(5, 3, 0, 1, .main);
    for (1..4) |x| b.put(@intCast(x), 0, 1, .cube, 0, .nature);
    b.put(1, 1, 1, .slab, 0, .accent);
    b.put(3, 1, 1, .slab, 0, .accent);
}

// Platformer roles: main spring, dark boost, accent crumble, wood hazard, roof checkpoint,
// nature plate, metal gate, color mover.
fn jumpCourse(b: *Builder) void {
    for (0..3) |x| for (0..3) |z| b.stone(@intCast(x), 0, @intCast(z));
    b.cube(1, 0, 1, .roof); // checkpoint at the start
    b.stone(1, 0, 4);
    b.cube(1, 1, 7, .accent); // crumbles under you
    b.cube(1, 0, 10, .main); // spring up to the ledge
    for (0..3) |x| for (12..15) |z| b.stone(@intCast(x), 6, @intCast(z));
    b.cube(0, 7, 13, .wood); // hazard on the ledge
    b.cube(2, 6, 14, .roof); // checkpoint at the goal
}

fn gateRoom(b: *Builder) void {
    for (0..5) |x| for (0..7) |z| b.stone(@intCast(x), 0, @intCast(z));
    b.cube(2, 0, 1, .nature); // pressure plate
    for (0..5) |x| for (1..4) |y| b.cube(@intCast(x), @intCast(y), 4, .metal); // gate wall
    b.cube(2, 0, 6, .roof);
}

fn moverBridge(b: *Builder) void {
    for (0..3) |x| for (0..3) |z| {
        b.stone(@intCast(x), 0, @intCast(z));
        b.stone(@intCast(x), 0, @intCast(z + 8));
    };
    b.put(1, 0, 3, .cube, 0, .color); // a mover sliding toward the far pad
}

const platformer = [_]Prefab{
    make("JUMP COURSE", .platformer, .{ 3, 8, 15 }, jumpCourse),
    make("GATE ROOM", .platformer, .{ 5, 4, 7 }, gateRoom),
    make("MOVER BRIDGE", .platformer, .{ 3, 1, 11 }, moverBridge),
};

const castle = [_]Prefab{
    make("TOWER", .castle, .{ 5, 7, 5 }, tower),
    make("WALL RUN", .castle, .{ 7, 5, 1 }, wallRun),
    make("GATEHOUSE", .castle, .{ 7, 6, 2 }, gatehouse),
};
const dungeon = [_]Prefab{
    make("CELL", .dungeon, .{ 5, 5, 5 }, prisonCell),
    make("CORRIDOR", .dungeon, .{ 5, 5, 7 }, corridor),
};
const eco_city = [_]Prefab{
    make("GREENHOUSE", .eco_city, .{ 5, 5, 5 }, greenhouse),
    make("WALKWAY", .eco_city, .{ 7, 5, 3 }, walkway),
};
const farm = [_]Prefab{
    make("BARN", .farm, .{ 5, 7, 7 }, barn),
    make("FENCE", .farm, .{ 7, 2, 1 }, fence),
    make("PLANTER", .farm, .{ 5, 2, 3 }, planter),
};

pub fn starters(style: Materials.Style) []const Prefab {
    return switch (style) {
        .castle => &castle,
        .dungeon => &dungeon,
        .eco_city => &eco_city,
        .farm => &farm,
        .platformer => &platformer,
        .glass => &.{},
    };
}

/// Blocks of each material a prefab needs.
pub fn cost(prefab: Prefab) [Materials.count]u32 {
    var result: [Materials.count]u32 = @splat(0);
    for (prefab.cells) |p| result[p.cell.material] += 1;
    return result;
}

test "every starter fits its declared size, uses its own style and has no repeated cell" {
    for (0..Materials.style_count) |s| {
        const style: Materials.Style = @enumFromInt(s);
        // Glass is a swatch palette of glazing: blocks and panes only, no ready-made pieces.
        if (style == .glass) {
            try std.testing.expectEqual(@as(usize, 0), starters(style).len);
            continue;
        }
        try std.testing.expect(starters(style).len >= 2);
        for (starters(style)) |p| {
            try std.testing.expect(p.cells.len > 0 and p.cells.len <= max_cells);
            for (p.cells, 0..) |c, i| {
                try std.testing.expect(c.x < p.size[0] and c.y < p.size[1] and c.z < p.size[2]);
                const own = Materials.roleOf(c.cell.material).style;
                try std.testing.expect(own == style or (style == .platformer and c.cell.material == Materials.ofRole(.castle, .main)));
                for (p.cells[0..i]) |o| try std.testing.expect(!(o.x == c.x and o.y == c.y and o.z == c.z));
            }
        }
    }
}

test "a ranger's starter stock pays for any one starter prefab" {
    const Kit = @import("../game/Kit.zig");
    for (0..Materials.style_count) |s| for (starters(@enumFromInt(s))) |p| {
        for (cost(p)) |n| try std.testing.expect(n <= Kit.starter_blocks);
    };
}

test "four quarter turns return a prefab cell to where it started" {
    const p: Placed = .{ .x = 1, .y = 2, .z = 0, .cell = .{ .shape = .ramp, .rot = 1 } };
    const size: [3]u8 = .{ 5, 3, 2 };
    var q = p;
    var s = size;
    for (0..4) |_| {
        q = turned(q, s, 1);
        s = turnedSize(s, 1);
        try std.testing.expect(q.x < s[0] and q.z < s[2]);
    }
    try std.testing.expectEqual(p, q);
    // One turn takes the front-left cell of a 5 x 2 footprint to x = 0 ... z = 4.
    const t = turned(.{ .x = 0, .y = 0, .z = 0, .cell = .{ .shape = .cube } }, size, 1);
    try std.testing.expectEqual(@as(u8, 0), t.x);
    try std.testing.expectEqual(@as(u8, 4), t.z);
}
