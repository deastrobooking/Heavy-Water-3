//! Runs mod scripts for `script` devices. Script API v1: a script is a WebAssembly export
//! `fn(a, b, c, d, time: f32) f32` in a mod's module, with no imports. Each call has a fuel
//! budget; globals (including the compiler's stack pointer) are reset after every call, so a
//! script is a function of its inputs and time. A trap or budget overrun yields 0 and is
//! counted; it never stops the world.
const std = @import("std");
const Wasm = @import("Wasm.zig");
const Host = @This();

pub const api_version: u32 = 1;
pub const max_modules = 8;
pub const max_scripts = 32;
pub const name_len = 24;
const signature = [_]Wasm.ValType{ .f32, .f32, .f32, .f32, .f32 };

const Loaded = struct { name: [name_len]u8, module: Wasm.Module, instance: Wasm.Instance, fuel: u64 };
pub const Script = struct { module: u8, function: u32, name: [48]u8 };
pub const Stats = struct { calls: u64 = 0, traps: u64 = 0, missing: u64 = 0, max_fuel: u64 = 0 };

allocator: std.mem.Allocator,
modules: [max_modules]?Loaded = @splat(null),
scripts: [max_scripts]Script = undefined,
script_count: usize = 0,
stats: Stats = .{},
last_trap: ?anyerror = null,

pub fn init(allocator: std.mem.Allocator) Host {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Host) void {
    for (&self.modules) |*slot| if (slot.*) |*m| {
        m.instance.deinit();
        m.module.deinit();
        slot.* = null;
    };
}

/// Loads `wasm` as mod `mod`'s script module and registers `exports` as "mod.export".
/// Nothing is registered unless every export exists with the script signature.
pub fn add(self: *Host, mod: []const u8, wasm: []const u8, exports: []const []const u8, fuel: u64, memory_pages: u32) !void {
    if (mod.len == 0 or mod.len >= name_len) return error.InvalidModName;
    if (self.script_count + exports.len > max_scripts) return error.TooManyScripts;
    const slot = for (&self.modules, 0..) |*m, i| {
        if (m.* == null) break i;
    } else return error.TooManyModules;
    var module = try Wasm.load(self.allocator, wasm);
    var functions: [max_scripts]u32 = undefined;
    for (exports, 0..) |name, i| {
        const f = module.exportedFunction(name) orelse {
            module.deinit();
            return error.MissingExport;
        };
        const t = module.functionType(f);
        if (!std.mem.eql(Wasm.ValType, t.params, &signature) or t.results.len != 1 or t.results[0] != .f32 or mod.len + 1 + name.len >= 48) {
            module.deinit();
            return error.WrongScriptSignature;
        }
        functions[i] = f;
    }
    // An instance points at its module, so the module moves into its slot first.
    self.modules[slot] = .{ .name = @splat(0), .module = module, .instance = undefined, .fuel = fuel };
    const loaded = &self.modules[slot].?;
    @memcpy(loaded.name[0..mod.len], mod);
    loaded.instance = Wasm.Instance.init(self.allocator, &loaded.module, .{ .max_memory_pages = memory_pages }) catch |err| {
        loaded.module.deinit();
        self.modules[slot] = null;
        return err;
    };
    for (exports, 0..) |name, i| {
        var s: Script = .{ .module = @intCast(slot), .function = functions[i], .name = @splat(0) };
        _ = std.fmt.bufPrint(&s.name, "{s}.{s}", .{ mod, name }) catch unreachable;
        self.scripts[self.script_count] = s;
        self.script_count += 1;
    }
}

pub fn find(self: *const Host, name: []const u8) ?usize {
    for (self.scripts[0..self.script_count], 0..) |s, i| if (std.mem.eql(u8, std.mem.sliceTo(&s.name, 0), name)) return i;
    return null;
}

/// Runs script `name`; missing scripts and traps give 0. Non-finite results also give 0.
pub fn call(self: *Host, name: []const u8, inputs: [4]f32, time: f32) f32 {
    const i = self.find(name) orelse {
        self.stats.missing += 1;
        return 0;
    };
    const s = self.scripts[i];
    const loaded = &self.modules[s.module].?;
    self.stats.calls += 1;
    defer loaded.instance.resetGlobals();
    const out = loaded.instance.callF32(s.function, &.{ inputs[0], inputs[1], inputs[2], inputs[3], time }, loaded.fuel) catch |err| {
        self.stats.traps += 1;
        self.last_trap = err;
        return 0;
    };
    self.stats.max_fuel = @max(self.stats.max_fuel, loaded.instance.used);
    return if (std.math.isFinite(out)) out else 0;
}

