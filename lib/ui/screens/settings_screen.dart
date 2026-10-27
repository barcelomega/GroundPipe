import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/model/author.dart';
import '../../data/repository/local_db.dart';
import '../../viewmodel/authors_viewmodel.dart';
import '../../viewmodel/library_viewmodel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // About section
          Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.music_note, size: 48, color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'GroundPipe',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Version 1.3.1+6',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Material Design music player for Newgrounds Audio Portal',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'MIT License',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),

          // Backup & Export section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Backup & Export',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Export Full Backup'),
            subtitle: const Text(
              'Playlists, likes, subscriptions, blocked artists, '
              'blacklist, and settings',
            ),
            trailing: _isExporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _isExporting ? null : _exportFullBackup,
          ),

          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import Full Backup'),
            subtitle: const Text('Restore from backup file'),
            trailing: _isImporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _isImporting ? null : _importFullBackup,
          ),

          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Export Track Links'),
            subtitle: const Text(
              'Text files with Newgrounds track links for user scripts',
            ),
            trailing: _isExporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _isExporting ? null : _exportTrackLinks,
          ),
        ],
      ),
    );
  }

  Future<void> _exportFullBackup() async {
    setState(() => _isExporting = true);

    try {
      final db = LocalDb.instance;

      // Collect all data
      final data = <String, dynamic>{
        'version': '1.3.1+6',
        'exportDate': DateTime.now().toIso8601String(),
        'playlists': await _getAllPlaylists(db),
        'likes': await _getLikes(db),
        'history': await _getHistory(db),
        'subscriptions': await _getSubscriptions(db),
        'blocked_authors': await _getBlockedAuthors(db),
        'blacklist': await _getBlacklist(db),
        'settings': await _getSettings(),
      };

      final json = jsonEncode(data);
      final bytes = utf8.encode(json);

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final fileName = 'groundpipe_backup_$timestamp.json';
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save GroundPipe backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(bytes),
      );

      // The user cancelled the system save dialog.
      if (savedPath == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup exported successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importFullBackup() async {
    setState(() => _isImporting = true);

    try {
      // Pick backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() => _isImporting = false);
        return;
      }

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final json = utf8.decode(bytes);
      final data = jsonDecode(json) as Map<String, dynamic>;

      // Confirm import
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import Backup?'),
          content: Text(
            'This will replace all current data with backup from:\n'
            '${data['exportDate']}\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() => _isImporting = false);
        return;
      }

      // Restore data
      final db = LocalDb.instance;
      await _restoreBackup(db, data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup imported successfully')),
      );

      // Reload library and subscriptions
      context.read<LibraryViewModel>().refresh();
      context.read<AuthorsViewModel>().load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _exportTrackLinks() async {
    setState(() => _isExporting = true);

    try {
      final db = LocalDb.instance;

      // Create archive
      final archive = Archive();

      // Export likes
      final likes = await _getLikes(db);
      final likesContent = _formatTrackLinks(likes);
      archive.addFile(
        ArchiveFile('likes.txt', likesContent.length, likesContent),
      );

      // Export playlists
      final playlists = await _getAllPlaylists(db);
      for (final playlist in playlists) {
        final tracks = playlist['tracks'] as List;
        if (tracks.isEmpty) continue;

        final content = _formatTrackLinks(tracks.cast<Map<String, dynamic>>());
        final safeName = _sanitizeFilename(playlist['name'] as String);
        archive.addFile(
          ArchiveFile('$safeName.txt', content.length, content),
        );
      }

      // Encode to ZIP
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) throw Exception('Failed to create ZIP');

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final fileName = 'groundpipe_track_links_$timestamp.zip';
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save GroundPipe track links',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: Uint8List.fromList(zipBytes),
      );

      // The user cancelled the system save dialog.
      if (savedPath == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Track links exported successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  List<int> _formatTrackLinks(List<Map<String, dynamic>> tracks) {
    final buffer = StringBuffer();
    for (final track in tracks) {
      final trackId = track['track_id'] as String?;
      if (trackId == null || trackId.isEmpty) continue;
      final artist = track['artist'] ?? 'Unknown Artist';
      final title = track['title'] ?? 'Unknown Title';
      buffer.writeln(
        'https://www.newgrounds.com/audio/listen/$trackId ($artist - $title)',
      );
    }
    return utf8.encode(buffer.toString());
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<List<Map<String, dynamic>>> _getAllPlaylists(LocalDb db) async {
    final playlists = await db.getPlaylists();
    final result = <Map<String, dynamic>>[];
    
    for (final playlist in playlists) {
      final tracks = await db.getPlaylistTracks(playlist.id!);
      result.add({
        'id': playlist.id,
        'name': playlist.name,
        'description': playlist.description,
        'ng_id': playlist.ngId,
        'created_at': playlist.createdAt,
        'tracks': tracks.map((t) => {
          'track_id': t.trackId,
          'title': t.title,
          'artist': t.artist,
          'author_url': t.authorUrl,
          'icon_url': t.iconUrl,
          'duration': t.duration,
          'genre': t.genre,
          'mp3_url': t.mp3Url,
          'position': t.position,
          'added_at': t.addedAt,
        }).toList(),
      });
    }
    
    return result;
  }

  Future<List<Map<String, dynamic>>> _getLikes(LocalDb db) async {
    final likes = await db.getStagedLikes();
    return likes.map((like) => {
      'track_id': like.trackId,
      'title': like.title,
      'artist': like.artist,
      'author_url': like.authorUrl,
      'icon_url': like.iconUrl,
      'duration': like.duration,
      'genre': like.genre,
      'liked_at': like.likedAt,
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _getHistory(LocalDb db) async {
    // History is not stored in database currently, return empty list
    return [];
  }

  Future<List<Map<String, dynamic>>> _getSubscriptions(LocalDb db) async {
    final authors = await db.getAuthors();
    return authors
        .where((author) => author.subscribed)
        .map((author) => {
              'username': author.username,
              'name': author.name,
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _getBlockedAuthors(LocalDb db) async {
    final authors = await db.getAuthors();
    return authors
        .where((author) => author.blocked)
        .map((author) => {
              'username': author.username,
              'name': author.name,
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _getBlacklist(LocalDb db) async {
    final rows = await db.getBlacklistedTracks();
    return rows
        .map((row) => {
              'track_id': row['track_id'],
              'title': row['title'],
              'blacklisted_at': row['blacklisted_at'],
            })
        .toList();
  }

  List<Author> _authorsFromBackup(Object? raw) {
    final entries = (raw as List?) ?? const [];
    final authors = <Author>[];
    for (final entry in entries.whereType<Map>()) {
      final username = entry['username'] as String?;
      if (username == null || username.isEmpty) continue;
      authors.add(Author(
        username: username,
        name: (entry['name'] as String?) ?? username,
      ));
    }
    return authors;
  }

  Future<Map<String, dynamic>> _getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final settings = <String, dynamic>{};
    
    for (final key in keys) {
      final value = prefs.get(key);
      settings[key] = value;
    }
    
    return settings;
  }

  Future<void> _restoreBackup(LocalDb db, Map<String, dynamic> data) async {
    final d = await db.db;
    
    // Clear existing data
    await d.delete('playlists');
    await d.delete('playlist_tracks');
    await d.delete('staged_likes');
    
    // Restore playlists
    final playlists = (data['playlists'] as List?) ?? [];
    for (final playlistData in playlists) {
      final playlist = playlistData as Map<String, dynamic>;
      final playlistId = await d.insert('playlists', {
        'name': playlist['name'],
        'description': playlist['description'],
        'ng_id': playlist['ng_id'],
        'created_at': playlist['created_at'],
      });
      
      // Restore tracks for this playlist
      final tracks = (playlist['tracks'] as List?) ?? [];
      for (final trackData in tracks) {
        final track = trackData as Map<String, dynamic>;
        await d.insert('playlist_tracks', {
          'playlist_id': playlistId,
          'track_id': track['track_id'],
          'title': track['title'],
          'artist': track['artist'],
          'author_url': track['author_url'],
          'icon_url': track['icon_url'],
          'duration': track['duration'],
          'genre': track['genre'],
          'mp3_url': track['mp3_url'],
          'position': track['position'],
          'added_at': track['added_at'],
        });
      }
    }
    
    // Restore likes
    final likes = (data['likes'] as List?) ?? [];
    for (final likeData in likes) {
      final like = likeData as Map<String, dynamic>;
      await d.insert('staged_likes', {
        'track_id': like['track_id'],
        'title': like['title'],
        'artist': like['artist'],
        'author_url': like['author_url'],
        'icon_url': like['icon_url'],
        'duration': like['duration'],
        'genre': like['genre'],
        'liked_at': like['liked_at'],
      });
    }
    
    // Restore subscriptions and blocked authors. Backups created before
    // these keys existed leave the current author preferences alone.
    final hasSubscriptions = data.containsKey('subscriptions');
    final hasBlockedAuthors = data.containsKey('blocked_authors');
    if (hasSubscriptions) await db.clearSubscriptions();
    if (hasBlockedAuthors) await db.clearBlockedAuthors();
    if (hasSubscriptions) {
      await db.importSubscriptions(
        _authorsFromBackup(data['subscriptions']),
      );
    }
    if (hasBlockedAuthors) {
      await db.importBlockedAuthors(
        _authorsFromBackup(data['blocked_authors']),
      );
    }

    // Restore blacklist. Backups created before it was included leave the
    // current blacklist alone.
    if (data.containsKey('blacklist')) {
      final blacklist = (data['blacklist'] as List?) ?? const [];
      await d.delete('blacklisted_tracks');
      for (final entry in blacklist.whereType<Map>()) {
        final trackId = entry['track_id'] as String?;
        if (trackId == null || trackId.isEmpty) continue;
        await d.insert('blacklisted_tracks', {
          'track_id': trackId,
          'title': entry['title'] as String?,
          'blacklisted_at': (entry['blacklisted_at'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        });
      }
    }

    // Restore settings
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final settings = (data['settings'] as Map<String, dynamic>?) ?? {};
    for (final entry in settings.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
    }
  }
}
