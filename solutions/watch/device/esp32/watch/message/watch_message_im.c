#include "watch_message_im.h"

#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#include "TIMCloudDef.h"
#include "TIMErrorCode.h"
#include "TIMManager.h"
#include "TIMMessageManager.h"
#include "cJSON.h"

typedef struct {
  pthread_mutex_t mutex;
  pthread_cond_t condition;
  int initialized;
  int online;
  int login_result;
  int logout_result;
  void (*on_text)(const char *, const char *, void *);
  void (*on_status)(int, int, const char *, void *);
  void *callback_user_data;
} watch_im_backend_context_t;

static void watch_im_set_result(watch_im_backend_context_t *context, int *result, int value) {
  pthread_mutex_lock(&context->mutex);
  *result = value;
  pthread_cond_broadcast(&context->condition);
  pthread_mutex_unlock(&context->mutex);
}

static int watch_im_wait_result(watch_im_backend_context_t *context, int *result, int timeout_ms) {
  struct timespec deadline;
  clock_gettime(CLOCK_REALTIME, &deadline);
  deadline.tv_sec += timeout_ms / 1000;
  deadline.tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
  if (deadline.tv_nsec >= 1000000000L) {
    ++deadline.tv_sec;
    deadline.tv_nsec -= 1000000000L;
  }
  pthread_mutex_lock(&context->mutex);
  while (*result == 0 && pthread_cond_timedwait(&context->condition, &context->mutex, &deadline) == 0) {}
  int value = *result;
  pthread_mutex_unlock(&context->mutex);
  return value;
}

static void watch_im_mkdir(const char *path) {
  if (!path || !path[0]) return;
  char buffer[512];
  snprintf(buffer, sizeof(buffer), "%s", path);
  for (char *p = buffer + 1; *p; ++p) {
    if (*p == '/') {
      *p = '\0';
      (void)mkdir(buffer, 0755);
      *p = '/';
    }
  }
  (void)mkdir(buffer, 0755);
}

static void watch_im_login(int32_t code, const char *desc, const char *json, const void *user_data) {
  (void)json;
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  watch_im_set_result(context, &context->login_result, code == ERR_SUCC ? 1 : -1);
  if (context->on_status) context->on_status(code == ERR_SUCC, code, desc, context->callback_user_data);
}

static void watch_im_logout(int32_t code, const char *desc, const char *json, const void *user_data) {
  (void)desc;
  (void)json;
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  watch_im_set_result(context, &context->logout_result, code == ERR_SUCC ? 1 : -1);
}

static void watch_im_send_result(int32_t code, const char *desc, const char *json, const void *user_data) {
  (void)json;
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  if (code != ERR_SUCC && context->on_status) context->on_status(1, code, desc, context->callback_user_data);
}

static void watch_im_network(enum TIMNetworkStatus status, int32_t code, const char *desc,
                             const void *user_data) {
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  // 每次网络状态变化都上报（含恢复为 kTIMConnected）。原先只报非 Connected 状态：
  // 网络一抖 im_online 被置 0，IM SDK 自动重连成功后却不会置回 1，状态永久失真。
  // status 文案放进 desc 前缀，便于从日志直接看出 Disconnected/Connecting/ConnectFailed。
  static const char *const kNames[] = {"connected", "disconnected", "connecting", "connect_failed"};
  const char *name = ((unsigned)status < sizeof(kNames) / sizeof(kNames[0])) ? kNames[status] : "unknown";
  char text[96];
  snprintf(text, sizeof(text), "network %s%s%s", name, (desc && desc[0]) ? ": " : "", desc ? desc : "");
  if (context->on_status) context->on_status(status == kTIMConnected, code, text, context->callback_user_data);
}

static void watch_im_kicked(const void *user_data) {
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  pthread_mutex_lock(&context->mutex);
  context->online = 0;
  pthread_mutex_unlock(&context->mutex);
  if (context->on_status) context->on_status(0, 0, "kicked offline", context->callback_user_data);
}

static void watch_im_expired(const void *user_data) {
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  pthread_mutex_lock(&context->mutex);
  context->online = 0;
  pthread_mutex_unlock(&context->mutex);
  if (context->on_status) context->on_status(0, 0, "UserSig expired", context->callback_user_data);
}

static void watch_im_receive(const char *json_array, const void *user_data) {
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  cJSON *array = cJSON_Parse(json_array);
  if (!cJSON_IsArray(array)) {
    cJSON_Delete(array);
    return;
  }
  cJSON *message = NULL;
  cJSON_ArrayForEach(message, array) {
    cJSON *type = cJSON_GetObjectItemCaseSensitive(message, kTIMMsgConvType);
    if (cJSON_IsNumber(type) && type->valueint != kTIMConv_C2C) continue;
    cJSON *self = cJSON_GetObjectItemCaseSensitive(message, kTIMMsgIsFormSelf);
    if (cJSON_IsTrue(self)) continue;
    cJSON *sender = cJSON_GetObjectItemCaseSensitive(message, kTIMMsgSender);
    cJSON *elements = cJSON_GetObjectItemCaseSensitive(message, kTIMMsgElemArray);
    if (!cJSON_IsString(sender) || !sender->valuestring || !cJSON_IsArray(elements)) continue;
    cJSON *element = NULL;
    cJSON_ArrayForEach(element, elements) {
      cJSON *element_type = cJSON_GetObjectItemCaseSensitive(element, kTIMElemType);
      cJSON *text = cJSON_GetObjectItemCaseSensitive(element, kTIMTextElemContent);
      if (cJSON_IsNumber(element_type) && element_type->valueint == kTIMElem_Text &&
          cJSON_IsString(text) && text->valuestring && context->on_text) {
        context->on_text(sender->valuestring, text->valuestring, context->callback_user_data);
      }
    }
  }
  cJSON_Delete(array);
}

