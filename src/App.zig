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
const HotReload = @import("asset/HotReload.zig");
const Registry = @import("asset/Registry.zig");
const Guid = @import("asset/Guid.zig");
const Loader = @import("asset/Loader.zig");
const Profile = @import("game/Profile.zig");
const Life = @import("city/Life.zig");
const Market = @import("city/Market.zig");
const Menu = @import("ui/Menu.zig");
const Canvas = @import("ui/Canvas.zig");
const Screens = @import("ui/Screens.zig");
const Settings = @import("game/Settings.zig");
const Dialogue = @import("game/Dialogue.zig");
const Audio = @import("audio/Audio.zig");
const FrameStats = @import("engine/FrameStats.zig");
const App = @This();
const R3 = @import("physics/Rotation.zig");

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
benchmark_sim: FrameStats = .{},
benchmark_substeps: Sandbox.BenchmarkMetrics = .{},
benchmark_tick: u64 = 0,
benchmark_ground_steps: u64 = 0,
benchmark_air_steps: u64 = 0,
benchmark_ground_fire_steps: u64 = 0,
benchmark_air_fire_steps: u64 = 0,
benchmark_ground_targets: u64 = 0,
benchmark_air_targets: u64 = 0,
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
reload: ?*HotReload = null,
reload_scan: std.Io.Timestamp = undefined,
reload_smoke_edited: ?std.Io.Timestamp = null,
reload_smoke_initial: bool = false,
reload_smoke_passed: bool = false,
reload_smoke_old: @import("asset/Catalog.zig").MeshHandle = .{},
deferred: [24]?Loader.Ticket = @splat(null),
deferred_handles: [24]@import("asset/Catalog.zig").MeshHandle = undefined,
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
core: *mach.Core = undefined,
/// Title, pause and settings menus (settings persist in `saves/settings.json`).
menu: Menu = .{},
/// A person is playing (no smoke, benchmark or showcase): the title opens and settings save.
interactive: bool = false,
/// Mouse position in canvas units, and the clickable areas of the last published GUI.
pointer: [2]f32 = .{ -1, -1 },
hits: [Canvas.hit_capacity]Canvas.Hit = undefined,
hit_len: usize = 0,
ui_height: f32 = 720,
window_height: f32 = 800,
seconds: f32 = 0,
/// The P1 pad's Menu button was pressed (opens or closes the pause menu).
pad_menu: bool = false,
/// Frames since a combat showcase was set up (its trigger rhythm).
showcase_frame: u32 = 0,
/// Where a combat showcase holds the player (saber lunges would carry them off).
showcase_feet: [3]f32 = @splat(0),
gui_showcase_ready: bool = false,
settings_dirty: bool = false,
/// Sound output; null when disabled (`-Daudio=false`), benchmarking, or without a device.
audio: ?*Audio = null,
/// The GUI control under the mouse last frame (hover sounds play on change).
hovered: ?u16 = null,
/// Mouse buttons held while captured: the weapon tool's primary and alternate triggers.
fire_held: bool = false,
alt_held: bool = false,

pub fn init(self: *App, core: *mach.Core, world: *World, app_mod: mach.Mod(App), renderer_mod: mach.Mod(Renderer), io: std.Io, allocator: std.mem.Allocator) !void {
    self.* = .{ .timer = mach.time.Timer.start(io), .allocator = allocator, .io = io, .core = core };
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
    // Caves and the mountain panorama: built in the background after the near content.
    for (world.catalog.landscape[0..world.catalog.landscape_count], world.catalog.pending_count..) |p, i| {
        self.deferred[i] = try self.loader.?.request(.{ .generate = p.generator }, 1);
        self.deferred_handles[i] = p.handle;
    }
    if (options.pack_stress > 0) try self.writeStressPack(&world.catalog);
    if (options.hot_reload or options.reload_smoke) try self.setupReload();
    self.sandbox.enableLife();
    if (options.benchmark_frontier) {
        // Keep all local-player rigs, cameras, simulation, and combat active in the benchmark.
        for (0..3) |i| self.sandbox.joinGuest(i);
        self.setupFrontierBenchmark();
    }
    self.importPrefabs();
    self.loadMods();
    if (options.character_showcase > 0) {
        self.sandbox.profile.presentation = if (options.character_showcase == 4) .feminine else .masculine;
        self.sandbox.profile.armor = switch (options.character_showcase) {
            2 => .sentinel,
            3, 4, 5 => .none,
            else => .scout,
        };
        self.sandbox.profile.helmet = if (options.character_showcase == 2) .sealed else .open;
        self.sandbox.profile.outfit = 2;
        if (options.character_showcase == 5) {
            self.sandbox.profile.class = .synthetic;
            self.sandbox.profile.presentation = .feminine;
            self.sandbox.profile.clothing = .undersuit;
            self.sandbox.profile.accent = 0;
        }
        self.sandbox.creator.begin(self.sandbox.profile);
        self.sandbox.player.mode = .walk;
    }
    // A person playing starts at the title screen (not in unattended smoke, benchmark, or
    // showcase runs); "new game" then opens the character creator.
    self.interactive = options.smoke_frames == 0 and options.benchmark_frames == 0 and options.showcase == 0 and options.character_showcase == 0;
    if (options.audio and (options.benchmark_frames == 0 or options.benchmark_frontier)) {
        self.audio = Audio.create(allocator, io, options.benchmark_frontier) catch |err| blk: {
            std.log.warn("Audio unavailable ({s}); running silent", .{@errorName(err)});
            break :blk null;
        };
    }
    if (self.interactive) {
        self.menu.settings = Settings.load(io, allocator);
        self.show_metrics = self.menu.settings.metrics;
        self.menu.has_save = self.saveExists();
        self.menu.open(.title);
    }
    if (self.audio) |a| a.setVolumes(self.menu.settings);
}

fn uiSound(self: *App, event: Audio.Director.Ui) void {
    if (self.audio) |a| Audio.Director.ui(a, event);
}

fn setupFrontierBenchmark(self: *App) void {
    const sb = &self.sandbox;
    const Combat = @import("game/Combat.zig");
    sb.progress.fighter = true;
    sb.progress.weapons = (@as(u16, 1) << @intFromEnum(Combat.WeaponKind.blaster)) |
        (@as(u16, 1) << @intFromEnum(Combat.WeaponKind.machine_gun));
    @import("game/Frontier.zig").refresh(sb);
    const carrier = sb.skies.carriers[0].position();
    sb.enemies.nests[0].position = .{ carrier[0], @import("procedural/Terrain.zig").surface(sb.seed, carrier[0], carrier[2]).height, carrier[2] };
    sb.combat.arsenals[0].active = .machine_gun;
    sb.tools.tool = .weapon;
    sb.player.mode = .walk;
    sb.view = .first;
}

/// Alternates a stationary ranger fight at a seeded nest with a scripted Kestrel attack run.
/// Each section drives the production Sandbox step, enemy AI, weapons, aircraft and audio cues.
fn driveFrontierBenchmark(self: *App) void {
    const period: u64 = 360;
    const section: u64 = 180;
    const cycle = self.benchmark_tick % period;
    if (cycle == 0) self.setupFrontierGround();
    if (cycle == section) self.setupFrontierAir();

    self.engine.input = .{};
    const warmup: u64 = if (options.benchmark_frontier) @import("engine/Flythrough.zig").frontier_warmup_frames else @import("engine/Flythrough.zig").warmup_frames;
    const measuring = self.rendered_frames_seen >= warmup and self.rendered_frames_seen < warmup + options.benchmark_frames;
    if (cycle < section) {
        const fire = cycle % 36 < 26;
        self.sandbox.trigger = .{ .fire = fire };
        if (measuring) {
            self.benchmark_ground_steps += 1;
            self.benchmark_ground_fire_steps += @intFromBool(fire);
        }
    } else {
        const phase_tick = cycle - section;
        self.engine.input.forward = 1;
        self.engine.input.fast = false;
        self.engine.input.jump = phase_tick < 24;
        const fire = phase_tick % 40 < 32;
        const alt = phase_tick % 120 < 75;
        self.sandbox.trigger = .{ .fire = fire, .alt = alt };
        if (measuring) {
            self.benchmark_air_steps += 1;
            self.benchmark_air_fire_steps += @intFromBool(fire);
        }
    }
    self.benchmark_tick += 1;
}

fn setupFrontierGround(self: *App) void {
    const sb = &self.sandbox;
    if (sb.hangar.piloting) @import("game/Frontier.zig").leaveJet(sb, &self.engine.camera);
    const nest = sb.enemies.nests[0].position;
    const toward: [3]f32 = @import("physics/Rotation.zig").normalize(.{ nest[0] - Sandbox.spawn[0], 0, nest[2] - Sandbox.spawn[2] });
    const x = nest[0] - toward[0] * 38;
    const z = nest[2] - toward[2] * 38;
    const y = @import("procedural/Terrain.zig").surface(sb.seed, x, z).height;
    sb.player.mode = .walk;
    sb.player.feet = .{ x, y, z };
    sb.player.velocity = .{ 0, 0, 0 };
    sb.body_yaw = std.math.atan2(toward[0], toward[2]);
    self.engine.camera.yaw = sb.body_yaw;
    self.engine.camera.pitch = -0.015;
    self.engine.camera.position = mach.math.vec3(x, y + 1.6, z);
    sb.view = .first;
    sb.combat.arsenals[0].active = .machine_gun;
    sb.enemies.units = @splat(null);
    for (0..6) |i| {
        const side = (@as(f32, @floatFromInt(i % 3)) - 1) * 3.5;
        const distance: f32 = 15 + @as(f32, @floatFromInt(i / 3)) * 5;
        const px = x + toward[0] * distance - toward[2] * side;
        const pz = z + toward[2] * distance + toward[0] * side;
        const py = @import("procedural/Terrain.zig").surface(sb.seed, px, pz).height;
        sb.enemies.units[i] = .{
            .kind = if (i < 3) .trooper else .drone,
            .nest = 0,
            .position = .{ px, py + (if (i < 3) @as(f32, 0) else 8), pz },
            .health = if (i < 3) 220 else 120,
            .state = .hunt,
            .target = 0,
            .cooldown = 0.2,
            .orbit = @as(f32, @floatFromInt(i)) * 1.2,
        };
    }
    self.benchmark_ground_targets += 6;
}

