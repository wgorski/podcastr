import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/models/track.dart';
import 'package:podcastr/screens/library_screen.dart';

/// Deterministic, emulator-free checks for the library long-press action sheet.
/// The action it offers depends on the track's [TrackStatus]: a ready track can
/// be archived; a downloading/queued one can only be cancelled (there's no
/// audio to archive yet). These run in milliseconds and don't race the live
/// download state the way driving the emulator does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The action sheet asks the native bridge whether Gemini is installed before
  // it builds. Stub the channel so the sheet opens without a real platform.
  const channel = MethodChannel('com.wgorski.podcastr/youtube');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isGeminiInstalled') return false;
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Track track(TrackStatus status) => Track(
        id: 'vid1',
        title: 'A Podcast',
        channel: 'Some Channel',
        duration: 600,
        size: '5.0 MB',
        addedAt: 'Today',
        color1: const Color(0xFF112233),
        color2: const Color(0xFFAABBCC),
        sourceUrl: 'https://youtu.be/vid1',
        status: status,
      );

  // A downloading card animates an indeterminate progress indicator forever, so
  // pumpAndSettle() would hang. Pump fixed durations to open the sheet instead.
  Future<void> openActionSheet(WidgetTester tester) async {
    await tester.longPress(find.text('A Podcast'));
    // Resolve the isGeminiInstalled future, then let the sheet animate in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpLibrary(WidgetTester tester, Track t) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        tracks: [t],
        archivedCount: 0,
        currentId: null,
        playing: false,
        onOpenTrack: (_) {},
        onPlay: (_) {},
        onArchive: (_) {},
        onCancelDownload: (_) {},
        onArchiveFinished: () async {},
        onSearch: () {},
        onOpenArchive: () {},
      ),
    ));
    await tester.pump();
  }

  testWidgets('ready track offers Archive, not Cancel download', (tester) async {
    await pumpLibrary(tester, track(TrackStatus.ready));
    await openActionSheet(tester);

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Cancel download'), findsNothing);
  });

  testWidgets('downloading track offers Cancel download, not Archive',
      (tester) async {
    await pumpLibrary(tester, track(TrackStatus.downloading));
    await openActionSheet(tester);

    expect(find.text('Cancel download'), findsOneWidget);
    expect(find.text('Archive'), findsNothing);
  });

  testWidgets('queued track offers Cancel download, not Archive',
      (tester) async {
    await pumpLibrary(tester, track(TrackStatus.queued));
    await openActionSheet(tester);

    expect(find.text('Cancel download'), findsOneWidget);
    expect(find.text('Archive'), findsNothing);
  });

  testWidgets('cancel download routes to onCancelDownload, not onArchive',
      (tester) async {
    Track? archived;
    Track? cancelled;
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        tracks: [track(TrackStatus.downloading)],
        archivedCount: 0,
        currentId: null,
        playing: false,
        onOpenTrack: (_) {},
        onPlay: (_) {},
        onArchive: (t) => archived = t,
        onCancelDownload: (t) => cancelled = t,
        onArchiveFinished: () async {},
        onSearch: () {},
        onOpenArchive: () {},
      ),
    ));
    await tester.pump();

    await openActionSheet(tester);
    await tester.tap(find.text('Cancel download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(cancelled?.id, 'vid1');
    expect(archived, isNull);
  });
}
