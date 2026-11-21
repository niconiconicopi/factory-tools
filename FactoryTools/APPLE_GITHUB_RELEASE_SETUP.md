# GitHubからApp Store Connectへアップロードする手順

このリポジトリには、Macを手元に置かずに署名付きiPhone/iPad/WatchビルドをApp Store Connectへアップロードする手動ワークフローを用意しています。Apple Developer Program登録、発行者設定、App Store Connect APIキーが揃うまでは実行できません。通常のpushやPull Requestでは配布ビルドもアップロードも始まりません。

ワークフローは、iPhone・iPad Simulatorの回帰テスト、共有Coreテスト、Watch Simulatorビルドがすべて成功した後にだけApp Store Connect APIキーを読み込みます。検証が失敗した場合は秘密鍵をrunnerへ渡しません。

ホスト型の通常テストとアップロード前テストでは、`testLocalLifetimePurchaseUnlocksAndClearingTransactionsRevokesPro` だけを実行対象から外します。これは StoreKit の購入・復元実装を飛ばすためではなく、XcodeのヘッドレスSimulator実行で `SKTestSession` の構成が失敗する既知の問題を分離するためです。購入マネージャーの通常回帰テストは引き続き実行します。この除外は実際のStoreKit購入・復元の成功を証明しません。StoreKit統合の確認と、最終的なApp Store Connect Sandbox/TestFlight購入・復元確認は別ゲートです。

## できること / しないこと

- GitHub ActionsのmacOS runnerでiPhone/iPad Simulatorテスト、共有Coreテスト、Watchビルド、iOS archiveを実行します。
- App Store Connect APIキーでXcodeの自動署名・プロビジョニングを行い、完成した署名付きビルドをApp Store Connectへアップロードします。
- ワークフローの確認欄は初期状態でオフです。オンにした手動実行だけがアップロードします。
- アップロード後のApple側処理やApp Store審査への提出は自動で行いません。
- App Store Connectへの登録、IAP・価格・地域・画像の設定、審査申請は別途必要です。

