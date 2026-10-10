# TestFlight builds: beta feedback (ADR 0023)

## Before archiving a TestFlight build: set the recipient

The owner's phone number is never committed (the repo is public). Create the gitignored file
`Apps/Spike/Beta.xcconfig.local` on the Mac that archives the build:

```
SEAL_FEEDBACK_RECIPIENT = +1XXXXXXXXXX
```

`Apps/Spike/Beta.xcconfig` includes it (`#include?`), and `Info/LaunchInfo.plist` copies it into the
`SealFeedbackRecipient` key. Regenerate the project after creating it (`sh scripts/generate-spike-project.sh`).

Without it the app still works: **Send feedback to Gil** opens the share sheet instead of Messages.

Check a built app: `plutil -extract SealFeedbackRecipient raw <App>.app/Info.plist`.

## How the app knows it's a TestFlight install

At launch the app asks StoreKit (`AppTransaction.shared`). A verified `sandbox` answer (TestFlight) or `xcode`
(run from Xcode) turns the beta features on. `production` (App Store), an unverified answer or an error turns them off,
and anything left on the phone from an earlier TestFlight install is deleted, never sent.

## TestFlight "What to Test" (paste into App Store Connect)

> This test version asks how each conversation went and keeps measurements like caption lag and battery. It never
> keeps what anyone said. You choose when to send them to Gil: Settings → Test version → Send feedback to Gil.
>
> Please try it in real conversations: at a table, in a restaurant, with two or more people. After you tap [ New ],
> rate how well you could follow it (1–10). A note helps a lot when something went wrong.

## What a tester sees

- **Once, on the first launch of a test build:** the notice (mock-up 06).
- **After a conversation:** the rating card (mock-up 01). If the tester paused it themselves (Stop), the card waits until
  they tap [ New ]; if it paused without them (quiet stop, a failure, the app closed or left mid-conversation), it also
  shows when they come back to it. Never while captioning, at most once per conversation.
- **Settings → Test version:** how many conversations are waiting, a preview of exactly what will be sent, then
  Messages with the report attached. Conversations are deleted from the phone only after Messages reports *sent*; the
  one still on screen stays and is sent again later under the same id.

## Debug flags for screenshots (Debug builds only)

`-ClarityDemoBeta`, `-ClarityDemoBetaSeed`, `-ClarityDemoBetaCard`, `-ClarityDemoBetaNote`, `-ClarityDemoBetaNotice`,
`-ClarityDemoBetaPreview`, `-ClarityDemoFlow rate|feedback` (see `Apps/Spike/Sources/DemoMode.swift`).
