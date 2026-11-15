package com.tencent.iot.watchapp.ui
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity
import com.tencent.iot.watchapp.call.*

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.core.view.doOnLayout
import com.tencent.rtmp.ui.TXCloudVideoView
import java.util.Locale

class OutgoingCallView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    private var active = false
    private var voiceMode = false
    private var microphoneEnabled = true
    private var speakerEnabled = true
    private var cameraEnabled = true
    private var activeStartedAt = 0L
    private var localVideo: TXCloudVideoView? = null
    private var remoteVideo: TXCloudVideoView? = null
    private val timerHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val timerRunnable = object : Runnable {
        override fun run() {
            if (!active) return
            updateTimer()
            timerHandler.postDelayed(this, 1000L)
        }
    }

    init {
        id = R.id.watch_outgoing_call_root
        LayoutInflater.from(context).inflate(R.layout.watch_outgoing_call, this, true)
        findViewById<TXCloudVideoView>(R.id.watch_call_remote_video).addVideoView(TextureView(context))
        findViewById<TXCloudVideoView>(R.id.watch_call_local_video).addVideoView(TextureView(context))
    }

    fun configure(voiceMode: Boolean, targetName: String, avatarRes: Int) {
        this.voiceMode = voiceMode
        active = false
        microphoneEnabled = true
        speakerEnabled = true
        cameraEnabled = true
        setBackgroundResource(if (voiceMode) R.drawable.watch_call_voice_background else R.color.watch_call_dark)

        val stage = findViewById<ImageView>(R.id.watch_call_stage)
        val avatarBackground = findViewById<ImageView>(R.id.watch_call_avatar_background)
        val avatarScrim = findViewById<View>(R.id.watch_call_avatar_scrim)
        stage.visibility = if (voiceMode) View.GONE else View.VISIBLE
        avatarBackground.visibility = View.GONE
        avatarScrim.visibility = View.GONE
        findViewById<View>(R.id.watch_call_video_overlay_top).visibility = if (voiceMode) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_call_video_overlay_bottom).visibility = if (voiceMode) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_call_video_wait).visibility = if (voiceMode) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_call_voice_content).visibility = if (voiceMode) View.VISIBLE else View.GONE
        findViewById<View>(R.id.watch_call_local_pip).visibility = View.GONE
        findViewById<View>(R.id.watch_call_remote_video).visibility = View.GONE
        findViewById<View>(R.id.watch_call_dock).visibility = View.VISIBLE
        findViewById<View>(R.id.watch_call_video_tools).visibility = if (voiceMode) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_call_voice_tools).visibility = if (voiceMode) View.VISIBLE else View.GONE
        findViewById<View>(R.id.watch_call_mute_action).visibility = if (voiceMode) View.GONE else View.GONE
        findViewById<View>(R.id.watch_call_voice_mute_action).visibility = if (voiceMode) View.VISIBLE else View.GONE
        findViewById<View>(R.id.watch_call_camera_action).visibility = if (voiceMode) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_call_flip_action).visibility = if (voiceMode) View.GONE else View.VISIBLE

        findViewById<TextView>(R.id.watch_call_nav_title).text = if (voiceMode) {
            context.getString(R.string.watch_call_voice)
        } else targetName
        findViewById<TextView>(R.id.watch_call_nav_subtitle).setText(
            if (voiceMode) R.string.watch_call_voice_calling else R.string.watch_call_video_calling,
        )
        findViewById<ImageView>(R.id.watch_call_video_wait_avatar).setImageResource(avatarRes)
        findViewById<ImageView>(R.id.watch_call_voice_avatar).setImageResource(avatarRes)
        findViewById<TextView>(R.id.watch_call_voice_name).text = targetName
        findViewById<TextView>(R.id.watch_call_video_wait_status).setText(R.string.watch_call_waiting)
        findViewById<TextView>(R.id.watch_call_voice_status).setText(R.string.watch_call_waiting)
        findViewById<ImageView>(R.id.watch_call_avatar_background).setImageResource(avatarRes)

        findViewById<ImageButton>(R.id.watch_call_nav_back).setOnClickListener {
            (context as? MainActivity)?.dismissOutgoingCall()
        }
        findViewById<TextView>(R.id.watch_call_main_action).apply {
            contentDescription = context.getString(R.string.watch_cancel)
            setOnClickListener { (context as? MainActivity)?.dismissOutgoingCall() }
        }
        bindActiveControls()
        renderControlState()
    }

    fun startLocalPreview(coordinator: CallCoordinator) {
        if (voiceMode || localVideo != null) return
        val local = findViewById<TXCloudVideoView>(R.id.watch_call_local_video)
        localVideo = local
        local.visibility = View.VISIBLE
        findViewById<ImageView>(R.id.watch_call_stage).visibility = View.GONE
        findViewById<View>(R.id.watch_call_video_wait).visibility = View.GONE
        local.doOnLayout {
            if (localVideo === local && isAttachedToWindow) coordinator.startLocalVideo(AndroidCallVideoSurface(local))
        }
    }

    fun setActive(coordinator: CallCoordinator, videoMode: Boolean) {
        if (active) return
        active = true
        voiceMode = !videoMode
        activeStartedAt = System.currentTimeMillis()
        timerHandler.removeCallbacks(timerRunnable)
        timerHandler.post(timerRunnable)

        findViewById<View>(R.id.watch_call_video_wait).visibility = View.GONE
        findViewById<View>(R.id.watch_call_voice_content).visibility = if (videoMode) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_call_video_overlay_top).visibility = if (videoMode) View.VISIBLE else View.GONE
        findViewById<View>(R.id.watch_call_video_overlay_bottom).visibility = if (videoMode) View.VISIBLE else View.GONE
        findViewById<View>(R.id.watch_call_video_tools).visibility = if (videoMode) View.VISIBLE else View.GONE
        findViewById<View>(R.id.watch_call_voice_tools).visibility = if (videoMode) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_call_mute_action).visibility = if (videoMode) View.VISIBLE else View.GONE
        findViewById<View>(R.id.watch_call_voice_mute_action).visibility = if (videoMode) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_call_local_pip).visibility = if (videoMode) View.VISIBLE else View.GONE
        findViewById<TextView>(R.id.watch_call_main_action).setText(R.string.watch_hangup)
        findViewById<TextView>(R.id.watch_call_main_action).setBackgroundResource(R.drawable.watch_call_action_cancel)
        findViewById<TextView>(R.id.watch_call_nav_subtitle).setText(
            if (videoMode) R.string.watch_call_active_video else R.string.watch_call_active_voice,
        )

        if (!videoMode) {
            findViewById<View>(R.id.watch_call_stage).visibility = View.GONE
            findViewById<View>(R.id.watch_call_avatar_background).visibility = View.GONE
            findViewById<View>(R.id.watch_call_voice_wave).visibility = View.VISIBLE
            return
        }
        val remote = findViewById<TXCloudVideoView>(R.id.watch_call_remote_video)
        remoteVideo = remote
        remote.visibility = View.VISIBLE
        remote.doOnLayout {
            if (active && remote.isAttachedToWindow) coordinator.bindRemote(AndroidCallVideoSurface(remote))
        }
        val local = localVideo ?: findViewById<TXCloudVideoView>(R.id.watch_call_local_video).also {
            localVideo = it
            it.visibility = View.VISIBLE
            it.doOnLayout {
                if (active && localVideo === it && it.isAttachedToWindow) coordinator.startLocalVideo(AndroidCallVideoSurface(it))
            }
        }
        val pip = findViewById<FrameLayout>(R.id.watch_call_local_pip)
        if (local.parent !== pip) {
            (local.parent as? FrameLayout)?.removeView(local)
            pip.addView(local, 0, FrameLayout.LayoutParams(-1, -1))
        }
        pip.bringToFront()
    }

    override fun onDetachedFromWindow() {
        active = false
        timerHandler.removeCallbacks(timerRunnable)
        super.onDetachedFromWindow()
    }

    private fun bindActiveControls() {
        findViewById<View>(R.id.watch_call_camera_action).setOnClickListener {
            val coordinator = (context as? MainActivity)?.callCoordinator ?: return@setOnClickListener
            val local = localVideo ?: findViewById<TXCloudVideoView>(R.id.watch_call_local_video)
            cameraEnabled = !cameraEnabled
            coordinator.setCameraEnabled(cameraEnabled, AndroidCallVideoSurface(local))
            local.visibility = if (cameraEnabled) View.VISIBLE else View.INVISIBLE
            renderControlState()
        }
        findViewById<View>(R.id.watch_call_flip_action).setOnClickListener {
            (context as? MainActivity)?.callCoordinator?.switchCamera()
        }
        findViewById<View>(R.id.watch_call_mute_action).setOnClickListener { toggleMicrophone() }
        findViewById<View>(R.id.watch_call_voice_mute_action).setOnClickListener { toggleMicrophone() }
        findViewById<View>(R.id.watch_call_speaker_action).setOnClickListener { toggleSpeaker() }
        findViewById<View>(R.id.watch_call_voice_speaker_action).setOnClickListener { toggleSpeaker() }
        findViewById<View>(R.id.watch_call_main_action).setOnClickListener {
            (context as? MainActivity)?.dismissOutgoingCall()
        }
    }

    private fun toggleMicrophone() {
        val coordinator = (context as? MainActivity)?.callCoordinator ?: return
        microphoneEnabled = !microphoneEnabled
        coordinator.setMicrophoneEnabled(microphoneEnabled)
        renderControlState()
    }

    private fun toggleSpeaker() {
        val coordinator = (context as? MainActivity)?.callCoordinator ?: return
        speakerEnabled = !speakerEnabled
        coordinator.setSpeakerphoneEnabled(speakerEnabled)
        renderControlState()
    }

    private fun renderControlState() {
        val muteIcon = findViewById<ImageView>(R.id.watch_call_mute_icon)
        val muteLabel = findViewById<TextView>(R.id.watch_call_mute_label)
        muteIcon.setImageResource(if (microphoneEnabled) R.drawable.watch_icon_mic else R.drawable.watch_icon_mic_off)
        muteLabel.setText(if (microphoneEnabled) R.string.watch_call_mute else R.string.watch_call_mic_on)
        findViewById<ImageView>(R.id.watch_call_voice_mute_icon).setImageResource(if (microphoneEnabled) R.drawable.watch_icon_mic else R.drawable.watch_icon_mic_off)
        findViewById<TextView>(R.id.watch_call_voice_mute_label).setText(if (microphoneEnabled) R.string.watch_call_mute else R.string.watch_call_mic_on)

        val speakerRes = if (speakerEnabled) R.drawable.watch_icon_speaker else R.drawable.watch_icon_earpiece
        findViewById<ImageView>(R.id.watch_call_speaker_icon).setImageResource(speakerRes)
        findViewById<TextView>(R.id.watch_call_speaker_label).setText(if (speakerEnabled) R.string.watch_call_speaker else R.string.watch_call_earpiece)
        findViewById<ImageView>(R.id.watch_call_voice_speaker_icon).setImageResource(speakerRes)
        findViewById<TextView>(R.id.watch_call_voice_speaker_label).setText(if (speakerEnabled) R.string.watch_call_speaker else R.string.watch_call_earpiece)
        findViewById<TextView>(R.id.watch_call_camera_label).setText(if (cameraEnabled) R.string.watch_call_camera else R.string.watch_call_camera_on)
    }

    private fun updateTimer() {
        val elapsedSeconds = ((System.currentTimeMillis() - activeStartedAt) / 1000L).coerceAtLeast(0L)
        val time = String.format(Locale.US, "%02d:%02d", elapsedSeconds / 60L, elapsedSeconds % 60L)
        val title = if (voiceMode) R.string.watch_call_active_voice else R.string.watch_call_active_video
        findViewById<TextView>(R.id.watch_call_nav_subtitle).text = context.getString(title, time)
        findViewById<TextView>(R.id.watch_call_voice_status).text = context.getString(title, time)
    }
}
