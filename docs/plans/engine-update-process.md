# Mach and Zig update process

Keep the game buildable while evaluating Mach and Zig changes. Treat an engine update as a reviewed port with a recorded source revision, toolchain, and validation result. Never move the default compiler pin until the candidate has cleared the gates below.

## Version record

For each candidate, record:

- Mach upstream URL, exact commit, package version, and checksum or immutable archive reference.
- Zig version and download URL, host archive checksum, and the Mach revision that nominates it.
- Heavy Water's base Mach commit, local patch list, and any patches proposed upstream.
- Build, test, smoke, backend, and benchmark results, including host platform and date.

Keep compiler pins and checksums in `tools/zig.py`. Keep the local base revision and the engine patch inventory in `vendor/mach/FORK.md`. Keep adoption decisions and measured feature gaps in [engine alignment](alignment.md#mach-tracking).

## Importing an upstream Mach revision

1. Select a tagged release or commit and record the exact revision before touching `vendor/mach`.
2. Fetch that revision into an isolated checkout or temporary worktree. Keep the current vendored tree as the known-good comparison point.
3. Compare the candidate against the recorded upstream base. Group changes by subsystem, then map each local fork patch to the new source. Preserve project patches deliberately; do not copy the old fork over the candidate or accept a broad overwrite.
4. Preserve upstream license files and update the version, provenance, and patch inventory together.
5. Build the candidate with its nominated Zig first. Record compile errors by owner: upstream API/compiler change, Heavy Water integration, or local patch conflict.
6. Resolve the port in small, reviewable changes. Keep the current compiler and Mach pair as the default while the candidate is incomplete.

The upstream snapshot and compiler archives belong in ignored `.tools/` storage. Changes to the engine itself belong in `vendor/mach`; changes to the game's package graph belong in the root `build.zig.zon`.

## Zig compatibility gates

Run the pinned pair after every fork change. For a candidate pair, run `build check`, asset compilation, and the target-specific backend compile. Then run headless tests, the Metal validation smoke run, and relevant benchmarks before adoption. Record skipped platform checks with the reason and target needed to perform them.

Zig breaking changes are handled as compatibility work, not by raising `.minimum_zig_version` speculatively. Keep `HEAVYWATER_ZIG_CHANNEL` opt-in while a channel is under evaluation. When a new Zig release or 0.18 development snapshot changes the recommended pin, update the download pin and its host checksums as a distinct, reviewable step, then run the matrix again.

Adopt a pair only when the game, tools, and selected engine backends build together. Change the Mach package metadata, root minimum Zig version, default Zig pin, and docs in the same adoption change so users cannot land on a mixed pair.

## Proposing missing engine features upstream

Before preparing a maintainer proposal, reduce the need to a small reproducible example and identify the exact public API or backend behavior involved. Check current upstream first, then compare all supported backend implementations. Keep the Heavy Water integration working locally while the proposal is under review.

Use this outline for an issue or pull request draft:

```text
Title: <specific API, compiler, or backend capability>

Mach revision and Zig version:
Affected backend(s):
Current behavior:
Expected behavior:
Minimal reproduction:
Proposed API or implementation:
Validation performed:
Compatibility and migration notes:
```

Keep the draft in the project until a maintainer is ready to receive it. Once an external issue or pull request is explicitly requested, link its result in `vendor/mach/FORK.md` and record which local patch can be removed when upstream includes it.

## Completion record

For every adopted or rejected candidate, add a dated entry to the Mach tracking section of `alignment.md` with:

- the candidate Mach and Zig revisions;
- the result of each gate and any remaining platform gaps;
- the decision and reason;
- upstream issue or pull request links, if one was opened;
- local patches retained, updated, or removed.