fn setupFrontierAir(self: *App) void {
    const sb = &self.sandbox;
    const carrier = sb.skies.carriers[0].position();
    const nest = sb.enemies.nests[0].position;
    const forward = @import("physics/Rotation.zig").normalize(R3.sub(carrier, nest));
    const entry = R3.add(nest, .{ -forward[0] * 34, 55, -forward[2] * 34 });
    const yaw = std.math.atan2(forward[0], forward[2]);
    sb.hangar.place(sb.seed, Sandbox.spawn, .{ entry[0], entry[1], entry[2] }, yaw);
    const fighter = &sb.hangar.fighter.?;
    fighter.body.vel = @import("character/math.zig").Vec3.init(forward[0] * 38, forward[1] * 38, forward[2] * 38);
    fighter.throttle = 0.45;
    fighter.grounded = false;
    sb.hangar.board(&self.engine.camera);
    self.engine.camera.yaw = yaw;
    self.engine.camera.pitch = std.math.asin(std.math.clamp(forward[1], -1, 1));
    const right: [3]f32 = .{ forward[2], 0, -forward[0] };
    for (0..5) |i| {
        const distance: f32 = 28 + @as(f32, @floatFromInt(i % 3)) * 18;
        const lateral = (@as(f32, @floatFromInt(i)) - 2) * 13;
        const at = R3.add(entry, .{ forward[0] * distance + right[0] * lateral, 8 + @as(f32, @floatFromInt(i % 2)) * 10, forward[2] * distance + right[2] * lateral });
        sb.skies.wasps[i] = .{ .position = at, .forward = forward, .carrier = 0, .health = 95, .state = .attack };
    }
    self.benchmark_air_targets += 5;
}

fn reportFrontierBenchmark(self: *App) void {
    const sim = self.benchmark_sim.summary();
    std.log.info("APPBENCH {{\"sim_steps\":{d},\"sim_p50_ms\":{d:.3},\"sim_p95_ms\":{d:.3},\"sim_p99_ms\":{d:.3},\"ground_steps\":{d},\"ground_fire_steps\":{d},\"ground_targets_spawned\":{d},\"air_steps\":{d},\"air_fire_steps\":{d},\"air_targets_spawned\":{d},\"audio_device\":{s}}}", .{
        self.benchmark_sim.total,
        sim.p50,
        sim.p95,
        sim.p99,
        self.benchmark_ground_steps,
        self.benchmark_ground_fire_steps,
        self.benchmark_ground_targets,
        self.benchmark_air_steps,
        self.benchmark_air_fire_steps,
        self.benchmark_air_targets,
        if (self.audio != null) "true" else "false",
    });
    inline for (@typeInfo(Sandbox.BenchmarkStage).@"enum".fields) |field| {
        const stage: Sandbox.BenchmarkStage = @enumFromInt(field.value);
        const sample = self.benchmark_substeps.stages[field.value];
        const mean = if (sample.total == 0) 0 else sample.sum_ms / @as(f64, @floatFromInt(sample.total));
        std.log.info("SIMSTAGE {{\"stage\":\"{s}\",\"samples\":{d},\"mean_ms\":{d:.3},\"max_ms\":{d:.3}}}", .{ @tagName(stage), sample.total, mean, sample.worst_ms });
    }
}

fn saveExists(self: *App) bool {
    std.Io.Dir.cwd().access(self.io, Save.default_path, .{}) catch return false;
    return true;
}

/// Any GUI that takes the keyboard and frees the mouse is open.
fn uiActive(self: *const App) bool {
    const sb = &self.sandbox;
    return self.menu.screen != .none or sb.creator.open or sb.talk != null or sb.shop != null or sb.trading != null;
}

/// Arrow keys, WASD, Enter/Space/E and Escape navigate every GUI.
/// Arrows, Enter and Escape always navigate; so do the bound move keys and the jump key.
fn navKey(self: *const App, key: mach.Core.KeyButtonID) ?Menu.Key {
    switch (key) {
        .up => return .up,
        .down => return .down,
        .left => return .left,
        .right => return .right,
        .enter, .kp_enter => return .confirm,
        .escape => return .back,
        else => {},
    }
    const action = self.menu.settings.bindings.action(key) orelse return null;
    return switch (action) {
        .forward => .up,
        .back => .down,
        .left => .left,
        .right => .right,
        .jump => .confirm,
        else => null,
    };
}

/// Routes one navigation key to whichever GUI is open (menus first, then panels).
fn uiNav(self: *App, k: Menu.Key) void {
    self.uiSound(switch (k) {
        .confirm => .confirm,
        .back => .back,
        else => .move,
    });
    if (self.menu.screen != .none) return self.menuKey(k);
    const sb = &self.sandbox;
    if (sb.creator.open) return self.creatorInput(switch (k) {
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
        .confirm => .enter,
        .back => .escape,
    });
    if (sb.talk != null) return sb.talkKey(switch (k) {
        .up => .up,
        .down => .down,
        .confirm => .confirm,
        .back => .back,
        else => return,
    });
    if (sb.shop != null) return sb.shopKey(switch (k) {
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
        .confirm => .confirm,
        .back => .close,
    });
    if (sb.trading != null) return sb.tradeKey(switch (k) {
        .up => .up,
        .down => .down,
        .confirm => .confirm,
        .back => .close,
        else => return,
    });
}

fn menuKey(self: *App, k: Menu.Key) void {
    self.runCommand(self.menu.key(k));
}

fn runCommand(self: *App, command: Menu.Command) void {
    switch (command) {
        .none => {},
        .@"resume" => {
            self.menu.open(.none);
            self.capture(self.core, true);
        },
        .new_game => self.newGame(),
        .continue_game, .load => if (self.quickload()) self.menu.open(.none),
        .save => {
            self.quicksave();
            self.menu.has_save = self.saveExists();
        },
        .character => {
            self.menu.open(.none);
            if (self.sandbox.seated != null) return self.report("LEAVE THE VEHICLE TO CUSTOMIZE", .{});
            self.actions.open_creator = true;
        },
        .quit => self.core.exit(),
        .settings_changed => {
            self.show_metrics = self.menu.settings.metrics;
            self.settings_dirty = true;
            if (self.audio) |a| a.setVolumes(self.menu.settings);
        },
    }
    // Settings are written once on leaving their screen, not on every (repeating) press.
    if (self.settings_dirty and self.menu.screen != .settings) {
        self.settings_dirty = false;
        if (self.interactive) self.menu.settings.store(self.io, self.allocator) catch |err| self.report("SETTINGS NOT SAVED {s}", .{@errorName(err)});
    }
}

/// From the title: a fresh ranger at the spawn point, starting in the creator.
fn newGame(self: *App) void {
    self.menu.open(.none);
    self.sandbox.player.mode = .walk;
    self.sandbox.resetPlayer(&self.engine.camera);
    self.sandbox.view = if (self.menu.settings.third_person) .third else .first;
    self.sandbox.creator.begin(self.sandbox.profile);
}

/// Title backdrop: a slow orbit over the city.
fn titleCamera(self: *App) void {
    const layout = &self.sandbox.catalog.district;
    const center = layout.nodes[0].position;
    const angle = self.seconds * 0.025 + 2.2;
    const camera = &self.engine.camera;
    self.sandbox.player.mode = .fly;
    camera.position = mach.math.vec3(center[0] + @sin(angle) * 300, center[1] + 110, center[2] + @cos(angle) * 300);
    const dx = center[0] + 60 - camera.position.x();
    const dz = center[2] + 120 - camera.position.z();
    camera.yaw = std.math.atan2(dx, dz);
    camera.pitch = std.math.atan2(center[1] + 20 - camera.position.y(), @sqrt(dx * dx + dz * dz));
}

/// Mouse over the GUI: hovering selects, clicking also activates.
fn pointAt(self: *App, click: bool) void {
    var id: ?u16 = null;
    var i = self.hit_len;
    while (i > 0) {
        i -= 1;
        if (self.hits[i].rect.contains(self.pointer[0], self.pointer[1])) {
            id = self.hits[i].id;
            break;
        }
    }
    if (id != self.hovered and id != null and !click) self.uiSound(.move);
    self.hovered = id;
    const hit = id orelse return;
    if (click) self.uiSound(.confirm);
    const row = Screens.hitRow(hit);
    const sb = &self.sandbox;
    // Only the top layer takes the mouse: a menu over a panel blocks the panel beneath.
    const menu_area = switch (Screens.hitArea(hit)) {
        .menu, .setting_left, .setting_right => true,
        else => false,
    };
    if (menu_area != (self.menu.screen != .none)) return;
    switch (Screens.hitArea(hit)) {
        .menu => {
            self.menu.select(row);
            if (click and self.menu.row == row) self.menuKey(.confirm);
        },
        .setting_left, .setting_right => {
            self.menu.select(row);
            if (click) self.menuKey(if (Screens.hitArea(hit) == .setting_left) .left else .right);
        },
        .creator_field => if (click and sb.creator.open) {
            sb.creator.field = @enumFromInt(row);
        },
        .creator_left, .creator_right => if (click and sb.creator.open) {
            sb.creator.field = @enumFromInt(row);
            sb.creator.adjust(if (Screens.hitArea(hit) == .creator_left) -1 else 1);
        },
        .creator_done => if (click) self.creatorInput(.enter),
        .fab_tab => if (sb.shop) |*shop| if (click) {
            shop.tab = row;
            shop.row = 0;
        },
        .trade_row => if (sb.trading != null) {
            sb.trade_row = row;
            if (click) sb.tradeKey(.confirm);
        },
        .trade_close => if (click) sb.tradeKey(.close),
        .shop_row => if (sb.shop) |*shop| {
            shop.row = row;
            if (click) sb.shopKey(.confirm);
        },
        .shop_close => if (click) sb.shopKey(.close),
        .choice => if (sb.talk) |*talk| {
            talk.choice = row;
            if (click) sb.talkKey(.confirm);
        },
        .talk_continue => if (click) sb.talkKey(.confirm),
    }
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
    self.creatorInput(k);
}

