/// Remembers which cover URLs failed for the track that is currently playing.
/// The player can then show its fallback immediately on re-entry instead of
/// probing the server again and blinking the placeholder.
class CoverFailureCache {
  CoverFailureCache._();

  static final CoverFailureCache instance = CoverFailureCache._();

  String? _trackId;
  final Set<String> _failed = {};

  /// Resets when playback moves to another track, so returning to a track
  /// gives its cover one more chance.
  void keepOnly(String trackId) {
    if (_trackId == trackId) return;
    _trackId = trackId;
    _failed.clear();
  }

  bool failed(String trackId, String url) =>
      _trackId == trackId && _failed.contains(url);

  void markFailed(String trackId, String url) {
    _trackId ??= trackId;
    if (_trackId != trackId) return;
    _failed.add(url);
  }
}
