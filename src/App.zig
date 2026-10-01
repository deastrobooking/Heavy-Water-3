const std = @import("std");
const mach = @import("mach");
const options = @import("options");
const Engine = @import("engine/Engine.zig");
const Time = @import("engine/Time.zig");
const Sky = @import("engine/Sky.zig");
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
const Gamepads = @import("engine/Gamepads.zig");
const Loader = @import("asset/Loader.zig");
const Profile = @import("game/Profile.zig");
const Life = @import("city/Life.zig");
const Market = @import("city/Market.zig");
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
pads: Gamepads = .{},
/// Background asset loading: deferred catalog meshes are built here and installed in `publish`.
loader: ?*Loader = null,
deferred: [8]?Loader.Ticket = @splat(null),
deferred_handles: [8]@import("asset/Catalog.zig").MeshHandle = undefined,
catalog: *@import("asset/Catalog.zig") = undefined,
started: std.Io.Timestamp = undefined,
/// `-Dpack-stress`: a generated pack loaded during the measured benchmark frames.
stress_pack: ?u8 = null,
stress_tickets: [64]?Loader.Ticket = @splat(null),
stress_handles: [64]@import("asset/Catalog.zig").MeshHandle = undefined,
stress_bytes: u64 = 0,
stress_installed: u32 = 0,
stress_requested: bool = false,
/// Guests joined from a controller leave when it disconnects; F6 and smoke guests stay.
pad_guests: [Sandbox.max_players - 1]bool = @splat(false),

