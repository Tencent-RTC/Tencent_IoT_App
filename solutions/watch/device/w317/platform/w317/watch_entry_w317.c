// Copyright (c) 2026 Tencent. All rights reserved.
//
// W317 watch 入口骨架。
// TODO(W317): 使用客户基线的任务、网络、时间和 SDK 接口补齐启动流程。

#include "watch_w317.h"

static int g_watch_started;

int watch_start(void) {
  if (g_watch_started) return 0;

  /*
   * TODO(W317):
   * 1. 创建 watch 任务并立即返回；
   * 2. 等待网络可用并完成时间同步；
   * 3. 初始化 IM、TRTC 和 watch app；
   * 4. 接入 watch_media_source_w317 和 watch_video_receiver_w317。
   *
   * 当前不伪造平台启动成功，避免 ESP32 占位库被误用于 W317。
   */
  return -1;
}

int watch_stop(void) {
  if (!g_watch_started) return 0;

  /* TODO(W317): 挂断、停止 watch app、登出 SDK、销毁任务和平台资源。 */
  g_watch_started = 0;
  return 0;
}
