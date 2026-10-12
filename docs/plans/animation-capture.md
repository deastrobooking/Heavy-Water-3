# User Animation Capture

## Goal

Let a player record a short performance with an ordinary webcam and turn it into a retargetable character clip. Treat this as **local motion capture**, not as video playback or direct keyframing. The result is an editable animation asset (`HWAN`) that can be previewed on the imported Captain rig and the procedural ranger.

## Data flow

```text
webcam or local video
        ↓
timestamped frames + per-joint confidence
        ↓
pose reconstruction and temporal cleanup
        ↓
canonical humanoid motion tracks
        ↓
retarget to a named game skeleton
        ↓
timeline review, trim, and correction
        ↓
HWAN clip + source/settings metadata
```

Keep raw video as temporary input by default. The user explicitly starts capture, grants camera access, sees a camera-active indicator, and chooses whether to keep or delete the source recording. Do not upload video or pose tracks. Audio is excluded unless a later feature explicitly needs it.

## Staged implementation

1. **Animation asset foundation:** import and validate glTF TRS tracks into versioned `HWAN`; bind clips to skeleton identities; preview them on the existing rig and controller. This is a prerequisite for captured motion, even without a camera.
2. **File-based capture prototype:** accept a prerecorded short clip so sessions are repeatable; identify one foreground person; estimate timestamped landmarks and confidence; smooth jitter; mark low-confidence/occluded spans; retarget onto the canonical game skeleton; allow trim, playback-speed, and root-motion controls; export `HWAN`.
3. **Mac webcam source:** add a narrow platform capture interface only after checking Mach's support. The repository currently has no webcam/video-input path. Keep camera enumeration and frame acquisition isolated from the pure-Zig animation importer and retargeter. macOS is first; do not claim another platform until built and exercised there.
4. **Editor integration:** show the clip timeline, confidence/occlusion track, source skeleton and target skeleton preview in the standalone Mesh Editor's animation workspace. Provide manual key correction and bake before the result can enter gameplay.

## Motion quality and limits

A single webcam view gives uncertain depth and can lose joints during turns, self-occlusion, loose clothing, or poor lighting. Preserve confidence values instead of inventing certainty. Use calibrated scale or a known height, enforce joint-length limits, smooth in timestamp space rather than assuming a fixed frame rate, and let users inspect and correct the result. Start with one visible performer and in-place humanoid motion; multi-person capture, face capture, fingers, props, and root-motion extraction are later work.

Pose estimation requires a model or algorithm in addition to video frames. Before selecting one, compare licensing, offline redistribution, CPU/GPU requirements on target Macs, model size, and Zig/native-dependency policy. Keep inference behind a replaceable interface; do not add a C/C++ runtime or network service by default. If local inference cannot meet the target frame budget, make that a documented optional tool dependency rather than silently uploading footage.

## Acceptance

- A short prerecorded clip produces a repeatable local landmark track with timestamps and confidence.
- Missing/uncertain landmarks are identified and can be corrected; smoothing does not erase fast strikes or foot contacts.
- Retargeted animation previews on a compatible imported skeleton, can be trimmed and saved as `HWAN`, and survives close/reopen.
- The source video can be deleted after baking; exported animation contains no image frames or camera metadata.
- Direct camera capture clearly indicates when the camera is active and never transmits frames or poses.

## Dependencies and open work

- [Skeletal animation](skeletal-animation.md): runtime skeleton, skin-weight, and clip import must land first.
- [Standalone mesh editor](mesh-editor.md): its rig/animation preview workspace consumes imported clips and provides correction UI.
- Camera backend and pose-estimation model choice remain open pending a local prototype and licensing/performance review.