fn creatorInput(self: *App, k: Creator.Key) void {
    switch (k) {
        .up, .down, .left, .right => self.uiSound(.move),
        .enter => self.uiSound(.confirm),
        .escape => self.uiSound(.back),
        else => {},
    }
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
        if (self.reload != null and !options.reload_smoke) self.watchMod(&pkg, entry.name) catch |err| std.log.warn("mod watch {s}: {s}", .{ entry.name, @errorName(err) });
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
        .key_repeat => |key| if (self.uiActive()) {
            // Held arrows scroll lists; held backspace erases the name.
            if (self.sandbox.creator.open and self.menu.screen == .none) {
                if (key.key == .backspace or key.key == .left or key.key == .right or key.key == .up or key.key == .down) self.creatorKey(key.key);
            } else if (key.key == .up or key.key == .down or key.key == .left or key.key == .right) self.uiNav(self.navKey(key.key).?);
        },
        .key_press => |key| if (self.menu.screen == .controls and self.menu.capturing) {
            self.runCommand(self.menu.bindKey(key.key));
        } else if (self.menu.screen == .none and self.sandbox.creator.open) self.creatorKey(key.key) else if (self.uiActive()) {
            // Number keys pick a conversation choice directly.
            const digits = [_]mach.Core.KeyButtonID{ .one, .two, .three, .four, .five, .six, .seven, .eight };
            if (self.menu.screen == .none) if (self.sandbox.talk) |*talk| for (digits, 0..) |d, i| if (key.key == d and self.sandbox.dialogue.revealed(talk.*)) {
                var visible: [Dialogue.max_choices]u8 = undefined;
                if (i < self.sandbox.dialogue.visibleChoices(talk.*, &self.sandbox.progress, &visible)) {
                    talk.choice = @intCast(i);
                    self.sandbox.talkKey(.confirm);
                }
            };
            if (self.navKey(key.key)) |k| self.uiNav(k);
        } else if (key.key == .escape) self.menu.open(.pause) else if (self.menu.settings.bindings.action(key.key)) |action| switch (action) {
            // Held movement keys are sampled each frame; these are the press edges.
            .forward, .back, .left, .right, .sprint, .ascend, .descend => {},
            // Mantle is held while climbing; pressed in the Kestrel it climbs out.
            .mantle => if (self.sandbox.hangar.piloting) {
                self.actions.leave_jet = true;
            },
            .camera_view => self.actions.toggle_view = true,
            .customize => self.actions.open_creator = true,
            .reset => self.actions.reset = true,
            .walk_fly => self.actions.toggle_mode = true,
            .metrics => self.show_metrics = !self.show_metrics,
            .culling => self.culling = !self.culling,
            .quicksave => self.quicksave(),
            .quickload => _ = self.quickload(),
            .tool_hands => self.actions.select_tool = 1,
            .tool_build => self.actions.select_tool = 2,
            .tool_wire => self.actions.select_tool = 3,
            .tool_bridge => self.actions.select_tool = 4,
            .tool_weapon => self.actions.select_tool = 5,
            .next_item => self.actions.next_item = true,
            .rotate => self.actions.rotate = true,
            .capture_prefab => self.actions.capture = true,
            .channel_down => self.actions.channel_down = true,
            .channel_up => self.actions.channel_up = true,
            .inspect => self.inspecting = !self.inspecting,
            .jump => self.engine.input.jump_pressed = true,
            .roll => self.engine.input.dodge = true,
            .stomp => self.engine.input.stomp = true,
            .grapple => self.engine.input.grapple = true,
            .traversal => self.engine.input.cycle_mode = true,
            .add_guest => self.toggleGuest(),
            .special_1 => self.actions.special_1 = true,
            .special_2 => self.actions.special_2 = true,
            .special_3 => self.actions.special_3 = true,
        },
        .mouse_release => |mouse| switch (mouse.button) {
            .left => self.fire_held = false,
            .right => self.alt_held = false,
            else => {},
        },
        .mouse_press => |mouse| if (self.uiActive()) {
            if (mouse.button == .left) self.pointAt(true);
        } else switch (mouse.button) {
            .left => if (self.captured) {
                self.fire_held = true;
                self.actions.interact = true;
            } else self.capture(core, true),
            .right => if (self.captured) {
                self.alt_held = true;
                self.actions.secondary = true;
            },
            else => {},
        },
        .mouse_capture_gained => self.captured = true,
        .mouse_capture_lost, .focus_lost => {
            self.fire_held = false;
            self.alt_held = false;
            self.captured = false;
            self.engine.input = .{};
        },
        .mouse_motion_relative => |motion| if (self.captured) {
            const sensitivity = self.menu.settings.sensitivity;
            self.engine.input.look_x += @as(f32, @floatCast(motion.dx)) * sensitivity;
            self.engine.input.look_y += @as(f32, @floatCast(motion.dy)) * sensitivity * (if (self.menu.settings.invert_y) @as(f32, -1) else 1);
        },
        .mouse_motion => |motion| {
            // Window points to canvas units (the canvas is `ui_height` units tall).
            const scale = self.ui_height / @max(self.window_height, 1);
            self.pointer = .{ @as(f32, @floatCast(motion.pos.x)) * scale, @as(f32, @floatCast(motion.pos.y)) * scale };
            if (self.uiActive()) self.pointAt(false);
        },
        else => {},
    };
    core.windows.lockShared();
    self.window_height = @floatFromInt(@max(core.windows.get(self.window, .height), 1));
    core.windows.unlockShared();
    // A GUI frees the mouse; leaving it does not grab the mouse again until a click.
    if (self.uiActive() and self.captured) self.capture(core, false);
    self.engine.input.sample(core, self.menu.settings.bindings);
    self.menu.seconds = self.seconds;
    self.pollPads();
    if (self.pad_menu) {
        self.pad_menu = false;
        if (self.menu.screen == .none and !self.uiActive()) self.menu.open(.pause) else if (self.menu.screen == .pause) self.menuKey(.back);
    }
    if (self.interactive) {
        const fov = self.menu.settings.fovRadians();
        // A raised sniper scope narrows the player's view.
        self.engine.camera.fov = fov * self.sandbox.combat.arsenals[0].zoom;
        for (&self.sandbox.guests, 1..) |*g, p| g.camera.fov = fov * self.sandbox.combat.arsenals[p].zoom;
    }
    if (self.uiActive()) self.engine.input = .{};
    self.sandbox.trigger = .{ .fire = self.fire_held and self.captured and !self.uiActive(), .alt = self.alt_held and self.captured and !self.uiActive() };
    const title = self.menu.screen != .none and self.menu.base == .title;
    const paused = self.menu.screen != .none and self.menu.base == .pause;
    if (title) self.titleCamera();
    if (options.smoke_frames > 0 and options.benchmark_frames == 0) {
        self.exerciseSmoke();
        // The last smoke stage drives the rover at full throttle.
        if (self.sandbox.seated != null) self.engine.input.forward = 1;
    }
    if (options.showcase > 0) self.showcase();
    const lap = self.timer.lap();
    self.seconds += lap;
    const steps = self.engine.advance(lap);
    for (0..steps) |_| {
        if (options.benchmark_frontier) self.driveFrontierBenchmark();
        self.routePads();
        // The pause menu stops the world; the title keeps it alive behind the menu.
        if (!paused) {
            const warmup: u64 = @import("engine/Flythrough.zig").frontier_warmup_frames;
            const measuring = options.benchmark_frontier and self.rendered_frames_seen >= warmup and self.rendered_frames_seen < warmup + options.benchmark_frames;
            if (measuring) {
                var timer = mach.time.Timer.start(self.io);
                self.sandbox.stepMeasured(&self.engine.camera, if (title) .{} else self.engine.input, if (title) .{} else self.actions, Time.fixed_dt, self.io, &self.benchmark_substeps) catch |err| self.report("ERROR {s}", .{@errorName(err)});
                self.benchmark_sim.record(timer.lap() * 1000);
            } else {
                self.sandbox.step(&self.engine.camera, if (title) .{} else self.engine.input, if (title) .{} else self.actions, Time.fixed_dt) catch |err| self.report("ERROR {s}", .{@errorName(err)});
            }
        }
        self.actions = .{};
        self.engine.input.clearEdges();
        self.pads.consume();
    }
    if (self.audio) |a| {
        const snap = Audio.Director.snapshot(&self.sandbox, self.engine.camera, paused);
        a.director.update(a, snap);
        for (self.sandbox.cues[0..self.sandbox.cue_count]) |c| Audio.Director.cue(a, snap, c.sound, c.position, c.pitch);
    }
    self.sandbox.cue_count = 0;
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
            if (cmd.join) self.pad_menu = true;
            cmd.join = false;
            if (!self.uiActive()) self.engine.input.merge(cmd.input);
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
            if (self.uiActive()) {
                // A pad driving P1 through any GUI: D-pad moves, X chooses, B goes back.
                if (cmd.up) self.uiNav(.up);
                if (cmd.down) self.uiNav(.down);
                if (cmd.left) self.uiNav(.left);
                if (cmd.right) self.uiNav(.right);
                if (cmd.interact) self.uiNav(.confirm);
                if (cmd.input.dodge) self.uiNav(.back);
                continue;
            }
            self.engine.camera.turn(cmd.input.look_x, cmd.input.look_y, Time.fixed_dt);
            self.actions.interact = self.actions.interact or cmd.interact;
            if (self.sandbox.hangar.piloting and cmd.interact) self.actions.leave_jet = true;
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
        g.fire = cmd.fire;
        g.alt = cmd.alt;
        if (g.trading == null) {
            g.special[0] = g.special[0] or (cmd.up and !cmd.alt);
            g.special[1] = g.special[1] or cmd.down;
            g.special[2] = g.special[2] or (cmd.up and cmd.alt);
        }
        g.next_weapon = g.next_weapon or cmd.left or cmd.right;
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
    const v = options.showcase;
    self.show_metrics = false;
    if ((v >= 18 and v <= 35) or (v >= 37 and v <= 45)) return self.guiShowcase(v);
    self.sandbox.player.mode = .fly;
    self.engine.input = .{};
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
    } else if (v == 16 or v == 17) {
        // Armor lineup: three guests in the exo rig, hardsuit, and vanguard face the camera.
        const Sandbox_ = @import("game/Sandbox.zig");
        const clothing = [_]Profile.Clothing{ .exo_rig, .hardsuit, .vanguard };
        for (&self.sandbox.guests, 0..) |*g, i| {
            if (!g.active) {
                self.sandbox.joinGuest(i);
                g.profile.clothing = clothing[i];
                g.profile.armor = .scout;
                g.profile.helmet = if (i == 2) .sealed else .visor;
                g.profile.outfit = @intCast((i * 2 + 2) % Profile.outfit_colors.len);
            }
            const x = Sandbox_.spawn[0] + (@as(f32, @floatFromInt(i)) - 1) * 1.6;
            const z = Sandbox_.spawn[2] + 3;
            g.player.feet = .{ x, @import("procedural/Terrain.zig").surface(self.sandbox.seed, x, z).height, z };
            g.player.velocity = .{ 0, 0, 0 };
            g.camera.yaw = std.math.pi;
            g.view = .first;
        }
        const ground = @import("procedural/Terrain.zig").surface(self.sandbox.seed, Sandbox_.spawn[0], Sandbox_.spawn[2] + 3).height;
        target = .{ Sandbox_.spawn[0], ground + 1.0, Sandbox_.spawn[2] + 3 };
        eye = .{ Sandbox_.spawn[0] + 0.6, ground + 1.5, Sandbox_.spawn[2] - 1.6 };
        // 17: a three-quarter close-up of the hardsuit.
        if (v == 17) eye = .{ Sandbox_.spawn[0] + 0.9, ground + 1.35, Sandbox_.spawn[2] + 1.35 };
    } else if (v == 36) {
        const Hydrology = @import("procedural/Hydrology.zig");
        const Seed = @import("procedural/Seed.zig");
        const lane: i64 = 0;
        const lane_seed = Seed.mix(self.sandbox.seed ^ @as(u64, @bitCast(lane)) ^ 0x464c4f57);
        const phase = @floor(Seed.unit(lane_seed) * Hydrology.fall_period / 4) * 4;
        var fall_x = Hydrology.fall_period - phase;
        while (fall_x < 900) fall_x += Hydrology.fall_period;
        const fall_z = Hydrology.centerZ(self.sandbox.seed, lane, fall_x);
        const water = Hydrology.level(self.sandbox.seed, lane, fall_x + 0.02);
        target = .{ fall_x, water - 1.2, fall_z };
        eye = .{ fall_x + 130, water + 105, fall_z - 180 };
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
    const dusk = v == 8 or (v >= 10 and v <= 15);
    self.sandbox.tick = if (dusk) @import("engine/Sky.zig").day_ticks * 52 / 100 else @import("engine/Sky.zig").day_ticks * 15 / 100;
    camera.position = mach.math.vec3(eye[0], eye[1], eye[2]);
    const dx = target[0] - eye[0];
    const dz = target[2] - eye[2];
    camera.yaw = std.math.atan2(dx, dz);
    camera.pitch = std.math.atan2(target[1] - eye[1], @sqrt(dx * dx + dz * dz));
}

