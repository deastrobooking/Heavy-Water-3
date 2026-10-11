@AGENTS.md

# Claude Code notes

Everything in AGENTS.md applies. These are additions for Claude Code.

- **Memory:** the project memory index lists the user's standing direction (native Zig only, docs aligned in the same change, the canopy world, hack-and-slash outside sanctuary cities). Treat it as background, check it against the docs, and do not restate it in answers.
- **Verification before saying done:** run the tests and the Metal smoke yourself, look at a capture for visual work, and reinstall the executable with `python3 tools/zig.py build -Doptimize=ReleaseFast` so the user's `zig-out/bin/heavy-water` is current.
- **Long runs:** the suite takes minutes. Run it with output redirected to a file, then grep the summary (`grep -a -E "error: '|tests passed"`), instead of streaming it.
- **Editing:** prefer the Edit tool for exact changes. A shell script is fine for mechanical edits across many files, but search for leftover references afterwards and let the compiler find the rest.
- **Reports:** lead with what the user can now do, then what was and was not checked. Link files as `[name](path)`; no backticked paths for files.
- **Migration work:** when a task touches Zig version differences, Mach, or `tools/zig.py`, read the "Zig-first platform and the 0.17 migration" section of AGENTS.md and [docs/plans/engine-update-process.md](docs/plans/engine-update-process.md) first. Record measured results (error counts by owner, which gates ran, what was skipped) in the Mach tracking section of [docs/plans/alignment.md](docs/plans/alignment.md), dated.
- **Shared working tree:** other agents and the user leave uncommitted changes here. Before committing, run `git status`, stage only the files you changed, and say which changes are not yours. Never reset or restore files you did not write.
- **Outward-facing steps need a yes:** opening an upstream issue or pull request, pushing, and changing a compiler pin are all asks, not defaults.
