// Copyright (c) 2026 Tencent. All rights reserved.
//
// ESP32-S3 远端视频接收实现。
//
// 按对端推流 codec 分流两条解码路径：
//
//   MJPEG（当前主路径，app 端发 JPEG 帧）
//     -> esp_new_jpeg 软解码（jpeg_dec_process，输出 RGB565_LE）
//     -> 直接送屏，无需额外色彩转换
//
//   H.264（保留路径，但 tinyh264 只支持 Constrained Baseline）
//     -> esp_h264_dec_sw（tinyh264，输出 I420）
//     -> I420 -> RGB565（BT.601 整数近似）
//     -> watch_display_esp_draw_rgb565 -> ST7789
//
// 为什么以 MJPEG 为主：
//   手机端硬件编码器默认输出 High Profile H.264（profile_idc=100），而 tinyh264
//   软解码器只支持 Constrained Baseline（66），实测直接报
//   "profile_idc is error" 无法解码。MJPEG 无 profile 概念、无帧间依赖，
//   软解码复杂度远低于 H.264，是 S3 上唯一能稳定跑通的远端视频解码路径。

#include "watch_video_receiver_esp.h"

#include <string.h>

#include "esp_heap_caps.h"
#include "esp_h264_dec.h"
#include "esp_h264_dec_param.h"
#include "esp_h264_dec_sw.h"
#include "esp_jpeg_dec.h" /* MJPEG 软解码（esp_new_jpeg，与上行编码同组件）*/
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/idf_additions.h" /* xTaskCreatePinnedToCoreWithCaps */
#include "freertos/semphr.h"
#include "freertos/task.h"

// 显示通路：
//   WATCH_VRX_SPI_DISPLAY：S3 的 SPI ST7789（watch_display_esp.c），远端 MJPEG 本文件软解后送屏；
//   WATCH_VRX_BOARD_DISPLAY：S31 等板级 av_device 屏，远端 MJPEG 原样交 av_device_playout_mjpg
//     （硬件 JPEG 解码 + 居中/放大 + RGB 面板，均在 av_device 自己的显示任务里），本文件不解码。
#ifndef WATCH_ESP_BOARD_AV
#define WATCH_ESP_BOARD_AV 0
#endif
#define WATCH_VRX_SPI_DISPLAY (WATCH_ENABLE_DISPLAY && !WATCH_ESP_BOARD_AV)
#define WATCH_VRX_BOARD_DISPLAY (WATCH_ENABLE_DISPLAY && WATCH_ESP_BOARD_AV)

#if WATCH_VRX_SPI_DISPLAY
#include "watch_camera_esp.h" /* 收远端时关本地预览 */
#include "watch_display_esp.h"
#else
// 不接屏时仍按 S3 屏幕尺寸（320x240）解码：解码负载与带屏固件一致，跨板对比 CPU 才有可比性。
// 解码结果直接丢弃。
#define WATCH_LCD_WIDTH 320
#define WATCH_LCD_HEIGHT 240
#endif
#if WATCH_VRX_BOARD_DISPLAY
#include "av_device.h"
#endif

#define TAG "watch_video_rx"

