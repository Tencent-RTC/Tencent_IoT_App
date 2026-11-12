package com.tencent.iot.aiglasses

import android.app.Application
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.tencent.iot.aiglasses.app.AppState
import com.tencent.iot.aiglasses.app.AppTheme
import kotlinx.coroutines.launch

class IoTAIGlassesApp : Application() {
    lateinit var state: AppState
        private set

    override fun onCreate() {
        super.onCreate()
        AppTheme.applySaved(this)
        state = AppState(this)
    }
}

val Fragment.state: AppState
    get() = (requireActivity().application as IoTAIGlassesApp).state

fun LifecycleOwner.observe(state: AppState, render: () -> Unit) {
    lifecycleScope.launch {
        repeatOnLifecycle(Lifecycle.State.STARTED) {
            state.changes.collect { render() }
        }
    }
}

fun Fragment.observeState(render: () -> Unit) = viewLifecycleOwner.observe(state, render)
