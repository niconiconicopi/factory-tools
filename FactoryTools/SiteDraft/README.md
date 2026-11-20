# Factory Tools public-pages draft

This folder is generated from the bilingual source drafts in the parent directory. It is a static HTML package with no JavaScript, external assets, packages, APIs, or paid service requirements.

## Before publishing

1. Confirm the publisher name, monitored support/privacy contact, effective date, and candidate privacy-policy link in `../PRIVACY_POLICY_DRAFT.md` and `../SUPPORT_PAGE_DRAFT.md`.
2. Review both documents against the final release build and the publisher's legal obligations. Confirm the stated platform behavior and mailbox language support.
3. Run `python Scripts/generate_public_site.py` from the workspace root, then `python Scripts/generate_public_site.py --check` to ensure these pages match the source drafts.
4. After the publisher has completed that review, run `python Scripts/generate_public_site.py --publication-copy-reviewed` and `python Scripts/generate_public_site.py --publication-copy-reviewed --check`. This checks required names/contact fields, a real YYYY-MM-DD date, monitored email syntax, and one shared HTTPS privacy URL before writing a separate candidate without the draft banner or `noindex`. It does not publish the pages or verify contact ownership, URL ownership, or reachability.
5. Publish the candidate folder on a publisher-controlled, stable HTTPS host, then configure the same privacy and support URLs in the app and App Store Connect. This repository includes a separately gated GitHub Pages deployment workflow; first set the repository's Pages source to **GitHub Actions**, then use it only after the owner approves the completed public copy.

The repository is public, so GitHub Pages is available without a separate Pages hosting charge on GitHub Free. Keep the site limited to policy and support material: GitHub says Pages is not intended for a site primarily facilitating commercial transactions or SaaS. GitHub also logs visitor IP addresses for security. Review the host's processing and any required notice before publishing; this is separate from Factory Tools' on-device data handling. [GitHub Pages availability and source setup](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site), [GitHub Pages usage policy](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits), [GitHub Pages visitor logging](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages).

The pages intentionally carry `noindex` and a visible draft banner. Do not publish before the publisher reviews the final copy and verifies the contact mailbox, candidate URLs, and legal requirements.
