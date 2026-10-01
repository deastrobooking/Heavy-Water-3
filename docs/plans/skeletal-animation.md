# Phase 14: skeletal animation and attachments

**Goal:** animated, skinned characters (players, pedestrians, keepers, and future creatures) whose animation follows the traversal controller, with props, tools, and hitboxes attached to named bones.

## Today

- **Avatars:** `game/Avatar.zig` builds characters from up to 16 scaled blocks, swinging limbs by a walk phase.
- **Motion states:** `Player.Motion` already names every state the animation must cover: idle, run, sprint, jump, fall, roll, stomp, wall slide, climb, hang, mantle, jet, hover, glide, dash, board, grapple zip, grapple swing, and swim.
- **Importer:** the glTF importer rejects skins and animations.
- **Renderer:** draws rigid instances only, and the vertex layout has no joints or weights.
- **Other users:** another agent's combat work (`src/combat/`) will want per-bone hitboxes and weapon sockets.

## Design

### Assets (through phase 13)

- **Skinned model, `HWSK` v1:** vertices add `joints: [4]u8` and `weights: [4]u8` (unorm), so 64 joints at most per draw, which is plenty for humanoids. The skeleton stores joint names, parent indices (parent before child), the rest pose (TRS), and inverse bind matrices. Named sockets are a joint plus an offset transform.
- **Animation clip, `HWAN` v1:** a skeleton GUID; per-joint translation, rotation, and scale tracks (STEP or LINEAR, with CUBICSPLINE resampled at import); duration; loop flag; and events (footstep, hit window) for gameplay and audio.
- **Importer:** reads glTF `skins`, `JOINTS_0` and `WEIGHTS_0` (u8 or u16 joints; float or normalized weights renormalized to 8 bits), inverse bind matrices, and `animations`. Its import settings are root scale, joint whitelist, resample rate, and clip splitting by name or frame range.

### Runtime

- **Pose:** local TRS per joint, sampled by binary search with the last key cached. Global transforms follow parent order, and skin matrices are global × inverse bind. Allocation-free with fixed capacities.
- **Blending:** crossfade between two clips (a weighted nlerp of quaternions), plus a 1D blend space for locomotion by ground speed (idle → walk → run → sprint). Additive layers (aim, look) come later.
- **Controller mapping:** a small table maps each `Player.Motion` to a clip or blend with crossfade times. It is data, a JSON asset referencing clips by GUID, so new characters reuse the controller without code changes.
- **Root motion:** not used; the traversal controller owns movement. Animations are authored in place.
- **Attachments:** `attach(prop, character, socket)`. Each frame, the prop's world transform is the character transform × the socket joint's global × the socket offset. Players use this for tools (salvage cutter, grapple), carried crates (hands), hats and accents, and combat weapons. Hitbox capsules per joint are published for combat queries.

### Rendering

- **Pipeline:** a skinned-mesh pipeline variant whose vertex shader reads a bone palette from a uniform buffer: 64 matrices × 64 bytes = 4 KiB per character, well within Mach's 64 KiB uniform binding limit. Each character's palette is selected with a dynamic offset, which Mach's Metal backend supports.
- **Batching:** one draw per character submesh. With four players, eight pedestrians, and three keepers that is under 100 draws.
- **Fallback:** if a needed shader feature fails on the pinned Mach, skin on the CPU into a per-frame vertex buffer (correct, slower), measured and reported.
- **Profiles:** the creator's colors and proportions become material tints and joint scales on the skinned ranger, keeping save compatibility through `Profile`.

### First content

A rigged ranger is generated in Zig, not downloaded: the block avatar's proportions become a low-poly skinned mesh, and the clips (idle, walk, run, jump, fall, climb, hang, roll, swim, glide) are keyframed in code and written as `HWAN`. This needs no external art and gives deterministic test fixtures. A small hand-written glTF skin fixture exercises the importer. Authored characters replace the generated ones later through the same pipeline.

## Slices

1. **Import and pose math.** The glTF skin and animation importer, the `HWSK` and `HWAN` formats, sampling, and the global and skin matrix pipeline, all tested headlessly.
2. **GPU skinning.** The skinned pipeline, palette uniforms, the generated ranger replacing the block avatar for players, and Metal validation in smoke.
3. **Controller and attachments.** The Motion → clip mapping with crossfades and the locomotion blend, sockets and attachments (carried crate, tools), and hitbox capsules for combat.
4. **Crowds.** Pedestrians and keepers use skinned characters, with skinning for distant or culled characters skipped.

## Acceptance

- **Import:** the fixture glTF imports, and joint hierarchy, inverse binds, and weights round-trip exactly. Weights sum to 1 ± 1/255. Malformed skins (cycles, more than 64 joints, bad weights) are rejected.
- **Pose math:** sampling at keys returns exact keys. Interpolation matches reference values. The rest pose times the inverse bind gives identity skin matrices, and a two-bone chain test checks global composition.
- **Gameplay:** a headless Sandbox test drives each traversal state and checks the selected clip and crossfade weights. A carried crate stays at the hand socket within 1 cm while walking, and hitbox capsules follow the arm through a swing.
- **Rendering:** smoke with Metal validation shows animated characters. Render CPU with four players and twenty animated characters stays inside the existing budget, measured with a new benchmark route.

## Risks

- **Mach's WGSL compiler:** it has gaps (no `cross`, no shifts in some expressions). Mitigation: write the skinning shader in the simplest WGSL, test it early in slice 2, and keep the CPU fallback.
- **Art quality of generated characters:** these are an engineering fixture, not final art. The pipeline is the deliverable.

**Out of scope:** inverse kinematics (foot placement and hand IK are a later slice), facial animation, cloth, and morph targets.
