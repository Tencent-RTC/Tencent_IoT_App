package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.watch.WatchAvatarResolver

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.widget.CheckBox
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

class GroupMemberPickerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    private val list: LinearLayout
    private val selectedLabel: TextView
    private val done: TextView
    private val selected = linkedMapOf<String, WatchImGroupCandidate>()
    private var candidates = emptyList<WatchImGroupCandidate>()
    private var defaultSelectedUserIds = emptySet<String>()
    private var doneAction: ((List<WatchImGroupCandidate>) -> Unit)? = null
    private var backAction: (() -> Unit)? = null

    init {
        LayoutInflater.from(context).inflate(R.layout.watch_group_member_picker, this, true)
        list = findViewById(R.id.watch_group_picker_list)
        selectedLabel = findViewById(R.id.watch_group_picker_selected)
        done = findViewById(R.id.watch_group_picker_done)
        findViewById<View>(R.id.watch_group_picker_back).setOnClickListener { backAction?.invoke() }
        done.setOnClickListener {
            if (selected.isEmpty()) {
                Toast.makeText(context, R.string.watch_group_member_picker_empty, Toast.LENGTH_SHORT).show()
            } else {
                doneAction?.invoke(selected.values.toList())
            }
        }
    }

    fun setCallbacks(onBack: () -> Unit, onDone: (List<WatchImGroupCandidate>) -> Unit) {
        this.backAction = onBack
        this.doneAction = onDone
    }

    fun setDefaultSelectedUserIds(userIds: Set<String>) {
        defaultSelectedUserIds = userIds.filter { it.isNotBlank() }.toSet()
    }

    fun showLoading() {
        list.removeAllViews()
        list.addView(TextView(context).apply {
            text = getContext().getString(R.string.watch_login_loading)
            setPadding(dp(16), dp(24), dp(16), dp(24))
            setTextColor(context.getColor(R.color.watch_text_secondary))
        })
    }

    fun render(candidates: List<WatchImGroupCandidate>) {
        val knownIds = candidates.map { it.userId }.toSet()
        val missingDefaultSelected = defaultSelectedUserIds.filterNot { it in knownIds }.map { userId ->
            WatchImGroupCandidate(
                userId = userId,
                displayName = userId,
                avatarRes = WatchAvatarResolver.resourceFor(userId),
                isWatch = userId != ImService.loggedInUserId,
                isCurrentUser = userId == ImService.loggedInUserId,
            )
        }
        this.candidates = (candidates + missingDefaultSelected).distinctBy { it.userId }
        selected.clear()
        this.candidates.filter { it.userId in defaultSelectedUserIds }.forEach { selected[it.userId] = it }
        list.removeAllViews()
        if (this.candidates.isEmpty()) {
            list.addView(TextView(context).apply {
                text = getContext().getString(R.string.watch_group_member_picker_empty)
                setPadding(dp(16), dp(24), dp(16), dp(24))
                setTextColor(context.getColor(R.color.watch_text_secondary))
            })
        } else {
            this.candidates.forEachIndexed { index, candidate ->
                list.addView(createRow(candidate))
                if (index != this.candidates.lastIndex) {
                    list.addView(View(context).apply {
                        setBackgroundColor(context.getColor(R.color.watch_line))
                        layoutParams = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(1))
                    })
                }
            }
        }
        updateSelectionLabel()
    }

    private fun createRow(candidate: WatchImGroupCandidate): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            minimumHeight = dp(64)
            setPadding(dp(14), dp(8), dp(10), dp(8))
        }
        val avatar = ImageView(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
            setImageResource(candidate.avatarRes)
            contentDescription = candidate.displayName
        }
        val name = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(12) }
            text = candidate.displayName
            setTextColor(context.getColor(R.color.watch_text_primary))
            textSize = 15f
        }
        val checkbox = CheckBox(context).apply {
            isChecked = selected.containsKey(candidate.userId)
            contentDescription = candidate.displayName
            setOnClickListener { toggle(candidate, this) }
        }
        row.addView(avatar)
        row.addView(name)
        row.addView(checkbox)
        row.setOnClickListener { toggle(candidate, checkbox) }
        return row
    }

    private fun toggle(candidate: WatchImGroupCandidate, checkbox: CheckBox) {
        if (selected.remove(candidate.userId) == null) selected[candidate.userId] = candidate
        checkbox.isChecked = selected.containsKey(candidate.userId)
        updateSelectionLabel()
    }

    private fun updateSelectionLabel() {
        selectedLabel.text = context.getString(R.string.watch_group_member_picker_selected, selected.size)
        done.isEnabled = selected.isNotEmpty()
        done.alpha = if (selected.isEmpty()) 0.45f else 1f
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
