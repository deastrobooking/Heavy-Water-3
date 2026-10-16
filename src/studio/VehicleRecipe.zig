//! Vehicle studio core: a small, versioned recipe that describes a hover car, the knobs and cage
//! brush that edit it, and an evaluation that builds the real car and reports the numbers the
//! flight model uses. A recipe reproduces each shipped design exactly (`fromDesign`), so the
//! studio and the game can never disagree about what a car is. No window, no allocation outside
//! `evaluate`, `encode` and `decode`.
const std = @import("std");
const car = @import("../vehicle/car.zig");
const hull = @import("../vehicle/hull.zig");
const Designs = @import("../vehicle/Designs.zig");
const m = @import("../character/math.zig");
const History = @import("History.zig").History;
const Knob = @import("Knob.zig");
const Brush = @import("Brush.zig");

pub const format_version: u32 = 1;
pub const n_knots = hull.n_knots;
pub const name_capacity = 24;
/// The cage curves scale a station's height or width between these factors of the base hull.
pub const cage_range = [2]f32{ 0.6, 1.5 };
/// The game's own rule for "can lift itself" (see the `Designs` test): four fans must produce at
/// least this multiple of the car's weight.
pub const min_lift_ratio: f32 = 1.35;
const gravity: f32 = 9.81;

const base: car.CarSpec = .{};

pub const Recipe = struct {
    format: u32 = format_version,
    name: []const u8 = "CUSTOM",
    length: f32 = base.hull.length,
    /// Per-station multipliers on the base hull: height scales the upper surfaces above the sill,
    /// width scales every width curve. 1 leaves the shipped hull unchanged.
    cage_height: [n_knots]f32 = @splat(1),
    cage_width: [n_knots]f32 = @splat(1),
    fan_radius: f32 = base.fan.radius,
    fan_blades: u8 = base.fan.blades,
    pad_x: f32 = base.pad_pos[0].x,
    pad_y: f32 = base.pad_pos[0].y,
    pad_z_front: f32 = base.pad_pos[0].z,
    pad_z_rear: f32 = base.pad_pos[2].z,
    wing: bool = true,
    wing_span: f32 = base.wing.?.span,
    wing_root_le: [3]f32 = .{ base.wing.?.root_le.x, base.wing.?.root_le.y, base.wing.?.root_le.z },
    hull_mass: f32 = base.hull_mass,
    fan_mass: f32 = base.fan_mass,
    wing_mass: f32 = base.wing_mass,
    fan_power: f32 = base.fan_power,
    cruise_thrust: f32 = base.cruise_thrust,
    boost_thrust: f32 = base.boost_thrust,
    ride_height: f32 = base.ride_height,
    paint: [3]f32 = Designs.palette(.skimmer).paint,
    accent: [3]f32 = Designs.palette(.skimmer).accent,
    lights: [3]f32 = Designs.palette(.skimmer).lights,

    pub const Error = error{InvalidRecipe};

    pub fn validate(self: Recipe) Error!void {
        if (self.format != format_version) return error.InvalidRecipe;
        if (self.name.len == 0 or self.name.len > name_capacity) return error.InvalidRecipe;
        for (self.name) |c| if (c < 0x20 or c > 0x7e) return error.InvalidRecipe;
        inline for (.{ Param.length, Param.fan_radius, Param.pad_x, Param.pad_z_front, Param.pad_z_rear, Param.wing_span, Param.hull_mass, Param.fan_mass, Param.fan_power, Param.cruise_thrust, Param.boost_thrust, Param.ride_height }) |p| {
            const r = range(p);
            const v = get(self, p);
            if (!std.math.isFinite(v) or v < r[0] or v > r[1]) return error.InvalidRecipe;
        }
        for (self.cage_height ++ self.cage_width) |v| if (!std.math.isFinite(v) or v < cage_range[0] or v > cage_range[1]) return error.InvalidRecipe;
        if (self.fan_blades < 4 or self.fan_blades > 12) return error.InvalidRecipe;
        if (!std.math.isFinite(self.pad_y) or self.pad_y < 0.3 or self.pad_y > 0.7) return error.InvalidRecipe;
        if (!std.math.isFinite(self.wing_mass) or self.wing_mass < 10 or self.wing_mass > 40) return error.InvalidRecipe;
        for (self.wing_root_le) |v| if (!std.math.isFinite(v) or @abs(v) > 4) return error.InvalidRecipe;
        if (self.boost_thrust < self.cruise_thrust) return error.InvalidRecipe;
        for (self.paint ++ self.accent ++ self.lights) |v| if (!std.math.isFinite(v) or v < 0 or v > 1) return error.InvalidRecipe;
    }
};

