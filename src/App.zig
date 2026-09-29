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
status: Overlay.Line = .{},
status_until: u64 = 0,
published_revision: ?u64 = null,

pub fn init(self: *App, core: *mach.Core, world: *World, app_mod: mach.Mod(App), renderer_mod: mach.Mod(Renderer), io: std.Io, allocator: std.mem.Allocator) !void {
    self.* = .{ .timer = mach.time.Timer.start(io), .allocator = allocator, .io = io };
    core.on_exit = app_mod.id.deinit;
    self.window = try core.windows.new(.{ .title = "Heavy Water | Procedural Frontier", .width = 1280, .height = 800, .on_render = renderer_mod.id.render });
    TestWorld.configure(world, options.seed);
    try self.sandbox.init(options.seed, &world.catalog, &self.engine.camera);
}

pub fn start(self: *App, core: *mach.Core, app_mod: mach.Mod(App), core_mod: mach.Mod(mach.Core)) !void {
    self.thread = try mach.startThread(core, app_mod.id.tick, core_mod, .app);
}

pub fn update(self: *App, core: *mach.Core) void {
    var events = core.events(.default);
    while (events.next()) |event| switch (event) {
        .close => core.exit(),
        .key_press => |key| switch (key.key) {
            .escape => self.capture(core, false),
            .r => self.actions.reset = true,
            .v => self.actions.toggle_mode = true,
            .f1 => self.show_metrics = !self.show_metrics,
            .c => self.culling = !self.culling,
            .f5 => self.quicksave(),
            .f9 => self.quickload(),
            else => {},
        },
        .mouse_press => |mouse| switch (mouse.button) {
            .left => if (self.captured) {
                self.actions.interact = true;
            } else self.capture(core, true),
            .right => if (self.captured) {
                self.actions.salvage = true;
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
    if (options.smoke_frames > 0 and options.benchmark_frames == 0) self.exerciseSmoke();
    const steps = self.engine.advance(self.timer.lap());
    for (0..steps) |_| {
        self.sandbox.step(&self.engine.camera, self.engine.input, self.actions, Time.fixed_dt) catch |err| self.report("ERROR {s}", .{@errorName(err)});
        self.actions = .{};
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
    self.report("LOADED {s}", .{Save.default_path});
}

fn exerciseSmoke(self: *App) void {
    const stage = @min(4, self.rendered_frames_seen * 5 / options.smoke_frames);
    if (stage == self.smoke_stage) return;
    self.smoke_stage = stage;
    const camera = &self.engine.camera;
    switch (stage) {
        1 => {
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
            // Walk mode at spawn, aim at the crate row, and grab.
            self.show_metrics = false;
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
            std.log.info("Smoke interaction: held={any}, machines={d}, save round trip {d} bytes", .{ held, self.sandbox.machine_count, bytes.len });
            // Press the door button; the rest of the run renders the door opening.
            self.sandbox.press = self.sandbox.findDevice(0, "button");
        },
        else => {},
    }
    std.log.info("Smoke stage {d}: culling={any}, hud={any}, mode={s}", .{ stage, self.culling, self.show_metrics, @tagName(self.sandbox.player.mode) });
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
    renderer.crosshair = self.captured or sandbox.player.mode == .walk;
    renderer.hud_lines[0].set("{s}  SALVAGED {d}  TOOL SALVAGE CUTTER", .{ if (sandbox.player.mode == .walk) "WALK" else "FLY", sandbox.modifications.len });
    if (sandbox.held) |i| {
        renderer.hud_lines[1].set("HOLDING CRATE {d}  CLICK DROP", .{i});
    } else switch (sandbox.target) {
        .prop => |i| renderer.hud_lines[1].set("CRATE {d}  CLICK GRAB", .{i}),
        .relic => |r| renderer.hud_lines[1].set("RELIC {d}:{d}:{d}  RMB SALVAGE", .{ r.ref.x, r.ref.z, r.ref.id }),
        .device => |ref| {
            const machine = &sandbox.machines[ref.machine].machine;
            const def = machine.blueprint.device(ref.device);
            switch (def.kind) {
                .button => renderer.hud_lines[1].set("{s} BUTTON  CLICK PRESS", .{def.name()}),
                .generator => renderer.hud_lines[1].set("GENERATOR {d:.0} W  LOAD {d:.0} W", .{ machine.outputs[ref.device][0], machine.network(ref.device).?.demand }),
                .actuator => renderer.hud_lines[1].set("{s} {d:.0}%  POWER {d:.0}%", .{ def.name(), machine.state[ref.device] * 100, machine.satisfaction(ref.device) * 100 }),
                else => renderer.hud_lines[1].set("{s}", .{def.name()}),
            }
        },
        .none => renderer.hud_lines[1] = .{},
    }
    renderer.hud_lines[2] = if (self.engine.time.tick < self.status_until) self.status else .{};
}

pub fn stop(self: *App) void {
    self.thread.join();
}
