//! Editable, source-linked appearance and shape modifiers for imported character meshes.
//! Disconnected triangle islands are the first safe editing boundary; glTF names and skin
//! weights refine the suggested labels, while every generated label remains author-editable.
const std = @import("std");
const Model = @import("Model.zig");
const Modifiers = @This();

pub const legacy_format_version: u32 = 1;
pub const format_version: u32 = 2;
pub const default_weld_cell: f32 = 0.0001;
pub const CharacterType = enum { captain, ranger, synthetic };
pub const Surface = enum { armor, skin, eyes, energy, neutral };
pub const Part = struct {
    /// Smallest source vertex index in this connected mesh island. Stable for unchanged source.
    id: u32,
    label: []const u8,
    surface: Surface = .armor,
    enabled: bool = true,
    center: [3]f32,
    vertex_count: u32,
    scale: [3]f32 = .{ 1, 1, 1 },
    offset: [3]f32 = .{ 0, 0, 0 },
    color: ?[3]f32 = null,
};
pub const Document = struct {
    format: u32 = format_version,
    /// Absent on v1 documents, which retain vertex-index-only island analysis.
    weld_cell: ?f32 = null,
    character_type: CharacterType = .captain,
    source_hash: []const u8,
    overall_scale: f32 = 1,
    skin_color: [3]f32 = .{ 0.78, 0.53, 0.39 },
    eye_color: [3]f32 = .{ 0.16, 0.78, 0.96 },
    armor_color: [3]f32 = .{ 0.22, 0.54, 0.68 },
    energy_color: [3]f32 = .{ 0.25, 0.9, 1 },
    parts: []Part,
};
pub const Palette = enum { skin, eyes, armor, energy };
pub const Edit = union(enum) {
    label: struct { id: u32, value: []const u8 },
    surface: struct { id: u32, value: Surface },
    color: struct { id: u32, value: ?[3]f32 },
    scale: struct { id: u32, value: [3]f32 },
    offset: struct { id: u32, value: [3]f32 },
    palette: struct { slot: Palette, value: [3]f32 },
    enabled: struct { id: u32, value: bool },
};
pub const Command = union(enum) {
    surface: struct { id: u32, before: Surface, after: Surface },
    color: struct { id: u32, before: ?[3]f32, after: ?[3]f32 },
    enabled: struct { id: u32, before: bool, after: bool },
    scale: struct { id: u32, before: [3]f32, after: [3]f32 },
    offset: struct { id: u32, before: [3]f32, after: [3]f32 },
    palette: struct { slot: Palette, before: [3]f32, after: [3]f32 },

    pub fn apply(self: Command, allocator: std.mem.Allocator, doc: *Document, direction: enum { before, after }) !void {
        switch (self) {
            .surface => |c| try edit(allocator, doc, .{ .surface = .{ .id = c.id, .value = if (direction == .before) c.before else c.after } }),
            .color => |c| try edit(allocator, doc, .{ .color = .{ .id = c.id, .value = if (direction == .before) c.before else c.after } }),
            .enabled => |c| try edit(allocator, doc, .{ .enabled = .{ .id = c.id, .value = if (direction == .before) c.before else c.after } }),
            .scale => |c| try edit(allocator, doc, .{ .scale = .{ .id = c.id, .value = if (direction == .before) c.before else c.after } }),
            .offset => |c| try edit(allocator, doc, .{ .offset = .{ .id = c.id, .value = if (direction == .before) c.before else c.after } }),
            .palette => |c| try edit(allocator, doc, .{ .palette = .{ .slot = c.slot, .value = if (direction == .before) c.before else c.after } }),
        }
    }

    fn coalesce(self: *Command, next: Command) bool {
        switch (self.*) {
            .scale => |*a| switch (next) { .scale => |b| if (a.id == b.id) { a.after = b.after; return true; }, else => {} },
            .offset => |*a| switch (next) { .offset => |b| if (a.id == b.id) { a.after = b.after; return true; }, else => {} },
            else => {},
        }
        return false;
    }
};

