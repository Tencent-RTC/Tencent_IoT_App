package com.tencent.iot.watchapp.watch
import com.tencent.iot.watchapp.R

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat

class WatchMapView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {
    private val road = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.watch_map_road)
        style = Paint.Style.STROKE
        strokeWidth = 22f
    }
    private val minorRoad = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.watch_map_road_secondary)
        style = Paint.Style.STROKE
        strokeWidth = 8f
    }
    private val park = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.watch_map_land)
        style = Paint.Style.FILL
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(ContextCompat.getColor(context, R.color.watch_map_land))
        val w = width.toFloat()
        val h = height.toFloat()

        canvas.drawCircle(w * 0.18f, h * 0.22f, w * 0.18f, park)
        canvas.drawCircle(w * 0.83f, h * 0.68f, w * 0.24f, park)

        val diagonal = Path().apply {
            moveTo(-w * 0.1f, h * 0.78f)
            cubicTo(w * 0.22f, h * 0.5f, w * 0.48f, h * 0.62f, w * 1.08f, h * 0.2f)
        }
        val cross = Path().apply {
            moveTo(w * 0.62f, -h * 0.1f)
            cubicTo(w * 0.48f, h * 0.24f, w * 0.52f, h * 0.56f, w * 0.42f, h * 1.1f)
        }
        canvas.drawPath(diagonal, road)
        canvas.drawPath(cross, road)

        val side = Path().apply {
            moveTo(-w * 0.1f, h * 0.25f)
            cubicTo(w * 0.28f, h * 0.34f, w * 0.6f, h * 0.06f, w * 1.1f, h * 0.48f)
        }
        canvas.drawPath(side, minorRoad)
        canvas.drawLine(w * 0.12f, 0f, w * 0.88f, h, minorRoad)
        canvas.drawLine(w * 0.92f, 0f, w * 0.18f, h, minorRoad)
    }
}
