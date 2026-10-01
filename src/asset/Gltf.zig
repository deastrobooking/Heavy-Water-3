const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const Model = @import("Model.zig");

/// glTF 2.0 importer for the asset compiler. Supports .gltf (data-URI or resolver-loaded buffers)
/// and .glb; triangle primitives with POSITION and NORMAL (TEXCOORD_0 optional); u8/u16/u32
/// indices; node TRS/matrix transforms; baseColorFactor materials. Textures, skins, morph
/// targets, sparse accessors, and extensions are rejected or ignored explicitly.
pub const Resolver = struct {
    context: ?*anyopaque = null,
    /// Loads an external buffer URI relative to the source file. Caller frees with the same allocator.
    load: ?*const fn (context: ?*anyopaque, allocator: std.mem.Allocator, uri: []const u8) anyerror![]u8 = null,
};

const Doc = struct {
    asset: struct { version: []const u8 },
    scene: ?u32 = null,
    scenes: []const struct { nodes: []const u32 = &.{} } = &.{},
    nodes: []const Node = &.{},
    meshes: []const struct { primitives: []const Primitive } = &.{},
    materials: []const MaterialDef = &.{},
    accessors: []const Accessor = &.{},
    bufferViews: []const BufferView = &.{},
    buffers: []const struct { byteLength: usize, uri: ?[]const u8 = null } = &.{},
    extensionsRequired: []const []const u8 = &.{},
};
const Node = struct {
    mesh: ?u32 = null,
    children: []const u32 = &.{},
    matrix: ?[16]f32 = null,
    translation: [3]f32 = .{ 0, 0, 0 },
    rotation: [4]f32 = .{ 0, 0, 0, 1 },
    scale: [3]f32 = .{ 1, 1, 1 },
    skin: ?u32 = null,
};
const Primitive = struct {
    attributes: struct { POSITION: u32, NORMAL: ?u32 = null, TEXCOORD_0: ?u32 = null },
    indices: ?u32 = null,
    material: ?u32 = null,
    mode: u32 = 4,
    targets: ?std.json.Value = null,
};
const MaterialDef = struct {
    name: ?[]const u8 = null,
    pbrMetallicRoughness: struct { baseColorFactor: [4]f32 = .{ 1, 1, 1, 1 } } = .{},
};
const Accessor = struct {
    bufferView: ?u32 = null,
    byteOffset: usize = 0,
    componentType: u32,
    normalized: bool = false,
    count: usize,
    type: []const u8,
    sparse: ?std.json.Value = null,
};
const BufferView = struct { buffer: u32, byteOffset: usize = 0, byteLength: usize, byteStride: ?usize = null };

const Mat = [16]f32; // column-major, as glTF stores it

/// External buffer dependencies, owned by the supplied arena. Uses the same URI restrictions
/// as compilation, so watchers never read a path compilation would refuse.
pub fn externalBuffers(arena: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    const json = if (source.len >= 12 and std.mem.eql(u8, source[0..4], "glTF")) (try splitGlb(source)).json else source;
    const doc = try std.json.parseFromSliceLeaky(Doc, arena, json, .{ .ignore_unknown_fields = true });
    var uris: std.ArrayList([]const u8) = .empty;
    for (doc.buffers) |b| if (b.uri) |uri| {
        if (std.mem.startsWith(u8, uri, "data:")) continue;
        if (uri.len == 0 or uri[0] == '/' or std.mem.indexOf(u8, uri, "..") != null or std.mem.indexOfScalar(u8, uri, ':') != null or std.mem.indexOfScalar(u8, uri, '\\') != null) return error.UnsafeUri;
        try uris.append(arena, uri);
    };
    return uris.toOwnedSlice(arena);
}

