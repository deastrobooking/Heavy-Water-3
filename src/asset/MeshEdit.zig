//! Headless vertex-level editing for imported meshes: picking, vertex selection, soft-selection
//! moves, vertex-colour painting, sculpt brushes and tearing selected faces off as a separate
//! model. The editor works in place on a `Model` it does not own; every change is recorded in a
//! stroke so it can be undone, and the touched vertex indices are queued for a partial GPU upload
//! (`Renderer.queueMeshPatch`). Part-level appearance edits stay in `Modifiers.zig`.
//!
//! Besides colour, each vertex can carry a cel pen (`Model.pens`): which cel material shades and
//! inks it (soft skin ramp, hard armour specular, banded hair, glowing accent ...), so the native
//! cel style can be drawn onto any region of an imported mesh. The editor's allocator must be the
//! one that owns the model, because painting the first pen allocates `Model.pens`.
const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const Model = @import("Model.zig");

pub const V = [3]f32;
pub const Error = error{ OutOfMemory, InvalidMesh, EmptySelection };

/// Copies of one position (UV and hard-edge seams) are welded within this distance, so moving or
/// painting one copy moves or paints them all and the surface does not crack open.
pub const weld_cell: f32 = 1e-4;
pub const max_history = 64;

/// Connectivity derived once from the indexed triangle list. Groups are welded copies; neighbours
/// and incident triangles are per vertex. Topology changes (extract, separate) only degenerate
/// triangles, so this stays valid for the whole session.
pub const Topology = struct {
    /// Vertex to the lowest vertex index of its welded group.
    weld: []u32,
    /// CSR: group members, indexed by representative (empty for non-representatives).
    group_offsets: []u32,
    group_items: []u32,
    /// CSR: neighbouring group representatives, indexed by representative.
    neighbor_offsets: []u32,
    neighbors: []u32,
    /// CSR: triangle numbers (index / 3) using each vertex.
    triangle_offsets: []u32,
    triangles: []u32,

    pub fn init(allocator: std.mem.Allocator, mesh: Mesh) Error!Topology {
        const n = mesh.vertices.len;
        if (n == 0 or mesh.indices.len % 3 != 0) return error.InvalidMesh;
        for (mesh.indices) |i| if (i >= n) return error.InvalidMesh;

        const weld = try allocator.alloc(u32, n);
        errdefer allocator.free(weld);
        {
            var first: std.AutoHashMapUnmanaged([3]i32, u32) = .empty;
            defer first.deinit(allocator);
            for (mesh.vertices, 0..) |v, i| {
                const entry = try first.getOrPut(allocator, quantize(v.position));
                if (!entry.found_existing) entry.value_ptr.* = @intCast(i);
                weld[i] = entry.value_ptr.*;
            }
        }
        const group_offsets, const group_items = try csr(allocator, n, weld, struct {
            fn each(weld_: []const u32, emit: anytype) !void {
                for (weld_, 0..) |rep, i| try emit.add(rep, @intCast(i));
            }
        }.each);
        errdefer allocator.free(group_offsets);
        errdefer allocator.free(group_items);
        const triangle_offsets, const triangles = try csr(allocator, n, mesh.indices, struct {
            fn each(indices: []const u32, emit: anytype) !void {
                for (indices, 0..) |v, k| try emit.add(v, @intCast(k / 3));
            }
        }.each);
        errdefer allocator.free(triangle_offsets);
        errdefer allocator.free(triangles);

        // Neighbour pairs between groups, deduplicated per representative.
        var pairs: std.ArrayList([2]u32) = .empty;
        defer pairs.deinit(allocator);
        var t: usize = 0;
        while (t < mesh.indices.len) : (t += 3) {
            const a = weld[mesh.indices[t]];
            const b = weld[mesh.indices[t + 1]];
            const c = weld[mesh.indices[t + 2]];
            for ([_][2]u32{ .{ a, b }, .{ b, c }, .{ c, a } }) |e| if (e[0] != e[1]) {
                try pairs.append(allocator, e);
                try pairs.append(allocator, .{ e[1], e[0] });
            };
        }
        std.mem.sort([2]u32, pairs.items, {}, struct {
            fn less(_: void, x: [2]u32, y: [2]u32) bool {
                return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]);
            }
        }.less);
        const neighbor_offsets = try allocator.alloc(u32, n + 1);
        errdefer allocator.free(neighbor_offsets);
        var unique: std.ArrayList(u32) = .empty;
        errdefer unique.deinit(allocator);
        @memset(neighbor_offsets, 0);
        var previous: ?[2]u32 = null;
        for (pairs.items) |p| {
            if (previous) |q| if (q[0] == p[0] and q[1] == p[1]) continue;
            previous = p;
            try unique.append(allocator, p[1]);
            neighbor_offsets[p[0] + 1] += 1;
        }
        for (1..n + 1) |i| neighbor_offsets[i] += neighbor_offsets[i - 1];
        return .{
            .weld = weld,
            .group_offsets = group_offsets,
            .group_items = group_items,
            .neighbor_offsets = neighbor_offsets,
            .neighbors = try unique.toOwnedSlice(allocator),
            .triangle_offsets = triangle_offsets,
            .triangles = triangles,
        };
    }

    pub fn deinit(self: *Topology, allocator: std.mem.Allocator) void {
        for ([_][]u32{ self.weld, self.group_offsets, self.group_items, self.neighbor_offsets, self.neighbors, self.triangle_offsets, self.triangles }) |s| allocator.free(s);
        self.* = undefined;
    }

    /// Every vertex welded to `v`, including `v`.
    pub fn group(self: Topology, v: u32) []const u32 {
        const rep = self.weld[v];
        return self.group_items[self.group_offsets[rep]..self.group_offsets[rep + 1]];
    }

    /// Representatives of the groups sharing an edge with `v`'s group.
    pub fn neighborsOf(self: Topology, v: u32) []const u32 {
        const rep = self.weld[v];
        return self.neighbors[self.neighbor_offsets[rep]..self.neighbor_offsets[rep + 1]];
    }

    pub fn trianglesOf(self: Topology, v: u32) []const u32 {
        return self.triangles[self.triangle_offsets[v]..self.triangle_offsets[v + 1]];
    }
};

/// Builds a compressed (offsets, items) table keyed by vertex from a list of (key, value) pairs.
fn csr(allocator: std.mem.Allocator, n: usize, source: []const u32, comptime each: anytype) Error!struct { []u32, []u32 } {
    const offsets = try allocator.alloc(u32, n + 1);
    errdefer allocator.free(offsets);
    @memset(offsets, 0);
    const Count = struct {
        offsets: []u32,
        fn add(self: *@This(), key: u32, _: u32) !void {
            self.offsets[key + 1] += 1;
        }
    };
    var counter: Count = .{ .offsets = offsets };
    try each(source, &counter);
    for (1..n + 1) |i| offsets[i] += offsets[i - 1];
    const items = try allocator.alloc(u32, offsets[n]);
    errdefer allocator.free(items);
    const cursor = try allocator.dupe(u32, offsets[0..n]);
    defer allocator.free(cursor);
    const Fill = struct {
        cursor: []u32,
        items: []u32,
        fn add(self: *@This(), key: u32, value: u32) !void {
            self.items[self.cursor[key]] = value;
            self.cursor[key] += 1;
        }
    };
    var filler: Fill = .{ .cursor = cursor, .items = items };
    try each(source, &filler);
    return .{ offsets, items };
}

fn quantize(p: V) [3]i32 {
    var key: [3]i32 = undefined;
    for (&key, p) |*k, x| k.* = @intFromFloat(std.math.clamp(@round(x / weld_cell), -2e9, 2e9));
    return key;
}

pub const Hit = struct { triangle: u32, distance: f32, point: V, vertex: u32 };

pub const Brush = enum {
    /// Push along the brush's average normal.
    draw,
    /// Push each vertex along its own normal.
    inflate,
    /// Pull each vertex toward its neighbours' average.
    smooth,
    /// Blend vertex colour toward the brush colour.
    paint,
    /// Set the cel pen inside the inner half of the brush (crisp edges, no blending).
    pen,
};

