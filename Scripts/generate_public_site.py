from __future__ import annotations

import argparse
from datetime import date
from html import escape
from pathlib import Path
import re
import sys
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "FactoryTools"
OUTPUT_DIR = SOURCE_DIR / "SiteDraft"
PUBLICATION_DIR = SOURCE_DIR / "SitePublicationCandidate"

STYLE = """\
:root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #17202a; background: #f3f5f6; }
body { margin: 0; line-height: 1.65; }
header { background: #17202a; color: #fff; padding: 1.5rem max(1rem, calc((100% - 54rem) / 2)); }
header h1 { margin: 0 0 .35rem; font-size: 1.55rem; }
header nav { display: flex; gap: 1.2rem; flex-wrap: wrap; }
header a { color: #cce7ff; }
.skip-link { position: absolute; left: 1rem; top: -5rem; z-index: 2; padding: .55rem .8rem; background: #fff; color: #17202a; border-radius: .3rem; }
.skip-link:focus { top: .5rem; }
main { box-sizing: border-box; max-width: 56rem; margin: 1.5rem auto; padding: clamp(1.1rem, 4vw, 2.4rem); background: #fff; border: 1px solid #dce2e6; border-radius: .8rem; }
.draft { border-left: .3rem solid #e1a323; padding: .8rem 1rem; background: #fff8e8; }
h2 { margin-top: 2rem; border-bottom: 1px solid #dce2e6; padding-bottom: .3rem; }
h3 { margin-top: 1.5rem; }
li { margin: .35rem 0; }
a { color: #075c99; overflow-wrap: anywhere; }
footer { max-width: 56rem; margin: 1rem auto 2rem; padding: 0 1rem; color: #52606b; font-size: .9rem; }
@media (max-width: 40rem) { header { padding: 1.2rem 1rem; } main { margin: .7rem; border-radius: .5rem; } }
"""


def plain_text_markup(value: str) -> str:
    pattern = re.compile(r"(https://[^\s<>]+|[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})")
    rendered: list[str] = []
    for part in pattern.split(value):
        if not part:
            continue
        if part.startswith("https://"):
            url = part
            suffix = ""
            while url and url[-1] in ".,;:!?)]":
                suffix = url[-1] + suffix
                url = url[:-1]
            safe_url = escape(url, quote=True)
            rendered.append(f'<a href="{safe_url}" target="_blank" rel="noopener noreferrer">{escape(url)}</a>{escape(suffix)}')
        elif "@" in part:
            address = escape(part, quote=True)
            rendered.append(f'<a href="mailto:{address}">{escape(part)}</a>')
        else:
            rendered.append(escape(part))
    return "".join(rendered)


def inline_markup(value: str) -> str:
    pieces = re.split(r"(\[[^\]]+\]\([^)]+\)|\*\*.+?\*\*|`[^`]+`)", value)
    rendered: list[str] = []
    for piece in pieces:
        if piece.startswith("**") and piece.endswith("**"):
            rendered.append(f"<strong>{inline_markup(piece[2:-2])}</strong>")
        elif piece.startswith("`") and piece.endswith("`"):
            rendered.append(f"<code>{escape(piece[1:-1])}</code>")
        elif piece.startswith("["):
            match = re.fullmatch(r"\[([^\]]+)\]\(([^)]+)\)", piece)
            if match:
                label, raw_url = match.groups()
                parsed = urlparse(raw_url)
                allowed = parsed.scheme == "https" or (not parsed.scheme and raw_url.endswith(".html"))
                href = escape(raw_url, quote=True) if allowed else "#"
                external = parsed.scheme == "https"
                attrs = ' target="_blank" rel="noopener noreferrer"' if external else ""
                rendered.append(f'<a href="{href}"{attrs}>{escape(label)}</a>')
            else:
                rendered.append(escape(piece))
        else:
            rendered.append(plain_text_markup(piece))
    return "".join(rendered)


