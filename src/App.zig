const std = @import("std");
const mach = @import("mach");
const options = @import("options");
const Engine = @import("engine/Engine.zig");
const Time = @import("engine/Time.zig");
const World = @import("world/World.zig");
const Renderer = @import("render/Renderer.zig");
const Overlay = @import("render/Overlay.zig");
const TestWorld = @import("game/TestWorld.zig");
const Sandbox = @import("game/Sandbox.zig");
const Save = @import("game/Save.zig");
const Build = @import("game/Build.zig");
const Blueprint = @import("machine/Blueprint.zig");
const prefab_dir = "saves/prefabs";
const Creator = @import("game/Creator.zig");
const App = @This();

pub const Modules = mach.Modules(.{ mach.Core, App, World, Renderer });
pub const mach_module = .app;
pub const mach_systems = .{ .main, .init, .start, .tick, .update, .publish, .deinit, .stop };
pub const main = mach.schedule(.{
    .{ mach.Core, .init }, .{ World, .init }, .{ App, .init }, .{ Renderer, .init }, .{ App, .start }, .{ mach.Core, .main },
});
pub const tick = mach.schedule(.{
    .{ App, .update }, .{ mach.Core, .snapshotStart }, .{ App, .publish }, .{ mach.Core, .snapshotEnd },
});
pub const deinit = mach.schedule(.{ .{ App, .stop }, .{ Renderer, .deinit }, .{ World, .deinit } });

engine: Engine = .{},
sandbox: Sandbox = undefined,
/// Edge-triggered actions collected from events, consumed by the next fixed step.
actions: Sandbox.Actions = .{},
allocator: std.mem.Allocator = undefined,
io: std.Io = undefined,
thread: mach.Thread = undefined,
timer: mach.time.Timer = undefined,
window: mach.ObjectID = undefined,
show_metrics: bool = true,
culling: bool = true,
captured: bool = false,
rendered_frames_seen: u64 = 0,
smoke_stage: u64 = 0,
smoke_rover_start: ?[3]f32 = null,
status: Overlay.Line = .{},
status_until: u64 = 0,
published_revision: ?u64 = null,
inspecting: bool = false,

pub fn init(self: *App, core: *mach.Core, world: *World, app_mod: mach.Mod(App), renderer_mod: mach.Mod(Renderer), io: std.Io, allocator: std.mem.Allocator) !void {
    self.* = .{ .timer = mach.time.Timer.start(io), .allocator = allocator, .io = io };
    core.on_exit = app_mod.id.deinit;
    self.window = try core.windows.new(.{ .title = "Heavy Water | Procedural Frontier", .width = 1280, .height = 800, .on_render = renderer_mod.id.render });
    TestWorld.configure(world, options.seed);
    try self.sandbox.init(allocator, options.seed, &world.catalog, &self.engine.camera);
    self.importPrefabs();
    // A new game begins by creating the character (not in unattended smoke or benchmark runs).
    if (options.smoke_frames == 0 and options.benchmark_frames == 0) self.sandbox.creator.begin(self.sandbox.profile);
}

/// While the creator is open, every key goes to it.
fn creatorKey(self: *App, key: mach.Core.KeyButtonID) void {
    const k: Creator.Key = switch (key) {
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
        .enter, .kp_enter => .enter,
        .escape => .escape,
        .backspace, .delete => .backspace,
        .space => .{ .char = ' ' },
        .minus => .{ .char = '-' },
        else => blk: {
            const tag = @tagName(key);
            if (tag.len == 1) break :blk .{ .char = tag[0] };
            const digits = [_][]const u8{ "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" };
            for (digits, 0..) |d, i| if (std.mem.eql(u8, tag, d)) break :blk .{ .char = '0' + @as(u8, @intCast(i)) };
            return;
        },
    };
    switch (self.sandbox.creator.key(k)) {
        .editing => {},
        .confirmed => |profile| {
            self.sandbox.profile = profile;
            self.report("WELCOME, {s}", .{profile.name()});
        },
        .canceled => {},
    }
}

