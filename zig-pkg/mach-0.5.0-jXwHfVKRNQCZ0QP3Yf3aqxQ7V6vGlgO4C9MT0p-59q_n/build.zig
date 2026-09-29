const std = @import("std");
const builtin = @import("builtin");

pub const SysgpuBackend = enum {
    default,
    webgpu,
    d3d12,
    metal,
    vulkan,
    opengl,
};

/// Examples:
///
/// `zig build` -> builds all of Mach
/// `zig build test` -> runs all tests
///
/// ## (optional) minimal dependency fetching
///
/// By default, all Mach dependencies will be added to the build. If you only depend on a specific
/// part of Mach, then you can opt to have only the dependencies you need fetched as part of the
/// build:
///
/// ```
/// b.dependency("mach", .{
///   .target = target,
///   .optimize = optimize,
///   .core = true,
///   .sysaudio = true,
/// });
/// ```
///
/// The presense of `.core = true` and `.sysaudio = true` indicate Mach should add the dependencies
/// required by `@import("mach").core` and `@import("mach").sysaudio` to the build. You can use this
/// option with the following:
///
/// * core (also implies sysgpu)
/// * sysaudio
/// * sysgpu
///
/// Note that Zig's dead code elimination and, more importantly, lazy code evaluation means that
/// you really only pay for the parts of `@import("mach")` that you use/reference.
pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const sysgpu_backend = b.option(SysgpuBackend, "sysgpu_backend", "sysgpu API backend") orelse .default;

    const build_examples = b.option(bool, "examples", "build/install examples specifically");
    const build_libs = b.option(bool, "libs", "build/install libraries specifically");
    const build_mach = b.option(bool, "mach", "build mach specifically");
    const build_core = b.option(bool, "core", "build core specifically");
    const build_sysaudio = b.option(bool, "sysaudio", "build sysaudio specifically");
    const build_sysgpu = b.option(bool, "sysgpu", "build sysgpu specifically");
    const build_all = build_examples == null and build_libs == null and build_mach == null and build_core == null and build_sysaudio == null and build_sysgpu == null;

    const want_examples = build_all or (build_examples orelse false);
    const want_libs = build_all or (build_libs orelse false);
    const want_mach = build_all or (build_mach orelse false);
    // libmach requires sysgpu, core, and sysaudio.
    const want_core = build_all or want_mach or want_libs or (build_core orelse false);
    const want_sysaudio = build_all or want_mach or want_libs or (build_sysaudio orelse false);
    const want_sysgpu = build_all or want_mach or want_libs or want_core or (build_sysgpu orelse false);

    const build_options = b.addOptions();
    build_options.addOption(bool, "want_mach", want_mach);
    build_options.addOption(bool, "want_core", want_core);
    build_options.addOption(bool, "want_sysaudio", want_sysaudio);
    build_options.addOption(bool, "want_sysgpu", want_sysgpu);
    build_options.addOption(SysgpuBackend, "sysgpu_backend", sysgpu_backend);

    var examples = [_]Example{
        .{ .name = "core-custom-entrypoint", .deps = &.{} },
        .{ .name = "core-triangle", .deps = &.{} },
        .{ .name = "core-triangles", .deps = &.{} },
        .{ .name = "core-transparent-window", .deps = &.{} },
        .{ .name = "custom-renderer", .deps = &.{} },
        .{ .name = "glyphs", .deps = &.{ .assets, .freetype } },
        .{ .name = "hardware-check", .deps = &.{ .assets, .zigimg } },
        .{ .name = "piano", .deps = &.{} },
        .{ .name = "play-opus", .deps = &.{.assets} },
        .{ .name = "sprite", .deps = &.{ .zigimg, .assets } },
        .{ .name = "text", .deps = &.{.assets} },
    };

    var sysaudio_tests = [_]SysAudioTest{
        .{ .name = "record" },
        .{ .name = "sine" },
    };

    // Setup Steps
    const docs_step = b.step("docs", "Generate docs");
    const editor_step = b.step("editor", "Build the 'mach' editor / CLI");
    buildEditor(b, optimize, target, editor_step);
    for (&examples) |*example| {
        example.run_step = b.step(
            b.fmt("run-{s}", .{example.name}),
            b.fmt("Run example: {s}", .{example.name}),
        );
    }
    const test_step = b.step("test", "Test Run: Unit Tests");
    for (&sysaudio_tests) |*sysaudio_test| {
        sysaudio_test.run_step = b.step(
            b.fmt("test-sysaudio-{s}", .{sysaudio_test.name}),
            b.fmt("Test Run: sysaudio {s}", .{sysaudio_test.name}),
        );
    }

    const module = b.addModule("mach", .{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    });
    module.addImport("build-options", build_options.createModule());

    buildExamples(
        b,
        optimize,
        target,
        module,
        &examples,
    );

    if (want_mach) {
        if (target.result.cpu.arch != .wasm32) {
            if (b.lazyDependency("freetype", .{
                .target = target,
                .optimize = optimize,
            })) |dep| module.linkLibrary(dep.artifact("freetype"));
            if (b.lazyDependency("kb-text-shape", .{
                .target = target,
                .optimize = optimize,
            })) |dep| module.linkLibrary(dep.artifact("kb-text-shape"));
            if (b.lazyDependency("opusfile", .{
                .target = target,
                .optimize = .ReleaseFast,
            })) |dep| module.linkLibrary(dep.artifact("opusfile"));
            if (b.lazyDependency("opusenc", .{
                .target = target,
                .optimize = .ReleaseFast,
            })) |dep| module.linkLibrary(dep.artifact("opusenc"));
        }

        if (want_examples) {
            for (examples) |example| b.getInstallStep().dependOn(example.install_step);
        }
    }
    if (want_core) {
        if (target.result.os.tag == .linux) {
            module.addCSourceFile(.{
                .file = b.path("src/core/linux/wayland.c"),
            });
        }
        linkCore(b, module);
    }
    if (want_sysaudio) {
        linkSysaudio(b, module);
        if (target.result.os.tag == .linux) {
            module.addCSourceFile(.{
                .file = b.path("src/sysaudio/pipewire/sysaudio.c"),
                .flags = &.{"-std=gnu99"},
            });
        }
        if (target.result.cpu.arch != .wasm32) {
            for (&sysaudio_tests) |*sysaudio_test| {
                const test_exe = b.addExecutable(.{
                    .name = b.fmt("sysaudio-{s}", .{sysaudio_test.name}),
                    .root_module = b.createModule(.{
                        .root_source_file = b.path(b.fmt("src/sysaudio/tests/{s}.zig", .{sysaudio_test.name})),
                        .target = target,
                        .optimize = optimize,
                    }),
                });
                test_exe.root_module.addImport("mach", module);

                const run_cmd = b.addRunArtifact(test_exe);
                if (b.args) |args| run_cmd.addArgs(args);

                sysaudio_test.run_step.dependOn(&run_cmd.step);
            }
        }
    }
    if (want_sysgpu) {
        linkSysgpu(b, module);
        if (b.lazyDependency("vulkan_headers", .{})) |vulkan_headers| {
            if (b.lazyDependency("vulkan_zig", .{})) |vulkan_zig| {
                const registry = vulkan_headers.path("registry/vk.xml");
                const vk_gen = vulkan_zig.artifact("vulkan-zig-generator");
                const vk_generate_cmd = b.addRunArtifact(vk_gen);
                vk_generate_cmd.addFileArg(registry);
                const vulkan_mod = b.addModule("vulkan", .{
                    .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
                });
                module.addImport("vulkan", vulkan_mod);
            }
        }
        if (target.result.os.tag.isDarwin()) {
            if (b.lazyDependency("mach_objc", .{
                .target = target,
                .optimize = optimize,
            })) |dep| module.addImport("objc", dep.module("mach-objc"));
        }
    }

    if (want_libs) {
        inline for (&[_]std.builtin.LinkMode{ .static, .dynamic }) |linkage| {
            const lib = b.addLibrary(.{
                .name = "mach",
                .linkage = linkage,
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/main.zig"),
                    .target = target,
                    .optimize = optimize,
                }),
            });
            if (target.result.os.tag == .ios) {
                // TODO(ios): do not require stripping binaries
                // Avoid pulling in std.debug.SelfInfo.MachO.findModule, which references
                // __dyld_get_image_header_containing_address, unavailable on iOS.
                lib.root_module.strip = true;
            }
            var iter = module.import_table.iterator();
            while (iter.next()) |e| {
                lib.root_module.addImport(e.key_ptr.*, e.value_ptr.*);
            }
            linkSysgpu(b, lib.root_module);
            linkCore(b, lib.root_module);
            linkSysaudio(b, lib.root_module);
            lib.installHeader(b.path("include/libmach.h"), "libmach.h");
            b.installArtifact(lib);
        }
    }

    if (target.result.cpu.arch != .wasm32) {
        // Creates a step for unit testing. This only builds the test executable
        // but does not run it.
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        var iter = module.import_table.iterator();
        while (iter.next()) |e| {
            unit_tests.root_module.addImport(e.key_ptr.*, e.value_ptr.*);
        }

        // Exposes a `test` step to the `zig build --help` menu, providing a way for the user to
        // request running the unit tests.
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);

        if (want_sysgpu) linkSysgpu(b, unit_tests.root_module);
        if (want_core) linkCore(b, unit_tests.root_module);
        if (want_sysaudio) linkSysaudio(b, unit_tests.root_module);
        if (want_mach) {
            if (b.lazyDependency("freetype", .{
                .target = target,
                .optimize = optimize,
            })) |dep| unit_tests.root_module.linkLibrary(dep.artifact("freetype"));
            if (b.lazyDependency("kb-text-shape", .{
                .target = target,
                .optimize = optimize,
            })) |dep| unit_tests.root_module.linkLibrary(dep.artifact("kb-text-shape"));
        }

        // Documentation
        const docs_obj = b.addObject(.{
            .name = "mach",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = .Debug,
            }),
        });
        //docs_obj.root_module.addOptions("build_options", build_options);
        const docs = docs_obj.getEmittedDocs();
        const install_docs = b.addInstallDirectory(.{
            .source_dir = docs,
            .install_dir = .prefix,
            .install_subdir = "docs",
        });
        docs_step.dependOn(&install_docs.step);
    }
}

