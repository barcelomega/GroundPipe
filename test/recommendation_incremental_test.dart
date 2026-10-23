import 'package:flutter_test/flutter_test.dart';
import 'package:ngmusic/viewmodel/recommendations_viewmodel.dart';

void main() {
  test('new favorites before the first known ID are collected', () {
    final known = {'3', '4'};

    final scan = RecommendationsViewModel.scanFavoritePage(
      ['1', '2', '3', '4'],
      known,
    );

    expect(scan.added, ['1', '2']);
    expect(scan.reachedOld, isTrue);
    expect(known, {'1', '2', '3', '4'});
  });

  test('a page without known IDs keeps scanning the next page', () {
    final known = {'9'};

    final scan = RecommendationsViewModel.scanFavoritePage(
      ['1', '2'],
      known,
    );

    expect(scan.added, ['1', '2']);
    expect(scan.reachedOld, isFalse);
  });

  test('a re-fave above newer tracks does not hide them', () {
    final known = {'1'};

    final scan = RecommendationsViewModel.scanFavoritePage(
      ['1', '2'],
      known,
    );

    expect(scan.added, ['2']);
    expect(scan.reachedOld, isTrue);
  });

  test('an unchanged page adds nothing', () {
    final known = {'1', '2'};

    final scan = RecommendationsViewModel.scanFavoritePage(
      ['1', '2'],
      known,
    );

    expect(scan.added, isEmpty);
    expect(scan.reachedOld, isTrue);
  });
}
