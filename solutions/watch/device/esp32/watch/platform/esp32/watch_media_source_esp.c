// Copyright (c) 2026 Tencent. All rights reserved.
//
// ESP32 媒体采集适配。
//
// 音频：复用 src/demo/iot_video_demo/av_device_esp32s3.c 的链路
//   - 上行：av_device_start_audio 启动采集任务（ES7210 + esp-sr AEC），
//           回调里把 PCM 包成 tc_iot_audio_frame 推给 watch_iot_media
//   - 下行：on_audio_frame_received 收到远端 PCM 后交 av_device_playout_audio（ES8311）
//
// 视频：av_device_esp32s3.c 的视频接口是空桩（针对未接摄像头的 S3-Korvo-2），
// 因此改用本目录的 watch_camera_esp.c：esp32-camera 采集 YUYV + esp_h264 软编码。
// 视频默认关闭，需在构建时定义 WATCH_ENABLE_CAMERA=1 开启，原因见下。
//
// 为什么视频默认关闭：
//   1. S3 无硬件 H.264 编码器，只能软编码，CPU 开销大，会与音频 AEC 抢 CPU；
//   2. 摄像头管脚、sensor 型号依开发板而异，默认值不一定匹配，错配时
//      esp_camera_init 必然失败，会让「音频本来能用」的场景一起起不来。
//   确认板子管脚后再开启，可避免把两条链路的问题耦合在一起。
//
// 注意管脚：音频管脚在 av_device_esp32s3.c（按 ESP32-S3-Korvo-2 V3.0 写死），
// 摄像头管脚在 watch_camera_esp.c 顶部的 WATCH_CAM_PIN_* 宏。本文件不含管脚定义。

#include "watch_media_source_esp.h"

#include <stddef.h>
#include <string.h>

#include "av_device.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "iot_demo_config.h"
#include "src/base/hal/tc_hal_audio.h"
#if WATCH_ENABLE_CAMERA
#include "watch_camera_esp.h"
#endif

#define TAG "watch_media_esp"

// 上行音频在采集任务里先编成 G722 再交给 TRTC（透传），而不是送 PCM 让 TRTC 内部编码。
//
// 原因：TRTC 内部编码器跑在 main_loop（CPU0）上，与收包、AES 加解密、下行解码、组包
// 挤在同一线程。实测双向音视频通话时 main_loop 占 CPU0 约 81%、IDLE0=0%，下行丢包约 30%。
// 采集任务 av_esp_mic 在 CPU1（通话中 CPU1 仍有 ~50% 空闲），编码挪过去可给 CPU0 减负。
// 置 0 恢复 PCM 上送（TRTC 内部编码），用于对比或排障。
#ifndef WATCH_ESP_UPLINK_G722
#define WATCH_ESP_UPLINK_G722 1
#endif
#define WATCH_ESP_G722_BITRATE 64000
// G722 64kbps：每个 16kHz 采样对应 4bit，20ms（320 采样）输出 160 字节。
#define WATCH_ESP_G722_OUT_MAX 512

static struct {
  watch_iot_push_audio_callback push_audio;
  watch_iot_push_video_callback push_video;
  void *push_user_data;
  int running;
  int video_running;
  uint64_t pts_ms;
#if WATCH_ESP_UPLINK_G722
  HALG722Encoder *g722;
  uint8_t g722_out[WATCH_ESP_G722_OUT_MAX];
  uint32_t g722_fail;
#endif
} s_esp_input;

// av_device 音频采集回调：在采集任务上下文被调用，数据为 16kHz 单声道 16bit PCM。
static void watch_esp_on_capture_audio(const uint8_t *data, uint32_t len, void *user_data) {
  (void)user_data;
  if (!s_esp_input.running || !s_esp_input.push_audio || !data || len == 0) return;
  tc_iot_audio_frame frame = {
      .codec = TC_IOT_AUDIO_CODEC_PCM,
      .sample_rate = TC_IOT_AUDIO_SAMPLE_RATE_16000,
      .channels = TC_IOT_AUDIO_CHANNEL_MONO,
      .frame_duration_ms = MIC_FRAME_MS,
      .data = (uint8_t *)data,
      .data_size = len,
      // 采集侧单调递增时间戳：按帧长累加，避免依赖墙上时间。
      .pts_ms = s_esp_input.pts_ms,
  };
  s_esp_input.pts_ms += MIC_FRAME_MS;
#if WATCH_ESP_UPLINK_G722
  if (s_esp_input.g722) {
    int32_t n = HAL_G722Encode(s_esp_input.g722, (const int16_t *)(const void *)data,
                               len / sizeof(int16_t), s_esp_input.g722_out,
                               sizeof(s_esp_input.g722_out));
    if (n <= 0) {
      // 编码失败丢弃本帧，不回退 PCM：同一通话内混用 PCM/G722 会让 TRTC 来回切编码路径。
      if ((s_esp_input.g722_fail++ % 500) == 0) {
        ESP_LOGW(TAG, "G722 encode failed (n=%ld len=%lu) x%lu", (long)n, (unsigned long)len,
                 (unsigned long)s_esp_input.g722_fail);
      }
      return;
    }
    frame.codec = TC_IOT_AUDIO_CODEC_G722;
    frame.data = s_esp_input.g722_out;
    frame.data_size = (uint32_t)n;
  }
#endif
  (void)s_esp_input.push_audio(&frame, s_esp_input.push_user_data);
}

