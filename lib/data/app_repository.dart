import '../models/playlist.dart';

class AppRepository {
  AppRepository({
    required this.playlists,
    List<String>? rootOrder,
    Map<String, List<String>>? playlistChildIds,
  })  : rootOrder = rootOrder ?? <String>[],
        playlistChildIds = playlistChildIds ?? <String, List<String>>{};

  final List<Playlist> playlists;
  final List<String> rootOrder;
  final Map<String, List<String>> playlistChildIds;

  void replacePlaylists(List<Playlist> next) {
    playlists
      ..clear()
      ..addAll(next);
    _pruneLinks();
    _refreshRootOrder();
  }

  void upsertPlaylist(Playlist playlist) {
    final index = playlists.indexWhere((item) => item.id == playlist.id);
    if (index == -1) {
      playlists.add(playlist);
    } else {
      playlists[index] = playlist;
    }
    _pruneLinks();
  }

  List<Playlist> rootPlaylists() {
    final childIds = playlistChildIds.values.expand((ids) => ids).toSet();
    final rootIds = playlists
        .map((playlist) => playlist.id)
        .where((id) => !childIds.contains(id))
        .toList();
    if (rootOrder.isEmpty) {
      final items = rootIds
          .map((id) => playlistById(id))
          .whereType<Playlist>()
          .where((playlist) => !playlist.isHidden)
          .toList();
      return _pinnedFirst(items);
    }

    final ordered = <Playlist>[];
    final used = <String>{};
    for (final id in rootOrder) {
      if (rootIds.contains(id)) {
        final playlist = playlistById(id);
        if (playlist != null && !playlist.isHidden) {
          ordered.add(playlist);
          used.add(id);
        }
      }
    }
    for (final id in rootIds) {
      if (!used.contains(id)) {
        final playlist = playlistById(id);
        if (playlist != null && !playlist.isHidden) {
          ordered.add(playlist);
        }
      }
    }
    return _pinnedFirst(ordered);
  }

  List<Playlist> childPlaylists(String playlistId) {
    final ids = playlistChildIds[playlistId] ?? <String>[];
    final items = ids
        .map((id) => playlistById(id))
        .whereType<Playlist>()
        .where((playlist) => !playlist.isHidden)
        .toList();
    return _pinnedFirst(items);
  }

  void addChildPlaylist(String parentId, String childId) {
    _detachFromParents(childId);
    _removeFromRoot(childId);
    final ids = playlistChildIds.putIfAbsent(parentId, () => <String>[]);
    if (!ids.contains(childId)) {
      ids.add(childId);
    }
  }

  void removePlaylists(List<String> playlistIds) {
    playlists.removeWhere((playlist) => playlistIds.contains(playlist.id));
    rootOrder.removeWhere((id) => playlistIds.contains(id));
    playlistChildIds.removeWhere((key, value) => playlistIds.contains(key));
    playlistChildIds.updateAll((key, value) {
      return value.where((id) => !playlistIds.contains(id)).toList();
    });
  }

  void movePlaylistsToParent(List<String> playlistIds, String? parentId) {
    for (final playlistId in playlistIds) {
      _detachFromParents(playlistId);
      _removeFromRoot(playlistId);
      if (parentId == null) {
        addToRoot(playlistId);
      } else {
        final ids = playlistChildIds.putIfAbsent(parentId, () => <String>[]);
        if (!ids.contains(playlistId)) {
          ids.add(playlistId);
        }
        _clearSharedFlag(playlistId);
      }
    }
    playlistChildIds.removeWhere((key, value) => value.isEmpty);
  }

  Playlist? playlistById(String id) {
    for (final playlist in playlists) {
      if (playlist.id == id) {
        return playlist;
      }
    }
    return null;
  }

  String? parentIdOf(String playlistId) {
    for (final entry in playlistChildIds.entries) {
      if (entry.value.contains(playlistId)) {
        return entry.key;
      }
    }
    return null;
  }

  List<Playlist> pathToPlaylist(String playlistId) {
    final path = <Playlist>[];
    final visited = <String>{};
    var currentId = playlistId;
    while (!visited.contains(currentId)) {
      visited.add(currentId);
      final playlist = playlistById(currentId);
      if (playlist == null) {
        break;
      }
      path.add(playlist);
      final parentId = parentIdOf(currentId);
      if (parentId == null) {
        break;
      }
      currentId = parentId;
    }
    return path.reversed.toList();
  }

  void updateVideoCount(String playlistId, int count) {
    final index = playlists.indexWhere((item) => item.id == playlistId);
    if (index == -1) {
      return;
    }
    final existing = playlists[index];
    playlists[index] = Playlist(
      id: existing.id,
      title: existing.title,
      videoCount: count,
      isYouTube: existing.isYouTube,
      isPinned: existing.isPinned,
      isFavorite: existing.isFavorite,
      isHidden: existing.isHidden,
      isShared: existing.isShared,
      sharedBy: existing.sharedBy,
    );
  }

