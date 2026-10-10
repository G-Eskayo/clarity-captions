# Honest claims: what Seal says about itself (2026-10-10)

Gil on #117: "make sure not to be false advertising… claiming it can differentiate people and their names when we
don't really have that capability at the moment."

What Seal can honestly say today:
- **Voices:** it starts a new line when the voice changes and labels it Speaker 1, Speaker 2. It goes by the sound of
  the voice, so it can mix people up: similar voices can share a label, and one person changing pitch can get a new
  one (evidence log E8, #91). It never knows who anyone is.
- **Names:** naming speakers is removed in v1 (#117). The "Words and names" list was taken out of Settings (#105).
- **Accuracy and speed:** Apple's on-device speech. Captions can be wrong. Lag hasn't been measured on a real phone yet
  (the simulator has no speech engine), so no "within a second" promise.
- **Reading:** OpenDyslexic is offered for comfort. No claim that it helps people read (E5).

Every user-facing claim found, checked against that. "Keep" means it's already honest.

| Where | Today | Proposed | Why |
|---|---|---|---|
| App, tour step 2 (`HowToUseTour.swift`) | "Your words show up here as people talk. Each new voice gets its own label." | "Your words show up here as you talk." Then: "Each voice gets its own line and label. Seal goes by the sound of the voice, so it can mix people up. It doesn't know who anyone is." | "Each new voice gets its own label" promises more than the model does. |
| App, first run (`FirstRun.swift`) | "Getting ready to tell voices apart" | Drop the screen. The launch dance covers the warm-up (#119). If it stays: "Getting ready" | Overstates it, and the screen is going away anyway. |
| App, first run | "Almost there! This is a one-time warm-up so you never wait later." | (gone with the screen) | "Never wait later" isn't true: Start still has to get ready until #119 lands. |
| App, first run | "Hi! Let's get you set up." / "I'll help you follow conversations by showing what people say. This takes about a minute." | "Seal shows what people around you are saying." / "It all happens on this phone. Setup takes about a minute." | Plain, no "I" voice, no exclamation. (Mock-up 03.) |
| App, first run | "This device can't show captions" / "…Sorry about that!" | "This phone can't run Seal." / "It needs an iPhone 12 or newer, or an iPad with an A14 chip or newer." | Concrete, matches the store listing and #101. |
| App (`ContentView`) | "Seal tells voices apart as people talk." banner | Removed (#117) | Overclaim, and a box. |
| App | "Name this speaker", "Double tap to name this speaker", "Speaker name", "Clear Name", "Enter a custom name…" | Removed with naming (#117, #118) | Naming is out of v1. |
| App, Settings | "OpenDyslexic was made for people with dyslexia. Atkinson Hyperlegible was designed by the Braille Institute for low vision." | Keep | Says who each font was made for, not that it helps. |
| App, beta | "It never keeps what anyone said." / "Never what anyone said." | Keep | True: reports hold no caption text (tested). |
| App, beta rating | "Every word" (top of the 1–10 scale) | Keep | It's the tester's rating, not a claim. |
| site/support.html, "Why does it say Speaker 1…" | "Seal notices when a different person starts talking and starts a new line for them. It does not know who people are. Tap a speaker label to give that voice a name for the conversation." | "Seal starts a new line when the voice changes and labels it Speaker 1, Speaker 2. It goes by the sound of the voice, so it can mix people up, especially similar voices. It doesn't know who anyone is." | Naming is gone; "a different person" overstates it. |
| site/support.html, "The captions got a name or word wrong" | "Open Settings and add it under 'Words and names'. Seal will then expect those words…" | "Captions come from your phone's speech recognition and can get words wrong, names most of all. For anything important, check with the person speaking." | "Words and names" was removed from Settings. |
| site/privacy.html, "What stays on your device" | "Names you give speakers and words you add (such as names of people and places) stay on your device." | Remove the line. | Neither exists in v1. |
| site/privacy.html | "Telling voices apart ("Speaker 1", "Speaker 2") is also done on your device…" | Keep | About where it happens, not how well. |
| docs/app-store-listing.md, promotional text | "…shows who is speaking…" | "…starts a new line when the voice changes…" | "Who" implies identity. |
| docs/app-store-listing.md, description | "When someone new starts talking, Seal starts a new line and labels them Speaker 1, Speaker 2 and so on. Tap a label to give that voice a name." | "When the voice changes, Seal starts a new line and labels it Speaker 1, Speaker 2. It goes by the sound of the voice, so it can mix people up." | Naming is gone; honest about mix-ups. |
| docs/app-store-listing.md, description | "Add names and words you use often so Seal spells them right" | Remove | Not in v1's Settings. |
| docs/app-store-listing.md, description | "Captions scroll on their own; scroll back to reread and tap to jump to the newest line" | Keep | True. |
| docs/app-store-listing.md, description | "Conversations are saved on your device for 30 days…" | "Tap [ Save ] to keep a conversation on your phone for 30 days." | Saving is no longer automatic (#106). |
| docs/app-store-listing.md, review notes | "…a bundled Core ML model (FluidAudio, Sortformer) labels who is speaking." | "…labels changes of speaker (Speaker 1, Speaker 2); it doesn't identify anyone." | Same reason as the promo text. |
| docs/app-store-listing.md, review notes | "Captions appear within about a second." | "Captions appear as people talk." (Add a number once it's measured on a phone.) | Not measured on a device yet. |
| docs/app-store-listing.md, review notes | "Tap a speaker label to name it." / "Tap Stop. The conversation is saved on the device…" | Remove the naming line. "Tap ✕ to pause, then [ Save ] keeps it on the device for 30 days." | Naming is gone; saving is a button now. |
| docs/app-store-listing.md, description | "Captions are made by a computer and can contain mistakes. Seal is not a medical device." | Keep | Honest, and needed for review. |

Nothing found claims a reading or hearing benefit. Keep it that way in the marketing site (#44) and the portfolio page.