pub const Platform = enum {
    wasm,
    linux,
    windows,
    darwin,
    null,

    pub fn fromTarget(target: std.Target) Platform {
        if (target.cpu.arch == .wasm32) return .wasm;
        if (target.os.tag.isDarwin()) return .darwin;
        if (target.os.tag == .windows) return .windows;
        if (target.os.tag == .linux) return .linux;
        return .null;
    }
};

/// Adds system framework / include / library paths from the bundled `xcode_frameworks` package,
/// picking the right subtree based on `target` (macOS vs iOS device vs iOS simulator).
fn addXCodeFrameworks(b: *std.Build, module: *std.Build.Module) void {
    const target = module.resolved_target orelse @panic("module must have .target specified");
    const optimize = module.optimize orelse @panic("module must have .optimize specified");

    const dep = b.lazyDependency("xcode_frameworks", .{
        .target = target,
        .optimize = optimize,
    }) orelse return;

    const subdir: ?[]const u8 = switch (target.result.os.tag) {
        .macos => null,
        .ios => if (target.result.abi == .simulator) "iphonesimulator" else "iphoneos",
        else => null,
    };

    if (subdir) |sd| {
        module.addSystemFrameworkPath(dep.path(b.fmt("{s}/Frameworks", .{sd})));
        module.addSystemIncludePath(dep.path(b.fmt("{s}/include", .{sd})));
        module.addLibraryPath(dep.path(b.fmt("{s}/lib", .{sd})));
    } else {
        module.addSystemFrameworkPath(dep.path("Frameworks"));
        module.addSystemIncludePath(dep.path("include"));
        module.addLibraryPath(dep.path("lib"));
    }
}

