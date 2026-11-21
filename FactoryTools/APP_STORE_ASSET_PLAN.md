# App Store screenshot and purchase-review asset plan

**Status: current bilingual screenshot candidate captured and verified on 2026-11-21 from commit `e01a704`.** Native Apple CI run [44866670896](https://github.com/niconiconicopi/factory-tools/actions/runs/44866670896) passed capture and screenshot OCR gates for 14 iPhone images (seven per language), four iPad images (two per language), and six S/M/L layout evidence images. Watch/archive run [44866670819](https://github.com/niconiconicopi/factory-tools/actions/runs/44866670819) passed and produced two Watch images (one per language). The candidates are downloaded under `FactoryTools-AppStore-Assets-Review-2026-11-21/latest-run-44866670896/` and `.../latest-run-44866670819/`. Dimensions were checked locally: iPhone 1206 × 2622, iPad 2064 × 2752, and Watch 416 × 496. All are direct, unaltered JPEG captures of the actual Release Simulator apps using app-provided in-memory sample fixtures; no generated art, compositing, added copy, or retouching. These are review candidates only. The publisher has not accepted them, and none has been uploaded to App Store Connect.

**Important limitations:** iPad connected/reconnecting states in the images are Simulator fixtures and do not prove an actual paired-device connection. The screenshots are not physical-device validation. Only one Watch screen is currently captured per language (the production counter); Cycle Time and Pro progress screens remain optional candidate additions in the asset plan. Do not imply that those Watch screens are represented by the current image set. The separate App Review screenshot for the real StoreKit purchase panel is not captured; it requires the App Store Connect product and a signed build.

Capture method: launch the actual Release Simulator app, enter screenshot-only sample-data mode, take the screen directly with `xcrun simctl io screenshot`, then use `sips` only to convert the PNG capture to JPEG. Synthetic values exist only inside the app's screenshot fixture; they are not real production records. The connected/offline iPad state is also a fixture. Do not present it as a physical-device test.

Apple requires at least one iPhone Dynamic Island medium-display screenshot, at least one 13-inch iPad screenshot when iPadOS is supported, and at least one Apple Watch screenshot when a Watch app is included. App Store Connect accepts up to 10 screenshots per device size, without alpha transparency. The current candidates meet the required base dimensions, but still need publisher review and confirmation against the actual App Store Connect upload slots. This does not replace physical-device, signed-distribution, or purchase testing.

**Historical note:** the 18-image package captured on 2026-11-10 is superseded and must not be uploaded. It predates the approved Japanese display name `現場ギア`; its Japanese home screenshot visibly says `Factory Tools`. Preliminary visual reviews from 2026-11-08 and 2026-11-10 are historical only. The screenshot-only Pro purchase preview is a mock and must never be uploaded as a product-page image or App Review purchase screenshot.

## Required capture sizes

| Platform | Required slot | Capture size to target | Notes |
|---|---|---:|---|
| iPhone | Dynamic Island, medium display | 1206 × 2622 portrait (current CI captures) | Apple also accepts 1179 × 2556; confirm the live slot before upload. |
| iPad | 13-inch display | 2064 × 2752 portrait | Apple also lists 2048 × 2732 for supported 13-inch models. |
| Apple Watch | Series 12 / Series 11 / Series 10 | 416 × 496 | If another Watch size is used, use the matching Apple-listed resolution consistently for Japanese and English. |

App icons are separate from these screenshots. Apple's current icon guidance uses a 1088 × 1088 watchOS design canvas, while Xcode's asset-catalog workflow documents generating platform variants from a single 1024 × 1024 source image. This project currently uses that single-image asset-catalog path, with opaque RGB PNGs for both the iPhone/iPad and Watch targets. Recheck the generated icon in the Xcode version used for archive; if switching to Icon Composer, use the current Watch design template instead of treating the screenshot dimensions or asset-catalog source size as the artwork canvas. References: [Apple app-icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Xcode asset-catalog icon workflow](https://developer.apple.com/documentation/xcode/configuring-your-app-icon?changes=_3), and [Icon Composer canvas guidance](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer?changes=l_2&language=objc).

Apple's October 5, 2026 announcement says apps submitted starting April 2027 need iPhone Duo screenshots. The current screenshot specification separately says screenshots are required starting then for apps using the iOS 27.1 SDK or later. Apple's September 9, 2026 submission notice sets the general iOS/iPadOS SDK minimum for that period at version 27, not 27.1. Treat Duo screenshots as required for any submission from April 2027 unless Apple updates its guidance. Prepare both portrait displays: 1398 × 2034 (outer) and 2007 × 2853 (inner). Confirm the live App Store Connect slots immediately before submission. References: [iPhone Duo submission announcement](https://developer.apple.com/news/?id=kkphp5qo), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), and [April 2027 SDK minimums](https://developer.apple.com/news/?id=k1mtkt1k).

## Product-page screenshot sequence

Keep the displayed feature state and access level accurate. This project uses direct, unaltered app-screen captures: do not composite the Japanese or English headline ideas in the tables onto the screenshots. Avoid showing real workplace names, people, or production data.

### iPhone

| Order | Capture | Japanese note (not overlaid) | English note (not overlaid) |
|---:|---|---|---|
| 1 | Industrial Dark home with Production Counter and target | 現場の数字を、ひと目で | Production at a glance |
| 2 | Counter interaction showing +1, Quick Add, Undo, and target controls | 数える操作を、すばやく | Count with fewer taps |
| 3 | Cycle Time with sample values | 現場の時間を、すぐ計算 | Shop-floor timing, made simple |
| 4 | Takt Time with sample values | 生産ペースをすぐ計算 | Calculate the required production pace |
| 5 | Defect Counter and Defect Rate using a separate home-scoped sample session | 生産数と不良数を記録 | Track output and defects |
| 6 | Basic counter/Cycle Time history and export or backup entry point | 記録を残し、持ち出せる | Keep and export your records |
| 7 | The real Process Capability (Cp/Cpk) form and calculated result from the app | 工程能力を数値で確認 | Check process capability with Cp/Cpk |

### iPad

| Order | Capture | Japanese note (not overlaid) | English note (not overlaid) |
|---:|---|---|---|
| 1 | Paired iPad counter dashboard connected to its iPhone authority | iPadからカウンターを操作 | Control your counter from iPad |
| 2 | Dashboard showing target and queued/offline state if the final UI makes that state clear | 接続状態と目標を確認 | See connection and target status |

### Apple Watch

| Order | Capture | Japanese note (not overlaid) | English note (not overlaid) |
|---:|---|---|---|
| 1 | Production Counter with count, target, and primary +1 action | 手元で、生産数をカウント | Count production from your wrist |
| 2 | Cycle Time stopwatch with a one-unit sample ready to record | サイクルタイムを手元で計測 | Measure Cycle Time from your wrist |
| 3 | Pro read-only Production Progress card with count, target, and completion | Watchで生産進捗を確認 | Check production progress on Watch |
| 4 | Pending/offline command state, only if it is visually clear and non-alarming | 接続後に操作を同期 | Commands sync when connected |

## Separate App Review purchase screenshot

Capture the actual signed iPhone Settings screen with the configured non-consumable product name, localized description, and Apple-provided display price. This is the IAP review asset; it is separate from product-page screenshots. Do not substitute a designed or screenshot-only mock for the real StoreKit purchase sheet. Verify the actual storefront display price and purchase behavior before accepting this App Review asset.

## Capture and upload checklist

- The superseded 2026-11-10 package and earlier CI artifact links are historical references only. Do not upload any image from them. Retrieve a fresh artifact after the current workflow completes, and inspect each included localized image against the current release UI and approved listing. The workflow's product-page artifact must contain only direct Release Simulator captures of actual app screens; generated images and screenshot-only mock purchase screens are excluded. A signed build is not a screenshot-format requirement.
- Only actual app-screen captures belong in the product-page image set. The `iphone-pro-purchase-ja.jpg` and `iphone-pro-purchase-en.jpg` mock previews are not valid product-page assets and must not be used.
- Keep synthetic home, counter, history, defect, and calculator data in the captured Release build.
- Use the prepared Apple-listed iPhone, iPad, and Watch dimensions; recapture from CI or a simulator/device only if the release UI changes.
- For submissions starting April 2027, include iPhone Duo outer- and inner-display screenshots in addition to the currently required Dynamic Island and 13-inch iPad screenshots.
- Capture each language directly from the app's Japanese or English UI; keep all screenshots free of added text or artwork.
- Keep the Apple Watch screenshot dimensions identical across those localizations.
- Verify every shown Pro feature is part of the approved launch offer and can be reached in the submitted build.
- Remove personal, workplace, and location information from status bars and sample records.
- Confirm files are PNG/JPEG without transparency and match the current App Store Connect device slots.
- Capture the separate IAP review screenshot only after StoreKit product setup and signed-build purchase-sheet verification.

## Apple references

- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Add watchOS app information](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information)
- [April 2027 App Store submission requirements](https://developer.apple.com/news/?id=k1mtkt1k)
- [Prepare and submit apps for iPhone Duo (October 2026)](https://developer.apple.com/news/?id=kkphp5qo)