pub const Dab = struct {
    center: V,
    radius: f32,
    /// Fraction of the radius per dab for shape brushes; colour blend amount for paint.
    strength: f32,
    color: V = .{ 1, 1, 1 },
    pen: u8 = 0,
    /// Only change selected vertices: paint or sculpt inside a selected region without
    /// spilling over its edge.
    masked: bool = false,
    /// 0 is a soft airbrush edge; toward 1 the full-strength core widens to a hard round edge.
    hardness: f32 = 0,
    /// How paint combines with the colour already there.
    blend: Blend = .mix,
    /// Repeat the dab mirrored across the model's centre plane (x), for symmetric characters.
    mirror: bool = false,
    /// The view direction in model space. When set, vertices facing away from the viewer are
    /// skipped, so a stroke on the front does not bleed through to the back.
    facing: ?V = null,
};

pub const Blend = enum {
    /// Fade toward the brush colour.
    mix,
    /// Darken: tint the existing colour by the brush colour (glazes, shadows, watercolour).
    multiply,
    /// Lighten: the inverse of multiply (highlights, glows).
    screen,
    /// Pull colour from the neighbours (painterly blending; ignores the brush colour).
    smudge,
};

pub const Similar = enum { pen, color };

/// A colour ramp of up to four stops, sorted by position (0..1).
pub const Ramp = struct {
    stops: [4]Stop = undefined,
    len: u8 = 0,
    pub const Stop = struct { at: f32, color: V };

    pub fn two(a: V, b: V) Ramp {
        var r: Ramp = .{};
        r.stops[0] = .{ .at = 0, .color = a };
        r.stops[1] = .{ .at = 1, .color = b };
        r.len = 2;
        return r;
    }

    pub fn three(a: V, mid: V, b: V) Ramp {
        var r = two(a, b);
        r.stops[2] = r.stops[1];
        r.stops[1] = .{ .at = 0.5, .color = mid };
        r.len = 3;
        return r;
    }

    pub fn sample(self: Ramp, t: f32) V {
        const x = std.math.clamp(t, 0, 1);
        if (self.len == 0) return .{ 1, 1, 1 };
        if (x <= self.stops[0].at) return self.stops[0].color;
        for (1..self.len) |i| {
            const a = self.stops[i - 1];
            const b = self.stops[i];
            if (x <= b.at) return lerp(a.color, b.color, if (b.at > a.at) (x - a.at) / (b.at - a.at) else 1);
        }
        return self.stops[self.len - 1].color;
    }
};

/// What a gradient fill measures to place each vertex on the ramp.
pub const Gradient = union(enum) {
    /// Along the line from `from` (ramp 0) to `to` (ramp 1).
    linear: struct { from: V, to: V },
    /// Outward from `center` (ramp 0) to `radius` (ramp 1).
    radial: struct { center: V, radius: f32 },
    /// Bottom (ramp 0) to top (ramp 1) of the affected vertices.
    height,
    /// Cavities (ramp 0) through flat (0.5) to edges and ridges (ramp 1), scaled by `contrast`.
    curvature: struct { contrast: f32 = 4 },
};

const Snapshot = struct { vertex: Mesh.Vertex, pen: u8, painted: bool };
const VertexChange = struct { index: u32, before: Snapshot, after: Snapshot };
const TriangleChange = struct { triangle: u32, before: [3]u32, after: [3]u32 };
const Stroke = struct {
    vertices: []VertexChange,
    triangles: []TriangleChange,
    fn deinit(self: Stroke, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.triangles);
    }
};

