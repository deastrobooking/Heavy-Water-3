//! Editable, source-linked appearance and shape modifiers for imported character meshes.
//! Disconnected triangle islands are the first safe editing boundary; glTF names and skin
//! weights refine the suggested labels, while every generated label remains author-editable.
const std = @import("std");
const Model = @import("Model.zig");
const Modifiers = @This();

pub const format_version: u32 = 1;
pub const CharacterType = enum { captain, ranger, synthetic };
pub const Surface = enum { armor, skin, eyes, energy, neutral };
pub const Part = struct {
    /// Smallest source vertex index in this connected mesh island. Stable for unchanged source.
    id: u32,
    label: []const u8,
    surface: Surface = .armor,
    center: [3]f32,
    vertex_count: u32,
    scale: [3]f32 = .{ 1, 1, 1 },
    offset: [3]f32 = .{ 0, 0, 0 },
    color: ?[3]f32 = null,
};
pub const Document = struct {
    format: u32 = format_version,
    character_type: CharacterType = .captain,
    source_hash: []const u8,
    overall_scale: f32 = 1,
    skin_color: [3]f32 = .{ 0.78, 0.53, 0.39 },
    eye_color: [3]f32 = .{ 0.16, 0.78, 0.96 },
    armor_color: [3]f32 = .{ 0.22, 0.54, 0.68 },
    energy_color: [3]f32 = .{ 0.25, 0.9, 1 },
    parts: []const Part,
};
pub const Component = struct { id: u32, count: u32, center: [3]f32, min: [3]f32, max: [3]f32 };
pub const Analysis = struct {
    /// For each vertex, the `id` of its disconnected component.
    vertex_parts: []u32,
    components: []Component,
};
pub const Error = error{ InvalidModifiers, SourceChanged, ComponentSetChanged, InvalidPartTransform, InvalidPartColor, OutOfMemory };

pub fn analyze(allocator: std.mem.Allocator, model: Model) !Analysis {
    const count = model.mesh.vertices.len;
    if (count == 0) return error.InvalidModifiers;
    const parents = try allocator.alloc(u32, count);
    defer allocator.free(parents);
    for (parents, 0..) |*p, i| p.* = @intCast(i);
    if (model.mesh.indices.len == 0 or model.mesh.indices.len % 3 != 0) return error.InvalidModifiers;
    for (model.mesh.indices) |index| if (index >= count) return error.InvalidModifiers;
    var triangle: usize = 0;
    while (triangle < model.mesh.indices.len) : (triangle += 3) {
        merge(parents, model.mesh.indices[triangle], model.mesh.indices[triangle + 1]);
        merge(parents, model.mesh.indices[triangle], model.mesh.indices[triangle + 2]);
    }

    const vertex_parts = try allocator.alloc(u32, count);
    errdefer allocator.free(vertex_parts);
    const sums = try allocator.alloc([3]f64, count);
    defer allocator.free(sums);
    const mins = try allocator.alloc([3]f32, count);
    defer allocator.free(mins);
    const maxs = try allocator.alloc([3]f32, count);
    defer allocator.free(maxs);
    const sizes = try allocator.alloc(u32, count);
    defer allocator.free(sizes);
    @memset(sums, .{ 0, 0, 0 });
    @memset(mins, .{ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32) });
    @memset(maxs, .{ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32) });
    @memset(sizes, 0);
    var component_count: usize = 0;
    for (model.mesh.vertices, 0..) |vertex, i| {
        const root = find(parents, @intCast(i));
        vertex_parts[i] = root;
        if (sizes[root] == 0) component_count += 1;
        sizes[root] += 1;
        for (0..3) |axis| {
            const value = vertex.position[axis];
            if (!std.math.isFinite(value)) return error.InvalidModifiers;
            sums[root][axis] += value;
            mins[root][axis] = @min(mins[root][axis], value);
            maxs[root][axis] = @max(maxs[root][axis], value);
        }
    }
    const components = try allocator.alloc(Component, component_count);
    errdefer allocator.free(components);
    var out: usize = 0;
    for (sizes, 0..) |size, root| {
        if (size == 0) continue;
        var center: [3]f32 = undefined;
        for (0..3) |axis| center[axis] = @floatCast(sums[root][axis] / @as(f64, @floatFromInt(size)));
        components[out] = .{ .id = @intCast(root), .count = size, .center = center, .min = mins[root], .max = maxs[root] };
        out += 1;
    }
    return .{ .vertex_parts = vertex_parts, .components = components };
}

