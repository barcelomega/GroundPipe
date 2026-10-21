import 'track.dart';

class Author {
  final String username;
  final String name;
  final bool subscribed;
  final bool blocked;

  const Author({
    required this.username,
    required this.name,
    this.subscribed = false,
    this.blocked = false,
  });

  static String key(String value) {
    final raw = value.trim();
    final uri = Uri.tryParse(raw.startsWith('//')
        ? 'https:$raw'
        : raw.contains('://')
            ? raw
            : 'https://$raw');
    if (uri != null &&
        uri.host.endsWith('.newgrounds.com') &&
        uri.host != 'www.newgrounds.com') {
      return uri.host.split('.').first.toLowerCase();
    }
    return raw.toLowerCase();
  }

  factory Author.fromTrack(Track track) => Author(
        username: key(track.artistAudioUrl),
        name: track.artist,
      );

  factory Author.fromMap(Map<String, dynamic> row) => Author(
        username: row['username'] as String,
        name: row['name'] as String,
        subscribed: row['subscribed'] == 1,
        blocked: row['blocked'] == 1,
      );

  String get audioUrl => 'https://$username.newgrounds.com/audio';

  Author copyWith({bool? subscribed, bool? blocked}) => Author(
        username: username,
        name: name,
        subscribed: subscribed ?? this.subscribed,
        blocked: blocked ?? this.blocked,
      );
}
