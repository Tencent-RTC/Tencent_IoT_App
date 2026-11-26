#ifndef WATCH_CAMERA_ESP_H
#define WATCH_CAMERA_ESP_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 采集分辨率。与 watch_camera_esp.c 内部的 WATCH_CAM_WIDTH/HEIGHT 共用同一组宏，
   供推流侧填写视频帧的 width/height，避免两处各写一份常量。
   必须是 16 的倍数（H.264 宏块对齐）。

   QVGA 320x240。曾降到 QQVGA 160x120 想缓解卡顿，实测无效并已回退：
   像素量降到 1/4，编码耗时反而从 avg=224ms 变成 avg=351ms（max 1164ms）。
   原因是瓶颈不在编码本身而在 CPU 争用——同期 main_loop 占 66.2%
   （组装远端视频帧）、av_esp_mic 占 66.2%，watch_cam 只拿到 30.3%，
   两核 IDLE 仅剩 1.8% / 0.4%。降分辨率省下的算力被其他任务吃掉，
   帧率没改善，却白损失画质并因与屏分辨率不符而丢掉本地预览。

   改这里时必须同步 watch_camera_esp.c 里 camera_config_t.frame_size，
   二者不一致会导致每帧都被尺寸校验丢弃（已加编译期断言防止漏改）。 */
#ifndef WATCH_CAM_FRAME_WIDTH
#define WATCH_CAM_FRAME_WIDTH 320
#endif
#ifndef WATCH_CAM_FRAME_HEIGHT
#define WATCH_CAM_FRAME_HEIGHT 240
#endif

/* 编码后的 H.264 帧回调。在采集任务上下文调用，data 仅在回调期间有效。 */
typedef void (*watch_camera_frame_callback)(const uint8_t *data, uint32_t len, bool is_key_frame,
                                            uint64_t pts_ms, void *user_data);

/* 初始化摄像头 + H.264 软编码器。重复调用安全（第二次直接返回 0）。 */
int watch_camera_esp_init(void);

/* 启动/停止采集编码任务。stop 幂等。 */
int watch_camera_esp_start(watch_camera_frame_callback callback, void *user_data);
void watch_camera_esp_stop(void);

#if WATCH_ENABLE_DISPLAY
/* 本地回显（预览）开关。默认在 init 成功后开启。
   关闭用于排除刷屏开销对编码帧率的影响——刷全屏需传输 150KB，与软编码共享 CPU。 */
void watch_camera_esp_set_preview(bool enabled);
#endif

/* 请求下一帧编码为 IDR（对端进房或丢包后需要关键帧）。 */
void watch_camera_esp_request_idr(void);

#ifdef __cplusplus
}
#endif

#endif
