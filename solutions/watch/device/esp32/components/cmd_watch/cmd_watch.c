// Copyright (c) 2026 Tencent. All rights reserved.
//
// watch 常驻应用的 ESP32 运行时与 console 命令。
//
// 与 src/watch/app/watch_main.c（POSIX 入口）等价，差异仅在于：
//   - main(argc, argv) + signal + select(stdin)  ->  FreeRTOS 任务 + esp_console 命令
//   - 配置由编译期 config.h 固化，不读文件系统
//
// 与 cmd_iot_demo 并存：watch 走 TRTC adapter 后端（双 SDKAppID、UserSig 本地生成、
// region 即房间号），两者不可同时运行，由 watch_start / iot_start 各自管理生命周期。

#include "cmd_watch.h"

#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "argtable3/argtable3.h"
#include "esp_console.h"
#include "esp_log.h"
#include "esp_netif_sntp.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "tc_iot.h"
#include "watch/app.h"
#include "watch/config.h"
#include "watch/platform.h"
#include "watch_media_iot.h"
#include "watch_media_source_esp.h"
#include "watch_message_im.h"
#if WATCH_ENABLE_CAMERA
#include "watch_camera_esp.h" /* watch_cam_test 自检命令 */
#endif
// watch_lcd_test 只针对 S3 的 SPI ST7789（watch_display_esp.c）；S31 的屏由 av_device 驱动，
// 不编该命令。
#ifndef WATCH_ESP_BOARD_AV
#define WATCH_ESP_BOARD_AV 0
#endif
#define CMD_WATCH_LCD_TEST (WATCH_ENABLE_DISPLAY && !WATCH_ESP_BOARD_AV)
#if CMD_WATCH_LCD_TEST
#include "watch_display_esp.h" /* watch_lcd_test 彩条自检 */
#endif
#include "watch_video_receiver_esp.h" /* 远端视频软解码 + 显示 */

#define TAG "cmd_watch"

#define WATCH_TASK_STACK (8 * 1024)
#define WATCH_TASK_PRIORITY 5
#define WATCH_TICK_INTERVAL_MS 100
#define WATCH_LOGIN_TIMEOUT_MS 10000
#define WATCH_SNTP_TIMEOUT_MS 15000
// 判定系统时间是否已是真实时间的下限：2020-01-01 UTC。
// 设备无 RTC，未同步时 time() 从 1970 开始计。
#define WATCH_TIME_VALID_THRESHOLD 1577836800

static struct {
  watch_config_t config;
  watch_app_t *app;
  watch_message_t *message;
  watch_message_backend_t message_backend;
  watch_media_t *media;
  watch_iot_media_t *iot_media;
  TaskHandle_t task;
  SemaphoreHandle_t login_semaphore;
  int login_result;
  volatile int running;
  volatile int stop_requested;
} s_watch;

// ==================== SDK 回调 ====================

static void watch_on_iot_login(tc_iot_error_e error_code, const char *message) {
  s_watch.login_result = (error_code == TC_IOT_ERR_SUCCESS) ? 1 : -1;
  if (error_code != TC_IOT_ERR_SUCCESS) {
    ESP_LOGE(TAG, "IoT login failed: %d %s", error_code, message ? message : "");
  }
  if (s_watch.login_semaphore) xSemaphoreGive(s_watch.login_semaphore);
}

static void watch_on_message_text(const char *from, const char *text, void *user_data) {
  // 所有 IM 文本先交给 watch_app 分流：普通文本上报业务层，呼叫信令转信令状态机。
  watch_app_receive_text((watch_app_t *)user_data, from, text);
}

static void watch_on_message_status(int online, int code, const char *description,
                                    void *user_data) {
  (void)user_data;
  ESP_LOGI(TAG, "IM status online=%d code=%d %s", online, code, description ? description : "");
}

static void watch_on_text(const char *from, const char *text, void *user_data) {
  (void)user_data;
  ESP_LOGI(TAG, "message from=%s: %s", from ? from : "", text ? text : "");
}