pub fn init(self: *App, core: *mach.Core, world: *World, app_mod: mach.Mod(App), renderer_mod: mach.Mod(Renderer), io: std.Io, allocator: std.mem.Allocator) !void {
    self.* = .{ .timer = mach.time.Timer.start(io), .allocator = allocator, .io = io };
    core.on_exit = app_mod.id.deinit;
    self.window = try core.windows.new(.{ .title = "Heavy Water | Procedural Frontier", .width = 1280, .height = 800, .on_render = renderer_mod.id.render });
    TestWorld.configure(world, options.seed);
    try self.sandbox.init(allocator, options.seed, &world.catalog, &self.engine.camera);
    self.catalog = &world.catalog;
    self.started = std.Io.Timestamp.now(io, .awake);
    self.loader = try Loader.create(allocator, io);
    for (world.catalog.pending[0..world.catalog.pending_count], 0..) |p, i| {
        self.deferred[i] = try self.loader.?.request(.{ .generate = p.generator }, 0);
        self.deferred_handles[i] = p.handle;
    }
    if (options.pack_stress > 0) try self.writeStressPack(&world.catalog);
    self.sandbox.enableLife();
    self.importPrefabs();
    self.loadMods();
    // A new game begins by creating the character (not in unattended smoke or benchmark runs).
    if (options.smoke_frames == 0 and options.benchmark_frames == 0 and options.showcase == 0) self.sandbox.creator.begin(self.sandbox.profile);
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

/// While a market stall is open, arrows, Enter, and Escape drive its panel.
fn tradeKey(key: mach.Core.KeyButtonID) ?Sandbox.TradeKey {
    return switch (key) {
        .up => .up,
        .down => .down,
        .enter, .kp_enter => .confirm,
        .escape => .close,
        else => null,
    };
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

/// Installs every valid package in `mods/<name>/`. A rejected package is logged with its reason
/// and leaves the world unchanged.
fn loadMods(self: *App) void {
    var dir = std.Io.Dir.cwd().openDir(self.io, "mods", .{ .iterate = true }) catch return;
    defer dir.close(self.io);
    var it = dir.iterate();
    while (it.next(self.io) catch null) |entry| {
        if (entry.kind != .directory) continue;
        var sub = dir.openDir(self.io, entry.name, .{}) catch continue;
        defer sub.close(self.io);
        const Files = struct {
            dir: std.Io.Dir,
            io: std.Io,
            pub fn read(files: @This(), allocator: std.mem.Allocator, path: []const u8) ![]u8 {
                return files.dir.readFileAlloc(files.io, path, allocator, .limited(@import("mod/Mod.zig").max_file_bytes));
            }
        };
        var pkg = @import("mod/Mod.zig").load(self.allocator, entry.name, Files{ .dir = sub, .io = self.io }) catch |err| {
            std.log.warn("mod {s} rejected: {s}", .{ entry.name, @errorName(err) });
            continue;
        };
        defer pkg.deinit();
        self.sandbox.installMod(&pkg) catch |err| {
            std.log.warn("mod {s} not installed: {s}", .{ entry.name, @errorName(err) });
            continue;
        };
        std.log.info("Mod {s} {d}.{d}.{d}: {d} blueprints, {d} scripts", .{ pkg.name(), pkg.version.major, pkg.version.minor, pkg.version.patch, pkg.blueprint_count, pkg.export_count });
    }
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
        .key_press => |key| if (self.sandbox.creator.open) self.creatorKey(key.key) else if (self.sandbox.trading != null and tradeKey(key.key) != null) self.sandbox.tradeKey(tradeKey(key.key).?) else switch (key.key) {
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
            .four => self.actions.select_tool = 4,
            .tab => self.actions.next_item = true,
            .t => self.actions.rotate = true,
            .p => self.actions.capture = true,
            .left_bracket => self.actions.channel_down = true,
            .right_bracket => self.actions.channel_up = true,
            .i => self.inspecting = !self.inspecting,
            .space => self.engine.input.jump_pressed = true,
            .left_control => self.engine.input.dodge = true,
            .x => self.engine.input.stomp = true,
            .g => self.engine.input.grapple = true,
            .b => self.engine.input.cycle_mode = true,
            .f6 => self.toggleGuest(),
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
    self.pollPads();
    if (options.smoke_frames > 0 and options.benchmark_frames == 0) {
        self.exerciseSmoke();
        // The last smoke stage drives the rover at full throttle.
        if (self.sandbox.seated != null) self.engine.input.forward = 1;
    }
    if (options.showcase > 0) self.showcase();
    const steps = self.engine.advance(self.timer.lap());
    for (0..steps) |_| {
        self.routePads();
        self.sandbox.step(&self.engine.camera, self.engine.input, self.actions, Time.fixed_dt) catch |err| self.report("ERROR {s}", .{@errorName(err)});
        self.actions = .{};
        self.engine.input.clearEdges();
        self.pads.consume();
    }
    if (self.sandbox.exported) |index| {
        self.sandbox.exported = null;
        self.exportPrefab(index);
    }
}

/// Joins and leaves happen once per frame; the Menu edge is cleared here so a frame without a
/// fixed step cannot toggle twice.
fn pollPads(self: *App) void {
    self.pads.poll();
    for (&self.pads.commands, 0..) |*cmd, c| {
        const p = Gamepads.playerIndex(c);
        if (p == 0) {
            self.engine.input.merge(cmd.input);
            continue;
        }
        const g = p - 1;
        if (cmd.join) {
            if (self.sandbox.guests[g].active) self.sandbox.leaveGuest(g) else self.sandbox.joinGuest(g);
            self.pad_guests[g] = self.sandbox.guests[g].active;
            self.report("P{d} {s}", .{ p + 1, if (self.pad_guests[g]) "JOINED" else "LEFT" });
        } else if (!cmd.connected and self.pad_guests[g]) {
            self.sandbox.leaveGuest(g);
            self.pad_guests[g] = false;
            self.report("P{d} CONTROLLER DISCONNECTED", .{p + 1});
        }
        if (cmd.respawn and self.sandbox.guests[g].active) self.sandbox.respawnGuest(g);
        cmd.join = false;
        cmd.respawn = false;
    }
}

/// Hands each pad's latest command to its player for the coming fixed step.
fn routePads(self: *App) void {
    for (self.pads.commands, 0..) |cmd, c| {
        const p = Gamepads.playerIndex(c);
        if (p == 0) {
            if (!cmd.connected) continue;
            if (self.sandbox.trading != null) {
                // A pad driving P1 at a stall: D-pad chooses, X trades, B closes.
                if (cmd.up) self.sandbox.tradeKey(.up);
                if (cmd.down) self.sandbox.tradeKey(.down);
                if (cmd.interact) self.sandbox.tradeKey(.confirm);
                if (cmd.input.dodge) self.sandbox.tradeKey(.close);
                continue;
            }
            self.engine.camera.turn(cmd.input.look_x, cmd.input.look_y, Time.fixed_dt);
            self.actions.interact = self.actions.interact or cmd.interact;
            self.actions.toggle_view = self.actions.toggle_view or cmd.view;
            continue;
        }
        if (!self.pad_guests[p - 1]) continue;
        const g = &self.sandbox.guests[p - 1];
        g.input = cmd.input;
        g.interact = g.interact or cmd.interact;
        g.toggle_view = g.toggle_view or cmd.view;
        g.trade_up = g.trade_up or cmd.up;
        g.trade_down = g.trade_down or cmd.down;
    }
}

/// F6: add the next free guest (idle unless a controller drives it), or remove the last.
fn toggleGuest(self: *App) void {
    for (self.sandbox.guests, 0..) |g, i| if (!g.active) {
        self.sandbox.joinGuest(i);
        return self.report("P{d} JOINED  CONNECT A CONTROLLER TO PLAY", .{i + 2});
    };
    var i: usize = self.sandbox.guests.len;
    while (i > 0) : (i -= 1) if (!self.pad_guests[i - 1]) {
        self.sandbox.leaveGuest(i - 1);
        return self.report("P{d} LEFT", .{i + 1});
    };
}

/// `-Dshowcase=N`: a fixed viewpoint on the city for screenshots and art review.
fn showcase(self: *App) void {
    const District = @import("procedural/District.zig");
    const layout = &self.sandbox.catalog.district;
    const camera = &self.engine.camera;
    self.sandbox.player.mode = .fly;
    self.show_metrics = false;
    self.engine.input = .{};
    const v = options.showcase;
    var target: [3]f32 = undefined;
    var eye: [3]f32 = undefined;
    if ((v >= 1 and v <= 6) or (v >= 10 and v <= 15)) {
        const s = District.span(layout, layout.edges[if (v >= 10) v - 10 else v - 1]);
        const d = @import("physics/Rotation.zig").sub(s.b, s.a);
        const side = @import("physics/Rotation.zig").normalize(.{ d[2], 0, -d[0] });
        target = s.point(0.5);
        const back = s.horizontal() * 0.62;
        eye = .{ target[0] + side[0] * back, target[1] + 18, target[2] + side[2] * back };
        // Look from the other side if a tower stands where the camera would be.
        for (layout.buildings[0..layout.building_count]) |b| if (@abs(eye[0] - b.base[0]) < b.half[0] + 4 and @abs(eye[2] - b.base[2]) < b.half[1] + 4) {
            eye = .{ target[0] - side[0] * back, target[1] + 18, target[2] - side[2] * back };
        };
    } else if (v == 9) {
        const s = District.span(layout, layout.edges[0]);
        target = s.point(0.6);
        eye = s.point(0.1);
        eye[1] += 2;
        target[1] += 2;
    } else {
        target = .{ -40, layout.nodes[0].position[1], 140 };
        eye = .{ 260, target[1] + 160, -420 };
    }
    // 8 is a dusk overview; 10–15 revisit roads 1–6 at dusk.
    const dusk = v == 8 or v >= 10;
    self.sandbox.tick = if (dusk) @import("engine/Sky.zig").day_ticks * 52 / 100 else @import("engine/Sky.zig").day_ticks * 15 / 100;
    camera.position = mach.math.vec3(eye[0], eye[1], eye[2]);
    const dx = target[0] - eye[0];
    const dz = target[2] - eye[2];
    camera.yaw = std.math.atan2(dx, dz);
    camera.pitch = std.math.atan2(target[1] - eye[1], @sqrt(dx * dx + dz * dz));
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
    const stage = @min(9, self.rendered_frames_seen * 10 / options.smoke_frames);
    if (stage == self.smoke_stage) return;
    self.smoke_stage = stage;
    const camera = &self.engine.camera;
    switch (stage) {
        1 => {
            for (self.sandbox.shrines, 0..) |shrine, k| std.log.info("Smoke shrine {d}: {d} rooms at {d:.0} {d:.0}, verified plan of {d} actions after {d} candidates", .{ k, shrine.generated.puzzle.rooms, shrine.origin[0], shrine.origin[2], shrine.generated.plan.len, shrine.generated.attempts });
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
            // Four-way split screen: three guests with their own inputs and third-person views.
            for (0..3) |i| self.sandbox.joinGuest(i);
            self.sandbox.guests[0].input = .{ .forward = 1 };
            self.sandbox.guests[1].input = .{ .look_x = 0.5 };
            self.sandbox.guests[2].view = .first;
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
        },
        5 => {
            if (self.sandbox.workshop) |w| std.log.info("Smoke lamp: lit={d:.0}", .{self.sandbox.machines[w].machine.outputs[3][2]});
            if (self.smoke_rover_start == null) self.smoke_rover_start = self.sandbox.physics.rigidPose(self.sandbox.machines[2].vehicle.?.rigid).?.position;
            // Press the door button, then take the rover for the rest of the run.
            self.sandbox.press = self.sandbox.findDevice(0, "button");
            self.sandbox.enterVehicle(2, camera);
        },
        6 => {
            if (self.sandbox.seated != null) self.sandbox.exitVehicle(camera);
            self.sandbox.player.setMode(.fly, camera.*);
            self.sandbox.view = .first;
            self.smokeSap();
            const origin = self.sandbox.treeOrigin(1);
            camera.position = mach.math.vec3(origin[0], origin[1] + 80, origin[2] - 220);
            camera.yaw = 0;
            camera.pitch = 0.5;
            self.show_metrics = true;
        },
        7 => {
            // Two guests leave: the remaining pair splits top and bottom.
            self.sandbox.leaveGuest(1);
            self.sandbox.leaveGuest(2);
            const flow = self.sandbox.sap_stats[1];
            std.log.info("Smoke sap: tree 1 demand={d:.0} W supply={d:.0} W satisfaction={d:.0}%", .{ flow.demand, flow.supplied, flow.satisfaction * 100 });
            const origin = self.sandbox.treeOrigin(2);
            camera.position = mach.math.vec3(origin[0], origin[1] + 100, origin[2] - 1000);
            camera.yaw = 0;
            camera.pitch = 0.12;
        },
        8 => {
            const nodes = self.sandbox.catalog.district.nodes;
            Build.selectTool(&self.sandbox, .bridge);
            self.sandbox.tools.bridge_from = 0;
            camera.position = mach.math.vec3(nodes[0].position[0], nodes[0].position[1] + 20, nodes[0].position[2]);
            const point = @import("game/BridgeTool.zig").anchor(nodes[3]);
            const dx = point[0] - camera.position.x();
            const dz = point[2] - camera.position.z();
            camera.yaw = std.math.atan2(dx, dz);
            camera.pitch = std.math.atan2(point[1] - camera.position.y(), @sqrt(dx * dx + dz * dz));
        },
        9 => {
            std.log.info("Smoke co-op: P2 at {d:.1} {d:.1} {d:.1}, motion {s}", .{ self.sandbox.guests[0].player.feet[0], self.sandbox.guests[0].player.feet[1], self.sandbox.guests[0].player.feet[2], @tagName(self.sandbox.guests[0].player.motion) });
            self.sandbox.leaveGuest(0);
            _ = self.sandbox.addBridge(.{ .a = 0, .b = 3 }) catch |err| return self.report("SMOKE BRIDGE {s}", .{@errorName(err)});
            const bytes = self.sandbox.save(self.allocator, camera.*) catch |err| return self.report("SMOKE CITY SAVE {s}", .{@errorName(err)});
            defer self.allocator.free(bytes);
            self.sandbox.restore(self.allocator, bytes, camera) catch |err| return self.report("SMOKE CITY LOAD {s}", .{@errorName(err)});
            var trips: u32 = 0;
            for (self.sandbox.life.cars) |slot| if (slot) |car| {
                trips += car.trips;
            };
            std.log.info("Smoke traffic: {d} cars, {d} pedestrians, {d} trips, {d} recoveries, {d} deadlocks broken", .{ self.sandbox.life.rigidCount(), Life.walker_count, trips, self.sandbox.life.resets, self.sandbox.life.deadlocks });
            std.log.info("Smoke market: day {d}, stall stock {any}, salvaged parts {d}", .{ self.sandbox.market.day, self.sandbox.market.stalls[0].stock, self.sandbox.wallet.parts });
            std.log.info("Smoke city: six plazas, bridge {d} > {d} restored with collision; save {d} bytes", .{ self.sandbox.bridges[0].?.edge.a, self.sandbox.bridges[0].?.edge.b, bytes.len });
        },
        else => {},
    }
    std.log.info("Smoke stage {d}: culling={any}, hud={any}, mode={s}, players={d}", .{ stage, self.culling, self.show_metrics, @tagName(self.sandbox.player.mode), 1 + self.sandbox.guestCount() });
}

fn smokeSap(self: *App) void {
    const sb = &self.sandbox;
    const origin = sb.treeOrigin(1);
    const radius = sb.tree(1).genome.base_radius;
    for ([_]f32{ -3, 3 }) |z| {
        const point: [3]f32 = .{ origin[0] + radius + 2, origin[1], origin[2] + z };
        _ = sb.spawnMachine(null, sb.catalog.content.sap_beacon.*, point, 0, false) catch |err| return self.report("SMOKE SAP {s}", .{@errorName(err)});
    }
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

/// Installs finished background builds into the catalog. Runs inside the render mutex, so the
/// render thread never sees a catalog entry change mid-frame.
/// Writes `zig-out/stress.hwpk`: N meshes from 1K to 128K vertices (log-spaced), and reserves a
/// catalog handle for each.
fn writeStressPack(self: *App, catalog: *@import("asset/Catalog.zig")) !void {
    const Mesh = @import("render/Mesh.zig");
    const Model = @import("asset/Model.zig");
    const Pack = @import("asset/Pack.zig");
    const n: usize = @min(options.pack_stress, self.stress_tickets.len);
    var inputs: [64]Pack.Input = undefined;
    var blobs: [64][]u8 = undefined;
    defer for (blobs[0..n]) |b| self.allocator.free(b);
    for (0..n) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(n - 1, 1)));
        const vertices: usize = @intFromFloat(1024 * std.math.pow(f32, 128, t));
        const verts = try self.allocator.alloc(Mesh.Vertex, vertices);
        const indices = try self.allocator.alloc(u32, vertices / 3 * 3);
        for (verts, 0..) |*v, k| v.* = .{ .position = .{ @floatFromInt(k % 256), @floatFromInt(k / 256), @floatFromInt(i) }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 0 } };
        for (indices, 0..) |*x, k| x.* = @intCast(k);
        const model = try Model.fromMesh(self.allocator, .{ .vertices = verts, .indices = indices }, .named("stress", .{ 1, 1, 1, 1 }));
        defer model.deinit(self.allocator);
        blobs[i] = try model.encode(self.allocator);
        inputs[i] = .{ .guid = @import("asset/Guid.zig").derived(std.fmt.allocPrint(self.allocator, "stress:{d}", .{i}) catch unreachable), .kind = .model, .data = blobs[i] };
        self.stress_handles[i] = try catalog.reserve();
    }
    const bytes = try Pack.write(self.allocator, inputs[0..n]);
    defer self.allocator.free(bytes);
    self.stress_bytes = bytes.len;
    std.Io.Dir.cwd().createDirPath(self.io, "zig-out") catch {};
    try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = "zig-out/stress.hwpk", .data = bytes });
    self.stress_pack = try self.loader.?.openPack(std.Io.Dir.cwd(), "zig-out/stress.hwpk");
    std.log.info("Pack stress: {d} meshes, {d} MiB written to zig-out/stress.hwpk", .{ n, bytes.len >> 20 });
}

