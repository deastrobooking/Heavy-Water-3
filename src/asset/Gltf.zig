const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const Model = @import("Model.zig");
const GameAnimation = @import("../character/Animation.zig");
const GameSkeleton = @import("../character/skeleton.zig");

/// glTF 2.0 importer for the asset compiler. Supports .gltf (data-URI or resolver-loaded buffers)
/// and .glb; triangle primitives with POSITION (NORMAL and TEXCOORD_0 optional); u8/u16/u32
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
    scenes: []const struct { name: ?[]const u8 = null, nodes: []const u32 = &.{} } = &.{},
    nodes: []const Node = &.{},
    meshes: []const struct { name: ?[]const u8 = null, primitives: []const Primitive } = &.{},
    materials: []const MaterialDef = &.{},
    accessors: []const Accessor = &.{},
    bufferViews: []const BufferView = &.{},
    buffers: []const struct { byteLength: usize, uri: ?[]const u8 = null } = &.{},
    extensionsRequired: []const []const u8 = &.{},
    extensionsUsed: []const []const u8 = &.{},
    skins: []const SkinDef = &.{},
    animations: []const std.json.Value = &.{},
    images: []const ImageDef = &.{},
    textures: []const std.json.Value = &.{},
};
const Node = struct {
    name: ?[]const u8 = null,
    mesh: ?u32 = null,
    children: []const u32 = &.{},
    matrix: ?[16]f32 = null,
    translation: [3]f32 = .{ 0, 0, 0 },
    rotation: [4]f32 = .{ 0, 0, 0, 1 },
    scale: [3]f32 = .{ 1, 1, 1 },
    skin: ?u32 = null,
};
const SkinDef = struct {
    name: ?[]const u8 = null,
    joints: []const u32 = &.{},
    inverseBindMatrices: ?u32 = null,
    skeleton: ?u32 = null,
};
const ImageDef = struct { name: ?[]const u8 = null, uri: ?[]const u8 = null, mimeType: ?[]const u8 = null, bufferView: ?u32 = null };
const Primitive = struct {
    attributes: struct { POSITION: u32, NORMAL: ?u32 = null, TEXCOORD_0: ?u32 = null, JOINTS_0: ?u32 = null, WEIGHTS_0: ?u32 = null },
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

pub const TraceModule = struct {
    id: []const u8,
    node: u32,
    node_name: []const u8,
    mesh: u32,
    mesh_name: []const u8,
    primitive: u32,
    material: ?[]const u8,
    vertex_count: ?usize,
    index_count: ?usize,
    has_normals: bool,
    generated_normals: bool,
    has_uv0: bool,
    triangle_mode: bool,
    has_morph_targets: bool,
    in_selected_scene: bool,
    world_transform: ?Mat,
};
pub const TraceDependency = struct { kind: []const u8, uri: ?[]const u8, embedded: bool, byte_length: ?usize = null };
pub const TraceJoint = struct { index: u32, node: u32, name: []const u8, parent_joint: ?u32 };
pub const TraceSkin = struct {
    index: u32,
    name: []const u8,
    joint_count: usize,
    inverse_bind_accessor: ?u32,
    joints: []const TraceJoint,
};
pub const Trace = struct {
    trace_format: u32 = 2,
    source_format: []const u8,
    gltf_version: []const u8,
    selected_scene: ?u32,
    scene_count: usize,
    node_count: usize,
    mesh_count: usize,
    material_count: usize,
    modules: []const TraceModule,
    skins: []const TraceSkin,
    dependencies: []const TraceDependency,
    extensions_used: []const []const u8,
    extensions_required: []const []const u8,
    skin_count: usize,
    animation_count: usize,
    image_count: usize,
    texture_count: usize,
    import_notes: []const []const u8,
};

pub const ModuleAddress = struct { node: u32, primitive: u32 };

/// Return the source map in caller-owned arena storage. Keep that arena alive while using names.
pub fn inspect(arena: std.mem.Allocator, source: []const u8) !Trace {
    return traceInArena(arena, source);
}

/// Produce a source map for static model import. Every node/mesh/primitive occurrence gets a
/// stable address in the source asset, even though the current HWMS runtime flattens those parts.
fn traceInArena(arena: std.mem.Allocator, source: []const u8) !Trace {
    const is_glb = source.len >= 12 and std.mem.eql(u8, source[0..4], "glTF");
    const json = if (is_glb) (try splitGlb(source)).json else source;
    const doc = try std.json.parseFromSliceLeaky(Doc, arena, json, .{ .ignore_unknown_fields = true });
    if (!std.mem.startsWith(u8, doc.asset.version, "2.")) return error.UnsupportedGltfVersion;
    const active_nodes = try selectedNodes(arena, doc);

    var modules: std.ArrayList(TraceModule) = .empty;
    var notes: std.ArrayList([]const u8) = .empty;
    for (doc.nodes, 0..) |node, node_index| if (node.mesh) |mesh_index| {
        if (mesh_index >= doc.meshes.len) continue;
        const mesh = doc.meshes[mesh_index];
        const node_name = node.name orelse try std.fmt.allocPrint(arena, "node_{d}", .{node_index});
        const mesh_name = mesh.name orelse try std.fmt.allocPrint(arena, "mesh_{d}", .{mesh_index});
        for (mesh.primitives, 0..) |primitive, primitive_index| {
            const id = try std.fmt.allocPrint(arena, "node/{d}:{s}/mesh/{d}:{s}/primitive/{d}", .{ node_index, node_name, mesh_index, mesh_name, primitive_index });
            const material_name = if (primitive.material) |material_index| if (material_index < doc.materials.len) doc.materials[material_index].name else null else null;
            const position_count = if (primitive.attributes.POSITION < doc.accessors.len) doc.accessors[primitive.attributes.POSITION].count else null;
            const index_count = if (primitive.indices) |index| if (index < doc.accessors.len) doc.accessors[index].count else null else position_count;
            try modules.append(arena, .{
                .id = id,
                .node = @intCast(node_index),
                .node_name = node_name,
                .mesh = mesh_index,
                .mesh_name = mesh_name,
                .primitive = @intCast(primitive_index),
                .material = material_name,
                .vertex_count = position_count,
                .index_count = index_count,
                .has_normals = primitive.attributes.NORMAL != null,
                .generated_normals = primitive.attributes.NORMAL == null,
                .has_uv0 = primitive.attributes.TEXCOORD_0 != null,
                .triangle_mode = primitive.mode == 4,
                .has_morph_targets = primitive.targets != null,
                .in_selected_scene = active_nodes.active[node_index],
                .world_transform = if (active_nodes.active[node_index]) active_nodes.world[node_index] else null,
            });
            if (primitive.attributes.NORMAL == null) try notes.append(arena, "A primitive has no NORMAL accessor; normals will be generated from its triangle faces.");
            if (primitive.mode != 4) try notes.append(arena, "A primitive is not triangle-list geometry and cannot be converted by the current model importer.");
            if (primitive.targets != null) try notes.append(arena, "Morph targets are present and are not supported by the current model importer.");
        }
    };

    const dependencies = try arena.alloc(TraceDependency, doc.buffers.len + doc.images.len);
    var dependency_count: usize = 0;
    for (doc.buffers, 0..) |buffer, i| {
        const embedded_glb = is_glb and i == 0 and buffer.uri == null;
        const data_uri = if (buffer.uri) |uri| std.mem.startsWith(u8, uri, "data:") else false;
        dependencies[dependency_count] = .{ .kind = "buffer", .uri = if (data_uri) null else buffer.uri, .embedded = embedded_glb or data_uri, .byte_length = buffer.byteLength };
        dependency_count += 1;
    }
    for (doc.images) |image| {
        const data_uri = if (image.uri) |uri| std.mem.startsWith(u8, uri, "data:") else false;
        dependencies[dependency_count] = .{ .kind = "image", .uri = if (data_uri) null else image.uri, .embedded = image.bufferView != null or data_uri, .byte_length = null };
        dependency_count += 1;
    }
    if (doc.extensionsRequired.len != 0) try notes.append(arena, "Required glTF extensions are not handled by the static mesh importer.");
    var node_has_skin = false;
    for (doc.nodes) |node| if (node.skin != null) {
        node_has_skin = true;
    };
    if (doc.skins.len != 0 or node_has_skin) try notes.append(arena, "Skeletal skins are retargeted onto the game's humanoid skeleton by bone name.");
    if (doc.animations.len != 0) try notes.append(arena, "Animations are traced but not imported into runtime clips yet.");
    if (doc.textures.len != 0 or doc.images.len != 0) try notes.append(arena, "Image textures are traced but the current HWMS material path imports base-color factors only.");

    const skins = try traceSkins(arena, doc);

    return .{
        .source_format = if (is_glb) "glb" else "gltf",
        .gltf_version = doc.asset.version,
        .selected_scene = doc.scene,
        .scene_count = doc.scenes.len,
        .node_count = doc.nodes.len,
        .mesh_count = doc.meshes.len,
        .material_count = doc.materials.len,
        .modules = try modules.toOwnedSlice(arena),
        .skins = skins,
        .dependencies = dependencies[0..dependency_count],
        .extensions_used = doc.extensionsUsed,
        .extensions_required = doc.extensionsRequired,
        .skin_count = doc.skins.len,
        .animation_count = doc.animations.len,
        .image_count = doc.images.len,
        .texture_count = doc.textures.len,
        .import_notes = try notes.toOwnedSlice(arena),
    };
}

fn traceSkins(arena: std.mem.Allocator, doc: Doc) ![]const TraceSkin {
    if (doc.skins.len == 0) return &.{};
    const node_parents = try arena.alloc(?u32, doc.nodes.len);
    @memset(node_parents, null);
    for (doc.nodes, 0..) |node, parent_index| for (node.children) |child| {
        if (child >= doc.nodes.len) return error.InvalidNode;
        if (node_parents[child] != null) return error.MultipleNodeParents;
        node_parents[child] = @intCast(parent_index);
    };

    const result = try arena.alloc(TraceSkin, doc.skins.len);
    for (doc.skins, 0..) |skin, skin_index| {
        if (skin.joints.len > 1024) return error.TooManyJoints;
        const joint_map = try arena.alloc(?u32, doc.nodes.len);
        @memset(joint_map, null);
        for (skin.joints, 0..) |node_index, joint_index| {
            if (node_index >= doc.nodes.len) return error.InvalidJoint;
            if (joint_map[node_index] != null) return error.DuplicateJoint;
            joint_map[node_index] = @intCast(joint_index);
        }
        const joints = try arena.alloc(TraceJoint, skin.joints.len);
        for (skin.joints, 0..) |node_index, joint_index| {
            var parent_joint: ?u32 = null;
            var ancestor = node_parents[node_index];
            var depth: usize = 0;
            while (ancestor) |node_parent| : (depth += 1) {
                if (depth > doc.nodes.len) return error.NodeCycle;
                if (joint_map[node_parent]) |joint_parent| {
                    parent_joint = joint_parent;
                    break;
                }
                ancestor = node_parents[node_parent];
            }
            const node_name = doc.nodes[node_index].name orelse try std.fmt.allocPrint(arena, "node_{d}", .{node_index});
            joints[joint_index] = .{ .index = @intCast(joint_index), .node = node_index, .name = node_name, .parent_joint = parent_joint };
        }
        result[skin_index] = .{
            .index = @intCast(skin_index),
            .name = skin.name orelse try std.fmt.allocPrint(arena, "skin_{d}", .{skin_index}),
            .joint_count = skin.joints.len,
            .inverse_bind_accessor = skin.inverseBindMatrices,
            .joints = joints,
        };
    }
    return result;
}

const SceneNodes = struct { active: []bool, world: []Mat };

fn selectedNodes(arena: std.mem.Allocator, doc: Doc) !SceneNodes {
    return selectedNodesWithPose(arena, doc, .bind);
}

fn selectedNodesWithPose(arena: std.mem.Allocator, doc: Doc, pose: PreviewPose) !SceneNodes {
    const active = try arena.alloc(bool, doc.nodes.len);
    @memset(active, false);
    const world = try arena.alloc(Mat, doc.nodes.len);
    if (doc.scenes.len != 0) {
        const scene_index = doc.scene orelse 0;
        if (scene_index >= doc.scenes.len) return error.InvalidScene;
        for (doc.scenes[scene_index].nodes) |root| {
            if (pose == .run) try markActiveRun(doc, active, world, root, identity, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 1 }, 0) else try markActive(doc, active, world, root, identity, 0, .bind);
        }
    } else {
        const referenced = try arena.alloc(bool, doc.nodes.len);
        @memset(referenced, false);
        for (doc.nodes) |node| for (node.children) |child| {
            if (child < referenced.len) referenced[child] = true;
        };
        for (referenced, 0..) |is_child, i| if (!is_child) {
            if (pose == .run) try markActiveRun(doc, active, world, @intCast(i), identity, .{ 0, 0, 0, 1 }, .{ 0, 0, 0, 1 }, 0) else try markActive(doc, active, world, @intCast(i), identity, 0, .bind);
        };
    }
    return .{ .active = active, .world = world };
}