/// Fixed-capacity undo history. Pushing after undo discards the redo tail.
pub fn History(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        items: [capacity]Command = undefined,
        len: usize = 0,
        cursor: usize = 0,

        pub fn push(self: *Self, command: Command) void {
            self.len = self.cursor;
            if (self.cursor > 0 and self.items[self.cursor - 1].coalesce(command)) return;
            if (self.len == capacity) {
                if (capacity == 0) return;
                std.mem.copyForwards(Command, self.items[0 .. capacity - 1], self.items[1..capacity]);
                self.len -= 1;
                self.cursor -= 1;
            }
            if (capacity == 0) return;
            self.items[self.len] = command;
            self.len += 1;
            self.cursor = self.len;
        }

        /// Apply before recording so invalid commands leave both the document and history intact.
        pub fn applyAndPush(self: *Self, allocator: std.mem.Allocator, doc: *Document, command: Command) !void {
            try command.apply(allocator, doc, .after);
            self.push(command);
        }

        pub fn undo(self: *Self) ?Command {
            if (self.cursor == 0) return null;
            self.cursor -= 1;
            return self.items[self.cursor];
        }

        pub fn redo(self: *Self) ?Command {
            if (self.cursor >= self.len) return null;
            const command = self.items[self.cursor];
            self.cursor += 1;
            return command;
        }
    };
}
pub const Component = struct { id: u32, count: u32, center: [3]f32, min: [3]f32, max: [3]f32 };
pub const Analysis = struct {
    /// For each vertex, the `id` of its disconnected component.
    vertex_parts: []u32,
    components: []Component,
};
const PartSlot = struct { id: u32, index: usize };
pub const PartSlots = struct {
    items: []PartSlot,

    fn init(allocator: std.mem.Allocator, parts: []const Part) !PartSlots {
        const items = try allocator.alloc(PartSlot, parts.len);
        errdefer allocator.free(items);
        for (parts, 0..) |part, i| items[i] = .{ .id = part.id, .index = i };
        // Insertion sort is efficient for the small sidecar lists and avoids depending on
        // different std sort APIs across the shipping and migration compilers.
        for (1..items.len) |i| {
            const item = items[i];
            var at = i;
            while (at > 0 and items[at - 1].id > item.id) : (at -= 1) items[at] = items[at - 1];
            items[at] = item;
        }
        return .{ .items = items };
    }

    fn deinit(self: PartSlots, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
    }

    pub fn indexOf(self: PartSlots, id: u32) ?usize {
        var lo: usize = 0;
        var hi = self.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.items[mid].id == id) return self.items[mid].index;
            if (self.items[mid].id < id) lo = mid + 1 else hi = mid;
        }
        return null;
    }
};
pub const PartVertices = struct {
    offsets: []u32,
    vertices: []u32,

    pub fn build(allocator: std.mem.Allocator, slot_of_vertex: []const u32, part_count: usize) !PartVertices {
        const offsets = try allocator.alloc(u32, part_count + 1);
        errdefer allocator.free(offsets);
        @memset(offsets, 0);
        for (slot_of_vertex) |slot| {
            if (slot >= part_count) return error.ComponentSetChanged;
            offsets[slot + 1] += 1;
        }
        for (0..part_count) |i| offsets[i + 1] += offsets[i];
        const vertices = try allocator.alloc(u32, slot_of_vertex.len);
        errdefer allocator.free(vertices);
        const cursor = try allocator.dupe(u32, offsets[0..part_count]);
        defer allocator.free(cursor);
        for (slot_of_vertex, 0..) |slot, vertex| {
            vertices[cursor[slot]] = @intCast(vertex);
            cursor[slot] += 1;
        }
        return .{ .offsets = offsets, .vertices = vertices };
    }

    pub fn deinit(self: PartVertices, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.offsets);
    }

    pub fn of(self: PartVertices, slot: usize) []const u32 {
        return self.vertices[self.offsets[slot]..self.offsets[slot + 1]];
    }
};

