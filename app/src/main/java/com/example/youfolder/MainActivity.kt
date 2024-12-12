package com.example.youfolder

import android.os.Bundle
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.example.youfolder.adapter.PlaylistAdapter
import com.example.youfolder.viewmodel.YouTubeViewModel

class MainActivity : AppCompatActivity() {

    // Create a ViewModel instance
    private val viewModel: YouTubeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Initialize RecyclerView
        val recyclerView: RecyclerView = findViewById(R.id.recyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)

        // Observe the ViewModel for playlists
        viewModel.playlists.observe(this) { playlistModel ->
            val adapter = PlaylistAdapter(playlistModel.items)
            recyclerView.adapter = adapter
        }

        // Observe errors
        viewModel.error.observe(this) { errorMessage ->
            Toast.makeText(this, errorMessage, Toast.LENGTH_LONG).show()
        }

        // Fetch playlists from YouTube API
        val channelId = "UCuDvjuShc0vAxCCcqTf1aWg" // Replace with your channel ID
        viewModel.fetchPlaylists(channelId)
    }
}