fn markActive(doc: Doc, active: []bool, world: []Mat, index: u32, parent: Mat, depth: u32, pose: PreviewPose) anyerror!void {
    if (index >= doc.nodes.len) return error.InvalidNode;
    if (depth > 64) return error.NodeCycle;
    if (active[index]) return;
    const node = doc.nodes[index];
    active[index] = true;
    const local = node.matrix orelse trs(node.translation, node.rotation, node.scale);
    world[index] = mul(parent, local);
    for (node.children) |child| try markActive(doc, active, world, child, world[index], depth + 1, pose);
}

fn sourcePoseDelta(name: ?[]const u8) ?[4]f32 {
    const source_name = name orelse return null;
    for (GameAnimation.run_tracks) |track| {
        if (matchesControllerJoint(source_name, @enumFromInt(track.joint))) {
            const q = GameAnimation.sample(GameAnimation.run, track, std.math.pi * 0.5);
            return .{ q.x, q.y, q.z, q.w };
        }
    }
    return null;
}

/// Count distinct humanoid joints (root excluded) that the imported skin's bone names drive.
pub fn mappedGameplayJointCount(trace: Trace) usize {
    var mapped: [GameSkeleton.humanoid_joint_count]bool = @splat(false);
    for (trace.skins) |skin| for (skin.joints) |joint| {
        if (humanoidJoint(joint.name)) |j| mapped[@intFromEnum(j)] = true;
    };
    var count: usize = 0;
    for (mapped) |yes| count += @intFromBool(yes);
    return count;
}

