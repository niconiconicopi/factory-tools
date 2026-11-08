# App Store age rating review

**Status: source-based draft.** Use this as a prepared answer sheet for App Store Connect, then verify every answer against the signed release build before submitting. Apple calculates the global and regional ratings from the questionnaire; this document does not assign the final rating.

## Current Apple process

App Store Connect requires an age rating. Its questionnaire covers in-app controls, app capabilities, and content frequencies; its answers determine global and region-specific ratings. Apple added social-media capability questions in July 2026. Starting November 16, 2026, the questionnaire will also include Shared Location and Dating and Relationships descriptors. Apple requires these declarations when submitting an app or changing its age-rating questionnaire; all apps must complete them by January 12, 2027. Factory Tools' first submission should include these new answers if the questionnaire presents them.

References:

- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [App Store Connect release notes: social-media age-rating questions](https://developer.apple.com/help/app-store-connect/release-notes/)
- [Upcoming Shared Location and Dating and Relationships age-rating descriptors](https://developer.apple.com/news/?id=yxkh08us)

## Proposed responses from the current source

These are recommendations based on the current iPhone, Watch, and iPad source. A “None” answer means the feature or content is absent from the product, not merely switched off by default.

| Questionnaire area | Proposed answer | Source-based reason |
|---|---|---|
| Parental controls | No | There are no parent or guardian monitoring, filtering, blocking, or usage-limit tools. |
| Age assurance | No | The app does not collect or verify a user's age. |
| Unrestricted web access | No | Settings opens only the publisher's privacy-policy and support links through external links; it does not embed a general-purpose browser. |
| User-generated content | No | User production records and exports are private operational data, not content broadly distributed as the app's intended experience. |
| Social media | No | There is no social feed, public profile, recommendation surface, like, comment, or social sharing feature. |
| Social media disabled for users under 13 | No / Not applicable | The app has no social-media capability and does not use an age-range API. |
| Shared Location (available from November 16, 2026) | No | The app does not access or share a person's real-world location. Local pairing exchanges counter data only between the user's own nearby devices; it is not a location-sharing feature. |
| Dating and Relationships (available from November 16, 2026) | No | The app has no dating or relationship-matching features and no virtual companion that engages in romantic or sexual content. |
| Messaging and chat | No | Watch and paired iPad exchanges carry counter commands and snapshots between the user's own devices; Watch can also send Cycle Time captures to its paired iPhone. The app has no user-to-user message, chat, or public-post feature. |
| Advertising | No | The app contains no ads or paid promotion. |
| Profanity or crude humor | None | No such language or humor is part of the app. |
| Horror or fear themes | None | No such content is part of the app. |
| Alcohol, tobacco, or drug references | None | No such content is part of the app. |
| Medical or treatment information | None | Manufacturing calculations do not provide medical diagnoses or treatment guidance. |
| Health or wellness topics | None | The app is for manufacturing measurements and production records, not health or lifestyle advice. |
| Mature or suggestive themes | None | No such content is part of the app. |
| Sexual content or nudity | None | No such content is part of the app. |
| Graphic sexual content or nudity | None | No such content is part of the app. |
| Cartoon or fantasy violence | None | No such content is part of the app. |
| Realistic violence | None | No such content is part of the app. |
| Prolonged graphic or sadistic realistic violence | None | No such content is part of the app. |
| Guns or other weapons | None | No such content is part of the app. |
| Gambling | No | No betting or wagering is offered. |
| Simulated gambling | None | No simulated betting or wagering is offered. |
| Contests | None | Production targets are private operational goals; users do not compete for rankings or rewards. |
| Loot boxes | No | No randomized virtual items are sold or awarded. |

## Age category and release notes

- Do not select **Made for Kids**. Factory Tools is designed for manufacturing work.
- Do not override Apple's calculated rating unless the publisher has a specific, documented reason.
- With the proposed “none/no” responses, an all-ages result (4+ on Apple's current global scale) is expected; Apple's questionnaire and any region-specific rules determine the actual published result.
- Leave the optional Age Suitability URL blank unless the publisher creates a page specifically describing the app's age suitability.
- Recheck the final answers after any feature addition involving browser access, public sharing, communication, age controls, ads, health information, or chance-based rewards.

## Evidence and limits

The current product has local production data, backup/CSV export, external policy/support links when configured, StoreKit purchase, direct Watch/iPad counter transport, and direct Watch Cycle Time capture. Those features do not appear to add social, messaging, unrestricted in-app browsing, advertising, medical, or chance-based content under the cited definitions. This is an inference from the current source; the publisher must make the final App Store Connect declaration against the release build.
