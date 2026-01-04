class VideoItem {
  VideoItem({
    required this.playlistItemId,
    required this.playlistId,
    required this.videoId,
    required this.title,
    required this.thumbnailUrl,
  });

  final String playlistItemId;
  final String playlistId;
  final String videoId;
  final String title;
  final String thumbnailUrl;
}
