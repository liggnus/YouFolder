package com.example.youfolder

import android.app.AlertDialog
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
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        swipeRefresh = findViewById(R.id.swipeRefresh)
        rv = findViewById(R.id.rvPlaylists)
        btnAdd = findViewById(R.id.btnAddPlaylist)

        rv.layoutManager = LinearLayoutManager(this)
        rv.adapter = adapter

        // Pull-to-refresh → reload playlists
        swipeRefresh.setOnRefreshListener {
            loadPlaylists()
        }

        // Restore AuthState that LoginActivity passed in
        val authJson = intent.getStringExtra("authStateJson")
        if (!authJson.isNullOrBlank()) {
            try {
                authState = AuthState.jsonDeserialize(authJson)
                // Auto-load playlists as soon as we have a valid AuthState
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

        // Show spinner while creating
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

                    // 🔁 Wait a bit so YouTube updates, then reload
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
                    runOnUiThread {
                        swipeRefresh.isRefreshing = false
                        adapter.submit(items)
                        android.widget.Toast.makeText(
                            this@MainActivity,
                            "Loaded ${items.size} playlists",
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
}

data class PlaylistsResponse(val items: List<PlaylistItem> = emptyList())
data class PlaylistItem(val id: String, val snippet: Snippet, val contentDetails: ContentDetails)
data class Snippet(val title: String)
data class ContentDetails(val itemCount: Int)

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
