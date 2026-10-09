# App Review risks for Seal's first submission (2026-10-09)

Researched 2026-10-09 for a planned submission around 13-15 Oct and a hard go-live of 25 Oct.
This doc covers only what `app-store-compliance.md` and `app-store-listing.md` miss or get wrong,
plus things found by reading the code and project files. Read it alongside those two docs.

Labels used below:
- **[Apple]**: stated in Apple's own guidelines or help pages (link given).
- **[Repo]**: checked directly in this repository on 2026-10-09.
- **[Anecdotal]**: forum or blog reports from other developers. Real cases, not policy.

## What the existing docs get wrong or leave out

1. **The app has no check that this device can run Apple's speech engine.** [Repo] Nothing in the code
   calls `SpeechTranscriber.isAvailable`, `supportedLocale(equivalentTo:)` or `DictationTranscriber`.
   An Apple engineer has said `SpeechTranscriber` has hardware requirements beyond "runs iOS 26": A16-class
   iPads meet them, older ones don't. Developers report it returning false on iPhone 11 and SE 2nd gen,
   which both run iOS 26. The build supports iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), and reviewers test
   universal apps on iPad. A reviewer on an older iPad would see an app that does nothing, which gets a
   2.1 rejection. Neither existing doc mentions this. It is the biggest technical risk found.
2. **The iPad build will probably fail upload validation.** [Repo + Anecdotal] The orientations are set to
   Portrait, LandscapeLeft and LandscapeRight, with no `PortraitUpsideDown` and no iPad-specific key.
   iPad apps that support multitasking have long been refused at upload with ITMS-90474 unless they
   declare all four orientations. `UIRequiresFullScreen`, the old way out, is deprecated as of iPadOS 26
   (TN3192). This costs nothing to find early by uploading a TestFlight build now.
3. **The privacy manifest needs more than UserDefaults.** [Repo] FluidAudio v0.17.5 (the checked-out
   version) ships **no** `PrivacyInfo.xcprivacy`. Because it is a statically linked Swift package, its code
   becomes part of the app binary. It calls `FileManager.attributesOfItem` (a file-timestamp
   required-reason API) in `ModelCache.swift`, `FileDownloader.swift` and `AudioSourceFactory.swift`.
   It also contains Hugging Face download code (`URLSession`), switched off by `ModelHub.offlineMode = true`.
   The app's own manifest therefore has to declare `NSPrivacyAccessedAPICategoryFileTimestamp` (C617.1)
   as well as UserDefaults (CA92.1). The listing doc's P5 item says to "check whether FluidAudio ships its
   own". It doesn't.
4. **The Mac target can't be uploaded as it stands.** [Repo + Apple 2.4.5(i)] `Apps/Mac/project.yml` has no
   entitlements file, so it has no App Sandbox and no `com.apple.security.device.audio-input`.
   Mac App Store apps must be sandboxed (2.4.5(i)). A sandboxed app without `audio-input` gets silent
   microphone input, which developers report as all-zero samples [Anecdotal]. The Mac target also has
   no asset catalog, so no app icon (`Apps/Mac/Resources` holds only `Models/`). It also needs its own
   16:10 screenshots [Apple]. Recommendation: leave the Mac app out of this submission and remove
   "Mac" from the description.
5. **ADR 0020 says it is "Implemented by #10", but the background-audio key is not in the project.**
   [Repo] Neither `project.yml` nor the generated `.pbxproj` contains `UIBackgroundModes`. The listing doc's
   "Holds" section is right; the ADR's status line is wrong and should be corrected so nobody assumes
   background captioning works.
6. **The review queue in Sept/Oct 2026 is slower than "2-5 days".** [Anecdotal] Developer forum threads from
   the last three weeks report version-1.0 apps sitting in "Waiting for Review" for 1-3 weeks: five apps
   submitted 24-28 Sep for Shipaton, one waiting since 12 Sep, and one submitted 2 Oct with an expedite
   request filed 5 Oct. With submission on 13-15 Oct and go-live on 25 Oct, there is room for one review
   and perhaps one quick resubmission, not two rejection cycles.
