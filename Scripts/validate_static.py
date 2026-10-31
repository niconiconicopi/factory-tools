from __future__ import annotations

import argparse
import json
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []
DEFAULT_BASE_STOREFRONT_CANDIDATE = "JP"
DEFAULT_BASE_STOREFRONT_PRICE_CANDIDATE = "JPY:980"


def require(condition: bool, message: str) -> None:
    if not condition:
        ERRORS.append(message)


class OpenStepParseError(ValueError):
    pass


class DuplicateJSONKeyError(ValueError):
    pass


def parse_json_no_duplicates(source: str) -> object:
    def make_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
        value: dict[str, object] = {}
        for key, item in pairs:
            if key in value:
                raise DuplicateJSONKeyError(f"duplicate JSON key {key!r}")
            value[key] = item
        return value

    return json.loads(source, object_pairs_hook=make_object)


def parse_openstep(source: str) -> object:
    index = 0
    length = len(source)

    def skip_trivia() -> None:
        nonlocal index
        while index < length:
            if source[index].isspace():
                index += 1
            elif source.startswith("//", index):
                newline = source.find("\n", index + 2)
                index = length if newline == -1 else newline + 1
            elif source.startswith("/*", index):
                closing = source.find("*/", index + 2)
                if closing == -1:
                    raise OpenStepParseError(f"unterminated block comment at offset {index}")
                index = closing + 2
            else:
                return

    def read_quoted() -> str:
        nonlocal index
        index += 1
        value: list[str] = []
        while index < length:
            char = source[index]
            index += 1
            if char == '"':
                return "".join(value)
            if char == "\\":
                if index == length:
                    raise OpenStepParseError("unterminated escape in quoted string")
                value.append(source[index])
                index += 1
            else:
                value.append(char)
        raise OpenStepParseError("unterminated quoted string")

    def read_atom() -> str:
        nonlocal index
        start = index
        while index < length and not source[index].isspace() and source[index] not in "{}()=;,\"":
            if source.startswith("/*", index) or source.startswith("//", index):
                break
            index += 1
        if index == start:
            raise OpenStepParseError(f"expected a value at offset {index}")
        return source[start:index]

    def expect(character: str) -> None:
        nonlocal index
        skip_trivia()
        if index >= length or source[index] != character:
            raise OpenStepParseError(f"expected {character!r} at offset {index}")
        index += 1

    def read_key() -> str:
        skip_trivia()
        if index >= length:
            raise OpenStepParseError("expected a dictionary key at end of file")
        return read_quoted() if source[index] == '"' else read_atom()

    def read_dictionary() -> dict[str, object]:
        nonlocal index
        expect("{")
        value: dict[str, object] = {}
        while True:
            skip_trivia()
            if index >= length:
                raise OpenStepParseError("unterminated dictionary")
            if source[index] == "}":
                index += 1
                return value
            key = read_key()
            expect("=")
            item = read_value()
            expect(";")
            if key in value:
                raise OpenStepParseError(f"duplicate dictionary key {key!r}")
            value[key] = item

    def read_array() -> list[object]:
        nonlocal index
        expect("(")
        value: list[object] = []
        while True:
            skip_trivia()
            if index >= length:
                raise OpenStepParseError("unterminated array")
            if source[index] == ")":
                index += 1
                return value
            value.append(read_value())
            skip_trivia()
            if index < length and source[index] == ",":
                index += 1
            elif index >= length or source[index] != ")":
                raise OpenStepParseError(f"expected ',' or ')' at offset {index}")

    def read_value() -> object:
        nonlocal index
        skip_trivia()
        if index >= length:
            raise OpenStepParseError("expected a value at end of file")
        if source[index] == "{":
            return read_dictionary()
        if source[index] == "(":
            return read_array()
        if source[index] == '"':
            return read_quoted()
        return read_atom()

    result = read_value()
    skip_trivia()
    if index != length:
        raise OpenStepParseError(f"unexpected content at offset {index}")
    return result


def local_project_file_references(
    project_objects: dict[str, object],
    project_object: dict[str, object],
    root: Path,
) -> list[Path]:
    references: list[Path] = []
    visited_groups: set[str] = set()

    def visit_group(group_id: object, parent_path: Path) -> None:
        if not isinstance(group_id, str) or group_id in visited_groups:
            return
        group = project_objects.get(group_id)
        if not isinstance(group, dict):
            return
        if group.get("isa") not in {"PBXGroup", "PBXVariantGroup"}:
            return
        visited_groups.add(group_id)
        group_path = group.get("path")
        current_path = parent_path / group_path if isinstance(group_path, str) else parent_path
        children = group.get("children", [])
        if not isinstance(children, list):
            return
        for child_id in children:
            child = project_objects.get(child_id) if isinstance(child_id, str) else None
            if not isinstance(child, dict):
                continue
            if child.get("isa") in {"PBXGroup", "PBXVariantGroup"}:
                visit_group(child_id, current_path)
                continue
            if child.get("isa") != "PBXFileReference" or child.get("sourceTree", "<group>") != "<group>":
                continue
            file_path = child.get("path", child.get("name"))
            if isinstance(file_path, str):
                references.append(current_path / file_path)

    visit_group(project_object.get("mainGroup"), root)
    return references


def delimiters_are_balanced(source: str) -> bool:
    pairs = {"}": "{", "]": "[", ")": "("}
    stack: list[str] = []
    quoted = escaped = line_comment = block_comment = False
    index = 0
    while index < len(source):
        char = source[index]
        following = source[index + 1] if index + 1 < len(source) else ""
        if line_comment:
            line_comment = char != "\n"
        elif block_comment:
            if char == "*" and following == "/":
                block_comment = False
                index += 1
        elif quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == "/" and following == "/":
            line_comment = True
            index += 1
        elif char == "/" and following == "*":
            block_comment = True
            index += 1
        elif char == '"':
            quoted = True
        elif char in "{[(":
            stack.append(char)
        elif char in "}])":
            if not stack or stack.pop() != pairs[char]:
                return False
        index += 1
    return not stack and not quoted and not block_comment


def relative_luminance(rgb: tuple[float, float, float]) -> float:
    linear = tuple(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in rgb)
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(first: tuple[float, float, float], second: tuple[float, float, float]) -> float:
    brighter, darker = sorted((relative_luminance(first), relative_luminance(second)), reverse=True)
    return (brighter + 0.05) / (darker + 0.05)


def bypasses_app_theme_manager(source: str) -> bool:
    return re.search(r"\bAppTheme\s*\.\s*industrialDark\b", source) is not None


def localization_placeholder_count(value: str) -> int:
    pattern = r"%(?:\d+\$)?(?:[-+#0 ]*\d*(?:\.\d+)?)?(?:hh|h|ll|l|q|z|t|L)?[@diuoxXfFeEgGaAcCsSp]"
    return len(re.findall(pattern, value))


def swiftui_unlocalized_copy_literals(source: str, catalog_keys: set[str]) -> list[tuple[int, str]]:
    """Find direct SwiftUI text literals that look like copy rather than localization keys."""
    pattern = re.compile(
        r'(?:Text|Button|Label|Section|NavigationLink|Picker|TextField|LabeledContent|'
        r'accessibilityLabel|accessibilityHint)\s*\(\s*"((?:\\.|[^"\\])*)"'
    )
    issues: list[tuple[int, str]] = []
    for match in pattern.finditer(source):
        literal = match.group(1)
        if literal in catalog_keys:
            continue
        # Swift interpolation can contain nested string literals, which a
        # lightweight source scan cannot parse safely. Leave those values to
        # the catalog-key and focused source checks below.
        if "\\(" in literal:
            continue
        if not any(character.isalpha() for character in literal):
            continue
        line = source.count("\n", 0, match.start()) + 1
        issues.append((line, literal))
    return issues


def localized_info_plist_value(source: str, key: str) -> str | None:
    match = re.search(
        rf'(?m)^\s*"?{re.escape(key)}"?\s*=\s*"((?:\\.|[^"\\])*)"\s*;',
        source,
    )
    return match.group(1) if match else None


def has_supported_ios_launch_screen(info: dict[str, object]) -> bool:
    return any(key in info for key in (
        "UILaunchStoryboardName",
        "UILaunchStoryboards",
        "UILaunchScreen",
        "UILaunchScreens",
    ))


def has_distinct_localized_copy(japanese: str | None, english: str | None) -> bool:
    return bool(japanese and japanese.strip() and english and english.strip() and japanese != english)


def is_https_url(value: object) -> bool:
    if not isinstance(value, str) or not value.strip() or re.search(r"\s", value):
        return False
    try:
        parsed = urlsplit(value)
        _ = parsed.port
    except ValueError:
        return False
    return (
        parsed.scheme.lower() == "https"
        and bool(parsed.hostname)
        and parsed.username is None
        and parsed.password is None
    )


def is_opaque_png(data: bytes) -> bool:
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        return False
    offset = len(signature)
    color_type: int | None = None
    has_transparency_chunk = False
    saw_image_end = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk_type = data[offset + 4:offset + 8]
        chunk_start = offset + 8
        chunk_end = chunk_start + length
        if chunk_end + 4 > len(data):
            return False
        if chunk_type == b"IHDR":
            if length != 13:
                return False
            color_type = data[chunk_start + 9]
        elif chunk_type == b"tRNS":
            has_transparency_chunk = True
        elif chunk_type == b"IEND":
            if length != 0:
                return False
            saw_image_end = True
            break
        offset = chunk_end + 4
    return color_type in {0, 2, 3} and not has_transparency_chunk and saw_image_end


def apple_workflow_contract_errors(source: str) -> list[str]:
    """Guard the public-free and manually gated private native verification workflow contract."""
    requirements = {
        "public or manually confirmed private-run job condition": "if: github.event.repository.visibility == 'public' || (github.event_name == 'workflow_dispatch' && inputs.enable_private_macos_runner == true && vars.FACTORYTOOLS_PRIVATE_MACOS_CI == 'enabled')",
        "private runner confirmation is required by default": "enable_private_macos_runner:\n        description: Confirm FACTORYTOOLS_PRIVATE_MACOS_CI is enabled only after a no-overage billing guard is verified.\n        required: true\n        type: boolean\n        default: false",
        "read-only repository permission": "permissions:\n  contents: read",
        "pinned checkout major version": "uses: actions/checkout@v7",
        "checkout credential persistence disabled": "persist-credentials: false",
        "standard macOS runner": "runs-on: macos-26",
        "source contract checks": "python3 -B -m unittest discover -s Scripts -p 'test_*.py'",
        "iPhone Simulator XCTest": "-scheme FactoryTools",
        "shared Core XCTest": "-scheme FactoryToolsCore",
        "Watch Simulator build": "-scheme FactoryToolsWatch",
        "code signing disabled": "CODE_SIGNING_ALLOWED=NO",
    }
    errors = [f"missing {label}" for label, text in requirements.items() if text not in source]
    if re.search(r"\bsecrets\.[A-Z0-9_]+\b", source):
        errors.append("workflow must not access repository secrets")
    return errors


def swift_unsafe_escape_hatches(source: str) -> list[str]:
    patterns = {
        "fatalError": r"\bfatalError\s*\(",
        "preconditionFailure": r"\bpreconditionFailure\s*\(",
        "assertionFailure": r"\bassertionFailure\s*\(",
        "forced try": r"\btry!\s*\S",
        "forced cast": r"\bas!\s+[A-Za-z_]",
        "forced unwrap": r"(?:\b[A-Za-z_]\w*|\)|\])!(?![=])",
    }
    return [name for name, pattern in patterns.items() if re.search(pattern, source)]


def app_store_metadata_limit_errors(markdown: str) -> list[str]:
    errors: list[str] = []
    for locale, heading in (("ja-JP", "Japanese (ja-JP)"), ("en-US", "English (en-US)")):
        section_match = re.search(
            rf"(?ms)^## {re.escape(heading)}\s*\n(.*?)(?=^## |\Z)",
            markdown,
        )
        if not section_match:
            errors.append(f"Missing {locale} App Store listing section.")
            continue
        section = section_match.group(1).strip()

        def field_value(field: str) -> str | None:
            match = re.search(
                rf"(?ms)^\*\*{re.escape(field)}\*\*\s*\n(.*?)(?=\n\s*\n\*\*|\Z)",
                section,
            )
            return match.group(1).strip() if match else None

        name = field_value("Name")
        subtitle = field_value("Subtitle")
        keywords = field_value("Keywords")
        description_match = re.search(r"(?ms)^\*\*Description\*\*\s*\n(.*)\Z", section)
        description = description_match.group(1).strip() if description_match else None
        for field, value in (("name", name), ("subtitle", subtitle), ("keywords", keywords), ("description", description)):
            if not value:
                errors.append(f"Missing {locale} App Store {field}.")
        if name and not 2 <= len(name) <= 30:
            errors.append(f"{locale} App Store name exceeds the 2–30 character limit.")
        if subtitle and len(subtitle) > 30:
            errors.append(f"{locale} App Store subtitle exceeds the 30-character limit.")
        if keywords and len(keywords.encode("utf-8")) > 100:
            errors.append(f"{locale} App Store keywords exceed the 100-byte UTF-8 limit.")
        if description and len(description) > 4000:
            errors.append(f"{locale} App Store description exceeds the 4,000-character limit.")
    return errors


def in_app_purchase_metadata_limit_errors(markdown: str) -> list[str]:
    errors: list[str] = []
    for locale, heading in (
        ("ja-JP", "Japanese product localization (ja-JP)"),
        ("en-US", "English product localization (en-US)"),
    ):
        section_match = re.search(
            rf"(?ms)^### {re.escape(heading)}\s*\n(.*?)(?=^### |^## |\Z)",
            markdown,
        )
        if not section_match:
            errors.append(f"Missing {locale} In-App Purchase localization.")
            continue
        section = section_match.group(1).strip()

        def field_value(field: str) -> str | None:
            match = re.search(
                rf"(?ms)^\*\*{re.escape(field)}\*\*\s*\n(.*?)(?=\n\s*\n\*\*|\Z)",
                section,
            )
            return match.group(1).strip() if match else None

        display_name = field_value("Display Name")
        description = field_value("Description")
        if not display_name:
            errors.append(f"Missing {locale} In-App Purchase display name.")
        elif not 2 <= len(display_name) <= 30:
            errors.append(f"{locale} In-App Purchase display name exceeds the 2–30 character limit.")
        if not description:
            errors.append(f"Missing {locale} In-App Purchase description.")
        elif len(description) > 45:
            errors.append(f"{locale} In-App Purchase description exceeds the 45-character limit.")
    if "**Type:** Non-consumable (one-time purchase)" not in markdown:
        errors.append("Factory Tools Pro must be listed as a non-consumable In-App Purchase.")
    if "**Product ID:** `factorytools.pro.lifetime` (candidate; use this exact value in App Store Connect)" not in markdown:
        errors.append("App Store listing draft must identify the selected Factory Tools Pro StoreKit product ID candidate.")
    if "**App Review Screenshot:** Capture the Pro purchase panel from the signed release build" not in markdown:
        errors.append("App Store listing draft must include the In-App Purchase review screenshot gate.")
    if "**Availability and price:** All currently available App Store territories where permitted; Japan base storefront, JPY ¥980 (confirmed); review Apple's generated local prices before release." not in markdown:
        errors.append("Factory Tools Pro metadata must show all-territory availability, the confirmed Japan base price, and regional-price review.")
    return errors


def local_markdown_link_errors(source_path: Path, markdown: str) -> list[str]:
    errors: list[str] = []
    pattern = re.compile(r"!?\[[^\]]*\]\((<[^>]+>|[^)\s]+)(?:\s+[^)]*)?\)")
    for match in pattern.finditer(markdown):
        destination = match.group(1).strip()
        if destination.startswith("<") and destination.endswith(">"):
            destination = destination[1:-1]
        parsed = urlsplit(destination)
        if parsed.scheme or parsed.netloc or not parsed.path:
            continue
        linked_path = source_path.parent / unquote(parsed.path)
        if not linked_path.exists():
            line = markdown.count("\n", 0, match.start()) + 1
            errors.append(f"{source_path}:{line}: unresolved local Markdown link {destination!r}")
    return errors


def is_valid_storekit_product_id(value: str) -> bool:
    return len(value) <= 100 and re.fullmatch(r"[A-Za-z0-9._-]+", value) is not None


def is_valid_app_store_sku(value: str) -> bool:
    return re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value) is not None


def is_valid_price_candidate(value: str) -> bool:
    match = re.fullmatch(r"([A-Z]{3}):([0-9]+(?:\.[0-9]{1,3})?)", value.strip())
    if not match:
        return False
    try:
        amount = Decimal(match.group(2))
    except InvalidOperation:
        return False
    return amount.is_finite() and amount > 0


def is_valid_base_storefront_candidate(value: str) -> bool:
    return re.fullmatch(r"[A-Z]{2}", value.strip()) is not None


def swift_model_persisted_properties(source: str, model_name: str) -> set[str]:
    body_match = re.search(
        rf"@Model\s+final class {re.escape(model_name)}\s*\{{(.*?)(?=^\}})",
        source,
        re.MULTILINE | re.DOTALL,
    )
    if not body_match:
        return set()
    return set(re.findall(
        r"(?m)^    (?:@Attribute\([^)]*\)\s+)?var\s+([A-Za-z][A-Za-z0-9]*)\s*:\s*[^{}\n]+$",
        body_match.group(1),
    ))


def family_sharing_decision(product_decisions: str) -> str | None:
    match = re.search(r"(?m)^- Family Sharing: \*\*(enabled|disabled) for Version 1\*\*\.", product_decisions)
    return match.group(1) if match else None


def resolve_family_sharing_candidate(
    product_decisions: str,
    candidate: str | None,
) -> tuple[str | None, bool]:
    approved = family_sharing_decision(product_decisions)
    conflicts = candidate is not None and approved is not None and candidate != approved
    return candidate or approved, conflicts


def bonjour_declaration_matches(info_services: object, transport_source: str) -> bool:
    match = re.search(r'\bserviceType\s*=\s*"([^"\s]+)"', transport_source)
    return bool(match and isinstance(info_services, list) and match.group(1) in info_services)


def release_preflight_blockers(
    app_bundle_id: str,
    marketing_version: str,
    build_number: str,
    watch_bundle_id: str,
    watch_companion_bundle_id: str,
    app_icon_valid: bool,
    watch_icon_valid: bool,
) -> list[str]:
    blockers: list[str] = []
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", app_bundle_id):
        blockers.append("Set a publisher-owned reverse-DNS iPhone Bundle ID.")
    elif "example" in {component.lower() for component in app_bundle_id.split(".")}:
        blockers.append("Replace the development-only com.example Bundle ID with a publisher-owned ID.")

    version_match = re.fullmatch(r"(\d+)\.\d+(?:\.\d+)?", marketing_version)
    if not version_match or int(version_match.group(1)) == 0:
        blockers.append("Replace the 0.x or malformed development marketing version with a release version.")
    if not build_number.isdigit() or int(build_number) < 1:
        blockers.append("Set a positive build number.")
    if watch_bundle_id != f"{app_bundle_id}.watchkitapp":
        blockers.append("Make the Watch Bundle ID derive from the iPhone Bundle ID with the .watchkitapp suffix.")
    if watch_companion_bundle_id != app_bundle_id:
        blockers.append("Set the Watch companion Bundle ID to match the iPhone Bundle ID.")
    if not app_icon_valid:
        blockers.append("Provide a valid opaque 1024px iPhone AppIcon asset.")
    if not watch_icon_valid:
        blockers.append("Provide a valid opaque 1024px watchOS AppIcon asset.")
    return blockers


def release_preflight_configuration_blockers(
    configuration_name: str,
    project_settings: dict[str, object],
    app_settings: dict[str, object],
    watch_settings: dict[str, object],
    app_icon_catalog_valid: bool,
    watch_icon_catalog_valid: bool,
    pro_price_candidate: str | None = None,
    family_sharing_candidate: str | None = None,
    base_storefront_candidate: str | None = None,
) -> list[str]:
    def resolve_project_setting(value: object) -> str:
        resolved = str(value)
        for key, replacement in project_settings.items():
            if isinstance(replacement, (str, int, float)):
                resolved = resolved.replace(f"$({key})", str(replacement))
        return resolved

    app_bundle_id = resolve_project_setting(app_settings.get("PRODUCT_BUNDLE_IDENTIFIER", ""))
    watch_bundle_id = resolve_project_setting(watch_settings.get("PRODUCT_BUNDLE_IDENTIFIER", ""))
    blockers = release_preflight_blockers(
        app_bundle_id=app_bundle_id,
        marketing_version=str(project_settings.get("MARKETING_VERSION", "")),
        build_number=str(project_settings.get("CURRENT_PROJECT_VERSION", "")),
        watch_bundle_id=watch_bundle_id,
        watch_companion_bundle_id=resolve_project_setting(
            watch_settings.get("INFOPLIST_KEY_WKCompanionAppBundleIdentifier", "")
        ),
        app_icon_valid=(
            app_icon_catalog_valid
            and app_settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon"
        ),
        watch_icon_valid=(
            watch_icon_catalog_valid
            and watch_settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon"
        ),
    )
    team_id = str(
        project_settings.get("DEVELOPMENT_TEAM")
        or app_settings.get("DEVELOPMENT_TEAM")
        or watch_settings.get("DEVELOPMENT_TEAM")
        or ""
    ).strip()
    if configuration_name == "Release" and not team_id:
        blockers.append("Set the Apple Developer Team ID for signing.")
    privacy_policy_value = app_settings.get(
        "FACTORYTOOLS_PRIVACY_POLICY_URL",
        project_settings.get("FACTORYTOOLS_PRIVACY_POLICY_URL", ""),
    )
    privacy_policy_url = resolve_project_setting(privacy_policy_value)
    if configuration_name == "Release" and not is_https_url(privacy_policy_url):
        blockers.append("Set the publisher-owned HTTPS Privacy Policy URL for the in-app link and App Store Connect.")
    support_url_value = project_settings.get("FACTORYTOOLS_SUPPORT_URL", "")
    support_url = resolve_project_setting(support_url_value)
    if configuration_name == "Release" and not is_https_url(support_url):
        blockers.append("Set the publisher-owned HTTPS Support URL with current contact information.")
    product_id = str(project_settings.get("FACTORYTOOLS_PRO_PRODUCT_ID", "")).strip()
    if configuration_name == "Release" and not is_valid_storekit_product_id(product_id):
        blockers.append("Set the App Store Connect non-consumable Factory Tools Pro product ID.")
    if configuration_name == "Release" and not (
        pro_price_candidate is not None and is_valid_price_candidate(pro_price_candidate)
    ):
        blockers.append(
            "Supply a valid base storefront price candidate as CURRENCY:AMOUNT; Japan's JPY 980 price remains fixed separately."
        )
    if configuration_name == "Release" and not (
        base_storefront_candidate is not None
        and is_valid_base_storefront_candidate(base_storefront_candidate)
    ):
        blockers.append(
            "Supply a two-letter base storefront country/region candidate; verify the actual territory in App Store Connect."
        )
    if configuration_name == "Release" and family_sharing_candidate not in {"enabled", "disabled"}:
        blockers.append("Decide whether Factory Tools Pro supports Family Sharing.")
    return [f"{configuration_name}: {blocker}" for blocker in blockers]


def apply_release_candidate_overrides(
    project_settings: dict[str, object],
    bundle_id: str | None = None,
    marketing_version: str | None = None,
    build_number: str | None = None,
    team_id: str | None = None,
    privacy_policy_url: str | None = None,
    pro_product_id: str | None = None,
    support_url: str | None = None,
) -> dict[str, object]:
    candidate_settings = dict(project_settings)
    if bundle_id is not None:
        candidate_settings["FACTORYTOOLS_APP_BUNDLE_ID"] = bundle_id
    if marketing_version is not None:
        candidate_settings["MARKETING_VERSION"] = marketing_version
    if build_number is not None:
        candidate_settings["CURRENT_PROJECT_VERSION"] = build_number
    if team_id is not None:
        candidate_settings["DEVELOPMENT_TEAM"] = team_id
    if privacy_policy_url is not None:
        candidate_settings["FACTORYTOOLS_PRIVACY_POLICY_URL"] = privacy_policy_url
    if pro_product_id is not None:
        candidate_settings["FACTORYTOOLS_PRO_PRODUCT_ID"] = pro_product_id
    if support_url is not None:
        candidate_settings["FACTORYTOOLS_SUPPORT_URL"] = support_url
    return candidate_settings


