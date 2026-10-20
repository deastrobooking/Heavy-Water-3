//! Saved vertex-tool edits of an imported character: the whole edited mesh (positions, colours,
//! cel pens, topology and skin influences) as a runtime model file beside the part sidecar. On
//! load it replaces the freshly imported source, as long as it still drives the same rig.
const std = @import("std");
const Model = @import("../asset/Model.zig");

pub const imported_path = "saves/imported-character.edited.hwmesh";
pub const captain_path = "saves/captain.edited.hwmesh";

pub const Error = error{ IncompatibleRig, OutOfMemory } || Model.DecodeError;

/// The bytes to write for `model`.
pub fn encode(allocator: std.mem.Allocator, model: Model) ![]u8 {
    return model.encode(allocator);
}

/// Decodes saved edits and checks they still belong on `source`: a skinned source needs a skin
/// with the same bones mapped to the same game joints (otherwise the retarget would drive the
/// wrong parts); an unskinned source needs an unskinned edit. The caller owns the result.
pub fn adopt(allocator: std.mem.Allocator, bytes: []const u8, source: Model) Error!Model {
    var edited = try Model.decode(allocator, bytes);
    errdefer edited.deinit(allocator);
    if ((source.skin == null) != (edited.skin == null)) return error.IncompatibleRig;
    if (source.skin) |s| {
        const e = edited.skin.?;
        if (s.bones.len != e.bones.len) return error.IncompatibleRig;
        for (s.bones, e.bones) |a, b| if (a.ranger_joint != b.ranger_joint) return error.IncompatibleRig;
    }
    return edited;
}

test "saved edits round-trip with pens and skin, and a different rig is refused" {
    const a = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    var source = try Model.fromMesh(a, try Mesh.cube(a), .{});
    defer source.deinit(a);
    const influences = try a.alloc(Model.SkinVertex, source.mesh.vertices.len);
    @memset(influences, .{ .joints = .{ 0, 0, 0, 0 }, .weights = .{ 1, 0, 0, 0 } });
    const bones = try a.alloc(Model.SkinBone, 1);
    bones[0] = .{ .ranger_joint = 3, .pivot = .{ 0, 1, 0 } };
    source.skin = .{ .vertices = influences, .bones = bones };

    var edited = try Model.clone(a, source);
    defer edited.deinit(a);
    edited.mesh.vertices[0].position[1] += 0.25;
    edited.mesh.vertices[1].color = .{ 1, 0, 0 };
    edited.pens = try a.alloc(u8, edited.mesh.vertices.len);
    @memset(edited.pens.?, 9);
    const bytes = try encode(a, edited);
    defer a.free(bytes);
    var back = try adopt(a, bytes, source);
    defer back.deinit(a);
    try std.testing.expectEqualSlices(Mesh.Vertex, edited.mesh.vertices, back.mesh.vertices);
    try std.testing.expectEqualSlices(u8, edited.pens.?, back.pens.?);

    // A source whose bone drives a different game joint refuses the saved edit.
    source.skin.?.bones[0].ranger_joint = 4;
    try std.testing.expectError(error.IncompatibleRig, adopt(a, bytes, source));
    // So does an unskinned source.
    var plain = try Model.fromMesh(a, try Mesh.cube(a), .{});
    defer plain.deinit(a);
    try std.testing.expectError(error.IncompatibleRig, adopt(a, bytes, plain));
    try std.testing.expectError(error.NotAModel, adopt(a, "junk junk junk junk junk junk junk junk junk junk junk!", source));
}