7. **The EU trader-status answer is required even if you skip the EU.** [Apple] App Store Connect asks for
   it when you submit a new app, and you must declare a status even if you don't distribute in the EU.
   Since 17 Feb 2025, apps without a trader status are removed from EU storefronts. If you declare
   yourself a trader, your address (or PO box), phone number and email appear on the product page.
8. **The age-rating questionnaire grew again in 2026.** [Anecdotal, secondary sources] New questions about
   user-generated content shown in feeds or discovery features appeared on 9 Jul 2026 and became required
   for submissions in Sept 2026. Answer them "No". Seal has no feed, and Share only hands text to another app.

## Ranked risk table

Likelihood is for this app as it stands today, before the fixes.

| # | Risk | Guideline | Likelihood | What triggers it | Prevention | Evidence |
|---|---|---|---|---|---|---|
| 1 | App does nothing on the reviewer's device | 2.1(a) | **High** if iPad stays enabled; Medium otherwise | `SpeechTranscriber` is not available on that hardware, so no captions and no message | Check `SpeechTranscriber.isAvailable` and locale support at launch. If either fails, use `DictationTranscriber` or show a plain "This device can't run Seal's captions" screen. Test on the oldest iPad you can borrow. | [Apple engineer, forum 801197, Sep 2025](https://developer.apple.com/forums/thread/801197); [806765](https://developer.apple.com/forums/thread/806765), [807739](https://developer.apple.com/forums/thread/807739) [Anecdotal device lists, late 2025] |
| 2 | Review delay pushes go-live past 25 Oct | (process) | **High** | Queue backlog for new apps; any rejection adds a full queue wait | Upload a TestFlight build now. Submit the day the build is ready, not on a fixed date. Set release to "Automatically release". Have an expedite request drafted (see notes). | [848708, Sep 2026](https://developer.apple.com/forums/thread/848708); [849518, 5 Oct 2026](https://developer.apple.com/forums/thread/849518); [840385, Jul 2026](https://developer.apple.com/forums/thread/840385) [Anecdotal] |
| 3 | Background audio rejected | 2.5.4 | **High** if `UIBackgroundModes` audio ships; None if it stays on hold | Reviewers read the `audio` mode as playback-only. Recording-only apps report rejections. | Keep background captioning out of v1 (as the listing doc's Holds say), or ship it with a screen recording attached in App Review notes and a step-by-step test. | [Apple 2.5.4](https://developer.apple.com/app-store/review/guidelines/#2.5.4); [forum 776949, Mar 2025-Jan 2026: real-time transcription app rejected; DTS says foreground-started recording may continue](https://developer.apple.com/forums/thread/776949); [826849, May 2026: rejected 3x despite video](https://developer.apple.com/forums/thread/826849) [Anecdotal] |
| 4 | Upload refused: iPad orientations | ITMS-90474 (upload validation) | **Medium-High** | Multitasking-capable iPad build without all four orientations | Add `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` with all four orientations. Confirm the caption layout survives upside-down and Split View. | [TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key) [Apple]; [ITMS-90474 reports](https://forum.defold.com/t/error-itms-90474-invalid-bundle-ipad-multitasking-support-requires-these-orientations/56128) [Anecdotal, older] |
| 5 | Missing required-reason declarations | Privacy manifest (since 1 May 2024) | **Certain** without a manifest | UserDefaults (app) + `attributesOfItem` (FluidAudio) in the binary | Add `PrivacyInfo.xcprivacy` to the app target with UserDefaults/CA92.1 and FileTimestamp/C617.1, tracking = false, no collected data types. Re-check the upload email for any other category it names. | [Apple upcoming requirements](https://developer.apple.com/news/upcoming-requirements/); [ITMS-91053 examples](https://forum.juce.com/t/missing-api-declaration/60484) [Anecdotal] |
| 6 | First-run speech download fails during review | 2.1 | Medium | Reviewer network is slow or filtered, or the asset download stalls; app sits on a progress bar | Make sure the download screen shows a clear error with a Retry button and never spins forever. Mention the download in notes (already drafted). Test with Network Link Conditioner on "Very Bad Network". | [Repo] `SpeechModelInstaller.swift`; no external source |
| 7 | Reviewer tests in a silent room and sees "Can't hear" | 2.1 | Low-Medium | No speech near the device, so it looks broken | Notes already say to play a podcast. Make sure "Can't hear" can't appear in the first ~10 s of a session. | [Repo] ADR 0018 |
| 8 | Mac build rejected or can't be uploaded | 2.4.5(i), 2.1 | **High** if included | No sandbox entitlement, no mic entitlement, no icon, no Mac screenshots | Submit iPhone + iPad only. Add the Mac platform to the same record later. Separately, check whether to switch off "Make this app available on Mac" (Apple silicon) in Pricing and Availability for v1. | [Apple 2.4.5](https://developer.apple.com/app-store/review/guidelines/#2.4.5); [sandbox audio-input zero samples, forum 771048](https://developer.apple.com/forums/thread/771048) [Anecdotal] |
| 9 | Recording consent / indication | 2.5.14 | Low | Conversations are saved automatically when captioning stops; the reviewer may count that as "making a record" | First-run screen should say in one line that conversation text is saved for 30 days and can be deleted. The mic indicator plus the Start button cover consent. | [Apple 2.5.14](https://developer.apple.com/app-store/review/guidelines/#2.5.14) |
| 10 | "Live Captions" in the store name | 2.3.7 / 5.2.5 | Low | "Live Captions" is also the name of Apple's own accessibility feature | Probably fine: it is descriptive, and other apps use similar wording. If you want zero risk, use "Seal: Conversation Captions" (27 characters). Never use Apple's icon style or the word "Apple". | [Apple 5.2.5](https://developer.apple.com/app-store/review/guidelines/#5.2.5) [Apple, judgment call] |
| 11 | Health framing | 1.4.1 / 5.1.1(ix) | Low | Copy reads as treating hearing loss. 5.1.1(ix) says healthcare services should come from legal entities, not individuals. | Already handled by the listing copy. Keep "accessibility" framing, and answer the age-rating "Medical or wellness" question "None". | [Apple 1.4.1, 5.1.1(ix)](https://developer.apple.com/app-store/review/guidelines/#1.4.1); [wellness app flagged despite disclaimers, forum 807508, late 2025](https://developer.apple.com/forums/thread/807508) [Anecdotal] |
| 12 | iOS 27 behaviour on review devices | 2.1, 2.5.1 | Low-Medium | Reviewers may run iOS 27; Speech or AVAudioSession behaves differently | Run the full self-test on iOS 27 release (not beta) before submitting. Build with release Xcode; this Mac has Xcode 26.6, which meets the 28 Apr 2026 minimum. | [Apple upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) |

## Pre-submission checklist (in order)

Items already tracked in `app-store-listing.md` (P1-P3, E1, M2, C1, C2) are not repeated, except where
the order matters.

1. **Today:** create the App Store Connect record with bundle ID `com.gileskayo.captions` and reserve the
   name. Answer DSA trader status (Business > Agreements > Compliance) so it can't block submission later.
2. **Add the device check (risk 1).** Use `SpeechTranscriber.isAvailable` and locale support, and either
   fall back to `DictationTranscriber` or show a plain-language "not supported on this device" screen.
   Either is acceptable to review; a blank screen is not.
3. **Add `PrivacyInfo.xcprivacy` to the iOS target:** UserDefaults CA92.1, FileTimestamp C617.1,
   `NSPrivacyTracking` false, empty collected-data list.
4. **Fix iPad orientations:** all four, iPad only.
5. **Add `ITSAppUsesNonExemptEncryption = NO`** (already in the listing doc). Do it in the same commit
   as steps 3-4.
6. **Upload a build to TestFlight now**, before the app is finished. This surfaces ITMS-90474, ITMS-91053,
   icon and other validation errors days early. Read the email Apple sends after processing, not just
   the Xcode result.
7. Decide **iPhone + iPad only** for v1. Remove "Works on iPhone, iPad and Mac" from the description, or
   change it to "iPhone and iPad".
8. Decide on **background captioning** (open question 1). If it stays on hold, make sure no
   `UIBackgroundModes` key slips in. Fix ADR 0020's status line either way.
9. **Test on real hardware, in this order:** iPhone 17 on iOS 26.x; iPhone on iOS 27 release; the oldest iPad
   available (expect the unsupported path); an iPad with A16 or M-series for the full path. Run first launch
   from a clean install each time, so the speech download runs, plus once with a bad network.
10. Check the **age rating** in App Store Connect, including the July 2026 feed/UGC questions (all No),
    and confirm the result is 4+.
11. Fill in the optional **Accessibility Nutrition Labels** (App Accessibility in App Store Connect). They are
    voluntary for now [Apple], but for an accessibility app they cost nothing and tell reviewers the
    category is intentional.
12. **Screenshots:** an iPhone Dynamic Island "medium" set (1206×2622 or 1179×2556) and a 13-inch iPad set
    (2064×2752 or 2048×2732) [Apple]. No Mac set unless the Mac app ships.
13. Host privacy/support pages with the real contact email (the draft still says `SUPPORT_EMAIL_TBD`), and
    open both URLs on a phone to confirm they load.
14. Add the in-app privacy link (listing doc P3). Then archive, upload, attach the build, and submit with
    the notes below.
15. If 3 business days pass in "Waiting for Review", file an expedited review request (see notes).

## Review notes must say

The listing doc's draft notes are good; add these points to them.

- Which devices it needs: "Live captioning uses Apple's SpeechTranscriber, which needs recent hardware
  (A16-class or newer on iPad). On older devices Seal shows a message saying so." Only write this if the
  check in step 2 exists.
- That the first launch downloads Apple's English speech model and needs network once. Already drafted;
  keep it.
- That transcripts, not audio, are saved on the device for 30 days, are excluded from backup, and can be
  deleted from Saved conversations. This answers 2.5.14 and 5.1.1 before the reviewer asks.
- That the app is English only (en-US) for now, so a reviewer on a non-English device locale isn't surprised.
- No account, no network service, no third-party AI, no analytics (already drafted).
- If background captioning ships: the 2.5.4 paragraph already drafted, plus an **attached screen recording**
  (lock the phone mid-sentence, unlock, show the "while you were away" marker). Forum reports say
  reviewers sometimes can't find background features, and a video is the usual fix.
- A contact phone number and email in App Review Information that you will actually answer during
  13-25 Oct.

## Open questions only the owner can answer

1. **Background captioning in v1, yes or no?** It is the single biggest rejection risk if it ships, and
   ADR 0020 says users need it. The middle path is v1 without it and a 1.1 update with it plus a video.
2. **iPad in v1?** Keeping it means the device check (step 2), the orientation fix, iPad screenshots and
   a real-iPad test. Dropping it (`TARGETED_DEVICE_FAMILY: "1"`) removes risks 1 and 4 on iPad, but the
   iPhone 11/SE 2 problem remains, so the device check is needed anyway.
3. **Mac in v1?** Recommended: no.
4. **Trader or non-trader under the EU DSA?** A free app with no ads or IAP from an individual is plausibly
   non-trader, but Apple won't decide for you. Trader means your contact details are public in the EU.
5. Should Seal also be available as an iPhone app on Apple silicon Macs until the native Mac app ships?
   It is untested there.
6. Which phone number and email should App Review contact during the window?
7. Is your mother's birthday an "event" for an expedite request? Apple's criteria are an event the
   developer is directly associated with, and a personal birthday is a weak case. Be honest in the
   request. A new app with no history gets less benefit of the doubt.

## Sources consulted

- App Review Guidelines (fetched 2026-10-09): https://developer.apple.com/app-store/review/guidelines/
- Upcoming requirements: https://developer.apple.com/news/upcoming-requirements/
- DSA trader requirements: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- App privacy details ("processed only on device is not collected"): https://developer.apple.com/app-store/app-privacy-details/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Accessibility Nutrition Labels: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels
- Age rating changes (secondary): https://mjtsai.com/blog/2025/07/28/updated-age-ratings-in-app-store-connect/
- Universal purchase with a native AppKit app (DTS answer): https://developer.apple.com/forums/thread/751188
- Expedited review criteria: https://developer.apple.com/contact/app-store/?topic=expedite
