package com.tencent.iot.aiglasses.services

import android.content.Context
import com.tencent.iot.aiglasses.models.Record
import org.json.JSONArray
import java.io.File
import java.io.IOException

class RecordStore(private val file: File) {

    constructor(context: Context) : this(File(context.filesDir, "records.json"))

    fun load(): List<Record>? = runCatching {
        val array = JSONArray(file.readText())
        List(array.length()) { Record.fromJson(array.getJSONObject(it)) }
    }.getOrNull()

    @Throws(IOException::class)
    fun save(records: List<Record>) {
        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, file.name + ".tmp")
        temp.writeText(JSONArray(records.map { it.toJson() }).toString(2))
        if (!temp.renameTo(file)) throw IOException("rename failed")
    }
}
