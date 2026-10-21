import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/author.dart';
import '../../viewmodel/authors_viewmodel.dart';

class AuthorActions extends StatelessWidget {
  final Author author;

  const AuthorActions({super.key, required this.author});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthorsViewModel>();
    final state = vm.stateOf(author);
    final enabled = vm.loaded && !vm.isBusy(author);

    Future<void> change(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save author preferences')),
          );
        }
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: enabled
              ? () => change(() => vm.setSubscribed(author, !state.subscribed))
              : null,
          icon:
              Icon(state.subscribed ? Icons.check : Icons.person_add_outlined),
          label: Text(state.subscribed ? 'Subscribed' : 'Subscribe'),
        ),
        IconButton(
          tooltip: state.blocked ? 'Unblock author' : 'Block author',
          color: state.blocked ? Theme.of(context).colorScheme.error : null,
          icon: Icon(state.blocked ? Icons.block : Icons.block_outlined),
          onPressed: enabled
              ? () => change(() => vm.setBlocked(author, !state.blocked))
              : null,
        ),
      ],
    );
  }
}
