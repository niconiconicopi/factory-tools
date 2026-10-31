# Factory Tools 公開準備ガイド

**現在の状態:** Apple Developer／App Store Connectの値は未設定との認識。Free／ProのVersion 1機能境界、日本を基準ストアとすること（JPY ¥980）、Family Sharingオフは決定済み。商品ID候補は `factorytools.pro.lifetime`。App Store Connectの設定は未完了。

## 公開にかかるApple登録料

App Storeで一般公開するにはApple Developer Programのメンバーシップが必要で、Appleの案内では年99米ドルまたは現地通貨の同等額です。これはアプリ開発用APIやSDKの料金とは別ですが、公開を続けるための年会費です。Developerアプリから登録する場合は、解約するまで毎年自動更新されます。日本円の金額と支払い条件は、登録画面に表示された内容で確認してください。登録・支払いはまだ行われていません。費用を含めて公開するかは公開者が判断します。[Appleの登録料と支払い条件](https://developer.apple.com/jp/help/account/membership/program-enrollment)

登録は、対応地域ならApple Developerアプリを入れたiPhoneまたはiPadからも行えます。登録にはApple Accountの2ファクタ認証と、端末のパスコードまたは生体認証などが必要です。これは登録手続きの方法であり、Xcode Cloudの最初のワークフローを作るMac/Xcode要件は別に残ります。[iPhone/iPadでの登録要件](https://developer.apple.com/help/account/membership/enrolling-in-the-app)

Appleの年会費免除は、一定の条件を満たす非営利団体、認定教育機関、政府機関向けです。個人・個人事業主は対象外で、免除申請者は有料アプリ契約に署名しておらず、アプリでデジタル商品・サービスを販売していない必要があります。Factory Tools Proを買い切りアプリ内購入として販売する計画とは両立しないため、このプロジェクトでは免除を見込まず、年会費を必要な公開コストとして扱います。[Appleの年会費免除条件](https://developer.apple.com/help/account/membership/fee-waivers)

このプロジェクトでは、登録と支払いは**無償でできる実装・文書・ソース検証を終えた後の最後の有料準備段階**に置きます。登録前でも、ソース作業、製品仕様の確定、公開文面の準備、Windows上の静的検証は進められます。Team IDの取得、App Store Connectの商品設定、署名付き提出は登録後の段階です。年会費は年ごとの更新費用であり、Developerアプリで加入したメンバーシップは自動更新です。更新を望まない場合は更新日の少なくとも1日前に解約し、支払い済みの年会費は返金されない点も含めて判断してください。[年会費・更新の説明](https://developer.apple.com/help/account/membership/enrolling-in-the-app)

## 登録前に選ぶ公開者の名義

Apple Developer Programには個人登録と組織登録があります。これは表示名だけの選択ではなく、Appleとの契約者とApp Store上の販売者名に関わります。登録・支払いは最後に保留したまま、どちらの名義で公開するかを先に決めておきます。

| 登録区分 | Appleが案内する主な条件 | App Store上の表示 |
|---|---|---|
| 個人・個人事業主 | Apple Accountの2ファクタ認証、法定年齢、本人の法的氏名・住所・連絡先。本人確認書類を求められる場合がある。D‑U‑N‑S番号は不要 | 個人の法的氏名が販売者として表示される。屋号やアプリ名にはできない |
| 組織 | Appleと契約できる法人等の法的実体、登録を行う人の契約権限、組織のD‑U‑N‑S番号、組織ドメインの業務メール、組織に結び付いた機能する公開Webサイト。追加書類を求められる場合がある | 法的な組織名が販売者として表示される |

AppleはD‑U‑N‑S番号について、多くの地域では無料で取得でき、番号の発行に最大5営業日、その情報がAppleへ届くまでさらに最大2営業日かかると案内しています。個人事業主・単独事業はAppleの案内上、個人として登録します。登録区分や公開者名義は、販売者名の希望と実際の法的資格に合わせて選びます。[Appleの登録要件](https://developer.apple.com/help/account/membership/program-enrollment)、[D‑U‑N‑S番号の確認・申請](https://developer.apple.com/help/account/membership/D-U-N-S)、[開発者名の設定](https://developer.apple.com/help/app-store-connect/create-an-app-record/set-your-developer-name/)

## いま分からなくて問題ない項目

ここにある多くの値は、自分で最初から知っている番号ではありません。Appleの開発者登録をした後、Appleが発行するものや、公開者として決めて登録するものです。

| 項目 | かんたんな説明 | どこで決まるか | 今の状態 |
|---|---|---|---|
| Apple Developer Program | App Storeでアプリを一般公開し、販売するための開発者メンバーシップ | 公開者本人または組織がAppleに登録。Account Holderが契約を管理する | 未登録との認識。Appleの案内は年99米ドルまたは現地通貨額。円での請求額は登録手続き画面で確認。加入は最後の有料準備として保留 |
| 公開者の登録区分・販売者名 | 個人名または法人等の法的名称のどちらをApp Store販売者として表示するか | 個人は法的氏名。組織は法的実体・契約権限・D‑U‑N‑S・組織ドメインの業務メール・機能する公開Webサイトが必要 | 未決定。登録前に名義と要件を確認 |
| Free／Proの機能境界 | どの機能を無料で使え、どの機能をPro購入で解放するか | Version 1の境界は決定済み。無料は基本ツール・基本不良記録・基本履歴・基本Watch/iPad操作・Industrial Dark。Proは独立した生産進捗、OEE、追加ホーム、詳細分析・専門ツール・高度なWatch機能・将来のProテーマ | 決定済み。公開前にアプリ表示とストア説明の一致を確認 |
| Bundle ID | iPhoneアプリを識別する固有番号。Watch版も同じ番号をもとに関連付ける | 公開者のWebドメイン等に合わせて決め、XcodeとApp Store Connectに同じ値を登録。アップロード後は変更できない | 未設定。発行者名義の値が必要 |
| App Store Connect SKU | 顧客には表示されない、App Store Connectでアプリを管理する内部番号 | 候補は `FACTORYTOOLS-IOS-001`。公開者のアカウント内で未使用かを確認してからアプリ記録を作成する | 候補を選定。アカウント内の未使用確認は未実施 |
| Team ID | Apple Developer登録にひも付く10文字のチーム番号 | 登録後、Apple Developerアカウントの「Membership details」に表示される | 未設定。登録後に確認 |
| Pro商品ID | アプリ内で「Factory Tools Pro」を識別する内部番号。購入者に表示する価格とは別物 | 今の候補は `factorytools.pro.lifetime`。App Store Connectの商品を作るときにこの値を使う。保存後は変更できない | 候補をプロジェクトに設定済み。商品登録は未実施 |
| プライバシーURL | アプリが扱うデータについて説明する公開ページの住所 | 内容と公開先を決めてWebで公開し、同じHTTPSアドレスをアプリとApp Store Connectに登録 | 未設定。公開ページが必要 |
| サポートURL | 問い合わせや困ったときの案内を載せる公開ページの住所 | 連絡方法を用意し、問い合わせを受け取れるページをWebで公開 | 未設定。公開ページと連絡先が必要 |
| Pro価格 | 利用者が支払うFactory Tools Proの価格 | 販売価格は**日本向け¥980で確定**。Appleの公式案内でも、日本のカスタム価格例として¥980が紹介されている。App Store Connectに登録し、購入画面で表示を確認する | 方針確定、ストア未設定 |
| 基準ストア価格 | App Storeの各国価格を作る起点となる国・地域と価格 | 日本・JPY ¥980を基準に設定する。他地域はAppleの生成価格を確認し、必要なら個別調整する | 決定済み。実登録と各地域価格の確認は会員登録後 |
| App Store表示言語 | 顧客に見えるストア上のアプリ名・説明文の基本言語 | 英語を基本言語にし、日本語のローカライズを追加する。アプリ内は日本語・英語に対応済み | 方針決定済み。App Store Connectで設定 |
| 公開対象の国・地域 | Factory ToolsとPro購入を利用可能にするApp Storeの国・地域 | V1は日本に加え、Appleが配信を認める全地域で公開する。英語をApp Storeの基本言語、日本語を追加ローカライズにし、アプリとPro商品で全配信可能地域を選ぶ。Appleが追加する将来の地域は、価格・法令確認後に別途追加する | 方針決定済み。App Store Connectで設定・確認 |
| 対応プラットフォーム | アプリをダウンロード可能にするApple端末 | V1はiPhone、iPad、ペアリングしたApple Watch。未検証のMacとVision Proへの互換配信はオフにする | App Store ConnectのMac／Vision Pro互換配信をオフにし、設定を確認 |
| EU Digital Services Actの販売者ステータス | EU向けにApp Storeで配信する際の販売者／非販売者の申告 | 公開者本人が事業活動に照らして判定し、App Store Connectで申告する。販売者の場合、AppleがEU向け商品ページに表示する連絡先を検証する。[Appleの公式要件](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) | 未申告。公開者の法的判断と、Appleが求める掲載連絡先の確認が必要 |
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
3. 追加費用をかけずに、Windows上のソース検証と文書の準備を終える。ネイティブ検証は、公開GitHubリポジトリで無料のmacOS runnerを使う[Apple native checks](https://github.com/niconiconicopi/factory-tools/actions/runs/41244759649)で実施でき、MacやApple Developer登録は不要。現在、iPhoneとiPadのSimulator XCTestが各221件、共有Core XCTestが47件、Watch Simulatorビルド、iPhone/iPadアプリとWatchを含む未署名archiveまで成功済み。Xcode Cloudは任意であり、最初のワークフロー設定にXcodeが動くMacが必要なため、このプロジェクトの無料検証には使わない。
4. 準備が整った最後の有料段階でApple Developer Programに登録する。登録を進めるかは公開者が判断し、費用の発生する操作は無断で行わない。
5. 登録後にTeam IDを確認し、署名を設定する。App Store Connectで商品、価格、Family Sharing、アプリ情報を登録し、EU公開前にDSA販売者ステータスと掲載連絡先を申告・確認する。
6. 公開したプライバシー／サポートページとHTTPSアドレスを設定し、App Review連絡先を登録する。
7. 署名済みアプリの購入画面で日本向け¥980を確認し、購入・復元、Watch/iPad連携を確認する。
8. 年齢評価、プライバシー、輸出コンプライアンスの質問に回答し、必要なスクリーンショットとWatch情報を揃えて提出する。

各値がそろった後は、リポジトリ内の `Scripts/validate_static.py --release-preflight` で入力形式と設定の不足を確認できる。これは値の所有者、Webページが実際に公開されているか、App Store Connectの実設定、署名済みアプリの動作までは確認しない。

## Appleの説明

- [Bundle IDとアプリ情報](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Apple DeveloperのTeam ID](https://developer.apple.com/help/glossary/team-id/)
- [App Store Connectで非消耗型IAPを作成する](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases)
- [IAPの商品IDについて](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
- [IAP価格の設定](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase)
- [Appleの日本向け¥980カスタム価格の例](https://developer.apple.com/jp/videos/play/tech-talks/110364/)
