//! Versioned, bounded space-colonization growth. A parent-before-child skeleton is shared by
//! rendering, woody collision, attachment queries and the vascular network. No frame-time growth.
const std = @import("std");
const Seed = @import("Seed.zig");
const Mesh = @import("../render/Mesh.zig");
const Physics = @import("../physics/Physics.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
pub const generator_version: u32 = 3;
pub const max_nodes = 640;
pub const max_platforms = 8;
pub const none: u16 = 0xffff;

pub const Genome = struct {
    version: u32 = 1,
    height: f32 = 380,
    base_radius: f32 = 24,
    crown_radius: f32 = 190,
    phyllotaxis: f32 = 137.5,
    apical_dominance: f32 = 0.45,
    phototropism: f32 = 0.35,
    gravitropism: f32 = 0.2,
    platform_tendency: f32 = 0.65,
    vascular_capacity: f32 = 200,
    bark: [3]f32 = .{ 0.36, 0.25, 0.17 },
    ridging: f32 = 0.12,
    lumen: [3]f32 = .{ 0.15, 0.85, 0.7 },

    pub fn validate(self: Genome) !void {
        if (self.version != 1) return error.UnsupportedGenome;
        const values = .{ self.height, self.base_radius, self.crown_radius, self.phyllotaxis, self.apical_dominance, self.phototropism, self.gravitropism, self.platform_tendency, self.vascular_capacity, self.ridging };
        inline for (values) |v| if (!std.math.isFinite(v)) return error.InvalidGenome;
        if (self.height < 300 or self.height > 600 or self.base_radius < 20 or self.base_radius > 50 or self.crown_radius < 150 or self.crown_radius > 250 or self.phyllotaxis < 30 or self.phyllotaxis > 330 or self.vascular_capacity <= 0 or self.vascular_capacity > 10000) return error.InvalidGenome;
        for ([_]f32{ self.apical_dominance, self.phototropism, self.gravitropism, self.platform_tendency, self.ridging } ++ self.bark ++ self.lumen) |v| if (!std.math.isFinite(v) or v < 0 or v > 1) return error.InvalidGenome;
    }
};
pub const Node = struct { position: V, radius: f32, parent: u16, depth: u8 };
pub const Platform = struct { node: u16, center: V, half: V };
pub const Attachment = struct { node: u16, distance: f32 };
pub const Tree = struct {
    seed: u64,
    genome: Genome,
    nodes: [max_nodes]Node = undefined,
    count: usize = 0,
    platforms: [max_platforms]Platform = undefined,
    platform_count: usize = 0,

    pub fn edgeStartRadius(self: *const Tree, i: usize) f32 {
        const node = self.nodes[i];
        const parent = self.nodes[node.parent];
        return if (node.depth == 0 or parent.depth > 0) parent.radius else node.radius * 1.2;
    }

    /// Every edge has a flow limit; the root is the shared tree supply.
    pub fn capacity(self: *const Tree, i: usize) f32 {
        if (self.nodes[i].depth == 0) return self.genome.vascular_capacity;
        const ratio = self.nodes[i].radius / self.genome.base_radius;
        return self.genome.vascular_capacity * @max(0.12, ratio * ratio);
    }

    /// Nearest woody surface in local coordinates, returning its vascular node. Taps must sit
    /// outside the wood, within reach; foliage is deliberately not a sap attachment surface.
    pub fn attachment(self: *const Tree, p: V, reach: f32) ?Attachment {
        var best: ?Attachment = null;
        for (self.nodes[1..self.count], 1..) |node, i| {
            const a = self.nodes[node.parent].position;
            const delta = R.sub(node.position, a);
            const t = std.math.clamp(R.dot(R.sub(p, a), delta) / R.dot(delta, delta), 0, 1);
            const center = R.add(a, R.scale(delta, t));
            const radius = self.edgeStartRadius(i) + (node.radius - self.edgeStartRadius(i)) * t;
            const distance = R.length(R.sub(p, center)) - radius;
            if (distance < -1 or distance > reach) continue;
            if (best == null or @abs(distance) < best.?.distance) best = .{ .node = @intCast(i), .distance = @abs(distance) };
        }
        return best;
    }
};

fn random(seed: u64, index: usize) f32 {
    return Seed.unit(Seed.mix(seed +% @as(u64, @intCast(index))));
}

pub fn grow(seed: u64, genome: Genome) !Tree {
    try genome.validate();
    var tree: Tree = .{ .seed = seed, .genome = genome };
    tree.nodes[0] = .{ .position = .{ 0, -14, 0 }, .radius = genome.base_radius, .parent = none, .depth = 0 };
    tree.count = 1;
    const trunk_steps = 20;
    for (0..trunk_steps + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / trunk_steps;
        tree.nodes[tree.count] = .{ .position = .{ 0, t * genome.height, 0 }, .radius = genome.base_radius * (1 - 0.88 * t), .parent = @intCast(tree.count - 1), .depth = 0 };
        tree.count += 1;
    }
    const spread = genome.crown_radius * (1 - genome.apical_dominance * 0.6);
    // Phyllotactic scaffolds give colonization starting sites around the leader.
    for (0..10) |i| {
        const parent: u16 = @intCast(8 + i);
        const angle = (@as(f32, @floatFromInt(i)) * genome.phyllotaxis + random(seed, 1) * 360) * std.math.pi / 180;
        const origin = tree.nodes[parent].position;
        tree.nodes[tree.count] = .{ .position = R.add(origin, .{ @cos(angle) * spread * 0.3, 8, @sin(angle) * spread * 0.3 }), .radius = genome.base_radius * 0.3, .parent = parent, .depth = 1 };
        tree.count += 1;
    }
    const attractor_count = 448;
    var targets: [attractor_count]V = undefined;
    var live: [attractor_count]bool = @splat(true);
    for (&targets, 0..) |*point, i| {
        const angle = random(seed, i * 3 + 11) * 2 * std.math.pi;
        const vertical = random(seed, i * 3 + 12) * 2 - 1;
        const radial = @sqrt(1 - vertical * vertical) * @sqrt(random(seed, i * 3 + 13));
        point.* = .{ @cos(angle) * spread * radial, genome.height * (0.50 + 0.46 * (vertical + 1) * 0.5), @sin(angle) * spread * radial };
    }
    const step: f32 = 8.5;
    for (0..44) |_| {
        var sums: [max_nodes]V = @splat(.{ 0, 0, 0 });
        var counts: [max_nodes]u16 = @splat(0);
        for (targets, &live) |target, *alive| {
            if (!alive.*) continue;
            var nearest: ?usize = null;
            var best = spread * 0.65;
            for (tree.nodes[0..tree.count], 0..) |node, n| {
                if (node.position[1] < genome.height * 0.3) continue;
                const distance = R.length(R.sub(target, node.position));
                if (distance < step * 1.1) {
                    alive.* = false;
                    break;
                }
                if (distance < best) {
                    nearest = n;
                    best = distance;
                }
            }
            if (alive.*) if (nearest) |n| {
                sums[n] = R.add(sums[n], R.normalize(R.sub(target, tree.nodes[n].position)));
                counts[n] += 1;
            };
        }
        const before = tree.count;
        for (0..before) |i| {
            if (counts[i] == 0 or tree.count == max_nodes) continue;
            const parent = tree.nodes[i];
            var direction = R.scale(sums[i], 1 / @as(f32, @floatFromInt(counts[i])));
            direction[1] += genome.phototropism * 0.6 - genome.gravitropism * @as(f32, @floatFromInt(parent.depth)) * 0.12;
            const shelf = parent.depth > 0 and random(seed, tree.count + 500) < genome.platform_tendency * 0.3;
            if (shelf) direction[1] *= 0.08;
            if (R.length(direction) < 0.01) continue;
            // Branches keep part of their parent's heading, so limbs curve instead of kinking
            // at every colonization step.
            var heading = R.normalize(direction);
            if (parent.depth > 0) {
                const incoming = R.normalize(R.sub(parent.position, tree.nodes[parent.parent].position));
                // A step that doubles back on its limb would hook; the attractor is left for a
                // later step or another branch to reach.
                if (R.dot(heading, incoming) < 0.25) continue;
                heading = R.normalize(R.add(R.scale(heading, 0.55), R.scale(incoming, 0.45)));
            }
            const position = R.add(parent.position, R.scale(heading, step));
            if (position[1] > genome.height or position[1] < genome.height * 0.25) continue;
            var duplicate = false;
            for (tree.nodes[0..tree.count]) |node| if (R.length(R.sub(position, node.position)) < step * 0.32) {
                duplicate = true;
                break;
            };
            if (duplicate) continue;
            const radius = if (parent.depth == 0) genome.base_radius * 0.22 else @max(0.65, parent.radius * 0.76);
            tree.nodes[tree.count] = .{ .position = position, .radius = radius, .parent = @intCast(i), .depth = parent.depth + 1 };
            if (shelf and tree.platform_count < max_platforms) {
                tree.platforms[tree.platform_count] = .{ .node = @intCast(tree.count), .center = R.add(position, .{ 0, radius * 0.2, 0 }), .half = .{ 9, 1.4, 7 } };
                tree.platform_count += 1;
            }
            tree.count += 1;
        }
        if (tree.count == before or tree.count == max_nodes) break;
    }
    extendTwigs(&tree, step);
    return tree;
}

/// Add fine, deterministic side twigs to primary and secondary limbs. Colonization lays out the
/// crown's large boughs; these short shoots fill the spaces between them and provide more leaf
/// attachment sites without changing the growth loop's attractor assignments.
fn extendTwigs(tree: *Tree, step: f32) void {
    const source_count = tree.count;
    for (1..source_count) |i| {
        const source = tree.nodes[i];
        if (source.depth < 1 or source.depth > 2 or source.position[1] < tree.genome.height * 0.42 or source.position[1] > tree.genome.height * 0.96) continue;
        if (random(tree.seed, i + 2300) > 0.78 or tree.count == max_nodes) continue;

        const incoming = R.normalize(R.sub(source.position, tree.nodes[source.parent].position));
        const radial = R.normalize(.{ source.position[0], 0, source.position[2] });
        const side = R.normalize(R.cross(incoming, .{ 0, 1, 0 }));
        const sign: f32 = if (random(tree.seed, i + 2400) < 0.5) -1 else 1;
        var direction = R.add(R.scale(incoming, 0.30), R.scale(radial, 0.30));
        direction = R.add(direction, .{ 0, 0.60, 0 });
        direction = R.add(direction, R.scale(side, sign * 0.42));
        direction = R.normalize(direction);
        const length = step * (0.34 + random(tree.seed, i + 2500) * 0.20);
        const position = R.add(source.position, R.scale(direction, length));
        if (position[1] > tree.genome.height) continue;

        tree.nodes[tree.count] = .{
            .position = position,
            .radius = @max(0.55, source.radius * 0.52),
            .parent = @intCast(i),
            .depth = source.depth + 1,
        };
        tree.count += 1;
    }
}

const Writer = struct {
    vertices: []Mesh.Vertex,
    indices: []u32,
    v: usize = 0,
    i: usize = 0,
    fn vertex(self: *Writer, p: V, n: V, color: V, material_tag: f32) void {
        self.vertices[self.v] = .{ .position = p, .normal = n, .uv = .{ -material_tag, p[1] / 4 }, .color = color };
        self.v += 1;
    }
    fn tri(self: *Writer, a: usize, b: usize, c: usize) void {
        for ([_]usize{ a, b, c }) |index| {
            self.indices[self.i] = @intCast(index);
            self.i += 1;
        }
    }
    fn tube(self: *Writer, a: V, b: V, r0: f32, r1: f32, sides: usize, genome: Genome) void {
        const direction = R.normalize(R.sub(b, a));
        const reference: V = if (@abs(direction[2]) < 0.9) .{ 0, 0, 1 } else .{ 1, 0, 0 };
        const u = R.normalize(R.cross(direction, reference));
        const v = R.cross(u, direction);
        const base = self.v;
        for (0..2) |ring| for (0..sides) |j| {
            const angle = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(sides)) * 2 * std.math.pi;
            const radial = R.add(R.scale(u, @cos(angle)), R.scale(v, @sin(angle)));
            const ridge = 1 - genome.ridging * (0.5 + 0.5 * @sin(angle * 5));
            self.vertex(R.add(if (ring == 0) a else b, R.scale(radial, if (ring == 0) r0 else r1)), R.normalize(R.add(radial, R.scale(direction, (r0 - r1) / R.length(R.sub(b, a))))), R.scale(genome.bark, ridge), 20);
        };
        self.vertex(a, R.scale(direction, -1), genome.bark, 20);
        self.vertex(b, direction, genome.bark, 20);
        for (0..sides) |j| {
            const next = (j + 1) % sides;
            self.tri(base + j, base + sides + j, base + next);
            self.tri(base + next, base + sides + j, base + sides + next);
            self.tri(base + sides * 2, base + j, base + next);
            self.tri(base + sides * 2 + 1, base + sides + next, base + sides + j);
        }
    }
    fn foliage(self: *Writer, center: V, half: V, color: V, phase: f32) void {
        // Rounded, lightly lobed crown clusters keep a soft leaf mass while the branch skeleton
        // remains visible through gaps. Smooth normals remove the old faceted-crystal look.
        const rows = 6;
        const sides = 12;
        const base = self.v;
        for (0..rows + 1) |row| for (0..sides) |column| {
            const latitude = std.math.pi * @as(f32, @floatFromInt(row)) / rows;
            const longitude = 2 * std.math.pi * @as(f32, @floatFromInt(column)) / sides;
            const lobes = 0.91 + 0.08 * @sin(longitude * 3 + phase) * @sin(latitude) + 0.04 * @sin(longitude * 7 - phase * 1.7) * @sin(latitude);
            const unit: V = .{ @sin(latitude) * @cos(longitude), @cos(latitude), @sin(latitude) * @sin(longitude) };
            const position: V = .{ center[0] + unit[0] * half[0] * lobes, center[1] + unit[1] * half[1] * lobes, center[2] + unit[2] * half[2] * lobes };
            const normal = R.normalize(.{ unit[0] / half[0], unit[1] / half[1], unit[2] / half[2] });
            const shade = 0.90 + 0.10 * @sin(longitude * 2 + phase);
            self.vertex(position, normal, R.scale(color, shade), 10);
        };
        for (0..rows) |row| for (0..sides) |column| {
            const a = base + row * sides + column;
            const b = base + row * sides + (column + 1) % sides;
            self.tri(a, a + sides, b);
            self.tri(b, a + sides, b + sides);
        };
    }
    fn box(self: *Writer, unit: Mesh, center: V, half: V, color: V) void {
        const base = self.v;
        for (unit.vertices) |point| self.vertex(R.add(center, .{ point.position[0] * half[0] * 2, point.position[1] * half[1] * 2, point.position[2] * half[2] * 2 }), point.normal, color, 0);
        for (unit.indices) |index| {
            self.indices[self.i] = @intCast(base + index);
            self.i += 1;
        }
    }
};

