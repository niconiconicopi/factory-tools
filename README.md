# Factory Tools

Factory Tools is a SwiftUI toolkit for production work on iPhone, Apple Watch, and iPad. It uses SwiftData for local persistence and contains no third-party packages, external APIs, paid SDKs, or cloud service dependencies.

The Xcode project targets iOS 17 and watchOS 10. Its schemes cover the app, shared Core logic, and Watch app. Read the [project overview](FactoryTools/README.md), [roadmap](FactoryTools/ROADMAP.md), and [product decisions](FactoryTools/PRODUCT_DECISIONS.md) for current scope and release status.

## Local checks

From the repository root, run:

```powershell
python -B -m unittest discover -s Scripts -p "test_*.py"
python Scripts/validate_static.py
python Scripts/generate_public_site.py --check
python Scripts/audit_source_hygiene.py
```

These checks run on Windows. They validate source structure and project contracts, but they do not compile Swift or run XCTest. Native Xcode build and simulator tests run through two GitHub Actions workflows: the [Apple native checks](.github/workflows/apple-native-checks.yml) cover iPhone/iPad tests and their bilingual screenshots; [Apple Watch and archive checks](.github/workflows/apple-watch-archive-checks.yml) run shared Core tests, Watch builds and screenshots, and the unsigned iOS archive in separate hosted Mac jobs.

Hosted simulator checks currently target the standard macOS 15 Apple silicon image (Xcode 16.4) while GitHub cannot acquire Intel macOS runners. The project targets iOS 17 and watchOS 10, so this provides an additional compatibility build; a signed Xcode 26 release archive is still required before App Store submission. The manual [Apple archive check](.github/workflows/apple-archive-check.yml) remains available when an on-demand unsigned archive and Watch embedding check is needed.

## Repository status

This is an in-development project. App Store publisher identity, signing, support and privacy URLs, and the store submission are not configured. If published, the source is intended for public review; no open-source license is included, so publication alone does not grant general reuse rights.

For the Japanese-language project guide, see [FactoryTools/README.md](FactoryTools/README.md).
