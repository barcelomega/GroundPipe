import 'package:flutter_test/flutter_test.dart';
import 'package:ngmusic/data/repository/ng_repository.dart';

void main() {
  final repository = NgRepository();

  test('parses Newgrounds audio recommendations from the listen page', () {
    final tracks = repository.parseRecommendedTracks('''
      <div class="pod">
        <div class="pod-head"><h2>You might also enjoy...</h2></div>
        <div class="pod-body">
          <div class="audio-wrapper">
            <div class="item-audiosubmission-small">
              <a class="item-link" href="https://www.newgrounds.com/audio/listen/1631843" title="Midnight Fright">
                <div class="item-icon"><img src="https://aicon.ngfiles.com/1631/1631843.webp" alt="Midnight Fright"></div>
              </a>
              <div class="detail-genre">Song Cinematic</div>
            </div>
          </div>
        </div>
      </div>
    ''');

    expect(tracks, hasLength(1));
    expect(tracks.single.id, '1631843');
    expect(tracks.single.title, 'Midnight Fright');
    expect(tracks.single.genre, 'Cinematic');
    expect(
        tracks.single.iconUrl, 'https://aicon.ngfiles.com/1631/1631843.webp');
  });

  test('recommendation track cache serialization preserves card metadata', () {
    final tracks = repository.parseRecommendedTracks('''
      <div class="pod">
        <div class="pod-head"><h2>You might also enjoy...</h2></div>
        <div class="pod-body"><div class="audio-wrapper">
          <div class="item-audiosubmission-small">
            <a class="item-link" href="/audio/listen/987" title="Cached song">
              <div class="item-icon"><img src="https://aicon.ngfiles.com/0/987.webp"></div>
            </a>
            <div class="detail-genre">Song Ambient</div>
          </div>
        </div></div>
      </div>
    ''');
    final restored =
        NgRepository.trackFromJson(NgRepository.trackToJson(tracks.single));

    expect(restored.id, '987');
    expect(restored.title, 'Cached song');
    expect(restored.genre, 'Ambient');
    expect(restored.iconUrl, tracks.single.iconUrl);
  });

  test('returns no tracks if the recommendations section is absent', () {
    expect(
        repository
            .parseRecommendedTracks('<html><body>No suggestions</body></html>'),
        isEmpty);
  });

  test('detects Newgrounds rate limit even when HTML says access verified', () {
    expect(
      () => repository.throwIfRateLimitedForTest(
        '<html><body>Access verified! You\'re making too many requests. Wait a bit before trying again.</body></html>',
      ),
      throwsA(isA<NgRateLimitException>()),
    );
  });
}