/// One editing session over a model. Strokes group every change between `begin` and `end` into
/// a single undo step (a whole brush drag, a whole gizmo move).
pub const Editor = struct {
    allocator: std.mem.Allocator,
    model: *Model,
    topology: Topology,
    selection: std.DynamicBitSetUnmanaged,
    /// Soft-selection weight per vertex for the current move (1 for selected vertices).
    weights: []f32,
    /// Vertices changed since the caller last drained them (for the partial GPU upload).
    dirty: std.ArrayList(u32) = .empty,
    /// Whether triangle indices changed since the caller last looked (needs an index upload).
    indices_dirty: bool = false,
    undo_stack: std.ArrayList(Stroke) = .empty,
    redo_stack: std.ArrayList(Stroke) = .empty,
    open_vertices: std.AutoArrayHashMapUnmanaged(u32, Snapshot) = .empty,
    open_triangles: std.AutoArrayHashMapUnmanaged(u32, [3]u32) = .empty,
    open: bool = false,
    /// Vertices whose colour was painted by hand. Part recolours (`Modifiers.Bake`) skip them.
    painted: std.DynamicBitSetUnmanaged,
    /// The symmetry plane (model x) for mirrored brushes: the centre of the model's bounds.
    mirror_x: f32 = 0,
    /// A second copy kept in step at the end of every stroke, undo and redo: the base model a
    /// part-appearance bake rebuilds the display from, so a recolour does not undo a sculpt.
    mirror: ?*Model = null,

    pub fn init(allocator: std.mem.Allocator, model: *Model) Error!Editor {
        var topology = try Topology.init(allocator, model.mesh);
        errdefer topology.deinit(allocator);
        var selection = try std.DynamicBitSetUnmanaged.initEmpty(allocator, model.mesh.vertices.len);
        errdefer selection.deinit(allocator);
        var painted = try std.DynamicBitSetUnmanaged.initEmpty(allocator, model.mesh.vertices.len);
        errdefer painted.deinit(allocator);
        const weights = try allocator.alloc(f32, model.mesh.vertices.len);
        @memset(weights, 0);
        return .{ .allocator = allocator, .model = model, .topology = topology, .selection = selection, .weights = weights, .painted = painted, .mirror_x = (model.bounds_min[0] + model.bounds_max[0]) / 2 };
    }

    pub fn deinit(self: *Editor) void {
        const a = self.allocator;
        for (self.undo_stack.items) |s| s.deinit(a);
        for (self.redo_stack.items) |s| s.deinit(a);
        self.undo_stack.deinit(a);
        self.redo_stack.deinit(a);
        self.open_vertices.deinit(a);
        self.open_triangles.deinit(a);
        self.dirty.deinit(a);
        a.free(self.weights);
        self.painted.deinit(a);
        self.selection.deinit(a);
        self.topology.deinit(a);
        self.* = undefined;
    }

    fn vertices(self: *Editor) []Mesh.Vertex {
        return self.model.mesh.vertices;
    }

    // ---- Picking and selection -------------------------------------------------------------

    /// Nearest front or back face along the ray (model space), skipping degenerate triangles.
    pub fn raycast(self: *const Editor, origin: V, direction: V) ?Hit {
        const mesh = self.model.mesh;
        var best: ?Hit = null;
        var t: usize = 0;
        while (t < mesh.indices.len) : (t += 3) {
            const tri = [3]u32{ mesh.indices[t], mesh.indices[t + 1], mesh.indices[t + 2] };
            if (tri[0] == tri[1] and tri[1] == tri[2]) continue;
            const a = mesh.vertices[tri[0]].position;
            const b = mesh.vertices[tri[1]].position;
            const c = mesh.vertices[tri[2]].position;
            const d = intersect(origin, direction, a, b, c) orelse continue;
            if (best != null and d >= best.?.distance) continue;
            const p = add(origin, scale(direction, d));
            var nearest = tri[0];
            for (tri[1..]) |v| if (dist2(mesh.vertices[v].position, p) < dist2(mesh.vertices[nearest].position, p)) {
                nearest = v;
            };
            best = .{ .triangle = @intCast(t / 3), .distance = d, .point = p, .vertex = nearest };
        }
        return best;
    }

    pub fn isSelected(self: *const Editor, v: u32) bool {
        return self.selection.isSet(v);
    }

    pub fn selectedCount(self: *const Editor) usize {
        return self.selection.count();
    }

    pub fn clearSelection(self: *Editor) void {
        self.selection.unsetAll();
    }

    /// Selects (or deselects) `v` and every vertex welded to it.
    pub fn selectVertex(self: *Editor, v: u32, on: bool) void {
        for (self.topology.group(v)) |m| self.selection.setValue(m, on);
    }

    /// Clicks the surface: selects the vertex nearest the hit, keeping the selection when `extend`.
    pub fn pick(self: *Editor, origin: V, direction: V, extend: bool) ?Hit {
        const hit = self.raycast(origin, direction) orelse return null;
        if (!extend) self.clearSelection();
        self.selectVertex(hit.vertex, true);
        return hit;
    }

    /// Selects (or deselects) every vertex within `radius` of `center`.
    pub fn selectSphere(self: *Editor, center: V, radius: f32, on: bool) void {
        const r2 = radius * radius;
        for (self.vertices(), 0..) |v, i| if (dist2(v.position, center) <= r2) self.selection.setValue(i, on);
    }

    /// Adds one ring of neighbours around the current selection.
    pub fn growSelection(self: *Editor) Error!void {
        var add_list: std.ArrayList(u32) = .empty;
        defer add_list.deinit(self.allocator);
        var it = self.selection.iterator(.{});
        while (it.next()) |i| for (self.topology.neighborsOf(@intCast(i))) |n| if (!self.selection.isSet(n)) try add_list.append(self.allocator, n);
        for (add_list.items) |n| self.selectVertex(n, true);
    }

    /// Expands the selection to every vertex connected to it (whole islands).
    pub fn selectLinked(self: *Editor) Error!void {
        var stack: std.ArrayList(u32) = .empty;
        defer stack.deinit(self.allocator);
        var it = self.selection.iterator(.{});
        while (it.next()) |i| try stack.append(self.allocator, @intCast(i));
        while (stack.pop()) |v| for (self.topology.neighborsOf(v)) |n| if (!self.selection.isSet(n)) {
            self.selectVertex(n, true);
            try stack.append(self.allocator, n);
        };
    }

    pub fn invertSelection(self: *Editor) void {
        self.selection.toggleAll();
    }

    // ---- Strokes and history ---------------------------------------------------------------

    /// Starts an undo step. Every change until `end` is one step.
    pub fn begin(self: *Editor) void {
        std.debug.assert(!self.open);
        self.open = true;
    }

    /// Closes the undo step. An empty stroke records nothing.
    pub fn end(self: *Editor) Error!void {
        std.debug.assert(self.open);
        self.open = false;
        defer self.open_vertices.clearRetainingCapacity();
        defer self.open_triangles.clearRetainingCapacity();
        if (self.open_vertices.count() == 0 and self.open_triangles.count() == 0) return;
        const vs = try self.allocator.alloc(VertexChange, self.open_vertices.count());
        errdefer self.allocator.free(vs);
        for (self.open_vertices.keys(), self.open_vertices.values(), vs) |index, before, *out| out.* = .{ .index = index, .before = before, .after = self.snapshot(index) };
        const ts = try self.allocator.alloc(TriangleChange, self.open_triangles.count());
        errdefer self.allocator.free(ts);
        for (self.open_triangles.keys(), self.open_triangles.values(), ts) |tri, before, *out| out.* = .{ .triangle = tri, .before = before, .after = self.model.mesh.indices[tri * 3 ..][0..3].* };
        try self.undo_stack.ensureUnusedCapacity(self.allocator, 1);
        for (self.redo_stack.items) |s| s.deinit(self.allocator);
        self.redo_stack.clearRetainingCapacity();
        if (self.undo_stack.items.len == max_history) self.undo_stack.orderedRemove(0).deinit(self.allocator);
        self.undo_stack.appendAssumeCapacity(.{ .vertices = vs, .triangles = ts });
        try self.syncMirror(self.undo_stack.items[self.undo_stack.items.len - 1]);
    }

    /// Sets the mirror model (or null). It must have the same vertex and index counts.
    pub fn setMirror(self: *Editor, mirror: ?*Model) Error!void {
        if (mirror) |m| if (m.mesh.vertices.len != self.vertices().len or m.mesh.indices.len != self.model.mesh.indices.len) return error.InvalidMesh;
        self.mirror = mirror;
    }

    fn syncMirror(self: *Editor, stroke: Stroke) Error!void {
        const m = self.mirror orelse return;
        if (self.model.pens != null and m.pens == null) {
            const pens = try self.allocator.alloc(u8, m.mesh.vertices.len);
            @memset(pens, 0);
            m.pens = pens;
        }
        for (stroke.vertices) |c| {
            m.mesh.vertices[c.index] = self.vertices()[c.index];
            if (self.model.pens) |pens| m.pens.?[c.index] = pens[c.index];
        }
        for (stroke.triangles) |c| m.mesh.indices[c.triangle * 3 ..][0..3].* = self.model.mesh.indices[c.triangle * 3 ..][0..3].*;
    }

    pub fn canUndo(self: *const Editor) bool {
        return self.undo_stack.items.len > 0;
    }

    pub fn canRedo(self: *const Editor) bool {
        return self.redo_stack.items.len > 0;
    }

    pub fn undo(self: *Editor) Error!bool {
        std.debug.assert(!self.open);
        try self.redo_stack.ensureUnusedCapacity(self.allocator, 1);
        const stroke = self.undo_stack.pop() orelse return false;
        try self.applyStroke(stroke, .before);
        self.redo_stack.appendAssumeCapacity(stroke);
        return true;
    }

    pub fn redo(self: *Editor) Error!bool {
        std.debug.assert(!self.open);
        try self.undo_stack.ensureUnusedCapacity(self.allocator, 1);
        const stroke = self.redo_stack.pop() orelse return false;
        try self.applyStroke(stroke, .after);
        self.undo_stack.appendAssumeCapacity(stroke);
        return true;
    }

    fn applyStroke(self: *Editor, stroke: Stroke, comptime side: enum { before, after }) Error!void {
        try self.dirty.ensureUnusedCapacity(self.allocator, stroke.vertices.len);
        for (stroke.vertices) |c| {
            const snap = if (side == .before) c.before else c.after;
            self.vertices()[c.index] = snap.vertex;
            if (self.model.pens) |pens| pens[c.index] = snap.pen;
            self.painted.setValue(c.index, snap.painted);
            self.dirty.appendAssumeCapacity(c.index);
        }
        for (stroke.triangles) |c| self.model.mesh.indices[c.triangle * 3 ..][0..3].* = if (side == .before) c.before else c.after;
        if (stroke.triangles.len > 0) self.indices_dirty = true;
        try self.syncMirror(stroke);
    }

    /// Remembers the vertex's value at the start of the stroke, once.
    fn touch(self: *Editor, v: u32) Error!void {
        std.debug.assert(self.open);
        const entry = try self.open_vertices.getOrPut(self.allocator, v);
        if (!entry.found_existing) entry.value_ptr.* = self.snapshot(v);
        try self.dirty.append(self.allocator, v);
    }

    fn snapshot(self: *Editor, v: u32) Snapshot {
        return .{ .vertex = self.vertices()[v], .pen = if (self.model.pens) |pens| pens[v] else 0, .painted = self.painted.isSet(v) };
    }

    /// The vertex's cel pen (0 when the model has none).
    pub fn penOf(self: *const Editor, v: u32) u8 {
        return if (self.model.pens) |pens| pens[v] else 0;
    }

    /// Gives the model a pen per vertex (all 0, which draws exactly as before) on first use.
    fn ensurePens(self: *Editor) Error![]u8 {
        if (self.model.pens) |pens| return pens;
        const pens = try self.allocator.alloc(u8, self.vertices().len);
        @memset(pens, 0);
        self.model.pens = pens;
        return pens;
    }

    fn touchTriangle(self: *Editor, t: u32) Error!void {
        std.debug.assert(self.open);
        const entry = try self.open_triangles.getOrPut(self.allocator, t);
        if (!entry.found_existing) entry.value_ptr.* = self.model.mesh.indices[t * 3 ..][0..3].*;
        self.indices_dirty = true;
    }

    /// Hands the caller the changed vertex indices (with repeats) and clears the list.
    pub fn takeDirty(self: *Editor) []const u32 {
        const items = self.dirty.items;
        self.dirty.clearRetainingCapacity();
        return items;
    }

    // ---- Soft selection and moves ----------------------------------------------------------

    /// Weights the move: selected vertices 1, others by distance to the nearest selected vertex
    /// with a smooth falloff to 0 at `radius` (0 is a hard selection).
    pub fn prepareSoft(self: *Editor, radius: f32) Error!void {
        @memset(self.weights, 0);
        var selected: std.ArrayList(V) = .empty;
        defer selected.deinit(self.allocator);
        var lo: V = @splat(std.math.inf(f32));
        var hi: V = @splat(-std.math.inf(f32));
        var it = self.selection.iterator(.{});
        while (it.next()) |i| {
            self.weights[i] = 1;
            const p = self.vertices()[i].position;
            try selected.append(self.allocator, p);
            for (0..3) |k| {
                lo[k] = @min(lo[k], p[k]);
                hi[k] = @max(hi[k], p[k]);
            }
        }
        if (selected.items.len == 0) return error.EmptySelection;
        if (radius <= 0) return;
        for (self.vertices(), 0..) |v, i| {
            if (self.weights[i] == 1) continue;
            // Cheap reject outside the selection's bounds grown by the radius.
            var outside = false;
            for (0..3) |k| outside = outside or v.position[k] < lo[k] - radius or v.position[k] > hi[k] + radius;
            if (outside) continue;
            var nearest = std.math.inf(f32);
            for (selected.items) |p| nearest = @min(nearest, dist2(p, v.position));
            self.weights[i] = falloff(@sqrt(nearest), radius);
        }
    }

    /// Weights a brush-centred region (the grab brush): 1 at `center`, 0 at `radius`.
    pub fn prepareAround(self: *Editor, center: V, radius: f32) void {
        for (self.vertices(), self.weights) |v, *w| w.* = falloff(@sqrt(dist2(v.position, center)), radius);
    }

    /// Moves every weighted vertex by `delta` times its weight. Call within a stroke.
    pub fn move(self: *Editor, delta: V) Error!void {
        var moved: std.ArrayList(u32) = .empty;
        defer moved.deinit(self.allocator);
        for (self.weights, 0..) |w, i| if (w > 0) {
            try self.touch(@intCast(i));
            self.vertices()[i].position = add(self.vertices()[i].position, scale(delta, w));
            try moved.append(self.allocator, @intCast(i));
        };
        try self.refreshNormals(moved.items);
    }

    // ---- Brushes ---------------------------------------------------------------------------

    /// One brush dab. Call repeatedly within a stroke while dragging.
    pub fn dab(self: *Editor, brush: Brush, d: Dab) Error!void {
        if (!d.mirror) return self.dabSide(brush, d, null);
        // Each side of the mirror plane is painted once: this dab owns the centre's side and the
        // mirrored dab owns the other, so a brush crossing the plane is not applied twice there.
        const side: f32 = if (d.center[0] >= self.mirror_x) 1 else -1;
        try self.dabSide(brush, d, side);
        var mirrored = d;
        mirrored.center[0] = 2 * self.mirror_x - d.center[0];
        if (d.facing) |f| mirrored.facing = .{ -f[0], f[1], f[2] };
        try self.dabSide(brush, mirrored, -side);
    }

    fn dabSide(self: *Editor, brush: Brush, d: Dab, side: ?f32) Error!void {
        if (d.radius <= 0) return;
        if (brush == .pen and d.pen >= Model.max_pens) return error.InvalidMesh;
        const pens: []u8 = if (brush == .pen) try self.ensurePens() else &.{};
        var hits: std.ArrayList(u32) = .empty;
        defer hits.deinit(self.allocator);
        var normal: V = .{ 0, 0, 0 };
        const r2 = d.radius * d.radius;
        for (self.vertices(), 0..) |v, i| if (dist2(v.position, d.center) <= r2 and (!d.masked or self.selection.isSet(i))) {
            if (side) |sd| if (if (sd > 0) v.position[0] < self.mirror_x else v.position[0] >= self.mirror_x) continue;
            if (d.facing) |f| if (dot(v.normal, f) > 0.1) continue;
            if (brush == .pen and falloff(@sqrt(dist2(v.position, d.center)), d.radius) < 0.5) continue;
            try hits.append(self.allocator, @intCast(i));
            normal = add(normal, v.normal);
        };
        if (hits.items.len == 0) return;
        normal = normalize(normal);
        // Smooth reads neighbours before any writes so the result does not depend on order.
        const targets = try self.allocator.alloc(V, hits.items.len);
        defer self.allocator.free(targets);
        for (hits.items, targets) |i, *target| {
            const v = self.vertices()[i];
            const w = shapedFalloff(@sqrt(dist2(v.position, d.center)), d.radius, d.hardness) * d.strength;
            target.* = switch (brush) {
                .draw => add(v.position, scale(normal, w * d.radius)),
                .inflate => add(v.position, scale(v.normal, w * d.radius)),
                .smooth => lerp(v.position, self.neighbourAverage(i), @min(1, w)),
                .paint => lerp(v.color, switch (d.blend) {
                    .mix => d.color,
                    .multiply => .{ v.color[0] * d.color[0], v.color[1] * d.color[1], v.color[2] * d.color[2] },
                    .screen => .{ 1 - (1 - v.color[0]) * (1 - d.color[0]), 1 - (1 - v.color[1]) * (1 - d.color[1]), 1 - (1 - v.color[2]) * (1 - d.color[2]) },
                    .smudge => self.neighbourColour(i),
                }, @min(1, w)),
                .pen => v.position,
            };
        }
        for (hits.items, targets) |i, target| {
            try self.touch(i);
            switch (brush) {
                .paint => {
                    self.vertices()[i].color = target;
                    self.painted.set(i);
                },
                .pen => pens[i] = d.pen,
                else => self.vertices()[i].position = target,
            }
        }
        // Welded copies follow their group's touched member so seams stay closed. Colour and pen
        // stay per copy: a seam between two materials is a real edge, not a crack.
        if (brush == .paint or brush == .pen) return;
        for (hits.items) |i| for (self.topology.group(i)) |m| if (m != i and (!d.masked or self.selection.isSet(m))) {
            try self.touch(m);
            self.vertices()[m].position = self.vertices()[i].position;
        };
        try self.refreshNormals(hits.items);
    }

    /// The vertices a fill or filter changes: the selection, or every vertex when none is selected.
    fn affected(self: *const Editor, i: usize) bool {
        return self.selection.count() == 0 or self.selection.isSet(i);
    }

    /// Discrete convexity per vertex in about -1 (cavity) .. 1 (ridge or edge): how far the
    /// neighbours fall below the tangent plane of the welded group's mean normal.
    pub fn curvature(self: *const Editor, out: []f32) void {
        const verts = self.model.mesh.vertices;
        for (verts, out, 0..) |v, *c, i| {
            const ns = self.topology.neighborsOf(@intCast(i));
            if (ns.len == 0) {
                c.* = 0;
                continue;
            }
            // Hard edges split the normal per face; the welded group's mean normal is the surface
            // direction a corner actually bulges along.
            var normal: V = .{ 0, 0, 0 };
            for (self.topology.group(@intCast(i))) |m| normal = add(normal, verts[m].normal);
            normal = normalize(normal);
            var sum: f32 = 0;
            for (ns) |n| {
                const d = sub(verts[n].position, v.position);
                const l = @sqrt(dot(d, d));
                if (l > 1e-9) sum -= dot(normal, d) / l;
            }
            c.* = std.math.clamp(sum / @as(f32, @floatFromInt(ns.len)), -1, 1);
        }
    }

    /// Fills the selection (or the whole mesh) with `ramp` placed by `gradient`, blended in by
    /// `amount` (0..1). One undo step when called inside a stroke.
    pub fn gradientFill(self: *Editor, gradient: Gradient, ramp: Ramp, amount: f32) Error!void {
        const verts = self.vertices();
        var lo: f32 = std.math.inf(f32);
        var hi: f32 = -std.math.inf(f32);
        var bend: []f32 = &.{};
        defer self.allocator.free(bend);
        switch (gradient) {
            .height => for (verts, 0..) |v, i| if (self.affected(i)) {
                lo = @min(lo, v.position[1]);
                hi = @max(hi, v.position[1]);
            },
            .curvature => {
                bend = try self.allocator.alloc(f32, verts.len);
                self.curvature(bend);
            },
            else => {},
        }
        for (verts, 0..) |v, i| {
            if (!self.affected(i)) continue;
            const t: f32 = switch (gradient) {
                .linear => |g| blk: {
                    const axis = sub(g.to, g.from);
                    const l2 = dot(axis, axis);
                    break :blk if (l2 > 1e-12) dot(sub(v.position, g.from), axis) / l2 else 0;
                },
                .radial => |g| if (g.radius > 0) @sqrt(dist2(v.position, g.center)) / g.radius else 0,
                .height => if (hi > lo) (v.position[1] - lo) / (hi - lo) else 0,
                .curvature => |g| 0.5 + 0.5 * std.math.clamp(bend[i] * g.contrast, -1, 1),
            };
            // Edge/cavity colouring leaves flat areas alone: its strength follows the curvature.
            const weight = if (gradient == .curvature) @abs(2 * t - 1) else 1;
            try self.touch(@intCast(i));
            verts[i].color = lerp(v.color, ramp.sample(t), std.math.clamp(amount * weight, 0, 1));
            self.painted.set(i);
        }
    }

    /// Quantizes colour to `levels` bands per channel (the flat, banded cel look).
    pub fn posterize(self: *Editor, levels: u8) Error!void {
        if (levels < 2) return error.InvalidMesh;
        const n: f32 = @floatFromInt(levels - 1);
        for (self.vertices(), 0..) |*v, i| {
            if (!self.affected(i)) continue;
            try self.touch(@intCast(i));
            for (&v.color) |*ch| ch.* = @round(std.math.clamp(ch.*, 0, 1) * n) / n;
            self.painted.set(i);
        }
    }

    /// Paints every selected vertex one colour (a fill, not a brush).
    pub fn fillSelection(self: *Editor, color: V) Error!void {
        var it = self.selection.iterator(.{});
        while (it.next()) |i| {
            try self.touch(@intCast(i));
            self.vertices()[i].color = color;
            self.painted.set(i);
        }
    }

    /// Sets the cel pen of every selected vertex.
    pub fn fillSelectionPen(self: *Editor, pen: u8) Error!void {
        if (pen >= Model.max_pens) return error.InvalidMesh;
        const pens = try self.ensurePens();
        var it = self.selection.iterator(.{});
        while (it.next()) |i| {
            try self.touch(@intCast(i));
            pens[i] = pen;
        }
    }

    /// Adds every vertex with the same pen (or, for colour, within `tolerance` per channel) as
    /// `v`: select everything already painted one way, then repaint or tear it off.
    pub fn selectSimilar(self: *Editor, v: u32, by: Similar, tolerance: f32) void {
        const want_pen = self.penOf(v);
        const want_color = self.vertices()[v].color;
        for (self.vertices(), 0..) |vertex, i| {
            const same = switch (by) {
                .pen => self.penOf(@intCast(i)) == want_pen,
                .color => @abs(vertex.color[0] - want_color[0]) <= tolerance and @abs(vertex.color[1] - want_color[1]) <= tolerance and @abs(vertex.color[2] - want_color[2]) <= tolerance,
            };
            if (same) self.selection.set(i);
        }
    }

    /// Mean colour of `v`'s neighbours (over welded groups: the first copy of each).
    fn neighbourColour(self: *Editor, v: u32) V {
        const ns = self.topology.neighborsOf(v);
        if (ns.len == 0) return self.vertices()[v].color;
        var sum: V = .{ 0, 0, 0 };
        for (ns) |n| sum = add(sum, self.vertices()[n].color);
        return scale(sum, 1 / @as(f32, @floatFromInt(ns.len)));
    }

    /// The colour and pen at a point on the surface (the eyedropper).
    pub fn sample(self: *const Editor, v: u32) struct { color: V, pen: u8 } {
        return .{ .color = self.model.mesh.vertices[v].color, .pen = self.penOf(v) };
    }

    fn neighbourAverage(self: *Editor, v: u32) V {
        const ns = self.topology.neighborsOf(v);
        if (ns.len == 0) return self.vertices()[v].position;
        var sum: V = .{ 0, 0, 0 };
        for (ns) |n| sum = add(sum, self.vertices()[n].position);
        return scale(sum, 1 / @as(f32, @floatFromInt(ns.len)));
    }

    /// Recomputes normals of the vertices around `moved` from their own incident triangles. Each
    /// copy keeps its own triangles, so hard edges (split normals) survive sculpting.
    fn refreshNormals(self: *Editor, moved: []const u32) Error!void {
        var around: std.AutoArrayHashMapUnmanaged(u32, void) = .empty;
        defer around.deinit(self.allocator);
        const indices = self.model.mesh.indices;
        for (moved) |v| for (self.topology.group(v)) |m| for (self.topology.trianglesOf(m)) |t| for (indices[t * 3 ..][0..3]) |corner| {
            try around.put(self.allocator, corner, {});
        };
        for (around.keys()) |v| {
            var n: V = .{ 0, 0, 0 };
            for (self.topology.trianglesOf(v)) |t| n = add(n, faceNormal(self.model.mesh, t));
            if (dot(n, n) < 1e-20) continue;
            try self.touch(v);
            self.vertices()[v].normal = normalize(n);
        }
    }

    // ---- Tearing a mesh apart --------------------------------------------------------------

    /// Copies the triangles whose three corners are selected into a new standalone model (the
    /// caller owns it), with indices rebased, materials and submeshes kept, skin influences
    /// sliced, and positions recentred so the part's pivot is its bounds centre (`pivot` reports
    /// the offset that was removed). Fails on an empty selection.
    pub fn extract(self: *const Editor, allocator: std.mem.Allocator, pivot: ?*V) Error!Model {
        const source = self.model.*;
        const remap = try allocator.alloc(u32, source.mesh.vertices.len);
        defer allocator.free(remap);
        @memset(remap, std.math.maxInt(u32));
        var vertex_count: u32 = 0;
        var index_count: usize = 0;
        for (0..source.mesh.indices.len / 3) |t| if (self.triangleSelected(t)) {
            index_count += 3;
            for (source.mesh.indices[t * 3 ..][0..3]) |v| if (remap[v] == std.math.maxInt(u32)) {
                remap[v] = vertex_count;
                vertex_count += 1;
            };
        };
        if (index_count == 0) return error.EmptySelection;

        const vertices_out = try allocator.alloc(Mesh.Vertex, vertex_count);
        errdefer allocator.free(vertices_out);
        for (remap, 0..) |r, v| if (r != std.math.maxInt(u32)) {
            vertices_out[r] = source.mesh.vertices[v];
        };
        const indices_out = try allocator.alloc(u32, index_count);
        errdefer allocator.free(indices_out);
        // Keep submesh order: each source submesh contributes its selected triangles in turn.
        var submeshes: std.ArrayList(Model.Submesh) = .empty;
        defer submeshes.deinit(allocator);
        var written: u32 = 0;
        for (source.submeshes) |sm| {
            const first = written;
            var t = sm.first_index / 3;
            while (t < (sm.first_index + sm.index_count) / 3) : (t += 1) if (self.triangleSelected(t)) {
                for (source.mesh.indices[t * 3 ..][0..3], 0..) |v, k| indices_out[written + k] = remap[v];
                written += 3;
            };
            if (written > first) try submeshes.append(allocator, .{ .first_index = first, .index_count = written - first, .material = sm.material });
        }
        // Triangles outside every submesh (should not happen in valid models) are still kept.
        if (written != index_count) {
            const first = written;
            for (0..source.mesh.indices.len / 3) |t| if (self.triangleSelected(t) and !inAnySubmesh(source.submeshes, t)) {
                for (source.mesh.indices[t * 3 ..][0..3], 0..) |v, k| indices_out[written + k] = remap[v];
                written += 3;
            };
            try submeshes.append(allocator, .{ .first_index = first, .index_count = written - first, .material = 0 });
        }
        const submeshes_out = try submeshes.toOwnedSlice(allocator);
        errdefer allocator.free(submeshes_out);
        const materials_out = try allocator.dupe(Model.Material, if (source.materials.len > 0) source.materials else &[_]Model.Material{.{}});
        errdefer allocator.free(materials_out);
        const skin_out: ?Model.Skin = if (source.skin) |skin| blk: {
            const influences = try allocator.alloc(Model.SkinVertex, vertex_count);
            errdefer allocator.free(influences);
            for (remap, 0..) |r, v| if (r != std.math.maxInt(u32)) {
                influences[r] = skin.vertices[v];
            };
            const bones = try allocator.dupe(Model.SkinBone, skin.bones);
            break :blk .{ .vertices = influences, .bones = bones };
        } else null;

        errdefer if (skin_out) |sk| {
            allocator.free(sk.vertices);
            allocator.free(sk.bones);
        };
        const pens_out: ?[]u8 = if (source.pens) |pens| blk: {
            const out_pens = try allocator.alloc(u8, vertex_count);
            for (remap, 0..) |r, v| if (r != std.math.maxInt(u32)) {
                out_pens[r] = pens[v];
            };
            break :blk out_pens;
        } else null;
        var out: Model = .{ .mesh = .{ .vertices = vertices_out, .indices = indices_out }, .submeshes = submeshes_out, .materials = materials_out, .bounds_min = undefined, .bounds_max = undefined, .skin = skin_out, .pens = pens_out };
        out.computeBounds();
        const center = scale(add(out.bounds_min, out.bounds_max), 0.5);
        if (pivot) |p| p.* = center;
        // A skinned part keeps model space so its bones' pivots still line up.
        if (out.skin == null) {
            for (out.mesh.vertices) |*v| v.position = sub(v.position, center);
            out.computeBounds();
        }
        return out;
    }

    /// Removes the selected triangles from this mesh (reversibly) by collapsing them in place, so
    /// GPU index ranges and submeshes stay valid. Use after `extract` to tear a part off.
    pub fn separate(self: *Editor) Error!usize {
        var removed: usize = 0;
        for (0..self.model.mesh.indices.len / 3) |t| if (self.triangleSelected(t)) {
            try self.touchTriangle(@intCast(t));
            const first = self.model.mesh.indices[t * 3];
            self.model.mesh.indices[t * 3 ..][0..3].* = .{ first, first, first };
            removed += 1;
        };
        return removed;
    }

    fn triangleSelected(self: *const Editor, t: usize) bool {
        const tri = self.model.mesh.indices[t * 3 ..][0..3];
        if (tri[0] == tri[1] and tri[1] == tri[2]) return false;
        for (tri) |v| if (!self.selection.isSet(v)) return false;
        return true;
    }
};

