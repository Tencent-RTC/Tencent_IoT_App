package com.tencent.iot.aiglasses.features.call

import com.tencent.iot.aiglasses.components.attachTopScrollShadow
import android.content.Context
import android.os.Bundle
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.core.view.isVisible
import androidx.core.widget.doAfterTextChanged
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppDialog
import com.tencent.iot.aiglasses.app.AppRoute
import com.tencent.iot.aiglasses.app.RootActivity
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.databinding.FragmentCallJoinBinding
import com.tencent.iot.aiglasses.designsystem.surface
import com.tencent.iot.aiglasses.models.SessionKind
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.services.trtc.TRTCCredentials
import com.tencent.iot.aiglasses.state

class CallJoinFragment : Fragment(R.layout.fragment_call_join) {

    private var _binding: FragmentCallJoinBinding? = null
    private val prefs by lazy { requireContext().getSharedPreferences("suisheng", Context.MODE_PRIVATE) }

    private val roomId: String
        get() = _binding?.roomInput?.text?.toString()?.trim().orEmpty()
    private val userId: String
        get() = _binding?.userInput?.text?.toString()?.trim().orEmpty()

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentCallJoinBinding.bind(view)
        binding.scroll.attachTopScrollShadow(binding.root)
        _binding = binding
        binding.header.setOnBack { router.pop() }
        binding.fieldsCard.surface(radius = 22f)
        binding.roomInput.setText(prefs.getString(ROOM_KEY, ""))
        binding.userInput.setText(prefs.getString(USER_KEY, null) ?: TRTCCredentials.userId(requireContext()))
        binding.roomInput.doAfterTextChanged { render() }
        binding.userInput.doAfterTextChanged { render() }
        binding.userInput.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_GO) join()
            false
        }
        binding.connectButton.setOnClickListener { state.reconnect() }
        binding.joinButton.setOnClickListener { join() }
        observeState(::render)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private val blockedReason: String?
        get() = when {
            !TRTCCredentials.isConfigured -> "未配置 TRTC 凭证"
            !state.isOnline -> "网络未连接，请恢复后进房"
            !state.isConnected -> "请先连接眼镜"
            roomId.isEmpty() -> "请输入房间号"
            userId.isEmpty() -> "请输入用户 ID"
            else -> null
        }

    private fun join() {
        hideKeyboard()
        if (state.session?.kind == SessionKind.CALL) {
            router.push(AppRoute.Live(SessionKind.CALL))
            return
        }
        if (blockedReason != null) return
        if (state.session != null) {
            state.dialog = AppDialog.Conflict
            return
        }
        val room = roomId
        val user = userId
        prefs.edit().putString(ROOM_KEY, room).putString(USER_KEY, user).apply()
        (requireActivity() as RootActivity).withMicrophone {
            if (isAdded && state.startCall(room, user)) router.push(AppRoute.Live(SessionKind.CALL))
        }
    }

    private fun hideKeyboard() {
        val view = view ?: return
        view.findFocus()?.clearFocus()
        requireContext().getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(view.windowToken, 0)
    }

    private fun render() {
        val binding = _binding ?: return
        val inCall = state.session?.kind == SessionKind.CALL
        binding.connectedDot.isVisible = state.isConnected
        binding.connectButton.isVisible = !state.isConnected
        val reason = if (inCall) null else blockedReason
        binding.blockedReason.isVisible = reason != null
        binding.blockedReason.text = reason
        binding.joinButton.text = if (inCall) "返回通话" else "进入房间"
        binding.joinButton.isEnabled = inCall || reason == null
    }

    private companion object {
        const val ROOM_KEY = "callRoomId"
        const val USER_KEY = "callUserId"
    }
}