pub fn compile(allocator: std.mem.Allocator, source: []const u8, resolver: Resolver) !Model {
    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var json_bytes = source;
    var glb_bin: ?[]const u8 = null;
    if (source.len >= 12 and std.mem.eql(u8, source[0..4], "glTF")) {
        const glb = try splitGlb(source);
        json_bytes = glb.json;
        glb_bin = glb.bin;
    }
    const doc = try std.json.parseFromSliceLeaky(Doc, arena, json_bytes, .{ .ignore_unknown_fields = true });
    if (!std.mem.startsWith(u8, doc.asset.version, "2.")) return error.UnsupportedGltfVersion;
    if (doc.extensionsRequired.len > 0) return error.UnsupportedExtension;

    const buffers = try arena.alloc([]const u8, doc.buffers.len);
    for (doc.buffers, buffers, 0..) |def, *data, i| {
        data.* = if (def.uri) |uri| try loadUri(arena, uri, resolver) else if (i == 0 and glb_bin != null) glb_bin.? else return error.MissingBuffer;
        if (data.len < def.byteLength) return error.BufferTooShort;
    }
    var builder: Builder = .{ .doc = doc, .buffers = buffers, .arena = arena };
    if (doc.scene) |i| if (i >= doc.scenes.len) return error.InvalidScene;
    const roots: []const u32 = if (doc.scenes.len > 0) doc.scenes[doc.scene orelse 0].nodes else blk: {
        // Without scenes, every node not referenced as a child is a root.
        var referenced = try arena.alloc(bool, doc.nodes.len);
        @memset(referenced, false);
        for (doc.nodes) |n| for (n.children) |c| if (c < referenced.len) {
            referenced[c] = true;
        };
        var list: std.ArrayList(u32) = .empty;
        for (referenced, 0..) |r, i| if (!r) try list.append(arena, @intCast(i));
        break :blk list.items;
    };
    for (roots) |root| try builder.visit(root, identity, 0);
    if (builder.indices.items.len == 0) return error.NoTriangles;
    if (builder.vertices.items.len > Model.max_vertices) return error.TooLarge;

    // Only the final owned arrays leave the arena.
    const vertices = try allocator.dupe(Mesh.Vertex, builder.vertices.items);
    errdefer allocator.free(vertices);
    const indices = try allocator.dupe(u32, builder.indices.items);
    errdefer allocator.free(indices);
    const submeshes = try allocator.dupe(Model.Submesh, builder.submeshes.items);
    errdefer allocator.free(submeshes);
    const materials = try allocator.dupe(Model.Material, builder.materials.items);
    var model: Model = .{ .mesh = .{ .vertices = vertices, .indices = indices }, .submeshes = submeshes, .materials = materials, .bounds_min = undefined, .bounds_max = undefined };
    model.computeBounds();
    return model;
}

