//! A native Zig WebAssembly interpreter for mod scripts: the WebAssembly 1.0 core instruction
//! set plus the sign-extension, non-trapping float-to-int, bulk-memory and multi-value
//! extensions that the pinned Zig compiler emits for `wasm32-freestanding`.
//!
//! The sandbox is the interpreter itself: modules may not import anything (no host calls, no
//! I/O), every call runs under an instruction budget ("fuel"), linear memory is capped and
//! every access is bounds-checked, and call depth and stack sizes are fixed. Structural checks
//! run at load (sections, indices, block nesting); operand types are not statically validated,
//! but values live in untyped 64-bit slots and every stack, local, global, table and memory
//! access is checked at run time, so a malformed module can compute nonsense or trap but
//! cannot reach outside its instance.
const std = @import("std");
const Wasm = @This();

pub const ValType = enum(u8) { i32 = 0x7f, i64 = 0x7e, f32 = 0x7d, f64 = 0x7c };
pub const FuncType = struct { params: []const ValType, results: []const ValType };
pub const LoadError = error{ InvalidModule, Unsupported, OutOfMemory };
pub const Trap = error{
    Unreachable,
    OutOfFuel,
    MemoryOutOfBounds,
    DivideByZero,
    IntegerOverflow,
    InvalidConversion,
    StackOverflow,
    StackUnderflow,
    CallDepthExceeded,
    IndirectCallTypeMismatch,
    UndefinedElement,
    UnknownFunction,
    InvalidOpcode,
};
pub const page_size = 65536;

const Jump = struct { else_pc: u32 = 0, end_pc: u32 = 0 };
const Function = struct {
    type_index: u32,
    locals: []ValType,
    /// Body expression: offsets into `Module.bytes`.
    start: u32,
    end: u32,
};
const Global = struct { type: ValType, mutable: bool, init: u64 };
const Data = struct { offset: ?u32, bytes: []const u8 };
const Export = struct { name: []const u8, kind: u8, index: u32 };

/// A parsed, structurally checked module. Owns a copy of the binary.
pub const Module = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    types: []FuncType,
    functions: []Function,
    globals: []Global,
    exports: []Export,
    data: []Data,
    /// Table 0 initialised from active element segments (function indices).
    table: []?u32,
    memory_min: u32 = 0,
    memory_max: ?u32 = null,
    has_memory: bool = false,
    /// Block, loop and if opcodes' matching else/end, keyed by opcode offset.
    jumps: std.AutoHashMapUnmanaged(u32, Jump) = .empty,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Module) void {
        self.jumps.deinit(self.allocator);
        self.arena.deinit();
        self.allocator.free(self.bytes);
    }

    pub fn exportedFunction(self: *const Module, name: []const u8) ?u32 {
        for (self.exports) |e| if (e.kind == 0 and std.mem.eql(u8, e.name, name)) return e.index;
        return null;
    }

    pub fn functionType(self: *const Module, index: u32) FuncType {
        return self.types[self.functions[index].type_index];
    }
};

const Reader = struct {
    bytes: []const u8,
    pos: usize,

    fn byte(r: *Reader) LoadError!u8 {
        if (r.pos >= r.bytes.len) return error.InvalidModule;
        r.pos += 1;
        return r.bytes[r.pos - 1];
    }
    fn uleb(r: *Reader, comptime T: type) LoadError!T {
        var result: u64 = 0;
        var shift: u7 = 0;
        while (true) {
            const b = try r.byte();
            if (shift >= @bitSizeOf(T) + 7) return error.InvalidModule;
            result |= @as(u64, b & 0x7f) << @intCast(@min(shift, 63));
            if (b & 0x80 == 0) break;
            shift += 7;
        }
        if (result > std.math.maxInt(T)) return error.InvalidModule;
        return @intCast(result);
    }
    fn sleb(r: *Reader, comptime T: type) LoadError!T {
        const U = std.meta.Int(.unsigned, @bitSizeOf(T));
        var result: u64 = 0;
        var shift: u7 = 0;
        var b: u8 = 0;
        while (true) {
            b = try r.byte();
            if (shift >= @bitSizeOf(T) + 7) return error.InvalidModule;
            if (shift < 64) result |= @as(u64, b & 0x7f) << @intCast(shift);
            shift += 7;
            if (b & 0x80 == 0) break;
        }
        if (shift < 64 and b & 0x40 != 0) result |= ~@as(u64, 0) << @intCast(shift);
        return @bitCast(@as(U, @truncate(result)));
    }
    fn bytesN(r: *Reader, n: usize) LoadError![]const u8 {
        if (n > r.bytes.len - r.pos) return error.InvalidModule;
        r.pos += n;
        return r.bytes[r.pos - n .. r.pos];
    }
    fn valtype(r: *Reader) LoadError!ValType {
        return switch (try r.byte()) {
            0x7f => .i32,
            0x7e => .i64,
            0x7d => .f32,
            0x7c => .f64,
            else => error.Unsupported,
        };
    }
};

