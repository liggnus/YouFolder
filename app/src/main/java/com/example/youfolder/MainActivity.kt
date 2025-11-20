package com.example.youfolder

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.EditText
import android.widget.ImageButton
import androidx.activity.ComponentActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationService
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Call
import retrofit2.Callback
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

class MainActivity : ComponentActivity() {

    private val authService by lazy { AuthorizationService(this) }
    private var authState: AuthState? = null

    private lateinit var rv: RecyclerView
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var btnAdd: ImageButton
    private val adapter = PlaylistsAdapter()

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var folderStore: FolderStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        folderStore = FolderStore(this)

        swipeRefresh = findViewById(R.id.swipeRefresh)
        rv = findViewById(R.id.rvPlaylists)
        btnAdd = findViewById(R.id.btnAddPlaylist)

        rv.layoutManager = LinearLayoutManager(this)
        rv.adapter = adapter

        // Tap → open playlist detail (videos + sub-folders)
        adapter.onItemClick = { playlist ->
            val state = authState
            if (state == null) {
                android.widget.Toast.makeText(
                    this,
                    "Auth missing, please sign in again.",
                    android.widget.Toast.LENGTH_LONG
                ).show()
            } else {
                val intent = Intent(this, PlaylistDetailActivity::class.java).apply {
                    putExtra("id", playlist.id)
                    putExtra("title", playlist.snippet.title)
                    putExtra("authStateJson", state.jsonSerializeString())
                }
                startActivity(intent)
            }
        }

        // Long press → manage (move / rename / remove / delete)
        adapter.onItemLongClick = { playlist ->
            showManageDialog(playlist)
        }

        // Pull-to-refresh → reload playlists
        swipeRefresh.setOnRefreshListener {
            loadPlaylists()
        }

        // Restore AuthState that LoginActivity passed in
        val authJson = intent.getStringExtra("authStateJson")
        if (!authJson.isNullOrBlank()) {
            try {
                authState = AuthState.jsonDeserialize(authJson)
                swipeRefresh.isRefreshing = true
                loadPlaylists()
            } catch (e: Exception) {
                Log.e("AUTH", "Failed to restore AuthState", e)
                android.widget.Toast.makeText(
                    this,
                    "Auth error, please sign in again.",
                    android.widget.Toast.LENGTH_LONG
                ).show()
                finish()
            }
        } else {
            android.widget.Toast.makeText(
                this,
                "Missing auth state, please sign in again.",
                android.widget.Toast.LENGTH_LONG
            ).show()
            finish()
        }

