import 'package:flutter/foundation.dart';

import '../data/model/author.dart';
import '../data/model/track.dart';
import '../data/repository/local_db.dart';
import '../data/repository/ng_repository.dart';

class SubscriptionsImportResult {
  final int found;
  final int added;
  final int skipped;

  const SubscriptionsImportResult({
    required this.found,
    required this.added,
    required this.skipped,
  });
}

class AuthorsViewModel extends ChangeNotifier {
  final _db = LocalDb.instance;
  final _repo = NgRepository();
  final _authors = <String, Author>{};
  final _busy = <String>{};
  bool loaded = false;
  String? error;
  int revision = 0;

  AuthorsViewModel() {
    load();
  }

  List<Author> get subscriptions =>
      _authors.values.where((author) => author.subscribed).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<Author> get blockedAuthors =>
      _authors.values.where((author) => author.blocked).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Author stateOf(Author author) => _authors[author.username] ?? author;
  bool isBusy(Author author) => _busy.contains(author.username);

  bool isBlocked(Track track) =>
      _authors[Author.fromTrack(track).username]?.blocked == true ||
      _authors[Author.key(track.artist)]?.blocked == true;

  Future<void> load() async {
    try {
      final authors = await _db.getAuthors();
      _authors
        ..clear()
        ..addEntries(authors.map((a) => MapEntry(a.username, a)));
      loaded = true;
      error = null;
      revision++;
    } catch (_) {
      error = 'Could not load author preferences';
    }
    notifyListeners();
  }

  Future<void> setSubscribed(Author author, bool subscribed) =>
      _save(author, subscribed: subscribed);

  Future<void> setBlocked(Author author, bool blocked) =>
      _save(author, blocked: blocked);

  Future<void> _save(Author author, {bool? subscribed, bool? blocked}) async {
    if (!loaded || !_busy.add(author.username)) return;
    notifyListeners();
    try {
      final updated = stateOf(author).copyWith(
        subscribed: subscribed,
        blocked: blocked,
      );
      await _db.saveAuthor(updated);
      _authors[author.username] = updated;
      error = null;
      revision++;
    } catch (_) {
      error = 'Could not save author preferences';
      rethrow;
    } finally {
      _busy.remove(author.username);
      notifyListeners();
    }
  }

  /// Imports the public "Following" list of [username] into subscriptions.
  ///
  /// Existing subscriptions, blocked authors and duplicate entries are kept
  /// intact, so the import can be repeated safely.
  Future<SubscriptionsImportResult> importSubscriptions(String username) async {
    final name = Author.key(username.trim());
    if (name.isEmpty || name.contains('://')) {
      throw ArgumentError('Enter a Newgrounds username');
    }

    final found = <String, Author>{};
    final visitedPages = <String>{};
    String? nextUrl;
    var page = 1;
    while (page <= 20) {
      final (pageAuthors, pageNext) = await _repo.getFollowingPage(
        name,
        page: page,
        url: nextUrl,
      );
      for (final author in pageAuthors) {
        found.putIfAbsent(author.username, () => author);
      }
      if (pageNext == null || !visitedPages.add(pageNext)) break;
      nextUrl = pageNext;
      page++;
      // One page at a time, with a small pause to avoid stressing Newgrounds.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    if (found.isEmpty) {
      return const SubscriptionsImportResult(found: 0, added: 0, skipped: 0);
    }

    var added = 0;
    final toSave = <Author>[];
    for (final author in found.values) {
      final existing = _authors[author.username];
      if (existing?.subscribed != true) added++;
      toSave.add(Author(
        username: author.username,
        name: author.name,
        subscribed: true,
        blocked: existing?.blocked ?? false,
      ));
    }

    await _db.importSubscriptions(toSave);
    for (final author in toSave) {
      _authors[author.username] = author;
    }
    error = null;
    revision++;
    notifyListeners();

    return SubscriptionsImportResult(
      found: found.length,
      added: added,
      skipped: found.length - added,
    );
  }

  /// Clears subscriptions while keeping blocked authors blocked.
  Future<void> clearSubscriptions() async {
    await _db.clearSubscriptions();
    final remove = <String>[];
    for (final entry in _authors.entries.toList()) {
      final updated = entry.value.copyWith(subscribed: false);
      if (updated.blocked) {
        _authors[entry.key] = updated;
      } else {
        remove.add(entry.key);
      }
    }
    for (final key in remove) {
      _authors.remove(key);
    }
    error = null;
    revision++;
    notifyListeners();
  }
}
