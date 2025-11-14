package com.example.youfolder

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Button
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.AuthState
import net.openid.appauth.ResponseTypeValues

class LoginActivity : ComponentActivity() {

    private val authService by lazy { AuthorizationService(this) }
    private var authState: AuthState? = null

    private val discoveryUri: Uri =
        Uri.parse("https://accounts.google.com/.well-known/openid-configuration")

    private val clientId: String =
        "978706435903-09c7vrppjvo0102p87o9g6p68ejvv428.apps.googleusercontent.com"

    private val redirectUri: Uri =
        Uri.parse("com.example.youfolder:/oauth2redirect")

    private val authLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { res ->
            val intent = res.data ?: return@registerForActivityResult
            val resp = AuthorizationResponse.fromIntent(intent)
            val ex = AuthorizationException.fromIntent(intent)

            if (resp != null) {
                authState = AuthState(resp, ex)
                val tokenReq = resp.createTokenExchangeRequest()
                authService.performTokenRequest(tokenReq) { tokenResp, tokenEx ->
                    if (tokenResp != null) {
                        authState?.update(tokenResp, tokenEx)

                        val json = authState!!.jsonSerializeString()
                        startActivity(
                            Intent(this, MainActivity::class.java)
                                .putExtra("authStateJson", json)
                        )
                        finish()
                    } else {
                        Log.e("AUTH", "Token exchange failed", tokenEx)
                    }
                }
            } else if (ex != null) {
                Log.e("AUTH", "Auth error", ex)
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login)

        val btn: Button = findViewById(R.id.btnLoginYouTube)
        btn.setOnClickListener { startGoogleLogin() }
    }

    private fun startGoogleLogin() {
        AuthorizationServiceConfiguration.fetchFromUrl(discoveryUri) { config, _ ->
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
                    // 🔹 this scope lets us CREATE / EDIT playlists
                    "https://www.googleapis.com/auth/youtube"
                )
                .build()

            Log.d("AUTH", "clientId=$clientId redirect=$redirectUri")
            Log.d("AUTH", "authUri=${request.toUri()}")

            val intent = authService.getAuthorizationRequestIntent(request)
            authLauncher.launch(intent)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        authService.dispose()
    }
}
