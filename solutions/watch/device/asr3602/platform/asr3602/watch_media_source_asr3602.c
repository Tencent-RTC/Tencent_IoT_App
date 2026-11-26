// Copyright (c) 2026 Tencent. All rights reserved.
//
// ASR3602 音视频采集 / 播放适配骨架。
// TODO(M2): 使用客户提供的录音、播放、摄像头和 JPEG 接口完成实现。

#include "watch_media_source_asr3602.h"

#include <string.h>

static int watch_asr3602_input_start(const watch_call_option_t *option,
                                     watch_iot_push_audio_callback push_audio,
                                     watch_iot_push_video_callback push_video,
                                     void *push_user_data, void *user_data) {
  (void)option;
  (void)push_audio;
  (void)push_video;
  (void)push_user_data;
  (void)user_data;
  /* TODO(M2): 启动 16 kHz 音频采集和按需的视频采集任务。 */
  return -1;
}

static void watch_asr3602_input_stop(void *user_data) {
  (void)user_data;
  /* TODO(M2): 停止采集任务，确保不再向上层推送数据。 */
}

int watch_media_source_asr3602_create(watch_iot_media_input_t *input) {
  if (!input) return -1;
  memset(input, 0, sizeof(*input));
  input->start = watch_asr3602_input_start;
  input->stop = watch_asr3602_input_stop;
  return 0;
}

void watch_media_source_asr3602_playout_audio(const tc_iot_audio_frame *frame) {
  (void)frame;
  /* TODO(M2): 解码需要的下行音频并交给扬声器播放。 */
}
