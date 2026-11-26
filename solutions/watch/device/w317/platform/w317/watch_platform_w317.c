// Copyright (c) 2026 Tencent. All rights reserved.
//
// W317 系统平台层骨架。
// TODO(W317): 使用客户基线提供的单调时钟和任务延时接口替换占位实现。

#include "watch/platform.h"

/*
 * 这是仅用于发布包结构和接口检查的占位时钟，不代表 W317 的真实时间。
 * 客户适配时必须替换为不受墙上时间回拨影响的单调时钟。
 */
static uint64_t g_placeholder_now_ms;

uint64_t watch_platform_now_ms(void) {
  return g_placeholder_now_ms;
}

void watch_platform_sleep_ms(uint32_t milliseconds) {
  /* TODO(W317): 调用客户 RTOS 的 sleep / delay 接口。 */
  g_placeholder_now_ms += milliseconds;
}
