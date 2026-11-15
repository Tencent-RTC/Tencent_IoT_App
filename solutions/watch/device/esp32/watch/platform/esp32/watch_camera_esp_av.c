// Copyright (c) 2026 Tencent. All rights reserved.
//
// watch_camera_esp.h 的「板级 av_device」实现（ESP32-S31 等自带摄像头驱动的板子）。
//
// S3 用 watch_camera_esp.c（esp32-camera + 软件 JPEG）；S31 的 sc101iot 已由
// av_device_esp32s31.c 驱动（esp_video 采集 + PPA 缩放 + 硬件 JPEG 编码），这里只做转接：
//   watch_camera_esp_start -> av_device_start_video，编码好的 MJPEG 帧原样回调给 watch。
// 摄像头在 av_device_init（watch_media_source_esp_create 里调用）时已打开，本文件不管初始化。
// 上行尺寸 / 帧率 / 质量在 cmd_iot_demo/CMakeLists.txt 配置，须与 WATCH_CAM_FRAME_WIDTH/HEIGHT 一致。

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "av_device.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "watch_camera_esp.h"

#define TAG "watch_cam_av"

static struct {
  watch_camera_frame_callback callback;
  void *user_data;
  bool started;
  bool size_checked;
} s_cam;

// 从 JPEG 的 SOF0/1/2 段读宽高。仅用于首帧核对配置是否一致。
static bool watch_cam_av_jpeg_size(const uint8_t *data, uint32_t size, int *width, int *height) {
  if (size < 4 || data[0] != 0xFF || data[1] != 0xD8) return false;
  uint32_t pos = 2;
  while (pos + 4 <= size) {
    if (data[pos] != 0xFF) return false;
    uint8_t marker = data[pos + 1];
    if (marker == 0xFF) {
      pos++;
      continue;
    }
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      pos += 2;
      continue;
    }
    uint32_t seg_len = ((uint32_t)data[pos + 2] << 8) | data[pos + 3];
    if (seg_len < 2) return false;
    if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
      if (pos + 9 > size) return false;
      *height = (data[pos + 5] << 8) | data[pos + 6];
      *width = (data[pos + 7] << 8) | data[pos + 8];
      return true;
    }
    if (marker == 0xDA) return false;
    pos += 2 + seg_len;
  }
  return false;
}

// av_device 采集任务上下文。data 只在回调期间有效，watch 侧同步推流、不缓存。
static void watch_cam_av_on_frame(const uint8_t *data, uint32_t len, bool is_key_frame,
                                  tc_iot_video_codec_e codec, void *user_data) {
  (void)user_data;
  if (!s_cam.started || !s_cam.callback || !data || len == 0) return;
  if (codec != TC_IOT_VIDEO_CODEC_MJPEG) {
    ESP_LOGW(TAG, "unexpected codec=%d from av_device, drop", (int)codec);
    return;
  }
  if (!s_cam.size_checked) {
    int w = 0;
    int h = 0;
    if (watch_cam_av_jpeg_size(data, len, &w, &h)) {
      s_cam.size_checked = true;
      if (w != WATCH_CAM_FRAME_WIDTH || h != WATCH_CAM_FRAME_HEIGHT) {
        ESP_LOGE(TAG, "uplink JPEG %dx%d != WATCH_CAM_FRAME %dx%d; check cmd_iot_demo/cmd_watch CMake",
                 w, h, WATCH_CAM_FRAME_WIDTH, WATCH_CAM_FRAME_HEIGHT);
      } else {
        ESP_LOGI(TAG, "first uplink frame: MJPEG %dx%d %u bytes", w, h, (unsigned)len);
      }
    }
  }
  s_cam.callback(data, len, is_key_frame, (uint64_t)(esp_timer_get_time() / 1000), s_cam.user_data);
}

int watch_camera_esp_init(void) {
  // 摄像头由 av_device_init 打开；打开失败时 start 会返回错误，上层降级为纯音频。
  return 0;
}

int watch_camera_esp_start(watch_camera_frame_callback callback, void *user_data) {
  if (!callback) return -1;
  if (s_cam.started) {
    ESP_LOGW(TAG, "camera already started");
    return 0;
  }
  s_cam.callback = callback;
  s_cam.user_data = user_data;
  s_cam.size_checked = false;
  s_cam.started = true;
  if (av_device_start_video(NULL, watch_cam_av_on_frame, NULL) != 0) {
    ESP_LOGE(TAG, "av_device_start_video failed (camera not initialized?)");
    s_cam.started = false;
    s_cam.callback = NULL;
    s_cam.user_data = NULL;
    return -1;
  }
  return 0;
}

void watch_camera_esp_stop(void) {
  if (!s_cam.started) return;
  // 先置位：av_device_stop_video 等采集任务退出期间，回调里不再向上推帧。
  s_cam.started = false;
  av_device_stop_video(watch_cam_av_on_frame, NULL);
  s_cam.callback = NULL;
  s_cam.user_data = NULL;
}

#if WATCH_ENABLE_DISPLAY
// 本板屏幕只显示远端画面（av_device 下行通路），不做本地预览。
void watch_camera_esp_set_preview(bool enabled) { (void)enabled; }
#endif

// MJPEG 每帧都是关键帧，无需请求。
void watch_camera_esp_request_idr(void) {}
