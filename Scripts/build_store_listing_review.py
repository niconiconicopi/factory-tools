"""Build a private, source-backed App Store content review page.

The output is a review aid, not an App Store screenshot or a published page.
All store copy is read from FactoryTools/APP_STORE_METADATA_DRAFT.md and all
promotional images are the current private layouts based on genuine captures.
"""

from __future__ import annotations

import html
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "FactoryTools-AppStore-Assets-Review-2026-11-21"
METADATA = ROOT / "FactoryTools" / "APP_STORE_METADATA_DRAFT.md"
OUTPUT = ASSET_ROOT / "STORE_LISTING_REVIEW_JA.html"
GALLERY_OUTPUT = ASSET_ROOT / "STORE_REVIEW_GALLERY_JA.html"
ART_DIR = "store-artwork-redesign-v5"
IPHONE_CAPTURE_DIR = "run-44941781304/iphone"
WATCH_CAPTURE_DIR = "run-44941781248/watch"
CARD_CAPTURE_DIR = "run-44941781304/card-sizes"
SCREENSHOTS = [
    ("01-home", "Home"),
    ("02-counter-quick-add", "Quick Add"),
    ("03-cycle-time", "Cycle Time"),
    ("04-defect-counter", "Defect Counter"),
    ("05-counter-history", "Count History"),
    ("06-takt-time", "Takt Time"),
    ("07-process-capability", "Process Capability"),
]
IPAD_SCREENSHOTS = [
    ("ipad-home", "Home"),
    ("ipad-takt-time", "Takt Time"),
]
IPAD_CAPTURE_DIR = "run-44941781304/ipad"


def extract_field(section: str, name: str) -> str:
    match = re.search(
        rf"\*\*{re.escape(name)}\*\*\s*\n(.*?)(?=\n\n\*\*|\Z)",
        section,
        re.S,
    )
    if not match:
        raise ValueError(f"Missing metadata field: {name}")
    return match.group(1).strip()


def extract_locale(markdown: str, heading: str, next_heading: str) -> dict[str, str]:
    start = markdown.index(heading) + len(heading)
    end = markdown.index(next_heading, start)
    section = markdown[start:end]
    return {
        "name": extract_field(section, "Name"),
        "subtitle": extract_field(section, "Subtitle"),
        "keywords": extract_field(section, "Keywords"),
        "description": extract_field(section, "Description"),
    }


def extract_iap_description(markdown: str, locale_heading: str, end_heading: str) -> str:
    start = markdown.index(locale_heading)
    end = markdown.index(end_heading, start)
    return extract_field(markdown[start:end], "Description")


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def multiline(value: str) -> str:
    return "<br>\n".join(esc(line) for line in value.splitlines())


def screenshot_strip(locale: str, labels: dict[str, str]) -> str:
    cards = []
    for basename, label in SCREENSHOTS:
        path = f"{ART_DIR}/{basename}-{locale}.jpg"
        cards.append(
            f'<figure><a href="{path}"><img loading="lazy" src="{path}" '
            f'alt="{esc(labels[label])}"></a><figcaption>{esc(labels[label])}</figcaption></figure>'
        )
    return "\n".join(cards)


def ipad_screenshot_strip(locale: str, labels: dict[str, str]) -> str:
    cards = []
    for index, (basename, label) in enumerate(IPAD_SCREENSHOTS, 1):
        path = f"store-artwork-ipad-v1/{index:02d}-{basename}-{locale}.jpg"
        source = f"{IPAD_CAPTURE_DIR}/{basename}-{locale}.jpg"
        cards.append(
            f'<figure><a href="{path}"><img loading="lazy" src="{path}" '
            f'alt="{esc(labels[label])} · iPad"></a>'
            f'<figcaption>{esc(labels[label])} · iPad Pro 13-inch · '
            f'<a href="{source}">{"実画面" if locale == "ja" else "Source capture"}</a></figcaption></figure>'
        )
    return "\n".join(cards)


