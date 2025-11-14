package com.example.youfolder

import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
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

    private lateinit var btnToggleSelection: Button
    private lateinit var btnMoveSelected: Button

    private val videoRows = mutableListOf<VideoRow>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_playlist_detail)

        folderStore = FolderStore(this)

        playlistId = intent.getStringExtra("id") ?: ""
        playlistTitle = intent.getStringExtra("title") ?: "Playlist"

        val btnBack: ImageButton = findViewById(R.id.btnBack)
        val tvTitle: TextView = findViewById(R.id.tvPlaylistTitle)
        tvTitle.text = playlistTitle
        title = playlistTitle

        btnBack.setOnClickListener { finish() }

        // ---- Sub-playlists list (vertical) ----
        rvSubPlaylists = findViewById(R.id.rvSubPlaylists)
        rvSubPlaylists.layoutManager = LinearLayoutManager(this)
        rvSubPlaylists.adapter = subAdapter

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

        // Long-press sub-folder → manage (move / remove)
        subAdapter.onItemLongClick = { playlist ->
            showSubFolderMenu(playlist)
        }

        // ---- Videos list ----
        rvVideos = findViewById(R.id.rvVideos)
        rvVideos.layoutManager = LinearLayoutManager(this)
        rvVideos.adapter = videoAdapter

        // new: open video when not in selection mode
        videoAdapter.onVideoClick = { row ->
            val url = "https://www.youtube.com/watch?v=${row.videoId}"
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            // Android will pick YouTube app if installed, otherwise browser
            startActivity(intent)
        }

        btnToggleSelection = findViewById(R.id.btnToggleSelection)
        btnMoveSelected = findViewById(R.id.btnMoveSelected)

        btnToggleSelection.setOnClickListener {
            videoAdapter.selectionMode = !videoAdapter.selectionMode
            btnToggleSelection.text =
                if (videoAdapter.selectionMode) "Cancel selection" else "Select videos"
            btnMoveSelected.isEnabled = false
        }

        videoAdapter.onSelectionChanged = { selected ->
            btnMoveSelected.isEnabled = selected.isNotEmpty()
        }

        btnMoveSelected.setOnClickListener {
            val selected = videoAdapter.currentItems().filter { it.selected }
            if (selected.isEmpty()) {
                Toast.makeText(this, "No videos selected.", Toast.LENGTH_SHORT).show()
            } else {
                showMoveVideosDialog(selected)
            }
        }

        val json = intent.getStringExtra("authStateJson") ?: ""
        authState = AuthState.jsonDeserialize(json)

        loadSubPlaylists()
        loadVideos()
    }

    // 🔁 When coming back to this screen, re read subfolders
    override fun onResume() {
        super.onResume()
        loadSubPlaylists()
    }

    // ---------- Sub-folders ----------

    private fun loadSubPlaylists() {
        val childIds = folderStore.getChildren(playlistId)

        if (childIds.isEmpty()) {
            runOnUiThread {
                subAdapter.submit(emptyList())
            }
            return
        }

        authState.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null) {
                Log.e("YT", "Token error (subfolders)", ex)
                return@performActionWithFreshTokens
            }

            if (accessToken.isNullOrBlank()) {
                Log.e("YT", "Missing access token (subfolders)")
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
                    val children = all.filter { it.id in childIds }

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

    private fun showSubFolderMenu(playlist: PlaylistItem) {
        val options = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()

        options += "Move into another subfolder"
        actions += { showMoveSubfolderDialog(playlist) }

        options += "Remove from this folder"
        actions += { moveOutToParentFolder(playlist) }

        AlertDialog.Builder(this)
            .setTitle(playlist.snippet.title)
            .setItems(options.toTypedArray()) { _, which ->
                actions[which].invoke()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun moveOutToParentFolder(child: PlaylistItem) {
        val parentOfCurrent = folderStore.getParent(playlistId)
        folderStore.setParent(child.id, parentOfCurrent)
        Toast.makeText(
            this,
            "Moved to parent folder",
            Toast.LENGTH_SHORT
        ).show()
        loadSubPlaylists()
    }

    private fun showMoveSubfolderDialog(child: PlaylistItem) {
        val allSubs = subAdapter.currentItems()
        val candidates = allSubs.filter { it.id != child.id }

        if (candidates.isEmpty()) {
            Toast.makeText(
                this,
                "No other subfolders to move into.",
                Toast.LENGTH_SHORT
            ).show()
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
            api.listVideos(
                part = "snippet",
                playlistId = playlistId,
                maxResults = 50,
                auth = "Bearer $accessToken"
            ).enqueue(object : Callback<PlaylistItemsResponse> {
                override fun onResponse(
                    call: Call<PlaylistItemsResponse>,
                    response: Response<PlaylistItemsResponse>
                ) {
                    if (!response.isSuccessful) {
                        Log.e("YT", "Error loading videos ${response.code()}")
                        return
                    }

                    val rows = response.body()?.items
                        ?.mapNotNull { item ->
                            val title = item.snippet?.title ?: return@mapNotNull null
                            val vid = item.snippet.resourceId?.videoId ?: return@mapNotNull null
                            VideoRow(
                                playlistItemId = item.id,
                                videoId = vid,
                                title = title
                            )
                        }.orEmpty()

                    runOnUiThread {
                        videoRows.clear()
                        videoRows.addAll(rows)
                        videoAdapter.selectionMode = false
                        btnToggleSelection.text = "Select videos"
                        btnMoveSelected.isEnabled = false
                        videoAdapter.submit(videoRows)
                    }
                }

                override fun onFailure(call: Call<PlaylistItemsResponse>, t: Throwable) {
                    Log.e("YT", "network fail", t)
                }
            })
        }
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

    /**
     * Move all selected videos to target playlist in sequence:
     * insert then delete then next.
     */
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
                btnToggleSelection.isEnabled = false
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
                        btnToggleSelection.isEnabled = true
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
}

data class PlaylistItemsResponse(val items: List<PlaylistVideoItem> = emptyList())

data class PlaylistVideoItem(
    val id: String,               // playlistItemId
    val snippet: VideoSnippet?
)

data class VideoSnippet(
    val title: String?,
    val resourceId: ResourceId?   // contains videoId
)

data class ResourceId(
    val videoId: String?
)

data class VideoRow(
    val playlistItemId: String,
    val videoId: String,
    val title: String,
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