fn matchesControllerJoint(source: []const u8, joint: GameSkeleton.Joint) bool {
    return humanoidJoint(source) == joint;
}

const Side = enum { center, left, right };

/// Maps a source bone name to the game's humanoid joint, across the common rig conventions:
/// Mixamo (`mixamorig:LeftForeArm`), VRoid (`J_Bip_L_UpperArm`), Blender/Rigify
/// (`DEF-forearm.L`), Unreal (`lowerarm_l`, `spine_03`), 3ds Max Biped (`Bip01 L Thigh`) and
/// Unity humanoid names. Side comes from a separate `L`/`R`/`Left`/`Right` token, or a token that
/// starts or ends with `left`/`right`; the part is the rest of the name with separators removed.
/// Fingers, twist and end bones return null and inherit their nearest mapped ancestor.
pub fn humanoidJoint(source: []const u8) ?GameSkeleton.Joint {
    var part_buf: [96]u8 = undefined;
    var part_len: usize = 0;
    var side: Side = .center;
    var tokens = std.mem.tokenizeAny(u8, source, " _.:-|/\\");
    while (tokens.next()) |raw| {
        var token_buf: [96]u8 = undefined;
        if (raw.len > token_buf.len) return null;
        const token = std.ascii.lowerString(&token_buf, raw);
        var rest = token;
        if (std.mem.eql(u8, token, "l") or std.mem.eql(u8, token, "left")) {
            side = .left;
            continue;
        }
        if (std.mem.eql(u8, token, "r") or std.mem.eql(u8, token, "right")) {
            side = .right;
            continue;
        }
        if (std.mem.startsWith(u8, rest, "left")) {
            side = .left;
            rest = rest[4..];
        } else if (std.mem.startsWith(u8, rest, "right")) {
            side = .right;
            rest = rest[5..];
        } else if (std.mem.endsWith(u8, rest, "left") and rest.len > 4) {
            side = .left;
            rest = rest[0 .. rest.len - 4];
        } else if (std.mem.endsWith(u8, rest, "right") and rest.len > 5) {
            side = .right;
            rest = rest[0 .. rest.len - 5];
        }
        for (rest) |ch| if (std.ascii.isAlphanumeric(ch)) {
            if (part_len == part_buf.len) return null;
            part_buf[part_len] = ch;
            part_len += 1;
        };
    }
    const part = part_buf[0..part_len];
    const has = struct {
        fn any(name: []const u8, comptime needles: []const []const u8) bool {
            inline for (needles) |n| if (std.mem.indexOf(u8, name, n) != null) return true;
            return false;
        }
        fn end(name: []const u8, comptime needles: []const []const u8) bool {
            inline for (needles) |n| if (std.mem.endsWith(u8, name, n)) return true;
            return false;
        }
    };
    // Fingers, twist/roll helpers and end markers follow their parent instead of driving a joint.
    if (has.any(part, &.{ "thumb", "index", "middle", "ring", "pinky", "little", "finger", "twist", "roll", "end", "ik", "pole", "target" })) return null;
    if (side != .center) {
        const l = side == .left;
        const pick = struct {
            fn of(left: bool, a: GameSkeleton.Joint, b: GameSkeleton.Joint) GameSkeleton.Joint {
                return if (left) a else b;
            }
        }.of;
        if (has.any(part, &.{ "toe", "ball" })) return pick(l, .toe_l, .toe_r);
        if (has.any(part, &.{ "foot", "ankle" })) return pick(l, .foot_l, .foot_r);
        if (has.any(part, &.{ "upleg", "upperleg", "thigh" })) return pick(l, .thigh_l, .thigh_r);
        if (has.any(part, &.{ "lowerleg", "calf", "shin", "knee" }) or has.end(part, &.{"leg"})) return pick(l, .shin_l, .shin_r);
        if (has.any(part, &.{ "hand", "wrist", "palm" })) return pick(l, .hand_l, .hand_r);
        if (has.any(part, &.{ "forearm", "lowerarm", "elbow" })) return pick(l, .lower_arm_l, .lower_arm_r);
        if (has.any(part, &.{ "upperarm", "uparm" }) or has.end(part, &.{"arm"})) return pick(l, .upper_arm_l, .upper_arm_r);
        if (has.any(part, &.{ "shoulder", "clavicle", "collar" })) return pick(l, .shoulder_l, .shoulder_r);
        return null;
    }
    if (has.any(part, &.{"head"})) return .head;
    if (has.any(part, &.{"neck"})) return .neck;
    if (has.any(part, &.{ "upperchest", "chest", "thorax" }) or has.end(part, &.{ "spine2", "spine3", "spine03", "spine003", "spine04", "spine004", "spine05" })) return .chest;
    if (has.end(part, &.{ "spine", "spine1", "spine01", "spine001", "spine02", "spine002", "abdomen", "waist" })) return .spine;
    if (has.end(part, &.{ "hips", "hip", "pelvis" })) return .hips;
    return null;
}


