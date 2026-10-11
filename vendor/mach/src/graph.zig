const std = @import("std");
const testing = std.testing;

const Queue = @import("mpsc.zig").Queue;
const Pool = @import("mpsc.zig").Pool;

/// Node in the graph, represents an object that can have parent/child relations
const Node = struct {
    id: u64,
    next: ?*Node = null, // Used by Pool, otherwise stores next_sibling
    parent: ?*Node = null,
    first_child: ?*Node = null,

    /// Returns true if this node has the given node as a child
    fn hasChild(n: *Node, child_id: u64) bool {
        var current = n.first_child;
        while (current) |child| : (current = child.next) {
            if (child.id == child_id) return true;
        }
        return false;
    }

    /// Adds a child to this node's children list
    fn addChild(n: *Node, child: *Node) void {
        var last_child: ?*Node = null;
        var current = n.first_child;
        while (current) |curr| : (current = curr.next) {
            last_child = curr;
        }

        child.parent = n;
        if (last_child) |last| last.next = child else n.first_child = child;
    }

    /// Removes a child from this node's children list
    fn removeChild(n: *Node, child_id: u64) void {
        if (n.first_child) |first| {
            if (first.id == child_id) {
                n.first_child = first.next;
                if (first.parent == n) {
                    first.parent = null;
                    first.next = null; // Clear the next pointer
                }
                return;
            }

            var prev = first;
            var current = first.next;
            while (current) |curr| {
                if (curr.id == child_id) {
                    prev.next = curr.next;
                    if (curr.parent == n) {
                        curr.parent = null;
                        curr.next = null; // Clear the next pointer
                    }
                    break;
                }
                prev = curr;
                current = curr.next;
            }
        }
    }
};

/// Error set for graph operations
pub const Error = error{
    OutOfMemory,
};

/// Read/write/mutate operations to perform on the graph.
const Op = union(enum) {
    /// Add a child to a parent. no-op if already a child.
    add_child: struct { parent_id: u64, child_id: u64 },

    /// Remove a child from a parent. no-op if not a child.
    remove_child: struct { parent_id: u64, child_id: u64 },

    /// Set the parent of a child node. no-op if already has this parent.
    set_parent: struct { child_id: u64, parent_id: u64 },

    /// Remove the parent of a child node. no-op if no parent.
    remove_parent: struct { child_id: u64 },

    /// Mark all descendants of the given node as .pending_delete in their respective Objects lists.
    cascade_delete: struct { id: u64 },

    /// Signals when all prior operations have been processed. Used by sync() to wait for pending
    /// writes.
    sync: struct { done: *std.atomic.Value(bool) },

    /// Query the children of the given node
    get_children: struct {
        node_id: u64,
        result: *std.ArrayList(u64),
        err: *?Error,
        done: *std.atomic.Value(bool),
    },

    /// Query the parent of a node
    get_parent: struct {
        node_id: u64,
        result: *?u64,
        done: *std.atomic.Value(bool),
    },
};

