import '../data/app_repository.dart';
import 'playlist.dart';

class SharedVideo {
  SharedVideo({
    required this.videoId,
    required this.title,
    required this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final String thumbnailUrl;

  Map<String, dynamic> toMap() {
    return {
      'videoId': videoId,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
    };
  }

  factory SharedVideo.fromMap(Map<dynamic, dynamic> map) {
    return SharedVideo(
      videoId: map['videoId']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Untitled video',
      thumbnailUrl: map['thumbnailUrl']?.toString() ?? '',
    );
  }
}

class SharedTree {
  SharedTree({
    required this.name,
    required this.playlists,
    required this.rootOrder,
    required this.playlistChildIds,
    required this.videosByPlaylist,
    this.sharedBy,
  });

  final String name;
  final String? sharedBy;
  final List<Playlist> playlists;
  final List<String> rootOrder;
  final Map<String, List<String>> playlistChildIds;
  final Map<String, List<SharedVideo>> videosByPlaylist;

  AppRepository toRepository() {
    return AppRepository(
      playlists: List<Playlist>.from(playlists),
      rootOrder: List<String>.from(rootOrder),
      playlistChildIds: playlistChildIds.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'sharedBy': sharedBy,
      'playlists': playlists.map((playlist) => playlist.toMap()).toList(),
      'rootOrder': rootOrder,
      'playlistChildIds': playlistChildIds,
      'videosByPlaylist': videosByPlaylist.map(
        (key, value) => MapEntry(
          key,
          value.map((video) => video.toMap()).toList(),
        ),
      ),
    };
  }

  factory SharedTree.fromMap(Map<dynamic, dynamic> map) {
    return SharedTree(
      name: map['name']?.toString() ?? 'Shared tree',
      sharedBy: map['sharedBy']?.toString(),
      playlists: (map['playlists'] is List)
          ? (map['playlists'] as List)
              .whereType<Map>()
              .map((entry) => Playlist.fromMap(entry))
              .toList()
          : <Playlist>[],
      rootOrder: (map['rootOrder'] is List)
          ? (map['rootOrder'] as List).map((e) => e.toString()).toList()
          : <String>[],
      playlistChildIds: (map['playlistChildIds'] is Map)
          ? (map['playlistChildIds'] as Map).map(
              (key, value) => MapEntry(
                key.toString(),
                value is List
                    ? value.map((e) => e.toString()).toList()
                    : <String>[],
              ),
            )
          : <String, List<String>>{},
      videosByPlaylist: (map['videosByPlaylist'] is Map)
          ? (map['videosByPlaylist'] as Map).map(
              (key, value) => MapEntry(
                key.toString(),
                value is List
                    ? value
                        .whereType<Map>()
                        .map(SharedVideo.fromMap)
                        .toList()
                    : <SharedVideo>[],
              ),
            )
          : <String, List<SharedVideo>>{},
    );
  }
}
