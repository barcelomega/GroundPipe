import 'package:flutter_test/flutter_test.dart';
import 'package:ngmusic/data/model/track.dart';

Track track({String iconUrl = '', String? localCoverPath}) => Track(
      id: '1629574',
      title: 'Track',
      artist: 'Artist',
      genre: '',
      iconUrl: iconUrl,
      duration: 0,
      audioType: 3,
      localCoverPath: localCoverPath,
    );

void main() {
  test('cached file paths are recognised on Android and Windows', () {
    final android = track(iconUrl: '/data/user/0/app/track_cache/1_icon.webp');
    expect(android.hasLocalIcon, isTrue);
    expect(android.localIconPath, '/data/user/0/app/track_cache/1_icon.webp');

    final uri = track(iconUrl: 'file:///data/user/0/app/1_icon.webp');
    expect(uri.hasLocalIcon, isTrue);
    expect(uri.localIconPath, '/data/user/0/app/1_icon.webp');

    final windows = track(iconUrl: r'C:\cache\1_icon.webp');
    expect(windows.hasLocalIcon, isTrue);
    expect(windows.localIconPath, r'C:\cache\1_icon.webp');

    expect(track(iconUrl: 'https://aicon.ngfiles.com/1/x.webp').hasLocalIcon,
        isFalse);
  });

  test('a cached full cover wins over the remote cover', () {
    final cached = track(
      iconUrl: '/cache/1_icon.webp',
      localCoverPath: '/cache/1_cover.webp',
    );
    expect(cached.coverUrl, '/cache/1_cover.webp');
    expect(cached.remoteCoverUrl,
        'https://aicon.ngfiles.com/1629/1629574_cover.webp');
    expect(cached.remoteIconUrl,
        'https://aicon.ngfiles.com/1629/1629574_medium.webp');
  });

  test('listing preview is always the round medium icon', () {
    final enriched = track(
      iconUrl: 'https://aicon.ngfiles.com/1629/1629574_full.webp?f=1',
    );
    expect(enriched.aIconUrl,
        'https://aicon.ngfiles.com/1629/1629574_medium.webp?f=1');
    expect(enriched.previewIconUrl,
        'https://aicon.ngfiles.com/1629/1629574_medium.webp?f=1');
    expect(enriched.remoteCoverUrl,
        'https://aicon.ngfiles.com/1629/1629574_cover.webp');
  });

  test('cached listing preview does not replace the full-size cover', () {
    final cachedPreview = track(iconUrl: '/cache/1629574_icon.webp');

    expect(cachedPreview.aIconUrl, '/cache/1629574_icon.webp');
    expect(cachedPreview.coverUrl,
        'https://aicon.ngfiles.com/1629/1629574_cover.webp');
  });
}
