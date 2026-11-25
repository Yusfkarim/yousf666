# Project-local agent guidance

This directory contains versioned, project-scoped coding guidance. OpenCode discovers the skill catalog through the project `skills.paths` configuration in `opencode.json`, and discovers project agents below `.opencode/agents`; the root `AGENTS.md` supplies project-specific rules. The project config explicitly loads the applicable ECC/Karpathy instructions and common/Dart/TypeScript/web rules.

## Upstream sources

- [Everything Claude Code (ECC)](https://github.com/affaan-m/ecc), inspected at commit `4adeee6732a12d1540f49a4d50a38ce8c97f9a53`. Its skills, relevant agents, rules, and OpenCode instructions are retained under this directory and `.opencode/`. ECC is MIT-licensed; the upstream license text is in `licenses/ECC-LICENSE`. Trailing whitespace was removed from one vendored Python helper (`skills/videodb/scripts/ws_listener.py`) so the repository whitespace check passes; its logic was not changed.
- [Andrej Karpathy skills](https://github.com/yusfkarim1012-dotcom/andrej-karpathy-skills), inspected at commit `2c606141936f1eeef17fa3043a72095b4765b9c2`. The `karpathy-guidelines` skill is retained under `skills/`; the upstream README and skill declare MIT. The upstream repository did not contain a separate license file at the inspected commit.

To update a source, inspect the new upstream revision, refresh the vendored files, retain attribution/license information, and re-check the OpenCode project configuration. Project-local copies are committed with this repository so they remain available when it is cloned into a fresh workspace.
