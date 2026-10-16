# Asset studio: specialized, touch-friendly, reusable tools for characters, vehicles, nature and cities

**Status:** proposed, 2026-10-15; the first vehicle studio slice (the headless core) is implemented 2026-10-15, see section 11, S5. Everything else here is planned. The [roadmap](../roadmap.md) stays the single plan.

**Owner direction (2026-10-15).** The mesh editor must grow beyond characters to vehicles, city assets and nature assets. The tools should be highly automated, and also support touchscreens for 3D drawing so artists can create and modify assets. Think of a gamified, stripped-down Blender: simplified shapes and brushes, not an open-ended modeler. Each tool is specialized for its task (character, vehicle, nature, city), built from highly reusable node-based design features with a GUI for quick modulation and high-performance reuse. The product is a local desktop four-player game; the tools serve that.

**Audience:** engineers and coding agents. Each phase names files, tests and acceptance. The four Zig blocks labelled *compiled* passed `zig test` on the default compiler and on `HEAVYWATER_ZIG_CHANNEL=0.17` (5 tests, all passing on both); they illustrate the design and are not committed code.

## 1. Principles

1. **Specialized, not open-ended.** Every studio offers a small set of operations that make sense for its asset: you lengthen a hull, graft a branch, add a window module; you do not move arbitrary vertices. Constraints are the feature: they keep results readable, in style, and cheap.
2. **Direct manipulation first, graphs underneath.** The default view is cards, sliders, brushes and snapping parts. The node graph is the same data shown for people who want to reuse and automate; nobody has to open it.
3. **One recipe per asset, evaluated deterministically.** A recipe is small versioned data (parameters, a validated graph, sockets). The same recipe produces the same mesh on every machine, which is how the game already treats genomes and character specs.
4. **Automate the boring parts.** Level of detail, collision, sockets, surface colours, symmetry and fitting come from the recipe automatically; the artist never builds them by hand.
5. **Reuse is the performance plan.** Parts and sub-graphs are shared by reference, instanced at draw time, cached per node, and baked once for export.
6. **Mouse, pen, touch and controller are all first-class.** No feature may depend on hover or a keyboard shortcut alone.
7. **Creations belong to the player who made them.** A design is saved in its creator's own library (their `Kit`), never in the shared world, and can be copied to a teammate deliberately.
8. **Native Zig, bounded, no frame allocation,** like the rest of the engine ([AGENTS.md](../../AGENTS.md)).

## 2. What exists today

The game already builds most asset kinds from small parametric descriptions. They each have their own screen and none shares undo, a library or a graph.

| Domain | What exists | Source |
| --- | --- | --- |
| Characters | Lofted anatomy (one `loft` function sweeps a varying cross-section along a centreline with rotation-minimizing frames and builds every limb, skirt and hair clump), a `Profile` with 35 editable fields, armor sets and cel styles as data, an imported-part editor | `character/loft.zig`, `character/curve.zig`, `game/Profile.zig`, `game/Creator.zig` |
| Vehicles | `CarSpec`: hull, fan, optional wing and nozzle specs, four fan positions and per-part masses; the hover car designs the player fabricates; a ship design bay with typed sockets is planned | `vehicle/car.zig`, `vehicle/Designs.zig`, [planetary frontier](planetary-frontier.md) |
| Villain frames | The Hive Forge: seven swappable parts (frame, head, shoulders, arms, legs, back unit, weapon) and five palettes | `game/EnemyDesign.zig` |
| Nature | A tree genome (about a dozen genes plus two colours) grown by space colonization, and eight L-system species grammars | `procedural/Arbor.zig`, `procedural/LSystem.zig`, `procedural/Vegetation.zig` |
| Cities | Bridge road styles (vine, girder, truss, arch, cable-stayed, suspension), a skyline generator, in-world prefab capture | `procedural/District.zig`, `procedural/Skyline.zig`, `game/BridgeTool.zig`, `game/Build.zig` |
| Mesh editing | Source-linked part documents, weld-aware analysis, undo and redo (`History(64)`), an incremental `Bake` | `asset/Modifiers.zig`, [mesheditor](mesheditor.md) |

What is missing: a shared studio shell, one recipe and library format, a node graph, brush tools, a pointer model that includes touch and pen, and any export beyond the game's own formats.

**Input today.** Mach's core event layer exposes mouse, keyboard and gamepad. A search of `vendor/mach` for touch, pressure, tablet and pencil support found none in the core; the generated Objective-C bindings (`vendor/mach-objc`, `app_kit.zig`) do contain the AppKit event APIs, so pen pressure on macOS would be new fork work. How an external touchscreen reaches a macOS app (usually as ordinary mouse events) and how Windows delivers touch (pointer messages) is **not verified here**, and no Windows host is available; plan those as compile-checked only until someone can test them.

