package com.example.youfolder.model

data class YouTubePlaylistModel(
    val kind: String,
    val etag: String,
    val items: List<PlaylistItem>
)

data class PlaylistItem(
    val kind: String,
    val etag: String,
    val id: String,
    val snippet: Snippet
)

data class Snippet(
    val title: String,
    val description: String,
    val thumbnails: Thumbnails
)

data class Thumbnails(
    val default: Thumbnail,
    val medium: Thumbnail,
    val high: Thumbnail
)

data class Thumbnail(
    val url: String,
    val width: Int,
    val height: Int
)