/// Loads every valid blueprint in the prefab directory into the palette; invalid files are
/// skipped with a log line, never partially applied.
fn importPrefabs(self: *App) void {
    var dir = std.Io.Dir.cwd().openDir(self.io, prefab_dir, .{ .iterate = true }) catch return;
    defer dir.close(self.io);
    var it = dir.iterate();
    var loaded: usize = 0;
    while (it.next(self.io) catch null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
        const bytes = dir.readFileAlloc(self.io, entry.name, self.allocator, .limited(1 << 20)) catch |err| {
            std.log.warn("prefab {s}: {s}", .{ entry.name, @errorName(err) });
            continue;
        };
        defer self.allocator.free(bytes);
        const bp = Blueprint.parse(self.allocator, bytes) catch |err| {
            std.log.warn("prefab {s}: {s}", .{ entry.name, @errorName(err) });
            continue;
        };
        _ = self.sandbox.addPrefab(bp) catch break;
        loaded += 1;
    }
    if (loaded > 0) std.log.info("Imported {d} prefabs from {s}", .{ loaded, prefab_dir });
}

/// Writes a captured prefab as a blueprint file other worlds import at startup.
fn exportPrefab(self: *App, index: usize) void {
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();
    const bp = &self.sandbox.prefabs[index];
    const doc = bp.toDoc(arena.allocator()) catch return self.report("EXPORT FAILED", .{});
    const json = std.json.Stringify.valueAlloc(arena.allocator(), doc, .{ .whitespace = .indent_2 }) catch return self.report("EXPORT FAILED", .{});
    const path = std.fmt.allocPrint(arena.allocator(), "{s}/{s}.json", .{ prefab_dir, bp.name() }) catch return;
    Save.writeFile(self.io, path, json) catch |err| return self.report("EXPORT FAILED {s}", .{@errorName(err)});
    std.log.info("Exported prefab {s}", .{path});
}

pub fn start(self: *App, core: *mach.Core, app_mod: mach.Mod(App), core_mod: mach.Mod(mach.Core)) !void {
    self.thread = try mach.startThread(core, app_mod.id.tick, core_mod, .app);
}

pub fn update(self: *App, core: *mach.Core) void {
    var events = core.events(.default);
    while (events.next()) |event| switch (event) {
        .close => core.exit(),
        .key_press => |key| if (self.sandbox.creator.open) self.creatorKey(key.key) else switch (key.key) {
            .escape => self.capture(core, false),
            .f2 => self.actions.toggle_view = true,
            .f4 => self.actions.open_creator = true,
            .r => self.actions.reset = true,
            .v => self.actions.toggle_mode = true,
            .f1 => self.show_metrics = !self.show_metrics,
            .c => self.culling = !self.culling,
            .f5 => self.quicksave(),
            .f9 => self.quickload(),
            .one => self.actions.select_tool = 1,
            .two => self.actions.select_tool = 2,
            .three => self.actions.select_tool = 3,
            .tab => self.actions.next_item = true,
            .t => self.actions.rotate = true,
            .p => self.actions.capture = true,
            .left_bracket => self.actions.channel_down = true,
            .right_bracket => self.actions.channel_up = true,
            .i => self.inspecting = !self.inspecting,
            else => {},
        },
        .mouse_press => |mouse| switch (mouse.button) {
            .left => if (self.captured) {
                self.actions.interact = true;
            } else self.capture(core, true),
            .right => if (self.captured) {
                self.actions.secondary = true;
            },
            else => {},
        },
        .mouse_capture_gained => self.captured = true,
        .mouse_capture_lost, .focus_lost => {
            self.captured = false;
            self.engine.input = .{};
        },
        .mouse_motion_relative => |motion| if (self.captured) {
            self.engine.input.look_x += @floatCast(motion.dx);
            self.engine.input.look_y += @floatCast(motion.dy);
        },
        else => {},
    };
    self.engine.input.sample(core);
    if (options.smoke_frames > 0 and options.benchmark_frames == 0) {
        self.exerciseSmoke();
        // The last smoke stage drives the rover at full throttle.
        if (self.sandbox.seated != null) self.engine.input.forward = 1;
    }
    const steps = self.engine.advance(self.timer.lap());
    for (0..steps) |_| {
        self.sandbox.step(&self.engine.camera, self.engine.input, self.actions, Time.fixed_dt) catch |err| self.report("ERROR {s}", .{@errorName(err)});
        self.actions = .{};
    }
    if (self.sandbox.exported) |index| {
        self.sandbox.exported = null;
        self.exportPrefab(index);
    }
}