## 3. Architecture

```text
 Recipe (JSON, versioned)        parameters + knobs + graph + sockets + surface roles
        |  validate (reject without mutating)
        v
 Evaluate (cached per node)      graph or cage -> loft/cage geometry; bounded, deterministic
        v
 Bake                            mesh + LODs + collider + sockets + colours  (the mesh editor's Bake, generalized)
        v
 Preview (live)  /  Install (Catalog.replaceHandle under the render mutex)  /  Export (HWMS, GLB)
```

Shared services (one implementation, used by every studio): the document and `History` from the mesh editor, picking and gizmos ([mesheditor](mesheditor.md) sections 4.7 and 4.8), the pointer and gesture layer (section 6), brushes (section 7), knobs and presets (section 8), the part library and sockets (section 9), and the bake.

Per-domain code is limited to: the operation set, the recipe schema, the derived readouts, and the constraints. That is the whole difference between a vehicle studio and a nature studio.

| Shared | Specialized per studio |
| --- | --- |
| Document, undo and redo, library, presets, knobs | Recipe schema and parameter ranges |
| Pointer, gestures, camera, picking, gizmos | Which operations and brushes are offered |
| Cage and brush engine, symmetry | Cage layouts (a hull cage differs from a branch cage) |
| Sockets and snapping | Socket kinds (wheel, fan, wing, weapon, window module, branch anchor) |
| Bake, auto level of detail, auto collider, export | Derived numbers (mass and thrust, sap capacity, floor area) |

## 4. The studios

Each studio is a mode of the same shell. Every item below is an operation the player sees as a button, brush or slider.

### 4.1 Character studio

Folds in today's Character Designer and imported-part editor.
- **Operations:** body proportion sliders (height, build, head and limb ratios), armor plate placement on named body envelopes, hair clump strokes, face preset, surface paint by role (armor, skin, eyes, energy).
- **Brushes:** pull and smooth on armor plate cages; a hair-stroke brush that lays loft strands along a drawn curve (the existing loft supports this).
- **Automation:** plates fit to the body envelope, symmetry on by default, rig-fit for imported bodies ([mesheditor](mesheditor.md) section 4.11), collision and level of detail from the recipe.
- **Keeps the Designer's new structure:** the 35-field list is already split into tabs (Basics, Hair, Gear, Armor RGB, Style), and the studio shell keeps that tabbed layout and its Screens layout test.

### 4.2 Vehicle studio

Builds on `CarSpec` and the planned ship design bay.
- **Operations:** draw or pull a hull silhouette as a small cage (side and top profile), choose a hull family, snap fans, wings, nozzles, weapons and cockpits onto typed sockets, set paint zones.
- **Knobs:** length, width, stance, wing span, fan size (section 8).
- **Derived readouts:** mass, inertia, thrust-to-weight and handling numbers from the part budgets, updated live; the same numbers the flight model uses, so the preview does not lie.
- **Constraints:** parts only snap to compatible sockets; budgets (mass, power, part count) keep designs flyable.
- **Automation:** colliders from the hull cage, light strips and rotor pivots registered as sockets so the game can spin and light them (as `Designs` does today).

### 4.3 Nature studio

Builds on the tree genome, the L-system species and the nature plan ([nature upgrade](nature-upgrade.md)).
- **Operations:** species and genome sliders, a growth-direction brush (paint where the crown should reach; this is the existing "graft a growth target" idea made visible), a leaf-density brush, trunk flare and lean, rocks as a noise-displaced cage, flowers and shrubs as small recipes.
- **Previews:** the recipe in the real forest at three distances, with a triangle count and the level-of-detail ladder, so artists see the cost ([nature upgrade](nature-upgrade.md) records 12.2M triangles on the benchmark route).
- **Automation:** the recipe regenerates the skeleton on the CPU in milliseconds and re-uploads kilobytes ([mesheditor](mesheditor.md) section 4.14); far-distance meshes and impostor sources are baked automatically.
- **Output:** new species become data entries the scatterer can pick by niche.

### 4.4 City studio

Builds on the grafted-tower, bridge-road and district ideas in [world](../world.md) and the existing bridge tool.
- **Operations:** draw a building footprint, choose a floor-plate profile, stack facade modules (window, balcony, market bay, glass, stone), place graft anchors where branches or bridges attach, set district palette.
- **Brushes:** a skyline brush that raises and varies a row of footprints; a bridge-road drawing tool that snaps to anchors with the existing style set.
- **Automation:** facade tiling, window lights, structural collars where a tower meets a trunk, and colliders.
- **Relationship to authoring:** buildings are assets; placing them in a city is the scene and authored-cell work in [phase 15](scenes.md) and [engine features](engine-features.md) E6.

## 5. Node-based design, used for reuse and automation

