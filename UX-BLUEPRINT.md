# UX Blueprint — Menu bar settings gear, About panel, and provider visibility toggles

## Window inventory

| Window | Type | SwiftUI Scene / Style | Notes |
|--------|------|-----------------------|-------|
| Usage popover | MenuBarExtra | `.menuBarExtraStyle(.window)` | Existing, unchanged style; gains a gear icon bottom-right and drops the "Avvia al login" toggle. |
| Settings | AppKit `NSWindow` (`NSHostingController`), presented by `AppWindowPresenter` | `TabView` (2 tabs: Generali, Provider), `Form` as root container per tab | **Deviates from the SwiftUI `Settings` scene** (see note below). No Cmd+, — the app is `LSUIElement` and gains a menu bar only while a window is key. No `ScrollView` in either tab — both fit without scrolling. |
| About | AppKit `NSWindow` (`NSHostingController`), presented by `AppWindowPresenter` | Plain content view, fixed non-resizable size | Not a sheet, not `.alert`, not `orderFrontStandardAboutPanel`. Same presenter as Settings, reused for a second independent window. |

**Deliberate deviation from SwiftUI `Settings`/`Window` scenes (decided during plan-mode risk
investigation, confirmed by the user):** in an `LSUIElement` app whose only `Scene` is a
lazily-instantiated `MenuBarExtra`, the SwiftUI `Settings` scene and `@Environment(\.openSettings)`
are unreliable — documented failure modes include the window opening behind other apps, or
`openSettings()` silently no-oping, especially on macOS 26. The known SwiftUI-only workaround
(a hidden 1x1 scene, a `NotificationCenter` handshake, timed sleeps) is a timing hack with no
determinism guarantee. Both Settings and About are instead presented via a plain AppKit
`NSWindow` + `NSHostingController`, created and owned by `AppWindowPresenter`, with manual
`NSApp.setActivationPolicy(.regular)` / `.accessory` toggling around window lifetime. This means
no Cmd+, — not a gap, a consequence of not declaring a `Settings` scene at all.

## Navigation structure

Not applicable in the traditional sense (no primary main window / sidebar). The app's single
entry point is the `MenuBarExtra` popover, already existing. This feature adds a gear icon as a
secondary entry point into two peer windows (Settings, About), reached via a dropdown menu, not
via NavigationSplitView or NavigationStack.

## Settings layout

- **Generali** — "Avvia al login" toggle (`LoginItemManager`, moved from the popover, unchanged
  binding/behavior).
- **Provider** — three independent toggles: "Claude Code", "Codex", "Antigravity (Gemini)",
  bound to `ProviderVisibilityStore`.

Both tabs use `Form` as their root container (M11) — no `ScrollView`, no unconstrained `List`.
Two toggles in Generali and three in Provider both comfortably fit a single screen at any
supported display size, so no further tab splitting is needed.

## Menu bar map (gear dropdown)

This is not the system application menu bar (the app is `LSUIElement`, no Dock icon, no
File/Edit/View menu bar in the traditional sense) — it is the gear icon's own dropdown menu,
rendered as a SwiftUI `Menu` inside the popover.

| Menu | Item | Shortcut | Action |
|------|------|----------|--------|
| Gear dropdown | Impostazioni | — (no Cmd+, — no `Settings` scene declared, see Window inventory note) | Opens the Settings window via `AppWindowPresenter` |
| Gear dropdown | About | — | Opens the About window |
| Gear dropdown | Esci | — | Terminates the app (`NSApplication.shared.terminate(nil)`), same action as the existing popover "Esci" button |

## Toolbar items

None. Neither the Settings window nor the About window needs a toolbar — both are small, static,
form-driven windows. The popover itself has no toolbar (it is a `MenuBarExtra` window, not a
standard `WindowGroup`).

## Keyboard shortcuts

| Action | Shortcut | Source |
|--------|----------|--------|
| Open Settings | — (no Cmd+,) | Gear dropdown → Impostazioni only; no `Settings` scene is declared, see Window inventory note |
| Close Settings / About window | Cmd+W | Standard `NSWindow` behavior once `.regular` activation policy grants the app menu |
| Quit | Cmd+Q | Standard, present via the system app menu while a window is key; "Esci" in the popover and gear dropdown are convenience duplicates for a menu-bar-only app, not replacements |

No custom shortcuts beyond `Cmd+W`/`Cmd+Q`, both a byproduct of the temporary `.regular`
activation policy while a Settings/About window is open, not scene-declared shortcuts. The gear
icon itself is a pointer/VoiceOver-only affordance (see Accessibility below), not shortcut-bound.

## Accessibility checklist

- [ ] Gear icon carries `.accessibilityLabel("Impostazioni e altre azioni")` (icon-only control, no visible text — required, not optional, per M10).
- [ ] The three provider toggles and the "Avvia al login" toggle keep their existing `Toggle("<label>", ...)` text labels, which already satisfy VoiceOver labeling without extra work.
- [ ] The About window's GitHub and istefox.dev links use `Link` (not a bare `Text` + `onTapGesture`), which is VoiceOver-actionable and keyboard-focusable by default.
- [ ] Dynamic Type / full keyboard access: not newly at risk here — all new controls are standard `Toggle`, `Menu`, `Link`, `Form` primitives that already inherit system accessibility behavior; no custom-drawn controls introduced.

## Notes for the architect

- **Superseded during implementation planning:** this blueprint originally recommended the
  SwiftUI `Settings { SettingsView() }` scene (M1/M3). That mechanism was found unreliable in an
  `LSUIElement` app whose only `Scene` is a lazily-instantiated `MenuBarExtra` (window opens
  behind other apps, `openSettings()` silently no-ops, worse on macOS 26). The user approved an
  AppKit `NSWindow` + `NSHostingController` presenter (`AppWindowPresenter`) instead — see the
  Window inventory note above. This is a deliberate, documented departure from M1/M3's literal
  scene requirement, not an oversight; the presenter still satisfies M1's intent (Settings is a
  dedicated window, never a `.sheet`).
- Both Settings tabs must use `Form` as their root, no `ScrollView`, per M11 — keep each tab short enough to avoid ever needing one; if the Provider tab ever grows past 3 toggles, split it rather than adding scrolling.
- The About window uses the same `AppWindowPresenter` as Settings, not `NSApp.orderFrontStandardAboutPanel`, so the istefox.dev link and GitHub link can be included as first-class SwiftUI `Link` views (`orderFrontStandardAboutPanel`'s `credits` key supports rich text but is more awkward for tappable links).
- The gear icon requires an explicit `.accessibilityLabel` since it is icon-only (SF Symbol `gearshape`) with no adjacent text.
- No violation of M2 (TabView is fine here — it is used only inside the Settings window, a legitimate secondary-window use, not as primary app navigation).