/// Parses `bytes` (copied). Imports and start functions are rejected: scripts are pure.
pub fn load(allocator: std.mem.Allocator, input: []const u8) LoadError!Module {
    const bytes = try allocator.dupe(u8, input);
    errdefer allocator.free(bytes);
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    var m: Module = .{ .allocator = allocator, .bytes = bytes, .types = &.{}, .functions = &.{}, .globals = &.{}, .exports = &.{}, .data = &.{}, .table = &.{}, .arena = undefined };
    errdefer m.jumps.deinit(allocator);
    var r: Reader = .{ .bytes = bytes, .pos = 0 };
    if (!std.mem.eql(u8, try r.bytesN(8), "\x00asm\x01\x00\x00\x00")) return error.InvalidModule;
    var function_types: []u32 = &.{};
    while (r.pos < bytes.len) {
        const id = try r.byte();
        const size = try r.uleb(u32);
        const body = try r.bytesN(size);
        var s: Reader = .{ .bytes = bytes, .pos = @intFromPtr(body.ptr) - @intFromPtr(bytes.ptr) };
        const section_end = s.pos + size;
        switch (id) {
            0, 12 => {},
            1 => {
                m.types = try a.alloc(FuncType, try s.uleb(u32));
                for (m.types) |*t| {
                    if (try s.byte() != 0x60) return error.InvalidModule;
                    const params = try a.alloc(ValType, try s.uleb(u32));
                    for (params) |*p| p.* = try s.valtype();
                    const results = try a.alloc(ValType, try s.uleb(u32));
                    for (results) |*p| p.* = try s.valtype();
                    t.* = .{ .params = params, .results = results };
                }
            },
            2 => if (try s.uleb(u32) != 0) return error.Unsupported,
            3 => {
                function_types = try a.alloc(u32, try s.uleb(u32));
                for (function_types) |*t| {
                    t.* = try s.uleb(u32);
                    if (t.* >= m.types.len) return error.InvalidModule;
                }
            },
            4 => {
                const n = try s.uleb(u32);
                if (n > 1) return error.Unsupported;
                if (n == 1) {
                    if (try s.byte() != 0x70) return error.Unsupported;
                    const flags = try s.byte();
                    const min = try s.uleb(u32);
                    if (flags & 1 != 0) _ = try s.uleb(u32);
                    if (min > 65536) return error.Unsupported;
                    m.table = try a.alloc(?u32, min);
                    @memset(m.table, null);
                }
            },
            5 => {
                const n = try s.uleb(u32);
                if (n > 1) return error.Unsupported;
                if (n == 1) {
                    const flags = try s.byte();
                    m.memory_min = try s.uleb(u32);
                    if (flags & 1 != 0) m.memory_max = try s.uleb(u32);
                    m.has_memory = true;
                }
            },
            6 => {
                m.globals = try a.alloc(Global, try s.uleb(u32));
                for (m.globals) |*g| {
                    g.type = try s.valtype();
                    g.mutable = try s.byte() == 1;
                    g.init = try constExpr(&s, m.globals[0 .. g - m.globals.ptr]);
                }
            },
            7 => {
                m.exports = try a.alloc(Export, try s.uleb(u32));
                for (m.exports) |*e| {
                    e.name = try s.bytesN(try s.uleb(u32));
                    e.kind = try s.byte();
                    e.index = try s.uleb(u32);
                }
            },
            8 => return error.Unsupported,
            9 => {
                const n = try s.uleb(u32);
                for (0..n) |_| {
                    if (try s.uleb(u32) != 0) return error.Unsupported;
                    const offset: u32 = @truncate(try constExpr(&s, m.globals));
                    const count = try s.uleb(u32);
                    for (0..count) |i| {
                        const f = try s.uleb(u32);
                        if (offset + i >= m.table.len) return error.InvalidModule;
                        m.table[offset + i] = f;
                    }
                }
            },
            10 => {
                const n = try s.uleb(u32);
                if (n != function_types.len) return error.InvalidModule;
                m.functions = try a.alloc(Function, n);
                for (m.functions, function_types) |*f, t| {
                    const len = try s.uleb(u32);
                    const end = s.pos + len;
                    var locals: std.ArrayListUnmanaged(ValType) = .empty;
                    const groups = try s.uleb(u32);
                    for (0..groups) |_| {
                        const count = try s.uleb(u32);
                        if (count > 50000 or locals.items.len + count > 50000) return error.Unsupported;
                        const v = try s.valtype();
                        try locals.appendNTimes(a, v, count);
                    }
                    f.* = .{ .type_index = t, .locals = locals.items, .start = @intCast(s.pos), .end = @intCast(end) };
                    try scanJumps(allocator, &m.jumps, bytes, s.pos, end);
                    s.pos = end;
                }
            },
            11 => {
                m.data = try a.alloc(Data, try s.uleb(u32));
                for (m.data) |*d| {
                    const flags = try s.uleb(u32);
                    if (flags == 2 and try s.uleb(u32) != 0) return error.Unsupported;
                    d.offset = if (flags == 1) null else @truncate(try constExpr(&s, m.globals));
                    d.bytes = try s.bytesN(try s.uleb(u32));
                }
            },
            else => return error.InvalidModule,
        }
        if (s.pos != section_end) return error.InvalidModule;
    }
    if (function_types.len != m.functions.len) return error.InvalidModule;
    for (m.exports) |e| if (e.kind == 0 and e.index >= m.functions.len) return error.InvalidModule;
    for (m.table) |entry| if (entry) |f| if (f >= m.functions.len) return error.InvalidModule;
    m.arena = arena;
    return m;
}

fn constExpr(r: *Reader, globals: []const Global) LoadError!u64 {
    const op = try r.byte();
    const v: u64 = switch (op) {
        0x41 => @as(u32, @bitCast(try r.sleb(i32))),
        0x42 => @bitCast(try r.sleb(i64)),
        0x43 => std.mem.readInt(u32, (try r.bytesN(4))[0..4], .little),
        0x44 => std.mem.readInt(u64, (try r.bytesN(8))[0..8], .little),
        0x23 => blk: {
            const i = try r.uleb(u32);
            if (i >= globals.len) return error.InvalidModule;
            break :blk globals[i].init;
        },
        else => return error.Unsupported,
    };
    if (try r.byte() != 0x0b) return error.InvalidModule;
    return v;
}

/// Skips an instruction's immediates (the opcode has already been read).
fn skipImmediates(r: *Reader, op: u8) LoadError!void {
    switch (op) {
        0x02, 0x03, 0x04 => _ = try r.sleb(i64), // block type: 0x40, a value type, or a type index
        0x0c, 0x0d, 0x10, 0x20...0x24 => _ = try r.uleb(u32),
        0x0e => {
            const n = try r.uleb(u32);
            for (0..n + 1) |_| _ = try r.uleb(u32);
        },
        0x11 => {
            _ = try r.uleb(u32);
            _ = try r.uleb(u32);
        },
        0x1c => {
            const n = try r.uleb(u32);
            for (0..n) |_| _ = try r.byte();
        },
        0x28...0x3e => {
            _ = try r.uleb(u32);
            _ = try r.uleb(u32);
        },
        0x3f, 0x40 => _ = try r.byte(),
        0x41 => _ = try r.sleb(i32),
        0x42 => _ = try r.sleb(i64),
        0x43 => _ = try r.bytesN(4),
        0x44 => _ = try r.bytesN(8),
        0xfc => switch (try r.uleb(u32)) {
            0...7 => {},
            8 => {
                _ = try r.uleb(u32);
                _ = try r.byte();
            },
            9 => _ = try r.uleb(u32),
            10 => {
                _ = try r.byte();
                _ = try r.byte();
            },
            11 => _ = try r.byte(),
            else => return error.Unsupported,
        },
        0x00, 0x01, 0x05, 0x0b, 0x0f, 0x1a, 0x1b, 0x45...0xc4 => {},
        else => return error.Unsupported,
    }
}

