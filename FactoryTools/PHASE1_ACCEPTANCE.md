# Phase 1 acceptance status

This checklist maps the agreed iPhone Phase 1 goal to the current source and regression coverage. App-source commit `4a7d97c` passed the iPhone/iPad app-hosted test suites, bilingual Release screenshots, dedicated bilingual S/M/L counter-card captures, and the required screenshot gate in [native run 42503560650](https://github.com/niconiconicopi/factory-tools/actions/runs/42503560650). [Watch/archive run 42503563358](https://github.com/niconiconicopi/factory-tools/actions/runs/42503563358) passed Watch, shared Core, and unsigned archive checks. The iPad run also validates the SwiftData test-store lifetime correction. Simulator evidence does not establish physical-device behavior.

| Acceptance item | Implementation | Regression evidence | Source status |
|---|---|---|---|
| Launch into an Industrial Dark custom home | `AppBootstrapView`, `ThemeManager`, `HomeView`, `HomeProfile` | `testBootstrapServiceCreatesHomeAndSettingsOnlyOnce`, `testThemeManagerResolvesIndustrialDarkTypographyAndBorderTokens` | Implemented |
| Add Production Counter from the Tool Registry | `ToolRegistry`, `HomeToolService`, `ToolPickerView` | `testHomeToolServiceUsesRegistryAvailabilityAsAuthority`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Use +1, -1, Quick Add, Undo, and a target | `CounterService`, `HomeToolCardView`, `CounterSettingsView` | `testUndoAppendsInverseEventAndPreservesHistory`, `testCustomQuickAddAmountIsRecordedAndCanBeUndone`, `testTargetCommandUpdatesSessionAndPersistsAnIdempotencyReceipt` | Implemented |
| Set S/M/L card sizes and reorder cards | `ToolCard`, `HomeToolService`, `HomeView`; home-management action targets are 44×44 pt | `testHomeCardServicePersistsSizeReorderAndRemoval`, home-scoped reorder coverage, and static guards for action hit areas | Run 42503560650 captured all three Production Counter sizes in Japanese and English; OCR verified the displayed count and, where supported, the target row. Reordering is covered through persisted service tests; hands-on drag interaction remains unverified |
| Keep home configuration, language, count, and history after reopening storage | SwiftData local model container and event-backed counter service | `testPersistentStoreRestoresCustomHomeCardsCounterAndLanguage` | Simulator XCTest passed again in latest iPhone/iPad run 42503560650 |
| Switch Japanese/English without changing internal IDs | `AppSettings`, `AppLanguage`, String Catalogs, stable Core `ToolID` | `testAppSettingsServicePersistsLanguageChanges`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Keep counter history and `currentCount` consistent | `CountEvent` history plus `CounterService` aggregate updates | Counter rollback, overflow, Undo ordering, reopen, and history-balance regressions in `CounterServiceTests.swift` | Implemented |

## Verification on this workspace

- `python Scripts/validate_static.py`: passes with the Free/Pro access registry, purchase integration, hosted-test storage isolation, localized Watch counter accessibility labels, and the deleted-home delayed-command regression; it inspects 67 Swift files, 285 XCTest methods, 431 Japanese/English strings, resources, target membership, privacy manifest, and architecture contracts. These static checks do not compile or run Swift tests.
- `python -B -m unittest discover -s Scripts -p "test_*.py"`: all 98 verifier self-tests pass, including a new regression that reproduces an empty Takt Time first frame, relaunches, and accepts the second capture only after the required values are visible.
- The latest full native screenshot gate passed on app-source commit `4a7d97c`; run 42503560650 completed the iPhone and iPad test suites, bilingual iPhone/iPad product captures, six dedicated bilingual S/M/L counter screenshots, and the required gate. Watch/archive run 42503563358 passed. This also verifies the fix for the earlier SwiftData test-store lifetime failure. The signed-release purchase screenshot and publisher acceptance remain distribution tasks.
- This Windows workspace still cannot run Apple's build tools or simulate interaction with physical devices. The simulator results are hosted CI evidence, not physical-device verification.

## Remaining gates

- Physical-device behavior and paired-device network operation remain unverified because this workspace has no Apple hardware.
- `python Scripts/validate_static.py --release-preflight` applies the selected Japan (JP), JPY ¥980 base-storefront candidates for syntax checks and reports three remaining source-configurable publisher identity blockers: Apple Developer Team ID and HTTPS Privacy Policy and Support URLs. Debug and Release use the provisional Bundle ID candidate `com.niconiconicopi.factorytools`; Apple availability and publisher registration are unverified, so confirm it after enrollment and before the first App Store record or upload. The Japan customer price is confirmed at ¥980; the product ID candidate is `factorytools.pro.lifetime`. Both require App Store Connect setup, where the price must be configured as decided. Version 1.0/build 1 is the first-release candidate; publisher identity and store setup are not configured in this workspace.
- App Store Connect privacy and export-compliance answers remain publisher-owned release steps; source-based review drafts and the encryption plist declaration are present, but the final archive and distribution regions still need publisher review.



