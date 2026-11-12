package com.tencent.iot.aiglasses.features.shared

import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.app.AppRoute
import com.tencent.iot.aiglasses.app.AppState
import com.tencent.iot.aiglasses.app.AppTab
import com.tencent.iot.aiglasses.features.call.CallJoinFragment
import com.tencent.iot.aiglasses.features.call.CallLiveFragment
import com.tencent.iot.aiglasses.features.chat.ChatFragment
import com.tencent.iot.aiglasses.features.device.DeviceFragment
import com.tencent.iot.aiglasses.features.home.HomeFragment
import com.tencent.iot.aiglasses.features.meeting.MeetingDetailFragment
import com.tencent.iot.aiglasses.features.meeting.MeetingLiveFragment
import com.tencent.iot.aiglasses.features.records.RecordsFragment
import com.tencent.iot.aiglasses.features.records.TranslationDetailFragment
import com.tencent.iot.aiglasses.features.translation.InterpretLiveFragment
import com.tencent.iot.aiglasses.features.translation.InterpretPrepFragment
import com.tencent.iot.aiglasses.features.translation.TranslationLiveFragment
import com.tencent.iot.aiglasses.models.RecordKind
import com.tencent.iot.aiglasses.models.SessionKind

object RouteDestination {
    fun root(tab: AppTab): Fragment = when (tab) {
        AppTab.HOME -> HomeFragment()
        AppTab.RECORDS -> RecordsFragment()
        AppTab.DEVICE -> DeviceFragment()
    }

    fun create(route: AppRoute, state: AppState): Fragment = when (route) {
        AppRoute.InterpretPrep -> InterpretPrepFragment()
        AppRoute.Calls -> CallJoinFragment()
        AppRoute.Chat -> ChatFragment()
        is AppRoute.Live -> when (route.kind) {
            SessionKind.TRANSLATION -> TranslationLiveFragment()
            SessionKind.INTERPRET -> InterpretLiveFragment()
            SessionKind.MEETING -> MeetingLiveFragment()
            SessionKind.CALL -> CallLiveFragment()
        }
        is AppRoute.RecordDetail -> if (state.records.firstOrNull { it.id == route.id }?.kind == RecordKind.MEETING) {
            MeetingDetailFragment.newInstance(route.id)
        } else {
            TranslationDetailFragment.newInstance(route.id)
        }
    }
}