// MJPEG 解码任务。
//
// 为什么不在回调里直接解码：on_video_frame_received 跑在 TRTC 的 main_loop 收包线程上，
// 640x480 缩放解码约 36ms/帧，再加刷屏（SPI 传 150KB）约 50ms，每帧近 90ms 会把收包
// 线程堵住，音频与视频包一起积压。因此回调只拷贝数据投递到「单槽邮箱」，由本任务解码。
//
// 单槽 = 只保留最新一帧：任务忙时新帧直接覆盖旧帧（丢旧不丢新），显示帧率随 CPU 余量
// 自适应，不会积压延迟。MJPEG 每帧独立，丢帧不影响后续解码。
//
// 不绑核、低优先级：本任务只该吃两个核的空闲时间。
// 实测通话中两个核轮流成为瓶颈：core 0 被 TRTC main_loop（AAC 编码 + 每包 AES-GCM）
// 占到 75% 左右，core 1 被 AEC（av_esp_mic ~60%）+ 摄像头编码（~21%）+ cam_task（~7%）
// 吃满（IDLE1=0%）。固定在任一核上都会被饿死（解码 avg 14ms 涨到 350ms、丢帧 2/3）。
// tskNO_AFFINITY 让调度器把它放到当前有空闲的核上。
// 优先级 4 低于 watch_cam（6）与 av_esp_mic（5），不会拖慢上行编码与音频采集。
// 栈放 PSRAM：纯计算 + SPI 刷屏，不访问 flash（见 HAL_OS_esp.c 的说明）。
#define WATCH_VRX_TASK_STACK (12 * 1024)
#define WATCH_VRX_TASK_PRIORITY 4
#define WATCH_VRX_TASK_CORE tskNO_AFFINITY
// 超过该时长未刷出远端帧，即视为远端视频不活跃，本地预览可以恢复。
#define WATCH_VRX_ACTIVE_WINDOW_US (1000 * 1000)

static struct {
  // H.264 路径
  esp_h264_dec_handle_t decoder;
  uint16_t *rgb565_buffer; /* I420->RGB565 转换缓冲 */
  int rgb565_capacity;     /* 像素数 */
  // MJPEG 路径（仅解码任务访问）
  jpeg_dec_handle_t jpeg_decoder;
  uint8_t *jpeg_outbuf; /* 解码输出，PSRAM、16 字节对齐 */
  int jpeg_outbuf_size;
  // MJPEG 邮箱：回调线程写 pending，解码任务换出到 working。
  SemaphoreHandle_t mbox_lock;
  SemaphoreHandle_t mbox_signal;
  TaskHandle_t task;
  volatile bool task_stop;
  volatile bool task_exited;
  uint8_t *pending_buf;
  size_t pending_cap;
  size_t pending_len; /* 0 = 无待处理帧 */
  uint8_t *working_buf;
  size_t working_cap;
  uint32_t dropped_frames;
  // 最近一次成功刷出远端画面的时刻；供本地预览判断是否让屏。
  volatile int64_t last_display_us;
  // 公共
  int src_width;  /* 远端输入分辨率（MJPEG：当前解码器按此配置） */
  int src_height;
  int display_width; /* MJPEG 解码输出分辨率；0 表示当前输入不可显示 */
  int display_height;
  uint32_t decoded_frames;
  uint64_t decode_total_us;
  uint64_t decode_max_us;
} s_rx;

// I420 -> RGB565（BT.601 整数近似，系数与 watch_display_esp.c 的 YUYV 版一致）。
// I420 为平面格式：Y 平面 width*height，U/V 平面各 width*height/4（2x2 共享一组 UV）。
static inline uint16_t i420_to_rgb565_px(int y, int u, int v) {
  const int cu = u - 128;
  const int cv = v - 128;
  int r = y + ((359 * cv) >> 8);
  int g = y - ((88 * cu + 183 * cv) >> 8);
  int b = y + ((454 * cu) >> 8);
  if (r < 0) r = 0; else if (r > 255) r = 255;
  if (g < 0) g = 0; else if (g > 255) g = 255;
  if (b < 0) b = 0; else if (b > 255) b = 255;
  return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}

static int ensure_rgb565_buffer(int width, int height) {
  int pixels = width * height;
  if (s_rx.rgb565_buffer && s_rx.rgb565_capacity >= pixels) {
    return 0;
  }
  if (s_rx.rgb565_buffer) {
    heap_caps_free(s_rx.rgb565_buffer);
    s_rx.rgb565_buffer = NULL;
    s_rx.rgb565_capacity = 0;
  }
  s_rx.rgb565_buffer = heap_caps_malloc((size_t)pixels * 2, MALLOC_CAP_SPIRAM);
  if (!s_rx.rgb565_buffer) {
    ESP_LOGE(TAG, "cannot allocate %d bytes for RGB565", pixels * 2);
    return -1;
  }
  s_rx.rgb565_capacity = pixels;
  return 0;
}

