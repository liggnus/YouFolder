package com.example.youfolder

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class PlaylistsAdapter : RecyclerView.Adapter<PlaylistsAdapter.VH>() {

    private val data = mutableListOf<PlaylistItem>()

    var onItemClick: ((PlaylistItem) -> Unit)? = null
    var onItemLongClick: ((PlaylistItem) -> Unit)? = null

    fun submit(items: List<PlaylistItem>) {
        data.clear()
        data.addAll(items)
        notifyDataSetChanged()
    }

    fun currentItems(): List<PlaylistItem> = data.toList()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v: View = LayoutInflater.from(parent.context)
            .inflate(R.layout.row_playlist, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val item = data[position]

        holder.title.text = item.snippet.title

        val count = item.contentDetails?.itemCount ?: 0
        holder.count.text = if (count == 1) {
            "1 video"
        } else {
            "$count videos"
        }

        holder.itemView.setOnClickListener {
            onItemClick?.invoke(item)
        }

        holder.itemView.setOnLongClickListener {
            onItemLongClick?.invoke(item)
            true
        }
    }

    override fun getItemCount(): Int = data.size

    class VH(v: View) : RecyclerView.ViewHolder(v) {
        val title: TextView = v.findViewById(R.id.tvTitle)
        val count: TextView = v.findViewById(R.id.tvCount)
    }
}
