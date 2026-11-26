package com.tencent.iot.watchapp.watch
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity
import com.tencent.iot.watchapp.im.ImService

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.PagerSnapHelper
import androidx.recyclerview.widget.RecyclerView

/** 设备页：按最新设计稿展示真实绑定手表，并支持横向分页。 */
class DevicesView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : LinearLayout(context, attrs, defStyleAttr) {
    private val bindings = WatchBindingStore.all(context, ImService.loggedInUserId)
    private var selectedIndex = 0
    private val carousel: RecyclerView
    private val pager: LinearLayout
    private val pagerDots: LinearLayout
    private val emptyState: View
    private val managementGroup: View
    private val settingsGroup: View
    private val snapHelper = PagerSnapHelper()

    init {
        orientation = VERTICAL
        LayoutInflater.from(context).inflate(R.layout.watch_devices_view, this, true)
        findViewById<View>(R.id.watch_devices_add).setOnClickListener {
            (context as? MainActivity)?.showWatchScanner(returnToDevices = true)
        }
        carousel = findViewById(R.id.watch_devices_carousel)
        pager = findViewById(R.id.watch_devices_pager)
        pagerDots = findViewById(R.id.watch_devices_pager_dots)
        emptyState = findViewById(R.id.watch_devices_empty)
        managementGroup = findViewById(R.id.watch_devices_management_group)
        settingsGroup = findViewById(R.id.watch_devices_settings_group)
        configureCarousel()
        renderSelection()
    }

    private fun configureCarousel() {
        carousel.layoutManager = LinearLayoutManager(context, RecyclerView.HORIZONTAL, false)
        carousel.adapter = WatchDeviceAdapter(bindings)
        snapHelper.attachToRecyclerView(carousel)
        carousel.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                if (newState != RecyclerView.SCROLL_STATE_IDLE) return
                val snapped = snapHelper.findSnapView(recyclerView.layoutManager) ?: return
                val index = recyclerView.getChildAdapterPosition(snapped)
                if (index != RecyclerView.NO_POSITION && index != selectedIndex) {
                    selectedIndex = index
                    renderSelection()
                }
            }
        })
        carousel.isNestedScrollingEnabled = false
        val hasBindings = bindings.isNotEmpty()
        emptyState.visibility = if (hasBindings) View.GONE else View.VISIBLE
        carousel.visibility = if (hasBindings) View.VISIBLE else View.GONE
        pager.visibility = if (hasBindings) View.VISIBLE else View.GONE
        managementGroup.visibility = if (hasBindings) View.VISIBLE else View.GONE
        settingsGroup.visibility = if (hasBindings) View.VISIBLE else View.GONE
    }

    private fun renderSelection() {
        val total = bindings.size
        selectedIndex = selectedIndex.coerceIn(0, (total - 1).coerceAtLeast(0))
        renderPager()
    }

    private fun renderPager() {
        pagerDots.removeAllViews()
        bindings.indices.forEach { index ->
            val hitTarget = FrameLayout(context).apply {
                contentDescription = context.getString(
                    R.string.watch_device_page_description_current,
                    index + 1,
                    bindings[index].deviceName,
                )
                isClickable = true
                setOnClickListener {
                    selectedIndex = index
                    carousel.smoothScrollToPosition(index)
                    renderSelection()
                }
            }
            val dotWidth = if (index == selectedIndex) 20 else 6
            val dot = View(context).apply {
                translationY = 6.dp().toFloat()
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = resources.displayMetrics.density * 4
                    setColor(ContextCompat.getColor(context, if (index == selectedIndex) R.color.watch_trust_blue else R.color.watch_text_tertiary))
                }
            }
            hitTarget.addView(dot, LinearLayout.LayoutParams(dotWidth.dp(), 6.dp()).apply {
                gravity = android.view.Gravity.CENTER
            })
            pagerDots.addView(hitTarget, LinearLayout.LayoutParams(32.dp(), 24.dp()))
        }
    }

    private fun Int.dp(): Int = (this * resources.displayMetrics.density).toInt()

    private class WatchDeviceAdapter(
        private val items: List<BoundWatch>,
    ) : RecyclerView.Adapter<WatchDeviceAdapter.Holder>() {
        override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): Holder {
            val card = LayoutInflater.from(parent.context).inflate(R.layout.watch_device_bound_card, parent, false)
            return Holder(card)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val binding = items[position]
            val isGirl = WatchAvatarResolver.resourceFor(binding.deviceName) == R.drawable.watch_avatar_xiaoya_card_design
            holder.itemView.background = ContextCompat.getDrawable(
                holder.itemView.context,
                if (isGirl) R.drawable.watch_device_card_girl else R.drawable.watch_device_card_boy,
            )
            holder.name.text = binding.deviceName
            holder.avatar.contentDescription = binding.deviceName
            holder.avatar.setImageResource(WatchAvatarResolver.resourceFor(binding.deviceName))
        }

        override fun getItemCount(): Int = items.size

        private class Holder(itemView: View) : RecyclerView.ViewHolder(itemView) {
            val name: TextView = itemView.findViewById(R.id.watch_device_bound_name)
            val avatar: android.widget.ImageView = itemView.findViewById(R.id.watch_device_bound_avatar)
        }
    }
}
