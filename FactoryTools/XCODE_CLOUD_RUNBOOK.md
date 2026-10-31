# Xcode Cloud setup and cost boundary

This plan provides a no-extra-service-cost path for native Apple builds after the publisher is ready to complete Apple enrollment. It does not claim that Xcode Cloud is configured or that any Apple build has passed.

## Included usage and cost control

- Apple Developer Program membership includes **25 Xcode Cloud compute hours per month**. This allowance is part of membership; do not buy an additional Xcode Cloud subscription or add a paid build service.
- Apple offers paid Xcode Cloud tiers above the included allowance. Check usage in App Store Connect and stop starting optional builds as the allowance gets close. Never enable an additional tier as a workaround.
- The membership itself remains the last paid preparation step. This document does not authorize enrollment, a subscription, or a remote account connection.

Apple's current references: [Membership inclusions](https://developer.apple.com/programs/whats-included/), [Xcode Cloud plans](https://developer.apple.com/xcode-cloud/), and [Xcode Cloud in App Store Connect](https://developer.apple.com/help/app-store-connect/xcode-cloud/).

## Prerequisites Apple requires

Xcode Cloud needs an active Apple Developer Program membership, an App Store Connect app record, a unique app Bundle ID, and a remote Git repository. Apple requires Xcode to create the first Xcode Cloud product/workflow and connect the source repository. The App Store Connect API can create a workflow only for an existing Xcode Cloud product; its `ciProducts` API offers listing, reading, and deletion, but no product-creation endpoint. The API therefore does not remove the initial Xcode setup requirement. After the initial product/workflow exists, workflows and build reports can also be managed through App Store Connect. This project currently has no publisher Bundle ID, app record, local/remote Git repository, or Xcode Cloud workflow. The workspace root also contains a separate audio project; the prepared root `.gitignore` excludes it, signing credentials, generated Xcode output, and unreviewed publisher-page candidates from a future repository.

The first workflow therefore still requires temporary access to a compatible Mac running Xcode. Once it is connected, routine builds and tests can run in Apple's cloud without keeping a Mac available. This is a setup gate, not a reason to rent a paid Mac service.

See Apple's [Xcode Cloud project requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud), [first workflow guide](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [Xcode Cloud products API](https://developer.apple.com/documentation/appstoreconnectapi/products), [workflow creation API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-ciworkflows), and [GitHub connection guide](https://developer.apple.com/documentation/xcode/connecting-xcode-cloud-to-github). The approved public repository is [niconiconicopi/factory-tools](https://github.com/niconiconicopi/factory-tools); Xcode Cloud itself is not configured and still needs a compatible Mac/Xcode setup.

## Workflow plan for Factory Tools

1. After enrollment is deliberately completed, choose a publisher-owned Bundle ID, create the App Store Connect app record, run `python Scripts/audit_source_hygiene.py`, and put the reviewed project in a remote Git repository with access granted only to the Xcode Cloud integration. The scan checks for common private-key/token patterns without printing matched values; the root `.gitignore` is only a safeguard and does not replace this scan.
2. On Xcode, create the first Xcode Cloud workflow for the `FactoryTools` app. Run the shared `FactoryTools` scheme's Test action on an iOS Simulator; its testable is the app-hosted `FactoryToolsTests` bundle. Run the separate `FactoryToolsCore` scheme's Test action on macOS for the app-independent `FactoryToolsCoreTests` bundle.
3. Add an iOS Simulator build for the `FactoryTools` scheme and a watchOS Simulator build for the `FactoryToolsWatch` scheme. The current Watch scheme has no test bundle, so it provides compile/build evidence only; app-side Watch receiver and shared Watch command/outbox behavior are covered by the app/Core test schemes, while paired-device behavior remains a signed-build release check. Keep archive and distribution actions disabled until the publisher's Bundle ID, Team ID, product metadata, and policy URLs are finalized.
4. Run the existing Windows checks before pushing changes. Xcode Cloud should add native compile/XCTest evidence; it does not replace App Store Connect review or real paired-device behavior checks.
5. Watch the included monthly compute-hour usage. Retain the build log and `.xcresult` evidence and download any release archive before its cloud artifact retention expires.

Apple documents Xcode Cloud actions for build, analyze, test, and archive in its [workflow action guide](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions). Cloud build artifacts are available for a limited retention period, so archive the final build evidence outside the workflow.

## Remaining limits

- This Windows workspace cannot create the initial Xcode Cloud connection, access signing credentials, run Apple's simulators, or produce a signed archive.
- Xcode Cloud can compile and run simulator tests, but this plan does not claim it verifies local WatchConnectivity, iPad peer networking, screen-capture redaction, App Store purchase behavior, or production hardware behavior.
- An Xcode Cloud build uses Apple's current Xcode/macOS environment. Recheck Apple's accepted SDK versions when the release archive is created.

## Mac-free native build and simulator checks

GitHub currently provides standard macOS runners free and without a minute limit for **public** repositories. A public repository exposes this source, product documents, tests, and icons; use it only after the publisher has approved that exposure. The workflow also supports a private repository without exposing the source: GitHub Free currently includes USD 12 of monthly compute usage, shared across eligible private runners and cloud sandbox usage; the standard macOS runner is USD 0.062 per minute, so an otherwise unused allowance covers about 193 rounded-up macOS runner minutes. Verify the account's current plan and remaining allowance first. To prevent any charge, either have no valid payment method on the account (GitHub blocks runner use after included compute is exhausted) or configure a hard-stop Actions budget before use. The workflow does not upload build artifacts or use caches. Its private mode is disabled by default and runs only after a manual dispatch, a checked confirmation, and the repository variable `FACTORYTOOLS_PRIVATE_MACOS_CI=enabled` are all present. Set that variable only after the no-overage guard is verified. See GitHub's [included usage](https://docs.github.com/en/billing/reference/product-usage-included), [macOS runner rates](https://docs.github.com/en/billing/reference/actions-runner-pricing), [Actions billing and no-payment-method behavior](https://docs.github.com/en/billing/concepts/product-billing/github-actions), and [hard-stop budget setup](https://docs.github.com/en/billing/how-tos/set-up-budgets).

The local [Apple native checks workflow](../.github/workflows/apple-native-checks.yml) runs source checks, iPhone Simulator XCTest, shared Core XCTest, and a Watch Simulator build. The connected public repository runs it on pushes, pull requests, or manual dispatch. Private repositories skip automatic push/pull-request runs and need the explicit, guarded manual dispatch described above. Current Mac-run evidence is tracked in the repository's [Actions history](https://github.com/niconiconicopi/factory-tools/actions).

This gives the project a Mac-free way to obtain native compile and simulator-test evidence. The private-repository route keeps source private and protects the account from charges only when the billing guard is configured as described above; the workflow cannot inspect that account-level setting. The public route is unlimited and free for standard runners, but source exposure is irreversible for existing forks and clones. This workflow does not sign or submit the app, create an App Store Connect record, or replace real paired-device checks. Apple's separate Xcode Cloud path still requires an initial Xcode setup on a Mac.

References: GitHub's [runner cost and availability](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [Actions billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions), plus Apple's [first Xcode Cloud workflow requirements](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow).
