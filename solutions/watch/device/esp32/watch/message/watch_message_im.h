#ifndef WATCH_MESSAGE_IM_H
#define WATCH_MESSAGE_IM_H

#include "watch/message.h"

#ifdef __cplusplus
extern "C" {
#endif

int watch_message_im_backend_create(watch_message_backend_t *backend);
void watch_message_im_backend_destroy(watch_message_backend_t *backend);

#ifdef __cplusplus
}
#endif

#endif