/// `-Dshowcase=18..26`: GUI screens for review. 18 title, 19 conversation, 20 upgrades,
/// 21 market shop, 22 wardrobe, 23 customization, 24 pause, 25 settings, 26 HUD,
/// 27 four-player split screen with a guest trading, 28 controls while rebinding,
/// 29 the garage with all three hover cars, 30 a Hive nest under attack, 31 the fabricator,
/// 32 the Skimmer in flight, 33 the Kestrel on its pad, 34 a dogfight by a Brood carrier,
/// 35 the carrier from above, 45 a live missile lock for HUD capture.
fn guiShowcase(self: *App, v: u32) void {
    const sb = &self.sandbox;
    self.engine.input = .{};
    sb.tick = @import("engine/Sky.zig").day_ticks * 15 / 100;
    if (v == 18) {
        if (self.menu.screen == .none) self.menu.open(.title);
        self.titleCamera();
        return;
    }
    if (sb.talk) |*talk| talk.reveal = 999;
    // 34/35: the Kestrel flies toward the first carrier on afterburner.
    if ((v == 34 or v == 35) and self.gui_showcase_ready) {
        const c = sb.skies.carriers[0].position();
        const f = sb.hangar.fighter.?.body.pos;
        const d = R3.normalize(.{ c[0] - f.x, c[1] + (if (v == 35) @as(f32, 30) else -10) - f.y, c[2] - f.z });
        self.engine.camera.yaw = std.math.atan2(d[0], d[2]);
        self.engine.camera.pitch = std.math.asin(d[1]);
        self.engine.input.fast = true;
    }
    // 45 holds a target directly in front of the Kestrel and keeps the missile lock live.
    if (v == 45 and self.gui_showcase_ready) {
        const f = sb.hangar.fighter.?;
        const target = f.body.pos.add(f.forward().scale(220));
        if (sb.enemies.units[0]) |*u| u.position = .{ target.x, target.y, target.z };
        sb.trigger = .{ .alt = true };
    }
    // 32: fly the Skimmer forward, boosting, from the garage toward the city.
    if (v == 32 and self.gui_showcase_ready) {
        self.engine.input.forward = 1;
        self.engine.input.fast = true;
        self.engine.input.jump = sb.garage.cars[0] != null and sb.garage.cars[0].?.flyer.ride < 4;
    }
    // 37–40: combat, held every frame: a trooper (or a squad) stays in front of the player.
    if (v >= 37 and v <= 40 and self.gui_showcase_ready) {
        const fwd: [3]f32 = .{ @sin(self.engine.camera.yaw), 0, @cos(self.engine.camera.yaw) };
        sb.player.feet = self.showcase_feet;
        const feet = sb.player.feet;
        const near: f32 = if (v == 37) 2.3 else 14;
        for (0..3) |i| {
            if (v == 37 and i > 0) break;
            const side: f32 = if (v == 37) 0 else (@as(f32, @floatFromInt(i)) - 1) * 3;
            const at: [3]f32 = .{ feet[0] + fwd[0] * near - fwd[2] * side, feet[1], feet[2] + fwd[2] * near + fwd[0] * side };
            if (sb.enemies.units[i]) |*u| {
                u.position = at;
                u.velocity = @splat(0);
                u.health = 5000;
            } else sb.enemies.units[i] = .{ .kind = .trooper, .nest = 0, .position = at, .health = 5000, .orbit = 0 };
        }
        sb.enemies.bolts = @splat(null);
        self.showcase_frame += 1;
        const f = self.showcase_frame;
        sb.trigger = switch (v) {
            37 => .{ .fire = (f / 8) % 2 == 0 },
            38 => .{ .fire = f % 70 < 2 },
            39 => .{ .fire = true },
            else => .{},
        };
        if (v == 40) sb.specials.players[0].lance = 2.5;
        return;
    }
    if (self.gui_showcase_ready) return;
    self.gui_showcase_ready = true;
    // Stand on the south market plaza, facing Maro's counter.
    const stall = sb.stallPosition(0);
    const plaza = sb.catalog.district.nodes[Market.stall_plazas[0]].position;
    const out = @import("physics/Rotation.zig").normalize(.{ plaza[0] - stall[0], 0, plaza[2] - stall[2] });
    sb.player.mode = .walk;
    sb.player.feet = .{ stall[0] + out[0] * 3.4, stall[1] + 0.05, stall[2] + out[2] * 3.4 };
    sb.player.velocity = .{ 0, 0, 0 };
    sb.view = .third;
    self.engine.camera.yaw = std.math.atan2(-out[0], -out[2]);
    self.engine.camera.pitch = -0.15;
    sb.wallet = .{ .scrap = 182, .parts = 6, .kits = .{ 1, 0, 2 } };
    sb.progress.levels = .{ 1, 0, 2, 0, 1, 0 };
    sb.progress.buySuit(.exo_rig, &sb.wallet) catch {};
    sb.wallet.scrap = 182;
    sb.profile.setName("MIRA-7") catch {};
    switch (v) {
        19 => sb.startTalk(.{ .keeper = 0 }),
        20 => sb.shop = .{ .kind = .upgrades, .row = 1 },
        21 => {
            sb.trading = 0;
            sb.trade_row = 1;
        },
        22 => sb.shop = .{ .kind = .wardrobe, .row = 3 },
        23 => sb.creator.begin(sb.profile),
        24 => self.menu.open(.pause),
        25 => {
            self.menu.open(.pause);
            self.menu.open(.settings);
        },
        29 => {
            sb.progress.vehicles = 0b111;
            @import("game/Frontier.zig").refresh(sb);
            const pad = @import("game/Garage.zig").padPosition(sb.seed, Sandbox.spawn, .dart);
            sb.player.feet = .{ pad[0] - 4, pad[1], pad[2] - 13 };
            self.engine.camera.yaw = 0.25;
            self.engine.camera.pitch = -0.2;
        },
        30 => {
            const nest = sb.enemies.nests[0].position;
            sb.player.feet = .{ nest[0] - 45, @import("procedural/Terrain.zig").surface(sb.seed, nest[0] - 45, nest[2]).height, nest[2] };
            self.engine.camera.yaw = std.math.pi / 2.0;
            self.engine.camera.pitch = 0.12;
            for (0..4) |_| sb.enemies.units[sb.enemies.unitCount(null)] = .{ .kind = .drone, .nest = 0, .position = .{ nest[0] - 15, nest[1] + 12, nest[2] + @as(f32, @floatFromInt(sb.enemies.unitCount(null))) * 4 - 6 }, .health = 60, .orbit = @as(f32, @floatFromInt(sb.enemies.unitCount(null))) };
            sb.enemies.units[5] = .{ .kind = .sentinel, .nest = 0, .position = .{ nest[0] - 8, nest[1] + 18, nest[2] }, .health = 260, .orbit = 0 };
            for ([_]f32{ -4, 4 }, 6..) |dz, slot| {
                const x = nest[0] - 22;
                const z = nest[2] + dz;
                sb.enemies.units[slot] = .{ .kind = .trooper, .nest = 0, .position = .{ x, @import("procedural/Terrain.zig").surface(sb.seed, x, z).height, z }, .health = 120, .orbit = 0 };
            }
            sb.progress.weapons = 0b10;
            sb.combat.arsenals[0].active = .blaster;
            sb.tools.tool = .weapon;
        },
        32 => {
            sb.progress.vehicles = 0b001;
            @import("game/Frontier.zig").refresh(sb);
            sb.player.mode = .walk;
            Frontier_board(sb, &self.engine.camera);
        },
        33 => {
            sb.progress.fighter = true;
            @import("game/Frontier.zig").refresh(sb);
            const pad = @import("game/Hangar.zig").padPosition(sb.seed, Sandbox.spawn);
            sb.player.feet = .{ pad[0] - 14, pad[1], pad[2] - 12 };
            self.engine.camera.yaw = 0.85;
            self.engine.camera.pitch = -0.08;
        },
        34, 35 => {
            sb.progress.fighter = true;
            @import("game/Frontier.zig").refresh(sb);
            // Start airborne, already closing on the first carrier with wasps up.
            const c = sb.skies.carriers[0].position();
            const entry = R3.add(c, .{ -160, if (v == 35) @as(f32, 40) else -30, -220 });
            sb.hangar.place(sb.seed, Sandbox.spawn, entry, std.math.atan2(@as(f32, 160), 220));
            sb.hangar.fighter.?.body.vel = @import("character/math.zig").Vec3.init(80, 0, 110);
            sb.hangar.fighter.?.throttle = 0.9;
            sb.hangar.fighter.?.grounded = false;
            sb.hangar.board(&self.engine.camera);
            sb.trigger = .{ .fire = v == 34 };
            for (0..5) |k| sb.skies.wasps[k] = .{ .position = R3.add(c, .{ -60 + @as(f32, @floatFromInt(k)) * 20, -25, -90 + @as(f32, @floatFromInt(k)) * 6 }), .forward = .{ -0.5, 0, -0.85 }, .carrier = 0, .state = .attack };
        },
        37, 38, 39, 40 => {
            const kind: @import("game/Combat.zig").WeaponKind = switch (v) {
                37 => .beam_saber,
                38 => .sniper_rifle,
                39 => .machine_gun,
                else => .heavy_rifle,
            };
            sb.progress.weapons = @as(u16, 1) << @intCast(@intFromEnum(kind));
            sb.combat.arsenals[0].active = kind;
            sb.tools.tool = .weapon;
            // The saber reads from behind; guns and powers from the eyes, as a viewmodel.
            sb.view = if (v == 37) .third else .first;
            if (v == 40) {
                sb.profile.class = .synthetic;
                sb.profile.clothing = .undersuit;
                sb.profile.armor = .none;
                sb.profile.helmet = .open;
                sb.profile.presentation = .feminine;
            }
            if (v == 37) self.engine.camera.yaw += 0.6;
            self.showcase_feet = sb.player.feet;
            self.engine.camera.pitch = -0.05;
        },
        41, 42, 43, 44 => {
            // Mountains and caves: the first range from the foothills, then cave system 0's
            // mouth, its first chamber, and its heart.
            const Caves = Sandbox.Caves;
            const sys = &sb.caves.systems[0];
            const Terrain = @import("procedural/Terrain.zig");
            const look = struct {
                fn at(camera: *@import("world/Camera.zig"), from: [3]f32, to: [3]f32) void {
                    const d = R3.normalize(R3.sub(to, from));
                    camera.yaw = std.math.atan2(d[0], d[2]);
                    camera.pitch = std.math.asin(d[1]);
                }
            }.at;
            sb.view = if (v == 42) .third else .first;
            sb.tools.tool = .hands;
            switch (v) {
                41 => {
                    const range = @import("procedural/Mountains.zig").ranges(sb.seed)[sys.range];
                    const mid = range.spine[2];
                    const toward = R3.normalize(.{ mid[0], 0, mid[1] });
                    const from: [3]f32 = .{ mid[0] - toward[0] * 900, 0, mid[1] - toward[2] * 900 };
                    sb.player.mode = .fly;
                    sb.player.feet = .{ from[0], Terrain.surface(sb.seed, from[0], from[2]).height + 70, from[2] };
                    // Free flight follows the camera.
                    self.engine.camera.position = mach.math.vec3(sb.player.feet[0], sb.player.feet[1], sb.player.feet[2]);
                    look(&self.engine.camera, sb.player.feet, .{ mid[0], 120, mid[1] });
                },
                42 => {
                    const from = R3.add(sys.entrance, R3.add(R3.scale(sys.inward, -9), .{ sys.inward[2] * 3, 0, -sys.inward[0] * 3 }));
                    sb.player.mode = .walk;
                    sb.player.feet = .{ from[0], Terrain.surface(sb.seed, from[0], from[2]).height, from[2] };
                    look(&self.engine.camera, R3.add(sb.player.feet, .{ 0, 4, 0 }), R3.add(sys.entrance, .{ 0, 2, 0 }));
                },
                43 => {
                    const room = sys.rooms[0];
                    const from = R3.sub(.{ room.center[0], room.floor, room.center[2] }, R3.scale(sys.inward, room.radii[0] * 0.5));
                    sb.player.mode = .walk;
                    sb.player.feet = from;
                    const next = sys.rooms[1];
                    look(&self.engine.camera, R3.add(from, .{ 0, 1.7, 0 }), .{ next.center[0], next.floor + 2, next.center[2] });
                },
                else => {
                    const heart = sys.heart();
                    const from = Caves.floorSpot(sys, @intCast(heart - &sys.rooms[0]), 0, 1, 0.7);
                    sb.player.mode = .walk;
                    sb.player.feet = from;
                    look(&self.engine.camera, R3.add(from, .{ 0, 1.7, 0 }), .{ heart.center[0], heart.floor + 2.5, heart.center[2] });
                },
            }
            sb.player.velocity = @splat(0);
        },
        45 => {
            sb.progress.fighter = true;
            @import("game/Frontier.zig").refresh(sb);
            for (&sb.skies.carriers) |*c| c.alive = false;
            sb.skies.wasps = @splat(null);
            const pad = @import("game/Hangar.zig").padPosition(sb.seed, Sandbox.spawn);
            // Stage above the canopy so it cannot obscure the lock target in
            // the chase-camera capture.
            const entry: [3]f32 = .{ pad[0] + 180, pad[1] + 1000, pad[2] - 100 };
            sb.hangar.place(sb.seed, Sandbox.spawn, entry, 0);
            sb.hangar.fighter.?.body.vel = @import("character/math.zig").Vec3.zero;
            sb.hangar.fighter.?.throttle = 0;
            sb.hangar.fighter.?.grounded = false;
            sb.hangar.board(&self.engine.camera);
            const f = sb.hangar.fighter.?;
            const target = f.body.pos.add(f.forward().scale(220));
            sb.enemies.units[0] = .{ .generation = 1, .kind = .drone, .nest = 0, .position = .{ target.x, target.y, target.z }, .health = 1000, .orbit = 0 };
            sb.player.mode = .walk;
        },
        31 => {
            sb.progress.inventory = .{ 14, 3, 9, 2 };
            sb.shop = .{ .kind = .fabricate, .tab = 0, .row = 0 };
        },
        28 => {
            self.menu.open(.pause);
            self.menu.open(.controls);
            _ = self.menu.settings.bindings.bind(.stomp, .k) catch {};
            self.menu.row = @intFromEnum(@import("game/Bindings.zig").Action.grapple);
            self.menu.capturing = true;
        },
        27 => {
            for (0..3) |i| sb.joinGuest(i);
            sb.guests[1].trading = 0;
            sb.guests[1].trade_row = 2;
        },
        else => {},
    }
}

