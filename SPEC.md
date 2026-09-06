# SPEC — Menu bar settings gear, About panel, and provider visibility toggles

**Topic slug:** menubar-settings-menu

## Objectives

Move "Avvia al login" out of the main usage popover into a dedicated Settings window, add an
About panel showing app name/version/copyright/links, and let the user choose which of the three
usage providers (Claude Code, Codex, Antigravity) are shown in the main popover — reachable from
a gear icon inside the popover rather than a native right-click context menu.

## Scope

In scope:
- A gear icon in the bottom-right corner of the existing usage popover (`UsagePopoverView`).
- Clicking the gear opens a small dropdown menu with three items: Impostazioni, About, Esci.
- A Settings window (SwiftUI `Settings` scene, `Cmd+,`) with two tabs: "Generali" (Avnvia al
  login) and "Provider" (three visibility toggles, one per provider).
- Removing the "Avvia al login" toggle from the main popover (it moves to Settings → Generali).
- An About panel/window: app name, version, copyright, link to the GitHub repository
  (istefox/counter), link to istefox.dev.
- Persisting provider visibility state across launches.
- Filtering the main popover's provider sections by the persisted visibility state.
- Stopping background polling for a provider's monitor when that provider is toggled off, and
  resuming polling when it is toggled back on.
- Scoping "Aggiorna ora" to currently visible providers only.
- A placeholder message in the popover when all three providers are hidden.
- Unit tests (Swift Testing) for the persistence and filtering logic.

Out of scope:
- Native NSStatusItem-based left/right-click distinction (explicitly declined by the user in
  favor of the gear-icon approach — MenuBarExtra stays as-is).
- Per-model breakdown UI changes, notarization/distribution, app icon/branding polish (tracked
  separately, not part of this feature).
- Any change to the underlying provider usage-fetching mechanisms (Claude Code, Codex,
  Antigravity monitors) beyond start/stop of polling.

## Stack

- Swift 6, SwiftUI, `@Observable` (existing pattern in the codebase).
- `ServiceManagement` (`SMAppService`) — already used by `LoginItemManager`, unchanged.
- `UserDefaults` / `@AppStorage` for provider visibility persistence.
- Swift Testing for new unit tests (per `AgentLimitsTests` target, XCTest not used for new code).
- No new external dependencies.

## Architecture

- `AgentLimitsApp.swift` gains a second `Scene`: `Settings { SettingsView() }`, alongside the
  existing `MenuBarExtra`. This is the standard SwiftUI mechanism for a Settings window and
  gives the app the conventional `Cmd+,` shortcut for free when the Settings window is key.
- New `ProviderVisibilityStore` (`@Observable`, `@MainActor`), analogous in shape to
  `LoginItemManager`, owning three persisted booleans (`isClaudeVisible`, `isCodexVisible`,
  `isAntigravityVisible`) backed by `UserDefaults` via `@AppStorage`-equivalent keys, default
  `true` for all three (so existing users see no behavior change until they open Settings).
- `UsagePopoverView` reads `ProviderVisibilityStore` from the environment and:
  - Renders each provider's `providerSection` conditionally on its visibility flag.
  - Shows a placeholder view ("Nessun provider selezionato — abilitane uno in Impostazioni")
    when all three flags are false.
  - Scopes the "Aggiorna ora" action to only the visible monitors.
  - Adds a gear `Image(systemName: "gearshape")` button, bottom-right corner, that presents a
    SwiftUI `Menu` (styled as a small dropdown, not a full-screen menu) with three actions:
    - "Impostazioni" — opens the Settings window (`NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`, the standard SwiftUI-scene-independent way to open a `Settings` scene programmatically, or `openSettings()` environment action on macOS 14+).
    - "About" — opens a new `AboutView` (a plain SwiftUI window scene, e.g. `Window("About AgentLimits", id: "about") { AboutView() }`, or `NSApp.orderFrontStandardAboutPanel` with custom `NSApplication.AboutPanelOptionKey` options — architect to choose based on how much custom content is needed for the istefox.dev link).
    - "Esci" — `NSApplication.shared.terminate(nil)` (same action already in the popover today; kept in both places, per the user's explicit request to also have it in the gear menu).
- New `SettingsView` (SwiftUI `TabView`) with two tabs:
  - "Generali" — the "Avvia al login" toggle, moved verbatim from `UsagePopoverView` (same
    `LoginItemManager` binding).
  - "Provider" — three `Toggle`s bound to `ProviderVisibilityStore`'s three flags, labeled
    "Claude Code", "Codex", "Antigravity (Gemini)".
- Each usage monitor (`UsageMonitor`, `CodexUsageMonitor`, `AntigravityUsageMonitor`) needs a way
  to stop/start its polling loop from the outside. If a `stopPolling()`/`startPolling()` pair does
  not already exist symmetrically on all three, the architect adds it — polling must be
  cancellable (e.g. cancel the `Task`/timer backing `startPolling()`), not merely "ignored while
  hidden", since the requirement is to stop actual network calls.
- `AgentLimitsApp.swift`'s `.task` wires visibility-change observation (e.g. `onChange` on each
  flag, or a single point that reacts to `ProviderVisibilityStore` changes) to call
  `startPolling()`/`stopPolling()` on the matching monitor.

