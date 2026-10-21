import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ngmusic/data/model/track.dart';
import 'package:ngmusic/ui/screens/discover_screen_new.dart';
import 'package:ngmusic/ui/widgets/mini_player.dart';
import 'package:ngmusic/ui/widgets/track_list_item.dart';
import 'package:ngmusic/viewmodel/authors_viewmodel.dart';
import 'package:ngmusic/viewmodel/library_viewmodel.dart';
import 'package:ngmusic/viewmodel/ng_viewmodel.dart';

class _Player extends ChangeNotifier implements NgViewModel {
  @override
  Track? currentTrack;
  int previousCalls = 0;
  int clearSearchCalls = 0;
  bool previousAvailable = true;

  void selectTrack(Track? track) {
    currentTrack = track;
    notifyListeners();
  }

  @override
  TabState stateOf(NgTab tab) => TabState()..loaded = true;
  @override
  void clearSearch() => clearSearchCalls++;
  @override
  bool get isPlaying => false;
  @override
  Duration? get duration => null;
  @override
  bool hasPrev() => previousAvailable;
  @override
  bool hasNext() => false;
  @override
  void playPrev() => previousCalls++;
  @override
  void togglePlayPause() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library extends ChangeNotifier implements LibraryViewModel {
  @override
  int get cacheRevision => 0;
  @override
  bool isCacheBusy(String id) => false;
  @override
  Future<bool> isTrackCached(String id) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Authors extends ChangeNotifier implements AuthorsViewModel {
  @override
  bool isBlocked(Track track) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Track _track(String id) => Track(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
      genre: 'Ambient',
      genreVerified: true,
      iconUrl: '',
      duration: 0,
      audioType: 3,
    );

Widget _app(_Player player, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<NgViewModel>.value(value: player),
        ChangeNotifierProvider<LibraryViewModel>(create: (_) => _Library()),
        ChangeNotifierProvider<AuthorsViewModel>(create: (_) => _Authors()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: child,
      ),
    );

void main() {
  testWidgets('search history stays under the toolbar and Back closes search',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'search_history': ['Ambient', 'Piano'],
    });
    final player = _Player();
    await tester.pumpWidget(_app(player, const DiscoverScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    final toolbar = tester.getRect(find.byType(AppBar));
    final history =
        tester.getRect(find.widgetWithText(ListTile, 'Recent searches'));
    expect(history.top, closeTo(toolbar.bottom, 1));
    expect(find.text('Ambient'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Discover'), findsOneWidget);
    expect(player.clearSearchCalls, 1);
  });

  testWidgets('current track highlight follows playback selection',
      (tester) async {
    final player = _Player();
    final first = _track('101');
    final second = _track('102');
    await tester.pumpWidget(_app(
      player,
      Scaffold(
        body: Column(children: [
          TrackListItem(track: first),
          TrackListItem(track: second),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    Color? background(String title) => tester
        .widget<Material>(find
            .descendant(
              of: find.ancestor(
                of: find.text(title),
                matching: find.byType(TrackListItem),
              ),
              matching: find.byType(Material),
            )
            .first)
        .color;

    expect(background(first.title), Colors.transparent);
    player.selectTrack(first);
    await tester.pumpAndSettle();
    expect(background(first.title), isNot(Colors.transparent));
    expect(background(second.title), Colors.transparent);
    player.selectTrack(second);
    await tester.pumpAndSettle();
    expect(background(first.title), Colors.transparent);
    expect(background(second.title), isNot(Colors.transparent));
  });

  testWidgets('mini player previous control works on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = _Player()..currentTrack = _track('103');
    await tester.pumpWidget(_app(
      player,
      const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer())),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Previous track'));
    expect(player.previousCalls, 1);

    player.previousAvailable = false;
    player.selectTrack(player.currentTrack);
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.skip_previous));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