fn scanJumps(allocator: std.mem.Allocator, jumps: *std.AutoHashMapUnmanaged(u32, Jump), bytes: []const u8, start: usize, end: usize) LoadError!void {
    var r: Reader = .{ .bytes = bytes[0..end], .pos = start };
    var open: [1024]u32 = undefined;
    var depth: usize = 0;
    while (r.pos < end) {
        const at: u32 = @intCast(r.pos);
        const op = try r.byte();
        try skipImmediates(&r, op);
        switch (op) {
            0x02, 0x03, 0x04 => {
                if (depth == open.len) return error.Unsupported;
                open[depth] = at;
                depth += 1;
                try jumps.put(allocator, at, .{});
            },
            0x05 => {
                if (depth == 0) return error.InvalidModule;
                jumps.getPtr(open[depth - 1]).?.else_pc = at;
            },
            0x0b => {
                if (depth == 0) {
                    if (r.pos != end) return error.InvalidModule;
                    return;
                }
                depth -= 1;
                jumps.getPtr(open[depth]).?.end_pc = at;
            },
            else => {},
        }
    }
    return error.InvalidModule;
}

pub const Limits = struct {
    max_memory_pages: u32 = 64,
    stack_values: usize = 16384,
    max_labels: usize = 4096,
    max_frames: usize = 128,
};

const Label = struct { height: u32, arity: u32, cont: u32, loop: bool, func: bool };
const Frame = struct { func: u32, locals: u32, return_pc: u32, labels: u32 };

/// An instantiated module: memory, globals, table, and fixed-size execution stacks.
pub const Instance = struct {
    module: *const Module,
    allocator: std.mem.Allocator,
    limits: Limits,
    memory: []u8,
    globals: []u64,
    initial_globals: []u64,
    table: []?u32,
    stack: []u64,
    labels: []Label,
    frames: []Frame,
    dropped: []bool,
    /// Instructions executed by the last call.
    used: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, module: *const Module, limits: Limits) !Instance {
        if (module.memory_min > limits.max_memory_pages) return error.MemoryLimit;
        const memory = try allocator.alloc(u8, @as(usize, module.memory_min) * page_size);
        errdefer allocator.free(memory);
        @memset(memory, 0);
        const globals = try allocator.alloc(u64, module.globals.len);
        errdefer allocator.free(globals);
        for (globals, module.globals) |*g, def| g.* = def.init;
        const initial = try allocator.dupe(u64, globals);
        errdefer allocator.free(initial);
        const table = try allocator.dupe(?u32, module.table);
        errdefer allocator.free(table);
        const dropped = try allocator.alloc(bool, module.data.len);
        errdefer allocator.free(dropped);
        @memset(dropped, false);
        for (module.data) |d| if (d.offset) |o| {
            if (@as(usize, o) + d.bytes.len > memory.len) return error.DataOutOfBounds;
            @memcpy(memory[o..][0..d.bytes.len], d.bytes);
        };
        const stack = try allocator.alloc(u64, limits.stack_values);
        errdefer allocator.free(stack);
        const labels = try allocator.alloc(Label, limits.max_labels);
        errdefer allocator.free(labels);
        const frames = try allocator.alloc(Frame, limits.max_frames);
        return .{ .module = module, .allocator = allocator, .limits = limits, .memory = memory, .globals = globals, .initial_globals = initial, .table = table, .stack = stack, .labels = labels, .frames = frames, .dropped = dropped };
    }

    pub fn deinit(self: *Instance) void {
        const a = self.allocator;
        a.free(self.memory);
        a.free(self.globals);
        a.free(self.initial_globals);
        a.free(self.table);
        a.free(self.stack);
        a.free(self.labels);
        a.free(self.frames);
        a.free(self.dropped);
    }

    /// Restores globals (including the compiler's stack pointer) to their initial values.
    pub fn resetGlobals(self: *Instance) void {
        @memcpy(self.globals, self.initial_globals);
    }

    /// Calls function `index` with raw argument slots and writes raw results. Runs at most
    /// `fuel` instructions.
    pub fn call(self: *Instance, index: u32, args: []const u64, results: []u64, fuel: u64) (Trap || error{BadArity})!void {
        if (index >= self.module.functions.len) return error.UnknownFunction;
        const t = self.module.functionType(index);
        if (args.len != t.params.len or results.len != t.results.len) return error.BadArity;
        @memcpy(self.stack[0..args.len], args);
        var exec: Exec = .{ .inst = self, .sp = @intCast(args.len), .fuel = fuel };
        defer self.used = fuel - exec.fuel;
        try exec.run(index);
        if (exec.sp != results.len) return error.StackUnderflow;
        @memcpy(results, self.stack[0..results.len]);
    }

    /// Convenience for float signals: calls an export taking and returning f32 values.
    pub fn callF32(self: *Instance, index: u32, args: []const f32, fuel: u64) !f32 {
        var raw: [8]u64 = undefined;
        if (args.len > raw.len) return error.BadArity;
        for (args, raw[0..args.len]) |v, *r| r.* = @as(u32, @bitCast(v));
        var out: [1]u64 = undefined;
        try self.call(index, raw[0..args.len], &out, fuel);
        return @bitCast(@as(u32, @truncate(out[0])));
    }
};

