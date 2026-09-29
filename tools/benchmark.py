#!/usr/bin/env python3
"""Run the fixed streaming route and retain its JSON counters plus host/toolchain context."""
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--seed", type=int, default=310399555161)
    parser.add_argument("--upload-budget-kib", type=int, default=320)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--output", type=Path, default=ROOT / ".tools/streaming-benchmark.json")
    args = parser.parse_args()
    if not 120 <= args.frames <= 4096:
        parser.error("--frames must be 120..4096 so the complete measured run fits the percentile sample buffer")
    if args.upload_budget_kib < 278:
        parser.error("--upload-budget-kib must be at least 278")
    command = [sys.executable, str(ROOT / "tools/zig.py"), "build", "run", "-Doptimize=ReleaseFast",
               f"-Dbenchmark-frames={args.frames}", f"-Dseed={args.seed}", f"-Dupload-budget-kib={args.upload_budget_kib}"]
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=os.name != "nt")
    try:
        output, _ = process.communicate(timeout=args.timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        if os.name != "nt":
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            if os.name != "nt":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
            process.communicate()
        raise SystemExit("Benchmark interrupted or timed out; no successful report written")
    print(output, end="")
    if process.returncode:
        raise SystemExit(process.returncode)
    records = [json.loads(line.split("BENCHMARK ", 1)[1]) for line in output.splitlines() if "BENCHMARK {" in line]
    if len(records) != 1:
        raise SystemExit("Expected exactly one benchmark result")
    result = records[0]
    checks = {
        "frames_complete": result["frames"] == args.frames,
        "upload_budget_respected": result["peak_upload_bytes"] <= result["upload_budget_bytes"],
        "gpu_residency_bounded": result["peak_resident_chunks"] <= 25,
        "pool_allocations_bounded": result["pool_allocations"] == 2 and result["gpu_pool_allocations"] == 50,
        "streaming_exercised": result["chunk_crossings"] >= 30 and result["evictions"] > 0 and result["uploads"] > 25,
        "active_ring_covered": result["underfilled_frames"] == 0,
        # macOS throttles occluded or backgrounded windows to ~1 Hz; such runs are not representative.
        "presentation_unthrottled": result["interval_p99_ms"] < 100,
    }
    report = {"timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "host": platform.platform(), "machine": platform.machine(), "optimize": "ReleaseFast",
              "zig": "0.16.0-dev.3142+5ccfeb926", "mach": "7ed0d504a9569fd4ad840ecb10ead16b90a8926e",
              "warmup_frames": 60, "checks": checks, "metrics": result, "log": output}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Report: {args.output}")
    if not all(checks.values()):
        raise SystemExit("Benchmark checks failed: " + ", ".join(k for k, passed in checks.items() if not passed))


if __name__ == "__main__":
    main()
