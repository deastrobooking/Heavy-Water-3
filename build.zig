const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = b.addOptions();
    options.addOption(u64, "seed", b.option(u64, "seed", "World seed") orelse 0x4845415659);
    options.addOption(u32, "smoke_frames", b.option(u32, "smoke-frames", "Exit after N rendered frames (0 = interactive)") orelse 0);
    options.addOption(u32, "benchmark_frames", b.option(u32, "benchmark-frames", "Run the streaming route for N measured frames, after 60 warm-up frames") orelse 0);
    options.addOption(usize, "upload_budget", (b.option(usize, "upload-budget-kib", "Terrain upload budget per frame in KiB (minimum 278)") orelse 320) * 1024);
    const mach = b.dependency("mach", .{ .target = target, .optimize = optimize, .core = true });
    // Versioned glTF → runtime model path. The host tool runs as part of the build graph and its
    // output is embedded, so the app never parses glTF at runtime.
    const compiler = b.addExecutable(.{ .name = "asset-compiler", .root_module = b.createModule(.{ .root_source_file = b.path("src/asset_compiler.zig"), .target = b.graph.host, .optimize = .ReleaseSafe }) });
    const compile_crate = b.addRunArtifact(compiler);
    compile_crate.addFileArg(b.path("assets/source/crate.gltf"));
    const crate = compile_crate.addOutputFileArg("crate.hwmesh");
    const assets = b.step("assets", "Compile source assets into zig-out/assets");
    assets.dependOn(&b.addInstallFileWithDir(crate, .{ .custom = "assets" }, "crate.hwmesh").step);
    // Blueprints are validated by the same tool; an invalid machine fails the build.
    const blueprint_names = [_][]const u8{ "powered_door", "elevator" };
    var blueprints: [blueprint_names.len]std.Build.LazyPath = undefined;
    for (blueprint_names, &blueprints) |name, *output| {
        const check_blueprint = b.addRunArtifact(compiler);
        check_blueprint.addFileArg(b.path(b.fmt("assets/source/blueprints/{s}.json", .{name})));
        output.* = check_blueprint.addOutputFileArg(b.fmt("{s}.json", .{name}));
        assets.dependOn(&b.addInstallFileWithDir(output.*, .{ .custom = "assets/blueprints" }, b.fmt("{s}.json", .{name})).step);
    }

    const app = b.createModule(.{ .root_source_file = b.path("src/App.zig"), .target = target, .optimize = optimize });
    app.addImport("mach", mach.module("mach"));
    app.addOptions("options", options);
    app.addAnonymousImport("crate.hwmesh", .{ .root_source_file = crate });
    for (blueprint_names, blueprints) |name, output| app.addAnonymousImport(b.fmt("{s}.blueprint", .{name}), .{ .root_source_file = output });
    const exe = @import("mach").addExecutable(mach.builder, .{ .name = "heavy-water", .app = app, .target = target, .optimize = optimize });
    if (target.result.os.tag == .linux) {
        exe.use_llvm = true;
        exe.use_lld = true;
    }
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Explore the engine test world").dependOn(&run.step);
    const tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/tests.zig"), .target = target, .optimize = optimize }) });
    tests.root_module.addImport("mach", mach.module("mach"));
    tests.root_module.addAnonymousImport("crate.gltf", .{ .root_source_file = b.path("assets/source/crate.gltf") });
    tests.root_module.addAnonymousImport("crate.hwmesh", .{ .root_source_file = crate });
    for (blueprint_names, blueprints) |name, output| tests.root_module.addAnonymousImport(b.fmt("{s}.blueprint", .{name}), .{ .root_source_file = output });
    b.step("test", "Run deterministic engine tests (no window)").dependOn(&b.addRunArtifact(tests).step);
    b.step("check", "Compile the application").dependOn(&exe.step);
}