fn inAnySubmesh(submeshes: []const Model.Submesh, t: usize) bool {
    for (submeshes) |sm| if (t * 3 >= sm.first_index and t * 3 < sm.first_index + sm.index_count) return true;
    return false;
}

/// Smooth 1-to-0 falloff over [0, radius].
/// `falloff` with a hard core: `hardness` 0 is the smooth airbrush curve, near 1 the brush is
/// at full strength almost to its rim.
pub fn shapedFalloff(distance: f32, radius: f32, hardness: f32) f32 {
    if (radius <= 0) return if (distance <= 0) 1 else 0;
    const soft = 1 - std.math.clamp(hardness, 0, 0.95);
    const x = std.math.clamp((1 - distance / radius) / soft, 0, 1);
    return x * x * (3 - 2 * x);
}

pub fn falloff(distance: f32, radius: f32) f32 {
    if (radius <= 0) return if (distance <= 0) 1 else 0;
    const x = std.math.clamp(1 - distance / radius, 0, 1);
    return x * x * (3 - 2 * x);
}

fn faceNormal(mesh: Mesh, t: u32) V {
    const a = mesh.vertices[mesh.indices[t * 3]].position;
    const b = mesh.vertices[mesh.indices[t * 3 + 1]].position;
    const c = mesh.vertices[mesh.indices[t * 3 + 2]].position;
    return cross(sub(b, a), sub(c, a));
}