const Exec = struct {
    inst: *Instance,
    sp: u32,
    lp: u32 = 0,
    fp: u32 = 0,
    pc: u32 = 0,
    fuel: u64,

    fn push(e: *Exec, v: u64) Trap!void {
        if (e.sp == e.inst.stack.len) return error.StackOverflow;
        e.inst.stack[e.sp] = v;
        e.sp += 1;
    }
    fn pop(e: *Exec) Trap!u64 {
        const floor = if (e.lp > 0) e.inst.labels[e.lp - 1].height else 0;
        if (e.sp <= floor and e.sp == 0) return error.StackUnderflow;
        e.sp -= 1;
        return e.inst.stack[e.sp];
    }
    fn pushI32(e: *Exec, v: u32) Trap!void {
        return e.push(v);
    }
    fn popI32(e: *Exec) Trap!u32 {
        return @truncate(try e.pop());
    }
    fn pushI64(e: *Exec, v: u64) Trap!void {
        return e.push(v);
    }
    fn popF32(e: *Exec) Trap!f32 {
        return @bitCast(try e.popI32());
    }
    fn pushF32(e: *Exec, v: f32) Trap!void {
        return e.push(@as(u32, @bitCast(v)));
    }
    fn popF64(e: *Exec) Trap!f64 {
        return @bitCast(try e.pop());
    }
    fn pushF64(e: *Exec, v: f64) Trap!void {
        return e.push(@as(u64, @bitCast(v)));
    }
    fn pushBool(e: *Exec, b: bool) Trap!void {
        return e.push(@intFromBool(b));
    }

    fn reader(e: *Exec) Reader {
        return .{ .bytes = e.inst.module.bytes, .pos = e.pc };
    }

    fn pushLabel(e: *Exec, label: Label) Trap!void {
        if (e.lp == e.inst.labels.len) return error.StackOverflow;
        e.inst.labels[e.lp] = label;
        e.lp += 1;
    }

    /// Block type → (params, results).
    fn blockArity(e: *Exec, bt: i64) Trap![2]u32 {
        if (bt == -64) return .{ 0, 0 };
        if (bt < 0) return .{ 0, 1 };
        const types = e.inst.module.types;
        if (bt >= types.len) return error.InvalidOpcode;
        const t = types[@intCast(bt)];
        return .{ @intCast(t.params.len), @intCast(t.results.len) };
    }

    fn enter(e: *Exec, func: u32, return_pc: u32) Trap!void {
        const m = e.inst.module;
        if (func >= m.functions.len) return error.UnknownFunction;
        if (e.fp == e.inst.frames.len) return error.CallDepthExceeded;
        const f = m.functions[func];
        const t = m.types[f.type_index];
        if (e.sp < t.params.len) return error.StackUnderflow;
        const locals: u32 = e.sp - @as(u32, @intCast(t.params.len));
        for (f.locals) |_| try e.push(0);
        e.inst.frames[e.fp] = .{ .func = func, .locals = locals, .return_pc = return_pc, .labels = e.lp };
        e.fp += 1;
        try e.pushLabel(.{ .height = e.sp, .arity = @intCast(t.results.len), .cont = f.end, .loop = false, .func = true });
        e.pc = f.start;
    }

    /// Branches to the label `depth` levels out.
    fn branch(e: *Exec, depth: u32) Trap!bool {
        const frame = e.inst.frames[e.fp - 1];
        if (depth >= e.lp - frame.labels) return error.InvalidOpcode;
        const index = e.lp - 1 - depth;
        const label = e.inst.labels[index];
        if (label.func) return e.ret();
        if (e.sp < label.arity) return error.StackUnderflow;
        const arity = label.arity;
        std.mem.copyForwards(u64, e.inst.stack[label.height..][0..arity], e.inst.stack[e.sp - arity .. e.sp]);
        e.sp = label.height + arity;
        if (label.loop) {
            e.lp = index + 1;
        } else {
            e.lp = index;
        }
        e.pc = label.cont;
        return false;
    }

    /// Returns from the current function. True when the outermost call has returned.
    fn ret(e: *Exec) Trap!bool {
        const frame = e.inst.frames[e.fp - 1];
        const t = e.inst.module.functionType(frame.func);
        const n: u32 = @intCast(t.results.len);
        if (e.sp < n or e.sp - n < frame.locals) return error.StackUnderflow;
        std.mem.copyForwards(u64, e.inst.stack[frame.locals..][0..n], e.inst.stack[e.sp - n .. e.sp]);
        e.sp = frame.locals + n;
        e.lp = frame.labels;
        e.fp -= 1;
        e.pc = frame.return_pc;
        return e.fp == 0;
    }

    fn address(e: *Exec, r: *Reader, size: usize) Trap!usize {
        _ = r.uleb(u32) catch return error.InvalidOpcode;
        const offset = r.uleb(u32) catch return error.InvalidOpcode;
        const base = try e.popI32();
        const at = @as(u64, base) + offset;
        if (at + size > e.inst.memory.len) return error.MemoryOutOfBounds;
        return @intCast(at);
    }

    fn load(e: *Exec, r: *Reader, comptime T: type) Trap!T {
        const at = try e.address(r, @sizeOf(T));
        return std.mem.readInt(T, e.inst.memory[at..][0..@sizeOf(T)], .little);
    }

    fn store(e: *Exec, r: *Reader, comptime T: type) Trap!void {
        const v: T = @truncate(try e.pop());
        const at = try e.address(r, @sizeOf(T));
        std.mem.writeInt(T, e.inst.memory[at..][0..@sizeOf(T)], v, .little);
    }

    fn run(e: *Exec, func: u32) Trap!void {
        try e.enter(func, 0);
        while (true) {
            if (e.fuel == 0) return error.OutOfFuel;
            e.fuel -= 1;
            const at = e.pc;
            var r = e.reader();
            const op = r.byte() catch return error.InvalidOpcode;
            e.pc = @intCast(r.pos);
            switch (op) {
                0x00 => return error.Unreachable,
                0x01 => {},
                0x02, 0x03 => {
                    const bt = r.sleb(i64) catch return error.InvalidOpcode;
                    const ar = try e.blockArity(bt);
                    const jump = e.inst.module.jumps.get(at) orelse return error.InvalidOpcode;
                    if (e.sp < ar[0]) return error.StackUnderflow;
                    if (op == 0x02)
                        try e.pushLabel(.{ .height = e.sp - ar[0], .arity = ar[1], .cont = jump.end_pc + 1, .loop = false, .func = false })
                    else
                        try e.pushLabel(.{ .height = e.sp - ar[0], .arity = ar[0], .cont = @intCast(r.pos), .loop = true, .func = false });
                    e.pc = @intCast(r.pos);
                },
                0x04 => {
                    const bt = r.sleb(i64) catch return error.InvalidOpcode;
                    const ar = try e.blockArity(bt);
                    const jump = e.inst.module.jumps.get(at) orelse return error.InvalidOpcode;
                    const cond = try e.popI32();
                    if (e.sp < ar[0]) return error.StackUnderflow;
                    const label: Label = .{ .height = e.sp - ar[0], .arity = ar[1], .cont = jump.end_pc + 1, .loop = false, .func = false };
                    if (cond != 0) {
                        try e.pushLabel(label);
                        e.pc = @intCast(r.pos);
                    } else if (jump.else_pc != 0) {
                        try e.pushLabel(label);
                        e.pc = jump.else_pc + 1;
                    } else e.pc = jump.end_pc + 1;
                },
                0x05 => {
                    // End of a taken then-branch: skip the else arm.
                    const label = e.inst.labels[e.lp - 1];
                    e.lp -= 1;
                    e.pc = label.cont;
                },
                0x0b => {
                    const label = e.inst.labels[e.lp - 1];
                    if (label.func) {
                        if (try e.ret()) return;
                    } else e.lp -= 1;
                },
                0x0c => if (try e.branch(r.uleb(u32) catch return error.InvalidOpcode)) return,
                0x0d => {
                    const depth = r.uleb(u32) catch return error.InvalidOpcode;
                    e.pc = @intCast(r.pos);
                    if (try e.popI32() != 0) if (try e.branch(depth)) return;
                },
                0x0e => {
                    const n = r.uleb(u32) catch return error.InvalidOpcode;
                    const i = try e.popI32();
                    var target: u32 = 0;
                    for (0..n + 1) |k| {
                        const d = r.uleb(u32) catch return error.InvalidOpcode;
                        if (k == @min(i, n)) target = d;
                    }
                    if (try e.branch(target)) return;
                },
                0x0f => if (try e.ret()) return,
                0x10 => try e.enter(r.uleb(u32) catch return error.InvalidOpcode, @intCast(r.pos)),
                0x11 => {
                    const type_index = r.uleb(u32) catch return error.InvalidOpcode;
                    _ = r.uleb(u32) catch return error.InvalidOpcode;
                    const i = try e.popI32();
                    if (i >= e.inst.table.len) return error.UndefinedElement;
                    const f = e.inst.table[i] orelse return error.UndefinedElement;
                    const m = e.inst.module;
                    if (type_index >= m.types.len or !sameType(m.types[type_index], m.functionType(f))) return error.IndirectCallTypeMismatch;
                    try e.enter(f, @intCast(r.pos));
                },
                0x1a => _ = try e.pop(),
                0x1b, 0x1c => {
                    if (op == 0x1c) {
                        const n = r.uleb(u32) catch return error.InvalidOpcode;
                        for (0..n) |_| _ = r.byte() catch return error.InvalidOpcode;
                        e.pc = @intCast(r.pos);
                    }
                    const c = try e.popI32();
                    const b = try e.pop();
                    const a = try e.pop();
                    try e.push(if (c != 0) a else b);
                },
                0x20, 0x21, 0x22 => {
                    const i = r.uleb(u32) catch return error.InvalidOpcode;
                    e.pc = @intCast(r.pos);
                    const frame = e.inst.frames[e.fp - 1];
                    const f = e.inst.module.functions[frame.func];
                    const count = e.inst.module.types[f.type_index].params.len + f.locals.len;
                    if (i >= count) return error.InvalidOpcode;
                    const slot = &e.inst.stack[frame.locals + i];
                    switch (op) {
                        0x20 => try e.push(slot.*),
                        0x21 => slot.* = try e.pop(),
                        else => {
                            slot.* = try e.pop();
                            try e.push(slot.*);
                        },
                    }
                },
                0x23, 0x24 => {
                    const i = r.uleb(u32) catch return error.InvalidOpcode;
                    e.pc = @intCast(r.pos);
                    if (i >= e.inst.globals.len) return error.InvalidOpcode;
                    if (op == 0x23) try e.push(e.inst.globals[i]) else {
                        if (!e.inst.module.globals[i].mutable) return error.InvalidOpcode;
                        e.inst.globals[i] = try e.pop();
                    }
                },
                0x28 => try e.pushI32(try e.load(&r, u32)),
                0x29 => try e.pushI64(try e.load(&r, u64)),
                0x2a => try e.pushI32(try e.load(&r, u32)),
                0x2b => try e.pushI64(try e.load(&r, u64)),
                0x2c => try e.pushI32(@bitCast(@as(i32, @as(i8, @bitCast(try e.load(&r, u8)))))),
                0x2d => try e.pushI32(try e.load(&r, u8)),
                0x2e => try e.pushI32(@bitCast(@as(i32, @as(i16, @bitCast(try e.load(&r, u16)))))),
                0x2f => try e.pushI32(try e.load(&r, u16)),
                0x30 => try e.pushI64(@bitCast(@as(i64, @as(i8, @bitCast(try e.load(&r, u8)))))),
                0x31 => try e.pushI64(try e.load(&r, u8)),
                0x32 => try e.pushI64(@bitCast(@as(i64, @as(i16, @bitCast(try e.load(&r, u16)))))),
                0x33 => try e.pushI64(try e.load(&r, u16)),
                0x34 => try e.pushI64(@bitCast(@as(i64, @as(i32, @bitCast(try e.load(&r, u32)))))),
                0x35 => try e.pushI64(try e.load(&r, u32)),
                0x36, 0x38 => try e.store(&r, u32),
                0x37, 0x39 => try e.store(&r, u64),
                0x3a, 0x3c => try e.store(&r, u8),
                0x3b, 0x3d => try e.store(&r, u16),
                0x3e => try e.store(&r, u32),
                0x3f => {
                    _ = r.byte() catch return error.InvalidOpcode;
                    try e.pushI32(@intCast(e.inst.memory.len / page_size));
                },
                0x40 => {
                    _ = r.byte() catch return error.InvalidOpcode;
                    const delta = try e.popI32();
                    const old: u32 = @intCast(e.inst.memory.len / page_size);
                    const limit = @min(e.inst.limits.max_memory_pages, e.inst.module.memory_max orelse e.inst.limits.max_memory_pages);
                    if (@as(u64, old) + delta > limit) {
                        try e.pushI32(@bitCast(@as(i32, -1)));
                    } else {
                        const grown = e.inst.allocator.realloc(e.inst.memory, (@as(usize, old) + delta) * page_size) catch {
                            try e.pushI32(@bitCast(@as(i32, -1)));
                            e.pc = @intCast(r.pos);
                            continue;
                        };
                        @memset(grown[e.inst.memory.len..], 0);
                        e.inst.memory = grown;
                        try e.pushI32(old);
                    }
                },
                0x41 => try e.pushI32(@bitCast(r.sleb(i32) catch return error.InvalidOpcode)),
                0x42 => try e.pushI64(@bitCast(r.sleb(i64) catch return error.InvalidOpcode)),
                0x43 => try e.pushI32(std.mem.readInt(u32, (r.bytesN(4) catch return error.InvalidOpcode)[0..4], .little)),
                0x44 => try e.pushI64(std.mem.readInt(u64, (r.bytesN(8) catch return error.InvalidOpcode)[0..8], .little)),
                0x45...0x4f => try e.compareI32(op),
                0x50...0x5a => try e.compareI64(op),
                0x5b...0x60 => {
                    const b = try e.popF32();
                    const a = try e.popF32();
                    try e.pushBool(compareFloat(op - 0x5b, a, b));
                },
                0x61...0x66 => {
                    const b = try e.popF64();
                    const a = try e.popF64();
                    try e.pushBool(compareFloat(op - 0x61, a, b));
                },
                0x67...0x78 => try e.arithI32(op),
                0x79...0x8a => try e.arithI64(op),
                0x8b...0x98 => try e.arithF32(op),
                0x99...0xa6 => try e.arithF64(op),
                0xa7...0xc4 => try e.convert(op),
                0xfc => {
                    const sub = r.uleb(u32) catch return error.InvalidOpcode;
                    e.pc = @intCast(r.pos);
                    try e.extended(sub, &r);
                },
                else => return error.InvalidOpcode,
            }
            if (op >= 0x28 and op <= 0x44) e.pc = @intCast(r.pos);
            if (op == 0xfc) e.pc = @intCast(r.pos);
        }
    }

    fn compareI32(e: *Exec, op: u8) Trap!void {
        if (op == 0x45) return e.pushBool(try e.popI32() == 0);
        const b = try e.popI32();
        const a = try e.popI32();
        const sa: i32 = @bitCast(a);
        const sb: i32 = @bitCast(b);
        try e.pushBool(switch (op) {
            0x46 => a == b,
            0x47 => a != b,
            0x48 => sa < sb,
            0x49 => a < b,
            0x4a => sa > sb,
            0x4b => a > b,
            0x4c => sa <= sb,
            0x4d => a <= b,
            0x4e => sa >= sb,
            else => a >= b,
        });
    }

    fn compareI64(e: *Exec, op: u8) Trap!void {
        if (op == 0x50) return e.pushBool(try e.pop() == 0);
        const b = try e.pop();
        const a = try e.pop();
        const sa: i64 = @bitCast(a);
        const sb: i64 = @bitCast(b);
        try e.pushBool(switch (op) {
            0x51 => a == b,
            0x52 => a != b,
            0x53 => sa < sb,
            0x54 => a < b,
            0x55 => sa > sb,
            0x56 => a > b,
            0x57 => sa <= sb,
            0x58 => a <= b,
            0x59 => sa >= sb,
            else => a >= b,
        });
    }

    fn arithI32(e: *Exec, op: u8) Trap!void {
        if (op <= 0x69) {
            const a = try e.popI32();
            return e.pushI32(switch (op) {
                0x67 => @clz(a),
                0x68 => @ctz(a),
                else => @popCount(a),
            });
        }
        const b = try e.popI32();
        const a = try e.popI32();
        try e.pushI32(try intBinary(u32, op - 0x6a, a, b));
    }

    fn arithI64(e: *Exec, op: u8) Trap!void {
        if (op <= 0x7b) {
            const a = try e.pop();
            return e.pushI64(switch (op) {
                0x79 => @clz(a),
                0x7a => @ctz(a),
                else => @popCount(a),
            });
        }
        const b = try e.pop();
        const a = try e.pop();
        try e.pushI64(try intBinary(u64, op - 0x7c, a, b));
    }

    fn arithF32(e: *Exec, op: u8) Trap!void {
        if (op <= 0x91) return e.pushF32(floatUnary(f32, op - 0x8b, try e.popF32()));
        const b = try e.popF32();
        const a = try e.popF32();
        try e.pushF32(floatBinary(f32, op - 0x92, a, b));
    }

    fn arithF64(e: *Exec, op: u8) Trap!void {
        if (op <= 0x9f) return e.pushF64(floatUnary(f64, op - 0x99, try e.popF64()));
        const b = try e.popF64();
        const a = try e.popF64();
        try e.pushF64(floatBinary(f64, op - 0xa0, a, b));
    }

    fn convert(e: *Exec, op: u8) Trap!void {
        switch (op) {
            0xa7 => try e.pushI32(@truncate(try e.pop())),
            0xa8 => try e.pushI32(@bitCast(try truncate(i32, try e.popF32()))),
            0xa9 => try e.pushI32(try truncate(u32, try e.popF32())),
            0xaa => try e.pushI32(@bitCast(try truncate(i32, try e.popF64()))),
            0xab => try e.pushI32(try truncate(u32, try e.popF64())),
            0xac => try e.pushI64(@bitCast(@as(i64, @as(i32, @bitCast(try e.popI32()))))),
            0xad => try e.pushI64(try e.popI32()),
            0xae => try e.pushI64(@bitCast(try truncate(i64, try e.popF32()))),
            0xaf => try e.pushI64(try truncate(u64, try e.popF32())),
            0xb0 => try e.pushI64(@bitCast(try truncate(i64, try e.popF64()))),
            0xb1 => try e.pushI64(try truncate(u64, try e.popF64())),
            0xb2 => try e.pushF32(@floatFromInt(@as(i32, @bitCast(try e.popI32())))),
            0xb3 => try e.pushF32(@floatFromInt(try e.popI32())),
            0xb4 => try e.pushF32(@floatFromInt(@as(i64, @bitCast(try e.pop())))),
            0xb5 => try e.pushF32(@floatFromInt(try e.pop())),
            0xb6 => try e.pushF32(@floatCast(try e.popF64())),
            0xb7 => try e.pushF64(@floatFromInt(@as(i32, @bitCast(try e.popI32())))),
            0xb8 => try e.pushF64(@floatFromInt(try e.popI32())),
            0xb9 => try e.pushF64(@floatFromInt(@as(i64, @bitCast(try e.pop())))),
            0xba => try e.pushF64(@floatFromInt(try e.pop())),
            0xbb => try e.pushF64(try e.popF32()),
            // Reinterpretations are no-ops on raw slots (i32/f32 bits stay zero-extended).
            0xbc, 0xbe => try e.pushI32(try e.popI32()),
            0xbd, 0xbf => try e.push(try e.pop()),
            0xc0 => try e.pushI32(@bitCast(@as(i32, @as(i8, @truncate(@as(i32, @bitCast(try e.popI32()))))))),
            0xc1 => try e.pushI32(@bitCast(@as(i32, @as(i16, @truncate(@as(i32, @bitCast(try e.popI32()))))))),
            0xc2 => try e.pushI64(@bitCast(@as(i64, @as(i8, @truncate(@as(i64, @bitCast(try e.pop()))))))),
            0xc3 => try e.pushI64(@bitCast(@as(i64, @as(i16, @truncate(@as(i64, @bitCast(try e.pop()))))))),
            else => try e.pushI64(@bitCast(@as(i64, @as(i32, @truncate(@as(i64, @bitCast(try e.pop()))))))),
        }
    }

    fn extended(e: *Exec, sub: u32, r: *Reader) Trap!void {
        switch (sub) {
            0 => try e.pushI32(@bitCast(saturate(i32, try e.popF32()))),
            1 => try e.pushI32(saturate(u32, try e.popF32())),
            2 => try e.pushI32(@bitCast(saturate(i32, try e.popF64()))),
            3 => try e.pushI32(saturate(u32, try e.popF64())),
            4 => try e.pushI64(@bitCast(saturate(i64, try e.popF32()))),
            5 => try e.pushI64(saturate(u64, try e.popF32())),
            6 => try e.pushI64(@bitCast(saturate(i64, try e.popF64()))),
            7 => try e.pushI64(saturate(u64, try e.popF64())),
            8 => {
                const seg = r.uleb(u32) catch return error.InvalidOpcode;
                _ = r.byte() catch return error.InvalidOpcode;
                const n = try e.popI32();
                const src = try e.popI32();
                const dst = try e.popI32();
                if (seg >= e.inst.module.data.len) return error.InvalidOpcode;
                const data = if (e.inst.dropped[seg]) &[_]u8{} else e.inst.module.data[seg].bytes;
                if (@as(u64, src) + n > data.len or @as(u64, dst) + n > e.inst.memory.len) return error.MemoryOutOfBounds;
                @memcpy(e.inst.memory[dst..][0..n], data[src..][0..n]);
            },
            9 => {
                const seg = r.uleb(u32) catch return error.InvalidOpcode;
                if (seg >= e.inst.dropped.len) return error.InvalidOpcode;
                e.inst.dropped[seg] = true;
            },
            10 => {
                _ = r.byte() catch return error.InvalidOpcode;
                _ = r.byte() catch return error.InvalidOpcode;
                const n = try e.popI32();
                const src = try e.popI32();
                const dst = try e.popI32();
                if (@as(u64, src) + n > e.inst.memory.len or @as(u64, dst) + n > e.inst.memory.len) return error.MemoryOutOfBounds;
                const m = e.inst.memory;
                if (dst <= src) std.mem.copyForwards(u8, m[dst..][0..n], m[src..][0..n]) else std.mem.copyBackwards(u8, m[dst..][0..n], m[src..][0..n]);
            },
            11 => {
                _ = r.byte() catch return error.InvalidOpcode;
                const n = try e.popI32();
                const v: u8 = @truncate(try e.popI32());
                const dst = try e.popI32();
                if (@as(u64, dst) + n > e.inst.memory.len) return error.MemoryOutOfBounds;
                @memset(e.inst.memory[dst..][0..n], v);
            },
            else => return error.InvalidOpcode,
        }
    }
};

