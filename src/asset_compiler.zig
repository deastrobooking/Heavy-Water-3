const std = @import("std");
const Gltf = @import("asset/Gltf.zig");
const Model = @import("asset/Model.zig");
const Blueprint = @import("machine/Blueprint.zig");
const Meta = @import("asset/Meta.zig");
const Guid = @import("asset/Guid.zig");
const Registry = @import("asset/Registry.zig");
const Heightmap = @import("procedural/Heightmap.zig");
const Synth = @import("audio/Synth.zig");
const Raster = @import("character/raster.zig");
const CharacterMath = @import("character/math.zig");
const CharacterSpec = @import("character/spec.zig");
const Modifiers = @import("asset/Modifiers.zig");

/// Build-time tool:
///   asset-compiler compile <source> <source.meta> <output>
///       check the sidecar (GUID, kind, importer, settings, unchanged source), then compile a
///       glTF model, validate a blueprint, or compile a PGM heightmap
///   asset-compiler trace <source.glb|source.gltf> <source.meta> <output.json>
///       validate asset identity and write a source-to-module report for 3D review/mod packaging
///   asset-compiler split <source.glb|source.gltf> <source.meta> <output-directory>
///       write one validated HWMS module per selected-scene node/mesh/primitive and modules.json
///   asset-compiler preview-bind <source.glb|source.gltf> <source.meta> <output.png> [bind|run]
///       CPU-skin the bind pose or the game's native procedural run pose into a review PNG
///   asset-compiler modifiers <source.glb|source.gltf> <source.meta> <output.json>
///       create a source-linked, auto-labeled Captain modifier document for editing
///   asset-compiler preview-modified <source.glb|source.gltf> <source.meta> <modifiers.json> <output.png> [bind|run]
///       apply palette, label and per-part shape edits, then render a review PNG
///   asset-compiler compile-modified <source.glb|source.gltf> <source.meta> <modifiers.json> <output.hwmesh> [bind|run]
///       compile a source-hash-validated, modifier-baked static model for the game
///   asset-compiler modifier-list <modifiers.json>
///       list editable connected mesh islands by stable source vertex ID
///   asset-compiler modifier-edit <input.json> <output.json> part <id> <property> <values...>
///       author one source-linked label/surface/color/scale/offset edit without replacing input
///       or: modifier-edit <input.json> <output.json> palette <skin|eyes|armor|energy> <r> <g> <b>
///   asset-compiler manifest <output> (<source.meta> <name> <output-name>)...
///       write the asset manifest the runtime registry loads
///   asset-compiler import <directory>
///       create missing sidecars (new GUIDs) and refresh hashes for every source under a
///       directory; existing GUIDs and settings are kept
///   asset-compiler sounds <directory>
///       write every synthesized game sound as a 16-bit mono WAV, for listening
///   asset-compiler heightmap <source.pgm> <output.hwmh> [world-width world-depth elevation base-height]
///       import ASCII or binary grayscale PGM data to the runtime heightmap format
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const io = init.io;
    if (args.len >= 2 and std.mem.eql(u8, args[1], "compile") and args.len == 5) return compile(init.gpa, io, args[2], args[3], args[4]);
    if (args.len == 5 and std.mem.eql(u8, args[1], "trace")) return trace(init.gpa, io, args[2], args[3], args[4]);
    if (args.len == 5 and std.mem.eql(u8, args[1], "split")) return split(init.gpa, io, args[2], args[3], args[4]);
    if ((args.len == 5 or args.len == 6) and std.mem.eql(u8, args[1], "preview-bind")) return previewBind(init.gpa, io, args[2], args[3], args[4], if (args.len == 6) args[5] else "bind");
    if (args.len == 5 and std.mem.eql(u8, args[1], "modifiers")) return createModifiers(init.gpa, io, args[2], args[3], args[4]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "modifier-list")) return listModifiers(init.gpa, io, args[2]);
    if (args.len >= 8 and std.mem.eql(u8, args[1], "modifier-edit")) return editModifiers(init.gpa, io, args[2..]);
    if ((args.len == 6 or args.len == 7) and std.mem.eql(u8, args[1], "preview-modified")) return previewModified(init.gpa, io, args[2], args[3], args[4], args[5], if (args.len == 7) args[6] else "bind");
    if ((args.len == 6 or args.len == 7) and std.mem.eql(u8, args[1], "compile-modified")) return compileModified(init.gpa, io, args[2], args[3], args[4], args[5], if (args.len == 7) args[6] else "bind");
    if (args.len >= 3 and std.mem.eql(u8, args[1], "manifest") and (args.len - 3) % 3 == 0) return manifest(init.gpa, io, args[2], args[3..]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "import")) return import(init.gpa, io, args[2]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "sounds")) return writeSounds(init.gpa, io, args[2]);
    if (args.len == 4 or args.len == 8) if (std.mem.eql(u8, args[1], "heightmap")) return compileHeightmap(init.gpa, io, args[2], args[3], args[4..]);
    std.log.err("usage: asset-compiler compile <source> <meta> <output> | trace <source> <meta> <output.json> | split <source> <meta> <output-dir> | preview-bind <source> <meta> <output.png> [bind|run] | modifiers <source> <meta> <output.json> | modifier-list <modifiers.json> | modifier-edit <input.json> <output.json> part <id> <property> <values...> | modifier-edit <input.json> <output.json> palette <slot> <r> <g> <b> | preview-modified <source> <meta> <modifiers.json> <output.png> [bind|run] | compile-modified <source> <meta> <modifiers.json> <output.hwmesh> [bind|run] | manifest ... | import <dir> | heightmap ...", .{});
    return error.InvalidArguments;
}