int watch_video_receiver_esp_init(void) {
  if (s_rx.decoder) return 0;
  esp_h264_dec_cfg_sw_t cfg = {
      .pic_type = ESP_H264_RAW_FMT_I420, /* 软解码器唯一支持的输出格式 */
  };
  if (esp_h264_dec_sw_new(&cfg, &s_rx.decoder) != ESP_H264_ERR_OK || !s_rx.decoder) {
    ESP_LOGE(TAG, "esp_h264_dec_sw_new failed (out of memory?)");
    return -1;
  }
  if (esp_h264_dec_open(s_rx.decoder) != ESP_H264_ERR_OK) {
    ESP_LOGE(TAG, "esp_h264_dec_open failed");
    esp_h264_dec_del(s_rx.decoder);
    s_rx.decoder = NULL;
    return -1;
  }
  ESP_LOGI(TAG, "H.264 sw decoder (tinyh264) ready");
  return 0;
}

// MJPEG 帧解码：jpeg_dec_process 输出 RGB565_LE，直接送屏。仅在解码任务中调用。
// 每帧一个完整 JPEG，无帧间依赖，解码失败只丢当前帧、不影响后续。
// 从 JPEG 的 SOF0/SOF1/SOF2 段读取宽高，不依赖解码器实例。
// 用途：判断远端分辨率是否变化。不能用 jpeg_dec_parse_header 来判断——解码器是按
// 某个输入分辨率配置 scale 的，分辨率变化后旧实例的输出尺寸不再正确。
// 实测：上一通 640x480 时解码器被配置为「缩放到 320x240」，手机改推 320x240 后沿用
// 旧实例，屏幕只显示画面左上角四分之一。
static bool watch_vrx_jpeg_size(const uint8_t *data, size_t size, int *width, int *height) {
  if (size < 4 || data[0] != 0xFF || data[1] != 0xD8) return false;
  size_t pos = 2;
  while (pos + 4 <= size) {
    if (data[pos] != 0xFF) return false;
    uint8_t marker = data[pos + 1];
    if (marker == 0xFF) { /* 填充字节 */
      pos++;
      continue;
    }
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) { /* 无长度段 */
      pos += 2;
      continue;
    }
    size_t seg_len = ((size_t)data[pos + 2] << 8) | data[pos + 3];
    if (seg_len < 2) return false;
    if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
      if (pos + 9 > size) return false;
      *height = (data[pos + 5] << 8) | data[pos + 6];
      *width = (data[pos + 7] << 8) | data[pos + 8];
      return *width > 0 && *height > 0;
    }
    if (marker == 0xDA) return false; /* 到了扫描数据还没见 SOF */
    pos += 2 + seg_len;
  }
  return false;
}