fn sameType(a: FuncType, b: FuncType) bool {
    return std.mem.eql(ValType, a.params, b.params) and std.mem.eql(ValType, a.results, b.results);
}

fn compareFloat(k: u8, a: anytype, b: @TypeOf(a)) bool {
    return switch (k) {
        0 => a == b,
        1 => a != b,
        2 => a < b,
        3 => a > b,
        4 => a <= b,
        else => a >= b,
    };
}

fn intBinary(comptime U: type, k: u8, a: U, b: U) Trap!U {
    const S = std.meta.Int(.signed, @bitSizeOf(U));
    const Shift = std.math.Log2Int(U);
    const sa: S = @bitCast(a);
    const sb: S = @bitCast(b);
    const sh: Shift = @truncate(b);
    return switch (k) {
        0 => a +% b,
        1 => a -% b,
        2 => a *% b,
        3 => blk: {
            if (b == 0) return error.DivideByZero;
            if (sa == std.math.minInt(S) and sb == -1) return error.IntegerOverflow;
            break :blk @bitCast(@divTrunc(sa, sb));
        },
        4 => if (b == 0) error.DivideByZero else a / b,
        5 => blk: {
            if (b == 0) return error.DivideByZero;
            if (sb == -1) break :blk 0;
            break :blk @bitCast(@rem(sa, sb));
        },
        6 => if (b == 0) error.DivideByZero else a % b,
        7 => a & b,
        8 => a | b,
        9 => a ^ b,
        10 => a << sh,
        11 => @bitCast(sa >> sh),
        12 => a >> sh,
        13 => std.math.rotl(U, a, sh),
        else => std.math.rotr(U, a, sh),
    };
}