Graphs are the storage form, not the first thing a player sees.
- **Op set per domain, fixed and small.** Geometry ops (primitive, loft along a curve, mirror, array, bevel, noise displace, merge), colour ops (surface role, gradient, palette pick) and parameter ops (knob, remap, random in range with a seed). A graph has at most 256 nodes and one output per asset.
- **Compile to a flat plan, as logic graphs do.** The compiled-graph design in [engine features](engine-features.md) E3 applies directly: validate every reference and reject cycles, then emit operands first; evaluation is a straight loop with fixed storage.
- **Cache per node.** Each node's result is keyed by its inputs and parameters; a slider change recomputes only the nodes downstream of it.
- **Sub-graphs are parts.** A part is a graph with exposed knobs and sockets; using it twice shares the definition and gives each use its own overrides. This is the reuse the owner asked for: a wing, a window module or a branch cluster is authored once.
- **Hidden by default.** Cards and sliders edit the same parameters; an "advanced" toggle shows the graph.

## 6. Input: mouse, pen, touch and controller

Define one pointer model in the engine's input layer so tools never ask what device they are on.
- **`PointerEvent`:** an id, a kind (mouse, pen, touch), a phase (down, move, up), a position and a pressure. Mouse and controller cursors produce the same events.
- **Gesture rules:** pen and mouse draw; touch navigates (one finger orbits, two pan and zoom) so a resting palm does not paint; a tool can ask for finger drawing, in which case two fingers navigate. A fixed four-pointer table, no allocation.
- **Sizing and layout:** touch targets of at least a stated minimum size at every interface scale, no hover-only controls, radial menus for tool choice, and a Screens-style test that every hit area meets the minimum.
- **Platform work (fork, upstream candidates):** pointer events with pressure from the platform layer. macOS pen pressure would come through the AppKit event APIs already present in the bindings; Windows pointer input is compile-checked only here. Report which backends were run; today none has been.

*Compiled* (the recogniser, with pen, one-finger and two-finger cases):

