# Factory Tools 公開準備ガイド

迷ったときの順番は[公開者向けチェックリスト](PUBLISHER_RELEASE_CHECKLIST_JA.md)にまとめています。

**現在の状態（2026-11-22）:** Apple Developer Program登録完了とTeam ID受領を報告済み。Team IDはXcodeプロジェクトへ設定し、GitHub Actionsが自動使用します。App Store Connectは未設定です。Free／ProのVersion 1機能境界、日本を基準ストアとすること（JPY ¥980）、Family Sharingオフは決定済み。商品ID候補は `factorytools.pro.lifetime`。プライバシー／サポートページとストア画像・掲載文は、本人確認用の非公開プレビューを用意済みで、公開・提出前の確認が必要です。Apple native run `44941781304` はiPhone/iPadテスト、14枚のiPhone撮影、S/M/L画像、4枚のiPad撮影と必須ゲートを通過。Watch/archive run `44941781248` はCoreテスト、Watch Debug/Releaseビルド、日英6画面、署名なしiOS/iPadアーカイブを通過しました。撮影原本と更新済みプレビューは `FactoryTools-AppStore-Assets-Review-2026-11-21/` に保存。WindowsではPython回帰テスト111件、リリース事前検査、ページ生成チェック、ソース衛生検査が通過。アプリソースrevision `64bdea1` 以降の現行GitHub mainには文書更新のみが追加されています。Windows検査はSwiftをコンパイルしません。署名、実機ペアリング、App Store Connect Sandboxでの購入・復元はまだ確認していません。

## 次に行う作業：アプリIDを1件登録

Apple Developer Programの登録が済んだので、次はAppleの画面でFactory Tools用の識別子を登録します。これはアプリを公開したり料金を発生させたりする操作ではありません。Bundle ID候補をアカウントで確保するための準備です。

