package com.tencent.iot.aiglasses.components

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.StyleRes
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppDialog
import com.tencent.iot.aiglasses.app.AppRoute
import com.tencent.iot.aiglasses.app.AppRouter
import com.tencent.iot.aiglasses.app.AppState
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.models.CaptionEngine
import com.tencent.iot.aiglasses.models.Clock
import com.tencent.iot.aiglasses.models.SessionKind

class DialogHost @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : FrameLayout(context, attrs) {

    private lateinit var state: AppState
    private lateinit var router: AppRouter
    private var shownId: String? = null
    private var refresh: (() -> Unit)? = null

    private val scrim = View(context).apply {
        setBackgroundColor(context.color(R.color.scrim))
        contentDescription = "关闭"
        setOnClickListener { state.dialog = null }
    }

    private val sheet = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        val padding = context.dpInt(24f)
        setPadding(padding, padding, padding, padding)
        background = context.roundedDrawable(if (context.isDarkTheme) 24f else 28f, R.color.sheet, R.color.sheet_border)
        if (!context.isDarkTheme) {
            elevation = context.dp(16f)
            outlineSpotShadowColor = context.color(R.color.toast_shadow)
            outlineAmbientShadowColor = context.color(R.color.toast_shadow)
        }
        isClickable = true
        accessibilityPaneTitle = "对话框"
    }

    init {
        translationZ = context.dp(40f)
        addView(scrim, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        val margin = context.dpInt(12f)
        addView(sheet, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM).apply {
            setMargins(margin, margin, margin, margin)
        })
    }

    fun bind(state: AppState, router: AppRouter) {
        this.state = state
        this.router = router
    }

    fun render(dialog: AppDialog?) {
        if (dialog?.id == shownId) {
            refresh?.invoke()
            return
        }
        shownId = dialog?.id
        refresh = null
        if (dialog == null) {
            scrim.animate().alpha(0f).setDuration(200).start()
            sheet.animate().translationY(sheet.height.toFloat() + context.dp(24f)).setDuration(240)
                .withEndAction { visibility = GONE }.start()
            return
        }
        sheet.removeAllViews()
        content(dialog)
        visibility = VISIBLE
        scrim.alpha = 0f
        scrim.animate().alpha(1f).setDuration(200).start()
        sheet.translationY = context.dp(320f)
        sheet.animate().translationY(0f).setDuration(280).withEndAction(null).start()
        sheet.post { sheet.sendAccessibilityEvent(android.view.accessibility.AccessibilityEvent.TYPE_VIEW_FOCUSED) }
    }

    private fun content(dialog: AppDialog) {
        when (dialog) {
            AppDialog.EndSession -> endSession()
            AppDialog.LeaveSession -> endSession(leaving = true)
            AppDialog.DiscardConfirm -> discardConfirm()
            AppDialog.MeetingInfo -> meetingInfo()
            AppDialog.Conflict -> sheetBody(
                title = "已有任务进行中",
                messages = listOf("翻译、同传、会议与通话不能同时使用眼镜麦克风。请返回当前任务，或先结束并保存。")
            ) {
                action("返回当前任务", R.style.Widget_Suisheng_Button_Primary_Sheet) {
                    state.dialog = null
                    state.session?.kind?.let { router.push(AppRoute.Live(it)) }
                }
                action("留在当前页面", R.style.Widget_Suisheng_Button_Sheet) { state.dialog = null }
            }
        }
    }

    private fun endSession(leaving: Boolean = false) {
        val kind = state.session?.kind ?: SessionKind.TRANSLATION
        val saves = kind == SessionKind.MEETING || state.session?.savesText == true
        sheetBody(
            title = when (kind) {
                SessionKind.MEETING -> "结束这场会议？"
                SessionKind.INTERPRET -> "结束本次同传？"
                else -> "结束本次翻译？"
            },
            messages = listOf("将停止音频采集。" + if (saves) "已确认的内容会保存到记录。" else "当前未开启保存文字。")
        ) {
            val finish = {
                val record = state.finishSession()
                if (record != null) router.replaceTop(AppRoute.RecordDetail(record.id)) else router.popToRoot()
            }
            val discard = { state.dialog = AppDialog.DiscardConfirm }
            if (leaving) {
                action(if (saves) "结束并保存" else "结束，不保存", R.style.Widget_Suisheng_Button_Primary_Sheet) { finish() }
                action("不结束，仅返回", R.style.Widget_Suisheng_Button_Sheet) {
                    state.dialog = null
                    router.popToRoot()
                }
            } else if (saves) {
                action("结束并保存", R.style.Widget_Suisheng_Button_Primary_Sheet) { finish() }
                action("不保存直接结束", R.style.Widget_Suisheng_Button_Sheet) { discard() }
            } else {
                action("不保存直接结束", R.style.Widget_Suisheng_Button_Primary_Sheet) { discard() }
            }
        }
    }

    private fun discardConfirm() {
        val session = state.session
        val count = session?.entries?.size ?: 0
        val what = if (session?.kind == SessionKind.MEETING) "会议" else "翻译"
        sheetBody(
            title = "确定不保存？",
            messages = listOf("本次$what" + (if (count > 0) "已有 $count 段内容，" else "") + "结束后将直接丢弃，无法恢复。")
        ) {
            action("确认不保存", R.style.Widget_Suisheng_Button_Danger_Sheet) {
                state.discardSession()
                router.popToRoot()
            }
            action("返回", R.style.Widget_Suisheng_Button_Sheet) { state.dialog = AppDialog.EndSession }
        }
    }

    private fun meetingInfo() {
        val session = state.session
        val messages = if (session == null) {
            listOf("当前没有进行中的会议")
        } else {
            listOf(
                "会议名称：" + session.title.ifEmpty { "未命名会议" },
                "会议语言：中文",
                "已进行 ${Clock.text(session.seconds)} · 已转 ${session.entries.size} 段",
                if (session.keepsAudio) "结束后保存录音与文字" else "结束后仅保存文字"
            )
        }
        sheetBody("会议信息", messages) {
            action("知道了", R.style.Widget_Suisheng_Button_Primary_Sheet) { state.dialog = null }
        }
    }

    private fun sheetBody(title: String, messages: List<String>, extra: (LinearLayout.() -> Unit)? = null, actions: LinearLayout.() -> Unit) {
        sheet.addView(TextView(context).apply {
            setTextAppearance(R.style.TextAppearance_Suisheng_SheetTitle)
            text = title
            isAccessibilityHeading = true
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = context.dpInt(12f)
        })
        messages.forEachIndexed { index, message ->
            sheet.addView(TextView(context).apply {
                setTextAppearance(R.style.TextAppearance_Suisheng_Footnote)
                setTextColor(context.color(R.color.text_secondary))
                setLineSpacing(context.dp(4f), 1f)
                text = message
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                if (index > 0) topMargin = context.dpInt(10f)
            })
        }
        extra?.invoke(sheet)
        val actionsColumn = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        actionsColumn.actions()
        sheet.addView(actionsColumn, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = context.dpInt(24f)
        })
    }

    private fun LinearLayout.action(title: String, @StyleRes style: Int, onClick: () -> Unit): Button {
        val button = Button(context, null, 0, style).apply {
            text = title
            setOnClickListener { onClick() }
        }
        addView(button, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            if (childCount > 0) topMargin = context.dpInt(9f)
        })
        return button
    }
}