/// The scalar parameters an artist edits directly or through knobs.
pub const Param = enum { length, fan_radius, pad_x, pad_z_front, pad_z_rear, wing_span, hull_mass, fan_mass, fan_power, cruise_thrust, boost_thrust, ride_height };
pub const param_count: usize = @as(usize, @intFromEnum(Param.ride_height)) + 1;

pub fn range(p: Param) [2]f32 {
    return switch (p) {
        .length => .{ 3.0, 7.0 },
        .fan_radius => .{ 0.2, 0.5 },
        .pad_x => .{ 0.9, 1.8 },
        .pad_z_front => .{ 0.5, 2.4 },
        .pad_z_rear => .{ -2.4, -0.5 },
        .wing_span => .{ 1.0, 3.2 },
        .hull_mass => .{ 400, 1500 },
        .fan_mass => .{ 20, 70 },
        .fan_power => .{ 100_000, 600_000 },
        .cruise_thrust => .{ 4_000, 16_000 },
        .boost_thrust => .{ 8_000, 40_000 },
        .ride_height => .{ 0.5, 2.0 },
    };
}

pub fn get(r: Recipe, p: Param) f32 {
    return switch (p) {
        .length => r.length,
        .fan_radius => r.fan_radius,
        .pad_x => r.pad_x,
        .pad_z_front => r.pad_z_front,
        .pad_z_rear => r.pad_z_rear,
        .wing_span => r.wing_span,
        .hull_mass => r.hull_mass,
        .fan_mass => r.fan_mass,
        .fan_power => r.fan_power,
        .cruise_thrust => r.cruise_thrust,
        .boost_thrust => r.boost_thrust,
        .ride_height => r.ride_height,
    };
}

/// Validate first, then assign: a rejected value leaves the recipe untouched.
pub fn set(r: *Recipe, p: Param, value: f32) Recipe.Error!void {
    const bounds = range(p);
    if (!std.math.isFinite(value) or value < bounds[0] or value > bounds[1]) return error.InvalidRecipe;
    switch (p) {
        .length => r.length = value,
        .fan_radius => r.fan_radius = value,
        .pad_x => r.pad_x = value,
        .pad_z_front => r.pad_z_front = value,
        .pad_z_rear => r.pad_z_rear = value,
        .wing_span => r.wing_span = value,
        .hull_mass => r.hull_mass = value,
        .fan_mass => r.fan_mass = value,
        .fan_power => r.fan_power = value,
        .cruise_thrust => r.cruise_thrust = value,
        .boost_thrust => r.boost_thrust = value,
        .ride_height => r.ride_height = value,
    }
}

pub fn paramsOf(r: Recipe) [param_count]f32 {
    var out: [param_count]f32 = undefined;
    inline for (0..param_count) |i| out[i] = get(r, @enumFromInt(i));
    return out;
}

/// The recipe that reproduces a shipped design exactly.
pub fn fromDesign(d: Designs.Design) Recipe {
    const s = Designs.spec(d);
    const p = Designs.palette(d);
    const wing: airfoilWing = if (s.wing) |w| .{ .span = w.span, .root = .{ w.root_le.x, w.root_le.y, w.root_le.z } } else .{ .span = base.wing.?.span, .root = .{ base.wing.?.root_le.x, base.wing.?.root_le.y, base.wing.?.root_le.z } };
    return .{
        .name = Designs.name(d),
        .length = s.hull.length,
        .fan_radius = s.fan.radius,
        .fan_blades = s.fan.blades,
        .pad_x = s.pad_pos[0].x,
        .pad_y = s.pad_pos[0].y,
        .pad_z_front = s.pad_pos[0].z,
        .pad_z_rear = s.pad_pos[2].z,
        .wing = s.wing != null,
        .wing_span = wing.span,
        .wing_root_le = wing.root,
        .hull_mass = s.hull_mass,
        .fan_mass = s.fan_mass,
        .wing_mass = s.wing_mass,
        .fan_power = s.fan_power,
        .cruise_thrust = s.cruise_thrust,
        .boost_thrust = s.boost_thrust,
        .ride_height = s.ride_height,
        .paint = p.paint,
        .accent = p.accent,
        .lights = p.lights,
    };
}
const airfoilWing = struct { span: f32, root: [3]f32 };