pub const Detail = enum { full, proxy, collision };
/// Foliage is clustered, not individual leaves; collision contains only wood and shelves.
pub fn mesh(allocator: std.mem.Allocator, tree: *const Tree, detail: Detail) !Mesh {
    const sides: usize = if (detail == .proxy) 4 else 12;
    var children: [max_nodes]u16 = @splat(0);
    for (tree.nodes[1..tree.count]) |node| children[node.parent] += 1;
    var edges: usize = 0;
    var foliage_clusters: usize = 0;
    for (tree.nodes[1..tree.count], 1..) |node, i| {
        if (detail != .proxy or node.depth < 3) edges += 1;
        if (detail != .collision) foliage_clusters += foliageLobes(tree, i, children[i]);
    }
    const platforms = if (detail == .proxy) 0 else tree.platform_count;
    const unit = try Mesh.block(allocator);
    defer unit.deinit(allocator);
    const vertices_per_cluster = 7 * 12;
    const indices_per_cluster = 6 * 12 * 6;
    const vertices = try allocator.alloc(Mesh.Vertex, edges * (sides * 2 + 2) + platforms * unit.vertices.len + foliage_clusters * vertices_per_cluster);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, edges * sides * 12 + platforms * unit.indices.len + foliage_clusters * indices_per_cluster);
    var writer: Writer = .{ .vertices = vertices, .indices = indices };
    for (tree.nodes[1..tree.count], 1..) |node, i| {
        if (detail != .proxy or node.depth < 3) writer.tube(tree.nodes[node.parent].position, node.position, tree.edgeStartRadius(i), node.radius, sides, tree.genome);
        const lobes = if (detail == .collision) 0 else foliageLobes(tree, i, children[i]);
        if (lobes > 0) {
            const r = (13 + 10 * (1 - tree.genome.apical_dominance)) * (0.9 + random(tree.seed, i + 700) * 0.2) * 0.62;
            const terminal = children[i] == 0;
            const cluster_radius = if (terminal) r * 0.74 else r * 0.60;
            for (0..lobes) |lobe| {
                const angle = (random(tree.seed, i + 1100) + @as(f32, @floatFromInt(lobe)) / @as(f32, @floatFromInt(lobes))) * 2 * std.math.pi;
                const size = cluster_radius * (0.8 + 0.4 * random(tree.seed, i * 3 + lobe + 1300));
                const offset: V = .{ @cos(angle) * cluster_radius * 0.48, cluster_radius * 0.12 * @as(f32, @floatFromInt(lobe)) - cluster_radius * 0.06, @sin(angle) * cluster_radius * 0.48 };
                const shade = random(tree.seed, i) * 0.12 + 0.03 * @as(f32, @floatFromInt(lobe));
                writer.foliage(R.add(node.position, offset), .{ size, size * 0.72, size }, .{ 0.16, 0.30 + shade, 0.20 }, random(tree.seed, i + 900) * 2 * std.math.pi + @as(f32, @floatFromInt(lobe)));
            }
        }
    }
    for (tree.platforms[0..platforms]) |p| writer.box(unit, p.center, p.half, .{ 0.38, 0.48, 0.26 });
    std.debug.assert(writer.v == vertices.len and writer.i == indices.len);
    return .{ .vertices = vertices, .indices = indices };
}