def markdown_body(source: str) -> str:
    lines = source.splitlines()
    blocks: list[str] = []
    paragraph: list[tuple[str, bool]] = []
    list_items: list[str] = []

    def flush_paragraph() -> None:
        if paragraph:
            body: list[str] = []
            for index, (line, hard_break) in enumerate(paragraph):
                body.append(inline_markup(line))
                if index < len(paragraph) - 1:
                    body.append("<br>\n" if hard_break else " ")
            blocks.append(f"<p>{''.join(body)}</p>")
            paragraph.clear()

    def flush_list() -> None:
        if list_items:
            blocks.append("<ul>" + "".join(f"<li>{inline_markup(item)}</li>" for item in list_items) + "</ul>")
            list_items.clear()

    for raw_line in lines:
        line = raw_line.strip()
        hard_break = raw_line.endswith("  ") or line.endswith("\\")
        if line.endswith("\\"):
            line = line[:-1].rstrip()
        if not line:
            flush_paragraph()
            flush_list()
            continue
        if line.startswith("# "):
            flush_paragraph()
            flush_list()
            continue
        if line == "---":
            flush_paragraph()
            flush_list()
            continue
        heading = re.match(r"^(#{2,4})\s+(.+)$", line)
        if heading:
            flush_paragraph()
            flush_list()
            level = len(heading.group(1))
            blocks.append(f"<h{level}>{inline_markup(heading.group(2))}</h{level}>")
            continue
        item = re.match(r"^-\s+(.+)$", line)
        if item:
            flush_paragraph()
            list_items.append(item.group(1))
            continue
        flush_list()
        paragraph.append((line, hard_break))
    flush_paragraph()
    flush_list()
    return "\n".join(blocks)


def public_content(document: str, *, discard_after: str, remove_draft_notice: str) -> tuple[str, str]:
    content = document.split(discard_after, 1)[0]
    content = content.replace(remove_draft_notice, "")
    japanese, separator, english = content.partition("## English")
    if not separator:
        raise ValueError("Source document must contain a separate English section.")
    japanese = re.sub(r"\A#.*?\n", "", japanese, count=1, flags=re.DOTALL)
    english = re.sub(r"\A\s*\n", "", english, count=1)
    return japanese, english


def html_page(*, title: str, source: str, draft_notice: str, publication_ready: bool = False, privacy_link: str = "privacy.html") -> str:
    ja, en = public_content(source, discard_after="## Before publication" if "## Before publication" in source else "## Publisher checklist", remove_draft_notice=draft_notice)
    indexing = "" if publication_ready else '  <meta name="robots" content="noindex, nofollow">\n'
    notice = "" if publication_ready else f'    <p class="draft" role="note">{escape("Draft page: publisher details and public URLs must be completed before publication. / 公開前に発行者情報と公開URLを確定してください。")}</p>\n'
    return f"""<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
{indexing}  <meta name="description" content="{escape(title, quote=True)}">
  <title>{escape(title)} | Factory Tools</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <a class="skip-link" href="#main">Skip to content / 本文へ</a>
  <header><h1>Factory Tools</h1><nav aria-label="Site navigation"><a href="index.html">Home / ホーム</a><a href="privacy.html">Privacy / プライバシー</a><a href="support.html">Support / サポート</a></nav></header>
  <main id="main" tabindex="-1">
{notice}    <h2>{escape(title)}</h2>
    <section lang="ja">{markdown_body(ja)}</section>
    <section lang="en"><h2>English</h2>{markdown_body(en)}</section>
  </main>
  <footer><a href="{escape(privacy_link, quote=True)}">Privacy / プライバシー</a> · Factory Tools</footer>
</body>
</html>
"""


def unresolved_publisher_fields(privacy: str, support: str) -> list[str]:
    fields = {
        "publisher legal name": "[Publisher's legal name / 発行者の正式名称]",
        "privacy effective date": "[YYYY-MM-DD]",
        "privacy contact": "[Public contact email or contact page / 公開連絡先メールアドレスまたは問い合わせページ]",
        "Japanese developer name": "[開発者名]",
        "Japanese support email": "[サポート用メールアドレス]",
        "English developer name": "[Developer name]",
        "English support email": "[Monitored support email address]",
        "Japanese published privacy URL": "[公開済みプライバシーポリシーURL]",
        "English published privacy URL": "[Published privacy policy URL]",
    }
    source = privacy + "\n" + support
    issues = [label for label, placeholder in fields.items() if placeholder in source]
    known_markers = set(fields.values())
    bracketed_values = re.findall(r"\[([^\]]+)\](?!\()", source)
    for value in bracketed_values:
        marker = f"[{value}]"
        if marker not in known_markers:
            issues.append(f"unreviewed bracketed field [{value}]")
    return issues


