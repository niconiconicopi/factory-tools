# Phase 1 acceptance status

This checklist maps the agreed iPhone Phase 1 goal to the current source and regression coverage. **Implemented** describes the code and test source; it does not claim an Apple-platform build or runtime test was executed.

| Acceptance item | Implementation | Regression evidence | Source status |
|---|---|---|---|
| Launch into an Industrial Dark custom home | `AppBootstrapView`, `ThemeManager`, `HomeView`, `HomeProfile` | `testBootstrapServiceCreatesHomeAndSettingsOnlyOnce`, `testThemeManagerResolvesIndustrialDarkTypographyAndBorderTokens` | Implemented |
| Add Production Counter from the Tool Registry | `ToolRegistry`, `HomeToolService`, `ToolPickerView` | `testHomeToolServiceUsesRegistryAvailabilityAsAuthority`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Use +1, -1, Quick Add, Undo, and a target | `CounterService`, `HomeToolCardView`, `CounterSettingsView` | `testUndoAppendsInverseEventAndPreservesHistory`, `testCustomQuickAddAmountIsRecordedAndCanBeUndone`, `testTargetCommandUpdatesSessionAndPersistsAnIdempotencyReceipt` | Implemented |
| Set S/M/L card sizes and reorder cards | `ToolCard`, `HomeToolService`, `HomeView`; home-management action targets are 44×44 pt | `testHomeCardServicePersistsSizeReorderAndRemoval`; static guard for the four named home-management action hit areas | Implemented in source; native layout unverified |
| Keep home configuration, language, count, and history after reopening storage | SwiftData local model container and event-backed counter service | `testPersistentStoreRestoresCustomHomeCardsCounterAndLanguage` | Implemented in source; native store behavior unverified |
| Switch Japanese/English without changing internal IDs | `AppSettings`, `AppLanguage`, String Catalogs, stable Core `ToolID` | `testAppSettingsServicePersistsLanguageChanges`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Keep counter history and `currentCount` consistent | `CountEvent` history plus `CounterService` aggregate updates | Counter rollback, overflow, Undo ordering, reopen, and history-balance regressions in `CounterServiceTests.swift` | Implemented |

## Verification on this workspace

- `python Scripts/validate_static.py`: passed with the Free/Pro access registry and purchase integration; it inspects 66 Swift files, 268 XCTest methods, 428 Japanese/English strings, resources, target membership, privacy manifest, and architecture contracts. These static checks do not compile or run Swift tests.
- `python -B -m unittest discover -s Scripts -p "test_*.py"`: 70 verifier, public-site, and source-hygiene self-tests pass, including public-free and manually guarded private native-workflow checks, crash-prone Swift escape-hatch checks (including app-source forced unwraps), App Store SKU syntax checks, iPhone `ThemeManager` routing/direct-palette bypass checks, Watch `WatchTheme` color-token isolation, bilingual site generation, publication-candidate field/date/contact/URL validation, HTML structure/accessibility checks, generated-file synchronization, sensitive/unrelated-path ignore rules, and secret-pattern detection.
- These checks do not compile or type-check Swift and do not execute XCTest.

## Remaining gates

- Native Xcode build, XCTest, and device/simulator behavior remain unverified because this workspace runs on Windows without Apple's toolchain.
- `python Scripts/validate_static.py --release-preflight` applies the selected Japan (JP), JPY ¥980 base-storefront candidates for syntax checks and reports five remaining publisher identity blockers: the development `com.example` Bundle ID in Debug and Release, Apple Developer Team ID, and HTTPS Privacy Policy and Support URLs. The Japan customer price is confirmed at ¥980; the product ID candidate is `factorytools.pro.lifetime`. Both require App Store Connect setup, where the price must be configured as decided. Version 1.0/build 1 is the first-release candidate; publisher identity and store setup are not configured in this workspace.
- App Store Connect privacy and export-compliance answers remain publisher-owned release steps; source-based review drafts and the encryption plist declaration are present, but the final archive and distribution regions still need publisher review.



