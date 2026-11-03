#!/usr/bin/env python3
"""Capture genuine localized App Store screens from an iPhone or 13-inch iPad Release Simulator."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
import uuid
from pathlib import Path

SCREENSHOT_SCENARIOS = ("home", "cycle-time", "takt-time", "defect-counter", "counter-history")
COMMAND_TIMEOUT_SECONDS = 900
HOME_READINESS_TIMEOUT_SECONDS = 30
HOME_READINESS_COMMAND_TIMEOUT_SECONDS = 10
HOME_SCREENSHOT_ATTEMPTS = 3
HOME_RENDER_SETTLE_SECONDS = 3
HOME_SCREENSHOT_VERIFIER = Path(__file__).with_name("verify_simulator_home_screenshot.swift")


def run(
    arguments: list[str],
    *,
    capture_output: bool = False,
    timeout_seconds: int = COMMAND_TIMEOUT_SECONDS,
) -> subprocess.CompletedProcess[str]:
    print(f"Running simulator capture command: {' '.join(arguments)}", flush=True)
    try:
        return subprocess.run(
            arguments,
            check=True,
            text=True,
            capture_output=capture_output,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as error:
        command = " ".join(arguments)
        raise RuntimeError(
            f"Simulator capture command timed out after {timeout_seconds} seconds: {command}"
        ) from error


def simulator_name(device_id: str) -> str:
    result = run(["xcrun", "simctl", "list", "devices", "--json"], capture_output=True)
    inventory = json.loads(result.stdout)
    for devices in inventory.get("devices", {}).values():
        for device in devices:
            if device.get("udid") == device_id:
                return str(device.get("name", "Apple Simulator"))
    raise RuntimeError("The requested Simulator device is not available.")


def ensure_simulator_booted(device_id: str) -> None:
    result = run(["xcrun", "simctl", "list", "devices", "--json"], capture_output=True)
    inventory = json.loads(result.stdout)
    state = next(
        (device.get("state") for devices in inventory.get("devices", {}).values()
         for device in devices if device.get("udid") == device_id),
        None,
    )
    if state is None:
        raise RuntimeError("The requested Simulator device is not available.")
    if state != "Booted":
        run(["xcrun", "simctl", "boot", device_id])
    run(["xcrun", "simctl", "bootstatus", device_id, "-b"])


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


def clear_capture_outputs(output_dir: Path, *, platform: str) -> None:
    """Remove only known screenshot outputs so a partial run cannot upload stale images."""
    output_dir.mkdir(parents=True, exist_ok=True)
    for scenario in SCREENSHOT_SCENARIOS:
        for language in ("en", "ja"):
            stem = f"{platform}-{scenario}-{language}"
            for suffix in (".jpg", ".png"):
                (output_dir / f"{stem}{suffix}").unlink(missing_ok=True)
    (output_dir / "capture-info.txt").unlink(missing_ok=True)


def wait_for_home_demo_data(device_id: str, *, language_code: str, capture_id: str) -> None:
    """Wait until the real SwiftData-backed counter query has reached the demo values."""
    deadline = time.monotonic() + HOME_READINESS_TIMEOUT_SECONDS
    print("Waiting for the simulator home counter query to load.", flush=True)
    while time.monotonic() < deadline:
        result = run(
            [
                "xcrun", "simctl", "spawn", device_id,
                "log", "show", "--last", "2m", "--style", "compact",
                "--predicate", 'subsystem == "com.factorytools.ios" AND category == "ScreenshotCapture"',
            ],
            capture_output=True,
            timeout_seconds=HOME_READINESS_COMMAND_TIMEOUT_SECONDS,
        )
        ready_line = any(
            f"captureID={capture_id}" in line
            and f"locale={language_code}" in line
            and "current=286 target=300" in line
            for line in result.stdout.splitlines()
        )
        if ready_line:
            print("SwiftData-backed home counter values are ready.", flush=True)
            return
        time.sleep(2)
    raise RuntimeError(
        f"The simulator home counter did not reach 286/300 within {HOME_READINESS_TIMEOUT_SECONDS} seconds."
    )


def capture_language(
    device_id: str,
    identifier: str,
    output_path: Path,
    *,
    japanese: bool,
    platform: str,
    scenario: str,
) -> tuple[int, int]:
    language = "ja" if japanese else "en"
    language_arguments = ["--factorytools-screenshot-demo"]
    if japanese:
        language_arguments.append("--factorytools-screenshot-japanese")
    language_arguments.append(f"--factorytools-screenshot-{scenario}")
    temporary_png = output_path.with_suffix(".png")
    attempts = HOME_SCREENSHOT_ATTEMPTS if scenario == "home" else 1
    for attempt in range(1, attempts + 1):
        capture_id = uuid.uuid4().hex
        capture_arguments = [f"--factorytools-screenshot-capture-id={capture_id}"]
        print(
            f"Launching {language} {platform} {scenario} screenshot (attempt {attempt}/{attempts}).",
            flush=True,
        )
        run(
            [
                "xcrun", "simctl", "launch", "--terminate-running-process", device_id,
                identifier, *language_arguments, *capture_arguments,
            ]
        )
        if scenario == "home":
            try:
                wait_for_home_demo_data(device_id, language_code=language, capture_id=capture_id)
            except RuntimeError as error:
                print(
                    f"Simulator readiness logs were unavailable; the final image OCR will decide capture readiness. {error}",
                    flush=True,
                )
            time.sleep(HOME_RENDER_SETTLE_SECONDS)
        else:
            # Allow SwiftUI's first layout and the locale-specific navigation title to settle.
            time.sleep(4)
        run(["xcrun", "simctl", "io", device_id, "screenshot", str(temporary_png)])
        run([
            "sips", "-s", "format", "jpeg", "-s", "formatOptions", "95",
            str(temporary_png), "--out", str(output_path),
        ])
        if scenario == "home":
            try:
                verification = run(
                    ["swift", str(HOME_SCREENSHOT_VERIFIER), str(output_path), "286", "300"],
                    capture_output=True,
                )
            except subprocess.CalledProcessError as error:
                recognized = (error.stderr or error.stdout or "").strip()
                temporary_png.unlink(missing_ok=True)
                if attempt == attempts:
                    raise RuntimeError(
                        f"{output_path.name} did not show both home counter values after {attempts} captures. "
                        f"Diagnostic JPEG retained at {output_path}. {recognized}"
                    ) from error
                output_path.unlink(missing_ok=True)
                print(f"Home counter values were not visible; relaunching the app. {recognized}", flush=True)
                continue
            print(verification.stdout.strip(), flush=True)
        temporary_png.unlink()
        break
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
    parser.add_argument(
        "--scenarios",
        nargs="+",
        choices=SCREENSHOT_SCENARIOS,
        default=["home"],
    )
    arguments = parser.parse_args()

    if not arguments.app.is_dir():
        parser.error(f"Release Simulator app does not exist: {arguments.app}")
    device = simulator_name(arguments.device_id)
    platform_label = "iPad" if arguments.platform == "ipad" else "iPhone"
    if arguments.platform == "ipad" and "13-inch" not in device:
        parser.error(f"A 13-inch iPad Simulator is required; found {device}.")
    identifier = bundle_identifier(arguments.app)
    clear_capture_outputs(arguments.output_dir, platform=arguments.platform)

    ensure_simulator_booted(arguments.device_id)
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
    if len(arguments.scenarios) != len(set(arguments.scenarios)):
        parser.error("Each screenshot scenario may be requested only once.")
    captures: dict[str, tuple[int, int]] = {}
    for scenario in arguments.scenarios:
        for japanese, language in ((False, "en"), (True, "ja")):
            filename = f"{arguments.platform}-{scenario}-{language}.jpg"
            captures[filename] = capture_language(
                arguments.device_id,
                identifier,
                arguments.output_dir / filename,
                japanese=japanese,
                platform=platform_label,
                scenario=scenario,
            )
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
    print(f"Captured {len(captures)} {platform_label} Release Simulator screenshots from {device}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
