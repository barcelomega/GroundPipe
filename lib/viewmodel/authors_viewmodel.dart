import 'package:flutter/foundation.dart';

import '../data/model/author.dart';
import '../data/model/track.dart';
import '../data/repository/local_db.dart';

class AuthorsViewModel extends ChangeNotifier {
  final _db = LocalDb.instance;
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
}
