#!/usr/bin/env bash
# Build the release APK and publish a GitHub release for the version currently
# in pubspec.yaml. Mechanical tail of the release workflow — the agent is
# expected to have already committed, merged to main, and pushed.
#
# Usage:  cut-release.sh "<short release title>" <notes-file>
#   e.g.  cut-release.sh "Seek from the waveform while paused" /tmp/relnotes.txt
#
# The release is tagged vX.Y.Z and the title becomes "vX.Y.Z — <short title>".
# Refuses to run if that tag/release already exists (version wasn't bumped).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# JDK 17 + Android SDK + Gradle on PATH; project-local GRADLE_USER_HOME.
source ./setup-env.sh

TITLE="${1:?release title required (e.g. \"Seek from the waveform while paused\")}"
NOTES_FILE="${2:?notes file required (path to a file containing the release body)}"
[ -f "$NOTES_FILE" ] || { echo "ERROR: notes file not found: $NOTES_FILE" >&2; exit 1; }

# Single source of truth for the version is pubspec.yaml; strip any +build suffix.
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)"
[ -n "$VERSION" ] || { echo "ERROR: could not read version from pubspec.yaml" >&2; exit 1; }
TAG="v${VERSION}"

# Guard: the version must have been bumped this session — never clobber an
# existing release (CLAUDE.md: bump 'version:' once per branch/session).
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "ERROR: release $TAG already exists. Bump 'version:' in pubspec.yaml first." >&2
  exit 1
fi

# Releases are cut from main; warn loudly if the local checkout isn't there.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
  echo "WARNING: on branch '$BRANCH', not 'main'. Releases target main — merge first." >&2
fi

echo ">> Building release APK for $TAG ..."
flutter build apk --release

APK="build/app/outputs/flutter-apk/podcastr-${VERSION}.apk"
[ -f "$APK" ] || { echo "ERROR: expected artifact not found: $APK" >&2; exit 1; }
echo ">> Built $APK ($(du -h "$APK" | cut -f1))"

echo ">> Creating GitHub release $TAG ..."
gh release create "$TAG" \
  --title "$TAG — $TITLE" \
  --notes-file "$NOTES_FILE" \
  --target main \
  "$APK"