fn pumpStressPack(self: *App, renderer: *Renderer) void {
    const pack = self.stress_pack orelse return;
    const loader = self.loader.?;
    const n: usize = @min(options.pack_stress, self.stress_tickets.len);
    if (!self.stress_requested and renderer.frames >= @import("engine/Flythrough.zig").warmup_frames) {
        self.stress_requested = true;
        renderer.pack_requested_frame = @intCast(renderer.frames);
        for (0..n) |i| {
            var name: [32]u8 = undefined;
            const guid = @import("asset/Guid.zig").derived(std.fmt.bufPrint(&name, "stress:{d}", .{i}) catch unreachable);
            self.stress_tickets[i] = loader.request(.{ .pack = .{ .pack = pack, .guid = guid } }, 1) catch null;
        }
    }
    for (&self.stress_tickets, 0..) |*slot, i| {
        const ticket = slot.* orelse continue;
        if (loader.take(ticket)) |model| {
            if (self.catalog.install(self.allocator, self.stress_handles[i], model)) {
                self.stress_installed += 1;
            } else |err| std.log.err("stress install: {s}", .{@errorName(err)});
        } else if (loader.failure(ticket)) |err| {
            std.log.err("stress load: {s}", .{@errorName(err)});
        } else continue;
        loader.release(ticket);
        slot.* = null;
    }
    renderer.pack_installed = self.stress_installed;
    renderer.pack_bytes = self.stress_bytes;
    if (self.stress_installed == n and renderer.pack_ready_frame < 0) renderer.pack_ready_frame = @intCast(renderer.frames);
}