/// Per-part offsets to the first index of each source triangle.
pub const PartTriangles = struct {
    offsets: []u32,
    triangles: []u32,

    pub fn build(allocator: std.mem.Allocator, model: Model, analysis: Analysis, slots: PartSlots, part_count: usize) !PartTriangles {
        if (model.mesh.indices.len % 3 != 0) return error.InvalidModifiers;
        const offsets = try allocator.alloc(u32, part_count + 1);
        errdefer allocator.free(offsets);
        @memset(offsets, 0);
        var triangle: usize = 0;
        while (triangle < model.mesh.indices.len) : (triangle += 3) {
            const vertex = model.mesh.indices[triangle];
            if (vertex >= analysis.vertex_parts.len) return error.InvalidModifiers;
            const slot = slots.indexOf(analysis.vertex_parts[vertex]) orelse return error.ComponentSetChanged;
            offsets[slot + 1] += 1;
        }
        for (0..part_count) |i| offsets[i + 1] += offsets[i];
        const triangles = try allocator.alloc(u32, model.mesh.indices.len / 3);
        errdefer allocator.free(triangles);
        const cursor = try allocator.dupe(u32, offsets[0..part_count]);
        defer allocator.free(cursor);
        triangle = 0;
        while (triangle < model.mesh.indices.len) : (triangle += 3) {
            const vertex = model.mesh.indices[triangle];
            const slot = slots.indexOf(analysis.vertex_parts[vertex]).?;
            triangles[cursor[slot]] = @intCast(triangle);
            cursor[slot] += 1;
        }
        return .{ .offsets = offsets, .triangles = triangles };
    }

    pub fn deinit(self: PartTriangles, allocator: std.mem.Allocator) void {
        allocator.free(self.triangles);
        allocator.free(self.offsets);
    }

    pub fn of(self: PartTriangles, slot: usize) []const u32 {
        return self.triangles[self.offsets[slot]..self.offsets[slot + 1]];
    }
};
/// Cached appearance bake for the in-game editor. Source geometry and the two lookup tables are
/// built once; a normal edit only visits one part's vertices and triangles.
pub const Bake = struct {
    pristine: Model,
    analysis: Analysis,
    slots: PartSlots,
    vertices: PartVertices,
    triangles: PartTriangles,
    /// Vertices painted by hand in the vertex editor keep the base model's colour instead of
    /// their part colour. Owned by the editor; null when nothing is painted.
    painted: ?*const std.DynamicBitSetUnmanaged = null,

    pub fn init(allocator: std.mem.Allocator, source: Model, doc: Document) !Bake {
        if (!validDocument(doc)) return error.InvalidModifiers;
        const analysis = try analyzeWithWeldCell(allocator, source, doc.weld_cell);
        errdefer {
            allocator.free(analysis.vertex_parts);
            allocator.free(analysis.components);
        }
        if (doc.parts.len != analysis.components.len) return error.ComponentSetChanged;
        const slots = try PartSlots.init(allocator, doc.parts);
        errdefer slots.deinit(allocator);
        for (analysis.components) |component| if (slots.indexOf(component.id) == null) return error.ComponentSetChanged;
        for (doc.parts) |part| {
            if (!validScale(part.scale) or !validOffset(part.offset)) return error.InvalidPartTransform;
            if (part.color) |color| if (!validColor(color)) return error.InvalidPartColor;
        }
        const slot_of_vertex = try allocator.alloc(u32, analysis.vertex_parts.len);
        defer allocator.free(slot_of_vertex);
        for (analysis.vertex_parts, slot_of_vertex) |id, *slot| slot.* = @intCast(slots.indexOf(id) orelse return error.ComponentSetChanged);
        const vertices = try PartVertices.build(allocator, slot_of_vertex, doc.parts.len);
        errdefer vertices.deinit(allocator);
        const triangles = try PartTriangles.build(allocator, source, analysis, slots, doc.parts.len);
        errdefer triangles.deinit(allocator);
        const pristine = try Model.clone(allocator, source);
        errdefer pristine.deinit(allocator);
        return .{ .pristine = pristine, .analysis = analysis, .slots = slots, .vertices = vertices, .triangles = triangles };
    }

    pub fn deinit(self: Bake, allocator: std.mem.Allocator) void {
        self.pristine.deinit(allocator);
        allocator.free(self.analysis.vertex_parts);
        allocator.free(self.analysis.components);
        self.slots.deinit(allocator);
        self.vertices.deinit(allocator);
        self.triangles.deinit(allocator);
    }

    pub fn applyAll(self: *const Bake, model: *Model, doc: Document) !void {
        if (model.mesh.vertices.len != self.pristine.mesh.vertices.len or model.mesh.indices.len != self.pristine.mesh.indices.len) return error.ComponentSetChanged;
        @memcpy(model.mesh.vertices, self.pristine.mesh.vertices);
        @memcpy(model.mesh.indices, self.pristine.mesh.indices);
        for (doc.parts) |part| try self.updatePart(model, doc, part.id);
    }

    pub fn updatePart(self: *const Bake, model: *Model, doc: Document, id: u32) !void {
        if (model.mesh.vertices.len != self.pristine.mesh.vertices.len or model.mesh.indices.len != self.pristine.mesh.indices.len) return error.ComponentSetChanged;
        const slot = self.slots.indexOf(id) orelse return error.ComponentSetChanged;
        const part = doc.parts[slot];
        if (part.id != id) return error.ComponentSetChanged;
        if (!validScale(part.scale) or !validOffset(part.offset)) return error.InvalidPartTransform;
        if (part.color) |color| if (!validColor(color)) return error.InvalidPartColor;
        for (self.vertices.of(slot)) |vertex_index| {
            const vertex = &model.mesh.vertices[vertex_index];
            const hand_painted = if (self.painted) |p| vertex_index < p.bit_length and p.isSet(vertex_index) else false;
            vertex.color = if (hand_painted) self.pristine.mesh.vertices[vertex_index].color else partColor(doc, part);
        }
        for (self.triangles.of(slot)) |offset_u32| {
            const offset: usize = offset_u32;
            if (part.enabled) {
                @memcpy(model.mesh.indices[offset .. offset + 3], self.pristine.mesh.indices[offset .. offset + 3]);
            } else {
                const repeated = self.pristine.mesh.indices[offset];
                @memset(model.mesh.indices[offset .. offset + 3], repeated);
            }
        }
        model.revision +%= 1;
    }
};
pub const Error = error{ InvalidModifiers, SourceChanged, ComponentSetChanged, InvalidPartTransform, InvalidPartColor, OutOfMemory };

