const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const Model = @This();

/// Runtime model format ("HWMS"). Little-endian, no padding:
///   magic "HWMS", format u32, vertex_stride u32, vertex_count u32, index_count u32,
///   submesh_count u32, material_count u32, bounds_min [3]f32, bounds_max [3]f32,
///   materials { base_color [4]f32, name [24]u8 }, submeshes { first_index u32, index_count u32, material u32 },
///   vertices, indices; v2 adds skin count, per-vertex influences, and 36-byte bind-DQ bones;
///   v3 uses the same influences with 16-byte Ranger-pivot bones; v4 appends one cel-pen byte per
///   vertex after everything else. `encode` writes v3 when a model has no pens, so unpainted
///   models stay byte-identical. The decoder retains v1–v3.
pub const magic = "HWMS";
pub const format_version: u32 = 4;
/// Cel pens are indices into the character cel table (`character/mesh.zig` `Material`); this
/// bound only rejects garbage, and the renderer clamps to the materials it has.
pub const max_pens = 64;
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
skin: ?Skin = null,
/// Optional per-vertex cel pen (which cel material shades and inks the vertex). Null draws every
/// vertex with pen 0, as imports did before pens existed.
pens: ?[]u8 = null,
/// CPU-side mutation counter used by live character slots; not part of the saved format.
revision: u64 = 0,

pub const SkinVertex = extern struct { joints: [4]u8, weights: [4]f32 };
/// HWMS v2 stored the source bind correction instead of the source pivot.
pub const LegacySkinBone = extern struct { real: [4]f32, dual: [4]f32 };
/// One imported joint. `ranger_joint` is the game joint whose pose drives it; `pivot` is where that
/// motion rotates, in model space (the bind position of the matched source joint).
pub const SkinBone = extern struct { ranger_joint: u8, padding: [3]u8 = .{ 0, 0, 0 }, pivot: [3]f32 };
/// A unit dual quaternion as the skinning palette stores it: rotation, then half-translation times rotation.
pub const BonePose = struct { real: [4]f32, dual: [4]f32 };

pub fn retargetLegacyBone(bind: LegacySkinBone, real: [4]f32, dual: [4]f32) BonePose {
    const real_dual = quatMul(real, bind.dual);
    const dual_real = quatMul(dual, bind.real);
    return .{
        .real = quatMul(real, bind.real),
        .dual = .{ real_dual[0] + dual_real[0], real_dual[1] + dual_real[1], real_dual[2] + dual_real[2], real_dual[3] + dual_real[3] },
    };
}

fn quatMul(a: [4]f32, b: [4]f32) [4]f32 {
    return .{
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    };
}

fn rotate(q: [4]f32, v: [3]f32) [3]f32 {
    const u = [3]f32{ q[0], q[1], q[2] };
    const c1 = [3]f32{ u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0] };
    const c = [3]f32{ 2 * c1[0], 2 * c1[1], 2 * c1[2] };
    const c2 = [3]f32{ u[1] * c[2] - u[2] * c[1], u[2] * c[0] - u[0] * c[2], u[0] * c[1] - u[1] * c[0] };
    return .{ v[0] + q[3] * c[0] + c2[0], v[1] + q[3] * c[1] + c2[1], v[2] + q[3] * c[2] + c2[2] };
}

/// Turn the game's palette entry for a joint into one for an imported bone. The game's entry
/// rotates about its own joint position (`rest`, in game metres); the imported mesh has its own
/// proportions, so keep the rotation, move the pivot to the bone's, and carry the joint's travel
/// across in model units (`unit` is model units per metre). At rest the result is the identity.
pub fn retargetBone(bone: SkinBone, rest: [3]f32, real: [4]f32, dual: [4]f32, unit: f32) BonePose {
    const conj = [4]f32{ -real[0], -real[1], -real[2], real[3] };
    const half = quatMul(dual, conj);
    const spun_rest = rotate(real, rest);
    var travel: [3]f32 = undefined;
    for (0..3) |axis| travel[axis] = 2 * half[axis] - rest[axis] + spun_rest[axis];
    const spun_pivot = rotate(real, bone.pivot);
    var shift: [4]f32 = .{ 0, 0, 0, 0 };
    for (0..3) |axis| shift[axis] = bone.pivot[axis] - spun_pivot[axis] + travel[axis] * unit;
    const d = quatMul(shift, real);
    return .{ .real = real, .dual = .{ d[0] * 0.5, d[1] * 0.5, d[2] * 0.5, d[3] * 0.5 } };
}

