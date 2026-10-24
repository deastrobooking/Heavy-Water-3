#!/usr/bin/env python3
"""Compare four fixed-scene limiter variants; retain logs and reject changed draw workloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def records(output, tag):
    return [json.loads(line.split(tag + ' ', 1)[1]) for line in output.splitlines() if tag + ' {' in line]


def source_hash():
    digest = hashlib.sha256()
    paths = [ROOT / 'build.zig', ROOT / 'tools/limiter.py']
    for folder in ('src', 'vendor/mach/src'):
        paths.extend(path for path in (ROOT / folder).rglob('*') if path.suffix in ('.zig', '.wgsl'))
    for path in sorted(paths):
        digest.update(str(path.relative_to(ROOT)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frames', type=int, default=600)
    parser.add_argument('--repeats', type=int, default=2)
    parser.add_argument('--timeout', type=int, default=1200)
    parser.add_argument('--output', type=Path, default=ROOT / 'zig-out/limiter')
    args = parser.parse_args()
    if not 120 <= args.frames <= 4096 or args.repeats < 1:
        parser.error('frames must be 120..4096 and repeats must be positive')
    args.output.mkdir(parents=True, exist_ok=True)
    variants = [('baseline', False, False), ('pixels', True, False), ('simulation', False, True), ('both', True, True)]
    results = []
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    source = source_hash()
    for repeat in range(args.repeats):
        # Reverse alternate rounds to expose warm-cache/order effects.
        for name, half, skip in (variants if repeat % 2 == 0 else list(reversed(variants))):
            if source_hash() != source:
                raise SystemExit('Source changed during the experiment; run in an isolated worktree')
            command = [sys.executable, 'tools/zig.py', 'build', 'run', '-Doptimize=ReleaseFast',
                       '-Dbenchmark-frontier=true', '-Dbenchmark-limiter=true', '-Daudio=false',
                       f'-Dbenchmark-frames={args.frames}', f'-Dlimiter-half-resolution={str(half).lower()}',
                       f'-Dlimiter-skip-sim={str(skip).lower()}', '-Dseed=310399555161']
            path = args.output / f'{repeat + 1}-{name}.log'
            print(f'Running {name}, round {repeat + 1}; log {path}', flush=True)
            with path.open('w') as log:
                process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=args.timeout)
                except (subprocess.TimeoutExpired, KeyboardInterrupt):
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait()
                    raise SystemExit('Limiter run interrupted/timed out; comparison is incomplete')
            if code:
                raise SystemExit(f'{name} exited {code}; see {path}')
            text = path.read_text()
            data = {'variant': name, 'round': repeat + 1}
            for tag in ('BENCHMARK', 'REPORT', 'APPBENCH', 'LIMITER'):
                found = records(text, tag)
                if len(found) != 1:
                    raise SystemExit(f'Expected one {tag} in {path}')
                data.update(found[0])
            results.append(data)
            print(f"  frame mean {data['frame_mean_ms']:.3f} ms; CPU {data['cpu_p50_ms']:.3f}; GPU {data['gpu_time_p50_ms']:.3f}", flush=True)
    baseline = results[0]
    same_workload = all(all(row[k] == baseline[k] for k in ('snapshot_hash', 'snapshot_tick', 'props', 'triangles', 'terrain_draws', 'solid_batches', 'views')) for row in results)
    valid = same_workload and baseline['snapshot_tick'] == 120 and baseline['views'] == 4
    valid = valid and all(row['triangles_min'] == row['triangles_max'] and row['missing_frames_all_views'] == 0 for row in results)
    valid = valid and all(row['width'] == baseline['width'] // (2 if row['variant'] in ('pixels', 'both') else 1) and row['height'] == baseline['height'] // (2 if row['variant'] in ('pixels', 'both') else 1) for row in results)
    valid = valid and all((row['sim_steps'] == 0) == row['skip_sim'] for row in results)
    valid = valid and all(row['gpu_time_available'] and row['gpu_time_samples'] >= 30 and row['interval_p99_ms'] < 100 and row['frames'] == args.frames for row in results)
    medians = {name: {key: statistics.median(row[key] for row in results if row['variant'] == name)
                      for key in ('frame_mean_ms', 'interval_p50_ms', 'interval_p95_ms', 'cpu_p50_ms', 'gpu_time_p50_ms', 'sim_p50_ms')}
               for name, _, _ in variants}
    base_frame = medians['baseline']['frame_mean_ms']
    reductions = {name: 100 * (1 - value['frame_mean_ms'] / base_frame) for name, value in medians.items() if name != 'baseline'}
    valid = valid and source_hash() == source
    report = {'revision': revision, 'source_sha256': source, 'valid_comparison': valid, 'same_draw_workload': same_workload, 'runs': results, 'medians': medians, 'frame_reduction_pct': reductions,
              'limits': 'Pixel reduction probes GPU raster/shading cost. Simulation bypass probes simulation cost only. Present pacing, thermal state and CPU/GPU resource contention can affect both; this does not isolate CPU command encoding or prove serialization.'}
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'valid_comparison': valid, 'frame_reduction_pct': reductions}, indent=2))
    if not valid:
        raise SystemExit('Workload/measurement validation failed; do not infer a limiter from this comparison')


if __name__ == '__main__':
    main()
