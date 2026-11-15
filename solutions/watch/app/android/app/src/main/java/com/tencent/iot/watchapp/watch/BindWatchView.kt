package com.tencent.iot.watchapp.watch
import com.tencent.iot.watchapp.R

import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView

class BindWatchPage @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    private val input: EditText
    private val error: TextView
    private val submit: android.widget.Button
    private var onBind: ((String) -> Unit)? = null

    init {
        LayoutInflater.from(context).inflate(R.layout.watch_bind_watch_view, this, true)
        input = findViewById(R.id.watch_bind_watch_input)
        error = findViewById(R.id.watch_bind_watch_error)
        submit = findViewById(R.id.watch_bind_watch_submit)
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                submit.isEnabled = !s.isNullOrBlank()
                if (!s.isNullOrBlank()) hideError()
            }
            override fun afterTextChanged(s: Editable?) = Unit
        })
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                submit.performClick()
                true
            } else false
        }
        submit.setOnClickListener {
            val deviceName = input.text.toString().trim()
            if (deviceName.isEmpty()) {
                showErrorInternal(context.getString(R.string.watch_bind_watch_device_required))
            } else {
                hideKeyboard()
                onBind?.invoke(deviceName)
            }
        }
    }

    fun setOnBack(action: () -> Unit) {
        findViewById<android.widget.ImageButton>(R.id.watch_bind_watch_back).setOnClickListener { action() }
    }

    fun setOnBind(action: (String) -> Unit) {
        onBind = action
    }

    fun showError(message: String) {
        showErrorInternal(message)
    }

    private fun showErrorInternal(message: String) {
        error.text = message
        error.visibility = VISIBLE
        input.requestFocus()
    }

    private fun hideError() {
        error.text = ""
        error.visibility = GONE
    }

    private fun hideKeyboard() {
        context.getSystemService(InputMethodManager::class.java)
            ?.hideSoftInputFromWindow(input.windowToken, 0)
    }
}