/// Links the system libraries, macOS frameworks, etc. that are needed to build sysgpu.
fn linkSysgpu(b: *std.Build, module: *std.Build.Module) void {
    const target = module.resolved_target orelse @panic("module must have .target specified");
    const optimize = module.optimize orelse @panic("module must have .optimize specified");
    _ = optimize;

    if (target.result.os.tag == .linux) {
        module.link_libc = true;
        if (b.lazyDependency("opengl_headers", .{})) |dep|
            module.addSystemIncludePath(dep.path("."));
    } else if (target.result.os.tag.isDarwin()) {
        module.linkFramework("CoreGraphics", .{});
        module.linkFramework("Foundation", .{});
        module.linkFramework("Metal", .{});
        module.linkFramework("QuartzCore", .{});

        addXCodeFrameworks(b, module);
    } else if (target.result.os.tag == .windows) {
        module.link_libc = true;
        // TODO(build): Windows should never link OpenGL except in debug builds.
        module.linkSystemLibrary("dxgi", .{});
        module.linkSystemLibrary("d3d12", .{});
        module.linkSystemLibrary("d3dcompiler_47", .{});
        module.linkSystemLibrary("opengl32", .{});

        if (b.lazyDependency("directx_headers", .{})) |dep|
            module.addSystemIncludePath(dep.path("include"));
        if (b.lazyDependency("opengl_headers", .{})) |dep|
            module.addSystemIncludePath(dep.path("."));
    }
}

