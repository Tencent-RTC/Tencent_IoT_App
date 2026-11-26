#ifndef WATCH_MEDIA_SOURCE_ESP_H
#define WATCH_MEDIA_SOURCE_ESP_H

#include "watch_media_iot.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 填充 ESP32 采集适配的 start/stop 回调，交由 watch_iot_media_set_input() 注入。
   首次调用会初始化音频 Codec（I2C/I2S/ES7210/ES8311）。 */
int watch_media_source_esp_create(watch_iot_media_input_t *input);

/* 远端音频下行播放：在 tc_iot_av_observer_s.on_audio_frame_received 中调用。 */
void watch_media_source_esp_playout_audio(const tc_iot_audio_frame *frame);

#ifdef __cplusplus
}
#endif

#endif
