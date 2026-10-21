<!--
SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
SPDX-License-Identifier: MIT
-->

# zig-mp3

An MPEG audio codec in Zig. It **decodes** MPEG-1, MPEG-2 LSF and MPEG-2.5,
Layers I, II and III, at all nine sampling frequencies and in every channel
mode, and reads the ID3 metadata that comes wrapped around it. It **encodes**
Layer II and Layer III.

Decoded output agrees with ffmpeg's decoder to within one least significant
bit of a 16-bit sample for Layer III, and two for Layers I and II, across
every format in the test matrix. Encoded output is read by ffmpeg as what it
claims to be at every setting, and reaches within a decibel of what its bit
budget arithmetically allows.

## Where it lives

The canonical repository is on Forgejo, with a mirror on Tangled:

```console
git clone https://git.jcollie.dev/jeff/zig-mp3.git
```

- <https://git.jcollie.dev/jeff/zig-mp3>
- <https://tangled.org/jcollie.dev/zig-mp3>

It is also on [Radicle](https://radicle.xyz/), where a repository is findable
only by its ID — this one is `rad:zYm7Hjq2obhp6sWMZsPYHrzsV9cq`:

```console
rad clone rad:zYm7Hjq2obhp6sWMZsPYHrzsV9cq
```

The API documentation is generated from the doc comments and published at
<https://jeff.jcollie.page/zig-mp3/>.

## Using it

Add it as a dependency and import the `mp3` module.

```zig
const mp3 = @import("mp3");
```

The core is a streaming decoder. Feed it whatever bytes you have; it tells you
what it did with them.

```zig
var decoder = mp3.Decoder.init();
var buffer: mp3.FrameBuffer = undefined;

var rest = data;
while (rest.len > 0) switch (decoder.next(rest, &buffer, .{})) {
    // Not a whole frame yet: read more and call again with the longer slice.
    .need_more => break,
    // A tag, rubbish between frames, or a frame that produced no audio.
    .skipped => |n| rest = rest[n..],
    .frame => |frame| {
        play(buffer[0 .. frame.samples * frame.channels]);
        rest = rest[frame.consumed..];
    },
};
```

Samples are `f32`, interleaved, nominally in −1…1; `mp3.toInt16` converts and
clips. Set `.end_of_input = true` on the final call so that the last frame is
not held back waiting for a successor to confirm it.

For a whole file already in memory:

```zig
var audio = try mp3.decodeAll(allocator, data);
defer audio.deinit();
// audio.samples, audio.sample_rate, audio.channels, audio.duration()
```

`decoder.reset()` throws away the bit reservoir and the filterbank history,
which is what a seek needs. The frame or two after a reset will be quiet while
the reservoir refills — an unavoidable consequence of how Layer III spreads a
frame's data backwards across its predecessors.

### Metadata

Decoding never allocates; reading metadata has to, so it is a separate call.

```zig
if (try mp3.id3.parse(allocator, data)) |*tag| {
    defer tag.deinit();
    std.debug.print("{?s} — {?s}\n", .{ tag.artist(), tag.title() });
}
```

ID3v1, v1.1 and ID3v2.2, v2.3 and v2.4 all come back as the same `Tag`, whose
accessors know which identifier each version used, so a caller never has to
ask which it got. Everything is decoded to UTF-8 whatever the frame claimed to
be encoded in — Latin-1, either byte order of UTF-16, or UTF-8. `tag.frames`
has the rest, including the payloads of frames this does not interpret, such
as attached pictures.

`tag.genre()` resolves ID3v1's numeric genres and the `(17)` form ID3v2
inherited from them; `tag.track()` and `tag.disc()` split the `3/12` form.

### Stream headers

`decoder.info()` returns the stream's Xing, Info or VBRI header once the
decoder has passed it, with LAME's encoder delay and padding when present.
`leadIn()` and `playableSamples()` turn those into the trims a player applies
for gapless playback.

## The command line tool

```
$ zig build
$ zig-out/bin/zig-mp3 track.mp3
mpeg1 layer3, 44100 Hz, 2 channels (joint_stereo)
constant 192 kbit/s
2298 frames, 2647296 samples per channel, 60.029 s
info header: 2298 frames, 1440705 bytes, seek table present
LAME3.100: 576 samples of delay, 1260 of padding
stated duration 60.000 s

v2_4 tag, 11 frames
  title        Sonata in Ré — Café ♫
  artist       Ünïcodé Player
  album        Tëst Recørds
  genre        Prog Rock
  track        3 of 12

$ zig-out/bin/zig-mp3 track.mp3 track.wav
```

Two arguments decode to a 16-bit PCM WAV, trimming the encoder's padding the
way a player would; `--raw` keeps it. An output of `-` writes to standard
output.

`--encode` goes the other way, reading a 16-bit PCM WAV and writing Layer II:

```
$ zig-out/bin/zig-mp3 --encode --bitrate 256 track.wav track.mp2
154 frames, 128731 bytes, 44100 Hz, 2 channels, 256 kbit/s
```

The bit rate has to be one the format can name, and naming one it cannot
prints the list that it can.

## Reading the API documentation

```
$ zig build docs          # into zig-out/docs
$ zig build docs-serve    # and read it at http://127.0.0.1:8000/
```

The generated viewer fetches `sources.tar` and `main.wasm` at runtime, which a
browser will not do from a `file://` page, so reading the documentation
locally means serving it — the same reason `zig std` runs a server rather than
opening a file. `-Ddocs-port=N` moves it off 8000.

## How it is put together

| file                     | what it does                                            |
| ------------------------ | ------------------------------------------------------- |
| `bitstream.zig`          | most-significant-bit-first reader                       |
| `header.zig`             | the four-byte frame header, all layers and versions      |
| `tags.zig`               | recognizing ID3v1, ID3v2 and APE blocks to step over     |
| `id3.zig`                | reading what is inside an ID3v1 or ID3v2 tag             |
| `vbr.zig`                | Xing, Info and VBRI headers, and the LAME extension      |
| `side_info.zig`          | the per-frame side information                           |
| `huffman.zig`            | Huffman decoding, tables built at compile time           |
| `layer12.zig`            | Layer I and II: allocations, scalefactors, requantization |
| `analysis.zig`           | the polyphase analysis filterbank, for encoding           |
| `psymodel2.zig`          | what the listener will not hear                          |
| `fft.zig`                | a radix-2 FFT, for the model above                       |
| `bitwriter.zig`          | most-significant-bit-first writer                        |
| `encode12.zig`           | the Layer II encoder: allocation, quantization, framing  |
| `mdct.zig`               | the forward transform, and the aliasing that goes with it |
| `huffman_encode.zig`     | Huffman coding in the writing direction                  |
| `encode3.zig`            | the Layer III encoder: the rate and distortion loops     |
| `layer3.zig`             | scalefactors, spectrum, requantization, stereo, reorder  |
| `imdct.zig`              | alias reduction, inverse MDCT, windows, overlap          |
| `synthesis.zig`          | the polyphase synthesis filterbank                       |
| `reference.zig`          | both filterbanks written longhand, for the tests to check against |
| `tools/docs_server.zig`  | serves `zig build docs` output over HTTP                 |
| `tools/gen_layer1.py`    | writes synthetic Layer I streams, which nothing encodes   |
| `wav.zig`                | just enough RIFF WAVE to read and write 16-bit PCM        |
| `decoder.zig`            | frame finding, the bit reservoir, the public decoder     |
| `tables/`                | generated constant tables                                |

Every stage walks the same list of scalefactor band widths, which is what
keeps long, short and mixed blocks from each needing their own code path: a
granule's spectrum is the concatenation of its bands, band `i` shares its index
with scalefactor `i`, and in a short block each band appears three times, once
per window.

Huffman tables are turned at compile time into a 9-bit lookup table with a
binary tree hanging off the entries whose code words are longer than that, so
the common case is one indexed load.

## Where the constants come from

The Huffman code tables, the scalefactor band widths and the polyphase window
are specified by ISO/IEC 11172-3 and 13818-3. They are not reproduced here
from memory. `tools/gen_tables.py` extracts them from two references that put
them in the public domain — [PDMP3][pdmp3] (Unlicense) and [minimp3][minimp3]
(CC0) — cross-checks them against each other where they overlap, and emits the
files in `src/tables/`:

```
$ curl -O https://raw.githubusercontent.com/technosaurus/PDMP3/master/pdmp3.c
$ curl -O https://raw.githubusercontent.com/lieff/minimp3/master/minimp3.h
$ python3 tools/gen_tables.py --pdmp3 pdmp3.c --minimp3 minimp3.h
$ zig fmt src/tables
```

Neither project's code is used; only the standard's numbers are read out of
them, and the generator asserts as it goes:

- every Huffman table must be a complete prefix code (Kraft equality, exactly);
- the count1 tables must match ISO/IEC 11172-3 Table B.7, transcribed
  independently into the generator;
- the three MPEG-1 scalefactor band rows derived from minimp3's widths must
  equal PDMP3's independently written band boundaries.

That last check earned its keep: PDMP3's table of table offsets has a typo in
the entry for Huffman table 33, which points 512 words short of where the
table actually is. Reading the tables through the declared offsets produced a
degenerate one-symbol "table"; walking the trees in layout order and checking
the result against the standard found it immediately.

Running the generator against the same two references reproduces the committed
files byte for byte.

[pdmp3]: https://github.com/technosaurus/PDMP3
[minimp3]: https://github.com/lieff/minimp3

## Is it right?

`zig build test` runs 133 tests. Most are unit tests with hand-checked
expectations, but the ones that matter most compare whole decoded streams
against reference decodings produced by ffmpeg, which are committed in
`testdata/` alongside the files that produce them.

Every push runs three checks on a Forgejo runner: REUSE compliance,
`zig fmt --check .`, and the test suite. `.forgejo/workflows/test.yaml` drives
them all through `nix develop`, so the runner needs nothing but Nix and gets
exactly the toolchain `flake.nix` pins — including the patched Zig, without
which a project containing a fuzz test cannot build its tests at all. When
those pass on `main`, a second job builds the API documentation and publishes
it to <https://jeff.jcollie.page/zig-mp3/>.

For a much wider sweep, `tools/check-against-ffmpeg.py` generates a synthetic
source, encodes it at forty-one combinations of layer, version, sampling frequency,
bit rate and channel mode, decodes each with both decoders and reports the
agreement:

```
$ python3 tools/check-against-ffmpeg.py

Layer III
  MPEG-1  44100 joint  128k     83.52 dB  peak 1     48483 bytes
  ...
Layer II
  MPEG-1  44100 stereo 384k     83.92 dB  peak 2    144195 bytes
  ...
Layer I
  MPEG-1  44100 joint/8 448k    76.50 dB  peak 2    166496 bytes
  ...

worst agreement 69.17 dB over 41 formats
every format agrees with ffmpeg to within its layer's tolerance
```

Around 80 dB with a peak difference of one is what two decoders that differ
only in the last bit of a 16-bit sample score; it is the floor set by rounding,
not a measure of remaining error. Anything actually wrong with a window, a
table or a stereo mode costs tens of decibels, which is how the one real bug
found late in development — a second Huffman region that stopped short of the
end of a short block's spectrum, quietly zeroing its upper bands — announced
itself.

Layers I and II settle at a peak difference of two rather than one, because
their requantization is a different arithmetic in the two decoders rather than
the same arithmetic rounded differently. This one multiplies each code by a
single number that folds the scalefactor and the quantization step together;
ffmpeg keeps them apart. Both are inside ISO/IEC 11172-4's tolerance by a wide
margin.

The three layers get their streams from three different places, which is worth
being explicit about. Layer III comes from LAME and Layer II from ffmpeg's own
MP2 encoder. Nothing in common use still encodes Layer I, so
`tools/gen_layer1.py` writes the bitstream directly — random allocations,
scalefactors and codes, drawn to fit the frame's bit budget exactly. Its
allocation table is the one thing it has in common with the decoder, and that
table is four bits naming a width of `n + 1`; the Layer II tables are
deliberately *not* mirrored into a generator, because reading them back out of
this decoder to write a stream would make the comparison confirm itself.
ffmpeg still supplies the reference decoding in every case, which is what makes
any of it evidence.

## Fuzzing

Feeding an MP3 decoder uniformly random bytes barely tests it: a frame sync is
four bytes of structure, so random input almost never gets past the sync
scanner and the interesting code is never reached. So `src/fuzz_test.zig`
*builds* streams instead — a header template held fixed the way a real file's
is, frames sized from it, bodies of arbitrary bytes, `main_data_begin` biased
small so the bit reservoir does not turn the frame away, and tags and rubbish
spliced in. That puts arbitrary data into the side information, the
scalefactors, the Huffman data and the block layouts, which is where a decoder
is most likely to mishandle it.

The generator takes its decisions from either source:

```
$ zig build test                          # seeded, deterministic, every build
$ zig build test -Dfuzz-rounds=300000     # the same, as a campaign
$ zig build fuzz --fuzz                   # driven by Zig's fuzzer
```

The seeded path is what does the work at present. It is deterministic, so a
failure reproduces, and the round count is a build option so that the same
targets serve both a two-second test run and a soak.

The targets, and what each is really for:

| target | what it is watching |
| --- | --- |
| built streams | the decoder end to end, and that chunking the input changes nothing |
| arbitrary bytes | the sync scanner and the tag skipper |
| the bit reader | the eight-byte load against a plain bit-at-a-time reader |
| the bit cache | the 57 bits the Huffman loop reads through, driven as the decoder drives it, against the same plain reader |
| the filterbanks | the halved arithmetic against the standard's own, in `reference.zig`, at both slot counts and writing into one channel of an interleaved pair as well as a buffer of its own |
| resets | the bit reservoir and the filterbank history across discontinuities |
| side information | that a malformed granule is rejected, not misread |
| Huffman | that decoding always terminates, always advances, always returns a representable pair |
| Layer I and II frames | that any allocation, scalefactor and code an arbitrary body can name decodes to finite, bounded samples, including when the subbands between them ask for more bits than the frame holds |
| encoding | that arbitrary samples, at any supported setting and in either layer, come back out as a stream this decoder reads as exactly what the encoder said it was making, and that neither the allocation loop nor the rate loop overspends its frame |
| the psychoacoustic model | that whatever the signal, every masking threshold is a real number at or above the threshold of hearing, every ratio a proportion of a band's energy, and the whole run repeats exactly after a reset |
| ID3 tags | that everything comes out valid UTF-8, and nothing leaks when allocation fails |
| Xing, Info and VBRI headers | that a duration is a finite number of seconds and a seek lands inside the file |
| the one shot interface | that it holds together, and leaks nothing when allocation fails |

The encoder is fuzzed differently from the rest, because it is the one part
of this library allowed to choose: there is no reference to hold it against
and no output to predict. What there is instead is a contract — every frame
must be the size its header claims, must parse back as the scale information
it was written as, must decode, and must give back the right number of finite
samples — and silence in must be silence out exactly.

That contract is not enough on its own, and the Layer III encoder proved it.
Its worst fault produced frames that satisfied every clause of it: correct
sizes, parseable side information, exact Huffman data, the right number of
finite samples — carrying noise. Structure can be perfect while the thing the
structure describes is meaningless. So the target also encodes a tone and
insists it comes back: not at any particular quality, since a signal-to-noise
ratio is the wrong measure for a coder that deliberately discards what cannot
be heard, but far enough above nothing to tell a coded signal from a destroyed
one.

The sharper guards for that fault live beside the code instead, where they can
aim: one checks that a quantizer step too small to code is refused rather than
clamped, and one rebuilds a granule from what the loops chose and insists it
still resembles the spectrum it was made from. Both fail if the clamp comes
back; the fuzz target, whose tone is an easier thing to code than the signal
that first exposed it, does not. Breadth and aim are different jobs.

Its input is not just noise, either. Uniform noise lights every subband at a
similar level, so the allocation loop takes the same path every time; the
target walks six shapes instead, adding silence, harmonic tones, samples well
past full scale, sparse impulses and direct current, which are what reach the
corners where subbands are given everything or nothing. What the loop decided
is then read back out of the encoder's own output with the decoder's parser,
which is both a check that the two agree about the layout and the only way to
see the choices from outside. Over a thousand rounds that reaches 45,802
subbands on the packed quantization classes, 30,694 given nothing at all,
2,542 given the most their table can name, all four scalefactor selectors and
all six shapes.

Choosing those took an audit rather than a guess. Counting how often each
target reached the code it was named for turned up one that never did at all:
the Xing and VBRI parser was called zero times in twenty thousand rounds,
because its magic is four bytes at an offset that depends on the header and
arbitrary bytes never land on it. It needed a generator that builds the frame
around it, and now finds a header about two thirds of the time, a third of
those carrying a LAME extension.

The frame header is not fuzzed at all, because it does not need to be: eleven
of its 32 bits are the sync word, so all 2^21 remaining headers are enumerated
and checked against each other outright — that every accessor agrees with the
fields it was derived from, that a frame size is stated exactly when a bit rate
is, that the joint stereo flags mean nothing outside joint stereo. Exactly
622,080 of them parse and 41,472 are free format, and the test says so, since a
change that quietly rejected everything would otherwise pass.

Three of those are differential: they hold an implementation written for speed
against one written to be read. That is what made the filterbank and bit reader
rewrites safe to attempt, and each of them catches a deliberately introduced
off-by-one immediately.

What every target asserts, whatever the input: the decoder never reads out of
bounds (Debug and ReleaseSafe builds check every one), every step consumes at
least one byte or asks for more, a frame that is returned is a whole frame
whose sample count matches its header, and every sample is finite. The tests
also assert that the generator keeps reaching that far, so that a change which
quietly made every generated stream unsyncable would fail rather than pass
vacuously — an earlier version of the harness was generating empty streams and
testing nothing.

Sample *magnitude* is deliberately not asserted. A frame is free to state the
largest global gain alongside the largest quantized values, and it then
legitimately decodes to values millions of times outside -1...1. The decoder
does not bound that, since what to do about it is the caller's business;
`toInt16` clamps.

`zig build fuzz --fuzz` compiles and starts, which needs the patched Zig in
this repository's `flake.nix` — stock Zig 0.16 cannot build a test executable
in fuzz mode at all. It does not get further: the same release leaves the
table of program counters empty, so `--fuzz=N` stops with `corrupted coverage
file: pcs_len was zero` and a plain `--fuzz` panics in the build runner's
coverage thread. Neither is a finding. The targets are written and correct for
when that is fixed.

## Speed

`zig build bench` decodes a stream end to end and then times the filterbank
stages on their own:

```
$ zig build bench
Layer III: 44100 Hz, 2 channels, 19 frames
  595.59 s of audio in 0.213 s
  2792x real time
  42.6 MB/s of bitstream, 246.3 M samples/s
  2339 ns per granule and channel

Layer II: 44100 Hz, 2 channels, 23 frames
  7069x real time, 623.5 M samples/s

Layer I: 44100 Hz, 2 channels, 20 frames
  4120x real time, 363.3 M samples/s

per granule and channel:
  polyphase synthesis           790 ns   33.8%
  IMDCT and windowing           743 ns   31.8%
  alias reduction                43 ns    1.8%
  frequency inversion            23 ns    1.0%
  everything else               740 ns   31.6%
```

"Everything else" is Huffman decoding and requantization. It used to be two
fifths of the time; the section below is what took it to a third.

All three layers are measured because they share the filterbank and almost
nothing else, so a change to it should move all three and a change to Layer
III should move only the first. The two simpler layers are quoted per sample
rather than per granule, which is a unit only Layer III has. Layer II is the
fastest of the three by a wide margin — it has no Huffman coding, no bit
reservoir and no hybrid transform — and its clip is 64 kbit/s, where a frame
carries eight of the thirty-two subbands and the filterbank skips the rest.

Each figure is the best of five runs rather than the mean. Another build on
another core cannot make this code faster, only slower, so the fastest run is
the one least contaminated by anything else — which matters, because on a busy
machine the mean of the stage timings swings by half.

Against ffmpeg on ten minutes of 192 kbit/s stereo, decoding to raw samples,
they finish together and this one uses less than half the processor:

| | wall | user | sys |
| --- | --- | --- | --- |
| this decoder | 0.39 s | 0.38 s | 0.01 s |
| `ffmpeg -threads 1` | 0.39 s | 0.66 s | 0.22 s |

ffmpeg's command line tool demuxes, decodes and writes on separate threads;
this decoder is single threaded and still does the job for rather less
processor time.

### How it got there

It started out ten times slower, and measurement — not intuition — found every
change that mattered. `perf` is in the devshell; because the whole granule
pipeline inlines into one symbol, marking the stages `noinline` for a
profiling run is what makes it legible.

**The filterbanks** were the first target, and both had the same two problems.
Each computed outputs that the standard's own symmetries give away: writing the
synthesis matrixing as D[u] = Σ s[j]·cos(u(2j+1)π/64), the row the standard
calls N[i] is D[16 + i] and D[64 − u] = −D[u], so half the rows are free and
D[32] is zero; the inverse MDCT's 36 outputs likewise obey x[17 − i] = −x[i]
over the first half and x[53 − i] = x[i] over the second. And both were written
as dot products, which end in a horizontal sum across a vector that costs more
than the multiplying did — transposing the coefficient tables so that results
accumulate in separate lanes removed that entirely.

Two more followed. The synthesis history had been kept in a buffer of twice the
length it needed, every value written to both halves so the window's reads
never straddled the wrap; a ring of sixteen 64-value blocks makes straddling
impossible by construction, because every read the standard asks for falls
inside one block. And building the 64 matrix rows out of the 32 computed
values was sixty-odd scalar moves per slot, where two shuffles and two sign
patterns do it in six vector operations.

**Requantization** was branching on the sign of every spectral value, which is
as good as random and mispredicted half the time; moving the sign across as a
bit took it from 19% of the profile to 8%. Its gain term is a power of two in
quarter steps, so a table replaced a libm call. Almost every spectral line is
small enough to have been coded without an escape, so a second small table
carries those values with their sign already in them. And the spectrum is no
longer cleared before being filled, nor requantized above the last line the
Huffman data actually coded — `memset` fell from 5.5% of the profile to 0.6%.

**The inverse MDCT** now looks at a subband before transforming it. An encoder
writes nothing above its lowpass, so an eighth of them are silent on the
broadband noise this is benchmarked with and a fifth on anything resembling
music, and the transform of nothing is nothing. That test also tells the
filterbank how far up the spectrum it has to matrix at all, which costs
nothing to pass on and is exact: a silent subband contributes its row of
cosines multiplied by zero.

**Layers I and II** arrived later and repeated two of the same lessons. Their
granule buffer was being cleared in full before every granule, which was 12%
of Layer I's time and 15% of Layer II's, nearly all of it zeroing subbands
about to be overwritten; a frame's allocations hold for all of its granules,
so what stays silent is known once and cleared once. Applying the
scalefactors in a second pass over the granule was a whole read-modify-write
of every sample that folds into the multiply already happening as each value
is read. And a Layer I frame at a middling bit rate codes about a dozen of
its sixty-four subband-and-channel pairs, so testing all sixty-four on each
of twelve time slots was 768 tests to find twelve; gathering the coded ones
once per granule, with their scalefactors already looked up, was worth a
third of Layer I's time.

Together those took Layer II from 5036x real time to 7069x and Layer I from
3009x to 4120x, and Layer III gained a little from the shared filterbank
change.

**Huffman decoding** is a chain of dependent reads — each one's position
depends on the width of the last — so an eight-byte load sat on the critical
path of every one. It now runs against a cache of the next 57 bits held in a
register, refilled once per code word rather than touched three times.
Counting rather than guessing found two more: 39.5% of pairs come from a table
with an escape, so the test for it is a coin flip taken sixteen million times a
minute — and it is fixed for a whole region, so it now sits outside the loop.
And the count1 partition was working out four values from four magnitude bits
and a run of sign bits with four dependent tests, three million times a minute;
there are only 256 combinations, so they are all worked out at compile time.

### What did not work

Rather more than what did, and each was quicker to measure than to argue about.

- **Caching the bit reader's window** inside `Reader`, so consecutive reads
  share a load. Slower: the branch deciding whether the window still covers the
  read costs more than the L1 load it saves. The same idea as a local buffer
  over the hot loop, where the compiler can keep it in registers, is the win
  described above.
- **The branchless sign trick in `spectralValue`.** It helped in requantization
  because it unblocked vectorising a 576-sample loop; here there is no loop to
  vectorise and it only lengthened a serial dependency. 5% slower.
- **Taking the code word and both sign bits from one 32-bit peek** rather than
  three loads. 8% slower against the reader, because the peek was a load and
  accumulating the bit count lengthened the chain. Against the register cache
  the same shape is free, and is how the loop is written now.
- **Splitting the synthesis accumulator four ways** to break the multiply-add
  dependency chain. 6% slower: a 32-lane multiply-add is already four
  independent 8-lane ones, so the parallelism was there and four accumulators
  only spilled registers. Two accumulators measured identically to one.
- **Matrixing two slots per pass** over the four-kilobyte coefficient table, on
  the theory that the stage was bound by loads. No change at all.
- **Padding the inverse MDCT's vectors to 24 lanes** rather than 32, to waste
  fewer on the 18 rows it needs. Five times slower — LLVM legalises a vector
  that is not a power of two into pieces costing far more than the lanes they
  save, the same trap an 18-lane vector fell into earlier.
- **Refilling the bit cache once per two code words** instead of once per word.
  Slightly slower.
- **Widening the Huffman lookup table**, which was not worth measuring once the
  tree walk behind it was counted: it is taken for 2.7% of code words.
- **The register bit cache in the Layer I and II sample loop.** It is the same
  shape of loop the cache was written for — a long chain of reads, each one's
  position set by the width of the last — and it changed nothing. The
  difference is that here the widths come from the allocations, which are
  known before any of the reads happen, so the next position never waits on a
  load and the latency the cache exists to hide was already hidden.
- **Clearing silent subbands in merged runs** rather than one at a time. 5%
  slower, and instructively so: one subband is a constant 48 bytes, which the
  compiler puts inline as a few vector stores, while a run has a length known
  only at runtime and becomes a call to `memset`. Merging turned every small
  inlined clear into a call. What is worth merging is the region above the
  highest coded subband, which is large, contiguous and known — so that one is
  a single clear and the isolated holes below it are not.
- **A full table for the Layer I and II scalefactors**, replacing a lookup for
  the index's remainder and a divide by the power of two its whole part named.
  The divide was free — there are only a few dozen per frame and its latency
  hides behind everything around it. The table stayed anyway, because one
  indexed load reads better than three operations, but it bought nothing.

Both filterbanks are also written out longhand in `reference.zig`, the way the
standard's flowcharts read, with tests holding the fast versions against them.
That is what made all of this safe to attempt: every change was checked against
a second implementation, against ffmpeg's decoder, and against the fuzz suite.

### On "the same output"

The standard does not define one correct set of samples. ISO/IEC 11172-4
defines compliance as staying within a tolerance of a reference decoder, and
every implementation in floating point lands somewhere inside it. What is
checked here — and what "agrees to within one least significant bit" means
throughout — is agreement with ffmpeg's decoder, not that this decoder's own
output never moves.

It does move, occasionally and by one. The order a sum is accumulated in
changes its rounding, so splitting the inverse MDCT's accumulator shifted 386
samples in 441,000 by a single count. That is far inside the tolerance and is
not a defect, but it is worth being exact about: these changes preserve
agreement with a reference, not byte-for-byte reproducibility against an
earlier build.

## Encoding

`zig-mp3 --encode` reads a 16-bit PCM WAV file and writes Layer III or, with
`--layer 2`, Layer II. Constant bit rate, stereo or mono.

```
$ zig-mp3 --encode --bitrate 256 music.wav music.mp3
layer 3: 115 frames, 96130 bytes, 44100 Hz, 2 channels, 256 kbit/s
```

**Layer II** takes 1152 samples of each channel and makes a frame in five
steps: the analysis filterbank turns them into 36 time slots of 32 subbands;
the psychoacoustic model says how much noise each subband can hide; a
scalefactor per subband and granule captures its peak; bits go to whichever
subband is furthest from hiding its own noise, one quantization class at a
time, until the frame is full; and the samples are quantized to what they
were given.

**Layer III** adds a second transform behind the filterbank, Huffman coding of
the quantized spectrum, and a pair of nested loops that decide how finely to
quantize. The loops are the heart of it:

- the *rate* loop asks how large the quantizer's step has to be for the
  granule to fit the bits it has been given. Bits fall as the step grows, so
  this is a search over one number;
- the *distortion* loop asks whether the noise that quantizing left behind is
  hidden. Where a band's noise is above what the model says can be masked
  there, that band's scalefactor goes up, which quantizes it more finely at
  the cost of bits everywhere else — so the rate loop runs again, and the two
  go round until either every band is hidden or nothing more can be done.

The one bug that mattered while writing it was in exactly that interaction.
The quantizer clamped a value too large for any Huffman table to name, which
seemed safe and was not: it made the bit count stop growing as the step
shrank, and the rate loop's search *depends* on that count growing. With the
predicate no longer monotonic the search returned a step far too small, every
line saturated, and the output was uncorrelated noise at a fifth of the right
amplitude. Reporting the overflow instead of hiding it took the round trip
from 0.6 dB to 79.

The encoders are built on the decoder's own tables — the allocation tables,
the quantization classes and the scalefactors are read out of `layer12.zig`
rather than written again — so the two cannot drift apart. What is *not*
shared is the interesting part, because it is the part the standard does not
specify. A decoder has one right answer. An encoder has a budget and a choice
about how to spend it, and the psychoacoustic model is where that choice is
made.

### The psychoacoustic model

`psymodel2.zig` is the shape of the standard's informative Psychoacoustic
Model 2, whose idea is that **tonality is predictability**. A steady sinusoid
advances its phase by the same amount every frame and holds its magnitude, so
the next frame can be extrapolated from the last two almost exactly; noise
cannot be extrapolated at all. So rather than ask what a band's spectrum looks
like, it asks how well each bin was predicted — which is per-bin, and far
sharper than the spectral flatness the first version of this used. Tonality is
the thing such a model most needs to get right, since a tone hides far less
noise than a noise of the same energy.

Around that:

- the critical band rate is Zwicker's `13 atan(0.00076 f) + 3.5 atan((f/7500)²)`;
- the threshold in quiet is Terhardt's
  `3.64 (f/1e3)^-0.8 − 6.5 exp(−0.6 (f/1e3 − 3.3)²) + 1e-3 (f/1e3)⁴`;
- masking spreads between partitions of a third of a critical band each by
  Schroeder's curve, steepened below the masker, since masking reaches much
  further up in frequency than down;
- and the threshold is held near what the last two frames allowed, so that a
  loud frame cannot license noise across the quiet one in front of it — which
  is the artefact a listener notices most.

**Written from the published description rather than ported.** The models
worth learning from — LAME's above all — are LGPL, and this is MIT. But a
psychoacoustic model is not normative, no decoder ever sees it, and the
algorithm is in the literature; what is implemented from a description is not
a derivative work of anyone's code. The permissively licensed alternatives
were considered and turned down for fit rather than licence: libvorbis's
`psy.c` is BSD-3-Clause and mature, but it is built around Vorbis's own
transform sizes and floor curves and does not produce a signal-to-mask ratio
at all.

Formulas rather than the standard's tables, for the same reason: the annex's
tables carry no more authority than the literature they came from, and a
formula works at every sampling rate rather than at the six the annex
tabulates. The masking constants at the foot of the file are tuning, not
specification — nothing about them is authoritative and none of them can make
a stream invalid.

### Is the encoder right?

Two questions, and they are worth keeping apart.

**Is the bitstream valid?** That is yes or no, and `tools/check-encoder.py`
asks ffmpeg: at every setting in its matrix, ffmpeg must recognise the file as
Layer II at the stated sampling rate, channel count and bit rate, and decode
the number of samples that went in. All twelve settings pass. The library's
own tests then encode and decode a signal and check it comes back.

**How good does it sound?** That is a matter of degree, and the honest answer
is that this has not been listened to. What can be measured is whether the
bits are being spent, and against what ceiling:

```
$ python3 tools/check-encoder.py
  Layer II  44100 stereo 384k   25.94 dB   4.35 bit/sample    5.96 dB/bit
  Layer II  44100 stereo 256k   23.73 dB   2.90 bit/sample    8.18 dB/bit
  Layer II  44100 stereo 128k   16.49 dB   1.45 bit/sample   11.36 dB/bit
  Layer III 44100 stereo 256k   30.04 dB   2.90 bit/sample   10.35 dB/bit
  Layer III 44100 stereo 128k   20.75 dB   1.45 bit/sample   14.30 dB/bit
  ...
worst 5.33 dB per bit over 20 settings, against a ceiling of about 6
```

Those signal-to-noise ratios look poor until the budget is read alongside
them. A uniform quantizer given *b* bits a sample cannot beat about 6.02*b*
decibels, and Layer II at 384 kbit/s in stereo has 4.35 bits for each of its
samples before headers and scalefactors are paid for — so 26 dB is the whole
of what is available there, and the encoder gets 25.7 of it.

Six is a ceiling for Layer II and not for Layer III, which reaches ten and
more. That is not an error in the arithmetic: Layer II sends a fixed number of
bits per sample, while Layer III Huffman codes its spectrum, so the bits it
sends are not the bits its quantizer used. The comparison worth making is
between the two layers at one bit rate, where Layer III should win — and at
128 kbit/s in stereo it is 20.75 dB against 16.49, and at 256 it is 30.04
against 23.73.

None of this is a listening test. A *worse* psychoacoustic model would score
better on a signal-to-noise ratio, since noise shaped into the places a
listener cannot hear it is still noise as far as the ratio is concerned. That
is the limit of what these numbers can tell you.

### What the encoder does not do

- **Short blocks, in Layer III.** The forward transform handles them and is
  tested through the whole long-start-short-stop sequence, but nothing yet
  decides *when* to switch, so every granule is a long block. That costs
  pre-echo on sharp attacks and nothing at all elsewhere.
- **The bit reservoir.** Layer III lets a granule borrow space from earlier
  frames; every frame here stands alone, with `main_data_begin` always zero.
  It is a few percent of quality on material whose demands vary frame to
  frame, and one fewer thing to get wrong.
- **MPEG-2 and MPEG-2.5 rates, in Layer III.** The low sampling frequencies
  use a different scalefactor scheme. Layer II encodes them.
- **Variable bit rate.** Every frame is the size the header says.
- **Joint and mid/side stereo.** Both decide that two channels are alike
  enough to share something, which is a judgement this has no way to make well
  yet. Coding both channels in full is always correct, if not always thrifty.
- **Layer I.** Nothing writes it any more, and `tools/gen_layer1.py` already
  produces the streams the decoder is tested against.

## Limitations

- **Tags are read, not written.** There is no encoder here and no tag writer
  either.
- **APE tag contents are not read.** They are recognized and stepped over so
  that they are never mistaken for audio, but nothing looks inside.
- **Compressed and encrypted ID3 frames are skipped.** Both are rare and both
  need machinery — zlib, and a key — that does not belong in a decoder. The
  rest of the tag still reads.
- **Layer II joint stereo is not verified against a reference.** ffmpeg's MP2
  encoder writes only stereo and mono, so the test matrix cannot reach it. The
  code that shares subbands between the channels is the same code Layer I uses,
  and that is tested at all four bounds; what goes untested is that combination
  with Layer II's own allocation tables.
- **Free format is not supported.** A frame whose header states no bit rate is
  skipped; reconstructing its size means measuring the distance to the next
  sync word, which is not implemented.
- **CRCs are not verified.** The two bytes are recognized and stepped over.
  That they are stepped over correctly is tested: `tools/gen_layer1.py --crc`
  writes frames with a real, correctly computed CRC, and one case in the
  matrix uses it.
- **Intensity stereo is implemented but not verified against a reference.**
  LAME does not produce it, so the test matrix cannot reach it; the code
  follows the standard for both MPEG-1 and the low sampling frequency versions
  but has not been exercised against a known-good decoder.
- **Mixed blocks at 8 kHz** follow a quirk where the long region of the block
  runs to 48 lines rather than 36, matching ffmpeg and minimp3. Real files
  containing this are close to nonexistent, and it is untested.

## References

### The standards

**ISO/IEC 11172-3:1993** — *Information technology: coding of moving pictures
and associated audio for digital storage media at up to about 1,5 Mbit/s.
Part 3: Audio.* The MPEG-1 audio standard, and the primary reference for all
of this. It defines the frame header, all three layers, the Huffman code
tables, the scalefactor band widths, the bit allocation tables and the
polyphase synthesis window. `header.zig`, `layer12.zig`, `layer3.zig`,
`imdct.zig` and `synthesis.zig` are each an implementation of some part of it.

**ISO/IEC 13818-3:1998** — *Information technology: generic coding of moving
pictures and associated audio information. Part 3: Audio.* MPEG-2's lower
sampling frequencies — 16, 22.05 and 24 kHz — which are not simply MPEG-1 at
half the rate. It gives Layer II a different bit allocation table, Layer III
different scalefactor band widths, a different scalefactor compression scheme
and different intensity stereo positions, and it halves the side information
by putting one granule in a frame instead of two.

**ISO/IEC 11172-4:1995** — *... Part 4: Compliance testing.* This is the
document that defines what "correct" means for a decoder, and it does not
define one right set of samples: it asks that output stay within a stated
tolerance of a reference decoder. That is why this project measures agreement
rather than equality, and why a peak difference of one or two counts as
correct. See [On "the same output"](#on-the-same-output).

**MPEG-2.5 has no standard.** It is Fraunhofer's extension of MPEG-2 LSF down
to 8, 11.025 and 12 kHz, signalled with a header bit combination that ISO/IEC
11172-3 reserves, and there is no specification to cite. The frame layout is
MPEG-2's with the sampling frequencies halved again; what is implemented here
is what the existing decoders agree on.

The numeric tables in `src/tables/` were **not** transcribed from these
documents. They are extracted from two public-domain implementations and
cross-checked against each other, for the reasons and with the safeguards set
out in [Where the constants come from](#where-the-constants-come-from).

### The metadata formats

None of these is a standard in the sense above; each is an informal
specification that became universal by being implemented.

- **ID3v1** and **ID3v1.1** — a fixed 128-byte block at the end of the file,
  with the track number squeezed into the last two bytes of the comment.
- **ID3v2.2**, **ID3v2.3.0** and **ID3v2.4.0** — the three incompatible
  revisions of the tag that goes at the front, published informally at
  `id3.org`. All three are read; they differ in frame identifier length, size
  encoding and text encodings.
- **APEv2** — recognized by its header or footer and stepped over, so that a
  tag is never mistaken for audio. Nothing looks inside.

### The encoder headers

Also informal, and also universal. All three live in the first frame of a
stream, where a decoder that does not know about them sees only silence.

- **Xing** and **Info** — the variable and constant bit rate forms of LAME's
  header: frame and byte counts, and a hundred-entry seek table.
- **VBRI** — Fraunhofer's equivalent, with a seek table of its own shape.
- The **LAME extension** that follows a Xing or Info header, whose encoder
  delay and padding fields are what make gapless playback possible. The field
  layout is documented in LAME's own source and in the widely circulated
  "LAME tag" description that grew up around it.

## Licence

MIT, and [REUSE](https://reuse.software) compliant: `reuse lint` passes.