const Builder = struct {
    doc: Doc,
    buffers: []const []const u8,
    arena: std.mem.Allocator,
    vertices: std.ArrayList(Mesh.Vertex) = .empty,
    indices: std.ArrayList(u32) = .empty,
    submeshes: std.ArrayList(Model.Submesh) = .empty,
    materials: std.ArrayList(Model.Material) = .empty,
    /// glTF material index → runtime material index; the last slot is the default material.
    material_map: [Model.max_materials + 1]?u32 = @splat(null),

    fn visit(self: *Builder, index: u32, parent: Mat, depth: u32) !void {
        if (index >= self.doc.nodes.len) return error.InvalidNode;
        if (depth > 64) return error.NodeCycle;
        const node = self.doc.nodes[index];
        if (node.skin != null) return error.SkinsUnsupported;
        const local = node.matrix orelse trs(node.translation, node.rotation, node.scale);
        const world = mul(parent, local);
        if (node.mesh) |m| {
            if (m >= self.doc.meshes.len) return error.InvalidMesh;
            for (self.doc.meshes[m].primitives) |p| try self.primitive(p, world);
        }
        for (node.children) |child| try self.visit(child, world, depth + 1);
    }

    fn primitive(self: *Builder, p: Primitive, world: Mat) !void {
        if (p.mode != 4) return error.NonTrianglePrimitive;
        if (p.targets != null) return error.MorphTargetsUnsupported;
        const normal_accessor = p.attributes.NORMAL orelse return error.MissingNormals;
        const positions = try self.accessor(p.attributes.POSITION, "VEC3");
        const normals = try self.accessor(normal_accessor, "VEC3");
        const uvs: ?View = if (p.attributes.TEXCOORD_0) |t| try self.accessor(t, "VEC2") else null;
        if (normals.count != positions.count or (uvs != null and uvs.?.count != positions.count)) return error.AttributeCountMismatch;
        if (positions.component != 5126 or normals.component != 5126) return error.UnsupportedComponentType;
        if (uvs) |u| if (u.component != 5126) return error.UnsupportedComponentType;

        const base: u32 = @intCast(self.vertices.items.len);
        const normal_matrix = normalMatrix(world);
        for (0..positions.count) |i| {
            const pos = transformPoint(world, positions.vec(3, i));
            const n = normalize(transformVector(normal_matrix, normals.vec(3, i)));
            const uv = if (uvs) |u| u.vec(2, i) else [2]f32{ 0, 0 };
            for (pos ++ n ++ uv) |v| if (!std.math.isFinite(v)) return error.NonFiniteValue;
            try self.vertices.append(self.arena, .{ .position = pos, .normal = n, .uv = uv });
        }
        const first: u32 = @intCast(self.indices.items.len);
        if (p.indices) |ia| {
            const view = try self.accessor(ia, "SCALAR");
            for (0..view.count) |i| {
                const v: u32 = switch (view.component) {
                    5121 => view.bytes[view.offset(i)],
                    5123 => std.mem.readInt(u16, view.bytes[view.offset(i)..][0..2], .little),
                    5125 => std.mem.readInt(u32, view.bytes[view.offset(i)..][0..4], .little),
                    else => return error.UnsupportedComponentType,
                };
                if (v >= positions.count) return error.InvalidIndex;
                try self.indices.append(self.arena, base + v);
            }
        } else {
            for (0..positions.count) |i| try self.indices.append(self.arena, base + @as(u32, @intCast(i)));
        }
        const count: u32 = @as(u32, @intCast(self.indices.items.len)) - first;
        if (count == 0 or count % 3 != 0) return error.InvalidTriangleList;
        // Reversing winding for mirrored transforms keeps front faces consistent.
        if (determinant3(world) < 0) {
            var t = first;
            while (t < first + count) : (t += 3) std.mem.swap(u32, &self.indices.items[t + 1], &self.indices.items[t + 2]);
        }
        const material_index = try self.material(p.material);
        if (self.submeshes.items.len > 0) {
            const last = &self.submeshes.items[self.submeshes.items.len - 1];
            if (last.material == material_index and last.first_index + last.index_count == first) {
                last.index_count += count;
                return;
            }
        }
        if (self.submeshes.items.len == Model.max_submeshes) return error.TooManySubmeshes;
        try self.submeshes.append(self.arena, .{ .first_index = first, .index_count = count, .material = material_index });
    }

    fn material(self: *Builder, index: ?u32) !u32 {
        const slot = if (index) |i| blk: {
            if (i >= self.doc.materials.len) return error.InvalidMaterial;
            if (i >= Model.max_materials) return error.TooManyMaterials;
            break :blk i;
        } else Model.max_materials;
        if (self.material_map[slot]) |mapped| return mapped;
        if (self.materials.items.len == Model.max_materials) return error.TooManyMaterials;
        const def: MaterialDef = if (index) |i| self.doc.materials[i] else .{ .name = "default" };
        for (def.pbrMetallicRoughness.baseColorFactor) |v| if (!std.math.isFinite(v)) return error.NonFiniteValue;
        try self.materials.append(self.arena, .named(def.name orelse "unnamed", def.pbrMetallicRoughness.baseColorFactor));
        self.material_map[slot] = @intCast(self.materials.items.len - 1);
        return self.material_map[slot].?;
    }

    fn accessor(self: *Builder, index: u32, expected_type: []const u8) !View {
        if (index >= self.doc.accessors.len) return error.InvalidAccessor;
        const a = self.doc.accessors[index];
        if (a.sparse != null) return error.SparseAccessorsUnsupported;
        if (a.normalized) return error.UnsupportedComponentType;
        if (!std.mem.eql(u8, a.type, expected_type)) return error.UnexpectedAccessorType;
        const view_index = a.bufferView orelse return error.MissingBufferView;
        if (view_index >= self.doc.bufferViews.len) return error.InvalidBufferView;
        const bv = self.doc.bufferViews[view_index];
        if (bv.buffer >= self.buffers.len) return error.MissingBuffer;
        const component_size: usize = switch (a.componentType) {
            5121 => 1,
            5123 => 2,
            5125, 5126 => 4,
            else => return error.UnsupportedComponentType,
        };
        const components: usize = if (std.mem.eql(u8, expected_type, "SCALAR")) 1 else if (std.mem.eql(u8, expected_type, "VEC2")) 2 else 3;
        const element = component_size * components;
        const stride = bv.byteStride orelse element;
        if (stride < element) return error.InvalidStride;
        const buffer = self.buffers[bv.buffer];
        if (bv.byteOffset > buffer.len or buffer.len - bv.byteOffset < bv.byteLength) return error.BufferViewOutOfRange;
        const bytes = buffer[bv.byteOffset..][0..bv.byteLength];
        if (a.count > 0 and (a.byteOffset > bytes.len or (a.count - 1) * stride + element > bytes.len - a.byteOffset)) return error.AccessorOutOfRange;
        return .{ .bytes = bytes, .start = a.byteOffset, .stride = stride, .count = a.count, .component = a.componentType };
    }
};