fn floatUnary(comptime F: type, k: u8, a: F) F {
    return switch (k) {
        0 => @abs(a),
        1 => -a,
        2 => @ceil(a),
        3 => @floor(a),
        4 => @trunc(a),
        5 => nearest(F, a),
        else => @sqrt(a),
    };
}

fn nearest(comptime F: type, a: F) F {
    if (std.math.isNan(a) or std.math.isInf(a)) return a;
    const r = @round(a);
    // Ties go to even.
    if (@abs(a - @trunc(a)) == 0.5) return std.math.copysign(2 * @round(a / 2), a);
    return std.math.copysign(r, a);
}

fn floatBinary(comptime F: type, k: u8, a: F, b: F) F {
    return switch (k) {
        0 => a + b,
        1 => a - b,
        2 => a * b,
        3 => a / b,
        4 => if (std.math.isNan(a) or std.math.isNan(b)) std.math.nan(F) else if (a == 0 and b == 0) (if (std.math.signbit(a)) a else b) else @min(a, b),
        5 => if (std.math.isNan(a) or std.math.isNan(b)) std.math.nan(F) else if (a == 0 and b == 0) (if (std.math.signbit(a)) b else a) else @max(a, b),
        else => std.math.copysign(a, b),
    };
}

fn truncate(comptime I: type, x: anytype) Trap!I {
    if (std.math.isNan(x)) return error.InvalidConversion;
    const t = @trunc(x);
    const lo: @TypeOf(x) = @floatFromInt(std.math.minInt(I));
    // The upper bound is exclusive: 2^N (or 2^(N-1) when signed) is exactly representable.
    const hi: @TypeOf(x) = -2 * @as(@TypeOf(x), @floatFromInt(std.math.minInt(std.meta.Int(.signed, @bitSizeOf(I))))) / @as(@TypeOf(x), if (@typeInfo(I).int.signedness == .signed) 2 else 1);
    if (t < lo or t >= hi) return error.IntegerOverflow;
    return @intFromFloat(t);
}