fn Frontier_board(sb: *Sandbox, camera: *@import("world/Camera.zig")) void {
    const car = &sb.garage.cars[0].?.flyer;
    // Face the city: the district's first plaza.
    const plaza = sb.catalog.district.nodes[0].position;
    const yaw = std.math.atan2(plaza[0] - car.body.pos.x, plaza[2] - car.body.pos.z);
    car.body.rot = @import("character/math.zig").Quat.fromAxisAngle(@import("character/math.zig").Vec3.unit_y, yaw);
    @import("game/Frontier.zig").board(sb, 0, camera);
}

/// Screen position (canvas units within `view`) of a world point, or null behind the camera.
fn project(camera: @import("world/Camera.zig"), view: Screens.Rect, point: [3]f32) ?[2]f32 {
    const f = camera.forward();
    const fw: [3]f32 = .{ f.x(), f.y(), f.z() };
    const right: [3]f32 = .{ @cos(camera.yaw), 0, -@sin(camera.yaw) };
    const up: [3]f32 = .{ fw[1] * right[2] - fw[2] * right[1], fw[2] * right[0] - fw[0] * right[2], fw[0] * right[1] - fw[1] * right[0] };
    const d: [3]f32 = .{ point[0] - camera.position.x(), point[1] - camera.position.y(), point[2] - camera.position.z() };
    const z = d[0] * fw[0] + d[1] * fw[1] + d[2] * fw[2];
    if (z < 1) return null;
    const x = d[0] * right[0] + d[1] * right[1] + d[2] * right[2];
    const y = d[0] * up[0] + d[1] * up[1] + d[2] * up[2];
    const t = @tan(camera.fov / 2);
    const aspect = view.w / view.h;
    const nx = x / (z * t * aspect);
    const ny = y / (z * t);
    if (@abs(nx) > 1.2 or @abs(ny) > 1.2) return null;
    return .{ view.x + (nx * 0.5 + 0.5) * view.w, view.y + (0.5 - ny * 0.5) * view.h };
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

fn quickload(self: *App) bool {
    const bytes = Save.readFile(self.io, self.allocator, Save.default_path) catch |err| {
        self.report("LOAD FAILED {s}", .{@errorName(err)});
        return false;
    };
    defer self.allocator.free(bytes);
    self.sandbox.restore(self.allocator, bytes, &self.engine.camera) catch |err| {
        self.report("LOAD FAILED {s}", .{@errorName(err)});
        return false;
    };
    // Prefabs saved with the world come first; the shared library fills in the rest.
    self.importPrefabs();
    self.report("LOADED {s}", .{Save.default_path});
    return true;
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
            self.smokeGui();
            self.smokeFrontier();
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

/// Drives the menus, a conversation and the tinker's panel through the same navigation the
/// keyboard and pads use. Settings are not written in unattended runs.
fn smokeGui(self: *App) void {
    const sb = &self.sandbox;
    self.menu.open(.pause);
    for ([_]Menu.Key{ .down, .down, .down, .down, .confirm, .right, .left, .back, .back }) |k| self.uiNav(k);
    const menu_closed = self.menu.screen == .none;
    sb.startTalk(.{ .keeper = 0 });
    const greeting = sb.dialogue.node(sb.talk.?).id;
    // Reveal, ask about the suit, reveal, and open the upgrades.
    for ([_]Menu.Key{ .confirm, .confirm, .confirm, .confirm }) |k| self.uiNav(k);
    const opened = sb.shop != null and sb.shop.?.kind == .upgrades;
    const scrap = sb.wallet.scrap;
    sb.wallet.scrap += 40;
    self.uiNav(.confirm);
    const level = sb.progress.level(.fuel_tank);
    self.uiNav(.back);
    sb.wallet.scrap = scrap;
    std.log.info("Smoke GUI: pause/settings closed={any}, keeper greeting {s}, upgrades opened={any}, fuel tank level {d}, panels closed={any}", .{ menu_closed, greeting, opened, level, !self.uiActive() });
}

/// Fabricates a car and a blaster through the fabricator panel, flies the car, and shoots a
/// drone, through the same calls the window and the simulation use.
fn smokeFrontier(self: *App) void {
    const sb = &self.sandbox;
    const Combat = @import("game/Combat.zig");
    const keep = sb.progress;
    const wallet = sb.wallet;
    sb.progress.inventory = .{ 20, 6, 20, 0 };
    sb.wallet.scrap += 200;
    sb.shop = .{ .kind = .fabricate };
    self.uiNav(.confirm);
    sb.shop.?.tab = 3;
    sb.shop.?.row = 0;
    self.uiNav(.confirm);
    self.uiNav(.back);
    const cars = sb.garage.cars[0] != null;
    const blaster = sb.progress.ownsWeapon(.blaster);
    // Fly the Skimmer for two seconds.
    var camera = self.engine.camera;
    sb.garage.board(0, &camera);
    const takeoff = sb.garage.cars[0].?.flyer.body.pos;
    for (0..120) |_| sb.garage.step(&sb.physics, .{ .forward = 1 }, 1.0 / 60.0);
    const flown = sb.garage.cars[0].?.flyer.body.pos.distance(takeoff);
    _ = sb.garage.leave(&sb.physics);
    // A drone ahead of a blaster.
    sb.enemies.units[0] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 300, 20 }, .health = 15, .orbit = 0 };
    var events: [32]Combat.Event = undefined;
    var aim: Combat.Aim = .{ .eye = .{ 0, 300, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 298.5, 0 }, .fire = true };
    var downed = false;
    for (0..60) |k| {
        if (k == 1) aim.fire = false;
        const n = sb.combat.step(0, &sb.physics, &sb.enemies, sb.progress.weapons, aim, 1.0 / 60.0, &events);
        for (events[0..@min(n, events.len)]) |e| if (e == .hive and e.hive == .unit_down) {
            downed = true;
        };
    }
    std.log.info("Smoke frontier: skimmer parked={any} flew {d:.1} m, blaster={any}, drone downed={any}; {d} nests, {d} pickups", .{ cars, flown, blaster, downed, sb.enemies.nest_count, sb.collectibles.count });
    // The Kestrel: fabricate it through the panel, lift off on its jets, and gun down a wasp.
    sb.progress.inventory = .{ 20, 8, 20, 0 };
    // The smoke stages vehicle handling directly, so provide the story reward normally earned
    // by asking Maro after spotting a carrier.
    sb.progress.setFlag("kestrel_blueprint");
    sb.wallet.scrap += 200;
    sb.shop = .{ .kind = .fabricate, .tab = 0, .row = 3 };
    self.uiNav(.confirm);
    self.uiNav(.back);
    var jet_camera = self.engine.camera;
    sb.hangar.board(&jet_camera);
    for (0..180) |_| sb.hangar.step(&sb.physics, .{ .aim = sb.hangar.fighter.?.forward(), .climb = 1 }, 1.0 / 60.0);
    const lifted = !sb.hangar.fighter.?.grounded;
    const Skies = @import("game/Skies.zig");
    const f = sb.hangar.fighter.?;
    // Aim up into clear sky: a level line from the pad can run into the rising ground.
    const wasp_at = f.body.pos.add(f.forward().scale(50)).add(@import("character/math.zig").Vec3.init(0, 60, 0));
    const nose = wasp_at.sub(f.body.pos).normalize();
    sb.skies.wasps[0] = .{ .position = .{ wasp_at.x, wasp_at.y, wasp_at.z }, .forward = .{ 0, 0, 1 }, .speed = 0, .carrier = 0, .health = 25 };
    const jet: Skies.Jet = .{ .position = .{ f.body.pos.x, f.body.pos.y, f.body.pos.z }, .velocity = @splat(0), .forward = .{ nose.x, nose.y, nose.z }, .airborne = true };
    var sky_events: [64]Skies.Event = undefined;
    var wasp_down = false;
    for (0..90) |_| {
        if (sb.skies.wasps[0]) |*w| {
            w.position = .{ wasp_at.x, wasp_at.y, wasp_at.z };
            w.speed = 0;
        }
        var count: usize = 0;
        sb.skies.fireJet(&sb.enemies, jet, sb.hangar.guns(), true, false, 1.0 / 60.0, &sky_events, &count);
        count = sb.skies.step(&sb.physics, &sb.enemies, null, &.{}, 1.0 / 60.0, &sky_events);
        for (sky_events[0..@min(count, sky_events.len)]) |e| wasp_down = wasp_down or e == .wasp_down;
    }
    _ = sb.hangar.leave(&sb.physics);
    std.log.info("Smoke flight: kestrel fabricated={any}, lifted off={any}, wasp downed={any}; carriers at {d:.0} and {d:.0} m up", .{ sb.progress.fighter, lifted, wasp_down, sb.skies.carriers[0].altitude, sb.skies.carriers[1].altitude });
    self.smokeCombat();
    self.smokeCaves();
    // Leave the run's progress as it was (later stages log the market and wallet).
    sb.progress = keep;
    sb.wallet = wallet;
    @import("game/Frontier.zig").refresh(sb);
}

