# App Store screenshot and purchase-review asset plan

**Status: Release Simulator screenshots are valid App Store screenshot candidates.** Apple requires screenshots in supported dimensions and formats; its current specifications do not require screenshots to come from a signed build or a physical device. The free hosted Apple runs use the Release configuration. App-source commit `053030e` passed [Apple native run 42475375225](https://github.com/niconiconicopi/factory-tools/actions/runs/42475375225), including the screenshot gate, six bilingual Production Counter S/M/L layout captures, and iPhone/iPad app-hosted tests; [Watch/archive run 42475375209](https://github.com/niconiconicopi/factory-tools/actions/runs/42475375209) also passed. A bilingual review package has been assembled at `FactoryTools-AppStore-Assets-Review-2026-11-08` in the workspace parent. Publisher acceptance and a final check that each image still matches the submitted app remain required. Recapture only if the UI or supported release changes. This does not replace physical-device, signed-distribution, or purchase testing.

**Preliminary visual and dimension review (2026-11-08):** Reviewed the current CI artifacts for Japanese/English iPhone homes, Japanese S/M/L counter cards, Japanese counter history and Quick Add, Japanese Cycle Time and Takt Time, the Japanese defect-counter home, the bilingual screenshot-only Pro preview, connected Japanese and offline English iPad dashboards, and the Japanese Watch home. The inspected values and key actions are legible, with no visible text clipping. The prepared unmodified candidates are JPEGs at 1206 × 2622 (Apple-listed iPhone Dynamic Island medium size), 2064 × 2752 (iPad 13-inch), and 416 × 496 (Watch Series 10–12); all selected Watch locales use the same size. This is an internal Simulator-image review only; publisher acceptance and physical-device/accessibility verification remain open.

The previous repeat on synchronized `main` commit `8b8e80d` passed [Apple native checks run 42432727380](https://github.com/niconiconicopi/factory-tools/actions/runs/42432727380) and [Watch/archive run 42432729530](https://github.com/niconiconicopi/factory-tools/actions/runs/42432729530). Those artifacts reproduce 14 iPhone, four iPad, and bilingual Watch Simulator screenshots. The current run artifacts are linked above; they verify the Takt Time retry on the hosted simulator, not final signed App Store assets.

Apple's current screenshot rules were reviewed on 2026-10-31. At least one screenshot is required for iPhone with Dynamic Island, one for 13-inch iPad when iPadOS is supported, and one for Apple Watch when a Watch app is included. App Store Connect allows up to 10 screenshots per device size. Screenshots must not have alpha transparency. The Watch screenshot dimensions must be consistent across localizations.

## Required capture sizes

| Platform | Required slot | Capture size to target | Notes |
|---|---|---:|---|
| iPhone | Dynamic Island, medium display | 1206 × 2622 portrait (current CI captures) | Apple also accepts 1179 × 2556; confirm the live slot before upload. |
| iPad | 13-inch display | 2064 × 2752 portrait | Apple also lists 2048 × 2732 for supported 13-inch models. |
| Apple Watch | Series 12 / Series 11 / Series 10 | 416 × 496 | If another Watch size is used, use the matching Apple-listed resolution consistently for Japanese and English. |

App icons are separate from these screenshots. Apple's current icon guidance uses a 1088 × 1088 watchOS design canvas, while Xcode's asset-catalog workflow documents generating platform variants from a single 1024 × 1024 source image. This project currently uses that single-image asset-catalog path, with opaque RGB PNGs for both the iPhone/iPad and Watch targets. Recheck the generated icon in the Xcode version used for archive; if switching to Icon Composer, use the current Watch design template instead of treating the screenshot dimensions or asset-catalog source size as the artwork canvas. References: [Apple app-icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Xcode asset-catalog icon workflow](https://developer.apple.com/documentation/xcode/configuring-your-app-icon?changes=_3), and [Icon Composer canvas guidance](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer?changes=l_2&language=objc).

Apple's October 2026 announcement says all app submissions beginning April 2027 need iPhone Duo screenshots; the screenshot-specification page associates the requirement with apps using the iOS 27.1 SDK or later, which is also the announced minimum SDK generation for that period. Prepare both portrait displays: 1398 × 2034 (outer) and 2007 × 2853 (inner). Confirm the live App Store Connect slots immediately before submission.

## Product-page screenshot sequence

Keep the displayed feature state and access level accurate. The listed Japanese and English copy are draft overlay headlines; localize any overlay for each App Store localization. Avoid showing real workplace names, people, or production data.

### iPhone

| Order | Capture | Japanese headline | English headline |
|---:|---|---|---|
| 1 | Industrial Dark home with Production Counter and target | 現場の数字を、ひと目で | Production at a glance |
| 2 | Counter interaction showing +1, Quick Add, Undo, and target controls | 数える操作を、すばやく | Count with fewer taps |
| 3 | Cycle Time with sample values | 現場の時間を、すぐ計算 | Shop-floor timing, made simple |
| 4 | Takt Time with sample values | 生産ペースをすぐ計算 | Calculate the required production pace |
| 5 | Defect Counter and Defect Rate using a separate home-scoped sample session | 生産数と不良数を記録 | Track output and defects |
| 6 | Basic counter/Cycle Time history and export or backup entry point | 記録を残し、持ち出せる | Keep and export your records |
| 7 | Pro purchase screen preview or an unlocked Pro tool, only after the final offer and feature set are approved | 専門ツールをProで解放 | Unlock specialist tools with Pro |

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

Capture the actual signed iPhone Settings screen with the configured non-consumable product name, localized description, and Apple-provided display price. This is the IAP review asset; it is separate from the product-page screenshots and from the screenshot-only Pro preview. The ¥980 preview can guide composition, but use the actual storefront display price and verify purchase behavior before accepting the App Review asset.

## Capture and upload checklist

- Review the local `FactoryTools-AppStore-Assets-Review-2026-11-08` package or retrieve the `factory-tools-app-store-iphone-product-page`, `factory-tools-iphone-counter-card-size-evidence`, and `factory-tools-app-store-ipad-product-page` artifacts from iPhone/iPad run 42475375225 and `factory-tools-app-store-watch-home` from Watch screenshot run 42475375209. The dedicated counter artifact contains six Japanese/English S/M/L captures; the iPhone artifact also contains the home and Pro preview captures. Check each localized image against the current release UI and approved listing. The product-page images may be uploaded from these Release Simulator captures once accepted; a signed build is not a screenshot-format requirement.
- The established iPhone home and Pro preview filenames are `iphone-home-ja.jpg`, `iphone-home-en.jpg`, `iphone-pro-purchase-ja.jpg`, and `iphone-pro-purchase-en.jpg`.
- Keep synthetic home, counter, history, defect, and calculator data in the captured Release build.
- Use the prepared Apple-listed iPhone, iPad, and Watch dimensions; recapture from CI or a simulator/device only if the release UI changes.
- For submissions starting April 2027, include iPhone Duo outer- and inner-display screenshots in addition to the currently required Dynamic Island and 13-inch iPad screenshots.
- Prepare both Japanese and English image sets if localized overlay text is used.
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