/// Links the system libraries, macOS frameworks, etc. that are needed to build core.
fn linkCore(b: *std.Build, module: *std.Build.Module) void {
    const target = module.resolved_target orelse @panic("module must have .target specified");
    const optimize = module.optimize orelse @panic("module must have .optimize specified");

    if (target.result.os.tag == .linux) {
        if (b.lazyDependency("wayland_headers", .{
            .target = target,
            .optimize = optimize,
        })) |dep| {
            module.addIncludePath(dep.path("libdecor"));
            module.addIncludePath(dep.path("wayland"));
            module.addIncludePath(dep.path("wayland-protocols"));
        }
        if (b.lazyDependency("x11_headers", .{})) |dep| {
            module.addSystemIncludePath(dep.path("."));
        }
    } else if (target.result.os.tag.isDarwin()) {
        if (target.result.os.tag == .macos) {
            module.linkFramework("AppKit", .{});
        } else {
            module.linkFramework("UIKit", .{});
        }
        module.linkFramework("CoreGraphics", .{});
        module.linkFramework("Foundation", .{});
        module.linkFramework("Metal", .{});
        module.linkFramework("QuartzCore", .{});

        addXCodeFrameworks(b, module);
        if (b.lazyDependency("mach_objc", .{
            .target = target,
            .optimize = optimize,
        })) |dep| module.addImport("objc", dep.module("mach-objc"));
    }
}

/// Links the system libraries, macOS frameworks, etc. that are needed to build sysaudio.
fn linkSysaudio(b: *std.Build, module: *std.Build.Module) void {
    const target = module.resolved_target orelse @panic("module must have .target specified");
    const optimize = module.optimize orelse @panic("module must have .optimize specified");
    _ = optimize;

    if (target.result.os.tag == .linux) {
        module.link_libc = true;

        if (b.lazyDependency("linux_audio_headers", .{})) |dep| {
            module.addIncludePath(dep.path("."));
            module.addIncludePath(dep.path("alsa-lib"));
        }
    } else if (target.result.os.tag.isDarwin()) {
        module.linkFramework("AudioToolbox", .{});
        module.linkFramework("CoreFoundation", .{});
        module.linkFramework("CoreAudio", .{});

        addXCodeFrameworks(b, module);
    }
}

const Dependency = enum {
    assets,
    freetype,
    zigimg,
};

const Example = struct {
    name: []const u8,
    deps: []const Dependency = &.{},

    install_step: *std.Build.Step = undefined,
    run_step: *std.Build.Step = undefined,
};