// 按远端输入分辨率（重新）配置解码器。返回 0 表示可显示，-1 表示不可显示。
static int watch_vrx_configure_decoder(int in_w, int in_h) {
  if (s_rx.jpeg_decoder) {
    jpeg_dec_close(s_rx.jpeg_decoder);
    s_rx.jpeg_decoder = NULL;
  }
  s_rx.src_width = in_w; /* 先记录输入分辨率，配置失败也不会每帧重试 */
  s_rx.src_height = in_h;
  s_rx.display_width = 0;
  s_rx.display_height = 0;

  jpeg_dec_config_t cfg = {
      .output_type = JPEG_PIXEL_FORMAT_RGB565_LE, /* 与 ST7789 面板一致，免二次转换 */
      .scale = {.width = 0, .height = 0},
      .rotate = JPEG_ROTATE_0D,
      .block_enable = false,
  };
  if (in_w == WATCH_LCD_WIDTH && in_h == WATCH_LCD_HEIGHT) {
    ESP_LOGI(TAG, "remote MJPEG %dx%d, no scaling", in_w, in_h);
  } else if (in_w >= WATCH_LCD_WIDTH && in_h >= WATCH_LCD_HEIGHT) {
    // esp_new_jpeg 的 scale 只能缩小，最大 1/8，且要求宽高为 8 的倍数（面板尺寸满足）。
    cfg.scale.width = WATCH_LCD_WIDTH;
    cfg.scale.height = WATCH_LCD_HEIGHT;
    ESP_LOGI(TAG, "remote MJPEG %dx%d, scaling to %dx%d", in_w, in_h, WATCH_LCD_WIDTH, WATCH_LCD_HEIGHT);
  } else {
    ESP_LOGW(TAG, "remote MJPEG %dx%d smaller than panel %dx%d, cannot display (decoder only downscales)",
             in_w, in_h, WATCH_LCD_WIDTH, WATCH_LCD_HEIGHT);
    return -1;
  }
  if (jpeg_dec_open(&cfg, &s_rx.jpeg_decoder) != JPEG_ERR_OK || !s_rx.jpeg_decoder) {
    ESP_LOGE(TAG, "jpeg_dec_open failed");
    s_rx.jpeg_decoder = NULL;
    return -1;
  }
  s_rx.display_width = WATCH_LCD_WIDTH;
  s_rx.display_height = WATCH_LCD_HEIGHT;
  return 0;
}

