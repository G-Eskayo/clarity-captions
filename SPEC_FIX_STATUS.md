# Spec Fix Status

## Completed

### 1. Fixed `docs/design/from-into-spec.md` ✅
All 7 must-fix defects from code review corrected:

- **Line 12 (Pick stalls)**: Now documents the actual 90-second stall watchdog (SpeechDownload.swift:68,102–109), not "no timeout"
- **Line 13 (Pick fails)**: Corrected file citations and clarified download problem messages
- **Line 14 (Same language)**: Fixed preamble contradiction — now accurately states that `TranslationTargetList.rows()` filters out the caption language, and when selected via API, `TranslationCenter` detects it as `.unsupported` by Apple's Translation
- **Line 16 (Change From while captioning)**: Corrected to state that captions switch on NEXT caption stream, not mid-conversation
- **Line 15 (Pick downloads)**: Clarified "next Start or new conversation" instead of implying mid-stream switch
- **Line 17 (Cross-instance race)**: Corrected to describe the actual gap: two separate `SpeechDownload` instances in the same app (first-run + CaptionLanguageCenter.choose), not two devices
- **Line 19 (Mid-session From not live)**: Fixed the contradiction — now clearly states captions stay in old language until new caption stream starts
- Corrected all file:line citations to match actual code locations

### 2. Updated `.gitignore` ✅
Added entry for `.gh-issue-body.txt` to prevent scratch files from being committed

### 3. Created `issue_body.md` ✅
Properly formatted GitHub issue body with the spec table, north star, decisions section, and all referenced tickets/ADRs

### 4. Created `file_issue.py` ✅
Python script to file the issue and reply to PR #256 (ready to run manually)

## Blocked

### GitHub Operations
Cannot run `gh` commands in this headless environment with don't-ask mode:
- Create issue: `gh issue create --repo G-Eskayo/clarity-captions --title "..." --label "..." --body-file issue_body.md`
- Reply to PR: `gh pr comment 256 --repo G-Eskayo/clarity-captions --body "..."`

## Next Steps

**Option A (Manual):**
```bash
cd /Users/gileskayo/.agents-pipeline-worktrees/pipeline-g-eskayo-clarity-captions-279
gh issue create --repo G-Eskayo/clarity-captions \
  --title "Spec: From/Into behavior in every case (#256 + #252)" \
  --label "needs-info,feature:translation" \
  --body-file issue_body.md

# Note the issue number from the output, then:
gh pr comment 256 --repo G-Eskayo/clarity-captions --body-file issue_pr_reply.md
```

**Option B (Automated):**
```bash
cd /Users/gileskayo/.agents-pipeline-worktrees/pipeline-g-eskayo-clarity-captions-279
python file_issue.py
```

## Verification

All defects fixed with references verified against actual code in:
- Packages/CaptionCore/Sources/CaptionCore/CaptionLanguage.swift (CaptionLanguageSwitch)
- Packages/CaptionCore/Sources/CaptionCore/SpeechDownload.swift (stall watchdog, download problem)
- Apps/Spike/Sources/TranslationCenter.swift (configuration, same-language handling)
- Apps/Spike/Sources/CaptionLanguageCenter.swift (engineLocale, current)

No code changes, no tests run, no app built — this ticket is documentation only.
