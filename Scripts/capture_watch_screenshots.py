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


def run(arguments: list[str], *, capture_output: bool = False) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(arguments, check=False, text=True, capture_output=True)
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
    print(f"Launching {'Japanese' if japanese else 'English'} Watch counter detail.", flush=True)
    run(["xcrun", "simctl", "launch", "--terminate-running-process", device_id, identifier, *launch_arguments])
    # Give WatchKit and the numeric content transition time to settle after each locale relaunch.
    time.sleep(8)
    temporary_png = output_path.with_suffix(".png")
    print(f"Capturing {output_path.name}.", flush=True)
    run(["xcrun", "simctl", "io", device_id, "screenshot", str(temporary_png)])
    run([
        "sips", "-s", "format", "jpeg", "-s", "formatOptions", "95",
        str(temporary_png), "--out", str(output_path),
    ])
    temporary_png.unlink()
    if not output_path.is_file() or output_path.stat().st_size < 10_000:
        raise RuntimeError(f"Screenshot output is missing or unexpectedly small: {output_path.name}")
    with output_path.open("rb") as stream:
        if stream.read(2) != b"\xff\xd8":
            raise RuntimeError(f"Screenshot is not a JPEG image: {output_path.name}")
    return image_dimensions(output_path)


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
    captures = {
        "watch-home-en.jpg": capture_language(
            arguments.device_id, identifier, arguments.output_dir / "watch-home-en.jpg", japanese=False
        ),
        "watch-home-ja.jpg": capture_language(
            arguments.device_id, identifier, arguments.output_dir / "watch-home-ja.jpg", japanese=True
        ),
    }
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