Appleは、App Store Connect APIキーを使った `xcodebuild` のヘッドレス自動署名と、`xcodebuild -exportArchive` によるアップロードを案内しています。[Xcode 13のAPIキー署名機能](https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes)、[Xcodeからのクラウド署名と配布](https://developer.apple.com/videos/play/wwdc2021/10204/)、[App Store Connectへのビルドアップロード](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

## Apple側で先に用意するもの

1. Apple Developer Program登録と、公開者名義の確定。
2. App Store Connect上のアプリ記録。iPhoneアプリの明示Bundle IDを登録します。
3. `factorytools.pro.lifetime` の非消費型IAP、¥980の日本基準価格、販売地域、Family Sharingオフの設定。
4. App Store Connect APIをまだ有効にしていない場合は、Account Holderとして利用申請します。Appleによる確認後、**Team API Key**を作成し、Xcodeの自動署名が使える **Admin** 権限を選びます。チームキーはアカウント内の全アプリに適用されるため、このプロジェクト専用の秘密として管理してください。Key IDとIssuer IDも控えます。`.p8` 秘密鍵は一度しかダウンロードできないため、安全な保管場所に保存し、公開リポジトリやチャットへ置かないでください。
5. プライバシーとサポートページを公開し、インターネットから到達できるHTTPS URLを決めます。

Appleの自動署名では、XcodeがアプリとWatchの配布プロビジョニングを管理します。Appleは `xcodebuild` のAPIキー認証を使ったヘッドレス自動署名を案内しており、クラウド配布署名はAdminまたはAccount Holderの権限を必要とします。個人登録では公開者本人がAccount Holderです。このワークフローでは Team API Key を用いるため、Admin権限を選ぶ手順にしています。プロビジョニングプロファイルや証明書をGitへ登録する方式は採用していません。[Xcode 13のAPIキー署名機能](https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes)、[App Store Connect APIキーの作成と権限](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)、[App Storeプロファイルと自動署名](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)

## GitHubリポジトリへ登録する値

GitHubの公開リポジトリで **Settings → Secrets and variables → Actions** を開き、以下を追加します。

### Repository variables

| 名前 | 値 |
|---|---|
| `FACTORYTOOLS_APP_BUNDLE_ID` | 暫定候補 `com.niconiconicopi.factorytools`。Apple Developerアカウントで利用可能性・登録可否を確認し、必要なら初回アップロード前に変更 |
| `APPLE_TEAM_ID` | 任意の上書き値。通常は空欄でよく、Xcodeプロジェクトに登録済みのTeam IDをワークフローが自動使用 |
| `FACTORYTOOLS_PRIVACY_POLICY_URL` | 公開済みプライバシーポリシーHTTPS URL |
| `FACTORYTOOLS_SUPPORT_URL` | 連絡先を含む公開済みサポートHTTPS URL |
| `FACTORYTOOLS_PRO_PRODUCT_ID` | `factorytools.pro.lifetime` |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect APIキーのKey ID |
| `APP_STORE_CONNECT_ISSUER_ID` | チームAPIキーのIssuer ID |

### Repository secret

| 名前 | 値 |
|---|---|
| `APP_STORE_CONNECT_API_KEY_CONTENTS` | ダウンロードした `.p8` APIキーの全文。`BEGIN PRIVATE KEY` と `END PRIVATE KEY` の行を含めます |
| `FACTORYTOOLS_PUBLISHER_LEGAL_NAME` | 公開ページに載せる発行者の氏名。公開リポジトリの原稿に直接書かず、Actions secretとして保管します。ページ公開後は公開表示されます |

`.p8` の内容やパスワード、認証情報をこのチャット、Issue、コミット、Actionsログに貼らないでください。ワークフローはその秘密値を一時ファイルへ書き、Xcodeコマンドの後にGitHub runnerの破棄領域とともに消します。

発行者名は `FACTORYTOOLS_PUBLISHER_LEGAL_NAME` としてGitHub Actions secretへ登録済みです。値は公開リポジトリのファイルには書かれていません。公開ワークフローでサイトを公開すると、そのページ上では表示されます。名前を変更する場合はGitHubの `Settings → Secrets and variables → Actions` からsecretを更新してください。ページ本文を確認し、公開に同意するまではワークフローを実行しないでください。

## 手動アップロード

1. [Release preflight](RELEASE_READINESS_AUDIT.md#release-preflight-evidence)でソース設定を確認します（候補HTTPS URLを含む静的検査は現在通過）。プライバシー／サポートページの内容を確認し、発行者名はActions secretに設定します。施行日は候補生成時に日本時間で自動設定されます。GitHub Pages公開後にURL到達を確認します。暫定Bundle IDのApple側利用可否とアプリ/IAP設定は別途確認します。
2. GitHubの **Actions → Apple App Store upload → Run workflow** をmainブランチから開きます。
3. Appleへのアップロードを行うときだけ、`confirm_app_store_connect_upload` をオンにします。対象バージョンと、App Store Connectで未使用のビルド番号を入力します。
4. 成功したらApp Store Connectのビルド処理完了を待ちます。ワークフローは審査提出をしません。

初期値のまま実行した場合は「アップロードなし」で終了し、秘密情報を読み込まず、Appleへの通信やビルドを開始しません。

## プライバシー／サポートページの公開

公開リポジトリでは、GitHub Freeの範囲でGitHub Pagesを使えます。リポジトリの **Settings → Pages → Build and deployment → Source** で **GitHub Actions** を選ぶと、静的ページ用の準備ができます。[GitHub Pagesの利用条件と設定](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)

発行者は2026-11-20にGitHub Pagesを公開先として選択しました。プライバシー候補URL `https://niconiconicopi.github.io/factory-tools/privacy.html` とサポート候補URL `https://niconiconicopi.github.io/factory-tools/support.html` はXcodeのDebug/Release設定へ登録済みです。ページはまだ公開していません。App Store Connectや配布ビルドに使う前に、公開コピーの確認、GitHub Pagesの有効化、HTTPSでの到達確認が必要です。発行者名は公開リポジトリに書かず、GitHub Actionsシークレット `FACTORYTOOLS_PUBLISHER_LEGAL_NAME` から候補へ注入します。施行日は公開用候補の生成日に日本時間で自動設定されます。

ワークフロー **Publish privacy and support pages** は手動実行だけで、公開確認欄の初期値はオフです。確認をオンにした場合も、mainブランチからのみ動き、発行者名と連絡先などが揃って公開コピー検証に通るまでデプロイされません。施行日は候補生成時に日本時間で設定されます。通常のpushでは公開しません。GitHub Pagesには訪問者IPアドレスをセキュリティ目的で記録する運用があるため、ホスティング側の取り扱いと必要な告知を公開者が確認してください。[GitHub Pagesの利用制限](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)、[GitHub Pagesのアクセス記録](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)

## 残るApple側の確認

GitHubの成功は署名付きバイナリのアップロードを示します。StoreKit購入/復元、Watch通信、iPadローカルネットワーク、実機表示は別途確認が必要です。実機が用意できない限り、それらの動作確認を完了扱いにはしません。また、App Store Connectの商用設定、スクリーンショット、年齢・プライバシー・輸出コンプライアンス回答、App Review連絡先は公開者が仕上げます。