fn listModifiers(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const bytes = try readFile(gpa, io, path);
    defer gpa.free(bytes);
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const doc = try std.json.parseFromSliceLeaky(Modifiers.Document, arena.allocator(), bytes, .{});
    std.log.info("{s}: {d} editable islands; color values are RGB 0..1", .{ path, doc.parts.len });
    for (doc.parts) |part| std.log.info("id {d:>5} | {s:<24} | {s:<7} | {d:>5} verts | center {d:.3}, {d:.3}, {d:.3}", .{
        part.id, part.label, @tagName(part.surface), part.vertex_count, part.center[0], part.center[1], part.center[2],
    });
}

fn editModifiers(gpa: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len < 5) return error.InvalidModifierEdit;
    if (std.mem.eql(u8, args[0], args[1])) return error.ModifierInputIsOutput;
    const input_bytes = try readFile(gpa, io, args[0]);
    defer gpa.free(input_bytes);
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    var doc = try std.json.parseFromSliceLeaky(Modifiers.Document, allocator, input_bytes, .{});

    if (std.mem.eql(u8, args[2], "palette")) {
        if (args.len != 7) return error.InvalidModifierEdit;
        const slot = std.meta.stringToEnum(Modifiers.Palette, args[3]) orelse return error.InvalidModifierEdit;
        try Modifiers.edit(allocator, &doc, .{ .palette = .{ .slot = slot, .value = try parseColor(args[4..7]) } });
    } else if (std.mem.eql(u8, args[2], "part")) {
        const id = std.fmt.parseInt(u32, args[3], 10) catch return error.InvalidModifierEdit;
        const property = args[4];
        if (std.mem.eql(u8, property, "label")) {
            if (args.len != 6) return error.InvalidModifierEdit;
            try Modifiers.edit(allocator, &doc, .{ .label = .{ .id = id, .value = args[5] } });
        } else if (std.mem.eql(u8, property, "surface")) {
            if (args.len != 6) return error.InvalidModifierEdit;
            const surface = std.meta.stringToEnum(Modifiers.Surface, args[5]) orelse return error.InvalidModifierEdit;
            try Modifiers.edit(allocator, &doc, .{ .surface = .{ .id = id, .value = surface } });
        } else if (std.mem.eql(u8, property, "color")) {
            if (args.len == 6 and std.mem.eql(u8, args[5], "clear")) {
                try Modifiers.edit(allocator, &doc, .{ .color = .{ .id = id, .value = null } });
            } else {
                if (args.len != 8) return error.InvalidModifierEdit;
                try Modifiers.edit(allocator, &doc, .{ .color = .{ .id = id, .value = try parseColor(args[5..8]) } });
            }
        } else if (std.mem.eql(u8, property, "scale") or std.mem.eql(u8, property, "offset")) {
            if (args.len != 8) return error.InvalidModifierEdit;
            const vector = try parseColor(args[5..8]);
            if (std.mem.eql(u8, property, "scale")) {
                try Modifiers.edit(allocator, &doc, .{ .scale = .{ .id = id, .value = vector } });
            } else {
                try Modifiers.edit(allocator, &doc, .{ .offset = .{ .id = id, .value = vector } });
            }
        } else return error.InvalidModifierEdit;
    } else return error.InvalidModifierEdit;

    const json = try std.json.Stringify.valueAlloc(gpa, doc, .{ .whitespace = .indent_2 });
    defer gpa.free(json);
    if (std.fs.path.dirname(args[1])) |parent| {
        if (std.fs.path.isAbsolute(parent)) {
            var directory = try std.Io.Dir.openDirAbsolute(io, parent, .{});
            defer directory.close(io);
            try directory.writeFile(io, .{ .sub_path = std.fs.path.basename(args[1]), .data = json });
        } else {
            try std.Io.Dir.cwd().createDirPath(io, parent);
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[1], .data = json });
        }
    } else {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[1], .data = json });
    }
    std.log.info("modifier edit written to {s}; preview it with `asset-compiler preview-modified`", .{args[1]});
}

