# CLAUDE.md — context for AI coding assistants

This file orients Claude (and any other AI coding assistant) when working in
this repo. Humans should read `README.md` first.

## What this is

**Podcastr** is an Android app that turns YouTube videos into a local audio
library. It was bootstrapped from a Claude Design HTML/CSS prototype
(`youtube-audio-extracted/youtube-audio/project/index.html`) and ported to
Flutter in a single iterative session.

- **UI**: Flutter (Dart), single `lib/main.dart` orchestrating the screen graph
- **YouTube extraction**: NewPipe Extractor v0.26.1 (Java/Kotlin) via a
  `MethodChannel("com.wgorski.podcastr/youtube")`
- **Download**: WorkManager `CoroutineWorker` (`DownloadWorker.kt`) runs
  as a foreground service, re-resolves the audio URL, streams bytes via
  OkHttp; progress streams back to Dart over an
  `EventChannel("com.wgorski.podcastr/downloads")`. Survives app kill.
- **Playback**: `just_audio` + `just_audio_background` for media-session
  integration
- **Persistence**: `shared_preferences` JSON blob (`podcastr.tracks.v1`)
- **Notifications**: download progress is the worker's own foreground
  notification (channel `podcastr.downloads`); playback is via
  `just_audio_background`.

## Layout

```
lib/
  main.dart                      # app root, screen routing, state
  theme/aurora_theme.dart        # tokens + gradients
  models/track.dart              # Track + JSON + palette helper + waveform seed
  data/seed_tracks.dart          # design-time fixture (unused at runtime)
  state/
    audio_controller.dart        # thin façade over just_audio AudioPlayer
    library_store.dart           # shared_preferences persistence
    download_manager.dart        # Dart façade: enqueue work, forward events
  services/
    youtube_downloader.dart      # MethodChannel + EventChannel bridge
  widgets/
    thumbnail.dart               # Thumbnail + SquareArt (file or procedural)
    library_card.dart            # Aurora overlay card
    mini_player.dart             # docked player
    waveform_scrubber.dart       # tap/drag scrubber
    back15_icon.dart             # composite skip-N icon
    equalizer.dart               # 3-bar animation
    status_bar.dart              # mocked 9:41 strip (only used on lock screen)
  screens/
    library_screen.dart          # wordmark + chips + list + empty state
    now_playing_screen.dart      # full player, controls, sleep-timer sheet
    download_sheet.dart          # resolving → ready → downloading → done
    lock_screen.dart             # background-playback card
    search_screen.dart           # live filter
    share_intent_screen.dart     # design mock; not wired at runtime

android/app/src/main/kotlin/com/wgorski/podcastr/
  MainActivity.kt                # MethodChannel + EventChannel handlers
  YoutubeResolver.kt             # shared NewPipe → audio URL picker (prefers ORIGINAL track)
  DownloadWorker.kt              # WorkManager CoroutineWorker (foreground)
  NewPipeDownloader.kt           # OkHttp-backed Downloader for NewPipe
```

## Conventions & gotchas the assistant should remember

- **Versioning — semver, bump once per branch/session.** The single source
  of truth is the `version:` field in `pubspec.yaml` (Flutter forwards it to
  `versionName`). Treat all the changes in a single branch or Claude Code
  session as **one** change: bump the version once for the whole unit of
  work, not once per file or per commit. Bump either the **minor** component
  (`0.X.0`) for new features / behavior changes, or the **patch** component
  (`0.0.X`) for bug fixes, refactors, or doc-only touch-ups — and if a
  session mixes both, the minor bump wins. Don't skip the bump, but don't
  bump repeatedly within the same session either. Release APKs
  are auto-named `podcastr-${versionName}.apk` via the `outputFileName` hook
  in `android/app/build.gradle.kts`, so the file in
  `build/app/outputs/flutter-apk/` always reflects the current version.
- **Aurora theme only.** The original prototype shipped three themes (Ember,
  Aurora, Editorial). Only Aurora was ported; the others are not needed.
- **No `Color.withOpacity`.** Use `Color.withValues(alpha: …)`. Requires
  Flutter ≥ 3.27 (pinned in `pubspec.yaml`).
- **Status bar.** The OS status bar is hidden via
  `SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [bottom])`.
  Do not re-add the in-app `StatusBar` widget at the top of screens — it's a
  design-time mock and remains only on the lock screen.
- **`Border.fromBorderSide` is a factory, not `const`.** Inside a `const`
  `BoxDecoration` use `Border.all(color: …, width: 1)` instead.
