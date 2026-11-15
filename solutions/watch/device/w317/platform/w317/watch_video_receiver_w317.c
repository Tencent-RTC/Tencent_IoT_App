// Copyright (c) 2026 Tencent. All rights reserved.
//
// W317 下行视频接收骨架。
// TODO(W317): 接入 MJPEG 解码和 LCD 显示接口。

#include "watch_video_receiver_w317.h"

int watch_video_receiver_w317_init(void) {
  /* TODO(W317): 初始化 JPEG 解码器和 LCD。 */
  return -1;
}

void watch_video_receiver_w317_on_frame(const tc_iot_video_frame *frame) {
  (void)frame;
  /* TODO(W317): 解码 MJPEG 帧并显示到 LCD。 */
}

void watch_video_receiver_w317_deinit(void) {
  /* TODO(W317): 释放 JPEG 解码器和 LCD 资源。 */
}
