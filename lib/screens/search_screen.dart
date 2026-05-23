import 'package:flutter/material.dart';
import '../models/track.dart';
import '../theme/aurora_theme.dart';
import '../widgets/thumbnail.dart';

class SearchScreen extends StatefulWidget {
  final List<Track> tracks;
  final VoidCallback onClose;
  final void Function(Track) onSelect;
  const SearchScreen({super.key, required this.tracks, required this.onClose, required this.onSelect});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _q.isEmpty
        ? widget.tracks
        : widget.tracks.where((t) =>
            t.title.toLowerCase().contains(_q.toLowerCase()) ||
            t.channel.toLowerCase().contains(_q.toLowerCase())).toList();

    return Container(
      color: AuroraTheme.bg,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AuroraTheme.text, size: 20),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AuroraTheme.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AuroraTheme.border, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 18, color: AuroraTheme.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _ctl,
                            autofocus: true,
                            onChanged: (v) => setState(() => _q = v),
                            cursorColor: AuroraTheme.accent,
                            style: AuroraTheme.body(size: 14, color: AuroraTheme.text),
                            decoration: InputDecoration(
                              hintText: 'Search your library',
                              hintStyle: AuroraTheme.body(size: 14, color: AuroraTheme.muted),
                              isDense: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _q.isEmpty ? 'IN YOUR LIBRARY' : '${results.length} ${results.length == 1 ? 'RESULT' : 'RESULTS'}',
                style: AuroraTheme.body(size: 10, weight: FontWeight.w700, color: AuroraTheme.dim, letterSpacing: 1.5),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: results.length,
              itemBuilder: (context, i) {
                final t = results[i];
                return InkWell(
                  onTap: () => widget.onSelect(t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        SquareArt(track: t, size: 50, radius: 8),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AuroraTheme.body(size: 14, weight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${t.channel} · ${formatShort(t.duration)}',
                                style: AuroraTheme.body(size: 12, color: AuroraTheme.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
