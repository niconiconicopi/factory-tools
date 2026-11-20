# Factory Tools TestFlight Field Test Plan

**Purpose:** verify the signed iPhone app and its optional Apple Watch and iPad companions on real devices without requiring the publisher to own Apple hardware. This plan is for a pre-release quality test, not a substitute for App Review or an App Store release.

## What this makes possible

After Apple Developer enrollment, an App Store Connect app record, and a signed TestFlight upload are available, invite people who already have compatible devices. Apple currently supports up to 10,000 external testers per app. The first build added to an external group is sent to TestFlight App Review; an internal testing group must exist first. Testers install the free TestFlight app and can send feedback through it. Builds are available for up to 90 days. See [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers) and [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

TestFlight In-App Purchases use Apple's sandbox environment. Purchases made there do not charge testers and do not become production purchases when the app is released. This allows the ¥980 Pro purchase and restore flow to be exercised after the App Store Connect product is configured. See [Testing In-App Purchases in TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/) and [Apple's sandbox overview](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox).

## Tester groups

Invite only people who agree to test. Use a small email-invited group for the first build; do not create a public invitation link unless the publisher deliberately wants open enrollment.

| Group | Devices needed | Coverage |
|---|---|---|
| iPhone | Supported iPhone | Install/startup, Japanese and English, home/card setup, every basic tool, persistence, accessibility, and feedback |
| Watch companion | iPhone plus paired Apple Watch | Counter and Cycle Time actions, offline queue, reconnection, acknowledgement and duplicate prevention |
| iPad companion | iPhone and iPad on the same local network | Pairing, remote counter actions, offline queue, reconnection, and pairing-code changes with queued commands |

One tester may cover multiple groups. The publisher does not need to own any of these devices. If no suitable Watch or iPad tester is available, record those cases as **not tested**; do not infer device behavior from the iPhone Simulator.

## Copy-ready tester invitation

### Japanese

Factory ToolsのTestFlightテストに協力いただける方を募集しています。製造現場向けの生産カウンターと計算ツールを、実際のAppleデバイスで確認するための任意参加のテストです。

- iPhoneテストにはiOS 17以降のiPhoneが必要です。
- WatchテストはiPhoneとペアリングしたwatchOS 10以降のApple Watchがある場合に参加できます。
- iPadテストはiPadOS 17以降のiPadと、連携先のiPhoneがある場合に参加できます。
- すべての入力には架空のホーム名・品名・数量を使い、職場や顧客の実データは入力しないでください。
- Factory Tools Proの購入・復元確認はAppleのTestFlightサンドボックスで行うため、実際の請求は発生しません。
- 参加は任意です。テスト手順に沿って確認し、気づいた問題はTestFlightのフィードバックから送ってください。パスワード、認証コード、ペアリングコード、実際の生産記録は送らないでください。

参加に同意いただいた方へ、AppleのTestFlight招待をお送りします。利用できる端末の種類（iPhone、Apple Watch、iPad）を教えてください。

### English

We are looking for volunteers to test Factory Tools through TestFlight. This optional beta test checks a production counter and manufacturing calculators on real Apple devices.

- The iPhone test requires an iPhone running iOS 17 or later.
- The Watch test is available if you have an Apple Watch running watchOS 10 or later, paired with an iPhone.
- The iPad test is available if you have an iPad running iPadOS 17 or later and an iPhone to pair with.
- Use invented home names, item names, and quantities. Do not enter real workplace, customer, or production data.
- Factory Tools Pro purchase and restore checks use Apple's TestFlight sandbox and do not create a real charge.
- Participation is optional. Follow the checklist and send issues through TestFlight feedback. Do not send passwords, verification codes, pairing codes, or real production records.

After you agree to participate, we will send Apple's TestFlight invitation. Please tell us which devices you can test: iPhone, Apple Watch, and/or iPad.

## Prepare a test build