static void watch_on_call_state(watch_call_state_t state, const char *peer, void *user_data) {
  (void)user_data;
  ESP_LOGI(TAG, "call state=%d peer=%s", (int)state, peer ? peer : "");
}

// 远端音频下行：交给 ES8311 播放。在 TRTC 接收线程上下文被调用，只做拷贝转发。
static void watch_on_remote_audio(const tc_iot_audio_frame *frame) {
  watch_media_source_esp_playout_audio(frame);
}

// 远端视频下行：软解码 + 送屏。在 TRTC 接收线程上下文被调用。
static void watch_on_remote_video(const tc_iot_video_frame *frame) {
  watch_video_receiver_esp_on_frame(frame);
}

// 呼叫信令由 IM 承载（watch_signaling），这里只接管媒体帧回调。
static const tc_iot_av_observer_s s_av_observer = {
    .on_audio_frame_received = watch_on_remote_audio,
    .on_video_frame_received = watch_on_remote_video,
};

// ==================== 生命周期 ====================

static void watch_runtime_teardown(void) {
  // 释放顺序与创建顺序相反：先停上层业务，再退 SDK 会话。
  if (s_watch.app) {
    watch_app_destroy(s_watch.app);
    s_watch.app = NULL;
  }
  if (s_watch.message) {
    watch_message_destroy(s_watch.message);
    s_watch.message = NULL;
  }
  watch_message_im_backend_destroy(&s_watch.message_backend);
  if (s_watch.media) {
    watch_media_destroy(s_watch.media);
    s_watch.media = NULL;
  }
  if (s_watch.iot_media) {
    watch_iot_media_destroy(s_watch.iot_media);
    s_watch.iot_media = NULL;
  }
  (void)tc_iot_logout();
  (void)tc_iot_deinit();
  if (s_watch.login_semaphore) {
    vSemaphoreDelete(s_watch.login_semaphore);
    s_watch.login_semaphore = NULL;
  }
}

// UserSig 的有效期字段由 watch_usersig 用 time(NULL) 计算。设备无 RTC，未同步时
// 系统时间停在 1970，签出的 UserSig 在服务端一定被判定为过期
// （实测：TRTC 进房返回 error_code:-100018 usersig expired）。
// 因此必须在生成 UserSig 之前完成一次 SNTP 对时。
static int watch_sync_system_time(void) {
  time_t now = time(NULL);
  if (now >= WATCH_TIME_VALID_THRESHOLD) {
    ESP_LOGI(TAG, "system time already valid: %lld", (long long)now);
    return 0;
  }
  esp_sntp_config_t config = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
  esp_err_t err = esp_netif_sntp_init(&config);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_netif_sntp_init failed: 0x%x", err);
    return -1;
  }
  err = esp_netif_sntp_sync_wait(pdMS_TO_TICKS(WATCH_SNTP_TIMEOUT_MS));
  // 同步完即可释放：只需校准一次，后续由系统时钟自行走时。
  esp_netif_sntp_deinit();
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "SNTP sync timeout (0x%x); check network and DNS", err);
    return -1;
  }
  now = time(NULL);
  if (now < WATCH_TIME_VALID_THRESHOLD) {
    ESP_LOGE(TAG, "system time still invalid after sync: %lld", (long long)now);
    return -1;
  }
  ESP_LOGI(TAG, "SNTP synced: %lld (%s)", (long long)now, asctime(gmtime(&now)));
  return 0;
}