pub fn generate(allocator: std.mem.Allocator, model: Model, source_hash: []const u8) !Document {
    const analysis = try analyze(allocator, model);
    defer allocator.free(analysis.vertex_parts);
    defer allocator.free(analysis.components);
    const parts = try allocator.alloc(Part, analysis.components.len);
    errdefer allocator.free(parts);
    var initialized: usize = 0;
    errdefer for (parts[0..initialized]) |part| allocator.free(part.label);
    for (analysis.components, parts) |component, *part| {
        part.* = .{
            .id = component.id,
            .label = try suggestedLabel(allocator, component, model),
            .surface = suggestedSurface(component, model),
            .center = component.center,
            .vertex_count = component.count,
        };
        initialized += 1;
    }
    return .{ .source_hash = try allocator.dupe(u8, source_hash), .parts = parts };
}

pub fn deinit(allocator: std.mem.Allocator, doc: Document) void {
    for (doc.parts) |part| allocator.free(part.label);
    allocator.free(doc.parts);
    allocator.free(doc.source_hash);
}

/// Applies label-selected palette colors and component transforms to a static preview/runtime
/// model. The model stays source geometry; the sidecar remains the editable source of truth.
pub fn apply(allocator: std.mem.Allocator, model: *Model, doc: Document, expected_hash: []const u8) !Analysis {
    if (doc.format != format_version or !validColor(doc.skin_color) or !validColor(doc.eye_color) or !validColor(doc.armor_color) or !validColor(doc.energy_color) or !std.math.isFinite(doc.overall_scale) or doc.overall_scale <= 0 or doc.overall_scale > 100) return error.InvalidModifiers;
    if (!std.mem.eql(u8, doc.source_hash, expected_hash)) return error.SourceChanged;
    const analysis = try analyze(allocator, model.*);
    errdefer {
        allocator.free(analysis.vertex_parts);
        allocator.free(analysis.components);
    }
    if (doc.parts.len != analysis.components.len) return error.ComponentSetChanged;
    for (analysis.components) |component| if (findPart(doc.parts, component.id) == null) return error.ComponentSetChanged;
    for (doc.parts) |part| {
        if (!validScale(part.scale) or !validOffset(part.offset)) return error.InvalidPartTransform;
        if (part.color) |color| if (!validColor(color)) return error.InvalidPartColor;
    }
    for (model.mesh.vertices, analysis.vertex_parts) |*vertex, id| {
        const part = findPart(doc.parts, id).?;
        const color = part.color orelse switch (part.surface) {
            .armor => doc.armor_color,
            .skin => doc.skin_color,
            .eyes => doc.eye_color,
            .energy => doc.energy_color,
            .neutral => .{ 1, 1, 1 },
        };
        const component = componentById(analysis.components, id).?;
        for (0..3) |axis| {
            vertex.position[axis] = (component.center[axis] + (vertex.position[axis] - component.center[axis]) * part.scale[axis]) * doc.overall_scale + part.offset[axis];
            vertex.color[axis] = color[axis];
        }
    }
    recalcNormals(model.*);
    model.computeBounds();
    return analysis;
}

pub fn triangleSurfaceColor(doc: Document, analysis: Analysis, model: Model, triangle: usize) [3]f32 {
    if (triangle * 3 + 2 >= model.mesh.indices.len) return .{ 1, 1, 1 };
    const id = analysis.vertex_parts[model.mesh.indices[triangle * 3]];
    const part = findPart(doc.parts, id) orelse return .{ 1, 1, 1 };
    return part.color orelse switch (part.surface) {
        .armor => doc.armor_color,
        .skin => doc.skin_color,
        .eyes => doc.eye_color,
        .energy => doc.energy_color,
        .neutral => .{ 1, 1, 1 },
    };
}

fn findPart(parts: []const Part, id: u32) ?Part {
    for (parts) |part| if (part.id == id) return part;
    return null;
}
fn componentById(components: []const Component, id: u32) ?Component {
    for (components) |component| if (component.id == id) return component;
    return null;
}
fn validColor(color: [3]f32) bool {
    for (color) |channel| if (!std.math.isFinite(channel) or channel < 0 or channel > 1) return false;
    return true;
}
fn validScale(scale: [3]f32) bool {
    for (scale) |axis| if (!std.math.isFinite(axis) or axis < 0.1 or axis > 5) return false;
    return true;
}
fn validOffset(offset: [3]f32) bool {
    for (offset) |axis| if (!std.math.isFinite(axis) or @abs(axis) > 10) return false;
    return true;
}

fn suggestedSurface(component: Component, model: Model) Surface {
    const height = @max(model.bounds_max[1] - model.bounds_min[1], 1e-5);
    const y = (component.center[1] - model.bounds_min[1]) / height;
    // A small, forward-facing island high on the head is a useful eye-color suggestion. It is
    // deliberately only a suggestion: authors can relabel any island in the modifier file.
    if (y > 0.85 and component.count <= 24 and component.center[2] > (model.bounds_min[2] + model.bounds_max[2]) * 0.5) return .eyes;
    return .armor;
}

