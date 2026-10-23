import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/authors_viewmodel.dart';
import 'artist_screen.dart';
import '../widgets/author_avatar.dart';

enum _SubscriptionsMenuAction { import, clear }

class AuthorsScreen extends StatefulWidget {
  final bool blocked;

  const AuthorsScreen({super.key, this.blocked = false});

  @override
  State<AuthorsScreen> createState() => _AuthorsScreenState();
}

class _AuthorsScreenState extends State<AuthorsScreen> {
  bool _importing = false;

  Future<void> _showImportDialog() async {
    final username = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ImportSubscriptionsDialog(),
    );
    if (username == null || username.isEmpty || !mounted) return;
    await _importSubscriptions(username);
  }

  Future<void> _importSubscriptions(String username) async {
    if (_importing) return;
    final vm = context.read<AuthorsViewModel>();
    setState(() => _importing = true);
    try {
      final result = await vm.importSubscriptions(username);
      if (!mounted) return;
      final message = result.added > 0
          ? 'Imported ${result.added} '
              '${result.added == 1 ? 'subscription' : 'subscriptions'}'
          : result.found == 0
              ? 'No subscriptions found for $username'
              : 'No new subscriptions to import';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import subscriptions: $message')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmClearSubscriptions() async {
    final vm = context.read<AuthorsViewModel>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Subscriptions'),
        content: const Text(
            'Remove all subscriptions? Blocked artists will stay blocked.'),
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
    if (confirm != true) return;
    try {
      await vm.clearSubscriptions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscriptions cleared')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear subscriptions: $message')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthorsViewModel>();
    final authors = widget.blocked ? vm.blockedAuthors : vm.subscriptions;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.blocked ? 'Blocked Artists' : 'Subscriptions'),
        actions: widget.blocked
            ? null
            : [
                PopupMenuButton<_SubscriptionsMenuAction>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Subscriptions options',
                  enabled: !_importing,
                  onSelected: (action) {
                    if (action == _SubscriptionsMenuAction.import) {
                      _showImportDialog();
                    } else {
                      _confirmClearSubscriptions();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _SubscriptionsMenuAction.import,
                      child: _SubscriptionsMenuRow(
                        icon: Icons.download_outlined,
                        label: 'Import Subscriptions',
                      ),
                    ),
                    PopupMenuItem(
                      value: _SubscriptionsMenuAction.clear,
                      enabled: authors.isNotEmpty,
                      child: const _SubscriptionsMenuRow(
                        icon: Icons.delete_sweep_outlined,
                        label: 'Clear Subscriptions',
                      ),
                    ),
                  ],
                ),
              ],
        bottom: _importing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: !vm.loaded
          ? Center(
              child: vm.error == null
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: vm.load, child: const Text('Retry')))
          : authors.isEmpty
              ? Center(
                  child: Text(widget.blocked
                      ? 'No blocked artists'
                      : 'Subscribe to authors from their audio pages'))
              : ListView.builder(
                  itemCount: authors.length,
                  itemBuilder: (context, index) {
                    final author = authors[index];
                    return ListTile(
                      leading: AuthorAvatar(author: author.username),
                      title: Text(author.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('@${author.username}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          try {
                            if (action == 'subscription') {
                              await vm.setSubscribed(
                                  author, !author.subscribed);
                            } else {
                              await vm.setBlocked(author, !author.blocked);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Could not save author preferences')),
                              );
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'subscription',
                              child: Text(author.subscribed
                                  ? 'Unsubscribe'
                                  : 'Subscribe')),
                          PopupMenuItem(
                              value: 'block',
                              child:
                                  Text(author.blocked ? 'Unblock' : 'Block')),
                        ],
                      ),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ArtistScreen(authorUrl: author.audioUrl),
                          )),
                    );
                  },
                ),
    );
  }
}

class _ImportSubscriptionsDialog extends StatefulWidget {
  const _ImportSubscriptionsDialog();

  @override
  State<_ImportSubscriptionsDialog> createState() =>
      _ImportSubscriptionsDialogState();
}

class _ImportSubscriptionsDialogState
    extends State<_ImportSubscriptionsDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Subscriptions'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          hintText: 'Enter your Newgrounds username...',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, __) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: const Text('Import'),
          ),
        ),
      ],
    );
  }
}

class _SubscriptionsMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SubscriptionsMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
