import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../data/model/track.dart';
import '../data/model/ng_user.dart';
import '../data/model/ng_audio_genres.dart';
import '../data/repository/ng_repository.dart';
import '../data/repository/ng_auth.dart';
import '../data/repository/cache_manager.dart';
import '../player/ng_audio_handler.dart';
import 'authors_viewmodel.dart';

enum NgTab { featured, latest, popular, topRated }

class TabState {
  List<Track> tracks = [];
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;
  int offset = 0;
  bool hasMore = false;
  bool loaded = false;
}

class NgViewModel extends ChangeNotifier {
  final NgRepository _repo = NgRepository();
  final NgAudioHandler audioHandler;

  final AuthorsViewModel? _authors;

  NgViewModel(this.audioHandler, {AuthorsViewModel? authors})
      : _authors = authors {
    _authors?.addListener(_onAuthorsChanged);
    audioHandler.playingStream.listen((_) => notifyListeners());
    audioHandler.processingStateStream.listen((state) {
      notifyListeners();
      if (state == NgProcessingState.completed) _onTrackCompleted();
    });
    audioHandler.positionStream.listen((_) => notifyListeners());
    audioHandler.durationStream.listen((_) => notifyListeners());

    audioHandler.onSkipToNext = () async => playNext();
    audioHandler.onSkipToPrevious = () async => playPrev();

    _tabs[NgTab.featured]!.hasMore = true;
    _tabs[NgTab.latest]!.hasMore = true;
    _tabs[NgTab.popular]!.hasMore = true;
    _tabs[NgTab.topRated]!.hasMore = true;

    loadTab(NgTab.featured);
    _tryLoadUser();
  }

  void _onAuthorsChanged() {
    final track = currentTrack;
    if (track != null && _authors!.isBlocked(track)) {
      _playGen++;
      currentTrack = null;
      isLoadingTrack = false;
      audioHandler.stop();
    }
    notifyListeners();
  }

  final _tabs = {
    NgTab.featured: TabState(),
    NgTab.latest: TabState(),
    NgTab.popular: TabState(),
    NgTab.topRated: TabState(),
  };

  TabState stateOf(NgTab tab) => _tabs[tab]!;

  Track? currentTrack;
  bool isLoadingTrack = false;
  String? playError;
  NgTab _activeTab = NgTab.featured;

  bool get isPlaying => audioHandler.isPlaying;
  Duration get position => audioHandler.position;
  Duration? get duration => audioHandler.duration;
  NgProcessingState get processingState => audioHandler.processingState;

  NgUser? currentUser;
  bool isLoadingUser = false;

  List<Track> searchResults = [];
  bool isSearching = false;
  String? searchError;
  String _lastQuery = '';
  bool _searchHasMore = false;
  int _searchOffset = 0;

  String get lastQuery => _lastQuery;

  void setActiveTab(NgTab tab) {
    _activeTab = tab;
    loadTab(tab);
  }

  void loadTab(NgTab tab) {
    final s = _tabs[tab]!;
    if (s.loaded && s.tracks.isNotEmpty) return;
    s.tracks = [];
    s.offset = 0;
    s.error = null;
    s.loaded = false;
    s.isLoading = true;
    notifyListeners();

    _fetchForTabWithMultiGenres(tab, 0).then((page) {
      final seen = <String>{};
      s.tracks = page.tracks.where((t) => seen.add(t.id)).toList();
      s.offset = page.nextOffset;
      s.hasMore = page.hasMore;
      s.isLoading = false;
      s.loaded = true;
      notifyListeners();
    }).catchError((e) {
      s.error = _errText(e, 'Ошибка загрузки');
      s.isLoading = false;
      notifyListeners();
    });
  }

  void reloadTab(NgTab tab) {
    _tabs[tab]!.loaded = false;
    loadTab(tab);
  }