- **Plugin JVM target drift.** Some Flutter plugins still compile against
  Java 11; the project itself targets Java 17. `android/build.gradle.kts`
  forces all subprojects to JVM 17 to avoid the "Inconsistent JVM-target
  compatibility" error.
- **`flutter_local_notifications` needs core-library desugaring.** Enabled
  via `isCoreLibraryDesugaringEnabled = true` + the `coreLibraryDesugaring`
  dependency in `android/app/build.gradle.kts`. Don't disable.
- **NewPipe Extractor is volatile.** YouTube changes its endpoints often.
  When YouTube extraction breaks, the first thing to try is bumping
  `com.github.TeamNewPipe:NewPipeExtractor` to the latest release on
  GitHub (currently `v0.26.1`). The custom `NewPipeDownloader.kt` already
  sets a recent Firefox UA and the YouTube consent cookie — both are
  required to avoid "The page needs to be reloaded" errors.
- **Always prefer the ORIGINAL audio track.** YouTube ships AI-dubbed
  alternate-language tracks for many videos (English original + Hindi /
  Portuguese / Spanish / etc. dubs). Picking by highest bitrate alone
  can land on a dub. The selection in `YoutubeResolver.kt` filters by
  `AudioTrackType.ORIGINAL` first, then untyped (single-language
  videos), then everything else. Don't simplify this away.
- **PoToken not implemented.** For age-restricted / DRM-flagged videos
  YouTube requires a proof-of-origin token generated by running their JS.
  We currently rely on streams that don't require it. If a video fails
  with a playability-related error, that's the likely cause.
- **MethodChannel name** is hardcoded in two places: Kotlin
  (`MainActivity.kt`) and Dart (`youtube_downloader.dart`). Keep them in
  sync if you ever rename it.
- **Sleep timer ticks regardless of pause state.** Once started, it counts
  down every second and calls `_audio.pause()` at zero. This mirrors how
  most podcast apps behave (the user wanted "if it doesn't work, implement
  it"; that's the model that shipped).
- **Persistence is in-process only.** Downloads continue if you navigate
  away from the sheet, but they stop if the app is killed. There's no
  WorkManager / foreground download service.

## Run

```bash
source ./setup-env.sh           # JDK 17 + Android SDK 36 + emulator on PATH
flutter pub get
flutter run                     # picks up emulator-5554 if it's already booted
```

The repo's `setup-env.sh` exports `GRADLE_USER_HOME` to a project-local
`.gradle-home/` so nothing leaks to `~/.gradle`. AVDs created via
`avdmanager create avd` should go to `.android-avd/` (export
`ANDROID_AVD_HOME=$PWD/.android-avd`).

## Things that look weird but aren't

- `lib/screens/share_intent_screen.dart` — design mock; not referenced by
  `main.dart` since real share-intent handling replaced it.
- `lib/data/seed_tracks.dart` — exports `seedTracks` (unused) and
  `downloadPreview` (unused). Kept because the design canvas referred to
  them and removing them risks losing reference data. Safe to delete if
  you're sure.
- `youtube-audio-extracted/` — the original Claude Design handoff bundle.
  Reference only; not part of the build.
- The first commit was the design bundle import; subsequent commits are
  the port. There's a lot of churn — read `README.md` for the result, not
  the history, when orienting.

## When in doubt

- Tests don't exist. The verification model is: `flutter analyze` clean,
  `flutter build apk --debug` succeeds, install via `adb install -r`,
  visual check via `adb exec-out screencap`.
- The user has the emulator named `pixel_test` (Pixel 6, API 36 ARM64
  Google Play image) already created under `.android-avd/`. Reuse it.

## Required workflow — verify every change in the emulator

After **every** change to Dart, Kotlin, manifest, Gradle, or resource files,
you must:

1. `flutter analyze` — fix any warnings before continuing.
2. `flutter build apk --debug` — must succeed.
3. `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
4. `adb shell am force-stop com.wgorski.podcastr && adb shell am start -W -n com.wgorski.podcastr/.MainActivity`.
5. Wait until `adb shell dumpsys window | grep mCurrentFocus` lands on
   `com.wgorski.podcastr/.MainActivity`.
6. `adb exec-out screencap -p > /tmp/<name>.png` and `sips -Z 1200 ... `
   for visual confirmation.
7. For changes that involve the share-intent flow:
   `adb shell 'am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "<url>" -n com.wgorski.podcastr/.MainActivity'`
   and screencap after a few seconds.

Do not declare a change "done" until the emulator screenshot reflects it.
"`flutter analyze` is clean" alone is not sufficient — Dart errors that
escape static checks (e.g. `PlatformException`s from misconfigured native
plugins, like the `AudioServiceActivity` requirement) will hang the app
on the splash screen but compile fine.