fn report(self: *App, comptime fmt: []const u8, args: anytype) void {
    self.status.set(fmt, args);
    self.status_until = self.engine.time.tick + 4 * 60;
    std.log.info("{s}", .{self.status.slice()});
}

/// File I/O runs on the application thread between fixed steps; rendering is unaffected.
fn quicksave(self: *App) void {
    const bytes = self.sandbox.save(self.allocator, self.engine.camera) catch |err| return self.report("SAVE FAILED {s}", .{@errorName(err)});
    defer self.allocator.free(bytes);
    Save.writeFile(self.io, Save.default_path, bytes) catch |err| return self.report("SAVE FAILED {s}", .{@errorName(err)});
    self.report("SAVED {s}", .{Save.default_path});
}

fn quickload(self: *App) void {
    const bytes = Save.readFile(self.io, self.allocator, Save.default_path) catch |err| return self.report("LOAD FAILED {s}", .{@errorName(err)});
    defer self.allocator.free(bytes);
    self.sandbox.restore(self.allocator, bytes, &self.engine.camera) catch |err| return self.report("LOAD FAILED {s}", .{@errorName(err)});
    // Prefabs saved with the world come first; the shared library fills in the rest.
    self.importPrefabs();
    self.report("LOADED {s}", .{Save.default_path});
}

fn exerciseSmoke(self: *App) void {
    const stage = @min(4, self.rendered_frames_seen * 5 / options.smoke_frames);
    if (stage == self.smoke_stage) return;
    self.smoke_stage = stage;
    const camera = &self.engine.camera;
    switch (stage) {
        1 => {
            // Create a character through the same key path the window uses.
            self.sandbox.creator.begin(self.sandbox.profile);
            for ([_]mach.Core.KeyButtonID{ .backspace, .backspace, .backspace, .backspace, .backspace, .backspace, .s, .o, .r, .a, .down, .right, .down, .down, .down, .right, .enter }) |key| self.creatorKey(key);
            std.log.info("Smoke character: {s}, hair style {s}", .{ self.sandbox.profile.name(), @tagName(self.sandbox.profile.hair_style) });
            self.culling = true;
            self.sandbox.player.setMode(.fly, camera.*);
            camera.position = mach.math.vec3(180, 35, 120);
            camera.yaw = 0.4;
        },
        2 => {
            // Look away to exercise a frame with zero visible relics.
            camera.yaw = std.math.pi;
            camera.position = mach.math.vec3(-400, 35, -300);
        },
        3 => {
            // Walk mode at spawn in third person, aim at the crate row, and grab.
            self.show_metrics = false;
            self.sandbox.view = .third;
            self.sandbox.player.mode = .walk;
            self.sandbox.resetPlayer(camera);
            const crate = self.sandbox.cratePosition(1);
            const eye = camera.position;
            const dx = crate[0] - eye.x();
            const dz = crate[2] - eye.z();
            camera.yaw = std.math.atan2(dx, dz);
            camera.pitch = std.math.atan2(crate[1] - eye.y(), @sqrt(dx * dx + dz * dz));
            self.actions.interact = true;
        },
        4 => {
            // In-memory save/restore round trip; never touches the user's save file.
            const held = self.sandbox.held;
            const bytes = self.sandbox.save(self.allocator, camera.*) catch |err| return self.report("SMOKE SAVE {s}", .{@errorName(err)});
            defer self.allocator.free(bytes);
            self.sandbox.restore(self.allocator, bytes, camera) catch |err| return self.report("SMOKE LOAD {s}", .{@errorName(err)});
            std.log.info("Smoke interaction: held={any}, machines={d}, save round trip {d} bytes", .{ held, self.sandbox.machineCount(), bytes.len });
            // Build a powered lamp circuit directly through the tool APIs, then drive.
            self.smokeBuild();
            if (self.smoke_rover_start == null) self.smoke_rover_start = self.sandbox.physics.rigidPose(self.sandbox.machines[2].vehicle.?.rigid).?.position;
            // Press the door button, then take the rover for the rest of the run.
            self.sandbox.press = self.sandbox.findDevice(0, "button");
            self.sandbox.enterVehicle(2, camera);
        },
        else => {},
    }
    std.log.info("Smoke stage {d}: culling={any}, hud={any}, mode={s}", .{ stage, self.culling, self.show_metrics, @tagName(self.sandbox.player.mode) });
}

