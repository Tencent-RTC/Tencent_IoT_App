package com.tencent.iot.aiglasses.app

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate

enum class AppTheme(val rawValue: String) {
    SOFT("soft"),
    DARK("dark");

    val toggled: AppTheme
        get() = if (this == DARK) SOFT else DARK

    private val nightMode: Int
        get() = if (this == DARK) AppCompatDelegate.MODE_NIGHT_YES else AppCompatDelegate.MODE_NIGHT_NO

    companion object {
        const val STORAGE_KEY = "appTheme"
        private const val PREFS = "suisheng"

        fun current(context: Context): AppTheme {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(STORAGE_KEY, null)
            return entries.firstOrNull { it.rawValue == raw } ?: SOFT
        }

        fun save(context: Context, theme: AppTheme) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(STORAGE_KEY, theme.rawValue).apply()
            AppCompatDelegate.setDefaultNightMode(theme.nightMode)
        }

        fun applySaved(context: Context) {
            AppCompatDelegate.setDefaultNightMode(current(context).nightMode)
        }
    }
}
