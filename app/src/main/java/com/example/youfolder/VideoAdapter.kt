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

    /**
     * When true, rows can be selected (long-press to enter).
     * Activity listens via onSelectionModeChanged to show/hide the bar.
     */
    var selectionMode: Boolean = false
        set(value) {
            field = value
            if (!value) {
                // leaving selection mode → clear selection
                data.forEach { it.selected = false }
            }
            notifyDataSetChanged()
            onSelectionModeChanged?.invoke(value)
        }

    /** Called when selection mode is toggled on/off */
    var onSelectionModeChanged: ((Boolean) -> Unit)? = null

    /** Called whenever the set of selected videos changes */
    var onSelectionChanged: ((List<VideoRow>) -> Unit)? = null

    /** Normal click (when NOT in selection mode) → open YouTube */
    var onVideoClick: ((VideoRow) -> Unit)? = null

    /**
     * Optional per-row delete callback (used only if you add a delete icon
     * back into the row layout). Right now we don’t have that view,
     * so this will never be called.
     */
    var onDeleteClick: ((VideoRow) -> Unit)? = null

    fun submit(videos: List<VideoRow>) {
        data.clear()
        data.addAll(videos)
        notifyDataSetChanged()
    }

    fun currentItems(): List<VideoRow> = data.toList()

    fun getSelectedVideos(): List<VideoRow> = data.filter { it.selected }

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

        // background highlight when selected in selection mode
        holder.itemView.setBackgroundColor(
            if (item.selected && selectionMode) {
                0xFFE0E0E0.toInt()        // light gray
            } else {
                Color.TRANSPARENT
            }
        )

        // normal tap
        holder.itemView.setOnClickListener {
            if (selectionMode) {
                // toggle this row's selection
                item.selected = !item.selected
                notifyItemChanged(position)
                onSelectionChanged?.invoke(data.filter { it.selected })
            } else {
                // open on YouTube
                onVideoClick?.invoke(item)
            }
        }

        // long press → enter selection mode if not already
        holder.itemView.setOnLongClickListener {
            if (!selectionMode) {
                selectionMode = true
                item.selected = true
                notifyItemChanged(position)
                onSelectionChanged?.invoke(data.filter { it.selected })
            }
            true
        }

        // We *currently* don't have a delete icon in the row layout,
        // so deleteButton is always null and this does nothing.
        holder.deleteButton?.apply {
            visibility = if (selectionMode) View.GONE else View.VISIBLE
            setOnClickListener {
                if (!selectionMode) {
                    onDeleteClick?.invoke(item)
                }
            }
        }
    }

    override fun getItemCount(): Int = data.size

    class VH(v: View) : RecyclerView.ViewHolder(v) {
        val thumb: ImageView = v.findViewById(R.id.ivThumbnail)
        val title: TextView = v.findViewById(R.id.tvTitle)
        // no btnDeleteVideo in layout right now → keep this null
        val deleteButton: View? = null
        // If you later add a delete icon back, change this to:
        // val deleteButton: View? = v.findViewById(R.id.btnDeleteVideo)
    }
}
