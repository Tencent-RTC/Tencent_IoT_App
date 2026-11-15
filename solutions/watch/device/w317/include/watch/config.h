#ifndef WATCH_CONFIG_H
#define WATCH_CONFIG_H

#include "watch/types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  char trtc_sdk_app_id[32];
  char trtc_secret_key[WATCH_SECRET_MAX];
  char im_sdk_app_id[32];
  char im_secret_key[WATCH_SECRET_MAX];
  unsigned int usersig_expire_sec;

  char device_id[WATCH_DEVICE_ID_MAX];
  /* TRTC 房间号（字符串房间）。adapter 后端经 tc_iot_config_s.region 传入，两端必须一致。 */
  char room_id[WATCH_ROOM_ID_MAX];
  char storage_path[160];
  char im_data_path[160];
  char audio_file_path[256];
  char video_file_path[256];
  char video_index_path[256];

  unsigned int auto_accept_delay_sec;
  unsigned int call_timeout_sec;

  char trtc_usersig[WATCH_USERSIG_MAX];
  char im_usersig[WATCH_USERSIG_MAX];
} watch_config_t;

void watch_config_init(watch_config_t *config);

/* 从编译期内置配置头加载配置并生成两份 UserSig，见 src/watch/config.h。
   配置在编译期固化进固件，运行时不访问文件系统，各平台（含无文件系统的 RTOS）行为一致。 */
int watch_config_load(watch_config_t *config);

int watch_config_generate_usersigs(watch_config_t *config, int64_t now);
void watch_config_dump(const watch_config_t *config);

#ifdef __cplusplus
}
#endif

#endif
