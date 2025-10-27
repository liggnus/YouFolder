package com.example.youfolder

import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Button
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.AuthState
import net.openid.appauth.ResponseTypeValues
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

    private val googleDiscoveryUri =
        Uri.parse("https://accounts.google.com/.well-known/openid-configuration")

    // Your ANDROID OAuth client id
    private val clientId =
        "978706435903-09c7vrppjvo0102p87o9g6p68ejvv428.apps.googleusercontent.com"

    // Must match the manifest intent-filter
    private val redirectUri: Uri by lazy {
        Uri.parse(
            "com.example.youfolder:/oauth2redirect"
        )
    }

    private lateinit var btnSignIn: Button
    private lateinit var btnLoad: Button
    private lateinit var rv: RecyclerView
    private val adapter = PlaylistsAdapter()

    private val authLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { res ->
            val intent = res.data ?: return@registerForActivityResult
            val resp = net.openid.appauth.AuthorizationResponse.fromIntent(intent)
            val ex = AuthorizationException.fromIntent(intent)
            if (resp != null) {
                authState = AuthState(resp, ex)
                val tokenReq = resp.createTokenExchangeRequest()
                authService.performTokenRequest(tokenReq) { tokenResp, tokenEx ->
                    if (tokenResp != null) {
                        authState?.update(tokenResp, tokenEx)
                        btnLoad.isEnabled = true
                    } else {
                        btnLoad.isEnabled = false
                    }
                }
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        btnSignIn = findViewById(R.id.btnSignIn)
        btnLoad = findViewById(R.id.btnLoadPlaylists)
        rv = findViewById(R.id.rvPlaylists)
        rv.layoutManager = LinearLayoutManager(this)
        rv.adapter = adapter

        btnSignIn.setOnClickListener { startGoogleLogin() }
        btnLoad.setOnClickListener { loadPlaylists() }
    }

    private fun startGoogleLogin() {
        AuthorizationServiceConfiguration.fetchFromUrl(googleDiscoveryUri) { config, _ ->
            if (config == null) return@fetchFromUrl

            val request = AuthorizationRequest.Builder(
                config,
                clientId,
                ResponseTypeValues.CODE,
                redirectUri
            )
                .setScopes(
                    "openid",
                    "email",
                    "profile",
                    "https://www.googleapis.com/auth/youtube.readonly"
                )
                .build()

            // Debug logs
            Log.d("AUTH", "clientId=$clientId redirect=$redirectUri")
            Log.d("AUTH", "authUri=" + request.toUri())

            val intent = authService.getAuthorizationRequestIntent(request)
            authLauncher.launch(intent)
        }
    }

    private fun loadPlaylists() {
        val state = authState ?: run {
            android.widget.Toast.makeText(this, "Please sign in first.", android.widget.Toast.LENGTH_SHORT).show()
            return
        }

        // Ensure fresh token before calling API
        state.performActionWithFreshTokens(authService) { accessToken, _, ex ->
            if (ex != null) {
                Log.e("API", "Token refresh failed", ex)
                runOnUiThread {
                    android.widget.Toast.makeText(this, "Auth error: ${ex.error}", android.widget.Toast.LENGTH_LONG).show()
                }
                return@performActionWithFreshTokens
            }

            if (accessToken.isNullOrBlank()) {
                runOnUiThread {
                    android.widget.Toast.makeText(this, "No access token. Please sign in again.", android.widget.Toast.LENGTH_LONG).show()
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
                        // Read the error body safely
                        val errorBodyString = response.errorBody()?.string() ?: "Unknown error"
                        val errorCode = response.code()

                        Log.e("API", "HTTP $errorCode ${response.message()} — $errorBodyString")
                        runOnUiThread {
                            android.widget.Toast.makeText(
                                this@MainActivity,
                                // Provide a more detailed error message
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

        // --- START OF FIX ---

        // 1. Create a Moshi instance that can handle Kotlin classes
        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        // 2. Build Retrofit, passing the custom Moshi instance to the converter
        val retrofit = Retrofit.Builder()
            .baseUrl("https://www.googleapis.com/")
            .client(client)
            // Use the Moshi instance you just created
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()

        // --- END OF FIX ---

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
