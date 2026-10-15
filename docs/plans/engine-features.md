# Engine feature review: Unreal-style systems against Heavy Water

**Status:** proposed, 2026-10-14. Nothing here is built. This reviews a list of Unreal-style engine features (visual scripting, an ability system, behavior trees, Nanite and Lumen equivalents, a material editor, live coding, world partition, a sequencer, a Chaos-style physics engine, animation blueprints and motion matching, and actor replication) against the game as it exists, says which fit and which do not, and orders the ones that do. The [roadmap](../roadmap.md) stays the single plan; the review of the earlier outside advice is in [alignment](alignment.md#review-of-external-advice-2026-10-01).

**Audience:** engineers and coding agents working in this repository. Each phase names the files it touches, the tests it needs and the acceptance it must meet.

**How this was checked.** Claims about the game come from reading the code and docs on 2026-10-14; where a number is quoted it was measured that day by the gates in [next steps](next-steps.md#technical-review--2026-10-14). The four Zig blocks labelled *compiled* are standalone files that passed `zig test` on the default compiler (`0.16.0-dev.3142+5ccfeb926`) and on `HEAVYWATER_ZIG_CHANNEL=0.17` (4 of 4 tests each). They illustrate the design against the repository's real data shapes; they are not committed code.

## 1. Verdicts

| # | Proposed feature | What the game has now | Fit | Verdict |
| --- | --- | --- | --- | --- |
| 1 | Blueprint-style visual scripting compiled by `comptime` | Machine blueprints wire 17 device kinds, including a `logic` device (JSON node lists, no loops or functions) and a `script` device (sandboxed WebAssembly, about 800 ns a call) | Partial: the need is real, the mechanism is not | **Adopt, reshaped:** compile authored graphs to a validated flat program ([E3](#e3-logic-graph-v2-compiled-node-graphs)) |
| 2 | Gameplay Ability System | `Specials` (a `Kind` enum, 13 `Mechanic`s, an `Info` table of cost, cooldown, damage and so on), 78 hero powers, per-player `Kit`, 100 energy | Strong: loot and powers are the MVP's hack-and-slash core | **Adopt, small:** tags, attributes and effects ([E1](#e1-ability-core-tags-attributes-effects)) |
| 3 | Behavior trees and an environment query system | `ai/Hive.zig` (109 lines) and inline state switches in `Enemies.zig` (10 enemy kinds, 24-unit cap) | Good for new roles; no case to rewrite what works | **Adopt, small:** reactive trees and scored queries ([E2](#e2-behavior-trees-and-queries)) |
| 4 | Nanite-style virtualized geometry | CPU cell culling, instanced draws, shader-side frustum rejection, indirect draws in the fork; no shader atomics | Poor: the stylized assets and the Mach limits both rule it out | **Reject.** Solve the forest's 12.2M triangles with ordinary level of detail ([nature plan](nature-upgrade.md)) |
| 5 | Lumen-style global illumination | A cel ramp with hemispheric ambient and rim light; no shadows yet | Poor: contradicts the art direction and the engine limits | **Reject.** Shadows and occlusion come first ([nature plan](nature-upgrade.md) Phase 6) |
| 6 | Node-based material editor | WGSL stages spliced onto a shared prelude; materials as tags and parametric `CelStyle` data | Later: the data comes first | **Defer** ([E7](#e7-material-data-then-a-graph)) |
| 7 | Hot reload and live coding | `-Dhot-reload` reloads models, blueprints and mod scripts on a worker | Partial: the data path exists; reloading engine code does not fit | **Extend data and script reload; reject dynamic-library live coding** |
| 8 | World partition and spatial streaming | A chunk streamer (128 m chunks, 7x7 generation, 5x5 render), a saved-modification overlay, a deterministic infinite world | Partial: authored cells and a far field are missing | **Adopt through the scenes plan** ([E6](#e6-authored-cells-and-the-far-field)) |
| 9 | Sequencer and cinematics | Fixed review cameras (`showcase`), a fly-through, audio cue plumbing, no timeline | Useful for the story chapters | **Adopt, small** ([E4](#e4-cinematic-tracks)) |
| 10 | Deterministic physics (Chaos-class) | Native Zig physics: boxes, up to eight oriented rigid boxes, triangle meshes, vehicles, a character controller, on a deterministic 60 Hz step | Mostly done; ragdolls missing | **Adopt ragdolls only;** SIMD only if a profile asks ([E5](#e5-animation-graph-ik-and-ragdolls)) |
| 11 | Animation blueprints, IK, motion matching | Two-bone IK and look-at (`character/ik.zig`), spring chains, a crossfading motion controller, GPU dual-quaternion skinning; phase 14 planned | Strong for the first two; motion matching needs data we lack | **Adopt phase 14 and foot IK; defer motion matching** |
| 12 | ECS-native actor replication | A phase 16 plan: listen server, input commands, 30 Hz snapshots, prediction, interpolation | Strong, without an ECS | **Adopt the compression ideas inside phase 16** ([E8](#e8-networking-additions)) |

## 2. Premises in the list that do not hold here

1. **There is no ECS.** The list assumes Mach's entity component system. This fork and the game have none, and [next steps](next-steps.md#review-of-external-performance-suggestions--2026-10-11) already decided to keep fixed arrays and focused Zig systems unless a measured entity-iteration bottleneck says otherwise. Every proposal below uses fixed-capacity per-actor structs instead.
2. **Mach's WebGPU path lacks what the rendering items need.** Shader atomics are unimplemented in the WGSL compiler, timestamp queries and texture-to-buffer readback are gaps, and the fork exposes no mesh shaders, work graphs or GPU-built command buffers (see [alignment](alignment.md#mach-tracking)). GPU-driven geometry and GI built on those are not available, and GPU time cannot be measured.
3. **`comptime` cannot compile content that players and modders author at run time.** Graphs and scripts live in saves and mods. They must be data, validated before use. `comptime` does fit built-in content (a comptime-checked behavior tree for the trooper).
4. **The art direction is a cel-shaded, painterly, no-bloom look** ([visual direction](visual-direction.md)). Features whose point is photographic fidelity are not goals.
5. **Determinism and saves constrain everything.** Systems run on the fixed 60 Hz step, allocate nothing per frame, validate before they mutate, and follow the save-contract rules in [AGENTS.md](../../AGENTS.md).
6. **A native Zig dependency is still a dependency.** The list suggests `zmath`. The repository owns its math and keeps dependencies vendored with provenance; use `@Vector` from the standard library if SIMD is ever needed.

## 3. Analysis by feature

### 3.1 Visual scripting and logic

**Have.** A machine is a blueprint of devices wired by signals: 17 kinds including `logic`, `script`, `proximity`, `latch` and `actuator`. The `logic` device evaluates a small JSON node list with one step of latency and no loops or functions. The `script` device calls an export of a sandboxed WebAssembly module with four signals and the world time and expects a finite number back; the interpreter has fuel, memory and depth limits. [Scripting](../scripting.md) records why WebAssembly was chosen (native Zig, deterministic, sandboxed, authorable) and measured it at about 800 ns a call.

**Gap.** Authoring a non-trivial circuit means writing and compiling a WebAssembly module. There is no graph editor, and the `logic` node list is too small to replace scripts.

**Analysis.** The pasted claim is that a node editor can compile graphs "by `comptime`" with no runtime cost. That holds only for graphs known when the game is built. Player and mod graphs arrive at run time, so the right shape is the same one the WebAssembly path already takes: validate, then run a tiny allocation-free program. A flat register program evaluates a few operations in tens of nanoseconds, is deterministic, and cannot hang or escape. Compiling graphs to WebAssembly would add a code generator for little gain.

**Recommendation.** Extend `logic` into compiled node graphs (E3). Keep WebAssembly for anything that needs real code.

### 3.2 Ability system

**Have.** `game/Specials.zig` defines a `Kind` per power, a `Mechanic` (grenade, sentry, shield, blink, slam, lance, launch, aura, field, cone, heal, chain, vanish) and an `Info` record of label, cost, cooldown, damage, radius, stun, push, lift, time, count and colour. Heroes carry three powers and a passive (health, saber weight, energy regeneration, run speed). Energy is a fixed 100. Each player's gear, wallet and pets live in their `Kit`.

**Gap.** There are no tags, no attributes with modifiers and no effect records. Stun, shield and burn are written into each mechanic, and passives are hard-coded per hero, so a new buff, a gear bonus or a loot affix means editing mechanics.

**Analysis.** This is the highest-value item on the list for this game. The MVP loop promises "loot for each player", and loot needs a uniform way to change attributes (health, run speed, damage scale) from gear, pets, hero passives, suit upgrades and timed effects, with stacking that is deterministic and explainable. The pasted idea of tag-and-attribute abilities fits, without an ECS: an `Actor` struct per player or enemy holding base attributes, a small fixed array of active effects and a tag set.

**Recommendation.** Build the core in E1 and move one mechanic family at a time onto it. Effects are transient (not saved); gear modifiers come from the saved `Kit` and are re-applied at load, so the save format changes only when loot affixes are added.

### 3.3 Behavior trees and queries

**Have.** `ai/Hive.zig` holds the faction's construction and corruption; unit behavior is spread across `Enemies.zig` (ten kinds: drone, sentinel, trooper, skirmisher, bulwark and the Scalari scout, stinger, titan, miner and hybrid), `Frontier.zig` and `Skies.zig` as state switches. Wounded troopers already seek blocked positions and melee or throw, with the logic inline.

**Gap.** There is no shared framework, and the modular Scalari frames (`EnemyDesign.zig`) will multiply roles.

**Analysis.** A tree is worth it where roles recombine, not as a rewrite of working units. Pitfalls matter more than the idea: a tree that resumes at its running child stops re-checking higher-priority conditions, so a chasing unit never switches to attacking. The reactive form below re-evaluates from the root each tick and keeps multi-tick progress in the unit, which also makes interruption free of cleanup. The environment query system reduces to a scored sample of candidate points (cover, flank, retreat) into a fixed array, which troopers already do informally.

**Recommendation.** E2: a small tree library and a query helper, first used for one new role, then for troopers behind their existing tests.

### 3.4 Rendering: virtualized geometry, global illumination, materials

**Virtualized geometry.** Micro-triangle software rasterization needs 64-bit atomics and GPU-driven culling, which Mach cannot do, and the assets are stylized meshes, not scans. The measured problem is different and ordinary: the forest submits 12,248,988 triangles on the nature route, six and a half times the 2026-10-13 figure, with unchanged CPU time. Per-distance level of detail, instanced skeleton-driven trees and impostors ([nature plan](nature-upgrade.md) phases 5d and 5f, [mesheditor](mesheditor.md) section 4.14) are the answer. **Reject** the Nanite equivalent; **adopt** level of detail.

**Global illumination.** Signed-distance-field GI and screen-space probes are heavy, need atomics and readback for good results, and push toward a photographic look the direction avoids. The visible lighting gaps are the missing shadows and occlusion, which the nature plan's Phase 6 covers (a sun cascade if the engine allows it, otherwise a canopy shadow field, plus baked vertex occlusion). **Reject** GI.

**Material editor.** Materials are a base colour plus procedural looks selected by tags in shared and per-stage WGSL (terrain, water, foliage, skin), and characters use the parametric `CelStyle` struct. Generated WGSL must respect the Mach compiler's limits (no `cross`, `pow` or `reflect`; one entry point per stage per module; reserved words), which the shared prelude already works around. A graph editor therefore belongs after materials are data (E7).

### 3.5 Tooling: hot reload, streaming, cinematics

**Hot reload.** `asset/HotReload.zig` reloads three kinds (`model`, `blueprint`, `script`) on a worker and applies results under the render mutex, and a bad edit never replaces the working asset. Reloading engine code as a dynamic library would have to cross Mach's main-thread module state (copied on an 8 MB stack), the render mutex and every pointer into game state; the cost and risk are high and a mod script already gives sub-second iteration for gameplay values. Extend reload to new data tables (abilities, trees, graphs, materials) instead.

**World streaming.** The streamer already pages 128 m chunks (active 3x3, render 5x5, generation 7x7) on a background worker with cancellation, fixed pools (49 CPU, 25 GPU) and an upload budget; saved removals overlay generated content by `(chunk, local_id)`. What Unreal's partition adds is authored content in cells and a coarse far field. The first belongs to the scenes plan ([phase 15](scenes.md)); the second to the nature plan's Phase 7. There is no ECS data to stream.

**Sequencer.** There are only fixed review cameras and benchmark fly-throughs. The story ([Story.md](../Story.md)) and the city liberation loop need short authored sequences: a camera path, audio cues, dialogue, flags and spawns, skippable, deterministic, and safe to save mid-sequence.

### 3.6 Physics and animation

**Physics.** `physics/` is native Zig and deterministic: a box world, up to eight oriented rigid boxes (`Rigid.zig`), triangle meshes, vehicles and a character controller. Frontier benchmark physics cost today is 0.594 ms mean and 1.024 ms max per step (measured), so SIMD is not a current need. There are no ragdolls, joints or destruction. Hack-and-slash feedback benefits most from ragdolled defeats; destruction does not.

**Animation.** `character/` has forward-kinematic poses, analytic two-bone IK and look-at, spring chains, a motion controller that crossfades and retargets clips, and GPU dual-quaternion skinning. [Phase 14](skeletal-animation.md) plans the `HWSK` and `HWAN` formats, a controller table, blend spaces and attachments. State-machine blending and foot IK are within that plan. Motion matching needs a large, consistent clip database; the [animation capture](animation-capture.md) plan could eventually build one, so defer it.

### 3.7 Networking

[Phase 16](networking.md) already specifies the authoritative listen server, input commands, 30 Hz snapshots, client-side prediction with replay and 100 ms interpolation. The pasted additions that are missing there are packet-size measures: quantized and delta-compressed snapshots, and interest management by chunk. Unreal-style per-variable replication and RPC layers are not needed: the game's actions already go through validators and reliable ordered messages.

## 4. Plan

Order follows the MVP rules in [AGENTS.md](../../AGENTS.md): hack-and-slash depth and per-player loot first, exploration and story tooling next, engine phases as their own plans.

### E0. Prerequisites

Do [next steps](next-steps.md#revised-next-steps) steps 0 and 1 first: a green suite (four failing tests) and an explicit save-format policy. Every phase below adds tests and some touch saves.

### E1. Ability core: tags, attributes, effects

**Size:** M. **Depends on:** E0. **Files:** new `game/Abilities.zig` (the core below), then `Specials.zig`, `Heroes.zig`, `Combat.zig`, `Kit.zig`.

1. Add the core with fixed capacities: a 64-bit `TagSet`, an `Attribute` enum (health, energy, run speed, damage scale), `Effect` records (duration, up to three modifiers, granted, required and blocking tags) and an `Actor` with at most eight active effects. Stacking order is fixed: additive modifiers, then multiplicative.
2. Validate before mutating: an activation checks blocking tags, the cooldown tag, energy and capacity first, then spends and applies, so a refused use changes nothing (the existing repository rule for loads and purchases).
3. Express cooldowns as effects that grant a cooldown tag. Replace the per-slot `cooldowns: [3]f32` and the separate `lance`, `aura` and `hidden` timers in `Specials.Player` with it, keeping the same timings; the `Info` table stays the data source for cost, cooldown and tuning.
4. Move one mechanic family at a time: shields and stuns first (they are already tag-like), then auras and fields, then damage-over-time.
5. Route hero passives (health, saber weight, energy regeneration, run speed) and suit upgrades through base attributes and modifiers instead of special cases.
6. Add loot affixes as per-gear modifier lists stored in the player's `Kit`. This is the first saved change: bump `Save.format_version`, migrate the previous format with empty affix lists, and add a round-trip test.
7. Do not save active effects; clear them at load (like seated and piloting state).

**Tests (each must be able to fail):** stacking order and exact values; refused activation leaves the actor byte-identical; cooldown tag gates reuse; stun blocks; effects expire on the fixed step; capacity overflow returns an error and changes nothing; a regression test that the migrated Specials produce the same damage and cooldown numbers as before for every `Kind`.

**Acceptance:** all current powers behave identically in the Metal smoke's combat and heroes stages, and one new timed buff is added without touching a mechanic.

*Compiled* (the core, with its test):

```zig
pub const Tag = enum(u6) { stunned, shielded, burning, cooldown_blink, cooldown_grenade, rooted };

pub const TagSet = struct {
    bits: u64 = 0,
    pub fn with(self: TagSet, tag: Tag) TagSet {
        return .{ .bits = self.bits | (@as(u64, 1) << @intFromEnum(tag)) };
    }
    pub fn has(self: TagSet, tag: Tag) bool {
        return self.bits & (@as(u64, 1) << @intFromEnum(tag)) != 0;
    }
    pub fn hasAny(self: TagSet, other: TagSet) bool {
        return self.bits & other.bits != 0;
    }
    pub fn hasAll(self: TagSet, other: TagSet) bool {
        return self.bits & other.bits == other.bits;
    }
    pub fn merge(self: TagSet, other: TagSet) TagSet {
        return .{ .bits = self.bits | other.bits };
    }
};

pub const Attribute = enum { health, energy, run_speed, damage_scale };
// The last variant fixes the count without reflection; in the repository use `enum_compat.fields`.
pub const attribute_count: usize = @as(usize, @intFromEnum(Attribute.damage_scale)) + 1;

pub const Op = enum { add, mul };
pub const Modifier = struct { attribute: Attribute, op: Op, magnitude: f32 };

/// A data record: what it changes, for how long, which tags it grants, and what gates it.
/// `duration` 0 applies the modifiers once and stores nothing; `inf` lasts until removed.
pub const Effect = struct {
    duration: f32 = 0,
    modifiers: [3]?Modifier = .{ null, null, null },
    grants: TagSet = .{},
    requires: TagSet = .{}, // all of these must be present on the target
    blocked_by: TagSet = .{}, // none of these may be present
};

pub const Ability = struct {
    cost: f32,
    cooldown: Effect, // grants a cooldown tag for a duration
    cooldown_tag: Tag,
    effect: Effect,
    blocked_by: TagSet = TagSet.with(.{}, .stunned),
};

pub const Actor = struct {
    pub const max_active = 8;
    base: [attribute_count]f32 = @splat(0),
    active: [max_active]struct { effect: Effect, remaining: f32 } = undefined,
    active_count: usize = 0,
    tags: TagSet = .{},

    /// Base value, then every additive modifier, then every multiplicative one: stacking order
    /// is fixed so the same effects always give the same number.
    pub fn current(self: *const Actor, attribute: Attribute) f32 {
        var add: f32 = 0;
        var mul: f32 = 1;
        for (self.active[0..self.active_count]) |entry| {
            for (entry.effect.modifiers) |maybe| if (maybe) |m| if (m.attribute == attribute) switch (m.op) {
                .add => add += m.magnitude,
                .mul => mul *= m.magnitude,
            };
        }
        return (self.base[@intFromEnum(attribute)] + add) * mul;
    }

    pub fn apply(self: *Actor, effect: Effect) error{ Blocked, Full }!void {
        if (!self.tags.hasAll(effect.requires) or self.tags.hasAny(effect.blocked_by)) return error.Blocked;
        if (effect.duration == 0) { // instant: change the base once
            for (effect.modifiers) |maybe| if (maybe) |m| {
                const slot = &self.base[@intFromEnum(m.attribute)];
                slot.* = switch (m.op) {
                    .add => slot.* + m.magnitude,
                    .mul => slot.* * m.magnitude,
                };
            };
            return;
        }
        if (self.active_count == max_active) return error.Full;
        self.active[self.active_count] = .{ .effect = effect, .remaining = effect.duration };
        self.active_count += 1;
        self.refreshTags();
    }

    /// Validate everything first; only then spend energy and apply, so a refused use changes nothing.
    pub fn activate(self: *Actor, ability: Ability) error{ Blocked, NotEnoughEnergy, OnCooldown, Full }!void {
        if (self.tags.hasAny(ability.blocked_by)) return error.Blocked;
        if (self.tags.has(ability.cooldown_tag)) return error.OnCooldown;
        if (self.base[@intFromEnum(Attribute.energy)] < ability.cost) return error.NotEnoughEnergy;
        if (self.active_count + 2 > max_active) return error.Full;
        self.base[@intFromEnum(Attribute.energy)] -= ability.cost;
        try self.apply(ability.effect);
        try self.apply(ability.cooldown);
    }

    pub fn step(self: *Actor, dt: f32) void {
        var kept: usize = 0;
        for (self.active[0..self.active_count]) |entry| {
            var e = entry;
            e.remaining -= dt;
            if (e.remaining > 0) {
                self.active[kept] = e;
                kept += 1;
            }
        }
        self.active_count = kept;
        self.refreshTags();
    }

    fn refreshTags(self: *Actor) void {
        var tags: TagSet = .{};
        for (self.active[0..self.active_count]) |entry| tags = tags.merge(entry.effect.grants);
        self.tags = tags;
    }
};

test "abilities gate on tags, cost and cooldown, and effects stack in a fixed order" {
    const shield: Ability = .{
        .cost = 40,
        .cooldown_tag = .cooldown_grenade,
        .cooldown = .{ .duration = 12, .grants = TagSet.with(.{}, .cooldown_grenade) },
        .effect = .{ .duration = 8, .grants = TagSet.with(.{}, .shielded), .modifiers = .{ .{ .attribute = .health, .op = .add, .magnitude = 80 }, .{ .attribute = .run_speed, .op = .mul, .magnitude = 0.9 }, null } },
    };
    var actor: Actor = .{};
    actor.base[@intFromEnum(Attribute.health)] = 100;
    actor.base[@intFromEnum(Attribute.energy)] = 100;
    actor.base[@intFromEnum(Attribute.run_speed)] = 10;

    try actor.activate(shield);
    try std.testing.expect(actor.tags.has(.shielded));
    try std.testing.expectEqual(@as(f32, 180), actor.current(.health));
    try std.testing.expectApproxEqAbs(@as(f32, 9), actor.current(.run_speed), 1e-5);
    try std.testing.expectEqual(@as(f32, 60), actor.base[@intFromEnum(Attribute.energy)]);
    try std.testing.expectError(error.OnCooldown, actor.activate(shield));
    try std.testing.expectEqual(@as(f32, 60), actor.base[@intFromEnum(Attribute.energy)]); // refused: unchanged

    actor.step(9); // the shield (8 s) is gone, the cooldown (12 s) is not
    try std.testing.expect(!actor.tags.has(.shielded) and actor.tags.has(.cooldown_grenade));
    try std.testing.expectEqual(@as(f32, 100), actor.current(.health));
    actor.step(4);
    try std.testing.expect(!actor.tags.has(.cooldown_grenade));

    // A stun tag blocks activation outright.
    try actor.apply(.{ .duration = 2, .grants = TagSet.with(.{}, .stunned) });
    try std.testing.expectError(error.Blocked, actor.activate(shield));
    // An effect that requires a tag the target lacks is refused.
    try std.testing.expectError(error.Blocked, actor.apply(.{ .duration = 1, .requires = TagSet.with(.{}, .burning) }));
}
```

### E2. Behavior trees and queries

**Size:** M. **Depends on:** E0. **Files:** new `ai/Tree.zig`, `ai/Query.zig`; then `game/Enemies.zig`.

1. Add the tree library below. Built-in trees are `comptime` tables checked at compile time (child indices in range, no cycles, leaf ids valid); mod trees, if added later, go through the same checker at load.
2. Add `ai/Query.zig`: score up to 32 candidate points into a fixed array using caller-supplied scoring functions (distance to cover, line of sight, distance from allies). It replaces ad hoc searches such as the trooper's blocked-position seek.
3. Use it first for a new role (for example a Scalari frame module that needs a ranged versus melee choice), not for existing units.
4. Port the trooper behind its current tests (cover, melee strike, grenade throw) and compare the traces tick by tick against the old switch before deleting it.
5. Keep the 24-unit cap and the per-step cost budget: record `sim_hive_ai` in the frontier benchmark before and after (today 0.219 ms mean).

**Tests:** priority and interruption (the example), a stateless tree gives the same result for two units with different contexts, and tree validation rejects out-of-range children and cycles.

**Acceptance:** a unit changes its choice on the tick its conditions change; the ported trooper matches the old behavior in the combat smoke stage; AI cost does not rise in the frontier benchmark.

*Compiled* (the reactive tree and its test):

```zig
pub const Status = enum { success, failure, running };
pub const NodeKind = enum { sequence, selector, inverter, leaf };

pub const Node = struct {
    kind: NodeKind,
    first_child: u16 = 0,
    child_count: u16 = 0,
    leaf: u16 = 0, // index into the caller's leaf table
};

/// Every tick starts at the root, so a higher-priority branch (an enemy came into reach) always
/// gets to interrupt a lower one (still chasing). The tree is immutable data shared by every
/// unit and holds no per-unit state; a leaf that takes several ticks keeps its progress in the
/// unit's own context, so abandoning a branch needs no cleanup. Recursion depth is the tree
/// depth, bounded by the node count.
pub fn tick(comptime Ctx: type, nodes: []const Node, root: u16, ctx: *Ctx, leaves: []const *const fn (*Ctx) Status) Status {
    const node = nodes[root];
    switch (node.kind) {
        .leaf => return leaves[node.leaf](ctx),
        .inverter => return switch (tick(Ctx, nodes, node.first_child, ctx, leaves)) {
            .success => .failure,
            .failure => .success,
            .running => .running,
        },
        .sequence, .selector => {
            const stop_on: Status = if (node.kind == .sequence) .failure else .success;
            var i: u16 = 0;
            while (i < node.child_count) : (i += 1) {
                const status = tick(Ctx, nodes, node.first_child + i, ctx, leaves);
                if (status == .running or status == stop_on) return status;
            }
            return if (node.kind == .sequence) .success else .failure;
        },
    }
}

const Brain = struct { distance: f32, attacks: u32 = 0, moved: f32 = 0, windup: u32 = 0 };
fn near(b: *Brain) Status {
    return if (b.distance < 5) .success else .failure;
}
fn windup(b: *Brain) Status { // a two-tick action: running, then done; its progress lives in the unit
    b.windup += 1;
    return if (b.windup < 2) .running else .success;
}
fn strike(b: *Brain) Status {
    b.attacks += 1;
    b.windup = 0;
    return .success;
}
fn chase(b: *Brain) Status {
    b.distance -= 1;
    b.moved += 1;
    return .running;
}

test "a higher-priority branch interrupts, a multi-tick action keeps its progress in the unit" {
    // 0 selector( 1 sequence( 3 near, 4 windup, 5 strike ), 2 chase )
    const nodes = [_]Node{
        .{ .kind = .selector, .first_child = 1, .child_count = 2 },
        .{ .kind = .sequence, .first_child = 3, .child_count = 3 },
        .{ .kind = .leaf, .leaf = 3 }, // chase
        .{ .kind = .leaf, .leaf = 0 }, // near
        .{ .kind = .leaf, .leaf = 1 }, // windup
        .{ .kind = .leaf, .leaf = 2 }, // strike
    };
    const leaves = [_]*const fn (*Brain) Status{ near, windup, strike, chase };
    var brain: Brain = .{ .distance = 6.5 };
    try std.testing.expectEqual(Status.running, tick(Brain, &nodes, 0, &brain, &leaves)); // far: chase, 5.5
    try std.testing.expectEqual(Status.running, tick(Brain, &nodes, 0, &brain, &leaves)); // far: chase, 4.5
    try std.testing.expectEqual(@as(f32, 2), brain.moved);
    try std.testing.expectEqual(Status.running, tick(Brain, &nodes, 0, &brain, &leaves)); // near now: windup 1, running
    try std.testing.expectEqual(@as(f32, 2), brain.moved); // the attack branch preempted the chase
    try std.testing.expectEqual(Status.success, tick(Brain, &nodes, 0, &brain, &leaves)); // windup 2, then strike
    try std.testing.expectEqual(@as(u32, 1), brain.attacks);
    brain.distance = 9; // the target leaves reach mid-windup: the chase interrupts, nothing to clean up
    _ = tick(Brain, &nodes, 0, &brain, &leaves);
    try std.testing.expectEqual(@as(f32, 3), brain.moved);
}
```

### E3. Logic graph v2: compiled node graphs

**Size:** M. **Depends on:** E0. **Files:** `machine/Device.zig`, `machine/Blueprint.zig`, `machine/Machine.zig`, `mod_validate.zig`; docs in [scripting](../scripting.md) and [mods](../mods.md).

1. Define the graph format in blueprint JSON: nodes with an operation and operand indices, one designated output, at most 64 nodes.
2. Compile at load into a flat register program (below): validate every reference and reject cycles, then emit operands first so the simulation only runs a straight loop. A rejected graph leaves the blueprint unloaded and reports `file: key: reason` like the mod validator.
3. Keep the one-step latency rule so graphs stay compatible with existing circuits, and keep the sandbox properties: no allocation, fixed registers, finite results (a non-finite result outputs 0, as scripts do).
4. Extend `build validate-mods` to compile every graph in installed mods.
5. Add an in-game graph panel to the machine editor, a list-and-wire view over the same node array, only after the format has shipped.
6. Optional later: a graph-to-WebAssembly generator for graphs that outgrow 64 nodes. Not needed for the first version.

**Tests:** the compiler rejects cycles, dangling references and oversized graphs; evaluation matches a hand-computed table; a graph and an equivalent script give the same outputs over 1,000 steps; hostile JSON is rejected without mutating.

**Acceptance:** an existing logic circuit loads unchanged, and a new circuit with a comparison and a select runs in the Metal smoke's building stage.

*Compiled* (the compiler and evaluator, with cycle and reference checks):

```zig
pub const GraphOp = enum { input, constant, add, mul, min, max, less, select };
pub const GraphNode = struct { op: GraphOp, a: u16 = 0, b: u16 = 0, c: u16 = 0, value: f32 = 0 };
pub const GraphError = error{ Cycle, BadReference, TooLarge, NoOutput };

pub const max_registers = 64;
pub const Program = struct {
    ops: [max_registers]GraphNode = undefined, // register i is the result of ops[i]; operands reference earlier registers
    len: usize = 0,
    output: u16 = 0,

    pub fn run(self: *const Program, inputs: []const f32) f32 {
        var reg: [max_registers]f32 = undefined;
        for (self.ops[0..self.len], 0..) |n, i| {
            reg[i] = switch (n.op) {
                .input => if (n.a < inputs.len) inputs[n.a] else 0,
                .constant => n.value,
                .add => reg[n.a] + reg[n.b],
                .mul => reg[n.a] * reg[n.b],
                .min => @min(reg[n.a], reg[n.b]),
                .max => @max(reg[n.a], reg[n.b]),
                .less => if (reg[n.a] < reg[n.b]) 1 else 0,
                .select => if (reg[n.a] != 0) reg[n.b] else reg[n.c],
            };
        }
        return reg[self.output];
    }
};

fn operandCount(op: GraphOp) u8 {
    return switch (op) {
        .input, .constant => 0,
        .add, .mul, .min, .max, .less => 2,
        .select => 3,
    };
}

/// Validates the whole graph, then emits operands-first order. Nothing is returned on error.
pub fn compileGraph(nodes: []const GraphNode, output: u16) GraphError!Program {
    if (nodes.len == 0) return error.NoOutput;
    if (nodes.len > max_registers) return error.TooLarge;
    if (output >= nodes.len) return error.BadReference;
    var program: Program = .{};
    var state: [max_registers]u2 = @splat(0); // 0 unseen, 1 on the stack, 2 emitted
    var slot: [max_registers]u16 = undefined;
    // Depth-first from the output with an explicit stack: no host recursion.
    var stack: [max_registers * 2]struct { node: u16, child: u8 } = undefined;
    var depth: usize = 0;
    stack[0] = .{ .node = output, .child = 0 };
    depth = 1;
    state[output] = 1;
    while (depth > 0) {
        const frame = &stack[depth - 1];
        const node = nodes[frame.node];
        const count = operandCount(node.op);
        if (frame.child < count) {
            const operand = switch (frame.child) {
                0 => node.a,
                1 => node.b,
                else => node.c,
            };
            frame.child += 1;
            if (operand >= nodes.len) return error.BadReference;
            switch (state[operand]) {
                1 => return error.Cycle,
                2 => {},
                else => {
                    state[operand] = 1;
                    stack[depth] = .{ .node = operand, .child = 0 };
                    depth += 1;
                },
            }
        } else {
            var emitted = node;
            if (count > 0) emitted.a = slot[node.a];
            if (count > 1) emitted.b = slot[node.b];
            if (count > 2) emitted.c = slot[node.c];
            slot[frame.node] = @intCast(program.len);
            program.ops[program.len] = emitted;
            program.len += 1;
            state[frame.node] = 2;
            depth -= 1;
        }
    }
    program.output = slot[output];
    return program;
}

test "graph compiles to a flat program, shares sub-expressions, and rejects cycles and bad references" {
    // out = select(a < b, a * 2, b + 1), where a and b are inputs 0 and 1
    const nodes = [_]GraphNode{
        .{ .op = .input, .a = 0 }, // 0 a
        .{ .op = .input, .a = 1 }, // 1 b
        .{ .op = .constant, .value = 2 }, // 2
        .{ .op = .constant, .value = 1 }, // 3
        .{ .op = .less, .a = 0, .b = 1 }, // 4
        .{ .op = .mul, .a = 0, .b = 2 }, // 5
        .{ .op = .add, .a = 1, .b = 3 }, // 6
        .{ .op = .select, .a = 4, .b = 5, .c = 6 }, // 7
    };
    const program = try compileGraph(&nodes, 7);
    try std.testing.expectEqual(@as(f32, 6), program.run(&.{ 3, 5 })); // 3 < 5: 3 * 2
    try std.testing.expectEqual(@as(f32, 5), program.run(&.{ 9, 4 })); // else: 4 + 1
    const cyclic = [_]GraphNode{ .{ .op = .add, .a = 1, .b = 1 }, .{ .op = .add, .a = 0, .b = 0 } };
    try std.testing.expectError(error.Cycle, compileGraph(&cyclic, 0));
    const dangling = [_]GraphNode{.{ .op = .add, .a = 7, .b = 0 }};
    try std.testing.expectError(error.BadReference, compileGraph(&dangling, 0));
    try std.testing.expectError(error.NoOutput, compileGraph(&.{}, 0));
}
```

### E4. Cinematic tracks

**Size:** M. **Depends on:** E0; best after [phase 15](scenes.md) so tracks can reference scene objects by id. A minimal version can use fixed poses and event ids now.

1. Define a sequence as a JSON asset (referenced by GUID once phase 15 lands): a duration and tracks of keys. Track kinds: camera (position and look target), event (audio cue, dialogue line, story flag, spawn, fade), and a float property track.
2. Drive it from the fixed step so playback is deterministic and the same on every machine. Events fire exactly once however the step lands, and seeking is silent, so a scrub or a save restore does not replay the past.
3. Make every sequence skippable and make skipping apply its end-state events (flags, spawns) once.
4. Store a sequence's played flag in the shared progress. Note that `Progress.max_flags` is 96 and quests and caves have already overflowed a smaller cap once; budget the new flags or raise the cap with a save bump.
5. Use it first for one story beat from [Story.md](../Story.md) in the Frontier city, replacing hard-coded camera moves.
6. Editing UI comes last: a scrubbable timeline over the same data.

**Tests:** the example's once-only and silent-seek properties, plus a save taken mid-sequence resumes at the saved time without refiring events.

**Acceptance:** a skippable sequence plays in the real game, its flags survive save and load, and the smoke covers play and skip.

*Compiled* (a camera track sampler and the once-only event player):

```zig
pub const Key = struct { time: f32, value: [3]f32 };

pub fn sampleTrack(keys: []const Key, time: f32) [3]f32 {
    if (keys.len == 0) return .{ 0, 0, 0 };
    if (time <= keys[0].time) return keys[0].value;
    for (keys[1..], 1..) |next, i| {
        const prev = keys[i - 1];
        if (time <= next.time) {
            const t = (time - prev.time) / (next.time - prev.time);
            return .{ prev.value[0] + (next.value[0] - prev.value[0]) * t, prev.value[1] + (next.value[1] - prev.value[1]) * t, prev.value[2] + (next.value[2] - prev.value[2]) * t };
        }
    }
    return keys[keys.len - 1].value;
}

pub const Event = struct { time: f32, id: u16 };

pub const Sequencer = struct {
    time: f32 = 0,
    events: []const Event, // sorted by time

    /// Advances by one fixed step and writes the ids of events in (old time, new time]. An event
    /// fires exactly once however the step lands on it, and a long step cannot skip one.
    pub fn advance(self: *Sequencer, dt: f32, out: []u16) usize {
        const from = self.time;
        self.time += dt;
        var n: usize = 0;
        for (self.events) |e| {
            if (e.time > from and e.time <= self.time and n < out.len) {
                out[n] = e.id;
                n += 1;
            }
        }
        return n;
    }
    /// Seeking never fires events: a scrub or a save restore must not replay the past.
    pub fn seek(self: *Sequencer, time: f32) void {
        self.time = time;
    }
};

test "camera track interpolates, and events fire once across any step size" {
    const keys = [_]Key{ .{ .time = 0, .value = .{ 0, 10, 0 } }, .{ .time = 2, .value = .{ 20, 10, 0 } }, .{ .time = 4, .value = .{ 20, 30, 0 } } };
    try std.testing.expectEqual([3]f32{ 10, 10, 0 }, sampleTrack(&keys, 1));
    try std.testing.expectEqual([3]f32{ 20, 20, 0 }, sampleTrack(&keys, 3));
    try std.testing.expectEqual([3]f32{ 20, 30, 0 }, sampleTrack(&keys, 99));

    const events = [_]Event{ .{ .time = 0.5, .id = 1 }, .{ .time = 1.0, .id = 2 }, .{ .time = 3.0, .id = 3 } };
    var fired: [8]u16 = undefined;
    var a: Sequencer = .{ .events = &events };
    var total: usize = 0;
    var seen: [8]u16 = undefined;
    while (a.time < 4) { // fixed 1/60 s steps
        const n = a.advance(1.0 / 60.0, &fired);
        for (fired[0..n]) |id| {
            seen[total] = id;
            total += 1;
        }
    }
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, seen[0..total]);

    var b: Sequencer = .{ .events = &events }; // one huge step still fires all three, once
    try std.testing.expectEqual(@as(usize, 3), b.advance(10, &fired));
    try std.testing.expectEqual(@as(usize, 0), b.advance(1, &fired));
    b.seek(0); // seek is silent
    try std.testing.expectEqual(@as(usize, 0), b.advance(0, &fired));
}
```

### E5. Animation graph, IK and ragdolls

**Size:** L. **Depends on:** [phase 14](skeletal-animation.md) slice 1 (`HWSK` and `HWAN`).

1. Land phase 14 as planned: the controller table (a JSON mapping from traversal motion to a clip or blend), crossfades, a one-dimensional locomotion blend space, sockets.
2. Add foot placement with the existing two-bone IK: plant feet on `Terrain.surface` normals and lift the pelvis; verify against the traversal controller so collision capsules are unchanged.
3. Add `physics/Ragdoll.zig` for defeats: a chain of capsules on the existing rigid-body path with joint limits, spawned from the pose at the moment of defeat and fading to a corpse after a fixed time. `Rigid` supports only eight oriented boxes today, so this needs either a larger pool or a lighter capsule body; decide with a benchmark.
4. Do not add destruction. Do not add motion matching until a clip database of a few hundred seconds exists.

**Tests:** blend weights sum to one and are continuous across a transition; foot IK keeps feet on the terrain surface within a tolerance on slopes; a ragdoll never penetrates terrain and settles within a time bound; ragdoll spawn cost stays under a per-step budget with the unit cap.

**Acceptance:** the combat smoke shows a defeat as a ragdoll without breaking the physics budget (mean 0.594 ms, max 1.024 ms today).

### E6. Authored cells and the far field

**Size:** L. **Depends on:** [phase 15](scenes.md) and the nature plan's Phase 7.

1. Define an authored cell as a scene loaded into the chunk streamer: placement is deterministic, identity extends the existing `(seed, generator, chunk, local_id)` scheme so saved removals still resolve, and loading follows the streamer's generation radius with the same cancellation.
2. Use the same cell format for authored city districts, cave interiors and encounter sites, so content stops living in code.
3. Add the far field from the nature plan: coarser terrain rings and sparse low-detail trees out to a few kilometres; reuse the terrain sampler so shape agrees.
4. Do not stream per-entity component data; there are no entities to stream.

**Tests:** an authored cell is identical after unload and reload, the streamer never exceeds its pool and budget over a long route, and saved removals resolve in authored cells.

**Acceptance:** one authored encounter site streams in and out on the benchmark route inside the existing upload budget.

### E7. Material data, then a graph

**Size:** M then L. **Depends on:** the mesh editor's M4 and the nature plan's terrain materials.

1. Turn materials into data: a table of parameters (base colour, roughness-like cel bands, tags) in JSON, extended by mods the way character content is (the `CelStyle` pattern), with validation ranges.
2. Add a build-time test that splices every material stage onto the shared prelude and compiles it through Mach's WGSL compiler, so a missing substitute for `pow` or `cross` fails in CI, not at run time.
3. Only then consider a graph editor that emits WGSL fragments for the data table; keep the Mach WGSL limits in the node set.

**Acceptance:** a new material is added by data and verified by the splice test with no shader file edit.

### E8. Networking additions

**Size:** S inside phase 16. **Depends on:** [phase 16](networking.md).

1. Quantize snapshot fields (positions to centimetres within the chunk, angles to 16 bits) and send deltas against the last acknowledged snapshot; the plan keeps packets under 1,200 bytes, so this is what lets four players and vehicles fit.
2. Add interest management by chunk: a client receives entities within its streamer's render radius.
3. Mark replicated fields with a declarative table checked through the `src/compat` reflection shims, not by direct `@typeInfo` loops.
4. Keep the authoritative, input-driven model and the existing validators; do not add per-variable replication or an RPC layer.

**Acceptance:** the loopback test sustains the plan's bandwidth target (under 64 kbit/s per client) with four players in the frontier scene.

### E9. Physics extras (only on evidence)

Use `@Vector` in the hottest physics loops only if the frontier benchmark shows physics near its budget (it does not: 0.594 ms mean). Do not add a math dependency. Destruction stays out of scope.

## 5. Rejected or deferred, with revisit triggers

| Feature | Decision | Revisit when |
| --- | --- | --- |
| Virtualized micro-polygon geometry | Reject | Mach gains atomics and a GPU-driven path *and* assets arrive that need it; level of detail comes first |
| Dynamic global illumination | Reject | the art direction changes; shadows and occlusion come first |
| Dynamic-library live coding | Reject | module state no longer has to cross a copied stack and a render mutex |
| Motion matching | Defer | a few hundred seconds of consistent clips exist ([animation capture](animation-capture.md)) |
| Chaos-scale destruction | Reject | a gameplay need names it |
| Mach ECS adoption | Defer | a measured entity-iteration bottleneck |
| `zmath` or another math dependency | Reject | `@Vector` proves insufficient on a profile |
| Node-based material graph | Defer to E7 step 3 | materials are data and the mesh editor's library exists |

## 6. Ordering and dependencies

```text
E0 green suite + save policy
 |-- E1 ability core --> loot affixes (Kit, save bump)
 |-- E2 behavior trees --> new enemy roles
 |-- E3 logic graphs   --> mod graphs, machine editor panel
 |-- E4 cinematic tracks --(phase 15)--> story beats
 |-- phase 14 --> E5 animation graph, foot IK, ragdolls
 |-- phase 15 + nature Phase 7 --> E6 authored cells, far field
 |-- mesh editor M4 + nature materials --> E7 material data
 `-- phase 16 --> E8 networking additions
```

E1 and E2 are the highest value for the MVP (per-player loot and readable fights). E3 and E4 serve the city exploration and story half. E5 to E8 ride on the engine phases already planned. The MVP gate in [next steps](next-steps.md#revised-next-steps) (milestone B) still has no content; none of these phases replaces it, so time-box them against it.

## 7. Validation, budgets and saves

- **Every phase:** `build check` on both compiler channels, the headless suite with a stated count, allocation-failure tests for any builder that allocates, and the Metal smoke under `MTL_DEBUG_LAYER=1` when rendering or the simulation changes. Say what ran and what did not in [validation](../validation.md).
- **Budgets:** simulation p99 stays under 4 ms and render CPU under 16.667 ms in the frontier benchmark (2.815 ms and 4.879 ms today); new systems record their own rows (for example `sim_abilities`, `sim_ai_trees`).
- **Frame path:** no allocation, fixed capacities, errors instead of sentinels.
- **Saves:** E1's loot affixes and E4's flags change saves; each bumps the format with a migration and a round-trip test. Effects, trees and graphs run on data that is already saved or rebuilt at load.
- **Mods:** abilities, trees, graphs and materials become Mod API 2 candidates once their formats are stable; validate them with the same file-and-key error reports as character content.

## 8. Decisions for the project owner

1. **Priority:** whether E1 and E2 (loot affixes and enemy roles) go ahead of the nature and mesh-editor tracks, given the MVP gate.
2. **Ability scope:** whether hero powers move wholesale onto the effect core, or only new content does.
3. **Graph authoring:** whether machine builders get a graph panel (E3 step 5) or WebAssembly remains the only way beyond simple circuits.
4. **Cinematics:** how many authored sequences the first city needs, which sets how much editor UI (E4 step 6) is worth building.
5. **Ragdolls:** whether defeats should ragdoll (E5) or keep the current reactions.

## 9. Reference

Sources read: [Specials.zig](../../src/game/Specials.zig), [Heroes.zig](../../src/game/Heroes.zig), [Enemies.zig](../../src/game/Enemies.zig), [Hive.zig](../../src/ai/Hive.zig), [Device.zig](../../src/machine/Device.zig), [Wasm.zig](../../src/script/Wasm.zig), [HotReload.zig](../../src/asset/HotReload.zig), [Streamer.zig](../../src/world/Streamer.zig), [Rigid.zig](../../src/physics/Rigid.zig), [ik.zig](../../src/character/ik.zig), [Animation.zig](../../src/character/Animation.zig), [Progress.zig](../../src/game/Progress.zig).

Commands used for the examples:

```sh
python3 tools/zig.py test engine_examples.zig                              # default pair: 4 of 4
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py test engine_examples.zig  # 0.17: 4 of 4
```

Two findings from compiling them are worth keeping: Zig 0.17 rejects `x ** n` array repetition with this spacing (use `@splat`), and rejects direct `@typeInfo(...).fields` reflection; inside the repository use the `src/compat` shims.