const View = struct {
    bytes: []const u8,
    start: usize,
    stride: usize,
    count: usize,
    component: u32,

    fn offset(self: View, i: usize) usize {
        return self.start + i * self.stride;
    }

    fn vec(self: View, comptime n: usize, i: usize) [n]f32 {
        var result: [n]f32 = undefined;
        for (&result, 0..) |*v, c| v.* = @bitCast(std.mem.readInt(u32, self.bytes[self.offset(i) + c * 4 ..][0..4], .little));
        return result;
    }
};

fn splitGlb(bytes: []const u8) !struct { json: []const u8, bin: ?[]const u8 } {
    if (std.mem.readInt(u32, bytes[4..8], .little) != 2) return error.UnsupportedGltfVersion;
    const total = std.mem.readInt(u32, bytes[8..12], .little);
    if (total > bytes.len) return error.Truncated;
    var at: usize = 12;
    var json: ?[]const u8 = null;
    var bin: ?[]const u8 = null;
    while (total - at >= 8) {
        const len = std.mem.readInt(u32, bytes[at..][0..4], .little);
        const kind = std.mem.readInt(u32, bytes[at + 4 ..][0..4], .little);
        at += 8;
        if (len > total - at) return error.Truncated;
        const chunk = bytes[at..][0..len];
        if (kind == 0x4E4F534A) json = chunk else if (kind == 0x004E4942 and bin == null) bin = chunk;
        at += len;
    }
    return .{ .json = json orelse return error.MissingJsonChunk, .bin = bin };
}

fn loadUri(arena: std.mem.Allocator, uri: []const u8, resolver: Resolver) ![]const u8 {
    if (std.mem.startsWith(u8, uri, "data:")) {
        const comma = std.mem.indexOfScalar(u8, uri, ',') orelse return error.InvalidDataUri;
        if (!std.mem.endsWith(u8, uri[0..comma], ";base64")) return error.InvalidDataUri;
        const encoded = uri[comma + 1 ..];
        const decoder = std.base64.standard.Decoder;
        const out = try arena.alloc(u8, try decoder.calcSizeForSlice(encoded));
        try decoder.decode(out, encoded);
        return out;
    }
    const load = resolver.load orelse return error.ExternalBufferUnavailable;
    // Reject absolute and parent paths so an asset cannot read outside its directory.
    if (uri.len == 0 or uri[0] == '/' or std.mem.indexOf(u8, uri, "..") != null or std.mem.indexOfScalar(u8, uri, ':') != null or std.mem.indexOfScalar(u8, uri, '\\') != null) return error.UnsafeUri;
    return load(resolver.context, arena, uri);
}

const identity: Mat = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };

fn trs(t: [3]f32, q: [4]f32, s: [3]f32) Mat {
    const x, const y, const z, const w = q;
    return .{
        (1 - 2 * (y * y + z * z)) * s[0], 2 * (x * y + z * w) * s[0],       2 * (x * z - y * w) * s[0],       0,
        2 * (x * y - z * w) * s[1],       (1 - 2 * (x * x + z * z)) * s[1], 2 * (y * z + x * w) * s[1],       0,
        2 * (x * z + y * w) * s[2],       2 * (y * z - x * w) * s[2],       (1 - 2 * (x * x + y * y)) * s[2], 0,
        t[0],                             t[1],                             t[2],                             1,
    };
}

fn mul(a: Mat, b: Mat) Mat {
    var r: Mat = undefined;
    for (0..4) |col| for (0..4) |row| {
        var sum: f32 = 0;
        for (0..4) |k| sum += a[k * 4 + row] * b[col * 4 + k];
        r[col * 4 + row] = sum;
    };
    return r;
}

fn transformPoint(m: Mat, p: [3]f32) [3]f32 {
    var r: [3]f32 = undefined;
    for (0..3) |row| r[row] = m[row] * p[0] + m[4 + row] * p[1] + m[8 + row] * p[2] + m[12 + row];
    return r;
}

fn transformVector(m: [9]f32, v: [3]f32) [3]f32 {
    var r: [3]f32 = undefined;
    for (0..3) |row| r[row] = m[row] * v[0] + m[3 + row] * v[1] + m[6 + row] * v[2];
    return r;
}