/// Möller–Trumbore, two-sided. Returns the ray distance or null.
fn intersect(o: V, d: V, a: V, b: V, c: V) ?f32 {
    const e1 = sub(b, a);
    const e2 = sub(c, a);
    const p = cross(d, e2);
    const det = dot(e1, p);
    if (@abs(det) < 1e-12) return null;
    const inv = 1 / det;
    const s = sub(o, a);
    const u = dot(s, p) * inv;
    if (u < 0 or u > 1) return null;
    const q = cross(s, e1);
    const v = dot(d, q) * inv;
    if (v < 0 or u + v > 1) return null;
    const t = dot(e2, q) * inv;
    return if (t > 0) t else null;
}

fn add(a: V, b: V) V {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
fn sub(a: V, b: V) V {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn scale(a: V, s: f32) V {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}
fn dot(a: V, b: V) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn cross(a: V, b: V) V {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
fn dist2(a: V, b: V) f32 {
    const d = sub(a, b);
    return dot(d, d);
}
fn lerp(a: V, b: V, t: f32) V {
    return add(a, scale(sub(b, a), t));
}
fn normalize(a: V) V {
    const l = @sqrt(dot(a, a));
    return if (l > 1e-12) scale(a, 1 / l) else .{ 0, 1, 0 };
}

// ---- Tests ---------------------------------------------------------------------------------

/// A flat 5x5-vertex grid on y = 0 (32 triangles) plus a separate unit cube island at x = 10.
fn testModel(allocator: std.mem.Allocator) !Model {
    const grid = 5;
    const cube = try Mesh.cube(allocator);
    defer cube.deinit(allocator);
    const vertices = try allocator.alloc(Mesh.Vertex, grid * grid + cube.vertices.len);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, (grid - 1) * (grid - 1) * 6 + cube.indices.len);
    errdefer allocator.free(indices);
    for (0..grid) |z| for (0..grid) |x| {
        vertices[z * grid + x] = .{ .position = .{ @floatFromInt(x), 0, @floatFromInt(z) }, .normal = .{ 0, 1, 0 }, .uv = .{ 0, 0 } };
    };
    var k: usize = 0;
    for (0..grid - 1) |z| for (0..grid - 1) |x| {
        const a: u32 = @intCast(z * grid + x);
        for ([_]u32{ a, a + grid, a + 1, a + 1, a + grid, a + grid + 1 }) |i| {
            indices[k] = i;
            k += 1;
        }
    };
    for (cube.vertices, 0..) |v, i| {
        vertices[grid * grid + i] = v;
        vertices[grid * grid + i].position[0] += 10;
    }
    for (cube.indices) |i| {
        indices[k] = i + grid * grid;
        k += 1;
    }
    var model = try Model.fromMesh(allocator, .{ .vertices = vertices, .indices = indices }, .{});
    _ = &model;
    return model;
}

test "topology welds seam copies and finds neighbours and incident triangles" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var topo = try Topology.init(a, model.mesh);
    defer topo.deinit(a);
    // Grid centre (2,2) = vertex 12 touches six triangles and six neighbouring vertices.
    try std.testing.expectEqual(@as(usize, 6), topo.trianglesOf(12).len);
    try std.testing.expectEqual(@as(usize, 6), topo.neighborsOf(12).len);
    // The cube has 24 vertices but 8 corners: each corner welds three face copies.
    try std.testing.expectEqual(@as(usize, 3), topo.group(25).len);
}

test "picking selects the nearest vertex and its welded copies; linked selection takes the island" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    const hit = ed.pick(.{ 2.1, 5, 1.9 }, .{ 0, -1, 0 }, false) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 12), hit.vertex);
    try std.testing.expectEqual(@as(usize, 1), ed.selectedCount());
    try std.testing.expect(ed.pick(.{ 50, 5, 50 }, .{ 0, -1, 0 }, true) == null);
    try ed.growSelection();
    try std.testing.expectEqual(@as(usize, 7), ed.selectedCount());
    try ed.selectLinked();
    try std.testing.expectEqual(@as(usize, 25), ed.selectedCount());
    // A cube corner picks all three of its copies.
    ed.clearSelection();
    _ = ed.pick(.{ 10.49, 5, 0.49 }, .{ 0, -1, 0 }, false) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), ed.selectedCount());
}

