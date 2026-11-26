#include "watch/config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "watch/usersig.h"

/* 内置配置头路径可由构建系统覆盖，便于一套源码为多台设备产出不同固件：
   -DWATCH_CONFIG_BUILTIN_HEADER="\"my_watch_config.h\"" */
#ifndef WATCH_CONFIG_BUILTIN_HEADER
#define WATCH_CONFIG_BUILTIN_HEADER "../config.h"
#endif
#include WATCH_CONFIG_BUILTIN_HEADER

/* 可选项缺省值：内置头只需填必填项。 */
#ifndef WATCH_CFG_ROOM_ID
#define WATCH_CFG_ROOM_ID ""
#endif
#ifndef WATCH_CFG_STORAGE_PATH
#define WATCH_CFG_STORAGE_PATH ""
#endif
#ifndef WATCH_CFG_IM_DATA_PATH
#define WATCH_CFG_IM_DATA_PATH ""
#endif
#ifndef WATCH_CFG_AUDIO_FILE_PATH
#define WATCH_CFG_AUDIO_FILE_PATH ""
#endif
#ifndef WATCH_CFG_VIDEO_FILE_PATH
#define WATCH_CFG_VIDEO_FILE_PATH ""
#endif
#ifndef WATCH_CFG_VIDEO_INDEX_PATH
#define WATCH_CFG_VIDEO_INDEX_PATH ""
#endif
#ifndef WATCH_CFG_USERSIG_EXPIRE_SEC
#define WATCH_CFG_USERSIG_EXPIRE_SEC WATCH_USERSIG_DEFAULT_EXPIRE_SEC
#endif
#ifndef WATCH_CFG_AUTO_ACCEPT_DELAY_SEC
#define WATCH_CFG_AUTO_ACCEPT_DELAY_SEC 0
#endif
#ifndef WATCH_CFG_CALL_TIMEOUT_SEC
#define WATCH_CFG_CALL_TIMEOUT_SEC 30
#endif

/* 必填项缺失或为空串时在编译期报错，而不是烧进固件后才在运行时暴露。 */
_Static_assert(sizeof(WATCH_CFG_TRTC_SDK_APP_ID) > 1, "WATCH_CFG_TRTC_SDK_APP_ID is empty");
_Static_assert(sizeof(WATCH_CFG_TRTC_SECRET_KEY) > 1, "WATCH_CFG_TRTC_SECRET_KEY is empty");
_Static_assert(sizeof(WATCH_CFG_IM_SDK_APP_ID) > 1, "WATCH_CFG_IM_SDK_APP_ID is empty");
_Static_assert(sizeof(WATCH_CFG_IM_SECRET_KEY) > 1, "WATCH_CFG_IM_SECRET_KEY is empty");
_Static_assert(sizeof(WATCH_CFG_DEVICE_ID) > 1, "WATCH_CFG_DEVICE_ID is empty");

static int watch_copy(char *destination, size_t capacity, const char *value) {
  if (!destination || !value || strlen(value) >= capacity) return -1;
  strcpy(destination, value);
  return 0;
}

void watch_config_init(watch_config_t *config) {
  if (!config) return;
  memset(config, 0, sizeof(*config));
  config->usersig_expire_sec = WATCH_USERSIG_DEFAULT_EXPIRE_SEC;
  config->auto_accept_delay_sec = 0;
  config->call_timeout_sec = 30;
}

int watch_config_load(watch_config_t *config) {
  if (!config) return -1;
  watch_config_init(config);
  if (watch_copy(config->trtc_sdk_app_id, sizeof(config->trtc_sdk_app_id), WATCH_CFG_TRTC_SDK_APP_ID) != 0 ||
      watch_copy(config->trtc_secret_key, sizeof(config->trtc_secret_key), WATCH_CFG_TRTC_SECRET_KEY) != 0 ||
      watch_copy(config->im_sdk_app_id, sizeof(config->im_sdk_app_id), WATCH_CFG_IM_SDK_APP_ID) != 0 ||
      watch_copy(config->im_secret_key, sizeof(config->im_secret_key), WATCH_CFG_IM_SECRET_KEY) != 0 ||
      watch_copy(config->device_id, sizeof(config->device_id), WATCH_CFG_DEVICE_ID) != 0 ||
      watch_copy(config->room_id, sizeof(config->room_id), WATCH_CFG_ROOM_ID) != 0 ||
      watch_copy(config->storage_path, sizeof(config->storage_path), WATCH_CFG_STORAGE_PATH) != 0 ||
      watch_copy(config->im_data_path, sizeof(config->im_data_path), WATCH_CFG_IM_DATA_PATH) != 0 ||
      watch_copy(config->audio_file_path, sizeof(config->audio_file_path), WATCH_CFG_AUDIO_FILE_PATH) != 0 ||
      watch_copy(config->video_file_path, sizeof(config->video_file_path), WATCH_CFG_VIDEO_FILE_PATH) != 0 ||
      watch_copy(config->video_index_path, sizeof(config->video_index_path), WATCH_CFG_VIDEO_INDEX_PATH) != 0) {
    return -1;
  }
  config->usersig_expire_sec = (unsigned int)(WATCH_CFG_USERSIG_EXPIRE_SEC);
  config->auto_accept_delay_sec = (unsigned int)(WATCH_CFG_AUTO_ACCEPT_DELAY_SEC);
  config->call_timeout_sec = (unsigned int)(WATCH_CFG_CALL_TIMEOUT_SEC);

  if (config->usersig_expire_sec == 0) return -2;
  if (!config->storage_path[0])
    snprintf(config->storage_path, sizeof(config->storage_path), "./watch_storage/%s", config->device_id);
  if (!config->im_data_path[0])
    snprintf(config->im_data_path, sizeof(config->im_data_path), "./watch_im_data/%s", config->device_id);

  return watch_config_generate_usersigs(config, 0);
}

int watch_config_generate_usersigs(watch_config_t *config, int64_t now) {
  if (!config || !config->device_id[0] || !config->trtc_sdk_app_id[0] || !config->trtc_secret_key[0] ||
      !config->im_sdk_app_id[0] || !config->im_secret_key[0]) return -1;
  char *end = NULL;
  unsigned long trtc_id = strtoul(config->trtc_sdk_app_id, &end, 10);
  if (end == config->trtc_sdk_app_id || *end != '\0' || trtc_id == 0 || trtc_id > 0xffffffffUL) return -1;
  unsigned long im_id = strtoul(config->im_sdk_app_id, &end, 10);
  if (end == config->im_sdk_app_id || *end != '\0' || im_id == 0 || im_id > 0xffffffffUL) return -1;
  if (now == 0) now = (int64_t)time(NULL);
  if (watch_usersig_generate_at((uint32_t)trtc_id, config->trtc_secret_key, config->device_id,
                                config->usersig_expire_sec, now, config->trtc_usersig,
                                sizeof(config->trtc_usersig)) < 0) return -1;
  if (watch_usersig_generate_at((uint32_t)im_id, config->im_secret_key, config->device_id,
                                config->usersig_expire_sec, now, config->im_usersig,
                                sizeof(config->im_usersig)) < 0) return -1;
  return 0;
}

void watch_config_dump(const watch_config_t *config) {
  if (!config) return;
  printf("watch config: device_id=%s room_id=%s trtc_app_id=%s im_app_id=%s\n",
         config->device_id, config->room_id, config->trtc_sdk_app_id, config->im_sdk_app_id);
  printf("watch config: trtc_usersig=%.8s*** im_usersig=%.8s***\n",
         config->trtc_usersig, config->im_usersig);
}