```zig
pub const PointerKind = enum { mouse, pen, touch };
pub const Phase = enum { down, move, up };
pub const PointerEvent = struct { id: u8, kind: PointerKind, phase: Phase, x: f32, y: f32, pressure: f32 = 1 };

pub const Gesture = union(enum) {
    none,
    /// A brush stroke sample: position and pressure.
    draw: struct { x: f32, y: f32, pressure: f32 },
    /// One-pointer camera orbit, in pixels since the previous event.
    orbit: struct { dx: f32, dy: f32 },
    /// Two touches: pan by the midpoint's movement and zoom by the change in their distance.
    pan_zoom: struct { dx: f32, dy: f32, scale: f32 },
};

/// Pens and the mouse draw. Touch navigates by default (one finger orbits, two pan and zoom),
/// which keeps a resting palm from painting; `touch_draws` lets a finger draw instead and then
/// two fingers navigate. No allocation: at most four pointers are tracked.
pub const Recognizer = struct {
    const Slot = struct { id: u8, kind: PointerKind, x: f32, y: f32, active: bool = false };
    touch_draws: bool = false,
    slots: [4]Slot = undefined,
    count: usize = 0,

    pub fn handle(self: *Recognizer, e: PointerEvent) Gesture {
        switch (e.phase) {
            .down => {
                if (self.count < self.slots.len) {
                    self.slots[self.count] = .{ .id = e.id, .kind = e.kind, .x = e.x, .y = e.y, .active = true };
                    self.count += 1;
                }
                return self.drawIfPointer(e);
            },
            .up => {
                for (self.slots[0..self.count], 0..) |s, i| if (s.id == e.id) {
                    self.slots[i] = self.slots[self.count - 1];
                    self.count -= 1;
                    break;
                };
                return .none;
            },
            .move => {
                const index = self.find(e.id) orelse return .none;
                const before = self.slots[index];
                const touches = self.touchCount();
                if (before.kind != .touch or (self.touch_draws and touches == 1)) {
                    self.slots[index].x = e.x;
                    self.slots[index].y = e.y;
                    return .{ .draw = .{ .x = e.x, .y = e.y, .pressure = e.pressure } };
                }
                if (touches >= 2) {
                    const other = self.otherTouch(index) orelse return .none;
                    const old_mid = .{ (before.x + other.x) / 2, (before.y + other.y) / 2 };
                    const old_distance = std.math.hypot(before.x - other.x, before.y - other.y);
                    self.slots[index].x = e.x;
                    self.slots[index].y = e.y;
                    const new_distance = std.math.hypot(e.x - other.x, e.y - other.y);
                    const new_mid = .{ (e.x + other.x) / 2, (e.y + other.y) / 2 };
                    const scale = if (old_distance > 1e-3) new_distance / old_distance else 1;
                    return .{ .pan_zoom = .{ .dx = new_mid[0] - old_mid[0], .dy = new_mid[1] - old_mid[1], .scale = scale } };
                }
                self.slots[index].x = e.x;
                self.slots[index].y = e.y;
                return .{ .orbit = .{ .dx = e.x - before.x, .dy = e.y - before.y } };
            },
        }
    }

    fn drawIfPointer(self: *Recognizer, e: PointerEvent) Gesture {
        if (e.kind != .touch or (self.touch_draws and self.touchCount() == 1)) {
            return .{ .draw = .{ .x = e.x, .y = e.y, .pressure = e.pressure } };
        }
        return .none;
    }
    fn find(self: *const Recognizer, id: u8) ?usize {
        for (self.slots[0..self.count], 0..) |s, i| if (s.id == id) return i;
        return null;
    }
    fn touchCount(self: *const Recognizer) usize {
        var n: usize = 0;
        for (self.slots[0..self.count]) |s| {
            if (s.kind == .touch) n += 1;
        }
        return n;
    }
    fn otherTouch(self: *const Recognizer, index: usize) ?Slot {
        for (self.slots[0..self.count], 0..) |s, i| if (i != index and s.kind == .touch) return s;
        return null;
    }
};

test "pen draws with pressure, one finger orbits, two fingers pinch and pan" {
    var r: Recognizer = .{};
    _ = r.handle(.{ .id = 1, .kind = .pen, .phase = .down, .x = 10, .y = 10, .pressure = 0.4 });
    const stroke = r.handle(.{ .id = 1, .kind = .pen, .phase = .move, .x = 12, .y = 11, .pressure = 0.7 });
    try std.testing.expectEqual(@as(f32, 0.7), stroke.draw.pressure);
    _ = r.handle(.{ .id = 1, .kind = .pen, .phase = .up, .x = 12, .y = 11 });

    _ = r.handle(.{ .id = 2, .kind = .touch, .phase = .down, .x = 100, .y = 100 });
    const orbit = r.handle(.{ .id = 2, .kind = .touch, .phase = .move, .x = 110, .y = 95 });
    try std.testing.expectEqual(@as(f32, 10), orbit.orbit.dx);
    try std.testing.expectEqual(@as(f32, -5), orbit.orbit.dy);

    _ = r.handle(.{ .id = 3, .kind = .touch, .phase = .down, .x = 210, .y = 95 }); // second finger
    const pinch = r.handle(.{ .id = 3, .kind = .touch, .phase = .move, .x = 310, .y = 95 }); // spread apart
    try std.testing.expectApproxEqAbs(@as(f32, 2), pinch.pan_zoom.scale, 1e-5); // 100 px apart became 200
    try std.testing.expectEqual(@as(f32, 50), pinch.pan_zoom.dx); // the midpoint moved right
    _ = r.handle(.{ .id = 3, .kind = .touch, .phase = .up, .x = 310, .y = 95 });
    try std.testing.expectEqual(@as(usize, 1), r.count);
}

test "a finger can draw when the tool asks, and a second finger then navigates" {
    var r: Recognizer = .{ .touch_draws = true };
    const down = r.handle(.{ .id = 1, .kind = .touch, .phase = .down, .x = 5, .y = 5 });
    try std.testing.expect(down == .draw);
    _ = r.handle(.{ .id = 2, .kind = .touch, .phase = .down, .x = 55, .y = 5 });
    const nav = r.handle(.{ .id = 2, .kind = .touch, .phase = .move, .x = 105, .y = 5 });
    try std.testing.expect(nav == .pan_zoom);
}
```

## 7. Brushes and shape tools

Shapes stay simple on purpose: a small control cage (tens of points) drives a lofted surface, so one gesture moves a whole region smoothly.
- **Pull, push, inflate, smooth and flatten** on the cage, with a smoothstep falloff (no creases) and symmetry across the mirror plane by default.
- **Draw a profile:** a pen stroke becomes a silhouette curve that the loft sweeps (hull side view, tower profile, branch cross-section).
- **Paint** surface roles and colours (the existing `Surface` roles from the mesh editor).
- **Stamp** library parts onto sockets, and **scatter** parts along a stroke (leaf clusters, windows, rivets) with a seed.
- Every stroke is one history entry (strokes coalesce), validated before it mutates.

*Compiled* (a symmetric pull brush with falloff, and socket snapping for modular parts):