/// Apply one authoring command only after validating it, so a rejected edit leaves the document
/// untouched. Part IDs are stable source vertex IDs, not list positions.
pub fn edit(allocator: std.mem.Allocator, doc: *Document, command: Edit) !void {
    switch (command) {
        .palette => |change| {
            if (!validColor(change.value)) return error.InvalidPartColor;
            switch (change.slot) {
                .skin => doc.skin_color = change.value,
                .eyes => doc.eye_color = change.value,
                .armor => doc.armor_color = change.value,
                .energy => doc.energy_color = change.value,
            }
        },
        .label => |change| {
            const index = partIndex(doc.parts, change.id) orelse return error.ComponentSetChanged;
            if (change.value.len == 0 or change.value.len > 80) return error.InvalidModifiers;
            for (change.value) |character| if (character < 0x20) return error.InvalidModifiers;
            const label = try allocator.dupe(u8, change.value);
            doc.parts[index].label = label;
        },
        .surface => |change| {
            const index = partIndex(doc.parts, change.id) orelse return error.ComponentSetChanged;
            doc.parts[index].surface = change.value;
        },
        .color => |change| {
            const index = partIndex(doc.parts, change.id) orelse return error.ComponentSetChanged;
            if (change.value) |color| if (!validColor(color)) return error.InvalidPartColor;
            doc.parts[index].color = change.value;
        },
        .scale => |change| {
            const index = partIndex(doc.parts, change.id) orelse return error.ComponentSetChanged;
            if (!validScale(change.value)) return error.InvalidPartTransform;
            doc.parts[index].scale = change.value;
        },
        .offset => |change| {
            const index = partIndex(doc.parts, change.id) orelse return error.ComponentSetChanged;
            if (!validOffset(change.value)) return error.InvalidPartTransform;
            doc.parts[index].offset = change.value;
        },
        .enabled => |change| {
            const index = partIndex(doc.parts, change.id) orelse return error.ComponentSetChanged;
            doc.parts[index].enabled = change.value;
        },
    }
}

fn partIndex(parts: []const Part, id: u32) ?usize {
    for (parts, 0..) |part, index| if (part.id == id) return index;
    return null;
}

pub fn analyze(allocator: std.mem.Allocator, model: Model) !Analysis {
    return analyzeWithWeldCell(allocator, model, null);
}

pub fn analyzeWithWeldCell(allocator: std.mem.Allocator, model: Model, weld_cell: ?f32) !Analysis {
    const count = model.mesh.vertices.len;
    if (count == 0) return error.InvalidModifiers;
    if (weld_cell) |cell| if (!std.math.isFinite(cell) or cell <= 0) return error.InvalidModifiers;
    const parents = try allocator.alloc(u32, count);
    defer allocator.free(parents);
    for (parents, 0..) |*p, i| p.* = @intCast(i);
    if (weld_cell) |cell| {
        var first_at: std.AutoHashMapUnmanaged([3]i32, u32) = .empty;
        defer first_at.deinit(allocator);
        for (model.mesh.vertices, 0..) |vertex, i| {
            const key = try quantize(vertex.position, cell);
            const entry = try first_at.getOrPut(allocator, key);
            if (entry.found_existing) merge(parents, entry.value_ptr.*, @intCast(i)) else entry.value_ptr.* = @intCast(i);
        }
    }
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
    const analysis = try analyzeWithWeldCell(allocator, model, default_weld_cell);
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
    return .{ .format = format_version, .weld_cell = default_weld_cell, .source_hash = try allocator.dupe(u8, source_hash), .parts = parts };
}

pub fn deinit(allocator: std.mem.Allocator, doc: Document) void {
    for (doc.parts) |part| allocator.free(part.label);
    allocator.free(doc.parts);
    allocator.free(doc.source_hash);
}

/// Applies label-selected palette colors and component transforms to a static preview/runtime
/// model. The model stays source geometry; the sidecar remains the editable source of truth.
pub fn apply(allocator: std.mem.Allocator, model: *Model, doc: Document, expected_hash: []const u8) !Analysis {
    if (!validDocument(doc) or !std.math.isFinite(doc.overall_scale) or doc.overall_scale <= 0 or doc.overall_scale > 100) return error.InvalidModifiers;
    if (!std.mem.eql(u8, doc.source_hash, expected_hash)) return error.SourceChanged;
    const analysis = try analyzeWithWeldCell(allocator, model.*, doc.weld_cell);
    errdefer {
        allocator.free(analysis.vertex_parts);
        allocator.free(analysis.components);
    }
    if (doc.parts.len != analysis.components.len) return error.ComponentSetChanged;
    const slots = try PartSlots.init(allocator, doc.parts);
    defer slots.deinit(allocator);
    for (analysis.components) |component| if (slots.indexOf(component.id) == null) return error.ComponentSetChanged;
    for (doc.parts) |part| {
        if (!validScale(part.scale) or !validOffset(part.offset)) return error.InvalidPartTransform;
        if (part.color) |color| if (!validColor(color)) return error.InvalidPartColor;
    }
    const filtered_indices = try filteredIndices(allocator, model, analysis, doc, slots);
    errdefer if (filtered_indices) |indices| allocator.free(indices);
    for (model.mesh.vertices, analysis.vertex_parts) |*vertex, id| {
        const part = doc.parts[slots.indexOf(id).?];
        const color = partColor(doc, part);
        const component = analysis.components[componentIndex(analysis.components, id).?];
        for (0..3) |axis| {
            vertex.position[axis] = (component.center[axis] + (vertex.position[axis] - component.center[axis]) * part.scale[axis]) * doc.overall_scale + part.offset[axis];
            vertex.color[axis] = color[axis];
        }
    }
    if (filtered_indices) |indices| {
        allocator.free(model.mesh.indices);
        model.mesh.indices = indices;
    }
    recalcNormals(model.*);
    model.computeBounds();
    return analysis;
}

