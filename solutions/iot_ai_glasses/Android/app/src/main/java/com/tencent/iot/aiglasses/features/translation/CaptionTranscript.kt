package com.tencent.iot.aiglasses.features.translation

import com.tencent.iot.aiglasses.components.attachTopScrollShadow
import android.animation.ValueAnimator
import android.content.Context
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.animation.doOnEnd
import androidx.core.view.isVisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon
import com.tencent.iot.aiglasses.models.TranscriptLine

class CaptionTranscript @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : FrameLayout(context, attrs) {

    data class Item(val index: Int, val line: TranscriptLine, val isLatest: Boolean)

    var bindCard: ((View, Item) -> Unit)? = null
    var createCard: ((Context) -> View) = { SentenceCard(it) }

    private val adapter = CardAdapter()
    private var follows = true
    private var userScrolling = false
    private var instantPin = true
    private var slotAnimator: ValueAnimator? = null
    private val nearBottom = context.dpInt(48f)
    private val slotHeight = context.dpInt(44f)

    private val list: RecyclerView = RecyclerView(context).apply {
        layoutManager = object : LinearLayoutManager(context) {
            override fun onLayoutCompleted(state: RecyclerView.State?) {
                super.onLayoutCompleted(state)
                if (follows && !userScrolling) post { pinToBottom(animated = !instantPin) }
            }
        }
        adapter = this@CaptionTranscript.adapter
        itemAnimator = null
        clipToPadding = false
        overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS
        isVerticalScrollBarEnabled = false
        contentDescription = "双语字幕"
        addItemDecoration(object : RecyclerView.ItemDecoration() {
            override fun getItemOffsets(outRect: android.graphics.Rect, view: View, parent: RecyclerView, state: RecyclerView.State) {
                if (parent.getChildAdapterPosition(view) > 0) outRect.top = context.dpInt(12f)
            }
        })
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING) userScrolling = true
                if (newState == RecyclerView.SCROLL_STATE_IDLE && userScrolling) {
                    userScrolling = false
                    if (distanceToBottom() <= nearBottom) scrollToLatest()
                }
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (!userScrolling) return
                val near = distanceToBottom() <= nearBottom
                if (follows && !near && dy < 0) setFollows(false)
                if (!follows && near && dy > 0) setFollows(true)
            }
        })
    }

    private val returnButton = TextView(context).apply {
        text = "回到最新 ↓"
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.caption_return_text))
        gravity = Gravity.CENTER
        val horizontal = context.dpInt(16f)
        setPadding(horizontal, 0, horizontal, 0)
        background = context.pressable(context.roundedDrawable(999f, R.color.caption_return_background, R.color.caption_return_border))
        isClickable = true
        isFocusable = true
        setOnClickListener { scrollToLatest() }
    }

    private val returnSlot = FrameLayout(context).apply {
        alpha = 0f
        visibility = GONE
        addView(returnButton, LayoutParams(LayoutParams.WRAP_CONTENT, context.dpInt(36f), Gravity.CENTER_HORIZONTAL or Gravity.TOP).apply {
            topMargin = context.dpInt(8f)
        })
    }

    private val emptyIcon = ImageView(context).apply { setAppIcon(AppIcon.MIC, R.color.accent) }
    private val emptyLabel = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        setTextColor(context.color(R.color.text_primary))
    }
    private val empty = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        addView(emptyIcon, LinearLayout.LayoutParams(context.dpInt(30f), context.dpInt(30f)))
        addView(emptyLabel, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = context.dpInt(12f)
        })
    }

    private val content = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        clipChildren = false
        addView(list, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        addView(returnSlot, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0))
    }

    init {
        addView(content, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(empty, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    fun attachTopShadow(host: View) = list.attachTopScrollShadow(host)

    fun set(entries: List<TranscriptLine>, isPaused: Boolean) {
        val wasEmpty = adapter.itemCount == 0
        content.isVisible = entries.isNotEmpty()
        empty.isVisible = entries.isEmpty()
        emptyLabel.text = if (isPaused) "已暂停收音" else "准备聆听"
        empty.contentDescription = emptyLabel.text
        if (wasEmpty && entries.isNotEmpty()) {
            instantPin = true
            resetFollow()
        }
        adapter.submitList(entries.mapIndexed { index, line -> Item(index, line.copy(), index == entries.lastIndex) })
    }

    private fun distanceToBottom(): Int {
        val last = adapter.itemCount - 1
        if (last < 0) return 0
        val view = list.layoutManager?.findViewByPosition(last) ?: return Int.MAX_VALUE
        return (view.bottom - (list.height - list.paddingBottom)).coerceAtLeast(0)
    }

    private fun pinToBottom(animated: Boolean) {
        val last = adapter.itemCount - 1
        if (last < 0 || list.height == 0) return
        val distance = distanceToBottom()
        when {
            distance == 0 -> instantPin = false
            distance == Int.MAX_VALUE -> if (animated) list.smoothScrollToPosition(last) else list.scrollToPosition(last)
            animated -> list.smoothScrollBy(0, distance)
            else -> {
                list.scrollBy(0, distance)
                instantPin = false
            }
        }
    }

    private fun scrollToLatest() {
        setFollows(true)
        pinToBottom(animated = true)
    }

    private fun resetFollow() {
        slotAnimator?.cancel()
        follows = true
        returnSlot.alpha = 0f
        returnSlot.visibility = GONE
        returnSlot.layoutParams = returnSlot.layoutParams.apply { height = 0 }
    }

    private fun setFollows(value: Boolean) {
        if (follows == value) return
        follows = value
        slotAnimator?.cancel()
        if (!value) returnSlot.visibility = VISIBLE
        slotAnimator = ValueAnimator.ofFloat(returnSlot.alpha, if (value) 0f else 1f).apply {
            duration = 180
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                val progress = it.animatedValue as Float
                returnSlot.alpha = progress
                returnSlot.layoutParams = returnSlot.layoutParams.apply { height = (slotHeight * progress).toInt() }
            }
            doOnEnd { if (follows) returnSlot.visibility = GONE }
            start()
        }
    }

    private inner class CardAdapter : ListAdapter<Item, RecyclerView.ViewHolder>(DIFF) {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            val card = createCard(parent.context)
            card.layoutParams = RecyclerView.LayoutParams(RecyclerView.LayoutParams.MATCH_PARENT, RecyclerView.LayoutParams.WRAP_CONTENT)
            return object : RecyclerView.ViewHolder(card) {}
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            val item = getItem(position)
            val bind = bindCard
            if (bind != null) bind(holder.itemView, item) else (holder.itemView as SentenceCard).set(item.index, item.line, item.isLatest)
        }
    }

    private companion object {
        val DIFF = object : DiffUtil.ItemCallback<Item>() {
            override fun areItemsTheSame(oldItem: Item, newItem: Item) = oldItem.line.id == newItem.line.id
            override fun areContentsTheSame(oldItem: Item, newItem: Item) = oldItem == newItem
        }
    }
}
