from __future__ import annotations

import unittest
from html.parser import HTMLParser
from pathlib import Path
import tempfile

import generate_public_site
import audit_source_hygiene


class _StructureParser(HTMLParser):
    VOID_ELEMENTS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag not in self.VOID_ELEMENTS:
            self.stack.append(tag)

    def handle_endtag(self, tag: str) -> None:
        if not self.stack or self.stack[-1] != tag:
            self.errors.append(f"unexpected closing tag: {tag}")
            return
        self.stack.pop()


class PublicSiteDraftTests(unittest.TestCase):
    def test_saved_site_matches_current_publisher_drafts(self) -> None:
        for filename, expected in generate_public_site.build_outputs().items():
            actual = (generate_public_site.OUTPUT_DIR / filename).read_text(encoding="utf-8")
            self.assertEqual(actual, expected, filename)

    def test_generated_pages_preserve_bilingual_publisher_fields(self) -> None:
        pages = generate_public_site.build_outputs()
        privacy = pages["privacy.html"]
        support = pages["support.html"]
        for name in ("index.html", "privacy.html", "support.html"):
            self.assertIn("現場ギア / Factory Tools", pages[name])
        self.assertIn('lang="ja"', privacy)
        self.assertIn('lang="en"', privacy)
        self.assertIn("Akira Kobayashi", privacy)
        self.assertIn("azalea.fortask@outlook.jp", privacy)
        self.assertIn("azalea.fortask@outlook.jp", support)
        self.assertIn("\u73fe\u5834\u30ae\u30a2", support)
        self.assertIn("Factory Tools", support)

    def test_privacy_page_retains_local_storage_and_transfer_disclosures_in_both_languages(self) -> None:
        privacy = generate_public_site.build_outputs()["privacy.html"]
        required_copy = (
            "端末内に保存します",
            "ペアリングしたiPadとの間では",
            "開発者や外部事業者のサーバーには送られません",
            "Appleの端末バックアップにアプリデータが含まれることがあります",
            "stores data that you enter or create",
            "directly with Apple Watch",
            "paired iPad",
            "not sent to a server operated by the developer or an outside provider",
            "Apple device backups may include app data",
            "GitHub logs visitor IP addresses for service security",
        )

        for statement in required_copy:
            with self.subTest(statement=statement):
                self.assertIn(statement, privacy)

    def test_generated_pages_omit_internal_publication_checklists(self) -> None:
        pages = generate_public_site.build_outputs()
        self.assertNotIn("Before publication", pages["privacy.html"])
        self.assertNotIn("Publisher checklist", pages["support.html"])
        self.assertIn("Draft page", pages["privacy.html"])
        self.assertIn("Draft page", pages["support.html"])

    def test_site_uses_only_local_assets_and_no_scripts(self) -> None:
        pages = generate_public_site.build_outputs()
        for name in ("index.html", "privacy.html", "support.html"):
            self.assertIn('<meta name="robots" content="noindex, nofollow">', pages[name])
            self.assertIn('href="styles.css"', pages[name])
            self.assertNotIn("<script", pages[name].lower())
            self.assertNotIn('<link rel="stylesheet" href="https://', pages[name])
            self.assertNotIn('<script src="https://', pages[name])
            self.assertNotIn('<img src="https://', pages[name])
            self.assertIn('class="skip-link"', pages[name])
            self.assertIn('id="main" tabindex="-1"', pages[name])

    def test_markdown_hard_breaks_are_preserved(self) -> None:
        body = generate_public_site.markdown_body("**Name:** A  \n**Date:** B")
        self.assertIn("A<br>\n<strong>Date:</strong> B", body)

    def test_generated_html_is_balanced_and_internal_links_exist(self) -> None:
        pages = generate_public_site.build_outputs()
        for filename in ("index.html", "privacy.html", "support.html"):
            parser = _StructureParser()
            parser.feed(pages[filename])
            self.assertEqual(parser.errors, [], filename)
            self.assertEqual(parser.stack, [], filename)
            for destination in ("index.html", "privacy.html", "support.html", "styles.css"):
                if f'href="{destination}"' in pages[filename]:
                    self.assertIn(destination, pages, filename)

    def test_gitignore_documents_sensitive_and_unrelated_paths(self) -> None:
        ignore_source = Path(generate_public_site.ROOT / ".gitignore").read_text(encoding="utf-8")
        for expected in (
            "/Audio教材_Phase1/",
            "*.p8",
            "*.p12",
            "*.mobileprovision",
            "*.xcarchive/",
            "*.xcresult/",
            "*.app/",
            "/FactoryTools/SitePublicationCandidate/",
        ):
            self.assertIn(expected, ignore_source)
        self.assertNotIn("/FactoryTools/\n", ignore_source)

    def test_current_source_paths_have_no_known_credentials(self) -> None:
        self.assertEqual(audit_source_hygiene.audit(generate_public_site.ROOT), [])

    def test_source_hygiene_finds_keys_and_tokens_without_echoing_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "FactoryTools"
            source.mkdir()
            (source / "signing.p8").write_bytes(b"-----BEGIN " + b"PRIVATE KEY-----SECRET-SAMPLE")
            (source / "client.swift").write_text('let token = "ghp_' + "A" * 30 + '"', encoding="utf-8")
            findings = audit_source_hygiene.audit(root)
        self.assertEqual({relative for relative, _ in findings}, {"FactoryTools/signing.p8", "FactoryTools/client.swift"})
        self.assertNotIn("SECRET-SAMPLE", repr(findings))

    def test_markdown_renderer_escapes_html_and_rejects_unsafe_links(self) -> None:
        body = generate_public_site.markdown_body(
            "<script>alert(1)</script>\n\n[unsafe](javascript:alert(1))\n\n[safe](privacy.html)"
        )
        self.assertIn("&lt;script&gt;", body)
        self.assertNotIn("<script>", body)
        self.assertNotIn('href="javascript:', body)
        self.assertIn('href="privacy.html"', body)

    def test_publication_candidate_is_blocked_while_publisher_fields_are_missing(self) -> None:
        privacy = (generate_public_site.SOURCE_DIR / "PRIVACY_POLICY_DRAFT.md").read_text(encoding="utf-8")
        support = (generate_public_site.SOURCE_DIR / "SUPPORT_PAGE_DRAFT.md").read_text(encoding="utf-8")
        privacy = privacy.replace("Akira Kobayashi", "[Publisher's legal name / 発行者の正式名称]")
        privacy = privacy.replace("2026-11-21", "[YYYY-MM-DD]")
        privacy = privacy.replace("azalea.fortask@outlook.jp", "[Public contact email or contact page / 公開連絡先メールアドレスまたは問い合わせページ]")
        support = support.replace("- 発行者: **Akira Kobayashi**", "- 開発者: **[開発者名]**")
        support = support.replace("- Publisher: **Akira Kobayashi**", "- Developer: **[Developer name]**")
        support = support.replace("- サポートメール: **azalea.fortask@outlook.jp**", "- サポートメール: **[サポート用メールアドレス]**")
        support = support.replace("- Support email: **azalea.fortask@outlook.jp**", "- Support email: **[Monitored support email address]**")
        support = support.replace("プライバシーについては **https://niconiconicopi.github.io/factory-tools/privacy.html**", "プライバシーについては **[公開済みプライバシーポリシーURL]")
        support = support.replace("Read our privacy policy at **https://niconiconicopi.github.io/factory-tools/privacy.html**", "Read our privacy policy at **[Published privacy policy URL]")
        missing = generate_public_site.unresolved_publisher_fields(privacy, support)
        self.assertGreaterEqual(len(missing), 7)
        with self.assertRaisesRegex(ValueError, "Resolve publisher-page issues"):
            generate_public_site.build_outputs(publication_ready=True, privacy_source=privacy, support_source=support)

    def test_reviewed_complete_copy_generates_separate_indexable_candidate(self) -> None:
        privacy = (generate_public_site.SOURCE_DIR / "PRIVACY_POLICY_DRAFT.md").read_text(encoding="utf-8")
        support = (generate_public_site.SOURCE_DIR / "SUPPORT_PAGE_DRAFT.md").read_text(encoding="utf-8")
        pages = generate_public_site.build_outputs(publication_ready=True, privacy_source=privacy, support_source=support)
        self.assertNotIn("noindex", pages["privacy.html"])
        self.assertNotIn("Draft page", pages["privacy.html"])
        self.assertIn("azalea.fortask@outlook.jp", pages["support.html"])
        self.assertIn("https://niconiconicopi.github.io/factory-tools/privacy.html", pages["support.html"])
        self.assertIn("GitHub Pagesで公開する場合", pages["privacy.html"])
        self.assertIn("GitHub logs visitor IP addresses for service security.", pages["privacy.html"])
        self.assertIn('href="mailto:azalea.fortask@outlook.jp"', pages["support.html"])
        self.assertIn('href="https://niconiconicopi.github.io/factory-tools/privacy.html"', pages["support.html"])
        self.assertIn("candidate without the draft banner", pages["README.md"])

    def test_publication_copy_rejects_invalid_dates_contacts_and_mismatched_urls(self) -> None:
        privacy = (generate_public_site.SOURCE_DIR / "PRIVACY_POLICY_DRAFT.md").read_text(encoding="utf-8")
        support = (generate_public_site.SOURCE_DIR / "SUPPORT_PAGE_DRAFT.md").read_text(encoding="utf-8")
        privacy = privacy.replace("2026-11-21", "2026-02-30")
        privacy = privacy.replace("azalea.fortask@outlook.jp", "not-an-email")
        support = support.replace("azalea.fortask@outlook.jp", "bad-email")
        support = support.replace("https://niconiconicopi.github.io/factory-tools/privacy.html", "https://example.org/privacy-ja.html", 1)
        support = support.replace("https://niconiconicopi.github.io/factory-tools/privacy.html", "https://example.org/privacy-en.html", 1)
        issues = generate_public_site.publication_copy_issues(privacy, support)
        self.assertTrue(any("YYYY-MM-DD" in issue for issue in issues))
        self.assertTrue(any("privacy contact" in issue for issue in issues))
        self.assertTrue(any("support email" in issue for issue in issues))
        self.assertTrue(any("same privacy-policy URL" in issue for issue in issues))

    def test_publication_copy_requires_bilingual_hosting_disclosure(self) -> None:
        privacy = (generate_public_site.SOURCE_DIR / "PRIVACY_POLICY_DRAFT.md").read_text(encoding="utf-8")
        support = (generate_public_site.SOURCE_DIR / "SUPPORT_PAGE_DRAFT.md").read_text(encoding="utf-8")
        privacy = privacy.replace("### このページのホスティング", "### ホスティング")
        privacy = privacy.replace("訪問者のIPアドレスを記録します", "訪問者データを記録します")
        privacy = privacy.replace("### Website hosting", "### Hosting")
        privacy = privacy.replace("logs visitor IP addresses", "logs connection data")
        issues = generate_public_site.publication_copy_issues(privacy, support)

        self.assertIn("Japanese privacy copy must describe website hosting separately from app data", issues)
        self.assertIn("Japanese privacy copy must disclose GitHub Pages visitor IP logging", issues)
        self.assertIn("English privacy copy must describe website hosting separately from app data", issues)
        self.assertIn("English privacy copy must disclose GitHub Pages visitor IP logging", issues)


if __name__ == "__main__":
    unittest.main()