fn markActiveRun(doc: Doc, active: []bool, world: []Mat, index: u32, parent_world: Mat, parent_bind_q: [4]f32, parent_pose_q: [4]f32, depth: u32) anyerror!void {
    if (index >= doc.nodes.len) return error.InvalidNode;
    if (depth > 64) return error.NodeCycle;
    const node = doc.nodes[index];
    if (node.matrix != null) return error.PosedMatrixNodeUnsupported;
    active[index] = true;
    const bind_local_q = node.rotation;
    const converted_delta = if (sourcePoseDelta(node.name)) |delta|
        quatMul(quatMul(quatConjugate(parent_bind_q), delta), parent_bind_q)
    else
        .{ 0, 0, 0, 1 };
    const pose_local_q = quatNormalize(quatMul(converted_delta, bind_local_q));
    const bind_world_q = quatNormalize(quatMul(parent_bind_q, bind_local_q));
    const pose_world_q = quatNormalize(quatMul(parent_pose_q, pose_local_q));
    const local_pose = trs(node.translation, pose_local_q, node.scale);
    world[index] = mul(parent_world, local_pose);
    for (node.children) |child| try markActiveRun(doc, active, world, child, world[index], bind_world_q, pose_world_q, depth + 1);
}

fn quatMul(a: [4]f32, b: [4]f32) [4]f32 {
    const ax, const ay, const az, const aw = a;
    const bx, const by, const bz, const bw = b;
    return .{
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    };
}

fn quatConjugate(q: [4]f32) [4]f32 {
    return .{ -q[0], -q[1], -q[2], q[3] };
}

fn quatNormalize(q: [4]f32) [4]f32 {
    const len = @sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
    return if (len > 1e-8) .{ q[0] / len, q[1] / len, q[2] / len, q[3] / len } else .{ 0, 0, 0, 1 };
}

pub fn traceJson(allocator: std.mem.Allocator, source: []const u8, provenance: anytype) ![]u8 {
    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const report = try traceInArena(arena_state.allocator(), source);
    return std.json.Stringify.valueAlloc(allocator, .{ .provenance = provenance, .source = report }, .{ .whitespace = .indent_2 });
}

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
    return compileFiltered(allocator, source, resolver, null, false, .bind, false);
}

pub const PreviewPose = enum { bind, run };

/// Compile a skinned source into a static visual preview. Skin weights and inverse-bind matrices
/// are evaluated on the CPU; the resulting HWMS contains no rig or animation data.
pub fn compileBindPosePreview(allocator: std.mem.Allocator, source: []const u8, resolver: Resolver) !Model {
    return compilePosePreview(allocator, source, resolver, .bind);
}

/// Preview one of the game's native procedural poses on a compatible named humanoid rig.
pub fn compilePosePreview(allocator: std.mem.Allocator, source: []const u8, resolver: Resolver, pose: PreviewPose) !Model {
    return compileFiltered(allocator, source, resolver, null, true, pose, false);
}

/// Compile a bind-pose mesh with retained per-vertex influences for runtime animation.
pub fn compileRigged(allocator: std.mem.Allocator, source: []const u8, resolver: Resolver) !Model {
    return compileFiltered(allocator, source, resolver, null, true, .bind, true);
}

/// Compile one node's primitive into an independent HWMS module, retaining its accumulated
/// ancestor transform. `inspect` supplies stable source addresses for these selectors.
pub fn compileModule(allocator: std.mem.Allocator, source: []const u8, resolver: Resolver, address: ModuleAddress) !Model {
    return compileFiltered(allocator, source, resolver, address, false, .bind, false);
}

