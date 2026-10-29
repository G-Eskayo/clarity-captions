# E24. How the Mac app knows a call has started and ended: Core Audio, not CallKit

- **Source:** Apple's macOS 27 SDK header `CallKit.framework/Headers/CXCallObserver.h`
  (`API_UNAVAILABLE(macos, tvos)`); Core Audio's process objects ([kAudioHardwarePropertyProcessObjectList](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyprocessobjectlist),
  `kAudioProcessPropertyIsRunningInput/Output`, macOS 14.2+); our own probe and app runs on the owner's MacBook Pro
  (macOS 27.0.1), #178 / PR #179.
- **What we took:** CallKit's call observer can't be used on macOS: the compiler refuses it. Core Audio lists every
  process using sound and whether it is recording or playing, with change notifications and no permission. #178's rule:
  a call is live while FaceTime or its call services (`com.apple.FaceTime`, `avconferenced`, `callservicesd`) use the
  microphone; an end must hold 2 s. In the app, switching from the room to the call takes 1.0 s; speech after that
  was captioned word for word (pretend call, `say` speech through the tap).
- **Real FaceTime call (2026-10-28, 20:43–20:46 UTC, owner's MacBook Pro):** ringing showed only
  `com.apple.FaceTime[out]` (not counted, correct); on answer `com.apple.avconferenced` opened the mic
  (`[inout]`) and held it until hang-up, with one sub-second drop at 20:44:16 that the 2 s grace covers. The #178
  build, launched idle during a second call, saw it by itself, switched to the call format, said "Captioning your
  FaceTime call" and captioned both people live. Replayed as `RealFaceTimeCallReplayTests`.
- **Confidence:** High for FaceTime video calls on this Mac. Continuity phone calls, Zoom/Teams/WhatsApp names: not
  yet seen live.
- **Drives:** #178's `CallSignal` / `CallWatcher`.
- **Public use:** Internal (process detail; added when the log moved to one file per entry, #210).
