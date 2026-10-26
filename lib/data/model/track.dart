class TrackAward {
  final String kind;
  final String label;
  final String date;

  const TrackAward({required this.kind, required this.label, this.date = ''});
}

class Track {
  final String id;
  final String title;
  final String artist;
  String genre;
  bool genreVerified;
  String iconUrl;
  final int duration;
  final int audioType;
  String? mp3Url;
  String? score;
  String? votes;

  int? votesPending;

  String? listens;

  String? downloads;
  String? faves;
  String? bpm;

  String? uploaded;

  String? fileInfo;

  List<String> tags = [];

  List<TrackAward> awards = [];

  String? authorIcon;
  String? authorUrl;

  /// Absolute path to a locally cached full-size cover, when known.
  String? localCoverPath;

  bool get hasLocalIcon {
    if (iconUrl.isEmpty) return false;
    if (iconUrl.startsWith('file:')) return true;
    if (iconUrl.contains('://')) return false;
    return iconUrl.startsWith('/') || _windowsPath.hasMatch(iconUrl);
  }

  String get localIconPath {
    if (!iconUrl.startsWith('file:')) return iconUrl;
    var plain = iconUrl.substring('file:'.length);
    if (plain.startsWith('//')) plain = plain.substring(2);
    return Uri.decodeComponent(plain);
  }

  static final _windowsPath = RegExp(r'^[A-Za-z]:[\\/]');

  String get artistAudioUrl {
    final raw = authorUrl?.trim() ?? '';
    if (raw.isNotEmpty) {
      final uri = Uri.tryParse(raw.startsWith('//')
          ? 'https:$raw'
          : raw.contains('://')
              ? raw
              : 'https://$raw');
      if (uri != null &&
          uri.host.endsWith('.newgrounds.com') &&
          uri.host != 'www.newgrounds.com') {
        return Uri.https(uri.host, '/audio').toString();
      }
    }
    return 'https://${artist.trim().toLowerCase()}.newgrounds.com/audio';
  }

  String? description;

  String? descriptionHtml;

  int? myVote;

  String? license;

  String? peaksUrl;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.genre,
    this.genreVerified = false,
    required this.iconUrl,
    required this.duration,
    required this.audioType,
    this.mp3Url,
    this.score,
    this.votes,
    this.votesPending,
    this.listens,
    this.downloads,
    this.faves,
    this.bpm,
    this.authorUrl,
    this.localCoverPath,
  });

  String? get _iconFolder {
    final numId = int.tryParse(id);
    return numId == null ? null : '${numId ~/ 1000}';
  }

  String get aIconUrl {
    if (hasLocalIcon) return iconUrl;
    return previewIconUrl;
  }

  /// The listing preview. Newgrounds' medium audio icon is the round disc
  /// variant, unlike the full square cover.
  String get previewIconUrl {
    final icon = _remoteIconFrom(iconUrl);
    if (icon != null) return icon;
    final folder = _iconFolder;
    if (folder == null) return iconUrl;
    return 'https://aicon.ngfiles.com/$folder/${id}_medium.webp';
  }

  /// Reduced icon on Newgrounds, ignoring any cached local file.
  String get remoteIconUrl => previewIconUrl;

  List<String> get artworkUrls {
    if (hasLocalIcon) return [iconUrl];
    return remoteArtworkUrls;
  }

  /// Remote artwork candidates even when [iconUrl] currently points at a
  /// cached file. Lets the UI recover from stale cache paths in the database.
  List<String> get remoteArtworkUrls {
    final out = <String>[];
    final icon = _remoteIconFrom(iconUrl);
    final cover = _remoteCoverFrom(iconUrl);
    if (icon != null) out.add(icon);
    if (cover != null && !out.contains(cover)) out.add(cover);
    final folder = _iconFolder;
    if (folder != null) {
      for (final variant in [
        '${id}_medium.webp',
        '${id}_full.webp',
        '${id}_cover.webp',
        '$id.png',
        '$id.jpg',
        '${id}_raw.png',
        '${id}_raw.jpg',
      ]) {
        final url = 'https://aicon.ngfiles.com/$folder/$variant';
        if (!out.contains(url)) out.add(url);
      }
    }
    if (iconUrl.contains('://') && !out.contains(iconUrl)) out.add(iconUrl);
    return out;
  }

  String? _remoteIconFrom(String source) {
    if (!source.contains('aicon.ngfiles.com')) return null;
    // Older submissions only have a plain icon (e.g. /882/882532.png); their
    // medium/cover variants were never generated, so keep the original URL.
    if (!RegExp(r'_(medium|small|full|cover)\.').hasMatch(source))
      return source;
    return source
        .replaceAll('_cover.', '_medium.')
        .replaceAll('_full.', '_medium.')
        .replaceAll('_small.', '_medium.');
  }

  String? _remoteCoverFrom(String source) {
    if (!source.contains('aicon.ngfiles.com')) return null;
    final cover = source
        .replaceAll('_medium.', '_cover.')
        .replaceAll('_full.', '_cover.')
        .replaceAll('_small.', '_cover.');
    return cover;
  }

  String get largeIconUrl => artworkUrls.isEmpty ? iconUrl : artworkUrls.first;

  String get coverUrl {
    final local = localCoverPath;
    if (local != null && local.isNotEmpty) return local;
    return remoteCoverUrl;
  }

  /// The full-size cover on Newgrounds, ignoring any cached local copy.
  String get remoteCoverUrl {
    final folder = _iconFolder;
    if (folder == null) return largeIconUrl;
    return 'https://aicon.ngfiles.com/$folder/${id}_cover.webp';
  }

  String get audioBaseUrl {
    final numId = int.tryParse(id);
    if (numId == null) return '';
    final folder = (numId ~/ 1000) * 1000;
    return 'https://audio.ngfiles.com/$folder/';
  }
}
