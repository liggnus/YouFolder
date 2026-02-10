import 'package:hive/hive.dart';

import '../models/playlist.dart';
import 'app_repository.dart';

class AppStorage {
  static const String boxName = 'youfolder';
  static const String keyPlaylists = 'playlists';
  static const String keyPlaylistChildIds = 'playlistChildIds';
  static const String keyRootOrder = 'rootOrder';
  static const String keySharedVideos = 'sharedVideos';
  static const String keyVideoCache = 'videoCache';
  static const String keyVideoCacheByAccount = 'videoCacheByAccount';
  static const String keyPreloadAtByAccount = 'preloadAtByAccount';

  Future<AppRepository> load() async {
    final box = await Hive.openBox(boxName);
    final playlists = _readPlaylists(box.get(keyPlaylists))
        .where(
          (playlist) => playlist.id != 'WL' && playlist.title.toLowerCase() != 'watch later',
        )
        .toList();
    final playlistChildIds = _readStringListMap(
      box.get(keyPlaylistChildIds),
    );
    final rootOrder = _readStringList(box.get(keyRootOrder));

    return AppRepository(
      playlists: playlists,
      rootOrder: rootOrder,
      playlistChildIds: playlistChildIds,
    );
  }

  Map<String, List<Map<dynamic, dynamic>>> loadSharedVideos() {
    final box = Hive.box(boxName);
    final raw = box.get(keySharedVideos);
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(
          key.toString(),
          value is List ? value.whereType<Map>().toList() : <Map<dynamic, dynamic>>[],
        ),
      );
    }
    return <String, List<Map<dynamic, dynamic>>>{};
  }

  Map<String, List<Map<dynamic, dynamic>>> loadVideoCache(String accountKey) {
    final box = Hive.box(boxName);
    final raw = box.get(keyVideoCacheByAccount) ??
        box.get(keyVideoCache);
    if (raw is Map) {
      final accountValue = raw[accountKey];
      if (accountValue is Map) {
        return accountValue.map(
          (key, value) => MapEntry(
            key.toString(),
            value is List ? value.whereType<Map>().toList() : <Map<dynamic, dynamic>>[],
          ),
        );
      }
    }
    return <String, List<Map<dynamic, dynamic>>>{};
  }

  Future<void> save(AppRepository repository) async {
    final box = await Hive.openBox(boxName);
    await box.put(
      keyPlaylists,
      repository.playlists.map((playlist) => playlist.toMap()).toList(),
    );
    await box.put(keyPlaylistChildIds, repository.playlistChildIds);
    await box.put(keyRootOrder, repository.rootOrder);
  }

  Future<void> saveSharedVideos(
    Map<String, List<Map<String, dynamic>>> sharedVideos,
  ) async {
    final box = await Hive.openBox(boxName);
    await box.put(keySharedVideos, sharedVideos);
  }

  Future<void> saveVideoCache(
    String accountKey,
    Map<String, List<Map<String, dynamic>>> videoCache,
  ) async {
    final box = await Hive.openBox(boxName);
    final raw = box.get(keyVideoCacheByAccount);
    final byAccount = <String, Map<String, List<Map<String, dynamic>>>>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          byAccount[key.toString()] = value.map(
            (k, v) => MapEntry(
              k.toString(),
              v is List
                  ? v
                      .whereType<Map>()
                      .map(
                        (entry) => entry.map(
                          (entryKey, entryValue) =>
                              MapEntry(entryKey.toString(), entryValue),
                        ),
                      )
                      .toList()
                  : <Map<String, dynamic>>[],
            ),
          );
        }
      });
    }
    byAccount[accountKey] = videoCache;
    await box.put(keyVideoCacheByAccount, byAccount);
  }

  Map<String, int> loadPreloadAtByAccount() {
    final box = Hive.box(boxName);
    final raw = box.get(keyPreloadAtByAccount);
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(
          key.toString(),
          value is int ? value : int.tryParse(value.toString()) ?? 0,
        ),
      );
    }
    return <String, int>{};
  }

  Future<void> savePreloadAtByAccount(Map<String, int> preloadAtByAccount) async {
    final box = await Hive.openBox(boxName);
    await box.put(keyPreloadAtByAccount, preloadAtByAccount);
  }

  List<Playlist> _readPlaylists(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((map) => Playlist.fromMap(map))
          .toList();
    }
    return <Playlist>[];
  }

  Map<String, List<String>> _readStringListMap(dynamic raw) {
    if (raw is Map) {
      final result = <String, List<String>>{};
      raw.forEach((key, value) {
        if (value is List) {
          result[key.toString()] = value.map((entry) => entry.toString()).toList();
        }
      });
      return result;
    }
    return <String, List<String>>{};
  }

  List<String> _readStringList(dynamic raw) {
    if (raw is List) {
      return raw.map((entry) => entry.toString()).toList();
    }
    return <String>[];
  }
}
