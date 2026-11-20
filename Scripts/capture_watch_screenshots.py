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
import uuid
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


def simulator_configuration(device_id: str) -> tuple[str, str, str]:
    result = run(["xcrun", "simctl", "list", "devices", "--json"], capture_output=True)
    inventory = json.loads(result.stdout)
    for runtime_identifier, devices in inventory.get("devices", {}).items():
        for device in devices:
            if device.get("udid") == device_id:
                name = str(device.get("name", "Apple Watch Simulator"))
                device_type_value = device.get("deviceTypeIdentifier")
                if not device_type_value:
                    raise RuntimeError("The selected Apple Watch Simulator has no device type identifier.")
                device_type = str(device_type_value)
                return name, device_type, str(runtime_identifier)
    raise RuntimeError("The requested Apple Watch Simulator device is not available.")


def simulator_state(device_id: str) -> str:
    result = run(["xcrun", "simctl", "list", "devices", "--json"], capture_output=True)
    inventory = json.loads(result.stdout)
    for devices in inventory.get("devices", {}).values():
        for device in devices:
            if device.get("udid") == device_id:
                return str(device.get("state", "Unknown"))
    raise RuntimeError("The requested Apple Watch Simulator device is not available.")


def create_capture_simulator(device_type: str, runtime_identifier: str, language: str) -> str:
    name = f"Factory Tools {language} {uuid.uuid4().hex[:8]}"
    result = run(
        ["xcrun", "simctl", "create", name, device_type, runtime_identifier],
        capture_output=True,
    )
    simulator_id = result.stdout.strip()
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", simulator_id):
        raise RuntimeError("Could not create an independent Apple Watch Simulator for the second locale.")
    return simulator_id


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


def verify_counter_content(image_path: Path) -> bool:
    verifier = Path(__file__).with_name("verify_watch_screenshot.swift")
    if not verifier.is_file():
        raise RuntimeError("The Apple Watch screenshot content verifier is missing.")
    try:
        run(["swift", str(verifier), str(image_path)], capture_output=True)
    except subprocess.CalledProcessError as error:
        diagnostic = error.stderr or error.output or ""
        if "Apple Watch screenshot is missing expected demo values:" in diagnostic:
            return False
        raise
    return True


def capture_language(device_id: str, identifier: str, output_path: Path, *, japanese: bool) -> tuple[int, int]:
    launch_arguments = ["--factorytools-screenshot-demo"]
    if japanese:
        launch_arguments.append("--factorytools-screenshot-japanese")
    print(f"Launching {'Japanese' if japanese else 'English'} Watch counter detail.", flush=True)
    run(["xcrun", "simctl", "launch", "--terminate-running-process", device_id, identifier, *launch_arguments])
    # Each locale gets a fresh simulator. Capture promptly so Always On does not
    # enter its dimmed presentation and suppress the counter/progress content.
    time.sleep(3)
    temporary_png = output_path.with_suffix(".png")
    print(f"Capturing {output_path.name}.", flush=True)
    for attempt in range(20):
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
        dimensions = image_dimensions(output_path)
        if verify_counter_content(output_path):
            return dimensions
        if attempt < 19:
            print("Waiting for the Watch counter to finish rendering before retrying capture.", flush=True)
            time.sleep(1)
    raise RuntimeError(f"The Watch counter values did not render in {output_path.name} after 20 captures.")


def boot_simulator(device_id: str, *, clean: bool) -> None:
    """Boot a dedicated watchOS Simulator for one locale capture."""
    state = simulator_state(device_id)
    if clean:
        if state == "Booted":
            print("Restarting the primary Apple Watch Simulator for a clean capture.", flush=True)
            run(["xcrun", "simctl", "shutdown", device_id])
        elif state != "Shutdown":
            raise RuntimeError(f"The primary Apple Watch Simulator is in an unexpected state: {state}.")
    else:
        print("Booting an independent Apple Watch Simulator for the second locale.", flush=True)
        if state != "Shutdown":
            raise RuntimeError(f"The independent Apple Watch Simulator should be shut down before capture; found {state}.")
    run(["xcrun", "simctl", "boot", device_id])
    run(["xcrun", "simctl", "bootstatus", device_id, "-b"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    arguments = parser.parse_args()
    if not arguments.app.is_dir():
        parser.error(f"Release Watch Simulator app does not exist: {arguments.app}")

    device, device_type, runtime_identifier = simulator_configuration(arguments.device_id)
    if "46mm" not in device:
        parser.error(f"A 46mm Apple Watch Simulator is required; found {device}.")
    identifier = bundle_identifier(arguments.app)
    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    english_device_id = create_capture_simulator(device_type, runtime_identifier, "English")
    captures = {}
    try:
        print(f"Booting independent locale simulators from 46mm device type: {device}.", flush=True)
        for device_id, filename, japanese, clean in (
            (arguments.device_id, "watch-home-ja.jpg", True, True),
            (english_device_id, "watch-home-en.jpg", False, False),
        ):
            boot_simulator(device_id, clean=clean)
            print(f"Installing the Release Watch Simulator app for {filename}.", flush=True)
            run(["xcrun", "simctl", "install", device_id, str(arguments.app)])
            captures[filename] = capture_language(
                device_id,
                identifier,
                arguments.output_dir / filename,
                japanese=japanese,
            )
    finally:
        print("Removing the temporary Apple Watch Simulator.", flush=True)
        if simulator_state(english_device_id) != "Shutdown":
            run(["xcrun", "simctl", "shutdown", english_device_id])
        run(["xcrun", "simctl", "delete", english_device_id])
    metadata = [
        "Factory Tools App Store Apple Watch screenshot capture",
        f"Simulator: {device}",
        f"Bundle ID: {identifier}",
        "Build configuration: Release Watch Simulator; each locale used an independent simulator; demo data is in-memory only.",
        "Screenshot content: Apple Vision OCR verified counter 286 and target 300 in each locale.",
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
