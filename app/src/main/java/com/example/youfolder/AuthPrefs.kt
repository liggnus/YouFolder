package com.example.youfolder

import android.content.Context
import android.util.Log
import net.openid.appauth.AuthState

object AuthPrefs {

    private const val PREFS_NAME = "auth_prefs"
    private const val KEY_AUTH_STATE = "auth_state_json"

    fun save(context: Context, state: AuthState) {
        val json = state.jsonSerializeString()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_AUTH_STATE, json)
            .apply()
        Log.d("AuthPrefs", "AuthState saved")
    }

    fun read(context: Context): AuthState? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_AUTH_STATE, null) ?: return null
        return try {
            AuthState.jsonDeserialize(json)
        } catch (e: Exception) {
            Log.e("AuthPrefs", "Failed to deserialize saved AuthState", e)
            null
        }
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_AUTH_STATE)
            .apply()
    }
}