static int watch_runtime_setup(void) {
  // 必须先对时再加载配置：watch_config_load 内部即生成两份 UserSig。
  if (watch_sync_system_time() != 0) {
    ESP_LOGE(TAG, "cannot obtain valid system time; UserSig would be rejected as expired");
    return -1;
  }
  if (watch_config_load(&s_watch.config) != 0) {
    ESP_LOGE(TAG, "invalid built-in config (check src/watch/config.h)");
    return -1;
  }
  watch_config_dump(&s_watch.config);

  s_watch.login_semaphore = xSemaphoreCreateBinary();
  if (!s_watch.login_semaphore) {
    ESP_LOGE(TAG, "cannot create login semaphore");
    return -1;
  }

  // 无文件系统时 storage_path 为空，IoT SDK 退化为内存态存储。
  tc_iot_config_s iot_config = {
      .storage_path = s_watch.config.storage_path,
      .log_level = TC_IOT_LOG_LEVEL_INFO,
      .on_log = NULL,
      .on_device_event = NULL,
      .region = s_watch.config.room_id, /* adapter 后端：region 即 TRTC 房间号 */
  };
  if (tc_iot_init(&iot_config) != TC_IOT_ERR_SUCCESS) {
    ESP_LOGE(TAG, "tc_iot_init failed");
    return -1;
  }

  // adapter 后端：product_id 承载 TRTC SDKAppID，device_secret 承载 TRTC UserSig。
  tc_iot_device_info_s device = {
      .product_id = s_watch.config.trtc_sdk_app_id,
      .device_id = s_watch.config.device_id,
      .device_secret = s_watch.config.trtc_usersig,
  };
  s_watch.login_result = 0;
  if (tc_iot_login(&device, watch_on_iot_login) != TC_IOT_ERR_SUCCESS) {
    ESP_LOGE(TAG, "tc_iot_login failed");
    return -1;
  }
  if (xSemaphoreTake(s_watch.login_semaphore, pdMS_TO_TICKS(WATCH_LOGIN_TIMEOUT_MS)) != pdTRUE ||
      s_watch.login_result != 1) {
    ESP_LOGE(TAG, "IoT login timeout or rejected");
    return -1;
  }
  ESP_LOGI(TAG, "IoT login ok");

  watch_media_backend_t media_backend;
  watch_iot_media_input_t media_input;
  if (watch_iot_media_create(&s_watch.iot_media, &media_backend) != 0) {
    ESP_LOGE(TAG, "watch_iot_media_create failed");
    return -1;
  }
  if (watch_media_source_esp_create(&media_input) != 0 ||
      watch_iot_media_set_input(s_watch.iot_media, &media_input) != 0) {
    ESP_LOGE(TAG, "cannot install esp media input");
    return -1;
  }
  // 进房是同步等待的（adapter 内部等 on_enter_room），返回即已真正在房间内。
  if (watch_iot_media_enter(s_watch.iot_media, &s_av_observer) != 0) {
    ESP_LOGE(TAG, "enter TRTC room failed (room=%s)", s_watch.config.room_id);
    return -1;
  }
  ESP_LOGI(TAG, "TRTC room entered: %s", s_watch.config.room_id);

  s_watch.media = watch_media_create(&media_backend);
  if (!s_watch.media) {
    ESP_LOGE(TAG, "watch_media_create failed");
    return -1;
  }

  watch_app_config_t app_config = {
      .user_id = s_watch.config.device_id,
      .auto_accept_delay_sec = s_watch.config.auto_accept_delay_sec,
      .call_timeout_sec = s_watch.config.call_timeout_sec,
      .media = s_watch.media,
      .on_text = watch_on_text,
      .on_call_state = watch_on_call_state,
  };
  s_watch.app = watch_app_create(&app_config);
  if (!s_watch.app) {
    ESP_LOGE(TAG, "watch_app_create failed");
    return -1;
  }
  if (watch_message_im_backend_create(&s_watch.message_backend) != 0) {
    ESP_LOGE(TAG, "watch_message_im_backend_create failed");
    return -1;
  }
  watch_message_config_t message_config = {
      .sdk_app_id = strtoull(s_watch.config.im_sdk_app_id, NULL, 10),
      .user_id = s_watch.config.device_id,
      .user_sig = s_watch.config.im_usersig,
      .data_path = s_watch.config.im_data_path,
      .on_text = watch_on_message_text,
      .on_status = watch_on_message_status,
      .user_data = s_watch.app,
      .backend = s_watch.message_backend,
  };
  s_watch.message = watch_message_create(&message_config);
  watch_app_set_message(s_watch.app, s_watch.message);
  if (!s_watch.message || watch_app_start(s_watch.app) != 0) {
    ESP_LOGE(TAG, "watch_app_start failed");
    return -1;
  }
#if WATCH_ENABLE_CAMERA
  // 摄像头预初始化并常驻，不等到接听时才初始化。
  //
  // esp32-camera 需要一块 30KB 的 internal DMA 缓冲。接听时远端视频已经在收，
  // WiFi/lwip 接收缓冲把 internal 压到 ~30KB（最低 8.5KB），此时再申请必然失败，
  // 实测 "esp_camera_init failed" 后降级为纯音频——手机看不到设备画面。
  //
  // 放在 IM 启动之后：两者都要大块 internal，IM 起不来整个 watch 会 assert，
  // 摄像头起不来只是降级为纯音频，因此先保 IM。初始化后 sensor 进入待机，不占 CPU。
  if (watch_camera_esp_init() != 0) {
    ESP_LOGW(TAG, "camera pre-init failed; video calls will be audio-only");
  }
#endif
  return 0;
}

