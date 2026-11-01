#!/usr/bin/env python3
"""Capture genuine bilingual iPhone or 13-inch iPad home screens from Release Simulator."""

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
                return str(device.get("name", "Apple Simulator"))
    raise RuntimeError("The requested Simulator device is not available.")


def bundle_identifier(app_path: Path) -> str:
    info_plist = app_path / "Info.plist"
    result = run(
        ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier", str(info_plist)],
        capture_output=True,
    )
    identifier = result.stdout.strip()
    if not identifier:
        raise RuntimeError("The Release Simulator app has no bundle identifier.")
    return identifier


def image_dimensions(image_path: Path, *, platform: str) -> tuple[int, int]:
    result = run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(image_path)], capture_output=True)
    width = re.search(r"pixelWidth:\s*(\d+)", result.stdout)
    height = re.search(r"pixelHeight:\s*(\d+)", result.stdout)
    if width is None or height is None:
        raise RuntimeError("Could not read the captured screenshot dimensions.")
    dimensions = int(width.group(1)), int(height.group(1))
    if dimensions[1] <= dimensions[0] or dimensions[1] < 1_000:
        raise RuntimeError(f"Expected a portrait {platform} screenshot, found {dimensions[0]}×{dimensions[1]}.")
    if platform == "iPad" and dimensions not in {(2064, 2752), (2048, 2732)}:
        raise RuntimeError(f"Expected an App Store 13-inch iPad size, found {dimensions[0]}×{dimensions[1]}.")
    return dimensions


def capture_language(
    device_id: str,
    identifier: str,
    output_path: Path,
    *,
    japanese: bool,
    platform: str,
) -> tuple[int, int]:
    language_arguments = ["--factorytools-screenshot-demo"]
    if japanese:
        language_arguments.append("--factorytools-screenshot-japanese")
    run(
        [
            "xcrun", "simctl", "launch", "--terminate-running-process", device_id,
            identifier, *language_arguments,
        ]
    )
    # Allow SwiftUI's first layout and the locale-specific navigation title to settle.
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
    return image_dimensions(output_path, platform=platform)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--platform", choices=("iphone", "ipad"), default="iphone")
    arguments = parser.parse_args()

    if not arguments.app.is_dir():
        parser.error(f"Release Simulator app does not exist: {arguments.app}")
    device = simulator_name(arguments.device_id)
    platform_label = "iPad" if arguments.platform == "ipad" else "iPhone"
    if arguments.platform == "ipad" and "13-inch" not in device:
        parser.error(f"A 13-inch iPad Simulator is required; found {device}.")
    identifier = bundle_identifier(arguments.app)
    arguments.output_dir.mkdir(parents=True, exist_ok=True)

    run(["xcrun", "simctl", "bootstatus", arguments.device_id, "-b"])
    status_bar_arguments = [
        "xcrun", "simctl", "status_bar", arguments.device_id, "override",
        "--time", "9:41", "--wifiMode", "active", "--wifiBars", "3",
        "--batteryState", "charged", "--batteryLevel", "100",
    ]
    if arguments.platform == "iphone":
        status_bar_arguments.extend(["--dataNetwork", "wifi", "--cellularMode", "active", "--cellularBars", "4"])
    run(status_bar_arguments)
    # xcodebuild build does not install its product; replace the Debug app that
    # the preceding XCTest step may have left on this Simulator with Release.
    run(["xcrun", "simctl", "install", arguments.device_id, str(arguments.app)])
    captures = {
        f"{arguments.platform}-home-en.jpg": capture_language(
            arguments.device_id,
            identifier,
            arguments.output_dir / f"{arguments.platform}-home-en.jpg",
            japanese=False,
            platform=platform_label,
        ),
        f"{arguments.platform}-home-ja.jpg": capture_language(
            arguments.device_id,
            identifier,
            arguments.output_dir / f"{arguments.platform}-home-ja.jpg",
            japanese=True,
            platform=platform_label,
        ),
    }
    metadata = [
        f"Factory Tools App Store {platform_label} screenshot capture",
        f"Simulator: {device}",
        f"Bundle ID: {identifier}",
        "Build configuration: Release Simulator; demo data uses an in-memory store and is compiled only for Simulator.",
    ]
    for filename, (width, height) in captures.items():
        metadata.append(f"{filename}: {width}×{height} JPEG")
    if run_id := os.environ.get("GITHUB_RUN_ID"):
        metadata.append(f"GitHub Actions run: {run_id}")
    (arguments.output_dir / "capture-info.txt").write_text("\n".join(metadata) + "\n", encoding="utf-8")
    print(f"Captured {len(captures)} bilingual {platform_label} screenshots from {device}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
