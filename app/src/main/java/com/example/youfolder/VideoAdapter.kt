package com.example.youfolder

import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

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

    // new: normal click when not in selection mode
    var onVideoClick: ((VideoRow) -> Unit)? = null

    fun submit(videos: List<VideoRow>) {
        data.clear()
        data.addAll(videos)
        notifyDataSetChanged()
    }

    fun currentItems(): List<VideoRow> = data.toList()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context)
            .inflate(android.R.layout.simple_list_item_1, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val item = data[position]
        holder.text.text = item.title

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
                // normal click → open video
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
        val text: TextView = v.findViewById(android.R.id.text1)
    }
}
