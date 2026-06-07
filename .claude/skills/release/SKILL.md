---
name: release
description: Use when the user wants to ship, cut, or publish a Podcastr release — "create a release", "cut a release", "release this", "publish the APK", "make a GitHub release". Commits and pushes pending work, merges to main if on a branch, builds the release APK, and creates the GitHub release with the APK attached.
---

# Cut a Podcastr release

## Overview

Turns the committed (or pending) work on the current branch into a published
GitHub release: a `vX.Y.Z` tag on `main` with release notes and the
`podcastr-X.Y.Z.apk` artifact attached. Version is whatever `pubspec.yaml`
already says — this skill does **not** bump it (CLAUDE.md: bump `version:`
once per branch/session, which happens during the work itself).

## Workflow

Do these in order. Steps 1–4 are normal git (you write the messages); step 6
runs the helper script for the mechanical build-and-publish tail.

1. **Check the version.** Read `version:` from `pubspec.yaml` → `X.Y.Z`. If it
   still matches the latest existing release (`gh release list`), the version
   wasn't bumped — stop and bump it (minor for features, patch for fixes)
   before continuing. The script also refuses to clobber an existing tag.

2. **Commit pending work.** If `git status` is dirty, commit it with a clear
   message (end with the `Co-Authored-By` trailer per the global git rule).
   Nothing to commit is fine — a release can be cut from already-committed work.

3. **Merge to main if needed.** Releases target `main`. If on a feature branch:
   ```bash
   git checkout main && git merge --no-ff <branch> && git checkout <branch>   # or stay on main
   ```
   This repo usually commits straight to `main`, in which case skip this.

4. **Push.** `git push origin main` (and the branch, if you used one).

5. **Write release notes to a file.** Use a temp file (e.g. `/tmp/relnotes.txt`)
   and pass it via `--notes-file` — **never** inline the body in a `-m`/heredoc,
   because apostrophes in the notes break shell quoting. Match the house style
   of prior releases (`gh release view <last-tag>`):
   - Opens with `Bugfix release.` or `Feature release.`
   - `**Fixed:**` / `**Added:**` paragraphs explaining the user-visible change
   - Footer: ``**APK:** `podcastr-X.Y.Z.apk` (~53 MB) is a release-optimized
     build (R8/tree-shaken), signed with the debug key for sideloading. Install
     with `adb install -r podcastr-X.Y.Z.apk`...``

6. **Build + publish.** Run the helper from the repo root:
   ```bash
   .claude/skills/release/cut-release.sh "<short release title>" /tmp/relnotes.txt
   ```
   It sources `setup-env.sh`, derives the version/tag from `pubspec.yaml`,
   refuses to overwrite an existing release, runs `flutter build apk --release`,
   verifies `podcastr-X.Y.Z.apk` exists, and creates the release on `main` with
   the APK attached. The release title becomes `vX.Y.Z — <short title>`.

7. **Report the release URL** that `gh` prints back to the user.

## Quick reference

| Thing | Value |
|-------|-------|
| Version source of truth | `version:` in `pubspec.yaml` (strip any `+build`) |
| Tag format | `vX.Y.Z` |
| Release title | `vX.Y.Z — <short title>` |
| APK artifact | `build/app/outputs/flutter-apk/podcastr-X.Y.Z.apk` (auto-named) |
| Release target | `main` |
| Notes | temp file + `--notes-file` (apostrophes break inline `-m`) |

## Common mistakes

- **Inlining notes with `-m "..."`** — an apostrophe (e.g. "doesn't") breaks the
  shell quoting. Always write to a file and use `--notes-file`.
- **Forgetting to bump the version** — the script aborts if the tag exists, but
  check first so you don't get halfway through.
- **Cutting from a branch** — the release `--target main`, so unmerged branch
  work won't be in the release. Merge and push to `main` first.
- **Skipping `source ./setup-env.sh`** — the script does it, but if you build
  manually first, the JDK/SDK/Gradle env must be loaded.
