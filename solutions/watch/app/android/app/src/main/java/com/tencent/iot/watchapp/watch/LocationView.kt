package com.tencent.iot.watchapp.watch
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.im.ImService

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.PagerSnapHelper
import androidx.recyclerview.widget.RecyclerView

/** 定位页：设备身份来自当前账号的真实绑定；定位遥测未接入时不伪造位置和电量。 */
class LocationView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : LinearLayout(context, attrs, defStyleAttr) {
    private val bindings = WatchBindingStore.all(context, ImService.loggedInUserId)
    private var selectedIndex = 0
    private lateinit var carousel: RecyclerView
    private lateinit var pager: LinearLayout
    private lateinit var countLabel: TextView
    private lateinit var marker: ImageView
    private val snapHelper = PagerSnapHelper()

    init {
        orientation = VERTICAL
        LayoutInflater.from(context).inflate(R.layout.watch_location_view, this, true)
        carousel = findViewById(R.id.watch_location_carousel)
        pager = findViewById(R.id.watch_location_pager)
        countLabel = findViewById(R.id.watch_location_count)
        marker = findViewById(R.id.watch_location_marker)
        configureCarousel()
        renderSelection()
    }

    private fun configureCarousel() {
        carousel.layoutManager = LinearLayoutManager(context, RecyclerView.HORIZONTAL, false)
        carousel.adapter = LocationAdapter(bindings)
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
        carousel.visibility = if (bindings.isEmpty()) View.GONE else View.VISIBLE
        findViewById<View>(R.id.watch_location_empty).visibility = if (bindings.isEmpty()) View.VISIBLE else View.GONE
        pager.visibility = if (bindings.size < 2) View.GONE else View.VISIBLE
    }

    private fun renderSelection() {
        val total = bindings.size
        selectedIndex = selectedIndex.coerceIn(0, (total - 1).coerceAtLeast(0))
        countLabel.text = context.getString(R.string.watch_device_count_format, if (total == 0) 0 else selectedIndex + 1, total)
        val selected = bindings.getOrNull(selectedIndex)
        marker.setImageResource(WatchAvatarResolver.resourceForOrDefault(selected?.deviceName.orEmpty()))
        renderPager()
    }

    private fun renderPager() {
        pager.removeAllViews()
        bindings.indices.forEach { index ->
            val dot = View(context)
            dot.setBackgroundResource(if (index == selectedIndex) R.drawable.watch_avatar_blue else R.drawable.watch_avatar_mint)
            dot.contentDescription = context.getString(R.string.watch_device_page_description, index + 1, bindings.size, bindings[index].deviceName)
            dot.setOnClickListener {
                selectedIndex = index
                carousel.smoothScrollToPosition(index)
                renderSelection()
            }
            pager.addView(dot, LinearLayout.LayoutParams(if (index == selectedIndex) dp(20) else dp(6), dp(6)).apply {
                marginStart = dp(3)
                marginEnd = dp(3)
            })
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private class LocationAdapter(private val items: List<BoundWatch>) : RecyclerView.Adapter<LocationAdapter.Holder>() {
        override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): Holder {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.watch_location_bound_card, parent, false)
            view.layoutParams = RecyclerView.LayoutParams(parent.measuredWidth.takeIf { it > 0 } ?: RecyclerView.LayoutParams.MATCH_PARENT, RecyclerView.LayoutParams.WRAP_CONTENT)
            return Holder(view)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val binding = items[position]
            holder.avatar.setImageResource(WatchAvatarResolver.resourceFor(binding.deviceName))
            holder.avatar.contentDescription = binding.deviceName
            holder.name.text = binding.deviceName
            holder.status.setText(R.string.watch_location_no_data)
            holder.address.setText(R.string.watch_location_no_data)
            holder.updated.setText(R.string.watch_location_no_data)
        }

        override fun getItemCount(): Int = items.size

        private class Holder(view: View) : RecyclerView.ViewHolder(view) {
            val avatar: ImageView = view.findViewById(R.id.watch_location_card_avatar)
            val name: TextView = view.findViewById(R.id.watch_location_card_name)
            val status: TextView = view.findViewById(R.id.watch_location_card_status)
            val address: TextView = view.findViewById(R.id.watch_location_card_address)
            val updated: TextView = view.findViewById(R.id.watch_location_card_updated)
        }
    }
}
