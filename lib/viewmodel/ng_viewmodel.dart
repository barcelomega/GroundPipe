import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/model/track.dart';
import '../data/model/ng_user.dart';
import '../data/model/ng_audio_genres.dart';
import '../data/repository/ng_repository.dart';
import '../data/repository/ng_auth.dart';
import '../data/repository/cache_manager.dart';
import '../data/repository/cover_failure_cache.dart';
import '../data/repository/waveform_cache.dart';
import '../data/repository/multi_genre_feed.dart';
import '../player/ng_audio_handler.dart';
import 'authors_viewmodel.dart';
import 'library_viewmodel.dart';

enum NgTab { featured, latest, popular, topRated }

class TabState {
  List<Track> tracks = [];
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;
  int offset = 0;
  bool hasMore = false;
  bool loaded = false;
  int generation = 0;
}

class NgViewModel extends ChangeNotifier {
  final NgRepository _repo = NgRepository();
  final NgAudioHandler audioHandler;

  final AuthorsViewModel? _authors;
  final LibraryViewModel? _library;

  NgViewModel(this.audioHandler,
      {AuthorsViewModel? authors, LibraryViewModel? library})
      : _authors = authors,
        _library = library {
    _authors?.addListener(_onAuthorsChanged);
    _library?.addListener(_onLibraryChanged);
    audioHandler.playingStream.listen((_) => notifyListeners());
    audioHandler.processingStateStream.listen((state) {
      notifyListeners();
      if (state == NgProcessingState.completed) _onTrackCompleted();
    });
    audioHandler.positionStream.listen((_) => notifyListeners());
    audioHandler.durationStream.listen((_) => notifyListeners());

    audioHandler.onSkipToNext = () async => playNext();
    audioHandler.onSkipToPrevious = () async => playPrev();
    audioHandler.onToggleLike = _toggleCurrentTrackLike;

    _tabs[NgTab.featured]!.hasMore = true;
    _tabs[NgTab.latest]!.hasMore = true;
    _tabs[NgTab.popular]!.hasMore = true;
    _tabs[NgTab.topRated]!.hasMore = true;

    loadTab(NgTab.featured);
    _tryLoadUser();
    _restorePlayerSettings();
  }

  void _onAuthorsChanged() {
    final track = currentTrack;
    if (track != null && _authors!.isBlocked(track)) {
      _playGen++;
      currentTrack = null;
      isLoadingTrack = false;
      audioHandler.stop();
      _lastNotificationLiked = false;
      unawaited(audioHandler.setLiked(false));
    }
    notifyListeners();
  }

  void _onLibraryChanged() => _syncNotificationLike();

  bool? _lastNotificationLiked;

  void _syncNotificationLike() {
    final track = currentTrack;
    final library = _library;
    if (track == null || library == null) return;
    final liked = library.isStagedLike(track.id);
    if (_lastNotificationLiked == liked) return;
    _lastNotificationLiked = liked;
    unawaited(audioHandler.setLiked(liked));
  }

  bool _likeBusy = false;

  Future<void> _toggleCurrentTrackLike() async {
    final track = currentTrack;
    final library = _library;
    if (track == null || library == null || _likeBusy) return;
    _likeBusy = true;
    try {
      if (library.isStagedLike(track.id)) {
        await library.removeStagedLike(track.id);
      } else {
        await library.addStagedLike(track);
      }
    } catch (_) {
      // Leave the notification state unchanged if storage fails.
      return;
    } finally {
      _likeBusy = false;
    }
    _syncNotificationLike();
    if (!_disposed) notifyListeners();
  }

  final _tabs = {
    NgTab.featured: TabState(),
    NgTab.latest: TabState(),
    NgTab.popular: TabState(),
    NgTab.topRated: TabState(),
  };

  final _genreFeeds = <NgTab, MultiGenreFeed>{};

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
  bool isLoadingMoreSearch = false;
  String? searchError;
  String _lastQuery = '';
  bool _searchHasMore = false;
  int _searchOffset = 0;
  int _searchGen = 0;

  String get lastQuery => _lastQuery;
  bool get searchHasMore => _searchHasMore;

  void setActiveTab(NgTab tab) {
    _activeTab = tab;
    loadTab(tab);
  }