fn applyCage(h: hull.HullSpec, height: [n_knots]f32, width: [n_knots]f32) hull.HullSpec {
    var s = h;
    for (0..n_knots) |k| {
        // A factor of exactly 1 is skipped so an untouched cage reproduces the base bit for bit.
        if (height[k] != 1) {
            const floor = h.y_sill[k];
            s.y_belt[k] = floor + (h.y_belt[k] - floor) * height[k];
            s.y_sh[k] = floor + (h.y_sh[k] - floor) * height[k];
            s.y_up[k] = floor + (h.y_up[k] - floor) * height[k];
            s.y_roof[k] = floor + (h.y_roof[k] - floor) * height[k];
        }
        if (width[k] != 1) {
            s.w_floor[k] = h.w_floor[k] * width[k];
            s.w_sill[k] = h.w_sill[k] * width[k];
            s.w_belt[k] = h.w_belt[k] * width[k];
            s.w_sh[k] = h.w_sh[k] * width[k];
            s.w_up[k] = h.w_up[k] * width[k];
            s.w_roof[k] = h.w_roof[k] * width[k];
        }
    }
    return s;
}

/// The generator spec the game builds a car from.
pub fn toSpec(r: Recipe) car.CarSpec {
    var s: car.CarSpec = .{};
    s.hull = applyCage(s.hull, r.cage_height, r.cage_width);
    s.hull.length = r.length;
    s.fan.radius = r.fan_radius;
    s.fan.blades = r.fan_blades;
    s.pad_pos = .{
        m.Vec3.init(r.pad_x, r.pad_y, r.pad_z_front),
        m.Vec3.init(-r.pad_x, r.pad_y, r.pad_z_front),
        m.Vec3.init(r.pad_x, r.pad_y, r.pad_z_rear),
        m.Vec3.init(-r.pad_x, r.pad_y, r.pad_z_rear),
    };
    if (r.wing) {
        var w = s.wing.?;
        w.span = r.wing_span;
        w.root_le = m.Vec3.init(r.wing_root_le[0], r.wing_root_le[1], r.wing_root_le[2]);
        s.wing = w;
    } else s.wing = null;
    s.hull_mass = r.hull_mass;
    s.fan_mass = r.fan_mass;
    s.wing_mass = r.wing_mass;
    s.fan_power = r.fan_power;
    s.cruise_thrust = r.cruise_thrust;
    s.boost_thrust = r.boost_thrust;
    s.ride_height = r.ride_height;
    return s;
}

pub fn palette(r: Recipe) Designs.Palette {
    return .{ .paint = r.paint, .accent = r.accent, .lights = r.lights };
}

/// The built car and the numbers an artist watches while editing. `parts` is owned.
pub const Evaluation = struct {
    parts: car.Parts,
    mass_kg: f32,
    /// Four fans' maximum thrust over the car's weight; the game requires at least `min_lift_ratio`.
    lift_ratio: f32,
    cruise_thrust_to_weight: f32,
    boost_thrust_to_weight: f32,
    body_triangles: usize,
    flyable: bool,

    pub fn deinit(self: *Evaluation, gpa: std.mem.Allocator) void {
        self.parts.deinit(gpa);
    }
};

pub fn evaluate(gpa: std.mem.Allocator, r: Recipe) !Evaluation {
    try r.validate();
    const spec = toSpec(r);
    var parts = try car.build(gpa, spec);
    errdefer parts.deinit(gpa);
    const flyer = car.flyer(spec, &parts, m.Vec3.init(0, 2, 0), 0);
    const weight = parts.mass.mass * gravity;
    const lift = 4 * flyer.maxFanThrust() / weight;
    return .{
        .parts = parts,
        .mass_kg = parts.mass.mass,
        .lift_ratio = lift,
        .cruise_thrust_to_weight = spec.cruise_thrust / weight,
        .boost_thrust_to_weight = spec.boost_thrust / weight,
        .body_triangles = parts.body.indices.items.len / 3,
        .flyable = lift > min_lift_ratio,
    };
}

pub fn encode(allocator: std.mem.Allocator, r: Recipe) ![]u8 {
    try r.validate();
    return std.json.Stringify.valueAlloc(allocator, r, .{ .whitespace = .indent_2 });
}

