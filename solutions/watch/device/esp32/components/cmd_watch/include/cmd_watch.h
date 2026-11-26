#ifndef CMD_WATCH_H
#define CMD_WATCH_H

#ifdef __cplusplus
extern "C" {
#endif

/* 注册 watch_start / watch_stop / watch_call / watch_hangup / watch_msg / watch_state。 */
void register_watch_commands(void);

#ifdef __cplusplus
}
#endif

#endif
