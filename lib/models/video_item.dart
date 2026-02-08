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

  Map<String, dynamic> toMap() {
    return {
      'playlistItemId': playlistItemId,
      'playlistId': playlistId,
      'videoId': videoId,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
    };
  }

  factory VideoItem.fromMap(Map<dynamic, dynamic> map) {
    return VideoItem(
      playlistItemId: map['playlistItemId']?.toString() ?? '',
      playlistId: map['playlistId']?.toString() ?? '',
      videoId: map['videoId']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Untitled video',
      thumbnailUrl: map['thumbnailUrl']?.toString() ?? '',
    );
  }
}