pub const Skin = struct { vertices: []SkinVertex, bones: []SkinBone, legacy_bind: ?[]LegacySkinBone = null };

pub fn deinit(self: Model, allocator: std.mem.Allocator) void {
    if (self.skin) |skin| {
        allocator.free(skin.vertices);
        allocator.free(skin.bones);
        if (skin.legacy_bind) |legacy| allocator.free(legacy);
    }
    if (self.pens) |pens| allocator.free(pens);
    allocator.free(self.materials);
    allocator.free(self.submeshes);
    self.mesh.deinit(allocator);
}

pub fn clone(allocator: std.mem.Allocator, source: Model) !Model {
    const materials = try allocator.dupe(Material, source.materials);
    errdefer allocator.free(materials);
    const submeshes = try allocator.dupe(Submesh, source.submeshes);
    errdefer allocator.free(submeshes);
    const vertices = try allocator.dupe(Mesh.Vertex, source.mesh.vertices);
    errdefer allocator.free(vertices);
    const indices = try allocator.dupe(u32, source.mesh.indices);
    errdefer allocator.free(indices);
    const skin: ?Skin = if (source.skin) |source_skin| blk: {
        const influences = try allocator.dupe(SkinVertex, source_skin.vertices);
        errdefer allocator.free(influences);
        const bones = try allocator.dupe(SkinBone, source_skin.bones);
        errdefer allocator.free(bones);
        const legacy_bind: ?[]LegacySkinBone = if (source_skin.legacy_bind) |source_legacy| try allocator.dupe(LegacySkinBone, source_legacy) else null;
        break :blk .{ .vertices = influences, .bones = bones, .legacy_bind = legacy_bind };
    } else null;
    errdefer if (skin) |s| {
        allocator.free(s.vertices);
        allocator.free(s.bones);
        if (s.legacy_bind) |legacy| allocator.free(legacy);
    };
    const pens: ?[]u8 = if (source.pens) |p| try allocator.dupe(u8, p) else null;
    return .{
        .pens = pens,
        .mesh = .{ .vertices = vertices, .indices = indices },
        .submeshes = submeshes,
        .materials = materials,
        .bounds_min = source.bounds_min,
        .bounds_max = source.bounds_max,
        .skin = skin,
        .revision = source.revision,
    };
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
    if (self.skin) |skin| {
        if (skin.legacy_bind != null) return error.LegacySkinNeedsReimport;
        if (skin.bones.len == 0 or skin.bones.len > 128 or skin.vertices.len != self.mesh.vertices.len) return error.InvalidSkinData;
        for (skin.vertices) |influence| {
            var sum: f32 = 0;
            for (influence.joints, influence.weights) |joint, weight| {
                if (joint >= skin.bones.len or !std.math.isFinite(weight) or weight < 0) return error.InvalidSkinData;
                sum += weight;
            }
            if (!std.math.isFinite(sum) or sum < 0.999 or sum > 1.001) return error.InvalidSkinData;
        }
        for (skin.bones) |bone| {
            if (bone.ranger_joint >= 64) return error.InvalidSkinData;
            for (bone.pivot) |v| if (!std.math.isFinite(v)) return error.InvalidSkinData;
        }
    }
    if (self.pens) |pens| {
        if (pens.len != self.mesh.vertices.len) return error.InvalidPens;
        for (pens) |p| if (p >= max_pens) return error.InvalidPens;
    }
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll(magic);
    for ([_]u32{ if (self.pens != null) format_version else 3, @sizeOf(Mesh.Vertex), @intCast(self.mesh.vertices.len), @intCast(self.mesh.indices.len), @intCast(self.submeshes.len), @intCast(self.materials.len) }) |v| try w.writeInt(u32, v, .little);
    for (self.bounds_min ++ self.bounds_max) |v| try w.writeInt(u32, @bitCast(v), .little);
    try w.writeInt(u32, if (self.skin) |s| @intCast(s.bones.len) else 0, .little);
    for (self.materials) |m| {
        for (m.base_color) |v| try w.writeInt(u32, @bitCast(v), .little);
        try w.writeAll(&m.name);
    }
    for (self.submeshes) |s| for ([_]u32{ s.first_index, s.index_count, s.material }) |v| try w.writeInt(u32, v, .little);
    for (self.mesh.vertices) |vertex| {
        const floats = vertex.position ++ vertex.normal ++ vertex.uv ++ vertex.color;
        for (floats) |v| try w.writeInt(u32, @bitCast(v), .little);
    }
    for (self.mesh.indices) |v| try w.writeInt(u32, v, .little);
    if (self.skin) |skin| {
        for (skin.vertices) |influence| {
            try w.writeAll(&influence.joints);
            for (influence.weights) |v| try w.writeInt(u32, @bitCast(v), .little);
        }
        for (skin.bones) |bone| {
            try w.writeByte(bone.ranger_joint);
            try w.writeAll(&bone.padding);
            for (bone.pivot) |v| try w.writeInt(u32, @bitCast(v), .little);
        }
    }
    if (self.pens) |pens| try w.writeAll(pens);
    return out.toOwnedSlice();
}

