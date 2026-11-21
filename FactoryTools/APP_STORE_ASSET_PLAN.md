# App Store screenshot and purchase-review asset plan

**Status (2026-11-21):** native run [44905957176](https://github.com/niconiconicopi/factory-tools/actions/runs/44905957176) passed on commit `cb16a8b`: source checks, iPhone and iPad app-hosted XCTest, 14 bilingual iPhone screenshots (seven per language), six S/M/L card images, four bilingual iPad screenshots, and the required screenshot gate. Watch/archive run [44905957182](https://github.com/niconiconicopi/factory-tools/actions/runs/44905957182) also passed on `cb16a8b`: shared Core tests, Watch Debug/Release builds, all six localized Watch captures and OCR checks, the required-six-image gate, and the unsigned iOS/iPad archive. Captures are under `FactoryTools-AppStore-Assets-Review-2026-11-21/latest-run-44905957176/` and `.../latest-run-44905957182/`. They use in-memory Simulator sample fixtures and have not been uploaded to App Store Connect.

**Important limitations:** iPad connected/reconnecting states in the images are Simulator fixtures and do not prove an actual paired-device connection. The screenshots are not physical-device validation. The separate App Review screenshot for the real StoreKit purchase panel is not captured; it requires the App Store Connect product and a signed build.

Capture method: launch the actual Release Simulator app, enter screenshot-only sample-data mode, take the screen directly with `xcrun simctl io screenshot`, then use `sips` only to convert the PNG capture to JPEG. Synthetic values exist only inside the app's screenshot fixture; they are not real production records. The connected/offline iPad state is also a fixture. Do not present it as a physical-device test.

Apple requires at least one iPhone Dynamic Island medium-display screenshot, at least one 13-inch iPad screenshot when iPadOS is supported, and at least one Apple Watch screenshot when a Watch app is included. App Store Connect accepts up to 10 screenshots per device size, without alpha transparency. The current candidates meet the required base dimensions, but still need publisher review and confirmation against the actual App Store Connect upload slots. This does not replace physical-device, signed-distribution, or purchase testing.

**Historical note:** the 18-image package captured on 2026-11-10 is superseded and must not be uploaded. It predates the approved Japanese display name `現場ギア`; its Japanese home screenshot visibly says `Factory Tools`. Preliminary visual reviews from 2026-11-08 and 2026-11-10 are historical only. The screenshot-only Pro purchase preview is a mock and must never be uploaded as a product-page image or App Review purchase screenshot.

## Private designed layout drafts

The first 18-layout treatment and v1–v3 are superseded. The current private iPhone review treatment is `FactoryTools-AppStore-Assets-Review-2026-11-21/store-artwork-redesign-v4/`: 14 layouts (seven per language), a contact sheet, and a reproducible local composition script. It uses a warm light field, dark app-screen panels, an orange brand accent, and short localized benefit headlines. The first headline now explicitly says that production count and remaining units are visible at a glance, matching the on-screen count `286 / 300` and remaining `14`. Each panel uses a genuine Release Simulator screen and trims only trailing empty screen area; visible app UI pixels are not painted over or replaced. Layouts are opaque RGB JPEGs at 1206 × 2622. This remains a private, unapproved draft. `STORE_REVIEW_GALLERY_JA.html` shows source captures and layout candidates; the new `STORE_LISTING_REVIEW_JA.html` puts the exact bilingual listing text, Pro offer, price, and the matching seven-image sequence for each locale together. Both are local review aids, not App Store screenshots or published pages. The separate iPad layouts remain reference-only because their connection state is a Simulator fixture. All displayed values are synthetic examples. Apple permits text/image overlays while requiring the images to show the app in use and accurately represent the product ([screenshot guideline 2.3.3](https://developer.apple.com/help/app-store/review/guideline-reference/2-3-3-screenshots/)).

## Listing references reviewed

Reviewed the live App Store listing content for [Counter-i](https://apps.apple.com/us/app/counter-i/id6754535857), [コータイム](https://apps.apple.com/jp/app/%E3%82%B3%E3%83%BC%E3%82%BF%E3%82%A4%E3%83%A0-%E4%BA%A4%E4%BB%A3%E5%8B%A4%E5%8B%99-%E3%82%B7%E3%83%95%E3%83%88%E3%82%AB%E3%83%AC%E3%83%B3%E3%83%80%E3%83%BC/id6804745947), [現場コネクト](https://apps.apple.com/jp/app/%E7%8F%BE%E5%A0%B4%E3%82%B3%E3%83%8D%E3%82%AF%E3%83%88/id6801697815), and [Nexdue](https://apps.apple.com/jp/app/nexdue/id6779507062). A screenshot-sequence reference for [Counter+](https://mwm.ai/apps/counter/478557426) lists the primary counter, settings, multiple counters, history, and themes. Image search also exposed the published screenshot sequence for [Counter 1](https://mwm.ai/apps/counter-1/1125810080): it starts with the single-count screen and large `+1` control, followed by display/settings and confirmation examples. The [Counter Tally Count](https://mwm.ai/apps/counter-tally-count/1144352844) screenshot preview shows a multi-counter list with color-coded rows and counts. These are generic-counter references rather than manufacturing competitors; they support a direct, legible product screen and a sequence that demonstrates distinct workflows. Counter-i's listing groups count entry, run history, reports, and production analysis; Nexdue focuses its offer on manufacturing schedules, one-time purchase, and repurposing older iPads. V4 uses its own real production-counter home screen and copy, without reusing competitor screenshots, art, or wording. The comparison used public screenshot previews and their descriptions; full-resolution competitor assets were not downloaded. V4 remains a private, unapproved draft; final visual selection remains open.

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
| 1 | Industrial Dark home with Production Counter showing 286 / 300 and 14 remaining | 生産数と残数を、ひと目で。 | See output at a glance. / Know what's left. |
| 2 | Counter interaction with the Quick Add amount-entry sheet | まとめて数えて、すぐ記録。 | Add a batch. / Keep the count moving. |
| 3 | Cycle Time form with stopwatch and calculated seconds per unit | 1サイクルを、正確に計測。 | Measure each cycle. / Save the result. |
| 4 | Defect Counter and Defect Rate using a separate home-scoped sample session | 生産数と不良数を同時に。 | Track output and defects. / See the defect rate. |
| 5 | Basic counter history with sample events | カウントの変化を記録。 | Keep a count history. / Export it as CSV. |
| 6 | Takt Time form and result calculated from net time and demand | 必要数から、タクトを計算。 | Calculate takt time. / Plan from your inputs. |
| 7 | The real Process Capability (Cp/Cpk) form and calculated result from the app | Cp・Cpkを、現場で計算。 | Calculate Cp and Cpk. / From process data. |

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
