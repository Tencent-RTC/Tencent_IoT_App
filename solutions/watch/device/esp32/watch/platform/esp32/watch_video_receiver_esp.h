// Copyright (c) 2026 Tencent. All rights reserved.
//
// ESP32-S3 远端视频接收：TRTC 收包 -> tinyh264 软解码 -> RGB565 -> ST7789 显示。
//
// S3 无硬件 H.264 解码器，走 esp_h264 的 tinyh264 软解码（sw/libs/esp32s3/libtinyh264.a）。
// 解码输出固定为 I420（esp_h264_dec_sw.c 只支持 I420），本模块负责 I420->RGB565 转换。

#ifndef WATCH_VIDEO_RECEIVER_ESP_H
#define WATCH_VIDEO_RECEIVER_ESP_H

#include <stdbool.h>

#include "tc_iot_def.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 初始化远端视频解码器。重复调用安全。
 * 必须在 watch_display_esp_init 之后调用（解码帧要送屏）。
 *
 * @return 0 成功，-1 失败
 */
int watch_video_receiver_esp_init(void);

/**
 * 处理一帧远端视频（tc_iot_av_observer_s.on_video_frame_received 的回调入参）。
 *
 * MJPEG：只拷贝并投递给后台解码任务（watch_vrx）后立即返回，不阻塞 TRTC 收包线程；
 *        任务忙时新帧覆盖旧帧（只保留最新一帧）。
 * H.264：在调用线程同步软解码（仅 Constrained Baseline 可解）。
 *
 * @param frame 远端视频帧
 */
void watch_video_receiver_esp_on_frame(const tc_iot_video_frame *frame);

/**
 * 远端画面是否正在显示（最近 1 秒内有远端帧刷到屏上）。
 * 本地预览据此让屏：远端活跃时不画本地画面，远端停流后自动恢复本地预览。
 */
bool watch_video_receiver_esp_is_active(void);

/** 反初始化，释放解码器。 */
void watch_video_receiver_esp_deinit(void);

#ifdef __cplusplus
}
#endif

#endif  // WATCH_VIDEO_RECEIVER_ESP_H
