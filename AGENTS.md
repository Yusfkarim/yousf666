# Repository guidance for coding agents

These instructions apply to all work in this repository. Keep changes small, traceable to the request, and aligned with the existing app architecture.

## Before implementation

- Inspect the relevant code and state the important assumptions. If the request has materially different interpretations, ask before choosing one.
- Define a concrete success check for multi-step work. Prefer the simplest change that meets it; avoid speculative features and unrelated cleanup.
- For bug fixes and new behavior, add or update focused tests first when the project has a runnable test harness.

## Security and data integrity

- Never hardcode, commit, log, or echo credentials. Use environment variables or the platform secret store; treat a credential exposed in chat or logs as compromised and rotate it.
- Validate untrusted input at boundaries. Enforce authorization in trusted server-side code, not only in Flutter or the admin UI.
- For Supabase changes, preserve RLS and least-privilege grants. Keep financial calculations and protected snapshots server-authoritative, and review any `SECURITY DEFINER` function and its `search_path`.
- Do not expose service-role keys in client code or build artifacts. Client-visible Supabase anon keys are configuration, not a substitute for access policies.

## Implementation and verification

- Make surgical edits; preserve local conventions and avoid unrelated refactors.
- Run the narrowest relevant checks, then broader checks where available. Report the exact checks run and distinguish verified results from assumptions or unavailable tooling.
- Review the final diff for scope, secrets, generated files, and whitespace before calling work complete. Do not claim a build, test, deployment, or release succeeded unless it was actually observed.
- For Flutter work, prefer the existing Riverpod/repository structure and theme/localization patterns. For SQL, check authorization and data-integrity behavior as well as syntax. For `admin_web`, retain RTL and responsive behavior.

## Installed guidance

OpenCode loads this file automatically. `opencode.json` also registers the vendored ECC skills and the Karpathy guidelines; `.opencode/agents/` contains focused project agents. Use the relevant skill when the task calls for it, especially security review, test-first implementation, Flutter/Dart review, and verification. The complete ECC rule catalog is retained under `.agents/rules/ecc/` for reference; the project config loads the applicable common, Dart, TypeScript, and web rules.
