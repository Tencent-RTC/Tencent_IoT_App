// Copyright (c) 2026 Tencent. All rights reserved.
//
// av_device 的 ESP32-S31-Korvo-1 实现。
//   - 摄像头：sc101iot DVP 直出 YUV422(UYVY)（V4L2 / esp_video），经
//     esp_video_init_with_flags(DVP) 探测、O_RDWR 打开、mmap 缓冲；DQBUF 得到的原始
//     YUV422 帧再经 P4 硬件 JPEG 编码器（esp_driver_jpeg）压成 JPEG，以 MJPEG 上抛。
//   - 音频：ES8389（I2S STD），通过 esp_codec_dev 采集 / 播放。采集与播放均按上层
//     契约以 16kHz / 单声道 / 16-bit 打开。
//

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>

#include "av_device.h"
#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/i2s_std.h"
#include "driver/jpeg_decode.h"
#include "driver/jpeg_encode.h"
#include "driver/ppa.h"
#include "esp_cam_ctlr_dvp.h"
#include "esp_cam_sensor_xclk.h"
#include "esp_check.h"
#include "esp_codec_dev.h"
#include "esp_codec_dev_defaults.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_rgb.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_video_device.h"
#include "esp_video_init.h"
#include "esp_video_ioctl.h"
#include "freertos/FreeRTOS.h"
#include "freertos/idf_additions.h"
#include "freertos/semphr.h"
#include "freertos/stream_buffer.h"
#include "freertos/task.h"
#include "linux/videodev2.h"

#define TAG "av_esp"

/* ==================== 板级 BSP（内联自官方 esp32_s31_korvo BSP，media-only） ====================
 * I2C 主机总线 / sc101iot DVP 摄像头(V4L2·esp_video) / ES8389 音频(I2S STD) 三块能力，
 * 初始化序列与官方 factory_demo 逐字一致（相同引脚、XCLK/SCCB 频率、esp_video_init(DVP)、
 * O_RDWR 打开）。刻意剔除 LCD/触摸/SD/按键/LED/LVGL 等无关外设依赖。 */

// 板级引脚 / 频率（板型 esp32_s31_korvo_1）。I2C 总线由音频 Codec 与摄像头 SCCB 共用。
#define BSP_I2C_SDA (GPIO_NUM_0)
#define BSP_I2C_SCL (GPIO_NUM_1)
#define BSP_AUDIO_I2S_MCLK (GPIO_NUM_2)
#define BSP_AUDIO_I2S_SCLK (GPIO_NUM_3)
#define BSP_AUDIO_I2S_LRCLK (GPIO_NUM_4)
#define BSP_AUDIO_I2S_SDOUT (GPIO_NUM_5)
#define BSP_AUDIO_I2S_DSIN (GPIO_NUM_6)
#define BSP_AUDIO_PA_CTRL (GPIO_NUM_7)
#define BSP_CAMERA_D0 (GPIO_NUM_46)
#define BSP_CAMERA_D1 (GPIO_NUM_47)
#define BSP_CAMERA_D2 (GPIO_NUM_48)
#define BSP_CAMERA_D3 (GPIO_NUM_49)
#define BSP_CAMERA_D4 (GPIO_NUM_50)
#define BSP_CAMERA_D5 (GPIO_NUM_51)
#define BSP_CAMERA_D6 (GPIO_NUM_52)
#define BSP_CAMERA_D7 (GPIO_NUM_53)
#define BSP_CAMERA_PCLK (GPIO_NUM_54)
#define BSP_CAMERA_XCLK (GPIO_NUM_55)
#define BSP_CAMERA_VSYNC (GPIO_NUM_56)
#define BSP_CAMERA_HSYNC (GPIO_NUM_57)
#define BSP_CAMERA_PWDN (GPIO_NUM_NC)
#define BSP_CAMERA_RESET (GPIO_NUM_NC)

// 音频 I2S 通道默认参数（实际采样率/声道由随后 esp_codec_dev_open 指定，不影响上层）。
#define BSP_AUDIO_DEFAULT_SAMPLE_RATE (48000)
#define BSP_AUDIO_DEFAULT_BITS_PER_SAMPLE (16)
// 摄像头默认频率与缓冲数。
#define BSP_CAMERA_DEFAULT_XCLK_FREQ_HZ (20 * 1000 * 1000)
#define BSP_CAMERA_DEFAULT_SCCB_FREQ_HZ (10 * 1000)
#define BSP_CAMERA_BUFFER_COUNT (2)

// 采集配置：像素格式固定 UYVY（sc101iot 只出 YUV422）。
typedef struct {
  uint32_t width;
  uint32_t height;
  uint32_t xclk_freq_hz;
} bsp_camera_config_t;

typedef struct {
  void *data;      // 帧数据指针
  size_t size;     // 帧字节数
  uint32_t index;  // 内部 V4L2 缓冲索引
} bsp_camera_frame_t;

typedef struct {
  uint32_t width;
  uint32_t height;
  uint32_t pixelformat;
  uint32_t bytesperline;
  uint32_t sizeimage;
} bsp_camera_format_t;

typedef struct bsp_camera_t {
  void *video_buffer[BSP_CAMERA_BUFFER_COUNT];
  size_t video_buffer_length[BSP_CAMERA_BUFFER_COUNT];
  uint32_t frame_size;
  int video_fd;
  bool video_initialized;
  bool started;
  // 缓冲是否已在驱动的 queued_list 里。esp_video 的 STREAMOFF 会清空队列
  // （esp_video_stop_capture: TAILQ_INIT + esp_video_buffer_reset），再次 STREAMON 前必须重新 QBUF，
  // 否则 DQBUF 永远等不到帧（实测：挂断后第二通电话无视频上行，采集任务卡死、停不下来）。
  bool buffers_queued;
  uint32_t buffer_count;
  bool first_frame_logged;
  bsp_camera_config_t config;
  bsp_camera_format_t format;
  struct v4l2_buffer dqbuf;
} bsp_camera_t;

static i2c_master_bus_handle_t s_i2c_bus;
static i2s_chan_handle_t s_audio_tx_chan;
static i2s_chan_handle_t s_audio_rx_chan;
static const audio_codec_data_if_t *s_audio_data_if;

static esp_err_t bsp_i2c_init(void);
static esp_err_t bsp_audio_init(void);
static esp_codec_dev_handle_t bsp_audio_codec_speaker_init(void);
static esp_codec_dev_handle_t bsp_audio_codec_microphone_init(void);
static esp_err_t bsp_camera_open(const bsp_camera_config_t *config, bsp_camera_t **ret_camera);
static esp_err_t bsp_camera_start(bsp_camera_t *camera);
static esp_err_t bsp_camera_stop(bsp_camera_t *camera);
static esp_err_t bsp_camera_get_frame(bsp_camera_t *camera, bsp_camera_frame_t *frame);
static esp_err_t bsp_camera_return_frame(bsp_camera_t *camera, const bsp_camera_frame_t *frame);
static esp_err_t bsp_camera_get_format(bsp_camera_t *camera, bsp_camera_format_t *out_format);
static esp_err_t bsp_camera_close(bsp_camera_t *camera);

// --- I2C（音频 Codec 与摄像头 SCCB 共享同一主机总线） ---
static esp_err_t bsp_i2c_init(void) {
  if (s_i2c_bus) {
    return ESP_OK;
  }
  const i2c_master_bus_config_t i2c_bus_config = {
      .clk_source = I2C_CLK_SRC_DEFAULT,
      .sda_io_num = BSP_I2C_SDA,
      .scl_io_num = BSP_I2C_SCL,
      .i2c_port = I2C_NUM_0,
      .flags.enable_internal_pullup = true,
  };
  ESP_RETURN_ON_ERROR(i2c_new_master_bus(&i2c_bus_config, &s_i2c_bus), TAG,
                      "create I2C bus failed");
  ESP_LOGI(TAG, "I2C bus initialized: SDA=%d, SCL=%d", BSP_I2C_SDA, BSP_I2C_SCL);
  return ESP_OK;
}

// --- 音频（ES8389，I2S STD）：固定 48k 立体声建立通道 ---
static esp_err_t bsp_audio_init(void) {
  if (s_audio_data_if) {
    return ESP_OK;
  }
  i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  // 停写后自动送 0：默认 auto_clear=false，没有新数据时 TX DMA 会循环发送最后几块缓冲
  // （6x240 帧 ≈ 90ms），挂断后扬声器反复播放最后一小段声音。
  chan_cfg.auto_clear_after_cb = true;
  ESP_RETURN_ON_ERROR(i2s_new_channel(&chan_cfg, &s_audio_tx_chan, &s_audio_rx_chan), TAG,
                      "create I2S channels failed");
  const i2s_std_config_t std_cfg = {
      .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(BSP_AUDIO_DEFAULT_SAMPLE_RATE),
      .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(BSP_AUDIO_DEFAULT_BITS_PER_SAMPLE,
                                                      I2S_SLOT_MODE_STEREO),
      .gpio_cfg =
          {
              .mclk = BSP_AUDIO_I2S_MCLK,
              .bclk = BSP_AUDIO_I2S_SCLK,
              .ws = BSP_AUDIO_I2S_LRCLK,
              .dout = BSP_AUDIO_I2S_SDOUT,
              .din = BSP_AUDIO_I2S_DSIN,
          },
  };
  ESP_RETURN_ON_ERROR(i2s_channel_init_std_mode(s_audio_tx_chan, &std_cfg), TAG,
                      "init I2S TX std mode failed");
  ESP_RETURN_ON_ERROR(i2s_channel_init_std_mode(s_audio_rx_chan, &std_cfg), TAG,
                      "init I2S RX std mode failed");
  ESP_RETURN_ON_ERROR(i2s_channel_enable(s_audio_tx_chan), TAG, "enable I2S TX failed");
  ESP_RETURN_ON_ERROR(i2s_channel_enable(s_audio_rx_chan), TAG, "enable I2S RX failed");

  audio_codec_i2s_cfg_t i2s_data_cfg = {
      .port = I2S_NUM_0,
      .tx_handle = s_audio_tx_chan,
      .rx_handle = s_audio_rx_chan,
  };
  s_audio_data_if = audio_codec_new_i2s_data(&i2s_data_cfg);
  ESP_RETURN_ON_FALSE(s_audio_data_if, ESP_FAIL, TAG, "create audio I2S data interface failed");
  ESP_LOGI(TAG, "Audio I2S initialized");
  return ESP_OK;
}

static esp_codec_dev_handle_t bsp_audio_codec_init(esp_codec_dev_type_t dev_type,
                                                   esp_codec_dec_work_mode_t codec_mode,
                                                   int16_t pa_pin) {
  esp_err_t ret = bsp_i2c_init();
  if (ret != ESP_OK) {
    ESP_LOGE(TAG, "I2C init failed (%s)", esp_err_to_name(ret));
    return NULL;
  }
  ret = bsp_audio_init();
  if (ret != ESP_OK) {
    ESP_LOGE(TAG, "audio init failed (%s)", esp_err_to_name(ret));
    return NULL;
  }

  const audio_codec_gpio_if_t *gpio_if = audio_codec_new_gpio();
  ESP_RETURN_ON_FALSE(gpio_if, NULL, TAG, "create codec GPIO interface failed");
  audio_codec_i2c_cfg_t i2c_cfg = {
      .port = I2C_NUM_0,
      .addr = ES8389_CODEC_DEFAULT_ADDR,
      .bus_handle = s_i2c_bus,
  };
  const audio_codec_ctrl_if_t *ctrl_if = audio_codec_new_i2c_ctrl(&i2c_cfg);
  ESP_RETURN_ON_FALSE(ctrl_if, NULL, TAG, "create codec I2C control interface failed");

  esp_codec_dev_hw_gain_t gain = {
      .pa_voltage = 5.0f,
      .codec_dac_voltage = 3.3f,
  };
  es8389_codec_cfg_t es8389_cfg = {
      .ctrl_if = ctrl_if,
      .gpio_if = gpio_if,
      .codec_mode = codec_mode,
      .pa_pin = pa_pin,
      .pa_reverted = false,
      .master_mode = false,
      .use_mclk = false,
      .digital_mic = false,
      .invert_mclk = false,
      .invert_sclk = false,
      .hw_gain = gain,
      .no_dac_ref = false,
  };
  const audio_codec_if_t *codec_if = es8389_codec_new(&es8389_cfg);
  ESP_RETURN_ON_FALSE(codec_if, NULL, TAG, "create ES8389 codec interface failed");

  esp_codec_dev_cfg_t codec_dev_cfg = {
      .dev_type = dev_type,
      .codec_if = codec_if,
      .data_if = s_audio_data_if,
  };
  return esp_codec_dev_new(&codec_dev_cfg);
}

static esp_codec_dev_handle_t bsp_audio_codec_speaker_init(void) {
  return bsp_audio_codec_init(ESP_CODEC_DEV_TYPE_OUT, ESP_CODEC_DEV_WORK_MODE_DAC,
                              BSP_AUDIO_PA_CTRL);
}

static esp_codec_dev_handle_t bsp_audio_codec_microphone_init(void) {
  return bsp_audio_codec_init(ESP_CODEC_DEV_TYPE_IN, ESP_CODEC_DEV_WORK_MODE_ADC, GPIO_NUM_NC);
}

// --- 摄像头（sc101iot DVP，V4L2/esp_video，直出 UYVY） ---
static esp_err_t bsp_camera_video_ioctl(int fd, unsigned long request, void *arg,
                                        const char *name) {
  int ret = ioctl(fd, request, arg);
  ESP_RETURN_ON_FALSE(ret == 0, ESP_FAIL, TAG, "esp-video %s failed", name);
  return ESP_OK;
}

static void bsp_camera_fill_dvp_pins(esp_cam_ctlr_dvp_pin_config_t *pin_cfg) {
  *pin_cfg = (esp_cam_ctlr_dvp_pin_config_t){
      .data_width = 8,
      .data_io =
          {
              BSP_CAMERA_D0,
              BSP_CAMERA_D1,
              BSP_CAMERA_D2,
              BSP_CAMERA_D3,
              BSP_CAMERA_D4,
              BSP_CAMERA_D5,
              BSP_CAMERA_D6,
              BSP_CAMERA_D7,
          },
      .vsync_io = BSP_CAMERA_VSYNC,
      .de_io = BSP_CAMERA_HSYNC,
      .pclk_io = BSP_CAMERA_PCLK,
      .xclk_io = BSP_CAMERA_XCLK,
  };
}