/// A graph of objects with parent/child/etc relations.
///
/// Reads/writes/mutations to the graph can be performed by any thread in parallel. This is possible
/// without a global mutex locking the entire graph because we represent all interactions with the
/// graph as /operations/ enqueued to a lock-free Multi Producer, Single Consumer (MPSC) FIFO queue.
///
/// When an operation is desired (adding a parent to a child, querying the children or parent of a
/// node, etc.) it is enqueued. Then, a background thread processes all pending operations. Atomics
/// are used to wait for reads to complete, and parallel writes are lock-free.
///
/// The graph uses lock-free pools to manage all nodes internally, eliminating runtime allocations
/// during operation processing.
pub const Graph = struct {
    /// Mirrors module.zig's PackedID layout for decoding ObjectIDs.
    const PackedID = packed struct(u64) {
        type_id: u16,
        generation: u16,
        index: u32,
    };

    const PoolDeleteInfo = struct {
        bitset: *std.bit_set.DynamicBitSetUnmanaged,
        mu: *std.Io.RwLock,
    };

    /// Queue of read/write/mutation operations to the graph.
    queue: Queue(Op),

    /// Pool of nodes for allocation and recycling.
    nodes: Pool(Node),

    io: std.Io,

    /// Maps node IDs to their struct, protected by a read-write lock
    id_to_node: struct {
        map: std.AutoHashMapUnmanaged(u64, *Node) = .{},
        lock: std.Io.RwLock = .init,
    } = .{},

    /// Pool of ArrayLists for query results
    result_lists: struct {
        available: std.ArrayList(*std.ArrayList(u64)) = .empty,
        lock: std.Io.Mutex = .init,
    } = .{},

    /// Registry of pending_delete bitsets and mutexes from each Objects pool, indexed by
    /// type_id.
    pending_delete_pools: std.ArrayList(PoolDeleteInfo) = .empty,

    preallocate_result_list_size: u32,

    /// Thread that processes operations from the queue
    thread: ?std.Thread = null,

    /// Flag to signal the processing thread to stop
    should_stop: std.atomic.Value(bool) = .init(false),

    /// Lock held while processing queue operations. Acquired during copyFrom to pause both
    /// src and dst processing threads while the snapshot is taken.
    process_mu: std.Io.Mutex = .init,

    /// Set by copyFrom to signal the processing thread to release process_mu promptly.
    copy_pending: std.atomic.Value(bool) = .init(false),

    /// Signaled by producers after pushing to the queue (and by deinit) so the processing thread
    /// can sleep instead of busy-spinning when there is no work to do.
    wake_event: std.Io.Event = .unset,

    /// Initialize the graph with the given pre-allocated space for nodes and operations.
    ///
    /// Spawns a backgroound thread for processing operations to the graph.
    pub fn init(
        graph: *Graph,
        allocator: std.mem.Allocator,
        io: std.Io,
        preallocate: struct {
            queue_size: u32,
            nodes_size: u32,
            num_result_lists: u32,
            result_list_size: u32,
        },
    ) !void {
        graph.* = .{
            .queue = undefined,
            .nodes = undefined,
            .io = io,
            .preallocate_result_list_size = preallocate.result_list_size,
        };

        try graph.queue.init(allocator, io, preallocate.queue_size);
        errdefer graph.queue.deinit(allocator);

        try graph.id_to_node.map.ensureTotalCapacity(allocator, preallocate.nodes_size);
        errdefer graph.id_to_node.map.deinit(allocator);

        graph.nodes = try Pool(Node).init(allocator, io, preallocate.nodes_size);
        errdefer graph.nodes.deinit(allocator);

        // Pre-allocate result lists
        try graph.result_lists.available.ensureTotalCapacity(allocator, preallocate.num_result_lists);
        errdefer {
            for (graph.result_lists.available.items) |list| {
                list.deinit(allocator);
                allocator.destroy(list);
            }
            graph.result_lists.available.deinit(allocator);
        }

        for (0..preallocate.num_result_lists) |_| {
            var list = try allocator.create(std.ArrayList(u64));
            list.* = .empty;
            errdefer {
                list.deinit(allocator);
                allocator.destroy(list);
            }
            try list.ensureTotalCapacity(allocator, preallocate.result_list_size);
            try graph.result_lists.available.append(allocator, list);
        }

        graph.thread = try std.Thread.spawn(.{ .allocator = allocator }, processThread, .{ graph, allocator });
    }

    pub fn deinit(graph: *Graph, allocator: std.mem.Allocator) void {
        graph.should_stop.store(true, .release);
        graph.wake_event.set(graph.io); // wake the processing thread so it observes should_stop
        graph.thread.?.join();
        for (graph.result_lists.available.items) |list| {
            list.deinit(allocator);
            allocator.destroy(list);
        }
        graph.result_lists.available.deinit(allocator);
        graph.id_to_node.map.deinit(allocator);
        graph.nodes.deinit(allocator);
        graph.queue.deinit(allocator);
        graph.pending_delete_pools.deinit(allocator);
    }

    /// Get an existing Node for the given ID, or null if not found
    fn getNode(graph: *Graph, id: u64) ?*Node {
        graph.id_to_node.lock.lockSharedUncancelable(graph.io);
        defer graph.id_to_node.lock.unlockShared(graph.io);
        return graph.id_to_node.map.get(id);
    }

    /// Returns true if the given object has any children in the graph.
    pub fn hasChildren(graph: *Graph, id: u64) bool {
        graph.id_to_node.lock.lockSharedUncancelable(graph.io);
        defer graph.id_to_node.lock.unlockShared(graph.io);
        const node = graph.id_to_node.map.get(id) orelse return false;
        return node.first_child != null;
    }

    /// Register an Objects's .pending_delete bitset and mutex so that cascadeDelete() can set bits
    /// across different pools when cascading a delete.
    ///
    /// The type_id must equal the current length of the list (i.e. type_ids must be registered in
    /// order).
    pub fn registerDeletePool(graph: *Graph, allocator: std.mem.Allocator, type_id: u16, bitset: *std.bit_set.DynamicBitSetUnmanaged, mu: *std.Io.RwLock) !void {
        std.debug.assert(type_id == graph.pending_delete_pools.items.len);
        try graph.pending_delete_pools.append(allocator, .{ .bitset = bitset, .mu = mu });
    }

    /// Enqueues an operation to mark all descendants of the given object as .pending_delete
    /// in their respective Objects pool.
    ///
    /// Processed asynchronously by the graph's background thread, use sync() to observe completion.
    pub fn cascadeDelete(graph: *Graph, allocator: std.mem.Allocator, id: u64) Error!void {
        try graph.queue.push(allocator, .{ .cascade_delete = .{ .id = id } });
        graph.wake_event.set(graph.io);
    }

    fn doCascadeDelete(graph: *Graph, node: *Node) void {
        var child = node.first_child;
        while (child) |c| : (child = c.next) {
            const unpacked: PackedID = @bitCast(c.id);
            if (unpacked.type_id < graph.pending_delete_pools.items.len) {
                const pool = &graph.pending_delete_pools.items[unpacked.type_id];
                pool.mu.lockUncancelable(graph.io);
                pool.bitset.set(unpacked.index);
                pool.mu.unlock(graph.io);
            }
            graph.doCascadeDelete(c);
        }
    }

    /// The thread that runs continuously in the background to process queue submissions.
    fn processThread(graph: *Graph, allocator: std.mem.Allocator) void {
        while (!graph.should_stop.load(.acquire)) {
            graph.drainQueue(allocator);
            if (graph.should_stop.load(.acquire)) break;

            // We must reset BEFORE the final drain to close the lost-wakeup race:
            //   - If a producer pushes between the first drain and the reset, the reset clears
            //     their wake; the second drain after reset will pick up their item and we loop
            //     again without sleeping.
            //   - If a producer pushes after the reset, their set() will keep the event armed so
            //     the wait() returns immediately.
            graph.wake_event.reset();
            graph.drainQueue(allocator);
            if (graph.should_stop.load(.acquire)) break;

            graph.wake_event.waitUncancelable(graph.io);
        }
    }

    fn drainQueue(graph: *Graph, allocator: std.mem.Allocator) void {
        graph.process_mu.lockUncancelable(graph.io);
        defer graph.process_mu.unlock(graph.io);
        while (graph.queue.pop()) |op| {
            graph.processOp(allocator, op);
            if (graph.copy_pending.load(.acquire)) break;
        }
    }

    /// Checks if a node has any relationships and if not, removes it from the graph
    inline fn cleanupIsolatedNode(graph: *Graph, node: *Node) void {
        if (node.parent != null or node.first_child != null) return;
        graph.id_to_node.lock.lockUncancelable(graph.io);
        defer graph.id_to_node.lock.unlock(graph.io);
        _ = graph.id_to_node.map.remove(node.id);
        graph.nodes.release(node);
    }

    /// Process a single operation to the graph.
    inline fn processOp(graph: *Graph, allocator: std.mem.Allocator, op: Op) void {
        switch (op) {
            .add_child => |data| {
                const parent = graph.getNode(data.parent_id) orelse return;
                const new_child = graph.getNode(data.child_id) orelse return;

                if (!parent.hasChild(new_child.id)) {
                    // Remove from old parent first, same as set_parent
                    if (new_child.parent) |old_parent| {
                        if (old_parent == parent) return;
                        old_parent.removeChild(new_child.id);
                        graph.cleanupIsolatedNode(old_parent);
                    }
                    parent.addChild(new_child);
                }
            },

            .remove_child => |data| {
                const parent = graph.getNode(data.parent_id) orelse return;
                const child = graph.getNode(data.child_id) orelse return;
                parent.removeChild(data.child_id);
                graph.cleanupIsolatedNode(parent);
                graph.cleanupIsolatedNode(child);
            },

            .set_parent => |data| {
                const child = graph.getNode(data.child_id) orelse return;
                const new_parent = graph.getNode(data.parent_id) orelse return;

                if (child.parent) |old_parent| {
                    if (old_parent == new_parent) return;
                    old_parent.removeChild(child.id);
                    graph.cleanupIsolatedNode(old_parent);
                }
                new_parent.addChild(child);
            },

            .remove_parent => |data| {
                const child = graph.getNode(data.child_id) orelse return;
                if (child.parent) |parent| {
                    parent.removeChild(child.id);
                    graph.cleanupIsolatedNode(parent);
                    graph.cleanupIsolatedNode(child);
                }
            },

            .cascade_delete => |data| {
                const node = graph.getNode(data.id) orelse return;
                graph.doCascadeDelete(node);
            },

            .sync => |data| {
                data.done.store(true, .release);
            },

            .get_children => |query| {
                const node = graph.getNode(query.node_id) orelse {
                    // Instead of just storing done, we return an empty result
                    query.done.store(true, .release);
                    return;
                };

                var current = node.first_child;
                while (current) |child| : (current = child.next) {
                    query.result.append(allocator, child.id) catch |err| {
                        query.err.* = err;
                        break;
                    };
                }
                query.done.store(true, .release);
            },

            .get_parent => |query| {
                const node = graph.getNode(query.node_id) orelse {
                    query.result.* = null;
                    query.done.store(true, .release);
                    return;
                };
                query.result.* = if (node.parent) |parent| parent.id else null;
                query.done.store(true, .release);
            },
        }
    }

    /// preallocateNodes2 ensures graph.id_to_node contains an entry for the two given IDs.
    fn preallocateNodes2(graph: *Graph, allocator: std.mem.Allocator, id1: u64, id2: u64) !void {
        graph.id_to_node.lock.lockUncancelable(graph.io);
        defer graph.id_to_node.lock.unlock(graph.io);

        // Preallocate first node
        const result1 = try graph.id_to_node.map.getOrPut(allocator, id1);
        if (!result1.found_existing) {
            const node = try graph.nodes.acquire(allocator);
            node.* = .{ .id = id1 };
            result1.value_ptr.* = node;
        }

        // Preallocate second node
        const result2 = try graph.id_to_node.map.getOrPut(allocator, id2);
        if (!result2.found_existing) {
            const node = try graph.nodes.acquire(allocator);
            node.* = .{ .id = id2 };
            result2.value_ptr.* = node;
        }
    }

    pub fn addChild(graph: *Graph, allocator: std.mem.Allocator, parent_id: u64, child_id: u64) Error!void {
        try graph.preallocateNodes2(allocator, parent_id, child_id);

        try graph.queue.push(allocator, .{ .add_child = .{
            .parent_id = parent_id,
            .child_id = child_id,
        } });
        graph.wake_event.set(graph.io);
    }

    pub fn removeChild(graph: *Graph, allocator: std.mem.Allocator, parent_id: u64, child_id: u64) Error!void {
        try graph.preallocateNodes2(allocator, parent_id, child_id);
        try graph.queue.push(allocator, .{ .remove_child = .{
            .parent_id = parent_id,
            .child_id = child_id,
        } });
        graph.wake_event.set(graph.io);
    }

    pub fn setParent(graph: *Graph, allocator: std.mem.Allocator, child_id: u64, parent_id: u64) Error!void {
        try graph.preallocateNodes2(allocator, child_id, parent_id);

        try graph.queue.push(allocator, .{ .set_parent = .{
            .child_id = child_id,
            .parent_id = parent_id,
        } });
        graph.wake_event.set(graph.io);
    }

    /// Waits for all prior operations enqueued by this thread to be processed by the background
    /// thread.
    pub fn sync(graph: *Graph, allocator: std.mem.Allocator) Error!void {
        var done = std.atomic.Value(bool).init(false);
        try graph.queue.push(allocator, .{ .sync = .{ .done = &done } });
        graph.wake_event.set(graph.io);

        // Graph operations are sub-microsecond, so a futex round-trip would dominate. Instead, we
        // spinLoopHint to keep us friendly to SMT siblings and let the CPU clock down.
        while (!done.load(.acquire)) std.atomic.spinLoopHint();
    }

    pub fn removeParent(graph: *Graph, allocator: std.mem.Allocator, child_id: u64) Error!void {
        try graph.queue.push(allocator, .{ .remove_parent = .{
            .child_id = child_id,
        } });
        graph.wake_event.set(graph.io);
    }

    pub const Results = struct {
        // The actual result items. Read-only.
        items: []const u64,

        // Internal / private fields.
        internal_list: *std.ArrayList(u64),
        internal_graph: *Graph,

        // Deinit returns the allocation back to the Graph memory pool for reuse in the future.
        pub fn deinit(r: Results) void {
            r.internal_graph.releaseResultList(r.internal_list);
        }
    };

    pub fn getChildren(graph: *Graph, allocator: std.mem.Allocator, id: u64) Error!Results {
        const results = try graph.acquireResultList(allocator, graph.preallocate_result_list_size);
        errdefer graph.releaseResultList(results);

        var done = std.atomic.Value(bool).init(false);
        var err: ?Error = null;

        try graph.queue.push(allocator, .{ .get_children = .{
            .node_id = id,
            .result = results,
            .err = &err,
            .done = &done,
        } });
        graph.wake_event.set(graph.io);

        // See sync() for the rationale on spinning rather than blocking.
        while (!done.load(.acquire)) std.atomic.spinLoopHint();

        if (err) |e| return e;
        return Results{
            .items = results.items,
            .internal_list = results,
            .internal_graph = graph,
        };
    }

    fn acquireResultList(graph: *Graph, allocator: std.mem.Allocator, min_capacity: usize) !*std.ArrayList(u64) {
        // Try to get an existing list first
        graph.result_lists.lock.lockUncancelable(graph.io);
        const list = graph.result_lists.available.pop();
        graph.result_lists.lock.unlock(graph.io);

        if (list) |l| {
            errdefer {
                graph.result_lists.lock.lockUncancelable(graph.io);
                defer graph.result_lists.lock.unlock(graph.io);
                graph.result_lists.available.appendAssumeCapacity(l);
            }
            try l.ensureTotalCapacity(allocator, min_capacity);
            return l;
        }

        // Create new result list if needed
        var new_list = try allocator.create(std.ArrayList(u64));
        errdefer allocator.destroy(new_list);
        new_list.* = .empty;
        try new_list.ensureTotalCapacity(allocator, graph.preallocate_result_list_size);
        return new_list;
    }

    fn releaseResultList(graph: *Graph, list: *std.ArrayList(u64)) void {
        list.clearRetainingCapacity();

        graph.result_lists.lock.lockUncancelable(graph.io);
        defer graph.result_lists.lock.unlock(graph.io);
        graph.result_lists.available.appendAssumeCapacity(list);
    }

    /// Copies src into dst, using the current state of the graph at the time the operation
    /// is processed. Queued operations are not copied.
    /// May be called repeatedly to keep `dst` in sync with `src`.
    ///
    /// The copy is optimized for speed rather than memory efficiency, operating under the
    /// assumption that src may be copied to dst in the future to update it frequently.
    /// For example, additional capacity in arrays is also mirrored rather than resizing to
    /// fit only what is needed, under the assumption that capacity may be needed in the next
    /// copyFrom operation.
    pub fn copyFrom(dst: *Graph, src: *Graph, allocator: std.mem.Allocator) Error!void {
        // Signal both processing threads to release their locks promptly.
        src.copy_pending.store(true, .release);
        dst.copy_pending.store(true, .release);

        // Lock both processing threads so neither graph is mutated during the copy.
        // Always lock in pointer order to prevent deadlocks.
        const first, const second = if (@intFromPtr(src) < @intFromPtr(dst))
            .{ &src.process_mu, &dst.process_mu }
        else
            .{ &dst.process_mu, &src.process_mu };

        first.lockUncancelable(src.io);
        second.lockUncancelable(src.io);
        defer second.unlock(src.io);
        defer first.unlock(src.io);

        // Clear the signals now that we hold both locks.
        src.copy_pending.store(false, .release);
        dst.copy_pending.store(false, .release);

        // Drain any remaining queued operations on src so the snapshot is fully
        // consistent with synchronous mutations (e.g. Objects.delete) that were
        // performed before the caller requested the copy.
        while (src.queue.pop()) |op| {
            src.processOp(allocator, op);
        }

        // Copy src into dst
        src.copyInto(dst, allocator) catch |err| {
            return err;
        };
    }

    /// Snapshots the current graph state into dst. Called by the processing thread
    /// so no concurrent mutations are possible.
    fn copyInto(src: *Graph, dst: *Graph, allocator: std.mem.Allocator) !void {
        // copy nodes
        try dst.nodes.copyFrom(&src.nodes, allocator);

        // copy id_to_node
        try dst.id_to_node.map.ensureTotalCapacity(allocator, src.id_to_node.map.capacity());
        dst.id_to_node.map.clearRetainingCapacity();
        var it = src.id_to_node.map.iterator();
        while (it.next()) |entry| {
            const dst_node = try dst.nodes.acquire(allocator);
            dst_node.* = .{ .id = entry.value_ptr.*.id };
            dst.id_to_node.map.putAssumeCapacity(entry.key_ptr.*, dst_node);
        }
        // Rebuild parent/child pointers using dst's own nodes.
        // A node's parent/child/next may reference an ID that was removed from the map
        // (e.g. by cleanupIsolatedNode) but not yet unlinked from the tree — treat as null.
        it = src.id_to_node.map.iterator();
        while (it.next()) |entry| {
            const src_node = entry.value_ptr.*;
            const dst_node = dst.id_to_node.map.get(entry.key_ptr.*) orelse continue;
            dst_node.parent = if (src_node.parent) |p| dst.id_to_node.map.get(p.id) else null;
            dst_node.first_child = if (src_node.first_child) |c| dst.id_to_node.map.get(c.id) else null;
            dst_node.next = if (src_node.next) |n| dst.id_to_node.map.get(n.id) else null;
        }

        // copy result_lists
        try dst.result_lists.available.ensureTotalCapacity(allocator, src.result_lists.available.capacity);
        while (dst.result_lists.available.items.len < src.result_lists.available.items.len) {
            var list = try allocator.create(std.ArrayList(u64));
            list.* = .empty;
            try list.ensureTotalCapacity(allocator, dst.preallocate_result_list_size);
            dst.result_lists.available.appendAssumeCapacity(list);
        }

        // copy preallocate_result_list_size
        dst.preallocate_result_list_size = src.preallocate_result_list_size;
    }

    pub fn getParent(graph: *Graph, allocator: std.mem.Allocator, id: u64) Error!?u64 {
        var result: ?u64 = null;
        var done = std.atomic.Value(bool).init(false);

        try graph.queue.push(allocator, .{ .get_parent = .{
            .node_id = id,
            .result = &result,
            .done = &done,
        } });
        graph.wake_event.set(graph.io);

        // See sync() for the rationale on spinning rather than blocking.
        while (!done.load(.acquire)) std.atomic.spinLoopHint();

        return result;
    }
};

