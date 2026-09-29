const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const Model = @This();

/// Runtime model format ("HWMS"). Little-endian, no padding:
///   magic "HWMS", format u32, vertex_stride u32, vertex_count u32, index_count u32,
///   submesh_count u32, material_count u32, bounds_min [3]f32, bounds_max [3]f32,
///   materials { base_color [4]f32, name [24]u8 }, submeshes { first_index u32, index_count u32, material u32 },
///   vertices (Mesh.Vertex fields in declaration order), indices u32.
/// Bump `format_version` for any layout change; old files are rejected, never reinterpreted.
pub const magic = "HWMS";
pub const format_version: u32 = 1;
pub const max_vertices = 1 << 20;
pub const max_submeshes = 16;
pub const max_materials = 16;
pub const name_len = 24;
const vertex_floats = @sizeOf(Mesh.Vertex) / 4;
const header_bytes = 4 + 6 * 4 + 6 * 4;

pub const Material = struct {
    base_color: [4]f32 = .{ 1, 1, 1, 1 },
    name: [name_len]u8 = @splat(0),

    pub fn named(text: []const u8, base_color: [4]f32) Material {
        var result: Material = .{ .base_color = base_color };
        const n = @min(text.len, name_len);
        @memcpy(result.name[0..n], text[0..n]);
        return result;
    }
};
pub const Submesh = struct { first_index: u32, index_count: u32, material: u32 };

mesh: Mesh,
submeshes: []Submesh,
materials: []Material,
bounds_min: [3]f32,
bounds_max: [3]f32,

pub fn deinit(self: Model, allocator: std.mem.Allocator) void {
    allocator.free(self.materials);
    allocator.free(self.submeshes);
    self.mesh.deinit(allocator);
}

/// Takes ownership of `mesh`. One submesh, one material covering the whole mesh.
pub fn fromMesh(allocator: std.mem.Allocator, mesh: Mesh, material: Material) !Model {
    errdefer mesh.deinit(allocator);
    const submeshes = try allocator.alloc(Submesh, 1);
    errdefer allocator.free(submeshes);
    const materials = try allocator.alloc(Material, 1);
    submeshes[0] = .{ .first_index = 0, .index_count = @intCast(mesh.indices.len), .material = 0 };
    materials[0] = material;
    var result: Model = .{ .mesh = mesh, .submeshes = submeshes, .materials = materials, .bounds_min = undefined, .bounds_max = undefined };
    result.computeBounds();
    return result;
}

pub fn computeBounds(self: *Model) void {
    self.bounds_min = @splat(std.math.inf(f32));
    self.bounds_max = @splat(-std.math.inf(f32));
    for (self.mesh.vertices) |vertex| for (0..3) |axis| {
        self.bounds_min[axis] = @min(self.bounds_min[axis], vertex.position[axis]);
        self.bounds_max[axis] = @max(self.bounds_max[axis], vertex.position[axis]);
    };
}

pub fn halfExtents(self: Model) [3]f32 {
    var result: [3]f32 = undefined;
    for (&result, 0..) |*h, axis| h.* = (self.bounds_max[axis] - self.bounds_min[axis]) / 2;
    return result;
}

pub fn encode(self: Model, allocator: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll(magic);
    for ([_]u32{ format_version, @sizeOf(Mesh.Vertex), @intCast(self.mesh.vertices.len), @intCast(self.mesh.indices.len), @intCast(self.submeshes.len), @intCast(self.materials.len) }) |v| try w.writeInt(u32, v, .little);
    for (self.bounds_min ++ self.bounds_max) |v| try w.writeInt(u32, @bitCast(v), .little);
    for (self.materials) |m| {
        for (m.base_color) |v| try w.writeInt(u32, @bitCast(v), .little);
        try w.writeAll(&m.name);
    }
    for (self.submeshes) |s| for ([_]u32{ s.first_index, s.index_count, s.material }) |v| try w.writeInt(u32, v, .little);
    for (self.mesh.vertices) |vertex| {
        const floats: [vertex_floats]f32 = @bitCast(vertex);
        for (floats) |v| try w.writeInt(u32, @bitCast(v), .little);
    }
    for (self.mesh.indices) |v| try w.writeInt(u32, v, .little);
    return out.toOwnedSlice();
}

pub const DecodeError = error{ NotAModel, UnsupportedVersion, UnsupportedVertexLayout, Truncated, TrailingBytes, TooLarge, InvalidIndex, InvalidSubmesh, InvalidMaterial, NonFiniteValue, OutOfMemory };

const Reader = struct {
    bytes: []const u8,
    at: usize = 0,
    fn int(self: *Reader) DecodeError!u32 {
        if (self.bytes.len - self.at < 4) return error.Truncated;
        defer self.at += 4;
        return std.mem.readInt(u32, self.bytes[self.at..][0..4], .little);
    }
    fn float(self: *Reader) DecodeError!f32 {
        const v: f32 = @bitCast(try self.int());
        return if (std.math.isFinite(v)) v else error.NonFiniteValue;
    }
};

