import 'package:googleapis/youtube/v3.dart' as yt;

class YouTubeService {
  YouTubeService(this._api);

  final yt.YouTubeApi _api;

  Future<List<yt.Playlist>> fetchAllPlaylists() async {
    final playlists = <yt.Playlist>[];
    String? pageToken;
    do {
      final response = await _api.playlists.list(
        ['snippet', 'contentDetails'],
        mine: true,
        maxResults: 50,
        pageToken: pageToken,
      );
      playlists.addAll(response.items ?? []);
      pageToken = response.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
    return playlists;
  }

  Future<yt.Playlist?> createPlaylist(String title) async {
    final playlist = yt.Playlist(
      snippet: yt.PlaylistSnippet(title: title),
      status: yt.PlaylistStatus(privacyStatus: 'private'),
    );
    return _api.playlists.insert(playlist, ['snippet', 'status']);
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _api.playlists.delete(playlistId);
  }

  Future<void> updatePlaylistTitle(String playlistId, String title) async {
    final playlist = yt.Playlist(
      id: playlistId,
      snippet: yt.PlaylistSnippet(title: title),
    );
    await _api.playlists.update(playlist, ['snippet']);
  }


  Future<List<yt.PlaylistItem>> fetchPlaylistItems(String playlistId) async {
    return fetchPlaylistItemsWithProgress(playlistId);
  }

  Future<List<yt.PlaylistItem>> fetchPlaylistItemsWithProgress(
    String playlistId, {
    void Function(int loaded)? onProgress,
  }) async {
    final items = <yt.PlaylistItem>[];
    String? pageToken;
    do {
      final response = await _api.playlistItems.list(
        ['snippet', 'contentDetails'],
        playlistId: playlistId,
        maxResults: 50,
        pageToken: pageToken,
      );
      items.addAll(response.items ?? []);
      onProgress?.call(items.length);
      pageToken = response.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
    return items;
  }

  Future<void> deletePlaylistItem(String playlistItemId) async {
    await _api.playlistItems.delete(playlistItemId);
  }

  Future<void> addVideoToPlaylist(String playlistId, String videoId) async {
    final item = yt.PlaylistItem(
      snippet: yt.PlaylistItemSnippet(
        playlistId: playlistId,
        resourceId: yt.ResourceId(kind: 'youtube#video', videoId: videoId),
      ),
    );
    await _api.playlistItems.insert(item, ['snippet']);
  }
}
