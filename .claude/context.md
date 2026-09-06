## Status (2026-09-06)
**Branch:** emdash/slimy-jokes-juggle-rl3y8
**Last commit:** afa3839 — feat(app): add settings menu, about panel and provider visibility toggles
**In progress:** Gear-icon settings menu feature complete: Settings window (Generali/Provider tabs), About window, per-provider visibility with polling stop/start. Settings/About use a custom AppKit NSWindow presenter (AppWindowPresenter), not the SwiftUI Settings scene — deliberate, documented in UX-BLUEPRINT.md.
**Next:** Not committed to PR/push yet. Manual GUI verification of the new gear menu, Settings tabs and About window (per plan's Verifica section) still recommended before merging.
**Open decisions:** none — RTF review cycle closed with 2 report-only/deferred findings (architectural NSWindow deviation, minor view-level test coverage gap), both accepted.
