//! A bounded, seeded lower-canopy district. Stable node IDs are bridge construction anchors;
//! graph validation runs before geometry is installed. Box descriptions feed render and collision.
const std = @import("std");
const R = @import("../physics/Rotation.zig");
const Physics = @import("../physics/Physics.zig");
const Mesh = @import("../render/Mesh.zig");
const Seed = @import("Seed.zig");
const Terrain = @import("Terrain.zig");
const TestArbor = @import("TestArbor.zig");
const V = R.Vec3;
/// v2: styled steel bridges on braced piers, plaza braces, and the skyscraper skyline.
pub const generator_version: u32 = 2;
const Bridges = @import("Bridges.zig");
const Skyline = @import("Skyline.zig");
pub const Building = Skyline.Building;
/// What holds a road up (see `Bridges.zig`).
pub const Style = enum { vine, girder, truss, arch, cable_stayed, suspension };
pub const node_count = 6;
pub const base_edge_count = 6;
pub const max_bridges = 4;
pub const width: f32 = 14;
pub const max_grade: f32 = 0.06;
pub const plaza_radius: f32 = 20;
pub const headroom: f32 = 6;
pub const Node = struct { position: V, kind: enum { arbor, tower }, tree: ?u8 = null };
pub const Edge = struct { a: u8, b: u8, style: Style = .girder };
pub const Obstacle = struct { position: V, radius: f32 };
pub const Layout = struct {
    seed: u64,
    nodes: [node_count]Node,
    edges: [base_edge_count]Edge,
    trees: [3]Obstacle,
    buildings: [Skyline.max_buildings]Building = @splat(.{}),
    building_count: usize = 0,
};
pub const Piece = struct { center: V, size: V, rotation: R.Quat = R.identity, color: V, solid: bool = true };
pub fn Pieces(comptime capacity: usize) type {
    return struct {
        items: [capacity]Piece = undefined,
        count: usize = 0,
        pub fn add(self: *@This(), piece: Piece) !void {
            if (self.count == capacity) return error.TooMuchGeometry;
            self.items[self.count] = piece;
            self.count += 1;
        }
        pub fn slice(self: *const @This()) []const Piece {
            return self.items[0..self.count];
        }
    };
}
pub const CityParts = Pieces(4096);
pub const BridgeParts = Pieces(320);
pub const Span = struct {
    a: V,
    b: V,
    pub fn length(self: Span) f32 {
        return R.length(R.sub(self.b, self.a));
    }
    pub fn horizontal(self: Span) f32 {
        const d = R.sub(self.b, self.a);
        return @sqrt(d[0] * d[0] + d[2] * d[2]);
    }
    pub fn rotation(self: Span) R.Quat {
        const d = R.sub(self.b, self.a);
        return R.mul(R.axisAngle(.{ 0, 1, 0 }, std.math.atan2(d[0], d[2])), R.axisAngle(.{ 1, 0, 0 }, -std.math.atan2(d[1], self.horizontal())));
    }
    pub fn point(self: Span, t: f32) V {
        return R.add(self.a, R.scale(R.sub(self.b, self.a), t));
    }
};

/// This reproduces the existing fixture's placement, including its ground-level ramp start.
pub fn testOrigin(seed: u64) V {
    const p = TestArbor.rampPoint(0);
    return .{ 60, Terrain.surface(seed, 60 + p[0], 22 + p[2]).height, 22 };
}
pub fn generate(seed: u64) !Layout {
    const origin = testOrigin(seed);
    const tower = TestArbor.boxes()[2];
    const entry = R.add(origin, .{ tower.center[0], TestArbor.tower_top, tower.center[2] });
    const jitter = (Seed.unit(Seed.mix(seed ^ 0x43495459)) - 0.5) * 12;
    const level = entry[1];
    const layout: Layout = .{
        .seed = seed,
        .nodes = .{
            .{ .position = entry, .kind = .arbor, .tree = 0 },
            .{ .position = .{ 140 + jitter, level + 2, -80 }, .kind = .tower },
            .{ .position = .{ 240, level + 4, 90 }, .kind = .arbor, .tree = 1 },
            .{ .position = .{ jitter, level + 6, 340 }, .kind = .tower },
            .{ .position = .{ -250, level + 3, 300 }, .kind = .arbor, .tree = 2 },
            .{ .position = .{ -240, level + 1, 80 + jitter }, .kind = .tower },
        },
        .edges = .{ .{ .a = 0, .b = 1 }, .{ .a = 1, .b = 2 }, .{ .a = 2, .b = 3 }, .{ .a = 3, .b = 4 }, .{ .a = 4, .b = 5 }, .{ .a = 5, .b = 0 } },
        .trees = .{
            .{ .position = origin, .radius = TestArbor.base_radius },
            .{ .position = .{ 240, Terrain.surface(seed, 240, 180).height, 180 }, .radius = 24 },
            .{ .position = .{ -340, Terrain.surface(seed, -340, 300).height, 300 }, .radius = 24 },
        },
    };
    try validate(&layout, &.{});
    var styled = layout;
    assignStyles(&styled);
    Skyline.generate(&styled);
    try validate(&styled, &.{});
    return styled;
}

