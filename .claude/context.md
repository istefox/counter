## Status (2026-09-07)
**Branch:** emdash/slimy-jokes-juggle-rl3y8
**Last commit:** 086f7e4 — fix(app): stabilize debug code signing and guard login-item registration
**In progress:** Fixed the recurring keychain "Always Allow" prompt: Debug builds now sign with the Apple Development cert instead of ad-hoc (stable designated requirement across rebuilds), and LoginItemManager blocks/flags login-item registration from any bundle outside /Applications.
**Next:** Not pushed/PR'd yet. On this machine, still needs the one-time manual repair: turn off "Avvia al login" in the running Debug build, quit it, launch /Applications/AgentLimits.app, turn login-item back on there, accept the keychain prompt once.
**Open decisions:** none.