/// Recolors a modifier-baked preview without applying component transforms a second time.
/// Runtime character customization starts from the build-baked mesh, so palette edits use this
/// path while the offline importer continues to use `apply` on source geometry.
pub fn recolor(allocator: std.mem.Allocator, model: *Model, doc: Document) !Analysis {
    if (!validDocument(doc)) return error.InvalidModifiers;
    const analysis = try analyzeWithWeldCell(allocator, model.*, doc.weld_cell);
    errdefer {
        allocator.free(analysis.vertex_parts);
        allocator.free(analysis.components);
    }
    if (doc.parts.len != analysis.components.len) return error.ComponentSetChanged;
    const slots = try PartSlots.init(allocator, doc.parts);
    defer slots.deinit(allocator);
    for (analysis.components) |component| if (slots.indexOf(component.id) == null) return error.ComponentSetChanged;
    for (doc.parts) |part| {
        if (!validScale(part.scale) or !validOffset(part.offset)) return error.InvalidPartTransform;
        if (part.color) |color| if (!validColor(color)) return error.InvalidPartColor;
    }
    for (model.mesh.vertices, analysis.vertex_parts) |*vertex, id| {
        vertex.color = partColor(doc, doc.parts[slots.indexOf(id).?]);
    }
    var triangle: usize = 0;
    while (triangle < model.mesh.indices.len) : (triangle += 3) {
        const part = doc.parts[slots.indexOf(analysis.vertex_parts[model.mesh.indices[triangle]]).?];
        if (!part.enabled) {
            const repeated = model.mesh.indices[triangle];
            @memset(model.mesh.indices[triangle .. triangle + 3], repeated);
        }
    }
    return analysis;
}

fn filteredIndices(allocator: std.mem.Allocator, model: *Model, analysis: Analysis, doc: Document, slots: PartSlots) !?[]u32 {
    const indices = model.mesh.indices;
    var kept: usize = 0;
    var triangle: usize = 0;
    while (triangle < indices.len) : (triangle += 3) {
        const visible = doc.parts[slots.indexOf(analysis.vertex_parts[indices[triangle]]).?].enabled;
        if (visible) kept += 3;
    }
    if (kept == indices.len) return null;
    const result = try allocator.alloc(u32, kept);
    var out: usize = 0;
    for (model.submeshes) |*submesh| {
        const end = @as(usize, submesh.first_index) + submesh.index_count;
        const first = out;
        var at: usize = submesh.first_index;
        while (at < end) : (at += 3) {
            if (!doc.parts[slots.indexOf(analysis.vertex_parts[indices[at]]).?].enabled) continue;
            @memcpy(result[out .. out + 3], indices[at .. at + 3]);
            out += 3;
        }
        submesh.first_index = @intCast(first);
        submesh.index_count = @intCast(out - first);
    }
    return result;
}

pub fn triangleSurfaceColor(doc: Document, analysis: Analysis, model: Model, triangle: usize) [3]f32 {
    if (triangle * 3 + 2 >= model.mesh.indices.len) return .{ 1, 1, 1 };
    const id = analysis.vertex_parts[model.mesh.indices[triangle * 3]];
    const part_index = partIndex(doc.parts, id) orelse return .{ 1, 1, 1 };
    const part = doc.parts[part_index];
    return partColor(doc, part);
}

fn partColor(doc: Document, part: Part) [3]f32 {
    return part.color orelse switch (part.surface) {
        .armor => doc.armor_color,
        .skin => doc.skin_color,
        .eyes => doc.eye_color,
        .energy => doc.energy_color,
        .neutral => .{ 1, 1, 1 },
    };
}

fn validDocument(doc: Document) bool {
    if (!validColor(doc.skin_color) or !validColor(doc.eye_color) or !validColor(doc.armor_color) or !validColor(doc.energy_color)) return false;
    return switch (doc.format) {
        legacy_format_version => doc.weld_cell == null,
        format_version => if (doc.weld_cell) |cell| std.math.isFinite(cell) and cell > 0 else false,
        else => false,
    };
}