pub fn addExecutable(
    mach_builder: *std.Build,
    options: struct {
        name: []const u8,
        app: *std.Build.Module,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    },
) *std.Build.Step.Compile {
    const entrypoint_mod = mach_builder.addModule(
        mach_builder.fmt("{s}-entrypoint", .{options.name}),
        .{
            .root_source_file = mach_builder.path("src/entrypoint/main.zig"),
            .optimize = options.optimize,
            .target = options.target,
        },
    );
    entrypoint_mod.addImport("app", options.app);

    const exe = mach_builder.addExecutable(.{
        .name = options.name,
        .root_module = entrypoint_mod,

        // Win32 manifest file for DPI-awareness configuration
        .win32_manifest = mach_builder.path("src/core/windows/win32.manifest"),
    });

    if (options.target.result.os.tag == .ios) {
        // TODO(ios): do not require stripping binaries
        // Avoid pulling in std.debug.SelfInfo.MachO.findModule, which references
        // __dyld_get_image_header_containing_address, unavailable on iOS.
        exe.root_module.strip = true;

        // Zig does not ship an iOS libc, and Zig does not auto-resolve an iOS sysroot
        // for `link_libc = true` modules the way it does for macOS. As a result, we
        // provide the iOS SDK ourselves to both the entrypoint and the user's app.
        addXCodeFrameworks(mach_builder, entrypoint_mod);
        addXCodeFrameworks(mach_builder, options.app);
    }

    return exe;
}

fn buildExamples(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
    mach_mod: *std.Build.Module,
    examples: []Example,
) void {
    for (examples) |*example| {
        const app_mod = b.addModule(example.name, .{
            .root_source_file = b.path(b.fmt("examples/{s}/App.zig", .{example.name})),
            .target = target,
            .optimize = optimize,
        });
        app_mod.addImport("mach", mach_mod);
        const exe = addExecutable(b, .{
            .name = example.name,
            .app = app_mod,
            .target = target,
            .optimize = optimize,
        });

        for (example.deps) |d| {
            switch (d) {
                .assets => {
                    if (b.lazyDependency("mach_example_assets", .{
                        .target = target,
                        .optimize = optimize,
                    })) |dep| app_mod.addImport("assets", dep.module("mach-example-assets"));
                },
                .freetype => {
                    if (b.lazyDependency("freetype", .{
                        .target = target,
                        .optimize = optimize,
                    })) |dep| app_mod.linkLibrary(dep.artifact("freetype"));
                },
                .zigimg => {
                    if (b.lazyDependency("zigimg", .{
                        .target = target,
                        .optimize = optimize,
                    })) |dep| app_mod.addImport("zigimg", dep.module("zigimg"));
                },
            }
        }

        if (target.result.os.tag == .ios) {
            example.install_step = &addIosBundle(b, exe, example.name).step;
            example.run_step.dependOn(addIosSimRun(b, example.install_step, example.name));
        } else {
            const run_cmd = b.addRunArtifact(exe);
            if (b.args) |args| run_cmd.addArgs(args);

            const installArtifact = b.addInstallArtifact(exe, .{});
            example.install_step = &installArtifact.step;
            run_cmd.step.dependOn(&installArtifact.step);
            example.run_step.dependOn(&run_cmd.step);
        }
    }
}

