# Phase 1 acceptance status

This checklist maps the agreed iPhone Phase 1 goal to the current source and regression coverage. The latest complete hosted verification of the main implementation is [Apple native checks run 42425249516](https://github.com/niconiconicopi/factory-tools/actions/runs/42425249516) plus [Watch/archive run 42425249527](https://github.com/niconiconicopi/factory-tools/actions/runs/42425249527), both on commit `9469311`. The current source adds one regression for late command delivery after deleting and recreating a same-named home; that change is awaiting its own hosted run. Simulator evidence does not establish physical-device behavior.

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

- `python Scripts/validate_static.py`: passes with the Free/Pro access registry, purchase integration, localized Watch counter accessibility labels, and the deleted-home delayed-command regression; it inspects 67 Swift files, 284 XCTest methods, 431 Japanese/English strings, resources, target membership, privacy manifest, and architecture contracts. These static checks do not compile or run Swift tests. The new regression still needs a fresh hosted Apple-platform run.
- `python -B -m unittest discover -s Scripts -p "test_*.py"`: all 91 verifier, public-site, and source-hygiene self-tests pass, including Watch Simulator boot-timeout behavior, public-free and manually guarded private native-workflow checks, crash-prone Swift escape-hatch checks, StoreKit/App Store metadata, screenshot workflow, bilingual site generation, legal-page publication guards, generated-file synchronization, ignore rules, and secret-pattern detection.
- The latest completed native evidence is from commit `9469311`: run 42425249516 passed 234 iPhone and 234 iPad XCTest cases, bilingual Release screenshot capture, and its screenshot gate; run 42425249527 passed 48 shared Core tests, Watch Debug/Release builds and screenshots, and an unsigned archive containing the Watch app. The new source test is not included in those runs. Simulator screenshots are diagnostic, not accepted release media.
- This Windows workspace still cannot run Apple's build tools or simulate interaction with physical devices. The simulator results are hosted CI evidence, not physical-device verification.

## Remaining gates

- Physical-device behavior and paired-device network operation remain unverified because this workspace has no Apple hardware.
- `python Scripts/validate_static.py --release-preflight` applies the selected Japan (JP), JPY ¥980 base-storefront candidates for syntax checks and reports three remaining source-configurable publisher identity blockers: Apple Developer Team ID and HTTPS Privacy Policy and Support URLs. Debug and Release use the provisional Bundle ID candidate `com.niconiconicopi.factorytools`; Apple availability and publisher registration are unverified, so confirm it after enrollment and before the first App Store record or upload. The Japan customer price is confirmed at ¥980; the product ID candidate is `factorytools.pro.lifetime`. Both require App Store Connect setup, where the price must be configured as decided. Version 1.0/build 1 is the first-release candidate; publisher identity and store setup are not configured in this workspace.
- App Store Connect privacy and export-compliance answers remain publisher-owned release steps; source-based review drafts and the encryption plist declaration are present, but the final archive and distribution regions still need publisher review.



