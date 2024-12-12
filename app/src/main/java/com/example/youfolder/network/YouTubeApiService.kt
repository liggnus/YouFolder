package com.example.youfolder.network

import com.example.youfolder.model.YouTubePlaylistModel
import retrofit2.Call
import retrofit2.http.GET
import retrofit2.http.Query

interface YouTubeApiService {
    @GET("playlists")
    fun getPlaylists(
        @Query("part") part: String = "snippet", // Define the "part" query parameter
        @Query("channelId") channelId: String,  // The YouTube channel ID
        @Query("key") apiKey: String           // The API key
    ): Call<YouTubePlaylistModel>
}
