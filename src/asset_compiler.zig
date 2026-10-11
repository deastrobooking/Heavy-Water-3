const std = @import("std");
const Gltf = @import("asset/Gltf.zig");
const Model = @import("asset/Model.zig");
const Blueprint = @import("machine/Blueprint.zig");
const Meta = @import("asset/Meta.zig");
const Guid = @import("asset/Guid.zig");
const Registry = @import("asset/Registry.zig");
const Heightmap = @import("procedural/Heightmap.zig");
const Synth = @import("audio/Synth.zig");

/// Build-time tool:
///   asset-compiler compile <source> <source.meta> <output>
///       check the sidecar (GUID, kind, importer, settings, unchanged source), then compile a
///       glTF model, validate a blueprint, or compile a PGM heightmap
///   asset-compiler trace <source.glb|source.gltf> <source.meta> <output.json>
///       validate asset identity and write a source-to-module report for 3D review/mod packaging
///   asset-compiler split <source.glb|source.gltf> <source.meta> <output-directory>
///       write one validated HWMS module per selected-scene node/mesh/primitive and modules.json
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
    if (args.len >= 3 and std.mem.eql(u8, args[1], "manifest") and (args.len - 3) % 3 == 0) return manifest(init.gpa, io, args[2], args[3..]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "import")) return import(init.gpa, io, args[2]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "sounds")) return writeSounds(init.gpa, io, args[2]);
    if (args.len == 4 or args.len == 8) if (std.mem.eql(u8, args[1], "heightmap")) return compileHeightmap(init.gpa, io, args[2], args[3], args[4..]);
    std.log.err("usage: asset-compiler compile <source> <meta> <output> | trace <source.glb|source.gltf> <meta> <output.json> | split <source.glb|source.gltf> <meta> <output-dir> | manifest <output> (<meta> <name> <output-name>)... | import <dir> | heightmap <source.pgm> <output.hwmh> [world-width world-depth elevation base-height]", .{});
    return error.InvalidArguments;
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
