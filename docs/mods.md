# Mods

A mod is a directory under `mods/` that adds machine blueprints and, optionally, WebAssembly scripts that run inside machines. The game installs every valid mod at startup. Mod API version **1** is deliberately small: validated data plus pure, budgeted functions. A mod cannot read files, call the engine, or touch another mod.

## Try the example

`mods/glowworks/` ships with the game, and `python3 tools/zig.py build run` builds its script module first; `python3 tools/zig.py build mods` builds only the mod. At startup the log reports `Mod glowworks 1.0.0: 1 blueprints, 2 scripts`. Press **2**, then **Tab** to the end of the palette, and place **breathing_lamp**. With the hands tool, press its red switch: the lamp breathes between dim and bright every four seconds. Aim at the `breath` device to see its script and output.

## Package format 1

```
mods/<name>/
  mod.json
  blueprints/*.json           # ordinary blueprint documents (same format as assets/source/blueprints)
  <module>.wasm               # optional, built from your source
```

```json
{
  "format": 1,
  "name": "glowworks",
  "version": "1.0.0",
  "api": 1,
  "description": "Script-driven lamps.",
  "blueprints": ["blueprints/breathing_lamp.json"],
  "scripts": { "module": "glowworks.wasm", "exports": ["breathe", "majority"], "fuel": 20000, "memory_pages": 4 }
}
```

Loading rejects the whole package, with the reason in the log, unless all of these hold:

- `format` is 1 and `api` equals the game's mod API version (1).
- `name` is lowercase letters, digits, and underscores (up to 23 characters) and matches the directory name.
- `version` is `major.minor.patch`.
- Every path is package-relative: no absolute paths, `..`, `.` or backslashes.
- At most 8 blueprints are listed, and each passes the normal blueprint validator.
- A `script` device names only this mod's declared exports (`"glowworks.breathe"`).
- There are at most 8 exports, `fuel` is between 100 and 1,000,000, and `memory_pages` is between 1 and 64.
- The module loads, imports nothing, has no start function, and exports every declared function with the script signature.

Installation is also all or nothing. A second mod with the same name, or a blueprint name that is taken by a different design, leaves the world unchanged. A blueprint already present with an identical design, which happens when a save made with the mod is loaded first, is not a conflict.

## Scripts

A `script` device has signal inputs `a`, `b`, `c`, `d` and output `out`, like a logic controller, plus a `"script": "<mod>.<export>"` field. Each simulation step, it calls the export with its inputs (as of the previous step, the same one-step latency as logic) and the world time in seconds:

```zig
export fn breathe(a: f32, b: f32, c: f32, d: f32, time: f32) f32 { ... }
```

Build for `wasm32-freestanding` with `-fno-entry -rdynamic` (see `build.zig`, which uses a 16 KiB stack). Other languages work if they produce a WebAssembly 1.0 module with no imports; the interpreter also accepts the sign-extension, saturating float-to-int, bulk-memory and multi-value extensions.

These rules keep scripts deterministic and safe:

- **Fuel:** each call may execute at most `fuel` instructions; the example needs 99–170.
- **Traps:** running out of fuel, any trap, or a non-finite result makes the output 0 for that step. These are counted and never stop the world.
- **Memory:** linear memory is capped at `memory_pages` × 64 KiB, and every access is bounds-checked. Calls nest at most 128 deep.
- **Purity:** globals, including the compiler's stack pointer, reset after every call. Treat scripts as pure functions of their inputs and time. Linear memory is not reset or saved, so state kept there is unsupported and would not survive a save.
- **Missing scripts:** a missing script, for example from an uninstalled mod, outputs 0, and the device's HUD and inspection show `MISSING`.

## Saves

Format 10 saves list the installed mods by name and version. Blueprints placed from a mod are saved in full, like any machine, so a world still loads without the mod. The game reports each missing or different mod, and its scripts output 0 until it is installed again.

## Not in API 1

Mods cannot yet add Arbor genomes, shrine templates, market wares, meshes, or textures. Scripts get no host functions: no world queries, logging, or randomness beyond their inputs. There is no dependency or load-order declaration (mods load in directory order and cannot reference each other), no hot reload, and no sandboxing beyond the interpreter. A mod's blueprints are trusted to be as harmless as any blueprint a player could build. See the [scripting evaluation](scripting.md) for why scripting is a WebAssembly interpreter.
