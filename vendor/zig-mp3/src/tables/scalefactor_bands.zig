// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! GENERATED FILE -- do not edit by hand; see tools/gen_tables.py.
//!
//! Scalefactor band widths, ISO/IEC 11172-3 Table B.8 and the
//! corresponding table of ISO/IEC 13818-3.
//!
//! One row per sampling frequency, ordered MPEG-1, MPEG-2, MPEG-2.5, and
//! within each version by the header's sampling-frequency index; use
//! `index` to find the row for a frame.
//!
//! Bands are given as widths rather than boundaries so that long, short
//! and mixed blocks can all be walked the same way: a granule's spectrum
//! is the concatenation of its bands, and band `i` of the list shares its
//! index with scalefactor `i`.  In the short lists each scalefactor band
//! appears three times in a row, once per window, which is both the order
//! the scalefactors arrive in and the order the spectral lines are stored
//! in before reordering.

pub const Bands = struct {
    /// Widths of the 22 long scalefactor bands.  Scalefactors are
    /// transmitted for bands 0...20; band 21 always uses a scalefactor
    /// of zero.
    long_widths: [22]u8,
    /// Widths of the 13 short scalefactor bands, each repeated once per
    /// window.  Scalefactors are transmitted for bands 0...11.
    short_widths: [39]u8,
    /// Band widths for a mixed block: `mixed_long` long bands followed by
    /// `mixed_short` short entries.  This is not simply a splice of the
    /// two lists above -- at 8 kHz the long region of a mixed block is 48
    /// lines rather than the 36 the other rates use.
    mixed_widths: [39]u8,
    /// Leading entries of `mixed_widths` that are long bands.
    mixed_long: u8,
    /// Trailing entries of `mixed_widths` that are short bands.
    mixed_short: u8,
};

/// Row index for a frame: `version` is 0 for MPEG-1, 1 for MPEG-2 and 2
/// for MPEG-2.5; `sample_rate_index` is the header field, 0...2.
pub fn index(version: u2, sample_rate_index: u2) usize {
    return @as(usize, version) * 3 + sample_rate_index;
}

