import 'package:shared_preferences/shared_preferences.dart';

/// Persists the id of the track the user last selected (tapped to open,
/// play, or pick from search). Reloaded on cold start so the mini-player
/// resumes on the same track the user left it on — rather than auto-binding
/// to the most recently downloaded one. Cleared when the selected track is
/// deleted or is no longer in the library on reload.
class SelectionStore {
  static const _key = 'podcastr.selection.v1';

  Future<String?> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_key);
  }

  Future<void> save(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, id);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