fn saturate(comptime I: type, x: anytype) I {
    if (std.math.isNan(x)) return 0;
    return truncate(I, x) catch if (x < 0) std.math.minInt(I) else std.math.maxInt(I);
}

// ---- Tests use hand-assembled modules; the Zig-compiled example mod is tested in Mod.zig.

/// Builds a module with one exported function "f" of the given type and body.
fn testModule(comptime params: []const u8, comptime results: []const u8, comptime locals: []const u8, comptime body: []const u8) []const u8 {
    const type_sec = [_]u8{ 1, 0x60, params.len } ++ params[0..params.len].* ++ [_]u8{results.len} ++ results[0..results.len].*;
    const func_body = (if (locals.len == 0) [_]u8{0} else [_]u8{ 1, locals.len, locals[0] }) ++ body[0..body.len].* ++ [_]u8{0x0b};
    const code_sec = [_]u8{ 1, func_body.len } ++ func_body;
    return "\x00asm\x01\x00\x00\x00" ++
        [_]u8{ 1, type_sec.len } ++ type_sec ++
        [_]u8{ 3, 2, 1, 0 } ++
        [_]u8{ 5, 3, 1, 0, 1 } ++
        [_]u8{ 7, 5, 1, 1, 'f', 0, 0 } ++
        [_]u8{ 10, code_sec.len } ++ code_sec;
}

