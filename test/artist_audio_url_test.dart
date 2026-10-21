import 'package:flutter_test/flutter_test.dart';
import 'package:ngmusic/data/model/track.dart';

Track track({String? authorUrl}) => Track(
      id: '123',
      title: 'Track',
      artist: '8-BiTek',
      genre: '',
      iconUrl: '',
      duration: 0,
      audioType: 3,
      authorUrl: authorUrl,
    );

void main() {
  test('playlist tracks without author metadata link directly to artist audio',
      () {
    expect(track().artistAudioUrl, 'https://8-bitek.newgrounds.com/audio');
  });

  test('artist profile links always open the audio section', () {
    for (final url in [
      'https://author.newgrounds.com',
      '//author.newgrounds.com/news/post/123',
      'author.newgrounds.com/audio?page=2',
    ]) {
      expect(track(authorUrl: url).artistAudioUrl,
          'https://author.newgrounds.com/audio');
    }
  });

  test(
      'submission link accidentally parsed as author falls back to artist name',
      () {
    expect(
      track(authorUrl: 'https://www.newgrounds.com/audio/listen/123')
          .artistAudioUrl,
      'https://8-bitek.newgrounds.com/audio',
    );
  });
}