static void watch_task(void *argument) {
  (void)argument;
  if (watch_runtime_setup() != 0) {
    watch_runtime_teardown();
    s_watch.running = 0;
    s_watch.task = NULL;
    ESP_LOGE(TAG, "watch start failed");
    vTaskDelete(NULL);
    return;
  }
  ESP_LOGI(TAG, "watch running: device_id=%s room=%s", s_watch.config.device_id,
           s_watch.config.room_id);
  // 驱动信令超时与延迟自动接听；节奏与 POSIX 入口一致（100ms）。
  while (!s_watch.stop_requested) {
    watch_app_tick(s_watch.app, watch_platform_now_ms());
    watch_platform_sleep_ms(WATCH_TICK_INTERVAL_MS);
  }
  watch_runtime_teardown();
  s_watch.running = 0;
  s_watch.task = NULL;
  ESP_LOGI(TAG, "watch stopped");
  vTaskDelete(NULL);
}

// ==================== console 命令 ====================

static int cmd_watch_start(int argc, char **argv) {
  (void)argc;
  (void)argv;
  if (s_watch.running) {
    ESP_LOGW(TAG, "watch already running");
    return 0;
  }
  memset(&s_watch, 0, sizeof(s_watch));
  s_watch.running = 1;
  if (xTaskCreate(watch_task, "watch", WATCH_TASK_STACK, NULL, WATCH_TASK_PRIORITY,
                  &s_watch.task) != pdPASS) {
    s_watch.running = 0;
    ESP_LOGE(TAG, "cannot create watch task");
    return 1;
  }
  return 0;
}

static int cmd_watch_stop(int argc, char **argv) {
  (void)argc;
  (void)argv;
  if (!s_watch.running) {
    ESP_LOGW(TAG, "watch not running");
    return 0;
  }
  s_watch.stop_requested = 1;
  // 等待任务自行收尾，避免在 console 线程里释放仍被使用的资源。
  for (int waited_ms = 0; s_watch.running && waited_ms < 5000; waited_ms += 100) {
    vTaskDelay(pdMS_TO_TICKS(100));
  }
  if (s_watch.running) ESP_LOGW(TAG, "watch stop timeout");
  return 0;
}

static struct {
  struct arg_str *user;
  struct arg_int *content;
  struct arg_end *end;
} s_call_args;

static int cmd_watch_call(int argc, char **argv) {
  if (!s_watch.running || !s_watch.app) {
    ESP_LOGE(TAG, "watch not running; run watch_start first");
    return 1;
  }
  if (arg_parse(argc, argv, (void **)&s_call_args) != 0) {
    arg_print_errors(stderr, s_call_args.end, argv[0]);
    return 1;
  }
  // 对端必须用 -u 显式指定（不设默认对端，避免误呼一个不存在的账号）。
  const char *peer = s_call_args.user->count > 0 ? s_call_args.user->sval[0] : NULL;
  if (!peer || !peer[0]) {
    ESP_LOGE(TAG, "usage: watch_call -u <user_id> [-c 1]");
    return 1;
  }
  watch_call_option_t option = {.media_content = WATCH_MEDIA_AUDIO_VIDEO,
                                .video_quality = WATCH_VIDEO_QUALITY_SD};
  if (s_call_args.content->count > 0) {
    option.media_content = (watch_media_content_t)s_call_args.content->ival[0];
  }
  return watch_app_call(s_watch.app, peer, &option) == 0 ? 0 : 1;
}

