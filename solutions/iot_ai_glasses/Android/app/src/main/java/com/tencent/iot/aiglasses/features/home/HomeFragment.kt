package com.tencent.iot.aiglasses.features.home

import android.content.Context
import android.graphics.Typeface
import android.os.Bundle
import android.text.TextUtils
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppDialog
import com.tencent.iot.aiglasses.app.AppRoute
import com.tencent.iot.aiglasses.app.AppTab
import com.tencent.iot.aiglasses.app.AppTheme
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.app.startCapture
import com.tencent.iot.aiglasses.databinding.FragmentHomeBinding
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.Elevation
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.elevation
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon
import com.tencent.iot.aiglasses.models.Record
import com.tencent.iot.aiglasses.models.SessionKind
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state

class HomeFragment : Fragment(R.layout.fragment_home) {

    private var _binding: FragmentHomeBinding? = null
    private val binding get() = _binding!!

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        _binding = FragmentHomeBinding.bind(view)
        val context = requireContext()
        val theme = AppTheme.current(context)
        binding.themeToggle.setIcon(if (theme == AppTheme.DARK) AppIcon.SUN else AppIcon.MOON)
        binding.themeToggle.contentDescription = if (theme == AppTheme.DARK) "切换到浅色主题" else "切换到深色主题"
        binding.themeToggle.setOnClickListener { AppTheme.save(context, theme.toggled) }

        binding.hero.setOnClickListener { router.select(AppTab.DEVICE) }
        binding.hero.contentDescription = "打开我的眼镜"
        binding.banner.setOnClickListener { state.session?.let { router.push(AppRoute.Live(it.kind)) } }

        val heavy = Typeface.create(Typeface.DEFAULT, if (context.isDarkTheme) 500 else 600, false)
        binding.featuresTitle.typeface = heavy
        binding.recentTitle.typeface = heavy
        buildFeatures()

        binding.recentAll.setOnClickListener { router.select(AppTab.RECORDS) }

        observeState(::render)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun buildFeatures() {
        val context = requireContext()
        val compact = resources.configuration.screenWidthDp - 44 < 347
        fun row(container: LinearLayout, features: List<Feature>, spacing: Float) {
            features.forEachIndexed { index, feature ->
                val card = FeatureCard(context, feature, compact)
                card.setOnClickListener { open(feature) }
                container.addView(card, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    if (index > 0) marginStart = context.dpInt(spacing)
                })
            }
        }
        row(binding.primaryRow, listOf(Feature.LISTEN, Feature.MEETING), if (compact) 10f else 12f)
        row(binding.secondaryRow, listOf(Feature.CALL, Feature.CHAT), if (compact) 10f else 12f)
    }

    private fun open(feature: Feature) {
        val kind = feature.sessionKind
        val session = state.session
        if (kind != null && session != null) {
            if (session.kind == kind) {
                router.push(AppRoute.Live(kind))
            } else {
                state.dialog = AppDialog.Conflict
            }
            return
        }
        if (feature == Feature.MEETING || feature == Feature.LISTEN) {
            val blocker = state.captureBlocker
            if (blocker != null) {
                state.showToast(blocker)
            } else {
                startCapture(if (feature == Feature.MEETING) SessionKind.MEETING else SessionKind.TRANSLATION)
            }
            return
        }
        router.push(feature.route)
    }

    private fun render() {
        val binding = _binding ?: return
        binding.hero.set(state.isConnected, state.batteryLevel)
        val session = state.session
        binding.banner.isVisible = session != null
        session?.let { binding.banner.set(state.sessionStatus(it), it.seconds) }
        renderRecent()
    }

    private fun renderRecent() {
        val binding = _binding ?: return
        val records = state.records
        binding.recentAll.text = "共 ${records.size} 条 · 全部"
        binding.recentAll.isVisible = records.isNotEmpty()
        binding.recentEmpty.isVisible = records.isEmpty()
        binding.recentList.removeAllViews()
        val spacing = binding.root.context.dpInt(10f)
        records.take(3).forEachIndexed { index, record ->
            val row = RecentRecordRow(requireContext())
            row.set(record)
            row.setOnClickListener { router.push(AppRoute.RecordDetail(record.id)) }
            binding.recentList.addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                if (index > 0) topMargin = spacing
            })
        }
        binding.recentList.isVisible = records.isNotEmpty()
    }
}