def gallery_cards(items: list[tuple[str, str, str]]) -> str:
    cards = []
    for image, source, label in items:
        source_link = f'<a href="{source}">実画面</a>' if source else ""
        cards.append(
            f'<figure><a href="{image}"><img loading="lazy" src="{image}" alt="{esc(label)}"></a>'
            f'<figcaption>{esc(label)}{" · " if source_link else ""}{source_link}</figcaption></figure>'
        )
    return "\n".join(cards)


def build_gallery() -> None:
    sections = []
    localized_names = {"ja": "日本語", "en": "English"}
    tool_names = {
        "ja": {"Home": "ホーム", "Quick Add": "クイック追加", "Cycle Time": "サイクルタイム", "Defect Counter": "不良カウンター", "Count History": "カウント履歴", "Takt Time": "タクトタイム", "Process Capability": "工程能力 Cp・Cpk（Pro）"},
        "en": {"Home": "Home", "Quick Add": "Quick Add", "Cycle Time": "Cycle Time", "Defect Counter": "Defect Counter", "Count History": "Count History", "Takt Time": "Takt Time", "Process Capability": "Process Capability Cp/Cpk (Pro)"},
    }
    for locale in ("ja", "en"):
        lang = localized_names[locale]
        phone_items = [
            (
                f"{ART_DIR}/{basename}-{locale}.jpg",
                f"{IPHONE_CAPTURE_DIR}/iphone-{basename.split('-', 1)[1]}-{locale}.jpg",
                f"{lang} · iPhone · {tool_names[locale][label]}",
            )
            for index, (basename, label) in enumerate(SCREENSHOTS, 1)
        ]
        sections.append(
            f'<section><h2>iPhone · {lang} · 7枚</h2><div class="grid">{gallery_cards(phone_items)}</div></section>'
        )
        ipad_items = [
            (
                f"store-artwork-ipad-v1/{index:02d}-{basename}-{locale}.jpg",
                f"{IPAD_CAPTURE_DIR}/{basename}-{locale}.jpg",
                f"{lang} · iPad · {tool_names[locale][label]}",
            )
            for index, (basename, label) in enumerate(IPAD_SCREENSHOTS, 1)
        ]
        sections.append(
            f'<section><h2>iPad · {lang} · 2枚</h2><div class="grid">{gallery_cards(ipad_items)}</div></section>'
        )
        watch_items = [
            (f"{WATCH_CAPTURE_DIR}/watch-{key}-{locale}.jpg", "", f"{lang} · Apple Watch · {label}")
            for key, label in (("counter", "Production Counter"), ("cycle-time", "Cycle Time"), ("production-progress", "Production Progress · Pro"))
        ]
        sections.append(
            f'<section><h2>Apple Watch · {lang} · 3枚</h2><div class="grid small">{gallery_cards(watch_items)}</div></section>'
        )
        size_items = [
            (f"{CARD_CAPTURE_DIR}/iphone-counter-size-{size}-{locale}.jpg", "", f"{lang} · Counter card · {size.upper()}")
            for size in ("small", "medium", "large")
        ]
        sections.append(
            f'<section><h2>生産カウンターカード · {lang} · S／M／L</h2><div class="grid small">{gallery_cards(size_items)}</div></section>'
        )

    GALLERY_OUTPUT.write_text(
        f"""<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>現場ギア／Factory Tools — ストア画像レビュー</title>
<style>:root{{color-scheme:light;--ink:#172125;--muted:#58666b;--accent:#ef711f;--paper:#f3f1ea;--card:#fff}}*{{box-sizing:border-box}}body{{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif}}header{{padding:38px max(24px,calc((100% - 1280px)/2));background:#182125;color:white;border-bottom:7px solid var(--accent)}}h1{{margin:0 0 8px;font-size:clamp(28px,4vw,42px)}}header p{{margin:6px 0;color:#d8e0e1}}main{{max-width:1280px;margin:0 auto;padding:24px}}.notice{{padding:18px 20px;background:#fff4df;border-left:5px solid var(--accent);border-radius:8px;margin:18px 0 32px}}section{{margin:40px 0}}h2{{font-size:25px;margin-bottom:14px}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:18px;align-items:start}}figure{{margin:0;padding:10px;background:var(--card);border-radius:12px;box-shadow:0 2px 10px #18212514}}img{{display:block;width:100%;height:auto;border-radius:7px}}figcaption{{padding:8px 2px 2px;font-weight:650;font-size:14px}}.small img{{max-width:260px;margin:auto}}a{{color:#a5480d}}</style></head><body>
<header><h1>現場ギア／Factory Tools — ストア画像レビュー</h1><p>掲載前の確認用 · すべて未承認・未公開</p><p>日本 ¥980 · Pro買い切り · Family Sharingオフ · 表示値はアプリの合成サンプル</p><p><a style="color:#ffd0a6" href="STORE_LISTING_REVIEW_JA.html">日英の掲載文・Pro価格・プライバシー／サポートページを確認する</a></p></header><main>
<div class="notice"><strong>画像の見方</strong><br>iPhone・iPadの掲載案はRelease Simulatorで撮った現行アプリ画面を使い、見出し・背景・枠を追加したものです。アプリUIを描き直していません。下の「実画面」リンクからiPadの未加工キャプチャを確認できます。Apple Watch画像はSimulator例で、実機でのペアリング確認を意味しません。いずれも公開・App Store提出はしていません。</div>
{"".join(sections)}</main></body></html>""",
        encoding="utf-8",
    )


