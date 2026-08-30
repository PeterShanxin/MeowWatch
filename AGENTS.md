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

## Normative documentation

Write standing guidance as current-state rules, not as a narrative of how the
repository reached them. Omit transition commentary about retired mechanisms or
prior directions when the current rule is sufficient. Keep historical rationale
in issues, ADRs, changelogs, or dated plans unless it is needed to apply a current
safety, compatibility, or unsupported-behavior boundary. Preserve negative wording
when it defines a real invariant; remove stale or redundant guidance instead of
accumulating exceptions.

## Codex-specific overrides

Keep only Codex-specific overrides in this file. General repository rules belong
in shared documentation, primarily `docs/AGENT_GUIDE.md`.