```zig
pub const Vec3 = [3]f32;

/// Pull points within `radius` of `center` by `delta`, scaled by a smooth falloff. Shapes stay
/// simple: artists move a small cage, and the lofted surface follows. With `mirror_x`, the same
/// brush also acts at the mirrored center so a symmetric part stays symmetric.
pub fn pullBrush(points: []Vec3, center: Vec3, radius: f32, delta: Vec3, mirror_x: bool) void {
    applyPull(points, center, radius, delta);
    if (mirror_x) {
        applyPull(points, .{ -center[0], center[1], center[2] }, radius, .{ -delta[0], delta[1], delta[2] });
    }
}

fn applyPull(points: []Vec3, center: Vec3, radius: f32, delta: Vec3) void {
    for (points) |*p| {
        const dx = p[0] - center[0];
        const dy = p[1] - center[1];
        const dz = p[2] - center[2];
        const d = @sqrt(dx * dx + dy * dy + dz * dz);
        if (d >= radius) continue;
        const t = 1 - d / radius;
        const weight = t * t * (3 - 2 * t); // smoothstep: zero slope at both ends, so no creases
        for (0..3) |axis| p[axis] += delta[axis] * weight;
    }
}

test "a symmetric pull moves both sides together and leaves distant points alone" {
    var cage = [_]Vec3{ .{ 1, 0, 0 }, .{ -1, 0, 0 }, .{ 1.5, 0, 0 }, .{ -1.5, 0, 0 }, .{ 9, 0, 0 } };
    pullBrush(&cage, .{ 1, 0, 0 }, 2, .{ 0, 1, 0 }, true);
    try std.testing.expectApproxEqAbs(cage[0][1], cage[1][1], 1e-6); // mirrored pair stays level
    try std.testing.expect(cage[0][1] > cage[2][1] and cage[2][1] > 0); // falloff: nearer moves more
    try std.testing.expectApproxEqAbs(cage[2][1], cage[3][1], 1e-6);
    try std.testing.expectEqual(@as(f32, 0), cage[4][1]); // outside the radius
    try std.testing.expectEqual(@as(f32, 1), cage[0][0]); // x unchanged for a y pull
    // Without mirroring only the near side moves.
    var one = [_]Vec3{ .{ 1, 0, 0 }, .{ -1, 0, 0 } };
    pullBrush(&one, .{ 1, 0, 0 }, 2, .{ 0, 1, 0 }, false);
    try std.testing.expect(one[0][1] > 0 and one[1][1] == 0);
}
```

```zig
pub const SocketKind = enum(u3) { wheel, fan, wing, weapon, cockpit };
pub const Socket = struct { position: Vec3, kind: SocketKind };

/// Finds the nearest free host socket of the same kind within `reach` and returns the translation
/// that seats the part's socket on it. Incompatible kinds never snap, so a kit cannot be mis-built.
pub fn snap(part: Socket, hosts: []const Socket, taken: u64, reach: f32) ?struct { host: usize, move: Vec3 } {
    var best: ?usize = null;
    var best_distance = reach;
    for (hosts, 0..) |host, i| {
        if (host.kind != part.kind or (taken >> @intCast(i)) & 1 == 1) continue;
        const dx = host.position[0] - part.position[0];
        const dy = host.position[1] - part.position[1];
        const dz = host.position[2] - part.position[2];
        const d = @sqrt(dx * dx + dy * dy + dz * dz);
        if (d <= best_distance) {
            best_distance = d;
            best = i;
        }
    }
    const i = best orelse return null;
    return .{ .host = i, .move = .{ hosts[i].position[0] - part.position[0], hosts[i].position[1] - part.position[1], hosts[i].position[2] - part.position[2] } };
}

test "parts snap to the nearest compatible free socket only" {
    const hull = [_]Socket{
        .{ .position = .{ 1.3, 0.4, 1.3 }, .kind = .fan },
        .{ .position = .{ -1.3, 0.4, 1.3 }, .kind = .fan },
        .{ .position = .{ 0, 0.9, 0.2 }, .kind = .cockpit },
    };
    const fan: Socket = .{ .position = .{ 1.0, 0.6, 1.0 }, .kind = .fan };
    const hit = snap(fan, &hull, 0, 1.0).?;
    try std.testing.expectEqual(@as(usize, 0), hit.host);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), hit.move[0], 1e-6);
    try std.testing.expectEqual(@as(?usize, 1), if (snap(fan, &hull, 0b1, 4.0)) |s| s.host else null); // first taken: next fan socket
    try std.testing.expect(snap(.{ .position = .{ 0, 0.9, 0.2 }, .kind = .wing }, &hull, 0, 5.0) == null); // wrong kind
    try std.testing.expect(snap(fan, &hull, 0, 0.1) == null); // out of reach
}
```

## 8. Knobs, presets and light gamification

