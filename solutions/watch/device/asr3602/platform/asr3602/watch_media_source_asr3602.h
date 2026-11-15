// Copyright (c) 2026 Tencent. All rights reserved.

#ifndef WATCH_MEDIA_SOURCE_ASR3602_H
#define WATCH_MEDIA_SOURCE_ASR3602_H

#include "watch_media_iot.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * 填充 ASR3602 录音和摄像头采集回调。
 * 当前实现只保留接口，客户需要接入真实设备驱动和 G722 / MJPEG 数据链路。
 */
int watch_media_source_asr3602_create(watch_iot_media_input_t *input);

/* 接收远端音频帧并交给 ASR3602 扬声器播放。 */
void watch_media_source_asr3602_playout_audio(const tc_iot_audio_frame *frame);

#ifdef __cplusplus
}
#endif

#endif  // WATCH_MEDIA_SOURCE_ASR3602_H
