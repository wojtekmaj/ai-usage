#!/usr/bin/env python3
"""Capture the native macOS usage popover with isolated mock data."""

import argparse
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--skip-build", action="store_true", help="Use the existing app bundle")
parser.add_argument("--output", type=Path, default=Path("screenshot.png"))
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent

if not args.skip_build:
    subprocess.run([str(root / "scripts/build-app.sh")], cwd=root, check=True)

app = root / ".build/AI Usage.app/Contents/MacOS/AiUsageApp"
environment = dict(os.environ, AI_USAGE_SCREENSHOT_MODE="1")

with subprocess.Popen(
    [str(app)], cwd=root, env=environment, stdout=subprocess.PIPE, text=True
) as process:
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + 30
            window_id = None

            while time.monotonic() < deadline:
                if not selector.select(timeout=1):
                    continue

                line = process.stdout.readline()

                if line.startswith("Screenshot window: "):
                    window_id = line.strip().split(": ", 1)[1]
                    break

                if process.poll() is not None:
                    raise RuntimeError(f"The screenshot app exited with status {process.returncode}")

            if window_id is None:
                raise RuntimeError("The screenshot popover did not open within 30 seconds")

        time.sleep(2)
        output = args.output.resolve()

        with tempfile.TemporaryDirectory(dir=output.parent) as temporary_directory:
            capture = Path(temporary_directory) / "screenshot.png"
            subprocess.run(
                ["/usr/sbin/screencapture", "-x", "-l", window_id, str(capture)],
                check=True,
            )
            capture.replace(output)

        print(f"Saved {output}")
    finally:
        process.terminate()
        process.wait(timeout=10)