static esp_err_t bsp_camera_video_init(bsp_camera_t *camera) {
  ESP_RETURN_ON_ERROR(bsp_i2c_init(), TAG, "camera shared I2C init failed");

  esp_cam_ctlr_dvp_pin_config_t dvp_pin = {0};
  bsp_camera_fill_dvp_pins(&dvp_pin);

  // 只初始化 DVP 分支（避免 FLAGS_ALL 连带初始化 ISP/UVC/H264/JPEG 时任一失败即回滚，
  // 把已探测成功的 DVP 一起拆掉）；SCCB 复用共享 I2C（init_sccb=false + i2c_handle）。
  esp_video_init_dvp_config_t dvp_config = {
      .sccb_config =
          {
              .init_sccb = false,
              .i2c_handle = s_i2c_bus,
              .freq = BSP_CAMERA_DEFAULT_SCCB_FREQ_HZ,
          },
      .reset_pin = BSP_CAMERA_RESET,
      .pwdn_pin = BSP_CAMERA_PWDN,
      .dvp_pin = dvp_pin,
      .xclk_freq = camera->config.xclk_freq_hz,
  };
  esp_video_init_config_t video_config = {
      .dvp = &dvp_config,
  };
  ESP_LOGI(TAG, "Initializing camera: dev=%s, shared_i2c=1, xclk=%" PRIu32,
           ESP_VIDEO_DVP_DEVICE_NAME, camera->config.xclk_freq_hz);
  ESP_RETURN_ON_ERROR(esp_video_init_with_flags(&video_config, ESP_VIDEO_INIT_FLAGS_DVP), TAG,
                      "esp-video DVP init failed");
  camera->video_initialized = true;

  // V4L2 以 O_RDWR 打开（S_FMT / REQBUFS / mmap 写映射均需写权限）。
  camera->video_fd = open(ESP_VIDEO_DVP_DEVICE_NAME, O_RDWR);
  ESP_RETURN_ON_FALSE(camera->video_fd >= 0, ESP_FAIL, TAG, "open %s failed",
                      ESP_VIDEO_DVP_DEVICE_NAME);

  struct v4l2_format format = {
      .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
  };
  format.fmt.pix.width = camera->config.width;
  format.fmt.pix.height = camera->config.height;
  format.fmt.pix.pixelformat = V4L2_PIX_FMT_UYVY;
  ESP_RETURN_ON_ERROR(bsp_camera_video_ioctl(camera->video_fd, VIDIOC_S_FMT, &format, "S_FMT"), TAG,
                      "esp-video set format failed");

  camera->format.width = format.fmt.pix.width;
  camera->format.height = format.fmt.pix.height;
  camera->format.pixelformat = format.fmt.pix.pixelformat;
  camera->format.bytesperline = format.fmt.pix.bytesperline;
  camera->format.sizeimage = format.fmt.pix.sizeimage;
  camera->frame_size = format.fmt.pix.sizeimage;
  ESP_LOGI(TAG,
           "Camera format: %" PRIu32 "x%" PRIu32 ", fourcc=%c%c%c%c, stride=%" PRIu32
           ", size=%" PRIu32,
           camera->format.width, camera->format.height, (char)(camera->format.pixelformat & 0xff),
           (char)((camera->format.pixelformat >> 8) & 0xff),
           (char)((camera->format.pixelformat >> 16) & 0xff),
           (char)((camera->format.pixelformat >> 24) & 0xff), camera->format.bytesperline,
           camera->format.sizeimage);

  struct v4l2_requestbuffers req = {
      .count = BSP_CAMERA_BUFFER_COUNT,
      .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
      .memory = V4L2_MEMORY_MMAP,
  };
  ESP_RETURN_ON_ERROR(bsp_camera_video_ioctl(camera->video_fd, VIDIOC_REQBUFS, &req, "REQBUFS"),
                      TAG, "esp-video request buffers failed");
  ESP_RETURN_ON_FALSE(req.count > 0 && req.count <= BSP_CAMERA_BUFFER_COUNT, ESP_FAIL, TAG,
                      "unexpected esp-video buffer count: %" PRIu32, req.count);

  for (uint32_t i = 0; i < req.count; i++) {
    struct v4l2_buffer buf = {
        .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
        .memory = V4L2_MEMORY_MMAP,
        .index = i,
    };
    ESP_RETURN_ON_ERROR(bsp_camera_video_ioctl(camera->video_fd, VIDIOC_QUERYBUF, &buf, "QUERYBUF"),
                        TAG, "esp-video query buffer failed");
    void *mapped_buffer =
        mmap(NULL, buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, camera->video_fd, buf.m.offset);
    ESP_RETURN_ON_FALSE(mapped_buffer && mapped_buffer != MAP_FAILED, ESP_FAIL, TAG,
                        "esp-video mmap buffer %" PRIu32 " failed", i);
    camera->video_buffer[i] = mapped_buffer;
    camera->video_buffer_length[i] = buf.length;
    ESP_RETURN_ON_ERROR(bsp_camera_video_ioctl(camera->video_fd, VIDIOC_QBUF, &buf, "QBUF"), TAG,
                        "esp-video queue buffer failed");
    ESP_LOGI(TAG, "Camera buffer[%" PRIu32 "]: ptr=%p, length=%" PRIu32, i, camera->video_buffer[i],
             buf.length);
  }
  camera->buffer_count = req.count;
  camera->buffers_queued = true;

  // DQBUF 默认无限等待（dqbuf_timeout_ticks=portMAX_DELAY）。设上限后，即使 sensor 不出帧，
  // 采集任务也能定期醒来检查停止标志并退出，不会卡死。
  struct timeval dqbuf_timeout = {.tv_sec = 1, .tv_usec = 0};
  if (ioctl(camera->video_fd, VIDIOC_S_DQBUF_TIMEOUT, &dqbuf_timeout) != 0) {
    ESP_LOGW(TAG, "esp-video set DQBUF timeout failed (capture stop may block)");
  }
  return ESP_OK;
}

