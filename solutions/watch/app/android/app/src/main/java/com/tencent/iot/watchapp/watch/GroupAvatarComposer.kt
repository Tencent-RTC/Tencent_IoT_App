package com.tencent.iot.watchapp.watch

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import androidx.appcompat.content.res.AppCompatResources
import kotlin.math.min

/** 根据群成员头像资源生成消息列表使用的组合头像。 */
object GroupAvatarComposer {
    fun create(context: Context, avatarResources: List<Int>): Drawable {
        val resources = avatarResources.take(4)
        val size = (48f * context.resources.displayMetrics.density).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val gap = (2f * context.resources.displayMetrics.density).coerceAtLeast(1f)
        val tile = (size - gap) / 2f

        resources.forEachIndexed { index, resourceId ->
            val drawable = AppCompatResources.getDrawable(context, resourceId) ?: return@forEachIndexed
            val rect = when {
                resources.size == 1 -> RectF(0f, 0f, size.toFloat(), size.toFloat())
                resources.size == 2 -> {
                    val left = index * (tile + gap)
                    RectF(left, 0f, left + tile, size.toFloat())
                }
                resources.size == 3 -> {
                    val left = when (index) {
                        0 -> (size - tile) / 2f
                        else -> (index - 1) * (tile + gap)
                    }
                    val top = if (index == 0) 0f else tile + gap
                    RectF(left, top, left + tile, top + tile)
                }
                else -> {
                    val column = index % 2
                    val row = index / 2
                    val left = column * (tile + gap)
                    val top = row * (tile + gap)
                    RectF(left, top, left + tile, top + tile)
                }
            }
            drawClipped(canvas, drawable, rect, min(rect.width(), rect.height()) * 0.22f)
        }
        return BitmapDrawable(context.resources, bitmap)
    }

    private fun drawClipped(canvas: Canvas, drawable: Drawable, rect: RectF, radius: Float) {
        val path = Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) }
        canvas.save()
        canvas.clipPath(path)
        drawable.setBounds(rect.left.toInt(), rect.top.toInt(), rect.right.toInt(), rect.bottom.toInt())
        drawable.draw(canvas)
        canvas.restore()
    }
}
