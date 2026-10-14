//! Bounded, deterministic turtle grammars shared by streamed canopy species.
//! The grammar is expanded into compact branches on the asset worker; runtime frames do no work.
const std = @import("std");
const Seed = @import("Seed.zig");

pub const Branch = struct {
    start: [3]f32,
    end: [3]f32,
    root_radius: f32,
    tip_radius: f32,
    terminal: bool,
    parent: ?u32,
    depth: u8,
};

pub const LeafAnchor = struct {
    position: [3]f32,
    direction: [3]f32,
};

pub const LeafForm = enum { ovate, lanceolate, scale, fan, cascade, blossom };

pub const Grammar = struct {
    production: []const u8,
    iterations: u8,
    turn: f32,
    base_length: f32,
    branch_decay: f32,
    base_radius: f32,
    starting_pitch: f32,
    start_height: f32,
    leaf_radius: f32,
    leaves_per_tip: usize,
    needles: bool = false,
    leaf_form: LeafForm = .ovate,
};

// All grammars use the same symbols and interpreter. Production choices alter crown structure,
// while the dimensional parameters distinguish deciduous, conifer, drooping, and fan species.
pub const grammars = [8]Grammar{
    .{ .production = "F[&+F]F[&-F]", .iterations = 4, .turn = 0.62, .base_length = 0.047, .branch_decay = 0.68, .base_radius = 0.016, .starting_pitch = 1.43, .start_height = 0.08, .leaf_radius = 0.016, .leaves_per_tip = 32 },
    .{ .production = "F[+&-F][&-F][-&-F]F", .iterations = 3, .turn = 0.62, .base_length = 0.064, .branch_decay = 0.72, .base_radius = 0.014, .starting_pitch = 1.48, .start_height = 0.08, .leaf_radius = 0.017, .leaves_per_tip = 38, .needles = true },
    .{ .production = "F[&-F]F[&+F]", .iterations = 4, .turn = 0.86, .base_length = 0.098, .branch_decay = 0.70, .base_radius = 0.012, .starting_pitch = 1.34, .start_height = 0.14, .leaf_radius = 0.020, .leaves_per_tip = 22, .leaf_form = .lanceolate },
    .{ .production = "F[+&F][-&F]F", .iterations = 4, .turn = 1.02, .base_length = 0.026, .branch_decay = 0.76, .base_radius = 0.018, .starting_pitch = 1.52, .start_height = 0.62, .leaf_radius = 0.016, .leaves_per_tip = 44, .leaf_form = .scale },
    .{ .production = "F[&+F][&-F]F", .iterations = 4, .turn = 0.72, .base_length = 0.090, .branch_decay = 0.66, .base_radius = 0.015, .starting_pitch = 1.43, .start_height = 0.28, .leaf_radius = 0.018, .leaves_per_tip = 22, .leaf_form = .fan },
    .{ .production = "F[&-F]F[&-F]", .iterations = 4, .turn = 0.77, .base_length = 0.070, .branch_decay = 0.68, .base_radius = 0.014, .starting_pitch = 1.44, .start_height = 0.34, .leaf_radius = 0.015, .leaves_per_tip = 22, .leaf_form = .cascade },
    .{ .production = "F[&+F][&-F]F", .iterations = 4, .turn = 0.68, .base_length = 0.085, .branch_decay = 0.67, .base_radius = 0.012, .starting_pitch = 1.41, .start_height = 0.30, .leaf_radius = 0.012, .leaves_per_tip = 22, .leaf_form = .blossom },
    .{ .production = "F[+&-F][&-F][-&-F]F", .iterations = 3, .turn = 0.98, .base_length = 0.11, .branch_decay = 0.77, .base_radius = 0.014, .starting_pitch = 1.48, .start_height = 0.10, .leaf_radius = 0.032, .leaves_per_tip = 48, .needles = true },
};

pub const Skeleton = struct {
    branches: []Branch,
    leaves: []LeafAnchor,

    pub fn deinit(self: Skeleton, allocator: std.mem.Allocator) void {
        allocator.free(self.branches);
        allocator.free(self.leaves);
    }
};

