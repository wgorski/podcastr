# Podcastr

A small Android app that turns YouTube videos into a local audio library.
Share a YouTube link from any app → Podcastr extracts the audio, downloads
it, and adds it to your library with the original artwork. Background
playback, lock-screen controls, sleep timer, search.

> **Heads up.** This is a personal/hobby app. Downloading copyrighted
> material may violate the YouTube Terms of Service in your jurisdiction.
> You are responsible for what you save. The author isn't.

## Features

- **Share-to-save.** Podcastr registers as a system share target for
  `text/plain` and for `https://(www|m).youtube.com/…` / `youtu.be/…`
  URLs. Tap "Share" in YouTube → "Podcastr".
- **YouTube extraction via NewPipe Extractor.** Same Java library the
  NewPipe F-Droid client uses; tracks YouTube's API churn with frequent
  releases.
- **Original thumbnails.** The highest-resolution thumbnail is cached
  alongside the audio and used in the library, player, lock screen, and
  system notification.
- **Spotify-style notification.** Full media-session integration: title,
  artwork, pause/resume on the lock screen and notification shade. Works
  with Bluetooth media buttons.
- **Download progress notification.** Status-bar notification with an
  Android-native progress bar; stays put if you leave the app.
- **Sleep timer.** 5 / 15 / 30 / 45 / 60 minutes, or "End of clip". Ticks
  while paused too; pauses playback when it expires.
- **Long-press to delete.** Bottom-sheet confirmation, removes the audio
  file from disk and the entry from the library.
- **Edge-to-edge dark UI.** The Aurora theme — cool, neon, glassy. Custom
  procedural artwork as a fallback when no thumbnail is available.

## Stack

| Layer | Choice | Why |
|---|---|---|
| UI | Flutter 3.27+ | Cross-platform, single codebase |
| YouTube extractor | [NewPipe Extractor](https://github.com/TeamNewPipe/NewPipeExtractor) (Kotlin) | Most reliable open-source extractor; yt-dlp doesn't run on Android |
| Audio playback | [`just_audio`](https://pub.dev/packages/just_audio) + [`just_audio_background`](https://pub.dev/packages/just_audio_background) | Media-session notification + lock-screen controls out of the box |
| Persistence | [`shared_preferences`](https://pub.dev/packages/shared_preferences) | One JSON blob; no DB needed for this scale |
| Share intent | [`receive_sharing_intent`](https://pub.dev/packages/receive_sharing_intent) | Handles SEND on cold start + while running |
| Notifications | [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) | Native Android progress notifications |

## Quick start

### Prereqs

- JDK 17
- Android SDK 36 (`platforms;android-36`, `build-tools;36.0.0`)
- An Android emulator + a system image (`system-images;android-36;google_apis_playstore;arm64-v8a` for Apple Silicon)
- Flutter 3.27 or newer (the codebase uses `Color.withValues`)

The repo includes a `setup-env.sh` for the macOS / Homebrew layout used
during development. It exports `JAVA_HOME`, `ANDROID_HOME`,
`GRADLE_USER_HOME`, and prepends the Android tooling to `PATH`. Adapt it
to your environment.

### Build

```bash
source ./setup-env.sh
flutter pub get
flutter build apk --debug
# → build/app/outputs/flutter-apk/app-debug.apk
```

A release build needs a real keystore; the default Gradle config signs
release with the debug key, which is fine for sideloading but rejected
by the Play Store.

### Run on an emulator

```bash
export ANDROID_AVD_HOME=$PWD/.android-avd
emulator -avd <your-avd-name> -no-snapshot-save &
adb wait-for-device
flutter run
```

### Run on a device

```bash
adb devices                                      # confirm device shows up
flutter run                                      # builds + installs + attaches
# or
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## How a download flow works end-to-end

1. User taps "Share" on a YouTube video → Android shows Podcastr in the
   share sheet (registered via `<intent-filter>` for `SEND text/plain`
   and `VIEW` of `youtube.com` / `youtu.be`).
2. `receive_sharing_intent` delivers the URL to Dart on launch or
   while running. A regex picks out the YouTube link from the shared
   text.
3. `DownloadSheet` calls Kotlin via `MethodChannel("com.example.podcastr/youtube")`:
   - `MainActivity.kt` runs NewPipe Extractor's `YoutubeStreamExtractor`
     on a background dispatcher.
   - `NewPipeDownloader.kt` is an OkHttp-backed `Downloader` that sets a
     Firefox UA + the YouTube consent cookie (otherwise YouTube returns
     "The page needs to be reloaded").
   - Returns `{ videoId, title, channel, durationSeconds, audioUrl,
     mimeType, extension, thumbnailUrl }` to Dart.
4. Dart streams the `audioUrl` to
   `${appDocumentsDir}/tracks/<videoId>.<ext>` over `package:http`,
   emitting a `DownloadProgress` for each chunk.
5. After the audio is on disk, the thumbnail is downloaded and saved
   next to it.
6. The new `Track` is prepended to `_tracks` and persisted to
   `SharedPreferences` as JSON.
7. Playback uses `just_audio` + `just_audio_background`; the
   foreground-service-backed notification surfaces title, artwork, and
   pause/resume controls in the system shade and on the lock screen.

## Known limitations

- **PoToken / age-gate.** YouTube's anti-bot defenses sometimes require a
  proof-of-origin token generated by running their JS in a WebView.
  Podcastr does not implement this. Most public videos work without it;
  some don't.
- **Download is in-process.** If the app is killed during a download, it
  doesn't resume. A proper implementation would use WorkManager / a
  foreground download service.
- **Debug-signed.** A release-signing config still needs to be added.
- **YouTube changes break the extractor periodically.** When that
  happens, bump `com.github.TeamNewPipe:NewPipeExtractor` in
  `android/app/build.gradle.kts` to the latest tag on GitHub.

## Layout

See [`CLAUDE.md`](CLAUDE.md) for a directory-by-directory map and
conventions to follow when extending the code.

## Acknowledgements

- The visual language is a Flutter port of an HTML/CSS/JS prototype
  generated with [Claude Design](https://claude.ai/design).
- YouTube extraction is built on
  [NewPipe Extractor](https://github.com/TeamNewPipe/NewPipeExtractor).
- Media-session notifications via Ryan Heise's
  [`audio_service`](https://pub.dev/packages/audio_service) /
  [`just_audio_background`](https://pub.dev/packages/just_audio_background).

## License

MIT — see [`LICENSE`](LICENSE) (add one before publishing if you haven't
yet).
