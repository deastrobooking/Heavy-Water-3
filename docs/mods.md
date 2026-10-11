# Mods

A mod is a directory under `mods/` that adds machine blueprints, character content (hairstyles, faces, armor, palettes, cel styles) and, optionally, WebAssembly scripts that run inside machines. The game installs every valid mod at startup. Mod API version **1** is deliberately small: validated data plus pure, budgeted functions. A mod cannot read files, call the engine, or touch another mod.

## Try the example

`mods/glowworks/` ships with the game, and `python3 tools/zig.py build run` builds its script module first; `python3 tools/zig.py build mods` builds only the mod. At startup the log reports `Mod glowworks 1.0.0: 1 blueprints, 2 scripts`. Press **2**, then **Tab** to the end of the palette, and place **breathing_lamp**. With the hands tool, press its red switch: the lamp breathes between dim and bright every four seconds. Aim at the `breath` device to see its script and output.

## Package format 1

```
mods/<name>/
  mod.json
  blueprints/*.json           # ordinary blueprint documents (same format as assets/source/blueprints)
  character/*.json            # optional character content, see "Character content" below
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
- At most 8 `character` files are listed, and every one passes the character content rules below.
- A `script` device names only this mod's declared exports (`"glowworks.breathe"`).
- There are at most 8 exports, `fuel` is between 100 and 1,000,000, and `memory_pages` is between 1 and 64.
- The module loads, imports nothing, has no start function, and exports every declared function with the script signature.

Installation is also all or nothing. A second mod with the same name, or a blueprint name that is taken by a different design, leaves the world unchanged. A blueprint already present with an identical design, which happens when a save made with the mod is loaded first, is not a conflict.

## Character content

A mod adds options to the character creator by listing data files under `"character"` in `mod.json`. Everything is JSON, validated before anything is installed, and there is no code to run. `mods/emberwear/` is a complete example (two hairstyles, a face, three armor pieces, a palette, an armor set and a cel style). Check your mod without starting the game:

```sh
python3 tools/zig.py build validate-mods               # every mod under mods/
python3 tools/zig.py build validate-mods -- mods/mine  # one mod directory
```

It prints `ok <mod>: ...` or `REJECTED <mod>` followed by one `file: key: reason (detail)` line per problem (up to 16), and exits non-zero on any rejection. It also builds the example mod's WebAssembly first, because it loads packages exactly as the game does.

### Files and ids

```json
{
  "format": 1,
  "hair_styles":   [ { "id": "flame_crest", "name": "Flame Crest", "base": "crest", "spike": 0.8 } ],
  "face_presets":  [ ... ],
  "armor_pieces":  [ ... ],
  "armor_sets":    [ ... ],
  "palettes":      [ ... ],
  "cel_styles":    [ ... ]
}
```

Every section is optional and a mod may spread sections across files. Each entry needs:

- `id`: lowercase letters, digits and underscores, up to 23 characters, unique within its kind in your mod.
- `name`: the label shown in the creator, 1 to 31 printable ASCII characters.

The game addresses an entry as `<mod>.<id>`, for example `emberwear.flame_crest`. That namespaced string is also what a save stores, so two mods can both define `ember` without clobbering each other, and a mod cannot redefine another mod's ids. Limits: 64 entries per mod and 256 in the whole game. Keys the schema does not list are errors, not ignored, so a typo like `"spikes"` is caught instead of silently doing nothing. Numbers are plain JSON numbers; colors are `"#rrggbb"` or `[r, g, b]` with channels from 0 to 1. Listing order is by mod name and then declaration order, so it never depends on directory order.

### Schema reference

Defaults apply when a key is omitted. Keys marked required have none. The tables in `src/game/CharacterContent.zig` (`schema`) are the source of truth; this is the same data.

| Kind | Key | Type and range | Default |
| --- | --- | --- | --- |
| `hair_styles` | `base` | built-in hair tag (`short`, `crest`, `bob`, `swept_back`, ...): the look used wherever the game cannot yet draw the mod style | `short` |
| | `length` | 0.1 to 2 | 1 |
| | `volume` | 0.5 to 2.5 | 1 |
| | `curl`, `spike` | 0 to 1 | 0 |
| | `parting` | -1 to 1 | 0 |
| | `cards` | whole number 8 to 64 (strand cards) | 24 |
| | `tip_color` | color, optional | unset |
| | `tint_slot` | `hair`, `highlight`, `accent` | `hair` |
| `face_presets` | `base` | built-in face tag (`classic`, `soft`, `angular`, `heroic`, `alien`) | `classic` |
| | `jaw_width`, `chin_height`, `nose_length`, `mouth_width` | 0.7 to 1.3 | 1 |
| | `cheek_fullness`, `lip_fullness` | 0.5 to 1.5 | 1 |
| | `eye_size` | 0.7 to 1.4 | 1 |
| | `eye_spacing` | 0.8 to 1.2 | 1 |
| | `eye_tilt`, `brow_height` | -1 to 1 | 0 |
| `armor_pieces` | `part` (required) | `helmet`, `pauldron`, `chest`, `bracer`, `gauntlet`, `belt`, `tasset`, `greave`, `boot`, `back` | |
| | `attach_joint` (required) | `head`, `neck`, `chest`, `spine`, `shoulder`, `upper_arm`, `forearm`, `hand`, `hip`, `thigh`, `shin`, `foot` | |
| | `silhouette` | `plate`, `wedge`, `dome`, `ring`, `blade`, `fin`, `cylinder`, `cone` | `plate` |
| | `size` | `[x, y, z]`, each 0.02 to 1.5 (metres) | `[0.2, 0.2, 0.2]` |
| | `offset` | `[x, y, z]` from the joint, each -0.5 to 0.5 | `[0, 0, 0]` |
| | `flare` | 0 to 2 | 0 |
| | `emissive` | 0 to 1 | 0 |
| | `fins` | whole number 0 to 8 | 0 |
| | `bevel` | 0 to 1 | 0.2 |
| | `mirror` | `true` places a matching piece on the other side | `true` |
| | `tint` | `outfit`, `accent`, `trim`, `metal` | `outfit` |
| `armor_sets` | `pieces` (required) | 1 to 12 ids of `armor_pieces` in the same mod | |
| | `base` | built-in armor tag (`none`, `scout`, `sentinel`, `rootweave`, `skyguard`, `gem_aegis`, `starforge`, `deep_prism`) | `none` |
| | `palette` | id of a `palettes` entry in the same mod, optional | unset |
| `palettes` | `role` (required) | `hair`, `outfit`, `accent`, `skin`, `coat` | |
| | `colors` (required) | 1 to 8 colors | |
| `cel_styles` | `bands` | whole number 2 to 6 | 3 |
| | `band_thresholds` | exactly `bands - 1` strictly ascending numbers in 0 to 1, optional (evenly spaced if omitted) | unset |
| | `shadow_tint` | color | a soft blue-violet |
| | `outline_color` | color | near black |
| | `rim_color` | color, optional | unset |
| | `outline_width` | 0 to 4 (pixels) | 1.5 |
| | `rim_strength` | 0 to 1 | 0.3 |
| | `specular_size` | 0 to 1 | 0.2 |
| | `saturation` | 0.5 to 1.5 | 1 |

References between entries use local ids (no `mod.` prefix) and must exist in the same mod, so a mod never depends on load order or on another mod being installed.

### Authoring guide

1. Copy `mods/emberwear/` to `mods/<yourmod>/`, set `name` in `mod.json` to the same lowercase name as the directory, and list your files under `"character"`.
2. Start from a built-in: set `base` to the nearest built-in hairstyle, face or armor. Wherever the game cannot yet draw your parameters, players see that built-in, never an empty slot.
3. Build armor from pieces. Declare each piece once (`part`, `attach_joint`, `silhouette`), tune `flare`, `fins` and `bevel`, nudge it with `offset`, and let `mirror` supply the other side. Then list the pieces in an `armor_sets` entry.
4. Run `build validate-mods -- mods/<yourmod>` after each edit.
5. In the game, open the creator (new game, or Customize). Your hairstyles appear after the built-in ones on the HAIR style row, faces on FACE style, armor sets on ARMOR, palettes after the outfit colors, and cel styles on the RENDER STYLE row (which reads "default" until a mod adds one).

A rejected mod installs nothing: not its blueprints, scripts or character content. The log shows the same `file: key: reason` lines as the validator.

### Saves

A player's chosen mod content is stored in their profile as namespaced ids (`"mod": {"hair_style": "emberwear.flame_crest"}`), never as indexes, so installing or removing other mods does not change anyone's look. Save format **15** adds this field; formats 12 to 14 still load and simply have no mod choices. If a mod is missing when a save loads, the profile keeps the id (the look returns when the mod does) and the character uses its built-in hair style, face style, armor or outfit color meanwhile. The render style row then reads "default (mod missing)". A malformed id (anything but lowercase `mod.id`) makes the profile invalid, like any other bad field.

### Validation errors

| Reason | Meaning and fix |
| --- | --- |
| `not valid JSON` | Syntax error; the detail is the parser's message. Check commas and quotes. |
| `wrong JSON type` | The value has the wrong shape: a string where a number belongs, `offset` without 3 numbers. |
| `required key is missing` | Add the key. For `format`, write `"format": 1`. |
| `unknown key (typo?)` | The key is not in the schema table; the detail lists the valid ones. |
| `value out of range` | Outside the range in the table, or `band_thresholds` not strictly ascending. |
| `not one of the allowed values` | Use one of the listed strings; the detail lists them. |
| `bad id` | Ids are lowercase letters, digits and underscores, at most 23 characters. References never carry a `mod.` prefix. |
| `bad display name`, `text too long` | 1 to 31 printable ASCII characters, not starting with a space. |
| `bad color` | Use `"#rrggbb"` or `[r, g, b]` with channels 0 to 1. |
| `id already declared in this mod` | Two entries of one kind share an id. |
| `refers to an id this mod does not declare` | A set names a piece or palette that is not in this mod; check spelling and kind. |
| `too many entries or items` | Over 64 entries in the mod, or a list longer than its limit. |
| `values contradict each other` | `band_thresholds` must have `bands - 1` items. |
| `mod already installed with different content`, `registry is full` | A second package with the same mod name, or more than 256 entries game-wide. |

Manifest-level failures (`UnsafePath`, `MissingFile`, `TooManyCharacterFiles`, `InvalidCharacterContent`) are reported by name with the other package errors.

### For developers: binding the content

Content flows as data only. `mod/Mod.zig` loads and validates, `Sandbox.installMod` installs into `Sandbox.characters` (a `CharacterContent.Registry`), the Creator lists it, and `Profile.mod` stores the choice. Renderers read an entry through typed getters and never see JSON:

```zig
const handle = profile.mod.resolve(.hair_style, sandbox.characters) orelse return builtin;
const entry = sandbox.characters.?.get(handle);
const spike = entry.float("spike").?;  // also int, boolean, choice, vec3, color, colorAt, list, refAt
```

Parameters come from the `schema` tables in `CharacterContent.zig`; adding one is a `Param` line plus the reader. The systems being built alongside this layer bind as follows:

| System | Struct fields it should accept | Read from |
| --- | --- | --- |
| Hair (`HairStyleDef`) | base style tag, length, volume, curl, spike, parting, card count, tip color, tint slot | `hair_style` entries |
| Head and face (`HeadSpec`) | base face tag, jaw width, chin height, cheek fullness, eye size, spacing, tilt, brow height, nose length, mouth width, lip fullness | `face_preset` entries |
| Armor pieces (`ShapeSpec`) | part, attach joint, silhouette, size, offset, flare, fin count, bevel, mirror, tint, emissive | `armor_piece` entries |
| Armor sets (`ArmorSetDef`) | base armor tag, piece list (`refAt("pieces", i)`), optional palette (`refAt("palette", 0)`) | `armor_set` entries |
| Palettes | role and 1 to 8 colors | `palette` entries (`colorAt("colors", i)`) |
| `CelStyle` | band count, thresholds, shadow tint, outline width and color, rim strength and color, specular size, saturation | `cel_style` entries |

The binding is mechanical: for each kind, write a function that turns an `Entry` into the struct, and call it where the character is built. `Selection.resolve` returns null when the choice is unset or its mod is missing, so the built-in path stays the default. Enum-valued parameters arrive as strings from `choice`; map them with `std.meta.stringToEnum` against the new enums. The test "schema base choices name real Profile enum tags" in `Creator.zig` fails if a listed `base` tag stops matching `Profile`, which is the cue to update the tables.

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

Saves (format 10 and later) list the installed mods by name and version. Blueprints placed from a mod are saved in full, like any machine, so a world still loads without the mod. The game reports each missing or different mod, and its scripts output 0 until it is installed again.

## Not in API 1

Mods cannot yet add Arbor genomes, shrine templates, market wares, meshes, or textures (character content is parametric data, not meshes). Static `.gltf`/`.glb` sources already compile to HWMS; `asset-compiler trace` records source lineage and `asset-compiler split` exports node/mesh/primitive modules, but model modules are not yet installable game content. Scripts get no host functions: no world queries, logging, or randomness beyond their inputs. There is no dependency or load-order declaration (mods load in directory order and cannot reference each other), no package reload, and no sandboxing beyond the interpreter. A mod's blueprints are trusted to be as harmless as any blueprint a player could build. See the [scripting evaluation](scripting.md) for why scripting is a WebAssembly interpreter.

## Development script reload

Run with `-Dhot-reload=true`, edit the mod's Zig source, then run `python3 tools/zig.py build mods` in another terminal. The watcher observes the compiled `.wasm` path recorded when the package loaded. It validates and stages the replacement on a worker, preserving registered script names and machine device state. Malformed modules, missing exports and signature changes leave the current module running. Export declarations, fuel/memory limits, package manifests and mod blueprints are fixed for the session; restart after changing them.
