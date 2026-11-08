# Factory Tools Apple Release Runbook

This runbook is for the Apple-platform verification and archive gates. It does not replace App Store Connect review, device testing, or publisher-owned release values. The current Windows workspace cannot execute these commands. The public GitHub Actions workflow can run a manually confirmed signed upload without a personal Mac after the publisher values and API key are configured; see [APPLE_GITHUB_RELEASE_SETUP.md](APPLE_GITHUB_RELEASE_SETUP.md). The optional Xcode Cloud route and its limits are documented in [XCODE_CLOUD_RUNBOOK.md](XCODE_CLOUD_RUNBOOK.md).

Enrollment in the paid Apple Developer Program is intentionally the final paid preparation step, after no-cost implementation, documentation, and source checks. It is not a prerequisite for those tasks. Team ID, App Store Connect setup, signed distribution, and TestFlight require enrollment and follow it; no paid enrollment or service is to be started during preparation.

## 1. Run source checks

From the repository root, run the Python checks documented in [README.md](README.md). Record their output separately from native test results.

## 2. Run native tests and platform builds

Use **Xcode 26 or later** with the iOS/iPadOS 26 and watchOS 26 SDKs for App Store uploads under Apple's requirements in force since April 28, 2026. Before archiving, recheck Apple's current minimum because SDK upload requirements change over time. If submission moves to April 2027 or later, plan for Xcode 27 or later with the iOS/iPadOS 27 and watchOS 27 SDKs; Apple's announced minimum then becomes SDK 27. The app already declares `UILaunchScreen` for that SDK generation. References: [current SDK upload requirement](https://developer.apple.com/news/upcoming-requirements/?id=04282026a), [April 2027 minimum](https://developer.apple.com/app-store/submitting/), and [launch screen requirement](https://developer.apple.com/documentation/technotes/tn3208-preparing-your-apps-launch-screen-to-meet-app-store-requirements).

Open `FactoryTools.xcodeproj` in the compatible Xcode installation, install an iOS Simulator runtime, then inspect available destinations:

```sh
xcodebuild -showdestinations -project FactoryTools.xcodeproj -scheme FactoryTools
```

Run the Core tests on macOS and the app tests on an available iPhone simulator. Replace `<iPhone simulator ID>` with an ID from the destination list.

```sh
xcodebuild test -project FactoryTools.xcodeproj -scheme FactoryToolsCore -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project FactoryTools.xcodeproj -scheme FactoryTools -destination 'platform=iOS Simulator,id=<iPhone simulator ID>' CODE_SIGNING_ALLOWED=NO
```

Build the iPhone/iPad and Watch schemes for their generic simulator platforms to catch target-specific compile and resource errors:

```sh
xcodebuild build -project FactoryTools.xcodeproj -scheme FactoryTools -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project FactoryTools.xcodeproj -scheme FactoryToolsWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Keep the `.xcresult` bundles for both test commands and the Xcode version/build number with the release evidence. The Watch scheme has no dedicated XCTest target; its source is compiled as a build dependency and its paired behavior needs a paired-device run.

The app now uses the eight-model `FactoryToolsSchemaV1` and its migration plan. Confirm `testVersionedSchemaV1DefinesAllPersistedModelsAndMigrationPlan` passes, then run `testPersistentStoreAddsHistoryAndReceiptModelsWithoutLosingExistingCounterData`. Before a later release changes a stored property or model inventory, add a versioned old-store fixture from the exact preceding release and verify that it opens through the planned migration without losing counts, events, homes, settings, or histories. The current five-model fixture uses today's model classes and is not a substitute for that release-to-release test.

## 3. Verify the release candidate on devices

On a signed candidate, verify the iPhone flow in [APP_REVIEW_NOTES_DRAFT.md](APP_REVIEW_NOTES_DRAFT.md), including first launch, Japanese/English switching, counter history and Undo, backup/export, and purchase/restore in the App Store sandbox.

For submissions starting April 2027, inspect the iPhone app on iPhone Duo with Xcode 27.1 or later and Device Hub across the device's poses and orientations. Check home/card layout, sheets, the counter controls, keyboard entry, and the iPhone-to-iPad pairing instructions. Capture the outer and inner display screenshots listed in [APP_STORE_ASSET_PLAN.md](APP_STORE_ASSET_PLAN.md). Apple announced that iPhone Duo screenshots are required for all app submissions beginning April 2027; the requirement is not limited to builds using a specific SDK.

Pair an Apple Watch and verify offline counter and Cycle Time capture, queue persistence after relaunch, acknowledgement recovery, reset confirmation, and language propagation after changing the iPhone setting. Pair an iPad through the local code flow and verify reconnection, queued commands, target changes, reset/Undo, and preservation of the active pairing when another connection is attempted. For iPad queue recovery, queue a command while disconnected, replace the iPhone pairing code, confirm that the command stays bound to the old code, restore the saved old code in iPhone Settings, re-enter it on iPad, and verify that the command applies once after acknowledgement.

While checking pairing on both devices, verify that the code and code-entry fields are obscured when the scene is inactive or screen capture/mirroring is active, then return to normal when the scene is active and capture ends. Also inspect the app-switcher preview after leaving Settings.

Record device models and OS versions, test account/sandbox outcomes (never credentials), steps and results for each path, and any failures. Do not treat simulator success as evidence of Watch/iPad local-network behavior.

## 4. Create and inspect the signed archive

After the publisher has supplied real values, configure these project settings: `FACTORYTOOLS_APP_BUNDLE_ID`, `DEVELOPMENT_TEAM`, `FACTORYTOOLS_PRIVACY_POLICY_URL`, `FACTORYTOOLS_SUPPORT_URL`, `FACTORYTOOLS_PRO_PRODUCT_ID`, `MARKETING_VERSION`, and `CURRENT_PROJECT_VERSION`. Set the public HTTPS URLs only after verifying they are published and reachable. Never commit signing credentials or private keys.

Archive the iOS app; this scheme embeds the Watch companion:

```sh
xcodebuild archive -project FactoryTools.xcodeproj -scheme FactoryTools -configuration Release -destination 'generic/platform=iOS' -archivePath '<archive path>' -allowProvisioningUpdates DEVELOPMENT_TEAM='<Apple team ID>' FACTORYTOOLS_APP_BUNDLE_ID='<publisher bundle ID>' FACTORYTOOLS_PRIVACY_POLICY_URL='<privacy URL>' FACTORYTOOLS_SUPPORT_URL='<support URL>' FACTORYTOOLS_PRO_PRODUCT_ID='<Pro product ID>' MARKETING_VERSION='<release version>' CURRENT_PROJECT_VERSION='<build number>'
```

Inspect the archive in Xcode Organizer, verify the iPhone and Watch bundle identifiers, signing, embedded Watch app, privacy manifest, icons, and generated `Info.plist` URLs/product ID. Validate upload and purchase/restore in the App Store sandbox/TestFlight before submitting.

## 5. Close App Store Connect decisions and evidence

- After all no-cost preparation is complete, the publisher may choose to enroll in the Apple Developer Program. Apple currently lists USD 99 per membership year (or local-currency equivalent); do not enroll or incur this cost during preparation. Enrollment is required before Team ID, App Store Connect, signing, TestFlight, and distribution steps. The Account Holder must accept the current Paid Apps Agreement and complete required tax and banking information before selling or sandbox-testing the Pro IAP. Set its tax category when configuring the product. See [Apple's App Store Connect workflow](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow), [agreement steps](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/), and [IAP setup workflow](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/).
- Configure App Store Connect with English as the primary metadata language and Japanese as a localization. The approved Version 1 launch covers all countries and regions where Apple permits distribution, including English-supported markets. Select all currently available territories for both the app and Pro IAP; do not opt into future territories until their rules and prices are reviewed. Set Japan (JP), JPY ¥980 as the base price, then review Apple-generated prices for each selected territory and verify the signed purchase sheet. See Apple's [metadata localization guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information), [app availability guidance](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store), [IAP availability guidance](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-availability-for-in-app-purchases), [IAP pricing workflow](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase), and [Japan ¥980 example](https://developer.apple.com/jp/videos/tech-talks/110364/).
- Keep platform availability within the approved Version 1 scope: iPhone, iPad, and paired Apple Watch. In App Store Connect, opt out of offering the compatible iOS/iPadOS app on Apple silicon Macs and Apple Vision Pro until those platforms receive a separate implementation and verification decision. Apple may make compatible iPhone/iPad apps available there automatically. See Apple's [Mac availability settings](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon/) and [visionOS compatibility guidance](https://developer.apple.com/documentation/visionos/determining-whether-to-bring-your-app-to-visionos).
- Before enabling EU availability, have the publisher assess and declare the account's EU Digital Services Act trader status in App Store Connect. Apple requires every developer to declare a status; if the publisher is a trader, Apple verifies and displays the required contact details on product pages in all 27 EU storefronts. An individual or organization can be a trader, so do not infer the answer from enrollment type. Confirm which contact fields Apple requires for that account and app; the publisher must supply and verify them. See Apple's [DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).
- Keep Family Sharing disabled on the Version 1 non-consumable, as approved in `PRODUCT_DECISIONS.md`; verify the App Store Connect product setting is off.
- In the signed app, verify that the Pro settings screen's Family Sharing disclosure matches the product's `isFamilyShareable` value after the App Store Connect setting is finalized.
- Create the single Factory Tools Pro non-consumable using the configured product ID and confirm its localized metadata and price.
- Publish the bilingual privacy and support pages with monitored publisher contact details; add App Review contact information.
- Upload genuine product-page screenshots that match the accepted Release UI and Apple's current dimensions; they may come from the hosted Release Simulator captures and do not need a signed build. Capture the separate IAP review image from the configured purchase screen after signed-build StoreKit verification. Include the required Watch icon and metadata.
- Complete age rating, privacy, export compliance, and App Review questions against the archive and the publisher's actual practices.

The release is complete only when the native build/tests, device checks, signed archive, App Store Connect configuration, and submission assets have direct recorded evidence. The Windows source verifier is supporting evidence only.