fn foliageLobes(tree: *const Tree, index: usize, child_count: u16) usize {
    const node = tree.nodes[index];
    if (node.depth == 0) return 0;
    if (child_count == 0) return 6;
    // Small leaf clusters continue along every secondary limb, while terminal twigs carry the
    // denser crown masses. Stable positions keep each generated Arbor reproducible.
    if (node.depth >= 1) return 2;
    return 0;
}

pub fn createCollider(allocator: std.mem.Allocator, physics: *Physics, tree: *const Tree, origin: V, user: u32) !Physics.MeshCollider {
    const geometry = try mesh(allocator, tree, .collision);
    defer geometry.deinit(allocator);
    const positions = try allocator.alloc(V, geometry.vertices.len);
    defer allocator.free(positions);
    for (positions, geometry.vertices) |*p, v| p.* = R.add(origin, v.position);
    return physics.createMesh(allocator, positions, geometry.indices, user);
}

test "space colonization is reproducible, bounded, acyclic and shaped by its genome" {
    const a = try grow(123, .{});
    const b = try grow(123, .{});
    try std.testing.expectEqualDeep(a.nodes[0..a.count], b.nodes[0..b.count]);
    try std.testing.expectEqualDeep(a.platforms[0..a.platform_count], b.platforms[0..b.platform_count]);
    try std.testing.expect(a.count > 40 and a.count <= max_nodes and a.platform_count > 0);
    for (a.nodes[1..a.count], 1..) |node, i| try std.testing.expect(node.parent < i and node.radius > 0);
    const narrow = try grow(123, .{ .apical_dominance = 1, .platform_tendency = 0 });
    const wide = try grow(123, .{ .apical_dominance = 0 });
    var narrow_width: f32 = 0;
    var wide_width: f32 = 0;
    for (narrow.nodes[0..narrow.count]) |n| narrow_width = @max(narrow_width, @sqrt(n.position[0] * n.position[0] + n.position[2] * n.position[2]));
    for (wide.nodes[0..wide.count]) |n| wide_width = @max(wide_width, @sqrt(n.position[0] * n.position[0] + n.position[2] * n.position[2]));
    try std.testing.expect(wide_width > narrow_width * 1.3);
    try std.testing.expectEqual(@as(usize, 0), narrow.platform_count);
    const other = try grow(124, .{});
    try std.testing.expect(!std.meta.eql(a.nodes[22], other.nodes[22]));
    try std.testing.expectError(error.UnsupportedGenome, grow(1, .{ .version = 2 }));
    try std.testing.expectError(error.InvalidGenome, grow(1, .{ .height = std.math.nan(f32) }));
}