test "soft-selection move falls off smoothly and undoes and redoes as one step" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    ed.selectVertex(12, true);
    try ed.prepareSoft(1.5);
    ed.begin();
    try ed.move(.{ 0, 0.5, 0 });
    try ed.move(.{ 0, 0.5, 0 });
    try ed.end();
    try std.testing.expectApproxEqAbs(@as(f32, 1), model.mesh.vertices[12].position[1], 1e-5);
    const near = model.mesh.vertices[13].position[1];
    try std.testing.expect(near > 0 and near < 1);
    try std.testing.expectEqual(@as(f32, 0), model.mesh.vertices[0].position[1]);
    // The raised peak tilts its neighbours' normals.
    try std.testing.expect(model.mesh.vertices[13].normal[1] < 0.999);
    try std.testing.expect(try ed.undo());
    for (model.mesh.vertices[0..25]) |v| {
        try std.testing.expectEqual(@as(f32, 0), v.position[1]);
        try std.testing.expectApproxEqAbs(@as(f32, 1), v.normal[1], 1e-6);
    }
    try std.testing.expect(!ed.canUndo() and ed.canRedo());
    try std.testing.expect(try ed.redo());
    try std.testing.expectApproxEqAbs(@as(f32, 1), model.mesh.vertices[12].position[1], 1e-5);
    try std.testing.expect(ed.takeDirty().len > 0);
    try std.testing.expectEqual(@as(usize, 0), ed.takeDirty().len);
}