/// Wraps `exe` into an `<name>.app` bundle under the install prefix (so it ends up at
/// `zig-out/<name>.app/`). Returns a step that finishes once both the executable and a
/// minimal `Info.plist` have been installed.
///
/// The plist is generated inline. CFBundleExecutable / CFBundleName / CFBundleIdentifier are
/// derived from `name`. This mirrors the bundling pattern in `ios_test/build.zig`.
fn addIosBundle(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    name: []const u8,
) *std.Build.Step.InstallFile {
    const app_dir = b.fmt("{s}.app", .{name});

    // Install the executable inside the bundle as `<name>.app/<name>`.
    const copy_exe = b.addInstallFile(
        exe.getEmittedBin(),
        b.fmt("{s}/{s}", .{ app_dir, name }),
    );

    // Generate an Info.plist that points at the embedded executable and identifies the bundle.
    const plist = b.addWriteFiles().add("Info.plist", b.fmt(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
        \\ "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\    <key>CFBundleExecutable</key>
        \\    <string>{s}</string>
        \\    <key>CFBundleIdentifier</key>
        \\    <string>org.hexops.{s}</string>
        \\    <key>CFBundleName</key>
        \\    <string>{s}</string>
        \\    <key>CFBundleVersion</key>
        \\    <string>1</string>
        \\    <key>CFBundleShortVersionString</key>
        \\    <string>1.0</string>
        \\    <key>CFBundlePackageType</key>
        \\    <string>APPL</string>
        \\    <key>LSRequiresIPhoneOS</key>
        \\    <true/>
        \\    <key>UIRequiredDeviceCapabilities</key>
        \\    <array><string>arm64</string></array>
        \\    <key>UISupportedInterfaceOrientations</key>
        \\    <array>
        \\        <string>UIInterfaceOrientationPortrait</string>
        \\    </array>
        \\    <key>UILaunchStoryboardName</key>
        \\    <string></string>
        \\    <key>UIApplicationSceneManifest</key>
        \\    <dict>
        \\        <key>UIApplicationSupportsMultipleScenes</key>
        \\        <false/>
        \\    </dict>
        \\</dict>
        \\</plist>
    , .{ name, name, name }));
    const install_plist = b.addInstallFile(plist, b.fmt("{s}/Info.plist", .{app_dir}));
    install_plist.step.dependOn(&copy_exe.step);
    return install_plist;
}

/// Returns a build step that boots an iPhone simulator (if none is already booted), brings the
/// Simulator.app to the foreground, then `simctl install`s the bundle produced by `bundle_step` and
/// launches it with `--console-pty` so the app's stdout/stderr streams back to the terminal.
///
/// iOS simulator only runs on a macOS host; on any other host this returns a step that fails the
/// build.
fn addIosSimRun(
    b: *std.Build,
    bundle_step: *std.Build.Step,
    name: []const u8,
) *std.Build.Step {
    if (b.graph.host.result.os.tag != .macos) {
        const fail = b.addFail(b.fmt(
            "iOS simulator requires a macOS host machine (host is {s})",
            .{@tagName(b.graph.host.result.os.tag)},
        ));
        return &fail.step;
    }

    // TODO(ios): allow users to specify bundle ID
    const bundle_id = b.fmt("org.hexops.{s}", .{name});
    const app_path = b.getInstallPath(.prefix, b.fmt("{s}.app", .{name}));

    const run = IosSimRun.create(b, app_path, bundle_id);
    run.step.dependOn(bundle_step);
    return &run.step;
}