fn quantize(position: [3]f32, cell: f32) ![3]i32 {
    var result: [3]i32 = undefined;
    for (position, 0..) |value, axis| {
        if (!std.math.isFinite(value)) return error.InvalidModifiers;
        const scaled = @floor(@as(f64, value) / @as(f64, cell));
        if (scaled < std.math.minInt(i32) or scaled > std.math.maxInt(i32)) return error.InvalidModifiers;
        result[axis] = @intFromFloat(scaled);
    }
    return result;
}

fn componentIndex(components: []const Component, id: u32) ?usize {
    var lo: usize = 0;
    var hi = components.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (components[mid].id == id) return mid;
        if (components[mid].id < id) lo = mid + 1 else hi = mid;
    }
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

test "modifier analysis welds cube face seams and applies author edits" {
    const allocator = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    const source_hash = "blake3:test-source-hash";
    const mesh = try Mesh.cube(allocator);
    var model = try Model.fromMesh(allocator, mesh, .named("captain", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    const doc = try generate(allocator, model, source_hash);
    defer deinit(allocator, doc);
    try std.testing.expectEqual(@as(usize, 1), doc.parts.len);
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

test "rejected edits preserve the document" {
    const allocator = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    const mesh = try Mesh.cube(allocator);
    var model = try Model.fromMesh(allocator, mesh, .named("cube", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    var doc = try generate(allocator, model, "source");
    defer deinit(allocator, doc);
    const invalid = [_]Edit{
        .{ .label = .{ .id = 0, .value = "" } },
        .{ .surface = .{ .id = 999, .value = .skin } },
        .{ .color = .{ .id = 0, .value = .{ 2, 0, 0 } } },
        .{ .scale = .{ .id = 0, .value = .{ 0, 1, 1 } } },
        .{ .offset = .{ .id = 0, .value = .{ 11, 0, 0 } } },
        .{ .palette = .{ .slot = .skin, .value = .{ 0, std.math.nan(f32), 0 } } },
    };
    for (invalid) |command| {
        const before = try std.json.Stringify.valueAlloc(allocator, doc, .{});
        defer allocator.free(before);
        const expected: anyerror = switch (command) {
            .surface => error.ComponentSetChanged,
            .color, .palette => error.InvalidPartColor,
            .scale, .offset => error.InvalidPartTransform,
            .enabled => error.ComponentSetChanged,
            .label => error.InvalidModifiers,
        };
        try std.testing.expectError(expected, edit(allocator, &doc, command));
        const after = try std.json.Stringify.valueAlloc(allocator, doc, .{});
        defer allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
    }
}

test "modifier bake rejects a missing component without changing the model" {
    const allocator = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    const mesh = try Mesh.cube(allocator);
    var model = try Model.fromMesh(allocator, mesh, .named("cube", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    var doc = try generate(allocator, model, "source");
    defer deinit(allocator, doc);
    const original = try allocator.dupe(@import("../render/Mesh.zig").Vertex, model.mesh.vertices);
    defer allocator.free(original);
    var missing = doc;
    missing.parts = doc.parts[0 .. doc.parts.len - 1];
    try std.testing.expectError(error.ComponentSetChanged, apply(allocator, &model, missing, "source"));
    try std.testing.expectEqualSlices(@import("../render/Mesh.zig").Vertex, original, model.mesh.vertices);
}

test "filtered modifier indices keep submeshes contiguous and count visible triangles" {
    const allocator = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    const mesh = try Mesh.cube(allocator);
    var model = try Model.fromMesh(allocator, mesh, .named("cube", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    const submeshes = try allocator.alloc(Model.Submesh, 2);
    allocator.free(model.submeshes);
    submeshes[0] = .{ .first_index = 0, .index_count = 18, .material = 0 };
    submeshes[1] = .{ .first_index = 18, .index_count = 18, .material = 0 };
    model.submeshes = submeshes;
    const doc = try generate(allocator, model, "source");
    defer deinit(allocator, doc);
    doc.parts[0].enabled = false;
    const analysis = try apply(allocator, &model, doc, "source");
    defer allocator.free(analysis.vertex_parts);
    defer allocator.free(analysis.components);
    try std.testing.expectEqual(model.submeshes[0].index_count, model.submeshes[1].first_index);
    try std.testing.expectEqual(@as(u32, @intCast(model.mesh.indices.len)), model.submeshes[0].index_count + model.submeshes[1].index_count);
    try std.testing.expect(model.mesh.indices.len < 36);
}

fn allocationProbe(allocator: std.mem.Allocator, recolor_only: bool) !void {
    const Mesh = @import("../render/Mesh.zig");
    const mesh = try Mesh.cube(allocator);
    var model = try Model.fromMesh(allocator, mesh, .named("cube", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    const doc = try generate(allocator, model, "source");
    defer deinit(allocator, doc);
    if (recolor_only) {
        const analysis = try recolor(allocator, &model, doc);
        allocator.free(analysis.vertex_parts);
        allocator.free(analysis.components);
    } else {
        const analysis = try apply(allocator, &model, doc, "source");
        allocator.free(analysis.vertex_parts);
        allocator.free(analysis.components);
    }
}

test "modifier apply cleans up on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{false});
}

test "modifier recolor cleans up on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{true});
}

test "cached part bake matches full recolor through appearance and visibility edits" {
    const allocator = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    const mesh = try Mesh.cube(allocator);
    var source = try Model.fromMesh(allocator, mesh, .named("cube", .{ 1, 1, 1, 1 }));
    defer source.deinit(allocator);
    var doc = try generate(allocator, source, "source");
    defer deinit(allocator, doc);
    const bake = try Bake.init(allocator, source, doc);
    defer bake.deinit(allocator);
    var actual = try Model.clone(allocator, source);
    defer actual.deinit(allocator);

    for (0..18) |step| {
        switch (step % 3) {
            0 => try edit(allocator, &doc, .{ .surface = .{ .id = 0, .value = if (step % 2 == 0) .skin else .energy } }),
            1 => try edit(allocator, &doc, .{ .color = .{ .id = 0, .value = if (step % 2 == 0) .{ 0.2, 0.4, 0.6 } else null } }),
            else => try edit(allocator, &doc, .{ .enabled = .{ .id = 0, .value = step % 2 == 0 } }),
        }
        try bake.updatePart(&actual, doc, 0);
        var expected = try Model.clone(allocator, source);
        defer expected.deinit(allocator);
        const analysis = try recolor(allocator, &expected, doc);
        allocator.free(analysis.vertex_parts);
        allocator.free(analysis.components);
        try std.testing.expectEqualSlices(Mesh.Vertex, expected.mesh.vertices, actual.mesh.vertices);
        try std.testing.expectEqualSlices(u32, expected.mesh.indices, actual.mesh.indices);
        try std.testing.expectEqualSlices(Model.Submesh, expected.submeshes, actual.submeshes);
        try std.testing.expectEqualSlices(f32, &expected.bounds_min, &actual.bounds_min);
        try std.testing.expectEqualSlices(f32, &expected.bounds_max, &actual.bounds_max);
    }
    try std.testing.expectEqual(source.mesh.indices.len, actual.mesh.indices.len);
}

test "welding joins split corners from the GLB fixture into one shell" {
    const allocator = std.testing.allocator;
    const Gltf = @import("Gltf.zig");
    const source = @embedFile("seam_cube.glb");
    var model = try Gltf.compile(allocator, source, .{});
    defer model.deinit(allocator);
    const legacy = try analyze(allocator, model);
    defer allocator.free(legacy.vertex_parts);
    defer allocator.free(legacy.components);
    const welded = try analyzeWithWeldCell(allocator, model, default_weld_cell);
    defer allocator.free(welded.vertex_parts);
    defer allocator.free(welded.components);
    try std.testing.expectEqual(@as(usize, 6), legacy.components.len);
    try std.testing.expectEqual(@as(usize, 1), welded.components.len);
    try std.testing.expectEqual(@as(u32, 0), welded.components[0].id);
    try std.testing.expectEqual(@as(u32, @intCast(model.mesh.vertices.len)), welded.components[0].count);
}

test "Captain v1 sidecar keeps its original component analysis" {
    const allocator = std.testing.allocator;
    const Gltf = @import("Gltf.zig");
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "assets/Characters/Test+Chroma (1).glb", allocator, .limited(1 << 20));
    defer allocator.free(source);
    var model = try Gltf.compilePosePreview(allocator, source, .{}, .bind);
    defer model.deinit(allocator);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tools/captain/Captain.modifiers.json", allocator, .limited(1 << 20));
    defer allocator.free(bytes);
    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const doc = try std.json.parseFromSliceLeaky(Document, arena_state.allocator(), bytes, .{});
    try std.testing.expectEqual(legacy_format_version, doc.format);
    const analysis = try apply(allocator, &model, doc, doc.source_hash);
    defer allocator.free(analysis.vertex_parts);
    defer allocator.free(analysis.components);
    try std.testing.expectEqual(doc.parts.len, analysis.components.len);
}

test "welded and unwelded ids match for an unsplit indexed shell" {
    const allocator = std.testing.allocator;
    const vertices = try allocator.alloc(@import("../render/Mesh.zig").Vertex, 4);
    defer allocator.free(vertices);
    vertices[0] = .{ .position = .{ 0, 0, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 0 } };
    vertices[1] = .{ .position = .{ 1, 0, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 1, 0 } };
    vertices[2] = .{ .position = .{ 1, 1, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 1, 1 } };
    vertices[3] = .{ .position = .{ 0, 1, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 1 } };
    const indices = [_]u32{ 0, 1, 2, 0, 2, 3 };
    const model: Model = .{ .mesh = .{ .vertices = vertices, .indices = @constCast(&indices) }, .submeshes = &.{}, .materials = &.{}, .bounds_min = .{ 0, 0, 0 }, .bounds_max = .{ 1, 1, 0 } };
    const legacy = try analyze(allocator, model);
    defer allocator.free(legacy.vertex_parts);
    defer allocator.free(legacy.components);
    const welded = try analyzeWithWeldCell(allocator, model, default_weld_cell);
    defer allocator.free(welded.vertex_parts);
    defer allocator.free(welded.components);
    try std.testing.expectEqualSlices(u32, legacy.vertex_parts, welded.vertex_parts);
    try std.testing.expectEqual(legacy.components.len, welded.components.len);
}

test "v1 modifiers retain unwelded analysis and v2 documents require a weld cell" {
    var legacy = Document{
        .format = legacy_format_version,
        .source_hash = "legacy",
        .parts = &.{},
    };
    try std.testing.expect(validDocument(legacy));
    legacy.format = format_version;
    try std.testing.expect(!validDocument(legacy));
    legacy.weld_cell = default_weld_cell;
    try std.testing.expect(validDocument(legacy));
    legacy.weld_cell = 0;
    try std.testing.expect(!validDocument(legacy));
}

test "modifier commands undo and redo each editable value byte for byte" {
    const allocator = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    const mesh = try Mesh.cube(allocator);
    var model = try Model.fromMesh(allocator, mesh, .named("cube", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    var doc = try generate(allocator, model, "source");
    defer deinit(allocator, doc);
    const commands = [_]Command{
        .{ .surface = .{ .id = 0, .before = .armor, .after = .skin } },
        .{ .color = .{ .id = 0, .before = null, .after = .{ 0.1, 0.2, 0.3 } } },
        .{ .enabled = .{ .id = 0, .before = true, .after = false } },
        .{ .scale = .{ .id = 0, .before = .{ 1, 1, 1 }, .after = .{ 1.1, 1.2, 1.3 } } },
        .{ .offset = .{ .id = 0, .before = .{ 0, 0, 0 }, .after = .{ 0.1, 0.2, 0.3 } } },
        .{ .palette = .{ .slot = .eyes, .before = doc.eye_color, .after = .{ 0.3, 0.4, 0.5 } } },
    };
    for (commands) |command| {
        const before = try std.json.Stringify.valueAlloc(allocator, doc, .{});
        defer allocator.free(before);
        try command.apply(allocator, &doc, .after);
        const after = try std.json.Stringify.valueAlloc(allocator, doc, .{});
        defer allocator.free(after);
        try command.apply(allocator, &doc, .before);
        const undone = try std.json.Stringify.valueAlloc(allocator, doc, .{});
        defer allocator.free(undone);
        try std.testing.expectEqualStrings(before, undone);
        try command.apply(allocator, &doc, .after);
        const redone = try std.json.Stringify.valueAlloc(allocator, doc, .{});
        defer allocator.free(redone);
        try std.testing.expectEqualStrings(after, redone);
        try command.apply(allocator, &doc, .before);
    }
}

test "modifier history coalesces transforms and rejected commands do not change state" {
    const allocator = std.testing.allocator;
    const Mesh = @import("../render/Mesh.zig");
    const mesh = try Mesh.cube(allocator);
    var model = try Model.fromMesh(allocator, mesh, .named("cube", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    var doc = try generate(allocator, model, "source");
    defer deinit(allocator, doc);
    var history: History(4) = .{};
    const first: Command = .{ .scale = .{ .id = 0, .before = .{ 1, 1, 1 }, .after = .{ 1.1, 1, 1 } } };
    const second: Command = .{ .scale = .{ .id = 0, .before = .{ 1.1, 1, 1 }, .after = .{ 1.2, 1, 1 } } };
    try history.applyAndPush(allocator, &doc, first);
    try history.applyAndPush(allocator, &doc, second);
    try std.testing.expectEqual(@as(usize, 1), history.len);
    try std.testing.expectEqual(@as(f32, 1.2), doc.parts[0].scale[0]);
    const before_rejection = try std.json.Stringify.valueAlloc(allocator, doc, .{});
    defer allocator.free(before_rejection);
    try std.testing.expectError(error.ComponentSetChanged, history.applyAndPush(allocator, &doc, .{ .surface = .{ .id = 999, .before = .armor, .after = .skin } }));
    try std.testing.expectEqual(@as(usize, 1), history.len);
    try std.testing.expectEqual(@as(usize, 1), history.cursor);
    const after_rejection = try std.json.Stringify.valueAlloc(allocator, doc, .{});
    defer allocator.free(after_rejection);
    try std.testing.expectEqualStrings(before_rejection, after_rejection);
    const undo = history.undo().?;
    try undo.apply(allocator, &doc, .before);
    try std.testing.expectEqual(@as(f32, 1), doc.parts[0].scale[0]);
    try history.applyAndPush(allocator, &doc, .{ .palette = .{ .slot = .eyes, .before = doc.eye_color, .after = .{ 0.2, 0.3, 0.4 } } });
    try std.testing.expectEqual(@as(usize, 1), history.len);
    try std.testing.expectEqual(@as(usize, 1), history.cursor);
    try std.testing.expect(history.redo() == null);
}