/// Parses and validates before returning, so a bad file never yields a recipe. Strings live in
/// `arena`, which the caller owns.
pub fn decode(arena: std.mem.Allocator, bytes: []const u8) !Recipe {
    const r = std.json.parseFromSliceLeaky(Recipe, arena, bytes, .{}) catch return error.InvalidRecipe;
    try r.validate();
    return r;
}

pub const CageCurve = enum { height, width };

/// One undoable edit. `gesture` ties together the pieces of one drag or stroke so they merge.
pub const Command = union(enum) {
    params: struct { gesture: u32, before: [param_count]f32, after: [param_count]f32 },
    cage: struct { gesture: u32, curve: CageCurve, before: [n_knots]f32, after: [n_knots]f32 },

    pub fn coalesce(self: *Command, next: Command) bool {
        switch (self.*) {
            .params => |*a| switch (next) {
                .params => |b| if (a.gesture == b.gesture) {
                    a.after = b.after;
                    return true;
                },
                else => {},
            },
            .cage => |*a| switch (next) {
                .cage => |b| if (a.gesture == b.gesture and a.curve == b.curve) {
                    a.after = b.after;
                    return true;
                },
                else => {},
            },
        }
        return false;
    }
};

/// The editing session: a recipe and its undo history. Every edit validates before it mutates.
pub const Studio = struct {
    recipe: Recipe,
    history: History(Command, 128) = .{},

    pub fn init(r: Recipe) Recipe.Error!Studio {
        try r.validate();
        return .{ .recipe = r };
    }

    /// Sets one parameter (a slider).
    pub fn setParam(self: *Studio, gesture: u32, p: Param, value: f32) Recipe.Error!void {
        var after = paramsOf(self.recipe);
        after[@intFromEnum(p)] = value;
        try self.commitParams(gesture, after);
    }

    /// Moves a macro knob; every parameter it maps changes together as one edit.
    pub fn applyKnob(self: *Studio, gesture: u32, knob: Knob, position: f32) (Recipe.Error || error{InvalidKnob})!void {
        var after = paramsOf(self.recipe);
        try knob.apply(position, &after);
        try self.commitParams(gesture, after);
    }

    /// One brush sample on a cage curve; samples of the same gesture merge into one undo step.
    pub fn brush(self: *Studio, gesture: u32, curve: CageCurve, center: f32, radius: f32, delta: f32) Recipe.Error!void {
        const field = switch (curve) {
            .height => &self.recipe.cage_height,
            .width => &self.recipe.cage_width,
        };
        var after = field.*;
        Brush.pullStations(&after, center, radius, delta, cage_range[0], cage_range[1]);
        if (std.mem.eql(f32, &after, field)) return;
        const command: Command = .{ .cage = .{ .gesture = gesture, .curve = curve, .before = field.*, .after = after } };
        try self.run(command, true);
        self.history.push(command);
    }

    pub fn undo(self: *Studio) Recipe.Error!bool {
        const command = self.history.undo() orelse return false;
        try self.run(command, false);
        return true;
    }

    pub fn redo(self: *Studio) Recipe.Error!bool {
        const command = self.history.redo() orelse return false;
        try self.run(command, true);
        return true;
    }

    fn commitParams(self: *Studio, gesture: u32, after: [param_count]f32) Recipe.Error!void {
        const before = paramsOf(self.recipe);
        if (std.mem.eql(f32, &before, &after)) return;
        const command: Command = .{ .params = .{ .gesture = gesture, .before = before, .after = after } };
        try self.run(command, true);
        self.history.push(command);
    }

    /// Applies a command's values to a copy, validates the copy, and only then replaces the recipe.
    fn run(self: *Studio, command: Command, forward: bool) Recipe.Error!void {
        var candidate = self.recipe;
        switch (command) {
            .params => |c| {
                const values = if (forward) c.after else c.before;
                inline for (0..param_count) |i| try set(&candidate, @enumFromInt(i), values[i]);
            },
            .cage => |c| {
                const values = if (forward) c.after else c.before;
                switch (c.curve) {
                    .height => candidate.cage_height = values,
                    .width => candidate.cage_width = values,
                }
            },
        }
        try candidate.validate();
        self.recipe = candidate;
    }
};

