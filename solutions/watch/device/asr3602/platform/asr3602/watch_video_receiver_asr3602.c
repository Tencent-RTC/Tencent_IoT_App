// Copyright (c) 2026 Tencent. All rights reserved.
//
// ASR3602 下行视频接收骨架。
// TODO(M3): 接入客户提供的 JPEG 解码器和 LCD 显示接口。

#include "watch_video_receiver_asr3602.h"

int watch_video_receiver_asr3602_init(void) {
  /* TODO(M3): 初始化 JPEG 解码器和 LCD。 */
  return -1;
}

void watch_video_receiver_asr3602_on_frame(const tc_iot_video_frame *frame) {
  (void)frame;
  /* TODO(M3): 解码 MJPEG 帧并显示到 LCD。 */
}

void watch_video_receiver_asr3602_deinit(void) {
  /* TODO(M3): 释放 JPEG 解码器和 LCD 资源。 */
}
