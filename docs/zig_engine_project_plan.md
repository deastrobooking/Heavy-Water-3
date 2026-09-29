# Zig-Native Game Engine: Project Roadmap

This document outlines the strategic phases for building a game engine centered around native Zig architecture, treating Mach as the foundation and strategically isolating C++ dependencies.

## Phase 1: Memory Foundation & Data Model
Establish the explicit allocator hierarchy and the Mach Object integration. Everything downstream depends on these memory guarantees.

**Objectives:**
*   Implement the Global Allocator Tree to guarantee zero steady-state heap allocations.
*   Define how Mach's entity system maps to dense struct-of-arrays (SoA) layouts.
*   Bind commodity libraries (Tier 3).

### Boilerplate: Memory System
```zig
const std = @import("std");

pub const EngineMemory = struct {
    world_arena: std.heap.ArenaAllocator,
    physics_arena: std.heap.ArenaAllocator,
    frame_arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) EngineMemory {
        return .{
            .world_arena = std.heap.ArenaAllocator.init(backing_allocator),
            .physics_arena = std.heap.ArenaAllocator.init(backing_allocator),
            .frame_arena = std.heap.ArenaAllocator.init(backing_allocator),
        };
    }
    
    pub fn resetFrame(self: *EngineMemory) void {
        _ = self.frame_arena.reset(.retain_capacity);
    }
};
```

---

## Phase 2: Tier 2 Abstraction & Baseline Simulation
Integrate external systems (like Jolt Physics) behind strict Zig-native data boundaries. The game code must interact only with Zig data structures.

**Objectives:**
*   Design Zig APIs to accept contiguous arrays (Transforms, Velocities) rather than individual objects.
*   Write C ABI bindings that bridge dense Zig arrays with external C/C++ systems.
*   Route external thread requests through the Zig job scheduler.

### Boilerplate: Physics Boundary
```zig
pub const PhysicsWorld = struct {
    // The game only ever sees this Zig-native data structure
    positions: []extern math.Vec3,
    rotations: []extern math.Quat,
    velocities: []extern math.Vec3,
    
    // Opaque handle to external C/C++ system
    backend: *c.JoltSystem,

    pub fn step(self: *PhysicsWorld, dt: f32, frame_alloc: std.mem.Allocator) !void {
        // Pass contiguous arrays to the backend, not individual objects
        c.Jolt_Step(self.backend, self.positions.ptr, self.velocities.ptr, self.positions.len, dt);
    }
};
```

---

## Phase 3: The Native Zig Renderer
Build a GPU-driven rendering pipeline entirely in Zig on top of Mach's `sysgpu`.

**Objectives:**
*   Implement Zig structures that mirror world state to GPU buffers.
*   Write Frustum, HZB, and LOD compute shaders for a compute-culling pipeline.
*   Implement a compile-time validated render graph.

### Boilerplate: Render Graph
```zig
pub fn RenderGraph(comptime config: RenderConfig) type {
    return struct {
        passes: [config.max_passes]RenderPass,
        transient_resources: ResourcePool,

        pub fn execute(self: *@This(), scene: *GpuScene) void {
            // Zig aggressively unrolls and optimizes this based on comptime config
            inline for (self.passes) |pass| {
                pass.dispatch(scene);
            }
        }
    };
}
```

---

## Phase 4: Procedural Generation & World Genome
Implement the strategic differentiator: a highly optimized, native Zig procedural generation pipeline.

**Objectives:**
*   Use `comptime` to generate specialized terrain builders.
*   Build geology, ecology, and civilization simulators as linear data transformations.
*   Implement constraint solvers for logical structure generation.

### Boilerplate: Comptime World Generator
```zig
pub fn TerrainGenerator(comptime params: GeneratorParameters) type {
    return struct {
        pub fn generate(allocator: std.mem.Allocator, seed: u64) ![]HeightMap {
            var map = try allocator.alloc(HeightMap, params.chunk_size);
            
            // Branchless, comptime-optimized generation
            if (params.erosion_strength > 0.0) {
                applyErosion(map, params.erosion_strength);
            }
            if (params.caves) {
                carveCaves(map, seed);
            }
            return map;
        }
    };
}
```

---

## Phase 5: Introspection, Editor & Modding Infrastructure
Exploit Zig's `@typeInfo` to auto-generate tooling and schemas directly from engine core types.

**Objectives:**
*   Write compile-time reflection to generate debug UIs (e.g., ImGui property panels).
*   Generate JSON/binary schemas from source code for modders.
*   Auto-generate high-speed binary read/write functions for serialization.

### Boilerplate: Compile-Time Reflection Tooling
```zig
pub fn generateInspector(comptime T: type, instance: *T) void {
    const info = @typeInfo(T);
    if (info != .Struct) return;

    inline for (info.Struct.fields) |field| {
        const value = @field(instance, field.name);
        
        switch (@typeInfo(field.type)) {
            .Float => imgui.sliderFloat(field.name, &@field(instance, field.name), 0.0, 1.0),
            .Bool => imgui.checkbox(field.name, &@field(instance, field.name)),
            else => { /* Recurse or handle custom types */ },
        }
    }
}
```