fn parseColor(values: []const []const u8) ![3]f32 {
    if (values.len != 3) return error.InvalidModifierEdit;
    var result: [3]f32 = undefined;
    for (values, 0..) |value, i| result[i] = std.fmt.parseFloat(f32, value) catch return error.InvalidModifierEdit;
    return result;
}

fn writeSounds(gpa: std.mem.Allocator, io: std.Io, directory: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, directory);
    for (0..Synth.sound_count) |i| {
        const sound: Synth.Sound = @enumFromInt(i);
        const samples = try Synth.generate(gpa, sound);
        defer gpa.free(samples);
        const bytes = try gpa.alloc(u8, 44 + samples.len * 2);
        defer gpa.free(bytes);
        // RIFF/WAVE header: PCM, mono, 16-bit.
        @memcpy(bytes[0..4], "RIFF");
        std.mem.writeInt(u32, bytes[4..8], @intCast(bytes.len - 8), .little);
        @memcpy(bytes[8..16], "WAVEfmt ");
        std.mem.writeInt(u32, bytes[16..20], 16, .little);
        std.mem.writeInt(u16, bytes[20..22], 1, .little);
        std.mem.writeInt(u16, bytes[22..24], 1, .little);
        std.mem.writeInt(u32, bytes[24..28], Synth.rate, .little);
        std.mem.writeInt(u32, bytes[28..32], Synth.rate * 2, .little);
        std.mem.writeInt(u16, bytes[32..34], 2, .little);
        std.mem.writeInt(u16, bytes[34..36], 16, .little);
        @memcpy(bytes[36..40], "data");
        std.mem.writeInt(u32, bytes[40..44], @intCast(samples.len * 2), .little);
        for (samples, 0..) |s, k| std.mem.writeInt(i16, bytes[44 + k * 2 ..][0..2], @intFromFloat(std.math.clamp(s, -1, 1) * 32767), .little);
        var name: [64]u8 = undefined;
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name, "{s}/{s}.wav", .{ directory, @tagName(sound) }), .data = bytes });
    }
    std.log.info("sounds: {d} WAV files in {s}", .{ Synth.sound_count, directory });
}

fn readFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20));
}

fn compileHeightmap(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, output_path: []const u8, settings_args: []const []const u8) !void {
    var settings: Heightmap.Settings = .{};
    if (settings_args.len != 0) {
        settings.world_width = std.fmt.parseFloat(f32, settings_args[0]) catch return error.InvalidSettings;
        settings.world_depth = std.fmt.parseFloat(f32, settings_args[1]) catch return error.InvalidSettings;
        settings.elevation = std.fmt.parseFloat(f32, settings_args[2]) catch return error.InvalidSettings;
        settings.base_height = std.fmt.parseFloat(f32, settings_args[3]) catch return error.InvalidSettings;
    }
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const heightmap = try Heightmap.importPgm(gpa, source, settings);
    defer heightmap.deinit(gpa);
    const output = try heightmap.encode(gpa);
    defer gpa.free(output);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = output });
    std.log.info("heightmap: {d}x{d}, {d:.1}x{d:.1} m, elevations {d:.1}..{d:.1} m -> {s}", .{
        heightmap.width,
        heightmap.height,
        settings.world_width,
        settings.world_depth,
        settings.base_height,
        settings.base_height + settings.elevation,
        output_path,
    });
}

