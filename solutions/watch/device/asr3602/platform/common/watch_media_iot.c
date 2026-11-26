#include "watch_media_iot.h"

#include <stdlib.h>
#include <string.h>

struct watch_iot_media {
  int entered;
  tc_iot_av_channel_t *audio_channel;
  tc_iot_av_channel_t *video_channel;
  watch_media_content_t content;
  watch_iot_media_input_t input;
  int input_started;
};

static void watch_iot_media_stop(void *user_data);

static int watch_iot_push_audio(const tc_iot_audio_frame *frame, void *user_data) {
  return watch_iot_media_push_audio((watch_iot_media_t *)user_data, frame);
}

static int watch_iot_push_video(const tc_iot_video_frame *frame, void *user_data) {
  return watch_iot_media_push_video((watch_iot_media_t *)user_data, frame);
}

static int watch_iot_media_start(const watch_call_option_t *option, const char *peer, void *user_data) {
  (void)peer;
  watch_iot_media_t *media = (watch_iot_media_t *)user_data;
  if (!media || !media->entered || !option) return -1;
  media->content = option->media_content;
  if (media->content == WATCH_MEDIA_AUDIO || media->content == WATCH_MEDIA_AUDIO_VIDEO) {
    media->audio_channel = tc_iot_create_audio_channel();
    if (!media->audio_channel) return -1;
  }
  if (media->content == WATCH_MEDIA_VIDEO || media->content == WATCH_MEDIA_AUDIO_VIDEO) {
    media->video_channel = tc_iot_create_video_channel(0,
        (tc_iot_video_quality_e)option->video_quality);
    if (!media->video_channel) {
      if (media->audio_channel) tc_iot_destroy_audio_channel(media->audio_channel);
      media->audio_channel = NULL;
      return -1;
    }
  }
  if (media->input.start && media->input.start(option, watch_iot_push_audio,
                                               watch_iot_push_video, media,
                                               media->input.user_data) != 0) {
    if (media->audio_channel) tc_iot_destroy_audio_channel(media->audio_channel);
    if (media->video_channel) tc_iot_destroy_video_channel(media->video_channel);
    media->audio_channel = NULL;
    media->video_channel = NULL;
    return -1;
  }
  media->input_started = media->input.start != NULL;
  return 0;
}

static int watch_iot_media_accept(const char *peer, void *user_data) {
  watch_iot_media_t *media = (watch_iot_media_t *)user_data;
  if (!media || !media->entered || !peer) return -1;
  tc_iot_contact_s contact = {.user_id = peer, .user_name = peer, .avatar_url = ""};
  return tc_iot_av_accept(&contact, NULL) == TC_IOT_ERR_SUCCESS ? 0 : -1;
}

static int watch_iot_media_reject(const char *peer, void *user_data) {
  watch_iot_media_t *media = (watch_iot_media_t *)user_data;
  if (!media || !media->entered || !peer) return -1;
  tc_iot_contact_s contact = {.user_id = peer, .user_name = peer, .avatar_url = ""};
  return tc_iot_av_reject(&contact, NULL) == TC_IOT_ERR_SUCCESS ? 0 : -1;
}

static int watch_iot_media_hangup(const char *peer, void *user_data) {
  watch_iot_media_t *media = (watch_iot_media_t *)user_data;
  if (!media || !media->entered || !peer) return -1;
  tc_iot_contact_s contact = {.user_id = peer, .user_name = peer, .avatar_url = ""};
  tc_iot_error_e result = tc_iot_av_hangup(&contact, NULL);
  watch_iot_media_stop(media);
  return result == TC_IOT_ERR_SUCCESS ? 0 : -1;
}

static void watch_iot_media_stop(void *user_data) {
  watch_iot_media_t *media = (watch_iot_media_t *)user_data;
  if (!media) return;
  if (media->input_started && media->input.stop) media->input.stop(media->input.user_data);
  media->input_started = 0;
  if (media->audio_channel) tc_iot_destroy_audio_channel(media->audio_channel);
  if (media->video_channel) tc_iot_destroy_video_channel(media->video_channel);
  media->audio_channel = NULL;
  media->video_channel = NULL;
}

int watch_iot_media_create(watch_iot_media_t **media, watch_media_backend_t *backend) {
  if (!media || !backend) return -1;
  watch_iot_media_t *context = (watch_iot_media_t *)calloc(1, sizeof(*context));
  if (!context) return -1;
  backend->start = watch_iot_media_start;
  backend->accept = watch_iot_media_accept;
  backend->reject = watch_iot_media_reject;
  backend->hangup = watch_iot_media_hangup;
  backend->stop = watch_iot_media_stop;
  backend->user_data = context;
  *media = context;
  return 0;
}

int watch_iot_media_set_input(watch_iot_media_t *media, const watch_iot_media_input_t *input) {
  if (!media || media->entered || media->audio_channel || media->video_channel) return -1;
  memset(&media->input, 0, sizeof(media->input));
  if (input) media->input = *input;
  return 0;
}

int watch_iot_media_enter(watch_iot_media_t *media, const tc_iot_av_observer_s *observer) {
  if (!media || media->entered) return -1;
  if (tc_iot_av_init(observer) != TC_IOT_ERR_SUCCESS) return -1;
  media->entered = 1;
  return 0;
}

int watch_iot_media_push_audio(watch_iot_media_t *media, const tc_iot_audio_frame *frame) {
  if (!media || !media->audio_channel || !frame) return -1;
  return tc_iot_push_audio_frame(media->audio_channel, frame) == TC_IOT_ERR_SUCCESS ? 0 : -1;
}

int watch_iot_media_push_video(watch_iot_media_t *media, const tc_iot_video_frame *frame) {
  if (!media || !media->video_channel || !frame) return -1;
  return tc_iot_push_video_frame(media->video_channel, frame) == TC_IOT_ERR_SUCCESS ? 0 : -1;
}

void watch_iot_media_leave(watch_iot_media_t *media) {
  if (!media || !media->entered) return;
  watch_iot_media_stop(media);
  (void)tc_iot_av_deinit();
  media->entered = 0;
}

void watch_iot_media_destroy(watch_iot_media_t *media) {
  if (!media) return;
  watch_iot_media_leave(media);
  free(media);
}
