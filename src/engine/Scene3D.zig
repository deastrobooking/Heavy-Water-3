//! Immediate 3D draw helpers over the existing catalog and world-prop renderer.
//! Callers own the output slice and reset the builder for each published frame.
const std = @import("std");
const Catalog = @import("../asset/Catalog.zig");
const Transform = @import("../world/Transform.zig");
const World = @import("../world/World.zig");
const Rotation = @import("../physics/Rotation.zig");

pub const Error = error{
    InvalidHandle,
    AssetNotReady,
    CapacityExceeded,
    InvalidTransform,
    InvalidTint,
};

pub const Options = struct {
    tint: [4]f32 = .{ 1, 1, 1, 1 },
    /// Per-axis size multiplier, applied before rotation.
    size: [3]f32 = .{ 1, 1, 1 },
    rotation: [4]f32 = Rotation.identity,
    lod: Catalog.MeshHandle = .none,
    lod_distance: f32 = 0,
};

/// A caller-owned, allocation-free command builder. `props` can be the frame's complete output
/// slice or a suffix of a larger prop list; `count` is the number appended by this builder.
pub const Frame = struct {
    catalog: *const Catalog,
    props: []World.Prop,
    count: usize = 0,

    pub fn init(catalog: *const Catalog, props: []World.Prop) Frame {
        return .{ .catalog = catalog, .props = props };
    }

    /// Appends one catalog model. Handles and all option values are checked before the output
    /// slice is changed, so a failed call leaves both `count` and the destination untouched.
    pub fn drawModel(self: *Frame, mesh: Catalog.MeshHandle, transform: Transform, options: Options) Error!void {
        try self.validateAsset(mesh);
        if (!options.lod.eql(.none)) try self.validateAsset(options.lod);
        if (!validTransform(transform, options)) return error.InvalidTransform;
        for (options.tint) |channel| if (!std.math.isFinite(channel)) return error.InvalidTint;
        if (self.count == self.props.len) return error.CapacityExceeded;

        self.props[self.count] = .{
            .mesh = mesh,
            .transform = transform,
            .tint = options.tint,
            .size = options.size,
            .rotation = options.rotation,
            .lod = options.lod,
            .lod_distance = if (options.lod.eql(.none)) 0 else options.lod_distance,
        };
        self.count += 1;
    }

    /// Draws the catalog's centered unit cube with `size` as full world-space dimensions.
    pub fn drawBox(self: *Frame, center: [3]f32, size: [3]f32, tint: [4]f32) Error!void {
        try self.drawModel(self.catalog.content.block, .{ .position = center }, .{ .tint = tint, .size = size });
    }

    /// Draws the catalog's centered unit sphere. `radius` is in world metres.
    pub fn drawSphere(self: *Frame, center: [3]f32, radius: f32, tint: [4]f32) Error!void {
        if (!std.math.isFinite(radius) or radius <= 0) return error.InvalidTransform;
        try self.drawModel(self.catalog.content.orb, .{ .position = center, .scale = radius * 2 }, .{ .tint = tint });
    }

    fn validateAsset(self: *const Frame, handle: Catalog.MeshHandle) Error!void {
        const entry = self.catalog.mesh(handle) orelse return error.InvalidHandle;
        if (!entry.ready) return error.AssetNotReady;
    }
};

fn validTransform(transform: Transform, options: Options) bool {
    if (!std.math.isFinite(transform.scale) or transform.scale <= 0) return false;
    for (transform.position) |v| if (!std.math.isFinite(v)) return false;
    for (options.size) |v| if (!std.math.isFinite(v) or v <= 0) return false;
    if (!std.math.isFinite(options.lod_distance)) return false;
    if (!options.lod.eql(.none) and options.lod_distance <= 0) return false;
    var norm_squared: f32 = 0;
    for (options.rotation) |v| {
        if (!std.math.isFinite(v)) return false;
        norm_squared += v * v;
    }
    return @abs(norm_squared - 1) <= 0.01;
}

fn fixtureCatalog(allocator: std.mem.Allocator, catalog: *Catalog) !void {
    catalog.* = .{};
    const block = try catalog.register(allocator, try @import("../asset/Model.zig").fromMesh(allocator, try @import("../render/Mesh.zig").block(allocator), .named("test block", .{ 1, 1, 1, 1 })));
    const orb = try catalog.register(allocator, try @import("../asset/Model.zig").fromMesh(allocator, try @import("../render/Mesh.zig").orb(allocator), .named("test sphere", .{ 1, 1, 1, 1 })));
    catalog.content.block = block;
    catalog.content.orb = orb;
}