fn compile(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, meta_path: []const u8, output: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const meta_bytes = readFile(gpa, io, meta_path) catch |err| {
        std.log.err("{s}: missing sidecar {s} ({s}); run `zig build import`", .{ source_path, meta_path, @errorName(err) });
        return error.MissingMeta;
    };
    defer gpa.free(meta_bytes);
    const meta = Meta.check(gpa, meta_bytes, source_path, source) catch |err| {
        std.log.err("{s}: {s}{s}", .{ meta_path, @errorName(err), if (err == error.StaleMeta or err == error.OldImporter) "; run `zig build import`" else "" });
        return err;
    };
    switch (meta.kind) {
        .blueprint => {
            _ = Blueprint.parse(gpa, source) catch |err| {
                std.log.err("{s}: {s}", .{ source_path, @errorName(err) });
                return err;
            };
            return cwd.writeFile(io, .{ .sub_path = output, .data = source });
        },
        .model => {
            var context: Context = .{ .io = io, .dir = std.fs.path.dirname(source_path) orelse "." };
            var model = Gltf.compile(gpa, source, .{ .context = &context, .load = Context.load }) catch |err| {
                std.log.err("{s}: {s}", .{ source_path, @errorName(err) });
                return err;
            };
            defer model.deinit(gpa);
            if (meta.model.scale != 1) {
                for (model.mesh.vertices) |*v| for (&v.position) |*c| {
                    c.* *= meta.model.scale;
                };
                model.computeBounds();
            }
            const bytes = try model.encode(gpa);
            defer gpa.free(bytes);
            try cwd.writeFile(io, .{ .sub_path = output, .data = bytes });
        },
        .heightmap => {
            const heightmap = try Heightmap.importPgm(gpa, source, meta.heightmap);
            defer heightmap.deinit(gpa);
            const bytes = try heightmap.encode(gpa);
            defer gpa.free(bytes);
            try cwd.writeFile(io, .{ .sub_path = output, .data = bytes });
        },
        else => return error.UnsupportedKind,
    }
}

fn trace(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, meta_path: []const u8, output_path: []const u8) !void {
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const meta_bytes = try readFile(gpa, io, meta_path);
    defer gpa.free(meta_bytes);
    const meta = try Meta.check(gpa, meta_bytes, source_path, source);
    if (meta.kind != .model) return error.UnsupportedKind;
    const provenance = .{
        .source_path = source_path,
        .guid = meta.guid,
        .source_hash = Meta.hashSource(source),
        .importer = "gltf",
        .importer_version = Meta.importers.gltf,
        .scale = meta.model.scale,
    };
    const json = try Gltf.traceJson(gpa, source, provenance);
    defer gpa.free(json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = json });
    std.log.info("trace: {s} -> {s}", .{ source_path, output_path });
}

fn previewBind(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, meta_path: []const u8, output_path: []const u8, pose_name: []const u8) !void {
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const meta_bytes = try readFile(gpa, io, meta_path);
    defer gpa.free(meta_bytes);
    const meta = try Meta.check(gpa, meta_bytes, source_path, source);
    if (meta.kind != .model) return error.UnsupportedKind;
    var context: Context = .{ .io = io, .dir = std.fs.path.dirname(source_path) orelse "." };
    const pose: Gltf.PreviewPose = if (std.mem.eql(u8, pose_name, "bind")) .bind else if (std.mem.eql(u8, pose_name, "run")) .run else return error.InvalidPreviewPose;
    var model = try Gltf.compilePosePreview(gpa, source, .{ .context = &context, .load = Context.load }, pose);
    defer model.deinit(gpa);
    if (meta.model.scale != 1) {
        for (model.mesh.vertices) |*v| {
            for (&v.position) |*c| c.* *= meta.model.scale;
        }
        model.computeBounds();
    }
    var image = try renderBindPose(gpa, &model, null);
    defer image.deinit(gpa);
    var png: std.ArrayList(u8) = .empty;
    defer png.deinit(gpa);
    try image.writePng(gpa, &png);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = png.items });
    std.log.info("{s} preview: {d} vertices, {d} triangles -> {s} (CPU-skinned review image; rig not included in HWMS)", .{ @tagName(pose), model.mesh.vertices.len, model.mesh.indices.len / 3, output_path });
}