test "basic child addition and querying" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{ .queue_size = 32, .nodes_size = 32, .num_result_lists = 8, .result_list_size = 8 });
    defer graph.deinit(allocator);

    try graph.addChild(allocator, 1, 2);

    const results = try graph.getChildren(allocator, 1);
    defer results.deinit();
    try testing.expectEqual(results.items.len, 1);
    try testing.expectEqual(results.items[0], 2);
}

test "basic parent querying" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{ .queue_size = 32, .nodes_size = 32, .num_result_lists = 8, .result_list_size = 8 });
    defer graph.deinit(allocator);

    try graph.addChild(allocator, 1, 2);
    const parent = try graph.getParent(allocator, 2);
    try testing.expectEqual(parent.?, 1);
}

test "child removal" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{ .queue_size = 32, .nodes_size = 32, .num_result_lists = 8, .result_list_size = 8 });
    defer graph.deinit(allocator);

    try graph.addChild(allocator, 1, 2);
    try graph.removeChild(allocator, 1, 2);

    const results = try graph.getChildren(allocator, 1);
    defer results.deinit();
    try testing.expectEqual(results.items.len, 0);
}

test "parent setting" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{ .queue_size = 32, .nodes_size = 32, .num_result_lists = 8, .result_list_size = 8 });
    defer graph.deinit(allocator);

    try graph.addChild(allocator, 1, 2);
    try graph.setParent(allocator, 2, 3); // Move child 2 from parent 1 to parent 3

    const parent = try graph.getParent(allocator, 2);
    try testing.expectEqual(parent.?, 3);
}