/// Longest roads get the grandest structures, so every style appears in one district.
fn assignStyles(layout: *Layout) void {
    var order: [base_edge_count]usize = .{ 0, 1, 2, 3, 4, 5 };
    const Length = struct {
        fn less(l: *const Layout, a: usize, b: usize) bool {
            return span(l, l.edges[a]).horizontal() > span(l, l.edges[b]).horizontal();
        }
    };
    std.mem.sort(usize, &order, @as(*const Layout, layout), Length.less);
    const grand = [_]Style{ .suspension, .cable_stayed, .arch, .truss, .girder };
    for (order, 0..) |e, rank| layout.edges[e].style = if (rank < grand.len) grand[rank] else if (Seed.unit(Seed.mix(layout.seed ^ 0x5354594c)) < 0.5) .truss else .arch;
}

pub fn span(layout: *const Layout, edge: Edge) Span {
    const a = layout.nodes[edge.a].position;
    const b = layout.nodes[edge.b].position;
    const d = R.sub(b, a);
    const horizontal: V = R.normalize(.{ d[0], 0, d[2] });
    // Half a meter of overlap with the plaza avoids cracks at every approach angle.
    return .{ .a = R.add(a, R.scale(horizontal, plaza_radius - 0.5)), .b = R.sub(b, R.scale(horizontal, plaza_radius - 0.5)) };
}
pub fn same(a: Edge, b: Edge) bool {
    return (a.a == b.a and a.b == b.b) or (a.a == b.b and a.b == b.a);
}
fn shares(a: Edge, b: Edge) bool {
    return a.a == b.a or a.a == b.b or a.b == b.a or a.b == b.b;
}
fn planarDistance(p: V, a: V, b: V) f32 {
    const d: V = .{ b[0] - a[0], 0, b[2] - a[2] };
    const q: V = .{ p[0] - a[0], 0, p[2] - a[2] };
    const t = std.math.clamp(R.dot(q, d) / @max(R.dot(d, d), 0.001), 0, 1);
    return R.length(R.sub(q, R.scale(d, t)));
}
fn cross2(a: V, b: V) f32 {
    return a[0] * b[2] - a[2] * b[0];
}

