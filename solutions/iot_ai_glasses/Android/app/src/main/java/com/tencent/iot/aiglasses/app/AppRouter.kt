package com.tencent.iot.aiglasses.app

import android.os.Bundle
import androidx.annotation.IdRes
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.features.shared.RouteDestination
import com.tencent.iot.aiglasses.models.SessionKind
import java.io.Serializable
import java.util.UUID

enum class AppTab(val title: String, val icon: AppIcon) {
    HOME("首页", AppIcon.HOME),
    RECORDS("记录", AppIcon.RECORDS),
    DEVICE("设备", AppIcon.GLASSES)
}

sealed interface AppRoute : Serializable {
    data object InterpretPrep : AppRoute
    data object Calls : AppRoute
    data object Chat : AppRoute
    data class Live(val kind: SessionKind) : AppRoute
    data class RecordDetail(val id: UUID) : AppRoute
}

class AppRouter(private val fragmentManager: FragmentManager, @IdRes private val containerId: Int, private val state: AppState) {
    var selectedTab: AppTab = AppTab.HOME
        private set

    var onChange: (() -> Unit)? = null

    private val stacks: Map<AppTab, ArrayList<String>> = AppTab.entries.associateWith { ArrayList() }
    private var nextId = 0

    val showsTabBar: Boolean
        get() = stack(selectedTab).size <= 1

    val canPop: Boolean
        get() = stack(selectedTab).size > 1

    fun restore(state: Bundle?) {
        if (state == null) {
            fragmentManager.commitNow {
                setReorderingAllowed(true)
                AppTab.entries.forEach { tab ->
                    val tag = "tab-${tab.name}"
                    val fragment = RouteDestination.root(tab)
                    add(containerId, fragment, tag)
                    if (tab != selectedTab) hide(fragment)
                    stack(tab).add(tag)
                }
            }
        } else {
            selectedTab = AppTab.valueOf(state.getString(KEY_TAB) ?: AppTab.HOME.name)
            nextId = state.getInt(KEY_NEXT_ID)
            AppTab.entries.forEach { tab ->
                stack(tab).addAll(state.getStringArrayList(KEY_STACK + tab.name).orEmpty())
            }
        }
        onChange?.invoke()
    }

    fun save(out: Bundle) {
        out.putString(KEY_TAB, selectedTab.name)
        out.putInt(KEY_NEXT_ID, nextId)
        AppTab.entries.forEach { tab -> out.putStringArrayList(KEY_STACK + tab.name, ArrayList(stack(tab))) }
    }

    fun select(tab: AppTab) {
        if (tab == selectedTab) {
            popToRoot(tab)
            return
        }
        fragmentManager.commitNow {
            hide(fragment(stack(selectedTab).last()))
            show(fragment(stack(tab).last()))
        }
        selectedTab = tab
        onChange?.invoke()
    }

    fun push(route: AppRoute, animated: Boolean = true) {
        val stack = stack(selectedTab)
        val tag = "route-${nextId++}"
        fragmentManager.commitNow {
            setReorderingAllowed(true)
            if (animated) setCustomAnimations(R.anim.push_enter, R.anim.push_exit)
            hide(fragment(stack.last()))
            add(containerId, RouteDestination.create(route, state), tag)
        }
        stack.add(tag)
        onChange?.invoke()
    }

    fun replaceTop(route: AppRoute) {
        pop()
        push(route)
    }

    fun pop() {
        val stack = stack(selectedTab)
        if (stack.size <= 1) return
        val tag = stack.removeAt(stack.lastIndex)
        fragmentManager.commitNow {
            setReorderingAllowed(true)
            setCustomAnimations(R.anim.pop_enter, R.anim.pop_exit)
            remove(fragment(tag))
            show(fragment(stack.last()))
        }
        onChange?.invoke()
    }

    fun popToRoot() = popToRoot(selectedTab)

    fun popToRoot(tab: AppTab) {
        val stack = stack(tab)
        if (stack.size <= 1) return
        val removed = stack.subList(1, stack.size).toList()
        stack.subList(1, stack.size).clear()
        fragmentManager.commitNow {
            setReorderingAllowed(true)
            removed.forEach { remove(fragment(it)) }
            if (tab == selectedTab) show(fragment(stack.first()))
        }
        onChange?.invoke()
    }

    private fun stack(tab: AppTab): ArrayList<String> = stacks.getValue(tab)

    private fun fragment(tag: String): Fragment =
        requireNotNull(fragmentManager.findFragmentByTag(tag)) { "Missing fragment $tag" }

    private companion object {
        const val KEY_TAB = "router.tab"
        const val KEY_NEXT_ID = "router.nextId"
        const val KEY_STACK = "router.stack."
    }
}

val Fragment.router: AppRouter
    get() = (requireActivity() as RootActivity).router

fun Fragment.startCapture(kind: SessionKind) {
    val activity = requireActivity() as RootActivity
    activity.withMicrophone {
        if (activity.state.startSession(kind)) activity.router.replaceTop(AppRoute.Live(kind))
    }
}
