package com.example.youfolder

import android.content.Context
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

// child playlist id -> parent playlist id (null means root / no parent)
// order[key] = list of childIds in the desired order
//   - key = parentId for sub-folders
//   - key = ROOT_KEY for root playlists
data class FolderConfig(
    val parent: MutableMap<String, String?> = mutableMapOf(),
    val order: MutableMap<String, MutableList<String>> = mutableMapOf()
)

class FolderStore(context: Context) {

    companion object {
        // special key used to store order of ROOT playlists
        private const val ROOT_KEY = "__root__"
    }

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

    /**
     * Return children of this parent in the stored order.
     */
    fun getChildren(parentId: String): List<String> {
        val cfg = load()

        // all children that currently claim this parent
        val allChildren = cfg.parent.filterValues { it == parentId }.keys.toSet()

        // order we previously stored (may be null)
        val storedOrder = cfg.order[parentId] ?: mutableListOf()

        val result = mutableListOf<String>()

        // first: take items from stored order that are still valid children
        for (id in storedOrder) {
            if (id in allChildren) {
                result.add(id)
            }
        }

        // then: append any children that weren't in storedOrder (new ones)
        for (id in allChildren) {
            if (!result.contains(id)) {
                result.add(id)
            }
        }

        return result
    }

    /**
     * Set parent of a playlist.
     * parentId = null  → make this playlist a root one.
     */
    fun setParent(childId: String, parentId: String?) {
        val cfg = load()
        val oldParent = cfg.parent[childId]

        if (parentId == null) {
            // root: remove any mapping; root order is handled separately
            cfg.parent.remove(childId)
        } else {
            if (childId == parentId) {
                save(cfg)
                return  // avoid self-parent
            }
            cfg.parent[childId] = parentId

            // ensure it's present in the order list for the new parent
            val list = cfg.order.getOrPut(parentId) { mutableListOf() }
            if (!list.contains(childId)) list.add(childId)
        }

        // remove from old parent's order list if parent changed
        if (oldParent != null && oldParent != parentId) {
            cfg.order[oldParent]?.remove(childId)
        }

        save(cfg)
    }

    fun clearParent(childId: String) {
        val cfg = load()
        val oldParent = cfg.parent[childId]
        if (oldParent != null) {
            cfg.parent.remove(childId)
            cfg.order[oldParent]?.remove(childId)
        }
        save(cfg)
    }

    /**
     * Save an explicit child order for this parent.
     * `orderedChildren` is the list of child IDs in the desired order.
     */
    fun setChildrenOrder(parentId: String, orderedChildren: List<String>) {
        val cfg = load()

        // Only keep entries that really belong to this parent
        val realChildren = cfg.parent.filterValues { it == parentId }.keys.toSet()

        val validOrdered = orderedChildren.filter { it in realChildren }.toMutableList()

        // add any missing real children at the end
        for (id in realChildren) {
            if (!validOrdered.contains(id)) {
                validOrdered.add(id)
            }
        }

        cfg.order[parentId] = validOrdered
        save(cfg)
    }

    // ---------- ROOT PLAYLIST ORDER ----------

    /**
     * Given the current root playlist IDs coming from the API,
     * return them in the persisted order (falling back to API order
     * for any new ones that we haven't seen before).
     */
    fun orderRootPlaylists(allRootIdsFromApi: List<String>): List<String> {
        val cfg = load()

        val roots = allRootIdsFromApi.toSet()
        val storedOrder = cfg.order[ROOT_KEY] ?: mutableListOf()

        val result = mutableListOf<String>()

        // 1) existing stored order, only if still present
        for (id in storedOrder) {
            if (id in roots) result.add(id)
        }

        // 2) any new roots not previously stored
        for (id in roots) {
            if (!result.contains(id)) result.add(id)
        }

        return result
    }

    /**
     * Persist the order for root playlists.
     * The caller should pass ONLY root IDs here.
     */
    fun setRootOrder(orderedRootIds: List<String>) {
        val cfg = load()
        val realRoots = orderedRootIds.toSet()

        val validOrdered = orderedRootIds.filter { it in realRoots }.toMutableList()
        cfg.order[ROOT_KEY] = validOrdered
        save(cfg)
    }
}