/// The saber and a sniper rifle fabricated through the panel, a saber combo on a trooper with
/// P1's rig, a piercing sniper beam, and each class's specials.
fn smokeCombat(self: *App) void {
    const sb = &self.sandbox;
    const Combat = @import("game/Combat.zig");
    const Specials = @import("game/Specials.zig");
    const Fabricator = @import("game/Fabricator.zig");
    sb.progress.inventory = .{ 30, 4, 30, 0 };
    sb.wallet.scrap += 100;
    var list: [Fabricator.recipes.len]u8 = undefined;
    for (Fabricator.onTab(.weapons, &list), 0..) |index, row| {
        const w = Fabricator.recipes[index].output.weapon;
        if (w != .beam_saber and w != .sniper_rifle) continue;
        sb.shop = .{ .kind = .fabricate, .tab = 3, .row = @intCast(row) };
        self.uiNav(.confirm);
        self.uiNav(.back);
    }
    const made = sb.progress.ownsWeapon(.beam_saber) and sb.progress.ownsWeapon(.sniper_rifle);
    const dt = 1.0 / 60.0;
    var events: [32]Combat.Event = undefined;
    const feet: [3]f32 = .{ 0, 298.4, 0 };
    sb.enemies.units = @splat(null);
    sb.enemies.units[0] = .{ .kind = .trooper, .nest = 0, .position = .{ 0, 298.4, 1.7 }, .health = 2000, .orbit = 0 };
    const saber: u16 = @as(u16, 1) << @intFromEnum(Combat.WeaponKind.beam_saber);
    var aim: Combat.Aim = .{ .eye = .{ 0, 300, 0 }, .forward = .{ 0, 0, 1 }, .feet = feet, .rig = @import("game/Frontier.zig").rigFor(sb, 0, sb.profile) };
    var cuts: usize = 0;
    var stunned = false;
    for (0..60) |k| {
        if (sb.enemies.units[0]) |*u| u.position = .{ 0, 298.4, 1.7 };
        aim.fire = k == 0 or k == 12 or k == 24;
        const n = sb.combat.step(0, &sb.physics, &sb.enemies, saber, aim, dt, &events);
        for (events[0..@min(n, events.len)]) |e| cuts += @intFromBool(e == .cut);
        if (sb.enemies.units[0]) |u| stunned = stunned or u.stun > 0;
    }
    const cut_health = if (sb.enemies.units[0]) |u| u.health else 0;
    // A sniper beam through two drones.
    sb.enemies.units[0] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 300, 30 }, .health = 1000, .orbit = 0 };
    sb.enemies.units[1] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 300, 50 }, .health = 1000, .orbit = 0 };
    const sniper: u16 = @as(u16, 1) << @intFromEnum(Combat.WeaponKind.sniper_rifle);
    aim = .{ .eye = .{ 0, 300, 0 }, .forward = .{ 0, 0, 1 }, .feet = feet, .fire = true };
    _ = sb.combat.step(0, &sb.physics, &sb.enemies, sniper, aim, dt, &events);
    const pierced = sb.enemies.units[0].?.health < 1000 and sb.enemies.units[1].?.health < 1000;
    // Specials: a ranger's arc grenade, a synthetic's kinetic slam.
    var special_events: [32]Specials.Event = undefined;
    sb.enemies.units[0] = .{ .kind = .trooper, .nest = 0, .position = .{ 0, 298.4, 7 }, .health = 1000, .orbit = 0 };
    sb.specials = .{};
    _ = sb.specials.step(0, .ranger, &sb.physics, &sb.enemies, &sb.combat, .{ .eye = .{ 0, 300, 0 }, .forward = .{ 0, 0, 1 }, .feet = feet, .pressed = .{ true, false, false } }, dt, &special_events);
    var grenade = false;
    for (0..90) |_| {
        const n = sb.specials.stepWorld(&sb.physics, &sb.enemies, &sb.combat, dt, &special_events);
        for (special_events[0..@min(n, special_events.len)]) |e| grenade = grenade or e == .burst;
    }
    sb.enemies.units[1] = .{ .kind = .drone, .nest = 0, .position = .{ 3, 299.5, 0 }, .health = 1000, .orbit = 0 };
    _ = sb.specials.step(1, .synthetic, &sb.physics, &sb.enemies, &sb.combat, .{ .eye = .{ 0, 300, 0 }, .forward = .{ 0, 0, 1 }, .feet = feet, .pressed = .{ false, true, false } }, dt, &special_events);
    const slammed = sb.enemies.units[1].?.velocity[0] > 3;
    std.log.info("Smoke combat: saber and sniper made={any}, saber cuts={d} trooper health {d:.0} stunned={any}, sniper pierced={any}, grenade burst={any}, slam threw={any}", .{ made, cuts, cut_health, stunned, pierced, grenade, slammed });
    sb.enemies.units = @splat(null);
    sb.specials = .{};
    sb.combat.arsenals = @splat(.{});
}

