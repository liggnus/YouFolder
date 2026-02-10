import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart' as yt;

import '../data/app_repository.dart';
import '../data/app_storage.dart';
import '../models/playlist.dart';
import '../models/shared_tree.dart';
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
  bool _quotaExceeded = false;
  final Map<String, List<VideoItem>> _sharedVideoCache = {};
  final Map<String, int> _preloadAtByAccount = {};
  static const Duration _preloadCooldown = Duration(minutes: 15);

  bool get isSignedIn => _account != null;
  bool get isBusy => _busy;
  String? get signedInEmail => _account?.email;
  bool isLoadingVideos(String playlistId) => _loadingVideos.contains(playlistId);
  bool get isSearchLoading => _searchLoading;
  double get searchProgress => _searchProgress;
  bool get isQuotaExceeded => _quotaExceeded;
  Map<String, List<VideoItem>> get sharedVideoCache => _sharedVideoCache;
  String get _cacheKey => signedInEmail ?? 'local';

  Future<void> init() async {
    _account = await _signIn.signInSilently();
    if (_account != null) {
      await _attachYouTubeApi();
      await syncPlaylists();
    }
    _loadSharedVideos();
    _loadPreloadAt();
    _loadVideoCache();
    notifyListeners();
  }

  void _loadSharedVideos() {
    final raw = storage.loadSharedVideos();
    _sharedVideoCache
      ..clear()
      ..addAll(
        raw.map(
          (key, value) => MapEntry(
            key,
            value.map(VideoItem.fromMap).toList(),
          ),
        ),
      );
  }

  void _loadPreloadAt() {
    _preloadAtByAccount
      ..clear()
      ..addAll(storage.loadPreloadAtByAccount());
  }

  void _loadVideoCache() {
    final raw = storage.loadVideoCache(_cacheKey);
    _videoCache
      ..clear()
      ..addAll(
        raw.map(
          (key, value) => MapEntry(
            key,
            value.map(VideoItem.fromMap).toList(),
          ),
        ),
      );
    for (final entry in _videoCache.entries) {
      if (repository.playlistById(entry.key) != null) {
        repository.updateVideoCount(entry.key, entry.value.length);
      }
    }
  }

  Future<void> _saveVideoCache() async {
    await storage.saveVideoCache(
      _cacheKey,
      _videoCache.map(
        (key, value) => MapEntry(
          key,
          value.map((video) => video.toMap()).toList(),
        ),
      ),
    );
  }

  Future<void> _savePreloadAt() async {
    await storage.savePreloadAtByAccount(_preloadAtByAccount);
  }

  Map<String, dynamic> buildTreeExport({
    required String name,
    List<String>? rootIds,
  }) {
    final allIds = <String>{};
    final roots = rootIds ??
        repository.rootPlaylists().map((playlist) => playlist.id).toList();
    for (final rootId in roots) {
      _collectSubtree(rootId, allIds);
    }
    final playlists = repository.playlists
        .where((playlist) => allIds.contains(playlist.id))
        .toList();
    final playlistChildIds = <String, List<String>>{};
    for (final entry in repository.playlistChildIds.entries) {
      if (!allIds.contains(entry.key)) {
        continue;
      }
      final children =
          entry.value.where((id) => allIds.contains(id)).toList();
      if (children.isNotEmpty) {
        playlistChildIds[entry.key] = children;
      }
    }
    final orderedRoots = roots.where(allIds.contains).toList();
    return {
      'version': 1,
      'treeName': name,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'playlists': playlists.map((playlist) => playlist.toMap()).toList(),
      'rootOrder': orderedRoots,
      'playlistChildIds': playlistChildIds,
    };
  }

  void _collectSubtree(String rootId, Set<String> out) {
    if (out.contains(rootId)) {
      return;
    }
    out.add(rootId);
    final children = repository.playlistChildIds[rootId] ?? <String>[];
    for (final child in children) {
      _collectSubtree(child, out);
    }
  }

  SharedTree parseSharedTreeJson(String jsonString) {
    final map = jsonDecode(jsonString) as Map<dynamic, dynamic>;
    final normalized = {
      ...map,
      'name': map['treeName'] ?? map['name'] ?? 'Shared tree',
    };
    return SharedTree.fromMap(normalized);
  }

  Future<void> importSharedTreeJson(String jsonString) async {
    final sharedTree = parseSharedTreeJson(jsonString);
    final idMap = <String, String>{};
    final now = DateTime.now().millisecondsSinceEpoch;

    for (var i = 0; i < sharedTree.playlists.length; i += 1) {
      final oldId = sharedTree.playlists[i].id;
      idMap[oldId] = 'import-$now-$i';
    }

    final wrapperId = 'import-root-$now';
    final sharedBy = sharedTree.sharedBy;
    final wrapper = Playlist(
      id: wrapperId,
      title: sharedTree.name,
      videoCount: 0,
      isYouTube: false,
      isShared: true,
      sharedBy: sharedBy,
    );
    repository.upsertPlaylist(wrapper);
    repository.addToRoot(wrapperId);

    for (final playlist in sharedTree.playlists) {
      final newId = idMap[playlist.id] ?? playlist.id;
      final videoCount =
          sharedTree.videosByPlaylist[playlist.id]?.length ?? 0;
      repository.upsertPlaylist(
        Playlist(
          id: newId,
          title: playlist.title,
          videoCount: videoCount,
          isYouTube: false,
          isPinned: playlist.isPinned,
          isFavorite: playlist.isFavorite,
          isHidden: playlist.isHidden,
          isShared: true,
          sharedBy: sharedBy,
        ),
      );
    }

    for (final entry in sharedTree.playlistChildIds.entries) {
      final parentId = idMap[entry.key];
      if (parentId == null) {
        continue;
      }
      final mappedChildren = entry.value
          .map((childId) => idMap[childId])
          .whereType<String>()
          .toList();
      repository.playlistChildIds[parentId] = mappedChildren;
    }

    final mappedRoots = sharedTree.rootOrder
        .map((rootId) => idMap[rootId])
        .whereType<String>()
        .toList();
    if (mappedRoots.isNotEmpty) {
      repository.playlistChildIds[wrapperId] = mappedRoots;
    }

    for (final entry in sharedTree.videosByPlaylist.entries) {
      final newId = idMap[entry.key];
      if (newId == null) {
        continue;
      }
      _sharedVideoCache[newId] = entry.value
          .map(
            (video) => VideoItem(
              playlistItemId: '',
              playlistId: newId,
              videoId: video.videoId,
              title: video.title,
              thumbnailUrl: video.thumbnailUrl,
            ),
          )
          .toList();
    }

    await storage.save(repository);
    await storage.saveSharedVideos(
      _sharedVideoCache.map(
        (key, value) => MapEntry(
          key,
          value.map((video) => video.toMap()).toList(),
        ),
      ),
    );
    notifyListeners();
  }

  Future<Map<String, dynamic>> buildTreeExportWithVideos({
    required String name,
    List<String>? rootIds,
  }) async {
    final export = buildTreeExport(name: name, rootIds: rootIds);
    export['sharedBy'] = signedInEmail ?? '';
    if (_youtubeService == null) {
      export['videosByPlaylist'] = <String, List<Map<String, dynamic>>>{};
      return export;
    }
    final playlists = (export['playlists'] as List?)
            ?.whereType<Map>()
            .map((entry) => entry['id']?.toString())
            .whereType<String>()
            .toList() ??
        <String>[];
    for (final playlistId in playlists) {
      await loadPlaylistVideos(playlistId);
    }
    final videosByPlaylist = <String, List<Map<String, dynamic>>>{};
    for (final playlistId in playlists) {
      final videos = _videoCache[playlistId] ?? <VideoItem>[];
      if (videos.isEmpty) {
        continue;
      }
      videosByPlaylist[playlistId] = videos
          .map(
            (video) => {
              'videoId': video.videoId,
              'title': video.title,
              'thumbnailUrl': video.thumbnailUrl,
            },
          )
          .toList();
    }
    export['videosByPlaylist'] = videosByPlaylist;
    return export;
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
    _loadPreloadAt();
    _loadVideoCache();
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
          isShared: playlist.isShared,
          sharedBy: playlist.sharedBy,
        );
      }).toList();
      final localPlaylists =
          repository.playlists.where((playlist) => !playlist.isYouTube).toList();
      repository.replacePlaylists([...mapped, ...localPlaylists]);
      await storage.save(repository);
      _setQuotaExceeded(false);
    } catch (error) {
      _setQuotaExceeded(_isQuotaExceededError(error));
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
      for (final id in playlistIds) {
        _sharedVideoCache.remove(id);
        _videoCache.remove(id);
      }
      await storage.saveSharedVideos(
        _sharedVideoCache.map(
          (key, value) => MapEntry(
            key,
            value.map((video) => video.toMap()).toList(),
          ),
        ),
      );
      await _saveVideoCache();
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

  Future<void> loadPlaylistVideos(String playlistId, {bool force = false}) async {
    if (_sharedVideoCache.containsKey(playlistId)) {
      _videoCache[playlistId] = _sharedVideoCache[playlistId] ?? <VideoItem>[];
      repository.updateVideoCount(
        playlistId,
        _videoCache[playlistId]?.length ?? 0,
      );
      notifyListeners();
      return;
    }
    if (_youtubeService == null) {
      _videoCache[playlistId] = <VideoItem>[];
      repository.updateVideoCount(playlistId, 0);
      notifyListeners();
      return;
    }
    if (!force && _videoCache.containsKey(playlistId)) {
      repository.updateVideoCount(
        playlistId,
        _videoCache[playlistId]?.length ?? 0,
      );
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
      _setQuotaExceeded(false);
      await _saveVideoCache();
    } catch (error) {
      _setQuotaExceeded(_isQuotaExceededError(error));
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
      await _saveVideoCache();
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
      await _saveVideoCache();
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<void> preloadAllVideos({bool force = false}) async {
    if (_youtubeService == null || _searchLoading) {
      return;
    }
    if (!force && _quotaExceeded) {
      return;
    }
    if (!force) {
      final lastAt = _preloadAtByAccount[_cacheKey] ?? 0;
      final lastTime = DateTime.fromMillisecondsSinceEpoch(lastAt);
      if (DateTime.now().difference(lastTime) < _preloadCooldown) {
        return;
      }
    }
    final playlists = repository.playlists;
    if (playlists.isEmpty) {
      return;
    }
    _searchLoading = true;
    _searchProgress = 0;
    notifyListeners();
    _preloadAtByAccount[_cacheKey] = DateTime.now().millisecondsSinceEpoch;
    await _savePreloadAt();
    try {
      for (var i = 0; i < playlists.length; i += 1) {
        final playlistId = playlists[i].id;
        if (force || !_videoCache.containsKey(playlistId)) {
          await loadPlaylistVideos(playlistId, force: force);
        }
        if (_quotaExceeded) {
          break;
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

  void _setQuotaExceeded(bool value) {
    if (_quotaExceeded == value) {
      return;
    }
    _quotaExceeded = value;
    notifyListeners();
  }

  bool _isQuotaExceededError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('quota') ||
        message.contains('quotaexceeded') ||
        message.contains('exceeded your');
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
    _sharedVideoCache.clear();
    _loadingVideos.clear();
    _searchLoading = false;
    _searchProgress = 0;
    _quotaExceeded = false;
    repository.replacePlaylists(<Playlist>[]);
    repository.rootOrder.clear();
    repository.playlistChildIds.clear();
    await storage.save(repository);
    await storage.saveSharedVideos(<String, List<Map<String, dynamic>>>{});
    notifyListeners();
  }
}
