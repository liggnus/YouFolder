package com.example.youfolder.viewmodel

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.example.youfolder.model.YouTubePlaylistModel
import com.example.youfolder.repository.YouTubeRepository

class YouTubeViewModel : ViewModel() {

    private val repository = YouTubeRepository()

    private val _playlists = MutableLiveData<YouTubePlaylistModel>()
    val playlists: LiveData<YouTubePlaylistModel> get() = _playlists

    private val _error = MutableLiveData<String>()
    val error: LiveData<String> get() = _error

    fun fetchPlaylists(channelId: String) {
        val apiKey = "AIzaSyDi3fzzbx_Y0VsRoA84lbmxgfcDjsGz84o" // Replace this with your actual API key
        repository.getPlaylists(channelId, apiKey, { playlists ->
            _playlists.postValue(playlists)
        }, { errorMessage ->
            _error.postValue(errorMessage)
        })
    }
}