/// Walks P1 in through the first cave mouth with the real simulation step, and reports the
/// ranges and caves.
fn smokeCaves(self: *App) void {
    const sb = &self.sandbox;
    const Terrain = @import("procedural/Terrain.zig");
    const Mountains = @import("procedural/Mountains.zig");
    const keep_player = sb.player;
    const keep_view = sb.view;
    var tallest: f32 = 0;
    for (Mountains.ranges(sb.seed)) |r| for (r.spine) |p| {
        tallest = @max(tallest, Terrain.surface(sb.seed, p[0], p[1]).height);
    };
    const sys = &sb.caves.systems[0];
    const outside = R3.add(sys.entrance, R3.scale(sys.inward, -10));
    sb.player = .{ .feet = .{ outside[0], Terrain.surface(sb.seed, outside[0], outside[2]).height, outside[2] }, .mode = .walk };
    sb.view = .first;
    var camera = self.engine.camera;
    camera.yaw = std.math.atan2(sys.inward[0], sys.inward[2]);
    camera.pitch = 0;
    var underground = false;
    for (0..60 * 8) |_| {
        sb.step(&camera, .{ .forward = 1 }, .{}, 1.0 / 60.0) catch break;
        const f = sb.player.feet;
        if (Sandbox.Caves.systemAt(&sb.caves, R3.add(f, .{ 0, 1, 0 })) == 0 and f[1] < Terrain.surface(sb.seed, f[0], f[2]).height - 4) underground = true;
    }
    const f = sb.player.feet;
    var built: usize = 0;
    for (sb.cave_colliders) |c| built += @intFromBool(!c.eql(.none));
    var meshes: usize = 0;
    for (sb.catalog.cave_meshes[0..sb.caves.count]) |h| meshes += @intFromBool(if (sb.catalog.mesh(h)) |e| e.ready else false);
    std.log.info("Smoke caves: {d} cave systems in {d} ranges (highest spine ground {d:.0} m), {d} meshes ready; walked in underground={any} grounded={any} {d:.1} m under the slope, {d} colliders built", .{ sb.caves.count, Mountains.count, tallest, meshes, underground, sb.player.grounded, Terrain.surface(sb.seed, f[0], f[2]).height - f[1], built });
    sb.player = keep_player;
    sb.view = keep_view;
    sb.cave_inside = @splat(null);
    sb.enemies.units = @splat(null);
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
        } else true) std.log.info("Deferred meshes ready {d:.0} ms after start (worst build {d:.0} ms)", .{ @as(f64, @floatFromInt(self.started.untilNow(self.io, .awake).nanoseconds)) / 1e6, loader.snapshotStats().worst_job_ms });
    }
}

