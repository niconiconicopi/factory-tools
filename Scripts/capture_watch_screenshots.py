#!/usr/bin/env python3
"""Capture bilingual App Store screenshots from the Release Apple Watch Simulator app."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

COMMAND_TIMEOUT_SECONDS = 300
MAX_SCREENSHOT_ATTEMPTS = 3
WATCH_SCREENSHOT_VERIFIER = Path(__file__).with_name("verify_watch_screenshot.swift")


def run(arguments: list[str], *, capture_output: bool = False) -> subprocess.CompletedProcess[str]:
    print(f"Running Watch capture command: {shlex.join(arguments)}", flush=True)
    try:
        result = subprocess.run(
            arguments,
            check=False,
            text=True,
            capture_output=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        command = shlex.join(arguments)
        raise RuntimeError(
            f"Watch capture command timed out after {COMMAND_TIMEOUT_SECONDS} seconds: {command}"
        ) from error
    if not capture_output:
        if result.stdout:
            print(result.stdout, end="", flush=True)
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr, flush=True)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            arguments,
            output=result.stdout,
            stderr=result.stderr,
        )
    return result


def record_failure_summary(error: Exception) -> None:
    annotation = f"{type(error).__name__}: {error}"
    if isinstance(error, subprocess.CalledProcessError):
        command_output = (error.stderr or error.stdout or "").strip()
        if command_output:
            annotation += "\n" + command_output[-1_200:]
    annotation = annotation[:1_800]
    annotation = (
        annotation.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
        .replace(":", "%3A")
        .replace(",", "%2C")
    )
    print(f"::error title=Apple Watch screenshot capture failure::{annotation}", flush=True)

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return

    lines = ["## Apple Watch screenshot capture failure", "", f"{type(error).__name__}: {error}"]
    if isinstance(error, subprocess.CalledProcessError):
        lines.extend(["", f"Command: `{shlex.join(error.cmd)}`"])
        if error.stdout:
            lines.extend(["", "### Command output", "```text", error.stdout.rstrip(), "```"])
        if error.stderr:
            lines.extend(["", "### Command error", "```text", error.stderr.rstrip(), "```"])
    lines.append("")
    with Path(summary_path).open("a", encoding="utf-8") as summary:
        summary.write("\n".join(lines))


def simulator_name(device_id: str) -> str:
    result = run(["xcrun", "simctl", "list", "devices", "--json"], capture_output=True)
    inventory = json.loads(result.stdout)
    for devices in inventory.get("devices", {}).values():
        for device in devices:
            if device.get("udid") == device_id:
                return str(device.get("name", "Apple Watch Simulator"))
    raise RuntimeError("The requested Apple Watch Simulator device is not available.")


def bundle_identifier(app_path: Path) -> str:
    result = run(
        ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier", str(app_path / "Info.plist")],
        capture_output=True,
    )
    identifier = result.stdout.strip()
    if not identifier:
        raise RuntimeError("The Release Watch Simulator app has no bundle identifier.")
    return identifier


def image_dimensions(image_path: Path) -> tuple[int, int]:
    result = run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(image_path)], capture_output=True)
    width = re.search(r"pixelWidth:\s*(\d+)", result.stdout)
    height = re.search(r"pixelHeight:\s*(\d+)", result.stdout)
    if width is None or height is None:
        raise RuntimeError("Could not read the Apple Watch screenshot dimensions.")
    dimensions = int(width.group(1)), int(height.group(1))
    if dimensions != (416, 496):
        raise RuntimeError(f"Expected a 416×496 Apple Watch screenshot, found {dimensions[0]}×{dimensions[1]}.")
    return dimensions


def capture_language(device_id: str, identifier: str, output_path: Path, *, japanese: bool) -> tuple[int, int]:
    launch_arguments = ["--factorytools-screenshot-demo"]
    if japanese:
        launch_arguments.append("--factorytools-screenshot-japanese")
    temporary_png = output_path.with_suffix(".png")

    for attempt in range(1, MAX_SCREENSHOT_ATTEMPTS + 1):
        print(
            f"Launching {'Japanese' if japanese else 'English'} Watch counter detail "
            f"(attempt {attempt}/{MAX_SCREENSHOT_ATTEMPTS}).",
            flush=True,
        )
        run(["xcrun", "simctl", "launch", "--terminate-running-process", device_id, identifier, *launch_arguments])
        # Give WatchKit's scene/activation changes and numeric content time to settle.
        time.sleep(20)
        print(f"Capturing {output_path.name}.", flush=True)
        run(["xcrun", "simctl", "io", device_id, "screenshot", str(temporary_png)])
        run([
            "sips", "-s", "format", "jpeg", "-s", "formatOptions", "95",
            str(temporary_png), "--out", str(output_path),
        ])
        try:
            verification = run(
                ["swift", str(WATCH_SCREENSHOT_VERIFIER), str(output_path), "286", "300"],
                capture_output=True,
            )
        except subprocess.CalledProcessError as error:
            recognized = (error.stderr or error.stdout or "").strip()
            temporary_png.unlink(missing_ok=True)
            output_path.unlink(missing_ok=True)
            if attempt == MAX_SCREENSHOT_ATTEMPTS:
                raise RuntimeError(
                    f"{output_path.name} did not show count and target after "
                    f"{MAX_SCREENSHOT_ATTEMPTS} captures. {recognized}"
                ) from error
            print(f"Counter text was not visible; restarting Watch Simulator. {recognized}", flush=True)
            restart_simulator(device_id)
            continue

        print(verification.stdout.strip(), flush=True)
        temporary_png.unlink()
        break

    if not output_path.is_file() or output_path.stat().st_size < 10_000:
        raise RuntimeError(f"Screenshot output is missing or unexpectedly small: {output_path.name}")
    with output_path.open("rb") as stream:
        if stream.read(2) != b"\xff\xd8":
            raise RuntimeError(f"Screenshot is not a JPEG image: {output_path.name}")
    return image_dimensions(output_path)


def restart_simulator(device_id: str) -> None:
    """Start a locale capture from a clean watchOS Simulator session."""
    print("Restarting Apple Watch Simulator for a clean locale capture.", flush=True)
    run(["xcrun", "simctl", "shutdown", device_id])
    run(["xcrun", "simctl", "boot", device_id])
    run(["xcrun", "simctl", "bootstatus", device_id, "-b"])


def print_screenshot_diagnostics(device_id: str) -> None:
    """Print simulator-only Watch rendering state without changing the captured UI."""
    print("Reading Watch screenshot rendering-state diagnostics.", flush=True)
    try:
        result = run(
            [
                "xcrun", "simctl", "spawn", device_id,
                "log", "show", "--last", "2m", "--style", "compact",
                "--predicate", 'subsystem == "com.factorytools.watch" AND category == "ScreenshotCapture"',
            ],
            capture_output=True,
        )
    except subprocess.CalledProcessError as error:
        output = (error.stderr or error.stdout or "").strip()
        print(f"Watch rendering-state diagnostics unavailable: {output or error}", flush=True)
        return
    if result.stdout.strip():
        print(result.stdout, flush=True)
    else:
        print("No Watch rendering-state records were emitted.", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    arguments = parser.parse_args()
    if not arguments.app.is_dir():
        parser.error(f"Release Watch Simulator app does not exist: {arguments.app}")

    device = simulator_name(arguments.device_id)
    if "46mm" not in device:
        parser.error(f"A 46mm Apple Watch Simulator is required; found {device}.")
    identifier = bundle_identifier(arguments.app)
    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Booting 46mm Apple Watch Simulator: {device}.", flush=True)
    run(["xcrun", "simctl", "bootstatus", arguments.device_id, "-b"])
    # watchOS Simulator does not support simctl status_bar overrides.
    # Install the Release build explicitly; the preceding Watch build step alone does not install it.
    print("Installing the Release Watch app.", flush=True)
    run(["xcrun", "simctl", "install", arguments.device_id, str(arguments.app)])
    # The Debug-to-Release switch can leave the first locale on a stale WatchKit
    # session. Start both language captures from the same clean simulator state.
    restart_simulator(arguments.device_id)
    # Capture both locales in one boot so any first/second boot transition cannot
    # be mistaken for a locale-specific rendering problem.
    captures = {
        "watch-home-ja.jpg": capture_language(
            arguments.device_id, identifier, arguments.output_dir / "watch-home-ja.jpg", japanese=True
        )
    }
    captures["watch-home-en.jpg"] = capture_language(
        arguments.device_id, identifier, arguments.output_dir / "watch-home-en.jpg", japanese=False
    )
    print_screenshot_diagnostics(arguments.device_id)
    metadata = [
        "Factory Tools App Store Apple Watch screenshot capture",
        f"Simulator: {device}",
        f"Bundle ID: {identifier}",
        "Build configuration: Release Watch Simulator; counter data is in-memory and simulator-only.",
    ]
    for filename, (width, height) in captures.items():
        metadata.append(f"{filename}: {width}×{height} JPEG")
    if run_id := os.environ.get("GITHUB_RUN_ID"):
        metadata.append(f"GitHub Actions run: {run_id}")
    (arguments.output_dir / "capture-info.txt").write_text("\n".join(metadata) + "\n", encoding="utf-8")
    print(f"Captured {len(captures)} bilingual Apple Watch screenshots from {device}.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        record_failure_summary(error)
        raise
