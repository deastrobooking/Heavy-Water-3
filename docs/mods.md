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

A mod adds options to the character creator by listing data files under `"character"` in `mod.json`. Everything is JSON, validated before anything is installed, and there is no code to run. `mods/emberwear/` is a complete example (two hairstyles, a face, a finned armor set, a palette and an ink cel style). Check your mod without starting the game:

```sh
python3 tools/zig.py build validate-mods               # every mod under mods/
python3 tools/zig.py build validate-mods -- mods/mine  # one mod directory
```

It prints `ok <mod>: ...` or `REJECTED <mod>` followed by one `file: key: reason (detail)` line per problem (up to 16), and exits non-zero on any rejection. It also builds the example mod's WebAssembly first, because it loads packages exactly as the game does.

### Files and ids

```json
{
  "format": 1,
  "hair_styles":  [ { "id": "flame_crest", "name": "Flame Crest", "clumps": [ { "az": 0, "el": 1.3, "pitch": 1.35, "length": 0.95 } ] } ],
  "face_presets": [ ... ],
  "armor_sets":   [ ... ],
  "palettes":     [ ... ],
  "cel_styles":   [ ... ]
}
```

Every section is optional and a mod may spread sections across files. Each entry needs:

- `id`: lowercase letters, digits and underscores, up to 23 characters, unique within its kind in your mod.
- `name`: the label shown in the creator, 1 to 31 printable ASCII characters.

The game addresses an entry as `<mod>.<id>`, for example `emberwear.flame_crest`. That namespaced string is also what a save stores, so two mods can both define `ember` without clobbering each other, and a mod cannot redefine another mod's ids. Limits: 64 entries per mod and 256 in the whole game. Keys the schema does not list are errors, not ignored, so a typo like `"lenght"` is caught instead of silently doing nothing. Numbers are plain JSON numbers; armor colors are `"#rrggbb"` or `[r, g, b]`. Listing order is by mod name and then declaration order.

### Schema reference

The schema is the game's own data structs, so a key is a field name and its value has that field's type. Omitted keys keep the struct's default. The doc comments on the structs are the full reference; this is the map.