static int cmd_watch_hangup(int argc, char **argv) {
  (void)argc;
  (void)argv;
  if (!s_watch.running || !s_watch.app) {
    ESP_LOGE(TAG, "watch not running");
    return 1;
  }
  return watch_app_hangup(s_watch.app) == 0 ? 0 : 1;
}

static struct {
  struct arg_str *user;
  struct arg_str *text;
  struct arg_end *end;
} s_msg_args;

static int cmd_watch_msg(int argc, char **argv) {
  if (!s_watch.running || !s_watch.message) {
    ESP_LOGE(TAG, "watch not running");
    return 1;
  }
  if (arg_parse(argc, argv, (void **)&s_msg_args) != 0) {
    arg_print_errors(stderr, s_msg_args.end, argv[0]);
    return 1;
  }
  const char *peer = s_msg_args.user->count > 0 ? s_msg_args.user->sval[0] : NULL;
  if (!peer || !peer[0] || s_msg_args.text->count == 0) {
    ESP_LOGE(TAG, "usage: watch_msg -u <user_id> -t <text>");
    return 1;
  }
  return watch_message_send_chat(s_watch.message, peer, s_msg_args.text->sval[0]) == 0 ? 0 : 1;
}

static int cmd_watch_state(int argc, char **argv) {
  (void)argc;
  (void)argv;
  ESP_LOGI(TAG, "running=%d call_state=%d im_online=%d", s_watch.running,
           s_watch.app ? (int)watch_app_state(s_watch.app) : -1,
           s_watch.message ? watch_message_is_online(s_watch.message) : -1);
  return 0;
}

#if WATCH_ENABLE_CAMERA
// 摄像头自检：不依赖 IM 对端、不依赖通话建立，直接验证板级链路是否通。
// 覆盖三件在通话场景下无法单独确认的事：
//   1. WATCH_CAM_PIN_* 是否与开发板一致（错了 esp_camera_init 直接失败）；
//   2. GC0308 能否经 SCCB（复用音频 I2C 总线）被 probe 到，PID 是否符合预期；
//   3. openh264 软编码在本机实际能跑多少帧——S3 无硬编码，这个只能实测。
// 前置条件：先执行 watch_start，它会完成 av_device_init（建 I2C 总线 + PCA9557）。
static uint32_t s_cam_test_frames = 0;
static uint32_t s_cam_test_bytes = 0;
static uint32_t s_cam_test_key_frames = 0;

static void cmd_watch_cam_test_on_frame(const uint8_t *data, uint32_t size, bool is_key_frame,
                                        uint64_t pts_ms, void *user_data) {
  (void)data;
  (void)pts_ms;
  (void)user_data;
  s_cam_test_frames++;
  s_cam_test_bytes += size;
  if (is_key_frame) s_cam_test_key_frames++;
}

#if CMD_WATCH_LCD_TEST
// 显示自检：画四条彩条（红绿蓝白）。用于把「面板/色彩」与「摄像头/YUV 转换」分开定位。
// 不依赖摄像头，只要 watch_start 完成（I2C 可用于 PCA9557 片选）即可执行。
static int cmd_watch_lcd_test(int argc, char **argv) {
  (void)argc;
  (void)argv;
  if (watch_display_esp_init() != 0) {
    ESP_LOGE(TAG, "display init failed; run watch_start first (needs I2C bus for PCA9557 CS)");
    return 1;
  }
  if (watch_display_esp_draw_test_pattern() != 0) {
    ESP_LOGE(TAG, "draw test pattern failed");
    return 1;
  }
  ESP_LOGI(TAG, "check screen: 4 vertical bands, left to right = RED GREEN BLUE WHITE");
  return 0;
}
#endif

