import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/state/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'podcastr.positions.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('get returns null for an unknown id', () async {
    final store = PositionStore();
    expect(await store.get('nothing-here'), isNull);
  });

  test('set then get returns the saved seconds', () async {
    final store = PositionStore();
    await store.set('vid1', 42);
    expect(await store.get('vid1'), 42);
  });

  test('set overwrites a prior value for the same id', () async {
    final store = PositionStore();
    await store.set('vid1', 10);
    await store.set('vid1', 99);
    expect(await store.get('vid1'), 99);
  });

  test('different ids are stored independently', () async {
    final store = PositionStore();
    await store.set('a', 1);
    await store.set('b', 2);
    expect(await store.get('a'), 1);
    expect(await store.get('b'), 2);
  });

  test('remove drops a specific entry without touching others', () async {
    final store = PositionStore();
    await store.set('a', 1);
    await store.set('b', 2);

    await store.remove('a');
    expect(await store.get('a'), isNull);
    expect(await store.get('b'), 2);
  });

  test('remove is a no-op when the id is unknown', () async {
    final store = PositionStore();
    await store.set('a', 1);
    await store.remove('does-not-exist');
    expect(await store.get('a'), 1);
  });

  test('malformed stored JSON is treated as empty', () async {
    SharedPreferences.setMockInitialValues({_key: 'not json'});
    final store = PositionStore();
    expect(await store.get('a'), isNull);

    // Subsequent writes should still work (recover gracefully).
    await store.set('a', 7);
    expect(await store.get('a'), 7);
  });
}