1. [Apple Developerアカウント](https://developer.apple.com/account/)に、Factory ToolsのTeam ID `5NKGZ84ZW3` のチームでサインインします。
2. **Certificates, Identifiers & Profiles → Identifiers** を開き、左上の **＋** を選びます。
3. **App IDs** を選んで続け、種類が **App** であることを確認して続けます。
4. Descriptionに `Factory Tools`、Bundle IDは **Explicit** を選び、`com.niconiconicopi.factorytools` を入力します。
5. 内容を確認して **Register** を選びます。Explicit App IDではIn-App Purchaseは既定で有効です。Push Notifications、Sign in with Apple、App Groupsなど、このアプリで使わない機能は追加しません。

Appleの公式手順では、明示Bundle IDはXcode側のBundle IDと一致させます。[App ID登録手順](https://developer.apple.com/help/account/identifiers/register-an-app-id/)。もしBundle IDが使用済みで登録できなければ、別のIDを作る前に止めてください。Xcode設定、Watch識別子、提出設定をまとめて同じIDへ変更します。成功したら「App ID登録できた」と知らせてもらえれば、次のApp Store Connect記録作成へ進みます。パスワードや認証コードをチャットに送る必要はありません。

## 公開にかかるApple登録料

App Storeで一般公開するためのApple Developer Program登録は完了したと発行者から報告を受けています（2026-11-18）。Appleの案内では会費は年99米ドルまたは現地通貨の同等額です。これはアプリ開発用APIやSDKの料金とは別の年会費です。更新日と請求額はAppleのアカウントページで確認してください。[Appleの登録料と支払い条件](https://developer.apple.com/jp/help/account/membership/program-enrollment)

Apple公式はApple Developer Programへの登録をWebとDeveloperアプリの両方で受け付けています。個人登録では本人の法的氏名がApp Storeの販売者名になります。本人確認書類や認証情報はAppleの画面だけに入力してください。アプリから登録する方法では、パスコード等を設定したiPhone/iPadまたは対応Mac、最新のDeveloperアプリ、iCloudへのサインインが必要です。[Apple Developer Programの登録方法](https://developer.apple.com/help/account/membership/program-enrollment/)、[Developerアプリでの登録要件](https://developer.apple.com/help/account/membership/enrolling-in-the-app)

署名付きビルドとApp Store Connectへのアップロードは、Team ID、App Store Connectアプリ記録、APIキーなどの設定後に既存のGitHub Actions手動ワークフローで実行する設計です。Xcode Cloudの初回設定に必要なMac/Xcodeとは別経路なので、Factory Toolsの提出用ビルドのためにMacを購入・レンタルする計画はありません。[GitHub Actionsからのアップロード手順](APPLE_GITHUB_RELEASE_SETUP.md)

発行者やテスターがiPhone・Watch・iPadを持っていなくても、登録後にTestFlightで外部テスターへ配布し、手持ちの実機で確認してもらう方法があります。テスター募集の手順、日英の確認項目、失敗時の報告方法は[TestFlight実機テスト計画](TESTFLIGHT_FIELD_TEST_PLAN.md)にまとめました。TestFlightの購入テストはサンドボックスで行われ、実際の請求はありません。Apple Developer登録、App Store Connect設定、および最初の外部テスト用ビルドの審査は必要です。[TestFlightの外部テスター招待](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)、[TestFlightでのIAPテスト](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/)

Appleの年会費免除は、一定の条件を満たす非営利団体、認定教育機関、政府機関向けです。個人・個人事業主は対象外で、免除申請者は有料アプリ契約に署名しておらず、アプリでデジタル商品・サービスを販売していない必要があります。Factory Tools Proを買い切りアプリ内購入として販売する計画とは両立しないため、このプロジェクトでは免除を見込まず、年会費を必要な公開コストとして扱います。[Appleの年会費免除条件](https://developer.apple.com/help/account/membership/fee-waivers)

発行者は2026-11-18にApple Developer Program登録完了を報告し、Team IDも共有済みです。どちらもXcodeプロジェクトへ反映しました。次はApp Store Connectのアプリ／Pro商品設定と署名付き提出の準備です。年会費は年ごとの更新費用であり、Developerアプリから加入した場合は自動更新です。更新を望まない場合は更新日の少なくとも1日前に解約し、支払い済みの年会費は返金されない点に注意してください。[年会費・更新の説明](https://developer.apple.com/help/account/membership/enrolling-in-the-app)

## 決定済みの登録名義

Apple Developer Programには個人登録と組織登録があります。これは表示名だけの選択ではなく、Appleとの契約者とApp Store上の販売者名に関わります。発行者は個人登録を選択し、2026-11-18に登録完了を報告しました。個人の法的氏名がApp Storeの販売者名になります。

| 登録区分 | Appleが案内する主な条件 | App Store上の表示 |
|---|---|---|
| 個人・個人事業主 | Apple Accountの2ファクタ認証、法定年齢、本人の法的氏名・住所・連絡先。本人確認書類を求められる場合がある。D‑U‑N‑S番号は不要 | 個人の法的氏名が販売者として表示される。屋号やアプリ名にはできない |
| 組織 | Appleと契約できる法人等の法的実体、登録を行う人の契約権限、組織のD‑U‑N‑S番号、組織ドメインの業務メール、組織に結び付いた機能する公開Webサイト。追加書類を求められる場合がある | 法的な組織名が販売者として表示される |

発行者は個人登録を選択済みです。Apple登録には本人の法的氏名・住所・連絡先が必要で、個人の法的氏名がApp Storeの販売者名として表示されます。登録情報はAppleの手続き画面に入力し、チャットには送らないでください。[Appleの登録要件](https://developer.apple.com/help/account/membership/program-enrollment)、[開発者名の設定](https://developer.apple.com/help/app-store-connect/create-an-app-record/set-your-developer-name/)

## EU向け販売者区分（DSA）

Version 1は全配信地域を選択済みのため、EU配信も含まれます。App Store ConnectでEUデジタルサービス法（DSA）の販売者区分を申告します。個人登録であることだけでは「販売者／非販売者」は決まらず、活動の実態を公開者本人が自己判断します。

Appleが示す判断材料は、アプリ内購入などの収益、消費者に向けた商業活動・宣伝、VAT登録、アプリを仕事・事業・職業として開発・販売しているか等です。これは例示であり、単一項目だけで自動判定する基準ではありません。趣味で、商業化する意図がなく作った場合は非販売者となる可能性がありますが、Factory Toolsは買い切りProを¥980で販売する計画があるため、趣味という説明だけでは非販売者と確定できません。Pro販売を含めた実態について公開者本人が最終自己評価し、App Store Connectに申告する必要があります。Appleは一般情報であり法的助言ではないと明記しています。判断が難しい場合は、必要に応じて法律の専門家に確認してください。[AppleのDSA販売者要件・判断材料・必要情報](https://developer.apple.com/jp/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)

| Apple Connectでの申告 | Appleの案内上の結果 |
|---|---|
| 販売者 | 個人アカウントでは住所または私書箱・電話番号・メールアドレスがEU向け商品ページに表示される。Appleによる連絡先確認と住所確認書類、支払い口座情報が必要 |
| 非販売者 | 販売者の連絡先は表示されず、EUの消費者に、契約に関する消費者保護上の権利が適用されない旨が表示される |

販売者と申告する場合、住所・電話番号は商品ページ上で公開されます。私書箱を使う場合も本人との関係を示す書類が必要です。自宅住所や電話番号はこのチャットや公開リポジトリに書かず、使う場合はAppleの手続き画面へ直接入力してください。サポートメールとして選んだアドレスをDSA用にも使うかは、公開者が別途確認します。

## いま分からなくて問題ない項目

ここにある多くの値は、自分で最初から知っている番号ではありません。Appleの開発者登録をした後、Appleが発行するものや、公開者として決めて登録するものです。

| 項目 | かんたんな説明 | どこで決まるか | 今の状態 |
|---|---|---|---|
| Apple Developer Program | App Storeでアプリを一般公開し、販売するための開発者メンバーシップ | 公開者本人または組織がAppleに登録。Account Holderが契約を管理する | 個人登録完了とTeam ID受領の報告あり（2026-11-18）。Team IDはXcode設定済み。App Store Connect設定が次の作業 |
| 公開者の登録区分・販売者名 | 個人名または法人等の法的名称のどちらをApp Store販売者として表示するか | 個人登録では本人の法的氏名がApp Storeの販売者名に表示される | 個人登録を選択済み。法的氏名はAppleの登録画面に入力。チャット・公開文面には入力しない |
| Free／Proの機能境界 | どの機能を無料で使え、どの機能をPro購入で解放するか | Version 1の境界は決定済み。無料は基本ツール・基本不良記録・基本履歴・基本Watch/iPad操作・Industrial Dark。Proは独立した生産進捗、OEE、追加ホーム、詳細分析・専門ツール・高度なWatch機能・将来のProテーマ | 決定済み。公開前にアプリ表示とストア説明の一致を確認 |
| Bundle ID | iPhoneアプリを識別する固有番号。Watch版も同じ番号をもとに関連付ける | 公開者のWebドメイン等に合わせて決め、XcodeとApp Store Connectに同じ値を登録。アップロード後は変更できない | 暫定候補 `com.niconiconicopi.factorytools` をDebug/Releaseに設定済み。Apple Developerで登録可能かを確認し、初回アップロード前に確定する |
| App Store Connect SKU | 顧客には表示されない、App Store Connectでアプリを管理する内部番号 | 候補は `FACTORYTOOLS-IOS-001`。公開者のアカウント内で未使用かを確認してからアプリ記録を作成する | 候補を選定。アカウント内の未使用確認は未実施 |
| Team ID | Apple Developer登録にひも付く10文字のチーム番号 | Apple Developerアカウントにサインインし、「Membership details」を開く | 発行者から値を受領しXcodeプロジェクトの共有設定へ追加済み。アップロード時はそこから自動取得。別アカウントを使う場合のみGitHub Actions変数で上書き |
| Pro商品ID | アプリ内で「Factory Tools Pro」を識別する内部番号。購入者に表示する価格とは別物 | 今の候補は `factorytools.pro.lifetime`。App Store Connectの商品を作るときにこの値を使う。保存後は変更できない | 候補をプロジェクトに設定済み。商品登録は未実施 |
| プライバシーURL | アプリが扱うデータについて説明する公開ページの住所 | 内容と公開先を決めてWebで公開し、同じHTTPSアドレスをアプリとApp Store Connectに登録 | 未設定。公開ページが必要 |
| サポートURL | 問い合わせや困ったときの案内を載せる公開ページの住所 | 連絡方法を用意し、問い合わせを受け取れるページをWebで公開 | メール窓口は `azalea.fortask@outlook.jp` に決定し、テストメール受信を確認。日英の下書きに反映済み。継続的な監視・日英返信の確認と公開ページ・URLは未完了 |
| Pro価格 | 利用者が支払うFactory Tools Proの価格 | 販売価格は**日本向け¥980で確定**。Appleの公式案内でも、日本のカスタム価格例として¥980が紹介されている。App Store Connectに登録し、購入画面で表示を確認する | 方針確定、ストア未設定 |
| 基準ストア価格 | App Storeの各国価格を作る起点となる国・地域と価格 | 日本・JPY ¥980を基準に設定する。他地域はAppleの生成価格を確認し、必要なら個別調整する | 決定済み。実登録と各地域価格の確認は会員登録後 |
| App Store表示言語 | 顧客に見えるストア上のアプリ名・説明文の基本言語 | 英語を基本言語にし、日本語のローカライズを追加する。アプリ内は日本語・英語に対応済み | 方針決定済み。App Store Connectで設定 |
| 公開対象の国・地域 | Factory ToolsとPro購入を利用可能にするApp Storeの国・地域 | V1は日本に加え、Appleが配信を認める全地域で公開する。英語をApp Storeの基本言語、日本語を追加ローカライズにし、アプリとPro商品で全配信可能地域を選ぶ。Appleが追加する将来の地域は、価格・法令確認後に別途追加する | 方針決定済み。App Store Connectで設定・確認 |
| 対応プラットフォーム | アプリをダウンロード可能にするApple端末 | V1はiPhone、iPad、ペアリングしたApple Watch。未検証のMacとVision Proへの互換配信はオフにする | App Store ConnectのMac／Vision Pro互換配信をオフにし、設定を確認 |
| EU Digital Services Actの販売者ステータス | App Store ConnectでEU向けの販売者／非販売者を申告する項目 | Appleの案内では、EUで配信しない場合も販売者ステータスの申告が必要。個人登録であることだけでは判定できず、公開者本人が活動内容から判断する。販売者の場合は、住所または私書箱、電話番号、メールアドレスをEU向け商品ページに表示し、本人確認し、支払い口座情報も登録する。[Appleの公式要件](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) | 未申告。公開者の法的判断と、Appleが求める掲載連絡先・支払い情報の確認が必要 |
| App Storeの主カテゴリ | App Storeでアプリを探すときの主な分類 | 工場の生産・現場業務を支援するため「ビジネス」を選ぶ。V1では副カテゴリを追加しない | 選定済み。登録時に確認 |
| Family Sharing | 家族のApple AccountにもPro購入を共有するか | Version 1ではオフ。オンにすると購入者が共有を許可した場合に購入者以外の最大5人が使える。人数を開発者が設定する機能ではなく、Appleのファミリーグループに従う。App Store Connectでオンにした後はオフに戻せない | 方針確定。App Store Connectでもオフを確認 |

Bundle IDはアプリの識別子で、Pro商品IDはアプリ内購入の識別子です。Team IDはAppleがアカウントに発行する番号です。これらは別々の値です。

Family SharingはVersion 1ではオフにします。購入者本人は同じApple Accountで使う自分のiPhone、iPad、WatchにProを復元できます。オンにすると購入者以外の家族最大5人に共有できますが、「3人まで」のように開発者が人数を絞る設定はありません。共有する家族の管理はAppleのファミリーグループに従います。App Store Connectで誤ってオンにしないよう商品設定時に確認します。オンにした後は無効へ戻せません。[Family Sharingの設定と制約](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/)

## Macを持たない場合のAppleビルド

Apple Developer Programには、Xcode Cloudの計算時間が**月25時間分**含まれます。通常のビルドや自動テストをAppleのクラウドで実行でき、メンバーシップ以外のビルド料金は発生しません。追加の有料計算時間もありますが、購入しない方針です。利用上限が近づいたら任意のビルドを止めます。

最初のXcode Cloudワークフロー作成には、Xcodeが動くMacとリモートGitリポジトリが必要です。Macを用意しない場合の別案として、GitHub Actionsでビルドとシミュレーター検証を行うワークフローを準備済みです。公開リポジトリなら標準macOSランナーを無料で実行できます。非公開リポジトリも、GitHub Freeの含有計算枠を使う手段がありますが、アカウントに有効な支払い方法がないか、超過課金を止める予算上限を設定してから、手動実行を有効にします。公開・非公開それぞれの条件は [`XCODE_CLOUD_RUNBOOK.md`](XCODE_CLOUD_RUNBOOK.md) を参照してください。[Apple Developer Programに含まれる機能](https://developer.apple.com/programs/whats-included/) と [Xcode Cloud](https://developer.apple.com/xcode-cloud/)、[GitHubのmacOSランナー料金](https://docs.github.com/en/billing/reference/actions-runner-pricing)

## 公開までに必要な順番

1. `PRODUCT_DECISIONS.md` の確定したFree／Pro境界と、アプリ・ストア説明の一致を確認する。
2. 料金が発生しない実装・文書・ソース検証を完了し、発行者名義で使うBundle ID、商品ID、公開連絡先、プライバシー／サポートページの内容を準備する。
3. 追加費用をかけずに、Windows上のソース検証と文書の準備を進める。最新のローカル検証はPythonテスト111件、静的構造検査（Swift 69ファイル・XCTestソース289件・日英445文字列）、公開ページ生成一致、ソース衛生、差分整合性が通過しています。アプリソースrevision `64bdea1` の [Apple native run 44941781304](https://github.com/niconiconicopi/factory-tools/actions/runs/44941781304) はiPhone/iPadテストと日英Release撮影、必須ゲートを通過し、[Watch/archive run 44941781248](https://github.com/niconiconicopi/factory-tools/actions/runs/44941781248) も共有Coreテスト、Watch Debug/Releaseビルド、日英Watch画面6枚とOCR、Watch入り未署名archiveを通過しました。StoreKitの自動テスト [run 44929262670](https://github.com/niconiconicopi/factory-tools/actions/runs/44929262670) は模擬買い切り取引によるPro解除と取引消去後の解除取り消しに成功しています。これらはSimulator／未署名ビルドとローカルStoreKitテストの証拠であり、実機、表示される購入シート、App Store Connect Sandbox／TestFlightでの署名購入・復元の確認ではありません。掲載用の日英文面と画像案は非公開の `STORE_LISTING_REVIEW_JA.html` で確認できます。Xcode Cloudは任意であり、初回設定にはMacとXcodeが必要なため使用しません。
4. Apple Developer Program登録は発行者から完了報告を受けており、Team IDもXcodeプロジェクトへ設定済み。通常はGitHub Actionsへの重複登録は不要です。
5. Bundle IDの利用可能性を確認してApp Store ConnectにアプリとPro商品を作成し、APIキーと署名設定を行う。商品、価格、Family Sharing、アプリ情報を登録し、EU配信の有無にかかわらずDSA販売者ステータスを申告する。販売者と判断した場合は、EU向け商品ページに表示する連絡先を本人確認し、支払い口座情報も登録する。
6. 公開したプライバシー／サポートページとHTTPSアドレスを設定し、App Review連絡先を登録する。
7. 署名済みアプリの購入画面で日本向け¥980を確認し、購入・復元、Watch/iPad連携を確認する。
8. 年齢評価、プライバシー、輸出コンプライアンスの質問に回答し、必要なスクリーンショットとWatch情報を揃えて提出する。2027年4月以降の提出では、iPhone Duoの外側・内側ディスプレイ用スクリーンショットも必要です。

各値がそろった後は、リポジトリ内の `Scripts/validate_static.py --release-preflight` で入力形式と設定の不足を確認できる。これは値の所有者、Webページが実際に公開されているか、App Store Connectの実設定、署名済みアプリの動作までは確認しない。

## Appleの説明

- [Bundle IDとアプリ情報](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Apple DeveloperのTeam ID](https://developer.apple.com/help/glossary/team-id/)
- [App Store Connectで非消耗型IAPを作成する](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases)
- [IAPの商品IDについて](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
- [IAP価格の設定](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase)
- [Appleの日本向け¥980カスタム価格の例](https://developer.apple.com/jp/videos/play/tech-talks/110364/)