fn smokeBuild(self: *App) void {
    const sb = &self.sandbox;
    const base = self.engine.camera.position;
    const kits = [_]Build.Item{ .generator, .button, .latch, .lamp };
    var refs: [kits.len]Sandbox.DeviceRef = undefined;
    for (kits, 0..) |item, i| {
        const x = base.x() + 3 + @as(f32, @floatFromInt(i)) * 1.5;
        const z = base.z() - 3;
        const point = .{ x, @import("procedural/Terrain.zig").surface(sb.seed, x, z).height + 0.7, z };
        refs[i] = sb.addWorkshopDevice(Build.kitDevice(item, @tagName(item)), point) catch |err| return self.report("SMOKE BUILD {s}", .{@errorName(err)});
    }
    const w = refs[0].machine;
    const bp = &sb.machines[w].blueprint;
    for ([_][2]usize{ .{ 0, 3 }, .{ 1, 2 }, .{ 2, 3 } }) |pair| {
        var buffer: [Build.max_candidates]@import("machine/Blueprint.zig").Wire = undefined;
        const n = Build.candidates(sb, refs[pair[0]], refs[pair[1]], &buffer);
        if (n == 0) return self.report("SMOKE WIRE NONE", .{});
        bp.connect(buffer[0].from, buffer[0].to) catch |err| return self.report("SMOKE WIRE {s}", .{@errorName(err)});
    }
    sb.machines[w].machine.reconfigure();
    sb.press = refs[1];
    // Capture it as a prefab (without exporting into the user's library) and place a copy.
    sb.target = .{ .device = refs[3] };
    Build.capture(sb);
    sb.exported = null;
    sb.tools = .{};
    const copy_origin = .{ base.x() + 3, @import("procedural/Terrain.zig").surface(sb.seed, base.x() + 3, base.z() - 8).height, base.z() - 8 };
    const copy = sb.spawnMachine(null, sb.prefabs[sb.prefab_count - 1], copy_origin, 1, false) catch |err| return self.report("SMOKE COPY {s}", .{@errorName(err)});
    std.log.info("Smoke build: workshop devices={d} wires={d}; prefab {s} placed in slot {d}", .{ bp.device_count, bp.wire_count, sb.prefabs[sb.prefab_count - 1].name(), copy });
}

fn capture(self: *App, core: *mach.Core, enabled: bool) void {
    core.windows.lock();
    defer core.windows.unlock();
    core.windows.set(self.window, .mouse_capture, enabled);
    if (!enabled) self.captured = false;
}

