class Playlist {
  Playlist({
    required this.id,
    required this.title,
    required this.videoCount,
    this.isYouTube = true,
    this.isPinned = false,
    this.isFavorite = false,
    this.isHidden = false,
  });

  final String id;
  final String title;
  final int videoCount;
  final bool isYouTube;
  final bool isPinned;
  final bool isFavorite;
  final bool isHidden;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'videoCount': videoCount,
      'isYouTube': isYouTube,
      'isPinned': isPinned,
      'isFavorite': isFavorite,
      'isHidden': isHidden,
    };
  }

  factory Playlist.fromMap(Map<dynamic, dynamic> map) {
    return Playlist(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      videoCount: (map['videoCount'] as num?)?.toInt() ?? 0,
      isYouTube: map['isYouTube'] == true,
      isPinned: map['isPinned'] == true,
      isFavorite: map['isFavorite'] == true,
      isHidden: map['isHidden'] == true,
    );
  }
}
