# AGENTS.md

Codex-specific entrypoint for this repository.

Before making changes, read `docs/AGENT_GUIDE.md` in full. It defines the
repository workflow, toolchain, release process, safety boundaries, and known
platform constraints.

High-cost repository constraints:

- Flutter is installed through Puro and is not on PATH on the maintainer's
  Windows machines. Use `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat`
  for local analyze/test commands.
- A release is complete only after the merged commit is tagged `v<version>`, the
  tag is pushed, and the R2 updater metadata is verified.
- Behavior-changing PRs keep `pubspec.yaml`, `lib/core/app_version.dart`, and
  `CHANGELOG.md` versions aligned.
- Manual validation uses a Release build. Stop running `meowwatch.exe` instances
  before `flutter build windows` so file locks cannot preserve a stale binary.

## Anti-slop quality bar

Treat every artifact as maintainer-owned, not as a trace of an AI session. Apply
this quality bar to code, comments, documentation, PR and issue text, UI copy,
architecture, configuration, and handoff notes.

- Do not narrate the prompt, agent, implementation journey, discarded approaches,
  or direction changes unless future maintainers need that rationale.
- Do not add boilerplate prose, obvious comments, duplicate summaries or rules,
  ceremonial files or checklists, or placeholder documentation merely to make a
  change look complete.
- Do not introduce wrappers, abstractions, fallbacks, compatibility paths, feature
  flags, or configuration "just in case". Each extra mechanism must satisfy a
  current requirement or documented risk.
- Prefer direct code and concise human-quality prose. Comments should explain
  non-obvious reasons, invariants, or trade-offs rather than restating the code.
- Current docs, UI copy, PRs, and issues should state current behavior directly.
  Put history in issues, ADRs, changelogs, or dated plans unless it is required to
  apply a live safety, compatibility, or unsupported-behavior boundary.
- Before handoff, inspect the diff specifically for AI slop and remove words,
  files, layers, and indirection that add neither required behavior nor durable
  information.

## Codex-specific overrides

Keep only Codex-specific overrides in this file. General repository rules belong
in shared documentation, primarily `docs/AGENT_GUIDE.md`.
