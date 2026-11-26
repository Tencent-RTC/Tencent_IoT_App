#ifndef WATCH_MESSAGE_H
#define WATCH_MESSAGE_H

#include <stddef.h>
#include <stdint.h>

#include "watch/types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct watch_message watch_message_t;

typedef void (*watch_message_text_callback)(const char *from_user_id, const char *text,
                                            void *user_data);
typedef void (*watch_message_status_callback)(int online, int code, const char *description,
                                              void *user_data);

typedef struct {
  int (*start)(uint64_t sdk_app_id, const char *user_id, const char *user_sig,
               const char *data_path, void (*on_text)(const char *, const char *, void *),
               void (*on_status)(int, int, const char *, void *), void *callback_user_data,
               void *backend_user_data);
  int (*send)(const char *to_user_id, const char *text, int online, void *user_data);
  void (*stop)(int timeout_ms, void *user_data);
  void *user_data;
} watch_message_backend_t;

typedef struct {
  uint64_t sdk_app_id;
  const char *user_id;
  const char *user_sig;
  const char *data_path;
  watch_message_text_callback on_text;
  watch_message_status_callback on_status;
  void *user_data;
  watch_message_backend_t backend;
} watch_message_config_t;

watch_message_t *watch_message_create(const watch_message_config_t *config);
int watch_message_start(watch_message_t *message);
int watch_message_send(watch_message_t *message, const char *to_user_id, const char *text);
int watch_message_send_chat(watch_message_t *message, const char *to_user_id, const char *text);
int watch_message_is_online(const watch_message_t *message);
void watch_message_stop(watch_message_t *message, int timeout_ms);
void watch_message_destroy(watch_message_t *message);

void watch_message_backend_deliver_text(const char *from_user_id, const char *text,
                                        void *user_data);
void watch_message_backend_report_status(int online, int code, const char *description,
                                         void *user_data);

#ifdef __cplusplus
}
#endif

#endif
