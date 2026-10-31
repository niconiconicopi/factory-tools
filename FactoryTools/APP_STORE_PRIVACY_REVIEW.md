# App Store privacy review draft

This source-based review prepares the App Store Connect privacy questionnaire. It is not a publisher attestation. Recheck it against the final app binary and all included Apple frameworks before publishing; App Store Connect responses apply across every supported platform.

## Current source findings

- The app has no login, developer-operated backend, external API, app-operated cloud storage or sync, advertising, analytics, tracking, or third-party SDK integration.
- SwiftData explicitly disables CloudKit. Production records, calculations, preferences, and home configuration are stored in the app's local store.
- SwiftData stores its default on-disk store in Application Support. The app does not mark that user data as excluded from backup. Apple says device backups may include downloaded app data and Watch backups are included with iPhone backups; this is Apple-managed system backup, not app-operated CloudKit sync. The app cannot inspect or manage those backup copies.
- A pairing secret is stored in Keychain. Watch and iPad command queues are stored locally on their respective devices.
- The app can send counter commands and one-unit Cycle Time samples between the user's paired iPhone and Apple Watch. The iPhone also sends counter catalog data and, while Pro is active, read-only Production Progress snapshots containing the selected home name, count, and target. The paired iPad receives counter commands and required session snapshots over the local peer connection. No project endpoint sends these records to a developer-operated or third-party server.
- User-selected JSON backup and CSV export files can be saved or shared to a location chosen in the system share sheet. The app does not control the destination selected by the user.
- Factory Tools Pro uses Apple's StoreKit non-consumable purchase. Apple's App Privacy guidance says payment information entered into Apple's payment service outside the app and not available to the developer is not collected by the developer. The app checks the signed entitlement locally and has no server or analytics destination for transaction data. Reconfirm the final StoreKit implementation and App Store privacy definitions before the publisher attests.
- `PrivacyInfo.xcprivacy` declares the System Boot Time accessed API with reason `35F9.1`, used by the local Cycle Time stopwatch. It does not declare collected data types.

## Proposed App Store Connect response

**Provisional answer: “No, we do not collect data from this app.”** The app does not transmit or retain production data on a developer-operated or third-party service; Watch/iPad transfers go directly to the user's own paired devices. Apple's OS may include app data in backups when the user enables device backup. Apple defines collection around data made accessible to the developer or third-party partners beyond real-time request servicing, and says developers are not responsible for disclosing data collected by Apple. Treat Apple-managed system backup separately from app collection, and have the publisher verify this interpretation against the final release binary and current App Privacy rules before attesting.

If any future version adds a server, analytics or advertising SDK, account, remote support diagnostics, cloud sync, or another data recipient, redo this review and update the App Store Connect answers before release.

## Separate required submission items

- A publicly accessible Privacy Policy URL is required for an iOS app. The bilingual draft is in [`PRIVACY_POLICY_DRAFT.md`](PRIVACY_POLICY_DRAFT.md); it must be reviewed, completed with publisher contact details, published, and entered in App Store Connect.
- Apple's App Store Connect privacy workflow requires a publisher account role that can edit app privacy. The publisher must save and publish the final answers and inspect the product page preview.
- Review the privacy manifest and the final build's linked frameworks as part of the Apple-platform release archive. The Windows static verifier does not create an Apple privacy report.

## References

- [Apple: App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple: Manage app privacy in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Apple: App Privacy Details and the definition of “collect”](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple: iCloud Backup contents](https://support.apple.com/en-us/108770)
- [Apple: Apple Watch backups](https://support.apple.com/en-us/108358)
- [Factory Tools source-based privacy data inventory](PRIVACY_DATA_INVENTORY.md)
