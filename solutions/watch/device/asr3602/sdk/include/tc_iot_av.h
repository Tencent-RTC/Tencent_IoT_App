// Copyright (c) 2026 Tencent. All rights reserved.

#ifndef __TC_IOT_AV_H__
#define __TC_IOT_AV_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "tc_iot_def.h"
#include "tc_iot_err.h"

#define MAX_CUSTOM_DATA_LENGTH (256)

typedef struct tc_iot_av_channel_s tc_iot_av_channel_t;

typedef struct {
  const char *user_id;
  const char *user_name;
  const char *avatar_url;
} tc_iot_contact_s;

typedef struct tc_iot_call_option_s {
  tc_iot_media_content_e media_content;
  tc_iot_video_quality_e video_quality;
  char custom_data[MAX_CUSTOM_DATA_LENGTH];
} tc_iot_call_option_t;

typedef enum {
  PTZ_CMD_UP = 0,
  PTZ_CMD_DOWN = 1,
  PTZ_CMD_LEFT = 2,
  PTZ_CMD_RIGHT = 3,
  PTZ_CMD_ZOOM_IN = 4,
  PTZ_CMD_ZOOM_OUT = 5,
  PTZ_CMD_STOP = 6
} ptz_command_e;

typedef struct {
  // 呼叫事件回调。注意：trtc adapter 后端下呼叫信令与状态机已下沉 demo 层
  // （用 ImSDK 实现），SDK 的 tc_iot_av_call/accept/reject/hangup 为空实现，
  // 因此这 5 个回调在 trtc 后端下不会再被触发。保留字段仅为 API 形态兼容
  // （mqtt 等其他后端仍会触发）。使用 trtc 后端的 demo 应把这几个回调留空
  // 或空实现，改由 demo 层 call_engine 的 ce_observer 承载呼叫事件。
  void (*on_call_requested)(const tc_iot_contact_s *contact, tc_iot_call_option_t option);
  void (*on_call_accepted)(const tc_iot_contact_s *contact);
  void (*on_call_rejected)(const tc_iot_contact_s *contact);
  void (*on_call_timeout)(const tc_iot_contact_s *contact);
  void (*on_call_hangup)(const tc_iot_contact_s *contact);

  // 远端用户进出房间通知（纯粹是"物理上是否同在一个房间"）。
  // 目前仅 adapter_trtc 后端实现并会调用这两个回调；其他后端未触发时，
  // 这两个字段保持 NULL 即可，可选实现，不影响其余回调正常工作。
  // 典型用途：不知道对端真实 user_id 时，用这两个回调发现"当前房间里有谁"。
  void (*on_remote_user_enter_room)(const tc_iot_contact_s *contact);
  void (*on_remote_user_exit_room)(const tc_iot_contact_s *contact);

  void (*on_monitor_begin)(int channel_id, tc_iot_call_option_t option);
  void (*on_monitor_switch)(int channel_id, tc_iot_video_quality_e quality);
  void (*on_monitor_end)(int channel_id);

  void (*on_ptz_command_received)(int channel_id, ptz_command_e ptz_command, int speed);
  void (*on_audio_frame_received)(const tc_iot_audio_frame *frame);
  void (*on_video_frame_received)(const tc_iot_video_frame *frame);
} tc_iot_av_observer_s;

typedef void (*tc_iot_av_operation_cb)(tc_iot_error_e error_code, const char *error_message);

typedef void (*tc_iot_av_contacts_cb)(tc_iot_error_e error_code, const char *error_message,
                                      const tc_iot_contact_s *contacts, uint32_t count, const char *next_cursor);

tc_iot_error_e tc_iot_av_init(const tc_iot_av_observer_s *observer);
tc_iot_error_e tc_iot_av_deinit(void);

tc_iot_error_e tc_iot_av_get_contacts(const char *cursor, uint32_t limit, tc_iot_av_contacts_cb callback);

tc_iot_error_e tc_iot_av_call(const tc_iot_contact_s *contact, tc_iot_call_option_t option,
                              tc_iot_av_operation_cb callback);
tc_iot_error_e tc_iot_av_accept(const tc_iot_contact_s *contact, tc_iot_av_operation_cb callback);
tc_iot_error_e tc_iot_av_reject(const tc_iot_contact_s *contact, tc_iot_av_operation_cb callback);
tc_iot_error_e tc_iot_av_hangup(const tc_iot_contact_s *contact, tc_iot_av_operation_cb callback);

tc_iot_av_channel_t *tc_iot_create_video_channel(int channel_id, tc_iot_video_quality_e quality);
tc_iot_av_channel_t *tc_iot_create_audio_channel();

tc_iot_error_e tc_iot_destroy_video_channel(tc_iot_av_channel_t *av_channel);
tc_iot_error_e tc_iot_destroy_audio_channel(tc_iot_av_channel_t *av_channel);

tc_iot_error_e tc_iot_push_video_frame(tc_iot_av_channel_t *av_channel, const tc_iot_video_frame *frame);
tc_iot_error_e tc_iot_push_audio_frame(tc_iot_av_channel_t *av_channel, const tc_iot_audio_frame *frame);

#ifdef __cplusplus
}
#endif

#endif /* __TC_IOT_AV_H__ */
