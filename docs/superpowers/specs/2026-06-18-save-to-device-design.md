# Save to device — design

## Goal

Add a context-menu action that copies a downloaded track's audio file out of
app-private storage into the phone's public **Downloads/** folder, where the
user and other apps can reach it. The file is copied verbatim — original
container/extension (`.m4a` / `.webm` / `.mp4`), no transcoding to real MP3.

## Placement

In the long-press actions sheet on a library card (`library_screen.dart`),
a new row sits **directly above "Archive"**:

```
Share
[Summarize via Gemini]   (only if Gemini installed)
Save to device           ← new
Archive
```

The "Save to device" row is shown **only when the track has a real downloaded
file** — i.e. `filePath != null` and the track is ready. Tracks that are still
downloading or failed don't get it (nothing to export).

Scope: library context menu only. The archive screen's menu is unchanged.

## Data flow

1. User taps "Save to device" → the sheet pops with `_TrackAction.saveToDevice`.
2. `_LibraryScreenState._showActions` handles it **inline** (the same way Share
   and Gemini are handled today, calling a service directly — `main.dart` is
   not touched).
3. It calls a new Dart service method:
   `YoutubeDownloader.saveToDownloads(filePath, displayName, mimeType)`.
4. That invokes a new MethodChannel method `exportToDownloads` on the existing
   `com.wgorski.podcastr/youtube` channel, passing `filePath`, `displayName`,
   and `mimeType`.
5. **Kotlin (`MainActivity.kt`)**, on API 29+:
   - Insert a row into `MediaStore.Downloads.EXTERNAL_CONTENT_URI` with
     `DISPLAY_NAME = displayName`, `MIME_TYPE = mimeType`,
     `RELATIVE_PATH = Environment.DIRECTORY_DOWNLOADS`, and `IS_PENDING = 1`.
   - Stream the source file's bytes into the `OutputStream` for the returned
     `Uri`.
   - Clear `IS_PENDING` and update.
   - `result.success(displayName)`.
   - No runtime permission required on API 29+.
6. Back in Dart: on success show a `SnackBar` ("Saved <name> to Downloads");
   on `PlatformException` show an error `SnackBar`.

## Filename

Sanitized track title + the source file's existing extension
(e.g. `My Podcast Episode.m4a`). Sanitization strips characters illegal in a
MediaStore display name (`/ \ : * ? " < > |` and control chars), collapses
whitespace, and falls back to the videoId if the title is empty after
sanitizing. MediaStore auto-deduplicates collisions (`name (1).m4a`), so no
manual collision handling.

The mimeType is derived from the extension on the Dart side (`.m4a` →
`audio/mp4`, `.webm` → `audio/webm`, `.mp4` → `video/mp4`), defaulting to
`application/octet-stream`.

## Decisions

- **API 29+ only.** MediaStore Downloads does not exist below Android 10.
  The project targets API 36 and the emulator is API 36. On API < 29 the
  native handler returns a `result.error("UNSUPPORTED", …)` and Dart shows a
  "not supported on this Android version" SnackBar — we do **not** build the
  legacy `WRITE_EXTERNAL_STORAGE` permission flow (YAGNI).
- **No transcoding.** Files are copied byte-for-byte in their original
  container. "mp3" in the user's request is colloquial; the real audio is
  `.m4a` / `.webm`.

## Verification

Per CLAUDE.md required workflow:
1. `flutter analyze` clean.
2. `flutter build apk --debug` succeeds.
3. `adb install -r`, force-stop + start, confirm focus.
4. Long-press a downloaded track → "Save to device" appears above "Archive".
5. Tap it → SnackBar confirms; verify the file lands in `/sdcard/Download/`
   via `adb shell ls /sdcard/Download/`.
6. Confirm the row is absent for a not-yet-downloaded track.

## Versioning

Minor bump in `pubspec.yaml` (new feature).
