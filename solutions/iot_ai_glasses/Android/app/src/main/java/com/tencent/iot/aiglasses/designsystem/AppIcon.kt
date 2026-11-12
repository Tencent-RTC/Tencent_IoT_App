package com.tencent.iot.aiglasses.designsystem

import android.widget.ImageView
import androidx.annotation.ColorRes
import androidx.annotation.DrawableRes
import com.tencent.iot.aiglasses.R

enum class AppIcon(@DrawableRes val res: Int) {
    HOME(R.drawable.menu_home),
    RECORDS(R.drawable.menu_record),
    GLASSES(R.drawable.menu_glasses),
    LISTEN(R.drawable.menu_listen),
    MEETING(R.drawable.menu_meeting),
    INTERPRET(R.drawable.menu_translate),
    CALL_FEATURE(R.drawable.menu_call),
    CHAT_FEATURE(R.drawable.menu_chat),
    LANGUAGE(R.drawable.menu_language),
    SPEAKER(R.drawable.menu_speaker),

    ARROW(R.drawable.icon_arrow),
    BACK(R.drawable.icon_back),
    MIC(R.drawable.icon_mic),
    PAUSE(R.drawable.icon_pause),
    PLAY(R.drawable.icon_play),
    STOP(R.drawable.icon_stop),
    SWAP(R.drawable.icon_swap),
    CHECK(R.drawable.icon_check),
    CLOSE(R.drawable.icon_close),
    DOWNLOAD(R.drawable.icon_download),
    MORE(R.drawable.icon_more),
    CALL(R.drawable.icon_call),
    CHAT(R.drawable.icon_chat),
    MUTE(R.drawable.icon_mute),
    SUN(R.drawable.icon_sun),
    MOON(R.drawable.icon_moon),
    CHEVRON_DOWN(R.drawable.icon_chevron_down),
    CALL_OUT(R.drawable.icon_call_out),
    CALL_IN(R.drawable.icon_call_in),
    CARD_ARROW(R.drawable.icon_card_arrow),
    SIGNAL(R.drawable.icon_signal)
}

fun ImageView.setAppIcon(icon: AppIcon, @ColorRes tint: Int) {
    setImageResource(icon.res)
    imageTintList = context.colorList(tint)
    importantForAccessibility = ImageView.IMPORTANT_FOR_ACCESSIBILITY_NO
}
