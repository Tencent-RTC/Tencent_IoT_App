// W317 watch 配置模板：编译期固化进客户固件，修改后需要重新编译烧录。
//
// 只修改下面 6 项。当前文件只包含占位值，不能写入真实 SecretKey 后提交到公开仓库。

#ifndef WATCH_CONFIG_BUILTIN_H
#define WATCH_CONFIG_BUILTIN_H

/* 必填：TRTC 账号 */
#define WATCH_CFG_TRTC_SDK_APP_ID "1400000000"
#define WATCH_CFG_TRTC_SECRET_KEY "replace-with-trtc-secret"

/* 必填：IM 账号 */
#define WATCH_CFG_IM_SDK_APP_ID "1600000000"
#define WATCH_CFG_IM_SECRET_KEY "replace-with-im-secret"

/* 必填：设备 ID，手机呼叫时使用 */
#define WATCH_CFG_DEVICE_ID "watch_device"

/* 必填：通话房间号，手机端使用同一个房间号 */
#define WATCH_CFG_ROOM_ID "room_1"

/* ---------- 以下为平台适配项 ---------- */

/* TODO(W317): 由客户确认可写的数据盘和 IM 存储目录。 */
#define WATCH_CFG_STORAGE_PATH "/data/watch"
#define WATCH_CFG_IM_DATA_PATH "/data/watch"

#define WATCH_CFG_USERSIG_EXPIRE_SEC 604800
#define WATCH_CFG_AUTO_ACCEPT_DELAY_SEC 0
#define WATCH_CFG_CALL_TIMEOUT_SEC 30

#endif  // WATCH_CONFIG_BUILTIN_H