static void watch_vrx_decode_mjpeg(uint8_t *data, size_t size) {
  int in_w = 0;
  int in_h = 0;
  if (!watch_vrx_jpeg_size(data, size, &in_w, &in_h)) {
    ESP_LOGW(TAG, "jpeg SOF not found (size=%u)", (unsigned)size);
    return;
  }
  // 分辨率变化（含首帧）时重新配置解码器；对端可以在通话中途改分辨率。
  if (in_w != s_rx.src_width || in_h != s_rx.src_height) {
    watch_vrx_configure_decoder(in_w, in_h);
  }
  if (!s_rx.jpeg_decoder) return; /* 当前分辨率不可显示 */

  jpeg_dec_io_t io = {
      .inbuf = data,
      .inbuf_len = (int)size,
      .inbuf_remain = 0,
      .outbuf = NULL,
      .out_size = 0,
  };
  jpeg_dec_header_info_t info = {0};
  if (jpeg_dec_parse_header(s_rx.jpeg_decoder, &io, &info) != JPEG_ERR_OK) {
    ESP_LOGW(TAG, "jpeg parse header failed");
    return;
  }

  // 输出缓冲：按解码器给出的尺寸（含 scale 后的输出）分配，16 字节对齐（S3 软解码要求）。
  // 缓冲可复用，尺寸不变时不重分配。
  //
  // 不能用 jpeg_calloc_align：反汇编 esp_jpeg_memory.c.obj 可见它首选
  // caps=0x804（MALLOC_CAP_INTERNAL|MALLOC_CAP_8BIT），失败才回落 0x404（PSRAM）。
  // 320x240 RGB565 = 150KB，启动后 internal 正好还有这么大的连续块，于是被它吃掉，
  // internal 从 ~165KB 掉到 ~33KB，接听时音频任务创建失败（"failed to create audio
  // task"），整条媒体链路起不来——上行无视频、屏幕也因摄像头未初始化而不亮。
  // 这里显式指定 PSRAM。
  int outbuf_len = 0;
  if (jpeg_dec_get_outbuf_len(s_rx.jpeg_decoder, &outbuf_len) != JPEG_ERR_OK || outbuf_len <= 0) {
    ESP_LOGW(TAG, "jpeg get outbuf len failed");
    return;
  }
  if (!s_rx.jpeg_outbuf || s_rx.jpeg_outbuf_size < outbuf_len) {
    if (s_rx.jpeg_outbuf) {
      heap_caps_free(s_rx.jpeg_outbuf);
      s_rx.jpeg_outbuf = NULL;
    }
    s_rx.jpeg_outbuf = (uint8_t *)heap_caps_aligned_calloc(16, 1, (size_t)outbuf_len,
                                                           MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_rx.jpeg_outbuf) {
      ESP_LOGE(TAG, "cannot alloc %d bytes for jpeg decode", outbuf_len);
      return;
    }
    s_rx.jpeg_outbuf_size = outbuf_len;
  }

  // 解码
  uint64_t decode_start_us = (uint64_t)esp_timer_get_time();
  io.outbuf = s_rx.jpeg_outbuf;
  io.out_size = outbuf_len;
  if (jpeg_dec_process(s_rx.jpeg_decoder, &io) != JPEG_ERR_OK) {
    ESP_LOGW(TAG, "jpeg decode failed");
    return;
  }
  uint64_t decode_us = (uint64_t)esp_timer_get_time() - decode_start_us;

  // 送屏：display_width/height 是解码输出尺寸（原始即面板尺寸，或 scale 后的面板尺寸）。
  // 再核对一次实际输出字节数，配置与输出不一致时不刷屏，避免把错位数据画上去。
#if WATCH_VRX_SPI_DISPLAY
  if (s_rx.display_width == WATCH_LCD_WIDTH && s_rx.display_height == WATCH_LCD_HEIGHT &&
      outbuf_len == WATCH_LCD_WIDTH * WATCH_LCD_HEIGHT * 2) {
    // 屏幕原本只在摄像头初始化（接听）时才点亮；远端视频往往在接听前就到了
    // （对端拨号即推流），此时屏未初始化，draw 会静默失败。这里按需初始化，
    // 重复调用安全。依赖的 I2C 总线（LCD_CS 在 PCA9557 上）在 watch_start 时已建好。
    static bool display_failed_logged = false;
    if (watch_display_esp_init() == 0) {
      if (watch_display_esp_draw_rgb565((const uint16_t *)s_rx.jpeg_outbuf, s_rx.display_width,
                                        s_rx.display_height) == 0) {
        s_rx.last_display_us = esp_timer_get_time();
      }
    } else if (!display_failed_logged) {
      ESP_LOGW(TAG, "display init failed; remote video decoded but not shown");
      display_failed_logged = true;
    }
  }
#endif

  // 解码耗时统计
  ++s_rx.decoded_frames;
  s_rx.decode_total_us += decode_us;
  if (decode_us > s_rx.decode_max_us) s_rx.decode_max_us = decode_us;
  if (s_rx.decoded_frames % 50 == 0) {
    ESP_LOGI(TAG, "mjpeg decode stat: frames=%lu dropped=%lu avg=%llums max=%llums",
             (unsigned long)s_rx.decoded_frames, (unsigned long)s_rx.dropped_frames,
             s_rx.decode_total_us / s_rx.decoded_frames / 1000, s_rx.decode_max_us / 1000);
  }
}