pub const DecodeError = error{ NotAModel, UnsupportedVersion, UnsupportedVertexLayout, Truncated, TrailingBytes, TooLarge, InvalidIndex, InvalidSubmesh, InvalidMaterial, InvalidJoint, InvalidSkinWeights, InvalidPens, NonFiniteValue, OutOfMemory };

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
    const version = try r.int();
    if (version < 1 or version > format_version) return error.UnsupportedVersion;
    if (try r.int() != @sizeOf(Mesh.Vertex)) return error.UnsupportedVertexLayout;
    const vertex_count = try r.int();
    const index_count = try r.int();
    const submesh_count = try r.int();
    const material_count = try r.int();
    if (vertex_count > max_vertices or index_count > max_vertices * 6 or submesh_count > max_submeshes or material_count > max_materials) return error.TooLarge;
    if (vertex_count == 0 or index_count == 0 or index_count % 3 != 0 or submesh_count == 0 or material_count == 0) return error.InvalidSubmesh;
    var result: Model = undefined;
    result.revision = 0;
    for (&result.bounds_min) |*v| v.* = try r.float();
    for (&result.bounds_max) |*v| v.* = try r.float();
    const bone_count = if (version >= 2) try r.int() else 0;
    if (bone_count > 128) return error.TooLarge;
    const bone_stride: usize = if (version == 2) 36 else 16;
    const expected = header_bytes + (if (version >= 2) @as(usize, 4) else 0) + material_count * (16 + name_len) + submesh_count * 12 + vertex_count * @sizeOf(Mesh.Vertex) + index_count * 4 + (if (bone_count > 0) vertex_count * 20 + bone_count * bone_stride else 0) + (if (version >= 4) @as(usize, vertex_count) else 0);
    if (bytes.len < expected) return error.Truncated;
    if (bytes.len > expected) return error.TrailingBytes;

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
        vertex.* = .{
            .position = floats[0..3].*,
            .normal = floats[3..6].*,
            .uv = floats[6..8].*,
            .color = floats[8..11].*,
        };
    }
    const indices = try allocator.alloc(u32, index_count);
    errdefer allocator.free(indices);
    for (indices) |*v| {
        v.* = try r.int();
        if (v.* >= vertex_count) return error.InvalidIndex;
    }
    var skin: ?Skin = null;
    if (bone_count > 0) {
        const influences = try allocator.alloc(SkinVertex, vertex_count);
        errdefer allocator.free(influences);
        for (influences) |*influence| {
            var weight_sum: f32 = 0;
            for (&influence.joints) |*joint| {
                joint.* = bytes[r.at];
                r.at += 1;
                if (joint.* >= bone_count) return error.InvalidJoint;
            }
            for (&influence.weights) |*weight| {
                weight.* = try r.float();
                if (weight.* < 0) return error.InvalidSkinWeights;
                weight_sum += weight.*;
            }
            if (weight_sum < 0.999 or weight_sum > 1.001) return error.InvalidSkinWeights;
        }
        const bones = try allocator.alloc(SkinBone, bone_count);
        errdefer allocator.free(bones);
        const legacy_bind: ?[]LegacySkinBone = if (version == 2) try allocator.alloc(LegacySkinBone, bone_count) else null;
        errdefer if (legacy_bind) |legacy| allocator.free(legacy);
        for (bones, 0..) |*bone, bone_index| {
            bone.ranger_joint = bytes[r.at];
            @memcpy(&bone.padding, bytes[r.at + 1 ..][0..3]);
            r.at += 4;
            if (bone.ranger_joint >= 64) return error.InvalidJoint;
            if (legacy_bind) |legacy| {
                for (&legacy[bone_index].real) |*v| v.* = try r.float();
                for (&legacy[bone_index].dual) |*v| v.* = try r.float();
                bone.pivot = .{ 0, 0, 0 };
            } else {
                for (&bone.pivot) |*v| v.* = try r.float();
            }
        }
        skin = .{ .vertices = influences, .bones = bones, .legacy_bind = legacy_bind };
    }
    errdefer if (skin) |s| {
        allocator.free(s.vertices);
        allocator.free(s.bones);
        if (s.legacy_bind) |legacy| allocator.free(legacy);
    };
    result.pens = if (version >= 4) blk: {
        const pens = try allocator.dupe(u8, bytes[r.at..][0..vertex_count]);
        for (pens) |p| if (p >= max_pens) {
            allocator.free(pens);
            return error.InvalidPens;
        };
        break :blk pens;
    } else null;
    result.mesh = .{ .vertices = vertices, .indices = indices };
    result.submeshes = submeshes;
    result.materials = materials;
    result.skin = skin;
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

