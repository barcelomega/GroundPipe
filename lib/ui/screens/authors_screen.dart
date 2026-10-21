import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/authors_viewmodel.dart';
import 'artist_screen.dart';
import '../widgets/author_avatar.dart';

class AuthorsScreen extends StatelessWidget {
  final bool blocked;

  const AuthorsScreen({super.key, this.blocked = false});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthorsViewModel>();
    final authors = blocked ? vm.blockedAuthors : vm.subscriptions;
    return Scaffold(
      appBar:
          AppBar(title: Text(blocked ? 'Blocked Artists' : 'Subscriptions')),
      body: !vm.loaded
          ? Center(
              child: vm.error == null
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: vm.load, child: const Text('Retry')))
          : authors.isEmpty
              ? Center(
                  child: Text(blocked
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
