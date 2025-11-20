package com.example.youfolder

import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide

class VideoAdapter : RecyclerView.Adapter<VideoAdapter.VH>() {

    private val data = mutableListOf<VideoRow>()

    var selectionMode: Boolean = false
        set(value) {
            field = value
            if (!value) {
                data.forEach { it.selected = false }
            }
            notifyDataSetChanged()
        }

    var onSelectionChanged: ((List<VideoRow>) -> Unit)? = null

    // normal click when not in selection mode
    var onVideoClick: ((VideoRow) -> Unit)? = null

    fun submit(videos: List<VideoRow>) {
        data.clear()
        data.addAll(videos)
        notifyDataSetChanged()
    }

    fun currentItems(): List<VideoRow> = data.toList()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context)
            .inflate(R.layout.row_video, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val item = data[position]
        holder.title.text = item.title

        // load thumbnail with Glide (if url is not null)
        if (!item.thumbnailUrl.isNullOrBlank()) {
            Glide.with(holder.itemView)
                .load(item.thumbnailUrl)
                .placeholder(android.R.drawable.ic_media_play)
                .centerCrop()
                .into(holder.thumb)
        } else {
            holder.thumb.setImageResource(android.R.drawable.ic_media_play)
        }

        holder.itemView.setBackgroundColor(
            if (item.selected && selectionMode) {
                0xFFE0E0E0.toInt()
            } else {
                Color.TRANSPARENT
            }
        )

        holder.itemView.setOnClickListener {
            if (selectionMode) {
                item.selected = !item.selected
                notifyItemChanged(position)
                onSelectionChanged?.invoke(data.filter { it.selected })
            } else {
                onVideoClick?.invoke(item)
            }
        }

        holder.itemView.setOnLongClickListener {
            if (!selectionMode) {
                selectionMode = true
                item.selected = true
                notifyItemChanged(position)
                onSelectionChanged?.invoke(data.filter { it.selected })
            }
            true
        }
    }

    override fun getItemCount(): Int = data.size

    class VH(v: View) : RecyclerView.ViewHolder(v) {
        val thumb: ImageView = v.findViewById(R.id.ivThumbnail)
        val title: TextView = v.findViewById(R.id.tvTitle)
    }
}