static esp_err_t bsp_camera_open(const bsp_camera_config_t *config, bsp_camera_t **ret_camera) {
  ESP_RETURN_ON_FALSE(config && ret_camera, ESP_ERR_INVALID_ARG, TAG,
                      "invalid camera open argument");
  *ret_camera = NULL;

  bsp_camera_t *camera =
      heap_caps_calloc(1, sizeof(*camera), MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  ESP_RETURN_ON_FALSE(camera, ESP_ERR_NO_MEM, TAG, "no memory for camera context");
  camera->config = *config;
  camera->video_fd = -1;

  esp_err_t ret = bsp_camera_video_init(camera);
  ESP_GOTO_ON_ERROR(ret, error, TAG, "esp-video camera init failed");
  *ret_camera = camera;
  return ESP_OK;

error:
  bsp_camera_close(camera);
  return ret;
}

static esp_err_t bsp_camera_start(bsp_camera_t *camera) {
  ESP_RETURN_ON_FALSE(camera, ESP_ERR_INVALID_ARG, TAG, "camera handle is null");
  if (camera->started) {
    return ESP_OK;
  }
  if (!camera->buffers_queued) {
    for (uint32_t i = 0; i < camera->buffer_count; i++) {
      struct v4l2_buffer buf = {
          .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
          .memory = V4L2_MEMORY_MMAP,
          .index = i,
      };
      ESP_RETURN_ON_ERROR(bsp_camera_video_ioctl(camera->video_fd, VIDIOC_QBUF, &buf, "QBUF"), TAG,
                          "esp-video re-queue buffer %" PRIu32 " failed", i);
    }
    camera->buffers_queued = true;
  }
  int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  ESP_RETURN_ON_ERROR(bsp_camera_video_ioctl(camera->video_fd, VIDIOC_STREAMON, &type, "STREAMON"),
                      TAG, "esp-video stream on failed");
  camera->started = true;
  camera->first_frame_logged = false;
  ESP_LOGI(TAG, "Camera stream started");
  return ESP_OK;
}

static esp_err_t bsp_camera_stop(bsp_camera_t *camera) {
  ESP_RETURN_ON_FALSE(camera, ESP_ERR_INVALID_ARG, TAG, "camera handle is null");
  if (!camera->started) {
    return ESP_OK;
  }
  int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  ESP_RETURN_ON_ERROR(
      bsp_camera_video_ioctl(camera->video_fd, VIDIOC_STREAMOFF, &type, "STREAMOFF"), TAG,
      "esp-video stream off failed");
  camera->started = false;
  camera->buffers_queued = false;  // STREAMOFF 已清空驱动队列，下次 start 需重新 QBUF
  ESP_LOGI(TAG, "Camera stream stopped");
  return ESP_OK;
}

static esp_err_t bsp_camera_get_frame(bsp_camera_t *camera, bsp_camera_frame_t *frame) {
  ESP_RETURN_ON_FALSE(camera && frame, ESP_ERR_INVALID_ARG, TAG, "invalid get frame argument");
  ESP_RETURN_ON_FALSE(camera->started, ESP_ERR_INVALID_STATE, TAG, "camera stream is not started");

  memset(&camera->dqbuf, 0, sizeof(camera->dqbuf));
  camera->dqbuf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  camera->dqbuf.memory = V4L2_MEMORY_MMAP;
  ESP_RETURN_ON_ERROR(
      bsp_camera_video_ioctl(camera->video_fd, VIDIOC_DQBUF, &camera->dqbuf, "DQBUF"), TAG,
      "esp-video dequeue buffer failed");
  ESP_RETURN_ON_FALSE(
      camera->dqbuf.index < BSP_CAMERA_BUFFER_COUNT && camera->video_buffer[camera->dqbuf.index],
      ESP_FAIL, TAG, "esp-video invalid dequeued buffer index: %" PRIu32, camera->dqbuf.index);

  if (!camera->first_frame_logged) {
    ESP_LOGI(TAG, "Camera first frame: index=%" PRIu32 ", bytes=%" PRIu32 ", length=%" PRIu32,
             camera->dqbuf.index, camera->dqbuf.bytesused, camera->dqbuf.length);
    camera->first_frame_logged = true;
  }

  frame->data = camera->video_buffer[camera->dqbuf.index];
  frame->size = camera->dqbuf.bytesused ? camera->dqbuf.bytesused : camera->frame_size;
  frame->index = camera->dqbuf.index;
  return ESP_OK;
}

static esp_err_t bsp_camera_return_frame(bsp_camera_t *camera, const bsp_camera_frame_t *frame) {
  ESP_RETURN_ON_FALSE(camera && frame, ESP_ERR_INVALID_ARG, TAG, "invalid return frame argument");
  ESP_RETURN_ON_FALSE(frame->index < BSP_CAMERA_BUFFER_COUNT, ESP_ERR_INVALID_ARG, TAG,
                      "invalid camera buffer index: %u", (unsigned int)frame->index);
  struct v4l2_buffer buf = {
      .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
      .memory = V4L2_MEMORY_MMAP,
      .index = frame->index,
  };
  return bsp_camera_video_ioctl(camera->video_fd, VIDIOC_QBUF, &buf, "QBUF");
}

static esp_err_t bsp_camera_get_format(bsp_camera_t *camera, bsp_camera_format_t *out_format) {
  ESP_RETURN_ON_FALSE(camera && out_format, ESP_ERR_INVALID_ARG, TAG,
                      "invalid camera format argument");
  *out_format = camera->format;
  return ESP_OK;
}

static esp_err_t bsp_camera_close(bsp_camera_t *camera) {
  if (!camera) {
    return ESP_OK;
  }
  if (camera->started) {
    (void)bsp_camera_stop(camera);
  }
  for (int i = 0; i < BSP_CAMERA_BUFFER_COUNT; i++) {
    if (camera->video_buffer[i]) {
      (void)munmap(camera->video_buffer[i], camera->video_buffer_length[i]);
      camera->video_buffer[i] = NULL;
    }
  }
  if (camera->video_fd >= 0) {
    (void)close(camera->video_fd);
    camera->video_fd = -1;
  }
  if (camera->video_initialized) {
    (void)esp_video_deinit_with_flags(ESP_VIDEO_INIT_FLAGS_DVP);
    camera->video_initialized = false;
  }
  heap_caps_free(camera);
  return ESP_OK;
}

/* ==================== 参数 ==================== */

// 音频：上层契约为单声道 16kHz 20ms/帧（MIC_FRAME_BYTES = 640）。
#define AV_ESP_CODEC_BITS_PER_SAMPLE 16
// ES8389 是立体声播录一体 Codec，该板 DAC→功放→喇叭走立体声通路。若以单声道打开，
// I2S 仅填充一个 slot，喇叭所在物理声道拿不到数据 → 完全无声（官方 BSP 默认即 stereo=2）。
// 因此 Codec 固定以 2 声道打开；上层仍是单声道契约：采集后下混为单声道、播放前上混为立体声。
#define AV_ESP_CODEC_CHANNELS 2
#define AV_ESP_ES8389_OUT_VOL 60
#define AV_ESP_ES8389_MIC_GAIN_DB 30.0f

// 音频采集任务。
#define AV_ESP_AUDIO_TASK_STACK (8 * 1024)
#define AV_ESP_AUDIO_TASK_PRIORITY 5
#define AV_ESP_AUDIO_STOP_WAIT_MS 1000

// 视频采集任务。
#define AV_ESP_VIDEO_TASK_STACK (8 * 1024)
#define AV_ESP_VIDEO_TASK_PRIORITY 5
#define AV_ESP_VIDEO_STOP_WAIT_MS 1000

// 本硬件搭载 sc101iot（PID 0xda4a），纯 DVP YUV422 sensor，不带 JPEG 直出编码器。
// 采集按 1280x720(720p) UYVY 取原始 YUV422 帧，再经 P4 硬件 JPEG 编码器（esp_driver_jpeg）
// 压成 JPEG，以 MJPEG 格式推给 RTC（每帧独立关键帧）。
// 注意：esp_video 的 VIDIOC_S_FMT 不允许改分辨率，宽高必须等于传感器当前默认格式
// （见 esp_video_device_common.c: common_video_set_format），否则报
// "input width=..., height=... is not supported"。1280x720 是所有 sc101iot 驱动版本都提供
// 的格式（index 0），需在固件 sdkconfig 中启用
// CONFIG_CAMERA_SC101IOT_DVP_DEFAULT_FMT_YUV422_1280X720_15FPS=y（INDEX_DEFAULT=0）。
#define AV_ESP_CAM_WIDTH 1280
#define AV_ESP_CAM_HEIGHT 720

// JPEG 编码质量：q85（较高画质）。UYVY 属 YUV422，子采样按 YUV422，每像素 2 字节（16bpp）。
// 注意：质量越高单帧字节数越大、上行码率越高；若发送队列溢出/RTT 升高可回调（如 55~70）。
#ifndef AV_ESP_JPEG_QUALITY
#define AV_ESP_JPEG_QUALITY 65
#endif
#define AV_ESP_YUV422_BYTES_PER_PIXEL 2

// 上行输出分辨率与帧率上限。默认等于 sensor 原始 720p、不限帧率（iot demo 行为不变）。
// watch 固件在 cmd_iot_demo/CMakeLists.txt 里覆盖（640x360 / 10fps / 低质量）：720p MJPEG
// 单帧数十 KB，15fps 远超 TRTC 上行视频限速 SEND_VIDEO_MAX_bps（2.4Mbps）。
// 输出尺寸与 sensor 不同时，先由 PPA（硬件 SRM）缩放 UYVY，再交 JPEG 编码器，不占 CPU。
// 宽须为 16 的倍数、高须为 8 的倍数（YUV422 JPEG 的 MCU 为 16x8）。
#ifndef AV_ESP_UPLINK_WIDTH
#define AV_ESP_UPLINK_WIDTH AV_ESP_CAM_WIDTH
#endif
#ifndef AV_ESP_UPLINK_HEIGHT
#define AV_ESP_UPLINK_HEIGHT AV_ESP_CAM_HEIGHT
#endif
// 0 = 不限（按 sensor 帧率出帧）；>0 时超出的帧直接归还、不编码。
#ifndef AV_ESP_UPLINK_MAX_FPS
#define AV_ESP_UPLINK_MAX_FPS 0
#endif
// JPEG 编码超时（ms）：需大于单帧有效编码时间；给 200ms 富余，避免偶发抖动误判超时。
#define AV_ESP_JPEG_ENC_TIMEOUT_MS 200

/* ==================== LCD 显示（下行视频） ====================
 * ESP32-S31-Korvo-1 主板不自带屏，需外接 ESP32-S3-LCD-EV-Board-SUB3（4.3"）。
 * 该子板为 16-bit 并口 RGB 面板（RGB565），无需 SPI/厂商初始化序列，直接配置
 * RGB 时序即可点亮。以下引脚/时序逐字对齐官方 esp32_s31_korvo BSP
 * （include/bsp/display.h 与 include/bsp/esp32_s31_korvo.h，板型 esp32_s31_korvo_1）。
 * 背光/DISP 在该板上为 GPIO_NC（常亮，无需控制）。 */
#define AV_ESP_LCD_H_RES 800U
#define AV_ESP_LCD_V_RES 480U
#define AV_ESP_LCD_PIXEL_CLOCK_HZ (26 * 1000 * 1000)
#define AV_ESP_LCD_DATA_WIDTH 16U
#define AV_ESP_LCD_BITS_PER_PIXEL 16U
#define AV_ESP_LCD_HSYNC_PULSE_WIDTH 1U
#define AV_ESP_LCD_HSYNC_BACK_PORCH 40U
#define AV_ESP_LCD_HSYNC_FRONT_PORCH 20U
#define AV_ESP_LCD_VSYNC_PULSE_WIDTH 1U
#define AV_ESP_LCD_VSYNC_BACK_PORCH 10U
#define AV_ESP_LCD_VSYNC_FRONT_PORCH 5U

// RGB 数据线 DB0..DB15（对应面板 B3..B7/G2..G7/R3..R7）。
#define AV_ESP_LCD_DATA0 GPIO_NUM_8
#define AV_ESP_LCD_DATA1 GPIO_NUM_9
#define AV_ESP_LCD_DATA2 GPIO_NUM_10
#define AV_ESP_LCD_DATA3 GPIO_NUM_11
#define AV_ESP_LCD_DATA4 GPIO_NUM_12
#define AV_ESP_LCD_DATA5 GPIO_NUM_13
#define AV_ESP_LCD_DATA6 GPIO_NUM_14
#define AV_ESP_LCD_DATA7 GPIO_NUM_15
#define AV_ESP_LCD_DATA8 GPIO_NUM_16
#define AV_ESP_LCD_DATA9 GPIO_NUM_17
#define AV_ESP_LCD_DATA10 GPIO_NUM_18
#define AV_ESP_LCD_DATA11 GPIO_NUM_19
#define AV_ESP_LCD_DATA12 GPIO_NUM_33
#define AV_ESP_LCD_DATA13 GPIO_NUM_34
#define AV_ESP_LCD_DATA14 GPIO_NUM_35
#define AV_ESP_LCD_DATA15 GPIO_NUM_36
#define AV_ESP_LCD_PCLK GPIO_NUM_40
#define AV_ESP_LCD_DE GPIO_NUM_43
#define AV_ESP_LCD_HSYNC GPIO_NUM_44
#define AV_ESP_LCD_VSYNC GPIO_NUM_45
#define AV_ESP_LCD_DISP_EN GPIO_NUM_NC

// 下行视频分辨率：对端下行 640x480(横屏)，与本机上行同分辨率。P4 硬件 JPEG 解码器不支持
// 解码降采样，必须按全分辨率解出 RGB565，故解码缓冲按 640x480 分配；分辨率异于预期(更大)
// 的下行帧会在 render 内被安全丢弃(告警)。
#define AV_ESP_DOWNLINK_WIDTH 640U
#define AV_ESP_DOWNLINK_HEIGHT 480U
// 解码 RGB565 缓冲（640x480x2≈614KB，落 PSRAM）。640/480 均为 16 的倍数，无额外对齐 padding。
#define AV_ESP_LCD_DECODE_BYTES (AV_ESP_DOWNLINK_WIDTH * AV_ESP_DOWNLINK_HEIGHT * sizeof(uint16_t))
// 合成缓冲：面板尺寸 RGB565(800x480x2=750KB)。640x480 画面写入其居中子区（左右各 80px
// 黑边、纵向铺满），整屏一次 draw_bitmap 上屏（单帧缓冲面板，避免残留上一帧内容）。
#define AV_ESP_LCD_PANEL_BYTES (AV_ESP_LCD_H_RES * AV_ESP_LCD_V_RES * sizeof(uint16_t))
// 下行 JPEG 最大受理字节数：与单槽缓冲(AV_ESP_VIDEO_SLOT_BYTES)对齐；640x480 MJPEG 单帧
// 常见数十~百余 KB，按 256KB 留足余量，否则 render 直接判为过大丢弃。
#define AV_ESP_LCD_MAX_JPEG_BYTES (256U * 1024U)

/* ==================== 全局状态 ==================== */

static bool audio_hardware_initialized = false;
static volatile bool audio_started = false;
static volatile bool audio_task_running = false;
static TaskHandle_t audio_task_handle = NULL;
static audio_device_callback_t audio_callback = NULL;
static void *audio_callback_context = NULL;

// ES8389 播录一体：分别派生 OUT（扬声器）与 IN（麦克风）两个 esp_codec_dev 句柄。
static esp_codec_dev_handle_t speaker_codec_device = NULL;
static esp_codec_dev_handle_t microphone_codec_device = NULL;

// 采集：Codec 以立体声读取（每样本 2 声道），取左声道下混为单声道后上抛。
// capture_stereo_buffer 容纳一帧立体声，字节数 = 2 * MIC_FRAME_BYTES（= MIC_FRAME_BYTES 个 int16）。
static int16_t capture_stereo_buffer[MIC_FRAME_BYTES];
static uint8_t capture_buffer[MIC_FRAME_BYTES];  // 下混后的单声道上抛帧（20ms/640B）

// 播放：远端单声道上混为立体声（L=R）后写入 Codec，分块处理任意长度的下行帧。
#define AV_ESP_PLAYOUT_STEREO_CHUNK_SAMPLES 512
static int16_t playback_stereo_buffer[AV_ESP_PLAYOUT_STEREO_CHUNK_SAMPLES * AV_ESP_CODEC_CHANNELS];

// 下行音频播放诊断计数。
static uint32_t audio_playback_received_frame_count = 0;
static uint32_t audio_playback_discard_frame_count = 0;
static uint32_t audio_playback_write_fail_frame_count = 0;

// 视频（DVP 摄像头，经 bsp_camera）。
static bool camera_initialized = false;
static bsp_camera_t *camera_handle = NULL;
static video_device_callback_t video_callback = NULL;
static void *video_callback_context = NULL;
static volatile bool video_stream_activate = false;
static TaskHandle_t video_task_handle = NULL;
static uint32_t camera_width = 0;
static uint32_t camera_height = 0;

// P4 硬件 JPEG 编码器：把 sensor 直出的 YUV422(UYVY) 帧压成 JPEG。
static jpeg_encoder_handle_t jpeg_encoder = NULL;
static uint8_t *jpeg_out_buffer = NULL;
static size_t jpeg_out_buffer_size = 0;

// 上行缩放（PPA SRM，UYVY -> UYVY）。uplink_width/height 为实际编码尺寸；
// 与 camera_width/height 相同时不缩放，uplink_ppa 为 NULL。
static ppa_client_handle_t uplink_ppa = NULL;
static uint8_t *uplink_scale_buffer = NULL;
static size_t uplink_scale_buffer_size = 0;
static uint32_t uplink_width = 0;
static uint32_t uplink_height = 0;

// LCD 显示（下行视频）：16-bit RGB565 面板 + 硬件 JPEG 解码器。
static bool lcd_initialized = false;
static esp_lcd_panel_handle_t lcd_panel = NULL;
static bool lcd_video_playout_initialized = false;
static SemaphoreHandle_t lcd_video_lock = NULL;
static uint8_t *lcd_video_rgb565_buffer = NULL;  // JPEG 解码输出缓冲（全分辨率上限）
static uint8_t *lcd_video_draw_buffer = NULL;    // 面板尺寸合成缓冲（画面居中 + 黑边）
static jpeg_decoder_handle_t lcd_video_jpeg_decoder = NULL;
static jpeg_decode_cfg_t lcd_video_jpeg_decode_config;
static uint32_t lcd_video_drop_count = 0;
// 上一帧在面板上的绘制尺寸（放大后）。尺寸变化时整屏清黑，避免残留旧画面的边缘。
static uint32_t lcd_video_last_draw_w = 0;
static uint32_t lcd_video_last_draw_h = 0;
// PPA 显示路径：缩放后直接写进面板 framebuffer（lcd_video_fb 归面板所有，不释放）。
static ppa_client_handle_t lcd_video_ppa = NULL;
static uint8_t *lcd_video_fb = NULL;
static bool lcd_video_ppa_failed = false;

/* ==================== 下行异步播放（视频显示 / 音频播放） ====================
 * 下行帧原先在 SDK 主循环(message_loop)线程内同步解码+绘制、同步写 I2S，单帧耗时可达
 * 上百毫秒，直接拖慢 SDK 收发/心跳，推高 RTT 与端到端时延。此处把两条下行播放链路都改为
 * “主循环仅投递 + 独立任务消费”：
 *   - 视频：主循环把最新一帧 JPEG 拷入单槽缓冲(覆盖旧帧=自动追最新帧)并唤醒显示任务，
 *           解码/居中/draw_bitmap 全在 av_esp_disp 任务里执行。
 *   - 音频：主循环把 PCM 写入 StreamBuffer，上混+阻塞写 Codec 在 av_esp_ply 任务里执行。
 * 两个 playout 接口调用后立即返回，主循环不再被解码/I2S 阻塞。 */

// 下行音频播放任务 + 缓冲（StreamBuffer 存单声道 S16LE 字节流）。
#define AV_ESP_AUDIO_PLAYOUT_TASK_STACK (4 * 1024)
#define AV_ESP_AUDIO_PLAYOUT_TASK_PRIORITY 5
// ~1s 单声道 16kHz 16-bit 缓冲（32000B/s）：足够吸收抖动又不过度堆积延迟。
#define AV_ESP_AUDIO_PLAYOUT_STREAM_BYTES (32 * 1024)
// 每次从 StreamBuffer 取出的最大单声道字节数（= 一个上混 chunk），512 样本 ≈ 32ms。
#define AV_ESP_AUDIO_PLAYOUT_READ_BYTES (AV_ESP_PLAYOUT_STEREO_CHUNK_SAMPLES * sizeof(int16_t))

static StreamBufferHandle_t audio_playout_stream = NULL;
static TaskHandle_t audio_playout_task_handle = NULL;
static volatile bool audio_playout_task_running = false;
// 请求播放任务丢弃缓冲里尚未播放的下行音频（最多约 1s）。通话结束时置位。
// 不能直接 xStreamBufferReset：播放任务阻塞在 Receive 上时 Reset 会失败。
static volatile bool audio_playout_flush_req = false;

// 下行视频显示任务 + 单槽最新帧缓冲。
#define AV_ESP_VIDEO_PLAYOUT_TASK_STACK (6 * 1024)
#define AV_ESP_VIDEO_PLAYOUT_TASK_PRIORITY 4
// 单帧下行 JPEG 上限：下行 640x480 MJPEG 单帧常见数十~百余 KB，按 256KB 留足余量；
// 超过则丢弃并告警。slot + work 双缓冲共占 2×256KB。
#define AV_ESP_VIDEO_SLOT_BYTES (256 * 1024)

static TaskHandle_t video_playout_task_handle = NULL;
static volatile bool video_playout_task_running = false;
static bool video_playout_started = false;
static SemaphoreHandle_t video_slot_lock = NULL;
static uint8_t *video_slot_buffer = NULL;  // 生产者(主循环)写入的最新帧
static uint8_t *video_work_buffer = NULL;  // 消费者(显示任务)解码用
static volatile size_t video_slot_len = 0;
static volatile bool video_slot_pending = false;
static uint32_t video_slot_drop_count = 0;

/* ==================== 前置声明 ==================== */

static esp_err_t _audio_open(void);
static void _audio_close(void);
static int _camera_open(void);
static void _camera_close(void);
static esp_err_t _jpeg_encoder_open(uint32_t width, uint32_t height);
static void _jpeg_encoder_close(void);
static esp_err_t _uplink_scaler_open(void);
static void _uplink_scaler_close(void);
static void _get_microphone_audio_stream(void *arg);
static void _get_camera_video_stream(void *arg);

// 下行异步播放
static void _audio_write_codec(const uint8_t *mono_data, size_t len);
static esp_err_t _audio_playout_start(void);
static void _audio_playout_stop(void);
static void _audio_playout_task(void *arg);
static esp_err_t _video_playout_start(void);
static void _video_playout_stop(void);
static void _video_playout_task(void *arg);

// LCD 显示内部实现
static esp_err_t _lcd_open(void);
static void _lcd_close(void);
static esp_err_t _jpeg_decoder_init(void);
static void _jpeg_decoder_deinit(void);
static esp_err_t _lcd_video_playout_open(void);
static void _lcd_video_playout_close(void);
static esp_err_t _lcd_video_playout_render(const uint8_t *jpeg_data, size_t jpeg_data_length);

/* ==================== 内存诊断 ==================== */

// 打印内部 SRAM 与 PSRAM 的【可用总量 free / 最大连续块 largest】，用于观测摄像头、LCD、
// 麦克风、扬声器等大块内存消费者在开/关前后的内存占用变化（largest 反映碎片程度）。
// 在每个开/关动作的前后各调用一次，两条日志相减即为该动作的内存增量。
static void _av_log_mem(const char *stage) {
  ESP_LOGI(TAG, "[MEM] %-22s internal free=%u largest=%u | psram free=%u largest=%u", stage,
           (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
           (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL),
           (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM),
           (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM));
}

/* ==================== 公开接口 ==================== */

// 外设开关（默认全开，iot demo 行为不变）。watch 固件按 WATCH_ENABLE_CAMERA /
// WATCH_ENABLE_DISPLAY 传入（见 cmd_iot_demo/CMakeLists.txt）：关掉的外设不初始化，
// 不占 PSRAM（LCD framebuffer 750KB、摄像头缓冲 3.6MB）、不占 DMA 带宽。
#ifndef AV_DEVICE_ENABLE_LCD
#define AV_DEVICE_ENABLE_LCD 1
#endif
#ifndef AV_DEVICE_ENABLE_CAMERA
#define AV_DEVICE_ENABLE_CAMERA 1
#endif

void av_device_init(const av_device_config_t *cfg) {
  (void)cfg;
  if (audio_hardware_initialized && (camera_initialized || !AV_DEVICE_ENABLE_CAMERA)) {
    return;
  }

#if AV_DEVICE_ENABLE_LCD
  // LCD 独立于音视频采集，尽早初始化用于显示远端下行画面；失败不阻断音视频。
  if (!lcd_initialized) {
    esp_err_t lcd_err = _lcd_open();
    if (lcd_err != ESP_OK) {
      ESP_LOGW(TAG, "LCD init failed: %s (downlink video display disabled)",
               esp_err_to_name(lcd_err));
    }
  }
#endif

#if AV_DEVICE_ENABLE_CAMERA
  // 初始化顺序对齐官方 factory_demo：先摄像头、后音频。官方在同款硬件上正是此顺序
  // 可正常出图——让摄像头先建立并占用共享 I2C（GPIO0/1）、先启动 DVP XCLK，再初始化
  // I2S 音频，避免音频外设先占用总线/时钟资源影响 sensor 探测。
  if (!camera_initialized) {
    if (_camera_open() == 0) {
      camera_initialized = true;
      ESP_LOGI(TAG, "camera initialized: sensor %ux%u -> JPEG %ux%u max_fps=%d q%d",
               (unsigned)camera_width, (unsigned)camera_height, (unsigned)uplink_width,
               (unsigned)uplink_height, AV_ESP_UPLINK_MAX_FPS, AV_ESP_JPEG_QUALITY);
    } else {
      ESP_LOGW(TAG, "camera init failed, video capture disabled");
    }
  }
#endif

  if (!audio_hardware_initialized) {
    esp_err_t err = _audio_open();
    if (err != ESP_OK) {
      ESP_LOGW(TAG, "audio init failed: %s", esp_err_to_name(err));
      _audio_close();
      return;
    }
    audio_hardware_initialized = true;
    ESP_LOGI(TAG, "audio initialized: %d-bit %dch %dHz (I2S STD, ES8389)",
             AV_ESP_CODEC_BITS_PER_SAMPLE, AV_ESP_CODEC_CHANNELS, MIC_SAMPLE_RATE);
  }
}

void av_device_deinit(void) {
  if (audio_started) {
    audio_task_running = false;
    int wait = AV_ESP_AUDIO_STOP_WAIT_MS / 20;
    while (audio_task_handle != NULL && wait-- > 0) {
      vTaskDelay(pdMS_TO_TICKS(20));
    }
    audio_started = false;
  }

  if (video_stream_activate) {
    video_stream_activate = false;
    int wait = AV_ESP_VIDEO_STOP_WAIT_MS / 20;
    while (video_task_handle != NULL && wait-- > 0) {
      vTaskDelay(pdMS_TO_TICKS(20));
    }
  }

  _camera_close();
  camera_initialized = false;

  _audio_close();
  audio_hardware_initialized = false;

  _lcd_close();
  ESP_LOGI(TAG, "deinitialized");
}

int av_device_start_audio(const char *audio_file_path, audio_device_callback_t callback,
                          void *user_data) {
  (void)audio_file_path;
  if (!audio_hardware_initialized || !callback) {
    return -1;
  }
  if (!microphone_codec_device) {
    ESP_LOGE(TAG, "mic not ready");
    return -1;
  }
  if (audio_callback && audio_callback == callback && audio_callback_context == user_data) {
    return 0;
  }
  if (audio_callback) {
    ESP_LOGE(TAG, "audio listener already occupied");
    return -1;
  }

  audio_callback = callback;
  audio_callback_context = user_data;

  if (!audio_started) {
    audio_task_running = true;
    audio_started = true;
    // 任务栈从 PSRAM 分配，避免占用紧张的内部 SRAM。
    BaseType_t ok = xTaskCreatePinnedToCoreWithCaps(
        _get_microphone_audio_stream, "av_esp_mic", AV_ESP_AUDIO_TASK_STACK, NULL,
        AV_ESP_AUDIO_TASK_PRIORITY, &audio_task_handle, tskNO_AFFINITY, MALLOC_CAP_SPIRAM);
    if (ok != pdPASS) {
      audio_task_running = false;
      audio_started = false;
      audio_task_handle = NULL;
      audio_callback = NULL;
      audio_callback_context = NULL;
      ESP_LOGE(TAG, "failed to create audio task");
      return -1;
    }
    ESP_LOGI(TAG, "audio capture started: out_frame=%d bytes", MIC_FRAME_BYTES);
  }

  return 0;
}

void av_device_stop_audio(audio_device_callback_t callback, void *user_data) {
  if (!audio_callback || audio_callback != callback || audio_callback_context != user_data) {
    return;
  }

  audio_callback = NULL;
  audio_callback_context = NULL;
  // 采集停止即通话结束：丢掉还没播完的下行音频，不让挂断后扬声器继续出声。
  audio_playout_flush_req = true;

  if (audio_started) {
    audio_task_running = false;
    int wait = AV_ESP_AUDIO_STOP_WAIT_MS / 20;
    while (audio_task_handle != NULL && wait-- > 0) {
      vTaskDelay(pdMS_TO_TICKS(20));
    }
    audio_started = false;
    ESP_LOGI(TAG, "audio capture stopped");
  }
}

void av_device_playout_audio(const uint8_t *data, uint32_t len) {
  static bool s_playout_first_logged = false;

  audio_playback_received_frame_count++;

  if (!audio_hardware_initialized || !speaker_codec_device || !data || len == 0) {
    audio_playback_discard_frame_count++;
    return;
  }

  if (!s_playout_first_logged) {
    ESP_LOGI(TAG, "[PLY] first frame: len=%u", (unsigned)len);
    s_playout_first_logged = true;
  } else if (audio_playback_received_frame_count % 2000 == 0) {
    ESP_LOGI(TAG, "[PLY] count=%u discard=%u fail=%u",
             (unsigned)audio_playback_received_frame_count,
             (unsigned)audio_playback_discard_frame_count,
             (unsigned)audio_playback_write_fail_frame_count);
  }

  // 惰性启动播放任务（首帧下行时）。本接口由 SDK 主循环单线程调用，无并发。
  if (_audio_playout_start() != ESP_OK) {
    audio_playback_discard_frame_count++;
    return;
  }

  const uint32_t aligned = len & ~(uint32_t)(sizeof(int16_t) - 1);  // 对齐到样本
  if (aligned == 0) {
    return;
  }

  // 仅把 PCM 投递到 StreamBuffer，实际上混 + 写 Codec 在播放任务里执行，主循环不阻塞。
  // 空间不足时整帧丢弃（避免半帧写入撕裂），并计入 discard。
  if (xStreamBufferSpacesAvailable(audio_playout_stream) < aligned) {
    audio_playback_discard_frame_count++;
    return;
  }
  (void)xStreamBufferSend(audio_playout_stream, data, aligned, 0);
}

int av_device_start_video(const char *video_file_path, video_device_callback_t callback,
                          void *user_data) {
  (void)video_file_path;
  if (!callback) {
    return -1;
  }
  if (!camera_initialized) {
    ESP_LOGE(TAG, "camera not initialized, call av_device_init first");
    return -1;
  }
  if (video_stream_activate) {
    ESP_LOGW(TAG, "video already running");
    return 0;
  }
  // 上一次的采集任务还没退出（例如卡在 DQBUF）：再建一个任务会两个任务争同一个摄像头。
  // DQBUF 已设 1s 超时，这里最多再等 1.5s。
  for (int i = 0; video_task_handle != NULL && i < 75; i++) {
    vTaskDelay(pdMS_TO_TICKS(20));
  }
  if (video_task_handle != NULL) {
    ESP_LOGE(TAG, "previous video task still running, refuse to start a new one");
    return -1;
  }

  video_callback = callback;
  video_callback_context = user_data;
  video_stream_activate = true;

  if (xTaskCreate(_get_camera_video_stream, "av_esp_cam", AV_ESP_VIDEO_TASK_STACK, NULL,
                  AV_ESP_VIDEO_TASK_PRIORITY, &video_task_handle) != pdPASS) {
    video_stream_activate = false;
    video_callback = NULL;
    ESP_LOGE(TAG, "failed to create video task");
    return -1;
  }
  ESP_LOGI(TAG, "video capture started: sensor %ux%u -> JPEG %ux%u", (unsigned)camera_width,
           (unsigned)camera_height, (unsigned)uplink_width, (unsigned)uplink_height);
  return 0;
}

void av_device_stop_video(video_device_callback_t callback, void *user_data) {
  (void)callback;
  (void)user_data;
  video_stream_activate = false;
  int wait = AV_ESP_VIDEO_STOP_WAIT_MS / 20;
  while (video_task_handle != NULL && wait-- > 0) {
    vTaskDelay(pdMS_TO_TICKS(20));
  }
  if (video_task_handle) {
    ESP_LOGW(TAG, "video task did not exit in time");
  }
}

// 远端下行视频：本平台下行实际为硬件 JPEG(MJPEG)。注意 IoT 封装层填充的 frame->codec
// 取自本机 _sys_device_ability（esp32p4/s31 未设置时默认 H264），与对端真实编码无关，
// 因此下行帧可能被 av_receiver 路由到本函数而非 av_device_playout_mjpg。为与 esp32p4
// 平台行为一致，这里统一交由硬件 JPEG 解码上屏；非 JPEG 数据会在 _lcd_video_playout_render
// 内的 SOI(0xFFD8) 校验处被安全丢弃，不会误解码。
void av_device_playout_video(const uint8_t *data, uint32_t len) {
  av_device_playout_mjpg(data, len);
}

// 远端下行 MJPEG：仅把最新一帧投递到单槽缓冲并唤醒显示任务，硬件解码 + LCD 绘制在
// av_esp_disp 任务里执行，避免阻塞 SDK 主循环。
void av_device_playout_mjpg(const uint8_t *data, uint32_t len) {
  if (data == NULL || len == 0U) {
    return;
  }
  // 快速 SOI 校验：非 JPEG 数据直接丢弃，不占用投递槽（render 内还会再校验一次）。
  if (len < 4U || data[0] != 0xffU || data[1] != 0xd8U) {
    return;
  }
  // 惰性启动显示任务（首帧下行时）。本接口由 SDK 主循环单线程调用，无并发。
  if (_video_playout_start() != ESP_OK) {
    return;
  }
  // 仅把“最新一帧”拷入单槽缓冲；若消费者正持锁拷贝(极短)则丢弃本帧（自动追最新帧），
  // 主循环不等待、不阻塞。
  if (xSemaphoreTake(video_slot_lock, 0) != pdTRUE) {
    ++video_slot_drop_count;
    return;
  }
  bool posted = false;
  if (len <= AV_ESP_VIDEO_SLOT_BYTES) {
    memcpy(video_slot_buffer, data, len);
    video_slot_len = len;
    video_slot_pending = true;
    posted = true;
  } else {
    ++video_slot_drop_count;
    if (video_slot_drop_count == 1U || video_slot_drop_count % 50U == 0U) {
      ESP_LOGW(TAG, "downlink JPEG too large for slot: len=%u cap=%u drops=%u", (unsigned)len,
               (unsigned)AV_ESP_VIDEO_SLOT_BYTES, (unsigned)video_slot_drop_count);
    }
  }
  xSemaphoreGive(video_slot_lock);
  if (posted && video_playout_task_handle != NULL) {
    xTaskNotifyGive(video_playout_task_handle);
  }
}

// MJPEG 每帧均为独立关键帧，无需 IDR 请求。
void av_device_request_idr(void) {}

uint64_t av_device_now_ms(void) {
  return (uint64_t)(esp_timer_get_time() / 1000);
}

// MP4 解封装：硬件平台不支持，返回空桩。
uint64_t av_device_get_mp4_duration_ms(const char *mp4_file_path) {
  (void)mp4_file_path;
  return 0;
}

uint64_t av_device_seek_mp4_ms(uint64_t target_ms) {
  (void)target_ms;
  return 0;
}

// 事件抓拍图（云存 demo 用）：当前不提供独立抓拍链路（避免与实时采集抢占摄像头），
// 显式返回失败，cloud_storage_demo 按 has_pic=false 处理。
int av_device_get_event_picture(uint32_t event_id, uint8_t *buf, uint32_t buf_size,
                                uint32_t *out_len) {
  (void)event_id;
  (void)buf;
  (void)buf_size;
  if (out_len) {
    *out_len = 0;
  }
  return -1;
}

/* ==================== 音频内部实现 ==================== */

static esp_err_t _audio_open(void) {
  _av_log_mem("audio open begin");
  const esp_codec_dev_sample_info_t sample_info = {
      .bits_per_sample = AV_ESP_CODEC_BITS_PER_SAMPLE,
      .channel = AV_ESP_CODEC_CHANNELS,
      .sample_rate = MIC_SAMPLE_RATE,
  };

  // ES8389 为播录一体单芯片：speaker(DAC) 与 mic(ADC) 是操作【同一颗芯片】的两个
  // 独立 esp_codec_dev 实例，esp_codec_dev_open 会写整套芯片寄存器，后 open 者会
  // 覆盖先 open 者的配置。必须与官方 factory_demo 顺序严格一致：
  //   先创建两个句柄 → 先 open mic(ADC) → 后 open speaker(DAC) → 最后统一设增益/音量。
  // 若先 open speaker 再 open mic（旧写法），mic 的 open 会把 speaker 的 DAC/PA 通路
  // 与音量寄存器覆盖掉，导致扬声器完全无声。
  speaker_codec_device = bsp_audio_codec_speaker_init();
  if (!speaker_codec_device) {
    ESP_LOGE(TAG, "speaker codec init failed");
    return ESP_FAIL;
  }
  microphone_codec_device = bsp_audio_codec_microphone_init();
  if (!microphone_codec_device) {
    ESP_LOGE(TAG, "microphone codec init failed");
    return ESP_FAIL;
  }

  int ret =
      esp_codec_dev_open(microphone_codec_device, (esp_codec_dev_sample_info_t *)&sample_info);
  if (ret != ESP_CODEC_DEV_OK) {
    ESP_LOGE(TAG, "open microphone codec failed: %d", ret);
    return ESP_FAIL;
  }
  _av_log_mem("mic opened");
  ret = esp_codec_dev_open(speaker_codec_device, (esp_codec_dev_sample_info_t *)&sample_info);
  if (ret != ESP_CODEC_DEV_OK) {
    ESP_LOGE(TAG, "open speaker codec failed: %d", ret);
    return ESP_FAIL;
  }
  _av_log_mem("speaker opened");

  // 增益/音量在两个 open 全部完成后统一设置，避免被随后的 open 覆盖。
  esp_codec_dev_set_in_gain(microphone_codec_device, AV_ESP_ES8389_MIC_GAIN_DB);
  esp_codec_dev_set_out_vol(speaker_codec_device, AV_ESP_ES8389_OUT_VOL);

  _av_log_mem("audio open done");
  return ESP_OK;
}

static void _audio_close(void) {
  _av_log_mem("audio close begin");
  _audio_playout_stop();
  if (microphone_codec_device) {
    esp_codec_dev_close(microphone_codec_device);
    esp_codec_dev_delete(microphone_codec_device);
    microphone_codec_device = NULL;
  }
  _av_log_mem("mic closed");
  if (speaker_codec_device) {
    esp_codec_dev_close(speaker_codec_device);
    esp_codec_dev_delete(speaker_codec_device);
    speaker_codec_device = NULL;
  }
  _av_log_mem("audio close done");
}

// 音频采集任务：Codec 以立体声 16k 打开，read 得到立体声帧后取左声道（slot0）
// 下混为单声道上抛（保持上层 640B/20ms 单声道契约）。
static void _get_microphone_audio_stream(void *arg) {
  (void)arg;

  const size_t mono_samples = MIC_FRAME_BYTES / sizeof(int16_t);
  const int stereo_bytes = (int)(mono_samples * AV_ESP_CODEC_CHANNELS * sizeof(int16_t));
  int16_t *mono = (int16_t *)capture_buffer;

  while (audio_task_running) {
    int ret = esp_codec_dev_read(microphone_codec_device, capture_stereo_buffer, stereo_bytes);
    if (ret != ESP_CODEC_DEV_OK) {
      vTaskDelay(pdMS_TO_TICKS(10));
      continue;
    }
    for (size_t i = 0; i < mono_samples; ++i) {
      mono[i] = capture_stereo_buffer[i * AV_ESP_CODEC_CHANNELS];
    }
    if (audio_callback && audio_task_running) {
      audio_callback(capture_buffer, MIC_FRAME_BYTES, audio_callback_context);
    }
  }

  audio_task_handle = NULL;
  vTaskDeleteWithCaps(NULL);
}

// 把单声道 S16LE PCM 上混为立体声(L=R)并分块阻塞写入 Codec。仅在播放任务里调用，
// 阻塞的 esp_codec_dev_write 因此不再发生在 SDK 主循环上。
static void _audio_write_codec(const uint8_t *mono_data, size_t len) {
  const size_t aligned = len & ~(size_t)(sizeof(int16_t) - 1);
  if (aligned == 0 || !speaker_codec_device) {
    return;
  }
  const int16_t *mono = (const int16_t *)(const void *)mono_data;
  const size_t total_samples = aligned / sizeof(int16_t);
  for (size_t off = 0; off < total_samples;) {
    size_t n = total_samples - off;
    if (n > AV_ESP_PLAYOUT_STEREO_CHUNK_SAMPLES) {
      n = AV_ESP_PLAYOUT_STEREO_CHUNK_SAMPLES;
    }
    for (size_t i = 0; i < n; ++i) {
      const int16_t s = mono[off + i];
      playback_stereo_buffer[i * AV_ESP_CODEC_CHANNELS] = s;
      playback_stereo_buffer[i * AV_ESP_CODEC_CHANNELS + 1] = s;
    }
    const int out_bytes = (int)(n * AV_ESP_CODEC_CHANNELS * sizeof(int16_t));
    int ret = esp_codec_dev_write(speaker_codec_device, playback_stereo_buffer, out_bytes);
    if (ret != ESP_CODEC_DEV_OK) {
      audio_playback_write_fail_frame_count++;
      ESP_LOGW(TAG, "[PLY] write fail #%u: ret=%d bytes=%d",
               (unsigned)audio_playback_write_fail_frame_count, ret, out_bytes);
      break;
    }
    off += n;
  }
}

// 下行音频播放任务：从 StreamBuffer 取 PCM，上混后写 Codec。阻塞 I2S 写限定在本任务内。
static void _audio_playout_task(void *arg) {
  (void)arg;
  uint8_t mono_chunk[AV_ESP_AUDIO_PLAYOUT_READ_BYTES];
  while (audio_playout_task_running) {
    size_t got = xStreamBufferReceive(audio_playout_stream, mono_chunk, sizeof(mono_chunk),
                                      pdMS_TO_TICKS(100));
    if (audio_playout_flush_req) {
      audio_playout_flush_req = false;
      size_t dropped = got;
      while ((got = xStreamBufferReceive(audio_playout_stream, mono_chunk, sizeof(mono_chunk), 0)) >
             0) {
        dropped += got;
      }
      if (dropped > 0) {
        ESP_LOGI(TAG, "[PLY] flushed %u bytes of pending downlink audio", (unsigned)dropped);
      }
      continue;
    }
    if (got == 0) {
      continue;
    }
    _audio_write_codec(mono_chunk, got);
  }
  audio_playout_task_handle = NULL;
  vTaskDeleteWithCaps(NULL);
}

// 惰性创建播放 StreamBuffer 与任务（首帧下行音频时）。幂等，主循环单线程调用。
static esp_err_t _audio_playout_start(void) {
  if (audio_playout_task_running) {
    return ESP_OK;
  }
  audio_playout_stream =
      xStreamBufferCreateWithCaps(AV_ESP_AUDIO_PLAYOUT_STREAM_BYTES, 1, MALLOC_CAP_SPIRAM);
  if (audio_playout_stream == NULL) {
    ESP_LOGE(TAG, "audio playout stream alloc failed");
    return ESP_ERR_NO_MEM;
  }
  audio_playout_task_running = true;
  BaseType_t ok = xTaskCreatePinnedToCoreWithCaps(
      _audio_playout_task, "av_esp_ply", AV_ESP_AUDIO_PLAYOUT_TASK_STACK, NULL,
      AV_ESP_AUDIO_PLAYOUT_TASK_PRIORITY, &audio_playout_task_handle, tskNO_AFFINITY,
      MALLOC_CAP_SPIRAM);
  if (ok != pdPASS) {
    audio_playout_task_running = false;
    audio_playout_task_handle = NULL;
    vStreamBufferDeleteWithCaps(audio_playout_stream);
    audio_playout_stream = NULL;
    ESP_LOGE(TAG, "failed to create audio playout task");
    return ESP_FAIL;
  }
  ESP_LOGI(TAG, "audio playout task started");
  _av_log_mem("audio playout started");
  return ESP_OK;
}

static void _audio_playout_stop(void) {
  if (audio_playout_task_running) {
    audio_playout_task_running = false;
    int wait = AV_ESP_AUDIO_STOP_WAIT_MS / 20;
    while (audio_playout_task_handle != NULL && wait-- > 0) {
      vTaskDelay(pdMS_TO_TICKS(20));
    }
  }
  if (audio_playout_stream != NULL) {
    vStreamBufferDeleteWithCaps(audio_playout_stream);
    audio_playout_stream = NULL;
  }
  _av_log_mem("audio playout stopped");
}

/* ==================== 视频内部实现 ==================== */

// 摄像头探测失败时的诊断：扫描共享 I2C 总线（GPIO0/1）上所有应答的 7-bit 地址。
// 先不带 XCLK 扫一次（应至少看到 ES8389 0x10，证明总线本身正常），再手动输出 20MHz XCLK
// 扫一次（多数 sensor 无 XCLK 不应答 SCCB）。据此区分：
//   - 带 XCLK 也只有 0x10：sensor 没有应答 -> 排线 / 模组 / 供电问题；
//   - 出现 0x68/0x3c 以外的新地址：模组型号与固件启用的驱动不符（如 0x21=GC0308、0x30=OV2640）。
static void _camera_diag_scan_once(const char *stage) {
  char found[200];
  size_t n = 0;
  found[0] = '\0';
  for (uint16_t addr = 0x08; addr < 0x78; ++addr) {
    if (i2c_master_probe(s_i2c_bus, addr, 20) == ESP_OK && n + 6 < sizeof(found)) {
      n += (size_t)snprintf(found + n, sizeof(found) - n, " 0x%02x", (unsigned)addr);
    }
  }
  ESP_LOGW(TAG, "[CAM-DIAG] i2c scan (%s):%s", stage, n ? found : " (none)");
}

static void _camera_diag_i2c_scan(void) {
  if (bsp_i2c_init() != ESP_OK || !s_i2c_bus) {
    ESP_LOGW(TAG, "[CAM-DIAG] i2c bus unavailable");
    return;
  }
  _camera_diag_scan_once("no xclk");
#if CONFIG_CAMERA_XCLK_USE_LEDC
  esp_cam_sensor_xclk_handle_t xclk = NULL;
  esp_cam_sensor_xclk_config_t xclk_cfg;
  memset(&xclk_cfg, 0, sizeof(xclk_cfg));
  xclk_cfg.ledc_cfg.timer = LEDC_TIMER_0;
  xclk_cfg.ledc_cfg.clk_cfg = LEDC_AUTO_CLK;
  xclk_cfg.ledc_cfg.channel = LEDC_CHANNEL_0;
  xclk_cfg.ledc_cfg.xclk_freq_hz = BSP_CAMERA_DEFAULT_XCLK_FREQ_HZ;
  xclk_cfg.ledc_cfg.xclk_pin = BSP_CAMERA_XCLK;
  if (esp_cam_sensor_xclk_allocate(ESP_CAM_SENSOR_XCLK_LEDC, &xclk) != ESP_OK) {
    ESP_LOGW(TAG, "[CAM-DIAG] xclk allocate failed");
    return;
  }
  if (esp_cam_sensor_xclk_start(xclk, &xclk_cfg) != ESP_OK) {
    ESP_LOGW(TAG, "[CAM-DIAG] xclk start failed");
    esp_cam_sensor_xclk_free(xclk);
    return;
  }
  vTaskDelay(pdMS_TO_TICKS(50));  // sensor 上电后需数 ms~数十 ms 才响应 SCCB
  _camera_diag_scan_once("xclk 20MHz on GPIO55");
  esp_cam_sensor_xclk_stop(xclk);
  esp_cam_sensor_xclk_free(xclk);
#else
  ESP_LOGW(TAG, "[CAM-DIAG] CONFIG_CAMERA_XCLK_USE_LEDC off, skip xclk scan");
#endif
}

static int _camera_open(void) {
  _av_log_mem("camera open begin");
  const bsp_camera_config_t config = {
      .width = AV_ESP_CAM_WIDTH,
      .height = AV_ESP_CAM_HEIGHT,
      .xclk_freq_hz = BSP_CAMERA_DEFAULT_XCLK_FREQ_HZ,
  };

  // sc101iot 只出 YUV422(UYVY)，S_FMT 固定按 UYVY 请求。reset/pwdn 引脚悬空(NC)，单次打开即可。
  esp_err_t err = bsp_camera_open(&config, &camera_handle);
  if (err != ESP_OK || !camera_handle) {
    ESP_LOGE(TAG, "bsp_camera_open failed: %s", esp_err_to_name(err));
    camera_handle = NULL;
    _camera_diag_i2c_scan();
    return -1;
  }

  bsp_camera_format_t format = {0};
  if (bsp_camera_get_format(camera_handle, &format) == ESP_OK) {
    camera_width = format.width;
    camera_height = format.height;
  } else {
    camera_width = AV_ESP_CAM_WIDTH;
    camera_height = AV_ESP_CAM_HEIGHT;
  }

  // 上行尺寸：与 sensor 不同时开 PPA 缩放；缩放器起不来则退回 sensor 原始尺寸（画面仍可用，
  // 只是码率偏高），不让整条视频链路失败。
  uplink_width = camera_width;
  uplink_height = camera_height;
  if ((uint32_t)AV_ESP_UPLINK_WIDTH != camera_width ||
      (uint32_t)AV_ESP_UPLINK_HEIGHT != camera_height) {
    if (_uplink_scaler_open() == ESP_OK) {
      uplink_width = AV_ESP_UPLINK_WIDTH;
      uplink_height = AV_ESP_UPLINK_HEIGHT;
    } else {
      ESP_LOGW(TAG, "uplink scaler unavailable, encoding at sensor size %ux%u",
               (unsigned)camera_width, (unsigned)camera_height);
    }
  }

  // sc101iot 只出原始 YUV422，需经硬件 JPEG 编码器压成 JPEG 才能按 MJPEG 推流。
  if (_jpeg_encoder_open(uplink_width, uplink_height) != ESP_OK) {
    ESP_LOGE(TAG, "jpeg encoder open failed");
    _uplink_scaler_close();
    bsp_camera_close(camera_handle);
    camera_handle = NULL;
    camera_width = 0;
    camera_height = 0;
    uplink_width = 0;
    uplink_height = 0;
    return -1;
  }
  _av_log_mem("camera open done");
  return 0;
}

// PPA SRM 缩放器：sensor UYVY -> 上行尺寸 UYVY。输出缓冲同时是 JPEG 编码器输入，
// 用 jpeg_alloc_encoder_mem 分配：地址与长度按 PSRAM cache line 对齐，满足 PPA 输出的
// 对齐检查（ppa_check_buffer_alignment）和 JPEG 输入的 DMA2D 要求。
//
// 宽高比与 sensor 不同时居中裁剪、不拉伸：取能铺满输出的等比缩放倍数 s，从 sensor 画面
// 正中裁出 out/s 大小的块再缩放。例：
//   640x360（16:9 横屏）：s=1/2，裁剪块 = 整幅 1280x720；
//   400x720（竖屏）     ：s=1，  裁剪块 = 正中 400x720（左右各裁掉 440 列），不缩放。
// PPA 缩放倍数精度为 1/16，s 必须是 1/16 的整数倍，否则输出尺寸会被截断，这里直接拒绝。
static uint32_t uplink_crop_x = 0;
static uint32_t uplink_crop_w = 0;
static uint32_t uplink_crop_y = 0;
static uint32_t uplink_crop_h = 0;
static uint32_t uplink_scale_16 = 16;  // 缩放倍数 * 16

static esp_err_t _uplink_scaler_open(void) {
  const uint32_t out_w = AV_ESP_UPLINK_WIDTH;
  const uint32_t out_h = AV_ESP_UPLINK_HEIGHT;
  if (out_w == 0U || out_h == 0U || out_w > camera_width || out_h > camera_height ||
      (out_w % 16U) != 0U || (out_h % 8U) != 0U) {
    ESP_LOGE(TAG, "invalid uplink size %ux%u (sensor %ux%u; need w%%16==0, h%%8==0, <= sensor)",
             (unsigned)out_w, (unsigned)out_h, (unsigned)camera_width, (unsigned)camera_height);
    return ESP_ERR_INVALID_ARG;
  }
  // s = max(out_w/cam_w, out_h/cam_h)：较大的那个方向铺满，另一方向居中裁剪。
  const bool fit_h = (uint64_t)out_h * camera_width >= (uint64_t)out_w * camera_height;
  const uint32_t num = fit_h ? out_h : out_w;
  const uint32_t den = fit_h ? camera_height : camera_width;
  if ((num * 16U) % den != 0U) {
    ESP_LOGE(TAG, "uplink %ux%u needs scale %u/%u, not a multiple of 1/16 (PPA precision)",
             (unsigned)out_w, (unsigned)out_h, (unsigned)num, (unsigned)den);
    return ESP_ERR_INVALID_ARG;
  }
  uplink_scale_16 = num * 16U / den;
  uplink_crop_w = (out_w * 16U / uplink_scale_16) & ~1U;  // YUV422：宽与 x 偏移须为偶数
  uplink_crop_h = out_h * 16U / uplink_scale_16;
  if (uplink_crop_w > camera_width) uplink_crop_w = camera_width & ~1U;
  if (uplink_crop_h > camera_height) uplink_crop_h = camera_height;
  uplink_crop_x = ((camera_width - uplink_crop_w) / 2U) & ~1U;
  uplink_crop_y = (camera_height - uplink_crop_h) / 2U;
  const ppa_client_config_t client_cfg = {
      .oper_type = PPA_OPERATION_SRM,
      .max_pending_trans_num = 1,
  };
  esp_err_t err = ppa_register_client(&client_cfg, &uplink_ppa);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "ppa_register_client failed: %s", esp_err_to_name(err));
    uplink_ppa = NULL;
    return err;
  }
  const jpeg_encode_memory_alloc_cfg_t mem_cfg = {
      .buffer_direction = JPEG_ENC_ALLOC_INPUT_BUFFER,
  };
  size_t allocated = 0;
  uplink_scale_buffer = (uint8_t *)jpeg_alloc_encoder_mem(
      (size_t)out_w * out_h * AV_ESP_YUV422_BYTES_PER_PIXEL, &mem_cfg, &allocated);
  if (!uplink_scale_buffer) {
    ESP_LOGE(TAG, "uplink scale buffer alloc failed");
    _uplink_scaler_close();
    return ESP_ERR_NO_MEM;
  }
  uplink_scale_buffer_size = allocated;
  ESP_LOGI(TAG, "uplink scaler ready: %ux%u crop %ux%u@(%u,%u) x%u/16 -> %ux%u (PPA SRM, UYVY)",
           (unsigned)camera_width, (unsigned)camera_height, (unsigned)uplink_crop_w,
           (unsigned)uplink_crop_h, (unsigned)uplink_crop_x, (unsigned)uplink_crop_y,
           (unsigned)uplink_scale_16, (unsigned)out_w, (unsigned)out_h);
  return ESP_OK;
}

