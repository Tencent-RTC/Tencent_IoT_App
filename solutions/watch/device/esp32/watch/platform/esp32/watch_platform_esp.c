// Copyright (c) 2026 Tencent. All rights reserved.
//
// watch 平台层的 ESP32 实现，替代 platform/common/watch_platform_posix.c：
//   - clock_gettime(CLOCK_MONOTONIC) -> esp_timer_get_time()（自启动起的单调微秒数）
//   - nanosleep()                    -> vTaskDelay()（让出 CPU 给其他 FreeRTOS 任务）
//
// 两个函数都只被 watch_app_tick / 信令超时与自动接听逻辑使用，不涉及 IM 或媒体状态机。

#include "watch/platform.h"

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

uint64_t watch_platform_now_ms(void) {
  // esp_timer_get_time 返回 int64_t 微秒，单调递增且不受 NTP/墙上时间回拨影响。
  return (uint64_t)(esp_timer_get_time() / 1000);
}

void watch_platform_sleep_ms(uint32_t milliseconds) {
  // pdMS_TO_TICKS 在 tick 周期为 10ms（IDF 默认 configTICK_RATE_HZ=100）时会把
  // 不足一个 tick 的时长截断为 0，导致 vTaskDelay(0) 只让出一次 CPU 而不真正延时。
  // watch 主循环以 100ms 为周期，这里对小于一个 tick 的请求至少延时一个 tick。
  TickType_t ticks = pdMS_TO_TICKS(milliseconds);
  if (ticks == 0 && milliseconds > 0) {
    ticks = 1;
  }
  vTaskDelay(ticks);
}