// 预览时长取较长值：本地回显要靠肉眼确认画面，5 秒太短来不及看。
#if WATCH_ENABLE_DISPLAY
#define WATCH_CAM_TEST_DURATION_MS 20000
#else
#define WATCH_CAM_TEST_DURATION_MS 5000
#endif

static int cmd_watch_cam_test(int argc, char **argv) {
  (void)argc;
  (void)argv;
  const int kDurationMs = WATCH_CAM_TEST_DURATION_MS;

  s_cam_test_frames = 0;
  s_cam_test_bytes = 0;
  s_cam_test_key_frames = 0;

  if (watch_camera_esp_init() != 0) {
    ESP_LOGE(TAG, "camera init failed; run watch_start first (needs I2C bus from av_device)");
    return 1;
  }
  // 本地回显默认关闭（屏幕只给远端画面），自检期间临时打开，结束后恢复关闭。
#if WATCH_ENABLE_DISPLAY
  watch_camera_esp_set_preview(true);
#endif
  if (watch_camera_esp_start(cmd_watch_cam_test_on_frame, NULL) != 0) {
    ESP_LOGE(TAG, "camera start failed");
#if WATCH_ENABLE_DISPLAY
    watch_camera_esp_set_preview(false);
#endif
    return 1;
  }
  ESP_LOGI(TAG, "capturing for %d ms ...", kDurationMs);
  vTaskDelay(pdMS_TO_TICKS(kDurationMs));
  watch_camera_esp_stop();
#if WATCH_ENABLE_DISPLAY
  watch_camera_esp_set_preview(false);
#endif

  if (s_cam_test_frames == 0) {
    ESP_LOGE(TAG, "no frame encoded: sensor opened but capture/encode produced nothing");
    return 1;
  }
  ESP_LOGI(TAG, "camera self-test: frames=%lu keyframes=%lu avg=%lu B/frame fps=%.1f",
           (unsigned long)s_cam_test_frames, (unsigned long)s_cam_test_key_frames,
           (unsigned long)(s_cam_test_bytes / s_cam_test_frames),
           (double)s_cam_test_frames * 1000.0 / (double)kDurationMs);
  return 0;
}
#endif

void register_watch_commands(void) {
  s_call_args.user = arg_str0("u", "user", "<user_id>", "peer user id");
  s_call_args.content = arg_int0("c", "content", "<1=audio>", "1 = audio only");
  s_call_args.end = arg_end(2);
  s_msg_args.user = arg_str0("u", "user", "<user_id>", "peer user id");
  s_msg_args.text = arg_str1("t", "text", "<text>", "message text");
  s_msg_args.end = arg_end(2);

  const esp_console_cmd_t commands[] = {
      {.command = "watch_start", .help = "start watch resident app", .hint = NULL,
       .func = &cmd_watch_start},
      {.command = "watch_stop", .help = "stop watch resident app", .hint = NULL,
       .func = &cmd_watch_stop},
      {.command = "watch_call", .help = "place a call", .hint = NULL, .func = &cmd_watch_call,
       .argtable = &s_call_args},
      {.command = "watch_hangup", .help = "hang up current call", .hint = NULL,
       .func = &cmd_watch_hangup},
      {.command = "watch_msg", .help = "send an IM text message", .hint = NULL,
       .func = &cmd_watch_msg, .argtable = &s_msg_args},
      {.command = "watch_state", .help = "print watch runtime state", .hint = NULL,
       .func = &cmd_watch_state},
#if WATCH_ENABLE_CAMERA
      {.command = "watch_cam_test",
       .help = "capture from camera and report encode stats (run after watch_start)",
       .hint = NULL, .func = &cmd_watch_cam_test},
#endif
#if CMD_WATCH_LCD_TEST
      {.command = "watch_lcd_test",
       .help = "draw RGB color bars to verify panel/color path (run after watch_start)",
       .hint = NULL, .func = &cmd_watch_lcd_test},
#endif
  };
  for (size_t i = 0; i < sizeof(commands) / sizeof(commands[0]); ++i) {
    ESP_ERROR_CHECK(esp_console_cmd_register(&commands[i]));
  }
}
