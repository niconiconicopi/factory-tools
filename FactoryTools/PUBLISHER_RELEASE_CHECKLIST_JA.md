# Factory Tools 公開者向けチェックリスト

Apple登録で入力する内容や、公開前に必要な作業を順番にまとめています。詳しい背景と公式リンクは [APPLE_RELEASE_SETUP_JA.md](APPLE_RELEASE_SETUP_JA.md)、ビルドと提出の手順は [APPLE_RELEASE_RUNBOOK.md](APPLE_RELEASE_RUNBOOK.md) を参照してください。

## 今すぐ必要な作業

Apple Developer Program登録完了の報告を受け、Team IDを受領してXcodeプロジェクトへ設定しました。次はApp Store Connectと署名アップロード用のGitHub設定です。法的氏名、住所、電話番号、Apple Account情報、確認コード、API秘密鍵は、このチャットや公開リポジトリへ送らないでください。

- [ ] App Store Connectで最初のアプリ記録を作る前に、個人登録では法的氏名がApp Storeの販売元／開発者名として公開され、ペンネームにできず、初回登録後は変更できないことを確認する。[Appleの開発者名の説明](https://developer.apple.com/help/app-store-connect/create-an-app-record/set-your-developer-name/)
- サポート／プライバシーページでは「Factory Tools」をブランド名として使えますが、それによってApp Storeの販売元名が非公開になるわけではありません。ページ上の運営者情報は別途公開前に確認します。

## 配布前の公開者確認

- [ ] サポートメールを公開後も確認できるようにし、日本語・英語の返信体制を整える。テストメールの受信は確認済みです。
- [x] 運営者は、問い合わせへの対応が終わったらメールを削除できると確認。公開後もプライバシーポリシーに沿って運用する。
- [x] 発行者名を公開リポジトリに入れず、GitHubのActionsシークレット `FACTORYTOOLS_PUBLISHER_LEGAL_NAME` に保存済み。氏名は公開用ページでは表示されるため、ページ本文を確認してから公開する。
- [ ] 日英のプライバシーポリシーとサポートページを確認する。公開用ページ案をレビューし、公開時に発行者名が表示されることを確認する。施行日は候補生成日に日本時間で自動設定する。
- [x] 無料のGitHub Pagesを公開先として選択（2026-11-20）。発行者名などの原稿を確定し、公開前にページ内容を確認する。
- [ ] GitHub Pagesを有効にしてプライバシー／サポートページを公開し、安定したHTTPS URLへのアクセスを確認する。
- [ ] EUを含む全地域で配信する方針に沿って、AppleのDSA販売者／非販売者の説明を読み、自分の活動実態から申告内容を判断する。現時点での本人の説明は「趣味として運営する」ですが、Proの買い切り販売（日本価格¥980）もAppleが挙げる判断要素の一つです。この回答だけで非販売者と確定せず、実際の販売・宣伝・事業との関係を踏まえ、App Store Connectで公開前に自己判断してください。個人登録や価格だけでこちらが法的区分を決めることはできません。販売者として申告する場合、Appleが求めるEU向け連絡先の表示・確認条件を先に確認してください。
- [x] 最新コード `729f44a` のApple CIが通過。ネイティブ run `44888194069` でiPhone/iPadテスト、画面撮影14枚＋4枚、S/M/L証拠6枚、画像最終ゲートが成功。Watch/archive run `44888194062` でWatch/Coreテスト・日英撮影2枚・署名なしiOS/iPadアーカイブが成功。StoreKit local run `44888208995` では商品読込・Pro解除・模擬取引消去後の再ロックも成功。これらは実機・署名済み販売購入の確認ではありません。
- [ ] iPhone/iPad/Watchの画像候補、ストア文面、Pro価格、プライバシー／サポートページを本人が公開前に確認する。実アプリ直接撮影の原本（Simulator例示データ使用）は `FactoryTools-AppStore-Assets-Review-2026-11-21/latest-run-44888194069/` と `.../latest-run-44888194062/`。iPhone/iPad用の見出し付きレイアウト案18枚は、非公開の `FactoryTools-AppStore-Assets-Review-2026-11-21/store-artwork-draft/rendered/review-gallery.html` で確認できます。画面素材は実アプリのキャプチャですが、見出し・背景・枠を加え、収まりに合わせて縮小・一部トリミングしています。架空UIは使っていません。iPad版にはSimulatorの試験接続状態（「接続しました」を含む）が表示されるため、実機でiPhoneとのペアリングを確認し、実際の状態に合った画像を選ぶまで提出候補にしません。どの画像も未承認・未提出です。プライバシー／サポートページは、発行者名と2026-11-21の候補日を入れた非公開・noindexの確認用HTMLを `FactoryTools-AppStore-Assets-Review-2026-11-21/Pages-preview/` に準備済み。まだページは公開していません。

## 登録後にまず確認

- [x] Apple DeveloperアカウントのTeam ID（10文字）をXcodeプロジェクトへ設定する。パスワードや本人確認情報は共有しない。
- [x] Team IDはXcodeプロジェクトへ設定済み。署名アップロード時にワークフローがそこから読み込むため、GitHub変数 `APPLE_TEAM_ID` の登録は通常不要。Apple Developerアカウントを変更した場合だけ上書き値を設定する。
- [ ] Account HolderとしてApp Store Connect API利用を申請し、署名用Team API Keyを作成する。`.p8`秘密鍵はGitHubの指定secretへ直接登録し、チャットには送らない。

## 登録後にApple側で行うこと

- [ ] Bundle ID候補 `com.niconiconicopi.factorytools` が利用可能か確認し、Apple Developerアカウントに登録する。
- [ ] App Store Connectにアプリ記録と、買い切り非消耗型商品の `factorytools.pro.lifetime` を作る。商品IDは作成後に変更できません。
- [ ] 英語を基本言語、日本語を追加言語に設定する。アプリとProを配信可能な地域で設定し、日本のPro価格を¥980、Family Sharingをオフにする。他地域のApple提示価格も確認する。
- [ ] 有料アプリ契約、税務・銀行情報、IAP税カテゴリをAccount Holderが設定する。
- [ ] DSA区分と、必要なEU向け公開連絡先を設定する。住所や電話番号の表示範囲を確認してから保存する。
- [ ] 公開済みプライバシー／サポートURLと、審査連絡先を登録する。

## 配布前テストと提出

- [ ] Team IDやURL等を設定して署名付きビルドを作成し、App Store Connectへアップロードする。現在の手順はGitHub Actionsを使う想定で、Macの用意は不要です。
- [ ] 発行者がApple端末を持っていないため、登録後に同意した外部テスターへTestFlightを配布する。iPhone、Watch、iPadの連携・オフライン復帰・履歴、Pro購入と復元を確認してもらう。
- [ ] 実際のStoreKit商品・価格・購入画面で購入と復元を確認し、App Review用IAP画像を用意する。
- [ ] スクリーンショット、Watch情報・アイコン、年齢評価、プライバシー、輸出コンプライアンスの回答を最終ビルドに合わせて設定し、App Reviewへ提出する。
- [ ] 審査承認後、アプリとPro商品が指定地域で公開され、¥980の購入・復元が動作することを確認する。

2027年4月以降の提出ではiPhone Duoの外側・内側画面画像も必要になります。公開前にAppleの最新要件を再確認してください。

## 完成と判断する条件

App Storeでアプリを配布でき、指定した地域でProを購入・復元でき、TestFlight等でiPhone・Watch・iPadの連携確認が完了した状態です。Simulatorの成功や未署名アーカイブだけでは、配布完了とは扱いません。