  Future<void> loadMoreForTab(NgTab tab) async {
    final s = _tabs[tab]!;
    if (s.isLoadingMore || !s.hasMore) return;

    s.isLoadingMore = true;
    notifyListeners();

    try {
      final page = await _fetchForTabWithMultiGenres(tab, s.offset);
      s.offset = page.nextOffset;
      s.hasMore = page.hasMore;
      final more = page.tracks;
      if (more.isNotEmpty) {
        final ids = s.tracks.map((t) => t.id).toSet();
        final fresh = more.where((t) => !ids.contains(t.id)).toList();
        s.tracks = [...s.tracks, ...fresh];
      }
    } catch (e) {
      s.error = _errText(e, 'Ошибка');
    } finally {
      s.isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<List<Track>> _fetchForTab(NgTab tab, int offset, {String? genre}) {
    return switch (tab) {
      NgTab.featured => _repo.getFeaturedTracks(
          offset: offset,
          genre: genre,
          sort: filterSort,
          artistType: filterArtistType,
          after: filterAfter,
          before: filterBefore,
        ),
      NgTab.latest => _repo.getBrowseTracks(
          offset: offset,
          genre: genre,
          sort: filterSort,
          artistType: filterArtistType,
          after: filterAfter,
          before: filterBefore,
        ),
      NgTab.popular => _repo.getPopularTracks(
          offset: offset,
          genre: genre,
          sort: filterSort,
          artistType: filterArtistType,
          after: filterAfter,
          before: filterBefore,
        ),
      NgTab.topRated => _repo.getTopRatedTracks(offset: offset, genre: genre),
    };
  }

  Future<({List<Track> tracks, int nextOffset, bool hasMore})>
      _fetchForTabWithMultiGenres(NgTab tab, int offset) async {
    final selectedIds = multiGenres.isNotEmpty
        ? multiGenres
        : genre == null
            ? const <String>{}
            : <String>{genre!.id};
    final selectedLabels = NgAudioGenres.groups
        .expand((group) => group.genres)
        .where((item) => selectedIds.contains(item.id))
        .map((item) => item.label.toLowerCase())
        .toSet();

    var pageOffset = offset;
    while (true) {
      // Fetch one globally sorted page, then filter locally to preserve its order.
      final received = await _fetchForTab(tab, pageOffset);
      final filtered = selectedLabels.isEmpty
          ? received
          : received
              .where((track) =>
                  selectedLabels.contains(track.genre.trim().toLowerCase()))
              .toList();
      final nextOffset = pageOffset + received.length;
      final hasMore = received.length >= 30;
      if (filtered.isNotEmpty || !hasMore) {
        return (
          tracks: filtered,
          nextOffset: nextOffset,
          hasMore: hasMore,
        );
      }
      // Don't stop pagination just because a server page had no selected genres.
      pageOffset = nextOffset;
    }
  }

  NgGenre? genre;
  Set<String> multiGenres = {};

  // Filter parameters
  String? filterSort = 'date';
  String? filterArtistType = 'approved';
  String? filterAfter;
  String? filterBefore;

  void setGenre(NgGenre? g) {
    if (genre?.id == g?.id) return;
    genre = g;
    multiGenres.clear(); // Clear multi-genre when using single genre
    if (g != null) multiGenres.add(g.id);

    for (final s in _tabs.values) {
      s.tracks = [];
      s.offset = 0;
      s.error = null;
      s.loaded = false;
      s.hasMore = true;
    }
    loadTab(_activeTab);
  }

  void setMultiGenres(Set<String> genres) {
    if (genres.isEmpty) {
      genre = null;
      multiGenres.clear();
    } else {
      multiGenres = Set.from(genres);
      genre = null; // Clear single genre when using multi
    }

    for (final s in _tabs.values) {
      s.tracks = [];
      s.offset = 0;
      s.error = null;
      s.loaded = false;
      s.hasMore = true;
    }
    loadTab(_activeTab);
  }

  void setFilters({
    String? sort,
    String? artistType,
    String? after,
    String? before,
  }) {
    filterSort = sort;
    filterArtistType = artistType;
    filterAfter = after;
    filterBefore = before;

    // Reset all tabs
    for (final s in _tabs.values) {
      s.tracks = [];
      s.offset = 0;
      s.error = null;
      s.loaded = false;
      s.hasMore = true;
    }
    loadTab(_activeTab);
  }

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _lastQuery = q;
    _searchOffset = 0;
    _searchHasMore = true;
    searchResults = [];
    isSearching = true;
    searchError = null;
    notifyListeners();

    try {
      if (RegExp(r'^\d{4,8}$').hasMatch(q)) {
        final byId = await _repo.getTrackById(q);
        searchResults = byId != null ? [byId] : [];
        _searchHasMore = false;
        if (byId == null) {
          searchError = 'No track #$q on Newgrounds.';
        }
      } else {
        searchResults = await _repo.searchTracks(q, offset: 0);
        _searchHasMore = searchResults.length >= 24;
      }
    } catch (e) {
      searchError = _errText(e, 'Ошибка поиска');
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreSearch() async {
    if (!_searchHasMore || isSearching) return;
    _searchOffset += 24;
    isSearching = true;
    notifyListeners();
    try {
      final more = await _repo.searchTracks(_lastQuery, offset: _searchOffset);
      if (more.isEmpty) {
        _searchHasMore = false;
      } else {
        searchResults = [...searchResults, ...more];
      }
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    searchResults = [];
    _lastQuery = '';
    _searchHasMore = false;
    isSearching = false;
    searchError = null;
    notifyListeners();
  }

  bool get isInSearch => _lastQuery.isNotEmpty;

  Future<void> _tryLoadUser() async {
    if (!await NgAuth.isLoggedIn()) return;
    await fetchUser();
  }

  Future<void> fetchUser() async {
    isLoadingUser = true;
    notifyListeners();
    try {
      final username = await NgAuth.getUsername();
      if (username != null && username.isNotEmpty && username != 'unknown') {
        currentUser = await _repo.getUserProfile(username);
      } else {
        currentUser = await _repo.getCurrentUser();
      }
    } finally {
      isLoadingUser = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await NgAuth.logout();
    currentUser = null;
    notifyListeners();
  }

  Future<bool?> setFollow(String artist, bool follow) =>
      _repo.setFollow(artist, follow);

  Future<bool?> getFollowStatus(String artist) => _repo.getFollowStatus(artist);

  List<Track>? _contextTracks;

  /// Returns the current queue context (null if no queue)
  List<Track>? get queueContext =>
      _contextTracks?.where((t) => _authors?.isBlocked(t) != true).toList();

  void setQueueContext(List<Track>? tracks) {
    _contextTracks = tracks;
  }

  String _errText(Object e, String prefix) => e is NgSiteDownException
      ? 'Newgrounds лежит: на сайте техработы, приложение ни при чём. Попробуй позже.'
      : '$prefix: $e';

  bool _shuffle = false;
  bool get shuffle => _shuffle;

  int _repeat = 0;
  int get repeat => _repeat;

  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    _repeat = (_repeat + 1) % 3;
    notifyListeners();
  }

  List<Track> get _allTracks {
    final tracks = _contextTracks ??
        (isInSearch ? searchResults : _tabs[_activeTab]!.tracks);
    return tracks.where((t) => _authors?.isBlocked(t) != true).toList();
  }

  int _playGen = 0;

  Future<void> playTrack(Track track) async {
    if (_authors?.isBlocked(track) == true) return;
    if (currentTrack?.id == track.id &&
        !isLoadingTrack &&
        audioHandler.isPlaying) {
      notifyListeners();
      return;
    }
    final gen = ++_playGen;
    currentTrack = track;
    isLoadingTrack = true;
    playError = null;
    _lastCompletedId = null;
    notifyListeners();

    try {
      await audioHandler.stop();
    } catch (_) {}
    if (gen != _playGen) return;

    try {
      // Check if track is cached
      final cachedPath = await CacheManager.instance.getCachedPath(track.id);
      final cachedArtwork =
          await CacheManager.instance.getCachedArtworkPath(track.id);
      final cachedIcon =
          await CacheManager.instance.getCachedIconPath(track.id);

      // Attach local art to the track itself. The mini player can then show
      // it synchronously instead of waiting for another cache lookup.
      if (cachedArtwork != null) track.localCoverPath = cachedArtwork;
      if (cachedIcon != null) {
        track.iconUrl = cachedIcon;
      } else if (cachedArtwork != null && !track.hasLocalIcon) {
        track.iconUrl = cachedArtwork;
      }
      if (cachedArtwork != null || cachedIcon != null) notifyListeners();

      final artworkUri = cachedArtwork != null
          ? Uri.file(cachedArtwork)
          : Uri.tryParse(track.coverUrl);
      if (cachedPath != null) {
        // Use cached file
        await audioHandler.playUrl(
          'file://$cachedPath',
          title: track.title,
          artist: track.artist,
          artworkUri: artworkUri,
        );
        if (gen != _playGen) {
          try {
            await audioHandler.stop();
          } catch (_) {}
          return;
        }
      } else {
        // Stream from network
        if (track.mp3Url == null || track.mp3Url!.isEmpty) {
          await _repo.enrichTrack(track);
        }
        if (gen != _playGen) return;

        final url = track.mp3Url;
        if (url == null || url.isEmpty) {
          playError = 'Не удалось найти ссылку на трек';
        } else {
          await audioHandler.playUrl(
            url,
            title: track.title,
            artist: track.artist,
            artworkUri: artworkUri,
          );
          if (gen != _playGen) {
            try {
              await audioHandler.stop();
            } catch (_) {}
            return;
          }
        }
      }
    } catch (e) {
      if (gen == _playGen) playError = _errText(e, 'Ошибка воспроизведения');
    } finally {
      if (gen == _playGen) {
        isLoadingTrack = false;
        notifyListeners();
      }
    }
  }

  void togglePlayPause() {
    if (audioHandler.isPlaying) {
      audioHandler.pause();
    } else {
      audioHandler.play();
    }
    notifyListeners();
  }

  void seekTo(Duration position) => audioHandler.seek(position);

  String? _lastCompletedId;

  void _onTrackCompleted() {
    if (currentTrack == null || _lastCompletedId == currentTrack!.id) return;
    if (_repeat == 2) {
      audioHandler.seek(Duration.zero);
      audioHandler.play();
      notifyListeners();
      return;
    }
    _lastCompletedId = currentTrack!.id;
    if (_shuffle) {
      _playRandom();
      return;
    }
    final list = _allTracks;
    final idx = list.indexWhere((t) => t.id == currentTrack!.id);
    if (idx != -1 && idx + 1 < list.length) {
      playTrack(list[idx + 1]);
    } else if (_repeat == 1 && list.isNotEmpty) {
      playTrack(list.first);
    }
  }

  void _playRandom() {
    final list = _allTracks;
    if (list.length <= 1) return;
    final rng = math.Random();
    Track next;
    do {
      next = list[rng.nextInt(list.length)];
    } while (next.id == currentTrack?.id && list.length > 1);
    playTrack(next);
  }

  void playNext() {
    if (_shuffle) {
      _playRandom();
      return;
    }
    final list = _allTracks;
    final idx = list.indexWhere((t) => t.id == currentTrack?.id);
    if (idx != -1 && idx + 1 < list.length) {
      playTrack(list[idx + 1]);
    } else if (_repeat == 1 && list.isNotEmpty) {
      playTrack(list.first);
    }
  }

  void playPrev() {
    final list = _allTracks;
    final idx = list.indexWhere((t) => t.id == currentTrack?.id);
    if (idx > 0) playTrack(list[idx - 1]);
  }

  bool hasPrev() {
    final idx = _allTracks.indexWhere((t) => t.id == currentTrack?.id);
    return idx > 0;
  }

  bool hasNext() {
    if (_shuffle || _repeat == 1) return _allTracks.length > 1;
    if (_repeat == 2) return true;
    final list = _allTracks;
    final idx = list.indexWhere((t) => t.id == currentTrack?.id);
    return idx != -1 && idx + 1 < list.length;
  }

  @override
  void dispose() {
    _authors?.removeListener(_onAuthorsChanged);
    audioHandler.dispose();
    super.dispose();
  }
}
