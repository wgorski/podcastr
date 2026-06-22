import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/models/track.dart';
import 'package:podcastr/state/library_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'podcastr.tracks.v1';

Track _track(String id) => Track(
      id: id,
      title: 'Title $id',
      channel: 'Channel',
      duration: 120,
      size: '5.0 MB',
      addedAt: 'Today',
      color1: const Color(0xFF112233),
      color2: const Color(0xFFAABBCC),
      filePath: '/tmp/$id.m4a',
      thumbnailPath: '/tmp/$id.jpg',
      sourceUrl: 'https://youtu.be/$id',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LibraryStore.load', () {
    test('returns empty list when no preferences are set', () async {
      final store = LibraryStore();
      expect(await store.load(), isEmpty);
    });

    test('returns empty list when stored JSON is malformed', () async {
      SharedPreferences.setMockInitialValues({_key: 'not valid json'});
      final store = LibraryStore();
      expect(await store.load(), isEmpty);
    });

    test('returns empty list when stored JSON has wrong shape', () async {
      SharedPreferences.setMockInitialValues({_key: '{"foo": "bar"}'});
      final store = LibraryStore();
      expect(await store.load(), isEmpty);
    });

    test('parses a previously-saved payload', () async {
      final payload = jsonEncode([_track('a').toJson(), _track('b').toJson()]);
      SharedPreferences.setMockInitialValues({_key: payload});

      final store = LibraryStore();
      final loaded = await store.load();

      expect(loaded.length, 2);
      expect(loaded[0].id, 'a');
      expect(loaded[1].id, 'b');
      expect(loaded[0].title, 'Title a');
      expect(loaded[0].filePath, '/tmp/a.m4a');
    });
  });

  group('LibraryStore.save', () {
    test('round-trips through load', () async {
      final store = LibraryStore();
      await store.save([_track('one'), _track('two'), _track('three')]);

      final loaded = await store.load();
      expect(loaded.map((t) => t.id), ['one', 'two', 'three']);
      expect(loaded[1].title, 'Title two');
    });

    test('empty save clears the library', () async {
      final store = LibraryStore();
      await store.save([_track('x')]);
      expect((await store.load()).length, 1);

      await store.save([]);
      expect(await store.load(), isEmpty);
    });

    test('writes a JSON array to the documented key', () async {
      final store = LibraryStore();
      await store.save([_track('only')]);

      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as List;
      expect(decoded, hasLength(1));
      expect((decoded[0] as Map)['id'], 'only');
    });
  });

  group('LibraryStore.deleteFileFor', () {
    test('is a no-op when filePath is null', () async {
      const t = Track(
        id: 'no-file',
        title: '',
        channel: '',
        duration: 0,
        size: '',
        addedAt: '',
        color1: Color(0xFF000000),
        color2: Color(0xFF000000),
        sourceUrl: 'https://youtu.be/no-file',
      );
      // Should complete without throwing.
      await LibraryStore().deleteFileFor(t);
    });

    test('does not throw when the referenced file does not exist', () async {
      final t = _track('missing').copyWith(
        filePath: '/tmp/podcastr-test-definitely-not-a-real-file.m4a',
      );
      await LibraryStore().deleteFileFor(t);
    });

    test('sweeps stray <id>.* audio/subtitle even when paths are nulled',
        () async {
      // Mirrors permanently deleting an archived track: filePath/subtitlePath
      // were cleared on archive, but the bytes (or a partial re-download) may
      // still be on disk.
      final dir = await Directory.systemTemp.createTemp('podcastr-purge-test');
      const id = 'vid42';
      final audio = File('${dir.path}/$id.mp4')..writeAsStringSync('audio');
      final subs = File('${dir.path}/$id.vtt')..writeAsStringSync('WEBVTT');
      final thumb = File('${dir.path}/$id.jpg')..writeAsStringSync('jpeg');
      // A neighbouring track whose id merely starts the same must survive.
      final other = File('${dir.path}/${id}9.mp4')..writeAsStringSync('keep');

      final archived = _track(id).copyWith(
        thumbnailPath: thumb.path,
        clearFilePath: true,
        clearSubtitle: true,
        archived: true,
      );
      expect(archived.filePath, isNull);
      expect(archived.subtitlePath, isNull);

      await LibraryStore().deleteFileFor(archived);

      expect(audio.existsSync(), isFalse);
      expect(subs.existsSync(), isFalse);
      expect(thumb.existsSync(), isFalse);
      expect(other.existsSync(), isTrue,
          reason: 'prefix match must respect the trailing dot');

      await dir.delete(recursive: true);
    });
  });

  group('LibraryStore.deleteAudioFor', () {
    test('deletes the audio + subtitle files but keeps the thumbnail',
        () async {
      final dir = await Directory.systemTemp.createTemp('podcastr-archive-test');
      final audio = File('${dir.path}/clip.m4a')..writeAsStringSync('audio');
      final subs = File('${dir.path}/clip.vtt')..writeAsStringSync('WEBVTT');
      final thumb = File('${dir.path}/clip.jpg')..writeAsStringSync('jpeg');

      final t = _track('clip').copyWith(
        filePath: audio.path,
        subtitlePath: subs.path,
        thumbnailPath: thumb.path,
      );

      await LibraryStore().deleteAudioFor(t);

      expect(audio.existsSync(), isFalse);
      expect(subs.existsSync(), isFalse);
      expect(thumb.existsSync(), isTrue, reason: 'cover must survive archiving');

      await dir.delete(recursive: true);
    });

    test('is a no-op when paths are null', () async {
      const t = Track(
        id: 'no-file',
        title: '',
        channel: '',
        duration: 0,
        size: '',
        addedAt: '',
        color1: Color(0xFF000000),
        color2: Color(0xFF000000),
        sourceUrl: 'https://youtu.be/no-file',
      );
      await LibraryStore().deleteAudioFor(t);
    });
  });
}
