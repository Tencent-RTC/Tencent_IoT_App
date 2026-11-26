// Copyright (c) 2026 Tencent. All rights reserved.

#ifndef __TC_IOT_PLAYBACK_H__
#define __TC_IOT_PLAYBACK_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

#include "tc_iot_av.h"
#include "tc_iot_err.h"

#define TC_IOT_PLAYBACK_FILE_NAME_LEN (128)
#define TC_IOT_PLAYBACK_DATE_LEN (16)

typedef struct {
  char file_name[TC_IOT_PLAYBACK_FILE_NAME_LEN];
  uint64_t start_time_utc_seconds;
  int32_t duration_ms;
  char custom_data[MAX_CUSTOM_DATA_LENGTH];
} tc_iot_playback_item_t;

typedef enum {
  TC_IOT_PLAYBACK_COMMAND_START = 1,
  TC_IOT_PLAYBACK_COMMAND_STOP = 2,
  TC_IOT_PLAYBACK_COMMAND_PAUSE = 3,
  TC_IOT_PLAYBACK_COMMAND_RESUME = 4,
  TC_IOT_PLAYBACK_COMMAND_SEEK = 5,
  TC_IOT_PLAYBACK_COMMAND_SET_SPEED = 6,
  TC_IOT_PLAYBACK_COMMAND_MAX = 7
} tc_iot_playback_command_type_t;

typedef struct tc_iot_playback_command {
  tc_iot_playback_command_type_t command_type;
  const char *file_name;
  int32_t seek_position_ms;
  int32_t playback_speed;
  char custom_data[MAX_CUSTOM_DATA_LENGTH];
} tc_iot_playback_command_t;

typedef struct {
  int (*on_request_date_list)(int channel_id, char dates[][TC_IOT_PLAYBACK_DATE_LEN], uint32_t max_date_count);

  int (*on_request_file_list)(int channel_id, uint64_t start_time_utc_seconds, tc_iot_playback_item_t *playback_list,
                              uint32_t max_playback_item_count);

  int (*on_receive_playback_command)(int channel_id, tc_iot_playback_command_t *command);
} tc_iot_playback_observer_s;

tc_iot_error_e tc_iot_playback_init(const tc_iot_playback_observer_s *observer);
tc_iot_error_e tc_iot_playback_deinit(void);

#ifdef __cplusplus
}
#endif

#endif /* __TC_IOT_PLAYBACK_H__ */