fn runI32(bytes: []const u8, args: []const u64) !u32 {
    var m = try load(std.testing.allocator, bytes);
    defer m.deinit();
    var inst = try Instance.init(std.testing.allocator, &m, .{});
    defer inst.deinit();
    var out: [1]u64 = undefined;
    try inst.call(0, args, &out, 100000);
    return @truncate(out[0]);
}

test "arithmetic, locals, and structured control flow" {
    const i32t = 0x7f;
    // sum = 0; i = n; loop { if i == 0 break; sum += i; i -= 1 } return sum
    const sum = testModule(&.{i32t}, &.{i32t}, &.{i32t}, &.{
        0x02, 0x40, // block
        0x03, 0x40, // loop
        0x20, 0x00, 0x45, 0x0d, 0x01, // local.get 0; i32.eqz; br_if 1
        0x20, 0x01, 0x20, 0x00, 0x6a, 0x21, 0x01, // sum += i
        0x20, 0x00, 0x41, 0x01, 0x6b, 0x21, 0x00, // i -= 1
        0x0c, 0x00, // br 0
        0x0b, 0x0b, 0x20, 0x01, //  end end; local.get 1
    });
    try std.testing.expectEqual(@as(u32, 5050), try runI32(sum, &.{100}));
    // if/else with a result, and select
    const choose = testModule(&.{i32t}, &.{i32t}, &.{}, &.{ 0x20, 0x00, 0x04, 0x7f, 0x41, 0x07, 0x05, 0x41, 0x09, 0x0b, 0x41, 0x01, 0x41, 0x02, 0x20, 0x00, 0x1b, 0x6a });
    try std.testing.expectEqual(@as(u32, 8), try runI32(choose, &.{1}));
    try std.testing.expectEqual(@as(u32, 11), try runI32(choose, &.{0}));
    // br_table: 0 → 10, 1 → 20, anything else → 30
    const table = testModule(&.{i32t}, &.{i32t}, &.{}, &.{
        0x02, 0x40, 0x02, 0x40, 0x02, 0x40, 0x20, 0x00, 0x0e, 0x02, 0x00, 0x01, 0x02, 0x0b, 0x41, 10, 0x0f, 0x0b, 0x41, 20, 0x0f, 0x0b, 0x41, 30,
    });
    for ([_]u32{ 0, 1, 2, 99 }, [_]u32{ 10, 20, 30, 30 }) |in, want| try std.testing.expectEqual(want, try runI32(table, &.{in}));
    // Memory: store then load, little-endian bytes and sign extension.
    const mem = testModule(&.{i32t}, &.{i32t}, &.{}, &.{ 0x41, 0x10, 0x20, 0x00, 0x36, 0x02, 0x00, 0x41, 0x10, 0x2c, 0x00, 0x00 });
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -1))), try runI32(mem, &.{0x1ff}));
}

test "traps: division, unreachable, bounds, fuel, and recursion depth" {
    const i32t = 0x7f;
    const div = testModule(&.{ i32t, i32t }, &.{i32t}, &.{}, &.{ 0x20, 0x00, 0x20, 0x01, 0x6d });
    try std.testing.expectError(error.DivideByZero, runI32(div, &.{ 1, 0 }));
    try std.testing.expectError(error.IntegerOverflow, runI32(div, &.{ 0x80000000, 0xffffffff }));
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -3))), try runI32(div, &.{ @as(u32, @bitCast(@as(i32, -7))), 2 }));
    try std.testing.expectError(error.Unreachable, runI32(testModule(&.{}, &.{i32t}, &.{}, &.{0x00}), &.{}));
    // One page of memory: loading at 65533 needs 4 bytes.
    const oob = testModule(&.{i32t}, &.{i32t}, &.{}, &.{ 0x20, 0x00, 0x28, 0x02, 0x00 });
    try std.testing.expectEqual(@as(u32, 0), try runI32(oob, &.{65532}));
    try std.testing.expectError(error.MemoryOutOfBounds, runI32(oob, &.{65533}));
    // An infinite loop runs out of fuel instead of hanging.
    try std.testing.expectError(error.OutOfFuel, runI32(testModule(&.{}, &.{i32t}, &.{}, &.{ 0x03, 0x40, 0x0c, 0x00, 0x0b, 0x41, 0x00 }), &.{}));
    // Unbounded recursion stops at the frame limit.
    try std.testing.expectError(error.CallDepthExceeded, runI32(testModule(&.{}, &.{i32t}, &.{}, &.{ 0x10, 0x00 }), &.{}));
    // Truncating NaN and out-of-range floats traps; the saturating forms clamp.
    const trunc = testModule(&.{0x7d}, &.{i32t}, &.{}, &.{ 0x20, 0x00, 0xa8 });
    try std.testing.expectError(error.InvalidConversion, runI32(trunc, &.{@as(u32, @bitCast(std.math.nan(f32)))}));
    try std.testing.expectError(error.IntegerOverflow, runI32(trunc, &.{@as(u32, @bitCast(@as(f32, 3e9)))}));
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -2))), try runI32(trunc, &.{@as(u32, @bitCast(@as(f32, -2.9)))}));
    const sat = testModule(&.{0x7d}, &.{i32t}, &.{}, &.{ 0x20, 0x00, 0xfc, 0x00 });
    try std.testing.expectEqual(@as(u32, 0x7fffffff), try runI32(sat, &.{@as(u32, @bitCast(@as(f32, 3e9)))}));
}

test "modules that import, start, or are malformed are rejected" {
    try std.testing.expectError(error.InvalidModule, load(std.testing.allocator, "\x00asm\x02\x00\x00\x00"));
    try std.testing.expectError(error.Unsupported, load(std.testing.allocator, "\x00asm\x01\x00\x00\x00" ++ [_]u8{ 2, 7, 1, 1, 'e', 1, 'f', 0, 0 }));
    // Truncated code section.
    const good = testModule(&.{}, &.{0x7f}, &.{}, &.{ 0x41, 0x05 });
    try std.testing.expectError(error.InvalidModule, load(std.testing.allocator, good[0 .. good.len - 2]));
    // Unbalanced blocks.
    try std.testing.expectError(error.InvalidModule, load(std.testing.allocator, testModule(&.{}, &.{}, &.{}, &.{ 0x02, 0x40 })));
    // Float semantics: nearest rounds ties to even; min handles signed zero.
    try std.testing.expectEqual(@as(f32, 2), nearest(f32, 2.5));
    try std.testing.expectEqual(@as(f32, -4), nearest(f32, -3.5));
    try std.testing.expect(std.math.signbit(floatBinary(f32, 4, 0.0, -0.0)));
}