fn determinant3(m: Mat) f32 {
    return m[0] * (m[5] * m[10] - m[9] * m[6]) - m[4] * (m[1] * m[10] - m[9] * m[2]) + m[8] * (m[1] * m[6] - m[5] * m[2]);
}

/// Inverse transpose of the upper 3×3: the cofactor matrix, sign-corrected for mirrored
/// transforms. Scale is removed by normalization.
fn normalMatrix(m: Mat) [9]f32 {
    const sign: f32 = if (determinant3(m) < 0) -1 else 1;
    const a = [3][3]f32{ .{ m[0], m[1], m[2] }, .{ m[4], m[5], m[6] }, .{ m[8], m[9], m[10] } };
    var r: [9]f32 = undefined;
    for (0..3) |c| for (0..3) |row| {
        const c1 = (c + 1) % 3;
        const c2 = (c + 2) % 3;
        const r1 = (row + 1) % 3;
        const r2 = (row + 2) % 3;
        r[c * 3 + row] = sign * (a[c1][r1] * a[c2][r2] - a[c1][r2] * a[c2][r1]);
    };
    return r;
}

fn normalize(v: [3]f32) [3]f32 {
    const len = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return if (len > 0) .{ v[0] / len, v[1] / len, v[2] / len } else .{ 0, 1, 0 };
}

test "crate source compiles to two material submeshes with expected bounds" {
    const model = try compile(std.testing.allocator, @embedFile("crate.gltf"), .{});
    defer model.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 48), model.mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 72), model.mesh.indices.len);
    try std.testing.expectEqual(@as(usize, 2), model.submeshes.len);
    try std.testing.expectEqualStrings("hull", std.mem.sliceTo(&model.materials[0].name, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 0.86), model.materials[0].base_color[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.53), model.bounds_max[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.4), model.bounds_min[1], 0.0001);
    // Interleaved band normals decode from the strided view.
    for (model.mesh.vertices) |v| try std.testing.expectApproxEqAbs(@as(f32, 1), v.normal[0] * v.normal[0] + v.normal[1] * v.normal[1] + v.normal[2] * v.normal[2], 0.0001);
}

test "node transforms are baked and hostile inputs are rejected" {
    const allocator = std.testing.allocator;
    // One triangle; node translated by +10 X and rotated 90° about Y.
    const buffer = [_]f32{ 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1 };
    const encoder = std.base64.standard.Encoder;
    var b64: [encoder.calcSize(@sizeOf(@TypeOf(buffer)))]u8 = undefined;
    _ = encoder.encode(&b64, std.mem.asBytes(&buffer));
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.print(
        \\{{"asset":{{"version":"2.0"}},"nodes":[{{"mesh":0,"translation":[10,0,0],"rotation":[0,0.70710678,0,0.70710678]}}],
        \\"meshes":[{{"primitives":[{{"attributes":{{"POSITION":0,"NORMAL":1}}}}]}}],
        \\"accessors":[{{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}},{{"bufferView":0,"byteOffset":36,"componentType":5126,"count":3,"type":"VEC3"}}],
        \\"bufferViews":[{{"buffer":0,"byteLength":72}}],"buffers":[{{"byteLength":72,"uri":"data:application/octet-stream;base64,{s}"}}]}}
    , .{b64});
    const model = try compile(allocator, text.written(), .{});
    defer model.deinit(allocator);
    // (1,0,0) rotated +90° about Y is (0,0,-1); then translated.
    try std.testing.expectApproxEqAbs(@as(f32, 10), model.mesh.vertices[1].position[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -1), model.mesh.vertices[1].position[2], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), model.mesh.vertices[0].normal[0], 0.0001);
    try std.testing.expectEqualStrings("default", std.mem.sliceTo(&model.materials[0].name, 0));

    const out_of_range = try std.mem.replaceOwned(u8, allocator, text.written(), "\"count\":3,\"type\":\"VEC3\"}]", "\"count\":4,\"type\":\"VEC3\"}]");
    defer allocator.free(out_of_range);
    try std.testing.expectError(error.AccessorOutOfRange, compile(allocator, out_of_range, .{}));
    const external = try std.mem.replaceOwned(u8, allocator, text.written(), "data:application/octet-stream;base64,", "../../secret.bin?");
    defer allocator.free(external);
    try std.testing.expectError(error.ExternalBufferUnavailable, compile(allocator, external, .{}));
    try std.testing.expectError(error.UnsafeUri, loadUri(allocator, "../x.bin", .{ .load = failLoad }));
}

fn failLoad(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8) anyerror![]u8 {
    return error.Unexpected;
}
