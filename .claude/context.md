## Status (2026-09-06)
**Branch:** feat/codex-provider
**Last commit:** e564b9f — fix(ci): use macos-15 runner for Tuist compatibility (Codex provider work below not yet committed)
**In progress:** Codex provider added on top of the Claude Code provider. App renamed ClaudeLimits → AgentLimits (bundle id it.stefer.AgentLimits). Codex data source is `codex app-server`'s JSON-RPC-over-stdio protocol (`account/rateLimits/read`, spawned fresh per refresh, no daemon dependency) — verified live end-to-end against the real account. Windows from the default `rateLimits` bucket and any `rateLimitsByLimitId` buckets are merged by duration (5h/weekly), keeping the highest percent per duration; per-bucket `limitId`/`limitName` are never shown (verified they're opaque backend metering categories unrelated to the configured model). Gemini provider not started.
**Next:** Run the `commit` skill for this branch (rename + Codex provider), then push/PR/CI/merge following the same flow as PR #1. After that, verify/plan the Gemini provider (Nimbalyst's "Gemini" support is for Google Antigravity IDE, not the Gemini CLI — needs its own investigation like Codex got).
**Open decisions:** none
