#!/usr/bin/env python3
"""Measure our own cold, hidden process. No credentials or user files are read by this script."""
import json
import subprocess
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
binary = root / "dist/Fast Music.app/Contents/MacOS/FastMusic"
process = subprocess.Popen([str(binary), "--no-show"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    # Settling time is part of the measurement protocol, not a build-job polling loop.
    time.sleep(3)
    samples = []
    for _ in range(12):
        line = subprocess.check_output(["ps", "-p", str(process.pid), "-o", "%cpu=,rss=,time="], text=True).strip()
        cpu, rss, cpu_time = line.split()
        samples.append({"cpu_percent": float(cpu), "rss_mib": round(int(rss) / 1024, 2), "cpu_time": cpu_time})
        time.sleep(1)
    print(json.dumps({"scenario": "cold launch, panel hidden, no audio; ps RSS (not physical footprint)", "samples": samples}, ensure_ascii=False, indent=2))
finally:
    process.terminate()
    process.wait(timeout=5)
