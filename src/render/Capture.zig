//! Frame capture to an image file, for art review and screenshot checks (`-Dcapture-frame=N`).
const std = @import("std");

/// A 24-bit BMP from packed RGBA8 pixels (rows top to bottom).
pub fn encodeBmp(allocator: std.mem.Allocator, width: u32, height: u32, rgba: []const u32) ![]u8 {
    const row = (width * 3 + 3) / 4 * 4;
    const size = 54 + row * height;
    const out = try allocator.alloc(u8, size);
    @memset(out, 0);
    out[0] = 'B';
    out[1] = 'M';
    std.mem.writeInt(u32, out[2..6], size, .little);
    std.mem.writeInt(u32, out[10..14], 54, .little);
    std.mem.writeInt(u32, out[14..18], 40, .little);
    std.mem.writeInt(i32, out[18..22], @intCast(width), .little);
    std.mem.writeInt(i32, out[22..26], @intCast(height), .little);
    std.mem.writeInt(u16, out[26..28], 1, .little);
    std.mem.writeInt(u16, out[28..30], 24, .little);
    std.mem.writeInt(u32, out[34..38], row * height, .little);
    for (0..height) |y| {
        // BMP rows run bottom to top, pixels as B, G, R.
        const dst = out[54 + (height - 1 - y) * row ..];
        for (0..width) |x| {
            const p = rgba[y * width + x];
            dst[x * 3] = @truncate(p >> 16);
            dst[x * 3 + 1] = @truncate(p >> 8);
            dst[x * 3 + 2] = @truncate(p);
        }
    }
    return out;
}

test "bmp rows are bottom-up BGR with 4-byte padding" {
    const pixels = [_]u32{ 0xff0000ff, 0xff00ff00, 0xffff0000, 0xffffffff, 0xff000000, 0xff808080 };
    const bmp = try encodeBmp(std.testing.allocator, 3, 2, &pixels);
    defer std.testing.allocator.free(bmp);
    try std.testing.expectEqual(@as(usize, 54 + 12 * 2), bmp.len);
    // Bottom row first: white, black, grey.
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 0, 0, 0, 128, 128, 128 }, bmp[54..63]);
    // Top row: red, green, blue as B,G,R.
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 0, 255, 0, 255, 0, 0 }, bmp[66..75]);
}
