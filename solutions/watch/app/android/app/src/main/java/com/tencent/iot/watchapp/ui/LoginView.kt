package com.tencent.iot.watchapp.ui
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity
import com.tencent.iot.watchapp.call.IoTLoginState
import com.tencent.iot.watchapp.config.WatchSdkConfig

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.MotionEvent
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.text.method.HideReturnsTransformationMethod
import android.text.method.PasswordTransformationMethod
import androidx.appcompat.app.AlertDialog

class LoginView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    private lateinit var loginButton: Button
    private lateinit var secretInput: EditText

    init {
        LayoutInflater.from(context).inflate(R.layout.watch_login_view, this, true)
        findViewById<EditText>(R.id.watch_room_id).setText(WatchSdkConfig.TRTC_ROOM_ID)
        findViewById<EditText>(R.id.watch_sdk_app_id).setText(WatchSdkConfig.TRTC_SDK_APP_ID.toString())
        secretInput = findViewById(R.id.watch_sdk_secret)
        secretInput.setText(WatchSdkConfig.TRTC_SECRET_KEY)
        loginButton = findViewById(R.id.watch_login_button)
        val secret = secretInput
        secret.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP && event.x >= secret.width - secret.paddingEnd - 48) {
                val visible = secret.transformationMethod == PasswordTransformationMethod.getInstance()
                secret.transformationMethod = if (visible) HideReturnsTransformationMethod.getInstance() else PasswordTransformationMethod.getInstance()
                secret.setSelection(secret.text.length)
                return@setOnTouchListener true
            }
            false
        }
        loginButton.setOnClickListener {
            val roomId = findViewById<EditText>(R.id.watch_room_id)
            val sdkAppId = findViewById<EditText>(R.id.watch_sdk_app_id)
            val missingFields = buildList {
                if (roomId.text.toString().trim().isEmpty()) add(context.getString(R.string.watch_room_label))
                if (sdkAppId.text.toString().trim().isEmpty()) add(context.getString(R.string.watch_sdk_app_id_label))
                if (secret.text.toString().trim().isEmpty()) add(context.getString(R.string.watch_sdk_secret_label))
            }
            if (missingFields.isNotEmpty()) {
                showMissingFields(missingFields)
                return@setOnClickListener
            }
            renderLoginState(IoTLoginState.LoggingIn)
            (context as? MainActivity)?.onLoginSubmitted(
                roomId.text.toString().trim(),
                sdkAppId.text.toString().trim(),
                secret.text.toString().trim(),
            )
        }
    }

    private fun showMissingFields(fields: List<String>) {
        AlertDialog.Builder(context)
            .setTitle(R.string.watch_login_missing_title)
            .setMessage(context.getString(R.string.watch_login_missing_message, fields.joinToString("、")))
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    fun renderLoginState(state: IoTLoginState) {
        when (state) {
            IoTLoginState.LoggingIn -> {
                loginButton.isEnabled = false
                loginButton.setText(R.string.watch_login_loading)
                secretInput.error = null
            }
            is IoTLoginState.Failed -> {
                loginButton.isEnabled = true
                loginButton.setText(R.string.watch_login)
                secretInput.error = context.getString(R.string.watch_login_failed)
            }
            else -> {
                loginButton.isEnabled = true
                loginButton.setText(R.string.watch_login)
            }
        }
    }
}