test "Arbor meshes share shelf surfaces, proxy is smaller, and attachment requires wood" {
    const a = std.testing.allocator;
    const tree = try grow(123, .{});
    const full = try mesh(a, &tree, .full);
    defer full.deinit(a);
    const proxy = try mesh(a, &tree, .proxy);
    defer proxy.deinit(a);
    const collision = try mesh(a, &tree, .collision);
    defer collision.deinit(a);
    try std.testing.expect(proxy.vertices.len < full.vertices.len);
    for ([_]Mesh{ full, proxy, collision }) |m| {
        for (m.indices) |i| try std.testing.expect(i < m.vertices.len);
        for (m.vertices) |v| for (v.position ++ v.normal) |f| try std.testing.expect(std.math.isFinite(f));
    }
    try std.testing.expect(tree.attachment(.{ 25, 0, 0 }, 4) != null);
    try std.testing.expect(tree.attachment(.{ 1000, 0, 0 }, 4) == null);
    const shelf = tree.platforms[0];
    const top = R.add(shelf.center, .{ 0, shelf.half[1], 0 });
    var found = false;
    for (collision.vertices) |v| if (@abs(v.position[1] - top[1]) < 0.001) {
        found = true;
        break;
    };
    try std.testing.expect(found);
}

test "generated shelf collider supports a walking character at the rendered deck height" {
    const Flat = struct {
        fn sample(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
            return .{ .height = -100, .normal = .{ 0, 1, 0 } };
        }
    };
    var physics = Physics.init(.{ .sample = Flat.sample });
    defer physics.deinit();
    const tree = try grow(123, .{});
    const collider = try createCollider(std.testing.allocator, &physics, &tree, .{ 0, 0, 0 }, 99);
    var supported = false;
    for (tree.platforms[0..tree.platform_count]) |platform| {
        const top = R.add(platform.center, .{ platform.half[0] * 0.75, platform.half[1], platform.half[2] * 0.75 });
        const hit = physics.raycast(R.add(top, .{ 0, 2, 0 }), .{ 0, -1, 0 }, 3, .none) orelse continue;
        if (@abs(hit.point[1] - top[1]) > 0.01) continue;
        try std.testing.expect(hit.mesh.eql(collider) and hit.normal[1] > 0.99);
        const landed = physics.moveCharacter(.{}, R.add(top, .{ 0, 0.5, 0 }), .{ 0, -1, 0 }, true);
        try std.testing.expect(landed.grounded);
        try std.testing.expectApproxEqAbs(top[1], landed.feet[1], 0.02);
        const walked = physics.moveCharacter(.{}, landed.feet, .{ -1, 0, 0 }, true);
        try std.testing.expect(walked.grounded);
        try std.testing.expectApproxEqAbs(top[1], walked.feet[1], 0.02);
        supported = true;
        break;
    }
    try std.testing.expect(supported);
}

fn meshProbe(allocator: std.mem.Allocator, tree: *const Tree) !void {
    const geometry = try mesh(allocator, tree, .full);
    geometry.deinit(allocator);
}

test "Arbor mesh construction frees partial allocations" {
    const tree = try grow(123, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, meshProbe, .{&tree});
}
