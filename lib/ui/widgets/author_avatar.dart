import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/repository/ng_repository.dart';

class AuthorAvatar extends StatefulWidget {
  final String author;
  final double size;

  const AuthorAvatar({super.key, required this.author, this.size = 40});

  @override
  State<AuthorAvatar> createState() => _AuthorAvatarState();
}

class _AuthorAvatarState extends State<AuthorAvatar> {
  late Future<String?> _avatar;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _avatar = NgRepository().getAuthorAvatar(widget.author);

  @override
  void didUpdateWidget(covariant AuthorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.author != widget.author) _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.person_outline,
          color: colors.onSurfaceVariant, size: widget.size * 0.6),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: widget.size,
        child: FutureBuilder<String?>(
          future: _avatar,
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) return placeholder;
            return CachedNetworkImage(
              imageUrl: url.startsWith('//') ? 'https:$url' : url,
              fit: BoxFit.cover,
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            );
          },
        ),
      ),
    );
  }
}
