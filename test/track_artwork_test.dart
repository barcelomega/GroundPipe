import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngmusic/data/model/track.dart';
import 'package:ngmusic/data/repository/cache_manager.dart';
import 'package:ngmusic/ui/widgets/track_artwork.dart';
import 'package:ngmusic/viewmodel/library_viewmodel.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

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

class _Library extends ChangeNotifier implements LibraryViewModel {
  @override
  int get cacheRevision => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A valid 1x1 transparent PNG.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPh'
  'fDwAChwGA60e6kgAAAABJRU5ErkJggg==',
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

  test('known icon paths are found synchronously', () {
    final root = Directory.systemTemp.createTempSync('artwork_paths');
    addTearDown(() => root.deleteSync(recursive: true));
    final permanent = Directory(p.join(root.path, 'permanent'))..createSync();
    final temporary = Directory(p.join(root.path, 'temporary'))..createSync();
    final legacy = Directory(p.join(root.path, 'legacy'))..createSync();

    final permanentIcon = File(p.join(permanent.path, '1_icon.webp'))
      ..writeAsBytesSync(_pngBytes);
    final temporaryIcon = File(p.join(temporary.path, '2_icon.webp'))
      ..writeAsBytesSync(_pngBytes);
    final legacyCover = File(p.join(legacy.path, '3_art.webp'))
      ..writeAsBytesSync(_pngBytes);

    final cache = CacheManager.instance;
    cache.debugSetArtworkDirectories(
      permanent: permanent.path,
      temporary: temporary.path,
      legacy: legacy.path,
    );
    addTearDown(cache.debugSetArtworkDirectories);

    expect(cache.knownIconPath('1'), permanentIcon.path);
    expect(cache.knownIconPath('2'), temporaryIcon.path);
    expect(cache.knownIconPath('3'), isNull);
    expect(cache.knownArtworkPath('3'), legacyCover.path);
  });

  test('caching a local icon writes it to the permanent store', () async {
    final root = Directory.systemTemp.createTempSync('artwork_save');
    addTearDown(() => root.deleteSync(recursive: true));
    final permanent = Directory(p.join(root.path, 'permanent'))..createSync();
    final temporary = Directory(p.join(root.path, 'temporary'))..createSync();
    final legacy = Directory(p.join(root.path, 'legacy'))..createSync();
    final source = File(p.join(root.path, 'source.png'))
      ..writeAsBytesSync(_pngBytes);

    final cache = CacheManager.instance;
    cache.debugSetArtworkDirectories(
      permanent: permanent.path,
      temporary: temporary.path,
      legacy: legacy.path,
    );
    addTearDown(cache.debugSetArtworkDirectories);

    final local = Track(
      id: 'local-track',
      title: 'Track',
      artist: 'Artist',
      genre: '',
      iconUrl: source.path,
      duration: 0,
      audioType: 3,
    );

    final saved = await cache.cachePermanentTrackIcon(local);
    expect(saved, p.join(permanent.path, 'local-track_icon.png'));
    expect(File(saved!).existsSync(), isTrue);
    expect(cache.knownIconPath(local.id), saved);
    expect(await cache.getCachedIconPath(local.id), saved);
  });

  testWidgets('a cached icon is rendered on the first frame', (tester) async {
    final root = Directory.systemTemp.createTempSync('artwork_first_frame');
    addTearDown(() => root.deleteSync(recursive: true));
    final icon = File(p.join(root.path, '1629574_icon.png'))
      ..writeAsBytesSync(_pngBytes);

    final cache = CacheManager.instance;
    cache.debugSetArtworkDirectories(permanent: root.path);
    addTearDown(cache.debugSetArtworkDirectories);

    final remote = track(
      iconUrl: 'https://aicon.ngfiles.com/1629/1629574_medium.webp',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryViewModel>(
        create: (_) => _Library(),
        child: MaterialApp(
          home: TrackArtwork(track: remote, size: 48, compact: true),
        ),
      ),
    );

    expect(cache.knownIconPath(remote.id), icon.path);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
