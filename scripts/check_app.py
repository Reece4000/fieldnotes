#!/usr/bin/env python3
"""Smoke-test the packaged macOS executable with isolated, disposable data."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


def main():
    bundle = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/Fieldnotes.app').resolve()
    executable = bundle / 'Contents/MacOS/Fieldnotes'
    with tempfile.TemporaryDirectory(prefix='fieldnotes-launch-') as directory:
        with tempfile.TemporaryFile(mode='w+') as output:
            process = subprocess.Popen(
                [str(executable), '--compact'],
                env=dict(os.environ, FIELDNOTES_DATA_DIR=directory),
                stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
            )
            try:
                try:
                    code = process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    code = None
            finally:
                # Include the Python worker and model process in test cleanup.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            output.seek(0)
            diagnostics = output.read()
            if code is not None:
                print(f'FAIL: packaged app exited during startup (code {code}).', file=sys.stderr)
                print(diagnostics, file=sys.stderr)
                return 1
            print('PASS: packaged app launched and stayed running with isolated test data.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
