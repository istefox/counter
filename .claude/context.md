## Status (2026-09-06)
**Branch:** feat/antigravity-provider (merged to main, PR #3, merge commit 30e6841)
**Last commit:** e56cab3 — feat(app): add Antigravity (Gemini) usage provider
**In progress:** All three planned providers are now implemented and merged: Claude Code (PR #1), Codex (PR #2), Antigravity/Gemini (PR #3). Antigravity's mechanism: Nimbalyst has no Gemini CLI code at all — its "Gemini" is entirely Google Antigravity IDE. Attaches to a running `language_server` hub (ps/lsof discovery) or spawns a standalone one, calls `GetUserStatus` over local Connect-RPC/HTTPS, reads `quotaInfo.remainingFraction`/`resetTime` per model. Verified live against the real account (Google AI Plus tier) — fixed a real `Process`+`Pipe` deadlock in the ps/lsof discovery helper (drain pipe before `waitUntilExit()`).
**Next:** No planned provider work remains. Possible follow-ups: app icon/branding polish, notarization/distribution, or additional per-model breakdown UI.
**Open decisions:** none