pub const bands = [9]Bands{
    // 44100 Hz
    .{
        .long_widths = .{
            4,  4,  4,  4,  4,  4,  6,  6,  8,  8,  10,
            12, 16, 20, 24, 28, 34, 42, 50, 54, 76, 158,
        },
        .short_widths = .{
            4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,
            6,  6,  6,  8,  8,  8,  10, 10, 10, 12, 12, 12,
            14, 14, 14, 18, 18, 18, 22, 22, 22, 30, 30, 30,
            56, 56, 56,
        },
        .mixed_widths = .{
            4,  4,  4,  4,  4,  4,  6,  6,  4,  4,  4,  6,
            6,  6,  8,  8,  8,  10, 10, 10, 12, 12, 12, 14,
            14, 14, 18, 18, 18, 22, 22, 22, 30, 30, 30, 56,
            56, 56, 0,
        },
        .mixed_long = 8,
        .mixed_short = 30,
    },
    // 48000 Hz
    .{
        .long_widths = .{
            4,  4,  4,  4,  4,  4,  6,  6,  6,  8,  10,
            12, 16, 18, 22, 28, 34, 40, 46, 54, 54, 192,
        },
        .short_widths = .{
            4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,
            6,  6,  6,  6,  6,  6,  10, 10, 10, 12, 12, 12,
            14, 14, 14, 16, 16, 16, 20, 20, 20, 26, 26, 26,
            66, 66, 66,
        },
        .mixed_widths = .{
            4,  4,  4,  4,  4,  4,  6,  6,  4,  4,  4,  6,
            6,  6,  6,  6,  6,  10, 10, 10, 12, 12, 12, 14,
            14, 14, 16, 16, 16, 20, 20, 20, 26, 26, 26, 66,
            66, 66, 0,
        },
        .mixed_long = 8,
        .mixed_short = 30,
    },
    // 32000 Hz
    .{
        .long_widths = .{
            4,  4,  4,  4,  4,  4,  6,  6,  8,  10,  12,
            16, 20, 24, 30, 38, 46, 56, 68, 84, 102, 26,
        },
        .short_widths = .{
            4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,
            6,  6,  6,  8,  8,  8,  12, 12, 12, 16, 16, 16,
            20, 20, 20, 26, 26, 26, 34, 34, 34, 42, 42, 42,
            12, 12, 12,
        },
        .mixed_widths = .{
            4,  4,  4,  4,  4,  4,  6,  6,  4,  4,  4,  6,
            6,  6,  8,  8,  8,  12, 12, 12, 16, 16, 16, 20,
            20, 20, 26, 26, 26, 34, 34, 34, 42, 42, 42, 12,
            12, 12, 0,
        },
        .mixed_long = 8,
        .mixed_short = 30,
    },
    // 22050 Hz
    .{
        .long_widths = .{
            6,  6,  6,  6,  6,  6,  8,  10, 12, 14, 16,
            20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54,
        },
        .short_widths = .{
            4,  4,  4,  4,  4,  4,  4,  4,  4,  6,  6,  6,
            6,  6,  6,  8,  8,  8,  10, 10, 10, 14, 14, 14,
            18, 18, 18, 26, 26, 26, 32, 32, 32, 42, 42, 42,
            18, 18, 18,
        },
        .mixed_widths = .{
            6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,  6,
            8,  8,  8,  10, 10, 10, 14, 14, 14, 18, 18, 18,
            26, 26, 26, 32, 32, 32, 42, 42, 42, 18, 18, 18,
            0,  0,  0,
        },
        .mixed_long = 6,
        .mixed_short = 30,
    },
    // 24000 Hz
    .{
        .long_widths = .{
            6,  6,  6,  6,  6,  6,  8,  10, 12, 14, 16,
            18, 22, 26, 32, 38, 46, 54, 62, 70, 76, 36,
        },
        .short_widths = .{
            4,  4,  4,  4,  4,  4,  4,  4,  4,  6,  6,  6,
            8,  8,  8,  10, 10, 10, 12, 12, 12, 14, 14, 14,
            18, 18, 18, 24, 24, 24, 32, 32, 32, 44, 44, 44,
            12, 12, 12,
        },
        .mixed_widths = .{
            6,  6,  6,  6,  6,  6,  6,  6,  6,  8,  8,  8,
            10, 10, 10, 12, 12, 12, 14, 14, 14, 18, 18, 18,
            24, 24, 24, 32, 32, 32, 44, 44, 44, 12, 12, 12,
            0,  0,  0,
        },
        .mixed_long = 6,
        .mixed_short = 30,
    },
    // 16000 Hz
    .{
        .long_widths = .{
            6,  6,  6,  6,  6,  6,  8,  10, 12, 14, 16,
            20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54,
        },
        .short_widths = .{
            4,  4,  4,  4,  4,  4,  4,  4,  4,  6,  6,  6,
            8,  8,  8,  10, 10, 10, 12, 12, 12, 14, 14, 14,
            18, 18, 18, 24, 24, 24, 30, 30, 30, 40, 40, 40,
            18, 18, 18,
        },
        .mixed_widths = .{
            6,  6,  6,  6,  6,  6,  6,  6,  6,  8,  8,  8,
            10, 10, 10, 12, 12, 12, 14, 14, 14, 18, 18, 18,
            24, 24, 24, 30, 30, 30, 40, 40, 40, 18, 18, 18,
            0,  0,  0,
        },
        .mixed_long = 6,
        .mixed_short = 30,
    },
    // 11025 Hz
    .{
        .long_widths = .{
            6,  6,  6,  6,  6,  6,  8,  10, 12, 14, 16,
            20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54,
        },
        .short_widths = .{
            4,  4,  4,  4,  4,  4,  4,  4,  4,  6,  6,  6,
            8,  8,  8,  10, 10, 10, 12, 12, 12, 14, 14, 14,
            18, 18, 18, 24, 24, 24, 30, 30, 30, 40, 40, 40,
            18, 18, 18,
        },
        .mixed_widths = .{
            6,  6,  6,  6,  6,  6,  6,  6,  6,  8,  8,  8,
            10, 10, 10, 12, 12, 12, 14, 14, 14, 18, 18, 18,
            24, 24, 24, 30, 30, 30, 40, 40, 40, 18, 18, 18,
            0,  0,  0,
        },
        .mixed_long = 6,
        .mixed_short = 30,
    },
    // 12000 Hz
    .{
        .long_widths = .{
            6,  6,  6,  6,  6,  6,  8,  10, 12, 14, 16,
            20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54,
        },
        .short_widths = .{
            4,  4,  4,  4,  4,  4,  4,  4,  4,  6,  6,  6,
            8,  8,  8,  10, 10, 10, 12, 12, 12, 14, 14, 14,
            18, 18, 18, 24, 24, 24, 30, 30, 30, 40, 40, 40,
            18, 18, 18,
        },
        .mixed_widths = .{
            6,  6,  6,  6,  6,  6,  6,  6,  6,  8,  8,  8,
            10, 10, 10, 12, 12, 12, 14, 14, 14, 18, 18, 18,
            24, 24, 24, 30, 30, 30, 40, 40, 40, 18, 18, 18,
            0,  0,  0,
        },
        .mixed_long = 6,
        .mixed_short = 30,
    },
    // 8000 Hz
    .{
        .long_widths = .{
            12, 12, 12, 12, 12, 12, 16, 20, 24, 28, 32,
            40, 48, 56, 64, 76, 90, 2,  2,  2,  2,  2,
        },
        .short_widths = .{
            8,  8,  8,  8,  8,  8,  8,  8,  8,  12, 12, 12,
            16, 16, 16, 20, 20, 20, 24, 24, 24, 28, 28, 28,
            36, 36, 36, 2,  2,  2,  2,  2,  2,  2,  2,  2,
            26, 26, 26,
        },
        .mixed_widths = .{
            12, 12, 12, 4,  4,  4,  8,  8,  8,  12, 12, 12,
            16, 16, 16, 20, 20, 20, 24, 24, 24, 28, 28, 28,
            36, 36, 36, 2,  2,  2,  2,  2,  2,  2,  2,  2,
            0,  0,  0,
        },
        .mixed_long = 6,
        .mixed_short = 30,
    },
};
