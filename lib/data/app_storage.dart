import 'package:hive/hive.dart';

import '../models/playlist.dart';
import 'app_repository.dart';

class AppStorage {
  static const String boxName = 'youfolder';
  static const String keyPlaylists = 'playlists';
  static const String keyPlaylistChildIds = 'playlistChildIds';
  static const String keyRootOrder = 'rootOrder';

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

  Future<void> save(AppRepository repository) async {
    final box = await Hive.openBox(boxName);
    await box.put(
      keyPlaylists,
      repository.playlists.map((playlist) => playlist.toMap()).toList(),
    );
    await box.put(keyPlaylistChildIds, repository.playlistChildIds);
    await box.put(keyRootOrder, repository.rootOrder);
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