  void loadTab(NgTab tab) {
    final s = _tabs[tab]!;
    if (s.loaded && s.tracks.isNotEmpty) return;
    _genreFeeds.remove(tab);
    s.tracks = [];
    s.offset = 0;
    s.error = null;
    s.loaded = false;
    s.isLoading = true;
    s.isLoadingMore = false;
    final generation = ++s.generation;
    notifyListeners();

    _fetchForTabPage(tab, 0).then((page) {
      if (generation != s.generation) return;
      final seen = <String>{};
      s.tracks = page.tracks.where((t) => seen.add(t.id)).toList();
      s.offset = page.nextOffset;
      s.hasMore = page.hasMore;
      s.isLoading = false;
      s.loaded = true;
      notifyListeners();
    }).catchError((e) {
      if (generation != s.generation) return;
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
    if (s.isLoading || s.isLoadingMore || !s.hasMore) return;

    s.isLoadingMore = true;
    final generation = s.generation;
    notifyListeners();

    try {
      final page = await _fetchForTabPage(tab, s.offset);
      if (generation != s.generation) return;
      s.offset = page.nextOffset;
      s.hasMore = page.hasMore;
      final more = page.tracks;
      if (more.isNotEmpty) {
        final ids = s.tracks.map((t) => t.id).toSet();
        final fresh = more.where((t) => !ids.contains(t.id)).toList();
        s.tracks = [...s.tracks, ...fresh];
      }
    } catch (e) {
      if (generation != s.generation) return;
      s.error = _errText(e, 'Ошибка');
    } finally {
      if (generation == s.generation) {
        s.isLoadingMore = false;
        notifyListeners();
      }
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

  Future<({List<Track> tracks, int nextOffset, bool hasMore})> _fetchForTabPage(
      NgTab tab, int offset) async {
    final selectedIds = _selectedGenreIds;
    if (selectedIds.isEmpty) {
      final received = await _fetchForTab(tab, offset);
      return (
        tracks: received,
        nextOffset: offset + received.length,
        hasMore: received.isNotEmpty,
      );
    }

    final feed = _genreFeedFor(tab, selectedIds);
    final tracks = await feed.take(MultiGenreFeed.pageSize);
    return (
      tracks: tracks,
      nextOffset: 0,
      hasMore: feed.hasMore,
    );
  }

  Set<String> get _selectedGenreIds => multiGenres.isNotEmpty
      ? multiGenres
      : genre == null
          ? const <String>{}
          : <String>{genre!.id};

  GenreSort get _genreSort => switch (filterSort) {
        'score' => GenreSort.score,
        'views' => GenreSort.views,
        _ => GenreSort.date,
      };

  MultiGenreFeed _genreFeedFor(NgTab tab, Set<String> selectedIds) {
    final existing = _genreFeeds[tab];
    if (existing != null && existing.matches(selectedIds, _genreSort)) {
      return existing;
    }
    final feed = MultiGenreFeed(
      genres: selectedIds.toList()..sort(),
      sort: _genreSort,
      loadPage: (genreId, offset) => _fetchForTab(tab, offset, genre: genreId),
    );
    _genreFeeds[tab] = feed;
    return feed;
  }

  NgGenre? genre;
  Set<String> multiGenres = {};

  // Filter parameters
  String? filterSort = 'date';
  String? filterArtistType = 'approved';
  String? filterAfter;
  String? filterBefore;

  void setGenre(NgGenre? g) {
    final sameGenre = genre?.id == g?.id;
    if (sameGenre && (g != null || multiGenres.isEmpty)) return;
    genre = g;
    multiGenres.clear(); // Clear multi-genre when using single genre
    if (g != null) multiGenres.add(g.id);
    _resetTabs();
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
    _resetTabs();
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
    _resetTabs();
    loadTab(_activeTab);
  }

  /// Applies every Discover filter in one step so the tab is loaded only once.
  void applyDiscoverFilters({
    required Set<String> genres,
    String? sort,
    String? artistType,
    String? after,
    String? before,
    NgTab? tab,
  }) {
    if (genres.isEmpty) {
      genre = null;
      multiGenres.clear();
    } else {
      multiGenres = Set.from(genres);
      genre = null;
    }
    filterSort = sort;
    filterArtistType = artistType;
    filterAfter = after;
    filterBefore = before;
    _resetTabs();
    final target = tab ?? _activeTab;
    _activeTab = target;
    loadTab(target);
  }

  void _resetTabs() {
    _genreFeeds.clear();
    for (final s in _tabs.values) {
      s.tracks = [];
      s.offset = 0;
      s.error = null;
      s.loaded = false;
      s.hasMore = true;
      s.isLoading = false;
      s.isLoadingMore = false;
      s.generation++;
    }
  }

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final gen = ++_searchGen;
    _lastQuery = q;
    _searchOffset = 0;
    _searchHasMore = true;
    searchResults = [];
    isSearching = true;
    isLoadingMoreSearch = false;
    searchError = null;
    notifyListeners();

    try {
      if (RegExp(r'^\d{4,8}$').hasMatch(q)) {
        final byId = await _repo.getTrackById(q);
        if (gen != _searchGen) return;
        searchResults = byId != null ? [byId] : [];
        _searchHasMore = false;
        if (byId == null) {
          searchError = 'No track #$q on Newgrounds.';
        }
      } else {
        final found = await _repo.searchTracks(q, offset: 0);
        if (gen != _searchGen) return;
        final seen = <String>{};
        searchResults = found.where((t) => seen.add(t.id)).toList();
        _searchHasMore = found.isNotEmpty;
      }
    } catch (e) {
      if (gen == _searchGen) searchError = _errText(e, 'Ошибка поиска');
    } finally {
      if (gen == _searchGen) {
        isSearching = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreSearch() async {
    if (!_searchHasMore || isSearching || isLoadingMoreSearch) return;
    final gen = _searchGen;
    final query = _lastQuery;
    final offset = _searchOffset + 24;
    isLoadingMoreSearch = true;
    notifyListeners();
    try {
      final more = await _repo.searchTracks(query, offset: offset);
      if (gen != _searchGen) return;
      _searchOffset = offset;
      final seen = searchResults.map((t) => t.id).toSet();
      final fresh = more.where((t) => seen.add(t.id)).toList();
      searchResults = [...searchResults, ...fresh];
      _searchHasMore = more.isNotEmpty && fresh.isNotEmpty;
    } catch (_) {
      // Keep the current page visible; stop the sentinel from retrying
      // in a tight loop until the user refreshes.
      if (gen == _searchGen) _searchHasMore = false;
    } finally {
      if (gen == _searchGen) {
        isLoadingMoreSearch = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    _searchGen++;
    searchResults = [];
    _lastQuery = '';
    _searchHasMore = false;
    _searchOffset = 0;
    isSearching = false;
    isLoadingMoreSearch = false;
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

  static const _kPlayerShuffle = 'player_shuffle';
  static const _kPlayerRepeat = 'player_repeat';
  static const _kPlayerSpeed = 'player_speed';
  static const _kPlayerPitch = 'player_pitch';
  static const _kPlayerSpeedPitchChained = 'player_speed_pitch_chained';

  bool _shuffle = false;
  bool get shuffle => _shuffle;

  int _repeat = 0;
  int get repeat => _repeat;

  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;

  double _playbackPitch = 0.0;
  double get playbackPitch => _playbackPitch;

  bool _speedPitchChained = false;
  bool get speedPitchChained => _speedPitchChained;

  bool _disposed = false;

  Future<void> _restorePlayerSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _shuffle = prefs.getBool(_kPlayerShuffle) ?? _shuffle;
      final repeat = prefs.getInt(_kPlayerRepeat);
      if (repeat != null && repeat >= 0 && repeat <= 2) _repeat = repeat;
      _playbackSpeed = (prefs.getDouble(_kPlayerSpeed) ?? 1.0).clamp(0.2, 3.0);
      _playbackPitch = (prefs.getDouble(_kPlayerPitch) ?? 0.0).clamp(-12.0, 12.0);
      _speedPitchChained = prefs.getBool(_kPlayerSpeedPitchChained) ?? false;
      // Push the restored values to the audio engine. Without this the sliders
      // show the saved speed/pitch but playback keeps the defaults.
      unawaited(audioHandler.setSpeed(_playbackSpeed));
      unawaited(audioHandler.setPitch(_playbackPitch));
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Preferences are best-effort; keep the defaults.
    }
  }

  Future<void> _persistPlayerSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPlayerShuffle, _shuffle);
      await prefs.setInt(_kPlayerRepeat, _repeat);
      await prefs.setDouble(_kPlayerSpeed, _playbackSpeed);
      await prefs.setDouble(_kPlayerPitch, _playbackPitch);
      await prefs.setBool(_kPlayerSpeedPitchChained, _speedPitchChained);
    } catch (_) {
      // Ignore storage failures.
    }
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    unawaited(_persistPlayerSettings());
    notifyListeners();
  }

  void cycleRepeat() {
    _repeat = (_repeat + 1) % 3;
    unawaited(_persistPlayerSettings());
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed.clamp(0.2, 3.0);
    if (_speedPitchChained) {
      _playbackPitch = ((math.log(_playbackSpeed) / math.ln2) * 12).clamp(-12.0, 12.0);
    }
    unawaited(audioHandler.setSpeed(_playbackSpeed));
    if (_speedPitchChained) {
      unawaited(audioHandler.setPitch(_playbackPitch));
    }
    unawaited(_persistPlayerSettings());
    notifyListeners();
  }

  void setPlaybackPitch(double semitones) {
    _playbackPitch = semitones.clamp(-12.0, 12.0);
    if (_speedPitchChained) {
      _playbackSpeed = (math.pow(2.0, _playbackPitch / 12) as double).clamp(0.2, 3.0);
    }
    unawaited(audioHandler.setPitch(_playbackPitch));
    if (_speedPitchChained) {
      unawaited(audioHandler.setSpeed(_playbackSpeed));
    }
    unawaited(_persistPlayerSettings());
    notifyListeners();
  }

  void toggleSpeedPitchChain() {
    _speedPitchChained = !_speedPitchChained;
    unawaited(_persistPlayerSettings());
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
    _syncNotificationLike();
    isLoadingTrack = true;
    playError = null;
    _lastCompletedId = null;

    // Waveform loading is independent of the MP3 source and starts before
    // notifying the player. Widgets join this same request when opened.
    unawaited(WaveformImageCache.instance.prepare(track));
    CoverFailureCache.instance.keepOnly(track.id);
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
          // Notify listeners to update UI with enriched data (e.g., peaksUrl)
          if (gen == _playGen) {
            notifyListeners();
          }
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
    _disposed = true;
    _authors?.removeListener(_onAuthorsChanged);
    _library?.removeListener(_onLibraryChanged);
    audioHandler.dispose();
    super.dispose();
  }
}
