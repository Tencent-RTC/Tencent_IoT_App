#ifndef WATCH_PLATFORM_H
#define WATCH_PLATFORM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 平台层提供单调时钟；单位为毫秒，不能使用会回拨的墙上时间。 */
uint64_t watch_platform_now_ms(void);

/* 平台层可在主循环或任务中调用，用于驱动信令超时和自动接听。 */
void watch_platform_sleep_ms(uint32_t milliseconds);

#ifdef __cplusplus
}
#endif

#endif
