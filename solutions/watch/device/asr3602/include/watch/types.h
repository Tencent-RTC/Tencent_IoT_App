#ifndef WATCH_TYPES_H
#define WATCH_TYPES_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WATCH_USER_ID_MAX 64
#define WATCH_DEVICE_ID_MAX 64
#define WATCH_SECRET_MAX 128
#define WATCH_USERSIG_MAX 512
#define WATCH_ROOM_ID_MAX 128
#define WATCH_CUSTOM_DATA_MAX 128

typedef enum {
  WATCH_MEDIA_UNKNOWN = 0,
  WATCH_MEDIA_AUDIO = 1,
  WATCH_MEDIA_VIDEO = 2,
  WATCH_MEDIA_AUDIO_VIDEO = 3,
} watch_media_content_t;

typedef enum {
  WATCH_VIDEO_QUALITY_UNKNOWN = 0,
  WATCH_VIDEO_QUALITY_LD = 1,
  WATCH_VIDEO_QUALITY_SD = 2,
  WATCH_VIDEO_QUALITY_HD = 3,
  WATCH_VIDEO_QUALITY_FHD = 4,
} watch_video_quality_t;

typedef struct {
  watch_media_content_t media_content;
  watch_video_quality_t video_quality;
  char custom_data[WATCH_CUSTOM_DATA_MAX];
} watch_call_option_t;

#ifdef __cplusplus
}
#endif

#endif