  void renamePlaylist(String playlistId, String title) {
    final index = playlists.indexWhere((item) => item.id == playlistId);
    if (index == -1) {
      return;
    }
    final existing = playlists[index];
    playlists[index] = Playlist(
      id: existing.id,
      title: title,
      videoCount: existing.videoCount,
      isYouTube: existing.isYouTube,
      isPinned: existing.isPinned,
      isFavorite: existing.isFavorite,
      isHidden: existing.isHidden,
      isShared: existing.isShared ? false : existing.isShared,
      sharedBy: existing.isShared ? null : existing.sharedBy,
    );
  }

  void setPinned(String playlistId, bool pinned) {
    final index = playlists.indexWhere((item) => item.id == playlistId);
    if (index == -1) {
      return;
    }
    final existing = playlists[index];
    playlists[index] = Playlist(
      id: existing.id,
      title: existing.title,
      videoCount: existing.videoCount,
      isYouTube: existing.isYouTube,
      isPinned: pinned,
      isFavorite: existing.isFavorite,
      isHidden: existing.isHidden,
      isShared: existing.isShared,
      sharedBy: existing.sharedBy,
    );
  }

  void setFavorite(String playlistId, bool favorite) {
    final index = playlists.indexWhere((item) => item.id == playlistId);
    if (index == -1) {
      return;
    }
    final existing = playlists[index];
    playlists[index] = Playlist(
      id: existing.id,
      title: existing.title,
      videoCount: existing.videoCount,
      isYouTube: existing.isYouTube,
      isPinned: existing.isPinned,
      isFavorite: favorite,
      isHidden: existing.isHidden,
      isShared: existing.isShared,
      sharedBy: existing.sharedBy,
    );
  }

  void setHidden(String playlistId, bool hidden) {
    final index = playlists.indexWhere((item) => item.id == playlistId);
    if (index == -1) {
      return;
    }
    final existing = playlists[index];
    playlists[index] = Playlist(
      id: existing.id,
      title: existing.title,
      videoCount: existing.videoCount,
      isYouTube: existing.isYouTube,
      isPinned: existing.isPinned,
      isFavorite: existing.isFavorite,
      isHidden: hidden,
      isShared: existing.isShared,
      sharedBy: existing.sharedBy,
    );
  }

  void _clearSharedFlag(String playlistId) {
    final index = playlists.indexWhere((item) => item.id == playlistId);
    if (index == -1) {
      return;
    }
    final existing = playlists[index];
    if (!existing.isShared) {
      return;
    }
    playlists[index] = Playlist(
      id: existing.id,
      title: existing.title,
      videoCount: existing.videoCount,
      isYouTube: existing.isYouTube,
      isPinned: existing.isPinned,
      isFavorite: existing.isFavorite,
      isHidden: existing.isHidden,
      isShared: false,
      sharedBy: null,
    );
  }

  void addToRoot(String playlistId) {
    _removeFromRoot(playlistId);
    rootOrder.add(playlistId);
  }

  void reorderRoot(List<String> orderedIds) {
    rootOrder
      ..clear()
      ..addAll(orderedIds);
  }

  void reorderChildren(String parentId, List<String> orderedIds) {
    playlistChildIds[parentId] = orderedIds;
  }

  void _pruneLinks() {
    final playlistIds = playlists.map((playlist) => playlist.id).toSet();
    playlistChildIds.removeWhere((key, value) => !playlistIds.contains(key));
    playlistChildIds.updateAll((key, value) {
      return value.where(playlistIds.contains).toList();
    });
  }

  void _refreshRootOrder() {
    final childIds = playlistChildIds.values.expand((ids) => ids).toSet();
    final rootIds = playlists
        .map((playlist) => playlist.id)
        .where((id) => !childIds.contains(id))
        .toSet();
    rootOrder.removeWhere((id) => !rootIds.contains(id));
    for (final id in rootIds) {
      if (!rootOrder.contains(id)) {
        rootOrder.add(id);
      }
    }
  }

  void _detachFromParents(String playlistId) {
    playlistChildIds.updateAll((key, value) {
      return value.where((id) => id != playlistId).toList();
    });
  }

  void _removeFromRoot(String playlistId) {
    rootOrder.removeWhere((id) => id == playlistId);
  }

  List<Playlist> _pinnedFirst(List<Playlist> items) {
    final pinned = <Playlist>[];
    final normal = <Playlist>[];
    for (final item in items) {
      if (item.isPinned) {
        pinned.add(item);
      } else {
        normal.add(item);
      }
    }
    return [...pinned, ...normal];
  }
}
