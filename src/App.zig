const std = @import("std");
const enum_compat = @import("enum_compat");
const mach = @import("mach");
const options = @import("options");
const Engine = @import("engine/Engine.zig");
const CelStyle = @import("character/CelStyle.zig");
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
const PadBindings = @import("engine/PadBindings.zig");
const PadPreset = @import("game/PadPreset.zig");
extern "c" fn hw_choose_save_json(json: [*]const u8, length: usize, suggested_name: [*:0]const u8) c_int;
extern "c" fn hw_choose_open_json(buffer: [*]u8, capacity: usize, length: *usize) c_int;
extern "c" fn hw_choose_open_glb(buffer: [*]u8, capacity: usize, length: *usize) c_int;
const HotReload = @import("asset/HotReload.zig");
const Registry = @import("asset/Registry.zig");
const Guid = @import("asset/Guid.zig");
const Loader = @import("asset/Loader.zig");
const Profile = @import("game/Profile.zig");
const MeshModifiers = @import("asset/Modifiers.zig");
const MeshModel = @import("asset/Model.zig");
const MeshTools = @import("game/MeshTools.zig");
const EditedMesh = @import("game/EditedMesh.zig");
const ToolEvent = union(enum) { press: struct { ray: MeshTools.Ray, extend: bool }, drag: MeshTools.Ray, release, control: MeshTools.Control };
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
/// Character look-dev (F3 cycles the cel style, F8 toggles ink, F10 cycles ramp/face-mask views).
cel_style: usize = options.cel_style,
cel_debug: CelStyle.Debug = @bitCast(options.cel_debug),
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
pad_connected: [4]bool = @splat(false),
menu_controller: usize = 0,
core: *mach.Core = undefined,
/// Title, pause and settings menus (settings persist in `saves/settings.json`).
menu: Menu = .{},
/// A person is playing (no smoke, benchmark or showcase): the title opens and settings save.
interactive: bool = false,
/// Serialized pre-test world, held in memory so disabling the test mode discards all session edits.
test_mode_save: ?[]u8 = null,
/// Mouse position in canvas units, and the clickable areas of the last published GUI.
pointer: [2]f32 = .{ -1, -1 },
hits: [Canvas.hit_capacity]Canvas.Hit = undefined,
hit_len: usize = 0,
ui_height: f32 = 720,
window_height: f32 = 800,
seconds: f32 = 0,
/// The P1 pad's Menu button was pressed (opens or closes the pause menu).
pad_menu: bool = false,
/// GUI scrolling: how far tall panels are scrolled, which screen it belongs to, the focus last
/// shown, and free scrolling asked for this frame (right stick, mouse wheel).
ui_scroll: f32 = 0,
ui_scroll_key: u32 = 0,
ui_scroll_focus: ?[4]f32 = null,
ui_scroll_free: f32 = 0,
/// Controller menu navigation repeat: the direction held on each pad and the wait before the
/// next step (a first step at once, then a pause, then a steady repeat).
nav_held: [4]?Menu.Key = @splat(null),
nav_wait: [4]f32 = @splat(0),
/// Frames since a combat showcase was set up (its trigger rhythm).
showcase_frame: u32 = 0,
/// Where a combat showcase holds the player (saber lunges would carry them off).
showcase_feet: [3]f32 = @splat(0),
gui_showcase_ready: bool = false,
/// The camera a fixed-view showcase set this frame, re-applied after the simulation steps.
showcase_pose: ?struct { eye: [3]f32, yaw: f32, pitch: f32 } = null,
/// Per-view blend into cave lighting (see `publish`), and the hue of the cave last entered.
underground: [5]f32 = @splat(0),
cave_hue: [5][3]f32 = @splat(.{ 0.35, 0.9, 1 }),
settings_dirty: bool = false,
/// Sound output; null when disabled (`-Daudio=false`), benchmarking, or without a device.
audio: ?*Audio = null,
/// The GUI control under the mouse last frame (hover sounds play on change).
hovered: ?u16 = null,
/// Mouse buttons held while captured: the weapon tool's primary and alternate triggers.
fire_held: bool = false,
alt_held: bool = false,
mesh_library_arena: std.heap.ArenaAllocator = undefined,
mesh_library: MeshModifiers.Document = undefined,
mesh_library_bake: ?*MeshModifiers.Bake = null,
mesh_library_preview_dirty: bool = false,
/// Vertex tools on the imported mesh. Pointer events queue here and apply in `publish`, where the
/// model may be mutated safely (the renderer reads it under the snapshot mutex).
mesh_tools: MeshTools = undefined,
tool_events: [32]ToolEvent = undefined,
tool_event_len: usize = 0,
tool_camera: ?@import("world/Camera.zig") = null,
tool_aspect: f32 = 16.0 / 9.0,
orbit_held: bool = false,
tools_showcase_done: bool = false,
/// Vertex edits made since the imported mesh was installed; they are not written to disk yet.
vertex_edits_pending: bool = false,
/// Set after a topology edit: the part library no longer matches the mesh, so its preview
/// bake is not rebuilt until a mesh is imported or installed again.
mesh_library_detached: bool = false,
/// Look for saved vertex edits once the mesh they apply to is installed.
edited_mesh_check: bool = true,
queued_character_model: ?MeshModel = null,
imported_rig_status: [96]u8 = @splat(0),
imported_rig_status_len: usize = 0,

/// Runtime content and saves are repository-root relative. If Finder or a shell starts the
/// executable from another directory, recover that root by walking up from the executable.
fn establishGameWorkingDirectory(io: std.Io) !void {
    const marker = "tools/captain/Captain.modifiers.json";
    const cwd = std.Io.Dir.cwd();
    if (cwd.access(io, marker, .{})) |_| {
        return;
    } else |_| {}

    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var path_len = try std.process.executableDirPath(io, &path_buffer);
    while (true) {
        const candidate = path_buffer[0..path_len];
        if (std.Io.Dir.openDirAbsolute(io, candidate, .{})) |dir| {
            const has_game_files = if (dir.access(io, marker, .{})) |_| true else |_| false;
            dir.close(io);
            if (has_game_files) return std.process.setCurrentPath(io, candidate);
        } else |_| {}

        const parent = std.fs.path.dirname(candidate) orelse break;
        if (parent.len == candidate.len) break;
        path_len = parent.len;
    }
    return error.GameFilesNotFound;
}

pub fn init(self: *App, core: *mach.Core, world: *World, app_mod: mach.Mod(App), renderer_mod: mach.Mod(Renderer), io: std.Io, allocator: std.mem.Allocator) !void {
    self.* = .{ .timer = mach.time.Timer.start(io), .allocator = allocator, .io = io, .core = core };
    try establishGameWorkingDirectory(io);
    core.on_exit = app_mod.id.deinit;
    self.window = try core.windows.new(.{ .title = "Heavy Water | Procedural Frontier", .width = 1280, .height = 800, .on_render = renderer_mod.id.render });
    TestWorld.configure(world, options.seed);
    try self.sandbox.init(allocator, options.seed, &world.catalog, &self.engine.camera);
    self.catalog = &world.catalog;
    self.mesh_library_arena = std.heap.ArenaAllocator.init(allocator);
    self.mesh_tools = MeshTools.init(allocator);
    const saved_library = std.Io.Dir.cwd().readFileAlloc(io, "saves/captain.modifiers.json", self.mesh_library_arena.allocator(), .limited(1 << 20)) catch null;
    const source_library_bytes = try std.Io.Dir.cwd().readFileAlloc(io, "tools/captain/Captain.modifiers.json", self.mesh_library_arena.allocator(), .limited(1 << 20));
    const source_library = try std.json.parseFromSliceLeaky(MeshModifiers.Document, self.mesh_library_arena.allocator(), source_library_bytes, .{});
    self.mesh_library = source_library;
    if (saved_library) |bytes| {
        if (std.json.parseFromSliceLeaky(MeshModifiers.Document, self.mesh_library_arena.allocator(), bytes, .{})) |override| {
            if (validMeshLibraryOverride(source_library, override)) {
                self.mesh_library = override;
                self.mesh_library_preview_dirty = true;
            } else std.log.warn("Ignoring stale or incompatible Captain component override; the file was preserved", .{});
        } else |err| std.log.warn("Ignoring invalid Captain component override ({s}); the file was preserved", .{@errorName(err)});
    }
    self.loadSavedCharacterImport();
    self.sandbox.creator.imported_doc = &self.mesh_library;
    if (options.smoke_frames > 0) self.mesh_library_preview_dirty = true;
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
        self.sandbox.profile.armor = if (options.character_showcase >= 6) .none else switch (options.character_showcase) {
            2 => .sentinel,
            3, 4, 5 => .none,
            else => .scout,
        };
        self.sandbox.profile.helmet = if (options.character_showcase == 2) .sealed else .open;
        if (options.character_showcase >= 6) {
            const looks = [_]Profile.HairStyle{ .short, .ponytail, .long, .crest, .hood, .bob, .twin_tails, .bun, .braids, .curly, .undercut, .short_curly, .curly_fade, .curly_coils, .afro, .long_curls, .textured_crop, .locs, .swept_back, .layered_shag, .nova_spike, .alien_crown, .crew_cut, .side_part, .spiky_hero, .widow_flame, .fringe_spikes, .super_flare, .flip_bob, .pilot_sweep, .big_fringe, .topknot, .spike_tail };
            const i = @min(@as(usize, options.character_showcase - 6), looks.len - 1);
            self.sandbox.profile.hair_style = looks[i];
        }
        self.sandbox.profile.outfit = 2;
        if (options.character_showcase >= 17 and options.character_showcase <= 19) {
            const armors = [_]Profile.Armor{ .gem_aegis, .starforge, .deep_prism };
            const stones = [_]Profile.Gemstone{ .ruby, .sapphire, .emerald };
            const i = options.character_showcase - 17;
            self.sandbox.profile.armor = armors[i];
            self.sandbox.profile.presentation = if (i == 1) .feminine else .masculine;
            self.sandbox.profile.gemstone = stones[i];
            self.sandbox.profile.gem_cut = if (i == 1) .star else .brilliant;
        }
        if (options.character_showcase >= 30 and options.character_showcase <= 33) {
            // The mecha armor sets over a hardsuit: mobile suit, buster, iron titan, battle plate.
            const sets = [_]Profile.Armor{ .mobile_suit, .buster, .iron_titan, .battle_plate };
            self.sandbox.profile.armor = sets[options.character_showcase - 30];
            self.sandbox.profile.clothing = .hardsuit;
            self.sandbox.profile.helmet = if (options.character_showcase == 31 or options.character_showcase == 33) .visor else .sealed;
        }
        if (options.character_showcase >= 40 and options.character_showcase <= 43) {
            // The emberwear example mod in the creator: 40 hair, face and cel style; 41 the
            // phoenix armor over a hardsuit with a visor; 42 sealed; 43 second hairstyle on the
            // exo rig with the open-faced armor.
            const Id = @import("game/CharacterContent.zig").Id;
            const p = &self.sandbox.profile;
            p.mod.set(.cel_style, Id.parse("emberwear.ink_wash").?);
            p.mod.set(.face_preset, Id.parse("emberwear.ember_eyes").?);
            p.mod.set(.hair_style, Id.parse(if (options.character_showcase == 43) "emberwear.wind_swept" else "emberwear.flame_crest").?);
            if (options.character_showcase != 40) p.mod.set(.armor_set, Id.parse("emberwear.phoenix").?);
            if (options.character_showcase == 41 or options.character_showcase == 42) p.clothing = .hardsuit;
            if (options.character_showcase == 43) p.clothing = .exo_rig;
            p.helmet = switch (options.character_showcase) {
                41 => .visor,
                42 => .sealed,
                else => .open,
            };
        }
        if (options.character_showcase == 44 or options.character_showcase == 45) {
            // Review the new fitted helmet profiles, appended hair cuts and Solar Mantle set.
            self.sandbox.profile.armor = .solar_mantle;
            self.sandbox.profile.clothing = .exo_rig;
            self.sandbox.profile.helmet = if (options.character_showcase == 44) .pilot else .recon;
            self.sandbox.profile.hair_style = if (options.character_showcase == 44) .crown_braid else .tempest_sweep;
            self.sandbox.profile.presentation = if (options.character_showcase == 44) .masculine else .feminine;
            self.sandbox.profile.gemstone = if (options.character_showcase == 44) .ruby else .sapphire;
        }
        if (options.character_showcase == 46) self.sandbox.profile.body_style = .captain_test;
        if (options.character_showcase == 47 or options.character_showcase == 48) self.importCharacterGlb(@embedFile("asset/rigged_character.glb"), false) catch |err| std.log.warn("showcase rig import failed: {s}", .{@errorName(err)});
        if (options.character_showcase == 5) {
            self.sandbox.profile.class = .synthetic;
            self.sandbox.profile.presentation = .feminine;
            self.sandbox.profile.clothing = .undersuit;
            self.sandbox.profile.accent = 0;
        }
        const tweak = options.character_tweak;
        if (tweak & 1 != 0) self.sandbox.profile.presentation = .feminine;
        if (tweak & 2 != 0) self.sandbox.profile.height = 0.9;
        if (tweak & 4 != 0) self.sandbox.profile.height = 1.1;
        if (tweak & 8 != 0) self.sandbox.profile.helmet = .open;
        if (tweak & 16 != 0) self.sandbox.profile.helmet = .sealed;
        if (tweak & 32 != 0) self.sandbox.profile.helmet = .visor;
        if (options.character_face > 0) self.sandbox.profile.face_style = @enumFromInt(@min(options.character_face - 1, enum_compat.fields(Profile.FaceStyle).len - 1));
        if (options.character_hair_color > 0) self.sandbox.profile.hair_color = @min(options.character_hair_color - 1, Profile.hair_colors.len - 1);
        self.sandbox.pose_override = switch (options.character_pose) {
            1 => .{ .action = .aim },
            2 => .{ .action = .swing, .arc = .overhead, .t = 0.35 },
            3 => .{ .action = .cast, .t = 0.5 },
            4 => .{ .action = .guard, .t = 1 },
            else => null,
        };
        self.sandbox.creator.begin(self.sandbox.profile);
        if (options.character_showcase == 46 and options.capture_frame > 0) self.sandbox.creator.openImported();
        if (options.character_showcase == 48) {
            self.sandbox.creator.openImported();
            self.sandbox.creator.vertex_tools = true;
        }
        // 47 reviews the live pose, so it needs the world view rather than the designer window.
        if (options.character_showcase == 47) {
            self.sandbox.creator.open = false;
            self.sandbox.view = .third;
        }
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
        if (self.menu.settings.max_progression_test) self.setMaxProgressionTest(true);
        self.pads.mapping = self.menu.settings.pad_mapping;
        self.show_metrics = self.menu.settings.metrics;
        self.menu.has_save = self.saveExists();
        self.menu.open(.title);
    }
    if (self.audio) |a| a.setVolumes(self.menu.settings);
}