/// Built-in knobs. Each maps one slider onto several parameters that should move together.
pub const knobs = [_]Knob{
    .{ .name = "LENGTH", .mappings = .{
        .{ .param = @intFromEnum(Param.length), .points = .{ .{ .at = 0, .value = 3.6 }, .{ .at = 0.5, .value = 4.7 }, .{ .at = 1, .value = 5.8 } } },
        .{ .param = @intFromEnum(Param.pad_z_front), .points = .{ .{ .at = 0, .value = 1.0 }, .{ .at = 0.5, .value = 1.3 }, .{ .at = 1, .value = 1.6 } } },
        .{ .param = @intFromEnum(Param.pad_z_rear), .points = .{ .{ .at = 0, .value = -0.95 }, .{ .at = 0.5, .value = -1.25 }, .{ .at = 1, .value = -1.55 } } },
        null,
    } },
    .{ .name = "POWER", .mappings = .{
        .{ .param = @intFromEnum(Param.fan_power), .points = .{ .{ .at = 0, .value = 220_000 }, .{ .at = 0.5, .value = 300_000 }, .{ .at = 1, .value = 420_000 } } },
        .{ .param = @intFromEnum(Param.cruise_thrust), .points = .{ .{ .at = 0, .value = 7_500 }, .{ .at = 0.5, .value = 9_500 }, .{ .at = 1, .value = 11_500 } } },
        .{ .param = @intFromEnum(Param.boost_thrust), .points = .{ .{ .at = 0, .value = 14_000 }, .{ .at = 0.5, .value = 19_000 }, .{ .at = 1, .value = 26_000 } } },
        null,
    } },
};

// ---- tests -------------------------------------------------------------------------------------

fn expectSpecsEqual(a: car.CarSpec, b: car.CarSpec) !void {
    try std.testing.expect(std.meta.eql(a, b));
}

test "a recipe reproduces every shipped design exactly, and builds the same car" {
    const a = std.testing.allocator;
    for (0..Designs.count) |i| {
        const d: Designs.Design = @enumFromInt(i);
        const r = fromDesign(d);
        try r.validate();
        try expectSpecsEqual(Designs.spec(d), toSpec(r));
        var eval = try evaluate(a, r);
        defer eval.deinit(a);
        var original = try car.build(a, Designs.spec(d));
        defer original.deinit(a);
        try std.testing.expectEqual(original.body.vertices.items.len, eval.parts.body.vertices.items.len);
        try std.testing.expectEqual(original.mass.mass, eval.mass_kg);
        try std.testing.expect(eval.flyable); // every shipped car clears the game's lift rule
        try std.testing.expectApproxEqAbs(Designs.palette(d).paint[0], palette(r).paint[0], 0);
    }
}

test "recipes round-trip through JSON exactly and reject bad files without returning a recipe" {
    const a = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    for (0..Designs.count) |i| {
        const r = fromDesign(@enumFromInt(i));
        const bytes = try encode(a, r);
        defer a.free(bytes);
        const back = try decode(arena.allocator(), bytes);
        try std.testing.expect(std.meta.eql(toSpec(r), toSpec(back)));
        try std.testing.expectEqualStrings(r.name, back.name);
        try std.testing.expectEqual(r.paint, back.paint);
    }
    try std.testing.expectError(error.InvalidRecipe, decode(arena.allocator(), "{\"format\": 2}"));
    try std.testing.expectError(error.InvalidRecipe, decode(arena.allocator(), "{\"format\": 1, \"length\": 99}"));
    try std.testing.expectError(error.InvalidRecipe, decode(arena.allocator(), "{\"format\": 1, \"surprise\": 1}")); // unknown field
    try std.testing.expectError(error.InvalidRecipe, decode(arena.allocator(), "not json"));
    var bad = fromDesign(.skimmer);
    bad.cruise_thrust = 15_000; // each value is inside its own range...
    bad.boost_thrust = 9_000; // ...but boost below cruise breaks the cross-field rule
    try std.testing.expectError(error.InvalidRecipe, encode(a, bad));
}

test "setting a parameter validates first and leaves the recipe unchanged on refusal" {
    var r = fromDesign(.skimmer);
    const before = r;
    try std.testing.expectError(error.InvalidRecipe, set(&r, .length, 99));
    try std.testing.expectError(error.InvalidRecipe, set(&r, .fan_radius, std.math.nan(f32)));
    try std.testing.expect(std.meta.eql(before, r));
    try set(&r, .length, 5.0);
    try std.testing.expectEqual(@as(f32, 5.0), r.length);
}