test "retargeting keeps the rotation, moves the pivot, and is the identity at rest" {
    const bone: SkinBone = .{ .ranger_joint = 3, .pivot = .{ 10, 20, 0 } };
    const rest = [3]f32{ 0.2, 1.4, 0 };
    // At rest the game's entry is the identity.
    const still = retargetBone(bone, rest, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 0 }, 100);
    try std.testing.expectEqualDeep([4]f32{ 0, 0, 0, 1 }, still.real);
    for (still.dual) |v| try std.testing.expectApproxEqAbs(@as(f32, 0), v, 1e-6);
    // Quarter turn about Y, pivoting on the game's joint: the game's own point at `rest` stays put.
    const s = @sqrt(0.5);
    const real = [4]f32{ 0, s, 0, s };
    const t_game = [3]f32{ rest[0] - rotate(real, rest)[0], rest[1] - rotate(real, rest)[1], rest[2] - rotate(real, rest)[2] };
    const d = quatMul(.{ t_game[0], t_game[1], t_game[2], 0 }, real);
    const moved = retargetBone(bone, rest, real, .{ d[0] * 0.5, d[1] * 0.5, d[2] * 0.5, d[3] * 0.5 }, 100);
    // The imported pivot must stay fixed, whatever the game's pivot was.
    const fixed = applyPose(moved, bone.pivot);
    for (bone.pivot, fixed) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-4);
    // A point one unit along +X from the pivot swings to -Z, like the game's rotation.
    const swung = applyPose(moved, .{ bone.pivot[0] + 1, bone.pivot[1], bone.pivot[2] });
    try std.testing.expectApproxEqAbs(bone.pivot[0], swung[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -1), swung[2] - bone.pivot[2], 1e-4);
    // Joint travel (a hip bob of 0.1 m) arrives in model units.
    const bob = retargetBone(bone, rest, .{ 0, 0, 0, 1 }, .{ 0, 0.05, 0, 0 }, 100);
    try std.testing.expectApproxEqAbs(@as(f32, 10), applyPose(bob, .{ 0, 0, 0 })[1], 1e-3);
}

fn applyPose(p: BonePose, v: [3]f32) [3]f32 {
    const conj = [4]f32{ -p.real[0], -p.real[1], -p.real[2], p.real[3] };
    const half = quatMul(p.dual, conj);
    const r = rotate(p.real, v);
    return .{ r[0] + 2 * half[0], r[1] + 2 * half[1], r[2] + 2 * half[2] };
}