/// Road clearance is conservative: no crossing/near-parallel roads unless they share a plaza.
/// Tall trees are excluded using a root-radius envelope (safe for the tapered trunks).
pub fn validateEdge(layout: *const Layout, edge: Edge, others: []const Edge) !void {
    if (edge.a >= node_count or edge.b >= node_count or edge.a == edge.b) return error.InvalidAnchor;
    const s = span(layout, edge);
    if (s.horizontal() < 20 or s.horizontal() > 650) return error.InvalidSpan;
    if (@abs(s.b[1] - s.a[1]) / s.horizontal() > max_grade) return error.BridgeTooSteep;
    for (layout.trees) |tree| if (planarDistance(tree.position, s.a, s.b) < tree.radius + width / 2 + 2) return error.TreeClearance;
    for (layout.buildings[0..layout.building_count]) |b| if (planarDistance(b.base, s.a, s.b) < b.radius() + width / 2 + 3) return error.BuildingClearance;
    for (layout.nodes, 0..) |node, i| {
        if (i == edge.a or i == edge.b) continue;
        if (planarDistance(node.position, s.a, s.b) < plaza_radius + width / 2 + 2) return error.PlazaClearance;
    }
    for (layout.nodes, 0..) |node, i| {
        if (i == edge.a or i == edge.b) continue;
        if (node.tree) |tree_id| if (tree_id > 0) try roadClearance(s, trunkSpur(layout, i));
    }
    // Include approaches inside the endpoint plazas, where a market roof can obstruct a road.
    for ([_]u8{ edge.a, edge.b }) |endpoint| {
        if (layout.nodes[endpoint].kind == .tower and planarDistance(marketPosition(layout, endpoint), layout.nodes[edge.a].position, layout.nodes[edge.b].position) < width / 2 + 3.3) return error.MarketClearance;
        if (layout.nodes[endpoint].tree) |tree_id| {
            if (tree_id == 0) continue; // Legacy test-Arbor entrance has its own acceptance test.
            const other = if (endpoint == edge.a) edge.b else edge.a;
            const road = R.normalize(R.sub(layout.nodes[other].position, layout.nodes[endpoint].position));
            const tree = layout.trees[tree_id].position;
            const here = layout.nodes[endpoint].position;
            const spur = R.normalize(.{ tree[0] - here[0], 0, tree[2] - here[2] });
            if (R.dot(road, spur) > 0.75) return error.JunctionClearance;
        }
    }
    const samples: usize = @intFromFloat(@ceil(s.horizontal() / 4));
    const side = R.rotate(s.rotation(), .{ width / 2, 0, 0 });
    for (0..samples + 1) |i| {
        const p = s.point(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(samples)));
        for ([_]f32{ -1, 0, 1 }) |sign| {
            const q = R.add(p, R.scale(side, sign));
            if (q[1] - 0.8 - Terrain.surface(layout.seed, q[0], q[2]).height < headroom) return error.GroundClearance;
        }
    }
    for (others) |other| {
        if (same(edge, other)) return error.DuplicateBridge;
        if (shares(edge, other)) {
            const common = if (edge.a == other.a or edge.a == other.b) edge.a else edge.b;
            const x = if (common == edge.a) edge.b else edge.a;
            const y = if (common == other.a) other.b else other.a;
            const u = R.normalize(R.sub(layout.nodes[x].position, layout.nodes[common].position));
            const v = R.normalize(R.sub(layout.nodes[y].position, layout.nodes[common].position));
            if (R.dot(u, v) > 0.75) return error.JunctionClearance;
            continue;
        }
        try roadClearance(s, span(layout, other));
    }
}

fn roadClearance(s: Span, t: Span) !void {
    const u = R.sub(s.b, s.a);
    const v = R.sub(t.b, t.a);
    const denominator = cross2(u, v);
    if (@abs(denominator) > 0.001) {
        const q = R.sub(t.a, s.a);
        const a = cross2(q, v) / denominator;
        const b = cross2(q, u) / denominator;
        if (a >= 0 and a <= 1 and b >= 0 and b <= 1) return error.RoadCrossing;
    }
    if (@min(@min(planarDistance(s.a, t.a, t.b), planarDistance(s.b, t.a, t.b)), @min(planarDistance(t.a, s.a, s.b), planarDistance(t.b, s.a, s.b))) < width + 2) return error.RoadCrossing;
}

pub fn validate(layout: *const Layout, additions: []const Edge) !void {
    if (additions.len > max_bridges) return error.TooManyBridges;
    for (layout.nodes) |node| for (node.position) |v| if (!std.math.isFinite(v) or @abs(v) > 10000) return error.InvalidAnchor;
    var all: [base_edge_count + max_bridges]Edge = undefined;
    @memcpy(all[0..base_edge_count], &layout.edges);
    @memcpy(all[base_edge_count..][0..additions.len], additions);
    const edges = all[0 .. base_edge_count + additions.len];
    for (edges, 0..) |edge, i| try validateEdge(layout, edge, edges[0..i]);
    try validateConnectivity(edges);
}

fn validateConnectivity(edges: []const Edge) !void {
    var reached: [node_count]bool = @splat(false);
    reached[0] = true;
    for (0..node_count) |_| for (edges) |edge| {
        if (reached[edge.a] or reached[edge.b]) {
            reached[edge.a] = true;
            reached[edge.b] = true;
        }
    };
    for (reached) |r| if (!r) return error.DisconnectedDistrict;
}

const vine: V = .{ 0.24, 0.46, 0.29 };

