# Phase 1 acceptance status

This checklist maps the agreed iPhone Phase 1 goal to the current source and regression coverage. Hosted Mac workflow [run 41294221145](https://github.com/niconiconicopi/factory-tools/actions/runs/41294221145) compiled and ran the app suites on iPhone and iPad simulators, captured bilingual Release product screenshots, and built an unsigned archive with the Watch app embedded. iPhone screenshots were visually reviewed; the Watch artifact still needs a corrected recapture. Simulator evidence does not establish physical-device behavior.

| Acceptance item | Implementation | Regression evidence | Source status |
|---|---|---|---|
| Launch into an Industrial Dark custom home | `AppBootstrapView`, `ThemeManager`, `HomeView`, `HomeProfile` | `testBootstrapServiceCreatesHomeAndSettingsOnlyOnce`, `testThemeManagerResolvesIndustrialDarkTypographyAndBorderTokens` | Implemented |
| Add Production Counter from the Tool Registry | `ToolRegistry`, `HomeToolService`, `ToolPickerView` | `testHomeToolServiceUsesRegistryAvailabilityAsAuthority`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Use +1, -1, Quick Add, Undo, and a target | `CounterService`, `HomeToolCardView`, `CounterSettingsView` | `testUndoAppendsInverseEventAndPreservesHistory`, `testCustomQuickAddAmountIsRecordedAndCanBeUndone`, `testTargetCommandUpdatesSessionAndPersistsAnIdempotencyReceipt` | Implemented |
| Set S/M/L card sizes and reorder cards | `ToolCard`, `HomeToolService`, `HomeView`; home-management action targets are 44×44 pt | `testHomeCardServicePersistsSizeReorderAndRemoval`; static guard for the four named home-management action hit areas | Simulator XCTest passed in run 41294221145; visual confirmation of each size and reorder gesture remains |
| Keep home configuration, language, count, and history after reopening storage | SwiftData local model container and event-backed counter service | `testPersistentStoreRestoresCustomHomeCardsCounterAndLanguage` | Simulator XCTest passed in run 41294221145 |
| Switch Japanese/English without changing internal IDs | `AppSettings`, `AppLanguage`, String Catalogs, stable Core `ToolID` | `testAppSettingsServicePersistsLanguageChanges`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Keep counter history and `currentCount` consistent | `CountEvent` history plus `CounterService` aggregate updates | Counter rollback, overflow, Undo ordering, reopen, and history-balance regressions in `CounterServiceTests.swift` | Implemented |

## Verification on this workspace

- `python Scripts/validate_static.py`: passed with the Free/Pro access registry and purchase integration; it inspects 66 Swift files, 271 XCTest methods, 431 Japanese/English strings, resources, target membership, privacy manifest, and architecture contracts. These static checks do not compile or run Swift tests.
- `python -B -m unittest discover -s Scripts -p "test_*.py"`: 84 verifier, public-site, and source-hygiene self-tests pass, including public-free and manually guarded private native-workflow checks, crash-prone Swift escape-hatch checks, StoreKit/App Store metadata, screenshot workflow with Watch image OCR wiring, privacy transfer disclosures, bilingual site generation, legal-page publication guards, generated-file synchronization, matching iPhone/Watch brand icons, ignore rules, and secret-pattern detection.
- Hosted Mac run [41317287689](https://github.com/niconiconicopi/factory-tools/actions/runs/41317287689) passed source checks, iPhone and iPad Simulator app suites, all shared Core tests, both Watch Simulator builds, bilingual Release screenshot capture, and an unsigned generic iOS archive with the Watch app embedded. The later Watch capture in [41346861432](https://github.com/niconiconicopi/factory-tools/actions/runs/41346861432) produced 416×496 images, but direct review shows the Japanese capture omitted the count while English includes it. The November 10 Watch review set shows the reverse, indicating transient capture readiness rather than a stable locale-specific defect. The local capture uses an independent simulator per locale and retries up to 20 times until Apple Vision OCR sees the exact counter and target. The hosted rerun and visual review are still required. Earlier iPhone/iPad images also predate the approved Japanese app name and must be recaptured before store use.
- This Windows workspace still cannot run Apple's build tools or simulate interaction with physical devices. The simulator results are hosted CI evidence, not physical-device verification.

## Remaining gates

- Physical-device behavior and paired-device network operation remain unverified because this workspace has no Apple hardware.
- `python Scripts/validate_static.py --release-preflight` now passes the configured candidate Bundle ID, known Team ID, HTTPS privacy/support URLs, app version/build, and platform assets. These checks do not establish Bundle ID availability, publish or verify the pages, configure App Store Connect, or validate a signed Apple build. The Japan customer price is confirmed at ¥980; `factorytools.pro.lifetime` is the product ID candidate. Store setup and purchase-sheet verification remain release gates.
- App Store Connect privacy and export-compliance answers remain publisher-owned release steps; source-based review drafts and the encryption plist declaration are present, but the final archive and distribution regions still need publisher review.



