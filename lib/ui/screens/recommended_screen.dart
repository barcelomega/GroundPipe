import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/model/playlist.dart';

import '../../viewmodel/library_viewmodel.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../../viewmodel/recommendations_viewmodel.dart';
import '../widgets/ng_drawer.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_list_item.dart';

class RecommendedScreen extends StatefulWidget {
  const RecommendedScreen({super.key});

  @override
  State<RecommendedScreen> createState() => _RecommendedScreenState();
}

class _RecommendedScreenState extends State<RecommendedScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final recommendations = context.watch<RecommendationsViewModel>();
    final library = context.watch<LibraryViewModel>();
    final tracks = recommendations.tracks
        .where((track) =>
            !library.isStagedLike(track.id) && !library.isBlacklisted(track.id))
        .toList();

    return Scaffold(
      drawer: const NgDrawer(),
      body: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Recommended'),
            floating: true,
            forceElevated: innerBoxIsScrolled,
            actions: [
              IconButton(
                tooltip: 'Refresh recommendations',
                onPressed: recommendations.isGathering
                    ? null
                    : recommendations.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: DropdownButtonFormField<int>(
                value: recommendations.selectedPlaylistId ?? -1,
                decoration: const InputDecoration(
                  labelText: 'Recommendation source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int>(
                    value: -1,
                    child: Text('All Likes'),
                  ),
                  ...recommendations.availablePlaylists.map(
                    (Playlist playlist) => DropdownMenuItem<int>(
                      value: playlist.id,
                      child:
                          Text(playlist.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: recommendations.isGathering
                    ? null
                    : (value) => recommendations.selectPlaylist(
                          value == -1 ? null : value,
                        ),
              ),
            ),
          ),
        ],
        body: Column(
          children: [
            if (recommendations.isGathering ||
                recommendations.isLoadingCache ||
                recommendations.error != null)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(recommendations.isGathering
                                ? 'Gathering statistics, please wait'
                                : recommendations.isLoadingCache
                                    ? 'Loading saved recommendations'
                                    : recommendations.error!),
                          ),
                        ],
                      ),
                      if (recommendations.isGathering) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: recommendations.totalAuthors == 0
                              ? null
                              : recommendations.completedAuthors /
                                  recommendations.totalAuthors,
                        ),
                        if (recommendations.currentAuthor != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${recommendations.currentAuthor} · page '
                              '${recommendations.currentPage}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: recommendations.refresh,
                child: tracks.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: 240,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(recommendations.isGathering
                                    ? 'Recommendations will appear as data is collected.'
                                    : recommendations.isLoadingCache
                                        ? 'Loading saved recommendations...'
                                        : 'Like tracks to build your recommendations.'),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          final isLiked = library.isStagedLike(track.id);
                          return Dismissible(
                            key: ValueKey('recommended_${track.id}'),
                            direction: DismissDirection.horizontal,
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                final wasLiked = isLiked;
                                if (isLiked) {
                                  await library.removeStagedLike(track.id);
                                } else {
                                  await library.addStagedLike(track);
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(wasLiked
                                          ? 'Removed from Likes'
                                          : 'Added to Likes'),
                                      action: SnackBarAction(
                                        label: 'Undo',
                                        onPressed: () {
                                          if (wasLiked) {
                                            library.addStagedLike(track);
                                          } else {
                                            library.removeStagedLike(track.id);
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                await library.addToBlacklist(track);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Blacklisted: ${track.title}'),
                                      action: SnackBarAction(
                                        label: 'Undo',
                                        onPressed: () => library
                                            .removeFromBlacklist(track.id),
                                      ),
                                    ),
                                  );
                                }
                              }
                              return false;
                            },
                            background: Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 24),
                              child: Icon(
                                isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                            secondaryBackground: Container(
                              color:
                                  Theme.of(context).colorScheme.errorContainer,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: Icon(
                                Icons.block,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                            child: TrackListItem(
                              track: track,
                              isLiked: isLiked,
                              onTap: () {
                                final player = context.read<NgViewModel>();
                                player.setQueueContext(tracks);
                                player.playTrack(track);
                              },
                              onLongPress: () => showTrackContextMenu(
                                  context, track,
                                  showLike: false),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
