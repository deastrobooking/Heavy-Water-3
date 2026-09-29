const std = @import("std");
const mach = @import("main.zig");
const Core = @import("Core.zig");
const StringTable = @import("StringTable.zig");
const Graph = @import("graph.zig").Graph;

/// A handle to a spawned thread.
pub const Thread = struct {
    thread: std.Thread,

    pub fn join(self: Thread) void {
        self.thread.join();
    }
};

/// Spawn a thread that runs the given function in a loop until the application exits.
pub fn startThread(
    core: *Core,
    on_tick: FunctionID,
    core_mod: Mod(Core),
    comptime kind: anytype,
) error{ThreadSpawnFailed}!Thread {
    // TODO(thread): use kind for measured preallocations, thread naming, etc.
    _ = kind;
    return .{
        .thread = std.Thread.spawn(.{}, runThread, .{ core, on_tick, core_mod }) catch
            return error.ThreadSpawnFailed,
    };
}

fn runThread(core: *Core, on_tick: FunctionID, core_mod: Mod(Core)) void {
    while (core.state.load(.acquire) == .running) {
        core_mod.callId(on_tick);
    }
}

/// Initialize a graph with default preallocations for the given kind.
pub fn initGraph(graph: *Graph, allocator: std.mem.Allocator, io: std.Io, comptime kind: anytype) !void {
    // TODO(object): measured preallocations
    _ = kind;
    try graph.init(allocator, io, .{
        .queue_size = 32,
        .nodes_size = 32,
        .num_result_lists = 8,
        .result_list_size = 8,
    });
}

/// Validate that the given tuple is a valid schedule, returning true if so.
fn validateSchedule(comptime entries: anytype) bool {
    const Entries = @TypeOf(entries);
    const entries_info = @typeInfo(Entries);
    if (entries_info != .@"struct" or !entries_info.@"struct".is_tuple) {
        @compileError("mach.schedule() expects a tuple of .{ Module, .fn_name } entries, found: " ++ @typeName(Entries));
    }
    inline for (entries) |tuple| {
        const tuple_info = @typeInfo(@TypeOf(tuple));
        // Check it's a 2-field tuple before accessing fields
        if (tuple_info != .@"struct" or !tuple_info.@"struct".is_tuple or tuple_info.@"struct".fields.len != 2) {
            @compileError("mach.schedule() entry expected tuple .{ Module, .fn_name }, found: " ++ @typeName(@TypeOf(tuple)));
        }
        const Module: type = tuple.@"0";
        const fn_name = tuple.@"1";

        // Validate first field is a valid module type
        if (!isValid(Module)) {
            @compileError("mach.schedule() entry first field must be a valid Mach module, " ++
                "found: " ++ @typeName(Module));
        }

        // Validate second field is an enum literal
        if (@typeInfo(@TypeOf(fn_name)) != .enum_literal) {
            @compileError("mach.schedule() entry expected tuple .{ Module, .fn_name }, second value not an enum literal, found: " ++ @typeName(@TypeOf(fn_name)));
        }

        // Validate function name exists in module's mach_systems
        if (!@hasField(ModuleFunctionName(Module), @tagName(fn_name))) {
            @compileError("mach.schedule() entry references ." ++ @tagName(fn_name) ++ " but module " ++ @typeName(Module) ++ " has no such entry in `mach_systems`");
        }
    }

    return true;
}

/// When a schedule is called, the list of module functions described within are executed in order.
///
/// Example:
/// ```
/// pub const foo = mach.schedule(.{
///     .{ App, .init },
///     .{ Physics, .init },
///     .{ App, .main },
/// });
/// ...
/// my_mod.call(.foo); // runs App.init, Physics.init, App.main in order
/// ```
pub fn schedule(entries: anytype) @TypeOf(entries) {
    _ = comptime validateSchedule(entries);
    return entries;
}

/// An ID representing a mach object. This is an opaque identifier which effectively encodes:
///
/// * An array index that can be used to O(1) lookup the actual data / struct fields of the object.
/// * The generation (or 'version') of the object, enabling detecting use-after-free in
///   many (but not all) cases.
/// * Which module the object came from, allowing looking up type information or the module name
///   from ID alone.
/// * Which list of objects in a module the object came from, allowing looking up type information
///   or the object type name - which enables debugging and type safety when passing opaque IDs
///   around.
///
pub const ObjectID = u64;

const ObjectTypeID = u16;

pub const ObjectsOptions = struct {
    /// If set to true, Mach will track when fields are set using the setField/setAll
    /// methods using a bitset with one bit per field to indicate 'the field was set'.
    /// You can get this information by calling `.updated(.field_name)`
    /// Note that calling `.updated(.field_name) will also set the flag back to false.
    track_fields: bool = false,

    /// When true, delete() will result in a panic indicating that objects in this list must be
    /// explicitly free()'d instead.
    require_free: bool = false,
};