        btnAdd.setOnClickListener { showCreatePlaylistDialog() }
    }

    // 🔁 Whenever we return to this screen, reload structure from FolderStore
    override fun onResume() {
        super.onResume()
        // Do not show spinner here, just quietly refresh
        loadPlaylists()
    }

    // ---------- Manage menu ----------

    private fun showManageDialog(playlist: PlaylistItem) {
        val options = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()

        options += "Move into folder"
        actions += { showMoveIntoFolderDialog(playlist) }

        if (folderStore.getParent(playlist.id) != null) {
            options += "Remove from folder"
            actions += {
                folderStore.clearParent(playlist.id)
                android.widget.Toast.makeText(
                    this,
                    "Removed from folder",
                    android.widget.Toast.LENGTH_SHORT
                ).show()
                loadPlaylists()
            }
        }

        options += "Rename"
        actions += { showRenameDialog(playlist) }

        options += "Delete from YouTube"
        actions += { showDeleteDialog(playlist) }

        AlertDialog.Builder(this)
            .setTitle(playlist.snippet.title)
            .setItems(options.toTypedArray()) { _, which ->
                actions[which].invoke()
            }
            .show()
    }

    private fun showMoveIntoFolderDialog(playlist: PlaylistItem) {
        val all = adapter.currentItems()
        val candidates = all.filter { it.id != playlist.id }

        if (candidates.isEmpty()) {
            android.widget.Toast.makeText(
                this,
                "No other playlists to move into.",
                android.widget.Toast.LENGTH_SHORT
            ).show()
            return
        }

        val names = candidates.map { it.snippet.title }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Move into folder")
            .setItems(names) { _, which ->
                val parent = candidates[which]
                folderStore.setParent(playlist.id, parent.id)
                android.widget.Toast.makeText(
                    this,
                    "Moved into \"${parent.snippet.title}\"",
                    android.widget.Toast.LENGTH_SHORT
                ).show()

                // Immediately hide from root list
                val updated = adapter.currentItems().filter { it.id != playlist.id }
                adapter.submit(updated)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ---------- Rename playlist (root folder) ----------

    private fun showRenameDialog(playlist: PlaylistItem) {
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
                    android.widget.Toast.makeText(
                        this,
                        "Name cannot be empty.",
                        android.widget.Toast.LENGTH_SHORT
                    ).show()
                } else if (newTitle == playlist.snippet.title) {
                    android.widget.Toast.makeText(
                        this,
                        "Name not changed.",
                        android.widget.Toast.LENGTH_SHORT
                    ).show()
                } else {
                    renamePlaylist(playlist, newTitle)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun renamePlaylist(playlist: PlaylistItem, newTitle: String) {
        val state = authState ?: run {
            android.widget.Toast.makeText(
                this,
                "Please sign in first.",
                android.widget.Toast.LENGTH_SHORT
            ).show()
            return
        }

        state.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null) {
                Log.e("API", "Token refresh failed (renamePlaylist)", ex)
                runOnUiThread {
                    android.widget.Toast.makeText(
                        this,
                        "Auth error: ${ex.error}",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
                return@performActionWithFreshTokens
            }

            if (accessToken.isNullOrBlank()) {
                runOnUiThread {
                    android.widget.Toast.makeText(
                        this,
                        "No access token. Please sign in again.",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
                return@performActionWithFreshTokens
            }

            val api = youtubeService()
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
                    response: retrofit2.Response<PlaylistItem>
                ) {
                    if (!response.isSuccessful) {
                        val errorBodyString = response.errorBody()?.string() ?: "Unknown error"
                        val errorCode = response.code()
                        Log.e(
                            "API",
                            "Rename playlist HTTP $errorCode ${response.message()} — $errorBodyString"
                        )
                        runOnUiThread {
                            android.widget.Toast.makeText(
                                this@MainActivity,
                                "Failed to rename folder ($errorCode)",
                                android.widget.Toast.LENGTH_LONG
                            ).show()
                        }
                        return
                    }

                    // ✅ Update UI immediately
                    runOnUiThread {
                        val updatedList = adapter.currentItems().map {
                            if (it.id == playlist.id) it.copy(snippet = Snippet(newTitle))
                            else it
                        }
                        adapter.submit(updatedList)

                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Renamed to \"$newTitle\"",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }

                    // optional: small delayed reload from YouTube to stay in sync
                    handler.postDelayed({
                        loadPlaylists()
                    }, 1000L)
                }

                override fun onFailure(call: Call<PlaylistItem>, t: Throwable) {
                    Log.e("API", "Network failure (renamePlaylist)", t)
                    runOnUiThread {
                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Network error: ${t.localizedMessage}",
                            android.widget.Toast.LENGTH_LONG
                        ).show()
                    }
                }
            })
        }
    }

    // ---------- Create playlist ----------

    private fun showCreatePlaylistDialog() {
        val input = EditText(this).apply {
            hint = "Playlist name"
        }

        AlertDialog.Builder(this)
            .setTitle("New playlist")
            .setView(input)
            .setPositiveButton("Create") { _, _ ->
                val title = input.text.toString().trim()
                if (title.isNotEmpty()) {
                    createPlaylist(title)
                } else {
                    android.widget.Toast.makeText(
                        this,
                        "Name cannot be empty.",
                        android.widget.Toast.LENGTH_SHORT
                    ).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun createPlaylist(title: String) {
        val state = authState ?: run {
            android.widget.Toast.makeText(
                this,
                "Please sign in first.",
                android.widget.Toast.LENGTH_SHORT
            ).show()
            return
        }

        runOnUiThread { swipeRefresh.isRefreshing = true }

        state.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null) {
                Log.e("API", "Token refresh failed (createPlaylist)", ex)
                runOnUiThread {
                    swipeRefresh.isRefreshing = false
                    android.widget.Toast.makeText(
                        this,
                        "Auth error: ${ex.error}",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
                return@performActionWithFreshTokens
            }

            if (accessToken.isNullOrBlank()) {
                runOnUiThread {
                    swipeRefresh.isRefreshing = false
                    android.widget.Toast.makeText(
                        this,
                        "No access token. Please sign in again.",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
                return@performActionWithFreshTokens
            }

            val api = youtubeService()
            val body = CreatePlaylistRequest(
                snippet = CreatePlaylistSnippet(title = title),
                status = CreatePlaylistStatus(privacyStatus = "private")
            )

            api.createPlaylist(
                part = "snippet,status",
                auth = "Bearer $accessToken",
                body = body
            ).enqueue(object : Callback<Void> {
                override fun onResponse(
                    call: Call<Void>,
                    response: retrofit2.Response<Void>
                ) {
                    if (!response.isSuccessful) {
                        val errorBodyString = response.errorBody()?.string() ?: "Unknown error"
                        val errorCode = response.code()
                        Log.e(
                            "API",
                            "Create playlist HTTP $errorCode ${response.message()} — $errorBodyString"
                        )
                        runOnUiThread {
                            swipeRefresh.isRefreshing = false
                            android.widget.Toast.makeText(
                                this@MainActivity,
                                "Failed to create playlist ($errorCode)",
                                android.widget.Toast.LENGTH_LONG
                            ).show()
                        }
                        return
                    }

                    runOnUiThread {
                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Playlist \"$title\" created",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }

                    handler.postDelayed({
                        swipeRefresh.isRefreshing = true
                        loadPlaylists()
                    }, 1500L)
                }

                override fun onFailure(call: Call<Void>, t: Throwable) {
                    Log.e("API", "Network failure (createPlaylist)", t)
                    runOnUiThread {
                        swipeRefresh.isRefreshing = false
                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Network error: ${t.localizedMessage}",
                            android.widget.Toast.LENGTH_LONG
                        ).show()
                    }
                }
            })
        }
    }

    // ---------- Delete playlist ----------

    private fun showDeleteDialog(playlist: PlaylistItem) {
        AlertDialog.Builder(this)
            .setTitle("Delete playlist")
            .setMessage("Delete \"${playlist.snippet.title}\" from YouTube?")
            .setPositiveButton("Delete") { _, _ ->
                deletePlaylist(playlist)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun deletePlaylist(playlist: PlaylistItem) {
        val state = authState ?: run {
            android.widget.Toast.makeText(
                this,
                "Please sign in first.",
                android.widget.Toast.LENGTH_SHORT
            ).show()
            return
        }

        runOnUiThread { swipeRefresh.isRefreshing = true }

        state.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null) {
                Log.e("API", "Token refresh failed (deletePlaylist)", ex)
                runOnUiThread {
                    swipeRefresh.isRefreshing = false
                    android.widget.Toast.makeText(
                        this,
                        "Auth error: ${ex.error}",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
                return@performActionWithFreshTokens
            }

            if (accessToken.isNullOrBlank()) {
                runOnUiThread {
                    swipeRefresh.isRefreshing = false
                    android.widget.Toast.makeText(
                        this,
                        "No access token. Please sign in again.",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
                return@performActionWithFreshTokens
            }

            val api = youtubeService()
            api.deletePlaylist(
                id = playlist.id,
                auth = "Bearer $accessToken"
            ).enqueue(object : Callback<Void> {
                override fun onResponse(
                    call: Call<Void>,
                    response: retrofit2.Response<Void>
                ) {
                    if (!response.isSuccessful) {
                        val errorBodyString = response.errorBody()?.string() ?: "Unknown error"
                        val errorCode = response.code()
                        Log.e(
                            "API",
                            "Delete playlist HTTP $errorCode ${response.message()} — $errorBodyString"
                        )
                        runOnUiThread {
                            swipeRefresh.isRefreshing = false
                            android.widget.Toast.makeText(
                                this@MainActivity,
                                "Failed to delete playlist ($errorCode)",
                                android.widget.Toast.LENGTH_LONG
                            ).show()
                        }
                        return
                    }

                    runOnUiThread {
                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Deleted \"${playlist.snippet.title}\"",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }

                    handler.postDelayed({
                        swipeRefresh.isRefreshing = true
                        loadPlaylists()
                    }, 1500L)
                }

                override fun onFailure(call: Call<Void>, t: Throwable) {
                    Log.e("API", "Network failure (deletePlaylist)", t)
                    runOnUiThread {
                        swipeRefresh.isRefreshing = false
                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Network error: ${t.localizedMessage}",
                            android.widget.Toast.LENGTH_LONG
                        ).show()
                    }
                }
            })
        }
    }

    // ---------- Load playlists (root only) ----------

    private fun loadPlaylists() {
        val state = authState ?: run {
            swipeRefresh.isRefreshing = false
            android.widget.Toast.makeText(
                this,
                "Please sign in first.",
                android.widget.Toast.LENGTH_SHORT
            ).show()
            return
        }

        state.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null) {
                Log.e("API", "Token refresh failed", ex)
                runOnUiThread {
                    swipeRefresh.isRefreshing = false
                    android.widget.Toast.makeText(
                        this,
                        "Auth error: ${ex.error}",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
                return@performActionWithFreshTokens
            }

            if (accessToken.isNullOrBlank()) {
                runOnUiThread {
                    swipeRefresh.isRefreshing = false
                    android.widget.Toast.makeText(
                        this,
                        "No access token. Please sign in again.",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                }
                return@performActionWithFreshTokens
            }

            val api = youtubeService()
            api.listPlaylists(
                part = "snippet,contentDetails",
                mine = true,
                maxResults = 50,
                auth = "Bearer $accessToken"
            ).enqueue(object : Callback<PlaylistsResponse> {
                override fun onResponse(
                    call: Call<PlaylistsResponse>,
                    response: retrofit2.Response<PlaylistsResponse>
                ) {
                    if (!response.isSuccessful) {
                        val errorBodyString = response.errorBody()?.string() ?: "Unknown error"
                        val errorCode = response.code()

                        Log.e(
                            "API",
                            "HTTP $errorCode ${response.message()} — $errorBodyString"
                        )
                        runOnUiThread {
                            swipeRefresh.isRefreshing = false
                            android.widget.Toast.makeText(
                                this@MainActivity,
                                "API Error: $errorCode. See Logcat for details.",
                                android.widget.Toast.LENGTH_LONG
                            ).show()
                        }
                        return
                    }

                    val items = response.body()?.items.orEmpty()
                    // Only root playlists (no parent)
                    val roots = items.filter { folderStore.getParent(it.id) == null }

                    runOnUiThread {
                        swipeRefresh.isRefreshing = false
                        adapter.submit(roots)
                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Loaded ${roots.size} playlists",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                }

                override fun onFailure(call: Call<PlaylistsResponse>, t: Throwable) {
                    Log.e("API", "Network failure", t)
                    runOnUiThread {
                        swipeRefresh.isRefreshing = false
                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Network error: ${t.localizedMessage}",
                            android.widget.Toast.LENGTH_LONG
                        ).show()
                    }
                }
            })
        }
    }

    // ---------- Retrofit setup ----------

    private fun youtubeService(): YouTubeApi {
        val log = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BODY
        }
        val client = OkHttpClient.Builder()
            .addInterceptor(log)
            .build()

        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        val retrofit = Retrofit.Builder()
            .baseUrl("https://www.googleapis.com/")
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()

        return retrofit.create(YouTubeApi::class.java)
    }

    override fun onDestroy() {
        super.onDestroy()
        authService.dispose()
    }
}

// Retrofit API + models

interface YouTubeApi {
    @GET("youtube/v3/playlists")
    fun listPlaylists(
        @Query("part") part: String,
        @Query("mine") mine: Boolean,
        @Query("maxResults") maxResults: Int,
        @Header("Authorization") auth: String
    ): Call<PlaylistsResponse>

    @POST("youtube/v3/playlists")
    fun createPlaylist(
        @Query("part") part: String,
        @Header("Authorization") auth: String,
        @Body body: CreatePlaylistRequest
    ): Call<Void>

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

data class PlaylistsResponse(val items: List<PlaylistItem> = emptyList())

// 🔧 contentDetails is now optional + has default
data class PlaylistItem(
    val id: String,
    val snippet: Snippet,
    val contentDetails: ContentDetails? = null
)

data class Snippet(val title: String)

data class ContentDetails(val itemCount: Int = 0)

data class CreatePlaylistRequest(
    val snippet: CreatePlaylistSnippet,
    val status: CreatePlaylistStatus
)

data class CreatePlaylistSnippet(
    val title: String,
    val description: String? = null
)

data class CreatePlaylistStatus(
    val privacyStatus: String
)

data class UpdatePlaylistRequest(
    val id: String,
    val snippet: Snippet
)
