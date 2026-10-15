#!/usr/bin/env python3
"""Run the required local compiler, test, and Metal smoke gates."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHANNEL = "HEAVYWATER_ZIG_CHANNEL"
TEST_COUNT = re.compile(r"(\d+) pass \((\d+) total\)")


def run_gate(
    label: str,
    command: list[str],
    *,
    channel: str | None = None,
    metal_validation: bool = False,
    expect_tests: bool = False,
    fresh_cache: bool = False,
) -> tuple[int, int] | None:
    env = os.environ.copy()
    env.pop(CHANNEL, None)
    if channel is not None:
        env[CHANNEL] = channel
    if metal_validation:
        env["MTL_DEBUG_LAYER"] = "1"

    print(f"\n== {label} ==", flush=True)
    with tempfile.TemporaryDirectory(prefix="heavy-water-validation-") as cache_dir:
        actual_command = [*command]
        if fresh_cache:
            actual_command.extend(["--cache-dir", cache_dir])
        print("$ " + " ".join(actual_command), flush=True)
        process = subprocess.Popen(
            actual_command,
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert process.stdout is not None
        lines: list[str] = []
        for line in process.stdout:
            print(line, end="", flush=True)
            lines.append(line)
        result = process.wait()
    if result != 0:
        raise SystemExit(f"{label} failed with exit status {result}")

    if expect_tests:
        matches = list(TEST_COUNT.finditer("".join(lines)))
        if not matches:
            raise SystemExit(f"{label} succeeded without a readable test count")
        passed, total = (int(value) for value in matches[-1].groups())
        if passed != total:
            raise SystemExit(f"{label} is red: {passed}/{total} tests passed")
        print(f"PASS {label}: {passed}/{total} tests", flush=True)
        return passed, total

    print(f"PASS {label}", flush=True)
    return None


def main() -> None:
    if sys.platform != "darwin":
        raise SystemExit("The full gate includes Metal smoke and must run on macOS.")

    python = sys.executable
    zig = [python, "tools/zig.py", "build"]
    default_tests = run_gate("default build check", [*zig, "check"])
    default_tests = run_gate(
        "default headless tests",
        [*zig, "test", "--summary", "all"],
        expect_tests=True,
        fresh_cache=True,
    )
    run_gate(
        "default Metal smoke (300 frames)",
        [*zig, "run", "-Doptimize=ReleaseSafe", "-Dsmoke-frames=300"],
        metal_validation=True,
    )

    run_gate("Zig 0.17 build check", [*zig, "check"], channel="0.17")
    migration_tests = run_gate(
        "Zig 0.17 headless tests",
        [*zig, "test", "--summary", "all"],
        channel="0.17",
        expect_tests=True,
        fresh_cache=True,
    )
    assert default_tests is not None and migration_tests is not None
    print(
        "\nValidation gate passed: "
        f"default {default_tests[0]}/{default_tests[1]}, "
        f"Zig 0.17 {migration_tests[0]}/{migration_tests[1]}, Metal smoke clean.",
        flush=True,
    )


if __name__ == "__main__":
    main()
