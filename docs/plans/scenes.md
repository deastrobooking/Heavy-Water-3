# Phase 15: scene graph and JSON scenes

**Goal:** hand-authored levels and reusable prefabs as hierarchical transform trees with components. They are stored as human-readable JSON, reference assets by GUID, load in the background, hot-reload during development, and are placed into the procedural world alongside generated content.

## Today

- **Hard-coded placement:** the world is generated from seed and generator versions (terrain, Arbors, district, shrines). Default placements (spawn crates, door, elevator, rover) are hard-coded in `Sandbox.init`.
- **Saves:** complete JSON world documents (format 12), but they are flat lists of machines, crates, bridges, and progression records, not authored scenes.
- **Missing:** a transform hierarchy, a level format, and a way to author a place by hand.

## Design

### Nodes

- **`SceneNode`** is fixed-size and trivially copyable: `id: u32` (stable within the scene); `parent`, `first_child`, and `next_sibling` indices; a local transform (translation, rotation quaternion, scale); a name; and a component mask with component slot indices.
- **Storage:** nodes live in one array, parent before child, so global transforms are computed in a single pass with no recursion. Trivial copying makes snapshots, undo, play-in-editor, and network replication straightforward.
- **Components:** each component type has its own fixed-capacity array keyed by node. The first set:
  - `mesh` (model ref, tint, LOD);
  - `collider` (box, mesh from model ref, static or dynamic);
  - `machine` (blueprint ref and initial state);
  - `crate`;
  - `spawn` (player start, guest starts);
  - `light` (emissive, for future clustered lights);
  - `trigger` (box volume, used as a machine sensor);
  - `prefab` (a nested scene ref with overrides);
  - `character` (skinned model and controller refs, phase 14);
  - `audio` (later).

### JSON format v1

```json
{
  "format": 1,
  "name": "Seed vault annex",
  "nodes": [
    { "id": 1, "name": "root", "transform": { "t": [0, 0, 0] } },
    { "id": 2, "parent": 1, "name": "gate", "transform": { "t": [0, 0, 12], "r": [0, 0.707, 0, 0.707] },
      "machine": { "blueprint_ref": "4c1e…", "state": [] } },
    { "id": 3, "parent": 1, "name": "lamp post", "transform": { "t": [4, 0, 2] },
      "prefab": { "scene_ref": "9a77…" } }
  ]
}
```

- **Asset references:** any field ending in `_ref` is an asset GUID, resolved through the phase 13 registry at hydration and checked against the expected kind. The convention is enforced by the loader, so a misspelled or missing reference is an error, never a silent default.
- **Hydration:** loading validates everything first: unique IDs, parents before children, no cycles, references resolved, blueprints validated, capacities checked. Only then does it create bodies and machines, staged the same way save loading is staged today.
- **Saving:** saving writes the same format, with stable key order and indentation, so diffs stay readable.

### Placement in the world

- **Anchors:** a scene is placed by an anchor: world-fixed, district plaza N, shrine site K, or Arbor and platform. One scene can therefore decorate any seed.
- **Spawn content:** the default spawn content (crates, door, elevator, rover) moves into `scenes/spawn.json`, replacing the hard-coded list.
- **Prefabs:** nested scene references with per-instance overrides (transform, tint, blueprint parameters). Captured machine prefabs become scenes too.
- **Saves:** the save records which scenes were placed (GUID plus anchor) and the deltas from them, as it already does for procedural content: removed nodes and changed machine states.

### Tooling without an editor

- **Hot reload:** scenes reload through phase 13 hot reload. Editing the JSON updates the running world when node IDs are unchanged; new nodes are added and removed ones despawned.
- **Inspection:** `-Dshowcase` and `-Dcapture-frame` cover viewpoints and screenshots. A scene can name its own viewpoints for capture.
- **Validation:** `asset-compiler` validates scenes at build time, as it does blueprints.

## Slices

1. **Nodes, transforms, JSON.** The node arrays, global transform pass, JSON v1 read and write, validation, and `_ref` resolution. Mesh and crate components first.
2. **Gameplay components and spawn scene.** Machine, collider, trigger, and spawn components. `scenes/spawn.json` replaces the hard-coded placements, and all existing tests pass unchanged. Saves record the placed scene.
3. **Prefabs and anchors.** Nested scenes with overrides, plaza, shrine, and Arbor anchors, and machine prefabs stored as scenes.
4. **Hot reload.** Live update of a running scene by stable node ID.

## Acceptance

- **Round trip:** a scene with 1,000 nodes survives JSON round-trip byte-identically. Global transforms match a reference computation within 1e-5.
- **Rejection:** cycles, duplicate IDs, children before parents, missing or wrong-kind references, invalid blueprints, and capacity overflows are rejected with no change to the world.
- **Spawn scene:** the spawn scene reproduces today's spawn exactly. Every existing acceptance test (door, elevator, rover, crate carry) passes unchanged on it.
- **Prefabs:** a prefab placed at three plaza anchors with different overrides behaves independently, as captured prefabs do today.
- **Hot reload:** editing a node's transform in the JSON moves it in a running smoke session without a restart or validation error.

## Risks

- **Two sources of truth** for spawn content during migration. Mitigation: slice 2 removes the hard-coded list in the same change.

**Out of scope:** a visual editor, scripting inside scenes (mod scripts via `script` devices already exist), and lighting bakes.
