import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart' as yt;

import '../data/app_repository.dart';
import '../data/app_storage.dart';
import '../models/playlist.dart';
import '../models/video_item.dart';
import '../services/google_auth_client.dart';
import '../services/youtube_service.dart';

enum PlaylistCreateResult {
  localOnly,
  syncedToYouTube,
  syncFailed,
}

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.storage,
    required GoogleSignIn signIn,
  }) : _signIn = signIn;

  final AppRepository repository;
  final AppStorage storage;
  final GoogleSignIn _signIn;

  GoogleSignInAccount? _account;
  GoogleAuthClient? _authClient;
  YouTubeService? _youtubeService;
  bool _busy = false;
  final Map<String, List<VideoItem>> _videoCache = {};
  final Set<String> _loadingVideos = {};
  bool _searchLoading = false;
  double _searchProgress = 0;

  bool get isSignedIn => _account != null;
  bool get isBusy => _busy;
  String? get signedInEmail => _account?.email;
  bool isLoadingVideos(String playlistId) => _loadingVideos.contains(playlistId);
  bool get isSearchLoading => _searchLoading;
  double get searchProgress => _searchProgress;

  Future<void> init() async {
    _account = await _signIn.signInSilently();
    if (_account != null) {
      await _attachYouTubeApi();
      await syncPlaylists();
    }
    notifyListeners();
  }

  Future<void> connect() async {
    _setBusy(true);
    try {
      _account = await _signIn.signIn();
      if (_account != null) {
        await _attachYouTubeApi();
        await syncPlaylists();
      }
    } finally {
      _setBusy(false);
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _signIn.disconnect();
    await _clearSessionData();
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    await _clearSessionData();
  }

  Future<void> switchAccount() async {
    await signOut();
    await connect();
  }

  Future<void> syncPlaylists() async {
    if (_youtubeService == null) {
      return;
    }
    _setBusy(true);
    try {
      final hiddenIds = repository.playlists
          .where((playlist) => playlist.isHidden)
          .map((playlist) => playlist.id)
          .toSet();
      final playlists = await _youtubeService!.fetchAllPlaylists();
      final mapped = playlists.map(_mapPlaylist).map((playlist) {
        if (!hiddenIds.contains(playlist.id)) {
          return playlist;
        }
        return Playlist(
          id: playlist.id,
          title: playlist.title,
          videoCount: playlist.videoCount,
          isYouTube: playlist.isYouTube,
          isPinned: playlist.isPinned,
          isFavorite: playlist.isFavorite,
          isHidden: true,
        );
      }).toList();
      repository.replacePlaylists(mapped);
      await storage.save(repository);
    } catch (error) {
      debugPrint('YouTube sync failed: $error');
    } finally {
      _setBusy(false);
    }
  }

  Future<PlaylistCreateResult> createPlaylist(
    String name, {
    String? parentId,
  }) async {
    if (_youtubeService == null) {
      final playlist = Playlist(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        title: name,
        videoCount: 0,
        isYouTube: false,
        isHidden: false,
      );
      repository.upsertPlaylist(playlist);
      if (parentId != null) {
        repository.addChildPlaylist(parentId, playlist.id);
      } else {
        repository.addToRoot(playlist.id);
      }
      await storage.save(repository);
      notifyListeners();
      return PlaylistCreateResult.localOnly;
    }

    _setBusy(true);
    try {
      final created = await _youtubeService!.createPlaylist(name);
      if (created?.id == null) {
        return PlaylistCreateResult.syncFailed;
      }
      final playlist = _mapPlaylist(created!);
      repository.upsertPlaylist(playlist);
      if (parentId != null) {
        repository.addChildPlaylist(parentId, playlist.id);
      } else {
        repository.addToRoot(playlist.id);
      }
      await storage.save(repository);
      return PlaylistCreateResult.syncedToYouTube;
    } catch (error) {
      debugPrint('YouTube playlist create failed: $error');
      return PlaylistCreateResult.syncFailed;
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<void> addChildPlaylist(String playlistId, String childId) async {
    repository.addChildPlaylist(playlistId, childId);
    await storage.save(repository);
    notifyListeners();
  }

  Future<void> movePlaylistsToFolder(
    List<String> playlistIds,
    String? folderId,
  ) async {
    repository.movePlaylistsToParent(playlistIds, folderId);
    await storage.save(repository);
    notifyListeners();
  }

  Future<void> deletePlaylists(List<String> playlistIds) async {
    if (playlistIds.isEmpty) {
      return;
    }

    _setBusy(true);
    try {
      if (_youtubeService != null) {
        for (final id in playlistIds) {
          final playlist = repository.playlistById(id);
          if (playlist != null && playlist.isYouTube) {
            try {
              await _youtubeService!.deletePlaylist(id);
            } catch (error) {
              debugPrint('YouTube delete failed for $id: $error');
            }
          }
        }
      }
      repository.removePlaylists(playlistIds);
      await storage.save(repository);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> reorderRootPlaylists(List<String> orderedIds) async {
    repository.reorderRoot(orderedIds);
    await storage.save(repository);
    notifyListeners();
  }

  Future<void> reorderChildPlaylists(
    String parentId,
    List<String> orderedIds,
  ) async {
    repository.reorderChildren(parentId, orderedIds);
    await storage.save(repository);
    notifyListeners();
  }

  Future<void> renamePlaylist(String playlistId, String title) async {
    if (title.trim().isEmpty) {
      return;
    }
    _setBusy(true);
    try {
      final playlist = repository.playlistById(playlistId);
      if (playlist != null && playlist.isPinned) {
        repository.renamePlaylist(playlistId, title);
        await storage.save(repository);
        return;
      }
      if (_youtubeService != null && playlist != null && playlist.isYouTube) {
        await _youtubeService!.updatePlaylistTitle(playlistId, title);
      }
      repository.renamePlaylist(playlistId, title);
      await storage.save(repository);
    } catch (error) {
      debugPrint('YouTube rename failed for $playlistId: $error');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> setPinned(List<String> playlistIds, bool pinned) async {
    for (final id in playlistIds) {
      repository.setPinned(id, pinned);
    }
    await storage.save(repository);
    notifyListeners();
  }

  Future<void> setFavorite(List<String> playlistIds, bool favorite) async {
    for (final id in playlistIds) {
      repository.setFavorite(id, favorite);
    }
    await storage.save(repository);
    notifyListeners();
  }

  Future<void> setHidden(List<String> playlistIds, bool hidden) async {
    for (final id in playlistIds) {
      repository.setHidden(id, hidden);
    }
    await storage.save(repository);
    notifyListeners();
  }

  List<VideoItem> videosForPlaylist(String playlistId) {
    return _videoCache[playlistId] ?? <VideoItem>[];
  }

  List<VideoItem> allCachedVideos() {
    return _videoCache.values.expand((items) => items).toList();
  }

  Future<void> loadPlaylistVideos(String playlistId) async {
    if (_youtubeService == null) {
      _videoCache[playlistId] = <VideoItem>[];
      repository.updateVideoCount(playlistId, 0);
      notifyListeners();
      return;
    }
    if (_loadingVideos.contains(playlistId)) {
      return;
    }
    _loadingVideos.add(playlistId);
    notifyListeners();
    try {
      final items = await _youtubeService!.fetchPlaylistItems(playlistId);
      final videos = items.map((item) => _mapVideo(item)).toList();
      _videoCache[playlistId] = videos;
      repository.updateVideoCount(playlistId, videos.length);
    } catch (error) {
      debugPrint('YouTube playlist items failed: $error');
    } finally {
      _loadingVideos.remove(playlistId);
      notifyListeners();
    }
  }

  Future<void> deletePlaylistItems(
    String playlistId,
    List<String> playlistItemIds,
  ) async {
    if (_youtubeService == null || playlistItemIds.isEmpty) {
      return;
    }
    _setBusy(true);
    try {
      for (final itemId in playlistItemIds) {
        try {
          await _youtubeService!.deletePlaylistItem(itemId);
        } catch (error) {
          debugPrint('YouTube delete item failed for $itemId: $error');
        }
      }
      final existing = _videoCache[playlistId] ?? <VideoItem>[];
      _videoCache[playlistId] = existing
          .where((item) => !playlistItemIds.contains(item.playlistItemId))
          .toList();
      repository.updateVideoCount(playlistId, _videoCache[playlistId]!.length);
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<void> movePlaylistItems(
    String fromPlaylistId,
    String toPlaylistId,
    List<VideoItem> items,
  ) async {
    if (_youtubeService == null || items.isEmpty) {
      return;
    }
    _setBusy(true);
    try {
      for (final item in items) {
        try {
          await _youtubeService!.addVideoToPlaylist(toPlaylistId, item.videoId);
          await _youtubeService!.deletePlaylistItem(item.playlistItemId);
        } catch (error) {
          debugPrint('YouTube move item failed for ${item.videoId}: $error');
        }
      }
      final itemIds = items.map((item) => item.playlistItemId).toSet();
      final existing = _videoCache[fromPlaylistId] ?? <VideoItem>[];
      _videoCache[fromPlaylistId] = existing
          .where((item) => !itemIds.contains(item.playlistItemId))
          .toList();
      repository.updateVideoCount(
        fromPlaylistId,
        _videoCache[fromPlaylistId]!.length,
      );

      final playlist = repository.playlistById(toPlaylistId);
      if (playlist != null) {
        repository.updateVideoCount(
          toPlaylistId,
          playlist.videoCount + items.length,
        );
      }
      _videoCache.remove(toPlaylistId);
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<void> preloadAllVideos() async {
    if (_youtubeService == null || _searchLoading) {
      return;
    }
    final playlists = repository.playlists;
    if (playlists.isEmpty) {
      return;
    }
    _searchLoading = true;
    _searchProgress = 0;
    notifyListeners();
    try {
      for (var i = 0; i < playlists.length; i += 1) {
        final playlistId = playlists[i].id;
        if (!_videoCache.containsKey(playlistId)) {
          await loadPlaylistVideos(playlistId);
        }
        _searchProgress = (i + 1) / playlists.length;
        notifyListeners();
      }
    } finally {
      _searchLoading = false;
      notifyListeners();
    }
  }

  Future<void> _attachYouTubeApi() async {
    if (_account == null) {
      return;
    }
    _authClient?.close();
    final headers = await _account!.authHeaders;
    _authClient = GoogleAuthClient(headers);
    _youtubeService = YouTubeService(yt.YouTubeApi(_authClient!));
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  Playlist _mapPlaylist(yt.Playlist playlist) {
    return Playlist(
      id: playlist.id ?? '',
      title: playlist.snippet?.title ?? 'Untitled playlist',
      videoCount: playlist.contentDetails?.itemCount ?? 0,
      isYouTube: true,
      isHidden: false,
    );
  }

  VideoItem _mapVideo(yt.PlaylistItem item) {
    final snippet = item.snippet;
    final thumbnail = snippet?.thumbnails?.high ??
        snippet?.thumbnails?.medium ??
        snippet?.thumbnails?.default_;
    return VideoItem(
      playlistItemId: item.id ?? '',
      playlistId: snippet?.playlistId ?? '',
      videoId: snippet?.resourceId?.videoId ?? '',
      title: snippet?.title ?? 'Untitled video',
      thumbnailUrl: thumbnail?.url ?? '',
    );
  }

  Future<void> _clearSessionData() async {
    _account = null;
    _authClient?.close();
    _authClient = null;
    _youtubeService = null;
    _busy = false;
    _videoCache.clear();
    _loadingVideos.clear();
    _searchLoading = false;
    _searchProgress = 0;
    repository.replacePlaylists(<Playlist>[]);
    repository.rootOrder.clear();
    repository.playlistChildIds.clear();
    await storage.save(repository);
    notifyListeners();
  }
}
