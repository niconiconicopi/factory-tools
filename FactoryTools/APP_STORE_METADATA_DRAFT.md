# App Store listing draft

This is a bilingual metadata draft prepared from the current app source. It is not published metadata. Version 1 is intended for all App Store countries and regions where Apple permits distribution. Use English as the primary App Store metadata language and Japanese as a localization. Japan's Pro customer price is confirmed at ¥980 as the base storefront; Apple-generated prices in other territories must be reviewed before release. Confirm app and IAP availability, name availability, published support/privacy URLs, screenshots, and App Store Connect setup before submission.

Apple currently limits app names and subtitles to 30 characters, descriptions to 4,000 characters, promotional text to 170 characters, and keywords to 100 bytes per localization. The text below stays within those limits. Keyword byte counts use UTF-8.

Apple requires an App Store support link with current contact information so customers can reach the publisher. The release preflight requires the same publisher-owned HTTPS support URL that Settings exposes in the app. See Apple's [App Store review guidelines](https://developer.apple.com/app-store/review/) and [Support URL reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

## Shared setup

| Field | Draft / status |
|---|---|
| App name | Factory Tools (confirm availability in App Store Connect) |
| Primary language | English; add Japanese localization so English remains the fallback in other storefronts |
| SKU | `FACTORYTOOLS-IOS-001` (candidate; confirm it is unused in the publisher's App Store Connect account before creating the record; it cannot be changed later) |
| Copyright | Enter the publisher's copyright statement in the version information |
| Primary category | Business (selected for the manufacturing operations focus) |
| Age rating | Complete the App Store Connect age-rating questionnaire |
| Support URL | Publisher to provide; it must lead to a support page with current contact information |
| Privacy Policy URL | Publisher to publish and provide; required for iOS apps |
| Promotional text | Leave blank for first submission |
| Screenshots and previews | Capture from a release build on supported Apple devices |
| In-app purchase | One non-consumable Factory Tools Pro purchase; offer in all currently available territories where permitted; Japan base price is ¥980, then review generated local prices |
| Family Sharing | Disabled for Version 1; verify the setting is off in App Store Connect |

App Store Connect treats the SKU as an internal app identifier, accepts letters, numbers, hyphens, periods, and underscores (not as the first character), and does not allow changes after the app record is created. `FACTORYTOOLS-IOS-001` is a syntax-checked candidate; verify account uniqueness before saving the record. Age Rating is explicitly required; complete its questionnaire in App Store Connect. The app-information reference also lists Copyright as a version property, so enter the publisher's appropriate rights statement there. See Apple's [SKU requirements](https://developer.apple.com/help/glossary/sku/), [app information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information), and [required and editable properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties).

## Factory Tools Pro In-App Purchase

**Type:** Non-consumable (one-time purchase)  
**Reference name:** Factory Tools Pro  
**Product ID:** `factorytools.pro.lifetime` (candidate; use this exact value in App Store Connect)  
**Availability and price:** All currently available App Store territories where permitted; Japan base storefront, JPY ¥980 (confirmed); review Apple's generated local prices before release.  
**Family Sharing:** Disabled for Version 1; verify the App Store Connect setting is off.
**App Review Screenshot:** Capture the Pro purchase panel from the signed release build

Apple's current App Store Connect reference sets In-App Purchase display names to 2–30 characters, descriptions to 45 characters, and product IDs to at most 100 supported characters. Product IDs can't be changed after creation, so the publisher must set the same ID in `FACTORYTOOLS_PRO_PRODUCT_ID`. The first non-consumable needs to be submitted with a new app version. See Apple's [product-field reference](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information) and [submission guide](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

### Japanese product localization (ja-JP)

**Display Name**  
Factory Tools Pro

**Description**  
専門ツールと高度な機能を解放

### English product localization (en-US)

**Display Name**  
Factory Tools Pro

**Description**  
Unlock Pro tools and advanced features.

## Japanese (ja-JP)

**Name**  
Factory Tools

**Subtitle**  
生産カウンターと現場計算

**Keywords**  
生産,工場,カウンター,OEE,不良率,タクト,箱詰め,単位換算,効率,時間計算

**Description**

生産数の記録から、サイクルタイムやOEEの確認まで。Factory Toolsは、製造現場で使うカウンターと計算ツールをまとめたアプリです。

生産カウンターで数量を記録し、目標への進捗を確認。タクトタイム、サイクルタイム、不良率、箱詰め、単位換算などの計算もすぐに行えます。無料のホームではカードのサイズや並び順を調整できます。追加ホームはFactory Tools Proで利用できます。

無料で使える機能
・生産カウンター：加算、減算、まとめ入力、取り消し、目標設定
・タクトタイム、サイクルタイム、不良カウンター、不良率
・箱詰め計算、単位換算
・カスタムホーム、カードのサイズ変更と並び替え
・カウンターとサイクルタイムの基本履歴
・履歴のCSV書き出し、JSONバックアップと追加読み込み
・Apple Watchでの生産カウントとサイクルタイム計測
・iPhoneと連携したiPadからの基本カウンター操作
・日本語と英語の表示

Factory Tools Pro（買い切り）
・独立した生産進捗カード、OEE計算
・Apple Watchでの生産進捗確認
・複数ホーム
・サイクルタイムの詳細履歴
・今後追加する専門ツールも同じ買い切りProに含む

データはAppleデバイス内に保存され、Factory Tools独自のクラウド同期はありません。Appleの端末バックアップを有効にしている場合、アプリデータがバックアップに含まれることがあります。WatchとiPadの連携には対応するAppleデバイスとのペアリングが必要です。通信できない間のカウント操作やサイクルタイム記録は端末内に保留され、接続後に送信されます。アプリから書き出したバックアップやCSVは、選択した保存先で管理できます。

基本機能は無料で利用できます。専門ツールや高度な機能は買い切りのFactory Tools Proで解放します。日本向けの販売価格は¥980です。購入画面ではAppleが表示する価格をご確認ください。

## English (en-US)

**Name**  
Factory Tools

**Subtitle**  
Shop floor production tools

**Keywords**  
manufacturing,production,counter,cycle time,takt time,OEE,defects,packing,conversion

**Description**

Record production and review cycle time or OEE with Factory Tools, a practical toolbox for manufacturing work.

Log output with the production counter and track progress toward a target. Calculate takt time, cycle time, defect rate, box packing, and unit conversions. Customize card sizes and ordering in your Free home; Factory Tools Pro unlocks additional homes.

FREE FEATURES
• Production counter with increment, decrement, quick add, undo, and targets
• Takt Time, Cycle Time, Defect Counter, and Defect Rate
• Box Calculator and Unit Converter
• Custom home with resizable and reorderable cards
• Basic counter and Cycle Time history
• CSV history export and JSON backup with additive import
• Production counting and Cycle Time capture from Apple Watch
• Basic counter controls from an iPad paired with iPhone
• Japanese and English

FACTORY TOOLS PRO (ONE-TIME PURCHASE)
• Standalone Production Progress card and OEE Calculator
• Read-only Production Progress view on Apple Watch
• Additional homes
• Detailed Cycle Time history
• Future specialist tools included in the same one-time purchase

Your data is stored on your Apple devices, with no Factory Tools cloud sync. Apple device backups may include app data if enabled in your device settings. Watch and iPad features require pairing with compatible Apple devices. Counter actions and Cycle Time captures made offline stay on the device until a connection returns. Backups and CSV files you export are managed at the location you choose.

Core tools are free. Specialist tools and advanced features are unlocked with the one-time Factory Tools Pro purchase. Apple displays the applicable price before purchase.

## Character and byte count

Counts exclude the field labels and Markdown formatting. The descriptions are checked as plain listing text, retaining their line breaks.

| Locale | Name | Subtitle | Keywords (UTF-8 bytes) | Description |
|---|---:|---:|---:|---:|
| Japanese | 13 / 30 | 12 / 30 | 96 / 100 bytes | 4,000-character limit |
| English | 13 / 30 | 27 / 30 | 84 / 100 bytes | 4,000-character limit |