/// Validates every count, range, and float before returning; embedded bytes need no alignment.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!Model {
    if (bytes.len < header_bytes or !std.mem.eql(u8, bytes[0..4], magic)) return error.NotAModel;
    var r: Reader = .{ .bytes = bytes, .at = 4 };
    if (try r.int() != format_version) return error.UnsupportedVersion;
    if (try r.int() != @sizeOf(Mesh.Vertex)) return error.UnsupportedVertexLayout;
    const vertex_count = try r.int();
    const index_count = try r.int();
    const submesh_count = try r.int();
    const material_count = try r.int();
    if (vertex_count > max_vertices or index_count > max_vertices * 6 or submesh_count > max_submeshes or material_count > max_materials) return error.TooLarge;
    if (vertex_count == 0 or index_count == 0 or index_count % 3 != 0 or submesh_count == 0 or material_count == 0) return error.InvalidSubmesh;
    const expected = header_bytes + material_count * (16 + name_len) + submesh_count * 12 + vertex_count * @sizeOf(Mesh.Vertex) + index_count * 4;
    if (bytes.len < expected) return error.Truncated;
    if (bytes.len > expected) return error.TrailingBytes;
    var result: Model = undefined;
    for (&result.bounds_min) |*v| v.* = try r.float();
    for (&result.bounds_max) |*v| v.* = try r.float();

    const materials = try allocator.alloc(Material, material_count);
    errdefer allocator.free(materials);
    for (materials) |*m| {
        for (&m.base_color) |*v| v.* = try r.float();
        @memcpy(&m.name, bytes[r.at..][0..name_len]);
        r.at += name_len;
    }
    const submeshes = try allocator.alloc(Submesh, submesh_count);
    errdefer allocator.free(submeshes);
    for (submeshes) |*s| {
        s.* = .{ .first_index = try r.int(), .index_count = try r.int(), .material = try r.int() };
        if (s.material >= material_count) return error.InvalidMaterial;
        if (s.index_count == 0 or s.index_count % 3 != 0 or s.first_index % 3 != 0 or s.first_index > index_count or index_count - s.first_index < s.index_count) return error.InvalidSubmesh;
    }
    const vertices = try allocator.alloc(Mesh.Vertex, vertex_count);
    errdefer allocator.free(vertices);
    for (vertices) |*vertex| {
        var floats: [vertex_floats]f32 = undefined;
        for (&floats) |*v| v.* = try r.float();
        vertex.* = @bitCast(floats);
    }
    const indices = try allocator.alloc(u32, index_count);
    errdefer allocator.free(indices);
    for (indices) |*v| {
        v.* = try r.int();
        if (v.* >= vertex_count) return error.InvalidIndex;
    }
    result.mesh = .{ .vertices = vertices, .indices = indices };
    result.submeshes = submeshes;
    result.materials = materials;
    return result;
}

test "runtime model round-trips and rejects version, truncation, and range errors" {
    const allocator = std.testing.allocator;
    const cube = try Mesh.cube(allocator);
    const model = try fromMesh(allocator, cube, .named("relic", .{ 0.5, 0.6, 0.7, 1 }));
    defer model.deinit(allocator);
    const bytes = try model.encode(allocator);
    defer allocator.free(bytes);
    const back = try decode(allocator, bytes);
    defer back.deinit(allocator);
    try std.testing.expectEqualSlices(Mesh.Vertex, model.mesh.vertices, back.mesh.vertices);
    try std.testing.expectEqualSlices(u32, model.mesh.indices, back.mesh.indices);
    try std.testing.expectEqualDeep(model.materials[0], back.materials[0]);
    try std.testing.expectEqual(@as(f32, 2), back.bounds_max[1]);

    const copy = try allocator.dupe(u8, bytes);
    defer allocator.free(copy);
    std.mem.writeInt(u32, copy[4..8], format_version + 1, .little);
    try std.testing.expectError(error.UnsupportedVersion, decode(allocator, copy));
    try std.testing.expectError(error.Truncated, decode(allocator, bytes[0 .. bytes.len - 1]));
    @memcpy(copy, bytes);
    std.mem.writeInt(u32, copy[copy.len - 4 ..][0..4], 9999, .little);
    try std.testing.expectError(error.InvalidIndex, decode(allocator, copy));
    try std.testing.expectError(error.NotAModel, decode(allocator, "glTF"));
}

fn decodeProbe(allocator: std.mem.Allocator, bytes: []const u8) !void {
    const model = try decode(allocator, bytes);
    model.deinit(allocator);
}

test "runtime model decode cleans up on allocation failure" {
    const cube = try Mesh.cube(std.testing.allocator);
    const model = try fromMesh(std.testing.allocator, cube, .{});
    defer model.deinit(std.testing.allocator);
    const bytes = try model.encode(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, decodeProbe, .{bytes});
}
