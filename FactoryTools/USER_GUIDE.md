# Factory Tools quick guide

This guide follows the current app interface. It is prepared for support and localization review; it is not an in-app help screen or a published support page.

## 日本語

### ホームとツール

- ホーム下部の「ツールを追加」から、生産カウンターや計算ツールを追加します。
- カード右上の「…」からカードのサイズ、順序、削除を変更します。生産カウンターでは目標値も設定できます。
- 左上のホームメニューからホームを切り替えたり、新しいホームを作成したりできます。「ホームを管理」では名前変更、並び替え、削除ができます。
- ホームを削除すると、そのホームのカード、カウンター、履歴、サイクルタイム記録、OEE記録も削除されます。最後のホームは削除できません。

### 生産カウンター

- 「+1」「−1」で数量を変更します。カウンターの「…」から任意の数量をまとめて加算したり、直近の操作を取り消したりできます。
- 目標値はカウンターの「…」またはカードの「…」にある目標設定から入力します。
- 履歴を開くと、日時・操作・操作後の数量を確認できます。履歴画面の共有ボタンからCSVを書き出せます。
- 「リセット」は確認後に現在値を0に戻します。操作履歴は残ります。

### 設定、バックアップ、言語

- 設定から表示言語を「システム」「日本語」「English」に切り替えられます。テーマは現在 Industrial Dark です。
- 「プライバシーの詳細」では保存先、端末間通信、書き出し、削除方法を確認できます。公開用ポリシーが設定されたビルドでは、全文へのリンクも表示されます。
- JSONバックアップを作成すると、共有シートから保存先や送信先を選べます。
- JSONバックアップの読み込みは既存データを置き換えず、別ホームとして追加します。同じファイルを再度読み込むと、もう一つコピーが追加されます。Freeではバックアップ内の先頭ホームが無料で使うホームになり、既存ホームや残りの復元ホームは保持されたままPro利用時までロックされます。
- 計数、サイクルタイム、OEEの履歴は各履歴画面からCSVに書き出せます。
- 生産進捗、OEE、追加ホーム、詳細分析などはFactory Tools Proの対象です。Proは買い切りで、日本向け価格は¥980です。購入が提供された場合は設定にAppleが表示する価格を確認し、同じApple Accountで復元できます。

### Apple Watch

- iPhoneとペアリングしたApple WatchにWatchアプリをインストールして開きます。基本的なカウンター連携は無料で利用できます。
- Watchでは画面に合わせた専用のコンパクトなレイアウトを使います。iPhoneのカードサイズやホーム全体の配置は引き継がず、Watchの各セクション内でカードの順序を保ちます。
- Watchでカウンターを選び、「+1」「−1」「+5」を使います。通信できない間の操作はWatch上で保留され、接続後にiPhoneへ送信されます。
- iPhoneが返す確認を受け取るまでは保留操作として表示されます。カタログが更新されないときは、一覧の更新操作を使います。
- iPhoneでホームを切り替える前に、Watchの未送信操作がなくなるまで同期してください。旧ホーム宛ての保留操作は、別ホームに誤記録されないようiPhoneで拒否され、Watchの待ち行列から除かれることがあります。拒否が表示されたら、対象ホームのカウンター値を確認してから未反映の操作だけを入力し直してください。
- ホームにサイクルタイムカードがある場合、Watchの「サイクルタイム」から1個あたりの時間を計測できます。開始/一時停止/再開の状態はWatch内に保存され、「停止して記録」でiPhoneの履歴へ送ります。未接続中の記録も順番に保留されます。
- Proを利用中でホームに生産進捗カードがある場合、Watchに読み取り専用の生産進捗カードが表示されます。数量と目標はiPhoneのホームと連動します。

### iPad

- iPhoneの設定でペアリングコードを作成し、共有シートなどで自分のiPadに渡します。コードは接続用の秘密情報として扱い、アプリ削除前に設定から削除してください。Keychainの項目はアプリ削除後も残る場合があります。基本的なiPadカウンター連携は無料で利用できます。
- iPadの設定に64桁のコードを入力して保存し、「接続」を押します。初回接続時にローカルネットワークへのアクセスを求められたら許可してください。端末が近くにあり、ローカルネットワークまたはピアツーピアWi‑Fiで通信できる状態で、ホーム右上の接続ボタンからカウンターダッシュボードを開きます。
- ペアリングコードの作り直しや削除は、確認画面を読んでから進めてください。iPadの未送信操作は旧コード用のキューに残り、新しいコードへは移りません。再接続や再送信が必要になる可能性がある場合は、変更・削除の前に旧コードを安全な場所に控えてください。コードを作り直した後は、iPhone設定の「保存済みの64桁コードでペアリングを復元」に旧コードを入力し、iPadにも同じコードを設定すると再送できます。
- iPadからの操作はiPhoneに送られ、iPhoneが正式なカウントと履歴を保存します。接続できないときは、両方の端末でFactory Toolsを開き、iPadの設定から再接続します。
- ペアリングコードを削除するには、iPhoneの設定で「ペアリングコードを削除」を選びます。