// 按需扩容 PSRAM 缓冲（只增不减，避免每帧 malloc/free 造成碎片）。
static bool watch_vrx_ensure_buf(uint8_t **buf, size_t *cap, size_t need) {
  if (*buf && *cap >= need) return true;
  size_t new_cap = need + need / 4; /* 留 25% 余量，JPEG 帧大小随画面波动 */
  uint8_t *p = (uint8_t *)heap_caps_malloc(new_cap, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
  if (!p) return false;
  if (*buf) heap_caps_free(*buf);
  *buf = p;
  *cap = new_cap;
  return true;
}

static void watch_vrx_task(void *arg) {
  (void)arg;
  while (!s_rx.task_stop) {
    if (xSemaphoreTake(s_rx.mbox_signal, pdMS_TO_TICKS(500)) != pdTRUE) continue;
    if (s_rx.task_stop) break;

    // 把 pending 与 working 交换：锁内只做指针交换，解码在锁外进行，
    // 回调线程拿锁的时间与帧大小无关。
    size_t len = 0;
    xSemaphoreTake(s_rx.mbox_lock, portMAX_DELAY);
    if (s_rx.pending_len > 0) {
      uint8_t *tmp_buf = s_rx.working_buf;
      size_t tmp_cap = s_rx.working_cap;
      s_rx.working_buf = s_rx.pending_buf;
      s_rx.working_cap = s_rx.pending_cap;
      s_rx.pending_buf = tmp_buf;
      s_rx.pending_cap = tmp_cap;
      len = s_rx.pending_len;
      s_rx.pending_len = 0;
    }
    xSemaphoreGive(s_rx.mbox_lock);

    // esp_new_jpeg 内部分配失败时不判空（实测 jpeg_dec_process_scale 里 EXCVADDR=0
    // 直接 LoadProhibited），所以 PSRAM 告急时宁可丢帧也不进解码器。
    if (len > 0 && heap_caps_get_free_size(MALLOC_CAP_SPIRAM) < 512 * 1024) {
      s_rx.dropped_frames++;
      static int64_t last_warn_us = 0;
      int64_t now = esp_timer_get_time();
      if (now - last_warn_us > 1000 * 1000) {
        ESP_LOGW(TAG, "psram low (%u B), skip decode", (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
        last_warn_us = now;
      }
      continue;
    }
    if (len > 0) watch_vrx_decode_mjpeg(s_rx.working_buf, len);
  }
  s_rx.task_exited = true;
  vTaskDeleteWithCaps(NULL);
}

static int watch_vrx_start_task(void) {
  if (s_rx.task) return 0;
  if (!s_rx.mbox_lock) s_rx.mbox_lock = xSemaphoreCreateMutex();
  if (!s_rx.mbox_signal) s_rx.mbox_signal = xSemaphoreCreateBinary();
  if (!s_rx.mbox_lock || !s_rx.mbox_signal) {
    ESP_LOGE(TAG, "cannot create mailbox semaphores");
    return -1;
  }
  s_rx.task_stop = false;
  s_rx.task_exited = false;
  if (xTaskCreatePinnedToCoreWithCaps(watch_vrx_task, "watch_vrx", WATCH_VRX_TASK_STACK, NULL,
                                      WATCH_VRX_TASK_PRIORITY, &s_rx.task, WATCH_VRX_TASK_CORE,
                                      MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) != pdPASS) {
    ESP_LOGE(TAG, "cannot create watch_vrx task");
    s_rx.task = NULL;
    return -1;
  }
  return 0;
}

// 回调线程（TRTC main_loop）：只拷贝 + 投递，不解码。
static void watch_vrx_post_mjpeg(const uint8_t *data, size_t size) {
  if (!s_rx.task && watch_vrx_start_task() != 0) return;
  xSemaphoreTake(s_rx.mbox_lock, portMAX_DELAY);
  if (s_rx.pending_len > 0) s_rx.dropped_frames++; /* 任务没来得及处理上一帧，覆盖之 */
  if (watch_vrx_ensure_buf(&s_rx.pending_buf, &s_rx.pending_cap, size)) {
    memcpy(s_rx.pending_buf, data, size);
    s_rx.pending_len = size;
  } else {
    s_rx.pending_len = 0;
  }
  xSemaphoreGive(s_rx.mbox_lock);
  xSemaphoreGive(s_rx.mbox_signal);
}

bool watch_video_receiver_esp_is_active(void) {
  int64_t last = s_rx.last_display_us;
  return last != 0 && (esp_timer_get_time() - last) < WATCH_VRX_ACTIVE_WINDOW_US;
}

void watch_video_receiver_esp_on_frame(const tc_iot_video_frame *frame) {
  // 诊断：每 5 秒打印 TRTC 交到本层的远端视频帧数，与 TRTC 侧 vjb(5s) out= 对照。
  {
    static uint32_t s_cb_frames;
    static int64_t s_cb_last_us;
    s_cb_frames++;
    int64_t now_us = esp_timer_get_time();
    if (s_cb_last_us == 0) s_cb_last_us = now_us;
    if (now_us - s_cb_last_us >= 5000000) {
      ESP_LOGI(TAG, "rx cb(5s): frames=%u codec=%d size=%u", (unsigned)s_cb_frames,
               frame ? (int)frame->codec : -1, frame ? (unsigned)frame->data_size : 0u);
      s_cb_frames = 0;
      s_cb_last_us = now_us;
    }
  }
  if (!frame || !frame->data || frame->data_size == 0) return;

  if (frame->codec == TC_IOT_VIDEO_CODEC_MJPEG) {
#if WATCH_VRX_BOARD_DISPLAY
    // av_device_playout_mjpg 只拷贝到单槽并唤醒其显示任务，立即返回，不阻塞收包线程。
    av_device_playout_mjpg(frame->data, (uint32_t)frame->data_size);
    s_rx.last_display_us = esp_timer_get_time();
#else
    watch_vrx_post_mjpeg(frame->data, frame->data_size);
#endif
    return;
  }
  if (frame->codec != TC_IOT_VIDEO_CODEC_H264) {
    ESP_LOGW(TAG, "unsupported remote codec=%d", (int)frame->codec);
    return;
  }
  if (!s_rx.decoder && watch_video_receiver_esp_init() != 0) return;

  esp_h264_dec_in_frame_t in_frame = {
      .raw_data = {.buffer = frame->data, .len = (uint32_t)frame->data_size},
  };
  esp_h264_dec_out_frame_t out_frame = {0};

  while (in_frame.raw_data.len > 0) {
    uint64_t decode_start_us = (uint64_t)esp_timer_get_time();
    esp_h264_err_t err = esp_h264_dec_process(s_rx.decoder, &in_frame, &out_frame);
    uint64_t decode_us = (uint64_t)esp_timer_get_time() - decode_start_us;
    if (err != ESP_H264_ERR_OK) {
      ESP_LOGW(TAG, "esp_h264_dec_process failed: %d", (int)err);
      break;
    }
    // consume 为 0 时避免死循环（防御性处理）
    if (in_frame.consume == 0) {
      ESP_LOGW(TAG, "decoder consumed 0 bytes, dropping rest");
      break;
    }
    in_frame.raw_data.buffer += in_frame.consume;
    in_frame.raw_data.len -= in_frame.consume;

    if (out_frame.out_size == 0 || !out_frame.outbuf) {
      continue; /* SPS/PPS 等非图像数据，无输出 */
    }

    // 读取解码分辨率（首帧确定，之后不变）
    if (s_rx.src_width == 0 || s_rx.src_height == 0) {
      esp_h264_dec_param_handle_t param = NULL;
      if (esp_h264_dec_sw_get_param_hd(s_rx.decoder, &param) == ESP_H264_ERR_OK && param) {
        esp_h264_resolution_t res = {0};
        if (esp_h264_dec_get_resolution(param, &res) == ESP_H264_ERR_OK) {
          s_rx.src_width = res.width;
          s_rx.src_height = res.height;
          ESP_LOGI(TAG, "remote video resolution: %dx%d", s_rx.src_width, s_rx.src_height);
#if WATCH_VRX_SPI_DISPLAY
          // 屏幕切到远端画面：关掉本地预览，避免两个源争抢同一块屏。
          watch_camera_esp_set_preview(false);
#endif
        }
      }
    }
    if (s_rx.src_width <= 0 || s_rx.src_height <= 0) continue;

    uint32_t width = (uint32_t)s_rx.src_width;
    uint32_t height = (uint32_t)s_rx.src_height;

    // 转换 + 送屏。当前假设远端分辨率等于屏尺寸（320x240 横屏），不匹配时仅提示。
    // S31 板级屏只接 MJPEG（硬件解码），H.264 解码结果不送屏。
#if WATCH_VRX_SPI_DISPLAY
    if (width == WATCH_LCD_WIDTH && height == WATCH_LCD_HEIGHT) {
      if (ensure_rgb565_buffer((int)width, (int)height) == 0) {
        const uint8_t *y_plane = out_frame.outbuf;
        const uint8_t *u_plane = y_plane + width * height;
        const uint8_t *v_plane = u_plane + (width * height) / 4;
        for (uint32_t y = 0; y < height; y++) {
          uint16_t *dst = s_rx.rgb565_buffer + y * width;
          const uint8_t *yrow = y_plane + y * width;
          const uint8_t *urow = u_plane + (y / 2) * (width / 2);
          const uint8_t *vrow = v_plane + (y / 2) * (width / 2);
          for (uint32_t x = 0; x < width; x++) {
            int u = urow[x / 2];
            int v = vrow[x / 2];
            dst[x] = i420_to_rgb565_px(yrow[x], u, v);
          }
        }
        watch_display_esp_draw_rgb565(s_rx.rgb565_buffer, width, height);
      }
    } else {
      static int warned = 0;
      if (!warned) {
        ESP_LOGW(TAG, "remote %ux%u != panel %dx%d, skipping display (needs scale/rotate)",
                 (unsigned)width, (unsigned)height, WATCH_LCD_WIDTH, WATCH_LCD_HEIGHT);
        warned = 1;
      }
    }
#endif

    // 解码耗时统计
    ++s_rx.decoded_frames;
    s_rx.decode_total_us += decode_us;
    if (decode_us > s_rx.decode_max_us) s_rx.decode_max_us = decode_us;
    if (s_rx.decoded_frames % 50 == 0) {
      ESP_LOGI(TAG, "decode stat: frames=%lu avg=%llums max=%llums",
               (unsigned long)s_rx.decoded_frames, s_rx.decode_total_us / s_rx.decoded_frames / 1000,
               s_rx.decode_max_us / 1000);
    }
  }
}

void watch_video_receiver_esp_deinit(void) {
  // 先停解码任务：解码器与输出缓冲只在任务里用，任务退出后才能释放。
  if (s_rx.task) {
    s_rx.task_stop = true;
    if (s_rx.mbox_signal) xSemaphoreGive(s_rx.mbox_signal);
    for (int i = 0; i < 100 && !s_rx.task_exited; i++) vTaskDelay(pdMS_TO_TICKS(10));
    if (!s_rx.task_exited) ESP_LOGW(TAG, "watch_vrx task did not exit in 1s");
    s_rx.task = NULL;
  }
  if (s_rx.pending_buf) heap_caps_free(s_rx.pending_buf);
  if (s_rx.working_buf) heap_caps_free(s_rx.working_buf);
  s_rx.pending_buf = s_rx.working_buf = NULL;
  s_rx.pending_cap = s_rx.working_cap = s_rx.pending_len = 0;
  s_rx.dropped_frames = 0;
  s_rx.last_display_us = 0;
  if (s_rx.decoder) {
    esp_h264_dec_close(s_rx.decoder);
    esp_h264_dec_del(s_rx.decoder);
    s_rx.decoder = NULL;
  }
  if (s_rx.jpeg_decoder) {
    jpeg_dec_close(s_rx.jpeg_decoder);
    s_rx.jpeg_decoder = NULL;
  }
  if (s_rx.jpeg_outbuf) {
    heap_caps_free(s_rx.jpeg_outbuf);
    s_rx.jpeg_outbuf = NULL;
    s_rx.jpeg_outbuf_size = 0;
  }
  if (s_rx.rgb565_buffer) {
    heap_caps_free(s_rx.rgb565_buffer);
    s_rx.rgb565_buffer = NULL;
    s_rx.rgb565_capacity = 0;
  }
  s_rx.src_width = s_rx.src_height = 0;
  s_rx.display_width = s_rx.display_height = 0;
  s_rx.decoded_frames = 0;
  s_rx.decode_total_us = 0;
  s_rx.decode_max_us = 0;
}
