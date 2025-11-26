package com.example.youfolder

import android.graphics.Color
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class PlaylistsAdapter : RecyclerView.Adapter<PlaylistsAdapter.VH>() {

    private val data = mutableListOf<PlaylistItem>()
    private val selectedIds = mutableSetOf<String>()

    var selectionMode: Boolean = false
        private set

    var onItemClick: ((PlaylistItem) -> Unit)? = null
    var onMenuClick: ((PlaylistItem) -> Unit)? = null
    var onSelectionModeChanged: ((Boolean) -> Unit)? = null
    var onSelectionChanged: ((List<PlaylistItem>) -> Unit)? = null

    // for drag-to-reorder
    var onStartDrag: ((RecyclerView.ViewHolder) -> Unit)? = null

    fun submit(items: List<PlaylistItem>) {
        data.clear()
        data.addAll(items)
        selectedIds.clear()
        if (selectionMode) {
            setSelectionMode(false)
        }
        notifyDataSetChanged()
    }

    fun currentItems(): List<PlaylistItem> = data.toList()

    fun selectedItems(): List<PlaylistItem> =
        data.filter { selectedIds.contains(it.id) }

    fun setSelectionMode(enabled: Boolean) {
        if (selectionMode == enabled) return
        selectionMode = enabled
        if (!enabled) {
            selectedIds.clear()
            onSelectionChanged?.invoke(emptyList())
        }
        onSelectionModeChanged?.invoke(enabled)
        notifyDataSetChanged()
    }

    private fun toggleSelection(item: PlaylistItem) {
        if (selectedIds.contains(item.id)) {
            selectedIds.remove(item.id)
        } else {
            selectedIds.add(item.id)
        }
        onSelectionChanged?.invoke(selectedItems())
        notifyDataSetChanged()
    }

    // Called by ItemTouchHelper during drag
    fun moveItem(fromPosition: Int, toPosition: Int) {
        if (fromPosition == toPosition) return
        val item = data.removeAt(fromPosition)
        data.add(toPosition, item)
        notifyItemMoved(fromPosition, toPosition)
    }

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

        val isSelected = selectedIds.contains(item.id)

        // Show checkmark + background when selected
        holder.check.visibility = if (selectionMode) View.VISIBLE else View.GONE
        holder.check.alpha = if (isSelected) 1f else 0.2f

        holder.itemView.setBackgroundColor(
            if (selectionMode && isSelected) 0xFFE0E0E0.toInt() else Color.TRANSPARENT
        )

        // Normal click vs selection click
        holder.itemView.setOnClickListener {
            if (selectionMode) {
                toggleSelection(item)
            } else {
                onItemClick?.invoke(item)
            }
        }

        // Long-press to enter selection mode
        holder.itemView.setOnLongClickListener {
            if (!selectionMode) {
                setSelectionMode(true)
                toggleSelection(item)
            }
            true
        }

        // Three-dot menu (single-item actions)
        holder.more.setOnClickListener {
            onMenuClick?.invoke(item)
        }

        // Drag handle → start drag
        holder.dragHandle.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_DOWN) {
                onStartDrag?.invoke(holder)
            }
            false
        }
    }

    override fun getItemCount(): Int = data.size

    class VH(v: View) : RecyclerView.ViewHolder(v) {
        val title: TextView = v.findViewById(R.id.tvTitle)
        val count: TextView = v.findViewById(R.id.tvCount)
        val check: ImageView = v.findViewById(R.id.ivCheck)
        val dragHandle: ImageView = v.findViewById(R.id.ivDragHandle)
        val more: ImageButton = v.findViewById(R.id.btnMore)
    }
}
