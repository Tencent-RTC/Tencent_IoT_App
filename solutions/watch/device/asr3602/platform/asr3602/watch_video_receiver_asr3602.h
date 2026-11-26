// Copyright (c) 2026 Tencent. All rights reserved.

#ifndef WATCH_VIDEO_RECEIVER_ASR3602_H
#define WATCH_VIDEO_RECEIVER_ASR3602_H

#include "tc_iot_av.h"

#ifdef __cplusplus
extern "C" {
#endif

int watch_video_receiver_asr3602_init(void);
void watch_video_receiver_asr3602_on_frame(const tc_iot_video_frame *frame);
void watch_video_receiver_asr3602_deinit(void);

#ifdef __cplusplus
}
#endif

#endif  // WATCH_VIDEO_RECEIVER_ASR3602_H
