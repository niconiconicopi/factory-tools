# App Store screenshot and purchase-review asset plan

**Status: direct bilingual Release Simulator captures passed their capture/OCR gates on 2026-11-21 from repository commit `f85aa07`; designed Store-image layouts are separate private review drafts.** Native Apple CI run [44895497260](https://github.com/niconiconicopi/factory-tools/actions/runs/44895497260) passed capture and screenshot OCR gates for 14 iPhone images (seven per language), four iPad images (two per language), and six S/M/L layout evidence images. Watch/archive run [44895497362](https://github.com/niconiconicopi/factory-tools/actions/runs/44895497362) passed and produced two Watch counter images (one per language). Those historical artifacts are under `FactoryTools-AppStore-Assets-Review-2026-11-21/latest-run-44895497260/` and `.../latest-run-44895497362/factory-tools-app-store-watch-home/`. A pending local change extends Watch capture to counter, Cycle Time, and Pro Production Progress in both languages; those six additional captures are not evidence until the hosted workflow passes. Source images are direct JPEG captures of the Release Simulator apps using app-provided in-memory sample fixtures. They remain publisher-review candidates and have not been uploaded to App Store Connect.

**Important limitations:** iPad connected/reconnecting states in the images are Simulator fixtures and do not prove an actual paired-device connection. The screenshots are not physical-device validation. The currently passing Watch evidence contains only the production counter; the added Cycle Time and Pro progress captures still require hosted build and OCR verification. Do not imply that these additional screens have already passed. The separate App Review screenshot for the real StoreKit purchase panel is not captured; it requires the App Store Connect product and a signed build.

Capture method: launch the actual Release Simulator app, enter screenshot-only sample-data mode, take the screen directly with `xcrun simctl io screenshot`, then use `sips` only to convert the PNG capture to JPEG. Synthetic values exist only inside the app's screenshot fixture; they are not real production records. The connected/offline iPad state is also a fixture. Do not present it as a physical-device test.

Apple requires at least one iPhone Dynamic Island medium-display screenshot, at least one 13-inch iPad screenshot when iPadOS is supported, and at least one Apple Watch screenshot when a Watch app is included. App Store Connect accepts up to 10 screenshots per device size, without alpha transparency. The current candidates meet the required base dimensions, but still need publisher review and confirmation against the actual App Store Connect upload slots. This does not replace physical-device, signed-distribution, or purchase testing.

**Historical note:** the 18-image package captured on 2026-11-10 is superseded and must not be uploaded. It predates the approved Japanese display name `現場ギア`; its Japanese home screenshot visibly says `Factory Tools`. Preliminary visual reviews from 2026-11-08 and 2026-11-10 are historical only. The screenshot-only Pro purchase preview is a mock and must never be uploaded as a product-page image or App Review purchase screenshot.

## Private designed layout drafts

The first 18-layout treatment in `store-artwork-draft/rendered/review-gallery.html` and the earlier `store-artwork-redesign-v1/` treatment are superseded. The current private review treatment is `FactoryTools-AppStore-Assets-Review-2026-11-21/store-artwork-redesign-v2/`: 14 iPhone layouts (seven per language) plus `contact-sheet.jpg` and a reproducible local composition script. It uses a restrained graphite background, short localized benefit headlines, and a large direct Release Simulator capture. Unlike v1, it has no diagonal promotional band, decorative scale, or hardware mockup. The screenshot pixels are not retouched or replaced; the complete capture is proportionally scaled inside a rounded crop with a soft edge shadow. Layouts are opaque RGB JPEGs at 1206 × 2622. This is a private review draft, not approved or uploaded. The iPad layouts remain separate reference-only drafts because their connection state is a Simulator fixture, not proven physical pairing. All sample values are synthetic examples. Apple requires screenshots to represent the app accurately, even when marketing copy is included ([screenshot guideline 2.3.3](https://developer.apple.com/help/app-store/review/guideline-reference/2-3-3-screenshots/)).

## Listing references reviewed

Reviewed the current App Store listings for [現場コネクト](https://apps.apple.com/jp/app/%E7%8F%BE%E5%A0%B4%E3%82%B3%E3%83%8D%E3%82%AF%E3%83%88/id6801697815), [ものレボ実績](https://apps.apple.com/jp/app/%E3%82%82%E3%81%AE%E3%83%AC%E3%83%9C%E5%AE%9F%E7%B8%BE/id6834638616), [FMES](https://apps.apple.com/jp/app/fmes/id1583885648), and a [counter app listing](https://apps.apple.com/jp/app/%E3%82%AB%E3%82%A6%E3%83%B3%E3%83%88%E3%82%AB%E3%82%A6%E3%83%B3%E3%82%BF%E3%83%BC-%E8%A4%87%E6%95%B0-%E5%A4%9A%E6%A9%9F%E8%83%BD-%E9%9F%B3%E3%82%AB%E3%82%A6%E3%83%B3%E3%83%88-%E5%85%B1%E6%9C%89%E3%82%82/id6765985766?platform=tv). The review informed the task-first headline sequence and clearer separation between the real app capture and its surrounding promotional layout. No competitor artwork, screenshots, or copy is reused.

## Required capture sizes

| Platform | Required slot | Capture size to target | Notes |
|---|---|---:|---|
| iPhone | Dynamic Island, medium display | 1206 × 2622 portrait (current CI captures) | Apple also accepts 1179 × 2556; confirm the live slot before upload. |
| iPad | 13-inch display | 2064 × 2752 portrait | Apple also lists 2048 × 2732 for supported 13-inch models. |
| Apple Watch | Series 12 / Series 11 / Series 10 | 416 × 496 | If another Watch size is used, use the matching Apple-listed resolution consistently for Japanese and English. |

App icons are separate from these screenshots. Apple's current icon guidance uses a 1088 × 1088 watchOS design canvas, while Xcode's asset-catalog workflow documents generating platform variants from a single 1024 × 1024 source image. This project currently uses that single-image asset-catalog path, with opaque RGB PNGs for both the iPhone/iPad and Watch targets. Recheck the generated icon in the Xcode version used for archive; if switching to Icon Composer, use the current Watch design template instead of treating the screenshot dimensions or asset-catalog source size as the artwork canvas. References: [Apple app-icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Xcode asset-catalog icon workflow](https://developer.apple.com/documentation/xcode/configuring-your-app-icon?changes=_3), and [Icon Composer canvas guidance](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer?changes=l_2&language=objc).

Apple's October 5, 2026 announcement says apps submitted starting April 2027 need iPhone Duo screenshots. The current screenshot specification separately says screenshots are required starting then for apps using the iOS 27.1 SDK or later. Apple's September 9, 2026 submission notice sets the general iOS/iPadOS SDK minimum for that period at version 27, not 27.1. Treat Duo screenshots as required for any submission from April 2027 unless Apple updates its guidance. Prepare both portrait displays: 1398 × 2034 (outer) and 2007 × 2853 (inner). Confirm the live App Store Connect slots immediately before submission. References: [iPhone Duo submission announcement](https://developer.apple.com/news/?id=kkphp5qo), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), and [April 2027 SDK minimums](https://developer.apple.com/news/?id=k1mtkt1k).

## Product-page screenshot sequence

Keep the displayed feature state and access level accurate. The source captures are unaltered app-screen images; the separate private layout drafts place concise Japanese or English headlines around them. Avoid showing real workplace names, people, or production data, and do not claim behavior that has not been verified.

### iPhone

| Order | Capture | Japanese headline (layout draft) | English headline (layout draft) |
|---:|---|---|---|
| 1 | Industrial Dark home with Production Counter and target | 数える。目標まで、ひと目。 | Count production. / See your target. |
| 2 | Counter interaction showing Quick Add amount entry | まとめて入力。記録は正確に。 | Add a batch. / Keep the count moving. |
| 3 | Cycle Time with sample values | 1サイクルずつ、現場で計測。 | Measure each cycle. / Save the result. |
| 4 | Defect Counter and Defect Rate using a separate home-scoped sample session | 生産数と不良数を、同じ画面で。 | Track output and defects. / See the defect rate. |
| 5 | Basic counter history with sample events | カウント履歴を残す。CSVで書き出す。 | Keep a count history. / Export it as CSV. |
| 6 | Takt Time with sample values | 稼働時間と必要数から、タクトを計算。 | Calculate takt time. / Plan from your inputs. |
| 7 | The real Process Capability (Cp/Cpk) form and calculated result from the app | 規格と工程データから、Cp・Cpkを計算。 | Calculate Cp and Cpk. / From process data. |

### iPad

| Order | Capture | Japanese headline (layout draft) | English headline (layout draft) |
|---:|---|---|---|
| 1 | iPad counter dashboard and paired-iPhone controls (Simulator fixture; not a real pairing result) | iPadから、 / カウンター操作。 | Use the counter / from iPad. |
| 2 | Connection and pending-action state (Simulator fixture; not a real pairing result) | 連携状態と / 保留中の操作を表示。 | See connection / and pending actions. |

### Apple Watch

| Order | Capture | Japanese note (not overlaid) | English note (not overlaid) |
|---:|---|---|---|
| 1 | Production Counter detail with count, target, and primary +1 action | 手元で、生産数をカウント | Count production from your wrist |
| 2 | Cycle Time stopwatch with a paused one-unit sample ready to resume | サイクルタイムを手元で計測 | Measure Cycle Time from your wrist |
| 3 | Pro read-only Production Progress detail with count, target, and completion | Watchで生産進捗を確認 | Check production progress on Watch |
| — | Pending/offline command state is a future optional capture, only if it is visually clear and non-alarming | 接続後に操作を同期 | Commands sync when connected |

## Separate App Review purchase screenshot

Capture the actual signed iPhone Settings screen with the configured non-consumable product name, localized description, and Apple-provided display price. This is the IAP review asset; it is separate from product-page screenshots. Do not substitute a designed or screenshot-only mock for the real StoreKit purchase sheet. Verify the actual storefront display price and purchase behavior before accepting this App Review asset.

## Capture and upload checklist

- The superseded 2026-11-10 package and earlier CI artifact links are historical references only. Do not upload any image from them. Retrieve a fresh artifact after the current workflow completes, and inspect each included localized image against the current release UI and approved listing. The workflow artifact is the genuine, direct Release Simulator source set. The separate private design draft can be a product-page image candidate only after the publisher confirms every headline and visual against the submitted app. A signed build is not a screenshot-format requirement.
- Every screenshot area in a designed product-page image must use a genuine current app capture. The `iphone-pro-purchase-ja.jpg` and `iphone-pro-purchase-en.jpg` screenshot-only mock previews are not valid product-page assets and must not be used; the separate App Review purchase image must show the real configured StoreKit purchase screen.
- Keep synthetic home, counter, history, defect, and calculator data in the captured Release build.
- Use the prepared Apple-listed iPhone, iPad, and Watch dimensions; recapture from CI or a simulator/device only if the release UI changes.
- For submissions starting April 2027, include iPhone Duo outer- and inner-display screenshots in addition to the currently required Dynamic Island and 13-inch iPad screenshots.
- Capture each language directly from the app's Japanese or English UI. If using a designed layout, add only accurate localized headlines and decorative framing around the genuine capture; do not invent or retouch UI.
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
