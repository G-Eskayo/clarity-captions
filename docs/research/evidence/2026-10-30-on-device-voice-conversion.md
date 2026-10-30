# On-device voice conversion and cloning: nothing ready for a paid iPhone app yet

- **Sources:** Yang et al., *StreamVC: Real-Time Low-Latency Voice Conversion*, ICASSP 2024,
  [arXiv 2401.03078](https://arxiv.org/abs/2401.03078). Sadov, Hutter & Near, *Low-latency Real-time Voice Conversion
  on CPU*, [arXiv 2311.00873](https://arxiv.org/abs/2311.00873), [KoeAI/LLVC](https://github.com/KoeAI/LLVC).
  [myshell-ai/OpenVoice](https://github.com/myshell-ai/OpenVoice) README. [Plachtaa/seed-vc](https://github.com/Plachtaa/seed-vc).
  Apple, [`requestPersonalVoiceAuthorization`](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/requestpersonalvoiceauthorization(completionhandler:)).
  Consumer Reports on consent in cloning apps
  ([2025](https://www.consumerreports.org/electronics/identity-theft/voice-cloning-apps-let-criminals-easily-steal-your-voice-a6024784872)).
- **What we took:** StreamVC converts any voice to any voice while streaming, at 70.8 ms on a Pixel 7, but no code or
  weights are released. LLVC runs under 20 ms on a CPU (MIT code) but converts to one fixed voice. OpenVoice V2's
  tone-colour converter is MIT and "free for commercial use", covers Spanish natively, but isn't streaming or
  phone-sized as released. Seed-VC has about 300 ms delay, wants a GPU and its licence is unclear (a mirror says
  GPL-3.0). Apple's Personal Voice is only the device owner's own voice. Popular cloning apps checked consent poorly.
- **Confidence:** Moderate for what each project says about itself (papers and READMEs, not our measurement). Weak for
  Seed-VC's licence. No size, heat or battery number on an iPhone exists for any of them.
- **Drives:** #247 part 2: no voice conversion now; OpenVoice V2 is the first to port and measure if the owner wants
  timbre later, with the consent rules in `voice-match-spike.md` (session only, never saved, only the live
  translation of that person's words, off by default).
- **Public use:** Internal.
