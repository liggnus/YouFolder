package com.example.youfolder

import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.MobileAds
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationService
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Call
import retrofit2.Callback
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Query
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

class PlaylistDetailActivity : ComponentActivity() {

    private val authService by lazy { AuthorizationService(this) }
    private lateinit var authState: AuthState
    private lateinit var folderStore: FolderStore

    private lateinit var rvVideos: RecyclerView
    private val videoAdapter = VideoAdapter()

    private lateinit var rvSubPlaylists: RecyclerView
    private val subAdapter = PlaylistsAdapter()

    private lateinit var playlistId: String
    private lateinit var playlistTitle: String

    // video selection bar
    private lateinit var layoutVideoSelectionBar: View
    private lateinit var btnMoveSelected: Button
    private lateinit var btnDeleteSelected: Button
    private lateinit var btnCancelVideoSelection: Button

    private lateinit var btnAddSubfolder: ImageButton

    private val videoRows = mutableListOf<VideoRow>()
    private val handler = Handler(Looper.getMainLooper())

    private lateinit var adView: AdView

    // folder selection bar
    private lateinit var layoutFolderSelectionBar: View
    private lateinit var btnMoveFolders: Button
    private lateinit var btnDeleteFolders: Button
    private lateinit var btnCancelFolderSelection: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_playlist_detail)

        // ---- Ads ----
        MobileAds.initialize(this) {}
        adView = findViewById(R.id.adView)
        adView.loadAd(AdRequest.Builder().build())

        folderStore = FolderStore(this)

        playlistId = intent.getStringExtra("id") ?: ""
        playlistTitle = intent.getStringExtra("title") ?: "Playlist"

        val btnBack: ImageButton = findViewById(R.id.btnBack)
        val tvTitle: TextView = findViewById(R.id.tvPlaylistTitle)
        tvTitle.text = playlistTitle
        title = playlistTitle

        btnBack.setOnClickListener { finish() }

        // --- folder selection bar ---
        layoutFolderSelectionBar = findViewById(R.id.layoutFolderSelectionBar)
        btnMoveFolders = findViewById(R.id.btnMoveFolders)
        btnDeleteFolders = findViewById(R.id.btnDeleteFolders)
        btnCancelFolderSelection = findViewById(R.id.btnCancelFolderSelection)

        btnCancelFolderSelection.setOnClickListener {
            subAdapter.setSelectionMode(false)
        }

        btnMoveFolders.setOnClickListener {
            val selected = subAdapter.selectedItems()
            if (selected.isNotEmpty()) {
                showMoveSelectedFoldersDialog(selected)
            }
        }

        btnDeleteFolders.setOnClickListener {
            val selected = subAdapter.selectedItems()
            if (selected.isNotEmpty()) {
                showDeleteSelectedFoldersDialog(selected)
            }
        }

        btnAddSubfolder = findViewById(R.id.btnAddSubfolder)
        btnAddSubfolder.setOnClickListener { showCreateSubfolderDialog() }

        // ---- Sub-playlists list ----
        rvSubPlaylists = findViewById(R.id.rvSubPlaylists)
        rvSubPlaylists.layoutManager = LinearLayoutManager(this)
        rvSubPlaylists.adapter = subAdapter

        // Drag-to-reorder for subfolders (drag handle in each row)
        val folderDragCallback = object : ItemTouchHelper.SimpleCallback(
            ItemTouchHelper.UP or ItemTouchHelper.DOWN,
            0
        ) {
            override fun onMove(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                val fromPos = viewHolder.bindingAdapterPosition
                val toPos = target.bindingAdapterPosition

                subAdapter.moveItem(fromPos, toPos)

                // persist new order for this parent playlist
                val newOrderIds = subAdapter.currentItems().map { it.id }
                folderStore.setChildrenOrder(playlistId, newOrderIds)

                return true
            }

            override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
                // no swipe
            }

            override fun isLongPressDragEnabled(): Boolean = false
        }

        val folderItemTouchHelper = ItemTouchHelper(folderDragCallback)
        folderItemTouchHelper.attachToRecyclerView(rvSubPlaylists)

        subAdapter.onStartDrag = { vh ->
            folderItemTouchHelper.startDrag(vh)
        }

        // selection mode for subfolders
        subAdapter.onSelectionModeChanged = { enabled ->
            layoutFolderSelectionBar.visibility = if (enabled) View.VISIBLE else View.GONE
            btnMoveFolders.isEnabled = false
            btnDeleteFolders.isEnabled = false
        }

        subAdapter.onSelectionChanged = { selected ->
            val has = selected.isNotEmpty()
            btnMoveFolders.isEnabled = has
            btnDeleteFolders.isEnabled = has
        }

        // Tap sub-folder → go deeper
        subAdapter.onItemClick = { playlist ->
            val state = authState
            val intent = Intent(this, PlaylistDetailActivity::class.java).apply {
                putExtra("id", playlist.id)
                putExtra("title", playlist.snippet.title)
                putExtra("authStateJson", state.jsonSerializeString())
            }
            startActivity(intent)
        }

        // Three-dot menu on sub-folder
        subAdapter.onMenuClick = { playlist ->
            showSubFolderMenu(playlist)
        }

        // ---- Videos list ----
        rvVideos = findViewById(R.id.rvVideos)
        rvVideos.layoutManager = LinearLayoutManager(this)
        rvVideos.adapter = videoAdapter

        layoutVideoSelectionBar = findViewById(R.id.layoutVideoSelectionBar)
        btnMoveSelected = findViewById(R.id.btnMoveSelected)
        btnDeleteSelected = findViewById(R.id.btnDeleteSelected)
        btnCancelVideoSelection = findViewById(R.id.btnCancelVideoSelection)

        layoutVideoSelectionBar.visibility = View.GONE
        btnMoveSelected.isEnabled = false
        btnDeleteSelected.isEnabled = false

        // open video when not in selection mode
        videoAdapter.onVideoClick = { row ->
            val url = "https://www.youtube.com/watch?v=${row.videoId}"
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }

        // per-row delete icon (outside selection mode)
        videoAdapter.onDeleteClick = { row ->
            AlertDialog.Builder(this)
                .setTitle("Delete video")
                .setMessage("Remove \"${row.title}\" from this playlist?")
                .setPositiveButton("Delete") { _, _ ->
                    deleteSelectedVideos(listOf(row))
                }
                .setNegativeButton("Cancel", null)
                .show()
        }

        // show/hide video selection bar
        videoAdapter.onSelectionModeChanged = { enabled ->
            layoutVideoSelectionBar.visibility = if (enabled) View.VISIBLE else View.GONE
            if (!enabled) {
                btnMoveSelected.isEnabled = false
                btnDeleteSelected.isEnabled = false
            }
        }

        // enable/disable move/delete based on selection
        videoAdapter.onSelectionChanged = { selected ->
            val hasSelection = selected.isNotEmpty()
            btnMoveSelected.isEnabled = hasSelection
            btnDeleteSelected.isEnabled = hasSelection
        }

        btnMoveSelected.setOnClickListener {
            val selected = videoAdapter.currentItems().filter { it.selected }
            if (selected.isEmpty()) {
                Toast.makeText(this, "No videos selected.", Toast.LENGTH_SHORT).show()
            } else {
                showMoveVideosDialog(selected)
            }
        }

        btnDeleteSelected.setOnClickListener {
            onDeleteSelectedClicked()
        }

        btnCancelVideoSelection.setOnClickListener {
            videoAdapter.selectionMode = false
        }

        val json = intent.getStringExtra("authStateJson") ?: ""
        authState = AuthState.jsonDeserialize(json)

        loadSubPlaylists()
        loadVideos()
    }

    override fun onResume() {
        super.onResume()
        loadSubPlaylists()
    }

    // ---------- Create sub-folder ----------

    private fun showCreateSubfolderDialog() {
        val input = EditText(this).apply {
            hint = "Sub-folder name"
        }

        AlertDialog.Builder(this)
            .setTitle("New sub-folder")
            .setView(input)
            .setPositiveButton("Create") { _, _ ->
                val title = input.text.toString().trim()
                if (title.isNotEmpty()) {
                    createSubPlaylist(title)
                } else {
                    Toast.makeText(this, "Name cannot be empty.", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun createSubPlaylist(title: String) {
        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null || accessToken.isNullOrBlank()) {
                Log.e("YT", "Token error when creating subfolder", ex)
                runOnUiThread {
                    Toast.makeText(this, "Auth error, please try again.", Toast.LENGTH_LONG).show()
                }
                return@performActionWithFreshTokens
            }

            val api = youtube()
            val body = CreatePlaylistRequest(
                snippet = CreatePlaylistSnippet(title = title),
                status = CreatePlaylistStatus(privacyStatus = "private")
            )

            api.createPlaylist(
                part = "snippet,contentDetails,status",
                auth = "Bearer $accessToken",
                body = body
            ).enqueue(object : Callback<PlaylistItem> {
                override fun onResponse(
                    call: Call<PlaylistItem>,
                    response: Response<PlaylistItem>
                ) {
                    if (!response.isSuccessful) {
                        Log.e("YT", "Create subfolder HTTP ${response.code()} ${response.message()}")
                        runOnUiThread {
                            Toast.makeText(
                                this@PlaylistDetailActivity,
                                "Failed to create sub-folder (${response.code()})",
                                Toast.LENGTH_LONG
                            ).show()
                        }
                        return
                    }

                    val created = response.body()
                    if (created == null) {
                        Log.e("YT", "Create subfolder: empty body")
                        runOnUiThread {
                            Toast.makeText(
                                this@PlaylistDetailActivity,
                                "Failed to create sub-folder.",
                                Toast.LENGTH_LONG
                            ).show()
                        }
                        return
                    }

                    folderStore.setParent(created.id, playlistId)

                    runOnUiThread {
                        val updated = subAdapter.currentItems().toMutableList()
                        updated.add(created)
                        subAdapter.submit(updated)

                        folderStore.setChildrenOrder(playlistId, updated.map { it.id })

                        Toast.makeText(
                            this@PlaylistDetailActivity,
                            "Created sub-folder \"$title\"",
                            Toast.LENGTH_SHORT
                        ).show()
                    }

                    handler.postDelayed({ loadSubPlaylists() }, 1500L)
                }

                override fun onFailure(call: Call<PlaylistItem>, t: Throwable) {
                    Log.e("YT", "Network error creating subfolder", t)
                    runOnUiThread {
                        Toast.makeText(
                            this@PlaylistDetailActivity,
                            "Network error: ${t.localizedMessage}",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                }
            })
        }
    }

    // ---------- Sub-folders ----------

    private fun loadSubPlaylists() {
        val childIds = folderStore.getChildren(playlistId)

        if (childIds.isEmpty()) {
            runOnUiThread { subAdapter.submit(emptyList()) }
            return
        }

        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null || accessToken.isNullOrBlank()) {
                Log.e("YT", "Token error (subfolders)", ex)
                return@performActionWithFreshTokens
            }

            val api = youtube()
            api.listPlaylists(
                part = "snippet,contentDetails",
                mine = true,
                maxResults = 50,
                auth = "Bearer $accessToken"
            ).enqueue(object : Callback<PlaylistsResponse> {
                override fun onResponse(
                    call: Call<PlaylistsResponse>,
                    response: Response<PlaylistsResponse>
                ) {
                    if (!response.isSuccessful) {
                        Log.e("YT", "Error loading subfolders ${response.code()}")
                        return
                    }

                    val all = response.body()?.items.orEmpty()
                    val byId = all.associateBy { it.id }

                    // preserve FolderStore order
                    val children = childIds.mapNotNull { byId[it] }

                    runOnUiThread {
                        subAdapter.submit(children)
                    }
                }

                override fun onFailure(call: Call<PlaylistsResponse>, t: Throwable) {
                    Log.e("YT", "network fail (subfolders)", t)
                }
            })
        }
    }

    private fun showMoveSelectedFoldersDialog(selected: List<PlaylistItem>) {
        val allSubs = subAdapter.currentItems()
        val candidates = allSubs.filter { p -> selected.none { it.id == p.id } }

        if (candidates.isEmpty()) {
            Toast.makeText(this, "No other subfolders to move into.", Toast.LENGTH_SHORT).show()
            return
        }

        val names = candidates.map { it.snippet.title }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Move ${selected.size} folder(s) into")
            .setItems(names) { _, which ->
                val newParent = candidates[which]
                selected.forEach { child ->
                    folderStore.setParent(child.id, newParent.id)
                }
                Toast.makeText(
                    this,
                    "Moved into \"${newParent.snippet.title}\"",
                    Toast.LENGTH_SHORT
                ).show()
                loadSubPlaylists()
                subAdapter.setSelectionMode(false)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showDeleteSelectedFoldersDialog(selected: List<PlaylistItem>) {
        AlertDialog.Builder(this)
            .setTitle("Delete ${selected.size} folder(s)?")
            .setMessage("Delete the selected folders and their playlists on YouTube? This cannot be undone.")
            .setPositiveButton("Delete") { _, _ ->
                selected.forEach { playlist ->
                    deleteSubfolder(playlist)
                }
                subAdapter.setSelectionMode(false)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showSubFolderMenu(playlist: PlaylistItem) {
        val options = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()

        options += "Rename folder"
        actions += { showRenameSubfolderDialog(playlist) }

        options += "Move into another subfolder"
        actions += { showMoveSubfolderDialog(playlist) }

        options += "Remove from this folder"
        actions += { moveOutToParentFolder(playlist) }

        options += "Delete folder"
        actions += { confirmDeleteSubfolder(playlist) }

        AlertDialog.Builder(this)
            .setTitle(playlist.snippet.title)
            .setItems(options.toTypedArray()) { _, which ->
                actions[which].invoke()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showRenameSubfolderDialog(playlist: PlaylistItem) {
        val input = EditText(this).apply {
            setText(playlist.snippet.title)
            setSelection(text.length)
        }

        AlertDialog.Builder(this)
            .setTitle("Rename folder")
            .setView(input)
            .setPositiveButton("Save") { _, _ ->
                val newTitle = input.text.toString().trim()
                if (newTitle.isEmpty()) {
                    Toast.makeText(this, "Name cannot be empty.", Toast.LENGTH_SHORT).show()
                } else if (newTitle == playlist.snippet.title) {
                    Toast.makeText(this, "Name not changed.", Toast.LENGTH_SHORT).show()
                } else {
                    renameSubfolder(playlist, newTitle)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun renameSubfolder(playlist: PlaylistItem, newTitle: String) {
        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null || accessToken.isNullOrBlank()) {
                Log.e("YT", "Token error when renaming subfolder", ex)
                runOnUiThread {
                    Toast.makeText(this, "Auth error, please try again.", Toast.LENGTH_LONG).show()
                }
                return@performActionWithFreshTokens
            }

            val api = youtube()
            val body = UpdatePlaylistRequest(
                id = playlist.id,
                snippet = Snippet(title = newTitle)
            )

            api.updatePlaylist(
                part = "snippet",
                auth = "Bearer $accessToken",
                body = body
            ).enqueue(object : Callback<PlaylistItem> {
                override fun onResponse(
                    call: Call<PlaylistItem>,
                    response: Response<PlaylistItem>
                ) {
                    if (!response.isSuccessful) {
                        Log.e("YT", "Rename subfolder HTTP ${response.code()} ${response.message()}")
                        runOnUiThread {
                            Toast.makeText(
                                this@PlaylistDetailActivity,
                                "Failed to rename folder (${response.code()})",
                                Toast.LENGTH_LONG
                            ).show()
                        }
                        return
                    }

                    runOnUiThread {
                        Toast.makeText(
                            this@PlaylistDetailActivity,
                            "Renamed to \"$newTitle\"",
                            Toast.LENGTH_SHORT
                        ).show()
                        loadSubPlaylists()
                    }
                }

                override fun onFailure(call: Call<PlaylistItem>, t: Throwable) {
                    Log.e("YT", "Network error renaming subfolder", t)
                    runOnUiThread {
                        Toast.makeText(
                            this@PlaylistDetailActivity,
                            "Network error: ${t.localizedMessage}",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                }
            })
        }
    }

    private fun moveOutToParentFolder(child: PlaylistItem) {
        val parentOfCurrent = folderStore.getParent(playlistId)
        folderStore.setParent(child.id, parentOfCurrent)
        Toast.makeText(this, "Moved to parent folder", Toast.LENGTH_SHORT).show()
        loadSubPlaylists()
    }

    private fun showMoveSubfolderDialog(child: PlaylistItem) {
        val allSubs = subAdapter.currentItems()
        val candidates = allSubs.filter { it.id != child.id }

        if (candidates.isEmpty()) {
            Toast.makeText(this, "No other subfolders to move into.", Toast.LENGTH_SHORT).show()
            return
        }

        val names = candidates.map { it.snippet.title }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Move into subfolder")
            .setItems(names) { _, which ->
                val newParent = candidates[which]
                folderStore.setParent(child.id, newParent.id)
                Toast.makeText(
                    this,
                    "Moved into \"${newParent.snippet.title}\"",
                    Toast.LENGTH_SHORT
                ).show()
                loadSubPlaylists()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun confirmDeleteSubfolder(playlist: PlaylistItem) {
        AlertDialog.Builder(this)
            .setTitle("Delete folder")
            .setMessage("Delete folder \"${playlist.snippet.title}\" and its playlist on YouTube? This cannot be undone.")
            .setPositiveButton("Delete") { _, _ ->
                deleteSubfolder(playlist)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun deleteSubfolder(playlist: PlaylistItem) {
        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null || accessToken.isNullOrBlank()) {
                Log.e("YT", "Token error when deleting subfolder", ex)
                runOnUiThread {
                    Toast.makeText(this, "Auth error, please try again.", Toast.LENGTH_LONG).show()
                }
                return@performActionWithFreshTokens
            }

            val api = youtube()
            val authHeader = "Bearer $accessToken"

            api.deletePlaylist(
                id = playlist.id,
                auth = authHeader
            ).enqueue(object : Callback<Void> {
                override fun onResponse(call: Call<Void>, response: Response<Void>) {
                    if (!response.isSuccessful) {
                        Log.e(
                            "YT",
                            "Delete playlist failed ${response.code()} ${response.message()}"
                        )
                        runOnUiThread {
                            Toast.makeText(
                                this@PlaylistDetailActivity,
                                "Failed to delete folder (${response.code()})",
                                Toast.LENGTH_LONG
                            ).show()
                        }
                        return
                    }

                    runOnUiThread {
                        Toast.makeText(
                            this@PlaylistDetailActivity,
                            "Deleted folder \"${playlist.snippet.title}\"",
                            Toast.LENGTH_SHORT
                        ).show()
                        loadSubPlaylists()
                    }
                }

                override fun onFailure(call: Call<Void>, t: Throwable) {
                    Log.e("YT", "Network error deleting subfolder", t)
                    runOnUiThread {
                        Toast.makeText(
                            this@PlaylistDetailActivity,
                            "Network error: ${t.localizedMessage}",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                }
            })
        }
    }

    // ---------- Videos ----------

    private fun loadVideos() {
        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null) {
                Log.e("YT", "Token error", ex)
                return@performActionWithFreshTokens
            }

            if (accessToken.isNullOrBlank()) {
                Log.e("YT", "Missing access token")
                return@performActionWithFreshTokens
            }

            val api = youtube()
            val authHeader = "Bearer $accessToken"
            val accumulated = mutableListOf<VideoRow>()

            fun fetchPage(pageToken: String?) {
                api.listVideos(
                    part = "snippet",
                    playlistId = playlistId,
                    maxResults = 50,
                    pageToken = pageToken,
                    auth = authHeader
                ).enqueue(object : Callback<PlaylistItemsResponse> {
                    override fun onResponse(
                        call: Call<PlaylistItemsResponse>,
                        response: Response<PlaylistItemsResponse>
                    ) {
                        if (!response.isSuccessful) {
                            Log.e("YT", "Error loading videos ${response.code()}")
                            return
                        }

                        val body = response.body()
                        val items = body?.items.orEmpty()

                        val rows = items.mapNotNull { item ->
                            val snippet = item.snippet ?: return@mapNotNull null
                            val title = snippet.title ?: return@mapNotNull null
                            val vid = snippet.resourceId?.videoId ?: return@mapNotNull null

                            val thumbUrl =
                                snippet.thumbnails?.medium?.url
                                    ?: snippet.thumbnails?.default?.url
                                    ?: snippet.thumbnails?.high?.url

                            VideoRow(
                                playlistItemId = item.id,
                                videoId = vid,
                                title = title,
                                thumbnailUrl = thumbUrl
                            )
                        }

                        accumulated.addAll(rows)

                        val next = body?.nextPageToken
                        if (next != null) {
                            fetchPage(next)
                        } else {
                            runOnUiThread {
                                videoRows.clear()
                                videoRows.addAll(accumulated)
                                videoAdapter.selectionMode = false
                                layoutVideoSelectionBar.visibility = View.GONE
                                btnMoveSelected.isEnabled = false
                                btnDeleteSelected.isEnabled = false
                                videoAdapter.submit(videoRows)
                                Log.d("YT", "Loaded ${accumulated.size} videos in total")
                            }
                        }
                    }

                    override fun onFailure(call: Call<PlaylistItemsResponse>, t: Throwable) {
                        Log.e("YT", "network fail", t)
                    }
                })
            }

            fetchPage(null)
        }
    }

    private fun onDeleteSelectedClicked() {
        val selectedVideos = videoAdapter.currentItems().filter { it.selected }

        if (selectedVideos.isEmpty()) {
            Toast.makeText(this, "No videos selected.", Toast.LENGTH_SHORT).show()
            return
        }

        AlertDialog.Builder(this)
            .setTitle("Delete selected videos")
            .setMessage("Remove ${selectedVideos.size} video(s) from this playlist?")
            .setPositiveButton("Delete") { _, _ ->
                deleteSelectedVideos(selectedVideos)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showMoveVideosDialog(selected: List<VideoRow>) {
        val selectedCopy = selected.map { it.copy() }

        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null || accessToken.isNullOrBlank()) {
                Log.e("YT", "Token error when loading target playlists", ex)
                return@performActionWithFreshTokens
            }

            val api = youtube()
            api.listPlaylists(
                part = "snippet,contentDetails",
                mine = true,
                maxResults = 50,
                auth = "Bearer $accessToken"
            ).enqueue(object : Callback<PlaylistsResponse> {
                override fun onResponse(
                    call: Call<PlaylistsResponse>,
                    response: Response<PlaylistsResponse>
                ) {
                    if (!response.isSuccessful) {
                        Log.e("YT", "Error loading target playlists ${response.code()}")
                        return
                    }

                    val all = response.body()?.items.orEmpty()
                    val candidates = all.filter { it.id != playlistId }

                    if (candidates.isEmpty()) {
                        runOnUiThread {
                            Toast.makeText(
                                this@PlaylistDetailActivity,
                                "No other playlists to move into.",
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                        return
                    }

                    val names = candidates.map { it.snippet.title }.toTypedArray()

                    runOnUiThread {
                        AlertDialog.Builder(this@PlaylistDetailActivity)
                            .setTitle("Move ${selectedCopy.size} video(s) to")
                            .setItems(names) { _, which ->
                                val target = candidates[which]
                                moveVideosToPlaylist(selectedCopy, target.id)
                            }
                            .setNegativeButton("Cancel", null)
                            .show()
                    }
                }

                override fun onFailure(call: Call<PlaylistsResponse>, t: Throwable) {
                    Log.e("YT", "network fail loading target playlists", t)
                }
            })
        }
    }

    private fun deleteSelectedVideos(selected: List<VideoRow>) {
        if (selected.isEmpty()) return

        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null || accessToken.isNullOrBlank()) {
                Log.e("YT", "Token error when deleting videos", ex)
                return@performActionWithFreshTokens
            }

            val api = youtube()
            val authHeader = "Bearer $accessToken"

            runOnUiThread {
                Toast.makeText(
                    this,
                    "Deleting ${selected.size} video(s)...",
                    Toast.LENGTH_SHORT
                ).show()
                btnMoveSelected.isEnabled = false
                btnDeleteSelected.isEnabled = false
            }

            fun processIndex(index: Int) {
                if (index >= selected.size) {
                    runOnUiThread {
                        loadVideos()
                        Toast.makeText(
                            this,
                            "Deleted ${selected.size} video(s)",
                            Toast.LENGTH_SHORT
                        ).show()
                        videoAdapter.selectionMode = false
                    }
                    return
                }

                val row = selected[index]

                api.deletePlaylistItem(
                    id = row.playlistItemId,
                    auth = authHeader
                ).enqueue(object : Callback<Void> {
                    override fun onResponse(
                        call: Call<Void>,
                        response: Response<Void>
                    ) {
                        if (!response.isSuccessful) {
                            Log.e("YT", "Delete failed ${response.code()}")
                        } else {
                            Log.d("YT", "Deleted video '${row.title}'")
                        }
                        processIndex(index + 1)
                    }

                    override fun onFailure(call: Call<Void>, t: Throwable) {
                        Log.e("YT", "Delete network fail", t)
                        processIndex(index + 1)
                    }
                })
            }

            processIndex(0)
        }
    }

    private fun moveVideosToPlaylist(selected: List<VideoRow>, targetPlaylistId: String) {
        if (selected.isEmpty()) return

        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null || accessToken.isNullOrBlank()) {
                Log.e("YT", "Token error when moving videos", ex)
                return@performActionWithFreshTokens
            }

            val api = youtube()
            val authHeader = "Bearer $accessToken"

            runOnUiThread {
                Toast.makeText(
                    this,
                    "Moving ${selected.size} video(s)...",
                    Toast.LENGTH_SHORT
                ).show()
                btnMoveSelected.isEnabled = false
                btnDeleteSelected.isEnabled = false
            }

            fun processIndex(index: Int) {
                if (index >= selected.size) {
                    runOnUiThread {
                        loadVideos()
                        Toast.makeText(
                            this,
                            "Moved ${selected.size} video(s)",
                            Toast.LENGTH_SHORT
                        ).show()
                        videoAdapter.selectionMode = false
                    }
                    return
                }

                val row = selected[index]

                val body = PlaylistItemInsertRequest(
                    snippet = PlaylistItemInsertSnippet(
                        playlistId = targetPlaylistId,
                        resourceId = ResourceIdForInsert(videoId = row.videoId)
                    )
                )

                api.insertPlaylistItem(
                    part = "snippet",
                    auth = authHeader,
                    body = body
                ).enqueue(object : Callback<PlaylistVideoItem> {
                    override fun onResponse(
                        call: Call<PlaylistVideoItem>,
                        response: Response<PlaylistVideoItem>
                    ) {
                        if (!response.isSuccessful) {
                            Log.e("YT", "Insert failed ${response.code()}")
                            processIndex(index + 1)
                            return
                        }

                        api.deletePlaylistItem(
                            id = row.playlistItemId,
                            auth = authHeader
                        ).enqueue(object : Callback<Void> {
                            override fun onResponse(
                                call: Call<Void>,
                                response: Response<Void>
                            ) {
                                if (!response.isSuccessful) {
                                    Log.e("YT", "Delete failed ${response.code()}")
                                } else {
                                    Log.d("YT", "Moved video '${row.title}'")
                                }
                                processIndex(index + 1)
                            }

                            override fun onFailure(call: Call<Void>, t: Throwable) {
                                Log.e("YT", "Delete network fail", t)
                                processIndex(index + 1)
                            }
                        })
                    }

                    override fun onFailure(call: Call<PlaylistVideoItem>, t: Throwable) {
                        Log.e("YT", "Insert network fail", t)
                        processIndex(index + 1)
                    }
                })
            }

            processIndex(0)
        }
    }

    // ---------- Retrofit ----------

    private fun youtube(): YouTubeDetailApi {
        val log = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BODY
        }
        val client = OkHttpClient.Builder()
            .addInterceptor(log)
            .build()

        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        return Retrofit.Builder()
            .baseUrl("https://www.googleapis.com/")
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(YouTubeDetailApi::class.java)
    }
}

// ---------- Retrofit API and models ----------

interface YouTubeDetailApi {
    @GET("youtube/v3/playlistItems")
    fun listVideos(
        @Query("part") part: String,
        @Query("playlistId") playlistId: String,
        @Query("maxResults") maxResults: Int,
        @Query("pageToken") pageToken: String? = null,
        @Header("Authorization") auth: String
    ): Call<PlaylistItemsResponse>

    @GET("youtube/v3/playlists")
    fun listPlaylists(
        @Query("part") part: String,
        @Query("mine") mine: Boolean,
        @Query("maxResults") maxResults: Int,
        @Header("Authorization") auth: String
    ): Call<PlaylistsResponse>

    @POST("youtube/v3/playlistItems")
    fun insertPlaylistItem(
        @Query("part") part: String,
        @Header("Authorization") auth: String,
        @Body body: PlaylistItemInsertRequest
    ): Call<PlaylistVideoItem>

    @DELETE("youtube/v3/playlistItems")
    fun deletePlaylistItem(
        @Query("id") id: String,
        @Header("Authorization") auth: String
    ): Call<Void>

    @POST("youtube/v3/playlists")
    fun createPlaylist(
        @Query("part") part: String,
        @Header("Authorization") auth: String,
        @Body body: CreatePlaylistRequest
    ): Call<PlaylistItem>

    @DELETE("youtube/v3/playlists")
    fun deletePlaylist(
        @Query("id") id: String,
        @Header("Authorization") auth: String
    ): Call<Void>

    @PUT("youtube/v3/playlists")
    fun updatePlaylist(
        @Query("part") part: String,
        @Header("Authorization") auth: String,
        @Body body: UpdatePlaylistRequest
    ): Call<PlaylistItem>
}

data class PlaylistItemsResponse(
    val items: List<PlaylistVideoItem> = emptyList(),
    val nextPageToken: String? = null
)

data class PlaylistVideoItem(
    val id: String, // playlistItemId
    val snippet: VideoSnippet?
)

data class VideoSnippet(
    val title: String?,
    val resourceId: ResourceId?,
    val thumbnails: Thumbnails?
)

data class Thumbnails(
    val default: ThumbnailDetails?,
    val medium: ThumbnailDetails?,
    val high: ThumbnailDetails?
)

data class ThumbnailDetails(
    val url: String?
)

data class ResourceId(
    val videoId: String?
)

data class VideoRow(
    val playlistItemId: String,
    val videoId: String,
    val title: String,
    val thumbnailUrl: String? = null,
    var selected: Boolean = false
)

data class PlaylistItemInsertRequest(
    val snippet: PlaylistItemInsertSnippet
)

data class PlaylistItemInsertSnippet(
    val playlistId: String,
    val resourceId: ResourceIdForInsert
)

data class ResourceIdForInsert(
    val kind: String = "youtube#video",
    val videoId: String
)
