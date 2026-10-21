import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/library_viewmodel.dart';

class BlacklistScreen extends StatefulWidget {
  const BlacklistScreen({super.key});

  @override
  State<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<BlacklistScreen> {
  @override
  Widget build(BuildContext context) {
    final lvm = context.watch<LibraryViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Blacklisted Tracks'),
        actions: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: lvm.getBlacklistedTracks(),
            builder: (context, snapshot) {
              final blacklisted = snapshot.data ?? [];
              if (blacklisted.isEmpty) return const SizedBox.shrink();

              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear Blacklist'),
                      content: const Text('Remove all blacklisted tracks?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    for (final item in blacklisted) {
                      await lvm.removeFromBlacklist(item['track_id'] as String);
                    }
                    setState(() {});
                  }
                },
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: lvm.getBlacklistedTracks(),
        builder: (context, snapshot) {
          final blacklistedItems = snapshot.data ?? [];

          if (blacklistedItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.block,
                    size: 64,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No blacklisted tracks',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Swipe right on tracks to blacklist them',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: blacklistedItems.length,
            itemBuilder: (context, i) {
              final item = blacklistedItems[i];
              final trackId = item['track_id'] as String;
              final title = item['title'] as String?;

              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.block,
                    color: colorScheme.onErrorContainer,
                    size: 20,
                  ),
                ),
                title: Text(title ?? 'Track #$trackId'),
                subtitle: Text('ID: $trackId', style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () async {
                    await lvm.removeFromBlacklist(trackId);
                    setState(() {});
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
