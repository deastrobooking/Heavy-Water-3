const std = @import("std");
const mach = @import("mach");
const options = @import("options");
const Engine = @import("engine/Engine.zig");
const World = @import("world/World.zig");
const Renderer = @import("render/Renderer.zig");
const TestWorld = @import("game/TestWorld.zig");
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
pub const deinit = mach.schedule(.{ .{ App, .stop }, .{ Renderer, .deinit } });

engine: Engine = .{},
thread: mach.Thread = undefined,
timer: mach.time.Timer = undefined,
window: mach.ObjectID = undefined,
show_metrics: bool = true,
culling: bool = false,
captured: bool = false,
rendered_frames_seen: u64 = 0,
smoke_stage: u64 = 0,

pub fn init(self: *App, core: *mach.Core, world: *World, app_mod: mach.Mod(App), renderer_mod: mach.Mod(Renderer), io: std.Io) !void {
    self.* = .{ .timer = mach.time.Timer.start(io) };
    core.on_exit = app_mod.id.deinit;
    self.window = try core.windows.new(.{ .title = "Heavy Water | Engine Field Test", .width = 1280, .height = 800, .on_render = renderer_mod.id.render });
    try TestWorld.populate(world, options.seed);
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
            .r => self.engine.camera = .{},
            .f1 => self.show_metrics = !self.show_metrics,
            .c => self.culling = !self.culling,
            else => {},
        },
        .mouse_press => |mouse| if (mouse.button == .left) {
            self.capture(core, true);
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
    if (options.smoke_frames > 0) self.exerciseSmoke(core);
    self.engine.update(self.timer.lap());
}

fn exerciseSmoke(self: *App, core: *mach.Core) void {
    const stage = @min(3, self.rendered_frames_seen * 4 / options.smoke_frames);
    if (stage == self.smoke_stage) return;
    self.smoke_stage = stage;
    switch (stage) {
        1 => {
            self.culling = true;
            self.engine.camera.yaw = 0.4;
        },
        2 => {
            core.windows.lock();
            defer core.windows.unlock();
            core.windows.set(self.window, .width, 960);
            core.windows.set(self.window, .height, 640);
        },
        3 => {
            self.show_metrics = false;
            self.engine.camera = .{};
        },
        else => {},
    }
    std.log.info("Smoke stage {d}: culling={any}, hud={any}", .{ stage, self.culling, self.show_metrics });
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
}

pub fn stop(self: *App) void {
    self.thread.join();
}
