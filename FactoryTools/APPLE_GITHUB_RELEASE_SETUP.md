# GitHubからApp Store Connectへアップロードする手順

このリポジトリには、Macを手元に置かずに署名付きiPhone/iPad/WatchビルドをApp Store Connectへアップロードする手動ワークフローを用意しています。Apple Developer Program登録、発行者設定、App Store Connect APIキーが揃うまでは実行できません。通常のpushやPull Requestでは配布ビルドもアップロードも始まりません。

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
4. App Store ConnectのチームAPIキーと、Xcodeが署名に使える権限。鍵の `.p8` ファイルは一度しかダウンロードできないため、公開リポジトリやチャットへ置かず保管します。
5. プライバシーとサポートページを公開し、インターネットから到達できるHTTPS URLを決めます。

Appleの自動署名では、XcodeがアプリとWatchの配布プロビジョニングを管理します。プロビジョニングプロファイルや証明書をGitへ登録する方式は採用していません。[App Storeプロファイルと自動署名](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)

## GitHubリポジトリへ登録する値

GitHubの公開リポジトリで **Settings → Secrets and variables → Actions** を開き、以下を追加します。

### Repository variables

| 名前 | 値 |
|---|---|
| `FACTORYTOOLS_APP_BUNDLE_ID` | 公開者が所有するアプリBundle ID |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `FACTORYTOOLS_PRIVACY_POLICY_URL` | 公開済みプライバシーポリシーHTTPS URL |
| `FACTORYTOOLS_SUPPORT_URL` | 連絡先を含む公開済みサポートHTTPS URL |
| `FACTORYTOOLS_PRO_PRODUCT_ID` | `factorytools.pro.lifetime` |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect APIキーのKey ID |
| `APP_STORE_CONNECT_ISSUER_ID` | チームAPIキーのIssuer ID |

### Repository secret

| 名前 | 値 |
|---|---|
| `APP_STORE_CONNECT_API_KEY_CONTENTS` | ダウンロードした `.p8` APIキーの全文。`BEGIN PRIVATE KEY` と `END PRIVATE KEY` の行を含めます |

`.p8` の内容やパスワード、認証情報をこのチャット、Issue、コミット、Actionsログに貼らないでください。ワークフローはその秘密値を一時ファイルへ書き、Xcodeコマンドの後にGitHub runnerの破棄領域とともに消します。

## 手動アップロード

1. [Release preflight](RELEASE_READINESS_AUDIT.md#release-preflight-evidence)の5つのプロジェクト項目が埋まり、Apple側のアプリ/IAP設定とURL公開が完了していることを確認します。
2. GitHubの **Actions → Apple App Store upload → Run workflow** を開きます。
3. Appleへのアップロードを行うときだけ、`confirm_app_store_connect_upload` をオンにします。対象バージョンと、App Store Connectで未使用のビルド番号を入力します。
4. 成功したらApp Store Connectのビルド処理完了を待ちます。ワークフローは審査提出をしません。

初期値のまま実行した場合は「アップロードなし」で終了し、秘密情報を読み込まず、Appleへの通信やビルドを開始しません。

## 残るApple側の確認

GitHubの成功は署名付きバイナリのアップロードを示します。StoreKit購入/復元、Watch通信、iPadローカルネットワーク、実機表示は別途確認が必要です。実機が用意できない限り、それらの動作確認を完了扱いにはしません。また、App Store Connectの商用設定、スクリーンショット、年齢・プライバシー・輸出コンプライアンス回答、App Review連絡先は公開者が仕上げます。
