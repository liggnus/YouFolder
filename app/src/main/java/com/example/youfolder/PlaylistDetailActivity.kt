package com.example.youfolder

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.util.Log
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
import retrofit2.http.GET
import retrofit2.http.Header
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

        val json = intent.getStringExtra("authStateJson") ?: ""
        authState = AuthState.jsonDeserialize(json)

        loadSubPlaylists()
        loadVideos()
    }

    // 🔁 When coming back to this screen, re-read subfolders
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

                    val titles = response.body()?.items
                        ?.mapNotNull { it.snippet?.title }
                        .orEmpty()

                    runOnUiThread {
                        videoAdapter.submit(titles)
                    }
                }

                override fun onFailure(call: Call<PlaylistItemsResponse>, t: Throwable) {
                    Log.e("YT", "network fail", t)
                }
            })
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
}

data class PlaylistItemsResponse(val items: List<PlaylistVideoItem> = emptyList())
data class PlaylistVideoItem(val snippet: VideoSnippet?)
data class VideoSnippet(val title: String?)
