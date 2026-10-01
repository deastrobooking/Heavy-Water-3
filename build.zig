const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = b.addOptions();
    options.addOption(u8, "character_showcase", b.option(u8, "character-showcase", "Character look: 1 scout, 2 sentinel, 3 unarmored; front view for capture") orelse 0);
    options.addOption(bool, "hot_reload", b.option(bool, "hot-reload", "Watch model, blueprint and mod script sources during development") orelse false);
    options.addOption(bool, "reload_smoke", b.option(bool, "reload-smoke", "Exercise model reload using an isolated source fixture") orelse false);
    options.addOption(u64, "seed", b.option(u64, "seed", "World seed") orelse 0x4845415659);
    options.addOption(u32, "smoke_frames", b.option(u32, "smoke-frames", "Exit after N rendered frames (0 = interactive)") orelse 0);
    options.addOption(u32, "benchmark_frames", b.option(u32, "benchmark-frames", "Run the streaming route for N measured frames, after 60 warm-up frames") orelse 0);
    const benchmark_arbor = b.option(u8, "benchmark-arbor", "Arbor to view on the canopy route: 0 test, 1 narrow genome, 2 spreading genome") orelse 0;
    if (benchmark_arbor > 2) @panic("benchmark-arbor must be 0, 1, or 2");
    options.addOption(u8, "benchmark_arbor", benchmark_arbor);
    options.addOption(bool, "benchmark_canopy", b.option(bool, "benchmark-canopy", "Aim the benchmark at the test Arbor, from up close to 1 km and back") orelse false);
    options.addOption(u32, "capture_frame", b.option(u32, "capture-frame", "Write rendered frame N to zig-out/capture.bmp, then exit (0 = off)") orelse 0);
    options.addOption(u8, "showcase", b.option(u8, "showcase", "Hold the camera on a city viewpoint: 1-6 each road, 7 overview, 8 dusk overview, 9 street level, 10-15 roads at dusk, 16 armor lineup, 17 hardsuit close-up, 18-28 GUI screens (title, talk, upgrades, shop, wardrobe, customize, pause, settings, HUD, 4-player, controls)") orelse 0);
    options.addOption(u32, "scale_objects", b.option(u32, "scale-objects", "Benchmark scale workload: N field objects (e.g. 10000, 100000, 1000000); 0 = off") orelse 0);
    options.addOption(u32, "pack_stress", b.option(u32, "pack-stress", "Benchmark: write a pack of N meshes (1K-128K vertices) and load it during measurement; 0 = off") orelse 0);
    options.addOption(usize, "asset_upload", (b.option(usize, "asset-upload-kib", "Late catalog mesh upload budget per frame in KiB (deferred and reloaded meshes)") orelse 4096) * 1024);
    options.addOption(usize, "field_upload", (b.option(usize, "field-upload-kib", "Scale workload instance upload budget per frame in KiB") orelse 2048) * 1024);
    options.addOption(usize, "upload_budget", (b.option(usize, "upload-budget-kib", "Terrain upload budget per frame in KiB (minimum 278)") orelse 320) * 1024);
    options.addOption(bool, "audio", b.option(bool, "audio", "Open the system audio device (default true; false runs silent)") orelse true);
    const mach = b.dependency("mach", .{ .target = target, .optimize = optimize, .core = true, .sysaudio = true });
    // Versioned glTF → runtime model path. The host tool runs as part of the build graph and its
    // output is embedded, so the app never parses glTF at runtime.
    const compiler = b.addExecutable(.{ .name = "asset-compiler", .root_module = b.createModule(.{ .root_source_file = b.path("src/asset_compiler.zig"), .target = b.graph.host, .optimize = .ReleaseSafe }) });
    // Every source has a `.meta` sidecar (GUID, source hash, importer, settings); compiling checks
    // it, and `zig build import` creates or refreshes sidecars deliberately.
    const import = b.addRunArtifact(compiler);
    import.addArgs(&.{ "import", "assets/source" });
    import.has_side_effects = true;
    b.step("import", "Create missing asset sidecars (new GUIDs) and refresh source hashes").dependOn(&import.step);
    const heightmap_import = b.addRunArtifact(compiler);
    heightmap_import.addArg("heightmap");
    if (b.args) |args| heightmap_import.addArgs(args);
    b.step("heightmap", "Import a PGM heightmap to the versioned HWMH terrain format").dependOn(&heightmap_import.step);
    const sounds = b.addRunArtifact(compiler);
    sounds.addArgs(&.{ "sounds", "zig-out/sounds" });
    sounds.has_side_effects = true;
    b.step("sounds", "Write every synthesized sound to zig-out/sounds/*.wav for listening").dependOn(&sounds.step);
    const manifest = b.addRunArtifact(compiler);
    manifest.addArg("manifest");
    const manifest_file = manifest.addOutputFileArg("assets.manifest");
    const compile_crate = b.addRunArtifact(compiler);
    compile_crate.addArg("compile");
    compile_crate.addFileArg(b.path("assets/source/crate.gltf"));
    compile_crate.addFileArg(b.path("assets/source/crate.gltf.meta"));
    const crate = compile_crate.addOutputFileArg("crate.hwmesh");
    manifest.addFileArg(b.path("assets/source/crate.gltf.meta"));
    manifest.addArgs(&.{ "crate", "crate.hwmesh" });
    const assets = b.step("assets", "Compile source assets into zig-out/assets");
    assets.dependOn(&b.addInstallFileWithDir(crate, .{ .custom = "assets" }, "crate.hwmesh").step);
    // Blueprints are validated by the same tool; an invalid machine fails the build.
    const blueprint_names = [_][]const u8{ "powered_door", "elevator", "rover", "sap_beacon", "proximity_gate", "street_lamp", "signal_relay", "rootsong_hearth", "rootsong_call" };
    var blueprints: [blueprint_names.len]std.Build.LazyPath = undefined;
    for (blueprint_names, &blueprints) |name, *output| {
        const check_blueprint = b.addRunArtifact(compiler);
        check_blueprint.addArg("compile");
        check_blueprint.addFileArg(b.path(b.fmt("assets/source/blueprints/{s}.json", .{name})));
        check_blueprint.addFileArg(b.path(b.fmt("assets/source/blueprints/{s}.json.meta", .{name})));
        output.* = check_blueprint.addOutputFileArg(b.fmt("{s}.json", .{name}));
        manifest.addFileArg(b.path(b.fmt("assets/source/blueprints/{s}.json.meta", .{name})));
        manifest.addArgs(&.{ name, b.fmt("blueprints/{s}.json", .{name}) });
        assets.dependOn(&b.addInstallFileWithDir(output.*, .{ .custom = "assets/blueprints" }, b.fmt("{s}.json", .{name})).step);
    }
    assets.dependOn(&b.addInstallFileWithDir(manifest_file, .{ .custom = "assets" }, "assets.manifest").step);

    // The example mod's scripts compile to WebAssembly and are written next to its manifest, where
    // the game loads mods from (`mods/<name>/`).
    const glowworks = b.addExecutable(.{ .name = "glowworks", .root_module = b.createModule(.{ .root_source_file = b.path("mods/glowworks/src/glowworks.zig"), .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }), .optimize = .ReleaseSmall }) });
    glowworks.entry = .disabled;
    glowworks.rdynamic = true;
    glowworks.stack_size = 16 * 1024;
    const mods = b.addUpdateSourceFiles();
    mods.addCopyFileToSource(glowworks.getEmittedBin(), "mods/glowworks/glowworks.wasm");
    b.step("mods", "Build the example mod's scripts into mods/").dependOn(&mods.step);

    const app = b.createModule(.{ .root_source_file = b.path("src/App.zig"), .target = target, .optimize = optimize });
    app.addImport("mach", mach.module("mach"));
    app.addOptions("options", options);
    app.addAnonymousImport("crate.hwmesh", .{ .root_source_file = crate });
    app.addAnonymousImport("assets.manifest", .{ .root_source_file = manifest_file });
    for (blueprint_names, blueprints) |name, output| app.addAnonymousImport(b.fmt("{s}.blueprint", .{name}), .{ .root_source_file = output });
    const exe = @import("mach").addExecutable(mach.builder, .{ .name = "heavy-water", .app = app, .target = target, .optimize = optimize });
    if (target.result.os.tag == .macos) {
        exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/gamepad.m"), .flags = &.{"-fno-objc-arc"} });
        exe.root_module.linkFramework("GameController", .{});
        exe.root_module.linkFramework("Foundation", .{});
    }
    if (target.result.os.tag == .linux) {
        exe.use_llvm = true;
        exe.use_lld = true;
    }
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(&mods.step);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Explore the engine test world").dependOn(&run.step);
    const tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/tests.zig"), .target = target, .optimize = optimize }) });
    tests.root_module.addImport("mach", mach.module("mach"));
    tests.root_module.addAnonymousImport("crate.gltf", .{ .root_source_file = b.path("assets/source/crate.gltf") });
    tests.root_module.addAnonymousImport("crate.hwmesh", .{ .root_source_file = crate });
    tests.root_module.addAnonymousImport("assets.manifest", .{ .root_source_file = manifest_file });
    for (blueprint_names, blueprints) |name, output| tests.root_module.addAnonymousImport(b.fmt("{s}.blueprint", .{name}), .{ .root_source_file = output });
    tests.root_module.addAnonymousImport("glowworks.wasm", .{ .root_source_file = glowworks.getEmittedBin() });
    tests.root_module.addAnonymousImport("glowworks.mod", .{ .root_source_file = b.path("mods/glowworks/mod.json") });
    tests.root_module.addAnonymousImport("glowworks.lamp", .{ .root_source_file = b.path("mods/glowworks/blueprints/breathing_lamp.json") });
    b.step("test", "Run deterministic engine tests (no window)").dependOn(&b.addRunArtifact(tests).step);
    b.step("check", "Compile the application").dependOn(&exe.step);
}
