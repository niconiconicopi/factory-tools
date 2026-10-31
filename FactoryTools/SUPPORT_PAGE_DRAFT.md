# Factory Tools Support Page

**Publication status: draft.** Before publishing, replace every bracketed publisher field with a real, monitored contact and update the supported app/platform versions. Do not publish a placeholder email or promise a response time that has not been established.

---

## 日本語

# Factory Tools サポート

Factory Toolsをご利用いただきありがとうございます。お問い合わせは以下の窓口へお送りください。

- 開発者: **[開発者名]**
- サポートメール: **[サポート用メールアドレス]**
- 対応言語: 日本語 / English

### お問い合わせに含めてください

- お使いの端末とOSのバージョン
- Factory Toolsのバージョン
- 発生した操作と、表示されたメッセージ
- 再現する場合は、その手順

購入・請求については、購入に使ったApple Accountの情報や支払い情報をメールに記載しないでください。請求処理はAppleが行います。購入済みのProが表示されない場合は、アプリの「設定」から「購入を復元」をお試しください。

### データと端末連携

生産記録、設定、履歴は端末内に保存されます。AppleのiCloudまたはコンピュータバックアップを有効にしている場合、アプリデータが端末バックアップに含まれることがありますが、Factory Toolsはそのバックアップを管理しません。アプリを削除する前に、必要なデータをバックアップとして書き出してください。書き出した記録やペアリングコードは、問い合わせメールへ添付しないでください。問い合わせでは、問題の手順と画面に表示された内容を説明してください。

WatchやiPadとの連携が止まった場合は、両方のアプリを開き、iPhone側のFactory Toolsを起動した状態で再接続してください。iPadの連携は近距離のローカル通信を使います。ペアリングコードの作り直しや削除をすると接続が停止します。iPadの未送信操作は旧コード用のキューに残り、新しいコードへは移動しません。再接続や再送信が必要になる可能性がある場合は、変更・削除の前に旧コードを安全な場所に控えてください。コード作り直し後は、iPhone設定の「保存済みの64桁コードでペアリングを復元」に旧コードを入力し、iPadにも同じコードを設定すると再送できます。ペアリングコードは接続用の秘密情報として扱い、公開の場所へ掲載しないでください。ペアリングを終了するときは、アプリを削除する前にiPhoneの設定でペアリングコードを削除してください。Keychainの項目はアプリを削除しても残る場合があります。

Watchにカウンター操作が送信待ちの間は、iPhoneでホームを切り替える前に同期が終わるまで待ってください。切り替えた後に旧ホーム宛ての操作が拒否された場合は、そのホームのカウンター値を確認し、未反映の操作だけを入力し直してください。

Watchでサイクルタイムを「停止して記録」した後、iPhoneの履歴にまだ表示されない場合、記録はWatch内で確認応答を待っています。両方のアプリを開いて接続を戻してください。別ホームで計測する案内が出た場合は、現在の計測を保存するかリセットしてから始めてください。

### プライバシー

プライバシーについては **[公開済みプライバシーポリシーURL]** をご確認ください。

---

## English

# Factory Tools Support

Thank you for using Factory Tools. Contact us at:

- Developer: **[Developer name]**
- Support email: **[Monitored support email address]**
- Support languages: Japanese / English

### Include in your request

- Your device and operating-system version
- Your Factory Tools version
- The action you took and any message shown
- Steps to reproduce the issue, if available

Do not include your Apple Account credentials, payment details, pairing code, or production records in an email. Apple handles billing. If a Pro purchase does not appear, try **Restore Purchases** in the app's Settings.

### Data and device connections

Production records, settings, and history are stored on your device. Apple device backups may include app data when iCloud or computer backup is enabled; Factory Tools does not manage those backups. Export a backup before deleting the app if you need to keep your data. Do not attach production records or a pairing code to a support email. Describe the steps and the message shown instead.

If Watch or iPad communication stops, open both apps and keep Factory Tools open on the iPhone while reconnecting. iPad communication uses a nearby local connection. Replacing or removing the pairing code stops the connection. Unsent iPad commands remain in the queue for the old code and are not moved to a new code. Keep a secure copy of the old code before replacing or removing it if you may need to reconnect or resume sending. After replacing it, enter the saved code in iPhone Settings under **Enter an existing 64-character code to restore pairing**, then set the same code on iPad to resume sending. Treat the pairing code as a secret and do not post it publicly. To end pairing, remove the pairing code in iPhone Settings before deleting the app; a Keychain item may remain after app removal.

While Watch counter commands are pending, wait for them to sync before switching homes on iPhone. If a command for the previous home is rejected after a switch, check that home's count and re-enter only actions that were not recorded.

If a Watch Cycle Time sample does not appear in iPhone history after **Stop & Save**, it remains on Watch until acknowledged. Open both apps and restore the connection. If the Watch says the active timer belongs to another home, save or reset that measurement before starting one for a different home.

### Privacy

Read our privacy policy at **[Published privacy policy URL]**.

---

## Publisher checklist

- Replace developer name and support email in both language sections.
- Confirm the mailbox is monitored and can receive replies in Japanese and English, or narrow the stated language support.
- Replace both privacy-policy placeholders with the same published HTTPS URL used by the app and App Store Connect.
- Review troubleshooting steps against the release build and current product behavior.
- Publish this page at a stable HTTPS URL, then set the same URL in the Release `FACTORYTOOLS_SUPPORT_URL` build setting and App Store Connect.