class RecentRecordRow @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val iconView = ImageView(context).apply {
        val inset = context.dpInt(8f)
        setPadding(inset, inset, inset, inset)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val titleView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Body)
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    }

    private val badgeView = TextView(context).apply {
        setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 10f)
        typeface = Typeface.create(Typeface.DEFAULT, 500, false)
        setTextColor(context.color(R.color.record_badge_text))
        val h = context.dpInt(6f)
        val v = context.dpInt(2f)
        setPadding(h, v, h, v)
        background = context.roundedDrawable(999f, R.color.record_badge_bg)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val starView = ImageView(context).apply {
        setImageResource(R.drawable.mi_star)
        setColorFilter(context.color(R.color.accent))
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val subtitleView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.text_secondary))
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = context.dpInt(56f)
        isClickable = true
        isFocusable = true
        val dark = context.isDarkTheme
        if (dark) {
            setPadding(context.dpInt(14f), context.dpInt(10f), context.dpInt(14f), context.dpInt(10f))
            background = context.pressable(null, context.roundedDrawable(16f, R.color.surface))
        } else {
            setPadding(context.dpInt(12f), context.dpInt(10f), context.dpInt(12f), context.dpInt(10f))
            background = context.pressable(context.roundedDrawable(16f, R.color.surface_raised))
            elevation(Elevation.RAISED)
        }
        addView(iconView, LayoutParams(context.dpInt(36f), context.dpInt(36f)).apply {
            marginEnd = context.dpInt(12f)
        })
        addView(LinearLayout(context).apply {
            orientation = VERTICAL
            addView(LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(titleView)
                addView(starView, LayoutParams(context.dpInt(12f), context.dpInt(12f)).apply {
                    marginStart = context.dpInt(5f)
                })
                addView(badgeView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                    marginStart = context.dpInt(6f)
                })
            })
            addView(subtitleView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dpInt(3f) })
        }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
            marginEnd = context.dpInt(8f)
        })
        addView(ImageView(context).apply { setAppIcon(AppIcon.ARROW, R.color.text_secondary) }, LayoutParams(context.dpInt(18f), context.dpInt(18f)))
    }

    fun set(record: Record) {
        val meeting = record.kind == com.tencent.iot.aiglasses.models.RecordKind.MEETING
        val iconTint = if (meeting) R.color.icon_tint_blue else R.color.icon_tint_purple
        val iconBg = if (meeting) R.color.icon_bg_blue else R.color.icon_bg_purple
        iconView.setImageResource(if (meeting) AppIcon.MEETING.res else AppIcon.LANGUAGE.res)
        iconView.setColorFilter(context.color(iconTint))
        iconView.background = context.roundedDrawable(10f, iconBg)
        titleView.text = record.title
        badgeView.text = if (record.isInterpret == true) "传译" else if (meeting) "纪要" else "翻译"
        starView.isVisible = record.isStarred
        subtitleView.text = record.subtitle()
        contentDescription = "${if (record.isStarred) "星标，" else ""}${record.title}，${record.subtitle()}"
    }
}

class Wordmark @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {
    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = "AI眼镜"
        addView(TextView(context).apply {
            setTextAppearance(R.style.TextAppearance_Suisheng_Wordmark)
            text = "AI眼镜"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        })
        addView(TextView(context).apply {
            setTextAppearance(R.style.TextAppearance_Suisheng_WordmarkCaption)
            text = "AI GLASSES"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            marginStart = context.dpInt(11f)
        })
        isAccessibilityHeading = true
    }
}
