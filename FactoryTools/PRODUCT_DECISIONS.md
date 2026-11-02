# Factory Tools product decisions

## Approved product direction

- Factory Tools has a practical Free edition and one Factory Tools Pro purchase.
- Pro is a single non-consumable, lifetime purchase. No subscription or separate tool, theme, setting, or Watch purchases.
- A verified Pro purchase unlocks every feature assigned to Pro. Future Pro features are included for existing buyers without additional charges.
- No account, external API, paid SDK, paid cloud, usage-billed service, or other paid development dependency. This is separate from the customer-facing sale price.
- App Store publication has a separate Apple distribution requirement: as checked 2026-10-31, Apple lists Developer Program membership at USD 99 per membership year (or local-currency equivalent). This is not a development service or app dependency, but it is a publisher cost that must be accepted before release. No enrollment or payment is authorized by this product decision. See [Apple Developer Program membership](https://developer.apple.com/jp/programs/enroll/).
- Japanese and English are supported. Stable tool and feature IDs are language-independent.
- The iPhone app's Japanese/English selection also controls the Watch companion's interface; System mode follows the Watch's current locale.
- Version 1 distribution scope is iPhone, iPad, and the paired Apple Watch companion. Apple can automatically make compatible iPhone/iPad apps available on Apple silicon Macs and Apple Vision Pro; keep those two compatibility storefronts disabled for Version 1 until separately tested and approved. Revisit them as a later platform decision.
- Local production data remains usable without a purchase or online account.
- Version 1 Apple Watch uses a compact Watch-native layout. It does not mirror iPhone S/M/L card sizes or the iPhone dashboard's cross-tool arrangement; corresponding cards keep their relative order within Watch's counter and progress sections. No separate Watch card-size controls are provided.

## Approved Version 1 Free / Pro boundary

The publisher approved the Version 1 boundary below on 2026-10-31. The table records the corresponding current build assignments. Access remains centralized in the registries so future product decisions can be changed without adding separate purchase states. A feature is gated only when implemented and assigned to its registry entry.

| Current Free assignment | Current Factory Tools Pro assignment |
|---|---|
| Production Counter, Cycle Time, Takt Time, Box Calculator, Unit Converter | Production Progress and OEE Calculator |
| Basic Defect Counter and Defect Rate | Additional home profiles and advanced dashboard customization |
| Basic custom home, card sizing and ordering, Industrial Dark | Detailed history charts, period comparisons, and analysis |
| Basic history review, local backup/restore, and data export | Detailed defect analysis, downtime, tool life, Cp/Cpk, advanced QC, tolerance and machining-condition calculations |
| Basic Apple Watch counter controls and Cycle Time capture; iPad counter controls | Read-only Production Progress on Apple Watch; advanced Watch tools, settings and notifications |
| Japanese and English | Pro themes, detailed warnings, complex shifts, calculation options, logs, precision and rounding controls |

The table and the Version 1 list below are the approved commercial boundary for the first release. Keep Industrial Dark, the basic Defect Counter and Defect Rate, basic history/export, basic Watch and iPad controls, and the listed basic tools free. Production Progress, OEE, additional homes, detailed analysis, specialist tools, advanced Watch features, and future Pro themes belong to the single Pro purchase.

### Confirmed Version 1 boundary

Approved: use the current Registry mapping for the first release, with the following plain-language limits:

- **Free:** Production Counter, Cycle Time, Takt Time, Box Calculator, Unit Converter, basic Defect Counter and Defect Rate; one home with card ordering/sizing; Industrial Dark; basic event history, backup/restore and CSV export; basic Watch counter and Cycle Time capture; iPad counter controls; Japanese and English.
- **Pro:** the standalone Production Progress card and OEE Calculator; additional homes and advanced dashboard customization; detailed charts, period comparisons and analysis; specialist tools and advanced settings; future Pro themes and advanced Watch features.

This keeps the core count, timing, calculation, basic defect, history and companion workflows useful without payment. The counter itself shows target/progress, while the separate progress dashboard and OEE analysis are Pro. Basic defect capture, basic history and export remain free; detailed defect categories and analysis, charts, and period comparisons are Pro. Industrial Dark is free; future Pro themes are included in the same purchase. Apply this boundary consistently to app copy, store listings, and review screenshots.

## Sale price and store setup

- Confirmed base storefront and price: **Japan (JP), JPY ¥980**. Configure this in App Store Connect after enrollment, then review Apple's generated prices for all selected territories and the signed purchase sheet. Other storefront prices may be adjusted independently. See Apple's [IAP pricing workflow](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase).
- Initial App Store availability: **all countries and regions where Apple permits App Store distribution at launch**, for both the app and Factory Tools Pro. The publisher chose to include English-supported markets as well as Japan; operationally, configure all currently available App Store territories, subject to each territory's availability and legal requirements. Use English as the primary App Store metadata language and Japanese as a localization so English copy is the fallback outside Japanese storefronts. Keep Japan as the base storefront at JPY ¥980; Apple may generate local prices for other territories, which must be reviewed before release. Do not automatically expand into newly added territories without a compliance and price review.
- App Store primary category: **Business**, matching the app's manufacturing operations and shop-floor workflow focus. Do not add a secondary category for Version 1.

- Japan customer sale price: **JPY ¥980 is the confirmed launch price decision**. Apple's official pricing guidance explicitly gives ¥980 as an example of a custom Japan storefront price. The publisher still needs to configure it in App Store Connect and confirm the final purchase sheet displays the intended price. The local preflight only checks input syntax and currency format. See [Apple's Japan ¥980 custom-price example](https://developer.apple.com/jp/videos/play/tech-talks/110364/) and [IAP pricing workflow](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase).
- Family Sharing: **disabled for Version 1**. The Pro purchase follows the buyer's Apple Account across that buyer's devices, including iPhone, iPad, and Watch, so family sharing is not needed for the purchaser's own devices. If it were enabled, it would extend Pro to up to five other family members, and the developer could not set a lower share count; Apple manages the family group. Apple says Family Sharing cannot be turned off for an IAP after it has been enabled. Keep the App Store Connect product setting off. See [Apple's Family Sharing setup guidance](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/) and [StoreKit support guidance](https://developer.apple.com/documentation/storekit/supporting-family-sharing-in-your-app).
- The local entitlement policy accepts only direct purchaser ownership for Version 1. A family-shared StoreKit entitlement does not grant Pro; keep this defense alongside the required App Store Connect Family Sharing-off setting.
- Product count: one non-consumable Factory Tools Pro item.
- Product ID candidate: **`factorytools.pro.lifetime`**. Keep this exact ID in the project and App Store Connect; confirm it is unused in the app before creating the non-consumable, because a saved product ID cannot be changed.
- StoreKit 2 verifies the entitlement locally, observes transactions, and offers Restore Purchases. No third-party billing SDK or entitlement server.
- The shared `FactoryTools` scheme uses `Resources/FactoryToolsPro.storekit` for Debug Run testing. It contains only the approved non-consumable, Family Sharing off, Japanese and English product text, and a ¥980 Japan test display price. Apple's local StoreKit configuration is test data; its price is not connected to the App Store Connect price. The Release Archive action does not select this file, and the actual product and price still need App Store Connect setup and verification.
- If the product is not configured or available, Free remains usable and no Pro entitlement is granted.

## Access implementation

Tool access belongs in Tool Registry metadata. Other feature access belongs in the shared Feature Access Registry. Screens, persistence services, and companion command handling ask those registries rather than embedding purchase decisions. OEE run creation checks the registry in its persistence service as well as hiding the Pro tool from Free users. `isPro` is the single app-wide entitlement state. Do not track purchases per tool, theme, or setting.

If a Free user imports a backup containing several homes, the import keeps every record and makes the backup's first ordered home the active Free home. Previously stored homes and additional imported homes remain saved and locked until Pro is active. This preserves basic backup restore without silently deleting customer data or granting access to multiple homes.

The App Store product description remains a draft until the included Pro features and final listing copy are reviewed against this approved boundary. The Japan sale-price decision is fixed at ¥980; App Store Connect configuration and purchase-sheet verification remain release tasks. Future Pro features are part of the same lifetime purchase.