pub fn publish(self: *App, renderer: *Renderer) void {
    self.installDeferred();
    self.pumpReload(renderer);
    self.pumpStressPack(renderer);
    self.rendered_frames_seen = renderer.frames;
    renderer.views[0].camera = self.engine.camera;
    if (options.character_showcase > 0) {
        const feet = self.sandbox.player.feet;
        renderer.views[0].camera.position = mach.math.vec3(feet[0], feet[1] + 1.12, feet[2] + 2.8);
        renderer.views[0].camera.yaw = std.math.pi;
        renderer.views[0].camera.pitch = -0.08;
    }
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
    renderer.views[0].crosshair = sandbox.seated == null and !self.uiActive() and (self.captured or sandbox.player.mode == .walk);
    renderer.views[0].hide_owner = if (sandbox.bodyShown()) 0 else 1;
    renderer.view_count = 1;
    // City showcases use P1's view only, even when guests stand in the shot.
    if (options.showcase == 0 or options.showcase >= 18) for (&sandbox.guests, 0..) |*g, i| if (g.active) {
        const view = &renderer.views[renderer.view_count];
        view.* = .{ .camera = g.camera, .hide_owner = if (g.view == .first) @intCast(i + 2) else 0, .crosshair = true, .accent = Profile.accent_colors[g.profile.accent] };
        // The GUI draws the guest's vitals and stall panel; this is its aimed prompt.
        if (g.target == .stall) {
            view.lines[1].set("{s}'S STALL  X TRADE", .{Screens.keeperName(sandbox, g.target.stall)});
        } else if (g.target == .device) {
            const def = sandbox.machines[g.target.device.machine].blueprint.device(g.target.device.device);
            if (def.kind == .button) view.lines[1].set("{s} BUTTON  X PRESS", .{def.name()});
        }
        renderer.view_count += 1;
    };
    const minutes: u32 = @intFromFloat(renderer.time_of_day * 24 * 60);
    const motion = if (sandbox.seated != null) "DRIVE" else if (sandbox.player.mode == .fly) "FLY" else @tagName(sandbox.player.motion);
    renderer.hud_lines[0].set("{d:0>2}:{d:0>2}  {s}  {s}  {s} FUEL {d:.0}  TOOL {s}  SCRAP {d}  PARTS {d}", .{ minutes / 60, minutes % 60, sandbox.profile.name(), motion, @tagName(sandbox.player.traversal), sandbox.player.fuel, @tagName(sandbox.tools.tool), sandbox.wallet.scrap, sandbox.wallet.parts });
    if (sandbox.hangar.piloting) {
        const f = &sandbox.hangar.fighter.?;
        const g = &sandbox.skies.guns;
        renderer.hud_lines[1].set("KESTREL  {d:.0} M/S  THR {d:.0}%{s}  HULL {d:.0}/{d:.0}  MSL {d}/{d}  GUNS {s}  CLICK FIRE  RMB LOCK  F OUT", .{ f.airspeed(), f.throttle * 100, if (self.engine.input.fast) " BURN" else "", @max(0, f.hull), f.hull_max, g.missile_ammo, g.missile_capacity, if (g.overheated) "HOT" else "OK" });
    } else if (sandbox.garage.piloting) |i| {
        const car = &sandbox.garage.cars[i].?.flyer;
        const ground = @import("procedural/Terrain.zig").surface(sandbox.seed, car.body.pos.x, car.body.pos.z).height;
        const race = sandbox.garage.race;
        renderer.hud_lines[1].set("{s}  {d:.0} M/S  BOOST {d:.0}%  {s} {d}/{d} {d:.1}s  {d:.0} M UP", .{ @import("vehicle/Designs.zig").name(@enumFromInt(i)), car.body.vel.length(), car.boost_charge * 100, if (race.active) "GATE" else if (race.finished) "FINISH" else "START", if (race.active) race.gate + 1 else 0, @import("game/Racing.zig").node_count, race.elapsed, car.body.pos.y - ground });
    } else if (sandbox.seated) |m| {
        const placed = &sandbox.machines[m];
        const motor = placed.machine.blueprint.vehicle.?.motor;
        renderer.hud_lines[1].set("{d:.1} M/S  POWER {d:.0}%  WASD DRIVE  SPACE BRAKE  CLICK EXIT", .{ placed.vehicle.?.forwardSpeed(&sandbox.physics), placed.machine.satisfaction(motor) * 100 });
    } else if (sandbox.held) |i| {
        renderer.hud_lines[1].set("HOLDING CRATE {d}  CLICK DROP", .{i});
    } else switch (sandbox.target) {
        .prop => |i| renderer.hud_lines[1].set("CRATE {d}  CLICK GRAB", .{i}),
        .relic => |r| renderer.hud_lines[1].set("RELIC {d}:{d}:{d}  RMB SALVAGE", .{ r.ref.x, r.ref.z, r.ref.id }),
        .bridge => |i| renderer.hud_lines[1].set("YOUR BRIDGE {d}  TOOL 4 + RMB REMOVE", .{i}),
        .stall => |i| renderer.hud_lines[1].set("TALK TO {s}  CLICK", .{Screens.keeperName(sandbox, i)}),
        .walker => renderer.hud_lines[1].set("CANOPY LOCAL  CLICK TALK", .{}),
        .car => |i| renderer.hud_lines[1].set("{s}  CLICK BOARD", .{@import("vehicle/Designs.zig").name(@enumFromInt(i))}),
        .jet => renderer.hud_lines[1].set("KESTREL FIGHTER  CLICK BOARD", .{}),
        .fabricator => renderer.hud_lines[1].set("FABRICATOR  CLICK OPEN", .{}),
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
    var hint_buffer: [96]u8 = undefined;
    const hint = Build.hint(sandbox, &hint_buffer);
    if (sandbox.seated == null and hint.len > 0 and sandbox.target != .device) renderer.hud_lines[1].set("{s}", .{hint});
    if (sandbox.tools.tool == .wire and Build.pendingWire(sandbox) != null) renderer.hud_lines[1].set("{s}", .{hint});
    renderer.hud_lines[2] = if (self.engine.time.tick < self.status_until) self.status else .{};
    if (renderer.hud_lines[2].len == 0 and sandbox.noticeText().len > 0) renderer.hud_lines[2].set("{s}", .{sandbox.noticeText()});
    if (renderer.hud_lines[2].len == 0 and sandbox.hangar.piloting) {
        const f = sandbox.hangar.fighter.?;
        var nearest: ?usize = null;
        var nearest_distance: f32 = 1400;
        for (sandbox.skies.carriers, 0..) |carrier, i| if (carrier.alive) {
            const p = carrier.position();
            const dx = p[0] - f.body.pos.x;
            const dy = p[1] - f.body.pos.y;
            const dz = p[2] - f.body.pos.z;
            const distance = @sqrt(dx * dx + dy * dy + dz * dz);
            if (distance < nearest_distance) {
                nearest = i;
                nearest_distance = distance;
            }
        };
        if (nearest) |i| {
            const carrier = sandbox.skies.carriers[i];
            switch (carrier.stage()) {
                .turrets => renderer.hud_lines[2].set("BROOD {d}  FLAK TURRETS {d}/4", .{ i + 1, carrier.activeTurrets() }),
                .bays => renderer.hud_lines[2].set("BROOD {d}  LAUNCH BAYS {d}/4", .{ i + 1, carrier.activeBays() }),
                .core => renderer.hud_lines[2].set("BROOD {d}  CORE EXPOSED — DESTROY CORE", .{i + 1}),
                .crashing => renderer.hud_lines[2].set("BROOD {d}  CORE BREACHED — CLEAR IMPACT ZONE", .{i + 1}),
            }
        }
    }
    self.publishGui(renderer, minutes);
}

/// Lays out this frame's GUI in canvas units (720 tall at interface size 100%) and keeps its
/// clickable areas for the next mouse events. Art-review showcases of the city draw none.
fn publishGui(self: *App, renderer: *Renderer, minutes: u32) void {
    const width: f32 = @floatFromInt(if (renderer.width == 0) 1280 else renderer.width);
    const height: f32 = @floatFromInt(if (renderer.height == 0) 800 else renderer.height);
    self.ui_height = 720 / self.menu.settings.ui_scale;
    renderer.ui.reset(self.ui_height * width / height, self.ui_height);
    self.hit_len = 0;
    if (options.showcase != 0 and options.showcase < 18) return;
    const sandbox = &self.sandbox;
    var inspect: [Renderer.panel_capacity]Build.PanelLine = @splat(.{});
    var inspect_slices: [Renderer.panel_capacity][]const u8 = undefined;
    var inspect_count: usize = 0;
    if (self.inspecting and sandbox.seated == null and !self.uiActive()) {
        inspect_count = Build.inspect(sandbox, &inspect);
        for (inspect[0..inspect_count], inspect_slices[0..inspect_count]) |*line, *out| out.* = line.slice();
    }
    var clock: [32]u8 = undefined;
    const f = Renderer.viewRect(0, renderer.view_count);
    const ui = &renderer.ui;
    // Flight marks: where the Kestrel's nose points and the missile lock, projected on P1's view.
    var marks: [2]Screens.Hud.Mark = undefined;
    var mark_count: usize = 0;
    if (sandbox.hangar.piloting) {
        const view_rect: Screens.Rect = .{ .x = f.x * ui.width, .y = f.y * ui.height, .w = f.w * ui.width, .h = f.h * ui.height };
        const jet = sandbox.hangar.fighter.?;
        const nose = jet.body.pos.add(jet.forward().scale(400));
        if (project(self.engine.camera, view_rect, .{ nose.x, nose.y, nose.z })) |p| {
            marks[mark_count] = .{ .x = p[0], .y = p[1], .kind = .nose };
            mark_count += 1;
        }
        if (sandbox.skies.lockPosition(&sandbox.enemies)) |target| if (project(self.engine.camera, view_rect, target)) |p| {
            marks[mark_count] = .{ .x = p[0], .y = p[1], .kind = .lock, .progress = sandbox.skies.guns.lock_progress };
            mark_count += 1;
        };
    }
    var special_keys: [3][12]u8 = undefined;
    // Guest views follow P1 in join order, as published above.
    var guests: [Sandbox.max_players - 1]Screens.Hud.Guest = undefined;
    var guest_count: usize = 0;
    if (options.showcase == 0 or options.showcase >= 18) for (sandbox.guests, 0..) |g, i| if (g.active and guest_count + 1 < renderer.view_count) {
        const view = guest_count + 1;
        const r = Renderer.viewRect(view, renderer.view_count);
        guests[guest_count] = .{ .index = @intCast(i), .view = .{ .x = r.x * ui.width, .y = r.y * ui.height, .w = r.w * ui.width, .h = r.h * ui.height }, .prompt = renderer.views[view].lines[1].slice() };
        guest_count += 1;
    };
    Screens.draw(ui, &self.menu, sandbox, .{
        .view = .{ .x = f.x * ui.width, .y = f.y * ui.height, .w = f.w * ui.width, .h = f.h * ui.height },
        .clock = std.fmt.bufPrint(&clock, "DAY {d}  {d:0>2}:{d:0>2}", .{ sandbox.market.day, minutes / 60, minutes % 60 }) catch "",
        .prompt = renderer.hud_lines[1].slice(),
        .toast = renderer.hud_lines[2].slice(),
        .inspect = inspect_slices[0..inspect_count],
        .time = self.seconds,
        .seed = sandbox.seed,
        .guests = guests[0..guest_count],
        .marks = marks[0..mark_count],
        .special_keys = .{
            @import("game/Bindings.zig").keyName(self.menu.settings.bindings.key(.special_1), &special_keys[0]),
            @import("game/Bindings.zig").keyName(self.menu.settings.bindings.key(.special_2), &special_keys[1]),
            @import("game/Bindings.zig").keyName(self.menu.settings.bindings.key(.special_3), &special_keys[2]),
        },
    });
    self.hit_len = ui.hit_len;
    @memcpy(self.hits[0..ui.hit_len], ui.hits[0..ui.hit_len]);
}

pub fn stop(self: *App) void {
    self.thread.join();
    if (options.benchmark_frontier) self.reportFrontierBenchmark();
    if (self.audio) |a| a.destroy();
    if (self.loader) |l| l.destroy();
    if (self.reload) |r| r.destroy();
    if (options.reload_smoke and !self.reload_smoke_passed) @panic("Reload smoke did not reach GPU acceptance");
    defer self.sandbox.deinit();
    // The app thread has exited, so the sandbox can be read safely.
    if (self.smoke_rover_start) |origin| {
        const now = self.sandbox.physics.rigidPose(self.sandbox.machines[2].vehicle.?.rigid).?.position;
        const dx = now[0] - origin[0];
        const dz = now[2] - origin[2];
        std.log.info("Smoke drive: rover moved {d:.1} m", .{@sqrt(dx * dx + dz * dz)});
    }
}

const reload_fixture = "zig-out/reload-smoke/crate.gltf";
fn setupReload(self: *App) !void {
    const watcher = try HotReload.create(self.allocator, self.io);
    errdefer watcher.destroy();
    const manifest = try std.json.parseFromSlice(Registry.Manifest, self.allocator, @embedFile("assets.manifest"), .{});
    defer manifest.deinit();
    for (manifest.value.assets) |asset| {
        const kind: HotReload.Kind = switch (asset.kind) {
            .model => .model,
            .blueprint => .blueprint,
            else => continue,
        };
        if (asset.source.len == 0) continue;
        if (options.reload_smoke) {
            if (!std.mem.eql(u8, asset.name, "crate")) continue;
            var arena: std.heap.ArenaAllocator = .init(self.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            const source = try std.Io.Dir.cwd().readFileAlloc(self.io, asset.source, a, .limited(64 << 20));
            const meta = try std.Io.Dir.cwd().readFileAlloc(self.io, try std.fmt.allocPrint(a, "{s}.meta", .{asset.source}), a, .limited(1 << 20));
            try Save.writeFile(self.io, reload_fixture, source);
            try Save.writeFile(self.io, reload_fixture ++ ".meta", meta);
            try watcher.add(.{ .guid = asset.guid, .kind = kind, .path = reload_fixture });
        } else try watcher.add(.{ .guid = asset.guid, .kind = kind, .path = asset.source });
    }
    self.reload = watcher;
    self.reload_scan = std.Io.Timestamp.now(self.io, .awake);
    watcher.scan();
    std.log.info("Development asset reload enabled", .{});
}
fn watchMod(self: *App, pkg: *const @import("mod/Mod.zig").Package, directory: []const u8) !void {
    const module = pkg.script_path orelse return;
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const key = try std.fmt.allocPrint(a, "mod-script:{s}", .{pkg.name()});
    const path = try std.fmt.allocPrint(a, "mods/{s}/{s}", .{ directory, module });
    var names: [8][]const u8 = undefined;
    try self.reload.?.add(.{ .guid = Guid.derived(key), .kind = .script, .path = path, .mod = pkg.name(), .exports = pkg.exports(&names), .fuel = pkg.fuel, .memory_pages = pkg.memory_pages });
}
/// Runs under the render snapshot mutex. Worker-owned results become live only here.
fn pumpReload(self: *App, renderer: *Renderer) void {
    const watcher = self.reload orelse return;
    if (self.reload_scan.untilNow(self.io, .awake).nanoseconds >= std.time.ns_per_s) {
        self.reload_scan = std.Io.Timestamp.now(self.io, .awake);
        watcher.scan();
    }
    while (watcher.take()) |result| {
        var event = result;
        defer event.deinit(self.allocator);
        if (event.failure) |err| {
            std.log.warn("Reload {s} rejected: {s}; current asset retained", .{ @tagName(event.kind), @errorName(err) });
            self.report("RELOAD FAILED {s}", .{@errorName(err)});
            continue;
        }
        self.applyReload(&event) catch |err| {
            std.log.warn("Reload {s} rejected: {s}; current asset retained", .{ @tagName(event.kind), @errorName(err) });
            self.report("RELOAD FAILED {s}", .{@errorName(err)});
            continue;
        };
        self.reload_smoke_initial = true;
        std.log.info("Reloaded {s}", .{@tagName(event.kind)});
        self.report("RELOADED {s}", .{@tagName(event.kind)});
    }
    if (options.reload_smoke) self.pumpReloadSmoke(renderer) catch |err| {
        std.log.err("Reload smoke: {s}", .{@errorName(err)});
        @panic("Reload smoke failed");
    };
}
fn applyReload(self: *App, event: *HotReload.Event) !void {
    switch (event.value.?) {
        .model => |model| {
            event.value = null; // replaceModel consumes on success and failure.
            _ = try self.catalog.replaceModel(self.allocator, event.guid, model);
            self.sandbox.refreshCrateGeometry();
        },
        .blueprint => |bp| {
            _ = try self.sandbox.reloadBlueprint(self.catalog, event.guid, bp);
        },
        .script => |host| try self.sandbox.scripts.replaceFrom(host),
    }
}
fn pumpReloadSmoke(self: *App, renderer: *Renderer) !void {
    if (self.reload_smoke_passed) return;
    if (self.reload_smoke_edited) |edited| {
        const handle = self.catalog.content.crate;
        if (handle.generation != self.reload_smoke_old.generation and renderer.scene.gpuMesh(handle) != null) {
            if (self.catalog.mesh(self.reload_smoke_old) != null) return error.StaleHandleStillValid;
            const color = self.catalog.mesh(handle).?.model.materials[0].base_color[0];
            if (@abs(color - 0.26) > 0.001) return error.ReloadColorMismatch;
            const milliseconds = @as(f64, @floatFromInt(edited.untilNow(self.io, .awake).nanoseconds)) / 1e6;
            if (milliseconds > 2000) return error.ReloadTooSlow;
            self.reload_smoke_passed = true;
            std.log.info("Reload smoke passed: generation {d} -> {d}, source edit to GPU {d:.0} ms", .{ self.reload_smoke_old.generation, handle.generation, milliseconds });
        }
        return;
    }
    if (!self.reload_smoke_initial or renderer.frames < 90) return;
    const source = try std.Io.Dir.cwd().readFileAlloc(self.io, reload_fixture, self.allocator, .limited(64 << 20));
    defer self.allocator.free(source);
    if (std.mem.indexOf(u8, source, "0.86") == null) return error.FixtureColorMissing;
    const changed = try std.mem.replaceOwned(u8, self.allocator, source, "0.86", "0.26");
    defer self.allocator.free(changed);
    self.reload_smoke_old = self.catalog.content.crate;
    try Save.writeFile(self.io, reload_fixture, changed);
    self.reload_smoke_edited = std.Io.Timestamp.now(self.io, .awake);
}
