# Phase 1 acceptance status

This checklist maps the agreed iPhone Phase 1 goal to the current source and regression coverage. Pushed commit `0258ae5` passed app-hosted iPhone/iPad XCTest and the required bilingual screenshot gate in [native run 42441852739](https://github.com/niconiconicopi/factory-tools/actions/runs/42441852739), and passed Watch/Core/archive checks in [run 42441852751](https://github.com/niconiconicopi/factory-tools/actions/runs/42441852751). The native run verifies the hosted OCR retry that recovered from the earlier transient black Takt Time frame. SDK 27 forward checks passed separately on unchanged app/project source revision `a050e18` in [run 42438704276](https://github.com/niconiconicopi/factory-tools/actions/runs/42438704276). Simulator evidence does not establish physical-device behavior.

| Acceptance item | Implementation | Regression evidence | Source status |
|---|---|---|---|
| Launch into an Industrial Dark custom home | `AppBootstrapView`, `ThemeManager`, `HomeView`, `HomeProfile` | `testBootstrapServiceCreatesHomeAndSettingsOnlyOnce`, `testThemeManagerResolvesIndustrialDarkTypographyAndBorderTokens` | Implemented |
| Add Production Counter from the Tool Registry | `ToolRegistry`, `HomeToolService`, `ToolPickerView` | `testHomeToolServiceUsesRegistryAvailabilityAsAuthority`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Use +1, -1, Quick Add, Undo, and a target | `CounterService`, `HomeToolCardView`, `CounterSettingsView` | `testUndoAppendsInverseEventAndPreservesHistory`, `testCustomQuickAddAmountIsRecordedAndCanBeUndone`, `testTargetCommandUpdatesSessionAndPersistsAnIdempotencyReceipt` | Implemented |
| Set S/M/L card sizes and reorder cards | `ToolCard`, `HomeToolService`, `HomeView`; home-management action targets are 44×44 pt | `testHomeCardServicePersistsSizeReorderAndRemoval`; static guard for the four named home-management action hit areas | Simulator XCTest passed in run 42428618160; visual confirmation of each size and reorder gesture remains |
| Keep home configuration, language, count, and history after reopening storage | SwiftData local model container and event-backed counter service | `testPersistentStoreRestoresCustomHomeCardsCounterAndLanguage` | Simulator XCTest passed in run 42428618160 |
| Switch Japanese/English without changing internal IDs | `AppSettings`, `AppLanguage`, String Catalogs, stable Core `ToolID` | `testAppSettingsServicePersistsLanguageChanges`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Keep counter history and `currentCount` consistent | `CountEvent` history plus `CounterService` aggregate updates | Counter rollback, overflow, Undo ordering, reopen, and history-balance regressions in `CounterServiceTests.swift` | Implemented |

## Verification on this workspace

- `python Scripts/validate_static.py`: passes with the Free/Pro access registry, purchase integration, localized Watch counter accessibility labels, and the deleted-home delayed-command regression; it inspects 67 Swift files, 284 XCTest methods, 431 Japanese/English strings, resources, target membership, privacy manifest, and architecture contracts. These static checks do not compile or run Swift tests.
- `python -B -m unittest discover -s Scripts -p "test_*.py"`: all 94 verifier self-tests pass, including a new regression that reproduces an empty Takt Time first frame, relaunches, and accepts the second capture only after the required values are visible.
- The latest full native screenshot gate passed on pushed commit `0258ae5`; run 42441852739 completed the bilingual iPhone/iPad captures and required gate, while Watch/archive run 42441852751 passed. The signed-release purchase screenshot and publisher acceptance remain distribution tasks.
- This Windows workspace still cannot run Apple's build tools or simulate interaction with physical devices. The simulator results are hosted CI evidence, not physical-device verification.

## Remaining gates

- Physical-device behavior and paired-device network operation remain unverified because this workspace has no Apple hardware.
- `python Scripts/validate_static.py --release-preflight` applies the selected Japan (JP), JPY ¥980 base-storefront candidates for syntax checks and reports three remaining source-configurable publisher identity blockers: Apple Developer Team ID and HTTPS Privacy Policy and Support URLs. Debug and Release use the provisional Bundle ID candidate `com.niconiconicopi.factorytools`; Apple availability and publisher registration are unverified, so confirm it after enrollment and before the first App Store record or upload. The Japan customer price is confirmed at ¥980; the product ID candidate is `factorytools.pro.lifetime`. Both require App Store Connect setup, where the price must be configured as decided. Version 1.0/build 1 is the first-release candidate; publisher identity and store setup are not configured in this workspace.
- App Store Connect privacy and export-compliance answers remain publisher-owned release steps; source-based review drafts and the encryption plist declaration are present, but the final archive and distribution regions still need publisher review.