fn installDeferred(self: *App) void {
    const loader = self.loader orelse return;
    var remaining: usize = 0;
    for (&self.deferred, self.deferred_handles) |*slot, handle| {
        const ticket = slot.* orelse continue;
        if (loader.take(ticket)) |model| {
            self.catalog.install(self.allocator, handle, model) catch |err| std.log.err("asset install: {s}", .{@errorName(err)});
        } else if (loader.failure(ticket)) |err| {
            std.log.err("asset build failed: {s}", .{@errorName(err)});
        } else {
            remaining += 1;
            continue;
        }
        loader.release(ticket);
        slot.* = null;
        if (remaining == 0 and for (self.deferred) |d| {
            if (d != null) break false;
        } else true) std.log.info("Deferred meshes ready {d:.0} ms after start (worst build {d:.0} ms)", .{ @as(f64, @floatFromInt(self.started.untilNow(self.io, .awake).nanoseconds)) / 1e6, loader.stats.worst_job_ms });
    }
}

pub fn publish(self: *App, renderer: *Renderer) void {
    self.installDeferred();
    self.pumpStressPack(renderer);
    self.rendered_frames_seen = renderer.frames;
    renderer.views[0].camera = self.engine.camera;
    renderer.tick = self.engine.time.tick;
    renderer.time_of_day = Sky.timeOfDay(self.sandbox.tick);
    renderer.show_metrics = self.show_metrics;
    renderer.culling = self.culling;
    renderer.prop_count = self.sandbox.publishProps(&renderer.props);
    // The removal set is large; copy it only when it changed.
    if (self.published_revision != self.sandbox.modifications.revision) {
        renderer.modifications = self.sandbox.modifications;
        self.published_revision = self.sandbox.modifications.revision;
    }
    const sandbox = &self.sandbox;
    renderer.views[0].crosshair = sandbox.seated == null and !sandbox.creator.open and (self.captured or sandbox.player.mode == .walk);
    renderer.views[0].hide_owner = if (sandbox.bodyShown()) 0 else 1;
    renderer.view_count = 1;
    for (&sandbox.guests, 0..) |*g, i| if (g.active) {
        const view = &renderer.views[renderer.view_count];
        view.* = .{ .camera = g.camera, .hide_owner = if (g.view == .first) @intCast(i + 2) else 0, .crosshair = true, .accent = Profile.accent_colors[g.profile.accent] };
        view.lines[0].set("{s}  {s}  {s}  FUEL {d:.0}", .{ g.profile.name(), @tagName(g.player.motion), @tagName(g.player.traversal), g.player.fuel });
        if (g.trading) |stall| {
            // The party shares P1's wallet; one row at a time fits a split view.
            view.lines[0].set("{s}  MARKET {d}  SCRAP {d}  PARTS {d}  DPAD CHOOSE  X TRADE  B CLOSE", .{ g.profile.name(), Market.stall_plazas[stall], sandbox.wallet.scrap, sandbox.wallet.parts });
            var row: Build.PanelLine = .{};
            sandbox.tradeRow(stall, g.trade_row, true, &row);
            view.lines[1].set("{s}", .{row.slice()});
        } else if (g.target == .stall) {
            view.lines[1].set("MARKET STALL {d}  X TRADE", .{Market.stall_plazas[g.target.stall]});
        } else if (g.target == .device) {
            const def = sandbox.machines[g.target.device.machine].blueprint.device(g.target.device.device);
            if (def.kind == .button) view.lines[1].set("{s} BUTTON  X PRESS", .{def.name()});
        }
        renderer.view_count += 1;
    };
    const minutes: u32 = @intFromFloat(renderer.time_of_day * 24 * 60);
    const motion = if (sandbox.seated != null) "DRIVE" else if (sandbox.player.mode == .fly) "FLY" else @tagName(sandbox.player.motion);
    renderer.hud_lines[0].set("{d:0>2}:{d:0>2}  {s}  {s}  {s} FUEL {d:.0}  TOOL {s}  SCRAP {d}  PARTS {d}", .{ minutes / 60, minutes % 60, sandbox.profile.name(), motion, @tagName(sandbox.player.traversal), sandbox.player.fuel, @tagName(sandbox.tools.tool), sandbox.wallet.scrap, sandbox.wallet.parts });
    if (sandbox.seated) |m| {
        const placed = &sandbox.machines[m];
        const motor = placed.machine.blueprint.vehicle.?.motor;
        renderer.hud_lines[1].set("{d:.1} M/S  POWER {d:.0}%  WASD DRIVE  SPACE BRAKE  CLICK EXIT", .{ placed.vehicle.?.forwardSpeed(&sandbox.physics), placed.machine.satisfaction(motor) * 100 });
    } else if (sandbox.held) |i| {
        renderer.hud_lines[1].set("HOLDING CRATE {d}  CLICK DROP", .{i});
    } else switch (sandbox.target) {
        .prop => |i| renderer.hud_lines[1].set("CRATE {d}  CLICK GRAB", .{i}),
        .relic => |r| renderer.hud_lines[1].set("RELIC {d}:{d}:{d}  RMB SALVAGE", .{ r.ref.x, r.ref.z, r.ref.id }),
        .bridge => |i| renderer.hud_lines[1].set("YOUR BRIDGE {d}  TOOL 4 + RMB REMOVE", .{i}),
        .stall => |i| renderer.hud_lines[1].set("MARKET STALL {d}  CLICK TRADE", .{Market.stall_plazas[i]}),
        .structure => |m| renderer.hud_lines[1].set("{s} STRUCTURE", .{sandbox.machines[m].blueprint.name()}),
        .device => |ref| {
            const machine = &sandbox.machines[ref.machine].machine;
            const def = machine.blueprint.device(ref.device);
            const shrine = sandbox.machines[ref.machine].shrine;
            switch (def.kind) {
                .button => if (shrine != null and std.mem.eql(u8, def.name(), "reset"))
                    renderer.hud_lines[1].set("SHRINE {d} RESET  CLICK: CRATES AND LATCHES RETURN", .{shrine.?})
                else if (shrine != null and std.mem.eql(u8, def.name(), "vault"))
                    renderer.hud_lines[1].set("SEED VAULT  CLICK OPEN", .{})
                else
                    renderer.hud_lines[1].set("{s} BUTTON  CLICK PRESS", .{def.name()}),
                .script => renderer.hud_lines[1].set("{s} SCRIPT {s}  OUT {d:.2}{s}", .{ def.name(), def.scriptName(), machine.outputs[ref.device][4], if (sandbox.scripts.find(def.scriptName()) == null) "  MISSING" else "" }),
                .plate => renderer.hud_lines[1].set("WEIGHT PLATE {s}  {s}", .{ def.name(), if (machine.outputs[ref.device][0] > 0.5) "PRESSED" else "NEEDS A CRATE" }),
                .seat => renderer.hud_lines[1].set("{s}  CLICK ENTER", .{machine.blueprint.name()}),
                .transmitter, .receiver => renderer.hud_lines[1].set("{s} {s} CHANNEL {d}  [ ] CHANGE", .{ def.name(), @tagName(def.kind), def.channel }),
                .root_sender, .root_listener => if (machine.root_group[ref.device]) |g|
                    renderer.hud_lines[1].set("{s} ROOTSONG CHANNEL {d}  ROOT GROUP {d}  [ ] CHANGE", .{ def.name(), def.channel, g })
                else
                    renderer.hud_lines[1].set("{s} ROOTSONG UNROOTED  NEEDS WOOD WITHIN 4 M", .{def.name()}),
                .lamp => renderer.hud_lines[1].set("{s} LAMP {s}", .{ def.name(), if (machine.outputs[ref.device][2] > 0) "LIT" else "DARK" }),
                .sap_tap => {
                    if (sandbox.tap_links[ref.machine][ref.device]) |link| {
                        const stats = sandbox.sap_stats[link.tree];
                        renderer.hud_lines[1].set("TREE {d} SAP {d:.0}/{d:.0} W  FLOW {d:.0}%", .{ link.tree, stats.supplied, stats.demand, stats.satisfaction * 100 });
                    } else renderer.hud_lines[1].set("SAP TAP DETACHED  NEEDS WOOD WITHIN 4 M", .{});
                },
                .generator => renderer.hud_lines[1].set("GENERATOR {d:.0} W  LOAD {d:.0} W", .{ machine.outputs[ref.device][0], machine.network(ref.device).?.demand }),
                .actuator => renderer.hud_lines[1].set("{s} {d:.0}%  POWER {d:.0}%", .{ def.name(), machine.state[ref.device] * 100, machine.satisfaction(ref.device) * 100 }),
                else => renderer.hud_lines[1].set("{s}", .{def.name()}),
            }
        },
        .none => renderer.hud_lines[1] = .{},
    }
    renderer.panel_count = 0;
    if (sandbox.trading != null) {
        var lines: [Sandbox.trade_rows + 2]Build.PanelLine = undefined;
        const count = sandbox.tradeLines(&lines);
        for (lines[0..count], renderer.panel[0..count]) |*line, *out| out.set("{s}", .{line.slice()});
        renderer.panel_count = count;
    } else if (sandbox.creator.open) {
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
    if (self.loader) |l| l.destroy();
    defer self.sandbox.deinit();
    // The app thread has exited, so the sandbox can be read safely.
    if (self.smoke_rover_start) |origin| {
        const now = self.sandbox.physics.rigidPose(self.sandbox.machines[2].vehicle.?.rigid).?.position;
        const dx = now[0] - origin[0];
        const dz = now[2] - origin[2];
        std.log.info("Smoke drive: rover moved {d:.1} m", .{@sqrt(dx * dx + dz * dz)});
    }
}
