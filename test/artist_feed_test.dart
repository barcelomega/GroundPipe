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
  test('live Newgrounds artist page and timeline', () async {
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
    final feed = TimelineFeed(
      authors: const [
        Author(username: '8-bitek', name: '8-BiTek'),
        Author(username: 'waterflame', name: 'Waterflame')
      ],
      loadPage: repo.getArtistTracksPage,
    );
    final timeline = await feed.take(4);
    expect(timeline, hasLength(4));
    for (var i = 1; i < timeline.length; i++) {
      expect(int.parse(timeline[i].id) < int.parse(timeline[i - 1].id), true);
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

  test('artist HTML load-more script advances to the next page', () {
    final (tracks, next) = NgRepository().parseArtistTracksPage(r'''
      <!doctype html>
      <html><body>
        <div class="audio-wrapper">
          <a class="item-audiosubmission" href="/audio/listen/789" title="Script track"></a>
        </div>
        <li id="22103919_audio_scroll_more" data-playlist-func="load-more">
          <script>
            (($) => {
              //($element, url, tagName, parentSelector, outerId)
              UsersContentController.loadMore($('#22103919_audio_scroll_more'), "https:\/\/8-bitek.newgrounds.com\/audio?page=2", "li", 'ul.itemlist', '22103919_audio').watch();
            })(jQuery);
          </script>
        </li>
      </body></html>
    ''', '8-Bitek');

    expect(tracks, hasLength(1));
    expect(tracks.single.id, '789');
    expect(next, 'https://8-bitek.newgrounds.com/audio?page=2');
  });

  test('artist HTML without a load-more control has no next page', () {
    final (_, next) = NgRepository().parseArtistTracksPage(
      '<!doctype html><html><body><ul class="itemlist"></ul></body></html>',
      '8-Bitek',
    );
    expect(next, isNull);
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

  test('author favorites counter separates exact and rounded values', () {
    final repo = NgRepository();
    const header = r'''
      <nav class="user-header-nav">
        <div class="user-header-buttons">
          <a href="/fans" class="user-header-button">
            <div><span>FANS</span><strong>646</strong></div>
          </a>
          <a href="/favorites" class="user-header-button current">
            <div><span>FAVES</span><strong>$value</strong></div>
          </a>
        </div>
      </nav>
    ''';

    final tooMany =
        repo.parseAuthorFavoritesCount(header.replaceFirst(r'$value', '3K'));
    expect(tooMany.count, isNull);
    expect(tooMany.isTooMany, isTrue);

    final exact =
        repo.parseAuthorFavoritesCount(header.replaceFirst(r'$value', '999'));
    expect(exact.count, 999);
    expect(exact.isTooMany, isFalse);

    final missing =
        repo.parseAuthorFavoritesCount('<html><body></body></html>');
    expect(missing.count, isNull);
    expect(missing.isUnknown, isTrue);
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

  test('timeline collects one page per author and sorts by track ID', () async {
    final pages = <String, List<int>>{};
    final feed = TimelineFeed(
      authors: const [
        Author(username: 'a', name: 'A'),
        Author(username: 'b', name: 'B')
      ],
      loadPage: (artist, {int page = 1}) async {
        pages.putIfAbsent(artist, () => []).add(page);
        if (artist == 'a') return ([song('3', artist)], 'next');
        return ([song('4', artist), song('2', artist)], null);
      },
    );
    expect((await feed.take(2)).map((t) => t.id), ['4', '3']);
    expect((await feed.take(2)).map((t) => t.id), ['2']);
    expect(pages, {
      'a': [1],
      'b': [1],
    });
    expect(feed.hasMore, false);
  });

  test('timeline loads only one page per author', () async {
    final requestedPages = <int>[];
    final feed = TimelineFeed(
      authors: const [Author(username: 'a', name: 'A')],
      loadPage: (artist, {int page = 1}) async {
        requestedPages.add(page);
        return ([song('1', artist)], 'https://a.newgrounds.com/audio?page=4');
      },
    );

    expect((await feed.take(2)).map((track) => track.id), ['1']);
    expect(requestedPages, [1]);
    expect(feed.hasMore, false);
  });

  test('timeline feed persists pool and emitted tracks', () async {
    const authors = [Author(username: 'a', name: 'A')];
    Future<(List<Track>, String?)> loader(String artist,
            {int page = 1}) async =>
        ([song('3', artist), song('2', artist), song('1', artist)], null);
    final feed = TimelineFeed(authors: authors, loadPage: loader);
    expect((await feed.take(1)).single.id, '3');

    final restored = TimelineFeed.fromJson(
      authors: authors,
      loadPage: loader,
      json: jsonDecode(jsonEncode(feed.toJson())) as Map<String, dynamic>,
    );
    expect(restored.emittedTracks.single.id, '3');
    expect((await restored.take(2)).map((track) => track.id), ['2', '1']);
    expect(restored.isComplete, true);
  });

  test('failed author load can be retried', () async {
    var fail = true;
    final feed = TimelineFeed(
      authors: const [
        Author(username: 'a', name: 'A'),
        Author(username: 'b', name: 'B'),
      ],
      loadPage: (artist, {int page = 1}) async {
        if (artist == 'b' && fail) {
          fail = false;
          throw Exception('offline');
        }
        return ([song(artist == 'a' ? '2' : '1', artist)], null);
      },
    );
    await expectLater(feed.take(2), throwsException);
    expect(feed.emittedTracks, isEmpty);
    expect((await feed.take(2)).map((t) => t.id), ['2', '1']);
  });

  test('timeline author progress includes empty authors', () async {
    final progress = <(int, int)>[];
    final feed = TimelineFeed(
      authors: const [
        Author(username: 'a', name: 'A'),
        Author(username: 'empty', name: 'Empty'),
      ],
      loadPage: (artist, {int page = 1}) async =>
          (artist == 'a' ? [song('1', artist)] : <Track>[], null),
      onProgress: (completed, total) => progress.add((completed, total)),
    );

    expect(await feed.take(1), hasLength(1));
    expect(progress, [(1, 2), (2, 2)]);
  });

  test('timeline reports merging after the pool is sorted', () async {
    var merging = false;
    final feed = TimelineFeed(
      authors: const [Author(username: 'a', name: 'A')],
      loadPage: (artist, {int page = 1}) async =>
          ([song('2', artist), song('1', artist)], null),
      onMerging: () => merging = true,
    );

    expect((await feed.take(1)).single.id, '2');
    expect(merging, true);
  });

  test('timeline caps the global pool at 250 and drops the smallest IDs',
      () async {
    final pages = <int>[];
    final tracks = [for (var id = 300; id >= 1; id--) song('$id', 'a')];
    final feed = TimelineFeed(
      authors: const [Author(username: 'a', name: 'A')],
      loadPage: (artist, {int page = 1}) async {
        pages.add(page);
        return (tracks, null);
      },
    );

    final ids = <String>[];
    ids.addAll((await feed.take(1)).map((track) => track.id));
    expect(feed.loadedTrackCount, TimelineFeed.candidateLimit);
    while (feed.hasMore) {
      ids.addAll((await feed.take(25)).map((track) => track.id));
    }
    expect(pages, [1]);
    expect(ids, hasLength(TimelineFeed.candidateLimit));
    expect(ids.first, '300');
    expect(ids.last, '51');
  });

  test('timeline reuses the pool across batches', () async {
    final pages = <int>[];
    final feed = TimelineFeed(
      authors: const [
        Author(username: 'a', name: 'A'),
        Author(username: 'b', name: 'B'),
      ],
      loadPage: (artist, {int page = 1}) async {
        pages.add(page);
        return ([song(artist == 'a' ? '2' : '1', artist)], null);
      },
    );

    expect((await feed.take(1)).single.id, '2');
    expect((await feed.take(1)).single.id, '1');
    expect(pages, [1, 1]);
  });

  test('restored timeline loads only authors missing from the cache', () async {
    const a = Author(username: 'a', name: 'A');
    const b = Author(username: 'b', name: 'B');
    final loadedAuthors = <String>[];
    Future<(List<Track>, String?)> loader(String artist, {int page = 1}) async {
      loadedAuthors.add(artist);
      return ([song(artist == 'a' ? '2' : '1', artist)], null);
    }

    final feed = TimelineFeed(authors: const [a], loadPage: loader);
    expect((await feed.take(1)).single.id, '2');

    final restored = TimelineFeed.fromJson(
      authors: const [a, b],
      loadPage: loader,
      json: jsonDecode(jsonEncode(feed.toJson())) as Map<String, dynamic>,
    );
    expect(restored.hasMore, true);
    expect((await restored.take(1)).single.id, '1');
    expect(loadedAuthors, ['a', 'b']);
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
