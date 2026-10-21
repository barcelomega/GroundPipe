import 'package:flutter/material.dart';
import '../../viewmodel/authors_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/model/track.dart';
import '../../data/model/ng_audio_genres.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../widgets/ng_drawer.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/track_list_item.dart';
import 'captcha_bypass_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _currentQuery = '';
  bool _isSearchMode = false;
  List<String> _searchHistory = [];

  // Filter parameters
  String _filterRange = 'all';
  String _filterSort = 'date';
  Set<String> _filterGenres = {}; // Multiple genres
  String _filterArtistType = 'approved';
  DateTime? _filterAfter;
  DateTime? _filterBefore;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _onTabChanged();
      }
    });

    _loadSearchHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _searchHistory = prefs.getStringList('search_history') ?? [];
    });
  }

  Future<void> _saveSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', _searchHistory);
  }

  void _addToSearchHistory(String query) {
    if (query.trim().isEmpty) return;

    setState(() {
      _searchHistory.remove(query); // Remove if exists
      _searchHistory.insert(0, query); // Add to front
      if (_searchHistory.length > 10) {
        _searchHistory = _searchHistory.sublist(0, 10); // Keep only last 10
      }
    });
    _saveSearchHistory();
  }

  void _enterSearchMode() {
    setState(() {
      _isSearchMode = true;
    });
    _searchFocusNode.requestFocus();
  }

  void _exitSearchMode() {
    _searchFocusNode.unfocus();
    setState(() {
      _isSearchMode = false;
      _searchController.clear();
      _currentQuery = '';
    });

    final vm = context.read<NgViewModel>();
    vm.clearSearch();
  }

  void _onTabChanged() {
    final vm = context.read<NgViewModel>();
    final tabs = [NgTab.featured, NgTab.latest, NgTab.popular];
    vm.setActiveTab(tabs[_tabController.index]);
    vm.loadTab(tabs[_tabController.index]);
    setState(() {});
  }

  void _search() {
    final vm = context.read<NgViewModel>();
    final query = _searchController.text.trim();
    _searchFocusNode.unfocus();

    if (query.isEmpty) {
      vm.clearSearch();
      final tabs = [NgTab.featured, NgTab.latest, NgTab.popular];
      vm.reloadTab(tabs[_tabController.index]);
    } else {
      vm.search(query);
    }
    setState(() => _currentQuery = query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_isSearchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSearchMode) _exitSearchMode();
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        drawer: _isSearchMode ? null : const NgDrawer(),
        appBar: _isSearchMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _exitSearchMode,
                ),
                title: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: const InputDecoration(
                    hintText: 'Search tracks...',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (query) {
                    if (query.trim().isNotEmpty) {
                      _addToSearchHistory(query.trim());
                      _search();
                    }
                  },
                ),
                actions: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        context.read<NgViewModel>().clearSearch();
                        setState(() => _currentQuery = '');
                        _searchFocusNode.requestFocus();
                      },
                    ),
                ],
              )
            : null,
        body: _isSearchMode
            ? (_currentQuery.isEmpty
                ? _buildSearchHistory(context)
                : _buildSearchResults(context))
            : NestedScrollView(
                floatHeaderSlivers: true,
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    // Normal AppBar with tabs
                    SliverAppBar(
                      title: const Text('Discover'),
                      floating: true,
                      pinned: true,
                      snap: false,
                      forceElevated: innerBoxIsScrolled,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.filter_list),
                          onPressed: () => _showFilterDialog(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _enterSearchMode,
                        ),
                      ],
                      bottom: TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'FEATURED'),
                          Tab(text: 'LATEST'),
                          Tab(text: 'POPULAR'),
                        ],
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTabContent(context, NgTab.featured),
                    _buildTabContent(context, NgTab.latest),
                    _buildTabContent(context, NgTab.popular),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSearchHistory(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_searchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Search for tracks',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _searchHistory.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Recent searches'),
            trailing: TextButton(
              onPressed: () {
                setState(() {
                  _searchHistory.clear();
                });
                _saveSearchHistory();
              },
              child: const Text('Clear'),
            ),
          );
        }

        final query = _searchHistory[index - 1];
        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(query),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _searchHistory.removeAt(index - 1);
              });
              _saveSearchHistory();
            },
          ),
          onTap: () {
            _searchController.text = query;
            _search();
          },
        );
      },
    );
  }

  Widget _buildTabContent(BuildContext context, NgTab tab) {
    final vm = context.watch<NgViewModel>();
    final lvm = context.watch<LibraryViewModel>();
    final state = vm.stateOf(tab);
    final authors = context.watch<AuthorsViewModel>();
    final tracks = state.tracks
        .where((t) => !lvm.isBlacklisted(t.id) && !authors.isBlocked(t))
        .toList();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (state.isLoading && state.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No tracks found',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _bypassCaptcha(context),
              icon: const Icon(Icons.shield),
              label: const Text('Solve Captcha'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => vm.reloadTab(tab),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: tracks.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          // Loading indicator at the end
          if (i == tracks.length) {
            if (state.isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            } else if (state.hasMore) {
              // Trigger load more
              WidgetsBinding.instance.addPostFrameCallback((_) {
                vm.loadMoreForTab(tab);
              });
              return const SizedBox.shrink();
            }
            return const SizedBox.shrink();
          }

          final track = tracks[i];
          final isBlacklisted = lvm.isBlacklisted(track.id);
          final isLiked = lvm.isStagedLike(track.id);

          if (isBlacklisted) return const SizedBox.shrink();

          return _buildTrackItem(context, track, tracks, isLiked);
        },
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final vm = context.watch<NgViewModel>();
    final lvm = context.watch<LibraryViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authors = context.watch<AuthorsViewModel>();
    final tracks = vm.searchResults
        .where((t) => !lvm.isBlacklisted(t.id) && !authors.isBlocked(t))
        .toList();

    if (vm.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vm.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _bypassCaptcha(context),
              icon: const Icon(Icons.shield),
              label: const Text('Solve Captcha'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _search(),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: tracks.length,
        itemBuilder: (context, i) {
          final track = tracks[i];
          final isBlacklisted = lvm.isBlacklisted(track.id);
          final isLiked = lvm.isStagedLike(track.id);

          if (isBlacklisted) return const SizedBox.shrink();

          return _buildTrackItem(context, track, tracks, isLiked);
        },
      ),
    );
  }

  Widget _buildTrackItem(
    BuildContext context,
    Track track,
    List<Track> queue,
    bool isLiked,
  ) {
    final vm = context.read<NgViewModel>();
    final lvm = context.read<LibraryViewModel>();
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: Key(track.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // Swipe left = blacklist
          await lvm.addToBlacklist(track);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Blacklisted: ${track.title}'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => lvm.removeFromBlacklist(track.id),
                ),
              ),
            );
          }
          return true;
        } else {
          // Swipe right = like/unlike toggle
          final wasLiked = isLiked;
          if (isLiked) {
            await lvm.removeStagedLike(track.id);
          } else {
            await lvm.addStagedLike(track);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(wasLiked ? 'Removed from Likes' : 'Added to Likes'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () {
                    if (wasLiked) {
                      lvm.addStagedLike(track);
                    } else {
                      lvm.removeStagedLike(track.id);
                    }
                  },
                ),
              ),
            );
          }
          return false;
        }
      },
      background: Container(
        color: colorScheme.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Icon(
          Icons.favorite,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
      secondaryBackground: Container(
        color: colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.block,
          color: colorScheme.onErrorContainer,
        ),
      ),
      child: TrackListItem(
        track: track,
        isLiked: isLiked,
        onTap: () {
          vm.setQueueContext(queue);
          vm.playTrack(track);
        },
        onLongPress: () => _showTrackMenu(context, track),
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    // Local state for dialog
    String tempRange = _filterRange;
    String tempSort = _filterSort;
    Set<String> tempGenres = Set.from(_filterGenres);
    String tempArtistType = _filterArtistType;
    DateTime? tempAfter = _filterAfter;
    DateTime? tempBefore = _filterBefore;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Filter & Sort',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          tempRange = 'all';
                          tempSort = 'date';
                          tempGenres.clear();
                          tempArtistType = 'approved';
                          tempAfter = null;
                          tempBefore = null;
                        });
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Range dropdown
                DropdownButtonFormField<String>(
                  value: tempRange,
                  decoration: const InputDecoration(
                    labelText: 'Range',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Today')),
                    DropdownMenuItem(
                        value: 'yesterday', child: Text('Yesterday')),
                    DropdownMenuItem(value: 'week', child: Text('Week')),
                    DropdownMenuItem(value: 'month', child: Text('Month')),
                    DropdownMenuItem(value: 'year', child: Text('Year')),
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (value) {
                    setModalState(() => tempRange = value!);
                  },
                ),
                const SizedBox(height: 12),

                // Sort By dropdown
                DropdownButtonFormField<String>(
                  value: tempSort,
                  decoration: const InputDecoration(
                    labelText: 'Sort By',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'date', child: Text('Date')),
                    DropdownMenuItem(value: 'score', child: Text('Score')),
                    DropdownMenuItem(value: 'views', child: Text('Views')),
                  ],
                  onChanged: (value) {
                    setModalState(() => tempSort = value!);
                  },
                ),
                const SizedBox(height: 12),

                // Artist Type dropdown
                DropdownButtonFormField<String>(
                  value: tempArtistType,
                  decoration: const InputDecoration(
                    labelText: 'Showing',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Artists')),
                    DropdownMenuItem(
                        value: 'approved', child: Text('Approved Artists')),
                    DropdownMenuItem(
                        value: 'undiscovered',
                        child: Text('Undiscovered Artists')),
                  ],
                  onChanged: (value) {
                    setModalState(() => tempArtistType = value!);
                  },
                ),
                const SizedBox(height: 12),

                // Genre selection button
                OutlinedButton.icon(
                  icon: const Icon(Icons.music_note),
                  label: Text(
                    tempGenres.isEmpty
                        ? 'All Genres'
                        : '${tempGenres.length} genre(s) selected',
                  ),
                  onPressed: () {
                    _showGenreSelector(context, tempGenres, (selected) {
                      setModalState(() => tempGenres = selected);
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),

                // Custom date range (only show if Range = Custom)
                if (tempRange == 'custom') ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: tempAfter ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setModalState(() => tempAfter = date);
                            }
                          },
                          child: Text(
                            tempAfter != null
                                ? 'After: ${tempAfter!.toString().split(' ')[0]}'
                                : 'After: (not set)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: tempBefore ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setModalState(() => tempBefore = date);
                            }
                          },
                          child: Text(
                            tempBefore != null
                                ? 'Before: ${tempBefore!.toString().split(' ')[0]}'
                                : 'Before: (not set)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Apply button
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _filterRange = tempRange;
                      _filterSort = tempSort;
                      _filterGenres = tempGenres;
                      _filterArtistType = tempArtistType;
                      _filterAfter = tempAfter;
                      _filterBefore = tempBefore;
                    });
                    Navigator.pop(ctx);
                    _applyFilters();
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('Apply Filters'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGenreSelector(BuildContext context, Set<String> selectedGenres,
      Function(Set<String>) onChanged) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Select Genres',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setModalState(() => selectedGenres.clear());
                        onChanged(selectedGenres);
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: NgAudioGenres.groups.length,
                  itemBuilder: (context, groupIndex) {
                    final group = NgAudioGenres.groups[groupIndex];
                    return ExpansionTile(
                      title: Text(group.label),
                      children: group.genres.map((genre) {
                        final isSelected = selectedGenres.contains(genre.id);
                        return CheckboxListTile(
                          title: Text(genre.label),
                          value: isSelected,
                          onChanged: (checked) {
                            setModalState(() {
                              if (checked == true) {
                                selectedGenres.add(genre.id);
                              } else {
                                selectedGenres.remove(genre.id);
                              }
                            });
                            onChanged(selectedGenres);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: Text('Done (${selectedGenres.length} selected)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyFilters() {
    final vm = context.read<NgViewModel>();

    // Prepare date strings
    String? afterStr;
    String? beforeStr;

    if (_filterRange == 'custom') {
      if (_filterAfter != null) {
        afterStr = _filterAfter!.toString().split(' ')[0]; // YYYY-MM-DD
      }
      if (_filterBefore != null) {
        beforeStr = _filterBefore!.toString().split(' ')[0]; // YYYY-MM-DD
      }
    } else if (_filterRange != 'all') {
      // Calculate date range based on interval
      final now = DateTime.now();
      switch (_filterRange) {
        case 'today':
          afterStr = now.toString().split(' ')[0];
          break;
        case 'yesterday':
          final yesterday = now.subtract(const Duration(days: 1));
          afterStr = yesterday.toString().split(' ')[0];
          beforeStr = yesterday.toString().split(' ')[0];
          break;
        case 'week':
          final weekAgo = now.subtract(const Duration(days: 7));
          afterStr = weekAgo.toString().split(' ')[0];
          break;
        case 'month':
          final monthAgo = DateTime(now.year, now.month - 1, now.day);
          afterStr = monthAgo.toString().split(' ')[0];
          break;
        case 'year':
          final yearAgo = DateTime(now.year - 1, now.month, now.day);
          afterStr = yearAgo.toString().split(' ')[0];
          break;
      }
    }

    // Use multi-genre search with parallel requests
    vm.setMultiGenres(_filterGenres);

    // Set filter parameters
    vm.setFilters(
      sort: _filterSort != 'score' ? _filterSort : null,
      artistType: _filterArtistType != 'all' ? _filterArtistType : null,
      after: afterStr,
      before: beforeStr,
    );

    // Reload current tab to apply filters
    final tabs = [NgTab.featured, NgTab.latest, NgTab.popular];
    vm.reloadTab(tabs[_tabController.index]);
  }

  void _showTrackMenu(BuildContext context, Track track) {
    final lvm = context.read<LibraryViewModel>();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylist(context, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Add to Likes'),
              onTap: () async {
                Navigator.pop(ctx);
                await lvm.addStagedLike(track);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to Likes')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Blacklist'),
              onTap: () async {
                Navigator.pop(ctx);
                await lvm.addToBlacklist(track);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Track blacklisted')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddToPlaylist(BuildContext context, Track track) async {
    final lvm = context.read<LibraryViewModel>();
    final playlist = await showAddToPlaylistSheet(
      context,
      tracks: [track],
      lvm: lvm,
    );
    if (playlist == null || !context.mounted) return;
    await lvm.addTrackToPlaylist(playlist, track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to "${playlist.name}"')),
      );
    }
  }

  Future<void> _bypassCaptcha(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CaptchaBypassScreen()),
    );
    if (result == true && context.mounted) {
      final vm = context.read<NgViewModel>();
      final tabs = [NgTab.featured, NgTab.latest, NgTab.popular];
      vm.reloadTab(tabs[_tabController.index]);
    }
  }
}