fn validMeshLibraryOverride(source: MeshModifiers.Document, override: MeshModifiers.Document) bool {
    if ((override.format != MeshModifiers.legacy_format_version and override.format != MeshModifiers.format_version) or
        !std.mem.eql(u8, source.source_hash, override.source_hash)) return false;
    // V1 ids were authored without welding. Keep their old analysis path when loading them even
    // if the freshly generated source document uses v2 welded ids.
    if (override.format == MeshModifiers.legacy_format_version and source.format != override.format) return true;
    if (source.format != override.format or source.weld_cell != override.weld_cell or source.parts.len != override.parts.len) return false;
    for (source.parts) |part| {
        var found = false;
        for (override.parts) |candidate| if (candidate.id == part.id) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}

fn uiSound(self: *App, event: Audio.Director.Ui) void {
    if (self.audio) |a| Audio.Director.ui(a, event);
}

fn setupFrontierBenchmark(self: *App) void {
    const sb = &self.sandbox;
    const Combat = @import("game/Combat.zig");
    sb.progress.fighter = true;
    sb.kits[0].weapons = (@as(u16, 1) << @intFromEnum(Combat.WeaponKind.blaster)) |
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
    inline for (enum_compat.fields(Sandbox.BenchmarkStage)) |field| {
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
    return self.menu.screen != .none or sb.creator.open or sb.talk != null or sb.shop != null or sb.trading != null or sb.tools.platform_editor_open;
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
    if (sb.tools.platform_editor_open) return Build.platformEditorAction(sb, switch (k) {
        .left => .horizontal,
        .right => .vertical,
        .up => .up_one,
        .down => .down_one,
        .confirm => .close,
        .back => .close,
    });
    if (self.meshToolsActive()) {
        // A pad cannot aim a brush, but it can pick tools, size the brush and leave; it must not
        // reach the part library hidden behind the tool bar.
        const count: i32 = @intCast(MeshTools.tool_labels.len);
        const current: i32 = @intFromEnum(self.mesh_tools.tool);
        return switch (k) {
            .left, .right => self.meshToolControl(@enumFromInt(@as(u8, @intCast(@mod(current + @as(i32, if (k == .right) 1 else -1), count))))),
            .up => self.meshToolControl(.radius_up),
            .down => self.meshToolControl(.radius_down),
            .back => self.meshToolControl(.close),
            .confirm => {},
        };
    }
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

fn syncTravelMenu(self: *App) void {
    self.menu.travel_players = 0;
    for (0..4) |p| if (self.sandbox.travelBlocked(p) == null) {
        self.menu.travel_players |= @as(u8, 1) << @intCast(p);
    };
}

fn menuKey(self: *App, k: Menu.Key) void {
    self.syncTravelMenu();
    self.runCommand(self.menu.key(k));
}

fn runCommand(self: *App, command: Menu.Command) void {
    switch (command) {
        .none => {},
        .party_toggle => {
            const p = self.menu.hero_player;
            if (p == 0) return self.report("PLAYER 1 HOST STAYS IN THE PARTY", .{});
            if (self.sandbox.guests[p - 1].active) self.sandbox.leaveGuest(p - 1) else self.sandbox.joinGuest(p - 1);
            self.pad_guests[p - 1] = self.sandbox.guests[p - 1].active;
        },
        .party_controller => {
            const p = self.menu.hero_player;
            self.menu.nextController(p);
            self.engine.input = .{};
            self.sandbox.trigger = .{};
            for (&self.sandbox.guests) |*g| {
                g.input = .{};
                g.fire = false;
                g.alt = false;
            }
            for (&self.pads.commands) |*cmd| cmd.* = .{ .connected = cmd.connected };
        },
        .party_ranger => self.loadNextRanger(),
        .party_position => {
            const p: usize = self.menu.hero_player;
            const next = (p + 1) % 4;
            if ((p > 0 and !self.sandbox.guests[p - 1].active) or (next > 0 and !self.sandbox.guests[next - 1].active)) return self.report("JOIN BOTH PLAYERS BEFORE SWAPPING POSITIONS", .{});
            if (self.sandbox.arena.active or self.sandbox.seated != null or self.sandbox.garage.piloting != null or self.sandbox.hangar.piloting) return self.report("LEAVE VEHICLES / ARENA BEFORE SWAPPING POSITIONS", .{});
            const sb = &self.sandbox;
            if (p > 0 and next > 0) {
                std.mem.swap(Sandbox.Guest, &sb.guests[p - 1], &sb.guests[next - 1]);
            } else {
                const g = &sb.guests[(if (p == 0) next else p) - 1];
                std.mem.swap(@TypeOf(sb.player), &sb.player, &g.player);
                std.mem.swap(@TypeOf(sb.profile), &sb.profile, &g.profile);
                std.mem.swap(@TypeOf(sb.body_yaw), &sb.body_yaw, &g.body_yaw);
                std.mem.swap(@TypeOf(sb.view), &sb.view, &g.view);
                std.mem.swap(f32, &sb.walk_phase, &g.walk_phase);
                std.mem.swap(f32, &sb.walk_amount, &g.walk_amount);
                sb.release();
                sb.trading = null;
                g.trading = null;
                g.target = .none;
                std.mem.swap(@TypeOf(self.engine.camera), &self.engine.camera, &g.camera);
            }
            std.mem.swap(@TypeOf(sb.own_profiles[0]), &sb.own_profiles[p], &sb.own_profiles[next]);
            // Each player keeps their own kit and pet as they change seats.
            std.mem.swap(Sandbox.Kit, &sb.kits[p], &sb.kits[next]);
            std.mem.swap(bool, &sb.known[p], &sb.known[next]);
            std.mem.swap(?Sandbox.Pets.Pet, &sb.pets.out[p], &sb.pets.out[next]);
            std.mem.swap(@TypeOf(sb.specials.players[0]), &sb.specials.players[p], &sb.specials.players[next]);
            std.mem.swap(@TypeOf(sb.combat.arsenals[0]), &sb.combat.arsenals[p], &sb.combat.arsenals[next]);
            std.mem.swap(@TypeOf(sb.combat.vitals[0]), &sb.combat.vitals[p], &sb.combat.vitals[next]);
            for (&self.menu.controller_players) |*owner| {
                if (owner.* == p) owner.* = @intCast(next) else if (owner.* == next) owner.* = @intCast(p);
            }
            self.menu.hero_player = @intCast(next);
            self.engine.input = .{};
            self.sandbox.trigger = .{};
            for (&sb.guests) |*g| {
                g.input = .{};
                g.fire = false;
                g.alt = false;
            }
            for (&self.pads.commands) |*cmd| cmd.* = .{ .connected = cmd.connected };
        },
        .travel => {
            if (self.sandbox.travelBlocked(self.menu.hero_player)) |reason| return self.report("{s}", .{reason});
            if (!self.sandbox.fastTravel(self.menu.hero_player, self.menu.row, &self.engine.camera)) return self.report("NO SAFE ARRIVAL NEAR DESTINATION", .{});
            self.menu.open(.none);
            self.engine.input = .{};
            self.capture(self.core, true);
        },
        .@"resume" => {
            self.menu.open(.none);
            self.capture(self.core, true);
        },
        .new_game => self.newGame(),
        .play_hero => self.playHero(),
        .start_arena => self.startArena(),
        .leave_arena => {
            @import("game/Frontier.zig").leaveArena(&self.sandbox, &self.engine.camera);
            self.menu.open(.none);
            self.capture(self.core, true);
        },
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
            self.pads.mapping = self.menu.settings.pad_mapping;
            self.setMaxProgressionTest(self.menu.settings.max_progression_test);
            self.settings_dirty = true;
            if (self.audio) |a| a.setVolumes(self.menu.settings);
        },
        .pad_export => {
            var vendor: []const u8 = "";
            var product: []const u8 = "";
            for (self.pads.samples, 0..) |_, i| if (self.pads.samples[i].connected != 0) {
                vendor = std.mem.sliceTo(&self.pads.samples[i].vendor, 0);
                product = std.mem.sliceTo(&self.pads.samples[i].product, 0);
                break;
            };
            const slot = self.menu.pad_preset_slot_index;
            const name = std.fmt.allocPrint(self.allocator, "Controller preset {d}", .{slot + 1}) catch return self.report("PRESET EXPORT FAILED", .{});
            defer self.allocator.free(name);
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const preset: PadPreset.Preset = .{ .name = name, .vendor = vendor, .product = product, .mapping = self.menu.settings.pad_mapping };
            PadPreset.saveSlot(self.io, arena.allocator(), slot, preset) catch |err| return self.report("PRESET EXPORT FAILED: {s}", .{@errorName(err)});
            const json = PadPreset.toJson(arena.allocator(), preset) catch |err| return self.report("PRESET EXPORT FAILED: {s}", .{@errorName(err)});
            if (@import("builtin").os.tag == .macos) {
                const filename = std.fmt.allocPrintSentinel(arena.allocator(), "heavy-water-controller-{d}.json", .{slot + 1}, 0) catch return self.report("PRESET EXPORT FAILED", .{});
                const result = hw_choose_save_json(json.ptr, json.len, filename);
                if (result == 0) return;
                if (result < 0) return self.report("COULD NOT WRITE PRESET FILE", .{});
                self.report("PRESET EXPORTED — UPLOAD THE JSON FILE TO SHARE IT", .{});
            } else {
                self.report("PRESET EXPORTED TO saves/controller-presets/slot-{d:0>2}.json", .{slot + 1});
            }
            @memset(&self.menu.pad_preset_label, 0);
            const label_len = @min(name.len, self.menu.pad_preset_label.len - 1);
            @memcpy(self.menu.pad_preset_label[0..label_len], name[0..label_len]);
        },
        .pad_import => {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            var preset: PadPreset.Preset = undefined;
            if (@import("builtin").os.tag == .macos) {
                var bytes: [16 << 10]u8 = undefined;
                var length: usize = 0;
                const result = hw_choose_open_json(&bytes, bytes.len, &length);
                if (result == 0) return;
                if (result < 0) return self.report("PRESET FILE IS TOO LARGE OR COULD NOT BE READ", .{});
                preset = PadPreset.parse(arena.allocator(), bytes[0..length]) catch |err| return self.report("PRESET IMPORT FAILED: {s}", .{@errorName(err)});
                PadPreset.saveSlot(self.io, arena.allocator(), self.menu.pad_preset_slot_index, preset) catch |err| return self.report("PRESET SLOT SAVE FAILED: {s}", .{@errorName(err)});
            } else {
                preset = PadPreset.loadSlot(self.io, arena.allocator(), self.menu.pad_preset_slot_index) catch |err| return self.report("PRESET IMPORT FAILED: {s}", .{@errorName(err)});
            }
            self.menu.settings.pad_mapping = preset.mapping;
            self.pads.mapping = preset.mapping;
            const n = @min(preset.name.len, self.menu.pad_preset_label.len - 1);
            @memset(&self.menu.pad_preset_label, 0);
            @memcpy(self.menu.pad_preset_label[0..n], preset.name[0..n]);
            self.settings_dirty = true;
            self.report("IMPORTED CONTROLLER PRESET: {s}", .{self.menu.pad_preset_label[0..n]});
        },
    }
    // Settings are written once on leaving their screen, not on every (repeating) press.
    if (self.settings_dirty and self.menu.screen != .settings) {
        self.settings_dirty = false;
        if (self.interactive) self.menu.settings.store(self.io, self.allocator) catch |err| self.report("SETTINGS NOT SAVED {s}", .{@errorName(err)});
    }
}

/// From the title: a fresh ranger at the spawn point, starting in the creator.
/// Heroes menu: the chosen player becomes the chosen Wildkin (their own ranger is kept to come
/// back to), or returns to their own ranger.
fn playHero(self: *App) void {
    const sb = &self.sandbox;
    const p = self.menu.hero_player;
    if (p > 0 and !sb.guests[p - 1].active) return;
    const profile = if (p == 0) &sb.profile else &sb.guests[p - 1].profile;
    const player = if (p == 0) &sb.player else &sb.guests[p - 1].player;
    if (self.menu.chosenHero()) |hero| {
        if (sb.own_profiles[p] == null and profile.species == .human) sb.own_profiles[p] = profile.*;
        profile.* = Sandbox.Heroes.profile(hero);
        // Wings come with the flight kit selected.
        if (Sandbox.Heroes.winged(hero)) player.traversal = .flight;
        self.report("P{d} IS NOW {s}, {s}", .{ p + 1, Sandbox.Heroes.roster[hero].name, Sandbox.Heroes.roster[hero].title });
    } else {
        if (sb.own_profiles[p]) |own| profile.* = own;
        sb.own_profiles[p] = null;
        self.report("P{d} IS THEIR OWN RANGER AGAIN", .{p + 1});
    }
    sb.cue(.ui_confirm, null);
}

/// HERO ARENA: from the title, continue the saved game (or start one as Bolt Quill), then take
/// the party into the Starbowl.
fn startArena(self: *App) void {
    if (self.menu.base == .title) {
        if (self.menu.has_save and self.quickload()) {} else {
            self.newGame();
            self.sandbox.profile = Sandbox.Heroes.profile(0);
            self.sandbox.creator.open = false;
            self.sandbox.creator.confirmed = true;
        }
    }
    @import("game/Frontier.zig").enterArena(&self.sandbox, &self.engine.camera);
    self.menu.open(.none);
    self.capture(self.core, true);
}

fn newGame(self: *App) void {
    self.menu.open(.none);
    for (&self.sandbox.kits, 0..) |*kit, slot| {
        if (slot == 0 or self.sandbox.guests[slot - 1].active) kit.ensureStarterPet();
    }
    self.sandbox.tools.tool = .weapon;
    self.sandbox.player.mode = .walk;
    self.sandbox.resetPlayer(&self.engine.camera);
    for (self.sandbox.guests, 0..) |g, i| if (g.active) self.sandbox.respawnGuest(i);
    self.sandbox.view = if (self.menu.settings.third_person) .third else .first;
    self.sandbox.creator.begin(self.sandbox.profile);
}

/// Title backdrop: a steady, elevated downtown view above the giant Arbor canopies. Moving through
/// the canopy produced distracting foreground pop while the city streamed behind the menu.
fn titleCamera(self: *App) void {
    const layout = &self.sandbox.catalog.district;
    var center: [3]f32 = .{ 0, 0, 0 };
    for (layout.nodes) |node| center = R3.add(center, node.position);
    center = R3.scale(center, 1.0 / @as(f32, @floatFromInt(layout.nodes.len)));
    const angle: f32 = 0.6;
    const camera = &self.engine.camera;
    self.sandbox.player.mode = .fly;
    camera.position = mach.math.vec3(center[0] + @sin(angle) * 460, center[1] + 230, center[2] + @cos(angle) * 460);
    const dx = center[0] - camera.position.x();
    const dz = center[2] - camera.position.z();
    camera.yaw = std.math.atan2(dx, dz);
    camera.pitch = std.math.atan2(center[1] + 150 - camera.position.y(), @sqrt(dx * dx + dz * dz));
}

/// Mouse over the GUI: hovering selects, clicking also activates.
fn pointAt(self: *App, click: bool) void {
    self.syncTravelMenu();
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
        .menu, .setting_left, .setting_right, .planet_globe => true,
        else => false,
    };
    if (menu_area != (self.menu.screen != .none)) return;
    switch (Screens.hitArea(hit)) {
        .menu => {
            self.menu.select(row);
            if (click and self.menu.row == row) self.menuKey(.confirm);
        },
        .planet_globe => {},
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
        .creator_tab => if (click and sb.creator.open and row < Screens.creator_tab_starts.len) {
            sb.creator.field = Screens.creator_tab_starts[row];
        },
        .creator_done => if (click) self.creatorInput(.enter),
        .creator_imported => if (click and sb.creator.open) {
            sb.creator.openImported();
            self.mesh_library_preview_dirty = true;
        },
        .enemy_forge => if (click and sb.creator.open) {
            sb.creator.enemy_design_open = !sb.creator.enemy_design_open;
            self.uiSound(.confirm);
        },
        .enemy_part => if (click and sb.creator.enemy_design_open) {
            sb.creator.enemy_part = @enumFromInt(row);
        },
        .enemy_left, .enemy_right => if (click and sb.creator.enemy_design_open) {
            sb.creator.enemy_part = @enumFromInt(row);
            sb.creator.enemy_design.cycle(sb.creator.enemy_part, if (Screens.hitArea(hit) == .enemy_left) -1 else 1);
        },
        .enemy_palette_left, .enemy_palette_right => if (click and sb.creator.enemy_design_open) sb.creator.enemy_design.cyclePalette(if (Screens.hitArea(hit) == .enemy_palette_left) -1 else 1),
        .enemy_style_left, .enemy_style_right => if (click and sb.creator.enemy_design_open) sb.creator.enemy_design.cycleLayerStyle(if (Screens.hitArea(hit) == .enemy_style_left) -1 else 1),
        .imported_import_glb => if (click and sb.creator.imported_open) self.chooseAndImportCharacter(),
        .imported_filter => if (click and sb.creator.imported_open) sb.creator.cycleImportedFilter(@as(i32, row) - @as(i32, sb.creator.imported_filter)),
        .imported_part => if (click and sb.creator.imported_doc != null) {
            sb.creator.selectImported(sb.creator.importedPartForRow(row));
        },
        .imported_surface_left, .imported_surface_right => if (click) {
            sb.creator.cycleImportedSurface(if (Screens.hitArea(hit) == .imported_surface_left) -1 else 1);
            self.mesh_library_preview_dirty = true;
        },
        .imported_palette_left, .imported_palette_right => if (click) {
            sb.creator.cycleImportedPalette(if (Screens.hitArea(hit) == .imported_palette_left) -1 else 1);
            self.mesh_library_preview_dirty = true;
        },
        .imported_color => if (click) {
            sb.creator.adjustImportedColor(row / 2, if (row % 2 == 0) -0.05 else 0.05);
            self.mesh_library_preview_dirty = true;
        },
        .imported_paint => if (click) {
            sb.creator.paintImportedPart();
            self.mesh_library_preview_dirty = true;
        },
        .imported_toggle => if (click) {
            sb.creator.toggleImportedPart();
            self.mesh_library_preview_dirty = true;
        },
        .imported_undo, .imported_redo => if (click) {
            if (Screens.hitArea(hit) == .imported_undo) _ = sb.creator.key(.undo) else _ = sb.creator.key(.redo);
            self.mesh_library_preview_dirty = true;
        },
        .imported_back => if (click) {
            sb.creator.imported_open = false;
        },
        .imported_save => if (click) self.saveMeshLibrary(),
        .mesh_tool => if (click) self.meshToolControl(@enumFromInt(row)),
        .platform_editor => if (click) Build.platformEditorAction(sb, @enumFromInt(row)),
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
fn creatorKey(self: *App, key: mach.Core.KeyButtonID, shift: bool) void {
    if (self.sandbox.creator.imported_open and self.sandbox.creator.vertex_tools) {
        const tag = @tagName(key);
        const digits = [_][]const u8{ "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "zero" };
        for (digits, 0..) |d, i| if (std.mem.eql(u8, tag, d) and i < MeshTools.tool_labels.len) return self.meshToolControl(@enumFromInt(i));
        switch (key) {
            .z => self.meshToolControl(if (shift) .redo else .undo),
            .left_bracket => self.meshToolControl(.radius_down),
            .right_bracket => self.meshToolControl(.radius_up),
            .escape => self.meshToolControl(.close),
            else => {},
        }
        return;
    }
    if (self.sandbox.creator.imported_open and key == .z) {
        self.creatorInput(if (shift) .redo else .undo);
        self.mesh_library_preview_dirty = true;
        return;
    }
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
    if (self.sandbox.creator.imported_open) switch (k) {
        .left, .right => self.mesh_library_preview_dirty = true,
        .char => |c| switch (std.ascii.toLower(c)) {
            'p', 'c', 'h' => self.mesh_library_preview_dirty = true,
            else => {},
        },
        else => {},
    };
    if (self.sandbox.creator.imported_open) switch (k) {
        .char => |c| if (std.ascii.toLower(c) == 's') {
            self.saveMeshLibrary();
            return;
        },
        else => {},
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
        var problems: @import("game/CharacterContent.zig").Report = .{};
        var pkg = @import("mod/Mod.zig").loadReported(self.allocator, entry.name, Files{ .dir = sub, .io = self.io }, &problems) catch |err| {
            std.log.warn("mod {s} rejected: {s}", .{ entry.name, @errorName(err) });
            for (problems.slice()) |*d| {
                var line: [320]u8 = undefined;
                std.log.warn("mod {s}: {s}", .{ entry.name, d.format(&line) });
            }
            continue;
        };
        defer pkg.deinit();
        self.sandbox.installMod(&pkg) catch |err| {
            std.log.warn("mod {s} not installed: {s}", .{ entry.name, @errorName(err) });
            continue;
        };
        if (self.reload != null and !options.reload_smoke) self.watchMod(&pkg, entry.name) catch |err| std.log.warn("mod watch {s}: {s}", .{ entry.name, @errorName(err) });
        std.log.info("Mod {s} {d}.{d}.{d}: {d} blueprints, {d} scripts, {d} character entries", .{ pkg.name(), pkg.version.major, pkg.version.minor, pkg.version.patch, pkg.blueprint_count, pkg.export_count, pkg.characterCount() });
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

/// Look-dev keys for artists tuning character shading. True when `key` was one of them.
fn celKey(self: *App, key: mach.Core.KeyButtonID) bool {
    switch (key) {
        .f3 => self.cel_style = (self.cel_style + 1) % CelStyle.presets.len,
        .f8 => self.cel_debug.outline_off = !self.cel_debug.outline_off,
        .f10 => {
            // Off, ramp bands, face shadow mask.
            const view: u2 = @as(u2, @intFromBool(self.cel_debug.ramp_view)) + 2 * @as(u2, @intFromBool(self.cel_debug.face_mask_view));
            const next = (view + 1) % 3;
            self.cel_debug.ramp_view = next == 1;
            self.cel_debug.face_mask_view = next == 2;
        },
        else => return false,
    }
    std.log.info("Character look: style {s}, ink {s}, view {s}", .{ CelStyle.presets[self.cel_style].name, if (self.cel_debug.outline_off) "off" else "on", if (self.cel_debug.ramp_view) "ramp" else if (self.cel_debug.face_mask_view) "face mask" else "normal" });
    return true;
}

pub fn update(self: *App, core: *mach.Core) void {
    var events = core.events(.default);
    while (events.next()) |event| switch (event) {
        .close => core.exit(),
        .key_repeat => |key| if (self.uiActive()) {
            // Held arrows scroll lists; held backspace erases the name.
            if (self.sandbox.creator.open and self.menu.screen == .none) {
                if (key.key == .backspace or key.key == .left or key.key == .right or key.key == .up or key.key == .down) self.creatorKey(key.key, false);
            } else if (key.key == .up or key.key == .down or key.key == .left or key.key == .right) self.uiNav(self.navKey(key.key).?);
        },
        .key_press => |key| if (self.celKey(key.key)) {
            // Handled: character look-dev keys work everywhere, including the creator.
        } else if (self.menu.screen == .controls and self.menu.capturing) {
            self.runCommand(self.menu.bindKey(key.key));
        } else if (self.menu.screen == .none and self.sandbox.creator.open) self.creatorKey(key.key, key.mods.shift) else if (self.uiActive()) {
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
        } else if (key.key == .o and self.sandbox.tools.tool == .build) {
            Build.openPlatformEditor(&self.sandbox);
        } else if (key.key == .escape) {
            self.menu.open(.pause);
            self.menu.hero_player = 0;
        } else if (self.menu.settings.bindings.action(key.key)) |action| switch (action) {
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
            .inspect => {
                self.actions.interact = true;
                if (self.sandbox.target == .structure) self.inspecting = !self.inspecting;
            },
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
            .left => {
                self.fire_held = false;
                self.menu.globe_dragging = false;
                if (self.meshToolsActive()) self.queueToolEvent(.release);
            },
            .right => {
                self.alt_held = false;
                self.orbit_held = false;
            },
            else => {},
        },
        .mouse_press => |mouse| if (self.uiActive()) {
            if (mouse.button == .left and self.menu.screen == .world_map and self.menu.map_zoom == 3 and self.hitUnderPointer() != null and Screens.hitArea(self.hitUnderPointer().?) == .planet_globe) {
                self.menu.globe_dragging = true;
            } else if (self.meshToolsActive() and self.hitUnderPointer() == null) {
                // Over the 3D view, not the panel: the press goes to the active tool.
                switch (mouse.button) {
                    .left => if (self.pointerRay()) |ray| self.queueToolEvent(.{ .press = .{ .ray = ray, .extend = mouse.mods.shift } }),
                    .right => self.orbit_held = true,
                    else => {},
                }
            } else if (mouse.button == .left) self.pointAt(true);
        } else switch (mouse.button) {
            .left => if (self.captured) {
                self.fire_held = true;
                self.actions.interact = true;
            } else {
                // The click that starts trackpad/mouse aiming is also a primary click. This keeps
                // laptop shooting responsive instead of requiring a second click after capture.
                self.capture(core, true);
                self.fire_held = true;
                self.actions.interact = true;
            },
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
        .mouse_scroll => |wheel| if (self.uiActive()) {
            if (self.meshToolsActive() and self.hitUnderPointer() == null) {
                self.mesh_tools.zoom(@floatCast(wheel.yoffset));
            } else self.ui_scroll_free -= wheel.yoffset * 24;
        },
        .mouse_motion => |motion| {
            // Window points to canvas units (the canvas is `ui_height` units tall).
            const scale = self.ui_height / @max(self.window_height, 1);
            const previous = self.pointer;
            self.pointer = .{ @as(f32, @floatCast(motion.pos.x)) * scale, @as(f32, @floatCast(motion.pos.y)) * scale };
            if (self.menu.globe_dragging and self.menu.screen == .world_map) {
                self.menu.rotateGlobe(self.pointer[0] - previous[0], self.pointer[1] - previous[1]);
            } else if (self.meshToolsActive()) {
                if (self.orbit_held) self.mesh_tools.orbit(self.pointer[0] - previous[0], self.pointer[1] - previous[1]) else if (self.pointerRay()) |ray| self.queueToolEvent(.{ .drag = ray });
            }
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
    self.menu.heroes_unlocked = self.sandbox.progress.heroes;
    self.menu.arena_active = self.sandbox.arena.active;
    self.syncTravelMenu();
    self.menu.players_present = 1;
    for (self.sandbox.guests, 1..) |g, i| if (g.active) {
        self.menu.players_present |= @as(u8, 1) << @intCast(i);
    };
    self.pollPads();
    if (self.pad_menu) {
        self.pad_menu = false;
        // Start: begins from the title (the highlighted CONTINUE or NEW GAME), finishes the
        // creator, pauses during play, and resumes from the pause menu.
        if (self.menu.screen == .title) {
            self.uiNav(.confirm);
        } else if (self.menu.screen == .none and self.sandbox.creator.open) {
            self.uiNav(.confirm);
        } else if (self.menu.screen == .none and !self.uiActive()) self.menu.open(.pause) else if (self.menu.screen == .pause) self.menuKey(.back);
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
        // Menus never advance gameplay. The title can still render the city, but combat, pickups
        // and the day cycle wait until a player enters the world.
        if (!paused and !title) {
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
    // Every sim step moves the camera to the player's eye; a fixed showcase view must survive
    // that, or a capture depends on whether its frame happened to step the simulation.
    if (options.showcase > 0) if (self.showcase_pose) |pose| {
        self.engine.camera.position = mach.math.vec3(pose.eye[0], pose.eye[1], pose.eye[2]);
        self.engine.camera.yaw = pose.yaw;
        self.engine.camera.pitch = pose.pitch;
    };
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
    if (self.menu.screen == .pad_controls) if (self.menu.pad_capturing_action) |action| {
        for (self.pads.button_edges, 0..) |edges, controller| if (edges != 0) {
            const physical = @as(u8, @intCast(@ctz(edges)));
            self.menu.settings.pad_mapping.buttons[@intFromEnum(action)] = physical;
            self.menu.pad_capturing_action = null;
            self.pads.commands[controller] = .{ .connected = self.pads.commands[controller].connected };
            self.runCommand(.settings_changed);
            self.report("{s} BOUND TO {s}", .{ PadBindings.actionName(action), PadBindings.buttonName(physical) });
            break;
        };
    };
    for (&self.pads.commands, 0..) |*cmd, c| {
        const p = @as(usize, self.menu.controller_players[c]);
        if (cmd.connected and !self.pad_connected[c]) {
            var label: [128]u8 = undefined;
            self.report("P{d} CONTROLLER FOUND: {s}", .{ p + 1, self.pads.deviceLabel(c, &label) });
        }
        self.pad_connected[c] = cmd.connected;
        self.menu.controllers_connected[c] = cmd.connected;
        if (cmd.respawn and self.menu.base != .title and (p == 0 or self.sandbox.guests[p - 1].active)) {
            self.menu.open(.pause);
            self.menu.hero_player = @intCast(p);
            self.menu.open(.player);
            self.menu_controller = c;
        }
        cmd.respawn = false;
        if (p == 0) {
            if (cmd.join) {
                self.pad_menu = true;
                self.menu.hero_player = 0;
                self.menu_controller = c;
            }
            cmd.join = false;
            if (!self.uiActive()) self.engine.input.merge(cmd.input);
            continue;
        }
        const g = p - 1;
        if (!cmd.connected) {
            self.sandbox.guests[g].input = .{};
            self.sandbox.guests[g].fire = false;
            self.sandbox.guests[g].alt = false;
            self.sandbox.guests[g].interact = false;
            self.sandbox.guests[g].special = @splat(false);
        }
        if (cmd.join) {
            self.menu_controller = c;
            if (!self.sandbox.guests[g].active) self.sandbox.joinGuest(g);
            if (self.menu.base != .title) {
                self.menu.open(.pause);
                self.menu.open(.party);
                self.menu.hero_player = @intCast(p);
            }
            self.pad_guests[g] = self.sandbox.guests[g].active;
            self.report("P{d} {s}", .{ p + 1, if (self.pad_guests[g]) "JOINED" else "LEFT" });
        }
        if (cmd.respawn and self.sandbox.guests[g].active) self.sandbox.respawnGuest(g);
        cmd.join = false;
        cmd.respawn = false;
    }
}

/// Hands each pad's latest command to its player for the coming fixed step.
fn routePads(self: *App) void {
    const navigating = self.uiActive();
    for (self.pads.commands, 0..) |cmd, c| {
        const p = @as(usize, self.menu.controller_players[c]);
        if (!cmd.connected) continue;
        if (navigating) {
            if (!self.uiActive()) continue;
            if (c == self.menu_controller or p == 0) {
                // A pad driving P1 through any GUI: the D-pad or left stick moves (held, it
                // repeats), A/X chooses, B goes back, and the right stick scrolls tall panels.
                self.padNavigate(c, cmd);
                if (cmd.interact) self.uiNav(.confirm);
                if (cmd.input.dodge and self.uiActive()) self.uiNav(.back);
                self.ui_scroll_free += cmd.input.look_y * 900 * Time.fixed_dt;
            }
            continue;
        }
        if (p == 0) {
            self.engine.camera.turn(cmd.input.look_x, cmd.input.look_y, Time.fixed_dt);
            // P1 shares the same direct energy/saber path as the guests.
            self.sandbox.padWeapons(cmd.fire, cmd.alt);
            self.actions.interact = self.actions.interact or cmd.interact;
            if (cmd.interact and self.sandbox.target == .structure) self.inspecting = !self.inspecting;
            // D-pad edges reach gameplay only after the UI routing branch above. Left/right
            // cycle owned weapons; up/down choose the same three specials as keyboard Z/C/H.
            self.actions.next_item = self.actions.next_item or cmd.left or cmd.right;
            self.actions.special_1 = self.actions.special_1 or (cmd.up and !cmd.alt);
            self.actions.special_2 = self.actions.special_2 or cmd.down;
            self.actions.special_3 = self.actions.special_3 or (cmd.up and cmd.alt);
            if (self.sandbox.hangar.piloting and cmd.interact) self.actions.leave_jet = true;
            self.actions.toggle_view = self.actions.toggle_view or cmd.view;
            continue;
        }
        if (!self.sandbox.guests[p - 1].active) continue;
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

/// Menu movement from one pad: D-pad held, else the left stick pushed past 0.6 (the stronger
/// axis wins). A new direction steps at once; held, it waits 0.38 s, then steps every 0.09 s.
fn padNavigate(self: *App, c: usize, cmd: Gamepads.Command) void {
    var dir: ?Menu.Key = null;
    if (cmd.held[0] or cmd.up) dir = .up else if (cmd.held[1] or cmd.down) dir = .down else if (cmd.held[2] or cmd.left) dir = .left else if (cmd.held[3] or cmd.right) dir = .right;
    if (dir == null) {
        const x = cmd.input.right;
        const y = cmd.input.forward;
        if (@max(@abs(x), @abs(y)) > 0.6) dir = if (@abs(y) >= @abs(x)) (if (y > 0) .up else .down) else (if (x > 0) .right else .left);
    }
    const now = dir orelse {
        self.nav_held[c] = null;
        return;
    };
    if (self.nav_held[c] != now) {
        self.nav_held[c] = now;
        self.nav_wait[c] = 0.38;
        return self.uiNav(now);
    }
    self.nav_wait[c] -= Time.fixed_dt;
    if (self.nav_wait[c] <= 0) {
        self.nav_wait[c] = 0.09;
        self.uiNav(now);
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

/// The flora review runs in the open land east and south of the city hub.
fn floraReviewOrigin() [3]f32 {
    const spawn = @import("game/Sandbox.zig").spawn;
    return .{ spawn[0] + 2500, 0, spawn[2] - 140 };
}

/// `-Dshowcase=N`: fixed city viewpoints and mesh lineups for screenshots and art review.
fn showcase(self: *App) void {
    const District = @import("procedural/District.zig");
    const layout = &self.sandbox.catalog.district;
    const camera = &self.engine.camera;
    const v = options.showcase;
    self.show_metrics = false;
    if ((v >= 18 and v <= 35) or (v >= 37 and v <= 46) or (v >= 48 and v <= 57) or v == 60 or v == 68 or v == 69 or v == 77 or v == 80 or v == 81 or v == 82) return self.guiShowcase(v);
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
    } else if (v == 61) {
        const Sandbox_ = @import("game/Sandbox.zig");
        const Terrain = @import("procedural/Terrain.zig");
        const armor_sets = [_]Profile.Armor{ .gem_aegis, .starforge, .deep_prism };
        const stones = [_]Profile.Gemstone{ .ruby, .sapphire, .emerald };
        for (&self.sandbox.guests, 0..) |*g, i| {
            if (!g.active) self.sandbox.joinGuest(i);
            g.profile.armor = armor_sets[i];
            g.profile.gemstone = stones[i];
            g.profile.gem_cut = if (i == 1) .star else .brilliant;
            g.profile.presentation = if (i == 1) .feminine else .masculine;
            g.profile.clothing = .field_jacket;
            g.profile.helmet = .open;
            g.profile.outfit = 5;
            const x = Sandbox_.spawn[0] + (@as(f32, @floatFromInt(i)) - 1) * 1.15;
            const z = Sandbox_.spawn[2] + 3;
            g.player.feet = .{ x, Terrain.surface(self.sandbox.seed, x, z).height, z };
            g.player.velocity = .{ 0, 0, 0 };
            g.camera.yaw = 0;
            g.view = .first;
        }
        const ground = Terrain.surface(self.sandbox.seed, Sandbox_.spawn[0], Sandbox_.spawn[2] + 3).height;
        target = .{ Sandbox_.spawn[0], ground + 0.92, Sandbox_.spawn[2] + 3 };
        eye = .{ Sandbox_.spawn[0] + 0.2, ground + 1.22, Sandbox_.spawn[2] - 1.6 };
    } else if (v == 16 or v == 17) {
        // Armor lineup: compare coverage tiers in the same neutral outfit and open-face pose.
        const Sandbox_ = @import("game/Sandbox.zig");
        const clothing = [_]Profile.Clothing{ .exo_rig, .hardsuit, .vanguard };
        for (&self.sandbox.guests, 0..) |*g, i| {
            if (!g.active) {
                self.sandbox.joinGuest(i);
                g.profile.clothing = clothing[i];
                g.profile.armor = .none;
                g.profile.helmet = .open;
                g.profile.outfit = 5;
            }
            const x = Sandbox_.spawn[0] + (@as(f32, @floatFromInt(i)) - 1) * 1.25;
            const z = Sandbox_.spawn[2] + 3;
            g.player.feet = .{ x, @import("procedural/Terrain.zig").surface(self.sandbox.seed, x, z).height, z };
            g.player.velocity = .{ 0, 0, 0 };
            g.camera.yaw = std.math.pi;
            g.view = .first;
        }
        const ground = @import("procedural/Terrain.zig").surface(self.sandbox.seed, Sandbox_.spawn[0], Sandbox_.spawn[2] + 3).height;
        target = .{ Sandbox_.spawn[0], ground + 0.95, Sandbox_.spawn[2] + 3 };
        eye = .{ Sandbox_.spawn[0] + 0.25, ground + 1.3, Sandbox_.spawn[2] + 0.45 };
        // 17: a three-quarter close-up of the hardsuit.
        if (v == 17) eye = .{ Sandbox_.spawn[0] + 0.9, ground + 1.35, Sandbox_.spawn[2] + 1.35 };
    } else if (v == 58 or v == 59) {
        // The pets in a row on the open meadow by the spawn (where the Wildkin line up), looking
        // out toward the mountains: 58 in their Hive collars, 59 freed.
        const Sandbox_ = @import("game/Sandbox.zig");
        const Terrain = @import("procedural/Terrain.zig");
        const pets = &self.sandbox.pets;
        const base: [3]f32 = .{ Sandbox_.spawn[0] + 30, 0, Sandbox_.spawn[2] - 40 };
        const yaw: f32 = 2.6;
        const fwd: [3]f32 = .{ @sin(yaw), 0, @cos(yaw) };
        const right: [3]f32 = .{ -@cos(yaw), 0, @sin(yaw) };
        for (&pets.spots, 0..) |*spot, i| {
            const x = base[0] + fwd[0] * 5 + right[0] * (@as(f32, @floatFromInt(i)) - 1.5) * 2.1;
            const z = base[2] + fwd[2] * 5 + right[2] * (@as(f32, @floatFromInt(i)) - 1.5) * 2.1;
            spot.* = .{ .position = .{ x, Terrain.surface(self.sandbox.seed, x, z).height, z }, .yaw = yaw + std.math.pi };
        }
        pets.placed = true;
        pets.showcase_free = v == 59;
        const ground = Terrain.surface(self.sandbox.seed, base[0], base[2]).height;
        eye = .{ base[0], ground + 1.7, base[2] };
        target = .{ base[0] + fwd[0] * 5, ground + 0.9, base[2] + fwd[2] * 5 };
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
    } else if (v == 71 or v == 72 or v == 73 or v == 74 or v == 75) {
        // Nature upgrade baselines: sparse floor cover, connected forest silhouettes, and
        // terrain relief at a fixed seed and location. Keep the player grounded at the stage
        // origin so streamed scatter and the camera use the same terrain samples each run.
        const Terrain = @import("procedural/Terrain.zig");
        const stage = floraReviewOrigin();
        const ground = Terrain.surface(self.sandbox.seed, stage[0], stage[2]).height;
        self.sandbox.player.feet = .{ stage[0], ground, stage[2] };
        self.sandbox.player.velocity = @splat(0);
        if (v == 71) {
            // Stand back from the random canopy scatter and look down across the floor plants.
            target = .{ stage[0] + 124, ground + 0.2, stage[2] - 24 };
            eye = .{ stage[0] + 124, ground + 11, stage[2] + 4 };
        } else if (v == 72) {
            target = .{ stage[0], ground + 18, stage[2] - 80 };
            eye = .{ stage[0] + 150, ground + 160, stage[2] + 220 };
        } else if (v == 73) {
            target = .{ stage[0], ground + 10, stage[2] };
            eye = .{ stage[0] + 220, ground + 240, stage[2] + 220 };
        } else {
            target = .{ stage[0], ground + 65, stage[2] };
            eye = .{ stage[0] + 95, ground + 82, stage[2] + 185 };
        }
    } else if (v == 62) {
        const Terrain = @import("procedural/Terrain.zig");
        const stage = floraReviewOrigin();
        const ground = Terrain.surface(self.sandbox.seed, stage[0], stage[2]).height;
        self.sandbox.player.feet = .{ stage[0], ground, stage[2] };
        self.sandbox.player.velocity = .{ 0, 0, 0 };
        // Frame the trunks and crowns together; the old ground-level view looked past the
        // staged trees and only showed the empty clearing beneath them.
        target = .{ stage[0] + 28, ground + 75, stage[2] };
        eye = .{ stage[0] + 28, ground + 98, stage[2] + 430 };
    } else if (v == 63) {
        const Terrain = @import("procedural/Terrain.zig");
        const stage = floraReviewOrigin();
        const x = stage[0];
        const z = stage[2];
        const ground = Terrain.surface(self.sandbox.seed, x, z).height;
        self.sandbox.player.mode = .walk;
        self.sandbox.player.feet = .{ x, ground, z };
        self.sandbox.player.velocity = @splat(0);
        self.sandbox.player.grounded = true;
        self.sandbox.view = .third;
        self.sandbox.body_yaw = 0;
        target = .{ x, ground + 0.92, z };
        eye = .{ x, ground + 1.5, z + 4.4 };
    } else if (v == 64 or v == 65) {
        const node_id: usize = if (v == 64) 2 else 4;
        const span = District.trunkSpur(layout, node_id);
        const entrance = span.point(-0.32);
        const inside = span.point(0.72);
        eye = .{ entrance[0], entrance[1] + 4.1, entrance[2] };
        target = .{ inside[0], inside[1] + 4.1, inside[2] };
    } else if (v == 78) {
        target = .{ 0, 1.3, 0 };
        eye = .{ 13, 10, 19 };
    } else if (v == 85) {
        const Region = @import("world/Region.zig");
        const Terrain = @import("procedural/Terrain.zig");
        const arrival = Region.antarctica.arrival;
        const ground = Terrain.surface(self.sandbox.seed, arrival[0], arrival[1]).height;
        self.sandbox.player.mode = .fly;
        self.sandbox.player.feet = .{ arrival[0], ground + 4, arrival[1] };
        target = .{ arrival[0], ground + 17, arrival[1] };
        eye = .{ arrival[0] + 175, ground + 115, arrival[1] + 235 };
    } else if (v == 86) {
        const Region = @import("world/Region.zig");
        const Terrain = @import("procedural/Terrain.zig");
        const arrival = Region.antarctica.arrival;
        const ground = Terrain.surface(self.sandbox.seed, arrival[0] + 116, arrival[1]).height;
        self.sandbox.player.mode = .fly;
        self.sandbox.player.feet = .{ arrival[0], ground + 4, arrival[1] };
        target = .{ arrival[0] + 116, ground + 5, arrival[1] };
        eye = .{ arrival[0] + 20, ground + 27, arrival[1] + 125 };
    } else if (v == 83 or v == 84) {
        const Terrain = @import("procedural/Terrain.zig");
        const origin = Sandbox.spawn;
        const ground = Terrain.surface(self.sandbox.seed, origin[0], origin[2]).height;
        self.sandbox.creator.enemy_design.layer_style = if (v == 83) .insectoid_carapace else .brushed_metal;
        self.sandbox.creator.enemy_design.palette = if (v == 83) .amber_carapace else .silver;
        self.sandbox.enemies.units[0] = .{ .kind = .scalari_titan, .nest = 0, .position = .{ origin[0], ground, origin[2] }, .health = 5000, .orbit = 0 };
        self.sandbox.player.feet = .{ origin[0] + 1000, ground, origin[2] + 1000 };
        self.sandbox.player.mode = .fly;
        target = .{ origin[0], ground + 2.5, origin[2] };
        eye = .{ origin[0] + 1.8, ground + 4.6, origin[2] + 14 };
    } else if (v == 70) {
        const origin = District.testOrigin(self.sandbox.seed);
        target = .{ origin[0], origin[1] + 185, origin[2] };
        eye = .{ origin[0] + 290, origin[1] + 250, origin[2] + 310 };
    } else if (v == 47) {
        // Scalari fleet art review: two capital ships behind three dragon-armored fighters.
        target = .{ 0, 480, -45 };
        eye = .{ 0, 680, 470 };
    } else if (v == 66) {
        // Habitat and Mother art review: frame their full cylindrical silhouettes in space.
        target = .{ 0, 790, 0 };
        eye = .{ 760, 920, 520 };
    } else if (v == 67) {
        // Review the new Wilds architecture as a clean lineup over the seeded terrain.
        const Terrain = @import("procedural/Terrain.zig");
        const ground = Terrain.surface(self.sandbox.seed, 0, 0).height;
        target = .{ 0, ground + 4.5, 0 };
        eye = .{ 0, ground + 18, 66 };
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
    const dusk = v == 8 or (v >= 10 and v <= 15) or v == 62 or v == 64 or v == 65;
    self.sandbox.tick = if (v == 85 or v == 86) 0 else if (v == 62 or v == 64 or v == 65) @import("engine/Sky.zig").day_ticks * 65 / 100 else if (dusk) @import("engine/Sky.zig").day_ticks * 52 / 100 else @import("engine/Sky.zig").day_ticks * 15 / 100;
    camera.position = mach.math.vec3(eye[0], eye[1], eye[2]);
    const dx = target[0] - eye[0];
    const dz = target[2] - eye[2];
    camera.yaw = std.math.atan2(dx, dz);
    camera.pitch = std.math.atan2(target[1] - eye[1], @sqrt(dx * dx + dz * dz));
    self.showcase_pose = .{ .eye = eye, .yaw = camera.yaw, .pitch = camera.pitch };
}

/// `-Dshowcase=18..26`: GUI screens for review. 18 title, 19 conversation, 20 upgrades,
/// 21 market shop, 22 wardrobe, 23 customization, 24 pause, 25 settings, 26 HUD,
/// 27 four-player split screen with a guest trading, 28 controls while rebinding,
/// 29 the garage with all three hover cars, 30 a Hive nest under attack, 31 the fabricator,
/// 32 the Skimmer in flight, 33 the Kestrel on its pad, 34 a dogfight by a Brood carrier,
/// 35 the carrier from above, 45 a live missile lock for HUD capture, 47 the Scalari fleet lineup,
/// and 60 the Rootdeep weapon temples.
fn guiShowcase(self: *App, v: u32) void {
    const sb = &self.sandbox;
    self.engine.input = .{};
    sb.tick = @import("engine/Sky.zig").day_ticks * 15 / 100;
    if (v == 18) {
        if (self.menu.screen == .none) self.menu.open(.title);
        self.titleCamera();
        return;
    }
    if (v == 60) {
        const shrine = sb.shrines[0];
        const origin = shrine.origin;
        const length = @import("procedural/Shrine.zig").length(shrine.generated.puzzle);
        const eye: [3]f32 = .{ origin[0] + 24, origin[1] + 12, origin[2] - 30 };
        const target: [3]f32 = .{ origin[0], origin[1] + 5, origin[2] + length * 0.5 };
        const dx = target[0] - eye[0];
        const dy = target[1] - eye[1];
        const dz = target[2] - eye[2];
        self.engine.camera.position = mach.math.vec3(eye[0], eye[1], eye[2]);
        self.engine.camera.yaw = std.math.atan2(dx, dz);
        self.engine.camera.pitch = std.math.atan2(dy, @sqrt(dx * dx + dz * dz));
        sb.player.mode = .fly;
        return;
    }
    if (v == 77) {
        // Inside the first Rootdeep shrine, looking down the walkway toward the vault.
        const origin = sb.shrines[0].origin;
        const eye: [3]f32 = .{ origin[0] - 0.5, origin[1] + 2.2, origin[2] + 1.0 };
        self.showcase_pose = .{ .eye = eye, .yaw = 0, .pitch = 0.04 };
        self.engine.camera.position = mach.math.vec3(eye[0], eye[1], eye[2]);
        self.engine.camera.yaw = 0;
        self.engine.camera.pitch = 0.04;
        sb.player.mode = .fly;
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
    // 37–40 and 69: combat art reviews keep a trooper (or a squad) in front of the player.
    if (((v >= 37 and v <= 40) or v == 69) and self.gui_showcase_ready) {
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
            69 => .{ .fire = f % 90 < 66 },
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
    sb.kits[0].wallet = .{ .scrap = 182, .parts = 6, .kits = .{ 1, 0, 2 } };
    sb.kits[0].levels = .{ 1, 0, 2, 0, 1, 0 };
    sb.kits[0].buySuit(.exo_rig) catch {};
    sb.kits[0].wallet.scrap = 182;
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
        68 => {
            self.menu.open(.pause);
            self.menu.open(.world_map);
        },
        80 => {
            sb.player.mode = .fly;
            sb.tools.tool = .build;
            sb.tools.preview = null;
            Build.openPlatformEditor(sb);
            const view_stall = sb.stallPosition(0);
            const eye: [3]f32 = .{ view_stall[0], view_stall[1] + 3, view_stall[2] - 3 };
            self.showcase_pose = .{ .eye = eye, .yaw = 0, .pitch = -0.32 };
            self.engine.camera.position = mach.math.vec3(eye[0], eye[1], eye[2]);
            self.engine.camera.yaw = 0;
            self.engine.camera.pitch = -0.32;
        },
        81 => {
            self.menu.open(.pause);
            self.menu.open(.world_map);
            self.menu.map_zoom = 3;
            self.menu.row = 0;
            self.menu.map_destination = 0;
        },
        82 => {
            sb.creator.begin(sb.profile);
            sb.creator.enemy_design_open = true;
            sb.creator.enemy_design.layer_style = .insectoid_carapace;
            sb.player.mode = .fly;
            const facing: [3]f32 = .{ @sin(self.engine.camera.yaw), 0, @cos(self.engine.camera.yaw) };
            for (&sb.enemies.units) |*slot| if (slot.*) |*unit| if (unit.kind == .scalari_titan) {
                unit.position = .{ sb.player.feet[0] + facing[0] * 11, sb.player.feet[1], sb.player.feet[2] + facing[2] * 11 };
                unit.yaw = self.engine.camera.yaw + std.math.pi;
                break;
            };
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
            sb.kits[0].weapons = 0b10;
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
        37, 38, 39, 40, 69 => {
            const kind: @import("game/Combat.zig").WeaponKind = switch (v) {
                37 => .beam_saber,
                38 => .sniper_rifle,
                39 => .machine_gun,
                69 => .blaster,
                else => .heavy_rifle,
            };
            sb.kits[0].weapons = @as(u16, 1) << @intCast(@intFromEnum(kind));
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
        48, 49, 50, 51 => {
            // Wildkin lineups, eight at a time, facing the camera on the plaza.
            sb.progress.heroes = 0;
            sb.encounters = @splat(null);
            sb.view = .first;
            // On the open meadow by the spawn, looking out toward the mountains.
            const ground = @import("procedural/Terrain.zig").surface(sb.seed, Sandbox.spawn[0] + 30, Sandbox.spawn[2] - 40).height;
            sb.player.feet = .{ Sandbox.spawn[0] + 30, ground, Sandbox.spawn[2] - 40 };
            self.engine.camera.yaw = 2.6;
            const yaw = self.engine.camera.yaw;
            const fwd: [3]f32 = .{ @sin(yaw), 0, @cos(yaw) };
            const right: [3]f32 = .{ -@cos(yaw), 0, @sin(yaw) };
            for (0..8) |i| {
                const hero = (v - 48) * 8 + i;
                if (hero >= Sandbox.Heroes.count) break;
                const at = R3.add(sb.player.feet, R3.add(R3.scale(fwd, 7.5), R3.scale(right, (@as(f32, @floatFromInt(i)) - 3.5) * 1.05)));
                sb.encounters[hero] = .{ .hero = @intCast(hero), .position = .{ at[0], @import("procedural/Terrain.zig").surface(sb.seed, at[0], at[2]).height, at[2] }, .yaw = yaw + std.math.pi };
            }
            self.engine.camera.pitch = -0.08;
        },
        54, 55 => {
            for (0..3) |i| sb.joinGuest(i);
            self.menu.open(.pause);
            self.menu.open(if (v == 54) .party else .world_map);
            self.menu.hero_player = 2;
        },
        56 => {
            // Interface size 150%: the Heroes screen is taller than the window and scrolls to
            // its focused BACK button.
            self.menu.settings.ui_scale = 1.5;
            sb.progress.heroes = Sandbox.Heroes.starters();
            self.menu.open(.pause);
            self.menu.open(.heroes);
            self.menu.row = Menu.heroes_back;
        },
        57 => {
            // Interface size 150%: the pause menu scrolled to its last item.
            self.menu.settings.ui_scale = 1.5;
            self.menu.open(.pause);
            self.menu.row = @intCast(Menu.pause_items.len - 1);
        },
        52 => {
            sb.progress.heroes = Sandbox.Heroes.starters() | 0b1011_0110_0000;
            self.menu.open(.pause);
            self.menu.open(.heroes);
            self.menu.row = Menu.heroes_first + 6;
        },
        53 => {
            sb.profile = Sandbox.Heroes.profile(0);
            sb.view = .third;
            @import("game/Frontier.zig").enterArena(sb, &self.engine.camera);
            self.engine.camera.pitch = -0.25;
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
            sb.kits[0].inventory = .{ 14, 3, 9, 2 };
            sb.shop = .{ .kind = .fabricate, .tab = 0, .row = 0 };
        },
        28 => {
            self.menu.open(.pause);
            self.menu.open(.controls);
            _ = self.menu.settings.bindings.bind(.stomp, .k) catch {};
            self.menu.row = @intFromEnum(@import("game/Bindings.zig").Action.grapple);
            self.menu.capturing = true;
        },
        46 => {
            self.menu.open(.pause);
            self.menu.open(.controls);
            self.menu.open(.pad_controls);
            self.menu.row = 0;
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

/// A max-progression test is a disposable session. Keep a complete serialized baseline so
/// turning the setting off discards world edits, story flags and player progression together.
fn setMaxProgressionTest(self: *App, enabled: bool) void {
    if (enabled) {
        if (self.test_mode_save != null) return;
        const baseline = self.sandbox.save(self.allocator, self.engine.camera) catch |err| {
            self.menu.settings.max_progression_test = false;
            return self.report("TEST MODE COULD NOT SNAPSHOT WORLD: {s}", .{@errorName(err)});
        };
        self.test_mode_save = baseline;
        self.sandbox.setMaxProgressionTest(true);
        return;
    }
    const baseline = self.test_mode_save orelse return;
    self.sandbox.setMaxProgressionTest(false);
    self.sandbox.restore(self.allocator, baseline, &self.engine.camera) catch |err| {
        self.menu.settings.max_progression_test = true;
        self.sandbox.setMaxProgressionTest(true);
        self.report("TEST BASELINE RESTORE FAILED: {s}", .{@errorName(err)});
        return;
    };
    self.allocator.free(baseline);
    self.test_mode_save = null;
}

/// File I/O runs on the application thread between fixed steps; rendering is unaffected.
fn quicksave(self: *App) void {
    if (self.test_mode_save != null) return self.report("TEST MODE: SAVING IS DISABLED; TURN IT OFF TO RESTORE YOUR CAMPAIGN", .{});
    const bytes = self.sandbox.save(self.allocator, self.engine.camera) catch |err| return self.report("SAVE FAILED {s}", .{@errorName(err)});
    defer self.allocator.free(bytes);
    Save.writeFile(self.io, Save.default_path, bytes) catch |err| return self.report("SAVE FAILED {s}", .{@errorName(err)});
    const rangers = self.saveRangers();
    self.report("SAVED {s} AND {d} RANGER FILE{s}", .{ Save.default_path, rangers, if (rangers == 1) "" else "S" });
}

/// Every known player's own ranger file, beside the team save; returns how many were written.
fn saveRangers(self: *App) usize {
    var written: usize = 0;
    for (0..Sandbox.max_players) |p| {
        if (!self.sandbox.known[p]) continue;
        var arena_state: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const file = self.sandbox.rangerFile(arena, p) catch continue;
        const json = std.json.Stringify.valueAlloc(arena, file, .{ .whitespace = .indent_2 }) catch continue;
        var buffer: [96]u8 = undefined;
        const path = Save.rangerPath(&buffer, file.profile.name) catch continue;
        Save.writeFile(self.io, path, json) catch |err| {
            self.report("RANGER SAVE FAILED {s}", .{@errorName(err)});
            continue;
        };
        written += 1;
    }
    return written;
}

/// FOUR PLAYER SETUP: the selected player takes up the next saved ranger after the one in their
/// seat (alphabetically, wrapping), skipping rangers another present player is playing.
fn loadNextRanger(self: *App) void {
    const sb = &self.sandbox;
    const p: usize = self.menu.hero_player;
    if (!sb.present(p)) return self.report("JOIN P{d} BEFORE LOADING A RANGER", .{p + 1});
    var dir = std.Io.Dir.cwd().openDir(self.io, Save.ranger_dir, .{ .iterate = true }) catch return self.report("NO SAVED RANGERS YET: SAVE THE GAME FIRST", .{});
    defer dir.close(self.io);
    // File names, sorted; the names are uppercase letters, digits, hyphens and underscores.
    var names: [64][48]u8 = undefined;
    var lens: [64]usize = undefined;
    var n: usize = 0;
    var it = dir.iterate();
    while (it.next(self.io) catch null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json") or entry.name.len > 48 or n == names.len) continue;
        @memcpy(names[n][0..entry.name.len], entry.name);
        lens[n] = entry.name.len;
        n += 1;
    }
    if (n == 0) return self.report("NO SAVED RANGERS YET: SAVE THE GAME FIRST", .{});
    var order: [64]usize = undefined;
    for (order[0..n], 0..) |*o, i| o.* = i;
    const Ctx = struct { names: *const [64][48]u8, lens: *const [64]usize };
    std.mem.sort(usize, order[0..n], Ctx{ .names = &names, .lens = &lens }, struct {
        fn less(c: Ctx, a: usize, b: usize) bool {
            return std.mem.order(u8, c.names[a][0..c.lens[a]], c.names[b][0..c.lens[b]]) == .lt;
        }
    }.less);
    // Start after the ranger in this seat.
    var current: [96]u8 = undefined;
    const here = Save.rangerPath(&current, (if (sb.own_profiles[p]) |*o| o else sb.profileOf(p)).name()) catch "";
    const here_file = here[@min(here.len, Save.ranger_dir.len + 1)..];
    var first: usize = 0;
    for (order[0..n], 0..) |i, k| if (std.mem.eql(u8, names[i][0..lens[i]], here_file)) {
        first = k + 1;
    };
    for (0..n) |step| {
        const i = order[(first + step) % n];
        const file = names[i][0..lens[i]];
        const bytes = dir.readFileAlloc(self.io, file, self.allocator, .limited(Save.max_bytes)) catch continue;
        defer self.allocator.free(bytes);
        const ranger = Save.decodeRanger(self.allocator, bytes) catch continue;
        if (sb.rangerInPlay(ranger.profile.name(), p)) continue;
        sb.takeRanger(p, ranger);
        sb.cue(.ui_confirm, null);
        return self.report("P{d} IS NOW {s} ({d} SCRAP)", .{ p + 1, ranger.profile.name(), ranger.kit.wallet.scrap });
    }
    self.report("EVERY SAVED RANGER IS ALREADY IN PLAY", .{});
}

fn quickload(self: *App) bool {
    const bytes = Save.readFile(self.io, self.allocator, Save.default_path) catch |err| {
        self.report("LOAD FAILED {s}", .{@errorName(err)});
        return false;
    };
    defer self.allocator.free(bytes);
    const test_mode = self.test_mode_save != null;
    const loaded_baseline = if (test_mode) self.allocator.dupe(u8, bytes) catch {
        self.report("LOAD FAILED: COULD NOT KEEP TEST BASELINE", .{});
        return false;
    } else null;
    if (test_mode) self.sandbox.setMaxProgressionTest(false);
    self.sandbox.restore(self.allocator, bytes, &self.engine.camera) catch |err| {
        if (loaded_baseline) |baseline| self.allocator.free(baseline);
        if (test_mode) self.sandbox.setMaxProgressionTest(true);
        self.report("LOAD FAILED {s}", .{@errorName(err)});
        return false;
    };
    if (loaded_baseline) |baseline| {
        self.allocator.free(self.test_mode_save.?);
        self.test_mode_save = baseline;
        self.sandbox.setMaxProgressionTest(true);
    }
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
            for ([_]mach.Core.KeyButtonID{ .backspace, .backspace, .backspace, .backspace, .backspace, .backspace, .s, .o, .r, .a, .down, .right, .down, .down, .down, .right, .enter }) |key| self.creatorKey(key, false);
            std.log.info("Smoke character: {s}, hair style {s}", .{ self.sandbox.profile.name(), @tagName(self.sandbox.profile.hair_style) });
            self.sandbox.creator.openImported();
            self.sandbox.creator.selectImported(0);
            self.sandbox.creator.toggleImportedPart();
            self.mesh_library_preview_dirty = true;
            std.log.info("Smoke mesh editor: queued one-component hide patch", .{});
            self.culling = true;
            self.sandbox.player.setMode(.fly, camera.*);
            camera.position = mach.math.vec3(180, 35, 120);
            camera.yaw = 0.4;
            // Visit every fast-travel destination; the last (New York) stays loaded for the frames
            // until stage 2, so its chunks stream and draw under the Metal validation layer.
            for (0..Sandbox.travel_count) |destination| {
                if (!self.sandbox.fastTravel(0, destination, camera)) return self.report("SMOKE TRAVEL {s} REFUSED", .{Sandbox.travel_labels[destination]});
                const feet = self.sandbox.player.feet;
                // Metro platforms are decks above the ground; only the open-terrain arrival is checked.
                const ground = @import("procedural/Terrain.zig").surface(self.sandbox.seed, feet[0], feet[2]).height;
                if (Sandbox.travel_destinations[destination].kind == .region and @abs(feet[1] - ground) > 2) return self.report("SMOKE TRAVEL {s} OFF GROUND", .{Sandbox.travel_labels[destination]});
                std.log.info("Smoke travel {s}: {d:.0} {d:.0} {d:.0}", .{ Sandbox.travel_labels[destination], feet[0], feet[1], feet[2] });
            }
        },
        2 => {
            self.sandbox.creator.toggleImportedPart();
            self.mesh_library_preview_dirty = true;
            self.sandbox.creator.imported_open = false;
            std.log.info("Smoke mesh editor: restored component with a second partial patch", .{});
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
            std.log.info("Smoke market: day {d}, stall stock {any}, salvaged parts {d}", .{ self.sandbox.market.day, self.sandbox.market.stalls[0].stock, self.sandbox.kits[0].wallet.parts });
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
    const scrap = sb.kits[0].wallet.scrap;
    sb.kits[0].wallet.scrap += 40;
    self.uiNav(.confirm);
    const level = sb.kits[0].level(.fuel_tank);
    self.uiNav(.back);
    sb.kits[0].wallet.scrap = scrap;
    std.log.info("Smoke GUI: pause/settings closed={any}, keeper greeting {s}, upgrades opened={any}, fuel tank level {d}, panels closed={any}", .{ menu_closed, greeting, opened, level, !self.uiActive() });
}

/// Fabricates a car and a blaster through the fabricator panel, flies the car, and shoots a
/// drone, through the same calls the window and the simulation use.
fn smokeFrontier(self: *App) void {
    const sb = &self.sandbox;
    const Combat = @import("game/Combat.zig");
    const keep = sb.progress;
    const wallet = sb.kits[0].wallet;
    sb.kits[0].inventory = .{ 20, 6, 20, 0 };
    sb.kits[0].wallet.scrap += 200;
    sb.shop = .{ .kind = .fabricate };
    self.uiNav(.confirm);
    sb.shop.?.tab = 3;
    sb.shop.?.row = 0;
    self.uiNav(.confirm);
    self.uiNav(.back);
    const cars = sb.garage.cars[0] != null;
    const blaster = sb.kits[0].ownsWeapon(.blaster);
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
        const n = sb.combat.step(0, &sb.physics, &sb.enemies, sb.kits[0].weapons, aim, 1.0 / 60.0, &events);
        for (events[0..@min(n, events.len)]) |e| if (e == .hive and e.hive == .unit_down) {
            downed = true;
        };
    }
    std.log.info("Smoke frontier: skimmer parked={any} flew {d:.1} m, blaster={any}, drone downed={any}; {d} nests, {d} pickups", .{ cars, flown, blaster, downed, sb.enemies.nest_count, sb.collectibles.count });
    // The Kestrel: fabricate it through the panel, lift off on its jets, and gun down a wasp.
    sb.kits[0].inventory = .{ 20, 8, 20, 0 };
    // The smoke stages vehicle handling directly, so provide the story reward normally earned
    // by asking Maro after spotting a carrier.
    sb.progress.setFlag("kestrel_blueprint");
    sb.kits[0].wallet.scrap += 200;
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
    self.smokeHeroes();
    self.smokePets();
    self.smokeTeam();
    // Leave the run's progress as it was (later stages log the market and wallet).
    sb.progress = keep;
    sb.kits[0].wallet = wallet;
    @import("game/Frontier.zig").refresh(sb);
}

/// The saber and a sniper rifle fabricated through the panel, a saber combo on a trooper with
/// P1's rig, a piercing sniper beam, and each class's specials.
fn smokeCombat(self: *App) void {
    const sb = &self.sandbox;
    const Combat = @import("game/Combat.zig");
    const Specials = @import("game/Specials.zig");
    const Fabricator = @import("game/Fabricator.zig");
    sb.kits[0].inventory = .{ 30, 4, 30, 0 };
    sb.kits[0].wallet.scrap += 100;
    var list: [Fabricator.recipes.len]u8 = undefined;
    for (Fabricator.onTab(.weapons, &list), 0..) |index, row| {
        const w = switch (Fabricator.recipes[index].output) {
            .weapon => |kind| kind,
            else => continue,
        };
        if (w != .beam_saber and w != .sniper_rifle) continue;
        sb.shop = .{ .kind = .fabricate, .tab = 3, .row = @intCast(row) };
        self.uiNav(.confirm);
        self.uiNav(.back);
    }
    const made = sb.kits[0].ownsWeapon(.beam_saber) and sb.kits[0].ownsWeapon(.sniper_rifle);
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
    _ = sb.specials.step(0, .{ .class = .ranger }, &sb.physics, &sb.enemies, &sb.combat, .{ .eye = .{ 0, 300, 0 }, .forward = .{ 0, 0, 1 }, .feet = feet, .pressed = .{ true, false, false } }, dt, &special_events);
    var grenade = false;
    for (0..90) |_| {
        const n = sb.specials.stepWorld(&sb.physics, &sb.enemies, &sb.combat, dt, &special_events);
        for (special_events[0..@min(n, special_events.len)]) |e| grenade = grenade or e == .burst;
    }
    sb.enemies.units[1] = .{ .kind = .drone, .nest = 0, .position = .{ 3, 299.5, 0 }, .health = 1000, .orbit = 0 };
    _ = sb.specials.step(1, .{ .class = .synthetic }, &sb.physics, &sb.enemies, &sb.combat, .{ .eye = .{ 0, 300, 0 }, .forward = .{ 0, 0, 1 }, .feet = feet, .pressed = .{ false, true, false } }, dt, &special_events);
    const slammed = sb.enemies.units[1].?.velocity[0] > 3;
    std.log.info("Smoke combat: saber and sniper made={any}, saber cuts={d} trooper health {d:.0} stunned={any}, sniper pierced={any}, grenade burst={any}, slam threw={any}", .{ made, cuts, cut_health, stunned, pierced, grenade, slammed });
    sb.enemies.units = @splat(null);
    sb.specials = .{};
    sb.combat.arsenals = @splat(.{});
}

/// Walks P1 in through the first cave mouth with the real simulation step, and reports the
/// ranges and caves.
/// The Wildkin and the Starbowl through the real paths: aim at an unmet city hero and meet
/// them, play as them from the Heroes menu, fire all three powers, then take the party into the
/// arena, clear the first wave with the simulation step, collect its reward, and leave.
fn smokeHeroes(self: *App) void {
    const sb = &self.sandbox;
    const Heroes = Sandbox.Heroes;
    const Frontier = @import("game/Frontier.zig");
    const keep_player = sb.player;
    const keep_profile = sb.profile;
    const keep_progress = sb.progress;
    const keep_kits = sb.kits;
    var camera = self.engine.camera;
    // Meet the first unmet hero with a spot: stand before them and look at their chest.
    var met: ?u8 = null;
    for (sb.encounters) |maybe| if (maybe) |spot| if (!sb.progress.hasHero(spot.hero) and met == null) {
        const eye: [3]f32 = .{ spot.position[0], spot.position[1] + 1.6, spot.position[2] - 3 };
        const target = Frontier.pick(sb, eye, R3.normalize(.{ 0, -0.45, 3 }), 8, 8);
        if (target != null and target.? == .hero and target.?.hero == spot.hero) {
            Frontier.recruit(sb, spot.hero);
            met = spot.hero;
        }
    };
    const joined = if (met) |h| sb.progress.hasHero(h) else false;
    // Play as them through the Heroes menu, then use each power.
    self.menu.open(.pause);
    self.menu.open(.heroes);
    self.menu.heroes_unlocked = sb.progress.heroes;
    self.menu.hero_player = 0;
    self.menu.row = Menu.heroes_first + (met orelse 0);
    self.runCommand(self.menu.key(.confirm));
    self.menu.open(.none);
    const became = met != null and sb.profile.species == Heroes.roster[met.?].species;
    var used: usize = 0;
    for (0..3) |k| {
        sb.specials.players[0].energy = 100;
        var actions: Sandbox.Actions = .{};
        switch (k) {
            0 => actions.special_1 = true,
            1 => actions.special_2 = true,
            else => actions.special_3 = true,
        }
        const before = sb.specials.players[0].cooldowns[k];
        sb.step(&camera, .{}, actions, 1.0 / 60.0) catch {};
        used += @intFromBool(sb.specials.players[0].cooldowns[k] > before);
    }
    // The Starbowl: wave one starts, is cleared, and pays out.
    Frontier.enterArena(sb, &camera);
    const entered = sb.arena.active;
    const scrap = sb.kits[0].wallet.scrap;
    for (0..60 * 4) |_| sb.step(&camera, .{}, .{}, 1.0 / 60.0) catch break;
    const bots = sb.enemies.unitCount(@import("game/Enemies.zig").arena_nest);
    for (&sb.enemies.units) |*u| if (u.*) |unit| if (unit.nest == @import("game/Enemies.zig").arena_nest) {
        u.* = null;
    };
    for (0..30) |_| sb.step(&camera, .{}, .{}, 1.0 / 60.0) catch break;
    const paid = sb.kits[0].wallet.scrap > scrap and sb.progress.arena_best >= 1;
    Frontier.leaveArena(sb, &camera);
    std.log.info("Smoke heroes: met {s} joined={any}, played as them={any}, powers used {d}/3; arena entered={any} wave 1 bots {d}, cleared and paid={any}, left={any}", .{ if (met) |h| Heroes.roster[h].name else "none", joined, became, used, entered, bots, paid, !sb.arena.active });
    sb.player = keep_player;
    sb.profile = keep_profile;
    sb.progress = keep_progress;
    sb.kits = keep_kits;
    sb.own_profiles = @splat(null);
    sb.specials = .{};
}

/// Pets through the real paths: aim at a wild pet and break its collar, walk away and see it
/// follow, then let it fight a Hive trooper beside its ranger until the trooper falls.
fn smokePets(self: *App) void {
    const sb = &self.sandbox;
    const Pets = Sandbox.Pets;
    const Frontier = @import("game/Frontier.zig");
    const keep_player = sb.player;
    const keep_progress = sb.progress;
    const keep_kits = sb.kits;
    const keep_mode = sb.player.mode;
    var camera = self.engine.camera;
    var freed: ?Pets.Species = null;
    for (sb.pets.spots, 0..) |spot, k| if (freed == null) {
        const sp: Pets.Species = @enumFromInt(k);
        if (sb.kits[0].hasPet(sp)) continue;
        const lift: f32 = if (Pets.info(sp).flies) Pets.hover else 0.7;
        const eye: [3]f32 = .{ spot.position[0], spot.position[1] + lift, spot.position[2] - 3 };
        const target = Frontier.pick(sb, eye, .{ 0, 0, 1 }, 8, 8);
        if (target != null and target.? == .wild_pet and target.?.wild_pet == sp) {
            _ = sb.pets.netHitWild(sp, 38);
            _ = sb.pets.netHitWild(sp, 38);
            Frontier.freePet(sb, 0, sp);
            freed = sp;
            sb.player.feet = spot.position;
        }
    };
    const out = sb.pets.out[0] != null and freed != null and sb.pets.out[0].?.species == freed.?;
    // Walk off 12 m; the pet keeps up.
    sb.player.mode = .walk;
    sb.player.feet = R3.add(sb.player.feet, .{ 12, 0, 0 });
    sb.player.feet[1] = @import("procedural/Terrain.zig").surface(sb.seed, sb.player.feet[0], sb.player.feet[2]).height;
    for (0..120) |_| sb.step(&camera, .{}, .{}, 1.0 / 60.0) catch break;
    const gap = if (sb.pets.out[0]) |pet| R3.length(R3.sub(.{ pet.position[0], 0, pet.position[2] }, .{ sb.player.feet[0], 0, sb.player.feet[2] })) else 999;
    // A weak trooper beside the ranger; the pet fights it down and learns from it.
    const xp_before = if (freed) |sp| sb.kits[0].pet_xp[@intFromEnum(sp)] else 0;
    var downed = false;
    if (sb.enemies.nest_count > 0) {
        const at = R3.add(sb.player.feet, .{ 5, 0, 3 });
        if (sb.enemies.spawnAt(.trooper, 0, at, 0.3)) for (0..60 * 8) |_| {
            sb.combat.vitals[0].health = sb.combat.vitals[0].max;
            sb.step(&camera, .{}, .{}, 1.0 / 60.0) catch break;
            if (freed) |sp| if (sb.kits[0].pet_xp[@intFromEnum(sp)] > xp_before) {
                downed = true;
                break;
            };
        };
    }
    std.log.info("Smoke pets: freed {s}={any}, followed within {d:.1} m, fought a trooper down and learned={any}", .{ if (freed) |sp| Pets.info(sp).name else "none", out, gap, downed });
    sb.player = keep_player;
    sb.player.mode = keep_mode;
    sb.progress = keep_progress;
    sb.kits = keep_kits;
    sb.pets.out = @splat(null);
}

/// Every player saves on their own: P2 joins, P1 and P2 earn and free different things, and a
/// save round trip (in memory; no files are written) brings each player's kit back to their seat.
/// P2's ranger file also round-trips.
fn smokeTeam(self: *App) void {
    const sb = &self.sandbox;
    const keep_kits = sb.kits;
    const keep_known = sb.known;
    const was_active = sb.guests[0].active;
    if (!was_active) sb.joinGuest(0);
    sb.kits[0].wallet.scrap = 111;
    sb.kits[1].wallet.scrap = 222;
    _ = sb.kits[1].freePet(.golem);
    var camera = self.engine.camera;
    var restored = false;
    var ranger_ok = false;
    if (sb.save(self.allocator, camera)) |bytes| {
        defer self.allocator.free(bytes);
        sb.kits = @splat(.{});
        if (sb.restore(self.allocator, bytes, &camera)) |_| {
            restored = sb.kits[0].wallet.scrap == 111 and sb.kits[1].wallet.scrap == 222 and sb.kits[1].hasPet(.golem) and !sb.kits[0].hasPet(.golem);
        } else |_| {}
    } else |_| {}
    var arena_state: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena_state.deinit();
    if (sb.rangerFile(arena_state.allocator(), 1)) |file| {
        if (std.json.Stringify.valueAlloc(arena_state.allocator(), file, .{})) |json| {
            if (Save.decodeRanger(self.allocator, json)) |ranger| ranger_ok = ranger.kit.wallet.scrap == 222 else |_| {}
        } else |_| {}
    } else |_| {}
    std.log.info("Smoke team: each player's kit restored to their seat={any}, P2 ranger file round trip={any}", .{ restored, ranger_ok });
    sb.kits = keep_kits;
    sb.known = keep_known;
    if (!was_active) sb.leaveGuest(0);
}

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
    self.captured = enabled;
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
    self.installImportedCharacter();
    self.loadEditedMesh();
    self.sandbox.creator.imported_doc = &self.mesh_library;
    self.applyMeshLibraryPreview(renderer);
    self.updateMeshTools(renderer);
    self.pumpReload(renderer);
    self.pumpStressPack(renderer);
    self.rendered_frames_seen = renderer.frames;
    renderer.views[0].camera = self.engine.camera;
    if ((options.showcase == 67 or options.showcase == 76)) {
        const Terrain = @import("procedural/Terrain.zig");
        const ground = Terrain.surface(self.sandbox.seed, 0, 0).height;
        // 76 holds the camera close on the temple (22 m east), entrance toward the viewer.
        const close = options.showcase == 76;
        renderer.views[0].camera.position = if (close) mach.math.vec3(22, ground + 7, 31) else mach.math.vec3(0, ground + 18, 66);
        renderer.views[0].camera.yaw = std.math.pi;
        renderer.views[0].camera.pitch = if (close) -0.12 else -0.202;
    }
    if (options.character_showcase > 0 and options.character_showcase != 48) {
        const feet = self.sandbox.player.feet;
        // Orbit the avatar for review: angle from the front, camera distance and look height.
        const angle: f32 = switch (options.character_view) {
            1 => std.math.pi / 2.0,
            2 => std.math.pi,
            3, 5 => 0.62,
            else => 0,
        };
        const face = options.character_view >= 4;
        const frame = Sandbox.creatorFrame(if (face) 1 else 0, self.sandbox.profile.height);
        // Whole-body reviews sit a little lower and wider than the in-game creator so feet show.
        const dist: f32 = if (face) frame.distance else 2.8;
        const eye_y: f32 = if (face) frame.eye_y else 1.12;
        renderer.views[0].camera.position = mach.math.vec3(feet[0] + dist * @sin(angle), feet[1] + eye_y, feet[2] + dist * @cos(angle));
        renderer.views[0].camera.yaw = std.math.pi + angle;
        renderer.views[0].camera.pitch = if (face) frame.pitch else -0.08;
    }
    if (options.showcase == 63) {
        // A repeatable pose reel for checking locomotion silhouettes in the Metal renderer.
        // The capture frame selects sprint, roll, dash, long jump, backflip or flight.
        const phase = renderer.frames % 90;
        const progress = @as(f32, @floatFromInt(phase)) / 90;
        const stage = @min(renderer.frames / 90, 5);
        const player = &self.sandbox.player;
        player.velocity = @splat(0);
        player.grounded = stage < 3;
        player.roll_timer = 0;
        player.dash_timer = 0;
        player.long_jump_timer = 0;
        player.backflip_timer = 0;
        player.motion = switch (stage) {
            0 => .sprint,
            1 => blk: {
                player.roll_timer = 0.42 * (1 - progress);
                break :blk .roll;
            },
            2 => blk: {
                player.dash_timer = 0.2 * (1 - progress);
                break :blk .dash;
            },
            3 => blk: {
                player.long_jump_timer = 0.68 * (1 - progress);
                break :blk .long_jump;
            },
            4 => blk: {
                player.backflip_timer = 0.72 * (1 - progress);
                break :blk .backflip;
            },
            else => .jet,
        };
        self.sandbox.walk_phase = @as(f32, @floatFromInt(renderer.frames)) * 0.11;
        self.sandbox.walk_amount = 1;
        renderer.views[0].camera.position = mach.math.vec3(player.feet[0], player.feet[1] + 1.4, player.feet[2] + 3.1);
        renderer.views[0].camera.yaw = std.math.pi;
        renderer.views[0].camera.pitch = -0.08;
    }
    renderer.tick = self.engine.time.tick;
    renderer.time_of_day = Sky.timeOfDay(self.sandbox.tick);
    renderer.show_metrics = self.show_metrics and !self.sandbox.creator.open;
    renderer.cel_style = self.cel_style;
    renderer.cel_debug = self.cel_debug;
    renderer.characters.content = self.sandbox.characters;
    renderer.culling = self.culling;
    if (options.showcase == 83 or options.showcase == 84) {
        const Terrain = @import("procedural/Terrain.zig");
        const origin = Sandbox.spawn;
        const ground = Terrain.surface(self.sandbox.seed, origin[0], origin[2]).height;
        renderer.prop_count = @import("game/Frontier.zig").publishTitanPreview(&self.sandbox, &renderer.props, .{ origin[0], ground, origin[2] }, 0);
    } else if (options.showcase == 78) {
        const Scene3D = @import("engine/Scene3D.zig");
        var scene = Scene3D.Frame.init(self.sandbox.catalog, &renderer.props);
        scene.drawBox(.{ -5, 1, 0 }, .{ 2, 2, 2 }, .{ 0.22, 0.52, 0.82, 1 }) catch unreachable;
        scene.drawSphere(.{ 0, 1, 0 }, 1, .{ 0.95, 0.48, 0.18, 1 }) catch unreachable;
        scene.drawModel(self.sandbox.catalog.content.crate, .{ .position = .{ 4, 1, 0 }, .scale = 1.8 }, .{ .tint = .{ 0.72, 0.88, 0.3, 1 } }) catch unreachable;
        scene.drawModel(self.sandbox.catalog.content.cars[0].body, .{ .position = .{ 8, 0.5, 0 }, .scale = 1.3 }, .{ .tint = .{ 1, 1, 1, 1 }, .lod = self.sandbox.catalog.content.cars[1].body, .lod_distance = 100 }) catch unreachable;
        renderer.prop_count = scene.count;
    } else {
        renderer.prop_count = self.sandbox.publishProps(&renderer.props);
    }
    if (options.showcase == 66 or (options.showcase == 67 or options.showcase == 76)) renderer.prop_count = 0;
    renderer.scene.flora_review = options.showcase == 62 or options.showcase == 74 or options.showcase == 75;
    renderer.scene.flora_review_variant = if (options.showcase == 74) 14 else if (options.showcase == 75) 12 else null;
    renderer.scene.flora_review_seed = self.sandbox.seed;
    renderer.scene.flora_review_origin = if (options.showcase == 74 or options.showcase == 75) blk: {
        var origin = floraReviewOrigin();
        origin[0] -= if (options.showcase == 74) 280 else 140;
        break :blk origin;
    } else floraReviewOrigin();
    renderer.scene.space_review = options.showcase == 66;
    if (options.showcase == 47 and renderer.prop_count + 5 <= renderer.props.len) {
        const fleet = [_]struct { mesh: @import("asset/Catalog.zig").MeshHandle, position: [3]f32, scale: f32 }{
            .{ .mesh = self.sandbox.catalog.content.scalari_throne_serpent, .position = .{ -120, 480, 15 }, .scale = 1 },
            .{ .mesh = self.sandbox.catalog.content.scalari_worldcoil_ark, .position = .{ 120, 480, 15 }, .scale = 1 },
            // Fighters are enlarged for this art-review lineup so their armor details read beside
            // the motherships; the flight/gameplay scale remains defined by their ship specs.
            .{ .mesh = self.sandbox.catalog.content.scalari_ember_wyrm, .position = .{ -48, 480, 110 }, .scale = 3.5 },
            .{ .mesh = self.sandbox.catalog.content.scalari_void_lance, .position = .{ 0, 480, 110 }, .scale = 3.5 },
            .{ .mesh = self.sandbox.catalog.content.scalari_dreadclaw, .position = .{ 48, 480, 110 }, .scale = 3.5 },
        };
        for (fleet) |ship| {
            renderer.props[renderer.prop_count] = .{ .mesh = ship.mesh, .transform = .{ .position = ship.position, .scale = ship.scale }, .tint = .{ 1, 1, 1, 1 } };
            renderer.prop_count += 1;
        }
    }
    if (options.showcase == 66 and renderer.prop_count + 4 <= renderer.props.len) {
        const habitat = self.sandbox.catalog.content.helios_habitat;
        const habitat_glow = self.sandbox.catalog.content.helios_habitat_glow;
        const mother = self.sandbox.catalog.content.rand_mother;
        const mother_glow = self.sandbox.catalog.content.rand_mother_glow;
        const showcase_props = [_]struct { mesh: @import("asset/Catalog.zig").MeshHandle, position: [3]f32, scale: f32, tint: [4]f32 }{
            .{ .mesh = mother, .position = .{ 0, 790, -360 }, .scale = 0.9, .tint = .{ 1, 1, 1, 1 } },
            .{ .mesh = mother_glow, .position = .{ 0, 790, -360 }, .scale = 0.9, .tint = .{ 1, 1, 1, 1.65 } },
            .{ .mesh = habitat, .position = .{ 0, 790, 360 }, .scale = 1.0, .tint = .{ 1, 1, 1, 1 } },
            .{ .mesh = habitat_glow, .position = .{ 0, 790, 360 }, .scale = 1.0, .tint = .{ 1, 1, 1, 1.65 } },
        };
        for (showcase_props) |prop| {
            renderer.props[renderer.prop_count] = .{ .mesh = prop.mesh, .transform = .{ .position = prop.position, .scale = prop.scale }, .tint = prop.tint };
            renderer.prop_count += 1;
        }
    }
    if ((options.showcase == 67 or options.showcase == 76) and renderer.prop_count + 3 <= renderer.props.len) {
        const Terrain = @import("procedural/Terrain.zig");
        const c = &self.sandbox.catalog.content;
        const assets = [_]struct { mesh: @import("asset/Catalog.zig").MeshHandle, x: f32 }{
            .{ .mesh = c.wilds_cabin, .x = -22 },
            .{ .mesh = c.wilds_barn, .x = 0 },
            .{ .mesh = c.cave_temple, .x = 22 },
        };
        for (assets) |asset| {
            if (options.showcase == 76 and asset.x != 22) continue;
            const ground = Terrain.surface(self.sandbox.seed, asset.x, 0).height;
            renderer.props[renderer.prop_count] = .{ .mesh = asset.mesh, .transform = .{ .position = .{ asset.x, ground, 0 } }, .tint = .{ 1, 1, 1, 1 } };
            renderer.prop_count += 1;
        }
    }
    // The removal set is large; copy it only when it changed.
    if (self.published_revision != self.sandbox.modifications.revision) {
        renderer.modifications = self.sandbox.modifications;
        self.published_revision = self.sandbox.modifications.revision;
    }
    const sandbox = &self.sandbox;
    renderer.views[0].crosshair = options.showcase != 62 and options.showcase != 63 and options.showcase != 66 and options.showcase != 67 and options.showcase != 78 and sandbox.seated == null and !self.uiActive() and (self.captured or sandbox.player.mode == .walk or sandbox.player.mode == .fly);
    renderer.views[0].hide_owner = if (options.showcase == 66 or (options.showcase == 67 or options.showcase == 76) or !sandbox.bodyShown()) 1 else 0;
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
    // Inside a cave the sun is shut out and the ambient takes the cave's hue; blend over about
    // half a second so crossing a mouth never pops.
    for (renderer.views[0..renderer.view_count], 0..) |*view, i| {
        const eye = [3]f32{ view.camera.position.x(), view.camera.position.y(), view.camera.position.z() };
        var target: f32 = 0;
        if (Sandbox.Caves.systemAt(&sandbox.caves, eye)) |system| {
            const ground = @import("procedural/Terrain.zig").surface(sandbox.seed, eye[0], eye[2]).height;
            const depth = std.math.clamp((ground - eye[1] - 1) / 6, 0, 1);
            target = depth * depth * (3 - 2 * depth);
            self.cave_hue[i] = Sandbox.Caves.veinHue(system);
        }
        self.underground[i] += (target - self.underground[i]) * 0.1;
        view.underground = self.underground[i];
        view.cave_hue = self.cave_hue[i];
    }
    const minutes: u32 = @intFromFloat(renderer.time_of_day * 24 * 60);
    const motion = if (sandbox.seated != null) "DRIVE" else if (sandbox.player.mode == .fly) "SUPER FLIGHT" else @tagName(sandbox.player.motion);
    renderer.hud_lines[0].set("{d:0>2}:{d:0>2}  {s}  {s}  {s} FUEL {d:.0}  TOOL {s}  SCRAP {d}  PARTS {d}", .{ minutes / 60, minutes % 60, sandbox.profile.name(), motion, @tagName(sandbox.player.traversal), sandbox.player.fuel, @tagName(sandbox.tools.tool), sandbox.kits[0].wallet.scrap, sandbox.kits[0].wallet.parts });
    if (sandbox.hangar.piloting) {
        const f = &sandbox.hangar.fighter.?;
        const g = &sandbox.skies.guns;
        renderer.hud_lines[1].set("KESTREL {d:.0}M/S BOOST {d:.0}%{s} HULL {d:.0}/{d:.0} MSL {d}/{d} GUN {s} / CLICK FIRE / RMB LOCK / F OUT", .{ f.airspeed(), f.boost_charge / @max(f.cfg.boost_capacity, 0.01) * 100, if (f.barrel_roll_timer > 0) " ROLL" else if (self.engine.input.fast and f.boost_charge > 0) " BURN" else "", @max(0, f.hull), f.hull_max, g.missile_ammo, g.missile_capacity, if (g.overheated) "HOT" else "OK" });
    } else if (sandbox.garage.piloting) |i| {
        const car = &sandbox.garage.cars[i].?.flyer;
        const ground = @import("procedural/Terrain.zig").surface(sandbox.seed, car.body.pos.x, car.body.pos.z).height;
        const race = sandbox.garage.race;
        var pb_buffer: [16]u8 = undefined;
        const personal_best = if (race.best > 0) std.fmt.bufPrint(&pb_buffer, "{d:.1}s", .{race.best}) catch "--" else "--";
        renderer.hud_lines[1].set("{s}  {d:.0} M/S  BOOST {d:.0}%  {s} {d}/{d} {d:.1}s  PB {s}  {d:.0} M UP", .{ @import("vehicle/Designs.zig").name(@enumFromInt(i)), car.body.vel.length(), car.boost_charge * 100, if (race.active) "GATE" else if (race.finished) "FINISH" else "START", if (race.active) race.gate + 1 else 0, @import("game/Racing.zig").node_count, race.elapsed, personal_best, car.body.pos.y - ground });
    } else if (sandbox.seated) |m| {
        const placed = &sandbox.machines[m];
        const motor = placed.machine.blueprint.vehicle.?.motor;
        renderer.hud_lines[1].set("{d:.1} M/S  POWER {d:.0}%  WASD DRIVE  SPACE BRAKE  X / CLICK EXIT", .{ placed.vehicle.?.forwardSpeed(&sandbox.physics), placed.machine.satisfaction(motor) * 100 });
    } else if (sandbox.held) |i| {
        renderer.hud_lines[1].set("HOLDING CRATE {d}  CLICK DROP", .{i});
    } else if (sandbox.player.boostTier() > 0) {
        renderer.hud_lines[1].set("BOOST x{d}  {d:.0} M/S  {d:.1} KM UP", .{ @as(u32, 1) << @intCast(sandbox.player.boostTier()), @sqrt(sandbox.player.velocity[0] * sandbox.player.velocity[0] + sandbox.player.velocity[1] * sandbox.player.velocity[1] + sandbox.player.velocity[2] * sandbox.player.velocity[2]), sandbox.player.feet[1] / 1000 });
    } else switch (sandbox.target) {
        .prop => |i| renderer.hud_lines[1].set("CRATE {d}  X / CLICK GRAB", .{i}),
        .relic => |r| renderer.hud_lines[1].set("YOUNG TREE {d}:{d}:{d}  X / CLICK HARVEST", .{ r.ref.x, r.ref.z, r.ref.id }),
        .bridge => |i| renderer.hud_lines[1].set("YOUR BRIDGE {d}  TOOL 4 + RMB REMOVE", .{i}),
        .stall => |i| renderer.hud_lines[1].set("TALK TO {s}  X / CLICK", .{Screens.keeperName(sandbox, i)}),
        .walker => renderer.hud_lines[1].set("CANOPY LOCAL  X / CLICK TALK", .{}),
        .car => |i| renderer.hud_lines[1].set("{s}  I / X (LEFT FACE) / CLICK BOARD", .{@import("vehicle/Designs.zig").name(@enumFromInt(i))}),
        .jet => renderer.hud_lines[1].set("KESTREL FIGHTER  X (LEFT FACE) / CLICK BOARD", .{}),
        .fabricator => renderer.hud_lines[1].set("FABRICATOR  X / CLICK OPEN", .{}),
        .hero => |i| renderer.hud_lines[1].set("MEET {s}, {s}  X / CLICK", .{ Sandbox.Heroes.roster[i].name, Sandbox.Heroes.roster[i].title }),
        .wild_pet => |sp| if (sandbox.pets.canCaptureWild(sp))
            renderer.hud_lines[1].set("{s} SNARED {d}%  X / CLICK TO CATCH", .{ Sandbox.Pets.info(sp).name, @as(u32, @intFromFloat(sandbox.pets.wild_health[@intFromEnum(sp)])) })
        else
            renderer.hud_lines[1].set("WILD {s}  WEAKEN WITH ENERGY NET  {d}%", .{ Sandbox.Pets.info(sp).name, @as(u32, @intFromFloat(sandbox.pets.wild_health[@intFromEnum(sp)])) }),
        .pet => |owner| if (sandbox.pets.out[owner]) |pet| {
            const kit = &sandbox.kits[owner];
            const next = kit.nextPet();
            if (owner == 0 and next != null and next.? != pet.species)
                renderer.hud_lines[1].set("PET {s} LV {d}  X / CLICK (SWAP TO {s})", .{ Sandbox.Pets.info(pet.species).name, kit.petLevel(pet.species), Sandbox.Pets.info(next.?).name })
            else if (owner == 0)
                renderer.hud_lines[1].set("PET {s} LV {d}  X / CLICK", .{ Sandbox.Pets.info(pet.species).name, kit.petLevel(pet.species) })
            else
                renderer.hud_lines[1].set("PET P{d}'S {s} LV {d}  X / CLICK", .{ owner + 1, Sandbox.Pets.info(pet.species).name, kit.petLevel(pet.species) });
        },
        .structure => |m| renderer.hud_lines[1].set("{s}  X / CLICK INVESTIGATE", .{sandbox.machines[m].blueprint.name()}),
        .device => |ref| {
            const machine = &sandbox.machines[ref.machine].machine;
            const def = machine.blueprint.device(ref.device);
            const shrine = sandbox.machines[ref.machine].shrine;
            switch (def.kind) {
                .button => if (shrine != null and std.mem.eql(u8, def.name(), "reset"))
                    renderer.hud_lines[1].set("SHRINE {d} RESET  X / CLICK: RESET", .{shrine.?})
                else if (shrine != null and std.mem.eql(u8, def.name(), "vault"))
                    renderer.hud_lines[1].set("SEED VAULT  X / CLICK OPEN", .{})
                else
                    renderer.hud_lines[1].set("{s} BUTTON  X / CLICK PRESS", .{def.name()}),
                .script => renderer.hud_lines[1].set("{s} SCRIPT {s}  OUT {d:.2}{s}", .{ def.name(), def.scriptName(), machine.outputs[ref.device][4], if (sandbox.scripts.find(def.scriptName()) == null) "  MISSING" else "" }),
                .plate => renderer.hud_lines[1].set("WEIGHT PLATE {s}  {s}", .{ def.name(), if (machine.outputs[ref.device][0] > 0.5) "PRESSED" else "NEEDS A CRATE" }),
                .seat => renderer.hud_lines[1].set("{s}  I / X / CLICK ENTER", .{machine.blueprint.name()}),
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
    if (options.showcase == 62 or options.showcase == 63 or options.showcase == 66) renderer.hud_lines = @splat(.{});
    self.publishGui(renderer, minutes);
}

/// Save the in-game component labels, roles and color palettes as a user library override.
fn saveMeshLibrary(self: *App) void {
    const json = std.json.Stringify.valueAlloc(self.allocator, self.mesh_library, .{ .whitespace = .indent_2 }) catch |err| {
        self.report("LIBRARY SAVE FAILED {s}", .{@errorName(err)});
        return;
    };
    defer self.allocator.free(json);
    const path = if (self.sandbox.profile.body_style == .imported_glb and self.imported_rig_status_len != 0) "saves/imported-character.modifiers.json" else "saves/captain.modifiers.json";
    Save.writeFile(self.io, path, json) catch |err| {
        self.report("LIBRARY SAVE FAILED {s}", .{@errorName(err)});
        return;
    };
    if (self.vertex_edits_pending) {
        if (!self.saveEditedMesh()) return;
        self.sandbox.creator.imported_status = .saved;
        self.report("LIBRARY AND EDITED MESH SAVED", .{});
        return;
    }
    self.sandbox.creator.imported_status = .saved;
    self.report("IMPORTED CHARACTER LIBRARY SAVED", .{});
}

fn editedMeshPath(self: *const App) []const u8 {
    return if (self.sandbox.profile.body_style == .imported_glb and self.imported_rig_status_len != 0) EditedMesh.imported_path else EditedMesh.captain_path;
}

/// Writes the edited mesh (sculpt, paint, pens, topology, skin) beside the part sidecar.
fn saveEditedMesh(self: *App) bool {
    const entry = self.catalog.mesh(self.catalog.content.captain_test) orelse return false;
    const bytes = EditedMesh.encode(self.allocator, entry.model) catch |err| {
        self.report("MESH SAVE FAILED {s}", .{@errorName(err)});
        return false;
    };
    defer self.allocator.free(bytes);
    Save.writeFile(self.io, self.editedMeshPath(), bytes) catch |err| {
        self.report("MESH SAVE FAILED {s}", .{@errorName(err)});
        return false;
    };
    self.vertex_edits_pending = false;
    return true;
}

/// Once the imported (or built-in) mesh is installed, replaces it with saved vertex edits when
/// they still fit its rig. The part library stays detached: the saved colours are final.
fn loadEditedMesh(self: *App) void {
    if (!self.edited_mesh_check or self.queued_character_model != null) return;
    const handle = &self.catalog.content.captain_test;
    const entry = self.catalog.meshMut(handle.*) orelse return;
    if (!entry.ready) return;
    self.edited_mesh_check = false;
    const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, self.editedMeshPath(), self.allocator, .limited(256 << 20)) catch return;
    defer self.allocator.free(bytes);
    const edited = EditedMesh.adopt(self.allocator, bytes, entry.model) catch |err| {
        std.log.warn("saved mesh edits ignored ({s}); the file was preserved", .{@errorName(err)});
        return;
    };
    self.mesh_tools.unbind();
    self.destroyMeshLibraryBake();
    self.catalog.replaceHandle(self.allocator, handle, edited) catch |err| {
        std.log.err("saved mesh edits failed to install: {s}", .{@errorName(err)});
        return;
    };
    self.mesh_library_detached = true;
    std.log.info("Loaded saved mesh edits from {s}", .{self.editedMeshPath()});
}

/// Deletes the saved edits and reloads the source mesh.
fn discardEditedMesh(self: *App) void {
    std.Io.Dir.cwd().deleteFile(self.io, self.editedMeshPath()) catch {};
    self.vertex_edits_pending = false;
    if (self.imported_rig_status_len != 0) {
        self.loadSavedCharacterImport();
        self.report("EDITS DISCARDED; SOURCE MESH RELOADED", .{});
    } else self.report("EDITS DISCARDED; RESTART TO RELOAD THE ORIGINAL MESH", .{});
}

/// Import a binary GLB into the Character Designer. Its skin is kept and retargeted live onto the
/// game's humanoid skeleton by bone name (`Gltf.humanoidJoint`, `character/Retarget.zig`); the
/// source GLB and the editable component sidecar are saved for repeat edits.
fn importCharacterGlb(self: *App, source: []const u8, persist: bool) !void {
    var scratch: std.heap.ArenaAllocator = .init(self.allocator);
    defer scratch.deinit();
    const trace = try @import("asset/Gltf.zig").inspect(scratch.allocator(), source);
    if (trace.skin_count == 0) return error.CharacterNeedsSkin;
    const mapped_count = @import("asset/Gltf.zig").mappedGameplayJointCount(trace);
    if (mapped_count == 0) return error.NoCompatibleGameplayJoints;
    var model = try @import("asset/Gltf.zig").compileRigged(self.allocator, source, .{});
    errdefer model.deinit(self.allocator);
    const source_hash = @import("asset/Meta.zig").hashSource(source);
    const generated = try MeshModifiers.generate(self.mesh_library_arena.allocator(), model, &source_hash);
    if (persist) {
        try Save.writeFile(self.io, "saves/imported-character.glb", source);
        const json = try std.json.Stringify.valueAlloc(scratch.allocator(), generated, .{ .whitespace = .indent_2 });
        try Save.writeFile(self.io, "saves/imported-character.modifiers.json", json);
    }
    self.destroyMeshLibraryBake();
    if (self.queued_character_model) |old| old.deinit(self.allocator);
    self.queued_character_model = model;
    model = undefined;
    self.mesh_library = generated;
    self.sandbox.creator.clearImportedHistory();
    self.mesh_library_preview_dirty = true;
    self.sandbox.profile.body_style = .imported_glb;
    self.sandbox.creator.draft.body_style = .imported_glb;
    self.sandbox.creator.imported_selected = 0;
    self.sandbox.creator.imported_status = .ready;
    const app_status = std.fmt.bufPrint(&self.imported_rig_status, "LIVE RETARGET {d}/21 JOINTS", .{mapped_count}) catch unreachable;
    self.imported_rig_status_len = app_status.len;
    const creator_status = std.fmt.bufPrint(&self.sandbox.creator.imported_rig_status, "LIVE RETARGET {d}/21 JOINTS", .{mapped_count}) catch unreachable;
    self.sandbox.creator.imported_rig_status_len = creator_status.len;
    if (persist) self.sandbox.creator.imported_open = true;
}

fn loadSavedCharacterImport(self: *App) void {
    const source = std.Io.Dir.cwd().readFileAlloc(self.io, "saves/imported-character.glb", self.allocator, .limited(64 << 20)) catch return;
    defer self.allocator.free(source);
    const modifiers = std.Io.Dir.cwd().readFileAlloc(self.io, "saves/imported-character.modifiers.json", self.mesh_library_arena.allocator(), .limited(1 << 20)) catch {
        self.importCharacterGlb(source, false) catch |err| std.log.warn("saved character import rejected: {s}", .{@errorName(err)});
        return;
    };
    self.importCharacterGlb(source, false) catch |err| {
        std.log.warn("saved character import rejected: {s}", .{@errorName(err)});
        return;
    };
    const override = std.json.parseFromSliceLeaky(MeshModifiers.Document, self.mesh_library_arena.allocator(), modifiers, .{}) catch return;
    if (validMeshLibraryOverride(self.mesh_library, override)) {
        self.mesh_library = override;
        self.sandbox.creator.clearImportedHistory();
        self.mesh_library_preview_dirty = true;
    }
}

fn chooseAndImportCharacter(self: *App) void {
    if (@import("builtin").os.tag != .macos) return self.report("GLB PICKER IS AVAILABLE ON MACOS", .{});
    const bytes = self.allocator.alloc(u8, 64 << 20) catch return self.report("NOT ENOUGH MEMORY TO OPEN GLB", .{});
    defer self.allocator.free(bytes);
    var length: usize = 0;
    const result = hw_choose_open_glb(bytes.ptr, bytes.len, &length);
    if (result == 0) return;
    if (result < 0) return self.report("GLB IS LARGER THAN 64 MB OR COULD NOT BE READ", .{});
    self.importCharacterGlb(bytes[0..length], true) catch |err| return self.report("GLB IMPORT FAILED: {s}", .{@errorName(err)});
    self.report("CHARACTER IMPORTED — {s}", .{self.imported_rig_status[0..self.imported_rig_status_len]});
}

fn installImportedCharacter(self: *App) void {
    const model = self.queued_character_model orelse return;
    self.mesh_tools.unbind();
    self.vertex_edits_pending = false;
    self.mesh_library_detached = false;
    // Saved edits of this source (if any) go on top once it is installed.
    self.edited_mesh_check = true;
    self.catalog.replaceHandle(self.allocator, &self.catalog.content.captain_test, model) catch |err| {
        model.deinit(self.allocator);
        self.queued_character_model = null;
        std.log.err("imported character install failed: {s}", .{@errorName(err)});
        return;
    };
    self.queued_character_model = null;
}

fn meshToolsActive(self: *const App) bool {
    return self.sandbox.creator.open and self.sandbox.creator.imported_open and self.sandbox.creator.vertex_tools and self.mesh_tools.active;
}

/// The topmost GUI hit under the pointer, if any.
fn hitUnderPointer(self: *const App) ?u16 {
    var i = self.hit_len;
    while (i > 0) {
        i -= 1;
        if (self.hits[i].rect.contains(self.pointer[0], self.pointer[1])) return self.hits[i].id;
    }
    return null;
}

/// The world ray under the pointer, from the camera the tools last aimed.
fn pointerRay(self: *const App) ?MeshTools.Ray {
    const camera = self.tool_camera orelse return null;
    const canvas_w = self.ui_height * self.tool_aspect;
    const ray = @import("engine/Scene3D.zig").screenRay(camera, self.tool_aspect, .{ self.pointer[0] / canvas_w, self.pointer[1] / self.ui_height }) orelse return null;
    return .{ .origin = ray.origin, .direction = ray.direction };
}

fn queueToolEvent(self: *App, event: ToolEvent) void {
    // Consecutive drags collapse to the latest; a full queue keeps the newest press/release.
    if (event == .drag and self.tool_event_len > 0 and self.tool_events[self.tool_event_len - 1] == .drag) {
        self.tool_events[self.tool_event_len - 1] = event;
        return;
    }
    if (self.tool_event_len == self.tool_events.len) return;
    self.tool_events[self.tool_event_len] = event;
    self.tool_event_len += 1;
}

fn meshToolControl(self: *App, c: MeshTools.Control) void {
    if (c == .open) {
        self.sandbox.creator.vertex_tools = true;
        // The part bake (whose base copy the tools keep in step) is built by the preview pass.
        self.mesh_library_preview_dirty = true;
        return;
    }
    self.queueToolEvent(.{ .control = c });
}

/// Binds the tools to the imported mesh, aims the orbit camera, applies queued pointer events and
/// uploads what they changed. Runs in `publish`, after the part preview.
fn updateMeshTools(self: *App, renderer: *Renderer) void {
    const creator = &self.sandbox.creator;
    creator.mesh_tools = &self.mesh_tools;
    if (!(creator.open and creator.imported_open and creator.vertex_tools)) {
        if (self.mesh_tools.active) self.mesh_tools.unbind();
        if (!(creator.open and creator.imported_open)) creator.vertex_tools = false;
        self.tool_event_len = 0;
        self.tool_camera = null;
        self.orbit_held = false;
        return;
    }
    const handle = &self.catalog.content.captain_test;
    const entry = self.catalog.meshMut(handle.*) orelse return;
    if (!entry.ready) return;
    if (!self.mesh_tools.bound(&entry.model)) {
        const mirror: ?*MeshModel = if (self.mesh_library_bake) |bake| &bake.pristine else null;
        self.mesh_tools.bind(&entry.model, mirror) catch |err| {
            self.report("VERTEX TOOLS FAILED {s}", .{@errorName(err)});
            creator.vertex_tools = false;
            return;
        };
    }
    if (self.mesh_library_bake) |bake| bake.painted = &self.mesh_tools.editor.?.painted;
    if (options.character_showcase == 48 and !self.tools_showcase_done) self.scriptToolsShowcase();
    if (self.sandbox.importedPlacement()) |place| {
        self.mesh_tools.base = place.base;
        self.mesh_tools.yaw = place.yaw;
        self.mesh_tools.model_scale = place.scale;
    }
    for (self.tool_events[0..self.tool_event_len]) |event| {
        const result = switch (event) {
            .press => |p| self.mesh_tools.press(p.ray, p.extend),
            .drag => |ray| self.mesh_tools.drag(ray),
            .release => self.mesh_tools.release(),
            .control => |c| self.applyToolAction(self.mesh_tools.control(c) catch |err| blk: {
                self.report("VERTEX TOOLS {s}", .{@errorName(err)});
                break :blk .none;
            }),
        };
        result catch |err| self.report("VERTEX TOOLS {s}", .{@errorName(err)});
        if (!self.mesh_tools.active) break;
    }
    self.tool_event_len = 0;
    if (!self.mesh_tools.active) return;
    const editor = &self.mesh_tools.editor.?;
    if (editor.topology_changed) {
        // Vertex and index counts changed: re-register the model so the renderer rebuilds its
        // buffers (a new handle generation), and let go of the part library, whose part ids
        // were keyed to the old vertices.
        editor.topology_changed = false;
        _ = editor.takeDirty();
        editor.indices_dirty = false;
        if (self.mesh_library_bake) |bake| {
            bake.deinit(self.allocator);
            self.allocator.destroy(bake);
            self.mesh_library_bake = null;
        }
        if (!self.mesh_library_detached) self.report("TOPOLOGY CHANGED: PART LIBRARY DETACHED FROM THIS MESH", .{});
        self.mesh_library_detached = true;
        self.vertex_edits_pending = true;
        creator.imported_status = .unsaved;
        const copy = MeshModel.clone(self.allocator, entry.model) catch |err| return self.report("TOPOLOGY UPDATE FAILED {s}", .{@errorName(err)});
        self.catalog.replaceHandle(self.allocator, handle, copy) catch |err| return self.report("TOPOLOGY UPDATE FAILED {s}", .{@errorName(err)});
        // `replaceHandle` reuses the entry's storage, so the editor's model pointer stays valid.
    }
    const dirty = editor.takeDirty();
    if (dirty.len > 0 or editor.indices_dirty) {
        entry.model.revision +%= 1;
        renderer.queueMeshPatch(.{ .handle = handle.*, .model = &entry.model, .all_vertices = true, .all_indices = editor.indices_dirty });
        editor.indices_dirty = false;
        creator.imported_status = .unsaved;
        self.vertex_edits_pending = true;
    }
    const width: f32 = @floatFromInt(if (renderer.width == 0) 1280 else renderer.width);
    const height: f32 = @floatFromInt(if (renderer.height == 0) 800 else renderer.height);
    self.tool_aspect = width / height;
    self.mesh_tools.aim(&self.engine.camera);
    self.tool_camera = self.engine.camera;
    self.mesh_tools.refreshOverlay(self.engine.camera, self.tool_aspect);
}

/// `-Dcharacter-showcase=48`: the same edits a player makes with the panel, for a capture: the
/// upper body filled with the armour cel pen in blue, a glowing accent band at the waist, a
/// sculpted bulge on the chest, an edges-and-cavities pass, and the head left selected under the move
/// gizmo to show the selection overlay.
fn scriptToolsShowcase(self: *App) void {
    self.tools_showcase_done = true;
    const tools = &self.mesh_tools;
    const e = &tools.editor.?;
    const lo = e.model.bounds_min;
    const hi = e.model.bounds_max;
    const h = hi[1] - lo[1];
    const centre: MeshTools.V = .{ (lo[0] + hi[0]) / 2, 0, (lo[2] + hi[2]) / 2 };
    const Material = @import("character/mesh.zig").Material;
    const script = struct {
        fn band(editor: *@import("asset/MeshEdit.zig").Editor, from: f32, to: f32) void {
            editor.clearSelection();
            for (editor.model.mesh.vertices, 0..) |v, i| if (v.position[1] >= from and v.position[1] < to) editor.selection.set(i);
        }
    };
    (struct {
        fn run(t: *MeshTools, ed: *@import("asset/MeshEdit.zig").Editor, l: [3]f32, height: f32, c: MeshTools.V) !void {
            script.band(ed, l[1] + 0.55 * height, l[1] + 0.82 * height);
            ed.begin();
            try ed.fillSelectionPen(@intFromEnum(Material.armor));
            try ed.fillSelection(MeshTools.swatches[6]);
            try ed.end();
            script.band(ed, l[1] + 0.5 * height, l[1] + 0.54 * height);
            ed.begin();
            try ed.fillSelectionPen(@intFromEnum(Material.accent));
            try ed.fillSelection(MeshTools.swatches[3]);
            try ed.end();
            // Sculpt the chest: aim at it from in front (either facing) and dab the draw brush.
            const chest_y = l[1] + 0.68 * height;
            for ([_]f32{ 1, -1 }) |side| {
                if (ed.raycast(.{ c[0], chest_y, c[2] + side * height * 3 }, .{ 0, 0, -side })) |hit| {
                    ed.begin();
                    for (0..6) |_| try ed.dab(.draw, .{ .center = hit.point, .radius = 0.08 * height, .strength = 0.05 });
                    try ed.end();
                    // Topology (S4): extrude a small chest patch outward, as an emblem plate.
                    ed.clearSelection();
                    ed.selectFacesInSphere(hit.point, 0.035 * height, true);
                    _ = ed.extrudeSelectedFaces(0.02 * height) catch |err| std.log.warn("showcase extrude: {s}", .{@errorName(err)});
                    break;
                }
            }
            // Edges and cavities over the whole mesh: dark crevices, light ridges (S2).
            ed.clearSelection();
            ed.begin();
            try ed.gradientFill(.{ .curvature = .{ .contrast = 6 } }, @import("asset/MeshEdit.zig").Ramp.two(.{ 0.02, 0.03, 0.06 }, .{ 0.9, 0.95, 1 }), 0.85);
            try ed.end();
            script.band(ed, l[1] + 0.86 * height, l[1] + 2 * height);
            // End on the move gizmo so the capture shows the handles on the selected head.
            t.setTool(.move);
        }
    }).run(tools, e, lo, h, centre) catch |err| std.log.err("vertex tools showcase failed: {s}", .{@errorName(err)});
    std.log.info("Vertex tools showcase: {d} undo steps, {d} vertices selected, {d} vertices in the mesh", .{ e.undo_stack.items.len, e.selectedCount(), e.model.mesh.vertices.len });
}

fn applyToolAction(self: *App, action: MeshTools.Action) void {
    switch (action) {
        .none => {},
        .close => {
            self.mesh_tools.unbind();
            self.sandbox.creator.vertex_tools = false;
        },
        .tear_off => self.tearOffPart(),
        .save => {
            if (self.saveEditedMesh()) {
                self.sandbox.creator.imported_status = .saved;
                self.report("EDITED MESH SAVED", .{});
            }
        },
        .discard => self.discardEditedMesh(),
    }
}

/// Saves the selected faces as a standalone runtime model under saves/parts and removes them
/// from the edited mesh (undoable).
fn tearOffPart(self: *App) void {
    var part = self.mesh_tools.tearOff(self.allocator) catch |err| {
        if (err == error.EmptySelection) return self.report("SELECT A PIECE TO TEAR OFF", .{});
        return self.report("TEAR OFF FAILED {s}", .{@errorName(err)});
    };
    defer part.deinit(self.allocator);
    const bytes = part.encode(self.allocator) catch |err| return self.report("PART SAVE FAILED {s}", .{@errorName(err)});
    defer self.allocator.free(bytes);
    var path_buffer: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buffer, "saves/parts/part-{d}.hwmesh", .{self.mesh_tools.parts_saved}) catch unreachable;
    Save.writeFile(self.io, path, bytes) catch |err| return self.report("PART SAVE FAILED {s}", .{@errorName(err)});
    self.report("PART SAVED {s}  ({d} VERTICES)", .{ path, part.mesh.vertices.len });
}

/// The catalog's immutable source snapshot and part lookup caches live for the editor session;
/// normal appearance edits update only the selected component's CPU and GPU ranges.
fn applyMeshLibraryPreview(self: *App, renderer: *Renderer) void {
    if (!self.mesh_library_preview_dirty) return;
    if (self.mesh_library_detached) {
        self.mesh_library_preview_dirty = false;
        return;
    }
    const handle = &self.catalog.content.captain_test;
    const entry = self.catalog.meshMut(handle.*) orelse return;
    if (!entry.ready) return;
    if (self.mesh_library_bake == null) {
        const bake = self.allocator.create(MeshModifiers.Bake) catch |err| {
            std.log.err("character library bake allocation failed: {s}", .{@errorName(err)});
            self.mesh_library_preview_dirty = false;
            return;
        };
        bake.* = MeshModifiers.Bake.init(self.allocator, entry.model, self.mesh_library) catch |err| {
            self.allocator.destroy(bake);
            std.log.err("character library bake setup failed: {s}", .{@errorName(err)});
            self.mesh_library_preview_dirty = false;
            return;
        };
        self.mesh_library_bake = bake;
        bake.applyAll(&entry.model, self.mesh_library) catch |err| {
            std.log.err("character library initial bake failed: {s}", .{@errorName(err)});
            self.mesh_library_preview_dirty = false;
            return;
        };
        _ = self.sandbox.creator.takeImportedDirty();
        renderer.queueMeshPatch(.{ .handle = handle.*, .model = &entry.model, .all_vertices = true, .all_indices = true });
    } else {
        const bake = self.mesh_library_bake.?;
        const dirty = self.sandbox.creator.takeImportedDirty();
        if (dirty.all) {
            bake.applyAll(&entry.model, self.mesh_library) catch |err| {
                std.log.err("character library full preview update failed: {s}", .{@errorName(err)});
                self.mesh_library_preview_dirty = false;
                return;
            };
            renderer.queueMeshPatch(.{ .handle = handle.*, .model = &entry.model, .all_vertices = true, .all_indices = true });
        } else for (dirty.ids[0..dirty.len]) |id| {
            const slot = bake.slots.indexOf(id) orelse {
                std.log.err("character library part {d} is missing from cached analysis", .{id});
                self.mesh_library_preview_dirty = false;
                return;
            };
            bake.updatePart(&entry.model, self.mesh_library, id) catch |err| {
                std.log.err("character library part update failed: {s}", .{@errorName(err)});
                self.mesh_library_preview_dirty = false;
                return;
            };
            renderer.queueMeshPatch(.{ .handle = handle.*, .model = &entry.model, .vertex_indices = bake.vertices.of(slot), .triangle_offsets = bake.triangles.of(slot) });
        }
    }
    self.mesh_library_preview_dirty = false;
}

fn destroyMeshLibraryBake(self: *App) void {
    // The vertex tools mirror their edits into the bake's base copy; let go of it first. They
    // rebind to whatever mesh is current on the next frame.
    self.mesh_tools.unbind();
    if (self.mesh_library_bake) |bake| {
        bake.deinit(self.allocator);
        self.allocator.destroy(bake);
        self.mesh_library_bake = null;
    }
}

/// Lays out this frame's GUI in canvas units (720 tall at interface size 100%) and keeps its
/// clickable areas for the next mouse events. Art-review showcases of the city draw none.
fn publishGui(self: *App, renderer: *Renderer, minutes: u32) void {
    const width: f32 = @floatFromInt(if (renderer.width == 0) 1280 else renderer.width);
    const height: f32 = @floatFromInt(if (renderer.height == 0) 800 else renderer.height);
    self.ui_height = 720 / self.menu.settings.ui_scale;
    renderer.ui.reset(self.ui_height * width / height, self.ui_height);
    self.hit_len = 0;
    if ((options.showcase != 0 and options.showcase < 18) or options.showcase == 47 or options.showcase == 62 or options.showcase == 63 or options.showcase == 66) return;
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
        .scroll = self.ui_scroll,
        .special_keys = .{
            @import("game/Bindings.zig").keyName(self.menu.settings.bindings.key(.special_1), &special_keys[0]),
            @import("game/Bindings.zig").keyName(self.menu.settings.bindings.key(.special_2), &special_keys[1]),
            @import("game/Bindings.zig").keyName(self.menu.settings.bindings.key(.special_3), &special_keys[2]),
        },
    });
    self.hit_len = ui.hit_len;
    @memcpy(self.hits[0..ui.hit_len], ui.hits[0..ui.hit_len]);
    self.scrollGui(ui);
}

/// Next frame's GUI scroll: a new screen starts at the top; a new selection is scrolled into
/// view; the right stick and mouse wheel scroll freely in between.
fn scrollGui(self: *App, ui: *const @import("ui/Canvas.zig")) void {
    const sb = &self.sandbox;
    const key: u32 = @as(u32, @intFromEnum(self.menu.screen)) | @as(u32, @intFromBool(sb.creator.open)) << 8 | @as(u32, @intFromBool(sb.talk != null)) << 9 | @as(u32, @intFromBool(sb.shop != null)) << 10 | @as(u32, @intFromBool(sb.trading != null)) << 11;
    if (key != self.ui_scroll_key) {
        self.ui_scroll_key = key;
        self.ui_scroll = 0;
        self.ui_scroll_focus = null;
    }
    const focus: ?[4]f32 = if (ui.focused) |f| .{ f.x, f.y, f.w, f.h } else null;
    const moved = !std.meta.eql(focus, self.ui_scroll_focus);
    self.ui_scroll_focus = focus;
    self.ui_scroll = ui.nextScroll(self.ui_scroll + self.ui_scroll_free, moved);
    self.ui_scroll_free = 0;
}

pub fn stop(self: *App) void {
    self.thread.join();
    if (options.benchmark_frontier) self.reportFrontierBenchmark();
    if (self.audio) |a| a.destroy();
    if (self.loader) |l| l.destroy();
    if (self.reload) |r| r.destroy();
    if (self.test_mode_save) |baseline| self.allocator.free(baseline);
    self.mesh_tools.deinit();
    self.destroyMeshLibraryBake();
    if (self.queued_character_model) |model| model.deinit(self.allocator);
    self.mesh_library_arena.deinit();
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
