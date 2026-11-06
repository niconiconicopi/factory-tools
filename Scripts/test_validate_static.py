import io
import os
import struct
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from capture_watch_screenshots import capture_language as capture_watch_language
from capture_watch_screenshots import record_failure_summary, run as run_watch_capture_command
from capture_simulator_screenshots import capture_language as capture_simulator_language
from capture_simulator_screenshots import clear_capture_outputs, wait_for_home_demo_data
from validate_static import (
    DuplicateJSONKeyError,
    OpenStepParseError,
    apple_workflow_contract_errors,
    apple_archive_workflow_contract_errors,
    apple_storekit_workflow_contract_errors,
    apple_upload_workflow_contract_errors,
    pages_publication_workflow_contract_errors,
    apply_release_candidate_overrides,
    app_store_metadata_limit_errors,
    bypasses_app_theme_manager,
    in_app_purchase_metadata_limit_errors,
    is_opaque_png,
    is_valid_app_store_sku,
    is_valid_base_storefront_candidate,
    is_valid_price_candidate,
    bonjour_declaration_matches,
    contrast_ratio,
    family_sharing_decision,
    has_distinct_localized_copy,
    has_supported_ios_launch_screen,
    is_https_url,
    is_valid_storekit_product_id,
    local_markdown_link_errors,
    local_project_file_references,
    localized_info_plist_value,
    localization_placeholder_count,
    parse_json_no_duplicates,
    parse_openstep,
    release_preflight_blockers,
    release_preflight_configuration_blockers,
    resolve_family_sharing_candidate,
    storekit_configuration_errors,
    swiftui_unlocalized_copy_literals,
    swift_model_persisted_properties,
    swift_unsafe_escape_hatches,
)


