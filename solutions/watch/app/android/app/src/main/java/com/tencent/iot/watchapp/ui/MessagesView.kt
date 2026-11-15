package com.tencent.iot.watchapp.ui
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity
import com.tencent.iot.watchapp.im.MessagesAdapter
import com.tencent.iot.watchapp.im.WatchImConversation

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import android.text.Editable
import android.text.TextWatcher

class MessagesView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    private val adapter: MessagesAdapter
    private var latestConversations: List<WatchImConversation> = emptyList()

    init {
        LayoutInflater.from(context).inflate(R.layout.watch_messages_view, this, true)
        adapter = MessagesAdapter { conversation -> (context as? MainActivity)?.showChat(conversation) }
        findViewById<RecyclerView>(R.id.watch_conversation_list).apply {
            layoutManager = LinearLayoutManager(context)
            adapter = this@MessagesView.adapter
        }
        findViewById<EditText>(R.id.watch_message_search).addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(text: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) {
                val query = text?.toString()?.trim().orEmpty()
                adapter.submitConversations(if (query.isBlank()) latestConversations else latestConversations.filter {
                    it.title.contains(query, ignoreCase = true) || it.preview.contains(query, ignoreCase = true)
                })
            }
            override fun afterTextChanged(editable: Editable?) = Unit
        })
        findViewById<android.widget.ImageButton>(R.id.watch_message_add).setOnClickListener {
            (context as? MainActivity)?.showAddContact()
        }
    }

    fun renderConversations(conversations: List<WatchImConversation>) {
        latestConversations = conversations
        val query = findViewById<EditText>(R.id.watch_message_search).text.toString().trim()
        adapter.submitConversations(if (query.isBlank()) conversations else conversations.filter {
            it.title.contains(query, ignoreCase = true) || it.preview.contains(query, ignoreCase = true)
        })
    }
}