test "parent removal" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{ .queue_size = 32, .nodes_size = 32, .num_result_lists = 8, .result_list_size = 8 });
    defer graph.deinit(allocator);

    try graph.addChild(allocator, 1, 2);
    try graph.removeParent(allocator, 2);

    const parent = try graph.getParent(allocator, 2);
    try testing.expectEqual(parent, null);
}

test "graph - idempotent child addition" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{
        .queue_size = 256,
        .nodes_size = 64,
        .num_result_lists = 32,
        .result_list_size = 32,
    });
    defer graph.deinit(allocator);

    try graph.addChild(allocator, 1, 2);
    try graph.addChild(allocator, 1, 2); // Add same child twice

    const results = try graph.getChildren(allocator, 1);
    defer results.deinit();
    try testing.expectEqual(results.items.len, 1);
}

test "graph - deep hierarchy and chain operations" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{
        .queue_size = 256,
        .nodes_size = 64,
        .num_result_lists = 32,
        .result_list_size = 32,
    });
    defer graph.deinit(allocator);

    try graph.addChild(allocator, 1, 2);
    try graph.addChild(allocator, 2, 3);
    try graph.addChild(allocator, 3, 4);
    try graph.addChild(allocator, 4, 5);

    // Verify chain
    try testing.expectEqual((try graph.getParent(allocator, 5)).?, 4);
    try testing.expectEqual((try graph.getParent(allocator, 4)).?, 3);
    try testing.expectEqual((try graph.getParent(allocator, 3)).?, 2);
    try testing.expectEqual((try graph.getParent(allocator, 2)).?, 1);

    // Test reparenting middle of chain
    try graph.setParent(allocator, 3, 1); // Move 3 to be under 1 directly

    // Verify chain was broken correctly
    try testing.expectEqual((try graph.getParent(allocator, 3)).?, 1);
    const results = try graph.getChildren(allocator, 2);
    defer results.deinit();
    try testing.expectEqual(results.items.len, 0);
}

