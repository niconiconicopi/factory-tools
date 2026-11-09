# Factory Tools privacy data inventory

This inventory describes the current source implementation to prepare the publisher's privacy review. It is not an App Store Connect submission; verify it against the final release build before publishing.

## Data stored on devices

| Data | Location | Purpose |
|---|---|---|
| Home names, tool cards, app settings, counter sessions and events, Cycle Time samples, OEE runs, processed command receipts | iPhone/iPad SwiftData store | Configure the toolbox and retain local production history |
| Pairing secret | iPhone/iPad Keychain | Authenticate an explicitly paired local iPad connection |
| Watch timer state and pending Watch commands | Watch app local file store | Preserve an active Cycle Time measurement and queued counter/Cycle Time records across relaunches until acknowledgement |
| Pending iPad commands and peer-scoped queue metadata | iPad app local file store | Preserve offline commands and prevent commands from being redirected when pairing changes |
| App data may be included in iPhone/iPad device backups; Apple Watch backup is included with paired iPhone backup | Apple-managed iCloud or computer backup, when enabled by the device owner | OS-managed device recovery; Factory Tools does not access or manage these backups |
| Backup JSON and history CSV | User-selected file location | User-initiated export or transfer; JSON can also be imported additively |

JSON and CSV exports cover persisted model/history data; neither includes pending Watch/iPad delivery queues or an active Watch Cycle Time timer. Support and privacy copy should tell users to finish syncing before removing or reinstalling an app.

The app model container disables CloudKit. The app has no app-operated cloud storage or sync, account, advertising, analytics, tracking, external API, or third-party SDK integration in the current project. SwiftData uses the app's Application Support storage by default, which Apple documents as eligible for device backup. The source does not set `isExcludedFromBackup`; therefore disclose Apple-managed backups according to the user's device backup settings. [Apple file-system guidance](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) and [iCloud Backup contents](https://support.apple.com/en-us/108770).

The iPad pairing code is stored in the iOS Keychain as a `WhenUnlockedThisDeviceOnly` item. Apple Developer Support has described Keychain survival after app removal as undocumented behavior; the privacy policy and support draft therefore say it **may** remain and direct users to remove the pairing code in Settings before deleting the app. See [Apple Developer Forums: Keychain items after uninstall](https://developer.apple.com/forums/thread/36442).

Factory Tools Pro uses Apple's StoreKit non-consumable purchase. StoreKit returns signed transaction/entitlement information to the app for on-device access control. The project does not collect or send purchase information to a developer-operated service, and it does not access payment-card details or Apple Account credentials. Recheck this description against the final StoreKit product and archived build.

## Device-to-device communication

- Apple Watch sends counter commands and one-unit Cycle Time samples to the paired iPhone through WatchConnectivity. The iPhone returns acknowledgements, supported counter/Cycle Time catalog data, and—while Pro is active—read-only Production Progress snapshots for Watch-enabled cards. These snapshots contain the selected home name, production count, and target count.
- A user may explicitly pair an iPad with an iPhone using a shared pairing code. The devices exchange counter commands, acknowledgements, and supported session snapshots over the local peer connection; the pairing secret is used to authenticate the connection.
- These transfers stay between the user's paired Apple devices. No project endpoint sends this data to a developer-operated or third-party server.

## System APIs and privacy manifest

The universal iPhone/iPad app and the Watch app use `ContinuousClock` for their local Cycle Time stopwatches. Each app bundle includes `PrivacyInfo.xcprivacy` declaring the System Boot Time accessed API with reason `35F9.1`. The Watch sends the resulting elapsed Cycle Time interval to its paired iPhone as an in-app measurement; it does not send the raw system boot time. The project verifier checks the manifest syntax, both target memberships, and the source's known required-reason API use.

The app also declares the Bonjour service and localized local-network permission text required for optional iPad pairing. The user initiates pairing and can remove the pairing code in Settings.

## Release review inputs

- Confirm the final release build still matches this inventory.
- Complete the publisher's App Store Connect privacy questionnaire using the source-based [APP_STORE_PRIVACY_REVIEW.md](APP_STORE_PRIVACY_REVIEW.md); confirm the provisional answer against the final binary and publish it in App Store Connect.
- Complete and publish [PRIVACY_POLICY_DRAFT.md](PRIVACY_POLICY_DRAFT.md), replace its publisher placeholders, provide the required public URL, and set `FACTORYTOOLS_PRIVACY_POLICY_URL`; Settings already exposes the localized in-app link when this value is a valid HTTPS URL.
- Review the local-network permission text and the privacy policy before distribution.
