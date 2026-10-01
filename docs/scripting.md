# Scripting runtime evaluation

The roadmap asked to evaluate a native Zig WebAssembly runtime before selecting a scripting approach. This is that evaluation and the decision.

## Requirements

1. **Native Zig:** no C or C++ libraries, consistent with the engine rule.
2. **Deterministic:** the same inputs give the same outputs on every machine. Scripts run inside the fixed-step simulation, and saves and co-op depend on it.
3. **Sandboxed:** a mod cannot read files, reach the network, corrupt the engine, or hang the frame.
4. **Authorable:** mod authors use real languages and tools, not a bespoke language.
5. **Cheap enough** for per-step machine logic.

## Options considered

| Option | Native Zig | Deterministic | Sandboxed | Authoring | Verdict |
| --- | --- | --- | --- | --- | --- |
| Logic graphs only (the existing `logic` device) | yes | yes | yes | node lists in JSON; no loops or functions | Kept for simple circuits; too limited alone |
| Embedded Lua, JavaScript, or Wren | no (C runtimes) | depends on the runtime | needs careful binding | good | Rejected by the native-Zig rule |
| A custom scripting language | yes | yes | yes | a new language to learn and tool | Rejected: high cost, poor authoring |
| Native plugins (dynamic libraries) | yes | no guarantee | none | good | Rejected: no sandbox |
| **WebAssembly, interpreted in Zig** | yes | yes (interpreter semantics) | yes | Zig, Rust, C, AssemblyScript… | **Selected** |
| WebAssembly with a JIT | yes in principle | yes | weaker, executable memory | same | Deferred: complexity and platform policy |

## What was built to evaluate it

`script/Wasm.zig` is a WebAssembly 1.0 interpreter in about 1,100 lines of Zig:

- **Coverage:** every core numeric, memory, control, and call instruction, plus the sign-extension, saturating conversion, bulk-memory and multi-value extensions that Zig emits.
- **Execution model:** module parsing with structural checks, and precomputed branch tables. An iterative interpreter with fixed value, label and frame stacks, so there is no host recursion.
- **Limits:** a fuel limit, a memory cap with bounds checks on every access, and a call-depth limit.
- **Safety model:** modules with imports or a start function are rejected. Operand types are not validated ahead of time; values are untyped 64-bit slots and every access is checked at run time. A malformed module can compute nonsense or trap, but cannot reach outside its instance.

## Measurements (Apple M3 Pro, 2026-09-30)

Measurements use the example mod `glowworks`, compiled by the pinned Zig with `ReleaseSmall` into a 6.8 KiB module with 8 functions, including the standard library's `sin`.

| Measure | ReleaseFast | ReleaseSafe |
| --- | --- | --- |
| `breathe` (sine) per call | 802 ns, 170 instructions | 836 ns |
| `majority` per call | 374 ns, 99 instructions | 408 ns |
| Interpreter throughput | 212–264 M instructions/s | 203–243 M instructions/s |
| The same `breathe` compiled natively | 5.6 ns | 5.6 ns |

Each instance uses its module's memory (64 KiB here) plus 194 KiB of fixed execution stacks.

**Correctness:**
- The interpreted `breathe` matches the native function to within 1e-6 over a minute of inputs, and `majority` matches its full truth table.
- Hand-assembled tests cover loops, `br_table`, `select`, memory sign extension, division traps, out-of-bounds traps, fuel exhaustion on an infinite loop, recursion depth, float-to-int traps and saturation, round-half-to-even, and signed-zero `min`.

## Decision

Mod scripting uses **WebAssembly, interpreted natively in Zig**, as mod API version 1.

- **Cost:** interpretation costs about 150× native time. At 0.4–0.8 µs per call, a 1 ms per-step budget covers over a thousand script devices, which is far beyond what a world holds today.
- **Scope:** scripts are machine logic, not engine extensions: pure functions of four signals and time, with no host imports.
- **Revisit when:** scripts need host queries, which means designing a capability-based import API; per-call cost dominates a measured workload, where register-based pre-decoding or a JIT would be the options; or scripts need state, which means saved linear-memory snapshots.

Spec conformance has not been measured against the official WebAssembly test suite; coverage is by the tests above and by real compiler output.