pub fn publish(self: *App, renderer: *Renderer) void {
    self.rendered_frames_seen = renderer.frames;
    renderer.camera = self.engine.camera;
    renderer.tick = self.engine.time.tick;
    renderer.show_metrics = self.show_metrics;
    renderer.culling = self.culling;
    renderer.prop_count = self.sandbox.publishProps(&renderer.props);
    // The removal set is large; copy it only when it changed.
    if (self.published_revision != self.sandbox.modifications.revision) {
        renderer.modifications = self.sandbox.modifications;
        self.published_revision = self.sandbox.modifications.revision;
    }
    const sandbox = &self.sandbox;
    renderer.crosshair = sandbox.seated == null and !sandbox.creator.open and (self.captured or sandbox.player.mode == .walk);
    renderer.hud_lines[0].set("{s}  {s}  TOOL {s}  SALVAGED {d}  1 2 3 TOOLS", .{ sandbox.profile.name(), if (sandbox.seated != null) "DRIVE" else if (sandbox.player.mode == .walk) "WALK" else "FLY", @tagName(sandbox.tools.tool), sandbox.modifications.len });
    if (sandbox.seated) |m| {
        const placed = &sandbox.machines[m];
        const motor = placed.machine.blueprint.vehicle.?.motor;
        renderer.hud_lines[1].set("{d:.1} M/S  POWER {d:.0}%  WASD DRIVE  SPACE BRAKE  CLICK EXIT", .{ placed.vehicle.?.forwardSpeed(&sandbox.physics), placed.machine.satisfaction(motor) * 100 });
    } else if (sandbox.held) |i| {
        renderer.hud_lines[1].set("HOLDING CRATE {d}  CLICK DROP", .{i});
    } else switch (sandbox.target) {
        .prop => |i| renderer.hud_lines[1].set("CRATE {d}  CLICK GRAB", .{i}),
        .relic => |r| renderer.hud_lines[1].set("RELIC {d}:{d}:{d}  RMB SALVAGE", .{ r.ref.x, r.ref.z, r.ref.id }),
        .structure => |m| renderer.hud_lines[1].set("{s} STRUCTURE", .{sandbox.machines[m].blueprint.name()}),
        .device => |ref| {
            const machine = &sandbox.machines[ref.machine].machine;
            const def = machine.blueprint.device(ref.device);
            switch (def.kind) {
                .button => renderer.hud_lines[1].set("{s} BUTTON  CLICK PRESS", .{def.name()}),
                .seat => renderer.hud_lines[1].set("{s}  CLICK ENTER", .{machine.blueprint.name()}),
                .transmitter, .receiver => renderer.hud_lines[1].set("{s} {s} CHANNEL {d}  [ ] CHANGE", .{ def.name(), @tagName(def.kind), def.channel }),
                .lamp => renderer.hud_lines[1].set("{s} LAMP {s}", .{ def.name(), if (machine.outputs[ref.device][2] > 0) "LIT" else "DARK" }),
                .generator => renderer.hud_lines[1].set("GENERATOR {d:.0} W  LOAD {d:.0} W", .{ machine.outputs[ref.device][0], machine.network(ref.device).?.demand }),
                .actuator => renderer.hud_lines[1].set("{s} {d:.0}%  POWER {d:.0}%", .{ def.name(), machine.state[ref.device] * 100, machine.satisfaction(ref.device) * 100 }),
                else => renderer.hud_lines[1].set("{s}", .{def.name()}),
            }
        },
        .none => renderer.hud_lines[1] = .{},
    }
    renderer.panel_count = 0;
    if (sandbox.creator.open) {
        var lines: [Renderer.panel_capacity]Creator.Line = undefined;
        const count = sandbox.creator.lines(&lines);
        for (lines[0..count], renderer.panel[0..count]) |*line, *out| out.set("{s}", .{line.slice()});
        renderer.panel_count = count;
    } else if (self.inspecting and sandbox.seated == null) {
        var lines: [Renderer.panel_capacity]Build.PanelLine = @splat(.{});
        const count = Build.inspect(sandbox, &lines);
        for (lines[0..count], renderer.panel[0..count]) |*line, *out| out.set("{s}", .{line.slice()});
        renderer.panel_count = count;
    }
    var hint_buffer: [96]u8 = undefined;
    const hint = Build.hint(sandbox, &hint_buffer);
    if (sandbox.seated == null and hint.len > 0 and sandbox.target != .device) renderer.hud_lines[1].set("{s}", .{hint});
    if (sandbox.tools.tool == .wire and Build.pendingWire(sandbox) != null) renderer.hud_lines[1].set("{s}", .{hint});
    renderer.hud_lines[2] = if (self.engine.time.tick < self.status_until) self.status else .{};
    if (renderer.hud_lines[2].len == 0 and sandbox.noticeText().len > 0) renderer.hud_lines[2].set("{s}", .{sandbox.noticeText()});
}

pub fn stop(self: *App) void {
    self.thread.join();
    defer self.sandbox.deinit();
    // The app thread has exited, so the sandbox can be read safely.
    if (self.smoke_rover_start) |origin| {
        const now = self.sandbox.physics.rigidPose(self.sandbox.machines[2].vehicle.?.rigid).?.position;
        const dx = now[0] - origin[0];
        const dz = now[2] - origin[2];
        std.log.info("Smoke drive: rover moved {d:.1} m", .{@sqrt(dx * dx + dz * dz)});
    }
}