/// A road deck and its structure in the given style.
pub fn bridgeParts(layout: *const Layout, s: Span, style: Style) !BridgeParts {
    var out: BridgeParts = .{};
    try Bridges.parts(layout, s, style, &out);
    return out;
}

pub fn trunkSpur(layout: *const Layout, i: usize) Span {
    const node = layout.nodes[i];
    const tree = layout.trees[node.tree.?];
    const radial = R.normalize(.{ node.position[0] - tree.position[0], 0, node.position[2] - tree.position[2] });
    return .{
        .a = R.sub(node.position, R.scale(radial, plaza_radius - 0.5)),
        .b = .{ tree.position[0] + radial[0] * (tree.radius + 6), node.position[1], tree.position[2] + radial[2] * (tree.radius + 6) },
    };
}

fn plaza(out: *CityParts, position: V) !void {
    // Four overlapping bars form an octagonal plaza. Every bearing has at least 20 m of deck.
    for (0..4) |i| try out.add(.{ .center = R.add(position, .{ 0, -0.5, 0 }), .size = .{ 16.57, 1, 40 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, @as(f32, @floatFromInt(i)) * std.math.pi / 4), .color = .{ 0.44, 0.48, 0.41 } });
}

// Reserve market bays using the same footprint in validation and mesh generation.
/// Centre of plaza `i`'s market bay floor (tower plazas only).
pub fn marketPosition(layout: *const Layout, i: usize) V {
    const node = layout.nodes[i];
    var best: f32 = -2;
    var offset: V = undefined;
    for (0..16) |candidate| {
        const angle = @as(f32, @floatFromInt(candidate)) * 2 * std.math.pi / 16;
        const radial: V = .{ @sin(angle), 0, @cos(angle) };
        var clearance: f32 = 2;
        for (layout.edges) |edge| {
            if (edge.a != i and edge.b != i) continue;
            const other = if (edge.a == i) edge.b else edge.a;
            clearance = @min(clearance, 1 - R.dot(radial, R.normalize(R.sub(layout.nodes[other].position, node.position))));
        }
        if (clearance > best) {
            best = clearance;
            offset = R.scale(radial, 15);
        }
    }
    return R.add(node.position, offset);
}

pub fn geometry(layout: *const Layout) !CityParts {
    var out: CityParts = .{};
    for (layout.edges) |edge| {
        const parts = try bridgeParts(layout, span(layout, edge), edge.style);
        for (parts.slice()) |p| try out.add(p);
    }
    for (layout.buildings[0..layout.building_count]) |b| try Skyline.geometry(layout, b, &out);
    for (layout.nodes, 0..) |node, i| {
        try plaza(&out, node.position);
        if (node.kind == .tower) {
            const ground = Terrain.surface(layout.seed, node.position[0], node.position[2]).height - 5;
            const height = node.position[1] - 1 - ground;
            try out.add(.{ .center = .{ node.position[0], ground + height / 2, node.position[2] }, .size = .{ 24, height, 24 }, .color = .{ 0.31, 0.44, 0.5 } });
            var y = ground + 4;
            var floor: usize = 0;
            while (y < node.position[1] - 1) : (y += 4) {
                const inset = if ((floor + i) % 3 == 0) @as(f32, 0.8) else 0;
                try out.add(.{ .center = .{ node.position[0], y, node.position[2] }, .size = .{ 25 - inset, 0.3, 25 - inset }, .color = .{ 0.66, 0.70, 0.64 }, .solid = false });
                floor += 1;
            }
            const stall = marketPosition(layout, i);
            try out.add(.{ .center = R.add(stall, .{ 0, 3.5, 0 }), .size = .{ 5, 0.25, 4 }, .color = .{ 0.83, 0.43, 0.28 } });
            for ([_]f32{ -2.2, 2.2 }) |x| try out.add(.{ .center = R.add(stall, .{ x, 1.75, 0 }), .size = .{ 0.18, 3.5, 0.18 }, .color = vine });
        } else if (node.tree.? > 0) {
            const tree = layout.trees[node.tree.?];
            const radius = tree.radius + 6;
            for (0..16) |j| {
                const a = @as(f32, @floatFromInt(j)) * 2 * std.math.pi / 16;
                try out.add(.{ .center = .{ tree.position[0] + @sin(a) * radius, node.position[1] - 0.5, tree.position[2] + @cos(a) * radius }, .size = .{ 2 * radius * @tan(@as(f32, std.math.pi / 16.0)) + 0.1, 1, 14 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, a), .color = .{ 0.42, 0.47, 0.28 } });
            }
            const parts = try bridgeParts(layout, trunkSpur(layout, i), .vine);
            for (parts.slice()) |p| try out.add(p);
            try Skyline.plazaBraces(layout, node.position, &out);
        }
    }
    return out;
}