/// The same functions compiled natively, for comparing interpreter results.
const native = struct {
    fn breathe(a: f32, time: f32) f32 {
        if (a < 0.5) return 0;
        return 0.55 + 0.45 * @sin(time * 2 * std.math.pi / 4);
    }
};

test "the Zig-compiled example mod runs in the interpreter and matches native results" {
    var host = Host.init(std.testing.allocator);
    defer host.deinit();
    try host.add("glowworks", @embedFile("glowworks.wasm"), &.{ "breathe", "majority" }, 20000, 4);
    try std.testing.expectEqual(@as(?usize, 1), host.find("glowworks.majority"));
    // Breathe: the interpreter's libm-based sine agrees with native code over a minute.
    var t: f32 = 0;
    while (t < 60) : (t += 0.37) {
        try std.testing.expectApproxEqAbs(native.breathe(1, t), host.call("glowworks.breathe", .{ 1, 0, 0, 0 }, t), 1e-6);
    }
    try std.testing.expectEqual(@as(f32, 0), host.call("glowworks.breathe", .{ 0, 0, 0, 0 }, 3));
    // Majority: the full truth table, with d inverting.
    for (0..16) |bits| {
        const v = [4]f32{ @floatFromInt(bits & 1), @floatFromInt(bits >> 1 & 1), @floatFromInt(bits >> 2 & 1), @floatFromInt(bits >> 3 & 1) };
        const votes = (bits & 1) + (bits >> 1 & 1) + (bits >> 2 & 1);
        const want: f32 = if ((votes >= 2) != (bits >> 3 & 1 == 1)) 1 else 0;
        try std.testing.expectEqual(want, host.call("glowworks.majority", v, 0));
    }
    try std.testing.expectEqual(@as(u64, 0), host.stats.traps);
    try std.testing.expect(host.stats.max_fuel > 0 and host.stats.max_fuel < 20000);
    // Unknown scripts give 0 and are counted.
    try std.testing.expectEqual(@as(f32, 0), host.call("glowworks.nothing", .{ 1, 1, 1, 1 }, 0));
    try std.testing.expectEqual(@as(u64, 1), host.stats.missing);
    // A starved budget traps cleanly to 0, and the next normal call still works.
    host.modules[0].?.fuel = 5;
    try std.testing.expectEqual(@as(f32, 0), host.call("glowworks.breathe", .{ 1, 0, 0, 0 }, 1));
    try std.testing.expectEqual(error.OutOfFuel, host.last_trap.?);
    host.modules[0].?.fuel = 20000;
    try std.testing.expectApproxEqAbs(native.breathe(1, 1), host.call("glowworks.breathe", .{ 1, 0, 0, 0 }, 1), 1e-6);
}

test "exports must exist with the script signature, and modules need no imports" {
    var host = Host.init(std.testing.allocator);
    defer host.deinit();
    try std.testing.expectError(error.MissingExport, host.add("glowworks", @embedFile("glowworks.wasm"), &.{"glow"}, 1000, 4));
    try std.testing.expectError(error.InvalidModule, host.add("broken", "\x00asm\x01\x00", &.{}, 1000, 4));
    try std.testing.expectEqual(@as(usize, 0), host.script_count);
    for (host.modules) |m| try std.testing.expect(m == null);
}

/// Moves a validated replacement out of a staging host. Export names stay stable; function
/// indices may change. No allocations or callbacks happen after old state is retired.
pub fn replaceFrom(self: *Host, staged: *Host) !void {
    const source = for (&staged.modules, 0..) |*m, i| {
        if (m.* != null) break i;
    } else return error.MissingModule;
    const name = std.mem.sliceTo(&staged.modules[source].?.name, 0);
    const destination = for (&self.modules, 0..) |*m, i| {
        if (m.*) |*loaded| if (std.mem.eql(u8, std.mem.sliceTo(&loaded.name, 0), name)) break i;
    } else return error.MissingModule;
    var functions: [max_scripts]u32 = undefined;
    var count: usize = 0;
    for (self.scripts[0..self.script_count], 0..) |script, i| {
        if (script.module != destination) continue;
        const match = staged.find(std.mem.sliceTo(&script.name, 0)) orelse return error.MissingExport;
        functions[i] = staged.scripts[match].function;
        count += 1;
    }
    if (count != staged.script_count) return error.ExportSetChanged;
    self.modules[destination].?.instance.deinit();
    self.modules[destination].?.module.deinit();
    self.modules[destination] = staged.modules[source];
    staged.modules[source] = null;
    self.modules[destination].?.instance.module = &self.modules[destination].?.module;
    for (self.scripts[0..self.script_count], 0..) |*script, i| if (script.module == destination) {
        script.function = functions[i];
    };
}
