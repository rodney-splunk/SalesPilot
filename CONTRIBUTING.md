# Contributing

Use a feature branch and pull request. Start with README setup and `bash scripts/test-safe.sh`. Include the user-visible behavior, tests and known limits. Use fictional transcripts only; never commit actual customer recordings, names/context, local provider configuration or credentials. Do not change network/security boundaries or auto-send behavior without deliberate review. Keep current-call naming ephemeral; there is no persistent people library. Preserve upstream notices.

Never run disruptive UI/audio suites during a call. Build candidates to another app path and use isolated workspaces. Coordinate native changes because running bundles use source paths from their build. Hosted tests require each contributor’s own authorized registration.

## Coordinating work

Use the canonical [roadmap](docs/ROADMAP.md). Claim an issue with its stable ID, assign yourself, record dependencies and acceptance criteria, then link the PR. Roles in the roadmap are not assigned owners. Use repository issue/PR templates; preserve failed results and retest evidence. Do not mark implemented behavior certified beyond the actual checks. Coordinate shared engine/UI modules before parallel edits. Keep presentation scripts outside this repository. Use the P1–P4 core optimization plan and architecture review; do not add features or activate dormant integrations during this scope.
