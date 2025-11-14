package com.example.youfolder

import android.content.Context
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

// child playlist id -> parent playlist id (null means root / no parent)
data class FolderConfig(
    val parent: MutableMap<String, String?> = mutableMapOf()
)

class FolderStore(context: Context) {

    private val prefs = context.getSharedPreferences("folder_store", Context.MODE_PRIVATE)

    private val moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()
    private val adapter = moshi.adapter(FolderConfig::class.java)

    // Always load latest config from SharedPreferences
    private fun load(): FolderConfig {
        val json = prefs.getString("config", null) ?: return FolderConfig()
        return adapter.fromJson(json) ?: FolderConfig()
    }

    // Always save the full config back
    private fun save(config: FolderConfig) {
        prefs.edit()
            .putString("config", adapter.toJson(config))
            .apply()
    }

    fun getParent(childId: String): String? {
        val cfg = load()
        return cfg.parent[childId]
    }

    fun getChildren(parentId: String): List<String> {
        val cfg = load()
        return cfg.parent.filterValues { it == parentId }.keys.toList()
    }

    /**
     * Set parent of a playlist.
     * parentId = null  → make this playlist a root one.
     */
    fun setParent(childId: String, parentId: String?) {
        val cfg = load()

        if (parentId == null) {
            // root: remove any mapping
            cfg.parent.remove(childId)
        } else {
            if (childId == parentId) return  // avoid self-parent
            cfg.parent[childId] = parentId
        }

        save(cfg)
    }

    fun clearParent(childId: String) {
        val cfg = load()
        cfg.parent.remove(childId)
        save(cfg)
    }
}