def locale_section(locale: str, data: dict[str, str], iap_description: str) -> str:
    ja = locale == "ja"
    labels = (
        {
            "Home": "1 生産数と残数",
            "Quick Add": "2 クイック追加",
            "Cycle Time": "3 サイクルタイム",
            "Defect Counter": "4 不良カウンター",
            "Count History": "5 カウント履歴",
            "Takt Time": "6 タクトタイム",
            "Process Capability": "7 工程能力 Cp・Cpk（Pro）",
        }
        if ja
        else {
            "Home": "1 Production count and remaining",
            "Quick Add": "2 Quick Add",
            "Cycle Time": "3 Cycle Time",
            "Defect Counter": "4 Defect Counter",
            "Count History": "5 Count History",
            "Takt Time": "6 Takt Time",
            "Process Capability": "7 Process Capability Cp/Cpk (Pro)",
        }
    )
    title = "日本語ストア" if ja else "English storefront"
    locale_code = "ja-JP" if ja else "en-US"
    return f"""
<section class="locale" id="{locale}">
  <div class="locale-head"><div><p class="eyebrow">{locale_code} · {title}</p>
  <h2>{esc(data['name'])}</h2><p class="subtitle">{esc(data['subtitle'])}</p></div>
  <div class="appmark"><img src="../FactoryTools/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="現場ギア / Factory Tools app icon"></div></div>
  <div class="facts"><div><small>{'Pro価格（日本）' if ja else 'Japan Pro price'}</small><strong>¥980 · {'買い切り' if ja else 'one-time'}</strong></div>
  <div><small>{'カテゴリ案' if ja else 'Category draft'}</small><strong>{'ビジネス' if ja else 'Business'}</strong></div>
  <div><small>{'ファミリー共有' if ja else 'Family Sharing'}</small><strong>{'オフ' if ja else 'Off'}</strong></div>
  <div><small>{'公開状態' if ja else 'Status'}</small><strong>{'未公開・要確認' if ja else 'Draft · review required'}</strong></div></div>
  <h3>{'掲載画像案（日英各7枚）' if ja else 'Screenshot sequence (7 images)'}</h3>
  <div class="screens">{screenshot_strip(locale, labels)}</div>
  <h3>{'iPad掲載候補（日英各2枚）' if ja else 'iPad screenshot candidates (2 images)'}</h3>
  <div class="screens">{ipad_screenshot_strip(locale, labels)}</div>
  <div class="copy-grid"><article><h3>{'説明文' if ja else 'Description'}</h3><div class="description">{multiline(data['description'])}</div></article>
  <aside><h3>{'検索キーワード案' if ja else 'Keyword draft'}</h3><p class="keywords">{esc(data['keywords'])}</p>
  <h3>{'Pro商品表示名' if ja else 'Pro display name'}</h3><p>Factory Tools Pro</p>
  <h3>{'Pro商品説明' if ja else 'Pro description'}</h3><p>{esc(iap_description)}</p></aside></div>
</section>"""


