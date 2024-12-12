package com.example.youfolder.repository

import com.example.youfolder.model.YouTubePlaylistModel
import com.example.youfolder.network.RetrofitInstance
import com.example.youfolder.network.YouTubeApiService
import retrofit2.Call
import retrofit2.Callback
import retrofit2.Response

class YouTubeRepository {

    private val youTubeApiService = RetrofitInstance.retrofit.create(YouTubeApiService::class.java)

    fun getPlaylists(
        channelId: String,
        apiKey: String, // Make sure this parameter is defined
        onSuccess: (YouTubePlaylistModel) -> Unit,
        onError: (String) -> Unit
    ) {
        val call = youTubeApiService.getPlaylists(channelId = channelId, apiKey = apiKey)
        call.enqueue(object : Callback<YouTubePlaylistModel> {
            override fun onResponse(call: Call<YouTubePlaylistModel>, response: Response<YouTubePlaylistModel>) {
                if (response.isSuccessful) {
                    response.body()?.let(onSuccess) ?: onError("Empty response body")
                } else {
                    onError("API error: ${response.code()} ${response.message()}")
                }
            }

            override fun onFailure(call: Call<YouTubePlaylistModel>, t: Throwable) {
                onError("API call failed: ${t.message}")
            }
        })
    }
}