static void _uplink_scaler_close(void) {
  if (uplink_ppa) {
    ppa_unregister_client(uplink_ppa);
    uplink_ppa = NULL;
  }
  if (uplink_scale_buffer) {
    free(uplink_scale_buffer);
    uplink_scale_buffer = NULL;
  }
  uplink_scale_buffer_size = 0;
}

// 把一帧 sensor UYVY 居中裁剪并缩放到 uplink_scale_buffer（阻塞，硬件完成后返回）。
static esp_err_t _uplink_scale_frame(const void *src) {
  const float scale = (float)uplink_scale_16 / 16.0f;  // 1/16 的整数倍，float 精确表示
  const ppa_srm_oper_config_t srm = {
      .in =
          {
              .buffer = src,
              .pic_w = camera_width,
              .pic_h = camera_height,
              .block_w = uplink_crop_w,
              .block_h = uplink_crop_h,
              .block_offset_x = uplink_crop_x,
              .block_offset_y = uplink_crop_y,
              .srm_cm = PPA_SRM_COLOR_MODE_YUV422_UYVY,
          },
      .out =
          {
              .buffer = uplink_scale_buffer,
              .buffer_size = uplink_scale_buffer_size,
              .pic_w = uplink_width,
              .pic_h = uplink_height,
              .block_offset_x = 0,
              .block_offset_y = 0,
              .srm_cm = PPA_SRM_COLOR_MODE_YUV422_UYVY,
          },
      .rotation_angle = PPA_SRM_ROTATION_ANGLE_0,
      .scale_x = scale,
      .scale_y = scale,
      .mode = PPA_TRANS_MODE_BLOCKING,
  };
  return ppa_do_scale_rotate_mirror(uplink_ppa, &srm);
}

