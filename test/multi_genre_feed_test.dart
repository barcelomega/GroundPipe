import 'package:flutter_test/flutter_test.dart';
import 'package:ngmusic/data/model/track.dart';
import 'package:ngmusic/data/repository/multi_genre_feed.dart';

Track song(
  String id, {
  String genre = 'a',
  String? score,
  String? listens,
}) =>
    Track(
      id: id,
      title: id,
      artist: genre,
      genre: genre,
      iconUrl: '',
      duration: 0,
      audioType: 3,
      score: score,
      listens: listens,
    );

void main() {
  test('date merge orders by ID and pages each genre lazily', () async {
    final requests = <String>[];
    final pages = <String, List<List<Track>>>{
      'a': [
        [song('10'), song('8')],
        [song('6'), song('4')],
      ],
      'b': [
        [song('9', genre: 'b'), song('7', genre: 'b')],
        [song('5', genre: 'b'), song('3', genre: 'b')],
      ],
    };
    final feed = MultiGenreFeed(
      genres: const ['a', 'b'],
      loadPage: (genre, offset) async {
        requests.add('$genre:$offset');
        final genrePages = pages[genre]!;
        final index = offset ~/ 2;
        return index < genrePages.length ? genrePages[index] : <Track>[];
      },
    );

    expect((await feed.take(3)).map((track) => track.id), ['10', '9', '8']);
    expect(requests, containsAll(['a:0', 'b:0']));
    expect((await feed.take(3)).map((track) => track.id), ['7', '6', '5']);
    expect(requests, containsAll(['a:2', 'b:2']));
    expect((await feed.take(3)).map((track) => track.id), ['4', '3']);
    expect(feed.hasMore, false);
  });

  test('score merge orders by score across genres', () async {
    final feed = MultiGenreFeed(
      genres: const ['a', 'b'],
      sort: GenreSort.score,
      loadPage: (genre, offset) async {
        if (offset > 0) return <Track>[];
        return genre == 'a'
            ? [
                song('3', score: '4.90'),
                song('2', score: '4.90'),
                song('1', score: '4.50'),
              ]
            : [
                song('4', genre: 'b', score: '4.70'),
                song('5', genre: 'b', score: '4.20'),
              ];
      },
    );

    expect((await feed.take(5)).map((track) => track.id), [
      '3',
      '2',
      '4',
      '1',
      '5',
    ]);
  });

  test('views merge orders by listen count', () async {
    final feed = MultiGenreFeed(
      genres: const ['a', 'b'],
      sort: GenreSort.views,
      loadPage: (genre, offset) async {
        if (offset > 0) return <Track>[];
        return genre == 'a'
            ? [
                song('1', listens: '1,200'),
                song('2', listens: '950'),
              ]
            : [
                song('3', genre: 'b', listens: '3,000'),
                song('4', genre: 'b', listens: '1.1K'),
              ];
      },
    );

    expect((await feed.take(4)).map((track) => track.id), [
      '3',
      '1',
      '4',
      '2',
    ]);
  });

  test('views merge falls back to ID when counts are unavailable', () async {
    final feed = MultiGenreFeed(
      genres: const ['a', 'b'],
      sort: GenreSort.views,
      loadPage: (genre, offset) async {
        if (offset > 0) return <Track>[];
        return genre == 'a'
            ? [song('2'), song('1')]
            : [song('4', genre: 'b'), song('3', genre: 'b')];
      },
    );

    expect((await feed.take(4)).map((track) => track.id), [
      '4',
      '3',
      '2',
      '1',
    ]);
  });
}