static int watch_im_start(uint64_t sdk_app_id, const char *user_id, const char *user_sig,
                          const char *data_path,
                          void (*on_text)(const char *, const char *, void *),
                          void (*on_status)(int, int, const char *, void *),
                          void *callback_user_data, void *backend_user_data) {
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)backend_user_data;
  if (!context || !user_id || !user_sig || sdk_app_id == 0 || context->initialized) return -1;
  context->on_text = on_text;
  context->on_status = on_status;
  context->callback_user_data = callback_user_data;
  watch_im_mkdir(data_path);
  cJSON *config = cJSON_CreateObject();
  cJSON_AddStringToObject(config, kTIMSdkConfigConfigFilePath, data_path ? data_path : "./watch_im_data");
  cJSON_AddStringToObject(config, kTIMSdkConfigLogFilePath, data_path ? data_path : "./watch_im_data");
  cJSON_AddBoolToObject(config, kTIMSdkConfigDisableCallbackOnMainThread, 1);
  char *config_json = cJSON_PrintUnformatted(config);
  cJSON_Delete(config);
  if (!config_json || TIMInit(sdk_app_id, config_json) != TIM_SUCC) {
    if (config_json) cJSON_free(config_json);
    return -1;
  }
  cJSON_free(config_json);
  context->initialized = 1;
  TIMSetNetworkStatusListenerCallback(watch_im_network, context);
  TIMSetKickedOfflineCallback(watch_im_kicked, context);
  TIMSetUserSigExpiredCallback(watch_im_expired, context);
  TIMAddRecvNewMsgCallback(watch_im_receive, context);
  context->login_result = 0;
  if (TIMLogin(user_id, user_sig, watch_im_login, context) != TIM_SUCC ||
      watch_im_wait_result(context, &context->login_result, 10000) != 1) {
    TIMRemoveRecvNewMsgCallback(watch_im_receive);
    TIMUninit();
    context->initialized = 0;
    return -1;
  }
  pthread_mutex_lock(&context->mutex);
  context->online = 1;
  pthread_mutex_unlock(&context->mutex);
  return 0;
}

static int watch_im_send(const char *to_user_id, const char *text, int online, void *user_data) {
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  if (!context || !to_user_id || !text || !context->online) return -1;
  cJSON *message = cJSON_CreateObject();
  cJSON *elements = cJSON_AddArrayToObject(message, kTIMMsgElemArray);
  cJSON *element = cJSON_CreateObject();
  cJSON_AddNumberToObject(element, kTIMElemType, kTIMElem_Text);
  cJSON_AddStringToObject(element, kTIMTextElemContent, text);
  cJSON_AddItemToArray(elements, element);
  if (online) cJSON_AddBoolToObject(message, kTIMMsgIsOnlineMsg, 1);
  char *message_json = cJSON_PrintUnformatted(message);
  cJSON_Delete(message);
  if (!message_json) return -1;
  char message_id[128] = {0};
  int result = TIMMsgSendMessage(to_user_id, kTIMConv_C2C, message_json, message_id,
                                 watch_im_send_result, context);
  cJSON_free(message_json);
  return result == TIM_SUCC ? 0 : -1;
}

static void watch_im_stop(int timeout_ms, void *user_data) {
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)user_data;
  if (!context || !context->initialized) return;
  TIMRemoveRecvNewMsgCallback(watch_im_receive);
  if (context->online) {
    context->logout_result = 0;
    if (TIMLogout(watch_im_logout, context) == TIM_SUCC && timeout_ms > 0) {
      (void)watch_im_wait_result(context, &context->logout_result, timeout_ms);
    }
  }
  TIMUninit();
  context->initialized = 0;
  context->online = 0;
}

int watch_message_im_backend_create(watch_message_backend_t *backend) {
  if (!backend) return -1;
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)calloc(1, sizeof(*context));
  if (!context) return -1;
  pthread_mutex_init(&context->mutex, NULL);
  pthread_cond_init(&context->condition, NULL);
  backend->start = watch_im_start;
  backend->send = watch_im_send;
  backend->stop = watch_im_stop;
  backend->user_data = context;
  return 0;
}

void watch_message_im_backend_destroy(watch_message_backend_t *backend) {
  if (!backend || !backend->user_data) return;
  watch_im_backend_context_t *context = (watch_im_backend_context_t *)backend->user_data;
  watch_im_stop(3000, context);
  pthread_cond_destroy(&context->condition);
  pthread_mutex_destroy(&context->mutex);
  free(context);
  memset(backend, 0, sizeof(*backend));
}
