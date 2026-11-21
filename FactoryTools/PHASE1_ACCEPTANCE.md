# Phase 1 acceptance status

This checklist maps the agreed iPhone Phase 1 goal to the current source and regression coverage. The latest app-source revision, `e01a704`, passed the iPhone and iPad Simulator XCTest suites, bilingual Release screenshot capture and OCR gates, six dedicated S/M/L counter captures, and the iPad screenshot gate in [native run 44866670896](https://github.com/niconiconicopi/factory-tools/actions/runs/44866670896). [Watch/archive run 44866670819](https://github.com/niconiconicopi/factory-tools/actions/runs/44866670819) passed shared Core tests, Watch Debug/Release Simulator builds, bilingual Watch captures, and the unsigned iOS archive embedding the Watch app. `git diff e01a704 HEAD` contains documentation changes only; the current Swift and Xcode project sources match the verified app revision. Physical Apple-device behavior remains unverified.

The current workflow-only guard skips the focused headless `SKTestSession` case during routine native CI and signed-upload preflight while retaining the manager regression tests. A later Xcode 27.1 hosted run also failed to load the configured local product, but its exact cause is unconfirmed; the added runtime product-ID assertion and failure diagnostics have not yet run on Apple CI. This does not establish real StoreKit purchase or restore behavior.

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

- `python Scripts/validate_static.py --release-preflight`: static inspection passes for 69 Swift files, 289 XCTest source cases, 445 Japanese/English strings, project/resource membership, architecture contracts, and bilingual listing/IAP limits. It does not compile or run Swift tests.
- `python -m unittest discover -s Scripts -p 'test_*.py'`: all 108 verifier self-tests pass in the current working tree, including screenshot-capture recovery and release workflow guards.
- The latest successful hosted iPhone/iPad and Watch/archive gates are runs 44866670896 and 44866670819 on app-source revision `e01a704`. The signed-release purchase screenshot and publisher acceptance remain distribution tasks.
- This Windows workspace still cannot run Apple's build tools or simulate interaction with physical devices. The simulator results are hosted CI evidence, not physical-device verification.

## Remaining gates

- Physical-device behavior and paired-device network operation remain unverified because this workspace has no Apple hardware.
- `python Scripts/validate_static.py --release-preflight` passes the selected Japan (JP), JPY ¥980 candidates and the source-configured Team ID, Bundle ID, Pro product ID, and publisher-approved HTTPS policy/support URL candidates. It only validates syntax and project settings; it does not verify Apple account ownership, public URL reachability, App Store Connect setup, signing credentials, or the actual price. Debug and Release still use the reversible Bundle ID candidate `com.niconiconicopi.factorytools`; verify availability in the Apple account before creating the first App Store record. The Pro product ID candidate remains `factorytools.pro.lifetime`. Version 1.0/build 1 is the first-release candidate; App Store Connect, privacy/support publication, signed upload, purchase testing, and publisher acceptance remain distribution tasks.
- App Store Connect privacy and export-compliance answers remain publisher-owned release steps; source-based review drafts and the encryption plist declaration are present, but the final archive and distribution regions still need publisher review.