test "graph - cleanup of isolated nodes" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{
        .queue_size = 256,
        .nodes_size = 64,
        .num_result_lists = 32,
        .result_list_size = 32,
    });
    defer graph.deinit(allocator);

    // First verify the initial state
    try graph.addChild(allocator, 1, 2);
    try graph.addChild(allocator, 2, 3);

    // Verify initial setup
    {
        const results1 = try graph.getChildren(allocator, 1);
        defer results1.deinit();
        try testing.expectEqual(results1.items.len, 1);
        try testing.expectEqual(results1.items[0], 2);

        const results2 = try graph.getChildren(allocator, 2);
        defer results2.deinit();
        try testing.expectEqual(results2.items.len, 1);
        try testing.expectEqual(results2.items[0], 3);
    }

    // Remove the parent-child relationship
    try graph.removeChild(allocator, 1, 2);

    // Node 2 should still exist and have node 3 as its child
    const node2_children = try graph.getChildren(allocator, 2);
    defer node2_children.deinit();
    try testing.expectEqual(node2_children.items.len, 1);
    try testing.expectEqual(node2_children.items[0], 3);

    // But node 2 should no longer have a parent
    try testing.expectEqual(try graph.getParent(allocator, 2), null);

    // Node 3 should still have node 2 as its parent
    try testing.expectEqual((try graph.getParent(allocator, 3)).?, 2);
}