test "sculpt brushes draw, inflate and smooth; paint blends colour" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    ed.begin();
    try ed.dab(.draw, .{ .center = .{ 2, 0, 2 }, .radius = 1.5, .strength = 0.5 });
    try ed.end();
    const peak = model.mesh.vertices[12].position[1];
    try std.testing.expect(peak > 0.5);
    try std.testing.expectEqual(@as(f32, 0), model.mesh.vertices[0].position[1]);
    ed.begin();
    for (0..20) |_| try ed.dab(.smooth, .{ .center = .{ 2, 0, 2 }, .radius = 3, .strength = 1 });
    try ed.end();
    try std.testing.expect(model.mesh.vertices[12].position[1] < peak * 0.6);
    ed.begin();
    try ed.dab(.paint, .{ .center = model.mesh.vertices[0].position, .radius = 1.2, .strength = 1, .color = .{ 1, 0, 0 } });
    try ed.end();
    try std.testing.expectEqual([3]f32{ 1, 0, 0 }, model.mesh.vertices[0].color);
    try std.testing.expectEqual([3]f32{ 1, 1, 1 }, model.mesh.vertices[24].color);
    // Inflating the cube pushes each face outward and keeps corner copies together.
    ed.begin();
    try ed.dab(.inflate, .{ .center = .{ 10, 1, 0 }, .radius = 3, .strength = 0.1 });
    try ed.end();
    const g = ed.topology.group(25);
    for (g[1..]) |m| try std.testing.expectEqual(model.mesh.vertices[g[0]].position, model.mesh.vertices[m].position);
    try std.testing.expectEqual(@as(usize, 4), ed.undo_stack.items.len);
    for (0..4) |_| _ = try ed.undo();
    try std.testing.expectEqual([3]f32{ 1, 1, 1 }, model.mesh.vertices[0].color);
    try std.testing.expectEqual(@as(f32, 0), model.mesh.vertices[12].position[1]);
}

test "a selected island tears off as its own recentred model and separate is undoable" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    try std.testing.expectError(error.EmptySelection, ed.extract(a, null));
    _ = ed.pick(.{ 10.2, 5, 0.1 }, .{ 0, -1, 0 }, false) orelse return error.TestUnexpectedResult;
    try ed.selectLinked();
    var pivot: V = undefined;
    var part = try ed.extract(a, &pivot);
    defer part.deinit(a);
    try std.testing.expectEqual(@as(usize, 24), part.mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 36), part.mesh.indices.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10), pivot[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), part.bounds_min[0] + part.bounds_max[0], 1e-5);
    // The part encodes and decodes as a standalone runtime model.
    const bytes = try part.encode(a);
    defer a.free(bytes);
    const back = try Model.decode(a, bytes);
    defer back.deinit(a);
    try std.testing.expectEqual(@as(usize, 36), back.mesh.indices.len);

    ed.begin();
    try std.testing.expectEqual(@as(usize, 12), try ed.separate());
    try ed.end();
    try std.testing.expect(ed.indices_dirty);
    try std.testing.expect(ed.raycast(.{ 10, 5, 0 }, .{ 0, -1, 0 }) == null);
    _ = try ed.undo();
    try std.testing.expect(ed.raycast(.{ 10, 5, 0 }, .{ 0, -1, 0 }) != null);
}

test "editor setup fails cleanly on every allocation" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    try std.testing.checkAllAllocationFailures(a, struct {
        fn run(allocator: std.mem.Allocator, m: *Model) !void {
            var ed = try Editor.init(allocator, m);
            defer ed.deinit();
        }
    }.run, .{&model});
}

test "cel pens paint crisp regions, mask to the selection, select alike, undo and survive extract" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    try std.testing.expect(model.pens == null);
    // Pen 9 (armor) inside the inner half of a radius-2 brush at the grid centre.
    ed.begin();
    try ed.dab(.pen, .{ .center = .{ 2, 0, 2 }, .radius = 2, .strength = 1, .pen = 9 });
    try ed.end();
    try std.testing.expectEqual(@as(u8, 9), ed.penOf(12));
    try std.testing.expectEqual(@as(u8, 9), ed.penOf(13));
    try std.testing.expectEqual(@as(u8, 0), ed.penOf(0));
    // Masked painting stays inside the selection: only the left column is selected.
    for ([_]u32{ 0, 5, 10, 15, 20 }) |v| ed.selectVertex(v, true);
    ed.begin();
    try ed.dab(.paint, .{ .center = .{ 0.5, 0, 2 }, .radius = 3, .strength = 1, .color = .{ 0, 0, 1 }, .masked = true });
    try ed.end();
    try std.testing.expect(model.mesh.vertices[10].color[0] < 0.2 and model.mesh.vertices[10].color[2] == 1);
    try std.testing.expectEqual([3]f32{ 1, 1, 1 }, model.mesh.vertices[11].color);
    // Select alike: every pen-9 vertex, then fill them with pen 8 (accent) in one step.
    ed.clearSelection();
    ed.selectSimilar(12, .pen, 0);
    const painted = ed.selectedCount();
    try std.testing.expect(painted >= 5 and painted < 25);
    ed.begin();
    try ed.fillSelectionPen(8);
    try ed.end();
    try std.testing.expectEqual(@as(u8, 8), ed.penOf(12));
    try std.testing.expectError(error.InvalidMesh, ed.fillSelectionPen(Model.max_pens));
    // The painted region tears off with its pens, and the model saves them (HWMS v4).
    var part = try ed.extract(a, null);
    defer part.deinit(a);
    for (part.pens.?) |pen| try std.testing.expectEqual(@as(u8, 8), pen);
    const bytes = try model.encode(a);
    defer a.free(bytes);
    const back = try Model.decode(a, bytes);
    defer back.deinit(a);
    try std.testing.expectEqualSlices(u8, model.pens.?, back.pens.?);
    _ = try ed.undo();
    _ = try ed.undo();
    _ = try ed.undo();
    for (model.pens.?) |pen| try std.testing.expectEqual(@as(u8, 0), pen);
}

