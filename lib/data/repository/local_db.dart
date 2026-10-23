import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../model/playlist.dart';
import '../model/track.dart';
import '../model/author.dart';

class LocalDb {
  /// Timeline keeps the first page of artwork in the permanent store. Older
  /// entries are loaded from the network when the user scrolls further.
  static const int timelineArtworkCacheLimit = 25;

  /// Likes are shown 50 at a time. Only this first page is kept in the
  /// permanent artwork store; the rest use the normal lazy artwork cache.
  static const int likesPageSize = 50;

  /// Per-author recommendation cache is capped at the newest 500 favorites.
  static const int recommendationFavoriteLimit = 500;

  static LocalDb? _instance;
  static LocalDb get instance => _instance ??= LocalDb._();
  LocalDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'ngmusic.db');
    return openDatabase(
      path,
      version: 20,
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          await db.execute('''
            DELETE FROM playlists
            WHERE ng_id IS NOT NULL AND id NOT IN (
              SELECT MIN(id) FROM playlists WHERE ng_id IS NOT NULL GROUP BY ng_id
            )
          ''');
          await db.execute('''
            DELETE FROM playlist_tracks
            WHERE playlist_id NOT IN (SELECT id FROM playlists)
          ''');
          await db.execute(_ngIdIndex);
        }
        if (from < 3) {
          await db.execute(
              'ALTER TABLE favorites ADD COLUMN is_ng INTEGER NOT NULL DEFAULT 0');
        }
        if (from < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS blacklisted_tracks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_id TEXT NOT NULL UNIQUE,
              blacklisted_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS staged_likes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_id TEXT NOT NULL UNIQUE,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              icon_url TEXT NOT NULL,
              duration INTEGER DEFAULT 0,
              genre TEXT,
              liked_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS cached_tracks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_id TEXT NOT NULL UNIQUE,
              local_path TEXT NOT NULL,
              cached_at INTEGER NOT NULL,
              size INTEGER DEFAULT 0
            )
          ''');
        }
        if (from < 5) {
          // Add position column if it doesn't exist
          await db.execute('''
            ALTER TABLE playlist_tracks ADD COLUMN position INTEGER DEFAULT 0
          ''').catchError((_) {
            // Column already exists, ignore error
          });
        }
        if (from < 6) {
          // Extend cached_tracks with full metadata
          await db.execute('DROP TABLE IF EXISTS cached_tracks');
          await db.execute('''
            CREATE TABLE cached_tracks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_id TEXT NOT NULL UNIQUE,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              genre TEXT,
              icon_url TEXT NOT NULL,
              duration INTEGER DEFAULT 0,
              audio_type INTEGER DEFAULT 3,
              score TEXT,
              author_url TEXT,
              local_path TEXT NOT NULL,
              cached_at INTEGER NOT NULL,
              size INTEGER DEFAULT 0
            )
          ''');
        }
        if (from < 7) {
          // Extend blacklisted_tracks with just title
          await db.execute('DROP TABLE IF EXISTS blacklisted_tracks');
          await db.execute('''
            CREATE TABLE blacklisted_tracks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_id TEXT NOT NULL UNIQUE,
              title TEXT,
              blacklisted_at INTEGER NOT NULL
            )
          ''');
        }
        if (from < 8) {
          // Version 7 fresh installs still used the original cache schema.
          final columns = await db.rawQuery('PRAGMA table_info(cached_tracks)');
          final names = columns.map((row) => row['name']).toSet();
          const metadata = {
            'title': "TEXT NOT NULL DEFAULT ''",
            'artist': "TEXT NOT NULL DEFAULT ''",
            'genre': 'TEXT',
            'icon_url': "TEXT NOT NULL DEFAULT ''",
            'duration': 'INTEGER DEFAULT 0',
            'audio_type': 'INTEGER DEFAULT 3',
            'score': 'TEXT',
            'author_url': 'TEXT',
          };
          for (final column in metadata.entries) {
            if (!names.contains(column.key)) {
              await db.execute(
                'ALTER TABLE cached_tracks ADD COLUMN ${column.key} ${column.value}',
              );
            }
          }
        }
        if (from < 9) {
          await db.execute(_authorPreferencesTable);
        }
        if (from < 10) {
          await db.execute(_trackGenresTable);
        }
        if (from < 11) {
          // Add title column to blacklisted_tracks for v10 fresh installs
          await db.execute('''
            ALTER TABLE blacklisted_tracks ADD COLUMN title TEXT
          ''').catchError((_) {
            // Column already exists, ignore
          });
        }
        if (from < 12) {
          final columns = await db.rawQuery('PRAGMA table_info(staged_likes)');
          if (!columns.any((row) => row['name'] == 'author_url')) {
            await db
                .execute('ALTER TABLE staged_likes ADD COLUMN author_url TEXT');
          }
          await db.execute(_recommendationFavoritesTable);
          await db.execute(_recommendationAuthorStateTable);
          await db.execute(_recommendationScoresTable);
        }
        if (from < 13) {
          final columns =
              await db.rawQuery('PRAGMA table_info(playlist_tracks)');
          if (!columns.any((row) => row['name'] == 'author_url')) {
            await db.execute(
                'ALTER TABLE playlist_tracks ADD COLUMN author_url TEXT');
          }
        }
        if (from < 14) {
          await db.execute(_trackRecommendationsTable);
        }
        if (from < 15) await db.execute(_recommendationSourceScoresTable);
        if (from < 16) await db.execute(_recommendationSourceStateTable);
        if (from < 17) await db.execute(_timelineCacheTable);
        if (from < 18) await db.execute(_recommendationCardsTable);
        if (from < 19) {
          final columns = await db
              .rawQuery('PRAGMA table_info(recommendation_author_state)');
          if (!columns.any((row) => row['name'] == 'favorite_count')) {
            await db.execute(
              'ALTER TABLE recommendation_author_state '
              'ADD COLUMN favorite_count INTEGER',
            );
          }
        }
        if (from < 20) {
          final columns = await db
              .rawQuery('PRAGMA table_info(recommendation_author_favorites)');
          if (!columns.any((row) => row['name'] == 'favorite_rank')) {
            await db.execute(
              'ALTER TABLE recommendation_author_favorites '
              'ADD COLUMN favorite_rank INTEGER NOT NULL DEFAULT 0',
            );
          }
          // Existing rows were inserted page by page from newest to oldest,
          // so their rowid already reflects the favorite order.
          await db.execute(
            'UPDATE recommendation_author_favorites '
            'SET favorite_rank = rowid WHERE favorite_rank = 0',
          );
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT,
            created_at INTEGER NOT NULL,
            ng_id TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE playlist_tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            playlist_id INTEGER NOT NULL,
            track_id TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            author_url TEXT,
            icon_url TEXT NOT NULL,
            duration INTEGER DEFAULT 0,
            genre TEXT,
            mp3_url TEXT,
            position INTEGER DEFAULT 0,
            added_at INTEGER NOT NULL,
            FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
            UNIQUE (playlist_id, track_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE favorites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            icon_url TEXT NOT NULL,
            duration INTEGER DEFAULT 0,
            genre TEXT,
            added_at INTEGER NOT NULL,
            is_ng INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE blacklisted_tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL UNIQUE,
            title TEXT,
            blacklisted_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE staged_likes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            author_url TEXT,
            icon_url TEXT NOT NULL,
            duration INTEGER DEFAULT 0,
            genre TEXT,
            liked_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            genre TEXT,
            icon_url TEXT NOT NULL,
            duration INTEGER DEFAULT 0,
            audio_type INTEGER DEFAULT 3,
            score TEXT,
            author_url TEXT,
            local_path TEXT NOT NULL,
            cached_at INTEGER NOT NULL,
            size INTEGER DEFAULT 0
          )
        ''');
        await db.execute(_ngIdIndex);
        await db.execute(_authorPreferencesTable);
        await db.execute(_trackGenresTable);
        await db.execute(_recommendationFavoritesTable);
        await db.execute(_recommendationAuthorStateTable);
        await db.execute(_recommendationScoresTable);
        await db.execute(_trackRecommendationsTable);
        await db.execute(_recommendationSourceScoresTable);
        await db.execute(_recommendationSourceStateTable);
        await db.execute(_timelineCacheTable);
        await db.execute(_recommendationCardsTable);
      },
    );
  }

  static const _ngIdIndex =
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_playlists_ng_id '
      'ON playlists(ng_id)';

  static const _authorPreferencesTable = '''
    CREATE TABLE IF NOT EXISTS author_preferences (
      username TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      subscribed INTEGER NOT NULL DEFAULT 0,
      blocked INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const _trackGenresTable = '''
    CREATE TABLE IF NOT EXISTS track_genres (
      track_id TEXT PRIMARY KEY,
      genre TEXT NOT NULL
    )
  ''';

  static const _recommendationFavoritesTable = '''
    CREATE TABLE IF NOT EXISTS recommendation_author_favorites (
      username TEXT NOT NULL,
      track_id TEXT NOT NULL,
      favorite_rank INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (username, track_id)
    )
  ''';

  static const _recommendationScoresTable = '''
    CREATE TABLE IF NOT EXISTS recommendation_track_scores (
      track_id TEXT PRIMARY KEY,
      score REAL NOT NULL
    )
  ''';

  static const _recommendationAuthorStateTable = '''
    CREATE TABLE IF NOT EXISTS recommendation_author_state (
      username TEXT PRIMARY KEY,
      next_url TEXT,
      complete INTEGER NOT NULL DEFAULT 0,
      favorite_count INTEGER
    )
  ''';

  static const _maxTrackRecommendationSets = 15;

  static const _trackRecommendationsTable = '''
    CREATE TABLE IF NOT EXISTS track_recommendations (
      track_id TEXT PRIMARY KEY,
      tracks_json TEXT NOT NULL,
      fetched_at INTEGER NOT NULL
    )
  ''';

  static const _recommendationSourceScoresTable = '''
    CREATE TABLE IF NOT EXISTS recommendation_source_scores (
      source TEXT NOT NULL,
      track_id TEXT NOT NULL,
      score REAL NOT NULL,
      PRIMARY KEY (source, track_id)
    )
  ''';

  static const _recommendationSourceStateTable = '''
    CREATE TABLE IF NOT EXISTS recommendation_source_state (
      source TEXT PRIMARY KEY,
      fingerprint TEXT NOT NULL
    )
  ''';

  static const _timelineCacheTable = '''
    CREATE TABLE IF NOT EXISTS timeline_cache (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      fingerprint TEXT NOT NULL,
      feed_json TEXT NOT NULL
    )
  ''';

  static const _recommendationCardsTable = '''
    CREATE TABLE IF NOT EXISTS recommendation_cards (
      source TEXT NOT NULL,
      track_id TEXT NOT NULL,
      track_json TEXT NOT NULL,
      PRIMARY KEY (source, track_id)
    )
  ''';

  Future<(String, String)?> getTimelineCache() async {
    final d = await db;
    final rows = await d.query('timeline_cache', where: 'id = 1');
    if (rows.isEmpty) return null;
    return (
      rows.first['fingerprint'] as String,
      rows.first['feed_json'] as String
    );
  }

  Future<void> saveTimelineCache(String fingerprint, String json) async {
    final d = await db;
    await d.insert(
        'timeline_cache',
        {
          'id': 1,
          'fingerprint': fingerprint,
          'feed_json': json,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearTimelineCache() async {
    final d = await db;
    await d.delete('timeline_cache');
  }

  Future<String?> getRecommendationSourceFingerprint(String source) async {
    final d = await db;
    final rows = await d.query('recommendation_source_state',
        columns: ['fingerprint'], where: 'source = ?', whereArgs: [source]);
    return rows.isEmpty ? null : rows.first['fingerprint'] as String;
  }

  Future<void> setRecommendationSourceFingerprint(
      String source, String fingerprint) async {
    final d = await db;
    await d.insert(
        'recommendation_source_state',
        {
          'source': source,
          'fingerprint': fingerprint,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getTrackRecommendations(String trackId) async {
    final d = await db;
    final rows = await d.query(
      'track_recommendations',
      columns: ['tracks_json'],
      where: 'track_id = ?',
      whereArgs: [trackId],
    );
    if (rows.isNotEmpty) {
      await d.update(
        'track_recommendations',
        {'fetched_at': DateTime.now().millisecondsSinceEpoch},
        where: 'track_id = ?',
        whereArgs: [trackId],
      );
    }
    await d.rawDelete('''
      DELETE FROM track_recommendations
      WHERE track_id NOT IN (
        SELECT track_id FROM track_recommendations
        ORDER BY fetched_at DESC LIMIT $_maxTrackRecommendationSets
      )
    ''');
    return rows.isEmpty ? null : rows.first['tracks_json'] as String;
  }

  Future<void> saveTrackRecommendations(String trackId, String json) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.insert(
          'track_recommendations',
          {
            'track_id': trackId,
            'tracks_json': json,
            'fetched_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawDelete('''
        DELETE FROM track_recommendations
        WHERE track_id NOT IN (
          SELECT track_id FROM track_recommendations
          ORDER BY fetched_at DESC LIMIT $_maxTrackRecommendationSets
        )
      ''');
    });
  }

  Future<Set<String>> getRecommendationCardTrackIds() async {
    final d = await db;
    final rows = await d.query('recommendation_cards', columns: ['track_id']);
    return rows.map((row) => row['track_id'] as String).toSet();
  }

  Future<Set<String>> getCachedTrackIds() async {
    final d = await db;
    final rows = await d.query('cached_tracks', columns: ['track_id']);
    return rows.map((row) => row['track_id'] as String).toSet();
  }

  Future<Set<String>> getPersistentArtworkTrackIds() async {
    final d = await db;
    final ids = <String>{};
    // Only the first page of Likes is durable for artwork purposes.
    final likeRows = await d.query(
      'staged_likes',
      columns: ['track_id'],
      orderBy: 'liked_at DESC',
      limit: likesPageSize,
    );
    ids.addAll(likeRows.map((row) => row['track_id'] as String));
    for (final table in [
      'playlist_tracks',
      'recommendation_cards',
    ]) {
      final rows = await d.query(table, columns: ['track_id']);
      ids.addAll(rows.map((row) => row['track_id'] as String));
    }
    ids.addAll(await getRecentRecommendationArtworkIds());
    final timeline = await getTimelineCache();
    if (timeline != null) {
      try {
        final feed = jsonDecode(timeline.$2) as Map<String, dynamic>;
        final emitted = (feed['emitted'] as List? ?? const []);
        for (final track in emitted.take(timelineArtworkCacheLimit)) {
          if (track is Map && track['id'] is String) {
            ids.add(track['id'] as String);
          }
        }
      } catch (_) {}
    }
    return ids;
  }

  Future<Set<String>> getRecommendationSourcesInUse() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT DISTINCT source FROM recommendation_source_scores',
    );
    return rows.map((row) => row['source'] as String).toSet();
  }

  Future<void> pruneRecommendationCards(
      String source, Set<String> keepIds) async {
    final d = await db;
    await d.transaction((txn) async {
      if (keepIds.isEmpty) {
        await txn.delete('recommendation_cards',
            where: 'source = ?', whereArgs: [source]);
        return;
      }
      final placeholders = List.filled(keepIds.length, '?').join(',');
      await txn.delete(
        'recommendation_cards',
        where: 'source = ? AND track_id NOT IN ($placeholders)',
        whereArgs: [source, ...keepIds],
      );
    });
  }

  Future<void> pruneCardsWithoutRecommendationScores() async {
    final d = await db;
    await d.rawDelete('''
      DELETE FROM recommendation_cards
      WHERE NOT EXISTS (
        SELECT 1 FROM recommendation_source_scores AS scores
        WHERE scores.source = recommendation_cards.source
          AND scores.track_id = recommendation_cards.track_id
      )
    ''');
  }

  Future<void> pruneTrackRecommendationsToRecentSets() async {
    final d = await db;
    await d.rawDelete('''
      DELETE FROM track_recommendations
      WHERE track_id NOT IN (
        SELECT track_id FROM track_recommendations
        ORDER BY fetched_at DESC LIMIT $_maxTrackRecommendationSets
      )
    ''');
  }

  Future<Set<String>> getRecentRecommendationArtworkIds() async {
    final d = await db;
    final rows = await d.query(
      'track_recommendations',
      columns: ['tracks_json'],
      orderBy: 'fetched_at DESC',
      limit: _maxTrackRecommendationSets,
    );
    final ids = <String>{};
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['tracks_json'] as String);
        if (decoded is! List) continue;
        for (final track in decoded.whereType<Map>()) {
          final id = track['id'];
          if (id is String && id.isNotEmpty) ids.add(id);
        }
      } catch (_) {}
    }
    return ids;
  }

  Future<void> pruneRecommendationAuthors(Set<String> usedAuthorKeys) async {
    final d = await db;
    await d.transaction((txn) async {
      final rows =
          await txn.query('recommendation_author_state', columns: ['username']);
      for (final row in rows) {
        final username = row['username'] as String;
        if (usedAuthorKeys.contains(username)) continue;
        await txn.delete('recommendation_author_favorites',
            where: 'username = ?', whereArgs: [username]);
        await txn.delete('recommendation_author_state',
            where: 'username = ?', whereArgs: [username]);
      }
    });
  }

  Future<Map<String, String>> getRecommendationCards(String source) async {
    final d = await db;
    final rows = await d.query('recommendation_cards',
        columns: ['track_id', 'track_json'],
        where: 'source = ?',
        whereArgs: [source]);
    return {
      for (final row in rows)
        row['track_id'] as String: row['track_json'] as String
    };
  }

  Future<void> saveRecommendationCards(
      String source, Map<String, String> trackJsonById) async {
    final d = await db;
    await d.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in trackJsonById.entries) {
        batch.insert(
          'recommendation_cards',
          {
            'source': source,
            'track_id': entry.key,
            'track_json': entry.value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> clearRecommendationCards(String source) async {
    final d = await db;
    await d.delete('recommendation_cards',
        where: 'source = ?', whereArgs: [source]);
  }

  Future<String?> getTrackGenre(String id) async {
    final d = await db;
    final rows =
        await d.query('track_genres', where: 'track_id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first['genre'] as String;
  }

  Future<void> saveTrackGenre(String id, String genre) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.insert('track_genres', {'track_id': id, 'genre': genre},
          conflictAlgorithm: ConflictAlgorithm.replace);
      for (final table in [
        'playlist_tracks',
        'staged_likes',
        'cached_tracks',
        'favorites'
      ]) {
        await txn.update(table, {'genre': genre},
            where: 'track_id = ?', whereArgs: [id]);
      }
      await txn.rawDelete('''
        DELETE FROM track_genres
        WHERE track_id NOT IN (
          SELECT track_id FROM track_genres
          ORDER BY rowid DESC LIMIT 5000
        )
      ''');
    });
  }

  Future<List<Author>> getAuthors() async {
    final d = await db;
    final rows =
        await d.query('author_preferences', orderBy: 'name COLLATE NOCASE');
    return rows.map(Author.fromMap).toList();
  }

  Future<void> saveAuthor(Author author) async {
    final d = await db;
    await d.insert(
        'author_preferences',
        {
          'username': author.username,
          'name': author.name,
          'subscribed': author.subscribed ? 1 : 0,
          'blocked': author.blocked ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Subscribes imported authors without dropping their blocked flag.
  Future<void> importSubscriptions(List<Author> authors) async {
    if (authors.isEmpty) return;
    final d = await db;
    await d.transaction((txn) async {
      for (final author in authors) {
        final existing = await txn.query(
          'author_preferences',
          columns: ['username'],
          where: 'username = ?',
          whereArgs: [author.username],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('author_preferences', {
            'username': author.username,
            'name': author.name,
            'subscribed': 1,
            'blocked': 0,
          });
        } else {
          await txn.update(
            'author_preferences',
            {'name': author.name, 'subscribed': 1},
            where: 'username = ?',
            whereArgs: [author.username],
          );
        }
      }
    });
  }

  /// Removes every subscription while keeping blocked authors blocked.
  Future<void> clearSubscriptions() async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.update('author_preferences', {'subscribed': 0});
      await txn.delete(
        'author_preferences',
        where: 'subscribed = 0 AND blocked = 0',
      );
    });
  }

  Future<List<String>> getRecommendationFavoriteIds(String username) async {
    final d = await db;
    final rows = await d.query(
      'recommendation_author_favorites',
      columns: ['track_id'],
      where: 'username = ?',
      whereArgs: [username],
      orderBy: 'favorite_rank ASC, track_id ASC',
    );
    return rows.map((row) => row['track_id'] as String).toList();
  }

  Future<(String?, bool)> getRecommendationAuthorState(String username) async {
    final d = await db;
    final rows = await d.query('recommendation_author_state',
        where: 'username = ?', whereArgs: [username], limit: 1);
    if (rows.isEmpty) return (null, false);
    return (rows.first['next_url'] as String?, rows.first['complete'] == 1);
  }

  Future<int?> getRecommendationAuthorFavoriteCount(String username) async {
    final d = await db;
    final rows = await d.query('recommendation_author_state',
        columns: ['favorite_count'],
        where: 'username = ?',
        whereArgs: [username],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['favorite_count'] as int?;
  }

  Future<void> setRecommendationAuthorFavoriteCount(
      String username, int count) async {
    final d = await db;
    final updated = await d.update(
      'recommendation_author_state',
      {'favorite_count': count},
      where: 'username = ?',
      whereArgs: [username],
    );
    if (updated == 0) {
      await d.insert(
        'recommendation_author_state',
        {
          'username': username,
          'next_url': null,
          'complete': 0,
          'favorite_count': count,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> saveRecommendationFavoritePage(
      String username, List<String> trackIds,
      {required String? nextUrl}) async {
    await commitRecommendationFavoritePage(
      username,
      trackIds: trackIds,
      nextUrl: nextUrl,
    );
  }

  Future<void> updateRecommendationAuthorState(String username,
      {required String? nextUrl}) async {
    final d = await db;
    await d.insert(
        'recommendation_author_state',
        {
          'username': username,
          'next_url': nextUrl,
          'complete': nextUrl == null ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> addRecommendationFavoriteIds(
      String username, List<String> trackIds) async {
    await prependRecommendationFavoriteIds(username, trackIds);
  }

  Future<void> mergeRecommendationFavoritePage(
      String username, List<String> trackIds,
      {required String? nextUrl}) async {
    await commitRecommendationFavoritePage(
      username,
      trackIds: trackIds,
      nextUrl: nextUrl,
    );
  }

  Future<void> commitRecommendationFavoritePage(String username,
      {required List<String> trackIds,
      required String? nextUrl,
      int? favoriteCount}) async {
    final d = await db;
    await d.transaction((txn) async {
      final existing = await txn.query(
        'recommendation_author_state',
        columns: ['favorite_count'],
        where: 'username = ?',
        whereArgs: [username],
        limit: 1,
      );
      final storedCount =
          existing.isEmpty ? null : existing.first['favorite_count'] as int?;

      // Pages arrive newest-first. New rows are appended after the current
      // newest block, so the next page (older favorites) gets a higher rank.
      final maxRows = await txn.rawQuery(
        'SELECT MAX(favorite_rank) AS max_rank '
        'FROM recommendation_author_favorites WHERE username = ?',
        [username],
      );
      var rank = (maxRows.first['max_rank'] as int? ?? 0) + 1;

      final unique = _uniqueIds(trackIds);
      final batch = txn.batch();
      for (final trackId in unique) {
        batch.insert(
            'recommendation_author_favorites',
            {
              'username': username,
              'track_id': trackId,
              'favorite_rank': rank++,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      batch.insert(
          'recommendation_author_state',
          {
            'username': username,
            'next_url': nextUrl,
            'complete': nextUrl == null ? 1 : 0,
            'favorite_count': favoriteCount ?? storedCount,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
      await _trimRecommendationFavorites(txn, username);
    });
  }

  /// Adds newly discovered favorites ahead of every cached favorite.
  ///
  /// [trackIds] must be in page order (newest first). The whole block is
  /// placed below the current minimum rank, preserving the favorite order.
  Future<void> prependRecommendationFavoriteIds(
      String username, List<String> trackIds) async {
    final unique = _uniqueIds(trackIds);
    if (unique.isEmpty) return;
    final d = await db;
    await d.transaction((txn) async {
      final minRows = await txn.rawQuery(
        'SELECT MIN(favorite_rank) AS min_rank '
        'FROM recommendation_author_favorites WHERE username = ?',
        [username],
      );
      final minRank = minRows.first['min_rank'] as int?;
      var rank = minRank == null ? 1 : minRank - unique.length;
      final batch = txn.batch();
      for (final trackId in unique) {
        batch.insert(
            'recommendation_author_favorites',
            {
              'username': username,
              'track_id': trackId,
              'favorite_rank': rank++,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
      await _trimRecommendationFavorites(txn, username);
    });
  }

  List<String> _uniqueIds(Iterable<String> ids) {
    final seen = <String>{};
    return [
      for (final id in ids)
        if (seen.add(id)) id,
    ];
  }

  Future<void> _trimRecommendationFavorites(
      Transaction txn, String username) async {
    await txn.rawDelete(
      '''
      DELETE FROM recommendation_author_favorites
      WHERE username = ?
        AND track_id NOT IN (
          SELECT track_id FROM recommendation_author_favorites
          WHERE username = ?
          ORDER BY favorite_rank ASC, track_id ASC
          LIMIT ?
        )
      ''',
      [username, username, recommendationFavoriteLimit],
    );
  }

  Future<void> resetRecommendationSource(String source) async {
    final d = await db;
    await d.delete('recommendation_source_scores',
        where: 'source = ?', whereArgs: [source]);
  }

  Future<void> resetIncompleteRecommendationAuthors() async {
    final d = await db;
    await d.transaction((txn) async {
      final rows = await txn.query('recommendation_author_state',
          columns: ['username'],
          where: 'complete = 0 AND username NOT LIKE ?',
          whereArgs: ['%:%']);
      for (final row in rows) {
        final username = row['username'] as String;
        await txn.delete('recommendation_author_favorites',
            where: 'username = ?', whereArgs: [username]);
        await txn.delete('recommendation_author_state',
            where: 'username = ?', whereArgs: [username]);
      }
    });
  }

  Future<void> removeRecommendationAuthors(Iterable<String> usernames) async {
    final d = await db;
    await d.transaction((txn) async {
      for (final username in usernames) {
        await txn.delete('recommendation_author_favorites',
            where: 'username = ?', whereArgs: [username]);
        await txn.delete('recommendation_author_state',
            where: 'username = ?', whereArgs: [username]);
      }
    });
  }

  Future<void> removeRecommendationAuthorsAndRebuild(
      Iterable<String> usernames, Map<String, double> authorWeights,
      {String source = 'likes'}) async {
    final d = await db;
    await d.transaction((txn) async {
      for (final username in usernames) {
        await txn.delete('recommendation_author_favorites',
            where: 'username = ?', whereArgs: [username]);
        await txn.delete('recommendation_author_state',
            where: 'username = ?', whereArgs: [username]);
      }
      await txn.delete('recommendation_source_scores',
          where: 'source = ?', whereArgs: [source]);
      if (authorWeights.isEmpty) return;
      final rows = <Map<String, Object?>>[];
      for (final username in authorWeights.keys) {
        rows.addAll(await txn.query('recommendation_author_favorites',
            where: 'username = ?', whereArgs: [username]));
      }
      final scores = <String, double>{};
      for (final row in rows) {
        final weight = authorWeights[row['username'] as String];
        if (weight == null || weight <= 0) continue;
        final id = row['track_id'] as String;
        scores.update(id, (score) => score + weight, ifAbsent: () => weight);
      }
      final batch = txn.batch();
      for (final entry in scores.entries) {
        batch.insert('recommendation_source_scores', {
          'source': source,
          'track_id': entry.key,
          'score': entry.value,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> resetIncompleteRecommendationSourceAuthors(String source) async {
    final d = await db;
    final rows = await d.query('recommendation_author_state',
        columns: ['username'],
        where: 'complete = 0 AND username LIKE ?',
        whereArgs: ['$source:%']);
    for (final row in rows) {
      final username = row['username'] as String;
      await d.delete('recommendation_author_favorites',
          where: 'username = ?', whereArgs: [username]);
      await d.delete('recommendation_author_state',
          where: 'username = ?', whereArgs: [username]);
    }
  }

  Future<void> saveRecommendationFavoriteIds(
      String username, List<String> trackIds) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('recommendation_author_favorites',
          where: 'username = ?', whereArgs: [username]);
      final batch = txn.batch();
      var rank = 1;
      for (final trackId in _uniqueIds(trackIds)) {
        batch.insert('recommendation_author_favorites', {
          'username': username,
          'track_id': trackId,
          'favorite_rank': rank++,
        });
      }
      await batch.commit(noResult: true);
      await _trimRecommendationFavorites(txn, username);
    });
  }

  Future<void> rebuildRecommendationScores(Map<String, double> authorWeights,
      {String source = 'likes'}) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('recommendation_source_scores',
          where: 'source = ?', whereArgs: [source]);
      if (authorWeights.isEmpty) return;
      final rows = <Map<String, Object?>>[];
      for (final username in authorWeights.keys) {
        rows.addAll(await txn.query('recommendation_author_favorites',
            where: 'username = ?', whereArgs: [username]));
      }
      final scores = <String, double>{};
      for (final row in rows) {
        final weight = authorWeights[row['username'] as String];
        if (weight == null || weight <= 0) continue;
        final trackId = row['track_id'] as String;
        scores.update(trackId, (score) => score + weight,
            ifAbsent: () => weight);
      }
      final batch = txn.batch();
      for (final entry in scores.entries) {
        batch.insert('recommendation_source_scores', {
          'source': source,
          'track_id': entry.key,
          'score': entry.value,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getRecommendationScores(
      {int limit = 200, int offset = 0, String source = 'likes'}) async {
    final d = await db;
    return d.query('recommendation_source_scores',
        where: 'source = ?',
        whereArgs: [source],
        orderBy: 'score DESC, track_id DESC',
        limit: limit,
        offset: offset);
  }

  Future<List<Playlist>> getPlaylists() async {
    final d = await db;
    final rows = await d.query('playlists', orderBy: 'created_at DESC');
    return rows.map(Playlist.fromMap).toList();
  }

  Future<Playlist> createPlaylist(String name, {String? description}) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = Playlist(name: name, description: description, createdAt: now);
    final id = await d.insert('playlists', p.toMap());
    return p.copyWith(id: id);
  }

  Future<Playlist> createPlaylistWithNgId(String name,
      {required String ngId}) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = Playlist(name: name, createdAt: now, ngId: ngId);
    final id = await d.insert('playlists', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != 0) return p.copyWith(id: id);
    final rows = await d.query('playlists',
        where: 'ng_id = ?', whereArgs: [ngId], limit: 1);
    if (rows.isEmpty) return p;
    return Playlist.fromMap(rows.first);
  }

  Future<void> renamePlaylist(int id, String name) async {
    final d = await db;
    await d.update('playlists', {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePlaylist(int id) async {
    final d = await db;
    final recommendationSource = 'playlist_$id';
    final authorPrefix = '$recommendationSource:';
    await d.transaction((txn) async {
      final authorRows = await txn.query(
        'recommendation_author_state',
        columns: ['username'],
        where: 'substr(username, 1, ?) = ?',
        whereArgs: [authorPrefix.length, authorPrefix],
      );
      for (final row in authorRows) {
        final username = row['username'] as String;
        await txn.delete('recommendation_author_favorites',
            where: 'username = ?', whereArgs: [username]);
        await txn.delete('recommendation_author_state',
            where: 'username = ?', whereArgs: [username]);
      }
      await txn.delete('recommendation_source_scores',
          where: 'source = ?', whereArgs: [recommendationSource]);
      await txn.delete('recommendation_cards',
          where: 'source = ?', whereArgs: [recommendationSource]);
      await txn.delete('recommendation_source_state',
          where: 'source = ?', whereArgs: [recommendationSource]);
      await txn.rawDelete('''
        DELETE FROM recommendation_cards
        WHERE NOT EXISTS (
          SELECT 1 FROM recommendation_source_scores AS scores
          WHERE scores.source = recommendation_cards.source
            AND scores.track_id = recommendation_cards.track_id
        )
      ''');
      await txn
          .delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [id]);
      await txn.delete('playlists', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<PlaylistTrack>> getPlaylistTracks(int playlistId) async {
    final d = await db;
    final rows = await d.query(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC, added_at ASC',
    );
    return rows.map(PlaylistTrack.fromMap).toList();
  }

  Future<Set<String>> getAllPlaylistTrackIds() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT DISTINCT track_id FROM playlist_tracks',
    );
    return rows.map((row) => row['track_id'] as String).toSet();
  }

  Future<int> trackCountForPlaylist(int playlistId) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) as c FROM playlist_tracks WHERE playlist_id = ?',
        [playlistId]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<bool> isTrackInPlaylist(int playlistId, String trackId) async {
    final d = await db;
    final r = await d.query(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<void> addTrackToPlaylist(int playlistId, Track track) async {
    final d = await db;
    await d.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
        'FROM playlist_tracks WHERE playlist_id = ?',
        [playlistId],
      );
      final position = rows.first['next_position'] as int;
      final pt = PlaylistTrack(
        playlistId: playlistId,
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        authorUrl: track.authorUrl,
        iconUrl: track.iconUrl,
        duration: track.duration,
        genre: track.genre.isEmpty ? null : track.genre,
        mp3Url: track.mp3Url,
        position: position,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await txn.insert('playlist_tracks', pt.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<void> removeTrackFromPlaylist(int playlistId, String trackId) async {
    final d = await db;
    await d.delete(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
    );
  }

  Future<void> reorderPlaylistTracks(
      int playlistId, List<String> trackIds) async {
    final d = await db;
    await d.transaction((txn) async {
      for (var i = 0; i < trackIds.length; i++) {
        await txn.update(
          'playlist_tracks',
          {'position': i},
          where: 'playlist_id = ? AND track_id = ?',
          whereArgs: [playlistId, trackIds[i]],
        );
      }
    });
  }

  Future<List<Favorite>> getFavorites() async {
    final d = await db;
    final rows = await d.query('favorites', orderBy: 'added_at DESC');
    return rows.map(Favorite.fromMap).toList();
  }

  Future<bool> isFavorite(String trackId) async {
    final d = await db;
    final r = await d.query(
      'favorites',
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<void> addFavorite(Track track, {bool isNg = false}) async {
    final d = await db;
    final fav = Favorite(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      iconUrl: track.iconUrl,
      duration: track.duration,
      genre: track.genre.isEmpty ? null : track.genre,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      isNg: isNg,
    );
    await d.insert('favorites', fav.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFavorite(String trackId) async {
    final d = await db;
    await d.delete('favorites', where: 'track_id = ?', whereArgs: [trackId]);
  }

  Future<void> setFavoriteIsNg(String trackId, bool isNg) async {
    final d = await db;
    await d.update('favorites', {'is_ng': isNg ? 1 : 0},
        where: 'track_id = ?', whereArgs: [trackId]);
  }

  Future<void> toggleFavorite(Track track, {bool isNg = false}) async {
    if (await isFavorite(track.id)) {
      await removeFavorite(track.id);
    } else {
      await addFavorite(track, isNg: isNg);
    }
  }

  static Track playlistTrackToTrack(PlaylistTrack pt) => Track(
        id: pt.trackId,
        title: pt.title,
        artist: pt.artist,
        genre: pt.genre ?? '',
        iconUrl: pt.iconUrl,
        duration: pt.duration,
        audioType: 3,
        mp3Url: pt.mp3Url,
      );

  static Track favoriteToTrack(Favorite f) => Track(
        id: f.trackId,
        title: f.title,
        artist: f.artist,
        genre: f.genre ?? '',
        iconUrl: f.iconUrl,
        duration: f.duration,
        audioType: 3,
      );

  // Blacklist methods
  Future<bool> isBlacklisted(String trackId) async {
    final d = await db;
    final r = await d.query(
      'blacklisted_tracks',
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<void> addToBlacklist(Track track) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await d.insert(
      'blacklisted_tracks',
      {
        'track_id': track.id,
        'title': track.title,
        'blacklisted_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFromBlacklist(String trackId) async {
    final d = await db;
    await d.delete(
      'blacklisted_tracks',
      where: 'track_id = ?',
      whereArgs: [trackId],
    );
  }

  Future<List<Map<String, dynamic>>> getBlacklistedTracks() async {
    final d = await db;
    return await d.query('blacklisted_tracks', orderBy: 'blacklisted_at DESC');
  }

  // Staged likes methods
  Future<List<StagedLike>> getStagedLikes() async {
    final d = await db;
    final rows = await d.query('staged_likes', orderBy: 'liked_at DESC');
    return rows.map(StagedLike.fromMap).toList();
  }

  Future<bool> isStagedLike(String trackId) async {
    final d = await db;
    final r = await d.query(
      'staged_likes',
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<void> addStagedLike(Track track) async {
    final d = await db;
    final like = StagedLike(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      iconUrl: track.iconUrl,
      duration: track.duration,
      genre: track.genre.isEmpty ? null : track.genre,
      likedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await d.insert('staged_likes', like.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Merge imported likes in one transaction. Existing rows are kept as-is,
  /// so re-importing the same favorites cannot create duplicates or reorder
  /// the user's current likes.
  Future<void> addStagedLikes(Iterable<Track> tracks) async {
    final items = tracks.toList();
    if (items.isEmpty) return;
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await d.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < items.length; i++) {
        final track = items[i];
        final like = StagedLike(
          trackId: track.id,
          title: track.title,
          artist: track.artist,
          authorUrl: track.authorUrl,
          iconUrl: track.iconUrl,
          duration: track.duration,
          genre: track.genre.isEmpty ? null : track.genre,
          // Keep the order returned by Newgrounds (newest favorite first).
          likedAt: now - i,
        );
        batch.insert('staged_likes', like.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> removeStagedLike(String trackId) async {
    final d = await db;
    await d.delete('staged_likes', where: 'track_id = ?', whereArgs: [trackId]);
  }

  Future<void> clearStagedLikes() async {
    final d = await db;
    await d.delete('staged_likes');
  }

  static Track stagedLikeToTrack(StagedLike sl) => Track(
        id: sl.trackId,
        title: sl.title,
        artist: sl.artist,
        genre: sl.genre ?? '',
        iconUrl: sl.iconUrl,
        duration: sl.duration,
        audioType: 3,
      );

  // Cached tracks methods
  Future<String?> getCachedTrackPath(String trackId) async {
    final d = await db;
    final r = await d.query(
      'cached_tracks',
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (r.isEmpty) return null;
    return r.first['local_path'] as String?;
  }

  Future<bool> isTrackCached(String trackId) async {
    final d = await db;
    final r = await d.query(
      'cached_tracks',
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<void> addCachedTrack(
      String trackId, String localPath, int size) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await d.insert(
      'cached_tracks',
      {
        'track_id': trackId,
        'local_path': localPath,
        'cached_at': now,
        'size': size,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeCachedTrack(String trackId) async {
    final d = await db;
    await d
        .delete('cached_tracks', where: 'track_id = ?', whereArgs: [trackId]);
  }

  Future<List<Map<String, dynamic>>> getAllCachedTracks() async {
    final d = await db;
    return await d.query('cached_tracks', orderBy: 'cached_at DESC');
  }
}