def publication_copy_issues(privacy: str, support: str) -> list[str]:
    issues = unresolved_publisher_fields(privacy, support)
    if issues:
        return issues

    if "### このページのホスティング" not in privacy:
        issues.append("Japanese privacy copy must describe website hosting separately from app data")
    if "### Website hosting" not in privacy:
        issues.append("English privacy copy must describe website hosting separately from app data")

    def value(pattern: str, source: str) -> str | None:
        match = re.search(pattern, source)
        return match.group(1).strip() if match else None

    publisher = value(r"\*\*Publisher / 運営者:\*\*\s*`([^`]+)`", privacy)
    if not publisher:
        issues.append("publisher legal name is empty or missing")
    elif "[" in publisher or "]" in publisher:
        issues.append("publisher legal name still contains brackets")

    effective_date = value(r"\*\*Effective date / 発効日:\*\*\s*`([^`]+)`", privacy)
    try:
        if effective_date is None or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", effective_date):
            raise ValueError
        date.fromisoformat(effective_date)
    except ValueError:
        issues.append("privacy effective date must be a real YYYY-MM-DD date")

    privacy_contact = value(r"\*\*Privacy contact / 個人情報に関する連絡先:\*\*\s*`([^`]+)`", privacy)
    if not privacy_contact or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", privacy_contact):
        if not privacy_contact or not _valid_https_url(privacy_contact):
            issues.append("privacy contact must be a public email address or HTTPS contact page")

    def email_value(pattern: str, label: str) -> str | None:
        result = value(pattern, support)
        if not result or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", result):
            issues.append(f"{label} must be a valid monitored email address")
        return result

    email_value(r"- サポートメール: \*\*([^*]+)\*\*", "Japanese support email")
    email_value(r"- Support email: \*\*([^*]+)\*\*", "English support email")

    japanese_url = value(r"プライバシーについては \*\*(https://[^*\s]+)\*\*", support)
    english_url = value(r"Read our privacy policy at \*\*(https://[^*\s]+)\*\*", support)
    if not _valid_https_url(japanese_url):
        issues.append("Japanese support page must link to a public HTTPS privacy-policy URL")
    if not _valid_https_url(english_url):
        issues.append("English support page must link to a public HTTPS privacy-policy URL")
    if japanese_url and english_url and japanese_url != english_url:
        issues.append("Japanese and English support sections must use the same privacy-policy URL")
    return issues


def _valid_https_url(value: str | None) -> bool:
    if not value or any(character.isspace() for character in value):
        return False
    parsed = urlparse(value)
    try:
        return parsed.scheme == "https" and bool(parsed.hostname) and parsed.username is None and parsed.password is None
    except ValueError:
        return False