// 创建 P4 硬件 JPEG 编码引擎，并分配一块可复用的 JPEG 输出缓冲。
static esp_err_t _jpeg_encoder_open(uint32_t width, uint32_t height) {
  if (jpeg_encoder) {
    return ESP_OK;
  }

  jpeg_encode_engine_cfg_t engine_cfg = {
      .intr_priority = 0,
      .timeout_ms = AV_ESP_JPEG_ENC_TIMEOUT_MS,
  };
  esp_err_t err = jpeg_new_encoder_engine(&engine_cfg, &jpeg_encoder);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "jpeg_new_encoder_engine failed: %s", esp_err_to_name(err));
    jpeg_encoder = NULL;
    return err;
  }

  // 输出缓冲上限取原始 YUV422 帧大小（width*height*2）：JPEG 压缩后必然更小，足够安全。
  // 用 jpeg_alloc_encoder_mem 分配以满足编码器 DMA/cache 对齐要求。
  size_t want = (size_t)width * height * AV_ESP_YUV422_BYTES_PER_PIXEL;
  jpeg_encode_memory_alloc_cfg_t mem_cfg = {
      .buffer_direction = JPEG_ENC_ALLOC_OUTPUT_BUFFER,
  };
  size_t allocated = 0;
  jpeg_out_buffer = (uint8_t *)jpeg_alloc_encoder_mem(want, &mem_cfg, &allocated);
  if (!jpeg_out_buffer) {
    ESP_LOGE(TAG, "jpeg output buffer alloc failed (%u bytes)", (unsigned)want);
    jpeg_del_encoder_engine(jpeg_encoder);
    jpeg_encoder = NULL;
    return ESP_ERR_NO_MEM;
  }
  jpeg_out_buffer_size = allocated;
  ESP_LOGI(TAG, "jpeg encoder ready: %ux%u YUV422->JPEG q%d, outbuf=%u bytes", (unsigned)width,
           (unsigned)height, AV_ESP_JPEG_QUALITY, (unsigned)jpeg_out_buffer_size);
  return ESP_OK;
}