pub fn mesh(allocator: std.mem.Allocator, pieces: []const Piece, collision: bool) !Mesh {
    const unit = try Mesh.block(allocator);
    defer unit.deinit(allocator);
    var count: usize = 0;
    for (pieces) |p| if (!collision or p.solid) {
        count += 1;
    };
    const vertices = try allocator.alloc(Mesh.Vertex, count * unit.vertices.len);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, count * unit.indices.len);
    var n: usize = 0;
    for (pieces) |p| {
        if (collision and !p.solid) continue;
        for (unit.vertices, vertices[n * unit.vertices.len ..][0..unit.vertices.len]) |v, *out| out.* = .{ .position = R.add(p.center, R.rotate(p.rotation, .{ v.position[0] * p.size[0], v.position[1] * p.size[1], v.position[2] * p.size[2] })), .normal = R.rotate(p.rotation, v.normal), .uv = v.uv, .color = p.color };
        for (unit.indices, indices[n * unit.indices.len ..][0..unit.indices.len]) |index, *out| out.* = @intCast(n * unit.vertices.len + index);
        n += 1;
    }
    return .{ .vertices = vertices, .indices = indices };
}
pub fn collider(allocator: std.mem.Allocator, physics: *Physics, pieces: []const Piece, user: u32) !Physics.MeshCollider {
    const m = try mesh(allocator, pieces, true);
    defer m.deinit(allocator);
    const positions = try allocator.alloc(V, m.vertices.len);
    defer allocator.free(positions);
    for (positions, m.vertices) |*p, v| p.* = v.position;
    return physics.createMesh(allocator, positions, m.indices, user);
}

test "seeded district is connected and every road respects grade and clearance" {
    for ([_]u64{ 0, 1, 42, 310399555161, 987654321 }) |seed| {
        const layout = try generate(seed);
        try validate(&layout, &.{});
        try std.testing.expectEqualDeep(layout, try generate(seed));
        const parts = try geometry(&layout);
        try std.testing.expect(parts.count < parts.items.len);
        try std.testing.expect(parts.count > 200);
    }
}

test "district solver rejects invalid additions before geometry is built" {
    const layout = try generate(310399555161);
    try validate(&layout, &.{.{ .a = 0, .b = 3 }});
    try std.testing.expectError(error.InvalidAnchor, validate(&layout, &.{.{ .a = 0, .b = 99 }}));
    try std.testing.expectError(error.DuplicateBridge, validate(&layout, &.{.{ .a = 1, .b = 0 }}));
    try std.testing.expectError(error.TreeClearance, validate(&layout, &.{.{ .a = 0, .b = 2 }}));
    var steep = layout;
    steep.nodes[1].position[1] += 100;
    try std.testing.expectError(error.BridgeTooSteep, validate(&steep, &.{}));
    try std.testing.expectError(error.DuplicateBridge, validate(&layout, &.{ .{ .a = 0, .b = 3 }, .{ .a = 3, .b = 0 } }));
}

test "solver rejects disconnected graphs, crossed roads, and insufficient ground clearance" {
    try std.testing.expectError(error.DisconnectedDistrict, validateConnectivity(&.{ .{ .a = 0, .b = 1 }, .{ .a = 1, .b = 2 }, .{ .a = 3, .b = 4 }, .{ .a = 4, .b = 5 } }));
    try std.testing.expectError(error.RoadCrossing, roadClearance(.{ .a = .{ -30, 40, 0 }, .b = .{ 30, 40, 0 } }, .{ .a = .{ 0, 40, -30 }, .b = .{ 0, 40, 30 } }));
    var low = try generate(310399555161);
    for (&low.nodes) |*node| node.position[1] -= 35;
    try std.testing.expectError(error.GroundClearance, validate(&low, &.{}));
}