test "graph - edge cases with non-existent nodes" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{
        .queue_size = 256,
        .nodes_size = 64,
        .num_result_lists = 32,
        .result_list_size = 32,
    });
    defer graph.deinit(allocator);

    // Test querying non-existent nodes
    const results = try graph.getChildren(allocator, 99999);
    defer results.deinit();
    try testing.expectEqual(results.items.len, 0);
    try testing.expectEqual(try graph.getParent(allocator, 99999), null);

    // These should not crash
    try graph.removeChild(allocator, 99999, 1);
    try graph.removeChild(allocator, 1, 99999);
    try graph.removeParent(allocator, 99999);

    // Add child to non-existent parent (should create both nodes)
    try graph.addChild(allocator, 100, 101);
    const results2 = (try graph.getChildren(allocator, 100));
    defer results2.deinit();
    try testing.expectEqual(results2.items.len, 1);
    try testing.expectEqual(results2.items[0], 101);
}

test "graph - multiple operations consistency" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;
    var graph: Graph = undefined;
    try graph.init(allocator, io, .{
        .queue_size = 256,
        .nodes_size = 64,
        .num_result_lists = 32,
        .result_list_size = 32,
    });
    defer graph.deinit(allocator);

    try graph.addChild(allocator, 1, 2);

    try graph.addChild(allocator, 1, 3);
    try graph.addChild(allocator, 2, 4);
    try graph.setParent(allocator, 3, 2); // Move 3 under 2
    try graph.removeParent(allocator, 4); // Remove 4's parent

    const results = try graph.getChildren(allocator, 2);
    defer results.deinit();
    try testing.expectEqual(results.items.len, 1);
    try testing.expectEqual(results.items[0], 3);

    try testing.expectEqual(try graph.getParent(allocator, 4), null);
}