static void _jpeg_encoder_close(void) {
  if (jpeg_out_buffer) {
    free(jpeg_out_buffer);
    jpeg_out_buffer = NULL;
  }
  jpeg_out_buffer_size = 0;
  if (jpeg_encoder) {
    jpeg_del_encoder_engine(jpeg_encoder);
    jpeg_encoder = NULL;
  }
}

static void _camera_close(void) {
  _av_log_mem("camera close begin");
  _jpeg_encoder_close();
  _uplink_scaler_close();
  if (camera_handle) {
    bsp_camera_close(camera_handle);
    camera_handle = NULL;
  }
  camera_width = 0;
  camera_height = 0;
  uplink_width = 0;
  uplink_height = 0;
  _av_log_mem("camera close done");
  ESP_LOGI(TAG, "camera closed");
}

// 视频采集任务：bsp_camera_get_frame 得到 sensor 直出的 YUV422(UYVY) 帧，（按需经 PPA
// 缩放后）由硬件 JPEG 编码器压成 JPEG，再以 MJPEG 上抛后归还。
static void _get_camera_video_stream(void *arg) {
  (void)arg;
  uint32_t frame_count = 0;
  uint32_t skipped_count = 0;
  // 编码输入固定为 width*height*2 字节（UYVY），不依赖 bytesused。
  const bool scaled = uplink_ppa != NULL;
  const uint32_t yuv_frame_size =
      (uint32_t)uplink_width * uplink_height * AV_ESP_YUV422_BYTES_PER_PIXEL;
  const jpeg_encode_cfg_t enc_cfg = {
      .src_type = JPEG_ENCODE_IN_FORMAT_YUV422,
      .sub_sample = JPEG_DOWN_SAMPLING_YUV422,
      .image_quality = AV_ESP_JPEG_QUALITY,
      .width = uplink_width,
      .height = uplink_height,
  };
  // 帧率上限：按时间片放行，未到点的帧直接归还（不缩放、不编码）。
  // 到点时刻按固定间隔累加（不按放行时刻重算），并允许提前半个间隔放行：sensor 实际出帧
  // 约 11fps（间隔 ~90ms）时，若只容忍几 ms，到点前的那帧总被跳过、只能隔帧放行（实测 7.7fps）。
  const int64_t frame_interval_us = AV_ESP_UPLINK_MAX_FPS > 0 ? 1000000 / AV_ESP_UPLINK_MAX_FPS : 0;
  const int64_t frame_early_us = frame_interval_us / 2;
  int64_t next_due_us = 0;

  if (bsp_camera_start(camera_handle) != ESP_OK) {
    ESP_LOGE(TAG, "bsp_camera_start failed");
    video_stream_activate = false;
    video_task_handle = NULL;
    vTaskDelete(NULL);
    return;
  }

  while (video_stream_activate) {
    bsp_camera_frame_t frame = {0};
    esp_err_t err = bsp_camera_get_frame(camera_handle, &frame);
    if (err != ESP_OK) {
      if (video_stream_activate) {
        vTaskDelay(pdMS_TO_TICKS(10));
      }
      continue;
    }

    if (frame_interval_us > 0 && frame.size != 0) {
      const int64_t now_us = esp_timer_get_time();
      if (next_due_us != 0 && now_us + frame_early_us < next_due_us) {
        ++skipped_count;
        bsp_camera_return_frame(camera_handle, &frame);
        continue;
      }
      // 落后超过一个间隔（如编码偶发变慢）时重新对齐，不追发积压的帧。
      next_due_us = (next_due_us == 0 || now_us - next_due_us > frame_interval_us)
                        ? now_us + frame_interval_us
                        : next_due_us + frame_interval_us;
    }

    const uint8_t *enc_input = (const uint8_t *)frame.data;
    esp_err_t scale_err = ESP_OK;
    if (frame.size != 0 && scaled) {
      scale_err = _uplink_scale_frame(frame.data);
      enc_input = uplink_scale_buffer;
    }

    if (frame.size == 0) {
      ESP_LOGW(TAG, "camera frame empty: index=%u", (unsigned)frame.index);
    } else if (scale_err != ESP_OK) {
      ESP_LOGW(TAG, "uplink scale failed: %s", esp_err_to_name(scale_err));
    } else {
      uint32_t jpeg_size = 0;
      esp_err_t enc_err = jpeg_encoder_process(jpeg_encoder, &enc_cfg, enc_input, yuv_frame_size,
                                               jpeg_out_buffer, jpeg_out_buffer_size, &jpeg_size);
      if (enc_err != ESP_OK || jpeg_size == 0) {
        ESP_LOGW(TAG, "jpeg encode failed: %s size=%u", esp_err_to_name(enc_err),
                 (unsigned)jpeg_size);
      } else {
        frame_count++;
        // MJPEG 每一帧都是独立关键帧，is_key_frame 恒为 true。
        if (video_callback && video_stream_activate) {
          video_callback((const uint8_t *)jpeg_out_buffer, jpeg_size, true,
                         TC_IOT_VIDEO_CODEC_MJPEG, video_callback_context);
        }
        if (frame_count == 1 || frame_count % 150 == 0) {
          ESP_LOGI(TAG, "encoded JPEG %ux%u frames=%u skipped=%u last=%u bytes (yuv=%u)",
                   (unsigned)uplink_width, (unsigned)uplink_height, (unsigned)frame_count,
                   (unsigned)skipped_count, (unsigned)jpeg_size, (unsigned)yuv_frame_size);
        }
      }
    }

    bsp_camera_return_frame(camera_handle, &frame);
  }

  bsp_camera_stop(camera_handle);
  video_task_handle = NULL;
  vTaskDelete(NULL);
}