def build_outputs(*, publication_ready: bool = False, privacy_source: str | None = None, support_source: str | None = None) -> dict[str, str]:
    privacy = privacy_source if privacy_source is not None else (SOURCE_DIR / "PRIVACY_POLICY_DRAFT.md").read_text(encoding="utf-8")
    support = support_source if support_source is not None else (SOURCE_DIR / "SUPPORT_PAGE_DRAFT.md").read_text(encoding="utf-8")
    if publication_ready:
        issues = publication_copy_issues(privacy, support)
        if issues:
            raise ValueError("Resolve publisher-page issues before generating publication pages: " + "; ".join(issues))
    privacy_notice = "**Draft only.** Complete every bracketed publisher field, review the text for the release build and applicable law, publish a stable public URL, and add an in-app link before submission. Do not publish this draft with placeholders."
    support_notice = "**Publication status: draft.** Before publishing, replace every bracketed publisher field with a real, monitored contact and update the supported app/platform versions. Do not publish a placeholder email or promise a response time that has not been established."
    privacy_page = html_page(title="Privacy Policy / プライバシーポリシー", source=privacy, draft_notice=privacy_notice, publication_ready=publication_ready)
    support_page = html_page(title="Support / サポート", source=support, draft_notice=support_notice, publication_ready=publication_ready)
    if publication_ready:
        robots_tag = ""
        draft_banner = ""
        publication_status = "This publication candidate is generated from the publisher-reviewed bilingual source drafts. Verify the legal contact, privacy/support URLs, and HTTPS reachability before uploading. This command does not publish the pages."
    else:
        robots_tag = '<meta name="robots" content="noindex, nofollow">'
        draft_banner = '<p class="draft" role="note">Draft site for local review. Complete publisher details and URLs before publishing. / ローカル確認用の下書きサイトです。公開前に発行者情報とURLを確定してください。</p>'
        publication_status = "The pages intentionally carry `noindex` and a visible draft banner. Do not publish before completing all placeholders and the publisher's legal/contact review."
    index = """<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">{robots_tag}<title>Factory Tools</title><link rel="stylesheet" href="styles.css"></head>
<body><a class="skip-link" href="#main">Skip to content / 本文へ</a><header><h1>Factory Tools</h1><nav aria-label="Site navigation"><a href="privacy.html">Privacy / プライバシー</a><a href="support.html">Support / サポート</a></nav></header><main id="main" tabindex="-1">{draft_banner}<h2>Information / ご案内</h2><p>Read our <a href="privacy.html">privacy policy / プライバシーポリシー</a> or visit <a href="support.html">support / サポート</a>.</p></main></body></html>
"""
    index = index.format(robots_tag=robots_tag, draft_banner=draft_banner)
    readme = """# Factory Tools public-pages draft

This folder is generated from the bilingual source drafts in the parent directory. It is a static HTML package with no JavaScript, external assets, packages, APIs, or paid service requirements.

## Before publishing

1. Complete the publisher name, monitored support/privacy contact, effective date, and privacy-policy link in `../PRIVACY_POLICY_DRAFT.md` and `../SUPPORT_PAGE_DRAFT.md`.
2. Review both documents against the signed release build and the publisher's legal obligations. Update the supported platform/version information.
3. Run `python Scripts/generate_public_site.py` from the workspace root, then `python Scripts/generate_public_site.py --check` to ensure these pages match the source drafts.
4. After the publisher has completed that review, run `python Scripts/generate_public_site.py --publication-copy-reviewed` and `python Scripts/generate_public_site.py --publication-copy-reviewed --check`. This checks required names/contact fields, a real YYYY-MM-DD date, monitored email syntax, and one shared HTTPS privacy URL before writing a separate candidate without the draft banner or `noindex`. It does not publish the pages or verify contact ownership, URL ownership, or reachability.
5. Publish the candidate folder on a publisher-controlled, stable HTTPS host, then configure the same privacy and support URLs in the app and App Store Connect. This repository includes a separately gated GitHub Pages deployment workflow; first set the repository's Pages source to **GitHub Actions**, then use it only after the owner approves the completed public copy.

The repository is public, so GitHub Pages is available without a separate Pages hosting charge on GitHub Free. Keep the site limited to policy and support material: GitHub says Pages is not intended for a site primarily facilitating commercial transactions or SaaS. GitHub also logs visitor IP addresses for security. Review the host's processing and any required notice before publishing; this is separate from Factory Tools' on-device data handling. [GitHub Pages availability and source setup](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site), [GitHub Pages usage policy](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits), [GitHub Pages visitor logging](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages).

{publication_status}
"""
    readme = readme.format(publication_status=publication_status)
    return {"index.html": index, "privacy.html": privacy_page, "support.html": support_page, "styles.css": STYLE, "README.md": readme}


def write_outputs(*, check: bool, publication_ready: bool = False) -> bool:
    outputs = build_outputs(publication_ready=publication_ready)
    output_dir = PUBLICATION_DIR if publication_ready else OUTPUT_DIR
    if check:
        mismatches = [name for name, content in outputs.items() if not (output_dir / name).is_file() or (output_dir / name).read_text(encoding="utf-8") != content]
        if mismatches:
            print("STALE: generated site files differ: " + ", ".join(mismatches), file=sys.stderr)
            return False
        print(f"PASS: {len(outputs)} generated {'publication-candidate' if publication_ready else 'draft'} files match their bilingual Markdown sources.")
        return True
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, content in outputs.items():
        (output_dir / name).write_text(content, encoding="utf-8", newline="\n")
    print(f"WROTE: {len(outputs)} static {'publication-candidate' if publication_ready else 'draft'} files to FactoryTools/{output_dir.name}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the no-dependency bilingual Factory Tools public-page draft.")
    parser.add_argument("--check", action="store_true", help="check generated files without writing")
    parser.add_argument("--publication-copy-reviewed", action="store_true", help="after publisher review and completing every field, generate a separate candidate without draft/noindex indicators")
    arguments = parser.parse_args()
    try:
        return 0 if write_outputs(check=arguments.check, publication_ready=arguments.publication_copy_reviewed) else 1
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
