import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngmusic/data/model/playlist.dart';
import 'package:ngmusic/data/model/track.dart';
import 'package:ngmusic/data/repository/ng_repository.dart';
import 'package:ngmusic/data/repository/waveform_cache.dart';
import 'package:ngmusic/ui/widgets/waveform_progress.dart';
import 'package:path/path.dart' as path;

Track _track(String id) => Track(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
      genre: '',
      iconUrl: '',
      duration: 1,
      audioType: 3,
    );

Future<Uint8List> _png(int width) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), 1),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Uint8List png;
  late Uint8List newerPng;
  final caches = <WaveformImageCache>[];

  setUpAll(() async {
    png = await _png(1);
    newerPng = await _png(2);
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('groundpipe_waveform_');
  });

  tearDown(() async {
    for (final cache in caches) {
      cache.dispose();
    }
    caches.clear();
    await root.delete(recursive: true);
  });

  WaveformImageCache cache({
    Future<String?> Function(Track, bool)? resolve,
    Future<Uint8List> Function(String)? download,
  }) {
    final value = WaveformImageCache(
      cacheDirectory: () async => root,
      resolveUrl: resolve,
      download: download,
      retryDelay: Duration.zero,
    );
    caches.add(value);
    return value;
  }

  test('extracts the real versioned PNG URL, retaining its query', () {
    final html = File('test/fixtures/listen_1572356.html').readAsStringSync();
    expect(
      NgRepository.parseWaveformUrl(html),
      'https://img.ngfiles.com/audio_peaks/3/1572000/'
      '1572356.1779923422-2633005.listen.png?f1779923463',
    );
    expect(
      NgRepository.parseWaveformUrl(
        ''''url': '//img.ngfiles.com/audio_peaks/3/1000/1234.v.listen.png?a=1&amp;b=2' ''',
      ),
      'https://img.ngfiles.com/audio_peaks/3/1000/1234.v.listen.png?a=1&b=2',
    );
    expect(NgRepository.parseWaveformUrl('<html>No waveform</html>'), isNull);
    expect(
      NgRepository.parseWaveformUrl(
        '"https://img.ngfiles.com/audio_peaks/3/1000/1234.listen.completed.png"',
      ),
      isNull,
    );
  });

  test('a restored like preloads peaks even with an existing MP3 URL',
      () async {
    final track = StagedLike.fromMap(const StagedLike(
      trackId: '1572356',
      title: 'DPI-filtration',
      artist: 'H31072',
      iconUrl: '',
      duration: 82,
      mp3Url: 'https://audio.ngfiles.com/already-known.mp3',
      likedAt: 1,
    ).toMap())
        .toTrack();
    expect(track.peaksUrl, isNull);
    var pages = 0;
    var images = 0;
    final store = cache();
    await http.runWithClient(() async {
      // No player widget or MP3 lookup is needed to start the preload.
      await store.prepare(track);
      final first = store.known(track.id);
      expect(first, isNotNull);
      first!.dispose();
      final reopened = await store.load(track);
      expect(reopened!.width, 1);
      reopened.dispose();
      final again = store.known(track.id);
      expect(again, isNotNull);
      again!.dispose();
    },
        () => MockClient((request) async {
              if (request.url.host == 'www.newgrounds.com') {
                pages++;
                return http.Response(
                    File('test/fixtures/listen_1572356.html')
                        .readAsStringSync(),
                    200);
              }
              images++;
              expect(request.url.path,
                  endsWith('1572356.1779923422-2633005.listen.png'));
              expect(request.url.query, 'f1779923463');
              return http.Response.bytes(png, 200);
            }));
    expect(pages, 1);
    expect(images, 1);
    expect(root.listSync().map((f) => path.basename(f.path)), ['1572356.png']);
  });

  test('playback and waveform lookup share one in-flight HTML request',
      () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    var requests = 0;
    final audioTrack = _track('1572356');
    final waveformTrack = _track('1572356');
    await http.runWithClient(() async {
      final audio = NgRepository().enrichTrack(audioTrack);
      final peaks = NgRepository().getWaveformUrl(waveformTrack);
      await started.future;
      response.complete(http.Response(
          File('test/fixtures/listen_1572356.html').readAsStringSync(), 200));
      await audio;
      expect(await peaks, contains('1572356.1779923422-2633005.listen.png?'));
      expect(audioTrack.mp3Url, isNotEmpty);
      expect(requests, 1);
    },
        () => MockClient((request) {
              requests++;
              if (!started.isCompleted) started.complete();
              return response.future;
            }));
  });

  test('startup reuses the current PNG from disk without network access',
      () async {
    await File(path.join(root.path, '1234.png')).writeAsBytes(png);
    await File(path.join(root.path, 'old.png')).writeAsBytes(png);
    var requests = 0;
    final store = cache(resolve: (track, refresh) async {
      requests++;
      throw const SocketException('Offline');
    });
    await store.prepare(_track('1234'));
    final image = store.known('1234');
    expect(image, isNotNull);
    image!.dispose();
    expect(requests, 0);
    expect(root.listSync().map((f) => path.basename(f.path)), ['1234.png']);
  });

  test('player opening during preload joins it instead of downloading twice',
      () async {
    final started = Completer<void>();
    final response = Completer<Uint8List>();
    var downloads = 0;
    final store = cache(
      resolve: (track, refresh) async => 'actual-url',
      download: (url) {
        downloads++;
        started.complete();
        return response.future;
      },
    );
    final track = _track('1');
    final preload = store.prepare(track);
    await started.future;
    final opened = store.load(track);
    final reopened = store.load(track);
    response.complete(png);
    await preload;
    final a = await opened;
    final b = await reopened;
    expect(a, isNotNull);
    expect(b, isNotNull);
    a!.dispose();
    expect(b!.width, 1);
    b.dispose();
    expect(downloads, 1);
  });

  test('late A cannot replace B or delete its cached PNG', () async {
    final started = Completer<void>();
    final response = Completer<Uint8List>();
    final store = cache(
      resolve: (track, refresh) async => track.id,
      download: (url) {
        if (url == 'A') {
          started.complete();
          return response.future;
        }
        return Future.value(newerPng);
      },
    );
    final a = _track('A');
    final oldLoad = store.prepare(a);
    await started.future;
    final oldWidget = store.load(a);
    await store.prepare(_track('B'));
    response.complete(png);
    await oldLoad;
    expect(await oldWidget, isNull);
    expect(store.known('A'), isNull);
    final current = store.known('B');
    expect(current!.width, 2);
    current.dispose();
    expect(root.listSync().map((f) => path.basename(f.path)), ['B.png']);
    expect(await File(path.join(root.path, 'B.png')).readAsBytes(), newerPng);
  });

  test('A -> B -> A starts fresh and rejects both superseded responses',
      () async {
    final aStarted = Completer<void>();
    final bStarted = Completer<void>();
    final oldA = Completer<Uint8List>();
    final oldB = Completer<Uint8List>();
    var aDownloads = 0;
    final store = cache(
      resolve: (track, refresh) async => track.id,
      download: (url) {
        if (url == 'B') {
          bStarted.complete();
          return oldB.future;
        }
        if (++aDownloads == 1) {
          aStarted.complete();
          return oldA.future;
        }
        return Future.value(newerPng);
      },
    );
    final first = store.prepare(_track('A'));
    await aStarted.future;
    final second = store.prepare(_track('B'));
    await bStarted.future;
    await store.prepare(_track('A'));
    oldA.complete(png);
    oldB.complete(png);
    await Future.wait([first, second]);
    final image = store.known('A');
    expect(image!.width, 2);
    image.dispose();
    expect(aDownloads, 2);
    expect(root.listSync().map((f) => path.basename(f.path)), ['A.png']);
    expect(await File(path.join(root.path, 'A.png')).readAsBytes(), newerPng);
  });

  test('corrupt disk cache and a transient download failure recover', () async {
    final file = File(path.join(root.path, '1.png'));
    await file.writeAsString('not a real PNG');
    final refreshes = <bool>[];
    var attempts = 0;
    final store = cache(
      resolve: (track, refresh) async {
        refreshes.add(refresh);
        return 'actual-url';
      },
      download: (url) async {
        if (++attempts == 1) throw TimeoutException('Temporary outage');
        return png;
      },
    );
    await store.prepare(_track('1'));
    final image = store.known('1');
    expect(image, isNotNull);
    image!.dispose();
    expect(refreshes, [false, true]);
    expect(await file.readAsBytes(), png);
  });

  test('network retries are bounded and reopening can recover later', () async {
    var attempts = 0;
    var offline = true;
    final store = cache(
      resolve: (track, refresh) async => 'actual-url',
      download: (url) async {
        attempts++;
        if (offline) throw const SocketException('Offline');
        return png;
      },
    );
    final track = _track('1');
    await store.prepare(track);
    expect(store.known('1'), isNull);
    expect(attempts, 3);
    expect(root.listSync(), isEmpty);
    offline = false;
    final recovered = await store.load(track);
    expect(recovered, isNotNull);
    recovered!.dispose();
    expect(attempts, 4);
  });

  testWidgets(
      'preloaded waveform renders on the first frame and after reopening',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final store = WaveformImageCache.instance;
    caches.add(store);
    final track = _track('1')
      ..peaksUrl =
          'https://img.ngfiles.com/audio_peaks/3/0/1.version.listen.png';
    var downloads = 0;
    await tester.runAsync(() => http.runWithClient(
          () => store.prepare(track),
          () => MockClient((request) async {
            downloads++;
            return http.Response.bytes(png, 200);
          }),
        ));

    Widget player() => MaterialApp(
          home: Scaffold(
            body: WaveformProgress(track: track, progress: 0.5),
          ),
        );
    await tester.pumpWidget(player());
    expect(find.byType(WaveformProgress), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(player());
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
    expect(downloads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