test "strokes, undo and redo keep a mirror model in step and track painted vertices" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var base = try Model.clone(a, model);
    defer base.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    try ed.setMirror(&base);
    ed.begin();
    try ed.dab(.draw, .{ .center = .{ 2, 0, 2 }, .radius = 1.5, .strength = 0.5 });
    try ed.dab(.paint, .{ .center = .{ 2, 0, 2 }, .radius = 1.5, .strength = 1, .color = .{ 0, 1, 0 } });
    try ed.dab(.pen, .{ .center = .{ 2, 0, 2 }, .radius = 1.5, .strength = 1, .pen = 9 });
    try ed.end();
    try std.testing.expectEqualSlices(Mesh.Vertex, model.mesh.vertices, base.mesh.vertices);
    try std.testing.expectEqualSlices(u8, model.pens.?, base.pens.?);
    try std.testing.expect(ed.painted.isSet(12) and !ed.painted.isSet(0));
    _ = try ed.undo();
    try std.testing.expectEqualSlices(Mesh.Vertex, model.mesh.vertices, base.mesh.vertices);
    try std.testing.expect(!ed.painted.isSet(12));
    _ = try ed.redo();
    try std.testing.expect(ed.painted.isSet(12));
    try std.testing.expectEqual(@as(u8, 9), base.pens.?[12]);
}

test "mirrored dabs paint both sides exactly once and backfaces are masked" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    // The test model spans x 0..10.5 (grid plus cube), so the mirror plane is x = 5.25.
    try std.testing.expectApproxEqAbs(@as(f32, 5.25), ed.mirror_x, 1e-5);
    ed.begin();
    try ed.dab(.paint, .{ .center = .{ 1, 0, 1 }, .radius = 0.5, .strength = 1, .color = .{ 1, 0, 0 }, .mirror = true });
    try ed.end();
    try std.testing.expectEqual([3]f32{ 1, 0, 0 }, model.mesh.vertices[6].color);
    // The mirror image of (1, 0, 1) is (9.5, 0, 1): no vertex there, so nothing else changed.
    var painted: usize = 0;
    for (model.mesh.vertices) |v| painted += @intFromBool(v.color[1] == 0);
    try std.testing.expectEqual(@as(usize, 1), painted);
    // The grid faces up; looking up from below (facing +y) masks every grid vertex.
    ed.begin();
    try ed.dab(.paint, .{ .center = .{ 2, 0, 2 }, .radius = 3, .strength = 1, .color = .{ 0, 0, 1 }, .facing = .{ 0, 1, 0 } });
    try ed.end();
    // No grid vertex turned blue (red stays red, untouched stay white).
    for (model.mesh.vertices[0..25]) |v| try std.testing.expect(v.color[0] > 0.5);
    // The same dab seen from above does paint them.
    ed.begin();
    try ed.dab(.paint, .{ .center = .{ 2, 0, 2 }, .radius = 3, .strength = 1, .color = .{ 0, 0, 1 }, .facing = .{ 0, -1, 0 } });
    try ed.end();
    try std.testing.expect(model.mesh.vertices[12].color[0] < 0.5);
}

test "blend modes multiply, screen and smudge, and hardness widens the full-strength core" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    for (model.mesh.vertices) |*v| v.color = .{ 0.5, 0.5, 0.5 };
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    ed.begin();
    try ed.dab(.paint, .{ .center = .{ 0, 0, 0 }, .radius = 0.4, .strength = 1, .color = .{ 0.5, 0.5, 0.5 }, .blend = .multiply });
    try ed.dab(.paint, .{ .center = .{ 4, 0, 4 }, .radius = 0.4, .strength = 1, .color = .{ 0.5, 0.5, 0.5 }, .blend = .screen });
    try ed.end();
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), model.mesh.vertices[0].color[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), model.mesh.vertices[24].color[0], 1e-5);
    // Smudging the dark corner pulls it toward its grey neighbours.
    ed.begin();
    try ed.dab(.paint, .{ .center = .{ 0, 0, 0 }, .radius = 0.4, .strength = 1, .blend = .smudge });
    try ed.end();
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), model.mesh.vertices[0].color[0], 1e-5);
    // At 80% of the radius a soft brush is nearly spent; a hard one is still at full strength.
    try std.testing.expect(shapedFalloff(0.8, 1, 0) < 0.15);
    try std.testing.expect(shapedFalloff(0.8, 1, 0.85) > 0.99);
}

test "the eyedropper reads colour and pen" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    ed.selectVertex(3, true);
    ed.begin();
    try ed.fillSelection(.{ 0.2, 0.3, 0.4 });
    try ed.fillSelectionPen(9);
    try ed.end();
    const got = ed.sample(3);
    try std.testing.expectEqual([3]f32{ 0.2, 0.3, 0.4 }, got.color);
    try std.testing.expectEqual(@as(u8, 9), got.pen);
}

test "ramps, gradient fills (linear, radial, height) and posterize" {
    const red: V = .{ 1, 0, 0 };
    const blue: V = .{ 0, 0, 1 };
    const ramp = Ramp.two(red, blue);
    try std.testing.expectEqual(red, ramp.sample(-1));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ramp.sample(0.5)[0], 1e-6);
    const tri = Ramp.three(red, .{ 0, 1, 0 }, blue);
    try std.testing.expectEqual([3]f32{ 0, 1, 0 }, tri.sample(0.5));

    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    // Linear along +x across the grid only (select the grid island).
    _ = ed.pick(.{ 2, 5, 2 }, .{ 0, -1, 0 }, false);
    try ed.selectLinked();
    ed.begin();
    try ed.gradientFill(.{ .linear = .{ .from = .{ 0, 0, 0 }, .to = .{ 4, 0, 0 } } }, ramp, 1);
    try ed.end();
    try std.testing.expectEqual(red, model.mesh.vertices[0].color);
    try std.testing.expectEqual(blue, model.mesh.vertices[4].color);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), model.mesh.vertices[2].color[0], 1e-6);
    // The cube was not selected, so it kept its colour.
    try std.testing.expectEqual([3]f32{ 1, 1, 1 }, model.mesh.vertices[25].color);
    // Radial from the grid centre.
    ed.begin();
    try ed.gradientFill(.{ .radial = .{ .center = .{ 2, 0, 2 }, .radius = 2 } }, ramp, 1);
    try ed.end();
    try std.testing.expectEqual(red, model.mesh.vertices[12].color);
    try std.testing.expectEqual(blue, model.mesh.vertices[14].color);
    // Height over the cube (y 0..2), nothing selected means the whole mesh.
    ed.clearSelection();
    ed.begin();
    try ed.gradientFill(.height, ramp, 1);
    try ed.end();
    for (model.mesh.vertices[25..]) |v| try std.testing.expectApproxEqAbs(v.position[1] / 2, v.color[2], 1e-5);
    // Posterize to 2 bands: every channel becomes 0 or 1.
    ed.begin();
    try ed.posterize(2);
    try ed.end();
    for (model.mesh.vertices) |v| for (v.color) |ch| try std.testing.expect(ch == 0 or ch == 1);
    try std.testing.expectError(error.InvalidMesh, ed.posterize(1));
    // One undo step per fill.
    for (0..4) |_| _ = try ed.undo();
    try std.testing.expectEqual([3]f32{ 1, 1, 1 }, model.mesh.vertices[0].color);
}

test "curvature marks ridges positive and cavities negative" {
    const a = std.testing.allocator;
    var model = try testModel(a);
    defer model.deinit(a);
    var ed = try Editor.init(a, &model);
    defer ed.deinit();
    // Raise the grid centre into a peak and sink a neighbour of the corner into a pit.
    model.mesh.vertices[12].position[1] = 1;
    model.mesh.vertices[6].position[1] = -1;
    const bend = try a.alloc(f32, model.mesh.vertices.len);
    defer a.free(bend);
    ed.curvature(bend);
    try std.testing.expect(bend[12] > 0.3);
    try std.testing.expect(bend[6] < -0.3);
    // A cube corner is convex.
    try std.testing.expect(bend[25] > 0.3);
    // Edge/cavity fill puts the peak toward the "edge" end of the ramp.
    ed.begin();
    try ed.gradientFill(.{ .curvature = .{} }, Ramp.two(.{ 0, 0, 0 }, .{ 1, 1, 1 }), 1);
    try ed.end();
    try std.testing.expect(model.mesh.vertices[12].color[0] > 0.8);
    try std.testing.expect(model.mesh.vertices[6].color[0] < 0.2);
}