/// Custom `std.Build.Step` that uses `xcrun simctl` to install + launch an iOS simulator app
/// bundle. Replaces an earlier shell-script-based implementation.
const IosSimRun = struct {
    step: std.Build.Step,
    app_path: []const u8,
    bundle_id: []const u8,

    fn create(b: *std.Build, app_path: []const u8, bundle_id: []const u8) *IosSimRun {
        const self = b.allocator.create(IosSimRun) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = b.fmt("ios-sim-run {s}", .{bundle_id}),
                .owner = b,
                .makeFn = make,
            }),
            .app_path = b.dupe(app_path),
            .bundle_id = b.dupe(bundle_id),
        };
        return self;
    }

    fn make(step: *std.Build.Step, opts: std.Build.Step.MakeOptions) anyerror!void {
        _ = opts;
        const self: *IosSimRun = @fieldParentPtr("step", step);
        const arena = step.owner.allocator;
        const io = step.owner.graph.io;

        // If no simulator is booted, find an available iPhone device and boot it.
        const booted_list = try std.process.run(arena, io, .{
            .argv = &.{ "xcrun", "simctl", "list", "devices", "booted" },
        });
        defer arena.free(booted_list.stdout);
        defer arena.free(booted_list.stderr);

        if (std.mem.indexOf(u8, booted_list.stdout, "Booted") == null) {
            const available = try std.process.run(arena, io, .{
                .argv = &.{ "xcrun", "simctl", "list", "devices", "available" },
            });
            defer arena.free(available.stdout);
            defer arena.free(available.stderr);

            const dev_id = parseFirstIPhoneUdid(available.stdout) orelse {
                try step.result_error_msgs.append(arena, "no available iPhone simulator devices found");
                return error.MakeFailed;
            };

            try expectSuccess(step, arena, io, &.{ "xcrun", "simctl", "boot", dev_id }, "simctl boot");
        }

        // Bring Simulator.app to the foreground (idempotent).
        try expectSuccess(step, arena, io, &.{ "open", "-a", "Simulator" }, "open Simulator");

        // Install the freshly-bundled .app.
        try expectSuccess(step, arena, io, &.{ "xcrun", "simctl", "install", "booted", self.app_path }, "simctl install");

        // Launch with --console-pty so app stdio streams back to this terminal. We use spawn + wait
        // here (instead of `run`) to inherit stdio rather than capture it.
        var launch = try std.process.spawn(io, .{
            .argv = &.{ "xcrun", "simctl", "launch", "--console-pty", "booted", self.bundle_id },
        });
        const term = try launch.wait(io);
        if (term != .exited or term.exited != 0) {
            try step.result_error_msgs.append(arena, "simctl launch exited non-zero");
            return error.MakeFailed;
        }
    }

    /// Run a command via `std.process.run`, free its captured stdio, and fail the step
    /// with `tag` in the error message if the child did not exit successfully.
    fn expectSuccess(
        step: *std.Build.Step,
        arena: std.mem.Allocator,
        io: std.Io,
        argv: []const []const u8,
        tag: []const u8,
    ) !void {
        const result = try std.process.run(arena, io, .{ .argv = argv });
        defer arena.free(result.stdout);
        defer arena.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) {
            const msg = std.fmt.allocPrint(arena, "{s} failed (term={any}): {s}", .{
                tag,
                result.term,
                std.mem.trim(u8, result.stderr, " \t\r\n"),
            }) catch "command failed";
            try step.result_error_msgs.append(arena, msg);
            return error.MakeFailed;
        }
    }

    /// Find the first iPhone UDID (8-4-4-4-12 hex form) in `xcrun simctl list devices`
    /// output. Returns a slice into `text`, so the caller must keep `text` alive.
    fn parseFirstIPhoneUdid(text: []const u8) ?[]const u8 {
        var iter = std.mem.splitScalar(u8, text, '\n');
        while (iter.next()) |line| {
            if (std.mem.indexOf(u8, line, "iPhone") == null) continue;
            const open_paren = std.mem.indexOfScalar(u8, line, '(') orelse continue;
            const close_paren = std.mem.indexOfScalarPos(u8, line, open_paren, ')') orelse continue;
            const candidate = line[open_paren + 1 .. close_paren];
            // UDIDs are formatted XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX (36 chars).
            if (candidate.len == 36) return candidate;
        }
        return null;
    }
};