| Kind | Maps to | Keys |
| --- | --- | --- |
| `hair_styles` | `hair_style.StyleDef` in `src/character/hair_style.zig` | `clumps` (required, list of `ClumpDef`, at most 96 counting `mirror` twins twice), `cap` (`CapDef`: `hairline`, five numbers; `lift`) |
| | `ClumpDef` | `az`, `el` (required); `yaw`, `pitch`, `length`, `width`, `thickness`, `taper`, `curl`, `flick`, `stand`, `layer` (whole 0 to 3), `spike`, `sway`, `mirror` |
| `face_presets` | `spec.FacePreset` in `src/character/spec.zig` | `masculine`, `feminine` (`spec.HeadSpec`: `cranium_width`, `cranium_depth`, `cranium_size`, `cheek_width`, `cheek_height`, `jaw_taper`, `chin_width`, `chin_point`, `chin_jut`, `neck_length`, `neck_thickness`, `brow_ridge`, `cheek_fullness`, `nose_bridge`, `nose_tip`), `head_ratio`, `eye_size_scale`, `eye_aspect_scale`, `eye_tilt`, `eye_height_add`, `brow_weight`, `brow_tilt`, `brow_gap`, `nose_mark`, `mouth_width` |
| `armor_sets` | `armor.ArmorSetDef` in `src/character/armor.zig` | `metal`, `secondary`, `trim` (required colors), `dark`, `shape` (`spec.ShapeSpec`: `silhouette`, `flare`, `crest`, `roundness`, `overlap`), `visor`, `pieces` (list of `armor.Piece`, at most 64) |
| | `armor.Piece` | `kind`, `anchor` (required); `sides`, `when`, `offset`, `size`, `scale`, `tilt`, `exponent`, `taper`, `color`, `material`, `fit`, `shape` (optional, overrides the set's) |
| `cel_styles` | `CelStyle.CelStyle` in `src/character/CelStyle.zig` | `base` (`heavy_water`, `watercolor`, `comic_ink`, `flat`: the preset you start from), `face_softness`, `outline_scale`, `outline_min_world`, `outline_max_world`, `materials` (an object keyed by material name, each a partial `MaterialStyle`: `ramp`, `rim`, `specular`, `outline`, `emissive`; unnamed fields keep the base's values) |
| `palettes` | creator swatches | `role` (`hair`, `outfit`, `accent`, `skin`, `coat`), `colors` (1 to 8). Listed in the creator; **not drawn yet** |

Enum-valued fields take the Zig tag as a string (`"kind": "dome_pauldron"`, `"anchor": "upper_arm"`); a wrong one lists the valid choices. The ranges are the real validators': `ArmorSetDef.validate`, `hair_style.validate`, `CelStyle.validate`, and for heads the limits in `CharacterContent.zig` (every built-in face lies inside them). Pieces are placed in meters on a 1.8 m body, relative to their anchor joint (see the header of `armor.zig` for the axes).

### Authoring guide

1. Copy `mods/emberwear/` to `mods/<yourmod>/`, set `name` in `mod.json` to the same lowercase name as the directory, and list your files under `"character"`.
2. Start from something that looks right: copy a piece list or clump list from `armor.zig` or `hair_library.zig` and change numbers. A cel style starts from a preset with `base`.
3. Run `python3 tools/zig.py build validate-mods -- mods/<yourmod>` after each edit. Every problem is one `file: key: reason (detail)` line, with the key path down to the field (`armor_sets[0].pieces[2].shape.crest`).
4. In the game, open the creator (new game, or Customize). Hairstyles appear after the built-in ones on HAIR style, faces on FACE style, armor sets on ARMOR (they replace the built-in armor, whatever its tag), palettes after the outfit colors, and cel styles on RENDER STYLE.
5. To review without the creator, run with `-Dcharacter-showcase=40` (hair, face and cel style of emberwear), `41` (phoenix armor over a hardsuit, visor), `42` (sealed helmet) or `43` (second hairstyle, exo rig). These expect a mod named `emberwear`.

A rejected mod installs nothing: not its blueprints, scripts or character content. The log shows the same `file: key: reason` lines as the validator.

What is drawn: the hair clumps (`HairSpec.custom`, still shaped by the player's spike, volume and length sliders and hair color), both heads and the eye and brow numbers of the face, the whole armor set (pieces, colors, shape, visor; its `shape` also drives hardsuit plates), and the cel style. A cel style applies to that player's characters only (each character id has its own table); the F3 look-dev preset applies to characters whose player picked none.

### Saves

A player's chosen mod content is stored in their profile as namespaced ids (`"mod": {"hair_style": "emberwear.flame_crest"}`), never as indexes, so installing or removing other mods does not change anyone's look. Save format **15** adds this field; formats 12 to 14 still load and simply have no mod choices. If a mod is missing when a save loads, the profile keeps the id (the look returns when the mod does) and the character uses its built-in hair style, face style, armor or cel style meanwhile; the render style row then reads "default (mod missing)". A malformed id (anything but lowercase `mod.id`) makes the profile invalid, like any other bad field.

### Validation errors

| Reason | Meaning and fix |
| --- | --- |
| `not valid JSON` | Syntax error; the detail is the parser's message. Check commas and quotes. |
| `wrong JSON type` | The value has the wrong shape: a string where a number belongs, `offset` without 3 numbers. |
| `required key is missing` | Add the key (`format`, `clumps`, `az`/`el`, `kind`/`anchor`, `metal`/`secondary`/`trim`). |
| `unknown key (typo?)` | Not a field of the struct; the detail lists the valid ones. |
| `value out of range` | Outside the struct validator's range; the detail gives the range for that field. |
| `not one of the allowed values` | Use one of the listed strings. |
| `bad id`, `bad display name`, `text too long` | Ids: lowercase letters, digits, underscores, at most 23. Names: 1 to 31 printable ASCII characters. |
| `bad color` | Use `"#rrggbb"` or `[r, g, b]`. |
| `id already declared in this mod` | Two entries of one kind share an id. |
| `too many entries or items` | Over 64 entries, 96 clumps, 64 pieces or 8 palette colors. |
| `values contradict each other` | A `center` piece on a limb anchor, or head proportions that give a degenerate outline. |
| `mod already installed with different content`, `registry is full` | A second package with the same mod name, or more than 256 entries game-wide. |

Manifest-level failures (`UnsafePath`, `MissingFile`, `TooManyCharacterFiles`, `InvalidCharacterContent`) are reported by name with the other package errors.

### For developers: binding the content

`mod/Mod.zig` loads and validates, `Sandbox.installMod` installs into `Sandbox.characters` (a `CharacterContent.Registry`), the Creator lists it, `Profile.mod` stores the choice and `App` hands the registry to `Renderer.characters`. Parsing is reflection over the real structs, so a field added to `ClumpDef`, `Piece`, `HeadSpec`, `MaterialStyle` and the rest is a valid key immediately; a new field on `ArmorSetDef` or `StyleDef` fails a comptime check in `CharacterContent.zig` until it is classified. The conversions are the binding:

```zig
const def = try CharacterContent.armorSet(entry);   // armor.ArmorSetDef, validated
const style = try CharacterContent.hairStyle(entry); // hair_style.StyleDef; HairSpec.custom = &style
const face = try CharacterContent.facePreset(entry); // spec.FacePreset (also headSpec)
const cel = try CharacterContent.celStyle(entry);    // CelStyle.CelStyle, ready for CelStyle.pack
```

`Ranger.initContent(a, profile, registry)` resolves `profile.mod` for each slot and falls back to the built-in choice when the id is unset, the mod is missing, or the entry no longer validates. The results borrow the entry's storage, so the registry must outlive the build. `Ranger.sameAppearance` compares the whole profile including `mod`, and `Characters` also rebuilds a character when mod content installs after it was built. `Renderer` keeps one cel table per character id (dynamic offset in the skinned bind group).

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
