package com.parksence.auth

import android.content.Context
import com.parksence.api.ApiClient
import com.parksence.api.UserProfile

/**
 * Persists JWT token and user profile in SharedPreferences.
 * Also keeps ApiClient.authToken in sync.
 */
object UserSession {

    private const val PREFS = "session"

    fun save(context: Context, token: String, profile: UserProfile) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            putString("token", token)
            putInt("user_id", profile.id)
            putString("email", profile.email)
            putString("vehicle_type", profile.vehicleType)
            putBoolean("is_disabled", profile.isDisabled)
            putBoolean("has_resident_permit", profile.hasResidentPermit)
            putString("resident_zone", profile.residentZone)
            apply()
        }
        ApiClient.authToken = token
    }

    fun load(context: Context): UserProfile? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val token = prefs.getString("token", null) ?: return null
        ApiClient.authToken = token
        return UserProfile(
            id = prefs.getInt("user_id", 0),
            email = prefs.getString("email", "") ?: "",
            vehicleType = prefs.getString("vehicle_type", "car") ?: "car",
            isDisabled = prefs.getBoolean("is_disabled", false),
            hasResidentPermit = prefs.getBoolean("has_resident_permit", false),
            residentZone = prefs.getString("resident_zone", "") ?: "",
        )
    }

    fun updateProfile(context: Context, profile: UserProfile) {
        val token = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("token", null) ?: return
        save(context, token, profile)
    }

    fun isLoggedIn(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).contains("token")

    fun logout(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        ApiClient.authToken = null
    }
}