fn createModifiers(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, meta_path: []const u8, output_path: []const u8) !void {
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const meta_bytes = try readFile(gpa, io, meta_path);
    defer gpa.free(meta_bytes);
    const meta = try Meta.check(gpa, meta_bytes, source_path, source);
    if (meta.kind != .model) return error.UnsupportedKind;
    var context: Context = .{ .io = io, .dir = std.fs.path.dirname(source_path) orelse "." };
    var model = try Gltf.compilePosePreview(gpa, source, .{ .context = &context, .load = Context.load }, .bind);
    defer model.deinit(gpa);
    if (meta.model.scale != 1) {
        for (model.mesh.vertices) |*vertex| {
            for (&vertex.position) |*axis| axis.* *= meta.model.scale;
        }
    }
    model.computeBounds();
    const hash = Meta.hashSource(source);
    const document = try Modifiers.generate(gpa, model, &hash);
    defer Modifiers.deinit(gpa, document);
    const json = try std.json.Stringify.valueAlloc(gpa, document, .{ .whitespace = .indent_2 });
    defer gpa.free(json);
    if (std.fs.path.dirname(output_path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = json });
    std.log.info("modifiers: generated {d} auto-labeled mesh islands for {s} (edit labels, surfaces, colors, and scales in {s})", .{ document.parts.len, @tagName(document.character_type), output_path });
}

fn previewModified(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, meta_path: []const u8, modifiers_path: []const u8, output_path: []const u8, pose_name: []const u8) !void {
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const meta_bytes = try readFile(gpa, io, meta_path);
    defer gpa.free(meta_bytes);
    const modifier_bytes = try readFile(gpa, io, modifiers_path);
    defer gpa.free(modifier_bytes);
    const meta = try Meta.check(gpa, meta_bytes, source_path, source);
    if (meta.kind != .model) return error.UnsupportedKind;
    const parsed = try std.json.parseFromSlice(Modifiers.Document, gpa, modifier_bytes, .{});
    defer parsed.deinit();
    var context: Context = .{ .io = io, .dir = std.fs.path.dirname(source_path) orelse "." };
    const pose: Gltf.PreviewPose = if (std.mem.eql(u8, pose_name, "bind")) .bind else if (std.mem.eql(u8, pose_name, "run")) .run else return error.InvalidPreviewPose;
    var model = try Gltf.compilePosePreview(gpa, source, .{ .context = &context, .load = Context.load }, pose);
    defer model.deinit(gpa);
    if (meta.model.scale != 1) {
        for (model.mesh.vertices) |*vertex| {
            for (&vertex.position) |*axis| axis.* *= meta.model.scale;
        }
    }
    model.computeBounds();
    const analysis = try Modifiers.apply(gpa, &model, parsed.value, &Meta.hashSource(source));
    defer gpa.free(analysis.vertex_parts);
    defer gpa.free(analysis.components);
    const triangle_colors = try gpa.alloc([3]f32, model.mesh.indices.len / 3);
    defer gpa.free(triangle_colors);
    for (triangle_colors, 0..) |*color, i| color.* = Modifiers.triangleSurfaceColor(parsed.value, analysis, model, i);
    var image = try renderBindPose(gpa, &model, triangle_colors);
    defer image.deinit(gpa);
    var png: std.ArrayList(u8) = .empty;
    defer png.deinit(gpa);
    try image.writePng(gpa, &png);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = png.items });
    std.log.info("modified preview: {s}, {d} editable mesh islands, {d} vertices -> {s}", .{ @tagName(parsed.value.character_type), parsed.value.parts.len, model.mesh.vertices.len, output_path });
}