def main() -> None:
    markdown = METADATA.read_text(encoding="utf-8")
    required = [
        ASSET_ROOT / f"{ART_DIR}/{basename}-{locale}.jpg"
        for locale in ("ja", "en")
        for basename, _ in SCREENSHOTS
    ]
    required.extend(
        ASSET_ROOT / f"{IPAD_CAPTURE_DIR}/{basename}-{locale}.jpg"
        for locale in ("ja", "en")
        for basename, _ in IPAD_SCREENSHOTS
    )
    required.extend(
        ASSET_ROOT / f"store-artwork-ipad-v1/{index:02d}-{basename}-{locale}.jpg"
        for locale in ("ja", "en")
        for index, (basename, _) in enumerate(IPAD_SCREENSHOTS, 1)
    )
    required.extend(
        ASSET_ROOT / f"{IPHONE_CAPTURE_DIR}/iphone-{basename.split('-', 1)[1]}-{locale}.jpg"
        for locale in ("ja", "en")
        for basename, _ in SCREENSHOTS
    )
    required.extend(
        ASSET_ROOT / f"{WATCH_CAPTURE_DIR}/watch-{key}-{locale}.jpg"
        for locale in ("ja", "en")
        for key in ("counter", "cycle-time", "production-progress")
    )
    required.extend(
        ASSET_ROOT / f"{CARD_CAPTURE_DIR}/iphone-counter-size-{size}-{locale}.jpg"
        for locale in ("ja", "en")
        for size in ("small", "medium", "large")
    )
    required.append(ROOT / "FactoryTools/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    required.extend(
        [
            ASSET_ROOT / "Pages-preview/privacy.html",
            ASSET_ROOT / "Pages-preview/support.html",
        ]
    )
    missing = [path for path in required if not path.is_file()]
    if missing:
        names = ", ".join(path.name for path in missing)
        raise SystemExit(f"Cannot build review page; required local capture/icon files are missing: {names}")
    ja = extract_locale(markdown, "## Japanese (ja-JP)", "## English (en-US)")
    en = extract_locale(markdown, "## English (en-US)", "## Character and byte count")
    ja_iap = extract_iap_description(
        markdown,
        "### Japanese product localization (ja-JP)",
        "### English product localization (en-US)",
    )
    en_iap = extract_iap_description(
        markdown,
        "### English product localization (en-US)",
        "## Japanese (ja-JP)",
    )
    page = f"""<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>現場ギア／Factory Tools — 掲載内容レビュー</title>
<style>
:root{{color-scheme:light;--ink:#202729;--muted:#657072;--paper:#f2f0e9;--card:#fffefa;--line:#ddd9ce;--orange:#ed6a18;--night:#111719}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif}}
header{{padding:38px max(22px,calc((100% - 1180px)/2));background:var(--night);color:#f6f3ed;border-bottom:5px solid var(--orange)}}
header h1{{font-size:clamp(25px,4vw,42px);line-height:1.1;margin:0 0 10px}}header p{{margin:0;color:#c9cfcb}}main{{max-width:1180px;margin:28px auto;padding:0 20px}}
.notice{{padding:16px 20px;background:#fff2e6;border-left:5px solid var(--orange);border-radius:8px;margin-bottom:22px}}
.toolbar{{display:flex;gap:10px;flex-wrap:wrap;margin:0 0 18px}}.toolbar a{{background:var(--night);color:white;padding:10px 16px;border-radius:24px;text-decoration:none}}
.locale{{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:clamp(18px,3vw,32px);margin:20px 0 32px;box-shadow:0 7px 24px #2027290d}}
.locale-head{{display:flex;align-items:center;justify-content:space-between;gap:20px}}.eyebrow{{text-transform:uppercase;letter-spacing:.12em;font-size:12px;color:var(--orange);font-weight:800;margin:0}}
h2{{font-size:clamp(30px,5vw,52px);line-height:1.05;margin:8px 0}}.subtitle{{font-size:18px;color:var(--muted);margin:0}}
.appmark{{width:88px;height:88px;border-radius:20px;overflow:hidden;flex:none;box-shadow:0 6px 18px #17202229}}.appmark img{{width:100%;height:100%;object-fit:cover}}
.facts{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:24px 0 30px}}.facts div{{background:#f3f1eb;padding:13px 15px;border-radius:10px}}.facts small{{display:block;color:var(--muted)}}.facts strong{{display:block;margin-top:3px}}
h3{{font-size:19px;margin:28px 0 12px}}.screens{{display:flex;gap:14px;overflow-x:auto;padding:0 0 12px;scroll-snap-type:x mandatory}}figure{{margin:0;flex:0 0 clamp(185px,23vw,260px);scroll-snap-align:start}}figure img{{display:block;width:100%;height:auto;border-radius:10px;box-shadow:0 6px 18px #17202222}}figcaption{{font-size:13px;color:var(--muted);padding:7px 2px}}
.copy-grid{{display:grid;grid-template-columns:minmax(0,2fr) minmax(240px,1fr);gap:28px;margin-top:26px}}.copy-grid article,.copy-grid aside{{border-top:1px solid var(--line);padding-top:6px}}
.description{{white-space:normal;line-height:1.75}}.keywords{{overflow-wrap:anywhere;color:var(--muted)}}footer{{max-width:1180px;margin:0 auto;padding:0 20px 36px;color:var(--muted);font-size:13px}}
@media(max-width:700px){{.copy-grid{{grid-template-columns:1fr}}.locale-head{{align-items:flex-start}}.appmark{{width:68px;height:68px}}}}
</style></head><body>
<header><h1>現場ギア／Factory Tools</h1><p>App Store掲載内容の確認用ページ · 公開前ドラフト</p></header>
<main><div class="notice"><strong>これはApp Store画面の偽装画像ではなく、掲載素材を確認するための非公開ページです。</strong><br>
実画面を使った画像案と、掲載予定の文章・Pro価格を同時に確認できます。すべて未承認・未公開です。表示値は合成サンプルです。iPhoneの掲載画像は実アプリのSimulator画面を使い、周囲に見出しとデザインを加えています。iPad画像は13インチiPad Pro Simulatorの実画面です。</div>
<nav class="toolbar"><a href="#ja">日本語の掲載内容</a><a href="#en">English listing</a><a href="Pages-preview/privacy.html">プライバシーポリシー案</a><a href="Pages-preview/support.html">サポートページ案</a><a href="../FactoryTools/APP_STORE_METADATA_DRAFT.md">元の掲載文書</a></nav>
{locale_section('ja', ja, ja_iap)}
{locale_section('en', en, en_iap)}
<section class="locale"><h2>未確定の公開設定</h2><p>英語を基本言語、日本語を追加言語とする案。配信対象はAppleが許可する全地域。日本のPro価格は¥980、Family Sharingはオフ。日本以外の価格、App Store Connectでのアプリ名・商品ID・URL登録、質問票、署名・実機テストはまだ未完了です。</p>
<p>Privacy Policy URL候補：<code>https://niconiconicopi.github.io/factory-tools/privacy.html</code><br>Support URL候補：<code>https://niconiconicopi.github.io/factory-tools/support.html</code><br>どちらもページ未公開で、アクセス確認前です。</p></section></main>
<footer>Factory Tools private review artifact · Metadata sourced from APP_STORE_METADATA_DRAFT.md · Promotional images use genuine app captures; no generated app UI.</footer>
</body></html>"""
    OUTPUT.write_text(page, encoding="utf-8")
    build_gallery()
    print("Wrote private App Store listing review page")


if __name__ == "__main__":
    main()
