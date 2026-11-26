#include "watch/signaling.h"

#include <string.h>

#include "cJSON.h"

static const char *watch_signal_type_string(watch_signal_type_t type) {
  switch (type) {
    case WATCH_SIGNAL_CALL: return "call";
    case WATCH_SIGNAL_ACCEPT: return "accept";
    case WATCH_SIGNAL_REJECT: return "reject";
    case WATCH_SIGNAL_HANGUP: return "hangup";
    default: return NULL;
  }
}

static watch_signal_type_t watch_signal_type_from_string(const char *value) {
  if (!value) return WATCH_SIGNAL_UNKNOWN;
  if (strcmp(value, "call") == 0) return WATCH_SIGNAL_CALL;
  if (strcmp(value, "accept") == 0) return WATCH_SIGNAL_ACCEPT;
  if (strcmp(value, "reject") == 0) return WATCH_SIGNAL_REJECT;
  if (strcmp(value, "hangup") == 0) return WATCH_SIGNAL_HANGUP;
  return WATCH_SIGNAL_UNKNOWN;
}

const char *watch_signal_reason_string(watch_signal_reason_t reason) {
  switch (reason) {
    case WATCH_SIGNAL_REASON_DECLINE: return "decline";
    case WATCH_SIGNAL_REASON_BUSY: return "busy";
    case WATCH_SIGNAL_REASON_CANCEL: return "cancel";
    case WATCH_SIGNAL_REASON_USER_HANGUP: return "user_hangup";
    default: return "";
  }
}

static watch_signal_reason_t watch_signal_reason_from_string(const char *value) {
  if (!value) return WATCH_SIGNAL_REASON_NONE;
  if (strcmp(value, "decline") == 0) return WATCH_SIGNAL_REASON_DECLINE;
  if (strcmp(value, "busy") == 0) return WATCH_SIGNAL_REASON_BUSY;
  if (strcmp(value, "cancel") == 0) return WATCH_SIGNAL_REASON_CANCEL;
  if (strcmp(value, "user_hangup") == 0) return WATCH_SIGNAL_REASON_USER_HANGUP;
  return WATCH_SIGNAL_REASON_NONE;
}

size_t watch_signal_encode(const watch_signal_message_t *message, char *buffer, size_t size) {
  if (!message || !buffer || size == 0 || !message->to[0] || !watch_signal_type_string(message->type)) {
    return 0;
  }
  cJSON *root = cJSON_CreateObject();
  if (!root) return 0;
  cJSON_AddNumberToObject(root, "v", 1);
  cJSON_AddStringToObject(root, "t", watch_signal_type_string(message->type));
  cJSON_AddNumberToObject(root, "sid", (double)message->sid);
  cJSON_AddStringToObject(root, "to", message->to);
  if (message->type == WATCH_SIGNAL_CALL) {
    cJSON_AddNumberToObject(root, "mc", message->option.media_content);
    cJSON_AddNumberToObject(root, "vq", message->option.video_quality);
    if (message->option.custom_data[0]) {
      char custom_data[WATCH_CUSTOM_DATA_MAX];
      memcpy(custom_data, message->option.custom_data, sizeof(custom_data));
      custom_data[sizeof(custom_data) - 1] = '\0';
      cJSON_AddStringToObject(root, "cd", custom_data);
    }
  } else if (message->type == WATCH_SIGNAL_REJECT || message->type == WATCH_SIGNAL_HANGUP) {
    const char *reason = watch_signal_reason_string(message->reason);
    if (reason[0]) cJSON_AddStringToObject(root, "rs", reason);
  }
  char *encoded = cJSON_PrintUnformatted(root);
  cJSON_Delete(root);
  if (!encoded) return 0;
  size_t length = strlen(encoded);
  if (length + 1 > size) {
    cJSON_free(encoded);
    return 0;
  }
  memcpy(buffer, encoded, length + 1);
  cJSON_free(encoded);
  return length;
}

static int watch_json_integer(const cJSON *item, int *value) {
  if (!cJSON_IsNumber(item) || item->valuedouble != (double)item->valueint) return -1;
  *value = item->valueint;
  return 0;
}

