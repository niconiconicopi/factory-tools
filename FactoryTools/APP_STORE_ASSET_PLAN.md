# App Store screenshot and purchase-review asset plan

**Status: simulator screenshots are diagnostic and not accepted for submission.** Runs [41350198179](https://github.com/niconiconicopi/factory-tools/actions/runs/41350198179) and [41443178099](https://github.com/niconiconicopi/factory-tools/actions/runs/41443178099) passed native checks, builds, captures, and unsigned archive. Manual review of the six available localized iPhone, iPad, and Watch home JPEGs confirms that 286 and target 300 are visible; the earlier audit's claim that these values were missing was incorrect. The older Watch images show a very low-contrast −1 control, corrected in source but still awaiting a fresh captured-image review. Run [41459057399](https://github.com/niconiconicopi/factory-tools/actions/runs/41459057399) added per-launch locale-aware home readiness, final-JPEG OCR for the home row, and position-aware Watch OCR. GitHub canceled it after 15 minutes: its job had runner ID 0 and no steps, and the annotation says a hosted macOS arm64 runner could not acquire capacity. It did not test this change. The native workflow now targets `macos-26-intel` with Xcode 26.6. The workflow also preserves screenshot JPEG diagnostics on OCR failure and uploads an xcresult plus Xcode log when XCTest fails. Keep images diagnostic until a newly assigned run's artifacts are reviewed and the post-fix Watch controls are legible. Demo records use in-memory stores and are enabled only for Simulator launches. Counter interaction/undo and the separate Pro purchase screen are not captured; the Pro screen must use the actual configured StoreKit product and price. No screenshots are committed to the repository. Do not use generated or reconstructed UI as a substitute for an app capture. Recheck Apple's specifications immediately before upload.

Apple's current screenshot rules were reviewed on 2026-10-31. At least one screenshot is required for iPhone with Dynamic Island, one for 13-inch iPad when iPadOS is supported, and one for Apple Watch when a Watch app is included. App Store Connect allows up to 10 screenshots per device size. Screenshots must not have alpha transparency. The Watch screenshot dimensions must be consistent across localizations.

## Required capture sizes

| Platform | Required slot | Capture size to target | Notes |
|---|---|---:|---|
| iPhone | Dynamic Island, medium display | 1179 × 2556 portrait | Apple accepts other listed resolutions; use the simulator/device actually selected for capture. |
| iPad | 13-inch display | 2064 × 2752 portrait | Apple also lists 2048 × 2732 for supported 13-inch models. |
| Apple Watch | Series 12 / Series 11 / Series 10 | 416 × 496 | If another Watch size is used, use the matching Apple-listed resolution consistently for Japanese and English. |

App icons are separate from these screenshots. Apple's current icon guidance uses a 1088 × 1088 watchOS design canvas, while Xcode's asset-catalog workflow documents generating platform variants from a single 1024 × 1024 source image. This project currently uses that single-image asset-catalog path, with opaque RGB PNGs for both the iPhone/iPad and Watch targets. Recheck the generated icon in the Xcode version used for archive; if switching to Icon Composer, use the current Watch design template instead of treating the screenshot dimensions or asset-catalog source size as the artwork canvas. References: [Apple app-icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Xcode asset-catalog icon workflow](https://developer.apple.com/documentation/xcode/configuring-your-app-icon?changes=_3), and [Icon Composer canvas guidance](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer?changes=l_2&language=objc).

Beginning April 2027, Apple's current announcement requires iPhone Duo screenshots for all app submissions, without conditioning the requirement on the SDK selected for the build. Prepare screenshots for both displays: 1398 × 2034 (outer display) and 2007 × 2853 (inner display) in portrait. Confirm the live App Store Connect slots immediately before submission.

## Product-page screenshot sequence

Keep the displayed feature state and access level accurate. The listed Japanese and English copy are draft overlay headlines; localize any overlay for each App Store localization. Avoid showing real workplace names, people, or production data.

### iPhone

| Order | Capture | Japanese headline | English headline |
|---:|---|---|---|
| 1 | Industrial Dark home with Production Counter and target | 現場の数字を、ひと目で | Production at a glance |
| 2 | Counter interaction showing +1, Quick Add, Undo, and target controls | 数える操作を、すばやく | Count with fewer taps |
| 3 | Cycle Time and Takt Time tools with sample values | 現場の時間を、すぐ計算 | Shop-floor timing, made simple |
| 4 | Defect Counter and Defect Rate using a separate home-scoped sample session | 生産数と不良数を記録 | Track output and defects |
| 5 | Basic counter/Cycle Time history and export or backup entry point | 記録を残し、持ち出せる | Keep and export your records |
| 6 | Pro screen or an unlocked Pro tool, only after the final offer and feature set are approved | 専門ツールをProで解放 | Unlock specialist tools with Pro |

### iPad

| Order | Capture | Japanese headline | English headline |
|---:|---|---|---|
| 1 | Paired iPad counter dashboard connected to its iPhone authority | iPadからカウンターを操作 | Control your counter from iPad |
| 2 | Dashboard showing target and queued/offline state if the final UI makes that state clear | 接続状態と目標を確認 | See connection and target status |

### Apple Watch

| Order | Capture | Japanese headline | English headline |
|---:|---|---|---|
| 1 | Production Counter with count, target, and primary +1 action | 手元で、生産数をカウント | Count production from your wrist |
| 2 | Cycle Time stopwatch with a one-unit sample ready to record | サイクルタイムを手元で計測 | Measure Cycle Time from your wrist |
| 3 | Pro read-only Production Progress card with count, target, and completion | Watchで生産進捗を確認 | Check production progress on Watch |
| 4 | Pending/offline command state, only if it is visually clear and non-alarming | 接続後に操作を同期 | Commands sync when connected |

## Separate App Review purchase screenshot

Capture the actual signed iPhone Settings screen with the configured non-consumable product name, localized description, and Apple-provided display price. This is the IAP review asset; it is separate from the product-page screenshots. Do not capture it until the final product ID, price, and Pro launch features are set.

## Capture and upload checklist

- Retrieve the `factory-tools-app-store-iphone-home` artifact and every other localized iPhone, iPad, and Watch artifact from the latest successful Apple native CI run; confirm each screen shows its required values and controls before accepting it.
- Create synthetic home, counter, history, defect, and calculator data in the release build.
- Capture iPhone, iPad, and Watch screens at the chosen Apple-listed sizes.
- For submissions starting April 2027, include iPhone Duo outer- and inner-display screenshots in addition to the currently required Dynamic Island and 13-inch iPad screenshots.
- Prepare both Japanese and English image sets if localized overlay text is used.
- Keep the Apple Watch screenshot dimensions identical across those localizations.
- Verify every shown Pro feature is part of the approved launch offer and can be reached in the submitted build.
- Remove personal, workplace, and location information from status bars and sample records.
- Confirm files are PNG/JPEG without transparency and match the current App Store Connect device slots.
- Capture the separate IAP review screenshot only after StoreKit product setup and signed-build verification.

## Apple references

- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Add watchOS app information](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information)
- [April 2027 App Store submission requirements](https://developer.apple.com/news/?id=k1mtkt1k)
- [Prepare and submit apps for iPhone Duo (October 2026)](https://developer.apple.com/news/?id=kkphp5qo)