アプリのデータは端末内に保存されます。JSONやCSVを書き出した場合、そのファイルは選択した保存先で管理されます。

## English

### Homes and tools

- Select **Add Tool** at the bottom of a home to add Production Counter or a calculator.
- Open a card's **…** menu to change its size or position, or remove it. Production Counter cards also offer target settings.
- Use the home menu in the upper-left corner to switch homes or create one. **Manage Homes** lets you rename, reorder, or delete homes.
- Deleting a home also deletes its cards, counters, counter history, Cycle Time samples, and OEE records. The last remaining home cannot be deleted.

### Production Counter

- Use **+1** and **−1** to change the count. Open the counter's **…** menu to add a custom amount or undo the latest operation.
- Set a target from **… > Goal Settings** on the counter or its card.
- Open History to review dates, actions, and the balance after each action. Use the share button in History to export CSV.
- **Reset** returns the current count to zero after confirmation. The event history remains available.

### Settings, backup, and language

- Choose **System**, **日本語**, or **English** in Settings. The current theme is Industrial Dark.
- **Privacy Details** explains local storage, paired-device transfers, exports, and deletion. Builds configured with the published policy URL also show a link to the full policy.
- Create a JSON backup in Settings, then choose where to save or send it from the share sheet.
- Importing a JSON backup adds separate homes and keeps existing data. Importing the same file again adds another copy. In Free, the backup's first home becomes the active Free home; existing homes and the remaining restored homes are kept and locked until Factory Tools Pro is active.
- Export Counter, Cycle Time, and OEE history as CSV from their history screens.
- Production Progress, OEE, additional homes, and detailed analysis are assigned to Factory Tools Pro. Pro is a one-time purchase; the confirmed Japan price is ¥980. When purchase is configured, Settings will show Apple's applicable price and allow restoration with the same Apple Account.

### Apple Watch

- Install and open the Watch app on the Apple Watch paired with your iPhone. Basic counter integration is available in Free.
- Watch uses a compact layout designed for its screen. iPhone card sizes and the full iPhone dashboard arrangement do not carry over; supported cards appear in Watch sections, with their relative order retained within each section.
- Select a counter and use **+1**, **−1**, or **+5**. Commands made while disconnected remain queued on the Watch and are sent to the iPhone when the connection returns.
- A command remains pending until the iPhone acknowledges it. Refresh the list if the available counters are out of date.
- Before switching homes on iPhone, wait for the Watch's pending commands to sync. A queued command for the previous home may be rejected and removed from the Watch queue so it cannot be recorded against a different home. If you see a rejection, check that home's count before entering only the missing actions again.
- If the selected home has a Cycle Time card, open **Cycle Time** on Watch to measure one unit. Start, pause, and resume state is saved on Watch. Select **Stop & Save** to add the sample to iPhone history; disconnected samples remain queued for delivery.
- With Pro active, a Production Progress card on the selected home also appears on Watch as a read-only view. Its count and target follow the iPhone home.

### iPad

- Create a pairing code in iPhone Settings and share it with your own iPad. Treat it as a connection secret and remove it in Settings before deleting the app; the Keychain item may remain after app removal.
- Basic counter control from iPad is available in Free.
- Enter the 64-character code in iPad Settings, save it, and select **Connect**. Allow local-network access if prompted. Keep the devices nearby and able to communicate over the local network or peer-to-peer Wi-Fi. Open the counter dashboard with the connection button in the top-right corner of the home screen.
- Replacing or removing a pairing code stops the existing connection. Unsent iPad commands remain in the queue for the old code and are not moved. If you may need to reconnect or resume sending, keep a secure copy of the old code before replacing or removing it. After replacing it, enter the saved old code in iPhone Settings under **Enter an existing 64-character code to restore pairing**, then set that same code on iPad to resume sending.
- iPad commands are sent to the iPhone, which saves the canonical count and history. If the connection fails, open Factory Tools on both devices and reconnect from iPad Settings.
- To remove pairing, select **Remove Pairing Code** in iPhone Settings.

App data is stored on your devices. JSON and CSV files are managed at the location you choose when exporting.




