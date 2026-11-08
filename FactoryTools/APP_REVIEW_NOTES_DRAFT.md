# App Review Notes — Factory Tools

**Draft only.** Verify the instructions against the signed submission build. The supplied support address below passed a receipt test; confirm it will be monitored throughout App Review and add the publisher's reviewer name and any required phone number before submission. Do not add credentials; the app has no account or sign-in flow.

## Review contact

- Contact: **[Publisher review contact name]**
- Email: **azalea.fortask@outlook.jp** (publisher-supplied support address; receipt test confirmed; monitoring during review must be confirmed)

## App access

Factory Tools has no sign-in, account creation, subscription, or developer-operated server dependency. Core functions operate on-device. The first launch creates a local home. Production data, history, and settings stay in app storage unless the user transfers them to a paired device or exports a file. Apple may include app data in device backups when enabled in the user's Apple device settings; Factory Tools does not access or manage those backups.

## Suggested iPhone review flow

1. Open Factory Tools. The app opens to the Industrial Dark home.
2. Tap **Add Tool**, add **Production Counter**, and use **+1**, **−1**, Quick Add, Undo, and target settings.
3. Open the counter history to review the saved events. Force-quit and reopen the app to confirm the local count and home remain available.
4. Open Settings to change Japanese/English and review the privacy details.
5. Open the Factory Tools Pro section in Settings. The first-release product is a single non-consumable; the purchase button displays Apple's localized StoreKit price. Use App Store sandbox purchase and restore flows to review entitlement access.
6. Other tools are available from **Add Tool**. Production Progress, OEE, and other explicitly assigned Pro features require an active Pro entitlement.

## Apple Watch review flow

The Watch app is a companion to the iPhone app and requires a paired iPhone for its authoritative counter data.

1. Install/open Factory Tools on a paired iPhone and Apple Watch.
2. Add a Production Counter from **Add Tool** if the home has no counter yet.
3. Open Factory Tools on Apple Watch, select the available counter, then use **+1**, **−1**, or **+5**. If the selected home has a Cycle Time card, use the Watch Cycle Time screen to start, pause, resume, and **Stop & Save** a one-unit measurement. With Pro active and a Production Progress card on the home, confirm its read-only Watch view matches the iPhone count and target.
4. Confirm counter operations apply once and the sample appears in iPhone Cycle Time history. If the iPhone is temporarily unavailable, completed Watch counter actions and Cycle Time samples remain queued and send when connectivity returns.

## iPad review flow

The iPad is an optional counter-control companion. The iPhone remains the source of truth for count history.

1. On iPhone, open Settings > paired-device section and generate a pairing code. Share the code with the review iPad using the system share sheet.
2. On iPad, open Settings, enter the 64-character pairing code, activate it, and select **Connect**.
3. Allow Local Network access when iOS asks. Keep Factory Tools open on the nearby iPhone.
4. From the iPad home, open the counter dashboard and send a counter command. Confirm the iPhone applies it and retains the event in its history.

If only one device is available during review, the full iPhone core flow remains available; Watch and iPad flows require the corresponding paired devices.

## 日本語

### アプリへのアクセス

サインイン、アカウント作成、サーバー接続はありません。基本機能は端末内で利用できます。カウント履歴、設定、バックアップは端末内で扱い、ユーザーが書き出したファイルは選択した保存先で管理します。

### iPhoneでの確認手順

1. Factory Toolsを起動し、Industrial Darkのホームを表示します。
2. ホーム下部の「ツールを追加」から「生産カウンター」を追加し、「+1」「−1」、Quick Add、Undo、目標値を確認します。
3. 履歴を開いて操作履歴を確認します。アプリを終了して再起動し、ホームとカウントが保持されることを確認します。
4. 設定で日本語/英語を切り替え、プライバシー情報を確認します。
5. 設定のFactory Tools Pro欄を開きます。初回商品は買い切り型の非消費型商品1つです。購入ボタンにはStoreKitのローカライズ価格が表示されます。Sandbox購入と復元でPro機能の解除を確認してください。
6. その他のツールは「ツールを追加」から確認できます。Pro対象機能には有効なPro購入状態が必要です。

### Apple Watch

ペアリング済みiPhoneにFactory Toolsをインストールして開き、生産カウンターとサイクルタイムカードを用意します。Apple WatchでFactory Toolsを開き、対象カウンターを選んで「+1」「−1」「+5」を操作します。サイクルタイム画面では開始/一時停止/再開し、「停止して記録」で1個分の計測値を送信できます。Proが有効で生産進捗カードがある場合は、Watchの読み取り専用進捗表示がiPhoneの数量と目標に一致することも確認します。iPhoneが各操作に応答するまでWatch側で保留し、通信復帰後に送信します。

### iPad

1. iPhoneの設定でペアリングコードを作成し、共有シートで審査用iPadに渡します。
2. iPadの設定で64桁のコードを入力して有効化し、「接続」を押します。
3. iOSがローカルネットワークへのアクセスを尋ねたら許可します。iPhoneは近くに置き、Factory Toolsを開いた状態にします。
4. iPadホーム右上の接続ボタンからカウンターダッシュボードを開き、カウンター操作を送ります。正式なカウントと履歴はiPhoneに保存されます。

審査時に1台しか利用できない場合も、iPhoneの機能はすべて確認できます。WatchとiPadの操作確認には各端末とのペアリングが必要です。

審査連絡先は、公開・監視されている発行者の連絡先に置き換えてください。

## Purchase review asset

The non-consumable Factory Tools Pro product is submitted with the iOS version. The App Review purchase screenshot is captured from the configured signed build and uploaded in App Store Connect. The product ID, displayed price, Family Sharing setting, review contact, and all required device screenshots must match the actual submission state.

## Before submission

- Confirm `azalea.fortask@outlook.jp` will be monitored during review, then replace the reviewer name placeholder and add any contact details App Store Connect requires.
- Confirm the sandbox product is available and both purchase and restore unlock the expected Pro feature set.
- Confirm the Pro purchase screen and product metadata match the single non-consumable product.
- Confirm the Watch/iPad steps against the submitted targets and actual release build.
- Attach only synthetic data to any review artifact; never include real production records or pairing secrets.