#if WATCH_ENABLE_CAMERA
// 摄像头编码回调：在采集任务上下文被调用，data 仅在回调期间有效，
// 此处同步交给 TRTC 推流，不做二次缓存。
static void watch_esp_on_capture_video(const uint8_t *data, uint32_t len, bool is_key_frame,
                                       uint64_t pts_ms, void *user_data) {
  (void)user_data;
  if (!s_esp_input.running || !s_esp_input.push_video || !data || len == 0) return;
  tc_iot_video_frame frame = {
      .codec = TC_IOT_VIDEO_CODEC_MJPEG,
      .type = is_key_frame ? TC_IOT_VIDEO_FRAME_TYPE_IDR : TC_IOT_VIDEO_FRAME_TYPE_P,
      .rotation = TC_IOT_VIDEO_ROTATION_0,
      .width = WATCH_CAM_FRAME_WIDTH,
      .height = WATCH_CAM_FRAME_HEIGHT,
      .data = (uint8_t *)data,
      .data_size = len,
      .pts_ms = pts_ms,
  };
  (void)s_esp_input.push_video(&frame, s_esp_input.push_user_data);
}
#endif

static int watch_esp_input_start(const watch_call_option_t *option,
                                 watch_iot_push_audio_callback push_audio,
                                 watch_iot_push_video_callback push_video,
                                 void *push_user_data, void *user_data) {
  (void)user_data;
  if (s_esp_input.running) {
    ESP_LOGW(TAG, "media input already started");
    return 0;
  }
  s_esp_input.push_audio = push_audio;
  s_esp_input.push_video = push_video;
  s_esp_input.push_user_data = push_user_data;
  s_esp_input.pts_ms = 0;
  s_esp_input.video_running = 0;
#if WATCH_ESP_UPLINK_G722
  // 采集任务启动前创建编码器（首次通话时创建，之后复用）：回调只读取该指针。
  // 创建失败则退回 PCM 上送（TRTC 内部编码），通话仍可用。
  if (!s_esp_input.g722) {
    s_esp_input.g722 = HAL_CreateG722Encoder(16000, 1, WATCH_ESP_G722_BITRATE);
    if (!s_esp_input.g722) {
      ESP_LOGW(TAG, "G722 encoder create failed; uplink falls back to PCM");
    }
  }
  s_esp_input.g722_fail = 0;
#endif
  s_esp_input.running = 1;
  // 第一个参数是 Linux 文件流路径，ESP 实现走真实采集，传 NULL。
  if (av_device_start_audio(NULL, watch_esp_on_capture_audio, NULL) != 0) {
    ESP_LOGE(TAG, "av_device_start_audio failed (check ES7210/ES8311 pins)");
    s_esp_input.running = 0;
    s_esp_input.push_audio = NULL;
    s_esp_input.push_video = NULL;
    s_esp_input.push_user_data = NULL;
    return -1;
  }

#if WATCH_ENABLE_CAMERA
  // 仅音频通话不启动摄像头，省掉软编码的 CPU 开销。
  int want_video = !option || option->media_content != WATCH_MEDIA_AUDIO;
  if (want_video && push_video) {
    if (watch_camera_esp_start(watch_esp_on_capture_video, NULL) == 0) {
      s_esp_input.video_running = 1;
    } else {
      // 视频失败不影响音频通话，降级继续。
      ESP_LOGW(TAG, "camera start failed; continuing with audio only");
    }
  }
#else
  (void)push_video;
#endif

  ESP_LOGI(TAG, "capture started: audio=1 video=%d (media_content=%d)", s_esp_input.video_running,
           option ? (int)option->media_content : -1);
  return 0;
}

static void watch_esp_input_stop(void *user_data) {
  (void)user_data;
  if (!s_esp_input.running) return;
  // 先置位再停采集：确保回调中途返回，不再向已失效的上层推帧。
  s_esp_input.running = 0;
#if WATCH_ENABLE_CAMERA
  if (s_esp_input.video_running) {
    watch_camera_esp_stop();
    s_esp_input.video_running = 0;
  }
#endif
  av_device_stop_audio(watch_esp_on_capture_audio, NULL);
  s_esp_input.push_audio = NULL;
  s_esp_input.push_video = NULL;
  s_esp_input.push_user_data = NULL;
#if WATCH_ESP_UPLINK_G722
  // 编码器跨通话复用、不在这里销毁：av_device_stop_audio 等待采集任务退出有超时，
  // 超时后回调可能仍在执行，此时销毁会 use-after-free。G722 编码器很小，常驻无妨。
#endif
  ESP_LOGI(TAG, "capture stopped");
}

int watch_media_source_esp_create(watch_iot_media_input_t *input) {
  if (!input) return -1;
  // Codec/I2S 初始化只做一次；start/stop 仅控制采集任务起停。
  static int s_device_initialized = 0;
  if (!s_device_initialized) {
    av_device_config_t device_config;
    memset(&device_config, 0, sizeof(device_config));
    av_device_init(&device_config);
    s_device_initialized = 1;
  }
  input->start = watch_esp_input_start;
  input->stop = watch_esp_input_stop;
  input->user_data = NULL;
  return 0;
}

void watch_media_source_esp_playout_audio(const tc_iot_audio_frame *frame) {
  if (!frame || !frame->data || frame->data_size == 0) return;
  // 只在通话中播放：设备常驻 TRTC 房间，挂断后对端可能还在房间里推流几秒
  // （实测挂断后约 4s 才退房），这段音频不应再从扬声器出来。
  if (!s_esp_input.running) return;
  av_device_playout_audio(frame->data, (uint32_t)frame->data_size);
}
