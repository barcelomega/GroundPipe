import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/library_viewmodel.dart';
import '../screens/authors_screen.dart';
import '../screens/blacklist_screen.dart';
import '../screens/cached_tracks_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/staged_likes_screen_new.dart';

/// Shared navigation drawer for the three main screens.
class NgDrawer extends StatelessWidget {
  const NgDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lvm = context.watch<LibraryViewModel>();

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: colorScheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.music_note, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'GroundPipe',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('Likes'),
              trailing: lvm.stagedLikes.isNotEmpty
                  ? Chip(
                      label: Text(lvm.stagedLikes.length.toString()),
                      labelStyle: const TextStyle(fontSize: 12),
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
              onTap: () => _open(context, const StagedLikesScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Blacklist'),
              onTap: () => _open(context, const BlacklistScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Cached Tracks'),
              onTap: () => _open(context, const CachedTracksScreen()),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Subscriptions'),
              onTap: () => _open(context, const AuthorsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Blocked Artists'),
              onTap: () => _open(context, const AuthorsScreen(blocked: true)),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => _open(context, const SettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => screen));
  }
}
