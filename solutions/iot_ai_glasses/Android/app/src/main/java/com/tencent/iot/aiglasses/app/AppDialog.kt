package com.tencent.iot.aiglasses.app

sealed interface AppDialog {
    val id: String

    data object EndSession : AppDialog {
        override val id = "end"
    }

    data object LeaveSession : AppDialog {
        override val id = "leave"
    }

    data object DiscardConfirm : AppDialog {
        override val id = "discard"
    }

    data object Conflict : AppDialog {
        override val id = "conflict"
    }

    data object MeetingInfo : AppDialog {
        override val id = "meeting-info"
    }
}