test "graph - copyFrom" {
    const allocator = testing.allocator;
    const io = std.Options.debug_io;

    var src: Graph = undefined;
    try src.init(allocator, io, .{ .queue_size = 32, .nodes_size = 32, .num_result_lists = 8, .result_list_size = 8 });
    defer src.deinit(allocator);

    // Build a small hierarchy: 1 -> 2, 1 -> 3, 2 -> 4
    try src.addChild(allocator, 1, 2);
    try src.addChild(allocator, 1, 3);
    try src.addChild(allocator, 2, 4);

    var dst: Graph = undefined;
    try dst.init(allocator, io, .{ .queue_size = 32, .nodes_size = 32, .num_result_lists = 8, .result_list_size = 8 });
    defer dst.deinit(allocator);

    // copyFrom enqueues onto src's queue, so all prior ops are processed first
    try dst.copyFrom(&src, allocator);

    // Verify the copied graph has the same structure
    {
        const children_1 = try dst.getChildren(allocator, 1);
        defer children_1.deinit();
        try testing.expectEqual(children_1.items.len, 2);
    }
    {
        const children_2 = try dst.getChildren(allocator, 2);
        defer children_2.deinit();
        try testing.expectEqual(children_2.items.len, 1);
        try testing.expectEqual(children_2.items[0], 4);
    }
    try testing.expectEqual((try dst.getParent(allocator, 2)).?, 1);
    try testing.expectEqual((try dst.getParent(allocator, 4)).?, 2);
}
