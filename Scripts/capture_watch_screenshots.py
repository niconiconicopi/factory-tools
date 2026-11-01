#!/usr/bin/env python3
"""Capture bilingual App Store screenshots from the Release Apple Watch Simulator app."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
from pathlib import Path


def run(arguments: list[str], *, capture_output: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, check=True, text=True, capture_output=capture_output)


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
    run(["xcrun", "simctl", "launch", "--terminate-running-process", device_id, identifier, *launch_arguments])
    time.sleep(4)
    temporary_png = output_path.with_suffix(".png")
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
    run(["xcrun", "simctl", "bootstatus", arguments.device_id, "-b"])
    run([
        "xcrun", "simctl", "status_bar", arguments.device_id, "override",
        "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
    ])
    # Install the Release build explicitly; the preceding Watch build step alone does not install it.
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
    raise SystemExit(main())
