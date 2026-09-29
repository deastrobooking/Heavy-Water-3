const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = b.addOptions();
    options.addOption(u64, "seed", b.option(u64, "seed", "World seed") orelse 0x4845415659);
    options.addOption(u32, "smoke_frames", b.option(u32, "smoke-frames", "Exit after N rendered frames (0 = interactive)") orelse 0);
    const mach = b.dependency("mach", .{ .target = target, .optimize = optimize, .core = true });
    const app = b.createModule(.{ .root_source_file = b.path("src/App.zig"), .target = target, .optimize = optimize });
    app.addImport("mach", mach.module("mach"));
    app.addOptions("options", options);
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
    b.step("test", "Run deterministic engine tests (no window)").dependOn(&b.addRunArtifact(tests).step);
    b.step("check", "Compile the application").dependOn(&exe.step);
}
