#ifndef WATCH_MEDIA_IOT_H
#define WATCH_MEDIA_IOT_H

#include "watch/media.h"

#include "tc_iot_av.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct watch_iot_media watch_iot_media_t;

typedef int (*watch_iot_push_audio_callback)(const tc_iot_audio_frame *frame, void *user_data);
typedef int (*watch_iot_push_video_callback)(const tc_iot_video_frame *frame, void *user_data);
typedef int (*watch_iot_input_start_callback)(const watch_call_option_t *option,
                                              watch_iot_push_audio_callback push_audio,
                                              watch_iot_push_video_callback push_video,
                                              void *push_user_data, void *user_data);
typedef void (*watch_iot_input_stop_callback)(void *user_data);

typedef struct {
  watch_iot_input_start_callback start;
  watch_iot_input_stop_callback stop;
  void *user_data;
} watch_iot_media_input_t;

int watch_iot_media_create(watch_iot_media_t **media, watch_media_backend_t *backend);
int watch_iot_media_set_input(watch_iot_media_t *media, const watch_iot_media_input_t *input);
int watch_iot_media_enter(watch_iot_media_t *media, const tc_iot_av_observer_s *observer);
int watch_iot_media_push_audio(watch_iot_media_t *media, const tc_iot_audio_frame *frame);
int watch_iot_media_push_video(watch_iot_media_t *media, const tc_iot_video_frame *frame);
void watch_iot_media_leave(watch_iot_media_t *media);
void watch_iot_media_destroy(watch_iot_media_t *media);

#ifdef __cplusplus
}
#endif

#endif
