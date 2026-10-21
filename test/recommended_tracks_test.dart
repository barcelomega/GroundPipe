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

  test('returns no tracks if the recommendations section is absent', () {
    expect(
        repository
            .parseRecommendedTracks('<html><body>No suggestions</body></html>'),
        isEmpty);
  });
}