fn buildEditor(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
    editor_step: *std.Build.Step,
) void {
    // Custom build step for producing build info (such as Mach and Zig version used.)
    const version_step = BuildInfoStep.create(b);
    const build_info_mod = b.createModule(.{
        .root_source_file = version_step.getOutput(),
    });

    const editor_mod = b.createModule(.{
        .root_source_file = b.path("editor/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    editor_mod.addImport("build_info", build_info_mod);

    const editor_exe = b.addExecutable(.{
        .name = "mach",
        .root_module = editor_mod,
    });

    const install_editor = b.addInstallArtifact(editor_exe, .{});
    editor_step.dependOn(&install_editor.step);
}

/// Custom build step for producing build info (such as Mach and Zig version used.)
///
/// Generates a build_info.zig file with `mach_version` (git tag or commit SHA) and
/// `mach_zig_version` string constants.
const BuildInfoStep = struct {
    step: std.Build.Step,
    generated_file: std.Build.GeneratedFile,

    fn create(b: *std.Build) *BuildInfoStep {
        const bs = b.allocator.create(BuildInfoStep) catch @panic("OOM");
        bs.* = .{
            .step = .init(.{
                .id = .custom,
                .name = "generate build_info.zig",
                .owner = b,
                .makeFn = make,
            }),
            .generated_file = .{ .step = &bs.step },
        };
        return bs;
    }

    fn getOutput(bs: *BuildInfoStep) std.Build.LazyPath {
        return .{ .generated = .{ .file = &bs.generated_file } };
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
        const b = step.owner;
        const bs: *BuildInfoStep = @fieldParentPtr("step", step);

        // Read the Mach Zig version from build.zig.zon.
        const zon_bytes = b.build_root.handle.readFileAlloc(b.graph.io, "build.zig.zon", b.allocator, .limited(1 * 1024 * 1024)) catch |err|
            return step.fail("unable to read build.zig.zon: {t}", .{err});
        const mach_zig_version = parseMachZigVersion(zon_bytes) orelse
            return step.fail("unable to find .mach_zig_version in build.zig.zon", .{});

        // Run git: prefer exact-match tag, otherwise full commit SHA.
        var code: u8 = 0;
        const git_dir = b.build_root.path orelse ".";
        const raw_version = b.runAllowFail(
            &.{ "git", "-C", git_dir, "describe", "--tags", "--exact-match", "HEAD" },
            &code,
            .ignore,
        ) catch b.runAllowFail(
            &.{ "git", "-C", git_dir, "rev-parse", "HEAD" },
            &code,
            .ignore,
        ) catch "unknown";
        const mach_version = std.mem.trim(u8, raw_version, " \r\n\t");

        const contents = try std.fmt.allocPrint(b.allocator,
            \\pub const mach_version: []const u8 = "{s}";
            \\pub const mach_zig_version: []const u8 = "{s}";
            \\
        , .{ mach_version, mach_zig_version });

        // Write to a deterministic cache location, hashed by the file
        // contents themselves.
        const digest = std.Build.Cache.HashHelper.oneShot(contents);
        const sub_path = b.pathJoin(&.{ "o", &digest, "build_info.zig" });
        const cache_path = b.cache_root.join(b.allocator, &.{sub_path}) catch @panic("OOM");

        b.cache_root.handle.createDirPath(b.graph.io, b.pathJoin(&.{ "o", &digest })) catch |err|
            return step.fail("unable to create cache dir: {t}", .{err});
        b.cache_root.handle.writeFile(b.graph.io, .{ .sub_path = sub_path, .data = contents }) catch |err|
            return step.fail("unable to write {s}: {t}", .{ cache_path, err });

        bs.generated_file.path = cache_path;
    }

    fn parseMachZigVersion(zon: []const u8) ?[]const u8 {
        const key = ".mach_zig_version";
        var idx: usize = 0;
        while (std.mem.indexOfPos(u8, zon, idx, key)) |k| {
            // Ensure preceding char is whitespace or start, to avoid matching .foo_mach_zig_version
            const prev_ok = k == 0 or std.ascii.isWhitespace(zon[k - 1]) or zon[k - 1] == ',';
            idx = k + key.len;
            if (!prev_ok) continue;
            const start_quote = std.mem.indexOfScalarPos(u8, zon, idx, '"') orelse return null;
            const end_quote = std.mem.indexOfScalarPos(u8, zon, start_quote + 1, '"') orelse return null;
            return zon[start_quote + 1 .. end_quote];
        }
        return null;
    }
};

const SysAudioTest = struct {
    name: []const u8,
    run_step: *std.Build.Step = undefined,
};

comptime {
    const supported_zig = std.SemanticVersion.parse("0.16.0-dev.3142+5ccfeb926") catch unreachable;
    if (builtin.zig_version.order(supported_zig) != .eq) {
        @compileError(std.fmt.comptimePrint("unsupported Zig version ({}). Required Zig version 2026.4.10-mach: https://machengine.org/docs/zig-version/", .{builtin.zig_version}));
    }
}
