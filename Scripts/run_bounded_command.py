#!/usr/bin/env python3
"""Run a command with a wall-clock limit while forwarding its output."""

from __future__ import annotations

import argparse
import os
import queue
import signal
import subprocess
import sys
import threading
import time


def terminate_process_group(process: subprocess.Popen[str]) -> None:
    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    else:
        process.terminate()

    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        if os.name == "posix":
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        else:
            process.kill()
        process.wait()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout-seconds", type=int, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if args.timeout_seconds < 1 or not command:
        parser.error("a positive timeout and command are required")

    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=(os.name == "posix"),
        )
    except OSError as error:
        print(f"Could not start command: {error}", file=sys.stderr, flush=True)
        return 127

    output: queue.Queue[str | None] = queue.Queue()

    def forward_output() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            output.put(line)
        output.put(None)

    reader = threading.Thread(target=forward_output, daemon=True)
    reader.start()
    deadline = time.monotonic() + args.timeout_seconds
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            print(
                f"Command exceeded its {args.timeout_seconds}-second limit; terminating it for diagnostics.",
                file=sys.stderr,
                flush=True,
            )
            terminate_process_group(process)
            reader.join(timeout=5)
            while True:
                try:
                    line = output.get_nowait()
                except queue.Empty:
                    break
                if line is not None:
                    sys.stdout.write(line)
            return 124

        try:
            line = output.get(timeout=remaining)
        except queue.Empty:
            continue
        if line is None:
            return process.wait()
        sys.stdout.write(line)
        sys.stdout.flush()


if __name__ == "__main__":
    raise SystemExit(main())
