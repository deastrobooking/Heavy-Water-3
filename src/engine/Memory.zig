//! Process memory for benchmark reports: the physical footprint macOS attributes to the
//! process (what Activity Monitor shows), including GPU allocations in unified memory.
const std = @import("std");
const builtin = @import("builtin");

/// Bytes, or null where unsupported.
pub fn footprint() ?u64 {
    if (builtin.os.tag != .macos) return null;
    const c = std.c;
    var info: c.task_vm_info_data_t = undefined;
    var count: c.mach_msg_type_number_t = c.TASK.VM.INFO_COUNT;
    if (c.task_info(c.mach_task_self(), c.TASK.VM.INFO, @ptrCast(&info), &count) != 0) return null;
    return info.phys_footprint;
}

test "the process footprint is reported on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const before = footprint().?;
    try std.testing.expect(before > 1 << 20);
    const block = try std.heap.page_allocator.alloc(u8, 64 << 20);
    defer std.heap.page_allocator.free(block);
    @memset(block, 1);
    try std.testing.expect(footprint().? > before + (32 << 20));
}
