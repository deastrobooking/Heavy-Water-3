//! Proportional sap allocation over a rooted vascular graph. Each request traverses all its
//! ancestors; its weakest edge limits its grant. This conservative policy never oversubscribes
//! an edge and requires no per-step allocation or iteration-order-dependent reservations.
const std = @import("std");
const Arbor = @import("../procedural/Arbor.zig");
pub const Request = struct { node: u16, watts: f32, granted: f32 = 0 };
pub const Result = struct { demand: f32 = 0, supplied: f32 = 0, satisfaction: f32 = 1 };

pub fn allocate(tree: *const Arbor.Tree, requests: []Request) Result {
    var demand: [Arbor.max_nodes]f32 = @splat(0);
    for (requests) |*request| {
        request.granted = 0;
        if (request.node >= tree.count or !std.math.isFinite(request.watts) or request.watts <= 0) continue;
        var node = request.node;
        while (node != Arbor.none) : (node = tree.nodes[node].parent) demand[node] += request.watts;
    }
    var result: Result = .{ .demand = demand[0] };
    for (requests) |*request| {
        if (request.node >= tree.count or !std.math.isFinite(request.watts) or request.watts <= 0) continue;
        var fraction: f32 = 1;
        var node = request.node;
        while (node != Arbor.none) : (node = tree.nodes[node].parent) {
            if (demand[node] > 0) fraction = @min(fraction, tree.capacity(node) / demand[node]);
        }
        request.granted = request.watts * fraction;
        result.supplied += request.granted;
    }
    result.satisfaction = if (result.demand > 0) @min(1, result.supplied / result.demand) else 1;
    return result;
}

test "taps share their tree, branch bottlenecks are respected, and idle taps draw nothing" {
    var tree = try Arbor.grow(123, .{ .vascular_capacity = 100 });
    var requests = [_]Request{ .{ .node = 1, .watts = 100 }, .{ .node = 2, .watts = 100 }, .{ .node = 1, .watts = 0 } };
    const overloaded = allocate(&tree, &requests);
    try std.testing.expectEqual(@as(f32, 50), requests[0].granted);
    try std.testing.expectEqual(@as(f32, 50), requests[1].granted);
    try std.testing.expectEqual(@as(f32, 0), requests[2].granted);
    try std.testing.expectEqual(@as(f32, 0.5), overloaded.satisfaction);
    requests[1].watts = 0;
    _ = allocate(&tree, &requests);
    try std.testing.expectEqual(@as(f32, 100), requests[0].granted);
    requests[0].node = 22; // A side branch has less capacity than the trunk.
    _ = allocate(&tree, &requests);
    try std.testing.expect(requests[0].granted <= tree.capacity(22));
    try std.testing.expect(requests[0].granted < 100);
    // Order changes cannot steal flow, and a separate tree has its own budget.
    var a = [_]Request{ .{ .node = 22, .watts = 80 }, .{ .node = 1, .watts = 40 } };
    var b = [_]Request{ a[1], a[0] };
    _ = allocate(&tree, &a);
    _ = allocate(&tree, &b);
    try std.testing.expectEqual(a[0].granted, b[1].granted);
    try std.testing.expectEqual(a[1].granted, b[0].granted);
    tree.genome.vascular_capacity = 200;
    var independent = [_]Request{.{ .node = 1, .watts = 100 }};
    try std.testing.expectEqual(@as(f32, 100), allocate(&tree, &independent).supplied);
}