fn suggestedLabel(allocator: std.mem.Allocator, component: Component, model: Model) ![]const u8 {
    const lo = model.bounds_min;
    const hi = model.bounds_max;
    const y = (component.center[1] - lo[1]) / @max(hi[1] - lo[1], 1e-5);
    const x = component.center[0];
    const half_width = @max((hi[0] - lo[0]) * 0.5, 1e-5);
    const is_side = @abs(x) > half_width * 0.12;
    const side: []const u8 = if (x < -half_width * 0.12) "left" else if (x > half_width * 0.12) "right" else "center";
    const label: []const u8 = if (y > 0.82)
        "head detail"
    else if (y > 0.73)
        (if (is_side) "shoulder plate" else "helmet / head")
    else if (y > 0.58)
        (if (is_side) "upper arm" else "chest / back")
    else if (y > 0.43)
        (if (is_side) "forearm / elbow" else "waist")
    else if (y > 0.25)
        (if (is_side) "thigh / knee" else "hip / groin")
    else if (y > 0.11)
        (if (is_side) "shin armor" else "lower leg")
    else
        (if (is_side) "boot / foot" else "lower trim");
    if (is_side and y > 0.25 and y <= 0.73) return std.fmt.allocPrint(allocator, "{s} {s}", .{ side, label });
    return allocator.dupe(u8, label);
}

fn find(parents: []u32, index: u32) u32 {
    var root = index;
    while (parents[root] != root) root = parents[root];
    var current = index;
    while (parents[current] != current) {
        const next = parents[current];
        parents[current] = root;
        current = next;
    }
    return root;
}
fn merge(parents: []u32, a: u32, b: u32) void {
    const ra = find(parents, a);
    const rb = find(parents, b);
    if (ra == rb) return;
    // The lower vertex index remains the stable component identifier.
    if (ra < rb) parents[rb] = ra else parents[ra] = rb;
}
fn recalcNormals(model: Model) void {
    for (model.mesh.vertices) |*vertex| vertex.normal = .{ 0, 0, 0 };
    var triangle: usize = 0;
    while (triangle < model.mesh.indices.len) : (triangle += 3) {
        const ia = model.mesh.indices[triangle];
        const ib = model.mesh.indices[triangle + 1];
        const ic = model.mesh.indices[triangle + 2];
        const a = model.mesh.vertices[ia].position;
        const b = model.mesh.vertices[ib].position;
        const c = model.mesh.vertices[ic].position;
        const ab = [3]f32{ b[0] - a[0], b[1] - a[1], b[2] - a[2] };
        const ac = [3]f32{ c[0] - a[0], c[1] - a[1], c[2] - a[2] };
        const normal = [3]f32{ ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0] };
        for ([3]u32{ ia, ib, ic }) |index| {
            for (0..3) |axis| model.mesh.vertices[index].normal[axis] += normal[axis];
        }
    }
    for (model.mesh.vertices) |*vertex| {
        const n = vertex.normal;
        const length = @sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        vertex.normal = if (length > 1e-8) .{ n[0] / length, n[1] / length, n[2] / length } else .{ 0, 1, 0 };
    }
}

test "modifier analysis groups disconnected islands and applies reversible author edits" {
    const allocator = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    const source_hash = "blake3:test-source-hash";
    const mesh = try Mesh.cube(allocator);
    var model = try Model.fromMesh(allocator, mesh, .named("captain", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    const doc = try generate(allocator, model, source_hash);
    defer deinit(allocator, doc);
    try std.testing.expectEqual(@as(usize, 6), doc.parts.len);
    const parts = try allocator.dupe(Part, doc.parts);
    defer allocator.free(parts);
    parts[0].surface = .skin;
    parts[0].scale = .{ 1, 2, 1 };
    var edited = doc;
    edited.parts = parts;
    edited.skin_color = .{ 0.7, 0.4, 0.2 };
    try std.testing.expectError(error.SourceChanged, apply(allocator, &model, edited, "different-source"));
    const analysis = try apply(allocator, &model, edited, source_hash);
    defer allocator.free(analysis.vertex_parts);
    defer allocator.free(analysis.components);
    try std.testing.expectEqual(@as(f32, 0.7), model.mesh.vertices[0].color[0]);
    try std.testing.expectEqual(@as(f32, 0.4), model.mesh.vertices[0].color[1]);
    try std.testing.expect(model.bounds_max[1] > 2);
}