fn compileModified(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, meta_path: []const u8, modifiers_path: []const u8, output_path: []const u8, pose_name: []const u8) !void {
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const meta_bytes = try readFile(gpa, io, meta_path);
    defer gpa.free(meta_bytes);
    const modifier_bytes = try readFile(gpa, io, modifiers_path);
    defer gpa.free(modifier_bytes);
    const meta = try Meta.check(gpa, meta_bytes, source_path, source);
    if (meta.kind != .model) return error.UnsupportedKind;
    const parsed = try std.json.parseFromSlice(Modifiers.Document, gpa, modifier_bytes, .{});
    defer parsed.deinit();
    var context: Context = .{ .io = io, .dir = std.fs.path.dirname(source_path) orelse "." };
    const pose: Gltf.PreviewPose = if (std.mem.eql(u8, pose_name, "bind")) .bind else if (std.mem.eql(u8, pose_name, "run")) .run else return error.InvalidPreviewPose;
    var model = try Gltf.compilePosePreview(gpa, source, .{ .context = &context, .load = Context.load }, pose);
    defer model.deinit(gpa);
    if (meta.model.scale != 1) for (model.mesh.vertices) |*vertex| {
        for (&vertex.position) |*axis| axis.* *= meta.model.scale;
    };
    model.computeBounds();
    const source_hash = Meta.hashSource(source);
    const analysis = try Modifiers.apply(gpa, &model, parsed.value, &source_hash);
    defer gpa.free(analysis.vertex_parts);
    defer gpa.free(analysis.components);
    const encoded = try model.encode(gpa);
    defer gpa.free(encoded);
    if (std.fs.path.dirname(output_path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = encoded });
    std.log.info("compiled modified {s} mesh: {d} editable islands, {d} vertices -> {s}", .{ @tagName(parsed.value.character_type), parsed.value.parts.len, model.mesh.vertices.len, output_path });
}

const BindPoseShader = struct {
    light: CharacterMath.Vec3,
    low_y: f32,
    height: f32,
    triangle_colors: ?[][3]f32 = null,

    pub fn fragment(s: BindPoseShader, f: Raster.Fragment) ?CharacterSpec.Rgb {
        // Texture-free test assets still get a useful cel-material preview. The height ramp is
        // deliberately diagnostic, so parts and silhouette remain readable without authored UVs.
        const t = std.math.clamp((f.world.y - s.low_y) / s.height, 0, 1);
        const lower = CharacterSpec.Rgb.hex(0x263e60);
        const upper = CharacterSpec.Rgb.hex(0x73b9bf);
        const base = CharacterSpec.Rgb.init(
            lower.r + (upper.r - lower.r) * t,
            lower.g + (upper.g - lower.g) * t,
            lower.b + (upper.b - lower.b) * t,
        );
        const ndl = @max(f.normal.normalize().dot(s.light), 0);
        const band: f32 = if (ndl < 0.22) 0.48 else if (ndl < 0.58) 0.76 else 1.0;
        const tint = if (s.triangle_colors) |colors| if (f.tri < colors.len) colors[f.tri] else [3]f32{ 1, 1, 1 } else [3]f32{ 1, 1, 1 };
        return CharacterSpec.Rgb.init(base.r * band * tint[0], base.g * band * tint[1], base.b * band * tint[2]);
    }
};