const Turtle = struct {
    position: [3]f32,
    yaw: f32,
    pitch: f32,
    depth: u8,
    last_branch: ?u32,
};

/// Expand and interpret one species grammar. Fixed symbol and pushdown limits keep this worker
/// bounded even if a future grammar is edited incorrectly.
pub fn generate(allocator: std.mem.Allocator, species: u8) !Skeleton {
    if (species >= grammars.len) return error.InvalidSpecies;
    const grammar = grammars[species];
    var current: [4096]u8 = undefined;
    var next: [4096]u8 = undefined;
    current[0] = 'F';
    var symbol_count: usize = 1;
    for (0..grammar.iterations) |_| {
        var next_count: usize = 0;
        for (current[0..symbol_count]) |symbol| {
            const replacement: []const u8 = if (symbol == 'F') grammar.production else &.{symbol};
            if (replacement.len > next.len - next_count) return error.GrammarLimit;
            @memcpy(next[next_count .. next_count + replacement.len], replacement);
            next_count += replacement.len;
        }
        @memcpy(current[0..next_count], next[0..next_count]);
        symbol_count = next_count;
    }

    var branches: std.ArrayList(Branch) = .empty;
    defer branches.deinit(allocator);
    var leaves: std.ArrayList(LeafAnchor) = .empty;
    defer leaves.deinit(allocator);
    var state: Turtle = .{ .position = .{ 0, grammar.start_height, 0 }, .yaw = 0, .pitch = grammar.starting_pitch, .depth = 0, .last_branch = null };
    var stack: [32]Turtle = undefined;
    var stack_len: usize = 0;
    for (current[0..symbol_count], 0..) |symbol, i| switch (symbol) {
        'F' => {
            var branch_scale: f32 = 1;
            for (0..state.depth) |_| branch_scale *= grammar.branch_decay;
            const variation = 0.93 + 0.14 * Seed.unit(Seed.mix(@as(u64, species) * 0x10000 + @as(u64, @intCast(i))));
            const length = grammar.base_length * branch_scale * variation;
            const horizontal = @cos(state.pitch);
            const direction = [3]f32{ @sin(state.yaw) * horizontal, @sin(state.pitch), @cos(state.yaw) * horizontal };
            const start = state.position;
            const end = [3]f32{ start[0] + direction[0] * length, start[1] + direction[1] * length, start[2] + direction[2] * length };
            const taper = @max(0.28, 1 - state.position[1] * 0.5);
            const root_radius = grammar.base_radius * branch_scale * taper;
            const terminal = i + 1 == symbol_count or current[i + 1] == ']';
            const branch_index: u32 = @intCast(branches.items.len);
            try branches.append(allocator, .{ .start = start, .end = end, .root_radius = root_radius, .tip_radius = root_radius * 0.72, .terminal = terminal, .parent = state.last_branch, .depth = state.depth });
            state.position = end;
            state.last_branch = branch_index;
            // Carry foliage down the smaller branch tiers as well as out to twig tips. This
            // fills the crown's silhouette without adding a large continuous leaf blob.
            const inner_cluster = state.depth >= 2 and i % 6 == 0;
            // The original broadleaf already has a dense crown. Other species need foliage
            // along their secondary limbs, not just isolated tip clusters.
            const foliated_bough = state.depth > 0 and (grammar.needles or species != 0);
            if (grammar.needles and foliated_bough) try leaves.append(allocator, .{ .position = .{ start[0] * 0.75 + end[0] * 0.25, start[1] * 0.75 + end[1] * 0.25, start[2] * 0.75 + end[2] * 0.25 }, .direction = direction });
            if (foliated_bough) try leaves.append(allocator, .{ .position = .{ (start[0] + end[0]) * 0.5, (start[1] + end[1]) * 0.5, (start[2] + end[2]) * 0.5 }, .direction = direction });
            if (terminal or inner_cluster or foliated_bough) try leaves.append(allocator, .{ .position = end, .direction = direction });
            // Each trunk tier turns before its side branches are interpreted. Without this,
            // repeated whorls occupy the same wedge and every species looks like a flat comb.
            if (state.depth == 0) state.yaw += 2.3999632;
        },
        '[' => {
            if (stack_len == stack.len) return error.GrammarLimit;
            stack[stack_len] = state;
            stack_len += 1;
            state.depth += 1;
        },
        ']' => {
            if (stack_len == 0) return error.UnbalancedGrammar;
            stack_len -= 1;
            state = stack[stack_len];
        },
        '+' => state.yaw += grammar.turn + (Seed.unit(Seed.mix(@as(u64, @intCast(i)) + 7)) - 0.5) * 0.16,
        '-' => state.yaw -= grammar.turn + (Seed.unit(Seed.mix(@as(u64, @intCast(i)) + 11)) - 0.5) * 0.16,
        '&' => state.pitch -= grammar.turn,
        '^' => state.pitch += grammar.turn,
        else => return error.InvalidSymbol,
    };
    if (stack_len != 0) return error.UnbalancedGrammar;

    // Let larger limbs support the combined cross-section of their child forks. Continuation
    // segments at the same depth keep their base taper; only deeper branch tiers add pipe load.
    const child_area = try allocator.alloc(f32, branches.items.len);
    defer allocator.free(child_area);
    @memset(child_area, 0);
    var reverse = branches.items.len;
    while (reverse > 0) {
        reverse -= 1;
        const branch = &branches.items[reverse];
        const supported_radius = @sqrt(child_area[reverse]);
        branch.tip_radius = @max(branch.tip_radius, supported_radius * 1.08);
        branch.root_radius = @max(branch.root_radius, branch.tip_radius / 0.72);
        if (branch.parent) |parent| {
            const parent_branch = branches.items[parent];
            if (branch.depth > parent_branch.depth) child_area[parent] += branch.root_radius * branch.root_radius;
        }
    }

    // The bole mesh is one normalized unit tall. Fit every species' branching grammar to that
    // height so its crown reaches the top of the trunk even when its production has fewer main
    // axis steps. Preserve each branch's relative shape and leave its first attachment grounded.
    var highest: f32 = grammar.start_height;
    for (branches.items) |branch| highest = @max(highest, branch.end[1]);
    const crown_height = @max(highest - grammar.start_height, 0.001);
    const fit = (0.94 - grammar.start_height) / crown_height;
    for (branches.items) |*branch| {
        branch.start[1] = grammar.start_height + (branch.start[1] - grammar.start_height) * fit;
        branch.end[1] = grammar.start_height + (branch.end[1] - grammar.start_height) * fit;
        branch.root_radius = @max(branch.root_radius, grammar.base_radius * 0.12);
        branch.tip_radius = @max(branch.tip_radius, grammar.base_radius * 0.08);
    }
    for (leaves.items) |*leaf| leaf.position[1] = grammar.start_height + (leaf.position[1] - grammar.start_height) * fit;

    const owned_branches = try branches.toOwnedSlice(allocator);
    errdefer allocator.free(owned_branches);
    const owned_leaves = try leaves.toOwnedSlice(allocator);
    return .{ .branches = owned_branches, .leaves = owned_leaves };
}

test "tree skeleton forks stay attached and parent first" {
    const a = std.testing.allocator;
    for (0..grammars.len) |species| {
        const skeleton = try generate(a, @intCast(species));
        defer skeleton.deinit(a);
        try std.testing.expect(skeleton.branches.len > 0 and skeleton.leaves.len > 0);
        for (skeleton.branches, 0..) |branch, i| {
            try std.testing.expect(std.math.isFinite(branch.root_radius) and std.math.isFinite(branch.tip_radius));
            try std.testing.expect(branch.root_radius >= branch.tip_radius and branch.tip_radius > 0);
            if (branch.parent) |parent| {
                try std.testing.expect(parent < i);
                const joined = skeleton.branches[parent].end;
                for (joined, branch.start) |a_pos, b_pos| try std.testing.expectApproxEqAbs(a_pos, b_pos, 0.00001);
            } else {
                try std.testing.expect(i == 0);
            }
        }
    }
}