fn compileFiltered(allocator: std.mem.Allocator, source: []const u8, resolver: Resolver, selector: ?ModuleAddress, allow_skin_preview: bool, preview_pose: PreviewPose, retain_rig: bool) !Model {
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
    const node_state = try selectedNodesWithPose(arena, doc, if (retain_rig) .bind else if (allow_skin_preview) preview_pose else .bind);
    var builder: Builder = .{ .doc = doc, .buffers = buffers, .arena = arena, .selector = selector, .allow_skin_preview = allow_skin_preview, .retain_rig = retain_rig, .node_world = node_state.world, .node_active = node_state.active };
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
    if (builder.has_static_rig_vertices) {
        if (builder.rig_bones.items.len >= 128) return error.TooManyJoints;
        const root_bone: u8 = @intCast(builder.rig_bones.items.len);
        try builder.rig_bones.append(arena, .{ .ranger_joint = @intCast(@intFromEnum(GameSkeleton.Joint.root)), .pivot = .{ 0, 0, 0 } });
        for (builder.rig_vertices.items) |*influence| if (influence.joints[0] == 255) {
            influence.* = .{ .joints = .{ root_bone, 0, 0, 0 }, .weights = .{ 1, 0, 0, 0 } };
        };
    }

    // Only the final owned arrays leave the arena.
    const vertices = try allocator.dupe(Mesh.Vertex, builder.vertices.items);
    errdefer allocator.free(vertices);
    const indices = try allocator.dupe(u32, builder.indices.items);
    errdefer allocator.free(indices);
    const submeshes = try allocator.dupe(Model.Submesh, builder.submeshes.items);
    errdefer allocator.free(submeshes);
    const materials = try allocator.dupe(Model.Material, builder.materials.items);
    var skin: ?Model.Skin = null;
    if (retain_rig) {
        if (builder.rig_skin == null or builder.rig_bones.items.len == 0 or builder.rig_vertices.items.len != vertices.len) return error.CharacterNeedsSkin;
        const rig_vertices = try allocator.dupe(Model.SkinVertex, builder.rig_vertices.items);
        errdefer allocator.free(rig_vertices);
        const rig_bones = try allocator.dupe(Model.SkinBone, builder.rig_bones.items);
        skin = .{ .vertices = rig_vertices, .bones = rig_bones };
    }
    var model: Model = .{ .mesh = .{ .vertices = vertices, .indices = indices }, .submeshes = submeshes, .materials = materials, .bounds_min = undefined, .bounds_max = undefined, .skin = skin };
    model.computeBounds();
    if (retain_rig) {
        model.bounds_min = builder.rig_bounds_min;
        model.bounds_max = builder.rig_bounds_max;
    }
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
    selector: ?ModuleAddress = null,
    allow_skin_preview: bool = false,
    retain_rig: bool = false,
    rig_skin: ?u32 = null,
    rig_vertices: std.ArrayList(Model.SkinVertex) = .empty,
    rig_bones: std.ArrayList(Model.SkinBone) = .empty,
    has_static_rig_vertices: bool = false,
    rig_bounds_min: [3]f32 = @splat(std.math.inf(f32)),
    rig_bounds_max: [3]f32 = @splat(-std.math.inf(f32)),
    node_world: []const Mat,
    node_active: []const bool,

    fn visit(self: *Builder, index: u32, parent: Mat, depth: u32) !void {
        if (index >= self.doc.nodes.len) return error.InvalidNode;
        if (depth > 64) return error.NodeCycle;
        const node = self.doc.nodes[index];
        if (node.skin != null and !self.allow_skin_preview) return error.SkinsUnsupported;
        const local = node.matrix orelse trs(node.translation, node.rotation, node.scale);
        const world = mul(parent, local);
        if (node.mesh) |m| {
            if (m >= self.doc.meshes.len) return error.InvalidMesh;
            for (self.doc.meshes[m].primitives, 0..) |p, primitive_index| {
                const selected = self.selector == null or (self.selector.?.node == index and @as(usize, self.selector.?.primitive) == primitive_index);
                if (selected) try self.primitive(p, world, node.skin);
            }
        }
        for (node.children) |child| try self.visit(child, world, depth + 1);
    }

    fn primitive(self: *Builder, p: Primitive, world: Mat, skin_index: ?u32) !void {
        if (p.mode != 4) return error.NonTrianglePrimitive;
        if (p.targets != null) return error.MorphTargetsUnsupported;
        const positions = try self.accessor(p.attributes.POSITION, "VEC3");
        const normals: ?View = if (p.attributes.NORMAL) |normal_accessor| try self.accessor(normal_accessor, "VEC3") else null;
        const uvs: ?View = if (p.attributes.TEXCOORD_0) |t| try self.accessor(t, "VEC2") else null;
        const skin_mats: ?[]const Mat = if (skin_index) |i| if (self.allow_skin_preview) try self.skinMatrices(i) else return error.SkinsUnsupported else null;
        const joints: ?View = if (p.attributes.JOINTS_0) |j| try self.accessor(j, "VEC4") else null;
        const weights: ?View = if (p.attributes.WEIGHTS_0) |w| try self.accessorAllowNormalized(w, "VEC4") else null;
        if ((normals != null and normals.?.count != positions.count) or (uvs != null and uvs.?.count != positions.count)) return error.AttributeCountMismatch;
        if (skin_mats != null and (joints == null or weights == null)) return error.MissingSkinAttributes;
        if ((joints != null and joints.?.count != positions.count) or (weights != null and weights.?.count != positions.count)) return error.AttributeCountMismatch;
        if (positions.component != 5126 or (normals != null and normals.?.component != 5126)) return error.UnsupportedComponentType;
        if (uvs) |u| if (u.component != 5126) return error.UnsupportedComponentType;
        if (skin_mats != null) {
            const weight_format_ok = (weights.?.component == 5126 and !weights.?.normalized) or ((weights.?.component == 5121 or weights.?.component == 5123) and weights.?.normalized);
            const joint_format_ok = joints.?.component == 5121 or joints.?.component == 5123;
            if (!weight_format_ok or !joint_format_ok) return error.UnsupportedSkinComponentType;
        }
        if (self.retain_rig) {
            if (skin_index) |skin_id| {
                if (self.rig_skin) |previous| {
                    if (previous != skin_id) return error.MultipleSkinsUnsupported;
                } else {
                    self.rig_skin = skin_id;
                    const skin = self.doc.skins[skin_id];
                    if (skin.joints.len == 0 or skin.joints.len > 128) return error.TooManyJoints;
                    for (skin.joints) |node_index| {
                        const match = mappedNodeJoint(self.doc, node_index);
                        // Rotate about the matched source joint, or the skin's first joint when no
                        // ancestor is named: the Ranger's own pivots are in its units and do not apply.
                        const pivot_node = if (match) |m| m.node else skin.joints[0];
                        const pivot_world = self.node_world[pivot_node];
                        try self.rig_bones.append(self.arena, .{ .ranger_joint = @intCast(@intFromEnum(if (match) |m| m.joint else GameSkeleton.Joint.root)), .pivot = .{ pivot_world[12], pivot_world[13], pivot_world[14] } });
                    }
                }
            }
        }

        const base: u32 = @intCast(self.vertices.items.len);
        const normal_matrix = normalMatrix(world);
        for (0..positions.count) |i| {
            var pos: [3]f32 = undefined;
            var n: [3]f32 = .{ 0, 1, 0 };
            if (skin_mats) |palette| {
                const source_pos = positions.vec(3, i);
                const source_n = if (normals) |view| view.vec(3, i) else [3]f32{ 0, 1, 0 };
                if (self.retain_rig) {
                    var bind_point: [3]f32 = .{ 0, 0, 0 };
                    var bind_normal: [3]f32 = .{ 0, 0, 0 };
                    const source_joints = joints.?.uint4(i);
                    const source_weights = weights.?.vec(4, i);
                    var influence: Model.SkinVertex = .{ .joints = .{ 0, 0, 0, 0 }, .weights = .{ 0, 0, 0, 0 } };
                    var weight_sum: f32 = 0;
                    for (0..4) |k| {
                        const weight = source_weights[k];
                        if (!std.math.isFinite(weight) or weight < 0) return error.InvalidSkinWeights;
                        if (weight == 0) continue;
                        if (source_joints[k] >= palette.len or source_joints[k] >= self.rig_bones.items.len) return error.InvalidJoint;
                        influence.joints[k] = @intCast(source_joints[k]);
                        influence.weights[k] = weight;
                        const bind_matrix = palette[source_joints[k]];
                        const transformed = transformPoint(bind_matrix, source_pos);
                        const transformed_normal = transformVector(normalMatrix(bind_matrix), source_n);
                        for (0..3) |axis| {
                            bind_point[axis] += transformed[axis] * weight;
                            bind_normal[axis] += transformed_normal[axis] * weight;
                        }
                        weight_sum += weight;
                    }
                    if (weight_sum < 1e-6) return error.InvalidSkinWeights;
                    for (&influence.weights) |*weight| weight.* /= weight_sum;
                    for (0..3) |axis| {
                        bind_point[axis] /= weight_sum;
                        bind_normal[axis] /= weight_sum;
                        self.rig_bounds_min[axis] = @min(self.rig_bounds_min[axis], bind_point[axis]);
                        self.rig_bounds_max[axis] = @max(self.rig_bounds_max[axis], bind_point[axis]);
                    }
                    // Freeze the original glTF bind pose into the model-space vertex stream.
                    // Runtime applies Ranger's bind-relative pose deltas to this geometry.
                    pos = bind_point;
                    n = normalize(bind_normal);
                    try self.rig_vertices.append(self.arena, influence);
                } else {
                const bone_indices = joints.?.uint4(i);
                const bone_weights = weights.?.vec(4, i);
                pos = .{ 0, 0, 0 };
                n = .{ 0, 0, 0 };
                var weight_sum: f32 = 0;
                for (0..4) |influence| {
                    const weight = bone_weights[influence];
                    if (!std.math.isFinite(weight) or weight < 0) return error.InvalidSkinWeights;
                    if (weight == 0) continue;
                    if (bone_indices[influence] >= palette.len) return error.InvalidJoint;
                    const matrix = palette[bone_indices[influence]];
                    const transformed_pos = transformPoint(matrix, source_pos);
                    const transformed_n = transformVector(normalMatrix(matrix), source_n);
                    for (0..3) |axis| {
                        pos[axis] += transformed_pos[axis] * weight;
                        n[axis] += transformed_n[axis] * weight;
                    }
                    weight_sum += weight;
                }
                if (weight_sum < 1e-6) return error.InvalidSkinWeights;
                for (0..3) |axis| {
                    pos[axis] /= weight_sum;
                    n[axis] /= weight_sum;
                }
                n = normalize(n);
                }
            } else {
                pos = transformPoint(world, positions.vec(3, i));
                n = if (normals) |view| normalize(transformVector(normal_matrix, view.vec(3, i))) else .{ 0, 1, 0 };
                if (self.retain_rig) {
                    self.has_static_rig_vertices = true;
                    for (0..3) |axis| {
                        self.rig_bounds_min[axis] = @min(self.rig_bounds_min[axis], pos[axis]);
                        self.rig_bounds_max[axis] = @max(self.rig_bounds_max[axis], pos[axis]);
                    }
                    try self.rig_vertices.append(self.arena, .{ .joints = .{ 255, 0, 0, 0 }, .weights = .{ 1, 0, 0, 0 } });
                }
            }
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
        if (normals == null) try self.generateNormals(base, first, count);
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

    fn skinMatrices(self: *Builder, skin_index: u32) ![]const Mat {
        if (skin_index >= self.doc.skins.len) return error.InvalidSkin;
        const skin = self.doc.skins[skin_index];
        if (skin.joints.len == 0 or skin.joints.len > 1024) return error.InvalidSkin;
        const palette = try self.arena.alloc(Mat, skin.joints.len);
        var inverse_binds: ?View = null;
        if (skin.inverseBindMatrices) |accessor_index| {
            inverse_binds = try self.accessor(accessor_index, "MAT4");
            if (inverse_binds.?.component != 5126 or inverse_binds.?.count != skin.joints.len) return error.InvalidInverseBindMatrices;
        }
        for (skin.joints, 0..) |node_index, joint_index| {
            if (node_index >= self.doc.nodes.len or !self.node_active[node_index]) return error.InvalidJoint;
            const inverse_bind = if (inverse_binds) |view| view.mat4(joint_index) else identity;
            // In mesh space glTF applies inverse(mesh-world) * joint-world * inverse-bind,
            // then the renderer's mesh-world transform. Those outer mesh transforms cancel.
            palette[joint_index] = mul(self.node_world[node_index], inverse_bind);
        }
        return palette;
    }

    fn generateNormals(self: *Builder, base: u32, first: u32, count: u32) !void {
        const vertex_count = self.vertices.items.len - base;
        const sums = try self.arena.alloc([3]f32, vertex_count);
        @memset(sums, .{ 0, 0, 0 });
        var triangle = first;
        while (triangle < first + count) : (triangle += 3) {
            const ia = self.indices.items[triangle];
            const ib = self.indices.items[triangle + 1];
            const ic = self.indices.items[triangle + 2];
            const a = self.vertices.items[ia].position;
            const b = self.vertices.items[ib].position;
            const c = self.vertices.items[ic].position;
            const face = cross(subtract(b, a), subtract(c, a));
            for (face) |value| if (!std.math.isFinite(value)) return error.NonFiniteValue;
            for ([3]u32{ ia, ib, ic }) |index| {
                const local: usize = @intCast(index - base);
                for (0..3) |axis| sums[local][axis] += face[axis];
            }
        }
        for (sums, 0..) |sum, i| {
            for (sum) |value| if (!std.math.isFinite(value)) return error.NonFiniteValue;
            self.vertices.items[@as(usize, base) + i].normal = normalize(sum);
        }
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
        return self.accessorWithNormalization(index, expected_type, false);
    }

    fn accessorAllowNormalized(self: *Builder, index: u32, expected_type: []const u8) !View {
        return self.accessorWithNormalization(index, expected_type, true);
    }

    fn accessorWithNormalization(self: *Builder, index: u32, expected_type: []const u8, allow_normalized: bool) !View {
        if (index >= self.doc.accessors.len) return error.InvalidAccessor;
        const a = self.doc.accessors[index];
        if (a.sparse != null) return error.SparseAccessorsUnsupported;
        if (a.normalized and !allow_normalized) return error.UnsupportedComponentType;
        if (a.normalized and a.componentType != 5121 and a.componentType != 5123) return error.UnsupportedComponentType;
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
        const components: usize = if (std.mem.eql(u8, expected_type, "SCALAR")) 1 else if (std.mem.eql(u8, expected_type, "VEC2")) 2 else if (std.mem.eql(u8, expected_type, "VEC4")) 4 else if (std.mem.eql(u8, expected_type, "MAT4")) 16 else 3;
        const element = component_size * components;
        const stride = bv.byteStride orelse element;
        if (stride < element) return error.InvalidStride;
        const buffer = self.buffers[bv.buffer];
        if (bv.byteOffset > buffer.len or buffer.len - bv.byteOffset < bv.byteLength) return error.BufferViewOutOfRange;
        const bytes = buffer[bv.byteOffset..][0..bv.byteLength];
        if (a.count > 0 and (a.byteOffset > bytes.len or (a.count - 1) * stride + element > bytes.len - a.byteOffset)) return error.AccessorOutOfRange;
        return .{ .bytes = bytes, .start = a.byteOffset, .stride = stride, .count = a.count, .component = a.componentType, .normalized = a.normalized };
    }
};

const View = struct {
    bytes: []const u8,
    start: usize,
    stride: usize,
    count: usize,
    component: u32,
    normalized: bool = false,

    fn offset(self: View, i: usize) usize {
        return self.start + i * self.stride;
    }

    fn vec(self: View, comptime n: usize, i: usize) [n]f32 {
        var result: [n]f32 = undefined;
        const component_size: usize = if (self.component == 5121) 1 else if (self.component == 5123) 2 else 4;
        const normalized_divisor: f32 = if (self.normalized) (if (self.component == 5121) 255 else 65535) else 1;
        for (&result, 0..) |*v, c| {
            const at = self.offset(i) + c * component_size;
            v.* = switch (self.component) {
                5121 => @as(f32, @floatFromInt(self.bytes[at])) / normalized_divisor,
                5123 => @as(f32, @floatFromInt(std.mem.readInt(u16, self.bytes[at..][0..2], .little))) / normalized_divisor,
                else => @bitCast(std.mem.readInt(u32, self.bytes[at..][0..4], .little)),
            };
        }
        return result;
    }

    fn mat4(self: View, i: usize) Mat {
        return self.vec(16, i);
    }

    fn uint4(self: View, i: usize) [4]u32 {
        var out: [4]u32 = undefined;
        const at = self.offset(i);
        for (&out, 0..) |*value, c| value.* = switch (self.component) {
            5121 => self.bytes[at + c],
            5123 => std.mem.readInt(u16, self.bytes[at + c * 2 ..][0..2], .little),
            else => unreachable,
        };
        return out;
    }
};

fn splitGlb(bytes: []const u8) !struct { json: []const u8, bin: ?[]const u8 } {
    if (std.mem.readInt(u32, bytes[4..8], .little) != 2) return error.UnsupportedGltfVersion;
    const total = std.mem.readInt(u32, bytes[8..12], .little);
    if (total < 12 or total != bytes.len) return error.InvalidGlbLength;
    var at: usize = 12;
    var json: ?[]const u8 = null;
    var bin: ?[]const u8 = null;
    var chunk_count: usize = 0;
    while (at < total) {
        if (total - at < 8) return error.Truncated;
        const len = std.mem.readInt(u32, bytes[at..][0..4], .little);
        const kind = std.mem.readInt(u32, bytes[at + 4 ..][0..4], .little);
        at += 8;
        if (len > total - at) return error.Truncated;
        if (len % 4 != 0) return error.InvalidChunkLength;
        if (chunk_count == 0 and kind != 0x4E4F534A) return error.InvalidChunkOrder;
        const chunk = bytes[at..][0..len];
        if (kind == 0x4E4F534A) {
            if (json != null) return error.DuplicateJsonChunk;
            json = chunk;
        } else if (kind == 0x004E4942) {
            if (bin != null) return error.DuplicateBinChunk;
            bin = chunk;
        }
        at += len;
        chunk_count += 1;
    }
    return .{ .json = json orelse return error.MissingJsonChunk, .bin = bin };
}

fn mappedJoint(name: []const u8) ?GameSkeleton.Joint {
    return humanoidJoint(name);
}

const MappedNode = struct { joint: GameSkeleton.Joint, node: u32 };

fn mappedNodeJoint(doc: Doc, node_index: u32) ?MappedNode {
    var current: ?u32 = node_index;
    var depth: usize = 0;
    while (current) |index| : (depth += 1) {
        if (depth > doc.nodes.len) return null;
        if (mappedJoint(doc.nodes[index].name orelse "")) |joint| return .{ .joint = joint, .node = index };
        var parent: ?u32 = null;
        for (doc.nodes, 0..) |candidate, candidate_index| {
            for (candidate.children) |child| if (child == index) {
                parent = @intCast(candidate_index);
                break;
            };
            if (parent != null) break;
        }
        current = parent;
    }
    return null;
}

fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
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

fn subtract(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
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

test "rigged GLB bakes bind geometry and retains mapped influences" {
    const allocator = std.testing.allocator;
    const source = try minimalSkinnedGltf(allocator);
    defer allocator.free(source);
    var model = try compileRigged(allocator, source, .{});
    defer model.deinit(allocator);
    const skin = model.skin orelse return error.TestExpectedSkin;
    try std.testing.expectEqual(model.mesh.vertices.len, skin.vertices.len);
    try std.testing.expectEqual(@as(usize, 1), skin.bones.len);
    try std.testing.expectEqual(@as(u8, @intCast(@intFromEnum(GameSkeleton.Joint.upper_arm_l))), skin.bones[0].ranger_joint);
    var weighted: usize = 0;
    for (skin.vertices) |influence| {
        var sum: f32 = 0;
        for (influence.weights) |weight| sum += weight;
        if (sum > 0.99) weighted += 1;
    }
    try std.testing.expectEqual(model.mesh.vertices.len, weighted);
}

test "rigged GLB accepts normalized byte skin weights" {
    const allocator = std.testing.allocator;
    const source = try minimalSkinnedGltfWithPackedWeights(allocator, true);
    defer allocator.free(source);
    var model = try compileRigged(allocator, source, .{});
    defer model.deinit(allocator);
    for (model.skin.?.vertices) |influence| {
        try std.testing.expectApproxEqAbs(@as(f32, 1), influence.weights[0], 1e-6);
        try std.testing.expectEqual(@as(f32, 0), influence.weights[1]);
    }
}

test "rigged GLB assigns static mesh pieces to a root influence" {
    const allocator = std.testing.allocator;
    const source = try minimalSkinnedGltf(allocator);
    defer allocator.free(source);
    const scene = try std.mem.replaceOwned(u8, allocator, source, "\"nodes\":[0,1]", "\"nodes\":[0,2,1]");
    defer allocator.free(scene);
    const mixed = try std.mem.replaceOwned(u8, allocator, scene, "\"nodes\":[{\"name\":\"LeftArm\"},{\"mesh\":0,\"skin\":0}]", "\"nodes\":[{\"name\":\"LeftArm\"},{\"mesh\":0,\"skin\":0},{\"mesh\":0,\"translation\":[0,0,2]}]");
    defer allocator.free(mixed);
    var model = try compileRigged(allocator, mixed, .{});
    defer model.deinit(allocator);
    const skin = model.skin orelse return error.TestExpectedSkin;
    try std.testing.expectEqual(@as(usize, 2), skin.bones.len);
    try std.testing.expectEqual(@as(u8, 1), skin.vertices[0].joints[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 2), model.mesh.vertices[0].position[2], 1e-6);
    try std.testing.expectEqual(@as(f32, 1), skin.vertices[0].weights[0]);
}

test "bundled humanoid GLB imports through the retained rig path" {
    const allocator = std.testing.allocator;
    var model = try compileRigged(allocator, @embedFile("rigged_character.glb"), .{});
    defer model.deinit(allocator);
    const skin = model.skin orelse return error.TestExpectedSkin;
    try std.testing.expectEqual(model.mesh.vertices.len, skin.vertices.len);
    try std.testing.expect(skin.bones.len > 1);
    try std.testing.expect(skin.bones.len <= RangerPaletteLimit);
}

const RangerPaletteLimit = 128;

fn minimalSkinnedGltf(allocator: std.mem.Allocator) ![]u8 {
    return minimalSkinnedGltfWithPackedWeights(allocator, false);
}

fn minimalSkinnedGltfWithPackedWeights(allocator: std.mem.Allocator, packed_weights: bool) ![]u8 {
    var bytes: [138]u8 = @splat(0);
    const positions = [_]f32{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    const normals = [_]f32{ 0, 0, 1, 0, 0, 1, 0, 0, 1 };
    for (positions, 0..) |v, i| std.mem.writeInt(u32, bytes[i * 4 ..][0..4], @bitCast(v), .little);
    for (normals, 0..) |v, i| std.mem.writeInt(u32, bytes[36 + i * 4 ..][0..4], @bitCast(v), .little);
    for (0..3) |i| {
        bytes[72 + i * 4] = 0;
        std.mem.writeInt(u32, bytes[84 + i * 16 ..][0..4], @bitCast(@as(f32, 1)), .little);
    }
    if (packed_weights) {
        @memset(bytes[84..96], 0);
        for (0..3) |i| bytes[84 + i * 4] = 255;
    }
    for (0..3) |i| std.mem.writeInt(u16, bytes[132 + i * 2 ..][0..2], @intCast(i), .little);

    const encoder = std.base64.standard.Encoder;
    var encoded: [encoder.calcSize(bytes.len)]u8 = undefined;
    _ = encoder.encode(&encoded, &bytes);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.print(
        \\{{"asset":{{"version":"2.0"}},"scene":0,"scenes":[{{"nodes":[0,1]}}],
        \\"nodes":[{{"name":"LeftArm"}},{{"mesh":0,"skin":0}}],"skins":[{{"joints":[0]}}],
        \\"meshes":[{{"primitives":[{{"attributes":{{"POSITION":0,"NORMAL":1,"JOINTS_0":2,"WEIGHTS_0":3}},"indices":4}}]}}],
        \\"accessors":[{{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}},
        \\{{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"}},
        \\{{"bufferView":2,"componentType":5121,"count":3,"type":"VEC4"}},
        \\{{"bufferView":3,"componentType":{d},{s}"count":3,"type":"VEC4"}},
        \\{{"bufferView":4,"componentType":5123,"count":3,"type":"SCALAR"}}],
        \\"bufferViews":[{{"buffer":0,"byteOffset":0,"byteLength":36}},{{"buffer":0,"byteOffset":36,"byteLength":36}},
        \\{{"buffer":0,"byteOffset":72,"byteLength":12}},{{"buffer":0,"byteOffset":84,"byteLength":{d}}},{{"buffer":0,"byteOffset":132,"byteLength":6}}],
        \\"buffers":[{{"byteLength":138,"uri":"data:application/octet-stream;base64,{s}"}}]}}
    , .{ if (packed_weights) @as(u32, 5121) else 5126, if (packed_weights) "\"normalized\":true," else "", if (packed_weights) @as(u32, 12) else 48, encoded });
    return out.toOwnedSlice();
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

test "humanoid joint names map across Mixamo, VRoid, Rigify, Unreal and Biped rigs" {
    const J = GameSkeleton.Joint;
    const cases = [_]struct { []const u8, ?J }{
        .{ "mixamorig:Hips", .hips },          .{ "mixamorig1:Spine", .spine },           .{ "mixamorig:Spine1", .spine },
        .{ "mixamorig:Spine2", .chest },       .{ "mixamorig:Neck", .neck },              .{ "mixamorig:Head", .head },
        .{ "mixamorig:LeftShoulder", .shoulder_l }, .{ "mixamorig:LeftArm", .upper_arm_l }, .{ "mixamorig:LeftForeArm", .lower_arm_l },
        .{ "mixamorig:LeftHand", .hand_l },    .{ "mixamorig:LeftHandIndex1", null },     .{ "mixamorig:RightUpLeg", .thigh_r },
        .{ "mixamorig:RightLeg", .shin_r },    .{ "mixamorig:RightFoot", .foot_r },       .{ "mixamorig:RightToeBase", .toe_r },
        .{ "J_Bip_C_Hips", .hips },            .{ "J_Bip_C_UpperChest", .chest },         .{ "J_Bip_L_UpperArm", .upper_arm_l },
        .{ "J_Bip_L_LowerArm", .lower_arm_l }, .{ "J_Bip_R_UpperLeg", .thigh_r },         .{ "J_Bip_R_LowerLeg", .shin_r },
        .{ "DEF-upper_arm.L", .upper_arm_l },  .{ "DEF-forearm.L", .lower_arm_l },        .{ "DEF-thigh.R", .thigh_r },
        .{ "DEF-shin.R", .shin_r },            .{ "DEF-spine.003", .chest },              .{ "DEF-spine.001", .spine },
        .{ "pelvis", .hips },                  .{ "spine_01", .spine },                   .{ "spine_03", .chest },
        .{ "clavicle_l", .shoulder_l },        .{ "upperarm_l", .upper_arm_l },           .{ "lowerarm_l", .lower_arm_l },
        .{ "upperarm_twist_01_l", null },      .{ "calf_r", .shin_r },                    .{ "ball_r", .toe_r },
        .{ "Bip01 L Thigh", .thigh_l },        .{ "Bip01 R Forearm", .lower_arm_r },      .{ "HeadTop_End", null },
        .{ "Armature", null },
    };
    for (cases) |case| {
        const got = humanoidJoint(case[0]);
        if (got != case[1]) {
            std.debug.print("{s}: expected {any}, got {any}\n", .{ case[0], case[1], got });
            return error.TestUnexpectedResult;
        }
    }
}