- **Knobs.** A knob is one 0 to 1 slider that drives several parameters through small piecewise curves, so "longer" lengthens the hull and spreads the fans together. Each studio ships a handful. Input is clamped and a rejected value changes nothing.
- **Presets and dice.** Named starting recipes per studio, and a "roll" that randomizes within each parameter's range from a seed, so artists iterate by choosing, not by building.
- **Gamified, optionally.** Challenges ("a hover car that tops 200 km/h within the mass budget", "a tree readable at 400 m under 30,000 triangles"), live budget meters, and tool unlocks tied to progress. These live in the creator's `Kit` (personal), never in shared progress. Whether and how to gate tools is an owner decision (section 12).

*Compiled* (a knob driving two parameters, with clamping and refusal of bad input):

```zig
pub const MapPoint = struct { at: f32, value: f32 };
pub const Mapping = struct { param: u8, points: [3]MapPoint }; // piecewise linear over three points

pub const Knob = struct {
    mappings: [4]?Mapping = .{ null, null, null, null },

    /// Writes every mapped parameter for a knob position in 0..1. Out-of-range input clamps, and a
    /// non-finite input is rejected before anything is written.
    pub fn apply(self: Knob, position: f32, params: []f32) error{InvalidKnob}!void {
        if (!std.math.isFinite(position)) return error.InvalidKnob;
        const t = std.math.clamp(position, 0, 1);
        for (self.mappings) |maybe| if (maybe) |m| {
            if (m.param >= params.len) return error.InvalidKnob;
        };
        for (self.mappings) |maybe| if (maybe) |m| {
            params[m.param] = if (t <= m.points[1].at)
                lerp(m.points[0], m.points[1], t)
            else
                lerp(m.points[1], m.points[2], t);
        };
    }
    fn lerp(a: MapPoint, b: MapPoint, t: f32) f32 {
        if (b.at <= a.at) return b.value;
        return a.value + (b.value - a.value) * std.math.clamp((t - a.at) / (b.at - a.at), 0, 1);
    }
};

test "one length knob drives hull length linearly and fan spread with an eased middle" {
    const length_knob: Knob = .{ .mappings = .{
        .{ .param = 0, .points = .{ .{ .at = 0, .value = 3.5 }, .{ .at = 0.5, .value = 4.5 }, .{ .at = 1, .value = 5.5 } } },
        .{ .param = 1, .points = .{ .{ .at = 0, .value = 1.0 }, .{ .at = 0.5, .value = 1.6 }, .{ .at = 1, .value = 1.8 } } },
        null,
        null,
    } };
    var params = [_]f32{ 0, 0 };
    try length_knob.apply(0.5, &params);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), params[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), params[1], 1e-5);
    try length_knob.apply(2, &params); // clamps to 1
    try std.testing.expectApproxEqAbs(@as(f32, 5.5), params[0], 1e-5);
    const before = params;
    try std.testing.expectError(error.InvalidKnob, length_knob.apply(std.math.nan(f32), &params));
    try std.testing.expectEqualSlices(f32, &before, &params); // a rejected input changes nothing
    var small = [_]f32{0}; // param 1 does not exist: refuse the whole write
    try std.testing.expectError(error.InvalidKnob, length_knob.apply(0.5, &small));
    try std.testing.expectEqual(@as(f32, 0), small[0]);
}
```

## 9. Reuse, automation and performance

- **Part library.** A per-player library of recipes and parts; entries are versioned documents with a content hash. A design references parts by id, so editing a part updates every use.
- **Instancing.** Identical parts share one mesh handle and differ by transform and tint, using the renderer's existing instanced draws ([scale](../scale.md)).
- **Automatic level of detail.** Lofted and cage shapes get coarser levels by lowering ring and segment counts; no general mesh decimator is needed. Each recipe bakes a near, mid and far mesh.
- **Automatic colliders.** Boxes or convex pieces from the cage; walkable surfaces keep their current rules.
- **Budgets (targets, to be measured).** An edit preview well under one frame of CPU for a typical asset (a few thousand vertices); bakes and exports run on a worker; the frame path allocates nothing; graph evaluation recomputes only changed nodes. The mesh editor benchmark shows incremental part updates in microseconds against tens of milliseconds for a full recolour (`build modifier-bench`), which is the pattern to keep.

## 10. Ownership, saves and later interchange

- **Where designs live:** in the creator's library, saved with their `Kit` document (a `Save.format_version` bump with a migration and a round-trip test, per the save rules). A teammate gets a copy through an explicit share action, not by default.
- **Recipe file (sketch, not compiled):**

```json
{
  "format": 1,
  "kind": "vehicle",
  "id": "hovercar.rook-7",
  "parameters": { "hull_length": 4.6, "wing_span": 2.2, "fan_radius": 0.55 },
  "knobs": [ { "name": "length", "position": 0.5 } ],
  "graph": { "nodes": [], "output": 0 },
  "sockets": [ { "kind": "fan", "position": [1.3, 0.4, 1.3] } ],
  "surface_roles": { "paint": [0.2, 0.5, 0.7] },
  "parts": [ "part.wing.swept-2" ],
  "source_hash": "blake3:..."
}
```