## Data model

`ProviderVisibilityStore` persisted keys (UserDefaults, suggested names — architect may adjust to
match existing key-naming conventions in the codebase):
- `providerVisibility.claudeCode` — Bool, default `true`.
- `providerVisibility.codex` — Bool, default `true`.
- `providerVisibility.antigravity` — Bool, default `true`.

No new persistent data beyond these three booleans. No migration needed: absent keys resolve to
default `true` via `@AppStorage`'s own default-value mechanism, so existing installations see all
three providers visible on first launch after the update, unchanged from today's behavior.

## UI flows

1. **Default state (no settings touched):** popover shows all three providers, "Avvia al login"
   is gone from the popover (moved to Settings), gear icon visible bottom-right.
2. **Opening the gear menu:** user clicks the gear icon → a dropdown appears with Impostazioni /
   About / Esci → user picks one:
   - Impostazioni → Settings window opens, focused on last-viewed tab (or "Generali" by default
     on first open).
   - About → About window/panel opens showing app icon, "AgentLimits", version string (from
     `CFBundleShortVersionString`), copyright, a link to `github.com/istefox/counter`, a link to
     `istefox.dev`.
   - Esci → app quits immediately (same as today's "Esci" button).
3. **Toggling a provider off in Settings → Provider tab:** that provider's monitor stops polling;
   the popover no longer shows that provider's section on next open (or live, if the popover is
   open — `@Observable`/environment propagation makes this live).
4. **Toggling a provider back on:** monitor's `startPolling()` is called again; the section
   reappears showing "Caricamento…" until the first refresh completes (consistent with today's
   cold-start behavior).
5. **All three toggled off:** popover shows the single placeholder message instead of any
   provider section; "Aggiorna ora" has nothing to refresh (button may be disabled or simply a
   no-op — architect's call, not a user-facing regression either way).
6. **"Aggiorna ora" with a mix of visible/hidden providers:** only visible providers' monitors
   are refreshed.

## Edge cases

- All three providers hidden → placeholder message (R-06).
- Toggling a provider on/off while its provider section is mid-refresh → the in-flight refresh
  may complete after the flag flips; the UI should reflect the current flag state, not a stale
  in-flight result racing the toggle (standard `@Observable` re-render handles this as long as
  polling is actually cancelled, not just ignored).
- App relaunch with a provider hidden → that monitor must NOT start polling until the user
  re-enables it (verifies R-05 persists across launches, not just within a session).
- Gear menu opened while the popover itself is about to close (e.g. user clicks elsewhere) → no
  special handling required beyond SwiftUI's default `Menu` dismissal behavior.
- About panel version string must reflect the actual `CFBundleShortVersionString` /
  `CFBundleVersion` from Info.plist, never a hardcoded literal, so it does not drift from
  `Project.swift`'s `CFBundleShortVersionString` on future releases.

## Success criteria

- [ ] R-01 — A gear icon appears in the bottom-right corner of the main usage popover.
- [ ] R-02 — Clicking the gear icon opens a dropdown menu with exactly three items: Impostazioni, About, Esci.
- [ ] R-03 — "Impostazioni" opens a Settings window with two tabs, "Generali" and "Provider".
- [ ] R-04 — The "Generali" tab contains the "Avvia al login" toggle, and this toggle no longer appears in the main popover.
- [ ] R-05 — The "Provider" tab contains three independently-persisted toggles (Claude Code, Codex, Antigravity), defaulting to enabled, that control which provider sections are shown in the main popover, persisted across app relaunches.
- [ ] R-06 — When all three provider toggles are off, the main popover shows a placeholder message instead of an empty list.
- [ ] R-07 — Disabling a provider's toggle stops that provider's background polling; re-enabling it resumes polling.
- [ ] R-08 — "Aggiorna ora" refreshes only the monitors of currently visible providers.
- [ ] R-09 — "About" opens a panel/window showing app name, version (read from the bundle, not hardcoded), copyright, a link to the GitHub repository (istefox/counter), and a link to istefox.dev.
- [ ] R-10 — "Esci" in the gear menu quits the app, equivalently to the existing "Esci" button in the popover.
- [ ] R-11 — Unit tests (Swift Testing) cover the provider-visibility persistence logic and the popover's provider-filtering logic.
- [ ] R-12 — `tuist generate` and the existing xcodebuild test command succeed after the change (no regression to the current build/test pipeline).