// sid 专用：不能走 watch_json_integer。
//
// sid 的类型是 uint32_t（见 watch/signaling.h），合法范围 0..4294967295，而
// cJSON 的 valueint 是 int，对超出 INT_MAX 的数值做饱和截断（cJSON.c:489
// "use saturation in case of overflow"）。于是 watch_json_integer 里的
// `valuedouble != (double)valueint` 必然不等，整条信令被当成格式错误静默丢弃。
//
// 实测故障：手机侧发来 sid=3548651868（合法 uint32，但 > INT_MAX 2147483647），
// 设备收到了 call 文本却不回 accept，手机一直停在「等待对方接听」。
// 本端自己生成的 sid 从 1 开始自增（watch_signaling.c:46），实际永远不会超过
// INT_MAX，所以主叫方向一直正常，这个 bug 只在被叫方向暴露。
//
// 因此改用 valuedouble 判断范围，不经过 valueint。
static int watch_json_uint32(const cJSON *item, uint32_t *value) {
  if (!cJSON_IsNumber(item)) return -1;
  double number = item->valuedouble;
  // 必须是无小数部分的非负整数，且在 uint32 范围内。
  if (number < 0.0 || number > 4294967295.0) return -1;
  if (number != (double)(uint32_t)number) return -1;
  *value = (uint32_t)number;
  return 0;
}

int watch_signal_decode(const char *json, size_t length, watch_signal_message_t *message) {
  if (!json || length == 0 || !message) return 0;
  char *input = (char *)cJSON_malloc(length + 1);
  if (!input) return 0;
  memcpy(input, json, length);
  input[length] = '\0';
  cJSON *root = cJSON_ParseWithLength(input, length);
  cJSON_free(input);
  if (!root || !cJSON_IsObject(root)) {
    cJSON_Delete(root);
    return 0;
  }
  memset(message, 0, sizeof(*message));
  int value = 0;
  uint32_t sid_value = 0;
  cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "v");
  cJSON *type = cJSON_GetObjectItemCaseSensitive(root, "t");
  cJSON *sid = cJSON_GetObjectItemCaseSensitive(root, "sid");
  cJSON *to = cJSON_GetObjectItemCaseSensitive(root, "to");
  int valid = watch_json_integer(version, &value) == 0 && value == 1 &&
              cJSON_IsString(type) && cJSON_IsString(to) && to->valuestring && to->valuestring[0] &&
              strlen(to->valuestring) < sizeof(message->to) &&
              watch_json_uint32(sid, &sid_value) == 0;
  if (!valid) {
    cJSON_Delete(root);
    return 0;
  }
  message->type = watch_signal_type_from_string(type->valuestring);
  message->sid = sid_value;
  strcpy(message->to, to->valuestring);
  if (message->type == WATCH_SIGNAL_UNKNOWN) {
    cJSON_Delete(root);
    return 0;
  }
  if (message->type == WATCH_SIGNAL_CALL) {
    cJSON *mc = cJSON_GetObjectItemCaseSensitive(root, "mc");
    cJSON *vq = cJSON_GetObjectItemCaseSensitive(root, "vq");
    if (watch_json_integer(mc, &value) != 0 || value < WATCH_MEDIA_AUDIO || value > WATCH_MEDIA_AUDIO_VIDEO) {
      cJSON_Delete(root);
      return 0;
    }
    message->option.media_content = (watch_media_content_t)value;
    message->option.video_quality = WATCH_VIDEO_QUALITY_UNKNOWN;
    if (vq) {
      if (watch_json_integer(vq, &value) != 0 || value < 0 || value > WATCH_VIDEO_QUALITY_FHD) {
        cJSON_Delete(root);
        return 0;
      }
      message->option.video_quality = (watch_video_quality_t)value;
    }
    cJSON *custom_data = cJSON_GetObjectItemCaseSensitive(root, "cd");
    if (custom_data) {
      if (!cJSON_IsString(custom_data) || !custom_data->valuestring ||
          strlen(custom_data->valuestring) >= sizeof(message->option.custom_data)) {
        cJSON_Delete(root);
        return 0;
      }
      strcpy(message->option.custom_data, custom_data->valuestring);
    }
  } else if (message->type == WATCH_SIGNAL_REJECT || message->type == WATCH_SIGNAL_HANGUP) {
    cJSON *reason = cJSON_GetObjectItemCaseSensitive(root, "rs");
    if (reason && !cJSON_IsString(reason)) {
      cJSON_Delete(root);
      return 0;
    }
    message->reason = watch_signal_reason_from_string(reason ? reason->valuestring : NULL);
  }
  cJSON_Delete(root);
  return 1;
}
