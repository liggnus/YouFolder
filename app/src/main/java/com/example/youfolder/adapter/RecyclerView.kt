package com.example.youfolder.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.example.youfolder.R
import com.example.youfolder.model.PlaylistItem

class PlaylistAdapter(private val playlists: List<PlaylistItem>) :
    RecyclerView.Adapter<PlaylistAdapter.PlaylistViewHolder>() {

    // ViewHolder class to hold item views
    class PlaylistViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.textTitle)
        val description: TextView = view.findViewById(R.id.textDescription)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PlaylistViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_playlist, parent, false)
        return PlaylistViewHolder(view)
    }

    override fun onBindViewHolder(holder: PlaylistViewHolder, position: Int) {
        val playlist = playlists[position]
        holder.title.text = playlist.snippet.title
        holder.description.text = playlist.snippet.description
    }

    override fun getItemCount() = playlists.size
}
