// watch 配置：编译期固化进固件，改完需要重新编译烧录才生效。
//
// 只需修改下面 6 项（TRTC / IM 两套账号 + 设备 ID + 房间号），手机 App 须使用同一套账号。
// 填好后本文件含明文 SecretKey，只适合开发调试，不要提交或推送到公开仓库。

#ifndef WATCH_CONFIG_BUILTIN_H
#define WATCH_CONFIG_BUILTIN_H

/* 必填：TRTC 账号 */
#define WATCH_CFG_TRTC_SDK_APP_ID "1400000000"            // 换成你的 TRTC SDKAppID
#define WATCH_CFG_TRTC_SECRET_KEY "replace-with-trtc-secret" // 换成你的 TRTC SecretKey

/* 必填：IM 账号 */
#define WATCH_CFG_IM_SDK_APP_ID "1600000000"              // 换成你的 IM SDKAppID
#define WATCH_CFG_IM_SECRET_KEY "replace-with-im-secret"  // 换成你的 IM SecretKey

/* 必填：设备 ID，手机呼叫时填这个名字 */
#define WATCH_CFG_DEVICE_ID "watch_device"

/* 通话房间号：手机端必须填同一个 */
#define WATCH_CFG_ROOM_ID "room_1"

/* ---------- 以下一般无需修改 ---------- */

/* 本地数据目录：ESP32 上为 SPIFFS 挂载点（storage 分区）。 */
#define WATCH_CFG_STORAGE_PATH "/data"
#define WATCH_CFG_IM_DATA_PATH "/data"

/* UserSig 有效期（秒），设备在本地用 SecretKey 生成。 */
#define WATCH_CFG_USERSIG_EXPIRE_SEC 604800

/* 来电自动接听延时（秒），0 表示立即接听。 */
#define WATCH_CFG_AUTO_ACCEPT_DELAY_SEC 0

/* 呼叫等待对方应答的超时时间（秒）。 */
#define WATCH_CFG_CALL_TIMEOUT_SEC 30

#endif
