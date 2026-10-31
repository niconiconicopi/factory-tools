# Export compliance review draft

Source-based preparation for Apple's App Store Connect encryption questions. This document is not a legal classification or publisher attestation. Confirm it against the final archive and the regions where the publisher will distribute the app.

## Current cryptographic use

- The iPhone/iPad local peer transport configures TLS 1.2 with a pre-shared key and the standard `TLS_PSK_WITH_AES_256_GCM_SHA384` cipher suite using Apple's Network.framework and Security.framework APIs.
- The Apple Watch companion uses WatchConnectivity for the paired-device command flow.
- Pairing secrets are generated with `SecRandomCopyBytes` and stored in the Apple Keychain.
- CryptoKit SHA-256 fingerprints the pairing secret to scope local iPad command queues. It does not implement encryption.
- StoreKit verifies App Store signed purchase transactions for the local Pro entitlement; no transaction-signing or encryption algorithm is implemented by Factory Tools.
- There is no custom cipher, cryptographic implementation, third-party crypto library, or network security SDK in the project.

## App configuration

`FactoryTools/Info.plist` and the generated Watch app Info.plist set `ITSAppUsesNonExemptEncryption` to Boolean `false`. In Apple's terminology, this indicates the app either does not use encryption or uses only encryption exempt from export-documentation requirements; it does **not** mean the app has no encryption.

The source uses encryption through Apple's Network.framework TLS implementation; the app supplies a random 256-bit PSK and selects a standard cipher suite but does not implement TLS or the AES-GCM/SHA-384 algorithms. CryptoKit SHA-256 is used for a local queue fingerprint, not encryption. Apple's algorithm-specific table says an app whose encryption is limited to functionality within Apple's operating system requires no encryption documentation in App Store Connect. On the current source inventory, the `false` value is consistent with that exempt-only configuration, subject to confirmation against the final archive, linked frameworks, and Apple's actual questionnaire. It remains a publisher determination, not a legal classification made by this source audit.

The two decisions must not be conflated: Apple still requires an export-compliance determination for an app that uses encryption, even when its operating-system encryption requires no documentation. Separately, Apple says exempt encryption might require a U.S. year-end self-classification report. Whether Factory Tools falls within a reportable U.S. export category is not established by the current source review or by an App Store Connect no-documentation outcome; the publisher must determine that under the applicable U.S. export rules for the final app and distribution.

## Release check

- The publisher must answer the App Store Connect export-compliance questions for the final archived build and intended territories, including the TLS-PSK local iPad connection, Apple Keychain/Security/CryptoKit use, and StoreKit. Reconfirm that all encryption is limited to Apple operating-system functionality before retaining the current `false` declaration. If the final implementation, linked frameworks, or questionnaire results require documentation, complete Apple's review and set the resulting export-compliance code in the app as directed.
- Determine separately whether the publisher must file a U.S. annual self-classification report. Apple's guidance says some exempt-encryption cases may still have this requirement; BIS identifies reporting duties by the applicable export category and classification path. Record the publisher's determination and any applicable reporting owner/date before distribution.
- Recheck the `ITSAppUsesNonExemptEncryption` value against the final linked code and frameworks whenever cryptographic behavior or dependencies change.
- If any future build adds a non-exempt algorithm, custom crypto, or a third-party cryptography library, reassess this declaration before upload.

## Apple references

- [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [Determine and upload app encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)
- [Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
- [Append a TLS cipher suite](https://developer.apple.com/documentation/security/sec_protocol_options_append_tls_ciphersuite(_:_:))
- [Apple TLS cipher suite values](https://developer.apple.com/documentation/security/ssl-cipher-suite-values?language=objc)
- [ITSAppUsesNonExemptEncryption property](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
- [Encryption documentation by algorithm](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
- [U.S. BIS: Annual self-classification reports](https://www.bis.gov/learn-support/encryption-controls/annual-self-classification)
