import os
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from validate_static import (
    DuplicateJSONKeyError,
    OpenStepParseError,
    apple_workflow_contract_errors,
    apple_upload_workflow_contract_errors,
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
    swiftui_unlocalized_copy_literals,
    swift_model_persisted_properties,
    swift_unsafe_escape_hatches,
)


class AppleWorkflowContractTests(unittest.TestCase):
    def test_current_workflow_obeys_public_no_cost_contract(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github" / "workflows" / "apple-native-checks.yml").read_text(encoding="utf-8")

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


class AppleUploadWorkflowContractTests(unittest.TestCase):
    def test_current_upload_workflow_is_manual_and_confirmed(self) -> None:
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github" / "workflows" / "apple-app-store-upload.yml").read_text(encoding="utf-8")

        self.assertEqual(apple_upload_workflow_contract_errors(workflow), [])

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
        self.assertIn("missing read-only repository permission", errors)
        self.assertIn("missing iPad Simulator regression suite", errors)
        self.assertIn("distribution upload workflow must not run on push, pull request, or schedule", errors)
        self.assertIn("workflow must not enable shell tracing or print App Store Connect key material", errors)


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