/* ==================== LCD 显示实现 ==================== */

// 初始化 16-bit RGB565 面板（引脚/时序对齐官方 esp32_s31_korvo BSP）。
static esp_err_t _lcd_open(void) {
  if (lcd_initialized) {
    return ESP_OK;
  }

  _av_log_mem("lcd open begin");
  ESP_LOGI(TAG, "Initializing RGB LCD: %ux%u RGB565, pclk=%d Hz", (unsigned)AV_ESP_LCD_H_RES,
           (unsigned)AV_ESP_LCD_V_RES, AV_ESP_LCD_PIXEL_CLOCK_HZ);

  esp_lcd_rgb_panel_config_t panel_config = {
      .clk_src = LCD_CLK_SRC_DEFAULT,
      .timings =
          {
              .pclk_hz = AV_ESP_LCD_PIXEL_CLOCK_HZ,
              .h_res = AV_ESP_LCD_H_RES,
              .v_res = AV_ESP_LCD_V_RES,
              .hsync_pulse_width = AV_ESP_LCD_HSYNC_PULSE_WIDTH,
              .hsync_back_porch = AV_ESP_LCD_HSYNC_BACK_PORCH,
              .hsync_front_porch = AV_ESP_LCD_HSYNC_FRONT_PORCH,
              .vsync_pulse_width = AV_ESP_LCD_VSYNC_PULSE_WIDTH,
              .vsync_back_porch = AV_ESP_LCD_VSYNC_BACK_PORCH,
              .vsync_front_porch = AV_ESP_LCD_VSYNC_FRONT_PORCH,
              .flags =
                  {
                      .pclk_active_neg = true,
                  },
          },
      .data_width = AV_ESP_LCD_DATA_WIDTH,
      .in_color_format = LCD_COLOR_FMT_RGB565,
      .num_fbs = 1,
      .dma_burst_size = 128,
      .hsync_gpio_num = AV_ESP_LCD_HSYNC,
      .vsync_gpio_num = AV_ESP_LCD_VSYNC,
      .de_gpio_num = AV_ESP_LCD_DE,
      .pclk_gpio_num = AV_ESP_LCD_PCLK,
      .disp_gpio_num = AV_ESP_LCD_DISP_EN,
      .data_gpio_nums =
          {
              AV_ESP_LCD_DATA0,
              AV_ESP_LCD_DATA1,
              AV_ESP_LCD_DATA2,
              AV_ESP_LCD_DATA3,
              AV_ESP_LCD_DATA4,
              AV_ESP_LCD_DATA5,
              AV_ESP_LCD_DATA6,
              AV_ESP_LCD_DATA7,
              AV_ESP_LCD_DATA8,
              AV_ESP_LCD_DATA9,
              AV_ESP_LCD_DATA10,
              AV_ESP_LCD_DATA11,
              AV_ESP_LCD_DATA12,
              AV_ESP_LCD_DATA13,
              AV_ESP_LCD_DATA14,
              AV_ESP_LCD_DATA15,
          },
      .flags =
          {
              .fb_in_psram = true,
          },
  };

  esp_lcd_panel_handle_t panel = NULL;
  esp_err_t err = esp_lcd_new_rgb_panel(&panel_config, &panel);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "create RGB panel failed: %s", esp_err_to_name(err));
    return err;
  }
  err = esp_lcd_panel_reset(panel);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "reset RGB panel failed: %s", esp_err_to_name(err));
    esp_lcd_panel_del(panel);
    return err;
  }
  err = esp_lcd_panel_init(panel);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "init RGB panel failed: %s", esp_err_to_name(err));
    esp_lcd_panel_del(panel);
    return err;
  }

  lcd_panel = panel;
  lcd_initialized = true;
  _av_log_mem("lcd open done");
  ESP_LOGI(TAG, "RGB LCD initialized; incoming MJPEG frames will be decoded and displayed");
  return ESP_OK;
}

static void _lcd_close(void) {
  _av_log_mem("lcd close begin");
  _video_playout_stop();
  _lcd_video_playout_close();
  if (lcd_panel) {
    esp_err_t err = esp_lcd_panel_del(lcd_panel);
    if (err != ESP_OK) {
      ESP_LOGW(TAG, "LCD panel deletion failed: %s", esp_err_to_name(err));
    }
    lcd_panel = NULL;
  }
  lcd_initialized = false;
  _av_log_mem("lcd close done");
}

static esp_err_t _jpeg_decoder_init(void) {
  if (lcd_video_jpeg_decoder) {
    return ESP_OK;
  }
  const jpeg_decode_engine_cfg_t engine_config = {
      .timeout_ms = 100,
  };
  if (jpeg_new_decoder_engine(&engine_config, &lcd_video_jpeg_decoder) != ESP_OK ||
      !lcd_video_jpeg_decoder) {
    ESP_LOGE(TAG, "Failed to create hardware JPEG decoder");
    return ESP_FAIL;
  }
  // 输出 RGB565；rgb_order 取 BGR 与 P4 一致（面板字节序）。若下行画面红蓝对调，
  // 将此处改为 JPEG_DEC_RGB_ELEMENT_ORDER_RGB 即可。
  lcd_video_jpeg_decode_config = (jpeg_decode_cfg_t){
      .output_format = JPEG_DECODE_OUT_FORMAT_RGB565,
      .rgb_order = JPEG_DEC_RGB_ELEMENT_ORDER_BGR,
  };
  return ESP_OK;
}

static void _jpeg_decoder_deinit(void) {
  if (lcd_video_jpeg_decoder) {
    jpeg_del_decoder_engine(lcd_video_jpeg_decoder);
    lcd_video_jpeg_decoder = NULL;
  }
}

