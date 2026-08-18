# Contributing to MeowWatch

Thanks for helping out! This page covers the one thing that trips people up:
**how CI runs on pull requests**, and how to get your own free Windows runner
if you maintain a fork.

For the full development workflow (toolchain paths, release flow, versioning,
gotchas) see [`docs/AGENT_GUIDE.md`](docs/AGENT_GUIDE.md) — it's the source of
truth. This file is just the contributor-facing CI summary.

## How CI works

Every PR must pass one check before it can merge: **`Build / Analyze & Test`**
(`flutter analyze` + `flutter test`). The suite is Windows-only (it asserts on
Windows file paths and uses Windows-rendered golden images), so the check always
runs on a Windows runner.

There are two ways that check can run:

| Path | Runner | Cost | When |
| --- | --- | --- | --- |
| **Default** | A **self-hosted Windows** runner (e.g. the maintainer's PC) | Free | Automatically, on every push to the PR |
| **Fallback** | **GitHub-hosted `windows-2022`** | Paid (2× minutes) | Only when you add the **`ci-hosted`** label to the PR |

Why the split: GitHub-hosted Windows minutes are metered and **billed at 2×**.
Re-running a hosted Windows check on every "address review feedback" push burns
the monthly minute budget fast. Running on a self-hosted runner is free and
unlimited, so that's the default; the hosted path is there only as an on-demand
escape hatch.

### If your check is stuck "Queued / Expected"

That means **no self-hosted runner is online**. Two options:

1. **Wait** for the runner to come online (if you or the maintainer owns one —
   bring it up, see below). The check resumes automatically.
2. **Add the `ci-hosted` label** to the PR. This immediately re-runs the check
   on GitHub-hosted Windows and unblocks the merge without needing a runner.
   Remove the label (and push again) to go back to the free self-hosted path.

The merge gate (`Build / Analyze & Test`) stays red/pending until one of the two
paths reports green — so you can never merge on an unverified commit.

## Running your own self-hosted Windows runner (optional)

If you maintain a **fork** and want free Windows CI, register your own Windows
runner. (Only do this for a repo you trust — never attach a self-hosted runner
to a public repo, where untrusted PRs could run code on your machine. MeowWatch
is private, which is why it's safe here.)

**Prerequisites on the Windows machine:**

1. **Flutter via [Puro](https://puro.dev/)** on the `stable` channel. The
   workflow expects it at `%USERPROFILE%\.puro\envs\stable\flutter\bin` (it does
   **not** use `subosito/flutter-action` on self-hosted runners). Install:
   ```powershell
   # Install Puro (see puro.dev for the current one-liner), then:
   puro create stable stable
   puro use stable
   ```
2. **Visual Studio with the "Desktop development with C++" workload** — required
   by `flutter build windows`. The Build Tools edition is enough.

**Register the runner:**

1. In your fork: **Settings → Actions → Runners → New self-hosted runner →
   Windows**. Follow the download/configure commands GitHub shows you.
2. When configuring, give it the labels **`self-hosted`**, **`windows`**, and
   **`meowwatch-ci`** (the `windows` label is added automatically on Windows;
   the workflow targets `runs-on: [self-hosted, windows, meowwatch-ci]`).
3. **Run it as the logged-in user**, not as `NETWORK SERVICE` — the service
   account can't see the Visual Studio C++ toolchain, so builds fail. The
   simplest is to start it interactively:
   ```powershell
   # from the runner install folder
   .\run.cmd
   ```
   (MeowWatch's maintainer does **not** install it as an autostart service —
   they start it on demand before a release and stop it after. You can do
   whatever fits your workflow.)

Once it shows **online** in Settings → Actions → Runners, your PR checks run on
it for free.

**No runner? No problem.** Just use the `ci-hosted` label (above) and your check
runs on GitHub-hosted Windows.