test "HWMS v3 round-trips retained influences and older fixtures remain readable" {
    const a = std.testing.allocator;
    var model = try fromMesh(a, try Mesh.cube(a), .named("rigged", .{ 1, 1, 1, 1 }));
    const influences = try a.alloc(SkinVertex, model.mesh.vertices.len);
    @memset(influences, .{ .joints = .{ 0, 0, 0, 0 }, .weights = .{ 1, 0, 0, 0 } });
    const bones = try a.alloc(SkinBone, 1);
    bones[0] = .{ .ranger_joint = 3, .pivot = .{ 0, 1, 0 } };
    model.skin = .{ .vertices = influences, .bones = bones };
    defer model.deinit(a);

    const bytes = try model.encode(a);
    defer a.free(bytes);
    const decoded = try decode(a, bytes);
    defer decoded.deinit(a);
    try std.testing.expectEqualDeep(model.skin.?, decoded.skin.?);
    try std.testing.expectEqual(@as(u8, 3), decoded.skin.?.bones[0].ranger_joint);

    // HWMS v2 used a 36-byte source-bind DQ per bone; construct that real legacy layout.
    const v2_bytes = try a.alloc(u8, bytes.len + 20);
    defer a.free(v2_bytes);
    const bone_at = bytes.len - 16;
    @memcpy(v2_bytes[0..bone_at], bytes[0..bone_at]);
    @memcpy(v2_bytes[bone_at .. bone_at + 4], bytes[bone_at .. bone_at + 4]);
    var v2_at = bone_at + 4;
    const old_bind = [8]f32{ 0, 0, 0, 1, 0.5, 0, 0, 0 };
    for (old_bind) |value| {
        std.mem.writeInt(u32, v2_bytes[v2_at..][0..4], @bitCast(value), .little);
        v2_at += 4;
    }
    std.mem.writeInt(u32, v2_bytes[4..8], 2, .little);
    const v2 = try decode(a, v2_bytes);
    defer v2.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), v2.skin.?.legacy_bind.?.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), v2.skin.?.legacy_bind.?[0].dual[0], 1e-6);
    try std.testing.expectError(error.LegacySkinNeedsReimport, v2.encode(a));

    // A v1 file is the old static payload, without a skin-count word.
    var static_model = try fromMesh(a, try Mesh.cube(a), .{});
    defer static_model.deinit(a);
    const current = try static_model.encode(a);
    defer a.free(current);
    const legacy = try a.alloc(u8, current.len - 4);
    defer a.free(legacy);
    @memcpy(legacy[0..52], current[0..52]);
    @memcpy(legacy[52..], current[56..]);
    std.mem.writeInt(u32, legacy[4..8], 1, .little);
    const old = try decode(a, legacy);
    defer old.deinit(a);
    try std.testing.expect(old.skin == null);
    try std.testing.expectEqualSlices(u32, static_model.mesh.indices, old.mesh.indices);
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

test "HWMS v4 carries per-vertex cel pens; unpainted models still write v3" {
    const a = std.testing.allocator;
    var model = try fromMesh(a, try Mesh.cube(a), .{});
    defer model.deinit(a);
    const plain = try model.encode(a);
    defer a.free(plain);
    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, plain[4..8], .little));
    model.pens = try a.alloc(u8, model.mesh.vertices.len);
    for (model.pens.?, 0..) |*p, i| p.* = @intCast(i % 5);
    const painted = try model.encode(a);
    defer a.free(painted);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, painted[4..8], .little));
    const back = try decode(a, painted);
    defer back.deinit(a);
    try std.testing.expectEqualSlices(u8, model.pens.?, back.pens.?);
    const copy = try clone(a, back);
    defer copy.deinit(a);
    try std.testing.expectEqualSlices(u8, model.pens.?, copy.pens.?);
    const bad = try a.dupe(u8, painted);
    defer a.free(bad);
    bad[bad.len - 1] = max_pens;
    try std.testing.expectError(error.InvalidPens, decode(a, bad));
    try std.testing.expectError(error.Truncated, decode(a, painted[0 .. painted.len - 1]));
    model.pens.?[0] = max_pens;
    try std.testing.expectError(error.InvalidPens, model.encode(a));
}
