package com.tencent.iot.watchapp.app

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AppSessionViewModel : ViewModel() {
    private val _screen = MutableStateFlow(AppScreen.LOGIN)
    val screen: StateFlow<AppScreen> = _screen.asStateFlow()

    fun onLoginSucceeded() {
        _screen.value = AppScreen.MESSAGES
    }

    fun onLogout() {
        _screen.value = AppScreen.LOGIN
    }

    fun select(screen: AppScreen) {
        if (screen != AppScreen.LOGIN) {
            _screen.value = screen
        }
    }

}
