// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! An MP3 decoder: MPEG-1, MPEG-2 LSF and MPEG-2.5 Layer III, with a reader
//! for the ID3 metadata that comes wrapped around it.
//!
//! The core is `Decoder`, which is fed bytes and hands back one frame of PCM
//! at a time; `decodeAll` wraps it for the common case of a whole file in
//! memory.  Samples come out as `f32` nominally in -1...1, which is what the
//! arithmetic produces; `toInt16` converts and clips.
//!
//! Metadata is separate, and allocates, since decoding is not:
//!
//!     if (try mp3.id3.parse(allocator, data)) |*tag| {
//!         defer tag.deinit();
//!         std.debug.print("{?s}\n", .{tag.title()});
//!     }
//!
//!     var decoder = mp3.Decoder.init();
//!     var buffer: mp3.FrameBuffer = undefined;
//!     var rest = data;
//!     while (rest.len > 0) switch (decoder.next(rest, &buffer, .{})) {
//!         .need_more => break,
//!         .skipped => |n| rest = rest[n..],
//!         .frame => |frame| {
//!             play(buffer[0 .. frame.samples * frame.channels]);
//!             rest = rest[frame.consumed..];
//!         },
//!     };

const std = @import("std");

const decoder = @import("decoder.zig");

pub const Header = @import("header.zig");
pub const id3 = @import("id3.zig");
pub const tags = @import("tags.zig");
pub const vbr = @import("vbr.zig");
pub const wav = @import("wav.zig");

pub const Decoder = decoder.Decoder;
pub const Step = decoder.Step;
pub const Frame = decoder.Frame;
pub const FrameBuffer = decoder.FrameBuffer;
pub const Audio = decoder.Audio;
pub const decodeAll = decoder.decodeAll;
pub const VbrInfo = vbr.Info;
pub const encode = @import("encode12.zig");
pub const Encoder = encode.Encoder;
pub const encode3 = @import("encode3.zig");
pub const Encoder3 = encode3.Encoder;
pub const toInt16 = decoder.toInt16;
pub const max_channels = decoder.max_channels;
pub const max_samples_per_frame = decoder.max_samples_per_frame;
pub const max_frame_samples = decoder.max_frame_samples;

test {
    _ = @import("bitstream.zig");
    _ = @import("header.zig");
    _ = @import("huffman.zig");
    _ = @import("side_info.zig");
    _ = @import("imdct.zig");
    _ = @import("synthesis.zig");
    _ = @import("reference.zig");
    _ = @import("analysis.zig");
    _ = @import("bitwriter.zig");
    _ = @import("fft.zig");
    _ = @import("psymodel2.zig");
    _ = @import("encode12.zig");
    _ = @import("mdct.zig");
    _ = @import("huffman_encode.zig");
    _ = @import("encode3.zig");
    _ = @import("layer12.zig");
    _ = @import("layer3.zig");
    _ = @import("id3.zig");
    _ = @import("tags.zig");
    _ = @import("decoder.zig");
    _ = @import("vbr.zig");
    _ = @import("wav.zig");
    _ = @import("decode_test.zig");
    _ = @import("fuzz_test.zig");
}