fn renderBindPose(gpa: std.mem.Allocator, model: *const Model, triangle_colors: ?[][3]f32) !Raster.Image {
    const V = CharacterMath.Vec3;
    const width: usize = 512;
    const height: usize = 768;
    const factor: usize = 2;
    const lo = V.init(model.bounds_min[0], model.bounds_min[1], model.bounds_min[2]);
    const hi = V.init(model.bounds_max[0], model.bounds_max[1], model.bounds_max[2]);
    const center = lo.add(hi).scale(0.5);
    const extents = hi.sub(lo);
    const radius = @max(extents.length() * 0.5, 0.1);
    const fovy = CharacterMath.radians(32);
    const target = V.init(center.x, lo.y + extents.y * 0.50, center.z);
    const fit_distance = extents.y * 0.5 / @tan(fovy * 0.5) * 1.24;
    const distance = @max(fit_distance, radius * 3.5);
    const eye = target.add(V.init(distance * 0.07, distance * 0.035, distance));
    const W = width * factor;
    const H = height * factor;
    const aspect = @as(f32, @floatFromInt(W)) / @as(f32, @floatFromInt(H));
    const view_proj = CharacterMath.Mat4.perspective(fovy, aspect, @max(radius * 0.02, 0.01), distance + radius * 4).mul(CharacterMath.Mat4.lookAt(eye, target, V.unit_y));
    const positions = try gpa.alloc(V, model.mesh.vertices.len);
    defer gpa.free(positions);
    const normals = try gpa.alloc(V, model.mesh.vertices.len);
    defer gpa.free(normals);
    const uvs = try gpa.alloc(CharacterMath.Vec2, model.mesh.vertices.len);
    defer gpa.free(uvs);
    for (model.mesh.vertices, positions, normals, uvs) |vertex, *p, *n, *uv| {
        p.* = V.init(vertex.position[0], vertex.position[1], vertex.position[2]);
        n.* = V.init(vertex.normal[0], vertex.normal[1], vertex.normal[2]);
        uv.* = CharacterMath.Vec2.init(vertex.uv[0], vertex.uv[1]);
    }
    var image = try Raster.Image.init(gpa, W, H, CharacterSpec.Rgb.hex(0x101927));
    errdefer image.deinit(gpa);
    image.fillGradient(CharacterSpec.Rgb.hex(0x172a3b), CharacterSpec.Rgb.hex(0x08121f));
    Raster.drawTriangles(&image, view_proj, positions, normals, uvs, model.mesh.indices, .none, 0, BindPoseShader{
        .light = V.init(-0.45, 0.72, 0.64).normalize(),
        .low_y = lo.y,
        .height = @max(extents.y, 0.01),
        .triangle_colors = triangle_colors,
    });
    return image.downsample(gpa, factor);
}

fn split(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, meta_path: []const u8, output_dir: []const u8) !void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const source = try readFile(arena, io, source_path);
    const meta_bytes = try readFile(arena, io, meta_path);
    const meta = try Meta.check(arena, meta_bytes, source_path, source);
    if (meta.kind != .model) return error.UnsupportedKind;
    const source_trace = try Gltf.inspect(arena, source);
    var context: Context = .{ .io = io, .dir = std.fs.path.dirname(source_path) orelse "." };
    const resolver: Gltf.Resolver = .{ .context = &context, .load = Context.load };
    const Pending = struct { file: []const u8, bytes: []const u8 };
    const ManifestModule = struct {
        id: []const u8,
        node: u32,
        mesh: u32,
        primitive: u32,
        material: ?[]const u8,
        generated_normals: bool,
        file: []const u8,
        content_hash: [71]u8,
        vertex_count: usize,
        triangle_count: usize,
        bounds_min: [3]f32,
        bounds_max: [3]f32,
    };
    const pending = try arena.alloc(Pending, source_trace.modules.len);
    const manifest_modules = try arena.alloc(ManifestModule, source_trace.modules.len);
    var count: usize = 0;
    const source_hash = Meta.hashSource(source);
    for (source_trace.modules) |part| {
        if (!part.in_selected_scene) continue;
        const model_file = try std.fmt.allocPrint(arena, "node-{d}-mesh-{d}-primitive-{d}.hwmesh", .{ part.node, part.mesh, part.primitive });
        const converted = blk: {
            var model = try Gltf.compileModule(gpa, source, resolver, .{ .node = part.node, .primitive = part.primitive });
            defer model.deinit(gpa);
            if (meta.model.scale != 1) {
                for (model.mesh.vertices) |*vertex| {
                    for (&vertex.position) |*coordinate| coordinate.* *= meta.model.scale;
                }
                model.computeBounds();
            }
            break :blk .{
                .bytes = try model.encode(arena),
                .vertex_count = model.mesh.vertices.len,
                .triangle_count = model.mesh.indices.len / 3,
                .bounds_min = model.bounds_min,
                .bounds_max = model.bounds_max,
            };
        };
        const relative = try std.fmt.allocPrint(arena, "{s}/{s}", .{ output_dir, model_file });
        pending[count] = .{ .file = relative, .bytes = converted.bytes };
        manifest_modules[count] = .{
            .id = part.id,
            .node = part.node,
            .mesh = part.mesh,
            .primitive = part.primitive,
            .material = part.material,
            .generated_normals = part.generated_normals,
            .file = model_file,
            .content_hash = Meta.hashSource(converted.bytes),
            .vertex_count = converted.vertex_count,
            .triangle_count = converted.triangle_count,
            .bounds_min = converted.bounds_min,
            .bounds_max = converted.bounds_max,
        };
        count += 1;
    }
    if (count == 0) return error.NoSceneModules;
    const guid = meta.guid.format();
    const manifest_json = try std.json.Stringify.valueAlloc(arena, .{
        .format = 1,
        .source_guid = &guid,
        .source_hash = source_hash,
        .importer_version = Meta.importers.gltf,
        .module_count = count,
        .modules = manifest_modules[0..count],
        .source_trace = source_trace,
    }, .{ .whitespace = .indent_2 });
    try std.Io.Dir.cwd().createDirPath(io, output_dir);
    for (pending[0..count]) |module| try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = module.file, .data = module.bytes });
    const manifest_path = try std.fmt.allocPrint(arena, "{s}/modules.json", .{output_dir});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = manifest_path, .data = manifest_json });
    std.log.info("split: {s} -> {d} HWMS modules in {s}", .{ source_path, count, output_dir });
}

