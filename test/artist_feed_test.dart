import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngmusic/data/model/author.dart';
import 'package:ngmusic/data/model/track.dart';
import 'package:ngmusic/data/repository/ng_repository.dart';
import 'package:ngmusic/data/repository/timeline_feed.dart';

Track song(String id, String artist) => Track(
      id: id,
      title: id,
      artist: artist,
      genre: '',
      iconUrl: '',
      duration: 0,
      audioType: 3,
    );

void main() {
  test('live Newgrounds artist page and publication date', () async {
    final repo = NgRepository();
    final (tracks, next) = await repo.getArtistTracksPage('8-bitek');
    expect(tracks, isNotEmpty);
    expect(tracks.first.duration, greaterThan(0));
    expect(tracks.any((t) => t.genreVerified && t.genre.isNotEmpty), true);
    final avatar = await repo.getAuthorAvatar('8-bitek');
    expect(avatar, startsWith('https://uimg.ngfiles.com/'));
    final featured = await repo.getFeaturedTracks();
    expect(featured.any((t) => t.genreVerified && t.genre.isNotEmpty), true);
    expect(next, contains('page=2'));
    await repo.loadPublicationDate(tracks.first);
    expect(tracks.first.publishedAt, isNotNull);
    final feed = TimelineFeed(
      authors: const [
        Author(username: '8-bitek', name: '8-BiTek'),
        Author(username: 'waterflame', name: 'Waterflame')
      ],
      loadPage: repo.getArtistTracksPage,
      loadDate: repo.loadPublicationDate,
    );
    final timeline = await feed.take(4);
    expect(timeline, hasLength(4));
    for (var i = 1; i < timeline.length; i++) {
      expect(timeline[i].publishedAt!.isAfter(timeline[i - 1].publishedAt!),
          false);
    }
  },
      skip: !const bool.fromEnvironment('RUN_NG_LIVE'),
      timeout: const Timeout(Duration(seconds: 90)));

  test(
      'artist AJAX response parses sibling playback, artwork, score and next page',
      () {
    final body = jsonEncode({
      'items': {
        '2026': [
          '''
        <div class="audio-wrapper"><div class="flexbox">
          <a class="item-audiosubmission" href="https://www.newgrounds.com/audio/listen/123?x=1" title="Song &amp; title">
            <img src="https://aicon.ngfiles.com/0/123_medium.webp">
            <div class="detail-description">This description is not a genre</div>
            <div class="star-score" title="Score: 4.84/5.00"></div>
            <div class="item-details-meta"><dd><strong>Song</strong></dd><dd>House</dd><dd>232 Views</dd></div>
          </a>
          <div><a data-audio-duration="338" data-audio-type="3"></a></div>
        </div></div>
      '''
        ]
      },
      'load_more': r'loadMore("https:\/\/author.newgrounds.com\/audio?page=2")',
    });
    final (tracks, next) = NgRepository().parseArtistTracksPage(body, 'Author');
    expect(tracks, hasLength(1));
    expect(tracks.single.id, '123');
    expect(tracks.single.duration, 338);
    expect(tracks.single.genre, 'House');
    expect(tracks.single.genreVerified, true);
    expect(tracks.single.score, '4.84');
    expect(tracks.single.artistAudioUrl, 'https://author.newgrounds.com/audio');
    expect(next, 'https://author.newgrounds.com/audio?page=2');
  });

  test('artist page parser accepts an HTML response instead of AJAX JSON', () {
    final (tracks, next) = NgRepository().parseArtistTracksPage('''
      <!doctype html>
      <html><body>
        <div class="audio-wrapper">
          <a class="item-audiosubmission" href="/audio/listen/456" title="HTML track">
            <img src="https://aicon.ngfiles.com/0/456.webp">
            <div class="item-details-meta"><dd><strong>Song</strong></dd><dd>Ambient</dd></div>
          </a>
          <span data-audio-duration="210" data-audio-type="3"></span>
        </div>
        <a href="?page=2">Next</a>
      </body></html>
    ''', 'SampleArtist');

    expect(tracks, hasLength(1));
    expect(tracks.single.id, '456');
    expect(tracks.single.title, 'HTML track');
    expect(tracks.single.duration, 210);
    expect(tracks.single.genre, 'Ambient');
    expect(next, 'https://sampleartist.newgrounds.com/audio?page=2');
  });

  test('profile avatars prefer the author image and support legacy SVG icons',
      () {
    final repo = NgRepository();
    expect(repo.parseAuthorAvatar('''
      <meta property="og:image" content="https://uimg.ngfiles.com/profile/1/1.webp">
      <img src="https://aicon.ngfiles.com/track.webp">
    '''), 'https://uimg.ngfiles.com/profile/1/1.webp');
    expect(repo.parseAuthorAvatar('''
      <div class="user-icon"><svg><image href="https://uimg.ngfiles.com/icons/1/1.webp" /></svg></div>
    '''), 'https://uimg.ngfiles.com/icons/1/1.webp');
  });

  test('track genre comes from sidestats, never the song description', () {
    expect(NgRepository().parseTrackGenre('''
      <div class="detail-description">An ambient track about space</div>
      <dl class="sidestats"><dt>Genre</dt><dd><a>Hip Hop - Modern</a></dd></dl>
    '''), 'Hip Hop - Modern');
  });

  test('favorite audio pages parse IDs and AJAX next-page URL', () {
    final (ids, next) = NgRepository().parseFavoriteAudioPage(r'''
      <ul class="itemlist alternating">
        <li><a href="https://www.newgrounds.com/audio/listen/123">Track</a>
            <a data-audio-playback="123"></a></li>
        <li><a href="/audio/listen/456">Other track</a></li>
        <li id="load-more"><script>
          UsersFavoritesController.loadMore($('#load-more'),
            "https:\/\/8-bitek.newgrounds.com\/favorites\/audio?page=4", "li", 'ul.alternating');
        </script></li>
      </ul>
    ''');
    expect(ids, ['123', '456']);
    expect(next, 'https://8-bitek.newgrounds.com/favorites/audio?page=4');
  });

  test(
      'mobile author listing parses Song - Genre without treating prose as genre',
      () {
    final repo = NgRepository();
    for (final entry in {
      'Song - Hip Hop - Modern': 'Hip Hop - Modern',
      'Loop - House': 'House',
      'An atmospheric song': '',
    }.entries) {
      final (tracks, _) = repo.parseArtistTracksPage(
          jsonEncode({
            'items': {
              '2026': [
                '''
          <a class="item-audiosubmission" href="/audio/listen/1" title="Track">
            <div class="detail-description">${entry.key}</div>
          </a>
        '''
              ]
            },
          }),
          'author');
      expect(tracks.single.genre, entry.value);
    }
  });

  test(
      'timeline merges author pages by actual date rather than numeric track IDs',
      () async {
    final feed = TimelineFeed(
      authors: const [
        Author(username: 'a', name: 'A'),
        Author(username: 'b', name: 'B')
      ],
      loadPage: (artist, {int page = 1}) async {
        if (artist == 'a' && page == 1) return ([song('1', artist)], 'next');
        if (artist == 'a') return ([song('3', artist)], null);
        return ([song('999', artist), song('4', artist)], null);
      },
      loadDate: (track) async {
        final day = {'1': 4, '999': 3, '3': 2, '4': 1}[track.id]!;
        track.publishedAt = DateTime.utc(2026, 10, day);
      },
    );
    expect((await feed.take(2)).map((t) => t.id), ['1', '999']);
    expect((await feed.take(2)).map((t) => t.id), ['3', '4']);
    expect(feed.hasMore, false);
  });

  test('timeline follows the page number supplied by load_more', () async {
    final requestedPages = <int>[];
    final feed = TimelineFeed(
      authors: const [Author(username: 'a', name: 'A')],
      loadPage: (artist, {int page = 1}) async {
        requestedPages.add(page);
        if (page == 1) {
          return ([song('1', artist)], 'https://a.newgrounds.com/audio?page=4');
        }
        return ([song('2', artist)], null);
      },
      loadDate: (track) async {
        track.publishedAt = DateTime.utc(2026, 10, track.id == '1' ? 2 : 1);
      },
    );

    expect((await feed.take(2)).map((track) => track.id), ['1', '2']);
    expect(requestedPages, [1, 4]);
    expect(feed.hasMore, false);
  });

  test('timeline feed persists cursors and emitted tracks', () async {
    final authors = const [Author(username: 'a', name: 'A')];
    final loader = (String artist, {int page = 1}) async => (
          [song('$page', artist)],
          page == 1 ? 'https://a.newgrounds.com/audio?page=2' : null
        );
    final dateLoader = (Track track) async {
      track.publishedAt = DateTime.utc(2026, 10, 3 - int.parse(track.id));
    };
    final feed =
        TimelineFeed(authors: authors, loadPage: loader, loadDate: dateLoader);
    expect((await feed.take(1)).single.id, '1');

    final restored = TimelineFeed.fromJson(
      authors: authors,
      loadPage: loader,
      loadDate: dateLoader,
      json: jsonDecode(jsonEncode(feed.toJson())) as Map<String, dynamic>,
    );
    expect(restored.emittedTracks.single.id, '1');
    expect((await restored.take(1)).single.id, '2');
    expect(restored.isComplete, true);
  });

  test('failed timeline batch can be retried without losing consumed tracks',
      () async {
    var fail = true;
    final feed = TimelineFeed(
      authors: const [Author(username: 'a', name: 'A')],
      loadPage: (artist, {int page = 1}) async =>
          ([song('1', artist), song('2', artist)], null),
      loadDate: (track) async {
        if (track.id == '2' && fail) throw Exception('offline');
        track.publishedAt = DateTime.utc(2026, 10, track.id == '1' ? 2 : 1);
      },
    );
    await expectLater(feed.take(2), throwsException);
    fail = false;
    expect((await feed.take(2)).map((t) => t.id), ['1', '2']);
  });

  test('timeline author progress waits for dates and includes empty authors',
      () async {
    final dateStarted = Completer<void>();
    final releaseDate = Completer<void>();
    final progress = <(int, int)>[];
    final feed = TimelineFeed(
      authors: const [
        Author(username: 'a', name: 'A'),
        Author(username: 'empty', name: 'Empty'),
      ],
      loadPage: (artist, {int page = 1}) async =>
          (artist == 'a' ? [song('1', artist)] : <Track>[], null),
      loadDate: (track) async {
        dateStarted.complete();
        await releaseDate.future;
        track.publishedAt = DateTime.utc(2026, 10, 1);
      },
      onProgress: (completed, total) => progress.add((completed, total)),
    );

    final pending = feed.take(1);
    await dateStarted.future;
    expect(progress, [(1, 2)]);
    releaseDate.complete();
    expect(await pending, hasLength(1));
    expect(progress, [(1, 2), (2, 2)]);
  });

  test('timeline reports merging while dates beyond the first head are pending',
      () async {
    final secondDateStarted = Completer<void>();
    final releaseDate = Completer<void>();
    var merging = false;
    final loadedDates = <String>[];
    final feed = TimelineFeed(
      authors: const [Author(username: 'a', name: 'A')],
      loadPage: (artist, {int page = 1}) async =>
          ([song('1', artist), song('2', artist), song('3', artist)], null),
      loadDate: (track) async {
        loadedDates.add(track.id);
        if (track.id == '2') {
          secondDateStarted.complete();
          await releaseDate.future;
        }
        track.publishedAt = DateTime.utc(2026, 10, 4 - int.parse(track.id));
      },
      onMerging: () => merging = true,
    );

    final pending = feed.take(2);
    await secondDateStarted.future;
    expect(feed.completedAuthors, 1);
    expect(merging, true);
    releaseDate.complete();
    expect((await pending).map((track) => track.id), ['1', '2']);
    expect(loadedDates, ['1', '2']);
    expect((await feed.take(1)).single.id, '3');
    expect(feed.hasMore, false);
  });

  test('timeline does not fetch the next page after filling a batch', () async {
    final pages = <int>[];
    final feed = TimelineFeed(
      authors: const [Author(username: 'a', name: 'A')],
      loadPage: (artist, {int page = 1}) async {
        pages.add(page);
        return ([song('$page', artist)], page == 1 ? '?page=2' : null);
      },
      loadDate: (track) async {
        track.publishedAt = DateTime.utc(2026, 10, 3 - int.parse(track.id));
      },
    );

    expect((await feed.take(1)).single.id, '1');
    expect(pages, [1]);
    expect(feed.hasMore, true);
    expect((await feed.take(1)).single.id, '2');
    expect(pages, [1, 2]);
    expect(feed.hasMore, false);
  });

  test('timeline reuses dates of unchanged heads across batches', () async {
    final dateLoads = <String>[];
    final feed = TimelineFeed(
      authors: const [
        Author(username: 'a', name: 'A'),
        Author(username: 'b', name: 'B'),
      ],
      loadPage: (artist, {int page = 1}) async =>
          ([song(artist, artist)], null),
      loadDate: (track) async {
        dateLoads.add(track.id);
        track.publishedAt = DateTime.utc(2026, 10, track.id == 'a' ? 2 : 1);
      },
    );

    expect((await feed.take(1)).single.id, 'a');
    expect((await feed.take(1)).single.id, 'b');
    expect(dateLoads, ['a', 'b']);
  });

  test('author keys are stable across names and profile/audio links', () {
    for (final value in [
      '8-BiTek',
      'https://8-bitek.newgrounds.com',
      '//8-bitek.newgrounds.com/audio'
    ]) {
      expect(Author.key(value), '8-bitek');
    }
  });
}
