package com.tencent.iot.aiglasses.app

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import android.graphics.Color
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import com.tencent.iot.aiglasses.IoTAIGlassesApp
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.databinding.ActivityRootBinding
import com.tencent.iot.aiglasses.designsystem.GlassBackdropDrawable
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.pageBackground
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.observe
import java.util.UUID

class RootActivity : AppCompatActivity() {
    lateinit var router: AppRouter
        private set

    val state: AppState
        get() = (application as IoTAIGlassesApp).state

    private lateinit var binding: ActivityRootBinding
    private var shownToast: UUID? = null
    private var imeVisible = false
    private var pendingMicrophoneAction: (() -> Unit)? = null

    private val microphonePermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val action = pendingMicrophoneAction
        pendingMicrophoneAction = null
        if (granted) action?.invoke() else state.showToast("需要麦克风权限才能通过眼镜收音")
    }

    private val backCallback = object : OnBackPressedCallback(false) {
        override fun handleOnBackPressed() {
            when {
                state.dialog != null -> state.dialog = null
                else -> router.pop()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRootBinding.inflate(layoutInflater)
        setContentView(binding.root)
        val barColor = if (isDarkTheme) color(R.color.background) else Color.TRANSPARENT
        window.statusBarColor = barColor
        window.navigationBarColor = barColor
        if (!isDarkTheme) applyGlassBackdrop()

        router = AppRouter(supportFragmentManager, R.id.content, state)
        router.onChange = ::render
        binding.tabBar.onSelect = router::select
        binding.dialogHost.bind(state, router)
        onBackPressedDispatcher.addCallback(this, backCallback)
        router.restore(savedInstanceState)
        val frame = Rect()
        window.decorView.viewTreeObserver.addOnGlobalLayoutListener {
            window.decorView.getWindowVisibleDisplayFrame(frame)
            val visible = window.decorView.height - frame.bottom > dpInt(150f)
            if (visible != imeVisible) {
                imeVisible = visible
                render()
            }
        }
        observe(state, ::render)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        router.save(outState)
    }

    private fun applyGlassBackdrop() {
        val backdrop = GlassBackdropDrawable()
        window.setBackgroundDrawable(backdrop)
        window.isNavigationBarContrastEnforced = false
        binding.root.background = pageBackground()
        val location = IntArray(2)
        binding.root.addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
            view.getLocationInWindow(location)
            backdrop.setInsets(location[1], window.decorView.height - location[1] - view.height)
        }
    }

    fun withMicrophone(action: () -> Unit) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            action()
            return
        }
        pendingMicrophoneAction = action
        microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
    }

    private fun render() {
        binding.tabBar.selection = router.selectedTab
        binding.tabBar.isVisible = router.showsTabBar && !imeVisible
        backCallback.isEnabled = router.canPop || state.dialog != null
        binding.dialogHost.render(state.dialog)
        renderToast()
    }

    private fun renderToast() {
        val toast = state.toast
        binding.toast.updateLayoutParams<android.widget.FrameLayout.LayoutParams> {
            bottomMargin = dpInt(if (router.showsTabBar) 84f else 150f)
        }
        if (toast == null) {
            if (shownToast != null) {
                shownToast = null
                binding.toast.animate().alpha(0f).translationY(dpInt(12f).toFloat()).setDuration(200)
                    .withEndAction { binding.toast.visibility = View.GONE }.start()
            }
            return
        }
        if (toast.id == shownToast) return
        shownToast = toast.id
        binding.toast.text = toast.text
        binding.toast.announceForAccessibility(toast.text)
        if (binding.toast.visibility != View.VISIBLE) {
            binding.toast.alpha = 0f
            binding.toast.translationY = dpInt(12f).toFloat()
            binding.toast.visibility = View.VISIBLE
        }
        binding.toast.animate().alpha(1f).translationY(0f).setDuration(200).withEndAction(null).start()
    }
}
