# Factory Tools Privacy Policy draft / プライバシーポリシー案

**Draft only.** Complete every bracketed publisher field, review the text for the release build and applicable law, publish a stable public URL, and add an in-app link before submission. Do not publish this draft with placeholders.

**Publisher / 運営者:** `[Publisher's legal name / 発行者の正式名称]`  
**Effective date / 発効日:** `[YYYY-MM-DD]`  
**Privacy contact / 個人情報に関する連絡先:** `azalea.fortask@outlook.jp`

## 日本語

### 対象

このポリシーは、Factory ToolsのiPhone、iPad、Apple Watchアプリで扱う情報について説明します。

### アプリが端末内で扱う情報

Factory Toolsは、ホーム名、ツールの配置、設定、生産数、不良数、操作履歴、サイクルタイム、OEEの記録など、利用者が入力または作成したデータを機能の提供と履歴表示のために端末内に保存します。ペアリング機能を使う場合、接続用の秘密コードを端末のKeychainに保存します。Apple Watchは計測中のサイクルタイム状態と未送信のカウンター操作・サイクルタイム記録を端末内に保留し、iPadは未送信のカウンター操作を端末内に保留します。

### サポートメールでのお問い合わせ

利用者がサポートへメールを送ると、返信先のメールアドレス、本文、利用者が記載・添付した情報を受け取ります。端末・OS・アプリのバージョン、操作内容、表示されたメッセージなど、問題の解決に必要な情報だけ記載してください。生産履歴、バックアップファイル、ペアリングコード、Apple Accountの認証情報、支払い情報は送らないでください。メールの内容は問い合わせへの返信と問題解決のためだけに扱い、対応が完了したら削除します。メールサービスによる処理・保存は[Microsoft プライバシー ステートメント](https://www.microsoft.com/ja-jp/privacy/privacystatement)に従います。

### 収集、送信、第三者提供

Proの買い切り購入と支払いはAppleのApp Storeが処理します。アプリはStoreKitを使って端末上で購入済みかを確認します。支払い方法、カード情報、Apple Accountの認証情報をアプリが取得したり、開発者へ送信したりすることはありません。

現在のアプリには、開発者が運営するサーバー、アカウント、外部API、アプリ独自のクラウド保存・同期、広告、分析、トラッキング、または第三者SDKはありません。生産データやStoreKitの購入確認情報を開発者へ送信しません。

接続中、Factory ToolsはApple Watchとの間でカウンター操作とサイクルタイム記録を直接送受信します。iPhoneからWatchへは、選択中ホームのカウンター情報に加え、Pro利用中はWatch表示を有効にした生産進捗カードのホーム名、生産数、目標数を送信します。ペアリングしたiPadとの間では、カウンター操作と必要なセッション情報を直接送受信します。これらの通信はFactory Toolsの端末間機能に使われ、開発者や外部事業者のサーバーには送られません。

利用者がJSONバックアップまたはCSVを書き出すと、システムの共有機能で利用者が選んだ保存先や送信先にファイルを渡せます。その後の保存先における取り扱いは、そのサービスのプライバシー条件に従います。

### 保存と削除

アプリのデータは各端末に保存され、開発者が管理する保管期間はありません。iPhone/iPadのiCloudバックアップまたはコンピュータバックアップを利用している場合、Appleの端末バックアップにアプリデータが含まれることがあります。Apple Watchのバックアップはペアリング済みiPhoneのバックアップに含まれます。バックアップの設定、管理、削除はAppleのシステムに従います。ホームを削除すると、そのホームに属するカウンターと履歴などのデータもアプリから削除されますが、既存の端末バックアップには更新または削除まで以前のデータが残る場合があります。サイクルタイムとOEEの記録は各画面の削除操作で削除できます。設定からペアリングコードも削除できます。ペアリングを終了するときは、アプリを削除する前に設定からコードを削除してください。AppleのKeychain項目はアプリ削除後も残る場合があるためです。エクスポートしたファイルは利用者が選んだ保存先で管理・削除してください。

JSONバックアップにもCSV書き出しにも、WatchやiPadからの未送信操作とWatchの計測中タイマーは含まれません。アプリを削除する前に、端末間の保留中データを同期してください。

### 子どものプライバシー

Factory Toolsアプリには、子どもの情報を開発者へ自動送信する機能はありません。子ども本人または保護者がサポートへメールを送る場合は、上記のメール取扱いが適用されます。対象年齢や地域に関する問い合わせは、保護者から上記の連絡先へお送りください。

### 変更と問い合わせ

このポリシーを変更するときは、改訂版を同じ公開ページに掲載し、発効日を更新します。プライバシーに関する問い合わせは上記の連絡先へお送りください。

### このページのホスティング

このポリシーまたはサポートページをGitHub Pagesで公開する場合、GitHubはサービスのセキュリティのため訪問者のIPアドレスを記録します。詳しくは[GitHubのプライバシーに関する説明](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)をご確認ください。これはFactory Toolsアプリが端末内で扱うデータとは別の、ページ閲覧に関するホスティング側の処理です。別のホストを使用する場合は、そのホストの実際のログ処理に合わせてこの説明を更新してください。

## English

### Scope

This policy describes information handled by the Factory Tools apps for iPhone, iPad, and Apple Watch.

### Information handled on your devices

Factory Tools stores data that you enter or create—such as home names, tool layouts, settings, production and defect counts, counter history, Cycle Time samples, and OEE records—on your devices to provide app features and display your history. If you use pairing, the connection secret is stored in the device Keychain. The Watch app stores active timer state and pending counter commands and Cycle Time samples locally; the iPad app stores pending counter commands locally until delivery.

### Collection, transmission, and sharing

Apple's App Store processes the one-time Pro purchase and payment. The app uses StoreKit to check the purchase entitlement on the device. The app does not access payment-method or card details or Apple Account credentials, and does not send them to the developer.

The current app has no developer-operated server, account, external API, app-operated cloud storage or sync, advertising, analytics, tracking, or third-party SDK. Production data and StoreKit entitlement checks are not sent to the developer.

### Support email

If you email support, the publisher receives your reply address, message, and any information or attachments you choose to include. Include only details needed to resolve the issue, such as device, operating-system, or app version, the action taken, and any message shown. Do not send production history, backup files, pairing codes, Apple Account credentials, or payment information. The publisher uses the message only to reply and resolve the support request, and deletes it after the request is resolved. The support mailbox uses Microsoft's Outlook email service; Microsoft's processing and storage are described in the [Microsoft Privacy Statement](https://www.microsoft.com/en-us/privacy/privacystatement).

While connected, the app exchanges counter commands and Cycle Time samples directly with Apple Watch. The iPhone also sends the selected home's counter catalog and, while Pro is active, the home name, production count, and target for Watch-enabled Production Progress cards. The app exchanges counter commands and required session information with a paired iPad. These transfers support the device-to-device features and are not sent to a server operated by the developer or an outside provider.

When you export a JSON backup or CSV file, the system share sheet lets you choose where to save or send it. The destination's own privacy terms govern how it handles the file after you share it.

### Storage and deletion

App data is stored on your devices, and the developer does not set a retention period for locally stored data. If you enable iCloud or computer backups for iPhone or iPad, Apple device backups may include app data. Apple Watch backups are included with the paired iPhone backup. Apple manages backup settings, retention, and deletion. Deleting a home removes its counters, history, and associated data from the app, but earlier copies may remain in existing device backups until those backups are updated or deleted. Cycle Time and OEE records can be deleted from their screens. You can also remove a pairing code in Settings. If you are ending pairing, remove the code in Settings before deleting the app; Apple Keychain items may remain after app removal. Manage and delete exported files at the location you chose.

Neither JSON backups nor CSV exports include unsent Watch or iPad commands or an active Watch timer. Sync pending device data before deleting the app.

Apple explains [what iCloud Backup includes](https://support.apple.com/en-us/108770) and [how Apple Watch backups work](https://support.apple.com/en-us/108358).

### Children's privacy

The Factory Tools app does not automatically send children's information to the developer. If a child or parent/guardian emails support, the support-email handling described above applies. For questions about age suitability or regional requirements, a parent or guardian may contact us using the details above.

### Changes and contact

If this policy changes, the updated version will be posted at the same public page with a revised effective date. Contact us using the details above with privacy questions.

### Website hosting

If this privacy or support page is published with GitHub Pages, GitHub logs visitor IP addresses for service security. See [GitHub's privacy information](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages). This is hosting-side processing associated with viewing the website, separate from data the Factory Tools app handles on your devices. If another host is used, update this notice to match that host's actual logging practices.

## Before publication

- Replace every bracketed field with the publisher's actual public details.
- Confirm all statements against the archived release build, including system frameworks, local device transfers, and any future SDK or purchase integration.
- Confirm the pairing-code removal wording against Apple's current Keychain behavior and the final Settings flow.
- Confirm the App Store purchase and payment wording against the final StoreKit configuration and Apple's current App Privacy guidance.
- Review Apple-managed backups separately from Factory Tools sync: [iCloud Backup contents](https://support.apple.com/ja-jp/108770) and [Apple Watch backups](https://support.apple.com/ja-jp/108358).
- Make this policy publicly accessible at a stable HTTPS URL, localize or provide the Japanese and English versions, link it from inside the app, and enter the URL in App Store Connect.
- Review this page's hosting notice against the actual host. GitHub Pages logs visitor IP addresses for security; a different host may have different access logs, terms, and notices.
- Obtain the publisher's legal/privacy review for the jurisdictions where the app will be offered.
