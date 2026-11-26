// Copyright (c) 2026 Tencent. All rights reserved.
//
// W317 watch 对外入口。
//
// 当前版本只提供平台适配骨架。客户需要在 watch_entry_w317.c 以及相关平台文件中
// 接入真实的 W317 RTOS、网络、音视频和显示接口后，才能完成编译和运行。

#ifndef WATCH_W317_H
#define WATCH_W317_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * 创建并启动 watch 任务后立即返回，不阻塞客户应用界面。
 * 重复调用返回 0；平台初始化或启动失败返回负值。
 */
int watch_start(void);

/*
 * 停止 watch 任务并释放平台资源。
 * 未启动或重复调用返回 0；停止失败返回负值。
 */
int watch_stop(void);

#ifdef __cplusplus
}
#endif

#endif  // WATCH_W317_H
