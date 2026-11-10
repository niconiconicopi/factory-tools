# Phase 1 acceptance status

This checklist maps the agreed iPhone Phase 1 goal to the current source and regression coverage. App-source revision `c01e71d` passed 237 XCTest cases on each iPhone and iPad Simulator, bilingual Release screenshots, dedicated bilingual S/M/L counter captures, and the required screenshot gate in [native run 42808313649](https://github.com/niconiconicopi/factory-tools/actions/runs/42808313649). A follow-up run verified the SwiftData fixture-directory lifetime fix: [native run 42819982935](https://github.com/niconiconicopi/factory-tools/actions/runs/42819982935) passed all 237 cases on each simulator and the required screenshot gate; [Watch/archive run 42819983047](https://github.com/niconiconicopi/factory-tools/actions/runs/42819983047) also passed. The app binary and UI remain unchanged from `c01e71d`; physical Apple-device behavior remains unverified.

The current working revision includes the already verified workflow-only guard that skips the known headless `SKTestSession` case during native CI and signed-upload preflight while retaining the manager regression tests. This does not establish real StoreKit purchase or restore behavior.

The source gives iPhone/iPad peer connections a 15-second TLS establishment deadline. The loopback XCTest leaves a peer handshake incomplete, confirms it times out, then confirms a correctly paired peer can connect; this passed on both simulators in run 42808313649.

| Acceptance item | Implementation | Regression evidence | Source status |
|---|---|---|---|
| Launch into an Industrial Dark custom home | `AppBootstrapView`, `ThemeManager`, `HomeView`, `HomeProfile` | `testBootstrapServiceCreatesHomeAndSettingsOnlyOnce`, `testThemeManagerResolvesIndustrialDarkTypographyAndBorderTokens` | Implemented |
| Add Production Counter from the Tool Registry | `ToolRegistry`, `HomeToolService`, `ToolPickerView` | `testHomeToolServiceUsesRegistryAvailabilityAsAuthority`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Use +1, -1, Quick Add, Undo, and a target | `CounterService`, `HomeToolCardView`, `CounterSettingsView` | `testUndoAppendsInverseEventAndPreservesHistory`, `testCustomQuickAddAmountIsRecordedAndCanBeUndone`, `testTargetCommandUpdatesSessionAndPersistsAnIdempotencyReceipt` | Implemented |
| Set S/M/L card sizes and reorder cards | `ToolCard`, `HomeToolService`, `HomeView`; home-management action targets are 44×44 pt | `testHomeCardServicePersistsSizeReorderAndRemoval`, home-scoped reorder coverage, and static guards for action hit areas | Run 42808313649 captured all three Production Counter sizes in Japanese and English; OCR verified the displayed count and, where supported, the target row. Reordering is covered through persisted service tests; hands-on drag interaction remains unverified |
| Keep home configuration, language, count, and history after reopening storage | SwiftData local model container and event-backed counter service | `testPersistentStoreRestoresCustomHomeCardsCounterAndLanguage` | Simulator XCTest passed in latest fully successful iPhone/iPad run 42808313649 |
| Switch Japanese/English without changing internal IDs | `AppSettings`, `AppLanguage`, String Catalogs, stable Core `ToolID` | `testAppSettingsServicePersistsLanguageChanges`, `testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage` | Implemented |
| Keep counter history and `currentCount` consistent | `CountEvent` history plus `CounterService` aggregate updates | Counter rollback, overflow, Undo ordering, reopen, and history-balance regressions in `CounterServiceTests.swift` | Implemented |

## Verification on this workspace

- `python Scripts/validate_static.py`: the current source inspection covers 67 Swift files, 286 XCTest methods, and 432 Japanese/English strings, plus resources, target membership, privacy manifest, and architecture contracts. These static checks do not compile or run Swift tests.
- `python -B -m unittest discover -s Scripts -p "test_*.py"`: all 100 verifier self-tests pass on commit `63b3014`, including guards for the writable SwiftData test-store lifetime. `python Scripts/validate_static.py` passes for 67 Swift files, 286 XCTest methods, and 432 localized strings.
- The latest successful hosted iPhone/iPad and Watch/archive gates are runs 42819982935 and 42819983047 on repository head `20882d3`; this head includes the SwiftData test-store cleanup fix. The iPhone/iPad application screens are unchanged from app-source revision `c01e71d`. The signed-release purchase screenshot and publisher acceptance remain distribution tasks.
- This Windows workspace still cannot run Apple's build tools or simulate interaction with physical devices. The simulator results are hosted CI evidence, not physical-device verification.

## Remaining gates

- Physical-device behavior and paired-device network operation remain unverified because this workspace has no Apple hardware.
- `python Scripts/validate_static.py --release-preflight` applies the selected Japan (JP), JPY ¥980 base-storefront candidates for syntax checks and reports three remaining source-configurable publisher identity blockers: Apple Developer Team ID and HTTPS Privacy Policy and Support URLs. Debug and Release use the provisional Bundle ID candidate `com.niconiconicopi.factorytools`; Apple availability and publisher registration are unverified, so confirm it after enrollment and before the first App Store record or upload. The Japan customer price is confirmed at ¥980; the product ID candidate is `factorytools.pro.lifetime`. Both require App Store Connect setup, where the price must be configured as decided. Version 1.0/build 1 is the first-release candidate; publisher identity and store setup are not configured in this workspace.
- App Store Connect privacy and export-compliance answers remain publisher-owned release steps; source-based review drafts and the encryption plist declaration are present, but the final archive and distribution regions still need publisher review.



