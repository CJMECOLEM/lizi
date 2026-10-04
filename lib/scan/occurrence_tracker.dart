/// Decides when a detected item should be counted during continuous scanning.
///
/// An item is counted once it has been seen in [confirmFrames] processed
/// frames (filters out one-frame misreads). It is counted again only after it
/// has left the frame — i.e. was not seen for longer than [goneAfter] — and
/// then reappears.
class OccurrenceTracker {
  OccurrenceTracker({
    this.confirmFrames = 2,
    this.goneAfter = const Duration(milliseconds: 800),
  });

  final int confirmFrames;
  final Duration goneAfter;

  final Map<String, _Track> _tracks = {};

  /// Feeds the keys detected in one frame and returns the keys that should be
  /// counted now.
  List<String> update(Iterable<String> keys, DateTime now) {
    _tracks.removeWhere((_, t) => now.difference(t.lastSeen) > goneAfter);

    final counted = <String>[];
    for (final key in keys.toSet()) {
      final track = _tracks.putIfAbsent(key, () => _Track(now));
      track.hits++;
      track.lastSeen = now;
      if (!track.counted && track.hits >= confirmFrames) {
        track.counted = true;
        counted.add(key);
      }
    }
    return counted;
  }

  void reset() => _tracks.clear();
}

class _Track {
  _Track(this.lastSeen);

  DateTime lastSeen;
  int hits = 0;
  bool counted = false;
}
