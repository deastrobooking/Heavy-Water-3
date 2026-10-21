# zig-mp3 vendor notes

This directory contains the MP3 decoder from Jeffrey C. Ollie's `zig-mp3`
project, pinned to the `zig-0.16` branch at commit
`50d4c967032119838e94b405ca478f673b42eabe` (MIT; see `LICENSES/MIT.txt`).
The game imports the streaming decoder in `src/decoder.zig` directly. Its
encoder and command-line tools are not part of the runtime path.

Local compatibility edits: test fixtures use typed `@splat` arrays and explicit
header copies instead of the array-repeat operator removed in Zig 0.17. These
edits do not change the decoder's runtime behavior.

Upstream: <https://git.jcollie.dev/jeff/zig-mp3>

Drop this vendor copy when the project adopts another maintained Zig MP3
decoder that supports the default toolchain and streaming frame decode.
