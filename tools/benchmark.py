#!/usr/bin/env python3
"""Run a fixed streaming or Arbor route and retain JSON counters plus host/toolchain context."""
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
    parser.add_argument("--canopy", action="store_true", help="View an Arbor up close, at 1 km, and back; check both LODs and render CPU budget")
    parser.add_argument("--arbor", type=int, choices=(0, 1, 2), default=0, help="Arbor on canopy route: 0 test, 1 narrow, 2 spreading (nonzero enables canopy)")
    parser.add_argument("--scale", type=int, default=0, help="Scale workload: N field objects on the streaming route (10000, 100000, 1000000)")
    parser.add_argument("--field-upload-kib", type=int, default=2048, help="Scale workload instance upload budget per frame")
    parser.add_argument("--seed", type=int, default=310399555161)
    parser.add_argument("--upload-budget-kib", type=int, default=320)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    args.canopy = args.canopy or args.arbor != 0
    if args.output is None:
        args.output = ROOT / ".tools" / (f"scale-{args.scale}-benchmark.json" if args.scale else f"canopy-{args.arbor}-benchmark.json" if args.canopy and args.arbor else "canopy-benchmark.json" if args.canopy else "streaming-benchmark.json")
    if args.scale and args.canopy:
        parser.error("--scale runs on the streaming route; do not combine it with --canopy or --arbor")
    if not 0 <= args.scale <= 4_000_000:
        parser.error("--scale must be 0..4000000")
    if not 120 <= args.frames <= 4096:
        parser.error("--frames must be 120..4096 so the complete measured run fits the percentile sample buffer")
    if args.upload_budget_kib < 278:
        parser.error("--upload-budget-kib must be at least 278")
    command = [sys.executable, str(ROOT / "tools/zig.py"), "build", "run", "-Doptimize=ReleaseFast",
               f"-Dbenchmark-frames={args.frames}", f"-Dbenchmark-canopy={str(args.canopy).lower()}", f"-Dbenchmark-arbor={args.arbor}", f"-Dseed={args.seed}", f"-Dupload-budget-kib={args.upload_budget_kib}", f"-Dscale-objects={args.scale}", f"-Dfield-upload-kib={args.field_upload_kib}"]
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
    # The renderer's REPORT line carries scale-workload and memory measurements.
    extra = [json.loads(line.split("REPORT ", 1)[1]) for line in output.splitlines() if "REPORT {" in line]
    if extra:
        result.update(extra[0])
    checks = {
        "frames_complete": result["frames"] == args.frames,
        "upload_budget_respected": result["peak_upload_bytes"] <= result["upload_budget_bytes"],
        "gpu_residency_bounded": result["peak_resident_chunks"] <= 25,
        "pool_allocations_bounded": result["pool_allocations"] == 2 and result["gpu_pool_allocations"] == 50,
        "streaming_exercised": result["chunk_crossings"] >= (12 if args.canopy else 30) and result["evictions"] > 0 and result["uploads"] > 25,
        "active_ring_covered": result["underfilled_frames"] == 0,
        # macOS throttles occluded or backgrounded windows to ~1 Hz; such runs are not representative.
        "presentation_unthrottled": result["interval_p99_ms"] < 100,
    }
    if args.canopy:
        checks["arbor_lods_exercised"] = result["arbor_detail_frames"] > 0 and result["arbor_proxy_frames"] > 0
        checks["render_cpu_budget"] = result["cpu_p99_ms"] < 16.667
    if args.scale:
        # The whole field must be resident before measuring starts, objects must draw, and the
        # CPU cost must stay within a 60 Hz frame however many objects there are.
        checks["field_resident_before_measuring"] = 0 <= result["field_resident_frame"] < 60
        checks["field_drawn"] = result["field_submitted_p50"] > 0 and result["field_runs_p99"] > 0
        checks["field_cpu_copy_freed"] = result["field_cpu_bytes_now"] == 0
        checks["render_cpu_budget"] = result["cpu_p99_ms"] < 16.667
    report = {"arbor": args.arbor, "scale_objects": args.scale, "route": "canopy" if args.canopy else "streaming", "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
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
