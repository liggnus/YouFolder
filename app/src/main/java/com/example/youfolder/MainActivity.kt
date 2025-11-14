package com.example.youfolder

import android.os.Bundle
import android.util.Log
import android.widget.Button
import androidx.activity.ComponentActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationService
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Call
import retrofit2.Callback
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Query
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

class MainActivity : ComponentActivity() {

    private val authService by lazy { AuthorizationService(this) }
    private var authState: AuthState? = null

    private lateinit var btnLoad: Button
    private lateinit var rv: RecyclerView
    private val adapter = PlaylistsAdapter()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        btnLoad = findViewById(R.id.btnLoadPlaylists)
        rv = findViewById(R.id.rvPlaylists)
        rv.layoutManager = LinearLayoutManager(this)
        rv.adapter = adapter

        // Restore AuthState that LoginActivity passed in
        val authJson = intent.getStringExtra("authStateJson")
        if (!authJson.isNullOrBlank()) {
            try {
                authState = AuthState.jsonDeserialize(authJson)
                btnLoad.isEnabled = true
            } catch (e: Exception) {
                Log.e("AUTH", "Failed to restore AuthState", e)
                btnLoad.isEnabled = false
            }
        } else {
            btnLoad.isEnabled = false
        }

        btnLoad.setOnClickListener { loadPlaylists() }
    }

    private fun loadPlaylists() {
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
                Log.e("API", "Token refresh failed", ex)
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
}

data class PlaylistsResponse(val items: List<PlaylistItem> = emptyList())
data class PlaylistItem(val id: String, val snippet: Snippet, val contentDetails: ContentDetails)
data class Snippet(val title: String)
data class ContentDetails(val itemCount: Int)
