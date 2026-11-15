package com.tencent.iot.watchapp.watch
import com.tencent.iot.watchapp.config.WatchSdkConfig

import android.content.Context
import org.json.JSONArray

data class BoundWatch(
    val productId: String,
    val deviceName: String,
)

/** 首期本地绑定数据源；设备上线后由服务端绑定接口替换。 */
object WatchBindingStore {
    private const val preferencesName = "watch_binding"
    private const val deviceNameKeyPrefix = "device_name_"
    private const val deviceNamesKeyPrefix = "device_names_"

    fun bind(context: Context, userId: String, deviceName: String): BoundWatch? {
        val normalized = deviceName.trim()
        if (normalized.isBlank()) return null
        val watches = all(context, userId).toMutableList()
        val existing = watches.firstOrNull { it.deviceName == normalized }
        if (existing != null) return existing
        val bound = BoundWatch(WatchSdkConfig.boundWatchProductId, normalized)
        watches += bound
        save(context, userId, watches)
        return bound
    }

    fun all(context: Context, userId: String): List<BoundWatch> {
        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        val newKey = namesKeyFor(userId)
        val storedNames = preferences.getString(newKey, null)
        val names = if (storedNames.isNullOrBlank()) {
            val legacyName = preferences.getString(legacyKeyFor(userId), null)?.trim().orEmpty()
            if (legacyName.isNotBlank()) {
                val migrated = listOf(legacyName)
                preferences.edit().putString(newKey, encode(migrated)).apply()
                migrated
            } else {
                emptyList()
            }
        } else {
            decode(storedNames)
        }
        return names.distinct().map { BoundWatch(WatchSdkConfig.boundWatchProductId, it) }
    }

    fun current(context: Context, userId: String): BoundWatch? {
        return all(context, userId).firstOrNull()
    }

    private fun save(context: Context, userId: String, watches: List<BoundWatch>) {
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(namesKeyFor(userId), encode(watches.map { it.deviceName }))
            .apply()
    }

    private fun encode(names: List<String>): String = JSONArray(names).toString()

    private fun decode(value: String): List<String> {
        return runCatching {
            val array = JSONArray(value)
            buildList(array.length()) {
                for (index in 0 until array.length()) {
                    array.optString(index).trim().takeIf { it.isNotBlank() }?.let(::add)
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun namesKeyFor(userId: String): String = "$deviceNamesKeyPrefix${userId.ifBlank { "anonymous" }}"

    private fun legacyKeyFor(userId: String): String = "$deviceNameKeyPrefix${userId.ifBlank { "anonymous" }}"
}