test "knobs, strokes and sliders edit through history and undo back to the exact start" {
    var studio = try Studio.init(fromDesign(.skimmer));
    const start = studio.recipe;
    try studio.applyKnob(1, knobs[0], 1.0); // longest
    try std.testing.expect(studio.recipe.length > start.length and studio.recipe.pad_z_front > start.pad_z_front);
    try studio.brush(2, .height, 4, 2.5, 0.2); // raise the roof around the cabin
    try studio.brush(2, .height, 4, 2.5, 0.1); // same stroke: one undo step
    try std.testing.expect(studio.recipe.cage_height[4] > 1.2);
    try studio.setParam(3, .ride_height, 1.4);
    try std.testing.expectEqual(@as(usize, 3), studio.history.cursor);
    try std.testing.expect(toSpec(studio.recipe).hull.y_roof[4] > toSpec(start).hull.y_roof[4]);

    try std.testing.expect(try studio.undo());
    try std.testing.expect(try studio.undo());
    try std.testing.expect(try studio.undo());
    try std.testing.expect(!(try studio.undo()));
    try std.testing.expect(std.meta.eql(start, studio.recipe)); // exactly the starting recipe
    try std.testing.expect(try studio.redo());
    try std.testing.expect(studio.recipe.length > start.length);
    // A refused edit changes neither the recipe nor the history.
    const cursor = studio.history.cursor;
    const snapshot = studio.recipe;
    try std.testing.expectError(error.InvalidRecipe, studio.setParam(9, .length, 50));
    try std.testing.expect(std.meta.eql(snapshot, studio.recipe));
    try std.testing.expectEqual(cursor, studio.history.cursor);
}

test "evaluation reports mass and lift, and flags a car that cannot lift itself" {
    const a = std.testing.allocator;
    var heavy = fromDesign(.courier);
    heavy.hull_mass = 1500;
    heavy.fan_mass = 70;
    heavy.fan_power = 100_000;
    heavy.fan_radius = 0.2;
    try heavy.validate(); // every value is individually legal
    var eval = try evaluate(a, heavy);
    defer eval.deinit(a);
    try std.testing.expect(!eval.flyable and eval.lift_ratio < min_lift_ratio);
    var light = fromDesign(.dart);
    var ok = try evaluate(a, light);
    defer ok.deinit(a);
    try std.testing.expect(ok.flyable and ok.lift_ratio > eval.lift_ratio);
    light.name = "";
    try std.testing.expectError(error.InvalidRecipe, evaluate(a, light));
}

test "every corner of the legal cage and parameter ranges builds a finite car" {
    const a = std.testing.allocator;
    var state: u64 = 0x9e3779b97f4a7c15;
    const next = struct {
        fn f(s: *u64) f32 {
            s.* = s.* *% 6364136223846793005 +% 1442695040888963407;
            return @as(f32, @floatFromInt(s.* >> 40)) / @as(f32, @floatFromInt(@as(u64, 1) << 24));
        }
    }.f;
    for (0..24) |trial| {
        var r = fromDesign(@enumFromInt(trial % Designs.count));
        // Extremes on half the trials, random interior values on the rest.
        for (0..n_knots) |k| {
            r.cage_height[k] = if (trial % 2 == 0) (if (next(&state) < 0.5) cage_range[0] else cage_range[1]) else cage_range[0] + next(&state) * (cage_range[1] - cage_range[0]);
            r.cage_width[k] = if (trial % 2 == 0) (if (next(&state) < 0.5) cage_range[0] else cage_range[1]) else cage_range[0] + next(&state) * (cage_range[1] - cage_range[0]);
        }
        inline for (0..param_count) |i| {
            const p: Param = @enumFromInt(i);
            const b = range(p);
            set(&r, p, b[0] + next(&state) * (b[1] - b[0])) catch {};
        }
        if (r.boost_thrust < r.cruise_thrust) r.boost_thrust = r.cruise_thrust;
        try r.validate();
        var eval = try evaluate(a, r);
        defer eval.deinit(a);
        for (eval.parts.body.vertices.items) |v| {
            try std.testing.expect(std.math.isFinite(v.pos.x) and std.math.isFinite(v.pos.y) and std.math.isFinite(v.pos.z));
            try std.testing.expect(std.math.isFinite(v.normal.x) and std.math.isFinite(v.normal.y) and std.math.isFinite(v.normal.z));
        }
        try std.testing.expect(std.math.isFinite(eval.lift_ratio) and eval.mass_kg > 0);
    }
}