// 首帧下行到达时惰性初始化解码器与缓冲，避免无下行时占用 PSRAM。
static esp_err_t _lcd_video_playout_open(void) {
  if (lcd_video_playout_initialized) {
    return ESP_OK;
  }
  if (!lcd_initialized || lcd_panel == NULL) {
    return ESP_ERR_INVALID_STATE;
  }

  esp_err_t err = ESP_OK;
  lcd_video_lock = xSemaphoreCreateMutex();
  if (lcd_video_lock == NULL) {
    err = ESP_ERR_NO_MEM;
    goto fail;
  }

  // 解码输出缓冲：按下行分辨率 640x480 的 RGB565 大小分配（614KB），而非整块面板；
  // 超此像素预算(尺寸异常偏大)的帧由 render 内 need_bytes 校验丢弃。
  lcd_video_rgb565_buffer =
      heap_caps_aligned_alloc(64, AV_ESP_LCD_DECODE_BYTES, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
  if (lcd_video_rgb565_buffer == NULL) {
    lcd_video_rgb565_buffer =
        heap_caps_aligned_alloc(64, AV_ESP_LCD_DECODE_BYTES, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  }
  if (lcd_video_rgb565_buffer == NULL) {
    err = ESP_ERR_NO_MEM;
    goto fail;
  }

  // 面板尺寸合成缓冲只在 CPU 回退路径用到，PPA 路径直接写 framebuffer，由 render 按需分配。

  if (_jpeg_decoder_init() != ESP_OK) {
    err = ESP_FAIL;
    goto fail;
  }

  lcd_video_playout_initialized = true;
  ESP_LOGI(TAG, "LCD video ready: decode up to %ux%u px, fit + center on %ux%u panel",
           (unsigned)AV_ESP_DOWNLINK_WIDTH, (unsigned)AV_ESP_DOWNLINK_HEIGHT,
           (unsigned)AV_ESP_LCD_H_RES, (unsigned)AV_ESP_LCD_V_RES);
  _av_log_mem("lcd decode buf opened");
  return ESP_OK;

fail:
  _lcd_video_playout_close();
  return err;
}

static void _lcd_video_playout_close(void) {
  _jpeg_decoder_deinit();
  if (lcd_video_rgb565_buffer != NULL) {
    heap_caps_free(lcd_video_rgb565_buffer);
    lcd_video_rgb565_buffer = NULL;
  }
  if (lcd_video_draw_buffer != NULL) {
    heap_caps_free(lcd_video_draw_buffer);
    lcd_video_draw_buffer = NULL;
  }
  if (lcd_video_ppa != NULL) {
    ppa_unregister_client(lcd_video_ppa);
    lcd_video_ppa = NULL;
  }
  lcd_video_fb = NULL;  // 归面板所有，不释放
  lcd_video_ppa_failed = false;
  if (lcd_video_lock != NULL) {
    vSemaphoreDelete(lcd_video_lock);
    lcd_video_lock = NULL;
  }
  lcd_video_last_draw_w = 0;
  lcd_video_last_draw_h = 0;
  lcd_video_playout_initialized = false;
  _av_log_mem("lcd decode buf closed");
}

// PPA 显示路径：已解码的 RGB565（lcd_video_rgb565_buffer，行跨度 stride_w）按等比缩放
// 铺满 800x480 面板、居中，由 PPA 直接写进面板 framebuffer。
//   - 缩放：倍数取 min(800/w, 480/h)，按 PPA 精度 1/16 向下取整；横屏 320x240 -> x2 = 640x480，
//     竖屏 240x320 -> x1.5 = 360x480，竖屏 480x640 -> x0.75 = 360x480（双线性）。
//   - 不经 CPU：原 CPU 路径逐像素放大 + draw_bitmap 整屏 memcpy（750KB/帧），显示任务占 CPU 41%。
//     输出直接落在 framebuffer 内，draw_bitmap 识别出来后只做 cache 同步、不再拷贝。
// 单 framebuffer：与原路径一样可能有轻微撕裂。
static esp_err_t _lcd_video_draw_ppa(uint32_t src_w, uint32_t src_h, uint32_t stride_w,
                                     uint32_t aligned_h) {
  if (lcd_video_ppa == NULL) {
    const ppa_client_config_t client_cfg = {
        .oper_type = PPA_OPERATION_SRM,
        .max_pending_trans_num = 1,
    };
    ESP_RETURN_ON_ERROR(ppa_register_client(&client_cfg, &lcd_video_ppa), TAG,
                        "display ppa_register_client failed");
  }
  if (lcd_video_fb == NULL) {
    void *fb = NULL;
    ESP_RETURN_ON_ERROR(esp_lcd_rgb_panel_get_frame_buffer(lcd_panel, 1, &fb), TAG,
                        "get RGB frame buffer failed");
    lcd_video_fb = (uint8_t *)fb;
  }

  uint32_t s16_w = AV_ESP_LCD_H_RES * 16U / src_w;
  uint32_t s16_h = AV_ESP_LCD_V_RES * 16U / src_h;
  uint32_t s16 = s16_w < s16_h ? s16_w : s16_h;
  if (s16 == 0U) {
    return ESP_ERR_INVALID_SIZE;  // 源比面板大 16 倍以上，不可能出现
  }
  if (s16 > 16U * 16U - 1U) {
    s16 = 16U * 16U - 1U;
  }
  // 与 PPA 驱动相同的取整方式计算输出块尺寸（ppa_srm.c: int + frag/16）。
  const uint32_t draw_w = src_w * (s16 / 16U) + src_w * (s16 % 16U) / 16U;
  const uint32_t draw_h = src_h * (s16 / 16U) + src_h * (s16 % 16U) / 16U;
  if (draw_w == 0U || draw_h == 0U || draw_w > AV_ESP_LCD_H_RES || draw_h > AV_ESP_LCD_V_RES) {
    return ESP_ERR_INVALID_SIZE;
  }
  const uint32_t off_x = ((AV_ESP_LCD_H_RES - draw_w) / 2U) & ~1U;
  const uint32_t off_y = (AV_ESP_LCD_V_RES - draw_h) / 2U;

  // 绘制区域变化（首帧 / 对端改分辨率或横竖屏）时整屏清黑；之后只覆盖中央区域。
  if (draw_w != lcd_video_last_draw_w || draw_h != lcd_video_last_draw_h) {
    memset(lcd_video_fb, 0, AV_ESP_LCD_PANEL_BYTES);
    ESP_RETURN_ON_ERROR(esp_lcd_panel_draw_bitmap(lcd_panel, 0, 0, (int)AV_ESP_LCD_H_RES,
                                                  (int)AV_ESP_LCD_V_RES, lcd_video_fb),
                        TAG, "clear panel failed");
    lcd_video_last_draw_w = draw_w;
    lcd_video_last_draw_h = draw_h;
    ESP_LOGI(TAG, "downlink video %ux%u -> panel %ux%u (x%u/16, PPA) at (%u,%u)", (unsigned)src_w,
             (unsigned)src_h, (unsigned)draw_w, (unsigned)draw_h, (unsigned)s16, (unsigned)off_x,
             (unsigned)off_y);
  }

  const float scale = (float)s16 / 16.0f;
  const ppa_srm_oper_config_t srm = {
      .in =
          {
              .buffer = lcd_video_rgb565_buffer,
              .pic_w = stride_w,
              .pic_h = aligned_h,
              .block_w = src_w,
              .block_h = src_h,
              .block_offset_x = 0,
              .block_offset_y = 0,
              .srm_cm = PPA_SRM_COLOR_MODE_RGB565,
          },
      .out =
          {
              .buffer = lcd_video_fb,
              .buffer_size = AV_ESP_LCD_PANEL_BYTES,
              .pic_w = AV_ESP_LCD_H_RES,
              .pic_h = AV_ESP_LCD_V_RES,
              .block_offset_x = off_x,
              .block_offset_y = off_y,
              .srm_cm = PPA_SRM_COLOR_MODE_RGB565,
          },
      .rotation_angle = PPA_SRM_ROTATION_ANGLE_0,
      .scale_x = scale,
      .scale_y = scale,
      .mode = PPA_TRANS_MODE_BLOCKING,
  };
  ESP_RETURN_ON_ERROR(ppa_do_scale_rotate_mirror(lcd_video_ppa, &srm), TAG, "display PPA SRM failed");

  // 指针落在 framebuffer 内：驱动只做 cache 同步，不拷贝。
  return esp_lcd_panel_draw_bitmap(
      lcd_panel, (int)off_x, (int)off_y, (int)(off_x + draw_w), (int)(off_y + draw_h),
      lcd_video_fb + ((size_t)off_y * AV_ESP_LCD_H_RES + off_x) * sizeof(uint16_t));
}

// 解码一帧下行 MJPEG 为 RGB565，等比缩放后居中绘制到 800x480 面板。
// RGB 面板的 draw_bitmap 为同步写入 framebuffer，无需等待刷新回调。
static esp_err_t _lcd_video_playout_render(const uint8_t *jpeg_data, size_t jpeg_data_length) {
  if (jpeg_data == NULL || jpeg_data_length < 4U || jpeg_data_length > AV_ESP_LCD_MAX_JPEG_BYTES ||
      jpeg_data[0] != 0xffU || jpeg_data[1] != 0xd8U) {
    return ESP_ERR_INVALID_SIZE;
  }

  esp_err_t err = _lcd_video_playout_open();
  if (err != ESP_OK) {
    return err;
  }
  if (xSemaphoreTake(lcd_video_lock, 0) != pdTRUE) {
    ++lcd_video_drop_count;
    return ESP_ERR_TIMEOUT;
  }

  jpeg_decode_picture_info_t picture_info = {0};
  const esp_err_t info_ret =
      jpeg_decoder_get_info(jpeg_data, (uint32_t)jpeg_data_length, &picture_info);
  const uint32_t src_w = picture_info.width;
  const uint32_t src_h = picture_info.height;
  // 硬件 JPEG 解码器按每行 16 像素对齐输出：实际行跨度(stride)可能大于图像宽度，
  // 右侧为无效 padding；高度同理按 16 对齐。故解码字节数以对齐后尺寸计算，而非 w*h。
  const uint32_t stride_w = (src_w + 15U) & ~15U;   // 实际行跨度（像素）
  const uint32_t aligned_h = (src_h + 15U) & ~15U;  // 对齐后高度（行）
  const uint32_t need_bytes = stride_w * aligned_h * (uint32_t)sizeof(uint16_t);
  // 仅要求能解析出正整数尺寸；硬约束：对齐后整帧字节数不能超过解码缓冲上限(下行 640x480)，
  // 放不下才丢（分辨率异于预期的更大帧）。
  if (info_ret != ESP_OK || src_w == 0U || src_h == 0U || need_bytes > AV_ESP_LCD_DECODE_BYTES) {
    ++lcd_video_drop_count;
    if (lcd_video_drop_count == 1U || lcd_video_drop_count % 50U == 0U) {
      ESP_LOGW(TAG, "drop MJPEG frame: info=%d size=%ux%u need=%u panel=%ux%u decbuf=%u drops=%u",
               info_ret, (unsigned)src_w, (unsigned)src_h, (unsigned)need_bytes,
               (unsigned)AV_ESP_LCD_H_RES, (unsigned)AV_ESP_LCD_V_RES,
               (unsigned)AV_ESP_LCD_DECODE_BYTES, (unsigned)lcd_video_drop_count);
    }
    err = ESP_ERR_INVALID_SIZE;
    goto done;
  }

  uint32_t decoded_size = 0;
  const esp_err_t decode_result = jpeg_decoder_process(
      lcd_video_jpeg_decoder, &lcd_video_jpeg_decode_config, jpeg_data, (uint32_t)jpeg_data_length,
      lcd_video_rgb565_buffer, AV_ESP_LCD_DECODE_BYTES, &decoded_size);
  // 至少要输出到 src_h 行（每行 stride_w 像素），否则数据不完整则丢弃。
  const uint32_t min_bytes = stride_w * src_h * (uint32_t)sizeof(uint16_t);
  if (decode_result != ESP_OK || decoded_size < min_bytes) {
    ++lcd_video_drop_count;
    if (lcd_video_drop_count == 1U || lcd_video_drop_count % 50U == 0U) {
      ESP_LOGW(TAG, "drop MJPEG frame: decode=%d size=%ux%u stride=%u decoded=%u min=%u drops=%u",
               decode_result, (unsigned)src_w, (unsigned)src_h, (unsigned)stride_w,
               (unsigned)decoded_size, (unsigned)min_bytes, (unsigned)lcd_video_drop_count);
    }
    err = ESP_ERR_INVALID_SIZE;
    goto done;
  }

  if (!lcd_video_ppa_failed) {
    err = _lcd_video_draw_ppa(src_w, src_h, stride_w, aligned_h);
    if (err == ESP_OK) {
      goto done;
    }
    // PPA 不可用（注册失败 / framebuffer 不满足对齐等）：永久退回 CPU 路径，本帧也走 CPU。
    ESP_LOGW(TAG, "PPA display path failed (%s), falling back to CPU copy", esp_err_to_name(err));
    lcd_video_ppa_failed = true;
    if (lcd_video_ppa) {
      ppa_unregister_client(lcd_video_ppa);
      lcd_video_ppa = NULL;
    }
    lcd_video_last_draw_w = 0;
    lcd_video_last_draw_h = 0;
  }
  if (lcd_video_draw_buffer == NULL) {
    lcd_video_draw_buffer =
        heap_caps_aligned_alloc(64, AV_ESP_LCD_PANEL_BYTES, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (lcd_video_draw_buffer == NULL) {
      ++lcd_video_drop_count;
      err = ESP_ERR_NO_MEM;
      goto done;
    }
    memset(lcd_video_draw_buffer, 0, AV_ESP_LCD_PANEL_BYTES);
  }

  // CPU 回退路径：源尺寸按面板夹取并对齐偶数，避免越界。小于面板一半的画面按整数倍最近邻放大
  // （如 320x240 放大 2 倍为 640x480）；竖屏画面（如 240x320）只能 1:1，偏小。
  const uint32_t copy_w = ((src_w < AV_ESP_LCD_H_RES) ? src_w : AV_ESP_LCD_H_RES) & ~1U;
  const uint32_t copy_h = ((src_h < AV_ESP_LCD_V_RES) ? src_h : AV_ESP_LCD_V_RES) & ~1U;
  if (copy_w == 0U || copy_h == 0U) {
    err = ESP_ERR_INVALID_SIZE;
    goto done;
  }
  uint32_t scale = AV_ESP_LCD_H_RES / copy_w;
  if (AV_ESP_LCD_V_RES / copy_h < scale) {
    scale = AV_ESP_LCD_V_RES / copy_h;
  }
  if (scale == 0U) {
    scale = 1U;
  }
  const uint32_t draw_w = copy_w * scale;
  const uint32_t draw_h = copy_h * scale;
  const uint32_t off_x = ((AV_ESP_LCD_H_RES - draw_w) / 2U) & ~1U;  // 面板居中贴放起点
  const uint32_t off_y = ((AV_ESP_LCD_V_RES - draw_h) / 2U) & ~1U;
  const uint16_t *src_pixels = (const uint16_t *)lcd_video_rgb565_buffer;
  uint16_t *dst_base = (uint16_t *)lcd_video_draw_buffer;
  // 绘制区域变化（首帧或对端改分辨率）时整屏清黑；之后只覆盖中央区域，黑边无需每帧重清。
  if (draw_w != lcd_video_last_draw_w || draw_h != lcd_video_last_draw_h) {
    memset(lcd_video_draw_buffer, 0, AV_ESP_LCD_PANEL_BYTES);
    lcd_video_last_draw_w = draw_w;
    lcd_video_last_draw_h = draw_h;
    ESP_LOGI(TAG, "downlink video %ux%u -> panel %ux%u (x%u) at (%u,%u)", (unsigned)src_w,
             (unsigned)src_h, (unsigned)draw_w, (unsigned)draw_h, (unsigned)scale,
             (unsigned)off_x, (unsigned)off_y);
  }
  for (uint32_t row = 0U; row < copy_h; ++row) {
    uint16_t *dst_row = dst_base + (size_t)(off_y + row * scale) * AV_ESP_LCD_H_RES + off_x;
    const uint16_t *src_row = src_pixels + (size_t)row * stride_w;
    if (scale == 1U) {
      memcpy(dst_row, src_row, (size_t)copy_w * sizeof(uint16_t));
      continue;
    }
    uint16_t *d = dst_row;
    for (uint32_t x = 0U; x < copy_w; ++x) {
      const uint16_t px = src_row[x];
      for (uint32_t k = 0U; k < scale; ++k) {
        *d++ = px;
      }
    }
    for (uint32_t k = 1U; k < scale; ++k) {
      memcpy(dst_row + (size_t)k * AV_ESP_LCD_H_RES, dst_row, (size_t)draw_w * sizeof(uint16_t));
    }
  }

  // 整屏一次上屏（含黑边）：单帧缓冲 RGB 面板 draw_bitmap 为同步拷入 framebuffer。
  err = esp_lcd_panel_draw_bitmap(lcd_panel, 0, 0, (int)AV_ESP_LCD_H_RES, (int)AV_ESP_LCD_V_RES,
                                  dst_base);
  if (err != ESP_OK) {
    ++lcd_video_drop_count;
    ESP_LOGW(TAG, "LCD draw_bitmap failed: %s", esp_err_to_name(err));
  }

done:
  xSemaphoreGive(lcd_video_lock);
  return err;
}

/* ==================== 下行视频显示任务 ==================== */

// 显示任务：被唤醒后取出单槽最新帧到 work 缓冲（持锁仅做一次 memcpy），随后无锁解码 +
// 居中 + draw_bitmap。所有耗时操作都在本任务执行，SDK 主循环不再被阻塞。
static void _video_playout_task(void *arg) {
  (void)arg;
  while (video_playout_task_running) {
    (void)ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(100));
    if (!video_playout_task_running) {
      break;
    }
    size_t len = 0;
    if (xSemaphoreTake(video_slot_lock, portMAX_DELAY) == pdTRUE) {
      if (video_slot_pending) {
        len = video_slot_len;
        if (len > AV_ESP_VIDEO_SLOT_BYTES) {
          len = AV_ESP_VIDEO_SLOT_BYTES;
        }
        memcpy(video_work_buffer, video_slot_buffer, len);
        video_slot_pending = false;
      }
      xSemaphoreGive(video_slot_lock);
    }
    if (len == 0) {
      continue;
    }
    esp_err_t err = _lcd_video_playout_render(video_work_buffer, len);
    if (err != ESP_OK && err != ESP_ERR_TIMEOUT && err != ESP_ERR_INVALID_SIZE &&
        err != ESP_ERR_INVALID_STATE) {
      ESP_LOGW(TAG, "LCD video frame dropped: %s", esp_err_to_name(err));
    }
  }
  video_playout_task_handle = NULL;
  vTaskDeleteWithCaps(NULL);
}

// 惰性创建单槽缓冲、work 缓冲与显示任务（首帧下行视频时）。幂等，主循环单线程调用。
static esp_err_t _video_playout_start(void) {
  if (video_playout_started) {
    return ESP_OK;
  }
  video_slot_lock = xSemaphoreCreateMutex();
  if (video_slot_lock == NULL) {
    return ESP_ERR_NO_MEM;
  }
  video_slot_buffer = (uint8_t *)heap_caps_malloc(AV_ESP_VIDEO_SLOT_BYTES, MALLOC_CAP_SPIRAM);
  // work 缓冲作为硬件 JPEG 解码输入，按 64 字节对齐以满足 DMA/cache 要求。
  video_work_buffer =
      (uint8_t *)heap_caps_aligned_alloc(64, AV_ESP_VIDEO_SLOT_BYTES, MALLOC_CAP_SPIRAM);
  if (video_slot_buffer == NULL || video_work_buffer == NULL) {
    ESP_LOGE(TAG, "video playout buffer alloc failed");
    goto fail;
  }
  video_playout_task_running = true;
  BaseType_t ok = xTaskCreatePinnedToCoreWithCaps(
      _video_playout_task, "av_esp_disp", AV_ESP_VIDEO_PLAYOUT_TASK_STACK, NULL,
      AV_ESP_VIDEO_PLAYOUT_TASK_PRIORITY, &video_playout_task_handle, tskNO_AFFINITY,
      MALLOC_CAP_SPIRAM);
  if (ok != pdPASS) {
    video_playout_task_running = false;
    video_playout_task_handle = NULL;
    ESP_LOGE(TAG, "failed to create video playout task");
    goto fail;
  }
  video_playout_started = true;
  ESP_LOGI(TAG, "video playout task started");
  _av_log_mem("video playout started");
  return ESP_OK;

fail:
  if (video_slot_buffer != NULL) {
    heap_caps_free(video_slot_buffer);
    video_slot_buffer = NULL;
  }
  if (video_work_buffer != NULL) {
    heap_caps_free(video_work_buffer);
    video_work_buffer = NULL;
  }
  if (video_slot_lock != NULL) {
    vSemaphoreDelete(video_slot_lock);
    video_slot_lock = NULL;
  }
  return ESP_FAIL;
}

static void _video_playout_stop(void) {
  if (video_playout_task_running) {
    video_playout_task_running = false;
    if (video_playout_task_handle != NULL) {
      xTaskNotifyGive(video_playout_task_handle);  // 唤醒以尽快退出等待
    }
    int wait = AV_ESP_VIDEO_STOP_WAIT_MS / 20;
    while (video_playout_task_handle != NULL && wait-- > 0) {
      vTaskDelay(pdMS_TO_TICKS(20));
    }
  }
  video_playout_started = false;
  video_slot_pending = false;
  if (video_slot_buffer != NULL) {
    heap_caps_free(video_slot_buffer);
    video_slot_buffer = NULL;
  }
  if (video_work_buffer != NULL) {
    heap_caps_free(video_work_buffer);
    video_work_buffer = NULL;
  }
  if (video_slot_lock != NULL) {
    vSemaphoreDelete(video_slot_lock);
    video_slot_lock = NULL;
  }
  _av_log_mem("video playout stopped");
}