class AppleWorkflowContractTests(unittest.TestCase):
    def test_current_workflow_obeys_public_no_cost_contract(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = "\n".join(
            (
                (root / ".github" / "workflows" / "apple-native-checks.yml").read_text(encoding="utf-8"),
                (root / ".github" / "workflows" / "apple-watch-archive-checks.yml").read_text(encoding="utf-8"),
            )
        )

        self.assertEqual(apple_workflow_contract_errors(workflow), [])

    def test_workflow_rejects_private_runner_or_secret_access(self) -> None:
        source = """if: github.event.repository.visibility == 'private'
permissions:
  contents: write
uses: actions/checkout@v7
  persist-credentials: true
runs-on: macos-26
run: xcodebuild test -scheme FactoryTools -scheme FactoryToolsCore -scheme FactoryToolsWatch CODE_SIGNING_ALLOWED=NO ${{ secrets.SIGNING_KEY }}
"""

        errors = apple_workflow_contract_errors(source)

        self.assertIn("missing public or manually confirmed private-run job condition", errors)
        self.assertIn("missing read-only repository permission", errors)
        self.assertIn("missing checkout credential persistence disabled", errors)
        self.assertIn("missing iPad Simulator regression suite", errors)
        self.assertIn("workflow must not access repository secrets", errors)


    def test_current_archive_workflow_is_manual_read_only_and_unsigned(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github" / "workflows" / "apple-archive-check.yml").read_text(encoding="utf-8")

        self.assertEqual(apple_archive_workflow_contract_errors(workflow), [])

    def test_archive_workflow_rejects_signing_secrets_and_push_triggers(self) -> None:
        source = """on:
  push:
permissions:
  contents: write
runs-on: macos-latest
run: xcodebuild archive -destination 'generic/platform=iOS' ${{ secrets.SIGNING_KEY }}
"""

        errors = apple_archive_workflow_contract_errors(source)

        self.assertIn("missing manual dispatch only", errors)
        self.assertIn("missing read-only repository permission", errors)
        self.assertIn("missing hosted macOS runner", errors)
        self.assertIn("archive verification workflow must not access repository secrets", errors)


    def test_current_storekit_probe_is_manual_public_free_and_ad_hoc_signed(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github" / "workflows" / "apple-storekit-local-test.yml").read_text(encoding="utf-8")

        self.assertEqual(apple_storekit_workflow_contract_errors(workflow), [])
        self.assertIn("runs-on: xcode-27", workflow)
        self.assertIn("xcrun simctl list runtimes", workflow)

    def test_storekit_probe_rejects_automatic_triggers_and_secrets(self) -> None:
        source = """on:
  push:
permissions:
  contents: write
runs-on: macos-latest
run: xcodebuild test -scheme FactoryTools CODE_SIGNING_ALLOWED=NO ${{ secrets.SIGNING_KEY }}
"""

        errors = apple_storekit_workflow_contract_errors(source)

        self.assertIn("missing manual dispatch only", errors)
        self.assertIn("missing read-only repository permission", errors)
        self.assertIn("StoreKit integration workflow must be manually dispatched only", errors)
        self.assertIn("StoreKit integration probe must allow simulator ad-hoc signing", errors)
        self.assertIn("StoreKit integration workflow must not access repository secrets", errors)

    def test_ipad_xctest_failures_write_result_summary_before_failing(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github" / "workflows" / "apple-native-checks.yml").read_text(encoding="utf-8")
        step_start = workflow.index("      - name: Test iPad and app-hosted regression suite")
        ipad_test = workflow[step_start:]

        self.assertIn('-resultBundlePath "$result_bundle"', ipad_test)
        self.assertIn('test_status=${PIPESTATUS[0]}', ipad_test)
        self.assertIn("xcresulttool get test-results summary --path", ipad_test)
        self.assertIn('>> "$GITHUB_STEP_SUMMARY"', ipad_test)
        self.assertIn('exit "$test_status"', ipad_test)
        self.assertIn("name: Upload iPad XCTest diagnostics", ipad_test)
        self.assertIn("factory-tools-ipad-xctest-diagnostics", ipad_test)
        self.assertIn("FactoryTools-iPad.xcresult", ipad_test)
        self.assertIn("FactoryTools-iPad-xcodebuild.log", ipad_test)
        self.assertIn('"13-inch" in device["name"]', ipad_test)
        self.assertIn('xcrun", "simctl", "bootstatus"', ipad_test)
        self.assertIn("-parallel-testing-enabled NO", ipad_test)


class WatchScreenshotDiagnosticsTests(unittest.TestCase):
    def test_capture_does_not_use_unsupported_watch_status_bar_override(self) -> None:
        source = (Path(__file__).resolve().parent / "capture_watch_screenshots.py").read_text(encoding="utf-8")

        self.assertNotIn('"status_bar"', source)

    def test_watch_simulator_boot_timeout_can_exceed_normal_command_timeout(self) -> None:
        with patch("capture_watch_screenshots.subprocess.run") as process_run:
            process_run.return_value = subprocess.CompletedProcess(["xcrun"], 0, stdout="ready", stderr="")
            run_watch_capture_command(["xcrun", "simctl", "bootstatus", "watch", "-b"], timeout_seconds=900)

        self.assertEqual(process_run.call_args.kwargs["timeout"], 900)

    def test_watch_capture_timeout_error_reports_the_selected_limit(self) -> None:
        with patch(
            "capture_watch_screenshots.subprocess.run",
            side_effect=subprocess.TimeoutExpired(["xcrun", "simctl", "bootstatus"], 900),
        ):
            with self.assertRaisesRegex(RuntimeError, "timed out after 900 seconds"):
                run_watch_capture_command(["xcrun", "simctl", "bootstatus"], timeout_seconds=900)

    def test_process_failure_summary_includes_command_and_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            summary_path = Path(temporary_directory) / "step-summary.md"
            previous_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
            os.environ["GITHUB_STEP_SUMMARY"] = str(summary_path)
            try:
                error = subprocess.CalledProcessError(
                    1,
                    ["xcrun", "simctl", "launch", "watch-simulator"],
                    output="launch started",
                    stderr="simulator refused launch: unavailable",
                )
                annotation = io.StringIO()
                with redirect_stdout(annotation):
                    record_failure_summary(error)
            finally:
                if previous_summary_path is None:
                    os.environ.pop("GITHUB_STEP_SUMMARY", None)
                else:
                    os.environ["GITHUB_STEP_SUMMARY"] = previous_summary_path

            summary = summary_path.read_text(encoding="utf-8")
            self.assertIn("Apple Watch screenshot capture failure", summary)
            self.assertIn("xcrun simctl launch watch-simulator", summary)
            self.assertIn("launch started", summary)
            self.assertIn("simulator refused launch: unavailable", summary)
            self.assertIn("::error title=Apple Watch screenshot capture failure::", annotation.getvalue())
            self.assertIn("simulator refused launch%3A unavailable", annotation.getvalue())


class ScreenshotFailureArtifactTests(unittest.TestCase):
    @staticmethod
    def failed_verification_capture(
        arguments: list[str], *, capture_output: bool = False
    ) -> subprocess.CompletedProcess[str]:
        if "screenshot" in arguments:
            Path(arguments[-1]).write_bytes(b"simulator screenshot fixture")
        elif arguments and arguments[0] == "sips" and "--out" in arguments:
            Path(arguments[-1]).write_bytes(b"\xff\xd8" + b"x" * 10_001)
        elif arguments and arguments[0] == "swift":
            raise subprocess.CalledProcessError(1, arguments, stderr="expected text was not recognized")
        return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

    def test_iphone_home_retains_final_failed_jpeg_for_ci_artifact_upload(self) -> None:
        import capture_simulator_screenshots

        with tempfile.TemporaryDirectory() as temporary_directory:
            output_path = Path(temporary_directory) / "iphone-home-en.jpg"
            with patch.object(capture_simulator_screenshots, "run", side_effect=self.failed_verification_capture), \
                    patch.object(capture_simulator_screenshots, "wait_for_home_demo_data"), \
                    patch.object(capture_simulator_screenshots.time, "sleep"):
                with self.assertRaisesRegex(RuntimeError, "Diagnostic JPEG retained"):
                    capture_simulator_language(
                        "simulator", "com.example.FactoryTools", output_path,
                        japanese=False, platform="iPhone", scenario="home",
                    )

            self.assertTrue(output_path.is_file())
            self.assertTrue(output_path.read_bytes().startswith(b"\xff\xd8"))
            self.assertFalse(output_path.with_suffix(".png").exists())

    def test_watch_home_retains_final_failed_jpeg_for_ci_artifact_upload(self) -> None:
        import capture_watch_screenshots

        with tempfile.TemporaryDirectory() as temporary_directory:
            output_path = Path(temporary_directory) / "watch-home-ja.jpg"
            with patch.object(capture_watch_screenshots, "run", side_effect=self.failed_verification_capture), \
                    patch.object(capture_watch_screenshots, "restart_simulator"), \
                    patch.object(capture_watch_screenshots.time, "sleep"):
                with self.assertRaisesRegex(RuntimeError, "Diagnostic JPEG retained"):
                    capture_watch_language("simulator", "com.example.FactoryTools.watch", output_path, japanese=True)

            self.assertTrue(output_path.is_file())
            self.assertTrue(output_path.read_bytes().startswith(b"\xff\xd8"))
            self.assertFalse(output_path.with_suffix(".png").exists())


class AppleUploadWorkflowContractTests(unittest.TestCase):
    def test_current_upload_workflow_is_manual_and_confirmed(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github" / "workflows" / "apple-app-store-upload.yml").read_text(encoding="utf-8")

        self.assertEqual(apple_upload_workflow_contract_errors(workflow), [])

    def test_upload_workflow_rejects_api_key_before_simulator_gates(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github" / "workflows" / "apple-app-store-upload.yml").read_text(encoding="utf-8")
        step_start = workflow.index("      - name: Prepare temporary App Store Connect API key")
        step_end = workflow.index("      - name: Create signed App Store archive", step_start)
        api_key_step = workflow[step_start:step_end]
        workflow_without_key = workflow[:step_start] + workflow[step_end:]
        first_test_step = workflow_without_key.index("      - name: Run current iPhone and shared Core regression suites")
        unsafe_workflow = workflow_without_key[:first_test_step] + api_key_step + workflow_without_key[first_test_step:]

        errors = apple_upload_workflow_contract_errors(unsafe_workflow)

        self.assertIn(
            "App Store Connect API key must not be loaded before all simulator tests and the Watch build pass",
            errors,
        )

    def test_upload_workflow_rejects_automatic_distribution_or_secret_echo(self) -> None:
        source = """name: Upload
on:
  push:
  workflow_dispatch:
    inputs:
      confirm_app_store_connect_upload:
        description: This uploads a signed build to App Store Connect only; it does not submit for App Review.
        required: true
        type: boolean
        default: true
permissions:
  contents: write
jobs:
  upload:
    if: inputs.confirm_app_store_connect_upload == true
    runs-on: macos-26
    steps:
      - run: echo "$APP_STORE_CONNECT_API_KEY_CONTENTS"
"""

        errors = apple_upload_workflow_contract_errors(source)

        self.assertIn("missing confirmation default is false", errors)
        self.assertIn("missing upload is limited to confirmed main-branch runs", errors)
        self.assertIn("missing read-only repository permission", errors)
        self.assertIn("missing iPad Simulator regression suite", errors)
        self.assertIn(
            "workflow must delay API key preparation until after simulator tests and the Watch build",
            errors,
        )
        self.assertIn("distribution upload workflow must not run on push, pull request, or schedule", errors)
        self.assertIn("workflow must not enable shell tracing or print App Store Connect key material", errors)


class SimulatorScreenshotWorkflowTests(unittest.TestCase):
    def test_home_readiness_ignores_stale_capture_logs(self) -> None:
        stale_output = subprocess.CompletedProcess(
            args=[], returncode=0,
            stdout='captureID=previous locale=en current=286 target=300\n', stderr="",
        )
        current_output = subprocess.CompletedProcess(
            args=[], returncode=0,
            stdout='captureID=current locale=en sessionCount=1 current=286 target=300\n', stderr="",
        )
        with patch("capture_simulator_screenshots.run", side_effect=[stale_output, current_output]) as run_command, \
             patch("capture_simulator_screenshots.time.sleep"):
            wait_for_home_demo_data("simulator", language_code="en", capture_id="current")
        self.assertEqual(run_command.call_count, 2)
        self.assertEqual(run_command.call_args.kwargs["timeout_seconds"], 10)
        self.assertIn("2m", run_command.call_args.args[0])

    def test_home_readiness_does_not_combine_state_from_different_log_lines(self) -> None:
        split_output = subprocess.CompletedProcess(
            args=[], returncode=0,
            stdout=(
                'captureID=current locale=en sessionCount=1\n'
                'current=286 target=300\n'
                'captureID=current locale=en sessionCount=1 current=286 target=300\n'
            ), stderr="",
        )
        with patch("capture_simulator_screenshots.run", return_value=split_output) as run_command, \
             patch("capture_simulator_screenshots.time.sleep"):
            wait_for_home_demo_data("simulator", language_code="en", capture_id="current")
        self.assertEqual(run_command.call_count, 1)

    def test_home_capture_falls_back_to_final_image_ocr_when_readiness_logs_timeout(self) -> None:
        import capture_simulator_screenshots

        def create_capture_fixture(arguments: list[str], *, capture_output: bool = False, timeout_seconds: int = 900):
            if "screenshot" in arguments:
                Path(arguments[-1]).write_bytes(b"simulator screenshot fixture")
            elif arguments and arguments[0] == "sips" and "--out" in arguments:
                Path(arguments[-1]).write_bytes(b"\xff\xd8" + b"x" * 10_001)
            elif arguments and arguments[0] == "swift":
                return subprocess.CompletedProcess(arguments, 0, stdout="286/300 visible", stderr="")
            return subprocess.CompletedProcess(arguments, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as temporary_directory:
            output_path = Path(temporary_directory) / "ipad-home-ja.jpg"
            with patch.object(capture_simulator_screenshots, "run", side_effect=create_capture_fixture), \
                 patch.object(capture_simulator_screenshots, "wait_for_home_demo_data", side_effect=RuntimeError("log query timed out")), \
                 patch.object(capture_simulator_screenshots, "image_dimensions", return_value=(2064, 2752)), \
                 patch.object(capture_simulator_screenshots.time, "sleep"):
                dimensions = capture_simulator_language(
                    "simulator", "com.example.FactoryTools", output_path,
                    japanese=True, platform="iPad", scenario="home",
                )

            self.assertEqual(dimensions, (2064, 2752))
            self.assertTrue(output_path.read_bytes().startswith(b"\xff\xd8"))

    def test_capture_cleans_stale_outputs_but_preserves_unrelated_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_dir = Path(temporary_directory)
            stale_names = ("ipad-home-en.jpg", "ipad-takt-time-ja.png", "capture-info.txt")
            for name in stale_names:
                (output_dir / name).write_text("stale", encoding="utf-8")
            unrelated = output_dir / "notes.txt"
            unrelated.write_text("keep", encoding="utf-8")

            clear_capture_outputs(output_dir, platform="ipad")

            self.assertTrue(all(not (output_dir / name).exists() for name in stale_names))
            self.assertEqual(unrelated.read_text(encoding="utf-8"), "keep")

    def test_ci_captures_bilingual_release_simulator_screenshots_without_persisting_demo_data(self) -> None:
        root = Path(__file__).resolve().parents[1]
        app_source = (root / "FactoryTools" / "App" / "FactoryToolsApp.swift").read_text(encoding="utf-8")
        bootstrap_view = (root / "FactoryTools" / "App" / "AppBootstrapView.swift").read_text(encoding="utf-8")
        home_view = (root / "FactoryTools" / "Features" / "Home" / "HomeView.swift").read_text(encoding="utf-8")
        capture_script = (root / "Scripts" / "capture_simulator_screenshots.py").read_text(encoding="utf-8")
        home_card = (root / "FactoryTools" / "Features" / "Home" / "HomeToolCardView.swift").read_text(encoding="utf-8")
        home_verifier = (root / "Scripts" / "verify_simulator_home_screenshot.swift").read_text(encoding="utf-8")
        workflow = (root / ".github" / "workflows" / "apple-native-checks.yml").read_text(encoding="utf-8")
        asset_plan = (root / "FactoryTools" / "APP_STORE_ASSET_PLAN.md").read_text(encoding="utf-8")

        self.assertIn("#if targetEnvironment(simulator)", app_source)
        self.assertIn('arguments.contains("--factorytools-screenshot-demo")', app_source)
        self.assertIn('case cycleTime = "cycle-time"', app_source)
        self.assertIn('case taktTime = "takt-time"', app_source)
        self.assertIn('case defectCounter = "defect-counter"', app_source)
        self.assertIn('case counterHistory = "counter-history"', app_source)
        self.assertIn('case counterQuickAdd = "counter-quick-add"', app_source)
        self.assertIn("insertUndoHistoryDemoEvents(for: production, context: context)", app_source)
        self.assertIn("reversesEventID: undoneIncrement.id", app_source)
        self.assertIn("kind: .undo", app_source)
        self.assertIn('case ipadDashboard = "ipad-dashboard"', app_source)
        self.assertIn('case ipadOffline = "ipad-offline"', app_source)
        self.assertIn("PeerCounterView(screenshotDemoMode:", home_view)
        self.assertIn(".presentationDetents(peerDashboardSheetDetents)", home_view)
        self.assertIn("private var peerDashboardSheetDetents: Set<PresentationDetent>", home_view)
        self.assertIn("screenshotDemoScenario?.peerCounterScreenshotMode == nil ? [.medium, .large] : [.large]", home_view)
        peer_view = (root / "FactoryTools" / "Features" / "Counter" / "PeerCounterView.swift").read_text(encoding="utf-8")
        self.assertIn('case .connected: "peer.status.connected"', peer_view)
        self.assertIn('case .offline: "peer.status.reconnecting"', peer_view)
        self.assertIn("guard screenshotDemoMode == nil else { return }", peer_view)
        self.assertIn("guard screenshotDemoScenario == nil else { return }", bootstrap_view)
        self.assertIn("guard screenshotDemoScenario == nil,", bootstrap_view)
        self.assertIn("case .cycleTime where card.toolID == ToolID.cycleTime.rawValue:", home_view)
        self.assertIn("case .taktTime where card.toolID == ToolID.taktTime.rawValue:", home_view)
        self.assertIn("case .counterHistory where card.toolID == ToolID.productionCounter.rawValue:", home_view)
        self.assertIn("initialSheet == nil || initialSheet == .customQuickAdd ? [.medium, .large] : [.large]", home_card)
        self.assertIn(".presentationDragIndicator(initialSheet == nil ? .visible : .hidden)", home_card)
        self.assertIn("isStoredInMemoryOnly: screenshotLanguage != nil", app_source)
        self.assertIn("ProductionSession(", app_source)
        self.assertIn('"--factorytools-screenshot-japanese"', app_source)
        self.assertIn('f"--factorytools-screenshot-{scenario}"', capture_script)
        self.assertIn('"sips", "-s", "format", "jpeg"', capture_script)
        self.assertIn('f"{arguments.platform}-{scenario}-{language}.jpg"', capture_script)
        self.assertIn("COMMAND_TIMEOUT_SECONDS = 900", capture_script)
        self.assertIn("HOME_READINESS_TIMEOUT_SECONDS = 30", capture_script)
        self.assertIn("HOME_READINESS_COMMAND_TIMEOUT_SECONDS = 10", capture_script)
        self.assertIn("def clear_capture_outputs", capture_script)
        self.assertIn("Simulator readiness logs were unavailable; the final image OCR will decide capture readiness.", capture_script)
        self.assertIn('"log", "show", "--last", "2m"', capture_script)
        self.assertIn("HOME_SCREENSHOT_ATTEMPTS = 3", capture_script)
        self.assertIn("HOME_RENDER_SETTLE_SECONDS = 3", capture_script)
        self.assertIn('language = "ja" if japanese else "en"', capture_script)
        self.assertIn("wait_for_home_demo_data(device_id, language_code=language, capture_id=capture_id)", capture_script)
        self.assertIn('"log", "show", "--last", "2m"', capture_script)
        self.assertIn('f"--factorytools-screenshot-capture-id={capture_id}"', capture_script)
        self.assertIn('f"captureID={capture_id}" in line', capture_script)
        self.assertIn("for line in result.stdout.splitlines()", capture_script)
        self.assertIn("time.sleep(HOME_RENDER_SETTLE_SECONDS)", capture_script)
        self.assertIn('f"locale={language_code}"', capture_script)
        self.assertIn('"swift", str(HOME_SCREENSHOT_VERIFIER)', capture_script)
        self.assertIn('["swift", str(HOME_SCREENSHOT_VERIFIER), str(output_path), *expected_values]', capture_script)
        self.assertIn('expected_values = ["286", "300", "10"]', capture_script)
        self.assertIn("initialSheet == .customQuickAdd ? [.medium, .large] : [.large]", home_card)
        self.assertLess(
            capture_script.index('"--out", str(output_path)', capture_script.index('run(["xcrun", "simctl", "io", device_id, "screenshot"')),
            capture_script.index('str(HOME_SCREENSHOT_VERIFIER), str(output_path)', capture_script.index('run(["xcrun", "simctl", "io", device_id, "screenshot"')),
        )
        self.assertIn('"286", "300"', capture_script)
        self.assertIn('current=286 target=300', capture_script)
        self.assertIn('subsystem: "com.factorytools.ios"', home_card)
        self.assertIn('category: "ScreenshotCapture"', home_card)
        self.assertIn("session?.currentCount.description", home_card)
        self.assertIn("confidence >= 0.5", home_verifier)
        self.assertIn("hasCountAndTargetOnSameRow", home_verifier)
        self.assertIn("abs(current.bounds.midY - target.bounds.midY) <= 0.06", home_verifier)
        self.assertIn("current.bounds.minX < target.bounds.minX", home_verifier)
        self.assertIn("Recognized text:", home_verifier)
        self.assertIn("timeout=timeout_seconds", capture_script)
        self.assertIn("Running simulator capture command:", capture_script)
        self.assertIn("CycleTimeSample(homeProfileID: home.id", app_source)
        self.assertIn('"27000" : ""', (root / "FactoryTools" / "Features" / "Tools" / "TaktTimeCalculatorView.swift").read_text(encoding="utf-8"))
        self.assertIn('"simctl", "install", arguments.device_id, str(arguments.app)', capture_script)
        self.assertIn('"13-inch" not in device', capture_script)
        self.assertIn('dimensions not in {(2064, 2752), (2048, 2732)}', capture_script)
        self.assertIn("-configuration Release", workflow)
        self.assertIn("Scripts/capture_simulator_screenshots.py", workflow)
        self.assertIn("uses: actions/upload-artifact@v7.0.1", workflow)
        self.assertIn("Diagnostic JPEG retained at {output_path}", capture_script)
        self.assertEqual(workflow.count("if: always()"), 4)
        self.assertEqual(workflow.count("if-no-files-found: ignore"), 4)
        self.assertIn("retention-days: 30", workflow)
        self.assertIn("Require iPhone and iPad screenshot captures", workflow)
        self.assertIn('exit "$failed"', workflow)
        self.assertIn("--scenarios home counter-quick-add cycle-time takt-time defect-counter counter-history", workflow)
        self.assertIn("factory-tools-app-store-iphone-product-page", workflow)
        self.assertIn("factory-tools-app-store-iphone-home", asset_plan)
        self.assertIn("Prepare 13-inch iPad Simulator before release screenshot captures", workflow)
        self.assertLess(
            workflow.index("Prepare 13-inch iPad Simulator before release screenshot captures"),
            workflow.index("Capture bilingual iPhone product-page screenshots from Release Simulator build"),
        )
        self.assertIn('"bootstatus", sys.argv[1], "-b"], check=True, timeout=900)', workflow)
        self.assertIn('xcrun simctl shutdown "$simulator_id"', workflow)
        self.assertIn("def ensure_simulator_booted(device_id: str) -> None:", capture_script)
        self.assertIn('["xcrun", "simctl", "boot", device_id]', capture_script)
        self.assertIn("Capture bilingual 13-inch iPad product-page screenshots from Release Simulator build", workflow)
        self.assertIn("--scenarios ipad-dashboard ipad-offline", workflow)
        self.assertIn("factory-tools-app-store-ipad-product-page", workflow)

    def test_ci_captures_bilingual_release_watch_screenshots_with_simulator_only_data(self) -> None:
        root = Path(__file__).resolve().parents[1]
        watch_app = (root / "FactoryToolsWatch" / "FactoryToolsWatchApp.swift").read_text(encoding="utf-8")
        watch_model = (root / "FactoryToolsWatch" / "WatchCounterModel.swift").read_text(encoding="utf-8")
        watch_view = (root / "FactoryToolsWatch" / "WatchHomeView.swift").read_text(encoding="utf-8")
        watch_theme = (root / "FactoryToolsWatch" / "WatchTheme.swift").read_text(encoding="utf-8")
        watch_strings = (root / "FactoryToolsWatch" / "Resources" / "Localizable.xcstrings").read_text(encoding="utf-8")
        capture_script = (root / "Scripts" / "capture_watch_screenshots.py").read_text(encoding="utf-8")
        screenshot_verifier = (root / "Scripts" / "verify_watch_screenshot.swift").read_text(encoding="utf-8")
        workflow = (root / ".github" / "workflows" / "apple-watch-archive-checks.yml").read_text(encoding="utf-8")

        self.assertIn("#if targetEnvironment(simulator)", watch_app)
        self.assertIn("model.screenshotDemoSessionID", watch_app)
        self.assertIn('ProcessInfo.processInfo.arguments.contains("--factorytools-screenshot-demo")', watch_model)
        self.assertIn('"--factorytools-screenshot-japanese"', watch_model)
        self.assertIn('"home.defaultName"', (root / "FactoryToolsWatch" / "Resources" / "Localizable.xcstrings").read_text(encoding="utf-8"))
        self.assertIn("currentCount: 286", watch_model)
        self.assertIn("targetCount: 300", watch_model)
        self.assertIn("static let primaryText = Color.white", watch_theme)
        self.assertIn("struct WatchCounterDetailView: View", watch_view)
        counter_detail = watch_view.split("struct WatchCounterDetailView: View", 1)[1]
        self.assertIn("@Environment(\\.isLuminanceReduced) private var isLuminanceReduced", counter_detail)
        self.assertIn("isLuminanceReduced ? WatchTheme.primaryText : WatchTheme.accent", counter_detail)
        self.assertIn("Text(verbatim: String(session.currentCount))", counter_detail)
        self.assertIn(".foregroundStyle(WatchTheme.primaryText)", counter_detail)
        self.assertIn("ProgressView(value: completion)", counter_detail)
        self.assertIn(".progressViewStyle(.linear)", counter_detail)
        self.assertIn(".tint(counterAccent)", counter_detail)
        self.assertIn(".tint(WatchTheme.secondaryText)", counter_detail)
        self.assertIn('.accessibilityLabel("watch.counter.subtractOne")', counter_detail)
        self.assertIn('.accessibilityLabel("watch.counter.addOne")', counter_detail)
        self.assertIn('"watch.counter.subtractOne"', watch_strings)
        self.assertIn('"watch.counter.addOne"', watch_strings)
        self.assertIn('category: "ScreenshotCapture"', watch_view)
        self.assertIn("@Environment(\\.colorScheme) private var colorScheme", counter_detail)
        self.assertIn("@Environment(\\.scenePhase) private var scenePhase", counter_detail)
        self.assertIn(r'.id("\(model.displayLanguage.rawValue)-\(String(describing: scenePhase))")', counter_detail)
        self.assertIn("redactionReasons.contains(.privacy)", watch_view)
        self.assertIn("redactionReasons.contains(.placeholder)", watch_view)
        self.assertNotIn("GeometryReader { geometry in", counter_detail)
        self.assertNotIn("Text(session.currentCount, format: .number)", counter_detail)
        self.assertIn('"simctl", "install", arguments.device_id, str(arguments.app)', capture_script)
        self.assertIn("dimensions != (416, 496)", capture_script)
        self.assertIn('"watch-home-en.jpg"', capture_script)
        self.assertIn('"watch-home-ja.jpg"', capture_script)
        self.assertLess(
            capture_script.index('"watch-home-ja.jpg": capture_language'),
            capture_script.index('captures["watch-home-en.jpg"] = capture_language'),
        )
        self.assertIn('print("Installing the Release Watch app.", flush=True)', capture_script)
        self.assertIn('print(f"Capturing {output_path.name}.", flush=True)', capture_script)
        self.assertIn("time.sleep(20)", capture_script)
        self.assertIn("MAX_SCREENSHOT_ATTEMPTS = 3", capture_script)
        self.assertIn('"swift", str(WATCH_SCREENSHOT_VERIFIER)', capture_script)
        self.assertIn('str(WATCH_SCREENSHOT_VERIFIER), str(output_path), "286", "300"', capture_script)
        self.assertLess(
            capture_script.index('"--out", str(output_path)', capture_script.index('run(["xcrun", "simctl", "io", device_id, "screenshot"')),
            capture_script.index('str(WATCH_SCREENSHOT_VERIFIER), str(output_path)', capture_script.index('run(["xcrun", "simctl", "io", device_id, "screenshot"')),
        )
        self.assertIn('"286", "300"', capture_script)
        self.assertIn("Counter text was not visible; restarting Watch Simulator.", capture_script)
        self.assertIn("Diagnostic JPEG retained at {output_path}", capture_script)
        self.assertIn("Watch screenshot is missing visible counter values", screenshot_verifier)
        self.assertIn("VNRecognizeTextRequest()", screenshot_verifier)
        self.assertIn("VNImageRequestHandler(url: imageURL).perform([request])", screenshot_verifier)
        self.assertIn("requiredVerticalRange.contains(item.bounds.midY)", screenshot_verifier)
        self.assertIn("index == 0 ? 0.40...0.75 : 0.10...0.42", screenshot_verifier)
        self.assertIn("Watch screenshot OCR:", screenshot_verifier)
        self.assertIn('"log", "show", "--last", "2m"', capture_script)
        self.assertNotIn("restart_simulator(arguments.device_id)", capture_script)
        self.assertIn("COMMAND_TIMEOUT_SECONDS = 300", capture_script)
        self.assertIn("SIMULATOR_BOOT_TIMEOUT_SECONDS = 900", capture_script)
        self.assertIn("timeout_seconds: int = COMMAND_TIMEOUT_SECONDS", capture_script)
        self.assertIn("timeout_seconds=SIMULATOR_BOOT_TIMEOUT_SECONDS", capture_script)
        self.assertIn('parser.add_argument("--device-name")', capture_script)
        self.assertIn("arguments.device_name or simulator_name(arguments.device_id)", capture_script)
        self.assertIn("Each launch terminates the prior app process", capture_script)
        self.assertIn('summary_path = os.environ.get("GITHUB_STEP_SUMMARY")', capture_script)
        self.assertIn("record_failure_summary(error)", capture_script)
        self.assertIn("stderr=result.stderr", capture_script)
        self.assertIn("if error.stderr:", capture_script)
        self.assertIn("Capture bilingual Apple Watch screenshots from Release Simulator build", workflow)
        self.assertIn("Build Watch Release Simulator target for screenshots", workflow)
        self.assertIn("timeout-minutes: 90", workflow)
        self.assertIn("timeout-minutes: 30", workflow)
        self.assertIn("id: build_watch_release", workflow)
        self.assertIn('timeout=30)', workflow)
        self.assertIn('echo "simulator_id=$simulator_id" >> "$GITHUB_OUTPUT"', workflow)
        self.assertIn("WATCH_SIMULATOR_ID: ${{ steps.build_watch_release.outputs.simulator_id }}", workflow)
        self.assertIn('--device-name "$simulator_name"', workflow)
        self.assertIn("INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp=YES", workflow)
        self.assertIn("Release-watchsimulator/FactoryToolsWatch.app", workflow)
        self.assertIn("FactoryTools.app/PlugIns/FactoryToolsWatch.app", workflow)
        self.assertIn("factory-tools-app-store-watch-home", workflow)
        self.assertRegex(
            workflow,
            r"id: capture_watch_screenshots\n\s+timeout-minutes: 30\n\s+continue-on-error: true",
        )
        self.assertIn("Test shared Core contracts", workflow)
        self.assertIn("Archive generic iPhone and iPad app without signing", workflow)

        ios_workflow = (root / ".github" / "workflows" / "apple-native-checks.yml").read_text(encoding="utf-8")
        for capture_id in ("capture_iphone_screenshots", "capture_ipad_screenshots"):
            self.assertRegex(
                ios_workflow,
                rf"id: {capture_id}\n(?:\s+timeout-minutes: \d+\n)?\s+continue-on-error: true",
            )


class LegalPagesWorkflowContractTests(unittest.TestCase):
    def test_current_legal_pages_workflow_is_manual_and_confirmed(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github" / "workflows" / "publish-legal-pages.yml").read_text(encoding="utf-8")

        self.assertEqual(pages_publication_workflow_contract_errors(workflow), [])

    def test_legal_pages_workflow_rejects_automatic_or_unconfirmed_deployment(self) -> None:
        source = """name: Publish Pages
on:
  push:
  workflow_dispatch:
    inputs:
      confirm_publication:
        description: Publish the completed, publisher-reviewed legal/support pages to GitHub Pages.
        required: true
        type: boolean
        default: true
permissions:
  contents: write
jobs:
  publish:
    if: inputs.confirm_publication == true
    steps:
      - uses: actions/deploy-pages@v4
"""

        errors = pages_publication_workflow_contract_errors(source)

        self.assertIn("missing publication confirmation defaults off", errors)
        self.assertIn("missing deployment is limited to confirmed main-branch runs", errors)
        self.assertIn("missing read-only repository permission by default", errors)
        self.assertIn("legal-pages publication workflow must not deploy automatically", errors)


class SwiftRuntimeSafetySourceTests(unittest.TestCase):
    def test_safe_optional_and_throwing_paths_are_allowed(self) -> None:
        source = """func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
    try JSONDecoder().decode(type, from: data)
}
let value = optionalValue?.description ?? "missing"
let differs = left != right
let isMissing = !isPresent
"""

        self.assertEqual(swift_unsafe_escape_hatches(source), [])

    def test_forced_runtime_escape_hatches_are_detected(self) -> None:
        source = """fatalError("unsupported")
preconditionFailure("missing")
assertionFailure("unexpected")
let value = try! decode()
let model = object as! Model
let endpoint = try! URL(string: "https://example.com")!
"""

        self.assertCountEqual(
            swift_unsafe_escape_hatches(source),
            ["fatalError", "preconditionFailure", "assertionFailure", "forced try", "forced cast", "forced unwrap"],
        )


class OpenStepParserTests(unittest.TestCase):
    def test_parses_comments_nested_dictionaries_and_trailing_commas(self) -> None:
        project = parse_openstep(
            '// UTF8 header\n'
            '{ rootObject = PROJECT; objects = { PROJECT = { isa = PBXProject; '
            'knownRegions = (ja, en,); }; }; }'
        )

        self.assertEqual(project["objects"]["PROJECT"]["knownRegions"], ["ja", "en"])

    def test_unescapes_quoted_values(self) -> None:
        project = parse_openstep('{ value = "Factory \\"Tools\\""; }')

        self.assertEqual(project["value"], 'Factory "Tools"')

    def test_rejects_missing_dictionary_terminator(self) -> None:
        with self.assertRaises(OpenStepParseError):
            parse_openstep("{ key = value }")

    def test_resolves_local_references_through_nested_groups(self) -> None:
        project = parse_openstep(
            '{ rootObject = PROJECT; objects = {'
            'PROJECT = { isa = PBXProject; mainGroup = ROOT; };'
            'ROOT = { isa = PBXGroup; children = (SOURCES, SDK,); };'
            'SOURCES = { isa = PBXGroup; path = Sources; children = (FILE,); };'
            'FILE = { isa = PBXFileReference; path = Main.swift; sourceTree = "<group>"; };'
            'SDK = { isa = PBXFileReference; path = System/Library/Frameworks/XCTest.framework; sourceTree = SDKROOT; };'
            '}; }'
        )

        references = local_project_file_references(
            project["objects"],
            project["objects"]["PROJECT"],
            Path("C:/workspace"),
        )

        self.assertEqual(references, [Path("C:/workspace/Sources/Main.swift")])


class LocalizationValidationTests(unittest.TestCase):
    def test_counts_format_arguments_without_counting_escaped_percent(self) -> None:
        self.assertEqual(localization_placeholder_count("Count: %1$lld of %2$@"), 2)
        self.assertEqual(localization_placeholder_count("100%% ready"), 0)

    def test_reads_localized_info_plist_string_value(self) -> None:
        self.assertEqual(
            localized_info_plist_value(
                'NSLocalNetworkUsageDescription = "Connect the iPad";',
                "NSLocalNetworkUsageDescription",
            ),
            "Connect the iPad",
        )

    def test_requires_nonempty_distinct_japanese_and_english_privacy_copy(self) -> None:
        self.assertTrue(has_distinct_localized_copy("iPadから接続します", "Connect from iPad"))
        self.assertFalse(has_distinct_localized_copy("Same", "Same"))
        self.assertFalse(has_distinct_localized_copy(" ", "Connect from iPad"))

    def test_detects_hardcoded_swiftui_copy_and_allows_keys_symbols_and_localized_interpolation(self) -> None:
        source = (
            'Text("Open settings")\n'
            'Button("保存してください") {}\n'
            'Text("home.renameNamed \\(homeName)")\n'
            'Text(" / \\(formattedValue)")\n'
            'Text("(\\(unit.symbol))")\n'
            'Text("home.empty.title")\n'
        )

        issues = swiftui_unlocalized_copy_literals(
            source,
            {"home.renameNamed %@", "home.empty.title"},
        )

        self.assertEqual(issues, [(1, "Open settings"), (2, "保存してください")])

    def test_detects_ui_that_bypasses_the_theme_manager_palette(self) -> None:
        self.assertTrue(bypasses_app_theme_manager("let theme = AppTheme.industrialDark"))
        self.assertTrue(bypasses_app_theme_manager("let theme = AppTheme . industrialDark"))
        self.assertFalse(bypasses_app_theme_manager("let theme = ThemeManager().theme(for: .industrialDark)"))
        self.assertFalse(bypasses_app_theme_manager("@Environment(\\.appTheme) var theme: AppTheme"))

    def test_accepts_supported_launch_screen_info_plist_keys(self) -> None:
        self.assertFalse(has_supported_ios_launch_screen({}))
        self.assertTrue(has_supported_ios_launch_screen({"UILaunchScreen": {}}))
        self.assertTrue(has_supported_ios_launch_screen({"UILaunchStoryboardName": "LaunchScreen"}))


class MarkdownLinkValidationTests(unittest.TestCase):
    def test_resolves_relative_files_and_ignores_urls_and_anchors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "guide.md").write_text("# Guide\n", encoding="utf-8")
            (root / "icon.png").write_bytes(b"image")
            source_path = root / "README.md"
            markdown = (
                "[guide](guide.md)\n"
                "![icon](icon.png)\n"
                "[section](#part)\n"
                "[external](https://example.com/page)\n"
                "[missing](missing.md)\n"
            )

            errors = local_markdown_link_errors(source_path, markdown)

        self.assertEqual(len(errors), 1)
        self.assertIn(":5:", errors[0])
        self.assertIn("missing.md", errors[0])


class AppStoreMetadataTests(unittest.TestCase):
    def test_bilingual_listing_fits_name_subtitle_keyword_and_description_limits(self) -> None:
        metadata = (
            "## Japanese (ja-JP)\n"
            "**Name**\nFactory Tools\n\n"
            "**Subtitle**\n生産カウンター\n\n"
            "**Keywords**\n生産,OEE\n\n"
            "**Description**\n説明文\n\n"
            "## English (en-US)\n"
            "**Name**\nFactory Tools\n\n"
            "**Subtitle**\nProduction counter\n\n"
            "**Keywords**\nproduction,counter\n\n"
            "**Description**\nDescription text\n"
        )

        self.assertEqual(app_store_metadata_limit_errors(metadata), [])

    def test_listing_rejects_overlong_title_subtitle_keyword_bytes_and_description(self) -> None:
        metadata = (
            "## Japanese (ja-JP)\n"
            "**Name**\n" + "名" * 31 + "\n\n"
            "**Subtitle**\n" + "補" * 31 + "\n\n"
            "**Keywords**\n" + "生" * 34 + "\n\n"
            "**Description**\n" + "説" * 4001 + "\n\n"
            "## English (en-US)\n"
            "**Name**\nFactory Tools\n\n"
            "**Subtitle**\nProduction counter\n\n"
            "**Keywords**\nproduction,counter\n\n"
            "**Description**\nDescription text\n"
        )

        errors = app_store_metadata_limit_errors(metadata)
        self.assertTrue(any("name" in error for error in errors))
        self.assertTrue(any("subtitle" in error for error in errors))
        self.assertTrue(any("keywords" in error for error in errors))
        self.assertTrue(any("description" in error for error in errors))

    def test_one_time_purchase_localizations_fit_apple_limits(self) -> None:
        metadata = (
            "**Type:** Non-consumable (one-time purchase)\n"
            "**Product ID:** `factorytools.pro.lifetime` (candidate; use this exact value in App Store Connect)\n\n"
            "**Availability and price:** All currently available App Store territories where permitted; Japan base storefront, JPY ¥980 (confirmed); review Apple's generated local prices before release.\n\n"
            "**App Review Screenshot:** Capture the Pro purchase panel from the signed release build\n\n"
            "### Japanese product localization (ja-JP)\n\n"
            "**Display Name**\nFactory Tools Pro\n\n"
            "**Description**\n専門ツールと高度な機能を解放\n\n"
            "### English product localization (en-US)\n\n"
            "**Display Name**\nFactory Tools Pro\n\n"
            "**Description**\nUnlock Pro tools and advanced features.\n"
        )
        self.assertEqual(in_app_purchase_metadata_limit_errors(metadata), [])

    def test_one_time_purchase_localizations_reject_overlong_fields(self) -> None:
        metadata = (
            "**Type:** Non-consumable (one-time purchase)\n"
            "**Product ID:** `factorytools.pro.lifetime` (candidate; use this exact value in App Store Connect)\n\n"
            "**Availability and price:** All currently available App Store territories where permitted; Japan base storefront, JPY ¥980 (confirmed); review Apple's generated local prices before release.\n\n"
            "**App Review Screenshot:** Capture the Pro purchase panel from the signed release build\n\n"
            "### Japanese product localization (ja-JP)\n\n"
            "**Display Name**\n" + "名" * 31 + "\n\n"
            "**Description**\n" + "説" * 46 + "\n\n"
            "### English product localization (en-US)\n\n"
            "**Display Name**\nFactory Tools Pro\n\n"
            "**Description**\nUnlock Pro tools and advanced features.\n"
        )
        errors = in_app_purchase_metadata_limit_errors(metadata)
        self.assertTrue(any("display name" in error for error in errors))
        self.assertTrue(any("description" in error for error in errors))

    def test_storekit_product_identifier_uses_apple_characters_and_length(self) -> None:
        self.assertTrue(is_valid_storekit_product_id("factorytools.pro.lifetime"))
        self.assertTrue(is_valid_storekit_product_id("A" * 100))
        self.assertFalse(is_valid_storekit_product_id("A" * 101))
        self.assertFalse(is_valid_storekit_product_id("factorytools/pro"))
        self.assertFalse(is_valid_storekit_product_id(""))

    def test_local_storekit_configuration_matches_approved_purchase(self) -> None:
        source = (Path(__file__).resolve().parents[1] / "FactoryTools" / "Resources" / "FactoryToolsPro.storekit").read_text(encoding="utf-8")

        self.assertEqual(storekit_configuration_errors(source, "factorytools.pro.lifetime"), [])

    def test_local_storekit_configuration_rejects_purchase_boundary_drift(self) -> None:
        source = '{"products":[{"productID":"other","type":"Consumable","familyShareable":true,"displayPrice":"1","localizations":[{"locale":"en_US"}]}],"settings":{"_storefront":"USA"}}'

        errors = storekit_configuration_errors(source, "factorytools.pro.lifetime")

        self.assertEqual(len(errors), 6)
        self.assertTrue(any("product ID" in error for error in errors))
        self.assertTrue(any("non-consumable" in error for error in errors))
        self.assertTrue(any("Family Sharing" in error for error in errors))

    def test_app_store_sku_uses_supported_characters_and_valid_prefix(self) -> None:
        self.assertTrue(is_valid_app_store_sku("FACTORYTOOLS-IOS-001"))
        self.assertTrue(is_valid_app_store_sku("App_1.0"))
        for value in ("-FactoryTools", ".FactoryTools", "_FactoryTools", "Factory Tools", "Factory/Tools", ""):
            with self.subTest(value=value):
                self.assertFalse(is_valid_app_store_sku(value))


class BonjourDeclarationTests(unittest.TestCase):
    def test_requires_transport_service_type_in_info_plist(self) -> None:
        transport = 'private let serviceType = "_factorytools._tcp"'

        self.assertTrue(bonjour_declaration_matches(["_factorytools._tcp"], transport))
        self.assertFalse(bonjour_declaration_matches(["_other._tcp"], transport))


class JSONResourceValidationTests(unittest.TestCase):
    def test_rejects_duplicate_keys_in_resource_json(self) -> None:
        with self.assertRaises(DuplicateJSONKeyError):
            parse_json_no_duplicates('{"language": "ja", "language": "en"}')


class SwiftDataModelSourceTests(unittest.TestCase):
    def test_persisted_property_parser_ignores_computed_properties_and_method_locals(self) -> None:
        source = """@Model
final class Example {
    @Attribute(.unique) var id: UUID
    var count: Int

    var displayCount: String {
        String(count)
    }

    init(count: Int) {
        self.id = UUID()
        self.count = count
        let localValue = count
    }
}
"""

        self.assertEqual(swift_model_persisted_properties(source, "Example"), {"id", "count"})
        self.assertEqual(swift_model_persisted_properties(source, "Missing"), set())


class ContrastCalculationTests(unittest.TestCase):
    def test_standard_black_and_white_contrast_is_twenty_one_to_one(self) -> None:
        self.assertEqual(contrast_ratio((0, 0, 0), (1, 1, 1)), 21)

    def test_equal_colors_have_one_to_one_contrast(self) -> None:
        self.assertEqual(contrast_ratio((0.2, 0.4, 0.6), (0.2, 0.4, 0.6)), 1)


class PNGValidationTests(unittest.TestCase):
    @staticmethod
    def make_png(color_type: int, with_transparency_chunk: bool = False) -> bytes:
        signature = b"\x89PNG\r\n\x1a\n"

        def chunk(kind: bytes, payload: bytes) -> bytes:
            return struct.pack(">I", len(payload)) + kind + payload + b"\0\0\0\0"

        header = struct.pack(">IIBBBBB", 1, 1, 8, color_type, 0, 0, 0)
        result = signature + chunk(b"IHDR", header)
        if with_transparency_chunk:
            result += chunk(b"tRNS", b"\0")
        return result + chunk(b"IEND", b"")

    def test_accepts_opaque_rgb_png(self) -> None:
        self.assertTrue(is_opaque_png(self.make_png(color_type=2)))

    def test_rejects_explicit_alpha_and_transparency_chunks(self) -> None:
        self.assertFalse(is_opaque_png(self.make_png(color_type=6)))
        self.assertFalse(is_opaque_png(self.make_png(color_type=2, with_transparency_chunk=True)))

    def test_rejects_invalid_or_truncated_png(self) -> None:
        self.assertFalse(is_opaque_png(b"not a PNG"))
        self.assertFalse(is_opaque_png(self.make_png(color_type=2)[:-3]))


class ReleasePreflightTests(unittest.TestCase):
    def test_base_storefront_price_option_has_explicit_name(self) -> None:
        script = Path(__file__).with_name("validate_static.py")
        for option in ("--candidate-base-storefront-price", "--candidate-pro-price"):
            with self.subTest(option=option):
                result = subprocess.run(
                    [sys.executable, str(script), "--release-preflight", "--candidate-base-storefront", "JP", option, "JPY:980"],
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    check=False,
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("base storefront price candidate", result.stdout)
                self.assertIn("BLOCKER:", result.stdout)

    def test_release_preflight_reports_blockers_with_cp932_console_encoding(self) -> None:
        script = Path(__file__).with_name("validate_static.py")
        environment = os.environ.copy()
        environment["PYTHONIOENCODING"] = "cp932"

        result = subprocess.run(
            [sys.executable, str(script), "--release-preflight"],
            capture_output=True,
            text=True,
            encoding="cp932",
            env=environment,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("BLOCKER:", result.stdout)
        self.assertNotIn("UnicodeEncodeError", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_release_preflight_uses_selected_storefront_candidates_by_default(self) -> None:
        script = Path(__file__).with_name("validate_static.py")
        result = subprocess.run(
            [sys.executable, str(script), "--release-preflight"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("JP / JPY:980", result.stdout)
        self.assertIn("5 project identity/configuration blocker(s)", result.stdout)
        self.assertIn("This count covers project settings only", result.stdout)
        self.assertNotIn("distribution blocker(s)", result.stdout)
        self.assertNotIn("base storefront price candidate", result.stdout)
        self.assertNotIn("base storefront country/region candidate", result.stdout)

    def test_family_sharing_decision_is_explicit_and_versioned(self) -> None:
        disabled = "- Family Sharing: **disabled for Version 1**. Do not enable."
        enabled = "- Family Sharing: **enabled for Version 1**."
        undecided = "- Family Sharing: undecided; off recommended."

        self.assertEqual(family_sharing_decision(disabled), "disabled")
        self.assertEqual(family_sharing_decision(enabled), "enabled")
        self.assertIsNone(family_sharing_decision(undecided))

    def test_release_uses_approved_family_sharing_choice_and_rejects_conflicting_candidate(self) -> None:
        decisions = "- Family Sharing: **disabled for Version 1**."

        self.assertEqual(resolve_family_sharing_candidate(decisions, None), ("disabled", False))
        self.assertEqual(resolve_family_sharing_candidate(decisions, "disabled"), ("disabled", False))
        self.assertEqual(resolve_family_sharing_candidate(decisions, "enabled"), ("enabled", True))

    def test_price_candidate_requires_currency_and_a_positive_amount(self) -> None:
        self.assertTrue(is_valid_price_candidate("JPY:980"))
        self.assertTrue(is_valid_price_candidate("USD:4.99"))
        self.assertFalse(is_valid_price_candidate("JPY:0"))
        self.assertFalse(is_valid_price_candidate("¥980"))
        self.assertFalse(is_valid_price_candidate("jpy:980"))
        self.assertFalse(is_valid_price_candidate("JPY:1e999"))

    def test_base_storefront_candidate_requires_two_uppercase_letters(self) -> None:
        self.assertTrue(is_valid_base_storefront_candidate("JP"))
        self.assertTrue(is_valid_base_storefront_candidate("US"))
        self.assertFalse(is_valid_base_storefront_candidate("jp"))
        self.assertFalse(is_valid_base_storefront_candidate("JPN"))
        self.assertFalse(is_valid_base_storefront_candidate("J1"))

    def test_release_preflight_rejects_malformed_base_storefront_candidate(self) -> None:
        script = Path(__file__).with_name("validate_static.py")
        result = subprocess.run(
            [sys.executable, str(script), "--release-preflight", "--candidate-base-storefront", "jp"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("base storefront country/region candidate", result.stdout)

    def test_complete_candidate_values_pass_cli_preflight_without_mutating_project(self) -> None:
        script = Path(__file__).with_name("validate_static.py")
        result = subprocess.run(
            [
                sys.executable, str(script), "--release-preflight",
                "--candidate-bundle-id", "jp.factorytools.publisher",
                "--candidate-marketing-version", "1.0",
                "--candidate-build-number", "1",
                "--candidate-team-id", "A1B2C3D4E5",
                "--candidate-privacy-policy-url", "https://privacy.factorytools.test/policy",
                "--candidate-support-url", "https://support.factorytools.test/",
                "--candidate-pro-product-id", "factorytools.pro.lifetime",
                "--candidate-base-storefront", "JP",
                "--candidate-base-storefront-price", "JPY:980",
                "--candidate-family-sharing", "disabled",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("candidate values passed source-level checks", result.stdout)
        self.assertIn("This is not a release approval", result.stdout)

    def test_privacy_policy_url_requires_https_without_credentials(self) -> None:
        self.assertTrue(is_https_url("https://privacy.factorytools.test/policy"))
        self.assertFalse(is_https_url("http://privacy.factorytools.test/policy"))
        self.assertFalse(is_https_url("https://user:secret@privacy.factorytools.test/policy"))
        self.assertFalse(is_https_url(""))

    def test_development_bundle_id_and_version_are_blockers(self) -> None:
        blockers = release_preflight_blockers(
            "com.example.FactoryTools",
            "0.1",
            "1",
            "com.example.FactoryTools.watchkitapp",
            "com.example.FactoryTools",
            True,
            True,
        )

        self.assertEqual(len(blockers), 2)
        self.assertTrue(any("com.example" in blocker for blocker in blockers))
        self.assertTrue(any("0.x" in blocker for blocker in blockers))

    def test_publisher_owned_identity_and_release_version_pass(self) -> None:
        blockers = release_preflight_blockers(
            "jp.factorytools",
            "1.0",
            "1",
            "jp.factorytools.watchkitapp",
            "jp.factorytools",
            True,
            True,
        )

        self.assertEqual(blockers, [])

    def test_watch_bundle_mismatch_is_reported(self) -> None:
        blockers = release_preflight_blockers(
            "jp.factorytools.app",
            "1.0",
            "1",
            "jp.factorytools.watch",
            "jp.factorytools.other",
            True,
            True,
        )

        self.assertEqual(len(blockers), 2)
        self.assertTrue(any(".watchkitapp" in blocker for blocker in blockers))
        self.assertTrue(any("companion Bundle ID" in blocker for blocker in blockers))

    def test_missing_icons_are_reported(self) -> None:
        blockers = release_preflight_blockers(
            "jp.factorytools.app",
            "1.0",
            "1",
            "jp.factorytools.app.watchkitapp",
            "jp.factorytools.app",
            False,
            False,
        )

        self.assertEqual(len(blockers), 2)
        self.assertTrue(any("iPhone AppIcon" in blocker for blocker in blockers))
        self.assertTrue(any("watchOS AppIcon" in blocker for blocker in blockers))

    def test_release_configuration_is_checked_independently_from_debug(self) -> None:
        project_settings = {
            "FACTORYTOOLS_APP_BUNDLE_ID": "jp.factorytools",
            "MARKETING_VERSION": "0.1",
            "CURRENT_PROJECT_VERSION": "1",
        }
        app_settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        }
        watch_settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID).watchkitapp",
            "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        }

        debug_blockers = release_preflight_configuration_blockers(
            "Debug", project_settings, app_settings, watch_settings, True, True
        )
        release_blockers = release_preflight_configuration_blockers(
            "Release",
            {
                **project_settings,
                "MARKETING_VERSION": "1.0",
                "FACTORYTOOLS_PRIVACY_POLICY_URL": "https://privacy.factorytools.test/policy",
                "FACTORYTOOLS_SUPPORT_URL": "https://support.factorytools.test/",
                "FACTORYTOOLS_PRO_PRODUCT_ID": "factorytools.pro.lifetime",
            },
            {**app_settings, "PRODUCT_BUNDLE_IDENTIFIER": "com.example.FactoryTools"},
            watch_settings,
            True,
            True,
        )

        self.assertEqual(len(debug_blockers), 1)
        self.assertTrue(debug_blockers[0].startswith("Debug:"))
        self.assertEqual(len(release_blockers), 7)
        self.assertTrue(all(blocker.startswith("Release:") for blocker in release_blockers))
        self.assertTrue(any("publisher-owned" in blocker for blocker in release_blockers))
        self.assertTrue(any("Team ID" in blocker for blocker in release_blockers))
        self.assertTrue(any("base storefront price candidate" in blocker for blocker in release_blockers))
        self.assertTrue(any("base storefront country/region candidate" in blocker for blocker in release_blockers))
        self.assertTrue(any("Family Sharing" in blocker for blocker in release_blockers))

    def test_configuration_specific_app_icon_selection_is_checked(self) -> None:
        blockers = release_preflight_configuration_blockers(
            "Release",
            {
                "FACTORYTOOLS_APP_BUNDLE_ID": "jp.factorytools",
                "MARKETING_VERSION": "1.0",
                "CURRENT_PROJECT_VERSION": "1",
                "FACTORYTOOLS_SUPPORT_URL": "https://support.factorytools.test/",
            },
            {
                "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AlternateIcon",
            },
            {
                "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID).watchkitapp",
                "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            },
            True,
            True,
            base_storefront_candidate="JP",
        )

        self.assertEqual(len(blockers), 6)
        self.assertIn("Release:", blockers[0])
        self.assertTrue(any("iPhone AppIcon" in blocker for blocker in blockers))
        self.assertTrue(any("Team ID" in blocker for blocker in blockers))
        self.assertTrue(any("Pro product ID" in blocker for blocker in blockers))

    def test_release_requires_an_https_policy_url(self) -> None:
        project_settings = {
            "FACTORYTOOLS_APP_BUNDLE_ID": "jp.factorytools",
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "FACTORYTOOLS_SUPPORT_URL": "https://support.factorytools.test/",
            "DEVELOPMENT_TEAM": "A1B2C3D4E5",
            "FACTORYTOOLS_PRIVACY_POLICY_URL": "http://privacy.factorytools.test/policy",
            "FACTORYTOOLS_PRO_PRODUCT_ID": "factorytools.pro.lifetime",
        }
        app_settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        }
        watch_settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID).watchkitapp",
            "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        }

        blockers = release_preflight_configuration_blockers(
            "Release", project_settings, app_settings, watch_settings, True, True,
            base_storefront_candidate="JP",
        )
        self.assertEqual(len(blockers), 3)
        self.assertIn("HTTPS Privacy Policy URL", blockers[0])

    def test_release_requires_an_https_support_url(self) -> None:
        project_settings = {
            "FACTORYTOOLS_APP_BUNDLE_ID": "jp.factorytools",
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": "A1B2C3D4E5",
            "FACTORYTOOLS_PRIVACY_POLICY_URL": "https://privacy.factorytools.test/policy",
            "FACTORYTOOLS_SUPPORT_URL": "http://support.factorytools.test/",
            "FACTORYTOOLS_PRO_PRODUCT_ID": "factorytools.pro.lifetime",
        }
        blockers = release_preflight_configuration_blockers(
            "Release",
            project_settings,
            {"PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID)", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"},
            {
                "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID).watchkitapp",
                "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            },
            True,
            True,
            base_storefront_candidate="JP",
        )
        self.assertEqual(len(blockers), 3)
        self.assertIn("HTTPS Support URL", blockers[0])

    def test_candidate_distribution_values_validate_both_targets_without_mutation(self) -> None:
        project_settings = {
            "FACTORYTOOLS_APP_BUNDLE_ID": "com.example.FactoryTools",
            "MARKETING_VERSION": "0.1",
            "CURRENT_PROJECT_VERSION": "1",
        }
        candidate_settings = apply_release_candidate_overrides(
            project_settings,
            bundle_id="jp.factorytools.company",
            marketing_version="1.2",
            build_number="7",
            team_id="A1B2C3D4E5",
            privacy_policy_url="https://privacy.factorytools.test/policy",
            support_url="https://support.factorytools.test/",
            pro_product_id="factorytools.pro.lifetime",
        )
        app_settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        }
        watch_settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID).watchkitapp",
            "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        }

        for configuration in ("Debug", "Release"):
            self.assertEqual(
                release_preflight_configuration_blockers(
                    configuration,
                    candidate_settings,
                    app_settings,
                    watch_settings,
                    True,
                    True,
                    pro_price_candidate="JPY:980",
                    family_sharing_candidate="disabled",
                    base_storefront_candidate="JP",
                ),
                [],
            )
        self.assertEqual(project_settings["FACTORYTOOLS_APP_BUNDLE_ID"], "com.example.FactoryTools")
        self.assertEqual(project_settings["MARKETING_VERSION"], "0.1")
        self.assertNotIn("DEVELOPMENT_TEAM", project_settings)

    def test_partial_or_invalid_candidate_values_leave_other_blockers_visible(self) -> None:
        candidate_settings = apply_release_candidate_overrides(
            {
                "FACTORYTOOLS_APP_BUNDLE_ID": "com.example.FactoryTools",
                "MARKETING_VERSION": "0.1",
                "CURRENT_PROJECT_VERSION": "1",
                "FACTORYTOOLS_SUPPORT_URL": "http://support.factorytools.test/",
            },
            bundle_id="com.example.NewName",
            build_number="0",
        )

        blockers = release_preflight_configuration_blockers(
            "Release",
            candidate_settings,
            {
                "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            },
            {
                "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID).watchkitapp",
                "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            },
            True,
            True,
        )

        self.assertEqual(len(blockers), 10)
        self.assertTrue(any("development-only" in blocker for blocker in blockers))
        self.assertTrue(any("0.x" in blocker for blocker in blockers))
        self.assertTrue(any("positive build number" in blocker for blocker in blockers))
        self.assertTrue(any("Team ID" in blocker for blocker in blockers))
        self.assertTrue(any("Privacy Policy URL" in blocker for blocker in blockers))
        self.assertTrue(any("Support URL" in blocker for blocker in blockers))
        self.assertTrue(any("Pro product ID" in blocker for blocker in blockers))

    def test_release_requires_an_app_store_non_consumable_product_id(self) -> None:
        candidate_settings = {
            "FACTORYTOOLS_APP_BUNDLE_ID": "jp.factorytools",
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": "A1B2C3D4E5",
            "FACTORYTOOLS_PRIVACY_POLICY_URL": "https://privacy.factorytools.test/policy",
            "FACTORYTOOLS_SUPPORT_URL": "https://support.factorytools.test/",
        }
        blockers = release_preflight_configuration_blockers(
            "Release",
            candidate_settings,
            {
                "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            },
            {
                "PRODUCT_BUNDLE_IDENTIFIER": "$(FACTORYTOOLS_APP_BUNDLE_ID).watchkitapp",
                "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(FACTORYTOOLS_APP_BUNDLE_ID)",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            },
            True,
            True,
        )

        self.assertEqual(len(blockers), 4)
        self.assertTrue(any("non-consumable Factory Tools Pro product ID" in blocker for blocker in blockers))
        self.assertTrue(any("base storefront price candidate" in blocker for blocker in blockers))
        self.assertTrue(any("base storefront country/region candidate" in blocker for blocker in blockers))
        self.assertTrue(any("Family Sharing" in blocker for blocker in blockers))


class WatchTransportSourceRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        project_root = Path(__file__).resolve().parents[1]
        cls.source = (project_root / "FactoryToolsWatch" / "WatchCounterModel.swift").read_text(encoding="utf-8")

    def test_watch_send_waits_for_an_existing_retry_delay(self) -> None:
        start = self.source.index("private func sendHeadIfReachable()")
        end = self.source.index("private func scheduleResponseTimeout(", start)
        send_function = self.source[start:end]

        self.assertIn("retryTask == nil", send_function)

    def test_watch_response_publishes_queue_and_snapshot_only_after_save(self) -> None:
        start = self.source.index("private func applyCommandResponse(")
        end = self.source.index("private func scheduleRetry()", start)
        response_function = self.source[start:end]
        save_index = response_function.index("try fileStore.save(updated)")

        self.assertLess(save_index, response_function.index("outbox = updated"))
        self.assertLess(save_index, response_function.index("sessions = updatedSessions"))
        self.assertLess(response_function.index("outbox = updated"), response_function.index("pendingCount = outbox.count"))


if __name__ == "__main__":
    unittest.main()
