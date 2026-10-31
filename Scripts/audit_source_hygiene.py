from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATHS = (
    ".gitignore",
    "FactoryTools",
    "FactoryTools.xcodeproj",
    "FactoryToolsCore",
    "FactoryToolsCoreTests",
    "FactoryToolsTests",
    "FactoryToolsWatch",
    "Scripts",
)
SECRET_SUFFIXES = {".p8", ".p12", ".mobileprovision", ".provisionprofile", ".pem", ".key"}
SECRET_PATTERNS = (
    ("private-key block", re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("GitHub token", re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
    ("GitHub fine-grained token", re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("AWS access-key ID", re.compile(rb"\bAKIA[0-9A-Z]{16}\b")),
    ("Slack token", re.compile(rb"\bxox[baprs]-[A-Za-z0-9-]{16,}\b")),
    ("Stripe secret key", re.compile(rb"\bsk_(?:live|test)_[A-Za-z0-9]{16,}\b")),
)
IGNORED_DIRECTORY_NAMES = {".git", "__pycache__", "DerivedData", "build", ".build", "xcuserdata"}


def files_to_scan(root: Path):
    for relative_path in SOURCE_PATHS:
        target = root / relative_path
        if not target.exists():
            continue
        if target.is_file():
            yield target
            continue
        for path in target.rglob("*"):
            if not path.is_file() or any(part in IGNORED_DIRECTORY_NAMES for part in path.relative_to(target).parts[:-1]):
                continue
            yield path


def audit(root: Path = ROOT) -> list[tuple[str, str]]:
    findings: list[tuple[str, str]] = []
    for path in files_to_scan(root):
        relative = path.relative_to(root).as_posix()
        if path.suffix.lower() in SECRET_SUFFIXES:
            findings.append((relative, "signing/private-key file"))
            continue
        try:
            content = path.read_bytes()
        except OSError:
            findings.append((relative, "unreadable source file"))
            continue
        if b"\0" in content:
            continue
        for label, pattern in SECRET_PATTERNS:
            if pattern.search(content):
                findings.append((relative, label))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan Factory Tools source paths for common signing credentials and API-token patterns.")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    findings = audit(arguments.root.resolve())
    if findings:
        for relative, label in findings:
            print(f"BLOCKER: credential-like content ({label}) in {relative}", file=sys.stderr)
        print("Remove credentials from source and rotate any exposed key before creating or pushing a remote repository.", file=sys.stderr)
        return 1
    print("PASS: no common signing-key or API-token patterns found in the Factory Tools source paths.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