- **Interchange with the sibling web engine** is a later, post-feature-freeze standard (see [interchange](interchange.md)). Two choices now make it cheap: recipes use stable string ids and carry no engine-internal indices, and the bake can export glTF binary (`GLB`), which web engines read natively ([mesheditor](mesheditor.md) section 4.13).

## 11. Plan

Sizes: S under a day, M a few days, L about a week. The studios are a user-directed tools track; per [AGENTS.md](../../AGENTS.md) they must not displace the MVP gate (the first city's investigation content and the per-city mission quota in [next steps](next-steps.md)). Time-box them.

### S0. Prerequisites (S)

The green suite and the explicit save floor are done ([next steps](next-steps.md#revised-next-steps) steps 0 and 1). Still needed: the mesh editor's M4 library ([mesheditor](mesheditor.md)); the studio library is the M4 library generalized.

### S1. Studio shell and shared services (M)

1. Extract the mesh editor's document, `History` and `Bake` behind a `StudioState` struct that owns no window (the `MeshEditorState` sketch in [mesheditor](mesheditor.md) section 4.9), so it is testable headless.
2. Define the recipe format v1 (section 10), a validator that rejects without mutating, and a v1 reader/writer test with a checked-in fixture.
3. Add knobs and presets (section 8) as data.
4. Add the part library and socket model; socket kinds are an enum per studio.

**Tests:** recipe round trip; rejected edit leaves the document identical; undo then redo is the identity; knob refusal changes nothing.
**Acceptance:** the existing imported-part editor runs on the shell with no behaviour change.

### S2. Pointer model and gestures (M)

1. Add `PointerEvent` and the recogniser (section 6) to `engine/Input.zig`; make the mouse and the controller cursor produce pointer events.
2. Route the Designer and the mesh editor panels through pointer events.
3. Add the hit-size rule and a layout test.

**Tests:** the recogniser cases above; every creator and studio hit area meets the minimum size at 720p and 2560x1600.
**Acceptance:** everything that works with the mouse works with the controller cursor, unchanged.

### S3. Platform pointer backends (M to L, fork work)

Pen pressure on macOS through the AppKit bindings; Windows pointer input. Keep each patch small and recorded in `vendor/mach/FORK.md`; validate on the backend you can run and say that the rest are compile-only.
**Acceptance:** a pen stroke reports pressure on a machine that has a pen; the matrix says which platforms ran.

### S4. Brushes, symmetry and the cage (M)

Implement the cage and the brush set (section 7) in a shared module; wire stroke coalescing into `History`.
**Tests:** falloff monotone, symmetry exact, strokes undo as one entry, a validated stroke never leaves non-finite points.

### S5. Vehicle studio (L) *(recommended first domain)*

Reason: `CarSpec` is already a clean parameter set, the socket model is needed for the planned ship design bay, and the derived readouts reuse the flight model. Steps: hull cage from `HullSpec`, sockets for fans, wings, nozzles and weapons, knobs, live mass and thrust readouts, bake to the existing car meshes.
**Tests:** the studio reproduces each current `Designs` entry exactly; budget violations are refused; sockets reject incompatible parts.
**Acceptance:** a player fabricates a custom car from the studio and flies it in the real game.

**Status (2026-10-15): the headless core is implemented; the studio is not yet playable.** Vehicles first, as the owner chose.

Built in `src/studio/`:
- `History.zig`, `Knob.zig`, `Brush.zig`: the shared services. Bounded undo and redo that merges a drag into one step; macro knobs; a smoothstep brush on a one-dimensional station cage that clamps to a valid range.
- `VehicleRecipe.zig`: a versioned recipe (`format` 1). `fromDesign` reproduces the three shipped cars bit for bit (`toSpec(fromDesign(d))` equals `Designs.spec(d)` and builds the same mesh and mass). Twelve parameters have ranges; a nine-station cage scales the hull's height and width between 0.6 and 1.5 of the base; JSON `encode` and `decode` reject unknown fields, out-of-range values and cross-field errors (boost below cruise) before returning a recipe; `Studio` validates a copy of the recipe before committing each edit, and offers knobs, the brush, undo and redo; `evaluate` builds the real car and reports mass, lift ratio, thrust to weight and triangle count, using the game's own rule that four fans must lift 1.35 times the weight.
- `VehiclePreview.zig` plus `asset-compiler vehicle-recipe` and `vehicle-preview`: a CPU three-view cel-shaded review sheet.

Checked: 10 new tests, plus five deliberate breakages of the code that the tests caught (never skipping a factor of 1, dropping the boost rule, never merging a stroke, an always-true lift rule, and skipping validation in `set`; one of them first survived because a test used an out-of-range value, which is now fixed). A fuzz test builds 24 recipes at and between the cage and parameter extremes, all finite. The gate passes: 451 of 451 on the default compiler and 0.17, and a clean Metal smoke. The three shipped cars and an edited custom car ("ROOK-7": longer, cabin raised, wider wing, bigger fans, new paint) were rendered and inspected; building the car, rendering three views and writing the PNG takes about 70 ms in ReleaseFast.

Findings and what is missing:
1. **Not playable yet.** `Designs.Design` is a fixed enum of three cars used by the garage (`Garage.max_cars = Designs.count`), the fabricator's output, `Progress.vehicles` (a `u8` bitmask), `Save.CarState.design` and the per-design catalog meshes. A custom car needs ids instead of an enum, dynamic mesh registration, and a `Save.format_version` bump with a migration.
2. **Mass ignores shape.** The car's mass is a fixed budget per part scaled onto the mesh's mass distribution, so making ROOK-7 longer and taller left it at exactly 1,046 kg, the skimmer's mass. The brush cannot create real trade-offs until hull mass follows the shape (for example proportional to the hull's volume).
3. **No UI or pointer layer yet**, and no sockets: the four fan pads are four numbers (`pad_x`, `pad_y`, `pad_z_front`, `pad_z_rear`), not snapping parts.
4. **The cage scales the existing nine stations only;** drawing a silhouette profile is future work.
5. The review sheet's top view crops a very long car slightly.

Next vehicle slices: V2 shape-derived hull mass; V3 custom design ids, registry and save migration; V4 a studio panel in the garage with knobs and the brush on mouse and controller; V5 sockets and snapping; V6 the pointer model with pen and touch (S2 and S3).

### S6. Nature studio (L)

Genome sliders, the growth-direction brush, leaf density, species as data entries, the cost preview. Depends on the nature plan's phases 5a to 5d. **Acceptance:** a new tree species appears in the forest by data and its triangle count and level-of-detail ladder are shown in the studio.

### S7. City studio (L)

Footprint, floor-plate, facade modules, graft anchors, skyline and bridge brushes. Depends on [phase 15](scenes.md) for placement. **Acceptance:** one authored building appears in the first city through an authored cell.

### S8. Graph view and advanced reuse (M)

The node view over the same data, sub-graph parts with exposed knobs, and per-node caching. **Tests:** cache hits skip recomputation, a cycle is rejected, graph results equal the direct recipe for every shipped preset.

### S9. Export and interchange hooks (M)

`GLB` export from the bake (round-trip test in [mesheditor](mesheditor.md) section 4.13) and the stable-id rules in [interchange](interchange.md). **Acceptance:** an exported vehicle opens in a glTF viewer with the right shape and colours.

### S10. Gamification layer (S to M, optional)

Challenges, budget meters and unlocks stored in each player's `Kit`.

## 12. Decisions for the project owner

1. **First domain:** vehicles first (recommended), or nature or city first.
2. **Touch hardware:** which devices matter first (a Windows touch display, an iPad as a pen display, a pen tablet), since platform support differs and none has been run here.
3. **Gamification:** purely optional challenges, or tool unlocks tied to story progress.
4. **Sharing:** whether a design can be copied to a teammate in the same session only, or kept in a shared local library.
5. **Time-box:** how much of the studio track runs before the first city's investigation content (the MVP gate).

## 13. Risks

| Risk | Mitigation |
| --- | --- |
| Touch and pen cannot be tested here | Build the pointer layer and recogniser headless first (S2); report each platform as run or compile-only (S3) |
| A "simple" brush set becomes an open-ended modeler | Specialized operations per studio; reject operations that do not serve the asset kind |
| Five studios duplicate work | One shell and shared services (S1); a studio is a recipe schema plus an operation set |
| Graphs scare players | Hidden by default; cards and knobs are the interface |
| Performance of live edits | Per-node caching, incremental bake, background export; measured before widening |
| Scope against the MVP | Time-box; the quota and investigation work in [next steps](next-steps.md) come first |

## 14. Reference

Sources read: [loft.zig](../../src/character/loft.zig), [curve.zig](../../src/character/curve.zig), [Profile.zig](../../src/game/Profile.zig), [car.zig](../../src/vehicle/car.zig), [Designs.zig](../../src/vehicle/Designs.zig), [EnemyDesign.zig](../../src/game/EnemyDesign.zig), [Arbor.zig](../../src/procedural/Arbor.zig), [LSystem.zig](../../src/procedural/LSystem.zig), [District.zig](../../src/procedural/District.zig), [Modifiers.zig](../../src/asset/Modifiers.zig).

```sh
python3 tools/zig.py test studio_examples.zig                              # default pair: 5 of 5
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py test studio_examples.zig  # 0.17: 5 of 5
```