pub fn Objects(options: ObjectsOptions, comptime T: type) type {
    // MultiArrayList doesn't support zero-field structs, so add a dummy field to make it work.
    // TODO(object): avoid constructing MultiArrayList entirely in this case?
    const has_fields = @typeInfo(T).@"struct".fields.len > 0;
    const StorageT = if (has_fields) T else struct { _padding: u0 = 0 };

    return struct {
        internal: struct {
            allocator: std.mem.Allocator,
            io: std.Io,

            /// Mutex to be held when operating on these objects.
            mu: std.Io.RwLock = .init,

            /// A registered ID indicating the type of objects being represented. This can be
            /// thought of as a hash of the module name + field name where this objects list is
            /// stored.
            type_id: ObjectTypeID,

            /// The actual object data
            data: std.MultiArrayList(StorageT) = .empty,

            /// Whether a given slot in data[i] has been freed or not
            freed: std.bit_set.DynamicBitSetUnmanaged = .{},

            /// Whether a given slot in data[i] is marked for pending deletion
            pending_delete: std.bit_set.DynamicBitSetUnmanaged = .{},

            /// The current generation number of data[i], when data[i] becomes freed and then alive
            /// again, this number is incremented by one.
            generation: std.ArrayList(Generation) = .empty,

            /// The recycling bin which tells which data indices are freed and can be reused.
            recycling_bin: std.ArrayList(Index) = .empty,

            /// The number of objects that could not fit in the recycling bin and hence were thrown
            /// on the floor and forgotten about. This means there are freed items recorded by freed.set(index)
            /// which aren't in the recycling_bin, and the next call to new() may consider cleaning up.
            thrown_on_the_floor: u32 = 0,

            /// Global pointer to object relations graph
            graph: *Graph,

            /// A bitset used to track per-field changes. Only used if options.track_fields == true.
            updated: ?std.bit_set.DynamicBitSetUnmanaged = if (options.track_fields) .{} else null,

            /// Tags storage
            tags: std.AutoHashMapUnmanaged(TaggedObject, ?ObjectID) = .{},
        },

        pub const IsMachObjects = void;

        fn toStorage(value: T) StorageT {
            if (has_fields) return value else return .{};
        }

        fn fromStorage(value: StorageT) T {
            if (has_fields) return value else return .{};
        }

        const Generation = u16;
        const Index = u32;

        const TaggedObject = struct {
            object_id: ObjectID,
            tag_hash: u64,
        };

        const PackedID = packed struct(u64) {
            type_id: ObjectTypeID,
            generation: Generation,
            index: Index,
        };

        pub const Slice = struct {
            index: Index,
            objs: *Objects(options, T),

            pub fn next(s: *Slice) ?ObjectID {
                const freed = &s.objs.internal.freed;
                const generation = &s.objs.internal.generation;
                const num_objects = generation.items.len;

                while (true) {
                    if (s.index == num_objects) {
                        s.index = 0;
                        return null;
                    }
                    defer s.index += 1;

                    if (!freed.isSet(s.index) and !s.objs.internal.pending_delete.isSet(s.index)) return @bitCast(PackedID{
                        .type_id = s.objs.internal.type_id,
                        .generation = generation.items[s.index],
                        .index = s.index,
                    });
                }
            }
        };

        fn deinit(objs: *@This(), allocator: std.mem.Allocator) void {
            objs.internal.data.deinit(allocator);
            objs.internal.freed.deinit(allocator);
            objs.internal.pending_delete.deinit(allocator);
            objs.internal.generation.deinit(allocator);
            objs.internal.recycling_bin.deinit(allocator);
            if (objs.internal.updated) |*updated_fields| updated_fields.deinit(allocator);
            objs.internal.tags.deinit(allocator);
        }

        /// Tries to acquire the mutex without blocking the caller's thread.
        /// Returns `false` if the calling thread would have to block to acquire it.
        /// Otherwise, returns `true` and the caller should `unlock()` the Mutex to release it.
        pub fn tryLock(objs: *@This()) bool {
            return objs.internal.mu.tryLock(objs.internal.io);
        }

        /// Acquires the mutex, blocking the caller's thread until it can.
        /// It is undefined behavior if the mutex is already held by the caller's thread.
        /// Once acquired, call `unlock()` on the Mutex to release it.
        pub fn lock(objs: *@This()) void {
            objs.internal.mu.lockUncancelable(objs.internal.io);
        }

        /// Releases the mutex which was previously acquired with `lock()` or `tryLock()`.
        /// It is undefined behavior if the mutex is unlocked from a different thread that it was locked from.
        pub fn unlock(objs: *@This()) void {
            objs.internal.mu.unlock(objs.internal.io);
        }

        /// Tries to acquire a shared (read) lock without blocking the caller's thread.
        ///
        /// Returns `false` if the calling thread would have to block to acquire it.
        /// Otherwise, returns `true` and the caller should call `unlockShared()` to release it.
        pub fn tryLockShared(objs: *@This()) bool {
            return objs.internal.mu.tryLockShared(objs.internal.io);
        }

        /// Acquires a shared (read) lock, blocking the caller's thread until it can.
        /// Multiple readers may hold the lock concurrently, but no writer may hold it while readers
        /// do.
        /// Once acquired, call `unlockShared()` on the Mutex to release it.
        pub fn lockShared(objs: *@This()) void {
            objs.internal.mu.lockSharedUncancelable(objs.internal.io);
        }

        /// Releases the shared (reader) lock which was previously acquired with `lockShared()` or
        /// `tryLockShared()`.
        pub fn unlockShared(objs: *@This()) void {
            objs.internal.mu.unlockShared(objs.internal.io);
        }

        pub fn new(objs: *@This(), value: T) std.mem.Allocator.Error!ObjectID {
            const allocator = objs.internal.allocator;
            const data = &objs.internal.data;
            const freed = &objs.internal.freed;
            const pending_delete = &objs.internal.pending_delete;
            const generation = &objs.internal.generation;
            const recycling_bin = &objs.internal.recycling_bin;

            // The recycling bin should always be big enough, but we check at this point if 10% of
            // all objects have been thrown on the floor. If they have, we find them and grow the
            // recycling bin to fit them.
            if (objs.internal.thrown_on_the_floor >= (data.len / 10)) {
                var iter = freed.iterator(.{ .kind = .set });
                freed_object_loop: while (iter.next()) |index| {
                    // We need to check if this index is already in the recycling bin since
                    // if it is, it could get recycled a second time while still
                    // in use.
                    for (recycling_bin.items) |recycled_index| {
                        if (index == recycled_index) continue :freed_object_loop;
                    }

                    // freed bitset contains data.capacity number of entries, we only care about ones that are in data.len range.
                    if (index > data.len - 1) break;
                    try recycling_bin.append(allocator, @intCast(index));
                }
                objs.internal.thrown_on_the_floor = 0;
            }

            if (recycling_bin.pop()) |index| {
                // Reuse a free slot from the recycling bin.
                freed.unset(index);
                pending_delete.unset(index);
                const gen = generation.items[index] + 1;
                generation.items[index] = gen;
                data.set(index, toStorage(value));
                return @bitCast(PackedID{
                    .type_id = objs.internal.type_id,
                    .generation = gen,
                    .index = index,
                });
            }

            // Ensure we have space for the new object
            try data.ensureUnusedCapacity(allocator, 1);
            try freed.resize(allocator, data.capacity, false);
            try pending_delete.resize(allocator, data.capacity, false);
            try generation.ensureUnusedCapacity(allocator, 1);

            // If we are tracking fields, we need to resize the bitset to hold another object's fields
            if (objs.internal.updated) |*updated_fields| {
                try updated_fields.resize(allocator, data.capacity * @typeInfo(T).@"struct".fields.len, true);
            }

            const index = data.len;
            data.appendAssumeCapacity(toStorage(value));
            freed.unset(index);
            generation.appendAssumeCapacity(0);

            return @bitCast(PackedID{
                .type_id = objs.internal.type_id,
                .generation = 0,
                .index = @intCast(index),
            });
        }

        /// Sets all fields of the given object to the given value.
        ///
        /// Unlike setAll(), this method does not respect any mach.Objects tracking
        /// options, so changes made to an object through this method will not be tracked.
        pub fn setValueRaw(objs: *@This(), id: ObjectID, value: T) void {
            const data = &objs.internal.data;

            const unpacked = objs.validateAndUnpack(id, "setValueRaw");
            data.set(unpacked.index, toStorage(value));
        }

        /// Sets all fields of the given object to the given value.
        ///
        /// Unlike setAllRaw, this method respects mach.Objects tracking
        /// and changes made to an object through this method will be tracked.
        pub fn setValue(objs: *@This(), id: ObjectID, value: T) void {
            const data = &objs.internal.data;

            const unpacked = objs.validateAndUnpack(id, "setValue");
            data.set(unpacked.index, toStorage(value));

            if (objs.internal.updated) |*updated_fields| {
                const updated_start = unpacked.index * @typeInfo(T).@"struct".fields.len;
                const updated_end = updated_start + @typeInfo(T).@"struct".fields.len;
                updated_fields.setRangeValue(.{ .start = @intCast(updated_start), .end = @intCast(updated_end) }, true);
            }
        }

        /// Sets a single field of the given object to the given value.
        ///
        /// Unlike set(), this method does not respect any mach.Objects tracking
        /// options, so changes made to an object through this method will not be tracked.
        pub fn setRaw(objs: *@This(), id: ObjectID, comptime field_name: std.meta.FieldEnum(T), value: @FieldType(T, @tagName(field_name))) void {
            const data = &objs.internal.data;
            const unpacked = objs.validateAndUnpack(id, "setRaw");

            data.items(field_name)[unpacked.index] = value;
        }

        /// Sets a single field of the given object to the given value.
        ///
        /// Unlike setAllRaw, this method respects mach.Objects tracking
        /// and changes made to an object through this method will be tracked.
        pub fn set(objs: *@This(), id: ObjectID, comptime field_name: std.meta.FieldEnum(T), value: @FieldType(T, @tagName(field_name))) void {
            const data = &objs.internal.data;
            const unpacked = objs.validateAndUnpack(id, "set");

            data.items(field_name)[unpacked.index] = value;

            if (options.track_fields)
                if (std.meta.fieldIndex(T, @tagName(field_name))) |field_index|
                    if (objs.internal.updated) |*updated_fields|
                        updated_fields.set(unpacked.index * @typeInfo(T).@"struct".fields.len + field_index);
        }

        /// Get a single field.
        pub fn get(objs: *@This(), id: ObjectID, comptime field_name: std.meta.FieldEnum(T)) @FieldType(T, @tagName(field_name)) {
            const data = &objs.internal.data;

            const unpacked = objs.validateAndUnpack(id, "get");
            return data.items(field_name)[unpacked.index];
        }

        /// Get all fields.
        pub fn getValue(objs: *@This(), id: ObjectID) T {
            const data = &objs.internal.data;

            const unpacked = objs.validateAndUnpack(id, "getValue");
            return fromStorage(data.get(unpacked.index));
        }

        /// Marks an object for deletion. The object is flagged for deletion, it remains alive and
        /// readable until someone, usually the owning module that knows how to cleanup its
        /// resources, invokes `free()` on it.
        ///
        /// Deletion is cascaded to all descendants in the object graph, marking them as deleted too
        ///
        /// Use `isDeleted()` to check if an object has been deleted but not yet freed, or
        /// `sliceDeleted()` to iterate all deleted objects from the set.
        ///
        /// If `require_free = true`, it is a @compileError to invoke this method on the set and
        /// free() must be used instead.
        pub fn delete(objs: *@This(), id: ObjectID) void {
            if (options.require_free) @compileError("delete() cannot be used when require_free is set; use free() instead");
            const unpacked = objs.validateAndUnpack(id, "delete");
            objs.internal.pending_delete.set(unpacked.index);

            // Enqueue the cascaded delete to all descendants in the graph.
            // TODO(object): better error handling here
            objs.internal.graph.cascadeDelete(objs.internal.allocator, id) catch {};
        }

        /// Immediately removes an object from the pool, freeing its slot for reuse.
        ///
        /// Freeing an object also removes its parent object in the graph, if any.
        ///
        /// In order to free an object, you must know how to release its resources - including graph
        /// resources. If `require_free = true`, then an object is declared as requiring manual
        /// `free()`.
        ///
        /// If `require_free = false`, you should use `delete()` instead which doesn't require
        /// knowing how to free the objects resources - by allowing the module that owns the object
        /// to release them later (by ultimately calling `free()` itself) instead.
        ///
        /// In debug builds, calling free() on an object which has children in the graph results in
        /// a panic.
        pub fn free(objs: *@This(), id: ObjectID) void {
            const unpacked = objs.validateAndUnpack(id, "free");
            const data = &objs.internal.data;
            const freed = &objs.internal.freed;
            const recycling_bin = &objs.internal.recycling_bin;
            if (recycling_bin.items.len < recycling_bin.capacity) {
                recycling_bin.appendAssumeCapacity(unpacked.index);
            } else objs.internal.thrown_on_the_floor += 1;

            freed.set(unpacked.index);
            objs.internal.pending_delete.unset(unpacked.index);

            // Enqueue our parents' removal from the graph
            objs.internal.graph.removeParent(objs.internal.allocator, id) catch {};

            if (mach.is_debug) {
                const undef: StorageT = undefined;
                data.set(unpacked.index, undef);
            }
        }

        /// Returns an iterator over objects marked for deletion.
        ///
        /// Used by modules to find objects that need to cleanup resources on objects before
        /// ultimately calling free() on each object.
        pub fn sliceDeleted(objs: *@This()) SliceDeleted {
            // Sync any cascaded deletions that may have occurred prior to this so our
            // pending_delete bits are up to date.
            objs.internal.graph.sync(objs.internal.allocator) catch {};

            return .{ .index = 0, .objs = objs };
        }

        pub const SliceDeleted = struct {
            index: Index,
            objs: *Objects(options, T),

            pub fn next(s: *SliceDeleted) ?ObjectID {
                const pending = &s.objs.internal.pending_delete;
                const generation = &s.objs.internal.generation;
                const num_objects = generation.items.len;

                while (true) {
                    if (s.index == num_objects) {
                        s.index = 0;
                        return null;
                    }
                    defer s.index += 1;

                    if (pending.isSet(s.index)) return @bitCast(PackedID{
                        .type_id = s.objs.internal.type_id,
                        .generation = generation.items[s.index],
                        .index = s.index,
                    });
                }
            }
        };

        /// Returns true if the object has been marked for deferred deletion.
        ///
        /// Calling this on an object which has been free()'d already is illegal and will result in
        /// undefined behavior in production builds, and a safety-check panic in debug builds.
        pub fn isDeleted(objs: *const @This(), id: ObjectID) bool {
            const unpacked = objs.validateAndUnpack(id, "isDeleted");

            // Sync any cascaded deletions that may have occurred prior to this so our
            // pending_delete bits are up to date.
            objs.internal.graph.sync(objs.internal.allocator) catch {};

            return objs.internal.pending_delete.isSet(unpacked.index);
        }

        /// Returns the number of objects currently marked for deferred deletion.
        pub fn numDeleted(objs: *const @This()) u32 {
            // Sync any cascaded deletions that may have occurred prior to this so our
            // pending_delete bits are up to date.
            objs.internal.graph.sync(objs.internal.allocator) catch {};

            return @intCast(objs.internal.pending_delete.count());
        }

        // TODO(objects): evaluate whether tag operations should ever return an error

        /// Sets a tag on an object
        pub fn setTag(objs: *@This(), id: ObjectID, comptime M: type, tag: ModuleTagEnum(M), value_id: ?ObjectID) !void {
            _ = objs.validateAndUnpack(id, "setTag");

            // TODO: validate that value_id is an object coming from the mach.Objects(T) list indicated by the tag value in M.mach_tags.
            //const value_mach_objects = moduleTagValueObjects(M, tag);

            const tagged = TaggedObject{
                .object_id = id,
                .tag_hash = std.hash.Wyhash.hash(0, @tagName(tag)),
            };
            try objs.internal.tags.put(objs.internal.allocator, tagged, value_id);
        }

        /// Removes a tag on an object
        pub fn removeTag(objs: *@This(), id: ObjectID, comptime M: type, tag: ModuleTagEnum(M)) void {
            _ = objs.validateAndUnpack(id, "removeTag");
            const tagged = TaggedObject{
                .object_id = id,
                .tag_hash = std.hash.Wyhash.hash(0, @tagName(tag)),
            };
            _ = objs.internal.tags.remove(tagged);
        }

        /// Whether an object has a tag
        pub fn hasTag(objs: *@This(), id: ObjectID, comptime M: type, tag: ModuleTagEnum(M)) bool {
            _ = objs.validateAndUnpack(id, "hasTag");
            const tagged = TaggedObject{
                .object_id = id,
                .tag_hash = std.hash.Wyhash.hash(0, @tagName(tag)),
            };
            return objs.internal.tags.contains(tagged);
        }

        /// Get an object's tag value, or null.
        pub fn getTag(objs: *@This(), id: ObjectID, comptime M: type, tag: ModuleTagEnum(M)) ?mach.ObjectID {
            _ = objs.validateAndUnpack(id, "getTag");
            const tagged = TaggedObject{
                .object_id = id,
                .tag_hash = std.hash.Wyhash.hash(0, @tagName(tag)),
            };
            return objs.internal.tags.get(tagged) orelse null;
        }

        /// Returns an iterator over all live objects. Excludes any objects which have been freed
        /// or marked for deletion.
        pub fn slice(objs: *@This()) Slice {
            // Sync any cascaded deletions that may have occurred prior to this so our
            // pending_delete bits are up to date.
            objs.internal.graph.sync(objs.internal.allocator) catch {};

            return Slice{
                .index = 0,
                .objs = objs,
            };
        }

        /// Validates the given object is from this list (type check) and alive (not a use after free
        /// situation.)
        fn validateAndUnpack(objs: *const @This(), id: ObjectID, comptime fn_name: []const u8) PackedID {
            const freed = &objs.internal.freed;
            const generation = &objs.internal.generation;

            // TODO(object): decide whether to disable safety checks like this in some conditions,
            // e.g. in release builds
            const unpacked: PackedID = @bitCast(id);
            if (unpacked.type_id != objs.internal.type_id) {
                @panic("mach: " ++ fn_name ++ "() called with object not from this list");
            }
            if (unpacked.generation != generation.items[unpacked.index]) {
                @panic("mach: " ++ fn_name ++ "() called with a freed object (use after free, recycled slot)");
            }
            if (freed.isSet(unpacked.index)) {
                @panic("mach: " ++ fn_name ++ "() called with a freed object (use after free)");
            }
            return unpacked;
        }

        /// If options have tracking enabled, this returns true when the given field has been set
        /// using the set() or setAll() methods. A subsequent call to .updated(), .anyUpdated(), etc.
        /// will return false until another set() or setAll() call is made.
        pub fn updated(objs: *@This(), id: ObjectID, field_name: anytype) bool {
            return objs.updatedOptions(id, field_name, false);
        }

        /// Same as updated(), but doesn't alter the behavior of subsequent .updated(), .anyUpdated(),
        /// etc. calls
        pub fn peekUpdated(objs: *@This(), id: ObjectID, field_name: anytype) bool {
            return objs.updatedOptions(id, field_name, true);
        }

        inline fn updatedOptions(objs: *@This(), id: ObjectID, field_name: anytype, comptime peek: bool) bool {
            if (!options.track_fields) return false;
            const unpacked = objs.validateAndUnpack(id, "updated");
            const field_index = std.meta.fieldIndex(T, @tagName(field_name)).?;
            const updated_fields = &(objs.internal.updated orelse return false);
            const updated_index = unpacked.index * @typeInfo(T).@"struct".fields.len + field_index;
            const updated_value = updated_fields.isSet(updated_index);
            if (!peek) updated_fields.unset(updated_index);
            return updated_value;
        }

        /// If options have tracking enabled, this returns true when any field has been set using
        /// the set() or setAll() methods. A subsequent call to .updated(), .anyUpdated(), etc. will
        /// return false until another set() or setAll() call is made.
        pub fn anyUpdated(objs: *@This(), id: ObjectID) bool {
            return objs.anyUpdatedOptions(id, false);
        }

        /// Same as anyUpdated(), but doesn't alter the behavior of subsequent .updated(), .anyUpdated(),
        /// etc. calls
        pub fn peekAnyUpdated(objs: *@This(), id: ObjectID) bool {
            return objs.anyUpdatedOptions(id, true);
        }

        inline fn anyUpdatedOptions(objs: *@This(), id: ObjectID, comptime peek: bool) bool {
            if (!options.track_fields) return false;
            const unpacked = objs.validateAndUnpack(id, "updated");
            const updated_fields = &(objs.internal.updated orelse return false);
            var any_updated = false;
            inline for (0..@typeInfo(T).@"struct".fields.len) |field_index| {
                const updated_index = unpacked.index * @typeInfo(T).@"struct".fields.len + field_index;
                const updated_value = updated_fields.isSet(updated_index);
                if (!peek) updated_fields.unset(updated_index);
                if (updated_value) any_updated = true;
            }
            return any_updated;
        }

        /// Tells if the given object is from this pool of objects. If it is, then it must also be
        /// alive/valid or else a panic will occur.
        pub fn is(objs: *const @This(), id: ObjectID) bool {
            const unpacked: PackedID = @bitCast(id);
            if (unpacked.type_id != objs.internal.type_id) return false;
            _ = objs.validateAndUnpack(id, "is");
            return true;
        }

        /// Get the parent of the child, or null.
        ///
        /// Object relations may cross the object-pool boundary; for example the parent or child of
        /// an object in this pool may not itself be in this pool. It might be from a different
        /// pool and a different type of object.
        pub fn getParent(objs: *@This(), id: ObjectID) !?ObjectID {
            return objs.internal.graph.getParent(objs.internal.allocator, id);
        }

        /// Set the parent of the child, or no-op if already the case.
        ///
        /// Object relations may cross the object-pool boundary; for example the parent or child of
        /// an object in this pool may not itself be in this pool. It might be from a different
        /// pool and a different type of object.
        pub fn setParent(objs: *@This(), id: ObjectID, parent: ?ObjectID) !void {
            try objs.internal.graph.setParent(objs.internal.allocator, id, parent orelse return objs.internal.graph.removeParent(objs.internal.allocator, id));
        }

        /// Get the children of the parent; returning a results.items slice which is read-only.
        /// Call results.deinit() when you are done to return memory to the graph's memory pool for
        /// reuse later.
        ///
        /// Object relations may cross the object-pool boundary; for example the parent or child of
        /// an object in this pool may not itself be in this pool. It might be from a different
        /// pool and a different type of object.
        pub fn getChildren(objs: *@This(), id: ObjectID) !Graph.Results {
            return objs.internal.graph.getChildren(objs.internal.allocator, id);
        }

        /// Add the given child to the parent, or no-op if already the case.
        ///
        /// Object relations may cross the object-pool boundary; for example the parent or child of
        /// an object in this pool may not itself be in this pool. It might be from a different
        /// pool and a different type of object.
        pub fn addChild(objs: *@This(), id: ObjectID, child: ObjectID) !void {
            return objs.internal.graph.addChild(objs.internal.allocator, id, child);
        }

        /// Remove the given child from the parent, or no-op if not the case.
        ///
        /// Object relations may cross the object-pool boundary; for example the parent or child of
        /// an object in this pool may not itself be in this pool. It might be from a different
        /// pool and a different type of object.
        pub fn removeChild(objs: *@This(), id: ObjectID, child: ObjectID) !void {
            return objs.internal.graph.removeChild(objs.internal.allocator, id, child);
        }

        /// Copies all object data from src into this Objects instance.
        ///
        /// All objects' fields are copied (not a deep copy, so beware of pointer fields!)
        ///
        /// src.graph is not copied, and dst.graph is not modified. Tags are copied. Note that
        /// tags and the graph store object IDs, effectively array indices, not object pointers
        /// or values. The pending_delete bitset is copied (which objects are deleted but not freed)
        /// but is not registered with src.graph or dst.graph for future cascading deletes.
        ///
        /// The copy is optimized for speed rather than memory efficiency, operating under the
        /// assumption that the objects to be copied may be frequently copied from src to dst.
        /// For example, freed to-be-recycled objects are copied too rather than being garbage
        /// collected during the copy process. Additional capacity in arrays is also mirrored
        /// rather than resizing to fit only what is needed, under the assumption that capacity
        /// may be needed in the next copy.
        pub fn copyFrom(dst: *@This(), src: *const @This()) std.mem.Allocator.Error!void {
            // allocator, io, and mu fields are not copied.
            const allocator = dst.internal.allocator;

            // copy type_id
            dst.internal.type_id = src.internal.type_id;

            // copy data
            const src_len = src.internal.data.len;
            try dst.internal.data.ensureTotalCapacity(allocator, src.internal.data.capacity);
            dst.internal.data.len = src_len;
            if (has_fields) {
                const src_slice = src.internal.data.slice();
                const dst_slice = dst.internal.data.slice();
                inline for (0..@typeInfo(StorageT).@"struct".fields.len) |i| {
                    const field_tag: std.meta.FieldEnum(StorageT) = @enumFromInt(i);
                    @memcpy(dst_slice.items(field_tag)[0..src_len], src_slice.items(field_tag)[0..src_len]);
                }
            }

            // copy freed
            try dst.internal.freed.resize(allocator, src.internal.freed.bit_length, false);
            const MaskInt = std.bit_set.DynamicBitSetUnmanaged.MaskInt;
            const freed_masks = (src.internal.freed.bit_length + @bitSizeOf(MaskInt) - 1) / @bitSizeOf(MaskInt);
            if (freed_masks > 0) {
                @memcpy(dst.internal.freed.masks[0..freed_masks], src.internal.freed.masks[0..freed_masks]);
            }

            // Sync any cascaded deletions that may have occurred prior to this so our
            // pending_delete bits are up to date.
            src.internal.graph.sync(src.internal.allocator) catch {};

            try dst.internal.pending_delete.resize(allocator, src.internal.pending_delete.bit_length, false);
            const pd_masks = (src.internal.pending_delete.bit_length + @bitSizeOf(MaskInt) - 1) / @bitSizeOf(MaskInt);
            if (pd_masks > 0) {
                @memcpy(dst.internal.pending_delete.masks[0..pd_masks], src.internal.pending_delete.masks[0..pd_masks]);
            }

            // copy generation
            try dst.internal.generation.ensureTotalCapacity(allocator, src.internal.generation.capacity);
            dst.internal.generation.items.len = src_len;
            if (src_len > 0) {
                @memcpy(dst.internal.generation.items[0..src_len], src.internal.generation.items[0..src_len]);
            }

            // copy recycling_bin
            try dst.internal.recycling_bin.ensureTotalCapacity(allocator, src.internal.recycling_bin.capacity);
            dst.internal.recycling_bin.items.len = src.internal.recycling_bin.items.len;
            if (src.internal.recycling_bin.items.len > 0) {
                @memcpy(dst.internal.recycling_bin.items, src.internal.recycling_bin.items);
            }

            // copy thrown_on_the_floor
            dst.internal.thrown_on_the_floor = src.internal.thrown_on_the_floor;

            // copy updated
            if (options.track_fields) {
                if (src.internal.updated) |src_updated| {
                    try dst.internal.updated.?.resize(allocator, src_updated.bit_length, false);
                    const updated_masks = (src_updated.bit_length + @bitSizeOf(MaskInt) - 1) / @bitSizeOf(MaskInt);
                    if (updated_masks > 0) {
                        @memcpy(dst.internal.updated.?.masks[0..updated_masks], src_updated.masks[0..updated_masks]);
                    }
                }
            }

            // copy tags
            dst.internal.tags.clearRetainingCapacity();
            try dst.internal.tags.ensureTotalCapacity(allocator, src.internal.tags.capacity());
            var tag_iter = src.internal.tags.iterator();
            while (tag_iter.next()) |entry| {
                dst.internal.tags.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        /// Queries the children of the given object ID (which may be any object, including one not
        /// in this list of objects - and finds the first child which would be from this list of
        /// objects.
        pub fn getFirstChildOfType(objs: *@This(), id: ObjectID) !?ObjectID {
            var children = try objs.getChildren(id);
            defer children.deinit();
            for (children.items) |child_id| {
                if (objs.is(child_id)) return child_id;
            }
            return null;
        }
    };
}

/// Unique identifier for every module in the program, including those only known at runtime.
pub const ModuleID = u32;

/// Unique identifier for a function within a single module, including those only known at runtime.
pub const ModuleFunctionID = u16;

/// Unique identifier for a function within a module, including those only known at runtime.
pub const FunctionID = struct { module_id: ModuleID, fn_id: ModuleFunctionID };

pub fn Mod(comptime M: type) type {
    return struct {
        pub const IsMachMod = void;

        pub const module_name = M.mach_module;
        pub const Module = M;

        id: ModFunctionIDs(M),
        _ctx: *anyopaque,
        _io: std.Io,
        _call: *const fn (ctx: *anyopaque, fn_id: FunctionID) void,

        /// Calls the module's named function, e.g. `foo_mod.call(.bar)` where `.bar` is declared in
        /// the module's `pub const mach_systems`
        ///
        /// `.bar` must be comptime known.
        pub fn call(r: *const @This(), comptime f: ModuleFunctionName(M)) void {
            r.callId(@field(r.id, @tagName(f)));
        }

        /// Calls a module's named function, e.g. `foo_mod.call(bar_mod.id.bar)` where the ID comes
        /// from any registered module.
        ///
        /// This is the dynamic runtime version of call().
        pub fn callId(r: *const @This(), fn_id: FunctionID) void {
            r._call(r._ctx, fn_id);
        }

        /// Calls the module's named function using std.Io.async
        ///
        /// The return value of the function is not guaranteed to be available until `std.Io.await`
        /// is called.
        ///
        /// The function *may* be called immediately, before `async` returns. This has weaker
        /// guarantees than `concurrent`, making more portable and reusable.
        ///
        /// When this function returns, it is guaranteed that `function` has already been called and
        /// completed, or it has successfully been assigned a unit of concurrency.
        ///
        /// Refer to std.Io documentation for more details.
        pub fn async(r: *const @This(), comptime f: ModuleFunctionName(M)) std.Io.Future(void) {
            return r.asyncId(@field(r.id, @tagName(f)));
        }

        /// Equivalent to async() except it calls any module's runtime-known function ID instead of
        /// a comptime-known name.
        pub fn asyncId(r: *const @This(), fn_id: FunctionID) std.Io.Future(void) {
            return r._io.async(callErased, .{ r._call, r._ctx, fn_id });
        }

        /// Calls the module's named function using std.Io.concurrent
        ///
        /// The return value of the function is not guaranteed to be available until `await` is
        /// called, allowing the caller to progress while waiting for any `std.Io` operations.
        ///
        /// This has stronger guarantee than `async`, placing restrictions on what kind of `std.Io`
        /// implementations are supported. By calling `async` instead, one allows, for example,
        /// stackful single-threaded blocking I/O.
        ///
        /// Refer to std.Io documentation for more details.
        pub fn concurrent(r: *const @This(), comptime f: ModuleFunctionName(M)) std.Io.ConcurrentError!std.Io.Future(void) {
            return r.concurrentId(@field(r.id, @tagName(f)));
        }

        /// Equivalent to concurrent() except it calls any module's runtime-known function ID
        /// instead of a comptime-known name.
        pub fn concurrentId(r: *const @This(), fn_id: FunctionID) std.Io.ConcurrentError!std.Io.Future(void) {
            return r._io.concurrent(callErased, .{ r._call, r._ctx, fn_id });
        }

        /// Equivalent to `async`, except the task is spawned in the given `group` instead of
        /// becoming associated with a `Future`.
        pub fn asyncGroup(r: *const @This(), group: *std.Io.Group, comptime f: ModuleFunctionName(M)) void {
            r.asyncGroupId(group, @field(r.id, @tagName(f)));
        }

        /// Equivalent to asyncGroup() except it calls any module's runtime-known function ID
        /// instead of a comptime-known name.
        pub fn asyncGroupId(r: *const @This(), group: *std.Io.Group, fn_id: FunctionID) void {
            group.async(r._io, callErased, .{ r._call, r._ctx, fn_id });
        }

        /// Equivalent to `concurrent`, except the task is spawned in the given `group` instead of
        /// becoming associated with a `Future`.
        pub fn concurrentGroup(r: *const @This(), group: *std.Io.Group, comptime f: ModuleFunctionName(M)) std.Io.ConcurrentError!void {
            return r.concurrentGroupId(group, @field(r.id, @tagName(f)));
        }

        /// Equivalent to concurrentGroup() except it calls any module's runtime-known function ID
        /// instead of a comptime-known name.
        pub fn concurrentGroupId(r: *const @This(), group: *std.Io.Group, fn_id: FunctionID) std.Io.ConcurrentError!void {
            return group.concurrent(r._io, callErased, .{ r._call, r._ctx, fn_id });
        }
    };
}

/// `std.Io` async/concurrent require a comptime-known function, and at Mod.callId time we only have
/// a function pointer: this bridges the gap.
fn callErased(
    call_fn: *const fn (ctx: *anyopaque, fn_id: FunctionID) void,
    ctx: *anyopaque,
    fn_id: FunctionID,
) void {
    call_fn(ctx, fn_id);
}

pub fn ModFunctionIDs(comptime Module: type) type {
    var field_names: []const []const u8 = &.{};
    var field_types: []const type = &.{};
    var field_attrs: []const std.builtin.Type.StructField.Attributes = &.{};
    for (Module.mach_systems) |fn_name| {
        field_names = field_names ++ [_][]const u8{@tagName(fn_name)};
        field_types = field_types ++ [_]type{FunctionID};
        field_attrs = field_attrs ++ [_]std.builtin.Type.StructField.Attributes{.{
            .default_value_ptr = null,
            .@"comptime" = false,
            .@"align" = null,
        }};
    }
    return @Struct(.auto, null, field_names[0..field_names.len], field_types[0..field_types.len], field_attrs[0..field_attrs.len]);
}

/// Enum describing all declarations for a given comptime-known module.
fn ModuleFunctionName(comptime M: type) type {
    validate(M);
    var enum_names: []const []const u8 = &.{};
    inline for (M.mach_systems) |fn_tag| {
        enum_names = enum_names ++ [_][]const u8{@tagName(fn_tag)};
    }
    const TagType = if (enum_names.len > 0) std.math.IntFittingRange(0, enum_names.len - 1) else u0;
    return @Enum(TagType, .exhaustive, enum_names, &std.simd.iota(TagType, enum_names.len));
}

/// Validates that every entry in `M.mach_systems` has a corresponding `pub fn <name>` or
/// `pub const <name> = mach.schedule(...)` decl.
///
/// Do not call this in the path of mach.schedule() because it could result in circular evaluation
/// of self-referential schedule decls.
fn validateModuleSystemDecls(comptime M: type) void {
    inline for (M.mach_systems) |fn_tag| {
        const name = @tagName(fn_tag);
        if (!@hasDecl(M, name)) {
            @compileError("Module ." ++ @tagName(M.mach_module) ++ " declares mach_systems entry ." ++ name ++ " but has no `pub fn " ++ name ++ "` or `pub const " ++ name ++ " = mach.schedule(...)` decl");
        }
        const F = @TypeOf(@field(M, name));
        const f_info = @typeInfo(F);
        const is_fn = f_info == .@"fn";
        const is_schedule = f_info == .@"struct" and f_info.@"struct".is_tuple;
        if (!is_fn and !is_schedule) {
            @compileError("Module ." ++ @tagName(M.mach_module) ++ " mach_systems entry ." ++ name ++ " must be a `pub fn` or `pub const " ++ name ++ " = mach.schedule(...)`, found: " ++ @typeName(F));
        }
    }
}

/// Enum describing all mach_tags for a given comptime-known module.
fn ModuleTagEnum(comptime M: type) type {
    // TODO(object): handle duplicate enum field case in mach_tags with a more clear error?
    // TODO(object): improve validation error messages here
    validate(M);
    if (@typeInfo(@TypeOf(M.mach_tags)) != .@"struct") {
        @compileError("mach: invalid module, `pub const mach_tags must be `.{ .is_monster, .{ .renderer, mach.Renderer.objects } }`, found: " ++ @typeName(@TypeOf(M.mach_tags)));
    }
    var enum_names: []const []const u8 = &.{};
    inline for (@typeInfo(@TypeOf(M.mach_tags)).@"struct".fields, 0..) |field, field_index| {
        const f = M.mach_tags[field_index];
        if (@typeInfo(field.type) == .enum_literal) {
            enum_names = enum_names ++ [_][]const u8{@tagName(f)};
        } else {
            if (@typeInfo(field.type) != .@"struct") {
                @compileError("mach: invalid module, mach_tags entry is not an enum literal or struct, found: " ++ @typeName(field.type));
            }
            // TODO(objects): validate length of struct
            const tag = f.@"0";
            const M2 = f.@"1";
            const object_list_tag = f.@"2";
            _ = object_list_tag; // autofix
            validate(M2);
            // TODO: validate that M2.object_list_tag is a mach objects list
            enum_names = enum_names ++ [_][]const u8{@tagName(tag)};
        }
    }
    const TagType = if (enum_names.len > 0) std.math.IntFittingRange(0, enum_names.len - 1) else u0;
    return @Enum(TagType, .exhaustive, enum_names, &std.simd.iota(TagType, enum_names.len));
}

pub fn Modules(module_lists: anytype) type {
    inline for (moduleTuple(module_lists)) |module| {
        validate(module);
        validateModuleSystemDecls(module);
    }
    return struct {
        /// All modules.
        // These already pass validate()
        pub const modules = moduleTuple(module_lists);

        /// Enum describing every module name compiled into the program.
        pub const ModuleName = NameEnum(modules);

        /// A struct whose comptime field of name `<module_name>` is the module type.
        // This is hoisted up here, not written inline, to avoid expending needless comptime eval
        // branches.
        const module_types_by_name = ModuleTypesByName(modules){};

        mods: ModulesByName(modules) = undefined,
        io: std.Io = undefined,
        allocator: std.mem.Allocator = undefined,

        module_names: StringTable = .{},
        object_names: StringTable = .{},
        name_ids: std.MultiArrayList(struct {
            module_name_id: u32,
            object_name_id: u32,
        }) = .{},
        graph: Graph = undefined,

        /// True once `init` has run once.
        initialized: bool = false,

        pub fn init(
            m: *@This(),
            allocator: std.mem.Allocator,
            io: std.Io,
        ) (std.mem.Allocator.Error || std.Thread.SpawnError || error{
            AlreadyInitialized,
        })!void {
            if (m.initialized) return error.AlreadyInitialized;
            m.io = io;
            m.allocator = allocator;
            m.module_names = .{};
            m.object_names = .{};
            m.name_ids = .{};
            try initGraph(&m.graph, allocator, io, .global);
            errdefer {
                m.graph.deinit(allocator);
                m.name_ids.deinit(allocator);
                m.object_names.deinit(allocator);
                m.module_names.deinit(allocator);
            }

            inline for (@typeInfo(@TypeOf(m.mods)).@"struct".fields) |field| {
                // TODO(objects): module-state-init
                const Mod2 = @TypeOf(@field(m.mods, field.name));
                var mod: Mod2 = undefined;
                const module_name_id = try m.module_names.indexOrPut(allocator, @tagName(Mod2.mach_module));
                const mod_fields = @typeInfo(@TypeOf(mod)).@"struct".fields;
                try m.name_ids.ensureUnusedCapacity(allocator, mod_fields.len);
                inline for (mod_fields) |mod_field| {
                    if (@typeInfo(mod_field.type) == .@"struct" and @hasDecl(mod_field.type, "IsMachObjects")) {
                        const object_name_id = try m.object_names.indexOrPut(allocator, mod_field.name);

                        const object_type_id = m.name_ids.addOneAssumeCapacity();
                        m.name_ids.set(object_type_id, .{
                            .module_name_id = module_name_id,
                            .object_name_id = object_name_id,
                        });

                        @field(mod, mod_field.name).internal = .{
                            .allocator = allocator,
                            .io = io,
                            .type_id = @intCast(object_type_id),
                            .graph = &m.graph,
                        };
                    }
                }
                @field(m.mods, field.name) = mod;

                // Register each Objects pool's pending_delete bitset and mutex with the graph
                // so that delete() can cascade across pools via cascadeDelete().
                inline for (mod_fields) |mod_field| {
                    if (@typeInfo(mod_field.type) == .@"struct" and @hasDecl(mod_field.type, "IsMachObjects")) {
                        const objs = &@field(@field(m.mods, field.name), mod_field.name);
                        try m.graph.registerDeletePool(allocator, objs.internal.type_id, &objs.internal.pending_delete, &objs.internal.mu);
                    }
                }
            }

            m.initialized = true;
        }

        fn deinitObjectPools(m: *@This(), allocator: std.mem.Allocator) void {
            inline for (@typeInfo(@TypeOf(m.mods)).@"struct".fields) |field| {
                const M = @TypeOf(@field(m.mods, field.name));
                inline for (@typeInfo(M).@"struct".fields) |mod_field| {
                    if (@typeInfo(mod_field.type) == .@"struct" and
                        @hasDecl(mod_field.type, "IsMachObjects"))
                    {
                        @field(@field(m.mods, field.name), mod_field.name).deinit(allocator);
                    }
                }
            }
        }

        pub fn deinit(m: *@This(), allocator: std.mem.Allocator) void {
            if (!m.initialized) return;
            m.graph.deinit(allocator);
            m.deinitObjectPools(allocator);
            m.name_ids.deinit(allocator);
            m.object_names.deinit(allocator);
            m.module_names.deinit(allocator);
            m.initialized = false;
        }

        pub fn Module(module_tag_or_type: anytype) type {
            const module_name: ModuleName = blk: {
                if (@typeInfo(@TypeOf(module_tag_or_type)) == .enum_literal or @typeInfo(@TypeOf(module_tag_or_type)) == .@"enum") break :blk @as(ModuleName, module_tag_or_type);
                validate(module_tag_or_type);
                break :blk module_tag_or_type.mach_module;
            };

            // Note: no need to validate(module) here because it is derived from `modules`.
            const module = @field(module_types_by_name, @tagName(module_name));

            return struct {
                mods: *ModulesByName(modules),
                modules: *Modules(module_lists),

                pub const mod_name: ModuleName = module_name;

                /// The allocator injected into module functions with a std.mem.Allocator parameter.
                pub fn allocator(m: *const @This()) std.mem.Allocator {
                    return m.modules.allocator;
                }

                /// The Io injected into module functions with a std.Io parameter.
                pub fn io(m: *const @This()) std.Io {
                    return m.modules.io;
                }

                pub fn getFunction(fn_name: ModuleFunctionName(module)) FunctionID {
                    return .{
                        .module_id = @intFromEnum(mod_name),
                        .fn_id = @intFromEnum(fn_name),
                    };
                }

                pub fn call(
                    m: *const @This(),
                    comptime fn_name: ModuleFunctionName(module),
                ) void {
                    const debug_name = @tagName(module_name) ++ "." ++ @tagName(fn_name);
                    if (!@hasField(module, @tagName(fn_name)) and !@hasDecl(module, @tagName(fn_name))) {
                        @compileError("Module ." ++ @tagName(module_name) ++ " declares mach_systems entry ." ++ @tagName(fn_name) ++ " but no pub fn or schedule with that name exists.");
                    }
                    const f = @field(module, @tagName(fn_name));
                    const F = @TypeOf(f);

                    if (@typeInfo(F) == .@"struct" and @typeInfo(F).@"struct".is_tuple) {
                        // Run a list of functions instead of a single function
                        // TODO: verify this is a mach.schedule() decl
                        inline for (f) |schedule_entry| {
                            // TODO: unify with Modules(modules).get(M)
                            const callMod: Module(schedule_entry.@"0") = .{ .mods = m.mods, .modules = m.modules };
                            if (!@hasField(ModuleFunctionName(schedule_entry.@"0"), @tagName(schedule_entry.@"1"))) {
                                @compileError("Module ." ++ @tagName(@TypeOf(callMod).mod_name) ++ " has no mach_systems entry '." ++ @tagName(schedule_entry.@"1") ++ "'");
                            }
                            const callFn = @as(ModuleFunctionName(schedule_entry.@"0"), schedule_entry.@"1");
                            callMod.call(callFn);
                        }
                        return;
                    }

                    // Inject arguments
                    var args: std.meta.ArgsTuple(F) = undefined;
                    outer: inline for (@typeInfo(std.meta.ArgsTuple(F)).@"struct".fields) |arg| {
                        if (@typeInfo(arg.type) == .pointer and
                            @typeInfo(std.meta.Child(arg.type)) == .@"struct" and
                            comptime isValid(std.meta.Child(arg.type)))
                        {
                            // *Module argument
                            // TODO: better error if @field(m.mods, ...) fails ("module not registered")
                            @field(args, arg.name) = &@field(m.mods, @tagName(std.meta.Child(arg.type).mach_module));
                            continue :outer;
                        }
                        if (arg.type == std.Io) {
                            @field(args, arg.name) = m.modules.io;
                            continue :outer;
                        }
                        if (arg.type == std.mem.Allocator) {
                            @field(args, arg.name) = m.modules.allocator;
                            continue :outer;
                        }
                        if (@typeInfo(arg.type) == .@"struct" and @hasDecl(arg.type, "IsMachMod")) {
                            const M = arg.type.Module;
                            var mv: Mod(M) = .{
                                .id = undefined,
                                ._ctx = m.modules,
                                ._io = m.modules.io,
                                ._call = (struct {
                                    pub fn call(ctx: *anyopaque, fn_id: FunctionID) void {
                                        const modules2: *Modules(module_lists) = @ptrCast(@alignCast(ctx));
                                        modules2.callDynamic(fn_id);
                                    }
                                }).call,
                            };
                            inline for (M.mach_systems) |m_fn_name| {
                                @field(mv.id, @tagName(m_fn_name)) = Module(M).getFunction(m_fn_name);
                            }
                            @field(args, arg.name) = mv;
                            continue :outer;
                        }
                        @compileError("mach: function " ++ debug_name ++ " has an invalid argument(" ++ arg.name ++ ") type: " ++ @typeName(arg.type));
                    }

                    const Ret = @typeInfo(F).@"fn".return_type orelse void;
                    switch (@typeInfo(Ret)) {
                        // TODO: define error handling of runnable functions
                        .error_union => @call(.auto, f, args) catch |err| std.debug.panic("error: {s}", .{@errorName(err)}),
                        else => @call(.auto, f, args),
                    }
                }
            };
        }

        pub fn get(m: *@This(), module_tag_or_type: anytype) Module(module_tag_or_type) {
            return .{ .mods = &m.mods, .modules = m };
        }

        pub fn callDynamic(m: *@This(), f: FunctionID) void {
            if (comptime modules.len == 0) return;
            const module_name: ModuleName = @enumFromInt(f.module_id);
            switch (module_name) {
                inline else => |mod_name| {
                    const M = @field(module_types_by_name, @tagName(mod_name));
                    const module_fn_name: ModuleFunctionName(M) = @enumFromInt(f.fn_id);
                    const mod: Module(mod_name) = .{ .mods = &m.mods, .modules = m };
                    // Note: we don't need to validate the module here because it is derived from
                    // `modules`.

                    switch (module_fn_name) {
                        inline else => |fn_name| mod.call(fn_name),
                    }
                },
            }
        }
    };
}

/// Validates that the given struct is a Mach module.
fn validate(comptime M: type) void {
    if (!@hasDecl(M, "mach_module")) {
        @compileError("mach: invalid module, missing `pub const mach_module = .foo;`: " ++
            @typeName(M));
    }
    if (@typeInfo(@TypeOf(M.mach_module)) != .enum_literal) {
        @compileError("mach: invalid module, `mach_module` must be an enum literal, found: " ++
            @typeName(@TypeOf(M.mach_module)));
    }
    if (!@hasDecl(M, "mach_systems")) {
        @compileError("mach: invalid module, missing `pub const mach_systems = .{ ... };`: " ++
            @typeName(M));
    }
    const systems_info = @typeInfo(@TypeOf(M.mach_systems));
    if (systems_info != .@"struct" or !systems_info.@"struct".is_tuple) {
        @compileError("mach: invalid module, `mach_systems` must be a tuple, found: " ++
            @typeName(@TypeOf(M.mach_systems)));
    }
    inline for (M.mach_systems) |system| {
        if (@typeInfo(@TypeOf(system)) != .enum_literal) {
            @compileError("mach: invalid module, `mach_systems` entries must be enum literals");
        }
    }
}

fn isValid(comptime M: type) bool {
    if (!@hasDecl(M, "mach_module")) return false;
    if (@typeInfo(@TypeOf(M.mach_module)) != .enum_literal) return false;
    if (!@hasDecl(M, "mach_systems")) return false;
    const systems_info = @typeInfo(@TypeOf(M.mach_systems));
    if (systems_info != .@"struct" or !systems_info.@"struct".is_tuple) return false;
    return true;
}

/// Given a tuple of Mach module structs, returns an enum which has every possible comptime-known
/// module name.
fn NameEnum(comptime mods: anytype) type {
    var enum_names: []const []const u8 = &.{};
    for (mods) |module| {
        validate(module);
        enum_names = enum_names ++ [_][]const u8{@tagName(module.mach_module)};
    }
    const TagType = if (enum_names.len > 0) std.math.IntFittingRange(0, enum_names.len - 1) else u0;
    return @Enum(TagType, .exhaustive, enum_names, &std.simd.iota(TagType, enum_names.len));
}

/// Given a tuple of module structs or module struct tuples:
///
/// ```
/// .{
///     .{ Baz, .{ Bar, Foo, .{ Fam } }, Bar },
///     Foo,
///     Bam,
///     .{ Foo, Bam },
/// }
/// ```
///
/// Returns a flat tuple, deduplicated:
///
/// .{ Baz, Bar, Foo, Fam, Bar, Bam }
///
fn moduleTuple(comptime tuple: anytype) []const type {
    return moduleTupleCollect(tuple);
}

fn moduleTupleCollect(comptime tuple: anytype) []const type {
    if (@typeInfo(@TypeOf(tuple)) != .@"struct" or !@typeInfo(@TypeOf(tuple)).@"struct".is_tuple) {
        @compileError("Expected to find a tuple, found: " ++ @typeName(@TypeOf(tuple)));
    }

    var types: []const type = &.{};
    for (tuple) |elem| {
        if (@typeInfo(@TypeOf(elem)) == .type and @typeInfo(elem) == .@"struct") {
            // Struct type
            validate(elem);
            for (types) |t| if (t == elem) continue;
            types = types ++ [_]type{elem};
        } else if (@typeInfo(@TypeOf(elem)) == .@"struct" and @typeInfo(@TypeOf(elem)).@"struct".is_tuple) {
            // Nested tuple
            for (moduleTupleCollect(elem)) |nested| {
                validate(nested);
                for (types) |t| if (t == nested) continue;
                types = types ++ [_]type{nested};
            }
        } else {
            @compileError("Expected to find a tuple or struct type, found: " ++ @typeName(@TypeOf(elem)));
        }
    }
    return types;
}

/// Given .{Foo, Bar, Baz} Mach modules, returns .{.foo = Foo, .bar = Bar, .baz = Baz} with field
/// names corresponding to each module's `pub const mach_module = .foo;` name.
fn ModuleTypesByName(comptime modules: anytype) type {
    var field_names: []const []const u8 = &.{};
    var field_types: []const type = &.{};
    var field_attrs: []const std.builtin.Type.StructField.Attributes = &.{};
    for (modules) |M| {
        field_names = field_names ++ [_][]const u8{@tagName(M.mach_module)};
        field_types = field_types ++ [_]type{type};
        field_attrs = field_attrs ++ [_]std.builtin.Type.StructField.Attributes{.{
            .default_value_ptr = @ptrCast(&M),
            .@"comptime" = true,
            .@"align" = null,
        }};
    }
    return @Struct(.auto, null, field_names[0..field_names.len], field_types[0..field_types.len], field_attrs[0..field_attrs.len]);
}

/// Given .{Foo, Bar, Baz} Mach modules, returns .{.foo: Foo = undefined, .bar: Bar = undefined, .baz: Baz = undefined}
/// with field names corresponding to each module's `pub const mach_module = .foo;` name, and each Foo type.
fn ModulesByName(comptime modules: anytype) type {
    var field_names: []const []const u8 = &.{};
    var field_types: []const type = &.{};
    var field_attrs: []const std.builtin.Type.StructField.Attributes = &.{};
    for (modules) |M| {
        field_names = field_names ++ [_][]const u8{@tagName(M.mach_module)};
        field_types = field_types ++ [_]type{M};
        field_attrs = field_attrs ++ [_]std.builtin.Type.StructField.Attributes{.{
            .default_value_ptr = @ptrCast(&@as(M, undefined)),
            .@"comptime" = false,
            .@"align" = null,
        }};
    }
    return @Struct(.auto, null, field_names[0..field_names.len], field_types[0..field_types.len], field_attrs[0..field_attrs.len]);
}

test "Long field name" {
    const test_module = struct {
        pub const mach_module = .test_module;
        pub const mach_systems = .{};
        really_really_really_really_really_really_really_long_field_name: Objects(.{}, struct {}),
        another_field: Objects(.{}, struct {}),
    };

    const allocator = std.testing.allocator;

    const io = std.Options.debug_io;
    var modules: Modules(.{test_module}) = .{};
    try modules.init(allocator, io);
    modules.deinit(allocator);
}

test "Many fields, same module" {
    const test_module = struct {
        pub const mach_module = .test_module;
        pub const mach_systems = .{};
        field0: Objects(.{}, struct {}),
        field1: Objects(.{}, struct {}),
        field2: Objects(.{}, struct {}),
        field3: Objects(.{}, struct {}),
        field4: Objects(.{}, struct {}),
        field5: Objects(.{}, struct {}),
        field6: Objects(.{}, struct {}),
        field7: Objects(.{}, struct {}),
        field8: Objects(.{}, struct {}),
        field9: Objects(.{}, struct {}),
    };

    const allocator = std.testing.allocator;

    const io = std.Options.debug_io;
    var modules: Modules(.{test_module}) = .{};
    try modules.init(allocator, io);
    modules.deinit(allocator);
}

test "Many fields, Many modules" {
    const test_module0 = struct {
        pub const mach_module = .test_module0;
        pub const mach_systems = .{};
        field0: Objects(.{}, struct {}),
        field1: Objects(.{}, struct {}),
        field2: Objects(.{}, struct {}),
        field3: Objects(.{}, struct {}),
    };
    const test_module1 = struct {
        pub const mach_module = .test_module1;
        pub const mach_systems = .{};
        field4: Objects(.{}, struct {}),
        field5: Objects(.{}, struct {}),
        field6: Objects(.{}, struct {}),
        field7: Objects(.{}, struct {}),
    };
    const test_module2 = struct {
        pub const mach_module = .test_module2;
        pub const mach_systems = .{};
        field8: Objects(.{}, struct {}),
        field9: Objects(.{}, struct {}),
    };

    const allocator = std.testing.allocator;

    const io = std.Options.debug_io;
    var modules: Modules(.{ test_module0, test_module1, test_module2 }) = .{};
    try modules.init(allocator, io);
    modules.deinit(allocator);
}

test "Modules.init cleans up allocation failures" {
    const TestModule = struct {
        pub const mach_module = .test_module;
        pub const mach_systems = .{};
        first: Objects(.{}, struct {}),
        second: Objects(.{}, struct {}),
    };
    const testInit = struct {
        fn run(allocator: std.mem.Allocator) !void {
            var modules: Modules(.{TestModule}) = .{};
            try modules.init(allocator, std.Options.debug_io);
            modules.deinit(allocator);
        }
    }.run;

    try std.testing.checkAllAllocationFailures(std.testing.allocator, testInit, .{});
}

test "Modules lifecycle" {
    const TestModule = struct {
        pub const mach_module = .test_module;
        pub const mach_systems = .{};
        objects: Objects(.{}, struct {}),
    };

    const allocator = std.testing.allocator;
    var modules: Modules(.{TestModule}) = .{};

    try modules.init(allocator, std.Options.debug_io);
    try std.testing.expectError(
        error.AlreadyInitialized,
        modules.init(allocator, std.Options.debug_io),
    );

    modules.deinit(allocator);
    modules.deinit(allocator);

    try modules.init(allocator, std.Options.debug_io);
    modules.deinit(allocator);
}

test "Mod.call" {
    // Records which module functions ran during the test.
    const recorder = struct {
        var bar_ran: bool = false;
    };
    const test_module = struct {
        pub const mach_module = .test_module;
        pub const mach_systems = .{ .barSystem, .tick };

        pub fn barSystem() void {
            recorder.bar_ran = true;
        }

        pub fn tick(m: Mod(@This())) void {
            // Mod.call dispatches a comptime-known function by its `.name` literal.
            m.call(.barSystem);
        }
    };

    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = aa.allocator();
    defer aa.deinit();

    const io = std.Options.debug_io;
    var modules: Modules(.{test_module}) = .{};
    try modules.init(allocator, io);
    defer modules.deinit(allocator);

    recorder.bar_ran = false;
    modules.get(.test_module).call(.tick);
    try std.testing.expect(recorder.bar_ran);
}

test "Mod.callId" {
    // Records which module functions ran during the test.
    const recorder = struct {
        var foo_ran: bool = false;
    };
    const test_module = struct {
        pub const mach_module = .test_module;
        pub const mach_systems = .{ .fooSystem, .tick };

        pub fn fooSystem() void {
            recorder.foo_ran = true;
        }

        pub fn tick(m: Mod(@This())) void {
            // Mod.callId dispatches a runtime FunctionID; `m.id.<name>` holds the ID for each system.
            m.callId(m.id.fooSystem);
        }
    };

    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = aa.allocator();
    defer aa.deinit();

    const io = std.Options.debug_io;
    var modules: Modules(.{test_module}) = .{};
    try modules.init(allocator, io);
    defer modules.deinit(allocator);

    recorder.foo_ran = false;
    modules.get(.test_module).call(.tick);
    try std.testing.expect(recorder.foo_ran);
}

test "Mod.async / asyncId / concurrent" {
    // Records which module functions ran during the test.
    const recorder = struct {
        var async_ran: bool = false;
        var async_id_ran: bool = false;
        var concurrent_ran: bool = false;
        var concurrent_unavailable: bool = false;
    };
    const test_module = struct {
        pub const mach_module = .test_module;
        pub const mach_systems = .{ .asyncSystem, .asyncIdSystem, .concurrentSystem, .tick };

        pub fn asyncSystem() void {
            recorder.async_ran = true;
        }
        pub fn asyncIdSystem() void {
            recorder.async_id_ran = true;
        }
        pub fn concurrentSystem() void {
            recorder.concurrent_ran = true;
        }

        pub fn tick(m: Mod(@This()), io: std.Io) void {
            // Future-returning form (no group): the future must be awaited. `async` is the
            // type-safe helper; `asyncId` takes the runtime FunctionID directly.
            var async_future = m.async(.asyncSystem);
            async_future.await(io);

            var async_id_future = m.asyncId(m.id.asyncIdSystem);
            async_id_future.await(io);

            // Concurrent form requires the Io implementation to provide concurrency; unlike the
            // async form it may fail with error.ConcurrencyUnavailable (e.g. the single-threaded
            // debug Io used in these tests).
            var concurrent_future = m.concurrent(.concurrentSystem) catch |err| switch (err) {
                error.ConcurrencyUnavailable => {
                    recorder.concurrent_unavailable = true;
                    return;
                },
            };
            concurrent_future.await(io);
        }
    };

    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = aa.allocator();
    defer aa.deinit();

    const io = std.Options.debug_io;
    var modules: Modules(.{test_module}) = .{};
    try modules.init(allocator, io);
    defer modules.deinit(allocator);

    recorder.async_ran = false;
    recorder.async_id_ran = false;
    recorder.concurrent_ran = false;
    recorder.concurrent_unavailable = false;
    modules.get(.test_module).call(.tick);
    try std.testing.expect(recorder.async_ran);
    try std.testing.expect(recorder.async_id_ran);
    // The concurrent task either ran, or the Io implementation reported it could not.
    try std.testing.expect(recorder.concurrent_ran or recorder.concurrent_unavailable);
}

test "Mod.asyncGroup / asyncGroupId / concurrentGroup" {
    // Records how many module functions ran during the test.
    const recorder = struct {
        var ran: std.atomic.Value(u32) = .init(0);
    };
    const test_module = struct {
        pub const mach_module = .test_module;
        pub const mach_systems = .{ .work, .tick };

        pub fn work() void {
            _ = recorder.ran.fetchAdd(1, .monotonic);
        }

        pub fn tick(m: Mod(@This()), io: std.Io) void {
            var group: std.Io.Group = .init;
            // Group form (no future): tasks are owned by the group and released when it is awaited.
            m.asyncGroup(&group, .work);
            m.asyncGroupId(&group, m.id.work);
            m.concurrentGroup(&group, .work) catch |err| switch (err) {
                error.ConcurrencyUnavailable => {},
            };
            group.await(io) catch {};
        }
    };

    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = aa.allocator();
    defer aa.deinit();

    const io = std.Options.debug_io;
    var modules: Modules(.{test_module}) = .{};
    try modules.init(allocator, io);
    defer modules.deinit(allocator);

    recorder.ran.store(0, .monotonic);
    modules.get(.test_module).call(.tick);
    // The two async tasks always run; the concurrent one runs too if the Io supports concurrency.
    try std.testing.expect(recorder.ran.load(.monotonic) >= 2);
}