fn manifest(gpa: std.mem.Allocator, io: std.Io, output: []const u8, triples: []const []const u8) !void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const entries = try arena.alloc(Registry.ManifestEntry, triples.len / 3);
    for (entries, 0..) |*e, i| {
        const bytes = try readFile(arena, io, triples[i * 3]);
        const doc = std.json.parseFromSliceLeaky(Meta.Doc, arena, bytes, .{}) catch return error.InvalidMeta;
        e.* = .{ .guid = doc.guid, .kind = doc.kind, .name = triples[i * 3 + 1], .output = triples[i * 3 + 2], .source = triples[i * 3] };
        if (std.mem.endsWith(u8, e.source, ".meta")) e.source = e.source[0 .. e.source.len - 5];
        for (entries[0..i]) |other| if (other.guid.eql(e.guid)) {
            std.log.err("{s}: GUID {s} is already used by {s}", .{ triples[i * 3], &e.guid.format(), other.name });
            return error.DuplicateGuid;
        };
    }
    const json = try std.json.Stringify.valueAlloc(arena, Registry.Manifest{ .format = Registry.manifest_format, .assets = entries }, .{ .whitespace = .indent_2 });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output, .data = json });
}

fn import(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    var created: usize = 0;
    var refreshed: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        _ = Meta.kindOf(entry.basename) catch continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, gpa, .limited(64 << 20));
        defer gpa.free(source);
        const meta_name = try std.fmt.allocPrint(gpa, "{s}.meta", .{entry.basename});
        defer gpa.free(meta_name);
        const existing = entry.dir.readFileAlloc(io, meta_name, gpa, .limited(1 << 20)) catch null;
        defer if (existing) |e| gpa.free(e);
        const updated = try Meta.refresh(gpa, existing, entry.basename, source, Guid.generate(io));
        defer gpa.free(updated);
        if (existing) |e| if (std.mem.eql(u8, e, updated)) continue;
        try entry.dir.writeFile(io, .{ .sub_path = meta_name, .data = updated });
        if (existing == null) created += 1 else refreshed += 1;
        std.log.info("{s}.meta {s}", .{ entry.path, if (existing == null) "created" else "refreshed" });
    }
    std.log.info("import: {d} sidecars created, {d} refreshed", .{ created, refreshed });
}

const Context = struct {
    io: std.Io,
    dir: []const u8,

    fn load(opaque_context: ?*anyopaque, allocator: std.mem.Allocator, uri: []const u8) anyerror![]u8 {
        const self: *Context = @ptrCast(@alignCast(opaque_context.?));
        const path = try std.fs.path.join(allocator, &.{ self.dir, uri });
        defer allocator.free(path);
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, allocator, .limited(256 << 20));
    }
};