def main() -> int:
    argument_parser = argparse.ArgumentParser(description="Validate Factory Tools project sources and resources.")
    argument_parser.add_argument(
        "--release-preflight",
        action="store_true",
        help="also check source-level release settings; this is not a release approval",
    )
    argument_parser.add_argument(
        "--candidate-bundle-id",
        help="check a candidate publisher Bundle ID without changing project settings",
    )
    argument_parser.add_argument(
        "--candidate-marketing-version",
        help="check a candidate release version without changing project settings",
    )
    argument_parser.add_argument(
        "--candidate-build-number",
        help="check a candidate positive build number without changing project settings",
    )
    argument_parser.add_argument(
        "--candidate-team-id",
        help="check a candidate Apple Developer Team ID without changing project settings",
    )
    argument_parser.add_argument(
        "--candidate-privacy-policy-url",
        help="check a candidate public HTTPS Privacy Policy URL without changing project settings",
    )
    argument_parser.add_argument(
        "--candidate-support-url",
        help="check a candidate public HTTPS Support URL with contact information without changing project settings",
    )
    argument_parser.add_argument(
        "--candidate-pro-product-id",
        help="check a candidate App Store Connect non-consumable product ID without changing project settings",
    )
    argument_parser.add_argument(
        "--candidate-base-storefront-price",
        "--candidate-pro-price",
        dest="candidate_pro_price",
        help="override the selected JP / JPY:980 base-storefront candidate; CURRENCY:AMOUNT syntax only and changes no settings",
    )
    argument_parser.add_argument(
        "--candidate-base-storefront",
        help="override the selected JP / JPY:980 base-storefront candidate; two-letter syntax only, does not configure App Store Connect",
    )
    argument_parser.add_argument(
        "--candidate-family-sharing",
        choices=("enabled", "disabled"),
        help="check the intended App Store Connect Family Sharing choice without changing project settings",
    )
    arguments = argument_parser.parse_args()
    candidate_values_supplied = any(value is not None for value in (
        arguments.candidate_bundle_id,
        arguments.candidate_marketing_version,
        arguments.candidate_build_number,
        arguments.candidate_team_id,
        arguments.candidate_privacy_policy_url,
        arguments.candidate_support_url,
        arguments.candidate_pro_product_id,
        arguments.candidate_pro_price,
        arguments.candidate_base_storefront,
        arguments.candidate_family_sharing,
    ))
    if not arguments.release_preflight and candidate_values_supplied:
        argument_parser.error("candidate values require --release-preflight")
    project = ROOT / "FactoryTools.xcodeproj" / "project.pbxproj"
    workflow_path = ROOT / ".github" / "workflows" / "apple-native-checks.yml"
    if workflow_path.is_file():
        workflow_source = workflow_path.read_text(encoding="utf-8")
        for workflow_issue in apple_workflow_contract_errors(workflow_source):
            ERRORS.append(f"Apple native workflow contract: {workflow_issue}")
    else:
        ERRORS.append("Apple native verification workflow is missing")
    scheme = ROOT / "FactoryTools.xcodeproj" / "xcshareddata" / "xcschemes" / "FactoryTools.xcscheme"
    core_scheme = ROOT / "FactoryTools.xcodeproj" / "xcshareddata" / "xcschemes" / "FactoryToolsCore.xcscheme"
    watch_scheme = ROOT / "FactoryTools.xcodeproj" / "xcshareddata" / "xcschemes" / "FactoryToolsWatch.xcscheme"
    catalog = ROOT / "FactoryTools" / "Resources" / "Localizable.xcstrings"
    source_files = (list((ROOT / "FactoryTools").rglob("*.swift"))
                    + list((ROOT / "FactoryToolsCore").rglob("*.swift"))
                    + list((ROOT / "FactoryToolsWatch").rglob("*.swift"))
                    + list((ROOT / "FactoryToolsTests").rglob("*.swift"))
                    + list((ROOT / "FactoryToolsCoreTests").rglob("*.swift")))
    platform_boundaries_path = ROOT / "FactoryTools" / "PLATFORM_BOUNDARIES.md"
    platform_boundaries = platform_boundaries_path.read_text(encoding="utf-8") if platform_boundaries_path.exists() else ""
    require(bool(platform_boundaries)
            and "FactoryToolsCore" in platform_boundaries
            and "CounterCommandReceipt" in platform_boundaries
            and "payload fingerprint" in platform_boundaries
            and "canonical writer" in platform_boundaries
            and "Network.framework Bonjour" in platform_boundaries
            and "iPhone remains the count authority" in platform_boundaries,
            "Watch/iPad boundary document must distinguish reusable core, persistence, command replay, and selected iPad transport direction")
    for source_anchor in (
        "Services/CounterService.swift",
        "Services/WatchCommandProcessor.swift",
        "Services/WatchConnectivityReceiver.swift",
        "Services/LocalPeerPairingKeyStore.swift",
        "Services/LocalPeerCounterOutboxRepository.swift",
        "Services/LocalPeerCounterTransport.swift",
        "Features/Counter/PeerCounterView.swift",
        "Models/CounterCommandReceipt.swift",
        "Models/ToolCard.swift",
        "Tools/ToolDefinition.swift",
        "Tools/ToolRegistry.swift",
        "Tools/LocalizedNumberParser.swift",
        "Settings/AppSettings.swift",
    ):
        require((ROOT / "FactoryTools" / source_anchor).is_file(),
                f"platform boundary document references a missing source file: {source_anchor}")
    for source_anchor in (
        "CounterCommand.swift", "CounterCommandOutbox.swift", "CounterCommandAcknowledgement.swift",
        "CounterPeerMessage.swift", "CounterPeerFrameCodec.swift", "WatchCounterCatalog.swift",
        "WatchCycleTimeCommand.swift", "ToolID.swift"
    ):
        require((ROOT / "FactoryToolsCore" / source_anchor).is_file(),
                f"shared Core source is missing: {source_anchor}")
    for roadmap_path in (ROOT / "FactoryTools" / "README.md", ROOT / "FactoryTools" / "ROADMAP.md"):
        roadmap_text = roadmap_path.read_text(encoding="utf-8")
        require("PLATFORM_BOUNDARIES.md" in roadmap_text,
                f"{roadmap_path.name} must link to the current Watch/iPad boundary proposal")

    try:
        pbx = project.read_text(encoding="utf-8")
    except OSError as error:
        print(f"FAIL: cannot read Xcode project: {error}")
        return 1

    try:
        project_tree = parse_openstep(pbx)
    except OpenStepParseError as error:
        print(f"FAIL: invalid OpenStep Xcode project: {error}")
        return 1
    if not isinstance(project_tree, dict):
        print("FAIL: Xcode project root must be an OpenStep dictionary")
        return 1
    project_objects = project_tree.get("objects")
    root_object_id = project_tree.get("rootObject")
    project_object = project_objects.get(root_object_id) if isinstance(project_objects, dict) and isinstance(root_object_id, str) else None
    if not isinstance(project_objects, dict):
        print("FAIL: Xcode project objects must be a dictionary")
        return 1
    if not isinstance(project_object, dict):
        print("FAIL: Xcode project rootObject does not resolve to a project dictionary")
        return 1
    for file_path in local_project_file_references(project_objects, project_object, ROOT):
        try:
            resolved_path = file_path.resolve()
            resolved_path.relative_to(ROOT.resolve())
            stays_in_workspace = True
        except (OSError, RuntimeError, ValueError):
            resolved_path = file_path
            stays_in_workspace = False
        require(stays_in_workspace,
                f"Xcode project file reference escapes the workspace: {file_path}")
        require(stays_in_workspace and resolved_path.exists(),
                f"Xcode project references a missing local file: {file_path}")

    native_targets = {
        object_id: value
        for object_id, value in project_objects.items()
        if isinstance(value, dict) and value.get("isa") == "PBXNativeTarget"
    }
    target_names = {value.get("name") for value in native_targets.values()}
    require(len(native_targets) == 5 and target_names == {"FactoryTools", "FactoryToolsTests", "FactoryToolsCore", "FactoryToolsCoreTests", "FactoryToolsWatch"},
            f"Project must contain iPhone, Watch, and their Core/test targets, found {sorted(str(name) for name in target_names)}")
    targets_by_name = {value.get("name"): value for value in native_targets.values()}
    app_target = targets_by_name.get("FactoryTools", {})
    test_target = targets_by_name.get("FactoryToolsTests", {})
    core_target = targets_by_name.get("FactoryToolsCore", {})
    core_test_target = targets_by_name.get("FactoryToolsCoreTests", {})
    watch_target = targets_by_name.get("FactoryToolsWatch", {})
    require(app_target.get("productType") == "com.apple.product-type.application",
            "FactoryTools must be an iOS application target")
    require(test_target.get("productType") == "com.apple.product-type.bundle.unit-test",
            "FactoryToolsTests must be a unit-test bundle")
    require(core_target.get("productType") == "com.apple.product-type.framework",
            "FactoryToolsCore must be a local framework target")
    require(core_test_target.get("productType") == "com.apple.product-type.bundle.unit-test",
            "FactoryToolsCoreTests must be a standalone unit-test bundle")
    require(watch_target.get("productType") == "com.apple.product-type.application.watchapp2",
            "FactoryToolsWatch must be a native companion watchOS application target")
    target_ids_by_name = {target.get("name"): target_id for target_id, target in native_targets.items()}

    def direct_target_dependencies(target: object) -> set[str]:
        if not isinstance(target, dict):
            return set()
        dependency_ids = target.get("dependencies", [])
        if not isinstance(dependency_ids, list):
            return set()
        dependency_targets: set[str] = set()
        for dependency_id in dependency_ids:
            dependency = project_objects.get(dependency_id)
            if isinstance(dependency, dict) and isinstance(dependency.get("target"), str):
                dependency_targets.add(dependency["target"])
        return dependency_targets

    expected_target_dependencies = {
        "FactoryTools": {target_ids_by_name.get("FactoryToolsCore")},
        "FactoryToolsTests": {
            target_ids_by_name.get("FactoryTools"),
            target_ids_by_name.get("FactoryToolsCore"),
        },
        "FactoryToolsCore": set(),
        "FactoryToolsCoreTests": {target_ids_by_name.get("FactoryToolsCore")},
        "FactoryToolsWatch": {target_ids_by_name.get("FactoryToolsCore")},
    }
    expected_target_dependencies["FactoryTools"].add(target_ids_by_name.get("FactoryToolsWatch"))
    for target_name, expected_dependencies in expected_target_dependencies.items():
        actual_dependencies = direct_target_dependencies(targets_by_name.get(target_name))
        require(actual_dependencies == expected_dependencies,
                f"{target_name} target dependency boundary changed (expected={sorted(str(value) for value in expected_dependencies)}, "
                f"found={sorted(actual_dependencies)})")

    def target_build_settings(target: object) -> list[tuple[str, dict[str, object]]]:
        if not isinstance(target, dict):
            return []
        configuration_list_id = target.get("buildConfigurationList")
        configuration_list = project_objects.get(configuration_list_id) if isinstance(configuration_list_id, str) else None
        if not isinstance(configuration_list, dict):
            return []
        configuration_ids = configuration_list.get("buildConfigurations", [])
        if not isinstance(configuration_ids, list):
            return []
        result: list[tuple[str, dict[str, object]]] = []
        for configuration_id in configuration_ids:
            configuration = project_objects.get(configuration_id) if isinstance(configuration_id, str) else None
            if not isinstance(configuration, dict):
                continue
            settings = configuration.get("buildSettings")
            if isinstance(settings, dict) and isinstance(configuration.get("name"), str):
                result.append((configuration["name"], settings))
        return result

    project_build_settings = target_build_settings(project_object)
    app_build_settings = target_build_settings(app_target)
    test_build_settings = target_build_settings(test_target)
    core_build_settings = target_build_settings(core_target)
    core_test_build_settings = target_build_settings(core_test_target)
    watch_build_settings = target_build_settings(watch_target)
    app_bundle_identifiers = {settings.get("PRODUCT_BUNDLE_IDENTIFIER") for _, settings in app_build_settings}
    require(len(project_build_settings) == 2
            and {name for name, _ in project_build_settings} == {"Debug", "Release"}
            and all(settings.get("FACTORYTOOLS_APP_BUNDLE_ID") == "com.example.FactoryTools" for _, settings in project_build_settings)
            and all(settings.get("FACTORYTOOLS_PRIVACY_POLICY_URL") == "" for _, settings in project_build_settings)
            and all(settings.get("FACTORYTOOLS_SUPPORT_URL") == "" for _, settings in project_build_settings)
            and all(settings.get("FACTORYTOOLS_PRO_PRODUCT_ID") == "factorytools.pro.lifetime" for _, settings in project_build_settings)
            and all(settings.get("MARKETING_VERSION") == "1.0" for _, settings in project_build_settings)
            and all(settings.get("CURRENT_PROJECT_VERSION") == "1" for _, settings in project_build_settings)
            and all("MARKETING_VERSION" not in settings and "CURRENT_PROJECT_VERSION" not in settings
                    for _, settings in app_build_settings + watch_build_settings)
            and all(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "$(FACTORYTOOLS_APP_BUNDLE_ID)"
                    for _, settings in app_build_settings)
            and all(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "$(FACTORYTOOLS_APP_BUNDLE_ID).watchkitapp"
                    and settings.get("INFOPLIST_KEY_WKCompanionAppBundleIdentifier") == "$(FACTORYTOOLS_APP_BUNDLE_ID)"
                    and settings.get("INFOPLIST_KEY_CFBundleDisplayName") == "Factory Tools"
                    and settings.get("INFOPLIST_KEY_CFBundleName") == "Factory Tools"
                    and settings.get("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption") == "NO"
                    for _, settings in watch_build_settings),
            "iPhone/Watch identity, display name, and version must stay aligned through shared project settings")
    require(len(app_build_settings) == 2 and {name for name, _ in app_build_settings} == {"Debug", "Release"},
            "iPhone app must define Debug and Release build configurations")
    require(len(test_build_settings) == 2 and {name for name, _ in test_build_settings} == {"Debug", "Release"},
            "test target must define Debug and Release build configurations")
    require(len(test_build_settings) == 2
            and all(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "$(FACTORYTOOLS_APP_BUNDLE_ID).tests"
                    for _, settings in test_build_settings)
            and len(core_build_settings) == 2
            and all(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "$(FACTORYTOOLS_APP_BUNDLE_ID).core"
                    for _, settings in core_build_settings)
            and len(core_test_build_settings) == 2
            and all(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "$(FACTORYTOOLS_APP_BUNDLE_ID).coretests"
                    for _, settings in core_test_build_settings),
            "app tests, shared Core, and Core tests must derive unique bundle identifiers from the publisher-owned app ID")
    require(len(core_test_build_settings) == 2 and {name for name, _ in core_test_build_settings} == {"Debug", "Release"}
            and all(settings.get("SDKROOT") == "macosx" for _, settings in core_test_build_settings)
            and all(settings.get("SUPPORTED_PLATFORMS") == "macosx" for _, settings in core_test_build_settings)
            and all("TEST_HOST" not in settings and "BUNDLE_LOADER" not in settings for _, settings in core_test_build_settings),
            "FactoryToolsCoreTests must be an app-independent macOS XCTest target")
    require(len(watch_build_settings) == 2 and {name for name, _ in watch_build_settings} == {"Debug", "Release"}
            and all(settings.get("SDKROOT") == "watchos" for _, settings in watch_build_settings)
            and all(settings.get("SUPPORTED_PLATFORMS") == "watchos watchsimulator" for _, settings in watch_build_settings)
            and all(settings.get("TARGETED_DEVICE_FAMILY") == "4" for _, settings in watch_build_settings)
            and all(settings.get("WATCHOS_DEPLOYMENT_TARGET") == "10.0" for _, settings in watch_build_settings)
            and len(app_bundle_identifiers) == 1
            and all(settings.get("INFOPLIST_KEY_WKCompanionAppBundleIdentifier") in app_bundle_identifiers for _, settings in watch_build_settings),
            "FactoryToolsWatch must be a watchOS 10 companion app target for Apple Watch")
    for configuration_name, settings in app_build_settings:
        require(settings.get("TARGETED_DEVICE_FAMILY") == "1,2",
                f"FactoryTools {configuration_name} must target both iPhone and iPad")
        require(settings.get("IPHONEOS_DEPLOYMENT_TARGET") == "17.0",
                f"FactoryTools {configuration_name} must use the iOS 17 baseline")
        require(settings.get("SWIFT_EMIT_LOC_STRINGS") == "YES",
                f"FactoryTools {configuration_name} must enable String Catalog extraction")
        require(settings.get("INFOPLIST_FILE") == "FactoryTools/Info.plist",
                f"FactoryTools {configuration_name} must use the local-network privacy Info.plist")

    app_info_plist = ROOT / "FactoryTools" / "Info.plist"
    app_info: dict[str, object] = {}
    try:
        with app_info_plist.open("rb") as info_file:
            app_info = plistlib.load(info_file)
        require(app_info.get("UIUserInterfaceStyle") == "Dark",
                "FactoryTools must launch with the Industrial Dark appearance")
        require(has_supported_ios_launch_screen(app_info),
                "FactoryTools must declare an App Store-supported launch screen for iOS 27 SDK uploads")
        require(bool(app_info.get("NSLocalNetworkUsageDescription")),
                "FactoryTools must declare its local-network purpose")
        require(app_info.get("FactoryToolsPrivacyPolicyURL") == "$(FACTORYTOOLS_PRIVACY_POLICY_URL)",
                "FactoryTools must expose the publisher-owned Privacy Policy URL through its build setting")
        require(app_info.get("FactoryToolsSupportURL") == "$(FACTORYTOOLS_SUPPORT_URL)",
                "FactoryTools must expose the publisher-owned Support URL through its build setting")
        require(app_info.get("FactoryToolsProProductID") == "$(FACTORYTOOLS_PRO_PRODUCT_ID)",
                "FactoryTools must expose the publisher-created Pro product ID through its build setting")
        require(app_info.get("ITSAppUsesNonExemptEncryption") is False,
                "FactoryTools must keep the current exempt-only encryption declaration pending publisher export review")
    except (OSError, plistlib.InvalidFileException) as error:
        require(False, f"FactoryTools Info.plist is invalid: {error}")

    pairing_key_store_path = ROOT / "FactoryTools" / "Services" / "LocalPeerPairingKeyStore.swift"
    pairing_key_store_source = pairing_key_store_path.read_text(encoding="utf-8") if pairing_key_store_path.is_file() else ""
    peer_crypto_path = ROOT / "FactoryTools" / "Services" / "LocalPeerCounterTransport.swift"
    peer_crypto_source = peer_crypto_path.read_text(encoding="utf-8") if peer_crypto_path.is_file() else ""
    export_compliance_path = ROOT / "FactoryTools" / "EXPORT_COMPLIANCE_REVIEW.md"
    export_compliance_source = export_compliance_path.read_text(encoding="utf-8") if export_compliance_path.is_file() else ""
    require("sec_protocol_options_add_pre_shared_key(" in peer_crypto_source
            and "sec_protocol_options_append_tls_ciphersuite(" in peer_crypto_source
            and "TLS_PSK_WITH_AES_256_GCM_SHA384" in peer_crypto_source
            and "sec_protocol_options_set_min_tls_protocol_version" in peer_crypto_source
            and ".TLSv12" in peer_crypto_source
            and "import CryptoKit" in pairing_key_store_source
            and "SHA256.hash(data:" in pairing_key_store_source
            and "no custom cipher" in export_compliance_source
            and "does **not** mean the app has no encryption" in export_compliance_source
            and "limited to functionality within Apple's operating system requires no encryption documentation" in export_compliance_source
            and "Apple still requires an export-compliance determination" in export_compliance_source
            and "annual self-classification report" in export_compliance_source
            and "consistent with that exempt-only configuration" in export_compliance_source
            and "intended territories" in export_compliance_source,
            "export-compliance review must match the TLS-PSK and system crypto source implementation")

    try:
        catalog_data = parse_json_no_duplicates(catalog.read_text(encoding="utf-8"))
        strings = catalog_data["strings"]
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError, KeyError) as error:
        print(f"FAIL: invalid string catalog: {error}")
        return 1

    watch_catalog = ROOT / "FactoryToolsWatch" / "Resources" / "Localizable.xcstrings"
    try:
        watch_catalog_data = parse_json_no_duplicates(watch_catalog.read_text(encoding="utf-8"))
        watch_strings = watch_catalog_data["strings"]
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError, KeyError) as error:
        print(f"FAIL: invalid Watch string catalog: {error}")
        return 1
    expected_watch_string_keys = {
        "watch.title", "watch.storageUnavailable", "watch.storageUnavailable.message", "watch.noCounters", "watch.noCounters.message",
        "watch.refresh", "watch.connection.connected", "watch.connection.waiting", "watch.pending",
        "watch.target", "watch.quickAddFive", "watch.sessionUnavailable", "watch.status.applied",
        "counter.defaultSessionName", "defect.defaultSessionName",
        "watch.status.alreadyApplied", "watch.status.noChange", "watch.status.staleUndo", "watch.status.rejected",
        "watch.queueFull.message",
        "watch.cycleTime", "watch.cycleTime.title", "watch.cycleTime.unitNote", "watch.cycleTime.finish",
        "watch.cycleTime.status.applied", "watch.cycleTime.status.alreadyApplied", "watch.cycleTime.homeChanged",
        "watch.cycleTime.startOrResume", "watch.cycleTime.pause", "watch.cycleTime.reset",
        "watch.cycleTime.reset.hint", "watch.cycleTime.reset.confirmation", "watch.cycleTime.cancel",
        "watch.productionProgress", "watch.progress.current", "watch.progress.fraction",
        "watch.productionProgress.noTarget",
    }
    require(set(watch_strings) == expected_watch_string_keys and watch_catalog_data.get("sourceLanguage") == "ja",
            "Watch String Catalog must contain exactly the localized keys used by the Watch UI")
    for key in expected_watch_string_keys:
        localizations = watch_strings.get(key, {}).get("localizations", {})
        require({"ja", "en"}.issubset(localizations)
                and all(localizations[language].get("stringUnit", {}).get("state") == "translated"
                        and bool(localizations[language].get("stringUnit", {}).get("value"))
                        for language in ("ja", "en")),
                f"Watch string {key} must have complete Japanese and English translations")

    development_region = project_object.get("developmentRegion")
    known_regions = project_object.get("knownRegions")
    project_regions = set(known_regions) if isinstance(known_regions, list) else set()
    require(isinstance(development_region, str) and catalog_data.get("sourceLanguage") == development_region,
            "the string catalog source language must match the Xcode project development region")
    require({"ja", "en"}.issubset(project_regions),
            "the Xcode project must declare both supported localization regions")

    package_reference_kinds = (
        "XCRemoteSwiftPackageReference",
        "XCLocalSwiftPackageReference",
        "XCSwiftPackageProductDependency",
    )
    for reference_kind in package_reference_kinds:
        require(reference_kind not in pbx, f"Xcode project declares a Swift package dependency ({reference_kind})")
    package_locks = list(project.parent.rglob("Package.resolved"))
    require(not package_locks, f"Xcode project contains resolved Swift package lockfiles: {[str(path.relative_to(ROOT)) for path in package_locks]}")
    app_framework_phase = re.search(
        r"^\s*D00000000000000000000001 /\* Frameworks \*/ = \{.*?files = \((.*?)\);",
        pbx,
        re.MULTILINE | re.DOTALL,
    )
    app_frameworks = set(re.findall(r"/\* ([^*]+) in Frameworks \*/", app_framework_phase.group(1))) if app_framework_phase else set()
    require(app_frameworks == {"FactoryToolsCore.framework"},
            f"iPhone app may link only the local shared Core framework, found {sorted(app_frameworks)}")
    test_framework_phase = re.search(
        r"^\s*D00000000000000000000002 /\* Frameworks \*/ = \{.*?files = \((.*?)\);",
        pbx,
        re.MULTILINE | re.DOTALL,
    )
    test_frameworks = set(re.findall(r"/\* ([^*]+) in Frameworks \*/", test_framework_phase.group(1))) if test_framework_phase else set()
    require(test_frameworks == {"XCTest.framework", "FactoryToolsCore.framework"},
            f"test target frameworks must include XCTest and local Core only, found {sorted(test_frameworks)}")
    core_test_framework_phase = re.search(
        r"^\s*D00000000000000000000004 /\* Core Tests Frameworks \*/ = \{.*?files = \((.*?)\);",
        pbx,
        re.MULTILINE | re.DOTALL,
    )
    core_test_frameworks = set(re.findall(r"/\* ([^*]+) in Frameworks \*/", core_test_framework_phase.group(1))) if core_test_framework_phase else set()
    require(core_test_frameworks == {"XCTest.framework", "FactoryToolsCore.framework"},
            f"standalone Core test bundle may link XCTest and the local Core framework only, found {sorted(core_test_frameworks)}")
    core_build_settings = target_build_settings(core_target)
    require(len(core_build_settings) == 2 and {name for name, _ in core_build_settings} == {"Debug", "Release"}
            and all(settings.get("DEFINES_MODULE") == "YES" for _, settings in core_build_settings)
            and all(settings.get("MACH_O_TYPE") == "staticlib" for _, settings in core_build_settings)
            and all(settings.get("SUPPORTED_PLATFORMS") == "iphoneos iphonesimulator macosx watchos watchsimulator" for _, settings in core_build_settings)
            and all(settings.get("SDKROOT") == "auto" for _, settings in core_build_settings)
            and all(settings.get("ALLOW_TARGET_PLATFORM_SPECIALIZATION") == "YES" for _, settings in core_build_settings)
            and all(settings.get("MACOSX_DEPLOYMENT_TARGET") == "13.0" for _, settings in core_build_settings),
            "FactoryToolsCore must be a local static framework that selects iOS, simulator, macOS, and watchOS slices by destination")
    require("PBXShellScriptBuildPhase" not in pbx,
            "Xcode project must not run unreviewed shell build phases")
    require(delimiters_are_balanced(pbx), "Xcode project has unbalanced OpenStep delimiters")
    for path in source_files:
        source_text = path.read_text(encoding="utf-8")
        require(delimiters_are_balanced(source_text),
                f"{path.relative_to(ROOT)} has unbalanced source delimiters")
        unsafe_operations = swift_unsafe_escape_hatches(source_text)
        if any(part.endswith("Tests") for part in path.parts):
            # XCTest fixtures deliberately force-unwrap fixed UUIDs and other known-good data.
            unsafe_operations = [operation for operation in unsafe_operations if operation != "forced unwrap"]
        require(not unsafe_operations,
                f"{path.relative_to(ROOT)} contains crash-prone Swift escape hatches: {unsafe_operations}")
    app_entry = (ROOT / "FactoryTools" / "App" / "FactoryToolsApp.swift").read_text(encoding="utf-8")
    persistence_schema = (ROOT / "FactoryTools" / "Persistence" / "FactoryToolsSchema.swift").read_text(encoding="utf-8")
    require("AppBootstrapView()" in app_entry and ".modelContainer(container)" in app_entry,
            "the app scene must launch the bootstrap view with its persistent SwiftData container")
    schema_inventory = re.search(r"static var models: \[any PersistentModel\.Type\] \{(.*?)\n    \}", persistence_schema, re.DOTALL)
    require(schema_inventory is not None
            and all(f"{model}.self" in schema_inventory.group(1) for model in (
                "HomeProfile", "ToolCard", "ProductionSession", "CountEvent", "AppSettings",
                "CycleTimeSample", "OEERun", "CounterCommandReceipt"
            ))
            and "Schema.Version(1, 0, 0)" in persistence_schema
            and "static var schemas: [any VersionedSchema.Type]" in persistence_schema
            and "[FactoryToolsSchemaV1.self]" in persistence_schema
            and "static var stages: [MigrationStage]" in persistence_schema,
            "the first-release SwiftData schema must freeze all current models in V1 and declare its migration plan")
    require("Schema(versionedSchema: FactoryToolsSchemaV1.self)" in app_entry
            and "migrationPlan: FactoryToolsMigrationPlan.self" in app_entry,
            "the app's persistent container must use the versioned V1 schema and migration plan")
    versioned_schema_tests_source = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    versioned_schema_test = re.search(
        r"func testVersionedSchemaV1DefinesAllPersistedModelsAndMigrationPlan\(\)(?: throws)? \{(.*?)(?=\n    func test|\Z)",
        versioned_schema_tests_source,
        re.DOTALL,
    )
    versioned_schema_test_body = versioned_schema_test.group(1) if versioned_schema_test else ""
    require("FactoryToolsSchemaV1.versionIdentifier" in versioned_schema_test_body
            and "FactoryToolsSchemaV1.models.count, 8" in versioned_schema_test_body
            and "FactoryToolsSchemaV1.persistedPropertyInventory.count, 8" in versioned_schema_test_body
            and 'persistedPropertyInventory["ProductionSession"]' in versioned_schema_test_body
            and "FactoryToolsMigrationPlan.schemas.count, 1" in versioned_schema_test_body
            and "FactoryToolsMigrationPlan.stages.isEmpty" in versioned_schema_test_body
            and "Schema(versionedSchema: FactoryToolsSchemaV1.self)" in versioned_schema_test_body
            and "migrationPlan: FactoryToolsMigrationPlan.self" in versioned_schema_test_body
            and "context.fetch(FetchDescriptor<HomeProfile>())" in versioned_schema_test_body,
            "native tests must create a versioned V1 container, check its model inventory, and persist a model")
    require("WatchConnectivityReceiver.shared.start(modelContainer: container)" in app_entry,
            "the iPhone app must activate its WatchConnectivity receiver with the local SwiftData container")
    retry_startup = app_entry.split("private func retryStoreInitialization()", 1)[1]
    require("WatchConnectivityReceiver.shared.start(modelContainer: container)" in retry_startup,
            "retrying local-store initialization must activate WatchConnectivity after the container recovers")
    require("cloudKitDatabase: .none" in app_entry,
            "app storage must explicitly disable CloudKit")
    require("onRetry: retryStoreInitialization" in app_entry
            and "showingRetryError: $showingRetryError" in app_entry
            and "@State private var container: ModelContainer?" in app_entry
            and "private func retryStoreInitialization()" in app_entry
            and "container = try Self.makeContainer()" in app_entry
            and "showingRetryError = true" in app_entry
            and "showingRetryError = false" in app_entry
            and 'Button("common.retry", action: onRetry)' in app_entry
            and '.alert("error.storeUnavailable.title", isPresented: $showingRetryError)' in app_entry
            and "fatalError(" not in app_entry,
            "app must offer an in-place retry when local-store initialization fails")
    require('TARGETED_DEVICE_FAMILY = "1,2"' in pbx, "app target must support universal iPhone and iPad devices")
    require(pbx.count("SWIFT_EMIT_LOC_STRINGS = YES") >= 2,
            "both app configurations must enable localized string extraction for the String Catalog")
    require("CODE_SIGN_ENTITLEMENTS" not in pbx,
            "Phase 1 must not add application entitlements for external services")
    require("ENABLE_TESTABILITY = YES" in pbx
            and pbx.count('BUNDLE_LOADER = "$(TEST_HOST)";') == 2
            and pbx.count('TEST_HOST = "$(BUILT_PRODUCTS_DIR)/FactoryTools.app/FactoryTools";') == 2,
            "Debug tests must host the app and enable @testable module access")
    bootstrap = (ROOT / "FactoryTools" / "App" / "AppBootstrapView.swift").read_text(encoding="utf-8")
    bootstrap_service_match = re.search(
        r"func seedMissingRecords\(\) throws \{([\s\S]*?)\n    \}",
        bootstrap,
    )
    bootstrap_service_body = bootstrap_service_match.group(1) if bootstrap_service_match else ""
    bootstrap_fetch_positions = [
        bootstrap_service_body.find("modelContext.fetch(FetchDescriptor<HomeProfile>())"),
        bootstrap_service_body.find("modelContext.fetch(FetchDescriptor<AppSettings>())"),
        bootstrap_service_body.find("modelContext.fetch(FetchDescriptor<ToolCard>())"),
        bootstrap_service_body.find("modelContext.fetch(FetchDescriptor<ProductionSession>())"),
    ]
    bootstrap_insert_position = bootstrap_service_body.find("if let homeToInsert { modelContext.insert(homeToInsert) }")
    require(all(position >= 0 for position in bootstrap_fetch_positions)
            and bootstrap_fetch_positions == sorted(bootstrap_fetch_positions)
            and bootstrap_insert_position > max(bootstrap_fetch_positions)
            and "if let settingsToInsert { modelContext.insert(settingsToInsert) }" in bootstrap_service_body
            and "modelContext.rollback()" in bootstrap_service_body,
            "bootstrap must complete all fallible reads before inserting seed records and roll back failed saves")
    require(".task { seedInitialDataIfNeeded() }" in bootstrap,
            "bootstrap must repair missing initial data after the root view appears")
    seed_retry = re.search(r"private func seedInitialDataIfNeeded\(\) \{(.*?)(?=\n    \})", bootstrap, re.DOTALL)
    seed_retry_body = seed_retry.group(1) if seed_retry else ""
    require("else if showingSeedError" in bootstrap
            and "ContentUnavailableView(" in bootstrap.split("else if showingSeedError", 1)[1].split("} else {", 1)[0]
            and 'Button("common.retry", action: seedInitialDataIfNeeded)' in bootstrap
            and seed_retry_body.find("showingSeedError = false") < seed_retry_body.find("AppBootstrapService(modelContext: modelContext).seedMissingRecords()")
            and "catch {\n            showingSeedError = true" in seed_retry_body,
            "initial-data save failure must leave a visible retry path and clear the failure state after recovery")
    require("HomeProfileOrdering.ordered(homes).first" in bootstrap
            and "enum HomeProfileOrdering" in (ROOT / "FactoryTools" / "Services" / "HomeToolService.swift").read_text(encoding="utf-8"),
            "startup must select a home deterministically when profile sort orders tie")
    require(".environment(\\.appTheme, activeTheme)" in bootstrap
            and ".environment(\\.font, activeTheme.bodyFont)" in bootstrap,
            "bootstrap must apply the selected theme and its default typography throughout the view hierarchy")
    require(".preferredColorScheme(.dark)" in bootstrap,
            "the Industrial Dark app must start in the dark appearance")
    require(".environment(\\.locale, selectedLocale)" in bootstrap
            and "AppLanguage.resolve(AppSettingsOrdering.primary(in: settings)?.language).locale" in bootstrap,
            "the saved Japanese/English selection must drive the full SwiftUI localization environment")
    require("AppSettingsOrdering.primary(in: settings)?.themeID" in bootstrap,
            "theme selection must use the same deterministic app-settings record as language selection")
    settings_view = (ROOT / "FactoryTools" / "Features" / "Settings" / "AppSettingsView.swift").read_text(encoding="utf-8")
    peer_settings_ui = settings_view.split('Section("settings.peer.title")', 1)[1].split('Section("settings.privacy")', 1)[0]
    require("get: { AppLanguage.resolve(settings.language) }" in settings_view,
            "the language picker must use the same safe preference resolution as the app locale")
    require('Section("settings.language")' not in settings_view,
            "the language setting must not repeat its label as both section heading and picker row")
    for language_case in ("system", "japanese", "english"):
        require(f'Text("settings.language.{language_case}").tag(AppLanguage.{language_case})' in settings_view,
                f"the language picker must expose the {language_case} option")
    require("modelContext.fetch(FetchDescriptor<HomeProfile>())" in bootstrap
            and "modelContext.fetch(FetchDescriptor<AppSettings>())" in bootstrap,
            "bootstrap must check the persistent store directly before inserting defaults")
    require("if homes.isEmpty" in bootstrap and "let home = HomeProfile(name: \"Production\"" in bootstrap
            and "homeToInsert = home" in bootstrap
            and "modelContext.insert(homeToInsert)" in bootstrap,
            "bootstrap must create the default home when no home exists")
    require("if settings.isEmpty" in bootstrap and "settingsToInsert = settingsRecord" in bootstrap
            and "modelContext.insert(settingsToInsert)" in bootstrap
            and "selectedHomeProfileID" in bootstrap,
            "bootstrap must create settings when the settings record is missing")
    require("selectedHomeProfileID" in bootstrap
            and "HomeProfileAccess.selectedHome(from: homes, selectedID: selectedID, isPro: proPurchases.hasPro)" in bootstrap,
            "bootstrap must restore the selected accessible home and use a deterministic entitlement-aware fallback")

    try:
        scheme_root = ET.parse(scheme).getroot()
    except (OSError, ET.ParseError) as error:
        ERRORS.append(f"invalid Xcode scheme XML: {error}")
    else:
        testable_names = {
            reference.attrib.get("BlueprintName")
            for reference in scheme_root.findall(".//TestableReference/BuildableReference")
        }
        require("FactoryToolsTests" in testable_names,
                "shared FactoryTools scheme must include the XCTest target")
    try:
        core_scheme_root = ET.parse(core_scheme).getroot()
    except (OSError, ET.ParseError) as error:
        ERRORS.append(f"invalid Core XCTest scheme XML: {error}")
    else:
        core_testables = {
            reference.attrib.get("BlueprintName")
            for reference in core_scheme_root.findall(".//TestableReference/BuildableReference")
        }
        require(core_testables == {"FactoryToolsCoreTests"},
                "FactoryToolsCore scheme must run only the standalone Core contract tests")
    try:
        watch_scheme_root = ET.parse(watch_scheme).getroot()
    except (OSError, ET.ParseError) as error:
        ERRORS.append(f"invalid Watch scheme XML: {error}")
    else:
        watch_buildables = {
            reference.attrib.get("BlueprintName")
            for reference in watch_scheme_root.findall(".//BuildActionEntry/BuildableReference")
        }
        watch_runnable = watch_scheme_root.find(".//BuildableProductRunnable/BuildableReference")
        require(watch_buildables == {"FactoryToolsWatch", "FactoryToolsCore"}
                and watch_runnable is not None
                and watch_runnable.attrib.get("BlueprintName") == "FactoryToolsWatch",
                "FactoryToolsWatch scheme must build and launch the Watch app with shared Core")

    deployment_targets = set(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);", pbx))
    require(deployment_targets == {"17.0"},
            f"all project targets must use the Phase 1 iOS 17 baseline, found {sorted(deployment_targets)}")
    macos_deployment_targets = set(re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([^;]+);", pbx))
    require(macos_deployment_targets == {"13.0"},
            f"Core and its independent test target must use the macOS 13 baseline, found {sorted(macos_deployment_targets)}")

    for path in (ROOT / "FactoryTools" / "Resources" / "Assets.xcassets").rglob("Contents.json"):
        try:
            parse_json_no_duplicates(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, DuplicateJSONKeyError) as error:
            ERRORS.append(f"invalid asset catalog JSON at {path.relative_to(ROOT)}: {error}")

    app_icon_contents = ROOT / "FactoryTools" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
    try:
        app_icon = parse_json_no_duplicates(app_icon_contents.read_text(encoding="utf-8"))
        icon_entries = app_icon.get("images", []) if isinstance(app_icon, dict) else []
        icon_entry = icon_entries[0] if len(icon_entries) == 1 and isinstance(icon_entries[0], dict) else {}
        icon_filename = icon_entry.get("filename", "")
        app_icon_file = app_icon_contents.parent / icon_filename if isinstance(icon_filename, str) and Path(icon_filename).name == icon_filename else app_icon_contents.parent / "__missing__"
        icon_data = app_icon_file.read_bytes()
        icon_header = icon_data[:24]
        valid_icon_entry = icon_entry.get("idiom") == "universal" and icon_entry.get("platform") == "ios" and icon_entry.get("size") == "1024x1024"
        valid_icon_png = (icon_header[:8] == b"\x89PNG\r\n\x1a\n"
                          and struct.unpack(">II", icon_header[16:24]) == (1024, 1024)
                          and is_opaque_png(icon_data))
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError, struct.error):
        valid_icon_entry = False
        valid_icon_png = False
    require(valid_icon_entry and valid_icon_png
            and len(app_build_settings) == 2
            and all(settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon" for _, settings in app_build_settings),
            "the iPhone app must have a valid opaque 1024px PNG AppIcon wired in Debug and Release")

    watch_icon_contents = ROOT / "FactoryToolsWatch" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
    try:
        watch_icon = parse_json_no_duplicates(watch_icon_contents.read_text(encoding="utf-8"))
        watch_icon_entries = watch_icon.get("images", []) if isinstance(watch_icon, dict) else []
        watch_icon_entry = watch_icon_entries[0] if len(watch_icon_entries) == 1 and isinstance(watch_icon_entries[0], dict) else {}
        watch_icon_filename = watch_icon_entry.get("filename", "")
        watch_icon_file = watch_icon_contents.parent / watch_icon_filename if isinstance(watch_icon_filename, str) and Path(watch_icon_filename).name == watch_icon_filename else watch_icon_contents.parent / "__missing__"
        watch_icon_data = watch_icon_file.read_bytes()
        watch_icon_header = watch_icon_data[:24]
        valid_watch_icon_entry = watch_icon_entry.get("idiom") == "universal" and watch_icon_entry.get("platform") == "watchos" and watch_icon_entry.get("size") == "1024x1024"
        valid_watch_icon_png = (watch_icon_header[:8] == b"\x89PNG\r\n\x1a\n"
                                and struct.unpack(">II", watch_icon_header[16:24]) == (1024, 1024)
                                and is_opaque_png(watch_icon_data))
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError, struct.error):
        valid_watch_icon_entry = False
        valid_watch_icon_png = False
    require(valid_watch_icon_entry and valid_watch_icon_png
            and len(watch_build_settings) == 2
            and all(settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon" for _, settings in watch_build_settings),
            "the Watch app must bundle a valid opaque 1024px PNG AppIcon in Debug and Release")

    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        require({"ja", "en"}.issubset(localizations), f"string {key!r} is missing Japanese or English")
        placeholder_counts: list[int] = []
        for language in ("ja", "en"):
            unit = localizations.get(language, {}).get("stringUnit", {})
            value = unit.get("value", "")
            require(unit.get("state") == "translated" and bool(value),
                    f"string {key!r} has no completed {language} translation")
            require("\ufffd" not in value, f"string {key!r} contains a Unicode replacement character in {language}")
            placeholder_counts.append(localization_placeholder_count(value))
        require(len(placeholder_counts) == 2 and placeholder_counts[0] == placeholder_counts[1],
                f"string {key!r} has a different number of format arguments in Japanese and English")

    store_unavailable_values = {
        language: strings.get("error.storeUnavailable.message", {}).get("localizations", {})
            .get(language, {}).get("stringUnit", {}).get("value", "")
        for language in ("ja", "en")
    }
    require("データの初期化は行っていません" in store_unavailable_values["ja"]
            and "アプリを削除しないでください" in store_unavailable_values["ja"]
            and "It hasn’t reset the store" in store_unavailable_values["en"]
            and "Keep the app installed" in store_unavailable_values["en"],
            "store-open failure must explain that data was not reset and the app should stay installed in both languages")

    pairing_description = strings.get("settings.peer.description", {}).get("localizations", {})
    pairing_description_values = {
        language: pairing_description.get(language, {}).get("stringUnit", {}).get("value", "")
        for language in ("ja", "en")
    }
    require("秘密情報として" in pairing_description_values["ja"]
            and "自分のiPadだけ" in pairing_description_values["ja"]
            and "アプリ削除前に設定からコードを削除" in pairing_description_values["ja"]
            and "Treat it as a secret" in pairing_description_values["en"]
            and "only with your own iPad" in pairing_description_values["en"]
            and "remove it in Settings before deleting the app" in pairing_description_values["en"],
            "iPad pairing help must warn in Japanese and English to protect and remove the pairing code")
    pairing_change_values = {
        language: strings.get("settings.peer.changeCode.message", {}).get("localizations", {})
            .get(language, {}).get("stringUnit", {}).get("value", "")
        for language in ("ja", "en")
    }
    require("前のコードに紐づいたキューに残り" in pairing_change_values["ja"]
            and "新しいコードへは移動しません" in pairing_change_values["ja"]
            and "同じコードを再入力すると送信を再開できます" in pairing_change_values["ja"]
            and "stay in the queue tied to the previous code" in pairing_change_values["en"]
            and "not moved to the new code" in pairing_change_values["en"]
            and "Re-enter the same code to resume" in pairing_change_values["en"],
            "iPad pairing-code confirmation must explain the retained per-peer queue in Japanese and English")
    for key, ja_phrase, en_phrase in (
        ("settings.peer.replaceCode.message", "旧コード用のキューに残り", "not moved"),
        ("settings.peer.removeCode.message", "このコード用のキューに残ります", "remain in the queue for this code"),
    ):
        values = {
            language: strings.get(key, {}).get("localizations", {}).get(language, {})
                .get("stringUnit", {}).get("value", "")
            for language in ("ja", "en")
        }
        require(ja_phrase in values["ja"] and en_phrase in values["en"]
                and "安全な場所" in values["ja"] and "secure copy" in values["en"],
                f"{key} must explain queue retention and secure code preservation in both languages")
    restore_message_values = {
        language: strings.get("settings.peer.restoreCode.message", {}).get("localizations", {})
            .get(language, {}).get("stringUnit", {}).get("value", "")
        for language in ("ja", "en")
    }
    require("保留操作を再送できます" in restore_message_values["ja"]
            and "resume commands waiting for that code" in restore_message_values["en"]
            and "元のキューに残ります" in restore_message_values["ja"]
            and "original queue" in restore_message_values["en"],
            "pairing-code restoration must explain how the matching old queue resumes in both languages")

    ui_key_pattern = re.compile(
        r'(?:Text|Button|Label|Section|NavigationLink|Picker|TextField|LabeledContent|String|accessibilityLabel|accessibilityHint)'
        r'\(\s*"([a-zA-Z][a-zA-Z0-9_.-]+)"'
    )
    for path in (ROOT / "FactoryTools").rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        for key in ui_key_pattern.findall(source):
            require(key in strings, f"{path.relative_to(ROOT)} references missing localization key {key!r}")
        for line, literal in swiftui_unlocalized_copy_literals(source, set(strings)):
            require(False,
                    f"{path.relative_to(ROOT)}:{line} contains SwiftUI copy that is not a localization key: {literal!r}")
        if path.name != "AppTheme.swift":
            require(not re.search(r"\bColor\s*\(|\.(?:white|black|red|orange|yellow|green|blue|gray|primary|secondary)\b(?!\s*\()", source),
                    f"{path.relative_to(ROOT)} defines or selects a color outside ThemeManager's palette")
            require(not re.search(r"\.font\(\s*\.", source),
                    f"{path.relative_to(ROOT)} selects a font outside ThemeManager's typography")
        if path.name not in {"AppTheme.swift", "ThemeManager.swift"}:
            require(not bypasses_app_theme_manager(source),
                    f"{path.relative_to(ROOT)} bypasses ThemeManager's selected Industrial Dark palette")

    watch_theme_path = ROOT / "FactoryToolsWatch" / "WatchTheme.swift"
    watch_theme_source = watch_theme_path.read_text(encoding="utf-8") if watch_theme_path.is_file() else ""
    require("enum WatchTheme" in watch_theme_source
            and all(f"static let {token} =" in watch_theme_source for token in (
                "background", "panel", "accent", "primaryText", "secondaryText", "warning"
            )),
            "Watch colors must be declared in its dedicated theme token palette")
    for path in (ROOT / "FactoryToolsWatch").rglob("*.swift"):
        if path == watch_theme_path:
            continue
        source = path.read_text(encoding="utf-8")
        require(not re.search(r"\bColor\s*\(|\.(?:white|black|red|orange|yellow|green|blue|gray|primary|secondary)\b(?!\s*\()", source),
                f"{path.relative_to(ROOT)} defines or selects a color outside WatchTheme")

    theme_source = (ROOT / "FactoryTools" / "Themes" / "AppTheme.swift").read_text(encoding="utf-8")
    palette = {
        name: tuple(float(component) for component in rgb)
        for name, *rgb in re.findall(
            r"^\s*(background|cardBackground|primaryText|secondaryText|accent|accentForeground|success|warning|critical): Color\(red:\s*([0-9.]+),\s*green:\s*([0-9.]+),\s*blue:\s*([0-9.]+)\)",
            theme_source,
            re.MULTILINE,
        )
    }
    required_palette = {"background", "cardBackground", "primaryText", "secondaryText", "accent", "accentForeground", "success", "warning", "critical"}
    require(required_palette.issubset(palette),
            "Industrial Dark palette is missing a color needed for contrast checks")
    for token in ("borderWidth", "homeTitleFont", "cardTitleFont", "bodyFont", "subheadlineFont", "captionFont", "smallCounterPointSize", "regularCounterPointSize"):
        require(re.search(rf"\blet\s+{token}\s*:", theme_source) is not None,
                f"theme is missing the {token} design token")
    require("func counterFont(for size: ToolCardSize, smallScale: CGFloat, regularScale: CGFloat) -> Font" in theme_source,
            "theme must build counter typography from scaled font tokens")
    if required_palette.issubset(palette):
        for foreground in ("primaryText", "secondaryText"):
            for background in ("background", "cardBackground"):
                ratio = contrast_ratio(palette[foreground], palette[background])
                require(ratio >= 4.5, f"{foreground} contrast on {background} is only {ratio:.2f}:1")
        for foreground in ("success", "warning", "critical"):
            ratio = contrast_ratio(palette[foreground], palette["cardBackground"])
            require(ratio >= 4.5, f"{foreground} contrast on cardBackground is only {ratio:.2f}:1")
        accent_ratio = contrast_ratio(palette["background"], palette["accent"])
        require(accent_ratio >= 3.0, f"theme background contrast on accent buttons is only {accent_ratio:.2f}:1")
        accent_foreground_ratio = contrast_ratio(palette["accentForeground"], palette["accent"])
        require(accent_foreground_ratio >= 4.5,
                f"accentForeground contrast on accent is only {accent_foreground_ratio:.2f}:1")

    registry = (ROOT / "FactoryTools" / "Tools" / "ToolRegistry.swift").read_text(encoding="utf-8")
    tool_id_source = (ROOT / "FactoryToolsCore" / "ToolID.swift").read_text(encoding="utf-8")
    tool_definition_source = (ROOT / "FactoryTools" / "Tools" / "ToolDefinition.swift").read_text(encoding="utf-8")
    for key in re.findall(r'titleKey:\s*"([a-zA-Z][a-zA-Z0-9_.-]+)"', registry):
        require(key in strings, f"Tool Registry references missing localization key {key!r}")
    cycle_time_view = (ROOT / "FactoryTools" / "Features" / "Tools" / "CycleTimeCalculatorView.swift").read_text(encoding="utf-8")
    takt_time_view = (ROOT / "FactoryTools" / "Features" / "Tools" / "TaktTimeCalculatorView.swift").read_text(encoding="utf-8")
    box_calculator_view = (ROOT / "FactoryTools" / "Features" / "Tools" / "BoxCalculatorView.swift").read_text(encoding="utf-8")
    box_packing_math = (ROOT / "FactoryToolsCore" / "BoxPackingMath.swift").read_text(encoding="utf-8")
    production_progress_math = (ROOT / "FactoryToolsCore" / "ProductionProgressMath.swift").read_text(encoding="utf-8")
    unit_conversion = (ROOT / "FactoryToolsCore" / "UnitConversion.swift").read_text(encoding="utf-8")
    localized_number_parser = (ROOT / "FactoryTools" / "Tools" / "LocalizedNumberParser.swift").read_text(encoding="utf-8")
    unit_converter_view = (ROOT / "FactoryTools" / "Features" / "Tools" / "UnitConverterView.swift").read_text(encoding="utf-8")
    home_card_view = (ROOT / "FactoryTools" / "Features" / "Home" / "HomeToolCardView.swift").read_text(encoding="utf-8")
    require("id: .cycleTime" in registry and "isAvailable: true" in registry.split("id: .cycleTime", 1)[1].split("),", 1)[0],
            "Cycle Time must be available through the canonical Tool Registry")
    per_unit_time_math = (ROOT / "FactoryToolsCore" / "PerUnitTimeMath.swift").read_text(encoding="utf-8")
    require("static func secondsPerUnit(totalSeconds: Int, quantity: Int) -> Double?" in per_unit_time_math
            and "guard numeratorSeconds > 0, denominatorUnits > 0 else { return nil }" in per_unit_time_math
            and "Double(numeratorSeconds) / Double(denominatorUnits)" in per_unit_time_math,
            "Cycle Time must calculate seconds per unit only from positive whole-number inputs")
    require("ContinuousClock.Instant" in cycle_time_view
            and "TimelineView(.periodic(from: .now, by: 0.1))" in cycle_time_view
            and "CycleTimeMeasurement.roundedWholeSeconds" in cycle_time_view
            and ".disabled(measuredWholeSeconds == nil)" in cycle_time_view
            and 'Text("cycleTime.timerRoundingNote")' in cycle_time_view,
            "Cycle Time stopwatch must use monotonic elapsed time and disclose its whole-second rounding")
    cycle_sample_service = (ROOT / "FactoryTools" / "Services" / "CycleTimeSampleService.swift").read_text(encoding="utf-8")
    require('CycleTimeCalculatorView(homeProfileID: card.homeProfileID)' in home_card_view
            and 'toolAction("cycleTime.open", systemImage: "timer", destination: .cycleTime)' in home_card_view
            and "CycleTimeSample.self" in persistence_schema
            and "homeProfileID == selectedHomeID" in cycle_time_view
            and "CycleTimeSampleService(modelContext: modelContext).save" in cycle_time_view
            and "CycleTimeSampleService(modelContext: modelContext).delete" in cycle_time_view
            and "modelContext.rollback()" in cycle_sample_service,
            "Cycle Time home cards must open a home-scoped calculator with rollback-safe sample history")
    require("id: .taktTime" in registry and "isAvailable: true" in registry.split("id: .taktTime", 1)[1].split("),", 1)[0]
            and "var supportedCardSizes: Set<ToolCardSize> { id.capabilities.supportedCardSizes }" in tool_definition_source,
            "Takt Time must be available with medium and large cards in the canonical Tool Registry")
    require("static func secondsPerUnit(netAvailableSeconds: Int, customerDemand: Int) -> Double?" in per_unit_time_math
            and "PerUnitTimeMath.secondsPerUnit(" in per_unit_time_math
            and 'Text("taktTime.netTimeNote")' in takt_time_view,
            "Takt Time must use net available seconds per customer demand and explain net time")
    require('TaktTimeCalculatorView()' in home_card_view
            and 'toolAction("taktTime.open", systemImage: "clock", destination: .taktTime)' in home_card_view,
            "Takt Time home cards must open the calculator")
    require("id: .boxCalculator" in registry and "isAvailable: true" in registry.split("id: .boxCalculator", 1)[1].split("),", 1)[0]
            and "case .taktTime, .oee, .defectRate, .boxCalculator:" in tool_id_source,
            "Box Calculator must be available with medium and large cards")
    require("import Foundation" in box_packing_math
            and "import SwiftUI" not in box_packing_math
            and "static func outcome(item: BoxDimensions, innerBox: BoxDimensions) -> BoxPackingOutcome" in box_packing_math
            and "static func maximumUnits(item: BoxDimensions, innerBox: BoxDimensions) -> BoxPackingResult?" in box_packing_math
            and "guard item.isPositive, innerBox.isPositive else { return .noFit }" in box_packing_math
            and box_packing_math.count("BoxDimensions(length: item.") == 6
            and box_packing_math.count("multipliedReportingOverflow") == 2
            and "hasOverflowingLayout ? .countTooLarge : .noFit" in box_packing_math
            and "BoxCalculator.outcome(" in box_calculator_view
            and "enum BoxCalculator" not in box_calculator_view
            and 'case .none:' in box_calculator_view
            and 'Text("boxCalculator.enterDimensions")' in box_calculator_view
            and 'case .some(.noFit):' in box_calculator_view
            and 'Text("boxCalculator.countTooLarge")' in box_calculator_view,
            "Box Calculator math must be Foundation-only, platform-reusable, overflow-safe, and distinct from its SwiftUI view")
    require("localizedInteger(result.unitsAlongLength)" in box_calculator_view
            and "localizedInteger(result.itemOrientation.length)" in box_calculator_view
            and "value.formatted(.number.locale(locale))" in box_calculator_view,
            "Box Calculator layout counts and millimeter dimensions must follow the selected Japanese/English number locale")
    require("import Foundation" in production_progress_math
            and "import SwiftUI" not in production_progress_math
            and "static func fraction(currentCount: Int, targetCount: Int) -> Double" in production_progress_math
            and "static func formatted(currentCount: Int, targetCount: Int, locale: Locale) -> String" not in production_progress_math
            and "ProductionProgressMath.fraction(" in home_card_view
            and "HomeCardPresentation.formattedProgress(" in home_card_view
            and "static func progressFraction" not in home_card_view
            and "static func formattedProgress(currentCount: Int, targetCount: Int, locale: Locale) -> String" in home_card_view,
            "Production Progress math must stay locale-neutral in Core while the app formats its accessible label")
    require('BoxCalculatorView()' in home_card_view
            and 'toolAction("boxCalculator.open", systemImage: "shippingbox", destination: .boxCalculator)' in home_card_view
            and 'Text("boxCalculator.sameOrientationNote")' in box_calculator_view
            and 'LabeledContent("boxCalculator.itemOrientation")' in box_calculator_view,
            "Box Calculator home cards must open the calculator, disclose its packing assumption, and show the selected item orientation")
    require("id: .unitConverter" in registry and "isAvailable: true" in registry.split("id: .unitConverter", 1)[1].split(")", 1)[0]
            and "case .unitConverter:" in tool_id_source,
            "Unit Converter must be available with small and medium cards")
    require("case length" in unit_conversion and "case mass" in unit_conversion
            and "case volume" in unit_conversion and "case temperature" in unit_conversion
            and "static func convert(_ value: Double, from source: MeasurementUnit, to target: MeasurementUnit) -> Double?" in unit_conversion
            and "source.category == target.category" in unit_conversion
            and "celsius >= -273.15" in unit_conversion
            and "guard value >= 0" in unit_conversion,
            "Unit Converter must keep four unit categories separate and reject invalid physical values")
    require("import Foundation" in localized_number_parser
            and "import SwiftUI" not in localized_number_parser
            and "try formatter.getObjectValue(&parsedObject, for: input, range: &parsedRange)" in localized_number_parser
            and "NSMaxRange(parsedRange) == inputLength" in localized_number_parser
            and "static func parseInteger(_ text: String, locale: Locale) -> Int?" in localized_number_parser
            and "formatter.generatesDecimalNumbers = true" in localized_number_parser
            and "NSDecimalRound(&roundedValue, &parsedValue, 0, .plain)" in localized_number_parser
            and "roundedValue >= Decimal(Int64.min)" in localized_number_parser
            and "roundedValue <= Decimal(Int64.max)" in localized_number_parser
            and "LocalizedNumberParser.parse(valueText, locale: locale)" in unit_converter_view
            and ".keyboardType(category == .temperature ? .numbersAndPunctuation : .decimalPad)" in unit_converter_view,
            "Unit Converter must parse locale-aware input completely, permit a negative temperature sign, and reject trailing text")
    integer_input_sources = (
        (ROOT / "FactoryTools" / "Features" / "Counter" / "CounterSettingsView.swift").read_text(encoding="utf-8"),
        box_calculator_view,
        cycle_time_view,
        takt_time_view,
        (ROOT / "FactoryTools" / "Features" / "Tools" / "OEECalculatorView.swift").read_text(encoding="utf-8"),
    )
    require(all("LocalizedNumberParser.parseInteger(" in source for source in integer_input_sources)
            and all('@Environment(\.locale) private var locale' in source for source in integer_input_sources)
            and all(not re.search(r"Int\([A-Za-z_][A-Za-z0-9_]*Text\)", source) for source in integer_input_sources),
            "localized integer entry must be shared by counter settings and every integer-based tool form")
    require('UnitConverterView()' in home_card_view
            and 'toolAction("unitConverter.open", systemImage: "arrow.left.arrow.right", destination: .unitConverter)' in home_card_view
            and "ForEach(category.units)" in unit_converter_view
            and ".onChange(of: category)" in unit_converter_view
            and "LocalizedNumberParser.parse(valueText, locale: locale)" in unit_converter_view
            and "Text(LocalizedStringKey(unit.titleKey))" in unit_converter_view,
            "Unit Converter home cards must open a locale-aware, category-filtered converter")
    unit_categories = {"unitConverter.category.length", "unitConverter.category.mass", "unitConverter.category.volume", "unitConverter.category.temperature"}
    unit_names = {f"unitConverter.unit.{name}" for name in (
        "millimeter", "centimeter", "meter", "kilometer", "inch", "foot", "gram", "kilogram",
        "ounce", "pound", "milliliter", "liter", "usFluidOunce", "usGallon", "celsius", "fahrenheit", "kelvin"
    )}
    require(unit_categories.issubset(strings) and unit_names.issubset(strings),
            "Unit Converter must have Japanese and English labels for every category and unit")

    all_swift = "\n".join(path.read_text(encoding="utf-8") for path in source_files)
    local_peer_transport_path = ROOT / "FactoryTools" / "Services" / "LocalPeerCounterTransport.swift"
    local_peer_transport = local_peer_transport_path.read_text(encoding="utf-8") if local_peer_transport_path.is_file() else ""
    peer_accept_match = re.search(
        r"private func accept\(_ connection: NWConnection, pairingKey: Data\) \{(.*?)(?=\n    private func connect\()",
        local_peer_transport,
        re.DOTALL,
    )
    peer_accept_source = peer_accept_match.group(1) if peer_accept_match else ""
    require(bonjour_declaration_matches(app_info.get("NSBonjourServices"), local_peer_transport),
            "FactoryTools Info.plist Bonjour services must include the Network.framework advertised service type")
    peer_outbox_repository_path = ROOT / "FactoryTools" / "Services" / "LocalPeerCounterOutboxRepository.swift"
    peer_outbox_repository = peer_outbox_repository_path.read_text(encoding="utf-8") if peer_outbox_repository_path.is_file() else ""
    peer_outbox_tests_path = ROOT / "FactoryToolsTests" / "LocalPeerPairingKeyStoreTests.swift"
    peer_outbox_tests = peer_outbox_tests_path.read_text(encoding="utf-8") if peer_outbox_tests_path.is_file() else ""
    peer_pairing_key_store_path = ROOT / "FactoryTools" / "Services" / "LocalPeerPairingKeyStore.swift"
    peer_pairing_key_store = peer_pairing_key_store_path.read_text(encoding="utf-8") if peer_pairing_key_store_path.is_file() else ""
    peer_pairing_save_match = re.search(
        r"static func save\(code: String\) throws \{(.*?)(?=\n    static func upsertStatus)",
        peer_pairing_key_store,
        re.DOTALL,
    )
    peer_pairing_save = peer_pairing_save_match.group(1) if peer_pairing_save_match else ""
    require("SecItemUpdate(" in peer_pairing_save
            and "errSecItemNotFound" in peer_pairing_save
            and "SecItemAdd(" in peer_pairing_save
            and "SecItemDelete(" not in peer_pairing_save
            and "func testKeychainUpdateFailurePreservesExistingPairingItem()" in peer_outbox_tests
            and "func testKeychainUpsertAddsOnlyWhenNoPairingItemExists()" in peer_outbox_tests
            and "func testKeychainUpsertDoesNotReplaceSuccessfulUpdate()" in peer_outbox_tests
            and "func testKeychainUpsertReturnsInitialRegistrationFailure()" in peer_outbox_tests,
            "pairing-key replacement must update atomically and only insert when no existing Keychain item is present")
    require("com.example" not in peer_pairing_key_store
            and "com.example" not in local_peer_transport
            and 'private static let service = "FactoryTools.LocalPeer.PairingKey.v1"' in peer_pairing_key_store
            and 'DispatchQueue(label: "FactoryTools.LocalPeer.Transport")' in local_peer_transport,
            "local peer keychain and queue namespaces must not inherit the development-only publisher Bundle ID")
    def settings_action_body(name: str) -> str:
        marker = f"private func {name}()"
        if marker not in settings_view:
            return ""
        return settings_view.split(marker, 1)[1].split("\n    private func ", 1)[0]

    generate_pairing_body = settings_action_body("generatePairingCode")
    request_pairing_generate_body = settings_action_body("requestPairingCodeGeneration")
    save_pairing_body = settings_action_body("savePairingCode")
    request_pairing_save_body = settings_action_body("requestPairingCodeSave")
    request_pairing_restore_body = settings_action_body("requestPairingCodeRestore")
    restore_pairing_body = settings_action_body("restorePairingCode")
    request_pairing_remove_body = settings_action_body("requestPairingCodeRemoval")
    remove_pairing_body = settings_action_body("removePairingCode")
    require(generate_pairing_body.find("LocalPeerPairingKeyStore.save(code: code)") >= 0
            and generate_pairing_body.find("LocalPeerPairingKeyStore.save(code: code)") < generate_pairing_body.find("peerTransport.stopAuthority()")
            and generate_pairing_body.find("peerTransport.stopAuthority()") < generate_pairing_body.find("startPeerAuthority()")
            and save_pairing_body.find("LocalPeerPairingKeyStore.save(code: code)") >= 0
            and save_pairing_body.find("LocalPeerPairingKeyStore.save(code: code)") < save_pairing_body.find("peerTransport.disconnectClient()")
            and remove_pairing_body.find("LocalPeerPairingKeyStore.remove()") >= 0
            and remove_pairing_body.find("LocalPeerPairingKeyStore.remove()") < remove_pairing_body.find("peerTransport.stopAuthority()"),
            "peer transport changes must happen only after pairing-key persistence succeeds")
    require('Button("settings.peer.activate", action: requestPairingCodeSave)' in settings_view
            and "loadCurrentPairingOutboxForCodeChange()" in request_pairing_save_body
            and "LocalPeerPairingCodeChangePolicy.requiresConfirmation(" in request_pairing_save_body
            and request_pairing_save_body.find("loadCurrentPairingOutboxForCodeChange()") < request_pairing_save_body.find("requiresConfirmation(")
            and "pendingCommandCount: peerTransport.pendingCommandCount" in request_pairing_save_body
            and "showingPairingCodeChangeConfirmation = true" in request_pairing_save_body
            and "func loadCurrentPairingOutboxForCodeChange() -> Bool" in local_peer_transport
            and '"settings.peer.changeCode.title"' in settings_view
            and '"settings.peer.changeCode.message"' in settings_view
            and "func testPairingCodeChangeNeedsConfirmationOnlyForDifferentCodeWithPendingCommands()" in peer_outbox_tests,
            "switching iPad pairing codes with pending commands must require an explicit, tested confirmation")
    require('Button("settings.peer.generateCode", action: requestPairingCodeGeneration)' in settings_view
            and 'Button("settings.peer.remove", role: .destructive, action: requestPairingCodeRemoval)' in settings_view
            and "LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeReset(currentCode: pairingCode)" in request_pairing_generate_body
            and "showingPairingCodeReplacementConfirmation = true" in request_pairing_generate_body
            and "LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeReset(currentCode: pairingCode)" in request_pairing_remove_body
            and "showingPairingCodeRemovalConfirmation = true" in request_pairing_remove_body
            and '"settings.peer.replaceCode.message"' in settings_view
            and '"settings.peer.removeCode.message"' in settings_view
            and "func testPairingCodeReplacementOrRemovalNeedsConfirmationWhenCodeExists()" in peer_outbox_tests,
            "pairing-code replacement and removal must warn about the retained queue and be confirmed before action")
    require(peer_settings_ui.count(".privacySensitive()") >= 3
            and peer_settings_ui.count(".redacted(reason: shouldRedactPairingSecrets ? .privacy : [])") >= 3
            and "Text(pairingCode)" in peer_settings_ui
            and 'TextField("settings.peer.enterCode", text: $pairingCodeDraft)' in peer_settings_ui
            and 'TextField("settings.peer.enterExistingCode", text: $pairingCodeDraft)' in peer_settings_ui
            and "PairingSecretVisibilityPolicy.shouldRedact(" in settings_view
            and "!sceneIsActive || isScreenCaptured" in peer_pairing_key_store
            and "func testPairingSecretIsRedactedWhenSceneIsInactiveOrScreenIsCaptured()" in peer_outbox_tests
            and "import UIKit" in settings_view
            and "UIDevice.current.userInterfaceIdiom" in settings_view
            and '@Environment(\.isSceneCaptured)' in settings_view
            and "UIScreen.capturedDidChangeNotification" not in settings_view
            and "hasCapturedConnectedScreen" not in settings_view,
            "pairing secrets must be privacy-redacted in inactive scenes and while screen capture is active")
    require('TextField("settings.peer.enterExistingCode", text: $pairingCodeDraft)' in settings_view
            and 'Button("settings.peer.restoreCode", action: requestPairingCodeRestore)' in settings_view
            and "LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeAuthorityCodeChange(" in request_pairing_restore_body
            and "showingPairingCodeRestoreConfirmation = true" in request_pairing_restore_body
            and "LocalPeerPairingKeyStore.save(code: code)" in restore_pairing_body
            and restore_pairing_body.find("LocalPeerPairingKeyStore.save(code: code)") < restore_pairing_body.find("peerTransport.stopAuthority()")
            and restore_pairing_body.find("peerTransport.stopAuthority()") < restore_pairing_body.find("peerTransport.disconnectClient()")
            and restore_pairing_body.find("peerTransport.disconnectClient()") < restore_pairing_body.find("startPeerAuthority()")
            and "UIDevice.current.userInterfaceIdiom != .pad" in restore_pairing_body
            and "peerTransport.stopAuthority()" in restore_pairing_body
            and '"settings.peer.restoreCode.message"' in settings_view
            and "func testRestoringSameAuthorityCodeSkipsConfirmationButChangingItRequiresConfirmation()" in peer_outbox_tests,
            "iPhone must allow restoring a retained pairing code after replacement and confirm changes")
    peer_processor_path = ROOT / "FactoryTools" / "Services" / "WatchCommandProcessor.swift"
    peer_processor_source = peer_processor_path.read_text(encoding="utf-8") if peer_processor_path.is_file() else ""
    peer_counter_view_path = ROOT / "FactoryTools" / "Features" / "Counter" / "PeerCounterView.swift"
    peer_counter_view = peer_counter_view_path.read_text(encoding="utf-8") if peer_counter_view_path.is_file() else ""
    peer_frame_codec_path = ROOT / "FactoryToolsCore" / "CounterPeerFrameCodec.swift"
    peer_frame_codec = peer_frame_codec_path.read_text(encoding="utf-8") if peer_frame_codec_path.is_file() else ""
    core_contract_tests_path = ROOT / "FactoryToolsCoreTests" / "CoreContractTests.swift"
    core_contract_tests = core_contract_tests_path.read_text(encoding="utf-8") if core_contract_tests_path.is_file() else ""
    require("CounterPeerConnectionPolicy.shouldAcceptIncomingConnection(" in peer_accept_source
            and "hasPendingOrActiveConnection: wire != nil" in peer_accept_source
            and "wire?.cancel()" not in peer_accept_source
            and 'statusKey = "peer.status.connecting"' in peer_accept_source
            and "testPeerAuthorityDoesNotReplacePendingOrActivePairedConnection" in core_contract_tests,
            "the iPhone peer authority must preserve its current connection until a new paired connection is established")
    require("@Environment(\\.locale) private var locale" in peer_counter_view
            and "value: formattedCount(transport.pendingCommandCount)" in peer_counter_view
            and 'Text(formattedCount(session.currentCount))' in peer_counter_view
            and 'Text("/ \\(formattedCount(session.targetCount))")' in peer_counter_view
            and '.accessibilityLabel("counter.currentCount")' in peer_counter_view
            and '.accessibilityLabel("counter.goal")' in peer_counter_view
            and 'value.formatted(.number.locale(locale))' in peer_counter_view,
            "the iPad counter dashboard must localize pending/count/target numbers and expose count and target labels to VoiceOver")
    counter_outbox_path = ROOT / "FactoryToolsCore" / "CounterCommandOutbox.swift"
    counter_outbox_source = counter_outbox_path.read_text(encoding="utf-8") if counter_outbox_path.is_file() else ""
    watch_model_path = ROOT / "FactoryToolsWatch" / "WatchCounterModel.swift"
    watch_model_source = watch_model_path.read_text(encoding="utf-8") if watch_model_path.is_file() else ""
    watch_view_path = ROOT / "FactoryToolsWatch" / "WatchHomeView.swift"
    watch_view_source = watch_view_path.read_text(encoding="utf-8") if watch_view_path.is_file() else ""
    watch_processor_path = ROOT / "FactoryTools" / "Services" / "WatchCommandProcessor.swift"
    watch_processor_source = watch_processor_path.read_text(encoding="utf-8") if watch_processor_path.is_file() else ""
    watch_catalog_source = (ROOT / "FactoryToolsCore" / "WatchCounterCatalog.swift").read_text(encoding="utf-8")
    watch_progress_test_source = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    watch_progress_test = re.search(
        r"func testWatchProductionProgressCatalogRequiresProAndWatchVisibility\(\) throws \{(.*?)(?=\n    func test|\Z)",
        watch_progress_test_source,
        re.DOTALL,
    )
    watch_progress_test_body = watch_progress_test.group(1) if watch_progress_test else ""
    require("public struct WatchProductionProgressSnapshot: Codable, Equatable, Identifiable" in watch_catalog_source
            and "public let progressCards: [WatchProductionProgressSnapshot]" in watch_catalog_source
            and "decodeIfPresent([WatchProductionProgressSnapshot].self, forKey: .progressCards) ?? []" in watch_catalog_source
            and "FeatureAccessRegistry.allows(definition.accessTier, isPro: isPro)" in watch_processor_source
            and "FeatureAccessRegistry.allows(.additionalWatchTools, isPro: isPro)" in watch_processor_source
            and "!includeCardsHiddenFromWatch" in watch_processor_source
            and "progressCards = catalog.progressCards" in watch_model_source
            and "model.progressCards" in watch_view_source
            and "WatchProductionProgressDetailView(progress: progress)" in watch_view_source
            and "watch.progress.fraction" in watch_view_source
            and "processor.catalog(isPro: false).progressCards.isEmpty" in watch_progress_test_body
            and "processor.catalog(isPro: true)" in watch_progress_test_body
            and "processor.peerCatalog(isPro: true).progressCards.isEmpty" in watch_progress_test_body
            and "card.showsOnWatch = false" in watch_progress_test_body,
            "Watch Production Progress must be a read-only, Pro-gated card with explicit visibility and compatibility coverage")
    other_swift = "\n".join(
        path.read_text(encoding="utf-8")
        for path in source_files
        if path not in {local_peer_transport_path, ROOT / "FactoryTools" / "App" / "ProPurchaseManager.swift"}
    )
    require("data.count - offset" in peer_frame_codec
            and "min(remainingCapacity, data.count - offset)" in peer_frame_codec
            and "offset + chunkLength" in peer_frame_codec,
            "peer frame chunking must bound addition by remaining input length to avoid integer overflow")
    require(not re.search(
        r"\b(?:URLSession|URLRequest|NSURLConnection|NWConnection|NWBrowser|NWPathMonitor|WebSocket|Alamofire|AFNetworking|Moya|Apollo|GraphQL)\b|\bURL\s*\(",
        other_swift,
    ), "Only the local peer transport may use Network.framework clients")
    require(not re.search(r"\bimport\s+(?:Network|CFNetwork|FoundationNetworking|WebKit|SafariServices)\b", other_swift)
            and "import Network" in local_peer_transport
            and "NWListener" in local_peer_transport
            and "NWBrowser" in local_peer_transport,
            "Local peer networking must stay in its dedicated Network.framework transport; no browser clients")
    authority_listener_failure = re.search(
        r"else if case \.failed = state \{(.*?)\n\s{20}\}",
        local_peer_transport,
        re.DOTALL,
    )
    require(authority_listener_failure is not None
            and "self.scheduleAuthorityRetry()" in authority_listener_failure.group(1)
            and "private func scheduleAuthorityRetry()" in local_peer_transport
            and "CounterCommandRetryPolicy.delaySeconds(forAttempt: authorityRetryAttempt)" in local_peer_transport
            and "self.authorityRetryAttempt = 0" in local_peer_transport
            and local_peer_transport.count("authorityRetryTask?.cancel()") >= 2,
            "iPhone peer authority must retry failed listeners with capped backoff and cancel retries when stopped or restarted")
    require(not re.search(r"https?://", all_swift, re.IGNORECASE),
            "Swift source contains an HTTP endpoint")
    require("sec_protocol_options_add_pre_shared_key" in local_peer_transport
            and "sec_protocol_options_append_tls_ciphersuite(" in local_peer_transport
            and "TLS_PSK_WITH_AES_256_GCM_SHA384" in local_peer_transport
            and "parameters.includePeerToPeer = true" in local_peer_transport
            and "sec_protocol_options_set_min_tls_protocol_version" in local_peer_transport
            and "sec_protocol_options_set_max_tls_protocol_version" in local_peer_transport
            and local_peer_transport.count(".TLSv12") == 2
            and "NWParameters(tls: tls, tcp: NWProtocolTCP.Options())" in local_peer_transport
            and "NWListener.Service" in local_peer_transport
            and "NWBrowser(for:" in local_peer_transport
            and "CounterPeerFrameDecoder" in local_peer_transport
            and "LocalPeerCounterOutboxRepository" in local_peer_transport
            and "outboxRepository.load(for: pairingKey)" in local_peer_transport
            and "reassignUnassignedLegacyOutbox(to: loadedPairingKey)" in local_peer_transport
            and "SHA256.hash(data: keyData)" in all_swift
            and '"settings.peer.reassignLegacy.message"' in settings_view
            and '"settings.peer.unassignedCommandsNotice"' in settings_view
            and '"settings.peer.unassignedCommandsError"' in settings_view
            and "only after the user chooses a pairing" in peer_outbox_repository
            and "WatchCommandProcessor(modelContext: modelContainer.mainContext)" in local_peer_transport
            and "allowNonWatchSessions: true," in local_peer_transport
            and "isPro: ProPurchaseManager.shared.hasPro" in local_peer_transport
            and "wire?.id == connectionID" in local_peer_transport
            and "self.listenerGeneration == listenerID" in local_peer_transport
            and "self.browserGeneration == browserID" in local_peer_transport
            and "retryTask?.cancel()" in local_peer_transport
            and "CounterCommandResponseValidator.isComplete(" in local_peer_transport
            and "guard let acknowledgement = message.acknowledgement else" in local_peer_transport
            and "scheduleResponseTimeout(for: command.id)" in local_peer_transport
            and '"peer.status.responseTimedOut"' in local_peer_transport
            and "peerTransport.disconnectClient()" in settings_view
            and "retryAfterInvalidResponse()" in local_peer_transport
            and "CounterCommandResponseValidator.indicatesUnavailableSession(" in local_peer_transport
            and "CounterCommandOutboxTransaction.acknowledge(" in local_peer_transport
            and "CounterService(modelContext: modelContext).apply(command, to: session)" in peer_processor_source,
            "iPad peer transport must use paired TLS, Bonjour/P2P, bounded framing, durable outbox, and the iPhone CounterService")
    queue_limit_test = re.search(
        r"func testOutboxCapacityPreservesSavedCommandsAndResumesAfterAcknowledgement\(\) throws \{(.*?)(?=\n    func test|\Z)",
        core_contract_tests,
        re.DOTALL,
    )
    queue_limit_test_body = queue_limit_test.group(1) if queue_limit_test else ""
    require("maximumPendingCommandCount = 5_000" in counter_outbox_source
            and "guard commands.count <= Self.maximumPendingCommandCount" in counter_outbox_source
            and "maximumFileSizeBytes = 4 * 1_048_576" in counter_outbox_source
            and "fileURL.resourceValues(forKeys: [.fileSizeKey])" in counter_outbox_source
            and "data.count <= Self.maximumFileSizeBytes" in counter_outbox_source
            and "pendingLimitReached(maximumCount:" in counter_outbox_source
            and "catch CounterCommandOutboxError.pendingLimitReached" in local_peer_transport
            and 'statusKey = "peer.status.queueFull"' in local_peer_transport
            and "queueLimitReached" in watch_model_source
            and "catch CounterCommandOutboxError.pendingLimitReached" in watch_model_source
            and '"watch.queueFull.message"' in watch_view_source
            and "CounterCommandOutbox.maximumPendingCommandCount" in queue_limit_test_body
            and "JSONDecoder().decode(CounterCommandOutbox.self, from: exactLimitPayload).count" in queue_limit_test_body
            and "maximumPendingCommandCount\n        )" in queue_limit_test_body
            and "try store.save(outbox)" in queue_limit_test_body
            and "XCTAssertEqual(try store.load(), outbox)" in queue_limit_test_body
            and "let savedCommands = outbox.pendingCommands" in queue_limit_test_body
            and "XCTAssertEqual(outbox.pendingCommands, savedCommands)" in queue_limit_test_body
            and "XCTAssertEqual(outbox.nextCommand, firstCommand)" in queue_limit_test_body
            and "XCTAssertTrue(outbox.acknowledgeHead(commandID: acknowledged.id))" in queue_limit_test_body
            and "peer.status.queueFull" in strings
            and "watch.queueFull.message" in watch_strings,
            "offline queue capacity must preserve old commands, reject new ones clearly, and resume after delivery on iPad and Watch")
    decoder_limit_test = re.search(
        r"func testOutboxDecoderRejectsMoreThanMaximumPendingCommands\(\) throws \{(.*?)(?=\n    func test|\Z)",
        core_contract_tests,
        re.DOTALL,
    )
    decoder_limit_test_body = decoder_limit_test.group(1) if decoder_limit_test else ""
    require("0...CounterCommandOutbox.maximumPendingCommandCount" in decoder_limit_test_body
            and "JSONDecoder().decode(CounterCommandOutbox.self, from: payload)" in decoder_limit_test_body,
            "persisted iPad command outboxes must reject a queue larger than the enqueue limit")
    oversized_outbox_test = re.search(
        r"func testOutboxFileStoreRejectsOversizedFileBeforeDecodingAndLeavesItUntouched\(\) throws \{(.*?)(?=\n    func test|\Z)",
        core_contract_tests,
        re.DOTALL,
    )
    oversized_outbox_test_body = oversized_outbox_test.group(1) if oversized_outbox_test else ""
    require("CounterCommandOutboxFileStore.maximumFileSizeBytes + 1" in oversized_outbox_test_body
            and "as? CounterCommandOutboxFileStoreError, .fileTooLarge" in oversized_outbox_test_body,
            "iPad command-outbox file reads must be size-bounded before JSON decoding")
    enqueue_start = local_peer_transport.find("func enqueue(_ command: CounterCommand)")
    enqueue_end = local_peer_transport.find("private func accept(", enqueue_start)
    enqueue_source = local_peer_transport[enqueue_start:enqueue_end] if enqueue_start >= 0 and enqueue_end > enqueue_start else ""
    send_next_start = local_peer_transport.find("private func sendNextCommandIfPossible()")
    send_next_end = local_peer_transport.find("@discardableResult", send_next_start)
    send_next_source = local_peer_transport[send_next_start:send_next_end] if send_next_start >= 0 and send_next_end > send_next_start else ""
    response_start = local_peer_transport.find("case .commandResult:")
    response_end = local_peer_transport.find("case .catalogRequest, .command:", response_start)
    response_source = local_peer_transport[response_start:response_end] if response_start >= 0 and response_end > response_start else ""
    require("CounterCommandOutboxTransaction.enqueue(" in enqueue_source
            and "try persistOutbox(candidate)" in enqueue_source
            and enqueue_source.index("CounterCommandOutboxTransaction.enqueue(") < enqueue_source.index("outbox = updated")
            and "CounterCommandOutboxTransaction.acknowledge(" in response_source
            and "CounterCommandResponseValidator.indicatesUnavailableSession(" in response_source
            and "try persistOutbox(candidate)" in response_source
            and "outbox = updated" in response_source
            and "pendingCommandCount = outbox.count" in response_source
            and "sendNextCommandIfPossible()" in response_source
            and "scheduleRetry()" in response_source
            and response_source.index("CounterCommandOutboxTransaction.acknowledge(") < response_source.index("outbox = updated")
            and response_source.index("outbox = updated") < response_source.index("sendNextCommandIfPossible()"),
            "iPad outbox enqueues and acknowledgements must commit memory/count/send state only after persistence succeeds")
    stale_ack_guard = "guard acknowledgement.commandID == command.id else { return }"
    require(stale_ack_guard in response_source
            and response_source.index(stale_ack_guard) < response_source.index("CounterCommandResponseValidator.isComplete")
            and len(re.findall(r"(?m)^\s*retryAttempt = 0$", local_peer_transport)) == 1
            and "retryAttempt = 0" in response_source
            and "retryTask == nil" in send_next_source
            and "XCTAssertFalse(CounterCommandResponseValidator.isComplete(unrelatedAck, snapshot: snapshot, matches: command))" in core_contract_tests,
            "iPad transport must ignore stale acknowledgements and honor retry backoff until a valid command response")
    require("while offset < data.count" in peer_frame_codec
            and "drainCompleteMessages()" in peer_frame_codec
            and "consumedByteCount" in peer_frame_codec
            and "coalescedFrameCount" in core_contract_tests
            and "requiresAuthoritativeSnapshot" in core_contract_tests
            and "testOutboxEnqueueTransactionKeepsCurrentQueueWhenPersistenceFails" in core_contract_tests
            and "testOutboxAcknowledgementTransactionKeepsHeadWhenPersistenceFails" in core_contract_tests
            and "testOutboxAcknowledgementTransactionRejectsAcknowledgementForPriorHead" in core_contract_tests
            and "testUnavailableSessionTransactionKeepsAllCommandsWhenPersistenceFails" in core_contract_tests,
            "iPad transport regressions must be covered for stale connections, complete command responses, and aggregate coalesced frames")
    require("identity(for keyData: Data)" in all_swift
            and "SHA256.hash(data: keyData)" in all_swift
            and "testCounterOutboxesAreIsolatedByPairingSecret" in peer_outbox_tests
            and "reopenedRepository.load(for: firstKey)" in peer_outbox_tests
            and "testLegacyOutboxStaysUnassignedUntilExplicitReassignment" in peer_outbox_tests
            and "testLegacyReassignmentConflictPreservesBothOutboxes" in peer_outbox_tests
            and "testMalformedLegacyOutboxRemainsUntouched" in peer_outbox_tests
            and "testLegacyOutboxRemainsAvailableWhenScopedSaveFails" in peer_outbox_tests
            and "loadUnassignedLegacyOutbox()" in peer_outbox_repository,
            "peer Outbox storage must be isolated by a non-secret pairing fingerprint and preserve unassigned legacy queues until explicit reassignment")
    require("operation: .setTarget(target)" in peer_counter_view
            and "operation: .quickAdd(amount)" in peer_counter_view
            and ".undo(eventID: eventID)" in peer_counter_view,
            "iPad counter screen must send locale-aware Quick Add, Undo, and target commands through the outbox")
    purchase_manager_path = ROOT / "FactoryTools" / "App" / "ProPurchaseManager.swift"
    purchase_manager = purchase_manager_path.read_text(encoding="utf-8") if purchase_manager_path.is_file() else ""
    purchase_price_view_path = ROOT / "FactoryTools" / "Features" / "Settings" / "AppSettingsView.swift"
    purchase_price_view = purchase_price_view_path.read_text(encoding="utf-8") if purchase_price_view_path.is_file() else ""
    storekit_sources = [path for path in source_files if re.search(
        r"^\s*import\s+StoreKit\b|RevenueCat|Purchases\.shared",
        path.read_text(encoding="utf-8"),
        re.MULTILINE,
    )]
    observe_transactions_position = purchase_manager.find("private func observeTransactions()")
    product_filter_position = purchase_manager.find("guard transaction.productID == productID else { continue }")
    transaction_finish_position = purchase_manager.find("await transaction.finish()", observe_transactions_position)
    require(storekit_sources == [purchase_manager_path]
            and "import StoreKit" in purchase_manager
            and "Transaction.currentEntitlements" in purchase_manager
            and "Transaction.updates" in purchase_manager
            and 0 <= observe_transactions_position < product_filter_position < transaction_finish_position
            and "AppStore.sync()" in purchase_manager
            and "await self.observeTransactions()" in purchase_manager
            and "await self.refresh()" in purchase_manager
            and "product.type == .nonConsumable" in purchase_manager
            and "evidence.grantsPro(for: productID)" in purchase_manager
            and "transaction.ownershipType == .familyShared" in purchase_manager
            and "case .familyShared:\n            return false" in all_swift
            and "ProEntitlementEvidence" in all_swift
            and "public func grantsPro(for configuredProductID: String) -> Bool" in all_swift
            and "testProEntitlementRequiresVerifiedActiveOwnershipOfConfiguredProduct" in core_contract_tests
            and 'XCTAssertFalse(evidence(ownership: .familyShared).grantsPro(for: "factorytools.pro"))' in core_contract_tests
            and "hasResolvedEntitlement = true" in purchase_manager
            and "Text(product.displayPrice)" in purchase_price_view
            and "¥980" not in all_swift
            and not re.search(r"RevenueCat|Purchases\.shared", purchase_manager),
            "StoreKit must stay in the first-party one-time Pro manager and show the StoreKit-localized regional price rather than a hard-coded yen amount")
    home_view_path = ROOT / "FactoryTools" / "Features" / "Home" / "HomeView.swift"
    home_view_source = home_view_path.read_text(encoding="utf-8") if home_view_path.is_file() else ""
    create_home_path = ROOT / "FactoryTools" / "Features" / "Home" / "CreateHomeView.swift"
    create_home_source = create_home_path.read_text(encoding="utf-8") if create_home_path.is_file() else ""
    backup_import_source = (ROOT / "FactoryTools" / "Settings" / "AppSettings.swift").read_text(encoding="utf-8")
    backup_import_match = re.search(
        r"@MainActor\s+struct FactoryToolsBackupImportService\s*\{(.*)\n\}",
        backup_import_source,
        re.S,
    )
    backup_import_body = backup_import_match.group(1) if backup_import_match else ""
    counter_service_test_source = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    settings_view_path = ROOT / "FactoryTools" / "Features" / "Settings" / "AppSettingsView.swift"
    settings_view_source = settings_view_path.read_text(encoding="utf-8") if settings_view_path.is_file() else ""
    require("FeatureAccessRegistry.allows(.multipleHomeProfiles" in home_view_source
            and "canCreateAnotherHome ? .createHome : .settings" in home_view_source
            and "FeatureAccessRegistry.allows(.multipleHomeProfiles" in create_home_source
            and "func addCopy(" in backup_import_body
            and "ProPurchaseManager" not in backup_import_body
            and "isPro: Bool = false" in backup_import_body
            and "HomeProfileOrdering.assignSortOrders(isPro ? homeOrder + importedHomes : importedHomes + homeOrder)" in backup_import_body
            and "primarySettings.selectedHomeProfileID = firstImportedHome.id" in backup_import_body
            and "testFreeBackupRestoreActivatesFirstImportedHomeAndKeepsOtherDataLocked" in counter_service_test_source
            and "await proPurchases.purchase()" in settings_view_source
            and "await proPurchases.restorePurchases()" in settings_view_source
            and 'Button("pro.retry")' in settings_view_source
            and "Task { await proPurchases.refresh() }" in settings_view_source
            and "if proPurchases.isConfigured {" in settings_view_source
            and "settings.backup.freeRestoreNotice" in settings_view_source
            and "isPro: proPurchases.hasPro" in settings_view_source
            and "proPurchases.hasPro" in settings_view_source
            and all_swift.count("isPro: ProPurchaseManager.shared.hasPro") >= 2
            and "testFreeWatchAndPeerControlsUseTheCanonicalCounterService" in all_swift,
            "Free/Pro checks must use centralized access metadata while preserving basic companion controls")
    app_swift = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "FactoryTools").rglob("*.swift"))
    require(not re.search(r"\btry\s*[!?]", app_swift), "app source contains a forced or silently ignored throwing operation")

    required_models = {"HomeProfile", "ToolCard", "ProductionSession", "CountEvent", "CounterCommandReceipt", "AppSettings", "CycleTimeSample", "OEERun"}
    declared_models = set(re.findall(r"@Model\s+final class\s+(\w+)", all_swift))
    require(required_models.issubset(declared_models), f"missing Phase 1 data models: {sorted(required_models - declared_models)}")
    registered_models = {model for model in required_models if f"{model}.self" in persistence_schema}
    require(registered_models == required_models,
            f"SwiftData schema omits required models: {sorted(required_models - registered_models)}")
    def schema_model_names(source: str, variable_name: str) -> set[str]:
        match = re.search(rf"\b{re.escape(variable_name)}\s*=\s*Schema\(\[(.*?)\]\)", source, re.DOTALL)
        return set(re.findall(r"\b(\w+)\.self", match.group(1))) if match else set()

    app_schema_models = set(re.findall(r"\b(\w+)\.self", schema_inventory.group(1))) if schema_inventory else set()
    app_declared_models = set(re.findall(r"@Model\s+final class\s+(\w+)", app_swift))
    require(app_declared_models == app_schema_models,
            f"SwiftData schema must register every app model exactly once (unregistered={sorted(app_declared_models - app_schema_models)}, undeclared={sorted(app_schema_models - app_declared_models)})")
    migration_tests = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    unit_pair_matrix_test = re.search(
        r"func testEveryUnitPairRoundTripsWithinItsCategory\(\) throws \{(.*?)(?=\n    func test|\Z)",
        migration_tests,
        re.DOTALL,
    )
    unit_pair_matrix_body = unit_pair_matrix_test.group(1) if unit_pair_matrix_test else ""
    require("for category in UnitCategory.allCases" in unit_pair_matrix_body
            and "UnitCategory.allCases.flatMap(\.units)" in unit_pair_matrix_body
            and "Set(categorizedUnits), Set(MeasurementUnit.allCases)" in unit_pair_matrix_body
            and "$0.category == category" in unit_pair_matrix_body
            and "for source in category.units" in unit_pair_matrix_body
            and "for target in category.units" in unit_pair_matrix_body
            and "UnitConversion.convert(converted, from: target, to: source)" in unit_pair_matrix_body
            and "accuracy: 1e-9" in unit_pair_matrix_body,
            "Unit Converter matrix test must exercise and round-trip every unit pair in each category")
    history_balance_test = re.search(
        r"func testHistoryBalancesReconstructEachEventAndRejectOverflow\(\) \{(.*?)(?=\n    func test|\Z)",
        migration_tests,
        re.DOTALL,
    )
    history_balance_body = history_balance_test.group(1) if history_balance_test else ""
    require("impossibleIncrement" in history_balance_body
            and "currentCount: 0" in history_balance_body
            and "currentCount: -1" in history_balance_body,
            "counter history balance test must reject impossible negative reconstructed counts and negative current counts")
    previous_schema_models = schema_model_names(migration_tests, "previousSchema")
    current_schema_models = schema_model_names(migration_tests, "currentSchema")
    require(bool(app_schema_models) and current_schema_models == app_schema_models,
            "store-reopen tests must use exactly the app's current SwiftData model schema")
    require(previous_schema_models == app_schema_models - {"CycleTimeSample", "OEERun", "CounterCommandReceipt"},
            "schema-upgrade tests must model the prior counter-only app schema before adding histories and command receipts")
    model_fields = {
        "HomeProfile": ("id", "name", "usesDefaultName", "sortOrder", "createdAt"),
        "ToolCard": ("id", "homeProfileID", "toolID", "sizeRawValue", "sortOrder", "showsOnWatch", "productionSessionID"),
        "ProductionSession": ("id", "homeProfileID", "toolID", "name", "currentCount", "targetCount", "nextEventSequence", "startedAt"),
        "CountEvent": ("id", "sessionID", "delta", "sequence", "occurredAt", "reversesEventID", "kindRawValue", "payloadSignature"),
        "CounterCommandReceipt": ("id", "sessionID", "processedAt", "payloadSignature"),
        "AppSettings": ("id", "language", "themeID", "selectedHomeProfileID"),
        "CycleTimeSample": ("id", "homeProfileID", "totalSeconds", "quantity", "createdAt"),
        "OEERun": ("id", "homeProfileID", "plannedProductionMinutes", "downtimeMinutes", "idealCycleTimeSeconds", "goodUnits", "defectiveUnits", "createdAt"),
    }
    property_inventory_match = re.search(
        r"static let persistedPropertyInventory: \[String: \[String\]\] = \[(.*?)\n    \]",
        persistence_schema,
        re.DOTALL,
    )
    schema_property_inventory = {
        model: tuple(re.findall(r'"([A-Za-z][A-Za-z0-9]*)"', properties))
        for model, properties in re.findall(r'"([A-Za-z][A-Za-z0-9]*)": \[(.*?)\]', property_inventory_match.group(1), re.DOTALL)
    } if property_inventory_match else {}
    require(schema_property_inventory == model_fields,
            "FactoryToolsSchemaV1 persisted-property inventory must match every current @Model property exactly")
    for model_name, fields in model_fields.items():
        model_path = next((path for path in (ROOT / "FactoryTools").rglob(f"{model_name}.swift")), None)
        model_source = model_path.read_text(encoding="utf-8") if model_path else ""
        require("@Model" in model_source and "@Attribute(.unique) var id: UUID" in model_source,
                f"{model_name} must be a uniquely identified SwiftData model")
        declared_persisted_fields = swift_model_persisted_properties(model_source, model_name)
        require(declared_persisted_fields == set(fields),
                f"{model_name} stored-property inventory differs from its V1 migration contract "
                f"(missing={sorted(set(fields) - declared_persisted_fields)}, "
                f"extra={sorted(declared_persisted_fields - set(fields))})")
        for field in fields:
            require(re.search(rf"\bvar\s+{field}\s*:", model_source) is not None,
                    f"{model_name} is missing its persisted {field} field")
    for core_directory in ("Models", "Services", "Settings", "Tools", "Presets"):
        for path in (ROOT / "FactoryTools" / core_directory).rglob("*.swift"):
            require(not re.search(r"^\s*import\s+SwiftUI\b", path.read_text(encoding="utf-8"), re.MULTILINE),
                    f"shared {core_directory} source {path.relative_to(ROOT)} must stay independent of SwiftUI views")
    core_sources = list((ROOT / "FactoryToolsCore").rglob("*.swift"))
    require(bool(core_sources) and all(
        "import Foundation" in path.read_text(encoding="utf-8")
        and not re.search(r"^\s*import\s+(?:SwiftUI|SwiftData|UIKit|WatchKit)\b", path.read_text(encoding="utf-8"), re.MULTILINE)
        and not re.search(r"\b(?:Locale|NumberFormatter|DateFormatter)\b", path.read_text(encoding="utf-8"))
        for path in core_sources
    ), "FactoryToolsCore must use Foundation-only, locale-neutral source independent of app UI and persistence frameworks")
    tool_definition = (ROOT / "FactoryTools" / "Tools" / "ToolDefinition.swift").read_text(encoding="utf-8")
    tool_card_model = (ROOT / "FactoryTools" / "Models" / "ToolCard.swift").read_text(encoding="utf-8")
    require("struct ToolDefinition" in tool_definition and "@Model" not in tool_definition
            and "let id: ToolID" in tool_definition and "var toolID: String" in tool_card_model,
            "tool registry definitions must stay separate from persisted home cards, which store stable tool IDs")
    require(re.search(r"homeCardRoute:\s*ToolCardRoute\s*,", tool_definition) is not None
            and "homeCardRoute: ToolCardRoute = .comingSoon" not in tool_definition,
            "every tool definition must supply its implemented card route explicitly")

    service = (ROOT / "FactoryTools" / "Services" / "CounterService.swift").read_text(encoding="utf-8")
    watch_processor = (ROOT / "FactoryTools" / "Services" / "WatchCommandProcessor.swift").read_text(encoding="utf-8")
    watch_receiver = (ROOT / "FactoryTools" / "Services" / "WatchConnectivityReceiver.swift").read_text(encoding="utf-8")
    watch_message_start = watch_receiver.find("didReceiveMessage message: [String: Any],\n        replyHandler:")
    watch_message_end = watch_receiver.find("private func makeCatalogData()", watch_message_start)
    watch_message_source = watch_receiver[watch_message_start:watch_message_end] if watch_message_start >= 0 and watch_message_end > watch_message_start else ""
    watch_model = (ROOT / "FactoryToolsWatch" / "WatchCounterModel.swift").read_text(encoding="utf-8")
    watch_send_start = watch_model.find("private func sendHeadIfReachable()")
    watch_send_end = watch_model.find("private func scheduleResponseTimeout(", watch_send_start)
    watch_send_source = watch_model[watch_send_start:watch_send_end] if watch_send_start >= 0 and watch_send_end > watch_send_start else ""
    watch_response_start = watch_model.find("private func applyCommandResponse(")
    watch_response_end = watch_model.find("private func scheduleRetry()", watch_response_start)
    watch_response_source = watch_model[watch_response_start:watch_response_end] if watch_response_start >= 0 and watch_response_end > watch_response_start else ""
    watch_view = (ROOT / "FactoryToolsWatch" / "WatchHomeView.swift").read_text(encoding="utf-8")
    watch_catalog = (ROOT / "FactoryToolsCore" / "WatchCounterCatalog.swift").read_text(encoding="utf-8")
    counter_outbox = (ROOT / "FactoryToolsCore" / "CounterCommandOutbox.swift").read_text(encoding="utf-8")
    watch_cycle_outbox = (ROOT / "FactoryToolsCore" / "WatchCycleTimeCommand.swift").read_text(encoding="utf-8")
    home_service = (ROOT / "FactoryTools" / "Services" / "HomeToolService.swift").read_text(encoding="utf-8")
    watch_cycle_processor_match = re.search(
        r"func process\(_ command: WatchCycleTimeCommand,.*?(?=\n    private func hasAuthorizedCycleTimeCard)",
        watch_processor,
        re.DOTALL,
    )
    watch_cycle_processor_body = watch_cycle_processor_match.group(0) if watch_cycle_processor_match else ""
    watch_cycle_duplicate_lookup_index = watch_cycle_processor_body.find("modelContext.fetch(sampleDescriptor)")
    watch_cycle_access_check_index = watch_cycle_processor_body.find(
        "FeatureAccessRegistry.allows(.watchCounterControl"
    )
    require("CounterService(modelContext: modelContext).apply(command, to: session)" in watch_processor
            and "allowNonWatchSessions" in watch_processor
            and "peerCatalog(isPro: Bool = false)" in watch_processor
            and "FeatureAccessRegistry.allows(feature, isPro: isPro)" in watch_processor
            and "HomeProfileAccess.selectedHome(from: homes, selectedID: selectedID, isPro: isPro)" in watch_processor
            and "HomeProfileAccess.canAccess(homeID, in: homes, isPro: isPro)" in watch_processor
            and "testPeerProcessorShowsSelectedHomeButAcceptsQueuedCommandsForOtherValidHomes" in migration_tests
            and "isPro: ProPurchaseManager.shared.hasPro" in watch_receiver
            and "CounterCommandAcknowledgement(commandID: command.id, status: .rejected)" in watch_processor
            and "$0.showsOnWatch" in watch_processor
            and ".productionCounter, .defectCounter" in watch_processor,
            "Watch and peer command paths must share CounterService while retaining Watch visibility rules")
    require("func process(_ command: WatchCycleTimeCommand" in watch_processor
            and "hasAuthorizedCycleTimeCard(homeID: command.homeProfileID" in watch_processor
            and "CycleTimeSampleService(modelContext: modelContext).save(" in watch_processor
            and "id: command.id" in watch_processor
            and "cycleTimeHome: WatchCycleTimeHomeSnapshot?" in watch_catalog
            and "WatchCycleTimeCommand" in watch_receiver
            and "WatchCommandWireKey.cycleTimeCommand" in watch_receiver
            and "WatchCycleTimeOutboxFileStore" in watch_model
            and "updated.finish()" in watch_model
            and "WatchCycleTimeCommandResponseValidator.accepts(" in watch_model
            and "WatchCycleTimeOutbox.maximumPendingCommandCount" in watch_model
            and '"watch.cycleTime.finish"' in watch_view
            and "WatchCycleTimeDetailView" in watch_view
            and '"watch.cycleTime.startOrResume"' in watch_view
            and '"watch.cycleTime.pause"' in watch_view
            and '"watch.cycleTime.reset.hint"' in watch_view
            and '"watch.cycleTime.reset.confirmation"' in watch_view
            and ".confirmationDialog(" in watch_view
            and "role: .destructive" in watch_view
            and "testWatchCycleTimeCommandValidatesAndRoundTripsMeasurement" in core_contract_tests
            and "testWatchCycleTimeOutboxPersistsTimerAndIdempotentFIFOCommands" in core_contract_tests
            and "testWatchCycleTimeOutboxFileStoreRejectsOversizedFileWithoutChangingIt" in core_contract_tests
            and "testWatchCycleTimeOutboxStoresItsMaximumValidQueueWithinFileLimit" in core_contract_tests
            and "testWatchCycleTimeOutboxKeepsHomeAndRetainsSubsecondMeasurementUntilSaveable" in core_contract_tests
            and "testWatchCycleTimeOutboxRejectsConflictingIDsAndOutOfOrderAcknowledgements" in core_contract_tests
            and "testFreeWatchCycleTimeCapturesAndIdempotentlyStoresSamplesOnIPhone" in migration_tests
            and watch_cycle_duplicate_lookup_index >= 0
            and watch_cycle_access_check_index >= 0
            and watch_cycle_duplicate_lookup_index < watch_cycle_access_check_index
            and "XCTAssertEqual(try processor.process(command, isPro: false).status, .alreadyApplied)" in migration_tests,
            "Free Watch Cycle Time must persist timer state, queue stable-ID samples offline, validate on iPhone, and avoid duplicate history rows")
    require("maximumFileSizeBytes = 4 * 1_048_576" in watch_cycle_outbox
            and "fileURL.resourceValues(forKeys: [.fileSizeKey])" in watch_cycle_outbox
            and "Data(contentsOf: fileURL, options: .mappedIfSafe)" in watch_cycle_outbox
            and "data.count <= Self.maximumFileSizeBytes" in watch_cycle_outbox,
            "Watch Cycle Time outbox files must be bounded before JSON decoding and when saved")
    require("testWatchCycleTimeOutboxFileStoreRejectsMalformedFileWithoutChangingIt" in core_contract_tests
            and "XCTAssertEqual(try Data(contentsOf: fileURL), malformed)" in core_contract_tests,
            "a malformed Watch Cycle Time outbox must remain intact when loading fails")
    watch_cycle_capacity_test = re.search(
        r"func testWatchCycleTimeOutboxStoresItsMaximumValidQueueWithinFileLimit\(\) throws \{(.*?)(?=\n    func test|\Z)",
        core_contract_tests,
        re.DOTALL,
    )
    watch_cycle_capacity_body = watch_cycle_capacity_test.group(1) if watch_cycle_capacity_test else ""
    require("0..<WatchCycleTimeOutbox.maximumPendingCommandCount" in watch_cycle_capacity_body
            and "try store.save(outbox)" in watch_cycle_capacity_body
            and "XCTAssertEqual(try store.load(), outbox)" in watch_cycle_capacity_body,
            "the maximum valid Watch cycle-time queue must fit the bounded file store")
    require("WatchDisplayLanguage(rawValue: $0.language) ?? .system" in watch_processor
            and watch_processor.find("let displayLanguage =") < watch_processor.find("FeatureAccessRegistry.allows(feature, isPro: isPro)")
            and "displayLanguage: displayLanguage" in watch_processor
            and "public let displayLanguage: WatchDisplayLanguage" in watch_catalog
            and "decodeIfPresent(WatchDisplayLanguage.self, forKey: .displayLanguage) ?? .system" in watch_catalog
            and "displayLanguage = catalog.displayLanguage" in watch_model
            and "private var displayLocale: Locale" in watch_view
            and ".environment(\\.locale, displayLocale)" in watch_view
            and 'XCTAssertEqual(restored.displayLanguage, .japanese)' in core_contract_tests
            and 'XCTAssertEqual(restoredLegacyCatalog.displayLanguage, .system)' in core_contract_tests,
            "Watch catalog must apply the iPhone language, keep empty-state screens localized, and decode old catalogs as system language")
    require(watch_processor.count("defaultSessionNameToolID: defaultSessionNameToolID(session, toolID: toolID)") == 2
            and "private func defaultSessionNameToolID(_ session: ProductionSession, toolID: ToolID) -> ToolID?" in watch_processor
            and '"ja", "en"' in watch_processor
            and "knownDefaultNames.contains(session.name) ? toolID : nil" in watch_processor
            and "defaultSessionNameToolID == .productionCounter" in watch_view
            and "defaultSessionNameToolID == .defectCounter" in watch_view
            and "Text(verbatim: session.sessionName)" in watch_view
            and "defaultSessionNameToolID == .productionCounter" in peer_counter_view
            and "defaultSessionNameToolID == .defectCounter" in peer_counter_view
            and "Text(verbatim: session.sessionName)" in peer_counter_view
            and "legacySession" in core_contract_tests,
            "generated counter-session names must follow each companion UI locale while custom and legacy names remain intact")
    require(service.count("WatchConnectivityReceiver.shared.publishCatalog()") >= 2
            and home_service.count("WatchConnectivityReceiver.shared.publishCatalog()") >= 5,
            "successful counter/home/card mutations must publish an updated Watch catalog")
    require("import WatchConnectivity" in watch_receiver
            and "session.activate()" in watch_receiver
            and "WatchCommandProcessor(modelContext:" in watch_receiver
            and "replyHandler(response)" in watch_receiver,
            "iPhone WatchConnectivity receiver must process commands through the app processor and reply")
    watch_catalog_start = watch_receiver.find("func publishCatalog()")
    watch_catalog_end = watch_receiver.find("nonisolated func session(", watch_catalog_start)
    watch_catalog_source = watch_receiver[watch_catalog_start:watch_catalog_end] if watch_catalog_start >= 0 and watch_catalog_end > watch_catalog_start else ""
    peer_authority_message_start = local_peer_transport.find("private func handleAuthorityMessage(")
    peer_authority_message_end = local_peer_transport.find("private func handleClientMessage(", peer_authority_message_start)
    peer_authority_message_source = local_peer_transport[peer_authority_message_start:peer_authority_message_end] if peer_authority_message_start >= 0 and peer_authority_message_end > peer_authority_message_start else ""
    peer_command_case = re.search(r"case \.command:\n(.*?)\n            case \.catalog, \.commandResult:", peer_authority_message_source, re.DOTALL)
    peer_command_source = peer_command_case.group(1) if peer_command_case else ""
    require("session.activationState == .activated" in watch_catalog_source
            and "session.isPaired" in watch_catalog_source
            and "session.isWatchAppInstalled" in watch_catalog_source
            and "session.updateApplicationContext(" in watch_catalog_source
            and "self.publishCatalog()" not in watch_message_source
            and peer_command_source.count("wire.send(.commandResult(") == 1
            and ".peerCatalog(" not in peer_command_source
            and "wire.send(.catalog(" not in peer_command_source,
            "companion catalog rebuilds must require an installed paired Watch and avoid duplicate post-command catalog publication")
    authority_start = local_peer_transport.find("func startAuthority(modelContainer:")
    authority_end = local_peer_transport.find("func publishCatalog()", authority_start)
    authority_source = local_peer_transport[authority_start:authority_end] if authority_start >= 0 and authority_end > authority_start else ""
    entitlement_resolution_match = re.search(
        r"\.onChange\(of: proPurchases\.hasResolvedEntitlement\) \{(.*?)\n        \}",
        bootstrap,
        re.DOTALL,
    )
    entitlement_resolution_source = entitlement_resolution_match.group(1) if entitlement_resolution_match else ""
    require("guard ProPurchaseManager.shared.hasResolvedEntitlement" in watch_receiver
            and watch_message_source.find("guard ProPurchaseManager.shared.hasResolvedEntitlement") >= 0
            and watch_message_source.find("guard ProPurchaseManager.shared.hasResolvedEntitlement") < watch_message_source.find("if requestsCatalog")
            and "replyHandler([WatchCommandWireKey.retry: true])" in watch_message_source
            and "guard ProPurchaseManager.shared.hasResolvedEntitlement" in authority_source
            and "guard proPurchases.hasResolvedEntitlement" in bootstrap
            and "WatchConnectivityReceiver.shared.publishCatalog()" in entitlement_resolution_source
            and "startPeerAuthorityIfAvailable()" in entitlement_resolution_source,
            "Watch and iPad transports must defer catalog and command handling until StoreKit entitlement resolution, preserving queued Pro actions on launch")
    require("CounterCommandOutboxFileStore" in watch_model
            and "updated.acknowledgeHead(acknowledgement)" in watch_model
            and "sendingCommandID != command.id" in watch_model
            and "CounterCommandResponseValidator.isComplete(" in watch_model
            and "CounterCommandResponseValidator.indicatesUnavailableSession(" in watch_model
            and "WatchCounterCommandResponseValidator.snapshot(snapshot, matches: expectedCommand)" in watch_model
            and "private var sendingAttemptID: UUID?" in watch_model
            and "self.sendingAttemptID == attemptID" in watch_model
            and "scheduleResponseTimeout(for: command, attemptID: attemptID)" in watch_model
            and "Task.sleep(for: .seconds(15))" in watch_model
            and "activationDidCompleteWith activationState" in watch_model
            and "sessionReachabilityDidChange(_ session: WCSession)" in watch_model
            and "self.applyCatalog(catalogData)" in watch_model
            and "self.refreshCatalog()" in watch_model
            and "self.sendHeadIfReachable()" in watch_model
            and "retryTask == nil" in watch_send_source
            and "var updatedSessions = sessions" in watch_response_source
            and watch_response_source.index("try fileStore.save(updated)") < watch_response_source.index("outbox = updated")
            and watch_response_source.index("try fileStore.save(updated)") < watch_response_source.index("sessions = updatedSessions")
            and watch_response_source.index("outbox = updated") < watch_response_source.index("pendingCount = outbox.count")
            and "clearSendingAttempt()" in watch_model
            and watch_model.index("self.sendingAttemptID == attemptID") < watch_model.index("self.applyCommandResponse(")
            and "self.sendingCommandID = nil" in watch_model
            and "responseSnapshot = nil" in watch_model
            and "private func scheduleRetry()" in watch_model
            and "CounterCommandRetryPolicy.delaySeconds(forAttempt: retryAttempt)" in watch_model
            and "updated.discardCommands(for: expectedCommand.sessionID)" in watch_model
            and "func retryStorage()" in watch_model
            and "try reloadOutboxFromDisk()" in watch_model
            and "private func reloadOutboxFromDisk() throws" in watch_model
            and "public enum WatchCounterCommandResponseValidator" in watch_catalog
            and "public enum CounterCommandResponseValidator" in watch_catalog
            and "indicatesUnavailableSession(" in watch_catalog
            and "acknowledgement.status == .rejected" in watch_catalog
            and "public mutating func discardCommands(for sessionID: UUID)" in counter_outbox
            and "public enum CounterCommandRetryPolicy" in counter_outbox,
            "Watch app must persist its outbox, serialize each head send, validate matching acknowledgements/snapshots, and retry with capped backoff")
    require('Label("watch.storageUnavailable"' in watch_view
            and 'Text("watch.storageUnavailable.message")' in watch_view
            and 'Label("watch.queueFull.message"' in watch_view
            and 'Button("watch.refresh"' in watch_view
            and "model.retryStorage()" in watch_view,
            "Watch storage failures must provide a localized, non-destructive retry action")
    require('ContentUnavailableView("watch.sessionUnavailable"' in watch_view
            and 'Button("watch.refresh"' in watch_view
            and "Text(status.messageKey)" in watch_view
            and 'Label("watch.status.rejected"' in watch_view
            and "@Environment(\\.scenePhase)" in watch_view
            and "if phase == .active { model.refreshCatalog() }" in watch_view,
            "Watch must explain unavailable sessions, offer catalog refresh recovery, and refresh on resume")
    counter_command = (ROOT / "FactoryToolsCore" / "CounterCommand.swift").read_text(encoding="utf-8")
    acknowledgement_source = (ROOT / "FactoryToolsCore" / "CounterCommandAcknowledgement.swift").read_text(encoding="utf-8")
    require("public struct CounterCommandOutbox: Codable, Equatable" in counter_outbox
            and "public static let currentSchemaVersion = 1" in counter_outbox
            and "pendingCommands.first(where: { $0.id == command.id })" in counter_outbox
            and "guard existing == command" in counter_outbox
            and "pendingCommands.first?.id == commandID" in counter_outbox
            and "acknowledgeHead(_ acknowledgement: CounterCommandAcknowledgement)" in counter_outbox
            and "uniqueIDs.count == commands.count" in counter_outbox
            and "public struct CounterCommandOutboxFileStore" in counter_outbox
            and "Data(contentsOf: fileURL, options: .mappedIfSafe)" in counter_outbox
            and "data.write(to: fileURL, options: .atomic)" in counter_outbox
            and "return CounterCommandOutbox()" in counter_outbox,
            "shared command outbox must preserve FIFO order, validate versioned restore, atomically persist, suppress exact retries, and reject ID conflicts")
    enqueue_transaction_start = counter_outbox.find("public static func enqueue(")
    acknowledgement_transaction_start = counter_outbox.find("public static func acknowledge(", enqueue_transaction_start)
    acknowledgement_transaction_end = counter_outbox.find("/// Bounded exponential retry schedule", acknowledgement_transaction_start)
    enqueue_transaction_source = counter_outbox[enqueue_transaction_start:acknowledgement_transaction_start]
    acknowledgement_transaction_source = counter_outbox[acknowledgement_transaction_start:acknowledgement_transaction_end]
    require(enqueue_transaction_start >= 0
            and acknowledgement_transaction_start > enqueue_transaction_start
            and acknowledgement_transaction_end > acknowledgement_transaction_start
            and "var candidate = current" in enqueue_transaction_source
            and "try persist(candidate)" in enqueue_transaction_source
            and enqueue_transaction_source.index("try persist(candidate)") < enqueue_transaction_source.index("return candidate")
            and "current.nextCommand?.id == command.id" in acknowledgement_transaction_source
            and "CounterCommandResponseValidator.isComplete(" in acknowledgement_transaction_source
            and "candidate.discardCommands(for: command.sessionID)" in acknowledgement_transaction_source
            and "candidate.acknowledgeHead(acknowledgement)" in acknowledgement_transaction_source
            and "try persist(candidate)" in acknowledgement_transaction_source
            and acknowledgement_transaction_source.index("try persist(candidate)") < acknowledgement_transaction_source.index("return candidate")
            and "testOutboxEnqueueTransactionKeepsCurrentQueueWhenPersistenceFails" in core_contract_tests
            and "testOutboxAcknowledgementTransactionKeepsHeadWhenPersistenceFails" in core_contract_tests
            and "testUnavailableSessionTransactionKeepsAllCommandsWhenPersistenceFails" in core_contract_tests,
            "outbox transactions must persist candidate queues before returning and cover failed enqueue/acknowledgement saves")
    require("public enum CounterCommandAcknowledgementStatus: String, Codable, Equatable, CaseIterable" in acknowledgement_source
            and "case applied" in acknowledgement_source
            and "case alreadyApplied" in acknowledgement_source
            and "case noChange" in acknowledgement_source
            and "case staleUndo" in acknowledgement_source
            and "case rejected" in acknowledgement_source
            and "public struct CounterCommandAcknowledgement: Codable, Equatable" in acknowledgement_source
            and "values.decode(UUID.self, forKey: .commandID)" in acknowledgement_source,
            "shared acknowledgement must expose stable, versioned, language-independent status values and command identity")
    backup_import_source = (ROOT / "FactoryTools" / "Settings" / "AppSettings.swift").read_text(encoding="utf-8")
    require("private func mappedID(" in backup_import_source
            and "private func mappedOptionalID(" in backup_import_source
            and not re.search(r"\]\s*!(?!=)", backup_import_source),
            "backup import ID remapping must report missing mappings instead of force-unwrapping")
    for operation in ("increment", "decrement", "quickAdd", "reset", "undo", "setTarget"):
        require(re.search(rf"\bfunc\s+{operation}\b", service) is not None,
                f"CounterService is missing the {operation} operation")
    for path in (ROOT / "FactoryTools").rglob("*.swift"):
        if path.name not in ("CounterService.swift", "ProductionSession.swift"):
            source = path.read_text(encoding="utf-8")
            require(not re.search(r"\bsession\.(?:currentCount|targetCount)\s*(?:\+=|-=|=(?!=))", source),
                    f"{path.relative_to(ROOT)} writes counter state outside CounterService")
    require(service.count("modelContext.insert(event)") == 1
            and "CounterCommand(sessionID: session.id, operation: .increment)" in service
            and "CounterCommand(sessionID: session.id, operation: .decrement)" in service
            and "CounterCommand(sessionID: session.id, operation: .quickAdd(amount))" in service
            and "CounterCommand(sessionID: session.id, operation: .reset)" in service
            and "CounterCommand(sessionID: session.id, operation: .undo(eventID: latest.id))" in service
            and "func apply(_ command: CounterCommand, to session: ProductionSession)" in service
            and "id: command.id" in service
            and "occurredAt: command.createdAt" in service
            and "payloadSignature: command.payloadSignature" in service
            and "guard storedSignature == command.payloadSignature" in service
            and "guard try event(withID: command.id) == nil" in service
            and "throw CounterServiceError.commandIdentifierConflict" in service
            and "return .alreadyApplied" in service
            and "latestUndoableEvent(in: events), original.id == eventID" in service
            and "static let currentSchemaVersion = 1" in counter_command
            and "values.decode(Int.self, forKey: .schemaVersion)" in counter_command
            and 'case quickAdd = "quickAdd"' in counter_command
            and "kind: kind" in service,
            "all counter operations must share the serializable, idempotent event and aggregate mutation path")
    require("#Predicate<CountEvent>" in service and "$0.sessionID == sessionID" in service,
            "counter history queries must be scoped to the active production session")
    require("if first.sequence != second.sequence" in service
            and "if first.occurredAt != second.occurredAt" in service
            and "first.id.uuidString < second.id.uuidString" in service,
            "Undo must select a deterministic latest event when sequence values tie")

    home_view = (ROOT / "FactoryTools" / "Features" / "Home" / "HomeView.swift").read_text(encoding="utf-8")
    require("@Query private var cards: [ToolCard]" in home_view,
            "home cards must observe persisted ToolCard changes from SwiftData")
    require("if homeCards.isEmpty" in home_view
            and 'ContentUnavailableView(\n                                "home.empty.title"' in home_view
            and 'description: Text("home.empty.message")' in home_view,
            "an empty home must explain the first tool-add action")
    for path in (ROOT / "FactoryTools" / "Features").rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        require(not re.search(r"modelContext\.(?:save|delete|insert|rollback)\s*\(", source),
                f"{path.relative_to(ROOT)} must route persistence mutations through an app service")
        require(not re.search(
            r"\b(?:home\.(?:name|usesDefaultName|sortOrder)|card\.(?:size|sizeRawValue|sortOrder))\s*=(?!=)",
            source,
        ), f"{path.relative_to(ROOT)} must route home/card property changes through an app service")
    require("HomeCardOrdering.ordered(cards)" in home_view,
            "home cards must use a deterministic order when stored sort positions tie")
    home_service = (ROOT / "FactoryTools" / "Services" / "HomeToolService.swift").read_text(encoding="utf-8")
    home_creation_test = re.search(
        r"func testCreateHomeCompactsExtremeSortOrdersWithoutChangingOrder\(\) throws \{(.*?)(?=\n    func test|\Z)",
        migration_tests,
        re.DOTALL,
    )
    home_creation_test_body = home_creation_test.group(1) if home_creation_test else ""
    require("HomeProfileOrdering.ordered(homes)" in home_service
            and "HomeProfileOrdering.assignSortOrders(orderedHomes)" in home_service
            and "sortOrder: orderedHomes.count" in home_service
            and "max() ?? -1) + 1" not in home_service,
            "creating a home must preserve deterministic order and avoid sort-order integer overflow")
    require("Int.min" in home_creation_test_body and "Int.max" in home_creation_test_body
            and '[0, 1, 2]' in home_creation_test_body,
            "home creation source test must cover extreme sort-order values and compacted positions")
    require("@Environment(\\.dynamicTypeSize)" in home_view
            and "HomeGridLayout.minimumColumnWidth(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)" in home_view
            and "HomeGridLayout.maximumContentWidth" in home_view
            and "static let maximumColumnCount = 5" in home_view
            and "availableWidth.isFinite" in home_view
            and "minimumColumnWidth.isFinite" in home_view
            and "spacing.isFinite" in home_view
            and "guard fittingCount.isFinite else { return maximumColumnCount }" in home_view
            and "HomeGridLayout.horizontalPadding * 2" in home_view
            and "HomeGridLayout.columnCount(" in home_view
            and "HomeGridLayout.rows(for: homeCards, columnCount: columnCount)" in home_view
            and "LazyVStack(spacing: HomeGridLayout.itemSpacing)" in home_view
            and "HStack(alignment: .top, spacing: HomeGridLayout.itemSpacing)" in home_view
            and "if !row.isFullWidth" in home_view
            and "isAccessibilitySize ? 280 : 160" in (ROOT / "FactoryTools" / "Features" / "Home" / "HomeView.swift").read_text(encoding="utf-8"),
            "home layout must adapt row columns to screen and Dynamic Type widths")
    require(".draggable(" in home_view and ".dropDestination(" in home_view,
            "home cards must support drag reordering")
    require(".sheet(item: $activeSheet)" in home_view and "case .toolPicker" in home_view and "case .settings" in home_view,
            "tool picker and settings must be reachable through one sheet router")
    card_view = (ROOT / "FactoryTools" / "Features" / "Home" / "HomeToolCardView.swift").read_text(encoding="utf-8")
    card_access_gate = card_view.find("if !canAccessTool {")
    card_route_switch = card_view.find("switch homeCardRoute", card_access_gate)
    card_access_else = card_view.find("} else {", card_access_gate)
    require(card_access_gate >= 0 and card_access_else >= card_access_gate
            and card_route_switch > card_access_else,
            "home cards must replace Pro tool content with the purchase entry when the entitlement is unavailable")
    require("@Query private var sessions: [ProductionSession]" in card_view
            and "ToolSessionAssignment.session(for: card, in: sessions)" in card_view,
            "counter cards must observe and resolve their persisted ProductionSession")
    require("HomeCardPresentation.minimumHeight(for: card.size)" in card_view
            and "HomeCardPresentation.outerSpacing(for: card.size)" in card_view
            and "HomeCardPresentation.showsTarget(for: card.size)" in card_view
            and "HomeCardPresentation.showsProgress(for: card.size)" in card_view,
            "card-size layout and information visibility must come from the shared presentation rules")
    require("@ScaledMetric(relativeTo: .title)" in card_view
            and "@ScaledMetric(relativeTo: .largeTitle)" in card_view
            and "smallScale: smallCounterScale" in card_view
            and "regularScale: regularCounterScale" in card_view,
            "counter typography must scale with the user's Dynamic Type setting through theme tokens")
    require("catch CounterServiceError.eventSequenceExhausted" in card_view
            and 'presentSaveError(messageKey: "error.counterEventLimit")' in card_view
            and "catch CounterServiceError.eventDeltaCannotBeReversed" in card_view
            and 'presentSaveError(messageKey: "error.counterEventInvalid")' in card_view
            and {"error.counterEventLimit", "error.counterEventInvalid"}.issubset(strings),
            "counter sequence limits and invalid-event Undo must show localized counter-specific messages")
    require('Image(systemName: "plus")' in card_view
            and "isAtMaximumCount ? theme.secondaryText : theme.accentForeground" in card_view
            and "isAtMaximumCount ? theme.cardBackground : theme.accent" in card_view,
            "the prominent counter action must use high-contrast, theme-controlled enabled and disabled colors")
    require("let isAtMaximumCount = session.currentCount == Int.max" in card_view
            and card_view.count(".disabled(isAtMaximumCount)") == 4,
            "increment and Quick Add controls must be disabled when the count reaches its maximum")
    require("ToolCardSize.allCases" in card_view and "supportedCardSizes" in card_view,
            "tool cards must expose registry-supported size choices")
    require('homeCardRoute.showsTargetSettings, session != nil' in card_view
            and 'self == .productionCounter || self == .productionProgress' in (ROOT / "FactoryTools" / "Tools" / "ToolDefinition.swift").read_text(encoding="utf-8"),
            "counter and progress target settings must not open an empty sheet when the session is unavailable")
    require("Label(LocalizedStringKey(size.titleKey), systemImage: \"checkmark\")" in card_view
            and "Text(LocalizedStringKey(size.titleKey))" in card_view,
            "both selected and unselected card-size menu labels must resolve through localization")
    require("number.locale(locale)" in card_view, "counter numbers must follow the selected app locale")
    require('.accessibilityLabel("counter.currentCount")' in card_view
            and ".accessibilityValue(Text(formattedCount(session.currentCount)))" in card_view
            and '.accessibilityLabel("counter.goal")' in card_view
            and ".accessibilityValue(Text(formattedCount(session.targetCount)))" in card_view
            and '.accessibilityLabel("counter.progress")' in card_view
            and "ProductionProgressMath.fraction(" in card_view
            and "HomeCardPresentation.formattedProgress(" in card_view
            and ".percent.precision(.fractionLength(1)).locale(locale)" in card_view
            and "counter.currentCount" in strings,
            "the displayed counter, target, and progress must expose localized VoiceOver labels and values")
    require('.accessibilityLabel("counter.minusOne")' in card_view
            and '.accessibilityLabel("counter.plusOne")' in card_view
            and '.accessibilityLabel("counter.moreActions")' in card_view
            and 'Button("counter.undo", systemImage:' in card_view
            and '.confirmationDialog(' in card_view
            and '"counter.resetConfirmation.title"' in card_view
            and '"counter.resetConfirmation.message"' in card_view
            and 'Label("counter.reset", systemImage: "arrow.counterclockwise")' in card_view,
            "primary counter controls must have localized accessible labels and destructive reset confirmation")
    require(card_view.count("minWidth: HomeCardPresentation.minimumActionWidth") >= 2
            and "static let minimumActionWidth: CGFloat = 44" in card_view
            and "static let actionSpacing: CGFloat = 2" in card_view
            and "HStack(spacing: HomeCardPresentation.actionSpacing)" in card_view
            and card_view.count(".buttonStyle(.plain)") >= 2
            and ".frame(width: HomeCardPresentation.minimumActionWidth, height: HomeCardPresentation.minimumActionWidth)" in card_view,
            "counter card actions must preserve at least 44-point tap targets without added button-style padding")
    require("HomeCardService(modelContext: modelContext).remove(card)" in home_view
            and "HomeCardService(modelContext: modelContext).move(sourceID, before: destinationID, in: home.id)" in home_view
            and "HomeCardService(modelContext: modelContext).setSize(size, for: card)" in card_view,
            "home card removal, reordering, and resizing must route through HomeCardService")
    for key in re.findall(r"case \.\w+:\s*\"([a-zA-Z][a-zA-Z0-9_.-]+)\"", card_view):
        require(key in strings, f"card size references missing localization key {key!r}")
    for operation in ("increment(session:", "decrement(session:", "quickAdd(", "reset(session:", "undo(session:"):
        require(f"CounterService(modelContext: modelContext).{operation}" in card_view,
                f"counter UI must route {operation.rstrip('(')} through CounterService")
    for evidence, description in (
        ('Button("counter.quickAddFive")', "the +5 Quick Add action"),
        ("quickAdd(5, to: session)", "the +5 Quick Add service call"),
        ('Button("counter.quickAddTen")', "the +10 Quick Add action"),
        ("quickAdd(10, to: session)", "the +10 Quick Add service call"),
        ('Button("counter.quickAddCustom", systemImage: "plus")', "the custom Quick Add action"),
        ("CounterUndoMenuItem(sessionID: session.id)", "the history-aware Undo menu action"),
        ('Label("counter.reset", systemImage: "arrow.counterclockwise")', "the reset action"),
        ('Button("counter.goalSettings", systemImage: "slider.horizontal.3")', "the target-settings action"),
    ):
        require(evidence in card_view, f"counter card is missing {description}")
    require("CounterHistoryOrdering.latestUndoableEvent(in: events) == nil" in card_view,
            "the Undo menu action must be disabled when the active session has no undoable event")
    require('.confirmationDialog(' in card_view
            and '"counter.resetConfirmation.title"' in card_view
            and '"counter.resetConfirmation.message"' in card_view
            and '.disabled(session.currentCount == 0)' in card_view
            and {"counter.reset", "counter.resetConfirmation.title", "counter.resetConfirmation.message"}.issubset(strings),
            "count reset must require localized confirmation and stay unavailable at zero")
    counter_settings = (ROOT / "FactoryTools" / "Features" / "Counter" / "CounterSettingsView.swift").read_text(encoding="utf-8")
    require(".presentationDetents([.medium, .large])" in counter_settings
            and ".presentationDragIndicator(.visible)" in counter_settings
            and ".presentationDetents([.medium, .large])" in settings_view
            and ".presentationDragIndicator(.visible)" in settings_view,
            "home and target settings sheets must remain expandable for keyboard input")
    require("CounterService(modelContext: modelContext).setTarget(" in counter_settings,
            "target changes must route through CounterService")
    require("struct CounterQuickAddView: View" in counter_settings
            and 'TextField("counter.quickAddAmount", text: $amountText)' in counter_settings
            and "value > 0" in counter_settings
            and "CounterService(modelContext: modelContext).quickAdd(amount, to: session)" in counter_settings
            and "counter.quickAddCustom" in strings
            and "counter.quickAddAmount" in strings
            and "counter.quickAddApply" in strings,
            "custom Quick Add must validate a positive amount, use CounterService, and be localized")
    require('Button("counter.history", systemImage: "clock.arrow.circlepath")' in card_view
            and "struct CounterHistoryView: View" in counter_settings
            and "#Predicate<CountEvent> { $0.sessionID == selectedSessionID }" in counter_settings
            and "CounterHistoryOrdering.ordered(events)" in counter_settings
            and "let orderedEvents = CounterHistoryOrdering.ordered(events)" in counter_settings
            and "let balances = CounterHistoryBalances.afterEachEvent(" in counter_settings
            and "orderedEvents: orderedEvents" in counter_settings
            and "if let countAfter = balances?[event.id]" in counter_settings
            and "if balances == nil" in counter_settings
            and "counter.history.balanceUnavailable" in counter_settings
            and {"counter.history", "counter.history.empty.title", "counter.history.empty.message",
                 "counter.history.kind.increment", "counter.history.kind.decrement", "counter.history.kind.quickAdd",
                 "counter.history.kind.reset", "counter.history.kind.undo", "counter.history.kind.unknown",
                 "counter.history.balanceUnavailable"}.issubset(strings),
            "count history must be session-scoped, deterministically ordered, compute balances once from the ordered rows, and localize corruption guidance")
    event_model = (ROOT / "FactoryTools" / "Models" / "CountEvent.swift").read_text(encoding="utf-8")
    require("var kindRawValue: String?" in event_model
            and "enum CounterEventKind: String" in counter_command
            and "struct CounterCommand: Codable, Equatable, Identifiable" in counter_command
            and "enum CounterCommandOperation: Codable, Equatable" in counter_command
            and 'event.kindRawValue ?? ""' in service
            and "csvField(value, neutralizeFormula: index == 4)" in service
            and "private static func csvField(_ value: String, neutralizeFormula: Bool) -> String" in service
            and '"=+-@".contains($0)' in service
            and "eventKindTitleKey(for: event)" in counter_settings,
            "counter event kinds must remain optional for existing rows and appear in history and exports")
    require("struct CSVExportFile: Transferable" in counter_settings
            and "ShareLink(" in counter_settings
            and "DataRepresentation(exportedContentType: .commaSeparatedText)" in counter_settings
            and '"session_id,event_id,sequence,timestamp_utc,kind,delta,count_after,reverses_event_id"' in service
            and "ISO8601DateFormatter()" in service
            and "records.filter { $0.sessionID == sessionID }" in service
            and "struct CounterHistoryCSVRecord: Sendable" in service
            and "CounterHistoryBalances.afterEachEvent" in service
            and "guard currentCount >= 0 else { return nil }" in service
            and "guard !overflow, previousCount >= 0 else { return nil }" in service
            and "CounterHistoryBalances.afterEachEvent(" in counter_settings
            and "orderedEvents: orderedEvents" in counter_settings
            and "CounterHistoryCSV.make(" in counter_settings
            and "records = orderedEvents.map(CounterHistoryCSVRecord.init)" in counter_settings
            and "makeContent: @Sendable () -> String" in counter_settings
            and "Data(file.makeContent().utf8)" in counter_settings
            and "item: CSVExportFile(content: Data(" not in counter_settings
            and "currentCount: session.currentCount" in counter_settings
            and "counter.history.balanceAfter" in counter_settings
            and {"counter.history.export", "counter.history.exportPreview"}.issubset(strings),
            "counter history must show per-event balances and defer stable session-scoped CSV generation until the share sheet requests it")
    require('TextField("counter.goal", text: $targetText)' in counter_settings
            and ".keyboardType(.numberPad)" in counter_settings
            and "guard let target = parsedTarget, target >= 0 else { return }" in counter_settings
            and 'Section("counter.goal")' not in counter_settings,
            "target settings must accept and validate a nonnegative numeric target")
    home_tool_service = (ROOT / "FactoryTools" / "Services" / "HomeToolService.swift").read_text(encoding="utf-8")
    add_tools_method = re.search(
        r"private func addTools\([\s\S]*?\n    \}\n\n    private func makeCard",
        home_tool_service,
        re.DOTALL,
    )
    add_tools_body = add_tools_method.group(0) if add_tools_method else ""
    card_builder = re.search(r"private func makeCard\(.*?\n    \}\n\}", home_tool_service, re.DOTALL)
    card_builder_body = card_builder.group(0) if card_builder else ""
    for evidence, description in (
        ("modelContext.insert(created)", "new session insertion"),
        ("try modelContext.fetch(cardDescriptor)", "card fetch"),
        ("modelContext.insert(card)", "new card insertion"),
        ("try modelContext.save()", "card and session save"),
    ):
        require(evidence in add_tools_body + card_builder_body,
                f"home-tool add transaction must include {description} so failures roll back pending changes")
    require("modelContext.rollback()" in add_tools_body and "func applyAssemblyPreset" in home_tool_service
            and "func applyPackagingPreset" in home_tool_service,
            "home preset card and session creation must roll back together and use the home-tool service")
    app_settings_service = (ROOT / "FactoryTools" / "Settings" / "AppSettings.swift").read_text(encoding="utf-8")
    settings_view = (ROOT / "FactoryTools" / "Features" / "Settings" / "AppSettingsView.swift").read_text(encoding="utf-8")
    theme_id_source = (ROOT / "FactoryTools" / "Themes" / "ThemeID.swift").read_text(encoding="utf-8")
    theme_tests = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    require("testWatchCatalogLocalizesGeneratedSessionNamesAfterLanguageChange" in theme_tests
            and 'XCTAssertNil(catalog.sessions.first(where: { $0.sessionName == "第2ライン" })?.defaultSessionNameToolID)' in theme_tests,
            "Watch and iPad default labels must localize while a custom session name remains verbatim")
    require("public let homeNameIsDefault: Bool?" in watch_catalog
            and "homeNameIsDefault: home.usesDefaultName ? true : nil" in watch_processor
            and 'watchHomeNameText(progress.homeName, isDefault: progress.homeNameIsDefault)' in watch_view
            and 'watchHomeNameText(cycleTimeHome.homeName, isDefault: cycleTimeHome.homeNameIsDefault)' in watch_view
            and 'watchHomeNameText(session.homeName, isDefault: session.homeNameIsDefault)' in watch_view
            and 'peerHomeNameText(session.homeName, isDefault: session.homeNameIsDefault)' in peer_counter_view
            and "testCompanionCatalogsMarkDefaultHomeNamesForLocalTranslation" in theme_tests
            and "XCTAssertTrue(watchCatalog.progressCards.first?.homeNameIsDefault == true)" in theme_tests,
            "Watch and iPad must localize only generated default home names and retain wire compatibility for older catalogs")
    require("product.isFamilyShareable ?" in settings_view
            and "pro.familySharing.available" in settings_view
            and "pro.familySharing.unavailable" in settings_view
            and "One purchase unlocks Production Progress, OEE, extra homes, and more. The App Store shows the applicable price." in strings.get("pro.description", {}).get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value", "")
            and "買い切りで生産進捗、OEE、追加ホームなどを解放します。価格はApp Storeに表示されます。" in strings.get("pro.description", {}).get("localizations", {}).get("ja", {}).get("stringUnit", {}).get("value", ""),
            "the Pro offer must show StoreKit's Family Sharing availability and must not claim that its price is undecided")
    require("enum ThemeID: String, Codable" in theme_id_source
            and 'case industrialDark = "industrial.dark"' in theme_id_source
            and "import SwiftUI" not in app_settings_service,
            "persisted theme IDs must be a UI-independent stable type")
    require("func setLanguage(_ language: AppLanguage, for settings: AppSettings) throws" in app_settings_service
            and "WatchConnectivityReceiver.shared.publishCatalog()" in app_settings_service
            and app_settings_service.find("try modelContext.save()", app_settings_service.find("func setLanguage"))
            < app_settings_service.find("WatchConnectivityReceiver.shared.publishCatalog()", app_settings_service.find("func setLanguage")),
            "app language changes must persist before publishing the updated Watch catalog")
    watch_language_test_match = re.search(
        r"func testWatchCommandProcessorCatalogAndCommandUseTheCanonicalCounterService\(\) throws \{(.*?)(?=\n    func test|\Z)",
        theme_tests,
        re.DOTALL,
    )
    watch_language_test = watch_language_test_match.group(1) if watch_language_test_match else ""
    require("AppSettings(language: AppLanguage.japanese.rawValue, selectedHomeProfileID: home.id)" in watch_language_test
            and "XCTAssertEqual(catalog.displayLanguage, .japanese)" in watch_language_test,
            "Watch catalog integration test must set and verify the selected Japanese language")
    require("struct FactoryToolsBackup: Codable, Equatable" in app_settings_service
            and "schemaVersion: 4" in app_settings_service
            and "CounterCommand.isWellFormedPayloadSignature($0)" in app_settings_service
            and "CounterCommand.payloadSignature(" in app_settings_service
            and "reversesEventID: event.reversesEventID" in app_settings_service
            and "FetchDescriptor<HomeProfile>()" in app_settings_service
            and "FetchDescriptor<ToolCard>()" in app_settings_service
            and "FetchDescriptor<ProductionSession>()" in app_settings_service
            and "FetchDescriptor<CountEvent>()" in app_settings_service
            and "FetchDescriptor<CounterCommandReceipt>()" in app_settings_service
            and "FetchDescriptor<CycleTimeSample>()" in app_settings_service
            and "FetchDescriptor<OEERun>()" in app_settings_service
            and "commandReceipts: commandReceipts.map(FactoryToolsBackup.CommandReceipt.init)" in app_settings_service
            and "decodeIfPresent([CommandReceipt].self, forKey: .commandReceipts) ?? []" in app_settings_service
            and "decodeIfPresent([OEERecord].self, forKey: .oeeRuns) ?? []" in app_settings_service
            and "FetchDescriptor<AppSettings>()" in app_settings_service
            and "encoder.outputFormatting = [.prettyPrinted, .sortedKeys]" in app_settings_service
            and "static func validateRecordCounts(_ counts: [Int], maximumRecordCount: Int) throws" in app_settings_service
            and "func testBackupRecordCountPreflightUsesOverflowSafeTotals()" in theme_tests
            and "func makeJSON(exportedAt: Date = .now) throws -> Data" in app_settings_service,
            "local backup must deterministically export every persisted model with a versioned JSON schema")
    backup_export_match = re.search(
        r"func makeJSON\(exportedAt: Date = \.now\) throws -> Data \{(.*?)(?=\n    \})",
        app_settings_service,
        re.DOTALL,
    )
    backup_export_body = backup_export_match.group(1) if backup_export_match else ""
    first_model_fetch = backup_export_body.find("modelContext.fetch(")
    last_model_count = backup_export_body.rfind("modelContext.fetchCount(")
    require(last_model_count >= 0 and first_model_fetch > last_model_count
            and "Self.validateRecordCounts(" in backup_export_body
            and all(f"fetchCount(FetchDescriptor<{model}>())" in backup_export_body for model in (
                "HomeProfile", "ToolCard", "ProductionSession", "CountEvent",
                "CounterCommandReceipt", "CycleTimeSample", "OEERun", "AppSettings"
            )),
            "backup export must enforce its aggregate record limit before materializing any persisted model arrays")
    require("FactoryToolsBackupService(modelContext: modelContext).makeJSON()" in settings_view
            and "struct FactoryToolsBackupFile: Transferable" in settings_view
            and "DataRepresentation(exportedContentType: .json)" in settings_view
            and "ShareLink(item: file" in settings_view
            and "settings.backup.errorMessage" in settings_view
            and {"settings.backup", "settings.backup.prepare", "settings.backup.description", "settings.backup.ready",
                 "settings.backup.share", "settings.backup.preview", "settings.backup.error", "settings.backup.errorMessage",
                 "settings.backup.chooseImport", "settings.backup.importPreview.title", "settings.backup.addCopy",
                 "settings.backup.importComplete", "settings.backup.importPreview.message", "settings.backup.preferencesKept",
                 "settings.backup.importedHomeSuffix", "settings.backup.homes", "settings.backup.cards",
                 "settings.backup.sessions", "settings.backup.events", "settings.backup.commandReceipts", "settings.backup.samples", "settings.backup.oeeRuns",
                 "settings.backup.invalidFileMessage", "settings.backup.tooLarge", "settings.backup.importErrorMessage",
                 "settings.backup.exportedAt", "settings.backup.homeNames", "settings.backup.reimportNotice",
                 "settings.backup.oeeRuns", "oee.historyExport", "oee.historyExportPreview"}.issubset(strings),
            "settings must offer a localized local JSON backup through the system share sheet")
    require('Section("settings.privacy")' in settings_view
            and 'Text("settings.privacy.localStorageDescription")' in settings_view
            and 'Text("settings.privacy.sharingDescription")' in settings_view
            and "private struct PrivacyDetailsView: View" in settings_view
            and "PrivacyDetailsView(policyURL: privacyPolicyURL)" in settings_view
            and 'object(forInfoDictionaryKey: "FactoryToolsPrivacyPolicyURL")' in settings_view
            and "components.scheme?.lowercased() == \"https\"" in settings_view
            and "components.user == nil" in settings_view
            and 'Link(destination: policyURL)' in settings_view
            and all(key in settings_view for key in (
                "settings.privacy.details.local.title", "settings.privacy.details.local.body",
                "settings.privacy.details.devices.title", "settings.privacy.details.devices.body",
                "settings.privacy.details.export.title", "settings.privacy.details.export.body",
                "settings.privacy.details.delete.title", "settings.privacy.details.delete.body",
            ))
            and {"settings.privacy", "settings.privacy.localStorage", "settings.privacy.localStorageDescription",
                 "settings.privacy.sharingDescription", "settings.privacy.details",
                 "settings.privacy.details.local.title", "settings.privacy.details.local.body",
                 "settings.privacy.details.devices.title", "settings.privacy.details.devices.body",
                 "settings.privacy.details.export.title", "settings.privacy.details.export.body",
                 "settings.privacy.details.delete.title", "settings.privacy.details.delete.body",
                 "settings.privacy.policyLink", "settings.privacy.policyNotConfigured"}.issubset(strings),
            "settings must provide bilingual privacy details and a validated public-policy link")
    local_privacy_details = strings.get("settings.privacy.details.local.body", {}).get("localizations", {})
    device_privacy_details = strings.get("settings.privacy.details.devices.body", {}).get("localizations", {})
    local_privacy_en = local_privacy_details.get("en", {}).get("stringUnit", {}).get("value", "")
    local_privacy_ja = local_privacy_details.get("ja", {}).get("stringUnit", {}).get("value", "")
    local_summary = strings.get("settings.privacy.localStorageDescription", {}).get("localizations", {})
    deletion_privacy = strings.get("settings.privacy.details.delete.body", {}).get("localizations", {})
    require("Apple may include app data in iPhone or iPad backups" in local_privacy_en
            and "Apple Watch backups are included" in local_privacy_en
            and "Appleのバックアップにアプリデータが含まれる場合があります" in local_privacy_ja
            and "Apple Watchのバックアップは" in local_privacy_ja
            and "device backups" in local_summary.get("en", {}).get("stringUnit", {}).get("value", "")
            and "端末バックアップ" in local_summary.get("ja", {}).get("stringUnit", {}).get("value", "")
            and "Existing Apple device backups may retain earlier copies" in deletion_privacy.get("en", {}).get("stringUnit", {}).get("value", "")
            and "Appleの既存バックアップには" in deletion_privacy.get("ja", {}).get("stringUnit", {}).get("value", "")
            and "Apple Watch also stores active Cycle Time timer state" in local_privacy_en
            and "Apple Watchは計測中のサイクルタイム状態" in local_privacy_ja
            and "Apple Watch also sends Cycle Time samples directly to iPhone" in device_privacy_details.get("en", {}).get("stringUnit", {}).get("value", "")
            and "Apple Watchからはサイクルタイム記録もiPhoneへ直接送信" in device_privacy_details.get("ja", {}).get("stringUnit", {}).get("value", "")
            and "While Pro is active, the iPhone sends the home name, production count, and target" in device_privacy_details.get("en", {}).get("stringUnit", {}).get("value", "")
            and "Pro利用中は、Watch表示を有効にした生産進捗カードのホーム名・生産数・目標数も" in device_privacy_details.get("ja", {}).get("stringUnit", {}).get("value", ""),
            "in-app privacy details must disclose Watch transfers and Apple-managed device backup behavior in Japanese and English")
    require('Section("settings.support")' in settings_view
            and 'object(forInfoDictionaryKey: "FactoryToolsSupportURL")' in settings_view
            and 'Link(destination: supportURL)' in settings_view
            and {"settings.support", "settings.support.contact", "settings.support.notConfigured"}.issubset(strings),
            "settings must provide a localized user-support link when configured")
    require("static func decodeAndValidate(" in app_settings_service
            and "static func readAndValidate(" in app_settings_service
            and "maximumBackupSizeInBytes = 64 * 1024 * 1024" in app_settings_service
            and "maximumBackupRecordCount = 500_000" in app_settings_service
            and "defer { file.closeFile() }" in app_settings_service
            and "file.read(upToCount: readLimit)" in app_settings_service
            and "addingReportingOverflow(count)" in app_settings_service
            and "validateBackupByteCount(data.count, maximumSizeInBytes: maximumSizeInBytes)" in app_settings_service
            and "byteCount <= maximumSizeInBytes" in app_settings_service
            and "validateBackupByteCount(data.count, maximumSizeInBytes: Self.maximumBackupSizeInBytes)" in app_settings_service
            and "case backupTooLarge" in app_settings_service
            and "(1...4).contains(backup.schemaVersion)" in app_settings_service
            and "backup.oeeRuns.allSatisfy" in app_settings_service
            and "backup.commandReceipts.allSatisfy" in app_settings_service
            and "let sessionPolicy = ToolRegistry.definition(for: toolID)?.sessionPolicy" in app_settings_service
            and "sessionPolicy.sessionToolID == toolID" in app_settings_service
            and "backup.homes.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })" in app_settings_service
            and "ToolRegistry.definition(for: toolID)?.supportedCardSizes.contains(size) == true" in app_settings_service
            and "guard let kindRawValue = event.kindRawValue" in app_settings_service
            and "case .increment: event.delta == 1 && event.reversesEventID == nil" in app_settings_service
            and "case .decrement: event.delta == -1 && event.reversesEventID == nil" in app_settings_service
            and "case .quickAdd: event.delta > 0 && event.reversesEventID == nil" in app_settings_service
            and "case .reset: event.delta < 0 && event.reversesEventID == nil" in app_settings_service
            and "case .undo: event.reversesEventID != nil" in app_settings_service
            and "let orderedSourceHomes = backup.homes.sorted" in app_settings_service
            and "let sourceCards = backup.cards" in app_settings_service
            and "importedCard.sortOrder = sortOrder" in app_settings_service
            and "importedCommandReceipts.forEach(modelContext.insert)" in app_settings_service
            and "commandReceipts: importedCommandReceipts.count" in app_settings_service
            and "importedOEERuns.forEach(modelContext.insert)" in app_settings_service
            and "oeeRuns: importedOEERuns.count" in app_settings_service
            and "case duplicateIdentifier" in app_settings_service
            and "case invalidRelationship" in app_settings_service
            and "case duplicateSequence" in app_settings_service
            and "addingReportingOverflow(event.delta)" in app_settings_service
            and "func testBackupFileReaderRejectsOversizedFilesBeforeJSONDecoding() throws" in migration_tests
            and 'invalidSessionToolRecords[0]["toolID"] = ToolID.cycleTime.rawValue' in migration_tests
            and 'unknownSessionToolRecords[0]["toolID"] = "unknown.tool"' in migration_tests
            and "maximumRecordCount: recordCount" in migration_tests
            and "maximumRecordCount: recordCount - 1" in migration_tests
            and "event.delta != -runningCount" in app_settings_service
            and "undoableEventIDs.last == reversedID" in app_settings_service
            and "initialCount >= 0" in app_settings_service
            and "setting.selectedHomeProfileID.map(homeIDs.contains) ?? true" in app_settings_service
            and "struct FactoryToolsBackupImportService" in app_settings_service
            and "func addCopy(" in app_settings_service
            and "defaultHomeName: String" in app_settings_service
            and "value.usesDefaultName ? defaultHomeName : value.name" in app_settings_service
            and 'defaultHomeName: localized("home.defaultName")' in settings_view
            and "HomeProfileOrdering.assignSortOrders(isPro ? homeOrder + importedHomes : importedHomes + homeOrder)" in app_settings_service
            and "modelContext.rollback()" in app_settings_service
            and "modelContext.delete" not in app_settings_service.split("struct FactoryToolsBackupImportService", 1)[1],
            "backup import must validate references, add a separate ID-remapped copy, and roll back failed saves without deleting existing records")
    require("if (3...4).contains(schemaVersion)" in app_settings_service
            and "values.decode([CommandReceipt].self, forKey: .commandReceipts)" in app_settings_service
            and "if (2...4).contains(schemaVersion)" in app_settings_service
            and "values.decode([OEERecord].self, forKey: .oeeRuns)" in app_settings_service
            and "incompleteV2.removeValue(forKey: \"oeeRuns\")" in migration_tests
            and "incompleteV3.removeValue(forKey: \"commandReceipts\")" in migration_tests
            and 'version3Object["schemaVersion"] = 3' in migration_tests
            and "upgradedLegacyBackup.schemaVersion, 4" in migration_tests
            and "v2Import.oeeRuns, 1" in migration_tests
            and "upgradedV2Backup.schemaVersion, 4" in migration_tests
            and "upgradedV2Backup.oeeRuns.count, 2" in migration_tests,
            "backup schema versions must enforce required fields and import Version 2 OEE history into a current Version 4 export")
    require("payloadSignature: command.payloadSignature" in service
            and "payloadSignature: value.payloadSignature" in app_settings_service
            and "importedEvents.map(\\.payloadSignature), sourceEvents.map(\\.payloadSignature)" in migration_tests
            and "importedReceipt.payloadSignature, sourceNoChangeReceipt.payloadSignature" in migration_tests
            and "testLegacyCounterRecordsWithoutSignaturesRetainReplayCompatibility" in migration_tests,
            "command payload signatures must persist in both event and no-op receipt rows, survive ID-remapped import, and preserve unsigned legacy replay behavior")
    require("func isWellFormedPayloadSignature(_ signature: String) -> Bool" in counter_command
            and "guard signature.count <= 512 else { return false }" in counter_command
            and "UInt64(dateValue, radix: 16)" in counter_command
            and "testCounterCommandPayloadSignatureIsCanonicalAndRejectsMalformedValues" in migration_tests
            and "testCounterServiceRejectsIDPresentInBothEventAndReceipt" in migration_tests
            and "testBackupRejectsMalformedCommandSignaturesAndCrossTypeIDReuse" in migration_tests,
            "command fingerprints must validate canonical operation/date fields and reject cross-record-type ID reuse")
    require("static func payloadSignature(" in counter_command
            and "occurredAt.timeIntervalSince1970.bitPattern == dateBits" in counter_command
            and "eventKindRawValue == CounterEventKind.quickAdd.rawValue" in counter_command
            and "mismatchedEvents[0][\"delta\"] = 2" in migration_tests,
            "backup event payloads must agree with the operation, timestamp, delta, and Undo target represented by their signature")
    version_one_upgrade_test = re.search(
        r"func testVersionOneBackupRestoresLegacyCounterSessionAssignment\(\) throws \{(.*?)(?=\n    func test|\Z)",
        migration_tests,
        re.DOTALL,
    )
    version_one_upgrade_body = version_one_upgrade_test.group(1) if version_one_upgrade_test else ""
    require("upgradedBackup.schemaVersion, 4" in version_one_upgrade_body
            and "upgradedSession.homeProfileID, importedHome.id" in version_one_upgrade_body
            and "upgradedSession.toolID, ToolID.productionCounter.rawValue" in version_one_upgrade_body,
            "Version 1 legacy counter import must be re-exportable as Version 4 with inferred session ownership")
    require("fileImporter(" in settings_view
            and "allowedContentTypes: [.json]" in settings_view
            and "showingImportPreview" in settings_view
            and "settings.backup.addCopy" in settings_view
            and "FactoryToolsBackupImportService(modelContext: modelContext).addCopy" in settings_view
            and "settings.backup.preferencesKept" in settings_view
            and "settings.backup.exportedAt" in settings_view
            and "settings.backup.homeNames" in settings_view
            and 'home.usesDefaultName ? localized("home.defaultName") : home.name' in settings_view
            and "settings.backup.reimportNotice" in settings_view,
            "backup import must preview contents, warn about repeat imports, and keep current app preferences")
    file_import_handler = re.search(
        r"private func handleBackupFileSelection\(_ result: Result<\[URL\], Error>\) \{(.*?)(?=\n    private func |\Z)",
        settings_view,
        re.DOTALL,
    )
    file_import_handler_body = file_import_handler.group(1) if file_import_handler else ""
    require("startAccessingSecurityScopedResource()" in file_import_handler_body
            and "stopAccessingSecurityScopedResource()" in file_import_handler_body
            and "defer" in file_import_handler_body
            and "FactoryToolsBackupService.readAndValidate(from: url)" in file_import_handler_body
            and '"settings.backup.tooLarge"' in settings_view
            and '"settings.backup.invalidFileMessage"' in file_import_handler_body
            and "func testOversizedBackupMessageIsLocalizedInJapaneseAndEnglish()" in migration_tests
            and "if (error as? CocoaError)?.code == .userCancelled { return }" in file_import_handler_body,
            "backup file input must validate inside a scoped-access lifetime, show localized errors, and ignore user cancellation")
    unknown_event_kind_test = re.search(
        r"func testBackupValidationRejectsMismatchedEventKindAndPreservesUnknownKinds\(\) throws \{(.*?)(?=\n    func test|\Z)",
        migration_tests,
        re.DOTALL,
    )
    unknown_event_kind_body = unknown_event_kind_test.group(1) if unknown_event_kind_test else ""
    require('events[0]["kindRawValue"] = "futureCounterAction"' in unknown_event_kind_body
            and 'XCTAssertEqual(importedEvents.first?.kindRawValue, "futureCounterAction")' in unknown_event_kind_body
            and "FactoryToolsBackupService(modelContext: importedContext).makeJSON()" in unknown_event_kind_body
            and 'XCTAssertEqual(reexportedBackup.events.first?.kindRawValue, "futureCounterAction")' in unknown_event_kind_body,
            "unknown future counter event kinds must survive backup validation, additive import, and re-export")
    require('theme.id.rawValue, "industrial.dark"' in theme_tests,
            "the persisted Industrial Dark ID must remain language-independent and stable")
    require("AppSettingsService(modelContext: modelContext).setLanguage($0, for: settings)" in settings_view,
            "settings UI must route language changes through AppSettingsService")
    require("HomeProfileService(modelContext: modelContext).setName(" in settings_view
            and "isPro: proPurchases.hasPro" in settings_view
            and "func setName(_ draft: String, for home: HomeProfile, isPro: Bool = false) throws" in home_tool_service
            and "HomeNameResolution.resolve(draft)" in home_tool_service
            and "home.name = previousName" in home_tool_service
            and "home.usesDefaultName = previouslyUsedDefaultName" in home_tool_service,
            "home-name editing must persist through HomeProfileService and restore the localized-default state")
    home_view = (ROOT / "FactoryTools" / "Features" / "Home" / "HomeView.swift").read_text(encoding="utf-8")
    create_home_view = (ROOT / "FactoryTools" / "Features" / "Home" / "CreateHomeView.swift").read_text(encoding="utf-8")
    manage_homes_view = (ROOT / "FactoryTools" / "Features" / "Home" / "ManageHomesView.swift").read_text(encoding="utf-8")
    rename_home_view = (ROOT / "FactoryTools" / "Features" / "Home" / "RenameHomeView.swift").read_text(encoding="utf-8")
    require("HomeProfileAccess.canAccess(" in home_view
            and ".selectHome(\n" in home_view
            and "isPro: proPurchases.hasPro" in home_view
            and "HomeProfileService(modelContext: modelContext).createHome(" in create_home_view
            and "isPro: proPurchases.hasPro" in create_home_view
            and "func createHome(named draft: String, isPro: Bool = false)" in home_tool_service
            and "FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: isPro)" in home_tool_service
            and 'case createHome' in home_view,
            "the home menu and persistence service must enforce the Free/Pro home-creation boundary")
    require("HomeProfileAccess.canAccess(home.id, in: homes, isPro: proPurchases.hasPro)" in manage_homes_view
            and "HomeProfileService(modelContext: modelContext).move(" in manage_homes_view
            and "isPro: proPurchases.hasPro" in manage_homes_view
            and "HomeProfileService(modelContext: modelContext).selectHome(home.id, isPro: proPurchases.hasPro)" in manage_homes_view
            and "HomeProfileService(modelContext: modelContext).deleteHome(home.id)" in manage_homes_view
            and "RenameHomeView(home: home, isPro: proPurchases.hasPro)" in manage_homes_view
            and "showingDeleteConfirmation" in manage_homes_view
            and "orderedHomes.count <= 1" in manage_homes_view
            and "HomeProfileService(modelContext: modelContext).setName(nameDraft, for: home, isPro: isPro)" in rename_home_view
            and 'case manageHomes' in home_view,
            "home management must support selecting, renaming, deleting, and persistently reordering profiles")
    require('home.renameNamed \\(displayName(for: home))' in manage_homes_view
            and 'home.moveEarlierNamed \\(displayName(for: home))' in manage_homes_view
            and 'home.moveLaterNamed \\(displayName(for: home))' in manage_homes_view
            and 'home.deleteNamed \\(displayName(for: home))' in manage_homes_view
            and manage_homes_view.count(".frame(width: 44, height: 44)") >= 4
            and ".frame(width: 36, height: 44)" not in manage_homes_view
            and 'home.usesDefaultName ? String(localized: "home.defaultName", locale: locale) : home.name' in manage_homes_view
            and {"home.renameNamed %@", "home.moveEarlierNamed %@", "home.moveLaterNamed %@", "home.deleteNamed %@"}.issubset(strings),
            "home-management accessibility actions must identify the named home in both locales")
    require("func deleteHome(_ homeID: UUID) throws" in home_tool_service
            and "guard homes.count > 1 else { throw HomeProfileServiceError.lastHome }" in home_tool_service
            and "sessionIDs.contains($0.sessionID)" in home_tool_service
            and "modelContext.delete(home)" in home_tool_service
            and "modelContext.rollback()" in home_tool_service
            and {"home.delete", "home.deleteConfirmation.title", "home.deleteConfirmation.message"}.issubset(strings),
            "home deletion must confirm data loss, retain one home, clean home-scoped data, and roll back failures")
    card_view = (ROOT / "FactoryTools" / "Features" / "Home" / "HomeToolCardView.swift").read_text(encoding="utf-8")
    require("_cards = Query(filter: #Predicate<ToolCard> { $0.homeProfileID == selectedHomeID })" in home_view
            and "HomeCardOrdering.ordered(cards.filter { $0.homeProfileID == home.id })" not in home_view,
            "the home screen must query only cards belonging to its selected profile")
    require("_sessions = Query(filter: #Predicate<ProductionSession> { $0.homeProfileID == selectedHomeID })" in card_view,
            "each home card must query sessions scoped to its own profile")
    require("func createHome(named draft: String, isPro: Bool = false) throws -> HomeProfile" in home_tool_service
            and "func selectHome(_ homeID: UUID, isPro: Bool = false) throws" in home_tool_service
            and "func move(_ homeID: UUID, before destinationID: UUID, isPro: Bool = false) throws -> Bool" in home_tool_service
            and "enum HomeProfileAccess" in home_tool_service
            and "static func canAccess(_ homeID: UUID, in homes: [HomeProfile], isPro: Bool) -> Bool" in home_tool_service
            and "testHomeProfileAccessPreservesAdditionalHomesButLocksThemForFree" in migration_tests
            and "static func assignSortOrders(_ homes: [HomeProfile])" in home_tool_service
            and "primarySettings.selectedHomeProfileID = home.id" in home_tool_service,
            "home-profile service must create, select, and reorder profiles")
    picker = (ROOT / "FactoryTools" / "Features" / "Home" / "ToolPickerView.swift").read_text(encoding="utf-8")
    require("func move(_ cardID: UUID" in home_tool_service
            and "func remove(_ card: ToolCard" in home_tool_service
            and "func setSize(_ size: ToolCardSize" in home_tool_service
            and "definition.supportedCardSizes.contains(size)" in home_tool_service
            and "modelContext.rollback()" in home_tool_service,
            "HomeCardService must enforce registry-supported sizes and restore state after save failures")
    require("homes.contains(where: { $0.id == homeID })" in home_tool_service
            and "homeDescriptor.includePendingChanges = true" in home_tool_service
            and "throw HomeToolServiceError.homeNotFound" in home_tool_service,
            "home-tool service must reject missing home profiles before creating sessions or cards")
    require("HomeToolService(modelContext: modelContext).add(tool, to: home.id, locale: locale, isPro: proPurchases.hasPro)" in picker,
            "tool-picker actions must route through the shared home-tool service")
    require("ToolCategory.allCases" in picker
            and '.searchable(text: $searchText, prompt: Text("tool.searchPrompt"))' in picker
            and "ToolRegistry.matching(searchText, locale: locale)" in picker
            and "ToolRegistry.matching(searchText, category: category, locale: locale)" in picker
            and "ContentUnavailableView(" in picker
            and "ToolCategory: String, Codable, CaseIterable, Identifiable" in (ROOT / "FactoryToolsCore" / "ToolID.swift").read_text(encoding="utf-8")
            and "static func matching(_ query: String" in registry
            and {"tool.category.production", "tool.category.quality", "tool.category.packing",
                 "tool.category.utility", "tool.searchPrompt", "tool.noSearchResults",
                 "tool.noSearchResultsHint"}.issubset(strings),
            "tool picker must group and search by localized names, stable IDs, and localized categories")
    picker_add_method = re.search(r"private func add\(_ tool: ToolDefinition\) \{(.*?)(?=\n    \})", picker, re.DOTALL)
    picker_preset_method = re.search(r"private func applyAssemblyPreset\(\) \{(.*?)(?=\n    \})", picker, re.DOTALL)
    picker_packaging_preset_method = re.search(r"private func applyPackagingPreset\(\) \{(.*?)(?=\n    \})", picker, re.DOTALL)
    require("@Query private var cards: [ToolCard]" in picker
            and "$0.homeProfileID == selectedHomeID" in picker
            and 'Text("tool.alreadyOnHome")' in picker
            and "home.preset.applied" in picker
            and picker_add_method is not None and "dismiss()" not in picker_add_method.group(1)
            and picker_preset_method is not None and "dismiss()" not in picker_preset_method.group(1)
            and picker_packaging_preset_method is not None and "dismiss()" not in picker_packaging_preset_method.group(1),
            "tool picker must stay open for batch edits and reflect the selected home’s current cards")
    require("HomeCardOrdering.ordered(allCards.filter { $0.homeProfileID == homeID })" in home_tool_service
            and "HomeCardOrdering.assignSortOrders(homeCards)" in home_tool_service
            and "sortOrder: homeCards.count" in home_tool_service
            and "first.id.uuidString < second.id.uuidString" in home_tool_service,
            "new cards must append after compacting existing home-card order values")
    require("ToolRegistry.definition(for: id), definition.isAvailable" in home_tool_service
            and "if let sessionPolicy = tool.sessionPolicy" in home_tool_service
            and "sessionPolicy.sessionToolID" in home_tool_service
            and "sessionPolicy.defaultSessionNameKey" in home_tool_service
            and "sessionPolicy.defaultTargetCount" in home_tool_service
            and "ToolRegistry.definition(for: cardToolID)?.sessionPolicy?.sessionToolID" in home_tool_service
            and "ToolSessionAssignment.session(for: homeID, toolID: sessionToolID, in: sessions)" in home_tool_service
            and "showsOnWatch: tool.supportsWatch" in home_tool_service,
            "home-tool additions and session recovery must follow canonical Registry availability, Watch capability, and session policy")
    watch_visibility_tests = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    watch_visibility_test = re.search(
        r"func testHomeToolServiceInitializesWatchVisibilityFromEveryRegistryDefinition\(\) throws \{(.*?)(?=\n    func test|\Z)",
        watch_visibility_tests,
        re.DOTALL,
    )
    watch_visibility_test_body = watch_visibility_test.group(1) if watch_visibility_test else ""
    require("for definition in ToolRegistry.all where definition.isAvailable" in watch_visibility_test_body
            and "card.showsOnWatch, definition.supportsWatch" in watch_visibility_test_body
            and "FactoryToolsBackupService.decodeAndValidate" in watch_visibility_test_body
            and "FactoryToolsBackupImportService(modelContext: importContext).addCopy(" in watch_visibility_test_body
            and watch_visibility_tests.count("orderedCards.map(\\.showsOnWatch)") >= 2,
            "watch-capability coverage must verify every registered tool through normal addition, both presets, and backup restore")
    assembly_preset = (ROOT / "FactoryTools" / "Presets" / "AssemblyPreset.swift").read_text(encoding="utf-8")
    require("AssemblyPreset.toolIDs" in home_tool_service
            and "ToolRegistry.matching" in picker
            and "applyAssemblyPreset()" in picker
            and all(f".{tool}" in assembly_preset for tool in ("productionCounter", "cycleTime", "taktTime", "defectCounter")),
            "Assembly starter preset must use stable tool IDs and be offered from the tool picker")
    require("PackagingPreset.toolIDs" in home_tool_service
            and "applyPackagingPreset()" in picker
            and all(f".{tool}" in assembly_preset for tool in ("productionCounter", "productionProgress", "defectCounter", "boxCalculator", "unitConverter"))
            and ".oee" in assembly_preset.split("struct PackagingPreset", 1)[1]
            and {"home.preset.packaging", "home.preset.packagingDescription"}.issubset(strings),
            "Packaging line starter preset must include OEE and use stable tool IDs and localized picker copy")
    require('String(localized: LocalizedStringResource(sessionPolicy.defaultSessionNameKey, locale: locale))' in home_tool_service
            and '"counter.defaultSessionName"' in (ROOT / "FactoryTools" / "Tools" / "ToolDefinition.swift").read_text(encoding="utf-8"),
            "persisted session names must use the app-selected localization lookup locale")
    require(".filter { $0.homeProfileID == homeID && $0.toolID == toolID.rawValue }" in home_tool_service
            and "first.startedAt < second.startedAt" in home_tool_service
            and "first.id.uuidString < second.id.uuidString" in home_tool_service,
            "tool sessions must be home/tool scoped and selected with stable ordering when duplicates exist")
    require("ToolSessionAssignment.session(for: card, in: sessions)" in card_view,
            "home cards must resolve and validate their production-session association")
    require("id: .productionProgress" in registry
            and "isAvailable: true" in registry.split("id: .productionProgress", 1)[1].split("),", 1)[0]
            and "case .productionProgress:" in tool_id_source,
            "Production Progress must be available as a medium or large card")
    require("progressContent(session: session)" in card_view
            and 'Text("progress.targetNotSet")' in card_view
            and 'Button("progress.setTarget"' in card_view
            and 'Text("progress.targetReached")' in card_view,
            "Production Progress must show shared count/target progress and handle missing and completed targets")
    require("sessionPolicy: .productionCounter" in registry
            and registry.count("sessionPolicy: .productionCounter") == 2
            and "ToolRegistry.definition(for: cardToolID)?.sessionPolicy?.sessionToolID" in home_tool_service,
            "Production Progress cards must share the home's production-counter session")
    require("id: .defectCounter" in registry
            and "isAvailable: true" in registry.split("id: .defectCounter", 1)[1].split("),", 1)[0]
            and "case .productionCounter, .cycleTime, .defectCounter:" in tool_id_source,
            "Defect Counter must be available at every card size")
    require("sessionPolicy: .defectCounter" in registry
            and "case .defectCounter: .defectCounter" in (ROOT / "FactoryToolsCore" / "ToolID.swift").read_text(encoding="utf-8")
            and 'case .defectCounter: "defect.defaultSessionName"' in (ROOT / "FactoryTools" / "Tools" / "ToolDefinition.swift").read_text(encoding="utf-8"),
            "Defect Counter must get its own zero-target session and localized name")
    require("ToolRegistry.definition(for: cardToolID)?.sessionPolicy?.sessionToolID" in home_tool_service
            and "counterContent(session: session, showsTargetSettings: false)" in card_view
            and "if showsTargetSettings" in card_view,
            "Defect Counter must use shared counter operations without production-target controls")
    defect_rate_math = tool_id_source
    require("case defectRate = \"quality.defectRate\"" in defect_rate_math
            and "static func fraction(defectCount: Int, productionCount: Int) -> Double?" in defect_rate_math
            and "guard defectCount >= 0, productionCount > 0 else { return nil }" in defect_rate_math
            and "Double(defectCount) / Double(productionCount)" in defect_rate_math,
            "Defect Rate must use a language-independent ID and reject invalid or zero-production ratios")
    require("id: .defectRate" in registry
            and "ToolCapabilities(supportsWatch: false, supportedCardSizes: [.medium, .large])" in tool_id_source
            and "defectRateContent()" in card_view
            and "ToolSessionAssignment.session(for: card.homeProfileID, toolID: .productionCounter, in: sessions)" in card_view
            and "ToolSessionAssignment.session(for: card.homeProfileID, toolID: .defectCounter, in: sessions)" in card_view
            and 'Label("defectRate.noProduction"' in card_view
            and {"tool.defectRate.title", "defectRate.value", "defectRate.counts", "defectRate.noProduction", "defectRate.needsCounters"}.issubset(strings),
            "Defect Rate must derive from this home's production and defect sessions and handle missing data")
    tool_id_source = (ROOT / "FactoryToolsCore" / "ToolID.swift").read_text(encoding="utf-8")
    stable_id_test_source = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    declared_tool_cases = re.findall(
        r'^\s+case\s+(\w+)\s*=\s*"([^"]+)"',
        tool_id_source.split("enum DefectRateMath", 1)[0],
        re.MULTILINE,
    )
    stable_id_test = re.search(
        r"func testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        stable_id_test_source,
        re.DOTALL,
    )
    stable_id_test_body = stable_id_test.group(1) if stable_id_test else ""
    expected_tool_ids = re.findall(r'^\s+"([^"]+)"\s*,?$', stable_id_test_body, re.MULTILINE)
    registry_source = (ROOT / "FactoryTools" / "Tools" / "ToolRegistry.swift").read_text(encoding="utf-8")
    registry_case_names = re.findall(r'\bid:\s*\.(\w+)', registry_source)
    declared_tool_ids = [raw_value for _, raw_value in declared_tool_cases]
    declared_case_names = [name for name, _ in declared_tool_cases]
    registry_tool_ids = [
        raw_value for case_name in registry_case_names
        for name, raw_value in declared_tool_cases if name == case_name
    ]
    require(bool(declared_tool_ids)
            and declared_tool_ids == expected_tool_ids,
            "stable ToolID test must list every declared language-independent tool ID")
    require(registry_tool_ids == declared_tool_ids
            and len(registry_case_names) == len(declared_case_names),
            "Tool Registry must include every stable ToolID exactly once in its declared order")
    tool_definition_source = (ROOT / "FactoryTools" / "Tools" / "ToolDefinition.swift").read_text(encoding="utf-8")
    core_tool_id_source = (ROOT / "FactoryToolsCore" / "ToolID.swift").read_text(encoding="utf-8")
    route_enum_source = tool_definition_source.split("struct ToolDefinition", 1)[0]
    declared_route_names = re.findall(r"^\s+case\s+(\w+)$", route_enum_source, re.MULTILINE)
    registry_entries = re.findall(r"ToolDefinition\((.*?)(?=\n\s*ToolDefinition\(|\n\s*\])", registry_source, re.DOTALL)
    registry_route_pairs: list[tuple[str, str]] = []
    registry_policy_pairs: list[tuple[str, str]] = []
    for entry in registry_entries:
        tool_match = re.search(r"\bid:\s*\.(\w+)", entry)
        route_match = re.search(r"\bhomeCardRoute:\s*\.(\w+)", entry)
        if tool_match and route_match:
            registry_route_pairs.append((tool_match.group(1), route_match.group(1)))
        policy_match = re.search(r"\bsessionPolicy:\s*\.(\w+)", entry)
        if tool_match and policy_match:
            registry_policy_pairs.append((tool_match.group(1), policy_match.group(1)))
    route_switch_source = card_view.split("switch homeCardRoute", 1)[1].split(".padding(HomeCardPresentation", 1)[0]
    rendered_route_names = re.findall(r"^\s+case\s+\.(\w+):", route_switch_source, re.MULTILINE)
    require(set(tool_name for tool_name, _ in registry_route_pairs) == set(declared_case_names)
            and len(registry_route_pairs) == len(declared_case_names)
            and len(set(route_name for _, route_name in registry_route_pairs)) == len(registry_route_pairs)
            and set(route_name for _, route_name in registry_route_pairs) == set(declared_route_names) - {"comingSoon"}
            and set(rendered_route_names) == set(declared_route_names),
            "every stable ToolID must map to one unique Registry card route and every route must render once")
    require("guard let definition, definition.isAvailable else { return .comingSoon }" in card_view,
            "unavailable tools must not dispatch into active calculator or counter implementations")
    require(dict(registry_policy_pairs) == {
                "productionCounter": "productionCounter",
                "productionProgress": "productionCounter",
                "defectCounter": "defectCounter",
            }
            and len(registry_policy_pairs) == 3
            and "case .productionCounter: .productionCounter" in core_tool_id_source
            and "case .productionCounter: 600" in core_tool_id_source
            and "case .defectCounter: .defectCounter" in core_tool_id_source
            and "case .defectCounter: 0" in core_tool_id_source
            and "case .productionCounter: \"counter.defaultSessionName\"" in tool_definition_source
            and "case .defectCounter: \"defect.defaultSessionName\"" in tool_definition_source,
            "Registry session policies must preserve shared production, dedicated defect, and their default session values")
    registry_test = re.search(
        r"func testRegistryContainsEveryToolOnceWithUniqueIdentifiers\(\) \{(.*?)(?=\n    func test|\Z)",
        stable_id_test_source,
        re.DOTALL,
    )
    registry_test_body = registry_test.group(1) if registry_test else ""
    require("expectedSessionPolicies" in registry_test_body
            and "definition.sessionPolicy, expectedSessionPolicies[definition.id]" in registry_test_body
            and "definition.supportsWatch, definition.id.capabilities.supportsWatch" in registry_test_body
            and "definition.supportedCardSizes, definition.id.capabilities.supportedCardSizes" in registry_test_body
            and "defaultSessionNameKey" in registry_test_body
            and "defaultTargetCount" in registry_test_body,
            "Registry XCTest must verify each tool's session assignment and default session values")
    picker_symbol_function = re.search(
        r"private func symbol\(for id: ToolID\) -> String \{(.*?)(?=\n    \})",
        picker,
        re.DOTALL,
    )
    picker_symbol_case_names = set(re.findall(r"case \.([A-Za-z_]\w*):", picker_symbol_function.group(1))) if picker_symbol_function else set()
    require(picker_symbol_case_names == set(declared_case_names),
            "tool-picker icon mapping must cover every registered tool ID exactly once")
    for route_name in ("cycleTime", "taktTime", "oee", "boxCalculator", "unitConverter"):
        require(re.search(rf"case \.{route_name}:\s*toolAction\(.*?destination: \.{route_name}\)", card_view, re.DOTALL) is not None,
                f"home-card route {route_name} must open its matching calculator sheet")
    for preset_name in ("AssemblyPreset", "PackagingPreset"):
        preset_match = re.search(rf"struct {preset_name}\s*\{{(.*?)(?=\n\}}|\Z)", assembly_preset, re.DOTALL)
        preset_body = preset_match.group(1) if preset_match else ""
        ids_match = re.search(r"toolIDs:\s*\[ToolID\]\s*=\s*\[(.*?)\]", preset_body, re.DOTALL)
        preset_case_names = re.findall(r"\.(\w+)", ids_match.group(1)) if ids_match else []
        require(bool(preset_case_names)
                and len(preset_case_names) == len(set(preset_case_names))
                and set(preset_case_names).issubset(set(declared_case_names)),
                f"{preset_name} must contain unique declared ToolIDs so applying it cannot add duplicate or unknown cards")
    oee_math = (ROOT / "FactoryToolsCore" / "PerUnitTimeMath.swift").read_text(encoding="utf-8")
    oee_view = (ROOT / "FactoryTools" / "Features" / "Tools" / "OEECalculatorView.swift").read_text(encoding="utf-8")
    oee_history_math = (ROOT / "FactoryTools" / "Tools" / "OEEHistoryMath.swift").read_text(encoding="utf-8")
    oee_history_csv = (ROOT / "FactoryTools" / "Tools" / "OEEHistoryCSV.swift").read_text(encoding="utf-8")
    history_date_window = (ROOT / "FactoryTools" / "Tools" / "HistoryDateWindow.swift").read_text(encoding="utf-8")
    cycle_time_csv = (ROOT / "FactoryTools" / "Tools" / "CycleTimeHistoryCSV.swift").read_text(encoding="utf-8")
    cycle_time_history_math = (ROOT / "FactoryTools" / "Tools" / "CycleTimeHistoryMath.swift").read_text(encoding="utf-8")
    cycle_time_view = (ROOT / "FactoryTools" / "Features" / "Tools" / "CycleTimeCalculatorView.swift").read_text(encoding="utf-8")
    require('cycleTime.removeSampleNamed \\(sample.createdAt.formatted(' in cycle_time_view
            and 'oee.removeRunNamed \\(run.createdAt.formatted(' in oee_view
            and "home.renameNamed %@" in strings
            and "cycleTime.removeSampleNamed %@" in strings
            and "oee.removeRunNamed %@" in strings,
            "destructive history actions must expose localized, date-specific VoiceOver names")
    require('case oee = "production.oee"' in tool_id_source
            and "id: .oee" in registry
            and "category: .production" in registry.split("id: .oee", 1)[1].split("),", 1)[0]
            and "case .taktTime, .oee, .defectRate, .boxCalculator:" in tool_id_source
            and "static func calculate(" in oee_math
            and "availability = Double(operatingMinutes) / Double(plannedProductionMinutes)" in oee_math
            and "quality = Double(goodUnits) / Double(totalUnits)" in oee_math
            and "overall = availability * performance * quality" in oee_math
            and "enum OEEHistoryMath" in oee_history_math
            and "for point in points where point.overall.isFinite" in oee_history_math
            and "private static func isNewer(_ first: OEEHistoryPoint, than second: OEEHistoryPoint)" in oee_history_math
            and "let ordered = points" not in oee_history_math
            and "changeFromPrevious" in oee_history_math
            and "enum OEEHistoryPeriod: String, CaseIterable, Identifiable" in oee_history_math
            and "HistoryDateWindow.trailingCalendarDays(days, endingAt: date, calendar: calendar)" in oee_history_math
            and "calendar.dateInterval(of: .day, for: date)" in history_date_window
            and "-> ClosedRange<Date>?" in history_date_window
            and "return start...date" in history_date_window
            and "let laterToday = now.addingTimeInterval(60 * 60)" in migration_tests
            and "let laterToday = OEEHistoryPoint(id: UUID(), createdAt: asOf.addingTimeInterval(60 * 60)" in migration_tests
            and "let visibleHistoryPoints = OEEHistoryMath.points(" in oee_view
            and "within: historyPeriod" in oee_view
            and "Picker(\"oee.historyPeriod\", selection: $historyPeriod)" in oee_view
            and "ForEach(visibleRuns)" in oee_view
            and "if !orderedRuns.isEmpty && !visibleRuns.isEmpty" in oee_view
            and "else if orderedRuns.isEmpty" in oee_view
            and "OEEHistoryMath.summary(from: visibleHistoryPoints)" in oee_view
            and "resultRow(\"oee.average\", value: historySummary.averageOverall)" in oee_view
            and "import Charts" in oee_view
            and "Chart(visibleHistoryPoints)" in oee_view
            and ".chartYScale(domain: 0...max(1, historySummary.bestOverall * 1.1))" in oee_view
            and '.accessibilityLabel("oee.historyChart")' in oee_view
            and "enum OEEHistoryCSV" in oee_history_csv
            and "filter { $0.homeProfileID == homeID }" in oee_history_csv
            and "recorded_at_utc" in oee_history_csv
            and "TimeZone(secondsFromGMT: 0)" in oee_history_csv
            and "run.goodUnits.addingReportingOverflow(run.defectiveUnits)" in oee_history_csv
            and "guard !overflow else { return nil }" in oee_history_csv
            and "struct OEECSVRecord: Sendable" in oee_history_csv
            and "let exportRecords = orderedRuns.map(OEECSVRecord.init)" in oee_view
            and "let orderedRuns = self.orderedRuns" in oee_view
            and "let historySummary = OEEHistoryMath.summary(from: visibleHistoryPoints)" in oee_view
            and "private var visibleRuns" not in oee_view
            and "records = exportRecords" in oee_view
            and "OEEHistoryCSV.make(homeID: homeID, records: records)" in oee_view
            and "OEEHistoryCSV.make(homeID: homeProfileID, runs: orderedRuns)" not in oee_view
            and 'SharePreview(Text("oee.historyExportPreview"))' in oee_view
            and 'toolAction("oee.open", systemImage: "gauge", destination: .oee)' in card_view
            and "OEECalculatorView(homeProfileID: card.homeProfileID)" in card_view
            and all(f'"{key}"' in oee_view for key in ("oee.plannedMinutes", "oee.downtimeMinutes", "oee.idealCycleSeconds", "oee.goodUnits", "oee.defectiveUnits", "oee.saveRun", "oee.savedRuns", "oee.noSavedRuns"))
            and "func saveRun()" in oee_view
            and ".onChange(of: proPurchases.hasPro)" in oee_view
            and "if !hasPro { dismiss() }" in oee_view
            and "catch OEERunServiceError.proRequired" in oee_view
            and "func load(_ run: OEERun)" in oee_view
            and "func delete(_ run: OEERun)" in oee_view
            and 'isPresented: $showingDeleteConfirmation' in oee_view
            and "runPendingDeletion = run" in oee_view
            and 'Text("oee.deleteConfirmation.message")' in oee_view
            and {"tool.oee.title", "oee.open", "oee.availability", "oee.performance", "oee.quality", "oee.overall",
                 "oee.formulaNote", "oee.performanceNote", "oee.invalidInput", "oee.saveRun", "oee.savedRuns",
                 "oee.noSavedRuns", "oee.goodOfTotal", "oee.savedRunLoadHint", "oee.historySummary", "oee.runCount",
                 "oee.latest", "oee.average", "oee.best", "oee.changeFromPrevious", "oee.noPrevious",
                 "oee.historyExport", "oee.historyExportPreview", "oee.historyChart", "oee.chartDate", "oee.historyPeriod",
                 "oee.period.days7", "oee.period.days30", "oee.period.days90", "oee.period.all",
                 "oee.noRunsForPeriod", "oee.deleteConfirmation.title", "oee.deleteConfirmation.message"}.issubset(strings),
            "OEE must be a bilingual Registry-backed calculator with validated production inputs and the standard three-factor formula")
    require("enum CycleTimeHistoryCSV" in cycle_time_csv
            and "filter { $0.homeProfileID == homeID }" in cycle_time_csv
            and "recorded_at_utc" in cycle_time_csv
            and "TimeZone(secondsFromGMT: 0)" in cycle_time_csv
            and "struct CycleTimeCSVRecord: Sendable" in cycle_time_csv
            and "let exportRecords = orderedSamples.map(CycleTimeCSVRecord.init)" in cycle_time_view
            and "let orderedSamples = self.orderedSamples" in cycle_time_view
            and "let historySummary = CycleTimeHistoryMath.summary(from: visibleHistoryPoints)" in cycle_time_view
            and "private var visibleSamples" not in cycle_time_view
            and "records = exportRecords" in cycle_time_view
            and "CycleTimeHistoryCSV.make(homeID: homeID, records: records)" in cycle_time_view
            and "CycleTimeHistoryCSV.make(homeID: homeProfileID, samples: orderedSamples)" not in cycle_time_view
            and 'SharePreview(Text("cycleTime.historyExportPreview"))' in cycle_time_view
            and "enum CycleTimeHistoryMath" in cycle_time_history_math
            and "for point in points where point.secondsPerUnit.isFinite && point.secondsPerUnit > 0" in cycle_time_history_math
            and "private static func isNewer(_ first: CycleTimeHistoryPoint, than second: CycleTimeHistoryPoint)" in cycle_time_history_math
            and "let ordered = points" not in cycle_time_history_math
            and "CycleTimeHistoryMath.summary(from: visibleHistoryPoints)" in cycle_time_view
            and "Picker(\"cycleTime.historyPeriod\", selection: $historyPeriod)" in cycle_time_view
            and "let visibleHistoryPoints = CycleTimeHistoryMath.points(" in cycle_time_view
            and "within: historyPeriod" in cycle_time_view
            and 'isPresented: $showingDeleteConfirmation' in cycle_time_view
            and "samplePendingDeletion = sample" in cycle_time_view
            and 'Text("cycleTime.deleteConfirmation.message")' in cycle_time_view
            and "HistoryDateWindow.trailingCalendarDays(days, endingAt: date, calendar: calendar)" in cycle_time_history_math
            and "Chart(visibleHistoryPoints)" in cycle_time_view
            and ".accessibilityLabel(\"cycleTime.historyChart\")" in cycle_time_view
            and {"cycleTime.historyExport", "cycleTime.historyExportPreview", "cycleTime.historySummary",
                 "cycleTime.sampleCount", "cycleTime.latest", "cycleTime.average", "cycleTime.best",
                 "cycleTime.changeFromPrevious", "cycleTime.noPrevious", "cycleTime.historyChart",
                 "cycleTime.chartDate", "cycleTime.secondsUnit", "cycleTime.historyPeriod",
                 "cycleTime.period.days7", "cycleTime.period.days30", "cycleTime.period.days90",
                 "cycleTime.period.all", "cycleTime.noSamplesForPeriod", "cycleTime.deleteConfirmation.title",
                 "cycleTime.deleteConfirmation.message"}.issubset(strings),
            "Cycle Time history must provide a localized trend summary and deterministic UTC home-scoped CSV")
    cycle_history_section_start = cycle_time_view.find("if !orderedSamples.isEmpty {")
    cycle_history_section_end = cycle_time_view.find("if !orderedSamples.isEmpty && !visibleSamples.isEmpty {", cycle_history_section_start)
    cycle_history_section = (
        cycle_time_view[cycle_history_section_start:cycle_history_section_end]
        if cycle_history_section_start >= 0 and cycle_history_section_end > cycle_history_section_start
        else ""
    )
    cycle_history_gate_index = cycle_history_section.find("if canReviewDetailedHistory {")
    cycle_history_chart_index = cycle_history_section.find("Chart(visibleHistoryPoints)")
    require("FeatureAccessRegistry.allows(.detailedHistoryAnalysis, isPro: proPurchases.hasPro)" in cycle_time_view
            and cycle_history_section.count("if canReviewDetailedHistory {") == 1
            and cycle_history_gate_index >= 0
            and cycle_history_chart_index > cycle_history_gate_index
            and 'Label("pro.description", systemImage: "lock.fill")' in cycle_history_section
            and "ForEach(visibleSamples)" in cycle_time_view
            and "let exportRecords = orderedSamples.map(CycleTimeCSVRecord.init)" in cycle_time_view,
            "Cycle Time period analysis and chart must require Pro while basic saved samples and CSV export remain available")
    counter_tests_source = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    packaging_preset_test = re.search(
        r"func testPackagingPresetAddsToolsInOrderWithSharedProductionSession\(\) throws \{(.*?)(?=\n    func test|\Z)",
        counter_tests_source,
        re.DOTALL,
    )
    require(packaging_preset_test is not None and ".unitConverter, .oee" in packaging_preset_test.group(1),
            "Packaging preset XCTest must lock in the OEE addition")
    require(".defectRate" in assembly_preset
            and "func testDefectRateMathHandlesValidZeroAndOutOfRangeRatios" in counter_tests_source
            and "func testDefectRateIsAvailableForMediumAndLargeCards" in counter_tests_source,
            "Defect Rate must be included in the Packaging preset and covered by focused XCTest source")

    core_test_source = (ROOT / "FactoryToolsCoreTests" / "CoreContractTests.swift").read_text(encoding="utf-8")
    require("import FactoryToolsCore" in core_test_source and "@testable import FactoryToolsCore" not in core_test_source
            and all(forbidden not in core_test_source for forbidden in ("SwiftData", "SwiftUI", "Locale"))
            and "FactoryTools" not in core_test_source.replace("FactoryToolsCore", ""),
            "Core contract tests must use only the public Core module API and XCTest, without the app or persistence layer")
    capabilities_switch_source = tool_id_source.split("public extension ToolID", 1)[1].split("\n}", 1)[0]
    capability_case_names = set(
        name
        for case_group in re.findall(r"case\s+((?:\.\w+(?:,\s*)?)+):", capabilities_switch_source)
        for name in re.findall(r"\.(\w+)", case_group)
    )
    capability_test = re.search(
        r"func testToolCapabilitiesAreDefinedInCoreForEveryStableID\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        core_test_source,
        re.DOTALL,
    )
    capability_test_body = capability_test.group(1) if capability_test else ""
    expected_capability_ids = set(re.findall(r"^\s+\.(\w+): ToolCapabilities", capability_test_body, re.MULTILINE))
    require(capability_case_names == set(declared_case_names)
            and expected_capability_ids == set(declared_case_names)
            and "XCTAssertEqual(toolID.capabilities, expected[toolID])" in capability_test_body
            and "Set(ToolCardSize.allCases)" in capability_test_body,
            "Core must declare and contract-test Watch/card-size capabilities exactly once for every stable ToolID")
    require("var supportsWatch: Bool { id.capabilities.supportsWatch }" in tool_definition_source
            and "var supportedCardSizes: Set<ToolCardSize> { id.capabilities.supportedCardSizes }" in tool_definition_source
            and "supportsWatch:" not in registry_source
            and "supportedCardSizes:" not in registry_source,
            "the app Registry must project cross-platform capabilities from Core rather than redeclare them")
    for test_name in (
        "testToolAndCardIdentifiersRemainStableAndLanguageIndependent",
        "testCounterSessionPoliciesAreStableAndPlatformNeutral",
        "testToolCapabilitiesAreDefinedInCoreForEveryStableID",
        "testCounterCommandCodableRoundTripsEveryOperation",
        "testCounterCommandRejectsUnsupportedSchemaVersion",
        "testCounterCommandAcknowledgementUsesStableVersionedWireValues",
        "testCounterCommandAcknowledgementRejectsUnsupportedSchemaAndUnknownStatus",
        "testWatchCounterCatalogRoundTripsStableSessionAndHomeIDs",
        "testWatchCounterCatalogRejectsDuplicateIDsInvalidValuesAndUnsupportedTools",
        "testWatchCommandResponseMustMatchCommandAndValidSessionSnapshot",
        "testCounterPeerMessagesRoundTripAndRejectMismatchedPayloads",
        "testCounterPeerFramesHandleFragmentationCoalescingAndBounds",
        "testOutboxPreservesFIFOAcrossEncodingAndOnlyAcknowledgesHead",
        "testOutboxSuppressesExactRetriesAndRejectsChangedPayloadForSameID",
        "testOutboxCanDiscardAllCommandsForAnUnavailableSessionAndPreserveOtherFIFOItems",
        "testCounterCommandRetryPolicyUsesBoundedExponentialDelays",
        "testOutboxDecoderRejectsDuplicatePersistedCommandIDs",
        "testOutboxDecoderRejectsMoreThanMaximumPendingCommands",
        "testOutboxFileStoreLoadsMissingFileAndPersistsAcrossFreshInstances",
        "testOutboxFileStoreDoesNotSilentlyReplaceMalformedQueue",
        "testOutboxFileStoreRejectsOversizedFileBeforeDecodingAndLeavesItUntouched",
        "testCounterCommandSignatureIsStableAndMatchesItsEvent",
        "testCounterCommandSignatureValidationRejectsMalformedValues",
        "testPersistedTimestampAcceptsFourDigitYearRangeOnly",
        "testCounterCommandSignatureMatchesEveryKnownEventShape",
        "testProductionProgressClampsAtBothBoundaries",
        "testPerUnitAndCycleTimeMathRejectNonpositiveInputs",
        "testOEECalculationUsesDocumentedFactorsAndRejectsInvalidInputs",
        "testBoxPackingUsesBestSingleOrientationAndRejectsNoFit",
        "testEveryUnitPairRoundTripsWithinItsCategory",
        "testUnitConversionRejectsInvalidValuesAndEnforcesTemperatureFloor",
    ):
        require(f"func {test_name}()" in core_test_source,
                f"standalone Core contract suite is missing {test_name}")
    require('CounterEventKind.allCases.map(\.rawValue), ["increment", "decrement", "quickAdd", "reset", "undo"]' in core_test_source
            and 'wireOperation["kind"] as? String, entry.1' in core_test_source
            and 'wireOperation["amount"] as? Int, 17' in core_test_source,
            "Core tests must lock in stable counter event and versioned command wire identifiers")
    require("-62_135_596_800" in core_test_source
            and "253_402_300_800" in core_test_source
            and "Date(timeIntervalSince1970: .nan)" in core_test_source
            and "count: 486" in core_test_source and "count: 487" in core_test_source
            and "Double.greatestFiniteMagnitude" in core_test_source
            and "Int.max" in core_test_source
            and "Set(UnitCategory.allCases.flatMap(\.units)), Set(MeasurementUnit.allCases)" in core_test_source,
            "Core tests must cover timestamp, conversion, category-completeness, and integer-overflow boundaries")
    tests = "\n".join(path.read_text(encoding="utf-8")
                       for directory in (ROOT / "FactoryToolsTests", ROOT / "FactoryToolsCoreTests")
                       for path in directory.rglob("*.swift"))
    home_grid_test_match = re.search(
        r"func testHomeGridAdaptsColumnCountAndKeepsLargeCardsFullWidth\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    home_grid_test = home_grid_test_match.group(1) if home_grid_test_match else ""
    for evidence, description in (
        ("HomeGridLayout.columnCount(availableWidth: 354, minimumColumnWidth: 160, spacing: 14), 2", "two-column phone layout"),
        ("HomeGridLayout.columnCount(availableWidth: 724, minimumColumnWidth: 160, spacing: 14), 4", "wide-screen layout"),
        ("HomeGridLayout.columnCount(availableWidth: 724, minimumColumnWidth: 280, spacing: 14), 2", "accessibility-size layout"),
        ("availableWidth: .greatestFiniteMagnitude", "large finite layout-width handling"),
        ("availableWidth: .infinity", "infinite layout-width rejection"),
        ("availableWidth: .nan", "NaN layout-width rejection"),
        ("minimumColumnWidth: .leastNonzeroMagnitude", "tiny-column-width saturation"),
        ("HomeGridLayout.rows(for: [], columnCount: 2).isEmpty", "empty home row layout"),
        ("HomeGridLayout.rows(for: [firstSmall, large, medium, lastSmall], columnCount: 2)", "large-card row grouping"),
        ("XCTAssertEqual(rows.map(\\.id), [firstSmall.id, large.id, medium.id])", "stable row identities"),
        ("XCTAssertEqual(rows.map(\\.isFullWidth), [false, true, false])", "full-width large card row"),
        ("HomeGridLayout.rows(for: [firstSmall, medium, large], columnCount: 1)", "single-column card layout"),
        ("HomeGridLayout.rows(for: [firstSmall, medium], columnCount: 0)", "zero-column fallback layout"),
    ):
        require(evidence in home_grid_test, f"home-grid layout test does not verify {description}")
    card_size_test_match = re.search(
        r"func testCardSizePresentationAddsSpaceAndInformationForLargerCards\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    card_size_test = card_size_test_match.group(1) if card_size_test_match else ""
    for evidence, description in (
        ("HomeCardPresentation.minimumHeight(for: .small), 146", "small-card height"),
        ("HomeCardPresentation.minimumHeight(for: .medium), 184", "medium-card height"),
        ("HomeCardPresentation.minimumHeight(for: .large), 232", "large-card height"),
        ("HomeCardPresentation.showsTarget(for: .small), false", "small-card target visibility"),
        ("HomeCardPresentation.showsTarget(for: .medium), true", "medium-card target visibility"),
        ("HomeCardPresentation.showsProgress(for: .large), true", "large-card progress visibility"),
        ("HomeCardPresentation.minimumActionWidth, 44", "minimum counter-action touch width"),
        ("XCTAssertGreaterThanOrEqual(mediumCardContentWidth, minimumCounterActionsWidth)", "counter actions fitting a minimum-width phone card"),
    ):
        require(evidence in card_size_test, f"card-size presentation test does not verify {description}")
    progress_test_match = re.search(
        r"func testProgressFractionIsSafeForZeroAndSaturatedTargets\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    progress_test = progress_test_match.group(1) if progress_test_match else ""
    for evidence, description in (
        ("currentCount: 25, targetCount: 100), 0.25", "normal progress fraction"),
        ("currentCount: 150, targetCount: 100), 1", "progress clamping at target"),
        ("currentCount: 25, targetCount: 0), 0", "zero-target handling"),
        ("currentCount: 25, targetCount: -10), 0", "negative-target handling"),
        ('HomeCardPresentation.formattedProgress(currentCount: 1, targetCount: 600, locale: Locale(identifier: "en_US"))', "localized fractional progress label"),
        ('"0.2%"', "fractional progress rounding for one unit"),
    ):
        require(evidence in progress_test, f"progress calculation test does not verify {description}")
    counter_accessibility_test = re.search(
        r"func testCounterAccessibilityLabelResolvesInJapaneseAndEnglish\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    counter_accessibility_body = counter_accessibility_test.group(1) if counter_accessibility_test else ""
    for evidence, description in (
        ('LocalizedStringResource("counter.progress", locale: AppLanguage.english.locale)', "English progress label"),
        ('LocalizedStringResource("counter.progress", locale: AppLanguage.japanese.locale)', "Japanese progress label"),
        ('"Progress toward target"', "English progress label value"),
        ('"目標への進捗"', "Japanese progress label value"),
    ):
        require(evidence in counter_accessibility_body, f"counter accessibility test does not verify {description}")
    named_home_accessibility_test = re.search(
        r"func testHomeManagementAccessibilityLabelsNameTheTargetInBothLanguages\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    named_home_accessibility_body = named_home_accessibility_test.group(1) if named_home_accessibility_test else ""
    for evidence, description in (
        ('String(localized: "home.renameNamed \\(homeName)", locale: AppLanguage.english.locale)', "English named-home rename label"),
        ('String(localized: "home.renameNamed \\(homeName)", locale: AppLanguage.japanese.locale)', "Japanese named-home rename label"),
        ('"Rename Assembly"', "English home-name interpolation"),
        ('"Assemblyの名前を変更"', "Japanese home-name interpolation"),
        ('String(localized: "home.deleteNamed \\(homeName)", locale: AppLanguage.japanese.locale)', "Japanese named-home delete label"),
        ('"通常生産を削除"', "Japanese localized-default home label"),
    ):
        require(evidence in named_home_accessibility_body, f"named-home accessibility test does not verify {description}")
    tool_guidance_test = re.search(
        r"func testToolFormGuidanceIsLocalizedInJapaneseAndEnglish\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    tool_guidance_body = tool_guidance_test.group(1) if tool_guidance_test else ""
    for key in (
        "cycleTime.invalidInput",
        "taktTime.invalidInput",
        "oee.invalidInput",
        "boxCalculator.enterDimensions",
        "boxCalculator.noFit",
        "unitConverter.invalidInput",
    ):
        require(f'"{key}"' in tool_guidance_body, f"tool-form guidance test does not cover {key}")
    require("AppLanguage.english.locale" in tool_guidance_body
            and "AppLanguage.japanese.locale" in tool_guidance_body
            and "Unexpected English guidance" in tool_guidance_body
            and "Unexpected Japanese guidance" in tool_guidance_body,
            "tool-form guidance test must resolve empty/error feedback in both locales")
    history_accessibility_test = re.search(
        r"func testHistoryDeletionAccessibilityLabelsIdentifyTheRecordInBothLanguages\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    history_accessibility_body = history_accessibility_test.group(1) if history_accessibility_test else ""
    for evidence, description in (
        ('"cycleTime.removeSampleNamed \\(timestamp)"', "Cycle Time date-aware delete label"),
        ('"oee.removeRunNamed \\(timestamp)"', "OEE date-aware delete label"),
        ('"Delete Cycle Time sample from Nov 2, 2026"', "English Cycle Time delete action"),
        ('"Nov 2, 2026のサイクルタイム記録を削除"', "Japanese Cycle Time delete action"),
        ('"Delete OEE result from Nov 2, 2026"', "English OEE delete action"),
        ('"Nov 2, 2026のOEE結果を削除"', "Japanese OEE delete action"),
    ):
        require(evidence in history_accessibility_body, f"history accessibility test does not verify {description}")
    empty_home_test = re.search(
        r"func testEmptyHomeGuidanceIsLocalizedInJapaneseAndEnglish\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    empty_home_body = empty_home_test.group(1) if empty_home_test else ""
    for evidence, description in (
        ('LocalizedStringResource("home.empty.title", locale: AppLanguage.english.locale)', "English empty-home title"),
        ('LocalizedStringResource("home.empty.title", locale: AppLanguage.japanese.locale)', "Japanese empty-home title"),
        ('LocalizedStringResource("home.empty.message", locale: AppLanguage.english.locale)', "English empty-home description"),
        ('LocalizedStringResource("home.empty.message", locale: AppLanguage.japanese.locale)', "Japanese empty-home description"),
    ):
        require(evidence in empty_home_body, f"empty-home localization test does not verify {description}")
    save_error_test = re.search(
        r"func testSaveFailureMessageIsLocalizedInJapaneseAndEnglish\(\)\s*\{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    save_error_body = save_error_test.group(1) if save_error_test else ""
    for evidence, description in (
        ('LocalizedStringResource("error.saveMessage", locale: AppLanguage.english.locale)', "English save-error message"),
        ('LocalizedStringResource("error.saveMessage", locale: AppLanguage.japanese.locale)', "Japanese save-error message"),
        ('"Please try again."', "neutral English save-error guidance"),
        ('"もう一度お試しください。"', "neutral Japanese save-error guidance"),
    ):
        require(evidence in save_error_body, f"save-error localization test does not verify {description}")
    history_delete_test = re.search(
        r"func testHistoryDeleteConfirmationsAreLocalizedInJapaneseAndEnglish\(\) \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    history_delete_body = history_delete_test.group(1) if history_delete_test else ""
    require(all(f'LocalizedStringResource("{key}"' in history_delete_body for key in (
        "cycleTime.deleteConfirmation.title", "cycleTime.deleteConfirmation.message",
        "oee.deleteConfirmation.title", "oee.deleteConfirmation.message"
    )) and history_delete_body.count("AppLanguage.english.locale") >= 4
            and history_delete_body.count("AppLanguage.japanese.locale") >= 4,
            "history deletion confirmation test must cover Cycle Time and OEE text in both languages")
    persistent_match = re.search(
        r"func testPersistentStoreRestoresCustomHomeCardsCounterAndLanguage\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    persistent_test = persistent_match.group(1) if persistent_match else ""
    for evidence, description in (
        ("try cardService.setSize(.medium, for: mediumCard)", "medium card-size service path"),
        ("try cardService.move(firstCard.id, before: counterCard.id, in: home.id)", "card-reorder service path"),
        ("try cardService.remove(removedCard)", "persisted card-removal service path"),
        ("orderedCards.map(\\.size), [.small, .large, .medium]", "persisted S/M/L card sizes"),
        ("orderedCards.map(\\.sortOrder), [0, 1, 2]", "persisted card ordering"),
        ("Set(orderedCards.map(\\.id)), expectedCardIDs", "exact persisted card identities after removal"),
        ('try HomeProfileService(modelContext: context).setName("Assembly Line", for: home)', "persisted custom home-name service path"),
        ('homes.first?.name, "Assembly Line"', "persisted custom home name"),
        ("homes.first?.usesDefaultName, false", "persisted custom-home display mode"),
        ("restoredSession.currentCount, 12", "persisted counter value"),
        ("restoredSession.targetCount, 24", "persisted counter target"),
        ("restoredSession.id, sessionID", "restored production-session identity"),
        ("events.map(\\.sessionID), [sessionID]", "persisted counter-event session association"),
        ("commandReceipts.map(\\.id), [commandReceiptID]", "persisted no-op command receipt identity"),
        ("events.reduce(0) { $0 + $1.delta }, restoredSession.currentCount", "persisted event sum matching display count"),
        ("settings.first?.language, AppLanguage.english.rawValue", "persisted selected language"),
        ("settings.first?.selectedHomeProfileID, selectedHomeID", "persisted nonfirst selected home profile"),
        ("let selectedHome = try HomeProfileService(modelContext: context).createHome(\n                named: \"Quality\",\n                isPro: true\n            )", "persisted second home creation before store reopen"),
        ("restoredSample.homeProfileID, homeID", "persisted home-scoped Cycle Time sample"),
        ("restoredSample.totalSeconds, 180", "persisted Cycle Time total seconds"),
        ("restoredSample.quantity, 12", "persisted Cycle Time quantity"),
        ("restoredSample.secondsPerUnit, 15", "restored Cycle Time result derived from saved inputs"),
        ("try CounterService(modelContext: context).undo(session: restoredSession)", "Undo after reopening the persistent store"),
        ("eventsAfterUndo.map(\\.delta), [12, -12]", "persisted event history supporting post-relaunch Undo"),
        ("eventsAfterUndo.reduce(0) { $0 + $1.delta }, restoredSession.currentCount", "post-relaunch Undo preserving the event-sum invariant"),
    ):
        require(evidence in persistent_test, f"persistent-store test does not verify {description}")
    home_scope_test = re.search(
        r"func testHomeCardServiceReordersOnlyTheSelectedHome\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    home_scope_evidence = home_scope_test.group(1) if home_scope_test else ""
    home_delete_test = re.search(
        r"func testHomeProfileServiceDeletesSelectedHomeDataAndSelectsRemainingHome\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    home_delete_body = home_delete_test.group(1) if home_delete_test else ""
    require("Set([sharedLegacyReceipt.id, preservedReceipt.id])" in home_delete_body,
            "home deletion must remove receipts for deleted sessions while preserving shared-session receipts")
    schema_upgrade_test = re.search(
        r"func testPersistentStoreAddsHistoryAndReceiptModelsWithoutLosingExistingCounterData\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    schema_upgrade_body = schema_upgrade_test.group(1) if schema_upgrade_test else ""
    require("let previousSchema = Schema([" in schema_upgrade_body
            and "let currentSchema = Schema([" in schema_upgrade_body
            and "CounterCommandReceipt.self" in schema_upgrade_body
            and "XCTAssertTrue(try context.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)" in schema_upgrade_body
            and "XCTAssertTrue(try context.fetch(FetchDescriptor<OEERun>()).isEmpty)" in schema_upgrade_body
            and "session.currentCount, 6" in schema_upgrade_body
            and "session.targetCount, 20" in schema_upgrade_body
            and "CycleTimeSampleService(modelContext: context).save" in schema_upgrade_body
            and "OEERunService(modelContext: context).save" in schema_upgrade_body
            and "let reopened = try ModelContainer(for: currentSchema" in schema_upgrade_body
            and "FetchDescriptor<CycleTimeSample>()).count, 1" in schema_upgrade_body
            and "FetchDescriptor<CounterCommandReceipt>()).count, 1" in schema_upgrade_body,
            "adding history and receipt models must preserve existing counter data and retain new records after store reopen")
    require("secondHomeCards.map(\\.sortOrder), [0, 1]" in home_scope_evidence,
            "home-scoped card reorder test must verify the other home keeps its order values")
    require('XCTAssertEqual(AppLanguage.resolve(settings.language).locale.identifier, "en")' in tests,
            "language-setting persistence test must verify the selected locale after saving")
    timestamp_source = (ROOT / "FactoryToolsCore" / "CounterCommand.swift").read_text(encoding="utf-8")
    require("timestamp.isFinite" in timestamp_source
            and "timestamp >= -62_135_596_800" in timestamp_source
            and "timestamp < 253_402_300_800" in timestamp_source,
            "persisted date validation must reject non-finite or non-ISO-year timestamps")
    backup_service_source = (ROOT / "FactoryTools" / "Settings" / "AppSettings.swift").read_text(encoding="utf-8")
    require("try Self.validate(backup)" in backup_service_source
            and "resolvedProductionSessionID: ToolSessionAssignment.session(for: card, in: sessions)?.id" in backup_service_source,
            "backup export must validate the complete snapshot before encoding it")
    stale_link_export_test = re.search(
        r"func testBackupExportResolvesStaleCardSessionLinksAndImportsCopyWithoutMutation\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    stale_link_export_body = stale_link_export_test.group(1) if stale_link_export_test else ""
    require("decodeAndValidate(data)" in stale_link_export_body
            and "backup.cards.first?.productionSessionID, session.id" in stale_link_export_body
            and "FactoryToolsBackupImportService(modelContext: context).addCopy" in stale_link_export_body
            and "importedCard.productionSessionID, importedSession.id" in stale_link_export_body
            and "card.productionSessionID, staleSessionID" in stale_link_export_body,
            "stale-link backup test must verify export and import recovery without mutating the stored card")
    for service_path, date_field in (
        ("Services/CounterService.swift", "command.createdAt"),
        ("Services/CycleTimeSampleService.swift", "createdAt"),
        ("Services/OEERunService.swift", "createdAt"),
    ):
        service_source = (ROOT / "FactoryTools" / service_path).read_text(encoding="utf-8")
        require(f"PersistedTimestamp.isSupported({date_field})" in service_source,
                f"{service_path} must validate timestamps before saving")
    oee_service_source = (ROOT / "FactoryTools" / "Services" / "OEERunService.swift").read_text(encoding="utf-8")
    require("FeatureAccessRegistry.allows(.oeeCalculator, isPro: isPro)" in oee_service_source
            and "throw OEERunServiceError.proRequired" in oee_service_source,
            "OEE persistence must enforce its Pro entitlement at the service boundary")
    for swift_path in (ROOT / "FactoryTools").rglob("*.swift"):
        swift_source = swift_path.read_text(encoding="utf-8")
        if "proPurchases" not in swift_source or swift_path.name == "FactoryToolsApp.swift":
            continue
        require(re.search(
            r"@EnvironmentObject\s+private\s+var\s+proPurchases\s*:\s*ProPurchaseManager",
            swift_source,
        ) is not None, f"{swift_path.relative_to(ROOT)} must inject the shared Pro purchase state")
    oee_free_gate_test = re.search(
        r"func testOEERunServiceRejectsFreeSaveThroughFeatureAccessRegistry\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    oee_free_gate_body = oee_free_gate_test.group(1) if oee_free_gate_test else ""
    require("OEERunServiceError, .proRequired" in oee_free_gate_body
            and "FetchDescriptor<OEERun>()).isEmpty" in oee_free_gate_body,
            "OEE service regression test must verify free saves are rejected without persisting a run")
    backup_date_test = re.search(
        r"func testBackupValidationRejectsTimestampsOutsideISO8601ExportRange\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    backup_date_body = backup_date_test.group(1) if backup_date_test else ""
    for date_field in ("exportedAt", "createdAt", "startedAt", "occurredAt", "processedAt"):
        require(f'("{date_field}"' in backup_date_body or f'("{date_field}",' in backup_date_body,
                f"backup timestamp test must cover {date_field}")
    require("cycleTimeSamples" in backup_date_body
            and "oeeRuns" in backup_date_body
            and "records[0][dateField.field] = 1e300" in backup_date_body
            and "makeJSON(" in backup_date_body
            and ".invalidStoredValue" in backup_date_body,
            "backup timestamp test must reject out-of-range dates for every persisted record type")
    persisted_date_test = re.search(
        r"func testPersistenceServicesRejectUnsupportedTimestampsWithoutWritingRecords\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    persisted_date_body = persisted_date_test.group(1) if persisted_date_test else ""
    for evidence in (
        "Date(timeIntervalSince1970: .infinity)",
        "Date(timeIntervalSince1970: .nan)",
        "error as? CycleTimeSampleServiceError, .invalidTimestamp",
        "error as? OEERunServiceError, .invalidTimestamp",
        "error as? CounterServiceError, .invalidTimestamp",
        "CountEvent>()).isEmpty",
        "CounterCommandReceipt>()).isEmpty",
        "session.currentCount, 0",
        "session.nextEventSequence, 0",
    ):
        require(evidence in persisted_date_body, f"persisted date test does not verify {evidence}")
    for evidence, description in (
        ("XCTAssertEqual(homeSession.currentCount, 0)", "initial production count"),
        ("XCTAssertEqual(homeSession.targetCount, 600)", "default production target"),
        ("XCTAssertEqual(homeSession.nextEventSequence, 0)", "initial count-event sequence"),
    ):
        require(evidence in tests, f"home-tool service test does not verify {description}")
    for test_suite in ("CounterServiceTests", "ToolRegistryTests"):
        require(re.search(rf"@MainActor\s+final class {test_suite}\s*:\s*XCTestCase", tests) is not None,
                f"{test_suite} must run SwiftData-dependent test methods on the main actor")
        suite_match = re.search(
            rf"@MainActor\s+final class {test_suite}\s*:\s*XCTestCase\s*\{{(.*?)(?=\n@MainActor\s+final class |\Z)",
            tests,
            re.DOTALL,
        )
        if suite_match and "makeContainer(" in suite_match.group(1):
            require("private func makeContainer(" in suite_match.group(1),
                    f"{test_suite} must declare its own model-container helper")
            helper_match = re.search(r"private func makeContainer\(.*?\n    \}", suite_match.group(1), re.DOTALL)
            if test_suite == "CounterServiceTests" and helper_match:
                require("CounterCommandReceipt.self" in helper_match.group(0),
                        "counter service test containers must register the receipt model")
    test_case_count = len(re.findall(r"\bfunc\s+test\w+\s*\(", tests))
    require(test_case_count >= 10, f"expected a substantive XCTest suite, found only {test_case_count} test cases")
    roadmap = (ROOT / "FactoryTools" / "ROADMAP.md").read_text(encoding="utf-8")
    platform_boundaries = (ROOT / "FactoryTools" / "PLATFORM_BOUNDARIES.md").read_text(encoding="utf-8")
    product_decisions = (ROOT / "FactoryTools" / "PRODUCT_DECISIONS.md").read_text(encoding="utf-8")
    registered_tool_count = registry.count("ToolDefinition(")
    require(f"{test_case_count} XCTest methods across app and Core targets" in roadmap,
            "the roadmap's XCTest source count must match the current test inventory")
    require("current UI offers refresh recovery" not in platform_boundaries
            and "Continue Watch lifecycle reliability work" not in platform_boundaries,
            "platform roadmap must not list completed Watch lifecycle behavior as outstanding work")
    pro_alignment_checks = {
        "transport scope": "## Version 1 transport scope" in platform_boundaries
            and "queued commands do not expire by time" in platform_boundaries
            and "up to 5,000 pending commands" in platform_boundaries
            and "rejects new actions until acknowledgements free a slot" in platform_boundaries,
        "release gate references": "## Remaining release gates" in roadmap
            and "PRODUCT_DECISIONS.md" in roadmap
            and "PRIVACY_DATA_INVENTORY.md" in roadmap,
        "approved boundary": "approved Version 1 Free/Pro boundary" in roadmap
            and "Production Counter, Cycle Time, Takt Time, Box Calculator, Unit Converter" in product_decisions,
        "boundary approval status": "publisher approved the Version 1 boundary below on 2026-10-31" in product_decisions
            and "Confirmed Version 1 boundary" in product_decisions
            and "Apply this boundary consistently to app copy, store listings, and review screenshots." in product_decisions,
        "tool tiers": registered_tool_count == 9
            and registry.count("accessTier: .free") == 7
            and registry.count("accessTier: .pro") == 2,
        "purchase terms": "JPY ¥980 is the confirmed launch price decision" in product_decisions
            and "one non-consumable Factory Tools Pro item" in product_decisions
            and "the developer could not set a lower share count" in product_decisions
            and family_sharing_decision(product_decisions) == "disabled",
        "price decision scope": "Confirmed base storefront and price: **Japan (JP), JPY ¥980**" in product_decisions
            and "Configure this in App Store Connect after enrollment" in product_decisions
            and DEFAULT_BASE_STOREFRONT_CANDIDATE == "JP"
            and DEFAULT_BASE_STOREFRONT_PRICE_CANDIDATE == "JPY:980",
        "Pro tool assignments": "accessTier: .pro" in registry.split("id: .oee", 1)[1].split("),", 1)[0]
            and "accessTier: .pro" in registry.split("id: .productionProgress", 1)[1].split("),", 1)[0],
        "runtime gates": "FeatureAccessRegistry.allows(definition.accessTier, isPro: proPurchases.hasPro)" in home_card_view
            and "FeatureAccessRegistry.allows(.detailedHistoryAnalysis, isPro: proPurchases.hasPro)" in cycle_time_view,
        "access tests": "testFeatureAccessAssignmentsMatchTheApprovedVersionOneBoundary" in core_contract_tests
            and "testFreePackagingPresetSkipsProToolsButKeepsFreeToolsUsable" in tests,
        "StoreKit setup": "StoreKit purchase/restore flow" in roadmap
            and "FACTORYTOOLS_PRO_PRODUCT_ID" in pbx,
    }
    failed_pro_checks = [name for name, passed in pro_alignment_checks.items() if not passed]
    require(not failed_pro_checks,
            "roadmap and product decisions must align with the implemented one-time Pro entitlement; failed: "
            + ", ".join(failed_pro_checks))
    require("Phase 1 iPhone foundation, Phase 2 iPhone tool expansion, Phase 3 local data portability, Phase 4 Apple Watch, and Phase 5 iPad adaptation" in roadmap,
            "roadmap must identify the complete implementation sequence")
    peer_command_test = re.search(
        r"func testPeerProcessorShowsSelectedHomeButAcceptsQueuedCommandsForOtherValidHomes\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    peer_command_body = peer_command_test.group(1) if peer_command_test else ""
    require("processor.peerCatalog()" in peer_command_body
            and "process(command, allowNonWatchSessions: true, isPro: true)" in peer_command_body
            and "selectedHomeCommand" in peer_command_body
            and "isPro: false).acknowledgement.status,\n            .rejected" in peer_command_body
            and "unlinkedResult.acknowledgement.status, .rejected" in peer_command_body
            and "deletedHomeResult.acknowledgement.status, .rejected" in peer_command_body
            and "alreadyApplied" in peer_command_body,
            "peer command regression coverage must include selected-home visibility, queued old-home delivery, idempotency, and invalid session links")
    bootstrap_seed_test = re.search(
        r"func testBootstrapServiceCreatesHomeAndSettingsOnlyOnce\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    bootstrap_seed_body = bootstrap_seed_test.group(1) if bootstrap_seed_test else ""
    require("XCTAssertTrue(cards.isEmpty)" in bootstrap_seed_body
            and "XCTAssertTrue(sessions.isEmpty)" in bootstrap_seed_body,
            "first-launch bootstrap must leave the home empty until the user adds a tool")
    bootstrap_rollback_source = (ROOT / "FactoryToolsTests" / "CounterServiceTests.swift").read_text(encoding="utf-8")
    bootstrap_rollback_test = re.search(
        r"func testBootstrapRepairSaveFailurePreservesPersistedLegacyState\(\) throws \{(.*?)(?=\n    func test|\Z)",
        bootstrap_rollback_source,
        re.DOTALL,
    )
    bootstrap_rollback_body = bootstrap_rollback_test.group(1) if bootstrap_rollback_test else ""
    require("allowsSave: false" in bootstrap_rollback_body
            and "AppBootstrapService(modelContext: context).seedMissingRecords()" in bootstrap_rollback_body
            and "settingsAfterRollback.selectedHomeProfileID" in bootstrap_rollback_body
            and "sessionAfterRollback.homeProfileID" in bootstrap_rollback_body
            and "let reopened = try ModelContainer" in bootstrap_rollback_body
            and "persistedSession.toolID" in bootstrap_rollback_body,
            "bootstrap save failure must retain saved legacy state after context rollback and store reopen")
    history_rollback_test = re.search(
        r"func testHistorySaveAndDeleteFailuresPreserveFileBackedRecords\(\) throws \{(.*?)(?=\n    func test|\Z)",
        bootstrap_rollback_source,
        re.DOTALL,
    )
    history_rollback_body = history_rollback_test.group(1) if history_rollback_test else ""
    require("let writableConfiguration = ModelConfiguration" in history_rollback_body
            and "let readOnlyConfiguration = ModelConfiguration" in history_rollback_body
            and "sampleService.save" in history_rollback_body
            and "runService.save" in history_rollback_body
            and "sampleService.delete" in history_rollback_body
            and "runService.delete" in history_rollback_body
            and "let reopened = try ModelContainer" in history_rollback_body
            and "FetchDescriptor<OEERun>()).map(\\.id), [runID]" in history_rollback_body,
            "Cycle Time and OEE save/delete failures must preserve file-backed history after reopen")
    counter_rollback_test = re.search(
        r"func testCounterSaveFailuresPreserveFileBackedCountAndCommandHistory\(\) throws \{(.*?)(?=\n    func test|\Z)",
        bootstrap_rollback_source,
        re.DOTALL,
    )
    counter_rollback_body = counter_rollback_test.group(1) if counter_rollback_test else ""
    require("let writableConfiguration = ModelConfiguration" in counter_rollback_body
            and "let readOnlyConfiguration = ModelConfiguration" in counter_rollback_body
            and "counter.increment(session: session)" in counter_rollback_body
            and "counter.quickAdd(0, to: session)" in counter_rollback_body
            and "counter.setTarget(30, for: session)" in counter_rollback_body
            and "AppSettingsService(modelContext: context).setLanguage(.english, for: settings)" in counter_rollback_body
            and "session.currentCount, 2" in counter_rollback_body
            and "session.nextEventSequence, 1" in counter_rollback_body
            and "settings.language, AppLanguage.japanese.rawValue" in counter_rollback_body
            and "let reopened = try ModelContainer" in counter_rollback_body
            and "FetchDescriptor<CounterCommandReceipt>()).isEmpty" in counter_rollback_body,
            "counter event, no-op receipt, target, and language save failures must preserve saved state after reopen")
    backup_import_rollback_test = re.search(
        r"func testBackupImportAddsRemappedCopyAndRollsBackOnSaveFailure\(\) throws \{(.*?)(?=\n    func test|\Z)",
        bootstrap_rollback_source,
        re.DOTALL,
    )
    backup_import_rollback_body = backup_import_rollback_test.group(1) if backup_import_rollback_test else ""
    require("let destinationHomeID = UUID()" in backup_import_rollback_body
            and "allowsSave: false" in backup_import_rollback_body
            and "destinationHomeID" in backup_import_rollback_body
            and "reopenedFailureContainer" in backup_import_rollback_body
            and "destinationSessionID" in backup_import_rollback_body
            and "destinationReceiptID" in backup_import_rollback_body
            and "destinationSampleID" in backup_import_rollback_body
            and "destinationRunID" in backup_import_rollback_body,
            "failed additive backup import must retain every pre-existing file-backed entity after reopen")
    decrement_undo_test = re.search(
        r"func testUndoReversesDecrementByAddingOne\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    decrement_undo_body = decrement_undo_test.group(1) if decrement_undo_test else ""
    for evidence, description in (
        ("session.currentCount, 3", "restored count after Undo reverses decrement"),
        ("events.map(\\.delta), [3, -1, 1]", "inverse event for decrement history"),
        ("events.last?.reversesEventID, decrement.id", "Undo link to the decrement event"),
        ("events.reduce(0) { $0 + $1.delta }, session.currentCount", "event-sum invariant after decrement Undo"),
    ):
        require(evidence in decrement_undo_body, f"decrement Undo test does not verify {description}")
    minimum_delta_undo_test = re.search(
        r"func testUndoRejectsMinimumIntegerDeltaWithoutOverflowOrMutation\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    minimum_delta_undo_body = minimum_delta_undo_test.group(1) if minimum_delta_undo_test else ""
    for evidence, description in (
        ("delta: Int.min", "minimum-integer event setup"),
        (".eventDeltaCannotBeReversed", "overflow-specific Undo rejection"),
        ("session.currentCount, 0", "unchanged count after rejection"),
        ("session.nextEventSequence, 1", "unchanged sequence after rejection"),
        ("events.map(\\.delta), [Int.min]", "unchanged event history after rejection"),
    ):
        require(evidence in minimum_delta_undo_body, f"minimum-delta Undo test does not verify {description}")
    backup_undo_test = re.search(
        r"func testBackupValidationRejectsNegativeIntermediateCountAndMalformedUndo\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    backup_undo_body = backup_undo_test.group(1) if backup_undo_test else ""
    require("let staleUndo" in backup_undo_body
            and "XCTAssertThrowsError" in backup_undo_body
            and "let latestFirstUndo" in backup_undo_body
            and "XCTAssertNoThrow" in backup_undo_body,
            "backup Undo validation tests must cover stale-target rejection and a valid repeated Undo order")
    for evidence, description in (
        ("testResetAppendsZeroingEventAndUndoRestoresPreviousCount", "reversible reset event and Undo test"),
        ("testResetAtZeroDoesNotWriteAnEvent", "empty reset no-op test"),
        ("testCustomQuickAddAmountIsRecordedAndCanBeUndone", "custom Quick Add and Undo test"),
        ("testCounterCommandRoundTripsAndDuplicateDeliveryAppliesOnlyOnce", "serializable idempotent counter-command test"),
        ("testWatchCommandProcessorCatalogAndCommandUseTheCanonicalCounterService", "Watch commands reuse the canonical counter service"),
        ("testWatchCatalogKeepsSelectedLanguageForEmptyHomeState", "Watch empty state preserves the selected app language"),
        ("testWatchCatalogLocalizesGeneratedSessionNamesAfterLanguageChange", "Watch and iPad default session labels follow the selected language"),
        ("testCompanionCatalogsMarkDefaultHomeNamesForLocalTranslation", "Watch and iPad generated home labels use their selected display locale"),
        ("testWatchCatalogTracksSelectedHomeAndVisibilityChangesAfterPersistence", "Watch catalog refresh follows home-selection and visibility persistence"),
        ("testWatchCommandProcessorRejectsHiddenUnsupportedAndDeletedSessions", "Watch commands reject hidden or unsupported sessions"),
        ("testCounterCommandRejectsSessionMismatchAndIdentifierCollision", "counter-command session and identifier integrity test"),
        ("testCounterCommandIgnoresUndoTargetThatIsNoLongerLatest", "stale counter-command Undo conflict test"),
        ("testNoChangeCommandReceiptPreventsReplayAfterCounterStateChanges", "counter no-op command replay protection test"),
        ("testNoChangeCommandReceiptPreventsReplayAfterStoreReopen", "persistent no-op command replay protection test"),
        ("testPersistentStoreAddsHistoryAndReceiptModelsWithoutLosingExistingCounterData", "SwiftData history and receipt schema-upgrade preservation test"),
        ("testFailedNoChangeSaveRemovesUncommittedCommandReceipt", "failed no-op receipt transaction rollback test"),
        ("testPersistenceServicesRejectUnsupportedTimestampsWithoutWritingRecords", "persisted timestamp write rejection test"),
        ("testBackupValidationRejectsTimestampsOutsideISO8601ExportRange", "backup timestamp export-range validation test"),
        ("testBackupValidationRejectsDanglingAndEventCollidingCommandReceipts", "backup command-receipt integrity test"),
        ("testBackupValidationEnforcesRegistrySupportedCardSizes", "backup Registry card-size matrix validation test"),
        ("testBackupValidationRejectsBlankHomeNames", "backup home-name integrity test"),
        ("testBackupValidationRejectsBlankSessionNames", "backup counter-session name integrity test"),
        ("testBackupValidationRejectsMismatchedEventKindAndPreservesUnknownKinds", "backup event-kind consistency and forward-compatibility import test"),
        ("testBackupValidationRejectsResetThatLeavesCountAboveZero", "backup reset-to-zero history integrity test"),
        ("testBackupValidationRejectsNegativeIntermediateCountAndMalformedUndo", "backup Undo order and stale-target validation test"),
        ("testHistoryOrderingUsesSequenceTimestampAndStableID", "deterministic counter history test"),
        ("testLatestUndoableEventMatchesCounterUndoOrder", "Undo availability and event-order test"),
        ("testHistoryCSVUsesStableColumnsAndChronologicalRows", "counter history CSV test"),
        ("testHistoryCSVValueSnapshotMatchesModelCSVOutput", "lazy counter CSV value-snapshot compatibility test"),
        ("testHistoryCSVPreservesAndEscapesUnknownEventKind", "counter history CSV future-kind preservation and escaping test"),
        ("testHistoryCSVExcludesEventsFromOtherSessions", "counter history CSV session-isolation test"),
        ("testHistoryBalancesReconstructEachEventAndRejectOverflow", "counter history running-balance test"),
        ("testRepeatedUndoMovesBackwardWithoutReversingPreviousUndo", "repeated Undo regression test"),
        ("testUndoReversesDecrementByAddingOne", "Undo of a decrement event"),
        ("testUndoRejectsMinimumIntegerDeltaWithoutOverflowOrMutation", "minimum-integer Undo overflow guard"),
        ("testUndoOnlyReadsEventsFromTheSelectedSession", "session-scoped Undo regression test"),
        ("testUndoBreaksDuplicateSequenceTiesByTimestampAndStableID", "sequence-tie Undo ordering test"),
        ("testUndoBreaksEqualTimestampTiesByStableEventID", "event-ID Undo tie-break test"),
        ("testEventSequenceExhaustionLeavesCounterAndHistoryUnchanged", "event-sequence overflow guard test"),
        ("testPersistentStoreRestoresCustomHomeCardsCounterAndLanguage", "persistent-store reopening test"),
        ("testQuickAddSaturatesAtIntegerMaximumWithoutOverflow", "integer-boundary counter test"),
        ("testUndoReversesOnlyTheAppliedPartOfSaturatedQuickAdd", "bounded quick-add undo test"),
        ("testQuickAddIgnoresNonpositiveAmountsAndEmptyUndo", "empty and nonpositive counter test"),
        ("testRegistryContainsEveryToolOnceWithUniqueIdentifiers", "Tool Registry ID uniqueness test"),
        ("testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage", "stable language-independent IDs for every tool"),
        ("testHomeCardOrderingMovesAndNormalizesCardPositions", "home-card reorder test"),
        ("testHomeCardOrderingCompactsGapsBeforeAppending", "home-card append-order normalization test"),
        ("testHomeCardOrderingUsesStableIDWhenSortOrdersTie", "deterministic card-order tie-break test"),
        ("testHomeProfileOrderingUsesStableIDWhenSortOrdersTie", "deterministic home-profile tie-break test"),
        ("testAppLanguageMapsToJapaneseAndEnglishLocales", "language locale mapping test"),
        ("testAppSettingsSelectionUsesStableIDWhenRecordsAreDuplicated", "deterministic duplicate-settings selection test"),
        ("testAppLanguageFallsBackToSystemForMissingOrUnknownPreference", "unknown saved-language fallback test"),
        ("testThemeManagerResolvesIndustrialDarkTypographyAndBorderTokens", "theme-manager design token test"),
        ("testNewSessionStartsWithNonnegativeCountsAndSequence", "nonnegative session initialization test"),
        ("testFailedCountSaveRestoresAggregateEventAndSequence", "failed counter save rollback test"),
        ("testCounterSaveFailuresPreserveFileBackedCountAndCommandHistory", "file-backed counter event, receipt, and target rollback test"),
        ("testFailedResetSaveRestoresCountSequenceAndEventHistory", "failed reset save rollback test"),
        ("testFailedUndoSaveRestoresAggregateSequenceAndHistory", "failed Undo save rollback test"),
        ("testFailedTargetSaveRestoresPreviousTarget", "failed target save rollback test"),
        ("testToolSessionAssignmentIsScopedToHomeAndToolAndReaddUsesSameSession", "home-scoped session recovery and re-add test"),
        ("testCycleTimeUsesTotalSecondsPerProducedUnit", "Cycle Time formula and invalid-input test"),
        ("testCycleTimeMeasurementRoundsToWholeSecondsAndRejectsInvalidTimes", "Cycle Time stopwatch rounding and boundary test"),
        ("testCycleTimeSampleServiceSavesAndDeletesHomeScopedSamples", "home-scoped Cycle Time sample save and delete test"),
        ("testCycleTimeSampleServiceRejectsInvalidValuesAndMissingHomes", "Cycle Time sample input and home validation test"),
        ("testCycleTimeSampleSaveFailureRollsBackInsertedSample", "Cycle Time sample save rollback test"),
        ("testCycleTimeToolIsAvailableWithoutCreatingCounterSession", "Cycle Time registry and independent-card test"),
        ("testTaktTimeUsesNetAvailableSecondsPerCustomerUnit", "Takt Time formula and invalid-input test"),
        ("testTaktTimeToolIsAvailableWithoutCreatingCounterSession", "Takt Time registry and independent-card test"),
        ("testDefectCounterTracksIndependentLocalizedCountWithSharedCounterService", "Defect Counter session isolation and shared-service test"),
        ("testDefectCounterSessionNameUsesJapaneseWithoutChangingStableToolID", "localized Defect Counter session and stable-ID test"),
        ("testBoxCalculatorChecksRotationsAndReturnsBestPackingLayout", "Box Calculator rotation and layout test"),
        ("testBoxCalculatorRejectsInvalidUnfittingAndOverflowingDimensions", "Box Calculator invalid-fit and overflow test"),
        ("testBoxCalculatorToolIsAvailableForMediumAndLargeCardsWithoutCreatingSession", "Box Calculator registry and independent-card test"),
        ("testBoxCalculatorPackingAssumptionIsLocalizedInJapaneseAndEnglish", "Box Calculator bilingual packing-assumption test"),
        ("testUnitConversionConvertsLengthMassVolumeAndTemperature", "Unit Converter formulas for four categories test"),
        ("testEveryUnitPairRoundTripsWithinItsCategory", "full Unit Converter unit-pair round-trip matrix test"),
        ("testUnitConversionRejectsInvalidValuesAndIncompatibleUnits", "Unit Converter invalid-value test"),
        ("testLocalizedNumberParserRespectsLocaleAndRequiresTheWholeInput", "localized number parsing and strict whole-input test"),
        ("testUnitConverterToolIsAvailableForSmallAndMediumCardsWithoutCreatingSession", "Unit Converter registry and independent-card test"),
        ("testUnitConverterCategoryAndUnitNamesAreLocalized", "Unit Converter bilingual category and unit labels test"),
        ("testProductionProgressReusesTheProductionCounterSessionWhenAddedFirst", "Production Progress shared-session creation and reuse test"),
        ("testProductionProgressFindsCounterSessionWhenItsLinkIsMissingOrStale", "Production Progress stale-link recovery test"),
        ("testProductionProgressGuidanceIsLocalizedInJapaneseAndEnglish", "Production Progress bilingual guidance test"),
        ("testToolSessionAssignmentSelectsEarliestMatchingDuplicateDeterministically", "deterministic duplicate-session recovery test"),
        ("testBlankHomeNameReturnsToLocalizedDefaultState", "blank home-name normalization test"),
        ("testDefaultProductionSessionNameUsesSelectedLocale", "localized session-name test"),
        ("testCardSizeLabelsResolveInJapaneseAndEnglish", "bilingual card-size label test"),
        ("testCounterAccessibilityLabelResolvesInJapaneseAndEnglish", "bilingual counter accessibility label test"),
        ("testHomeManagementAccessibilityLabelsNameTheTargetInBothLanguages", "bilingual named-home accessibility actions test"),
        ("testToolFormGuidanceIsLocalizedInJapaneseAndEnglish", "bilingual tool-form validation and empty-guidance test"),
        ("testHistoryDeletionAccessibilityLabelsIdentifyTheRecordInBothLanguages", "bilingual date-aware history deletion label test"),
        ("testEmptyHomeGuidanceIsLocalizedInJapaneseAndEnglish", "bilingual empty-home guidance test"),
        ("testSaveFailureMessageIsLocalizedInJapaneseAndEnglish", "bilingual save-error guidance test"),
        ("testHistoryDeleteConfirmationsAreLocalizedInJapaneseAndEnglish", "bilingual permanent-history deletion confirmation test"),
        ("testInvalidCounterEventMessageIsLocalizedInJapaneseAndEnglish", "bilingual invalid-counter-event guidance test"),
        ("testCounterHistoryCorruptionGuidanceIsLocalizedInJapaneseAndEnglish", "bilingual corrupted-history guidance test"),
        ("testHomeGridAdaptsColumnCountAndKeepsLargeCardsFullWidth", "responsive home-card row layout test"),
        ("testCardSizePresentationAddsSpaceAndInformationForLargerCards", "S/M/L card presentation test"),
        ("testProgressFractionIsSafeForZeroAndSaturatedTargets", "bounded progress calculation test"),
        ("testCardSessionLookupRejectsCrossHomeLinksAndRecoversStaleSessionIDs", "stale and cross-home session lookup test"),
        ("testBootstrapServiceCreatesHomeAndSettingsOnlyOnce", "idempotent initial-data seeding test"),
        ("testBootstrapServiceRepairsMissingSettingsWithoutDuplicatingHome", "partial bootstrap data recovery test"),
        ("testBootstrapServiceRepairsMissingHomeWithoutDuplicatingSettings", "reverse partial bootstrap data recovery test"),
        ("testBootstrapServiceRepairsUnknownSelectedHomeID", "unknown selected-home recovery test"),
        ("testBootstrapServicePreservesValidNonfirstHomeSelection", "valid selected-home preservation test"),
        ("testBootstrapServiceMigratesLegacySessionFromItsCounterCard", "unambiguous legacy counter-session migration test"),
        ("testBootstrapServiceSkipsAmbiguousOrMismatchedLegacySessionAssignments", "ambiguous legacy-session preservation test"),
        ("testBootstrapServiceRollsBackDefaultsWhenInitialSaveFails", "failed bootstrap save rollback test"),
        ("testHistorySaveAndDeleteFailuresPreserveFileBackedRecords", "file-backed Cycle Time and OEE save/delete rollback test"),
        ("testHomeCardServicePersistsSizeReorderAndRemoval", "persistent home-card mutation service test"),
        ("testHomeCardServiceReordersOnlyTheSelectedHome", "home-scoped card reorder test"),
        ("testHomeProfileServicePersistsCustomAndDefaultNames", "custom home-name persistence test"),
        ("testHomeProfileServiceUsesTheCentralFeatureAccessPolicy", "centralized home access policy test"),
        ("testHomeProfileServiceCreatesAndSelectsNamedHome", "named home creation and selection test"),
        ("testHomeProfileServiceRenamesNonselectedHomeWithoutChangingSelectionOrOrder", "independent home rename preservation test"),
        ("testHomeProfileServiceRejectsBlankNewHomeName", "blank home creation validation test"),
        ("testHomeProfileServiceSelectsExistingHomeAndRejectsUnknownID", "home selection and validation test"),
        ("testHomeCardServiceRollsBackWhenSaveFails", "failed home-card save rollback test"),
        ("testHomeCardServiceRejectsSizesNotAllowedByToolRegistry", "registry card-size constraint test"),
        ("testHomeProfileServiceRestoresNameWhenSaveFails", "failed home-name save rollback test"),
        ("testHomeProfileServiceRestoresSelectionWhenSaveFails", "failed home selection rollback test"),
        ("testHomeProfileServiceReordersAndCompactsHomePositions", "persisted home-profile reorder test"),
        ("testHomeProfileServiceRestoresOrderWhenMoveSaveFails", "failed home-profile reorder rollback test"),
        ("testHomeProfileSaveFailuresPreservePersistedSelectionNamesAndOrder", "persistent home create/select/rename/reorder rollback test"),
        ("testHomeProfileServiceDeletesSelectedHomeDataAndSelectsRemainingHome", "selected home deletion and dependent-data cleanup test"),
        ("testHomeProfileServicePreservesSelectionWhenDeletingAnotherHome", "nonselected home deletion selection test"),
        ("testHomeProfileServiceRejectsDeletingLastOrUnknownHome", "last and unknown home deletion protection test"),
        ("testHomeDeleteSaveFailurePreservesPersistedHomesAndRelatedData", "persistent existing-data preservation after failed home deletion test"),
        ("testCardAndPresetSaveFailuresPreservePersistedDataAndRollbackNewRecords", "persistent card and preset rollback test"),
        ("testHomeProfileServiceRollsBackDeleteWhenSaveFails", "failed home deletion rollback test"),
        ("testHomeToolServiceAddsCardsAndReusesOnlyTheMatchingHomeSession", "home-tool add and session-reuse service test"),
        ("testHomeToolServiceUsesJapaneseNameWithoutChangingStableToolID", "Japanese session name and stable tool ID test"),
        ("testAssemblyPresetAddsLocalizedToolsInOrderWithIndependentSessions", "Assembly preset ordering and session test"),
        ("testAssemblyPresetSkipsExistingCardsAndCanBeAppliedRepeatedly", "idempotent Assembly preset test"),
        ("testAssemblyPresetRollsBackAllNewRecordsWhenBatchSaveFails", "failed Assembly preset batch rollback test"),
        ("testPackagingPresetAddsToolsInOrderWithSharedProductionSession", "Packaging preset order and shared-session test"),
        ("testPackagingPresetSkipsExistingCardsAndCanBeAppliedRepeatedly", "idempotent Packaging preset test"),
        ("testPackagingPresetRollsBackAllNewRecordsWhenBatchSaveFails", "failed Packaging preset batch rollback test"),
        ("testHomeToolServiceUsesRegistryAvailabilityAsAuthority", "canonical Registry availability enforcement test"),
        ("testHomeToolServiceInitializesWatchVisibilityFromEveryRegistryDefinition", "Registry-driven Watch card-visibility and backup round-trip test"),
        ("testHomeToolServiceRejectsMissingHomeWithoutWritingData", "missing home rejection test"),
        ("testHomeToolServiceCompactsExistingOrderAndAppendsNewCard", "home-tool service card-order compaction test"),
        ("testHomeToolServiceRollsBackCardAndSessionWhenSaveFails", "failed home-tool add rollback test"),
        ("testAppSettingsServicePersistsLanguageChanges", "language-setting persistence test"),
        ("testAppSettingsServiceRestoresLanguageWhenSaveFails", "language-setting save-failure rollback test"),
        ("testNoOpSettingsChangesDoNotRequireStoreWrites", "no-op settings write avoidance test"),
        ("testBackupIncludesEveryStoredModelAndIsDeterministicWithoutMutation", "deterministic read-only full local backup test"),
        ("testBackupExportResolvesStaleCardSessionLinksAndImportsCopyWithoutMutation", "backup export/import recovery for stale card-session links test"),
        ("testBackupImportAddsRemappedCopyAndRollsBackOnSaveFailure", "additive backup import and save rollback test"),
        ("testRepeatedBackupImportsCreateIndependentCopiesAndKeepCurrentPreferences", "repeated import collision, preference preservation, and copy-isolation test"),
        ("testBackupImportCompactsCardOrderBeforeAppendingNewCards", "imported card-order normalization test"),
        ("testBackupImportPreservesHomeOrderWhenPayloadRecordsAreUnsorted", "imported home-order normalization test"),
        ("testBackupImportLocalizesDefaultHomeNameBeforeMarkingItCustom", "localized imported default-home name test"),
        ("testBackupValidationRejectsUnsupportedVersionAndBrokenReferences", "backup schema and relationship validation test"),
        ("testBackupRejectsCounterSessionLinksAcrossHomesAndTools", "cross-home and cross-tool backup session-link rejection test"),
        ("testBackupValidationRejectsInvalidEventBalancesAndDuplicateSequences", "counter event integrity validation test"),
        ("testOEECalculatorReturnsAvailabilityPerformanceQualityAndOverall", "OEE factor and overall calculation test"),
        ("testOEECalculatorRejectsInvalidInputsAndReportsUncappedPerformance", "OEE input validation and uncapped performance test"),
        ("testOEEToolIsAvailableAsAMediumOrLargeProductionCard", "OEE tool Registry and card-size test"),
        ("testOEERunServiceSavesHomeScopedResults", "home-scoped OEE history save test"),
        ("testOEERunServiceRejectsInvalidInputMissingHomeAndCrossHomeDelete", "OEE history validation and home-isolation test"),
        ("testOEERunServiceRollsBackWhenSaveFails", "OEE history save rollback test"),
        ("testPersistentStoreRestoresOEERunHistory", "persistent OEE history reopen test"),
        ("testOEEHistorySummaryCalculatesLatestAverageBestAndChange", "OEE history summary metric test"),
        ("testOEEHistorySummaryUsesStableIDForTiedTimesAndPreservesOver100Percent", "OEE history deterministic order and uncapped summary test"),
        ("testOEEHistorySummaryReturnsNilWithoutFiniteResults", "OEE history invalid-value filtering test"),
        ("testOEEHistoryCSVIsDeterministicUTCAndHomeScoped", "OEE history CSV determinism, time zone, and home-isolation test"),
        ("testCycleTimeHistoryCSVIsDeterministicUTCAndHomeScoped", "Cycle Time history CSV determinism, time zone, and home-isolation test"),
        ("testCycleTimeHistorySummaryCalculatesLatestAverageBestAndChange", "Cycle Time history summary metrics and tied-time stability test"),
        ("testCycleTimeHistorySummaryIgnoresInvalidAndNonpositiveSamples", "Cycle Time history invalid-value filtering test"),
        ("testCycleTimeHistoryPeriodIncludesCalendarBoundaryAndExcludesFutureSamples", "Cycle Time history period boundary and future-date test"),
        ("testCycleTimeHistoryPeriodUsesCalendarArithmeticAcrossDaylightSavingChange", "Cycle Time history daylight-saving boundary test"),
        ("testToolRegistrySearchUsesLocalizedNamesStableIDsAndCategories", "localized tool search, stable ID, and category test"),
        ("testFactoryToolsJourneySurvivesReopenAndBackupCopy", "end-to-end home, counter, persistence, and backup-copy journey test"),
        ("testImportedHomeLifecycleReopensReexportsAndDeletesOnlyItsOwnData", "file-backed import, reopen, re-export, and scoped deletion lifecycle test"),
        ("testOEEHistoryPeriodIncludesCalendarBoundariesAndExcludesFutureEntries", "OEE period calendar-boundary and future-date test"),
        ("testOEEHistoryPeriodsUseCalendarArithmeticAcrossDaylightSavingChanges", "OEE period daylight-saving boundary test"),
    ):
        require(evidence in tests, f"missing {description}")

    bilingual_tool_search = re.search(
        r"func testToolRegistrySearchUsesLocalizedNamesStableIDsAndCategories\(\) \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    bilingual_tool_search_body = bilingual_tool_search.group(1) if bilingual_tool_search else ""
    require('Locale(identifier: "ja")' in registry and 'Locale(identifier: "en")' in registry
            and "searchLocales.contains" in registry
            and 'matching("production counter", locale: japanese)' in bilingual_tool_search_body
            and 'matching("生産カウンター", locale: english)' in bilingual_tool_search_body
            and 'matching("Quality", locale: japanese)' in bilingual_tool_search_body
            and 'matching("品質", locale: english)' in bilingual_tool_search_body,
            "tool search must match Japanese and English names/categories regardless of the selected display language")
    backup_session_link_test = re.search(
        r"func testBackupRejectsCounterSessionLinksAcrossHomesAndTools\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    backup_session_link_test_body = backup_session_link_test.group(1) if backup_session_link_test else ""
    require(all(evidence in backup_session_link_test_body for evidence in (
                "crossHomeCards[0][\"homeProfileID\"]",
                "crossToolCards[0][\"toolID\"]",
                "ambiguousLegacyLink[\"sessions\"]",
                "ambiguousLegacyLink[\"cards\"]",
                "error as? FactoryToolsBackupError, .invalidRelationship",
            )),
            "backup relationship regression must reject a session linked across homes, tool owners, or ambiguous legacy cards")
    repeated_import_test = re.search(
        r"func testRepeatedBackupImportsCreateIndependentCopiesAndKeepCurrentPreferences\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    repeated_import_test_body = repeated_import_test.group(1) if repeated_import_test else ""
    require(repeated_import_test_body.count("importer.addCopy(from: backup") == 2
            and "Set(sessions.map(\\.id)).count, 3" in repeated_import_test_body
            and "Set(events.map(\\.id)).count, 3" in repeated_import_test_body
            and "settings.language, AppLanguage.japanese.rawValue" in repeated_import_test_body
            and "HomeProfileService(modelContext: context).deleteHome(firstCopy.id)" in repeated_import_test_body
            and "sourceSession.currentCount, 3" in repeated_import_test_body,
            "repeated additive import must remap IDs independently, preserve current preferences, and isolate later home deletion")
    journey_test = re.search(
        r"func testFactoryToolsJourneySurvivesReopenAndBackupCopy\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    journey_test_body = journey_test.group(1) if journey_test else ""
    require(all(evidence in journey_test_body for evidence in (
                "AppBootstrapService(modelContext: context).seedMissingRecords()",
                "defaultHome.usesDefaultName",
                "settings.themeID, ThemeID.industrialDark.rawValue",
                "setLanguage(.japanese, for: settings)",
                "AppLanguage.resolve(settings.language), .japanese",
                "HomeProfileService(modelContext: context)",
                "HomeToolService(modelContext: context)",
                "cardService.setSize(.small",
                "cardService.setSize(.medium",
                "cardService.setSize(.large",
                "cardService.move(thirdCard.id, before: firstCard.id, in: defaultHome.id)",
                "counter.increment(session: primarySession)",
                "counter.quickAdd(5, to: primarySession)",
                "counter.decrement(session: primarySession)",
                "counter.undo(session: primarySession)",
                "primarySession.currentCount, 1",
                "primarySession.currentCount, 6",
                "primarySession.currentCount, 5",
                "AppSettingsService(modelContext: context).setLanguage(.english",
                "AppLanguage.resolve(settings.language), .english",
                "ModelContainer(for: schema, configurations: [configuration])",
                "FactoryToolsBackupService(modelContext: restoredContext).makeJSON()",
                "FactoryToolsBackupImportService(modelContext: importContext).addCopy(",
                "importedPrimarySession.currentCount, 6",
            )),
            "end-to-end journey regression must cover bootstrap, home/card edits, counter Undo, language, store reopen, and backup-copy restore")
    imported_lifecycle_test = re.search(
        r"func testImportedHomeLifecycleReopensReexportsAndDeletesOnlyItsOwnData\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    imported_lifecycle_body = imported_lifecycle_test.group(1) if imported_lifecycle_test else ""
    require(all(evidence in imported_lifecycle_body for evidence in (
                'ModelConfiguration(\n            "ImportedFactoryLifecycle"',
                "FactoryToolsBackupImportService(modelContext: context).addCopy(",
                "FactoryToolsBackupService(modelContext: context).makeJSON()",
                "HomeProfileService(modelContext: context).deleteHome(importedHome.id)",
                "FetchDescriptor<CountEvent>()",
                "FetchDescriptor<CycleTimeSample>()",
                "FetchDescriptor<OEERun>()",
                "let finalContainer = try ModelContainer(for: schema, configurations: [writableConfiguration])",
                "finalSession.currentCount, 7",
                "finalSession.targetCount, 40",
                "finalContext.fetch(FetchDescriptor<CountEvent>())",
                "finalContext.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty",
                "finalContext.fetch(FetchDescriptor<OEERun>()).isEmpty",
            )),
            "backup lifecycle regression must persist, reopen, re-export, delete one imported home, and preserve other-home data")

    failed_home_delete = re.search(
        r"func testHomeDeleteSaveFailurePreservesPersistedHomesAndRelatedData\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    failed_home_delete_body = failed_home_delete.group(1) if failed_home_delete else ""
    require("allowsSave: true" in failed_home_delete_body
            and "allowsSave: false" in failed_home_delete_body
            and "HomeProfileService(modelContext: context).deleteHome(deletedHomeID)" in failed_home_delete_body
            and all(f"FetchDescriptor<{model}>" in failed_home_delete_body for model in (
                "HomeProfile", "ToolCard", "ProductionSession", "CountEvent", "CounterCommandReceipt",
                "CycleTimeSample", "OEERun", "AppSettings"
            )),
            "failed deletion regression must persist a full baseline, reopen read-only, and check every related model survives")
    failed_home_profile = re.search(
        r"func testHomeProfileSaveFailuresPreservePersistedSelectionNamesAndOrder\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    failed_home_profile_body = failed_home_profile.group(1) if failed_home_profile else ""
    require("allowsSave: true" in failed_home_profile_body
            and "allowsSave: false" in failed_home_profile_body
            and all(operation in failed_home_profile_body for operation in (
                "service.createHome", "service.selectHome", "service.setName", "service.move"
            ))
            and 'XCTAssertEqual(restoredHomes.map(\.name), ["Production", "Assembly"])' in failed_home_profile_body
            and "XCTAssertEqual(settings.selectedHomeProfileID, firstHomeID)" in failed_home_profile_body,
            "failed home profile regression must retain persisted records, names, home order, and selection")
    failed_card_preset = re.search(
        r"func testCardAndPresetSaveFailuresPreservePersistedDataAndRollbackNewRecords\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    failed_card_preset_body = failed_card_preset.group(1) if failed_card_preset else ""
    require("allowsSave: true" in failed_card_preset_body
            and "allowsSave: false" in failed_card_preset_body
            and all(operation in failed_card_preset_body for operation in (
                "cardService.setSize", "cardService.move", "cardService.remove", "applyPackagingPreset"
            ))
            and "XCTAssertEqual(restoredCards.map(\.id), [firstCardID, secondCardID])" in failed_card_preset_body
            and "XCTAssertEqual(restoredSession.id, sessionID)" in failed_card_preset_body
            and "XCTAssertEqual(restoredSession.currentCount, 5)" in failed_card_preset_body
            and "XCTAssertEqual(restoredSession.targetCount, 20)" in failed_card_preset_body,
            "failed card and preset regression must retain persisted cards and sessions and omit partial additions")

    oee_boundary = re.search(
        r"func testOEECalculatorRejectsInvalidInputsAndReportsUncappedPerformance\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    parser_boundary = re.search(
        r"func testLocalizedNumberParserRespectsLocaleAndRequiresTheWholeInput\(\) \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    box_guidance_boundary = re.search(
        r"func testBoxCalculatorPackingAssumptionIsLocalizedInJapaneseAndEnglish\(\) \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    unit_conversion_boundary = re.search(
        r"func testUnitConversionRejectsInvalidValuesAndIncompatibleUnits\(\) \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    require(oee_boundary is not None and "plannedProductionMinutes: Int.max" in oee_boundary.group(1)
            and "largeFiniteResult?.overall.isFinite == true" in oee_boundary.group(1),
            "OEE boundary test must check large integer inputs remain finite")
    require(parser_boundary is not None and all(token in parser_boundary.group(1) for token in (
                '"NaN"', '"Infinity"', '"1e999"', 'parseInteger("1,234"',
                'Locale(identifier: "ja_JP")), 1_234)',
                'parseInteger("1.234"', 'parseInteger("1.5"', 'parseInteger("123items"',
                'parseInteger("9,223,372,036,854,775,808"'
            )),
            "localized number parser test must cover locale grouping, fractions, trailing text, and integer overflow")
    require(box_guidance_boundary is not None
            and 'LocalizedStringResource("boxCalculator.enterDimensions", locale: AppLanguage.english.locale)' in box_guidance_boundary.group(1)
            and 'LocalizedStringResource("boxCalculator.enterDimensions", locale: AppLanguage.japanese.locale)' in box_guidance_boundary.group(1),
            "Box Calculator's incomplete-input guidance must be covered in Japanese and English")
    require(unit_conversion_boundary is not None
            and "Double.greatestFiniteMagnitude, from: .celsius, to: .fahrenheit" in unit_conversion_boundary.group(1),
            "unit conversion test must reject a non-finite temperature conversion result")

    remove_and_readd_test = re.search(
        r"func testToolSessionAssignmentIsScopedToHomeAndToolAndReaddUsesSameSession\(\) throws \{(.*?)(?=\n    func test|\Z)",
        tests,
        re.DOTALL,
    )
    remove_and_readd_evidence = remove_and_readd_test.group(1) if remove_and_readd_test else ""
    require("HomeCardService(modelContext: context).remove(counterCard)" in remove_and_readd_evidence
            and "context.delete(counterCard)" not in remove_and_readd_evidence
            and "XCTAssertEqual(restoredSession.currentCount, 14)" in remove_and_readd_evidence
            and "XCTAssertEqual(restoredSession.targetCount, 50)" in remove_and_readd_evidence,
            "remove-and-readd coverage must use HomeCardService and retain the session count and target")

    project_source_names = set(re.findall(r"/\* ([^*]+\.swift) in Sources \*/", pbx))
    actual_source_names = {path.name for path in source_files}
    require(project_source_names == actual_source_names,
            f"Xcode source membership differs (project-only={sorted(project_source_names - actual_source_names)}, "
            f"files-only={sorted(actual_source_names - project_source_names)})")

    build_file_names = dict(re.findall(
        r"([A-F0-9]{24}) /\* ([^*]+\.swift) in Sources \*/ = \{",
        pbx,
    ))

    def source_membership(phase_id: str) -> set[str]:
        phase = re.search(
            rf"^\s*{phase_id} /\* Sources \*/ = \{{.*?files = \((.*?)\);",
            pbx,
            re.MULTILINE | re.DOTALL,
        )
        if not phase:
            return set()
        build_file_ids = re.findall(r"\b[A-F0-9]{24}\b", phase.group(1))
        return {build_file_names[build_file_id] for build_file_id in build_file_ids if build_file_id in build_file_names}

    app_source_names = {path.name for path in (ROOT / "FactoryTools").rglob("*.swift")}
    test_source_names = {path.name for path in (ROOT / "FactoryToolsTests").rglob("*.swift")}
    core_test_source_names = {path.name for path in (ROOT / "FactoryToolsCoreTests").rglob("*.swift")}
    watch_source_names = {path.name for path in (ROOT / "FactoryToolsWatch").rglob("*.swift")}
    core_source_names = {path.name for path in core_sources}
    require(source_membership("D40000000000000000000001") == app_source_names,
            "FactoryTools app target must compile every app Swift file and no test source")
    require(source_membership("D40000000000000000000003") == test_source_names,
            "FactoryToolsTests target must compile every test Swift file and no app source")
    require(source_membership("D40000000000000000000006") == core_test_source_names,
            "FactoryToolsCoreTests target must compile only the standalone Core contract test source")
    require(source_membership("D40000000000000000000008") == watch_source_names,
            "FactoryToolsWatch target must compile every Watch Swift source and no iPhone source")
    require(source_membership("D40000000000000000000005") == core_source_names,
            "FactoryToolsCore target must compile every shared source file independently of the iPhone app")

    resource_build_names = dict(re.findall(
        r"([A-F0-9]{24}) /\* ([^*]+) in Resources \*/ = \{",
        pbx,
    ))

    def resource_membership(phase_id: str) -> set[str]:
        phase = re.search(
            rf"^\s*{phase_id} /\* Resources \*/ = \{{.*?files = \((.*?)\);",
            pbx,
            re.MULTILINE | re.DOTALL,
        )
        if not phase:
            return set()
        build_file_ids = re.findall(r"\b[A-F0-9]{24}\b", phase.group(1))
        return {resource_build_names[build_file_id] for build_file_id in build_file_ids if build_file_id in resource_build_names}

    require(resource_membership("D40000000000000000000002") == {
                "Localizable.xcstrings", "Assets.xcassets", "InfoPlist.strings", "PrivacyInfo.xcprivacy"
            }, "FactoryTools app target must bundle its localized resources and privacy manifest")
    require(resource_membership("D40000000000000000000007") == set(),
            "standalone Core tests must not bundle app resources or localization catalogs")
    require(resource_membership("D40000000000000000000009") == {"Localizable.xcstrings", "Assets.xcassets"},
            "FactoryToolsWatch must bundle its own Japanese/English String Catalog and watchOS AppIcon asset catalog")
    privacy_manifest_path = ROOT / "FactoryTools" / "PrivacyInfo.xcprivacy"
    try:
        privacy_manifest = plistlib.loads(privacy_manifest_path.read_bytes())
    except (OSError, plistlib.InvalidFileException, ValueError):
        privacy_manifest = None
    expected_privacy_manifest = {
        "NSPrivacyAccessedAPITypes": [{
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategorySystemBootTime",
            "NSPrivacyAccessedAPITypeReasons": ["35F9.1"],
        }],
    }
    require(privacy_manifest == expected_privacy_manifest,
            "the app privacy manifest must declare only the ContinuousClock stopwatch's approved SystemBootTime reason")
    privacy_inventory = (ROOT / "FactoryTools" / "PRIVACY_DATA_INVENTORY.md").read_text(encoding="utf-8")
    require("not an App Store Connect submission" in privacy_inventory
            and "no app-operated cloud storage or sync, account, advertising, analytics, tracking, external API, or third-party SDK integration" in privacy_inventory
            and "Apple-managed iCloud or computer backup, when enabled by the device owner" in privacy_inventory
            and "isExcludedFromBackup" in privacy_inventory
            and "iPhone/iPad SwiftData store" in privacy_inventory
            and "iPhone/iPad Keychain" in privacy_inventory
            and "Preserve an active Cycle Time measurement" in privacy_inventory
            and "one-unit Cycle Time samples" in privacy_inventory
            and "WatchConnectivity" in privacy_inventory
            and "local peer connection" in privacy_inventory
            and "35F9.1" in privacy_inventory
            and "App Store Connect privacy questionnaire" in privacy_inventory,
            "privacy inventory must cover local Watch timer state and Cycle Time transfer alongside its data posture, manifest reason, and publisher review gate")
    privacy_review = (ROOT / "FactoryTools" / "APP_STORE_PRIVACY_REVIEW.md").read_text(encoding="utf-8")
    require("one-unit Cycle Time samples" in privacy_review
            and "Provisional answer" in privacy_review
            and "final release binary" in privacy_review
            and "Apple-managed system backup" in privacy_review,
            "App Store privacy review must include Watch Cycle Time and retain the final-binary publisher verification gate")
    age_rating_review = (ROOT / "FactoryTools" / "APP_STORE_AGE_RATING_REVIEW.md").read_text(encoding="utf-8")
    require("Watch can also send Cycle Time captures" in age_rating_review
            and "direct Watch Cycle Time capture" in age_rating_review
            and "final App Store Connect declaration" in age_rating_review,
            "age-rating evidence must describe Watch Cycle Time while retaining publisher attestation as a release gate")
    xcode_cloud_runbook = (ROOT / "FactoryTools" / "XCODE_CLOUD_RUNBOOK.md").read_text(encoding="utf-8")
    require("25 Xcode Cloud compute hours per month" in xcode_cloud_runbook
            and "do not buy an additional Xcode Cloud subscription" in xcode_cloud_runbook
            and "requires Xcode to create the first Xcode Cloud product/workflow" in xcode_cloud_runbook
            and "remote Git repository" in xcode_cloud_runbook
            and "no product-creation endpoint" in xcode_cloud_runbook
            and "does not remove the initial Xcode setup requirement" in xcode_cloud_runbook
            and "does not claim that Xcode Cloud is configured" in xcode_cloud_runbook,
            "Xcode Cloud guidance must keep the included compute limit, no-Mac bootstrap limitation, and initial Xcode/repository setup gate explicit")
    asset_plan = (ROOT / "FactoryTools" / "APP_STORE_ASSET_PLAN.md").read_text(encoding="utf-8")
    require("Beginning April 2027" in asset_plan
            and "for all app submissions" in asset_plan
            and "1398 × 2034 (outer display)" in asset_plan
            and "2007 × 2853 (inner display)" in asset_plan
            and "without conditioning the requirement on the SDK selected" in asset_plan
            and "https://developer.apple.com/news/?id=kkphp5qo" in asset_plan,
            "store asset plan must include current iPhone Duo timing and both display sizes for April 2027 submissions")
    privacy_policy = (ROOT / "FactoryTools" / "PRIVACY_POLICY_DRAFT.md").read_text(encoding="utf-8")
    require("Apple Watchは計測中のサイクルタイム状態" in privacy_policy
            and "iPadは未送信のカウンター操作" in privacy_policy
            and "カウンター操作とサイクルタイム記録を" in privacy_policy
            and "Watch表示を有効にした生産進捗カードのホーム名、生産数、目標数" in privacy_policy
            and "The Watch app stores active timer state and pending counter commands and Cycle Time samples locally" in privacy_policy
            and "the iPad app stores pending counter commands locally" in privacy_policy
            and "counter commands and Cycle Time samples directly with Apple Watch" in privacy_policy
            and "the home name, production count, and target for Watch-enabled Production Progress cards" in privacy_policy
            and "Keychain項目はアプリ削除後も残る場合がある" in privacy_policy
            and "Keychain items may remain after app removal" in privacy_policy,
            "privacy policy draft must match Watch and iPad data flows and explain pairing-secret removal in both languages")
    support_page = (ROOT / "FactoryTools" / "SUPPORT_PAGE_DRAFT.md").read_text(encoding="utf-8")
    require("Watchでサイクルタイムを「停止して記録」した後" in support_page
            and "記録はWatch内で確認応答を待っています" in support_page
            and "Watch Cycle Time sample does not appear" in support_page
            and "remains on Watch until acknowledged" in support_page
            and "アプリを削除する前にiPhoneの設定でペアリングコードを削除" in support_page
            and "remove the pairing code in iPhone Settings before deleting the app" in support_page
            and "iPadの未送信操作は旧コード用のキューに残り" in support_page
            and "Unsent iPad commands remain in the queue for the old code" in support_page
            and "旧コードを安全な場所に控えてください" in support_page
            and "secure copy of the old code" in support_page
            and "保存済みの64桁コードでペアリングを復元" in support_page
            and "Enter an existing 64-character code to restore pairing" in support_page,
            "bilingual support draft must explain offline Watch recovery and per-pairing iPad queue behavior")
    user_guide = (ROOT / "FactoryTools" / "USER_GUIDE.md").read_text(encoding="utf-8")
    require("アプリ削除前に設定から削除してください" in user_guide
            and "Keychainの項目はアプリ削除後も残る場合があります" in user_guide
            and "remove it in Settings before deleting the app" in user_guide
            and "the Keychain item may remain after app removal" in user_guide
            and "iPadの未送信操作は旧コード用のキューに残り" in user_guide
            and "Unsent iPad commands remain in the queue for the old code" in user_guide
            and "旧コードを安全な場所に控えてください" in user_guide
            and "secure copy of the old code" in user_guide
            and "保存済みの64桁コードでペアリングを復元" in user_guide
            and "Enter an existing 64-character code to restore pairing" in user_guide,
            "bilingual user guide must explain pairing-code removal and retained command queues")
    release_runbook = (ROOT / "FactoryTools" / "APPLE_RELEASE_RUNBOOK.md").read_text(encoding="utf-8")
    require("replace the iPhone pairing code" in release_runbook
            and "restore the saved old code in iPhone Settings" in release_runbook
            and "re-enter it on iPad" in release_runbook
            and "verify that the command applies once after acknowledgement" in release_runbook,
            "Apple release runbook must cover restoring the old pairing secret and exactly-once queued-command recovery")
    require("iPhone Duo with Xcode 27.1 or later and Device Hub" in release_runbook
            and "across the device's poses and orientations" in release_runbook
            and "outer and inner display screenshots" in release_runbook
            and "required for all app submissions beginning April 2027" in release_runbook,
            "release runbook must include iPhone Duo layout verification and its April 2027 screenshot gate")
    require("EU Digital Services Act trader status" in release_runbook
            and "declare the account's EU Digital Services Act trader status" in release_runbook
            and "all 27 EU storefronts" in release_runbook,
            "global-release runbook must require an EU trader-status declaration and verified display contacts")
    require("Version 1 distribution scope is iPhone, iPad, and the paired Apple Watch companion" in product_decisions
            and "opt out of offering the compatible iOS/iPadOS app on Apple silicon Macs and Apple Vision Pro" in release_runbook,
            "Version 1 App Store platform availability must stay within the approved iPhone, iPad, and Watch scope")
    require("code and code-entry fields are obscured" in release_runbook
            and "screen capture/mirroring is active" in release_runbook
            and "app-switcher preview" in release_runbook,
            "device runbook must verify pairing-secret redaction during capture and app switching")
    accessed_api_types = (privacy_manifest or {}).get("NSPrivacyAccessedAPITypes", [])
    all_source_text = "\n".join(path.read_text(encoding="utf-8") for path in source_files)
    required_reason_api_patterns = (
        r"\bUserDefaults\b|@AppStorage",
        r"\b(?:creationDate|modificationDate|fileModificationDate)\b|contentModificationDateKey|creationDateKey|\b(?:getattrlist|stat|fstat|fstatat|lstat)\s*\(",
        r"\bsystemUptime\b|\bmach_absolute_time\s*\(",
        r"\b(?:volumeAvailableCapacity\w*|volumeTotalCapacityKey|systemFreeSize|systemSize|statfs|statvfs|fstatfs|fstatvfs)\b",
        r"\bactiveInputModes\b",
    )
    require(not any(re.search(pattern, all_source_text) for pattern in required_reason_api_patterns),
            "source uses a required-reason API beyond the declared ContinuousClock timer and needs a manifest audit")
    require("ContinuousClock.Instant" in all_source_text and any(
                isinstance(entry, dict)
                and entry.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategorySystemBootTime"
                for entry in accessed_api_types
            ),
            "ContinuousClock stopwatch use must retain its SystemBootTime privacy reason")
    localized_info_files = {
        "en": ROOT / "FactoryTools" / "en.lproj" / "InfoPlist.strings",
        "ja": ROOT / "FactoryTools" / "ja.lproj" / "InfoPlist.strings",
    }
    for language, path in localized_info_files.items():
        require(path.is_file()
                and 'CFBundleDisplayName = "Factory Tools";' in path.read_text(encoding="utf-8")
                and 'CFBundleName = "Factory Tools";' in path.read_text(encoding="utf-8")
                and "NSLocalNetworkUsageDescription" in path.read_text(encoding="utf-8"),
                f"{language} InfoPlist.strings must localize app names and local-network permission text")
    japanese_network_copy = localized_info_plist_value(
        localized_info_files["ja"].read_text(encoding="utf-8") if localized_info_files["ja"].is_file() else "",
        "NSLocalNetworkUsageDescription",
    )
    english_network_copy = localized_info_plist_value(
        localized_info_files["en"].read_text(encoding="utf-8") if localized_info_files["en"].is_file() else "",
        "NSLocalNetworkUsageDescription",
    )
    require(has_distinct_localized_copy(japanese_network_copy, english_network_copy),
            "Japanese and English local-network permission descriptions must both be present and translated")

    defined_id_list = re.findall(r"^\s*([A-F0-9]{24})\s*(?:/\*.*?\*/\s*)?=", pbx, re.MULTILINE)
    defined_ids = set(defined_id_list)
    require(len(defined_id_list) == len(defined_ids), "Xcode project contains duplicate 24-character object IDs")
    referenced_ids = set(re.findall(r"\b[A-F0-9]{24}\b", pbx))
    require(referenced_ids.issubset(defined_ids),
            f"Xcode project references undefined object IDs: {sorted(referenced_ids - defined_ids)}")

    metadata_path = ROOT / "FactoryTools" / "APP_STORE_METADATA_DRAFT.md"
    try:
        metadata_source = metadata_path.read_text(encoding="utf-8")
        metadata_errors = app_store_metadata_limit_errors(metadata_source)
        metadata_errors.extend(in_app_purchase_metadata_limit_errors(metadata_source))
    except OSError as error:
        metadata_source = ""
        metadata_errors = [f"Cannot read App Store metadata draft: {error}"]
    require("all countries and regions where Apple permits App Store distribution at launch" in product_decisions
            and "English as the primary App Store metadata language" in product_decisions
            and "Japanese as a localization" in product_decisions
            and "App Store primary category: **Business**" in product_decisions
            and "all App Store countries and regions where Apple permits distribution" in metadata_source
            and "| Primary language | English; add Japanese localization" in metadata_source
            and "| Primary category | Business (selected" in metadata_source,
            "App Store metadata and product decisions must match the bilingual all-territory launch and Business-category plan")
    for error in metadata_errors:
        require(False, error)
    sku_match = re.search(r"^\| SKU \| `([^`]+)`", metadata_source, re.MULTILINE)
    require(sku_match is not None and is_valid_app_store_sku(sku_match.group(1)),
            "App Store Connect SKU candidate must use Apple-supported characters and start with a letter or number")
    for markdown_path in sorted((ROOT / "FactoryTools").rglob("*.md")):
        try:
            markdown_source = markdown_path.read_text(encoding="utf-8")
        except OSError as error:
            require(False, f"Cannot read Markdown document {markdown_path}: {error}")
            continue
        for error in local_markdown_link_errors(markdown_path, markdown_source):
            require(False, error)
    require("Apple Watchでの生産カウントとサイクルタイム計測" in metadata_source
            and "日本向けの販売価格は¥980です" in metadata_source
            and "iPhoneと連携したiPadからの基本カウンター操作" in metadata_source
            and "Japan's Pro customer price is confirmed at ¥980" in metadata_source
            and "Production counting and Cycle Time capture from Apple Watch" in metadata_source
            and "iPad paired with iPhone" in metadata_source
            and "通信できない間のカウント操作やサイクルタイム記録は端末内に保留" in metadata_source
            and "Counter actions and Cycle Time captures made offline stay on the device" in metadata_source
            and "Family Sharing | Disabled for Version 1" in metadata_source
            and "**Family Sharing:** Disabled for Version 1" in metadata_source
            and "追加ホームはFactory Tools Proで利用できます。" in metadata_source
            and "Factory Tools Pro unlocks additional homes." in metadata_source
            and "独立した生産進捗カード、OEE計算" in metadata_source
            and "Standalone Production Progress card and OEE Calculator" in metadata_source
            and "Apple Watchでの生産進捗確認" in metadata_source
            and "Read-only Production Progress view on Apple Watch" in metadata_source
            and "Factory Tools Pro（買い切り）" in metadata_source
            and "FACTORY TOOLS PRO (ONE-TIME PURCHASE)" in metadata_source
            and "PLANNED ONE-TIME PURCHASE" not in metadata_source
            and "Advanced Watch settings" not in metadata_source
            and "高度なWatch設定" not in metadata_source
            and "advanced dashboard settings" not in metadata_source
            and "高度なダッシュボード設定" not in metadata_source,
            "App Store draft must match the current Watch/iPad pairing and implemented Pro feature boundary")

    if ERRORS:
        for error in ERRORS:
            print(f"FAIL: {error}")
        return 1

    print(f"PASS: valid OpenStep project, {len(source_files)} Swift files, {test_case_count} XCTest cases across app and Core targets, {len(strings) + len(watch_strings)} bilingual strings, schemes/assets, target/resource membership, crash-prone Swift escape-hatch checks, and public-free/private-opt-in native workflow contract.")
    print("PASS: bilingual App Store listing draft fits Apple's name, subtitle, description, and keyword limits.")
    print("PASS: localized Factory Tools Pro in-app purchase metadata fits Apple's display-name and description limits.")
    print("PASS: no Swift packages, third-party billing SDKs, external service endpoints, or distributed counter backends; Apple StoreKit is isolated to the one-time Pro manager; local peer transport is isolated.")
    if arguments.release_preflight:
        base_storefront_candidate = (
            arguments.candidate_base_storefront
            if arguments.candidate_base_storefront is not None
            else DEFAULT_BASE_STOREFRONT_CANDIDATE
        )
        base_storefront_price_candidate = (
            arguments.candidate_pro_price
            if arguments.candidate_pro_price is not None
            else DEFAULT_BASE_STOREFRONT_PRICE_CANDIDATE
        )
        project_settings = dict(project_build_settings)
        app_settings = dict(app_build_settings)
        watch_settings = dict(watch_build_settings)
        blockers: list[str] = []
        family_sharing_candidate, family_sharing_conflicts = resolve_family_sharing_candidate(
            product_decisions,
            arguments.candidate_family_sharing,
        )
        if family_sharing_conflicts:
            approved_family_sharing = family_sharing_decision(product_decisions)
            blockers.append(
                f"Family Sharing candidate conflicts with the approved Version 1 decision ({approved_family_sharing})."
            )
        print(
            "INFO: checking selected base-storefront candidate "
            f"{base_storefront_candidate} / {base_storefront_price_candidate}; "
            "this does not configure or verify App Store Connect."
        )
        for configuration_name in ("Debug", "Release"):
            project_configuration = apply_release_candidate_overrides(
                project_settings.get(configuration_name, {}),
                bundle_id=arguments.candidate_bundle_id,
                marketing_version=arguments.candidate_marketing_version,
                build_number=arguments.candidate_build_number,
                team_id=arguments.candidate_team_id,
                privacy_policy_url=arguments.candidate_privacy_policy_url,
                support_url=arguments.candidate_support_url,
                pro_product_id=arguments.candidate_pro_product_id,
            )
            app_configuration = app_settings.get(configuration_name, {})
            watch_configuration = watch_settings.get(configuration_name, {})
            blockers.extend(
                release_preflight_configuration_blockers(
                    configuration_name,
                    project_configuration,
                    app_configuration,
                    watch_configuration,
                    app_icon_catalog_valid=valid_icon_entry and valid_icon_png,
                    watch_icon_catalog_valid=valid_watch_icon_entry and valid_watch_icon_png,
                    pro_price_candidate=base_storefront_price_candidate,
                    family_sharing_candidate=family_sharing_candidate,
                    base_storefront_candidate=base_storefront_candidate,
                )
            )
        if blockers:
            print(f"BLOCKED: source preflight found {len(blockers)} project identity/configuration blocker(s).")
            print(
                "LIMIT: This count covers project settings only; it does not assess Apple enrollment, "
                "App Store Connect setup, URL reachability, native builds/tests, review assets, or publication readiness."
            )
            for blocker in blockers:
                print(f"BLOCKER: {blocker}")
            return 2
        if candidate_values_supplied:
            print("PASS: candidate values passed source-level checks in Debug and Release. This is not a release approval; confirm Bundle ID/product ownership, signing, App Store Connect setup, and public URL reachability separately.")
        else:
            print("PASS: Debug and Release source identity/resource checks passed. This is not a release approval.")
    print("LIMIT: Static checks do not compile or type-check Swift; this Windows host lacks Apple's iOS build/simulator and XCTest toolchain.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
