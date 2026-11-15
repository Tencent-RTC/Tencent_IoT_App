#include "watch/message.h"

#include <stdlib.h>
#include <string.h>

struct watch_message {
  watch_message_config_t config;
  int online;
  int started;
};

watch_message_t *watch_message_create(const watch_message_config_t *config) {
  if (!config || !config->backend.start || !config->backend.send || !config->backend.stop ||
      !config->user_id || !config->user_id[0] || !config->user_sig || !config->user_sig[0]) {
    return NULL;
  }
  watch_message_t *message = (watch_message_t *)calloc(1, sizeof(*message));
  if (!message) return NULL;
  message->config = *config;
  return message;
}

int watch_message_start(watch_message_t *message) {
  if (!message || message->started) return -1;
  int result = message->config.backend.start(
      message->config.sdk_app_id, message->config.user_id, message->config.user_sig,
      message->config.data_path,
      watch_message_backend_deliver_text,
      watch_message_backend_report_status, message,
      message->config.backend.user_data);
  if (result == 0) {
    message->started = 1;
    message->online = 1;
  }
  return result;
}

int watch_message_send(watch_message_t *message, const char *to_user_id, const char *text) {
  if (!message || !message->started || !to_user_id || !to_user_id[0] || !text) return -1;
  return message->config.backend.send(to_user_id, text, 1, message->config.backend.user_data);
}

int watch_message_send_chat(watch_message_t *message, const char *to_user_id, const char *text) {
  if (!message || !message->started || !to_user_id || !to_user_id[0] || !text) return -1;
  return message->config.backend.send(to_user_id, text, 0, message->config.backend.user_data);
}

int watch_message_is_online(const watch_message_t *message) { return message && message->online; }

void watch_message_stop(watch_message_t *message, int timeout_ms) {
  if (!message || !message->started) return;
  message->config.backend.stop(timeout_ms, message->config.backend.user_data);
  message->started = 0;
  message->online = 0;
}

void watch_message_destroy(watch_message_t *message) {
  if (!message) return;
  watch_message_stop(message, 3000);
  free(message);
}

void watch_message_backend_deliver_text(const char *from_user_id, const char *text,
                                        void *user_data) {
  watch_message_t *message = (watch_message_t *)user_data;
  if (message && message->config.on_text) {
    message->config.on_text(from_user_id, text, message->config.user_data);
  }
}

void watch_message_backend_report_status(int online, int code, const char *description,
                                         void *user_data) {
  watch_message_t *message = (watch_message_t *)user_data;
  if (!message) return;
  message->online = online != 0;
  if (message->config.on_status) {
    message->config.on_status(online, code, description, message->config.user_data);
  }
}
