# Phase 1 acceptance status

This checklist maps the agreed iPhone Phase 1 goal to the current source and regression coverage. Hosted Mac workflow [run 41780014206](https://github.com/niconiconicopi/factory-tools/actions/runs/41780014206) passed the iPhone and iPad app suites, shared Core tests, Watch Debug/Release builds, bilingual iPhone/iPad Release screenshot capture, and unsigned archive with the Watch app embedded. The optional Watch screenshot step failed while the simulator waited for watchOS System App; its boot wait has since been increased to 15 minutes, and the hosted recheck is [run 41800837089](https://github.com/niconiconicopi/factory-tools/actions/runs/41800837089). Simulator evidence does not establish physical-device behavior.

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

- `python Scripts/validate_static.py`: passed with the Free/Pro access registry, purchase integration, and localized Watch counter accessibility labels; it inspects 67 Swift files, 272 XCTest methods, 431 Japanese/English strings, resources, target membership, privacy manifest, and architecture contracts. These static checks do not compile or run Swift tests.
- `python -B -m unittest discover -s Scripts -p "test_*.py"`: 88 verifier, public-site, and source-hygiene self-tests pass, including Watch Simulator boot-timeout behavior, public-free and manually guarded private native-workflow checks, crash-prone Swift escape-hatch checks, StoreKit/App Store metadata, screenshot workflow, bilingual site generation, legal-page publication guards, generated-file synchronization, ignore rules, and secret-pattern detection.
- The 2026-11-04 native run [41780014206](https://github.com/niconiconicopi/factory-tools/actions/runs/41780014206) includes the newer StoreKit/VoiceOver source and passes both native app suites. The Apple Watch screenshot retry fix is under hosted recheck in run 41800837089. Simulator screenshots are diagnostic, not accepted release media.
- This Windows workspace still cannot run Apple's build tools or simulate interaction with physical devices. The simulator results are hosted CI evidence, not physical-device verification.

## Remaining gates

- Physical-device behavior and paired-device network operation remain unverified because this workspace has no Apple hardware.
- `python Scripts/validate_static.py --release-preflight` applies the selected Japan (JP), JPY ¥980 base-storefront candidates for syntax checks and reports five remaining publisher identity blockers: the development `com.example` Bundle ID in Debug and Release, Apple Developer Team ID, and HTTPS Privacy Policy and Support URLs. The Japan customer price is confirmed at ¥980; the product ID candidate is `factorytools.pro.lifetime`. Both require App Store Connect setup, where the price must be configured as decided. Version 1.0/build 1 is the first-release candidate; publisher identity and store setup are not configured in this workspace.
- App Store Connect privacy and export-compliance answers remain publisher-owned release steps; source-based review drafts and the encryption plist declaration are present, but the final archive and distribution regions still need publisher review.



