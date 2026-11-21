# Factory Tools 公開者向けチェックリスト

Apple登録で入力する内容や、公開前に必要な作業を順番にまとめています。詳しい背景と公式リンクは [APPLE_RELEASE_SETUP_JA.md](APPLE_RELEASE_SETUP_JA.md)、ビルドと提出の手順は [APPLE_RELEASE_RUNBOOK.md](APPLE_RELEASE_RUNBOOK.md) を参照してください。

## 今すぐ必要な作業

Apple Developer Program登録完了の報告を受け、Team IDを受領してXcodeプロジェクトへ設定しました。次はApple Developer側でApp IDを登録し、その後App Store Connectにアプリ記録を作成します。法的氏名、住所、電話番号、Apple Account情報、確認コード、API秘密鍵は、このチャットや公開リポジトリへ送らないでください。

- [ ] **次に行うのはApple Developer側でのApp ID登録です。** [公開準備ガイドの「App ID登録」手順](APPLE_RELEASE_SETUP_JA.md#次に行う作業アプリidを1件登録)に沿って、Descriptionを `Factory Tools`、Explicit Bundle IDを `com.niconiconicopi.factorytools` にします。これは識別子を確保する準備で、アプリ公開や追加料金は発生しません。使用済みで登録できない場合は、別のBundle IDを決める前に止めてください。

- [ ] App Store Connectで最初のアプリ記録を作る前に、個人登録では法的氏名がApp Storeの販売元／開発者名として公開され、ペンネームにできず、初回登録後は変更できないことを確認する。[Appleの開発者名の説明](https://developer.apple.com/help/app-store-connect/create-an-app-record/set-your-developer-name/)
- サポート／プライバシーページでは「Factory Tools」をブランド名として使えますが、それによってApp Storeの販売元名が非公開になるわけではありません。ページ上の運営者情報は別途公開前に確認します。

### App Store Connectで最初のアプリ記録を作るとき

1. [App Store Connect](https://appstoreconnect.apple.com/) の「App」から「＋」→「新規App」を選ぶ。
2. プラットフォームは **iOS** を選ぶ（iPadとWatchのコンパニオンを含む）。
3. 基本言語 **English**、アプリ名 **Factory Tools**、Bundle ID **`com.niconiconicopi.factorytools`** を選ぶ。日本語名 **現場ギア** はアプリ記録作成後に日本語ローカライズとして追加する。
4. SKU **`FACTORYTOOLS-IOS-001`** を使う前に、App Store Connectアカウント内で未使用と確認する。SKUは作成後に変更できない。
5. 個人登録者の販売元名は法的氏名となり、アプリ記録作成後に変更できない。Apple画面で本人が確認してから作成する。法的氏名をこのチャットやリポジトリへ入力しない。

このXcodeプロジェクトはiPhone/iPad用のiOSアプリを主アプリにしており、WatchのBundle IDは `com.niconiconicopi.factorytools.watchkitapp` です。Watch専用の別App Storeアプリ記録は作らず、iOSアプリ記録作成後に同じ商品の「Apple Watch」欄へ画像などを追加します。Appleの案内も、コンパニオンWatchアプリでは先にiOSアプリ記録を作ってからWatch情報を加える手順です。[Apple Watch情報を追加する](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information/) · [AppleのBundle ID仕様](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleIdentifier)

Appleの現行手順では、ビルドをアップロードする前にアプリ記録が必要です。個人登録の開発者名は法的氏名で、後から変更できません。[アプリ記録を追加する](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app) · [開発者名を設定する](https://developer.apple.com/help/app-store-connect/create-an-app-record/set-your-developer-name/)

## 配布前の公開者確認

- [ ] サポートメールを公開後も確認できるようにし、日本語・英語の返信体制を整える。テストメールの受信は確認済みです。
- [x] 運営者は、問い合わせへの対応が終わったらメールを削除できると確認。公開後もプライバシーポリシーに沿って運用する。
- [x] 発行者名を公開リポジトリに入れず、GitHubのActionsシークレット `FACTORYTOOLS_PUBLISHER_LEGAL_NAME` に保存済み。氏名は公開用ページでは表示されるため、ページ本文を確認してから公開する。
- [ ] 日英のプライバシーポリシーとサポートページを確認する。公開用ページ案をレビューし、公開時に発行者名が表示されることを確認する。施行日は候補生成日に日本時間で自動設定する。
- [x] 無料のGitHub Pagesを公開先として選択（2026-11-20）。発行者名などの原稿を確定し、公開前にページ内容を確認する。
- [ ] GitHub Pagesを有効にしてプライバシー／サポートページを公開し、安定したHTTPS URLへのアクセスを確認する。
- [ ] EUを含む全地域で配信する方針に沿って、AppleのDSA販売者／非販売者の説明を読み、自分の活動実態から申告内容を判断する。現時点での本人の説明は「趣味として運営する」ですが、Proの買い切り販売（日本価格¥980）もAppleが挙げる判断要素の一つです。この回答だけで非販売者と確定せず、実際の販売・宣伝・事業との関係を踏まえ、App Store Connectで公開前に自己判断してください。個人登録や価格だけでこちらが法的区分を決めることはできません。販売者として申告する場合、Appleが求めるEU向け連絡先の表示・確認条件を先に確認してください。
- [x] Apple native run `44932996378` がcommit `1cb1ec3` で成功。iPhone/iPadアプリ内テスト、iPhone 14枚・iPad 4枚・S/M/Lカード画像6枚の生成、必須キャプチャゲートを確認。新しいiPadホーム／タクトタイム画像は `FactoryTools-AppStore-Assets-Review-2026-11-21/run-44932996378/ipad/` に保存。Watch/archive run `44932996450` は未確認（GitHub Actionsで待機中）。過去のWatch/archive成功 `44930125630`、StoreKit local test `44929262670` は、それぞれ当時のコミットでの結果。どのCI結果も実機接続や署名済みApp Store購入の確認ではありません。
- [ ] iPhone/iPad/Watchの画像候補、ストア文面、Pro価格、プライバシー／サポートページを本人が公開前に確認する。iPhone/iPadのRelease Simulator原本とカード画像は各runの成果物を `FactoryTools-AppStore-Assets-Review-2026-11-21/run-44932996378/` と `.../card-sizes/` に保存。Watchの最新原本はrun `44930125630`。iPhone用見出し付き案14枚（日英各7枚）は `store-artwork-redesign-v5/contact-sheet.jpg`、iPad用案4枚（日英各2枚）は `store-artwork-ipad-v1/contact-sheet.jpg`。どちらも実画面のUIピクセルを描き直さず、見出しや枠を加えた非公開ドラフト。掲載画像・文章・Pro価格・プライバシー／サポート内容は未承認・未提出。全端末画像の一覧は `STORE_REVIEW_GALLERY_JA.html`、日英の掲載文・価格・iPhone/iPad画像の確認ページは `STORE_LISTING_REVIEW_JA.html`。旧iPad接続状態画像は提出不可。プライバシー／サポートページも発行者名を含む非公開・noindexの確認用HTMLで、未公開。

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
