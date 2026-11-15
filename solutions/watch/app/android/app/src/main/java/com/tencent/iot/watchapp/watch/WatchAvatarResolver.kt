package com.tencent.iot.watchapp.watch
import com.tencent.iot.watchapp.R

/** 为绑定设备稳定分配男孩／女孩头像，避免每次重绘随机变化。 */
object WatchAvatarResolver {
    fun resourceFor(identity: String): Int {
        return if ((identity.hashCode() and 1) == 0) {
            R.drawable.watch_avatar_lele_card_design
        } else {
            R.drawable.watch_avatar_xiaoya_card_design
        }
    }

    fun resourceForOrDefault(identity: String, defaultIdentity: String = "watch"): Int =
        resourceFor(identity.ifBlank { defaultIdentity })
}