1. Complete the [release preflight](RELEASE_READINESS_AUDIT.md#release-preflight-evidence) and the signed-upload setup in [APPLE_GITHUB_RELEASE_SETUP.md](APPLE_GITHUB_RELEASE_SETUP.md). These require Apple Developer membership, publisher-owned contact and URL values, and App Store Connect credentials.
2. Run the normal iPhone/iPad workflow and Watch/archive workflow. The required screenshot gate must pass before the signed upload.
3. Configure the App Store Connect app record and the single non-consumable `factorytools.pro.lifetime` product, with Japan at ¥980 and Family Sharing off.
4. In App Store Connect, create an internal TestFlight group, then an external group. Add the uploaded build to the external group and submit the first build for TestFlight review. Supply accurate beta review notes and a monitored feedback contact.
5. Invite testers by email. Share the invitation only with people who accepted. Ask each person to install TestFlight and the beta build, use synthetic data, and report the result of each relevant section below.

## Instructions for every tester

Before starting, note the app version/build, device model, and OS version. Use invented home, product, target, and count values. Do not enter workplace, customer, employee, or production data. TestFlight feedback may include device and app details; review screenshots before sending them.

For each item, mark **Pass**, **Fail**, or **Not tested**. For a failure, include the step, what appeared, what was expected, and whether restarting the app changed the result. Do not send passwords, Apple verification codes, pairing secrets, or private workplace information.

## iPhone test checklist

### First launch and home

- [ ] Install and open the beta. Confirm the Industrial Dark home appears without a blank screen or indefinite loading state.
- [ ] Switch Japanese → English → Japanese. Confirm the screen language changes and previously created home/card data remains.
- [ ] Add Production Counter from the tool picker. Confirm the card appears on the selected home.
- [ ] Change the card through S, M, and L. Move it before and after another card; close and reopen the app and confirm its size and order remain.

### Counter behavior and persistence

- [ ] Tap +1 and −1. Confirm the displayed count changes by exactly one and never drops below zero.
- [ ] Use preset Quick Add and a custom amount. Confirm the exact new total.
- [ ] Use Undo once after an increment, decrement, and Quick Add. Confirm each reverses the latest eligible action exactly once.
- [ ] Set and change a target. Confirm the target and progress display update.
- [ ] Force-quit and reopen the app. Confirm count, target, card order/size, language, and history remain.
- [ ] Add another Production Counter card. Confirm cards intended to share a production session show the same count.

### Basic tools and Free/Pro access

- [ ] Enter a Cycle Time sample and confirm the per-unit result; use the stopwatch and save a sample if available in the build.
- [ ] Enter Takt Time demand, available time, and breaks; confirm the result and empty/incomplete-input guidance.
- [ ] Try Box Calculator and Unit Converter with a valid example and an invalid/incomplete example.
- [ ] Record production and defects on the same home. Confirm the defect count and defect-rate result update, including the zero-production state.
- [ ] As a Free tester, confirm tools/features marked Pro show the purchase route and do not write Pro-only data.
- [ ] If the Pro sandbox test is enabled for this build, purchase Factory Tools Pro. Confirm the sandbox purchase unlocks the agreed Pro features on iPhone. TestFlight sandbox purchases do not incur a real charge.
- [ ] On the same Apple Account, install the beta on another supported device and use **Restore Purchases**. Confirm the same lifetime Pro entitlement returns without asking you to purchase a second time.
- [ ] If your App Store storefront is outside Japan, record the displayed Pro price and storefront currency. Do not include payment details. The publisher separately verifies that Family Sharing is off in App Store Connect.

### Accessibility and recovery

- [ ] Increase system text size and use VoiceOver on the home-management actions and counter controls. Confirm labels identify the action and the affected home/tool.
- [ ] Temporarily make storage unavailable only if the tester can do so safely; otherwise mark startup-recovery checks **Not tested**. Never delete or alter personal data for this test.
- [ ] If a screen appears blank or incomplete, wait briefly, then leave and reopen that screen. Report whether it recovers and include the screenshot if it contains only synthetic data.

## Optional Apple Watch test checklist

Use a paired Watch included in the build. Record the Watch model and watchOS version.

- [ ] Open the Watch app and confirm the displayed language follows the iPhone setting.
- [ ] Use +1 and −1 online. Confirm the iPhone count and Watch count converge to the same value.
- [ ] Confirm basic counter controls and Cycle Time remain available without Pro. With Pro active and a Watch-enabled Production Progress card on the selected home, confirm the Watch shows the matching count and target as read-only information.
- [ ] Turn off connectivity or move out of range. Queue a count action; reconnect and confirm it is applied once, with no duplicate count.
- [ ] Start, pause/resume, and save a one-unit Cycle Time capture. Confirm it reaches iPhone history once; repeat while offline and confirm it arrives after reconnection.
- [ ] Restart the Watch app while an action is pending. Confirm it is retained or safely reports a recoverable error rather than disappearing silently.

## Optional iPad test checklist

Use an iPhone authority and iPad on the same local network. Allow the local-network prompt only when intentionally pairing these devices.

- [ ] Pair the iPad with the intended iPhone and confirm the dashboard shows the current count and target.
- [ ] Confirm basic iPad counter controls work without Pro. With Pro active on the same Apple Account, confirm the Pro-assigned iPad features shown by this build unlock after entitlement refresh or Restore Purchases.
- [ ] Send +1, −1, Quick Add, Undo, and target changes from iPad. Confirm the iPhone remains authoritative and both screens converge.
- [ ] Disconnect the local network, queue an action, then reconnect. Confirm it is acknowledged once and the pending count clears.
- [ ] Change or remove the pairing code while commands are pending. Confirm the app explains the consequence and preserves the old queue until the tester explicitly chooses how to handle it.
- [ ] Restart both apps and confirm pairing and unsent queue state recover as described.

## Triage and exit criteria

Collect feedback by build and device group. Treat data loss, duplicate counter events, a Pro entitlement granted to the wrong account, a stuck purchase state, or a pairing queue sent to the wrong iPhone as release-blocking. Fix confirmed issues, upload a new build, and rerun the affected checklist. Keep any section without a qualified tester visibly marked **not tested** in the release audit.

Use this minimal result record for each tester; a tester code can be a random label such as `T01` and must not identify the person.

| Tester code | App version/build | Device model and OS | Storefront / displayed Pro price | iPhone | Watch | iPad | Issue reference / notes |
|---|---|---|---|---|---|---|---|
|  |  |  |  | Pass / Fail / Not tested | Pass / Fail / Not tested | Pass / Fail / Not tested |  |

Record only the storefront and price shown by the App Store sheet, never the Apple Account, receipt, payment method, address, or other personal details. Attach screenshots only when they contain synthetic app data and no account or payment information.

TestFlight is a no-additional-charge route for these beta transactions, but Apple Developer membership and App Store Connect setup are still required. A TestFlight pass is not proof of App Review acceptance or a substitute for completing App Store Connect's privacy, export, age-rating, price, region, and Family Sharing settings.