test "immediate 3D helpers preserve order, transforms, tint, primitives, and LOD" {
    var catalog: Catalog = undefined;
    try fixtureCatalog(std.testing.allocator, &catalog);
    defer catalog.deinit(std.testing.allocator);

    var props: [4]World.Prop = undefined;
    var frame = Frame.init(&catalog, &props);
    const model = catalog.content.block;
    const lod = catalog.content.orb;
    const transform: Transform = .{ .position = .{ 4, 5, 6 }, .scale = 2 };
    const tint: [4]f32 = .{ 0.2, 0.4, 0.8, 1 };
    const rotation = Rotation.axisAngle(.{ 0, 1, 0 }, 0.5);
    try frame.drawModel(model, transform, .{ .tint = tint, .size = .{ 2, 3, 4 }, .rotation = rotation, .lod = lod, .lod_distance = 90 });
    try frame.drawBox(.{ 10, 2, -3 }, .{ 2, 4, 6 }, tint);
    try frame.drawSphere(.{ -2, 1, 7 }, 1.5, tint);

    try std.testing.expectEqual(@as(usize, 3), frame.count);
    try std.testing.expect(props[0].mesh.eql(model));
    try std.testing.expect(std.meta.eql(transform, props[0].transform));
    try std.testing.expectEqual(tint, props[0].tint);
    try std.testing.expectEqual([3]f32{ 2, 3, 4 }, props[0].size);
    try std.testing.expectEqual(rotation, props[0].rotation);
    try std.testing.expect(props[0].lod.eql(lod));
    try std.testing.expectEqual(@as(f32, 90), props[0].lod_distance);
    try std.testing.expect(props[1].mesh.eql(catalog.content.block));
    try std.testing.expectEqual([3]f32{ 2, 4, 6 }, props[1].size);
    try std.testing.expect(props[2].mesh.eql(catalog.content.orb));
    try std.testing.expectEqual(@as(f32, 3), props[2].transform.scale);
    try std.testing.expectEqual([3]f32{ -2, 1, 7 }, props[2].transform.position);
}

test "3D helper rejects invalid, stale, pending, and full submissions without mutation" {
    var catalog: Catalog = undefined;
    try fixtureCatalog(std.testing.allocator, &catalog);
    defer catalog.deinit(std.testing.allocator);
    const pending = try catalog.reserve();
    const stale = try catalog.reserve();
    try std.testing.expect(catalog.meshes.remove(stale));

    const marker: World.Prop = .{ .mesh = catalog.content.block, .transform = .{}, .tint = .{ 0.5, 0.5, 0.5, 1 } };
    var props = [_]World.Prop{marker};
    var frame = Frame.init(&catalog, &props);
    try std.testing.expectError(error.InvalidHandle, frame.drawModel(stale, .{}, .{}));
    try std.testing.expectError(error.AssetNotReady, frame.drawModel(pending, .{}, .{}));
    try std.testing.expectError(error.InvalidHandle, frame.drawModel(catalog.content.block, .{}, .{ .lod = stale, .lod_distance = 20 }));
    try std.testing.expectError(error.InvalidTransform, frame.drawModel(catalog.content.block, .{}, .{ .lod = catalog.content.orb }));
    try std.testing.expectError(error.InvalidTint, frame.drawModel(catalog.content.block, .{}, .{ .tint = .{ 1, std.math.nan(f32), 1, 1 } }));
    try std.testing.expectEqual(@as(usize, 0), frame.count);
    try std.testing.expect(std.meta.eql(marker, props[0]));

    try frame.drawBox(.{ 0, 0, 0 }, .{ 1, 1, 1 }, .{ 1, 1, 1, 1 });
    const appended_box = props[0];
    try std.testing.expectError(error.CapacityExceeded, frame.drawSphere(.{ 0, 0, 0 }, 1, .{ 1, 1, 1, 1 }));
    try std.testing.expectEqual(@as(usize, 1), frame.count);
    try std.testing.expect(std.meta.eql(appended_box, props[0]));
}

test "sphere helper rejects a nonpositive radius without appending" {
    var catalog: Catalog = undefined;
    try fixtureCatalog(std.testing.allocator, &catalog);
    defer catalog.deinit(std.testing.allocator);
    var props: [1]World.Prop = undefined;
    var frame = Frame.init(&catalog, &props);
    try std.testing.expectError(error.InvalidTransform, frame.drawSphere(.{ 0, 0, 0 }, 0, .{ 1, 1, 1, 1 }));
    try std.testing.expectEqual(@as(usize, 0), frame.count);
}
