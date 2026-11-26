# ESP32-S31 跑通 watch

本文手把手教你在 ESP32-S31 开发板上跑通 **watch** 示例：设备开机后登录 IM，手机呼叫设备即可进行**双向音视频通话**。

1. **准备硬件**：一块开发板 + 一根 USB 数据线。
2. **搭建环境**：安装乐鑫 ESP-IDF v6.1。
3. **下载源码并填账号**：改一个配置文件。
4. **编译烧录**：3 条命令。
5. **运行测试**：连 Wi-Fi、启动 watch、手机呼叫。

## 第 1 步：准备硬件

| 开发板 | 板载外设 | ESP-IDF 版本 |
|---|---|---|
| [ESP32-S31-Korvo-1](https://esp32-s31.espressif.com/zh-hans/docs/1-开发板资源/ESP32-S31-Korvo-1) | 摄像头 + 麦克风 + 扬声器；屏幕需另接 ESP32-S3-LCD-EV-Board-SUB3 子板（不接也能通话，只是看不到手机画面） | v6.1 |

另外准备：

- 一根 **USB 数据线**（注意不是只能充电的线），插在开发板标有 **UART** 的 USB 口上。
- 一个 **2.4GHz Wi-Fi**（路由器或手机热点均可，ESP32 不支持 5GHz）。
- 一部装好对端 App 的**手机**，用来呼叫设备。

## 第 2 步：搭建 ESP-IDF 环境

ESP-IDF 是乐鑫官方的开发框架，编译、烧录都靠它。**只需装一次**。

1. 打开 [乐鑫官方入门教程](https://docs.espressif.com/projects/esp-idf/zh-cn/latest/get-started/index.html)，下载 Windows 版「ESP-IDF 安装器」，安装 ESP-IDF **v6.1**（更早的版本不支持 ESP32-S31），一路下一步即可。装好后桌面会出现「ESP-IDF 终端」。
2. 验证安装：打开「ESP-IDF 终端」，执行下面的命令，输出 `ESP-IDF v6.1` 就说明装好了。

```bash
idf.py --version
```

> **说明：** 后面所有命令都要在「ESP-IDF 终端」里输入。

## 第 3 步：下载源码并填写账号

### 3.1 下载源码

```bash
git clone https://github.com/Tencent-RTC/Tencent_IoT_App.git
cd Tencent_IoT_App/solutions/watch/device/esp32
```

这个目录就是 ESP-IDF 工程，后面的命令都在这里执行；watch 源码（含配置文件）在其中的 `watch` 目录。

### 3.2 准备账号

watch 需要 **TRTC**（音视频）和 **IM**（即时通信，用于呼叫信令）两套账号，在腾讯云控制台各创建一个应用，记下 **SDKAppID** 和 **SecretKey**：

| 账号 | 去哪里拿 | 需要记下 |
|---|---|---|
| TRTC | [TRTC 控制台 → 应用管理](https://console.cloud.tencent.com/trtc/app) | SDKAppID、SecretKey |
| IM | [IM 控制台 → 应用列表](https://console.cloud.tencent.com/im) | SDKAppID、SecretKey |

> **注意：** 手机 App 必须使用**同一套** TRTC 和 IM 账号，否则互相呼叫不到。

### 3.3 填写配置文件

用任意文本编辑器打开源码里的 `watch/config.h`，**只改下面几行**：

```c
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
```

> **说明：**
> - 配置会编译进固件，**改完配置要重新编译烧录**才生效。
> - 填好的 `config.h` 里有明文 SecretKey，只适合开发调试，**不要提交或推送到公开仓库**。

## 第 4 步：编译烧录

### 4.1 用 USB 线连接开发板和电脑

把 USB 线插在开发板的 **UART** 口上，然后在电脑上找到开发板对应的**串口名**（下文称 `<串口>`）：

打开 **设备管理器 → 端口(COM 和 LPT)**，找到名称为 `Silicon Labs CP210x` 的端口，括号里的 `COMx`（如 `COM3`）就是串口名。看不到端口时，先安装 [CP210x 驱动](https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers)。

> **说明：** 如果拔掉 USB 线后这个串口名就消失了，说明找对了。

### 4.2 编译并烧录

在「ESP-IDF 终端」里进入工程目录（3.1 节 `cd` 进去的 `device/esp32`），依次执行 3 条命令（把 `<串口>` 换成上一步找到的串口名）：

```bash
idf.py --preview set-target esp32s31   # 第 1 条：选择芯片，只需执行一次
idf.py build                           # 第 2 条：编译，第一次会联网下载依赖，需要几分钟
idf.py -p <串口> flash monitor         # 第 3 条：烧录，并打开串口监视器
```

例如串口为 `COM3` 时：

```bash
idf.py --preview set-target esp32s31
idf.py build
idf.py -p COM3 flash monitor
```

编译成功的最后会看到 `Project build complete`。

烧录**大约需要 10 分钟**（ESP32-S31 烧录速度较慢，固件和数据分区合计约 7MB），进度条在走就说明正常，请耐心等待。烧录完成后开发板自动重启，终端里开始滚动日志，最后出现命令提示符：

```text
esp32s31>
```

> **说明：**
> - 串口监视器要一直开着，第 5 步的命令都在这里输入。按 **Ctrl+]** 可以退出监视器，之后执行 `idf.py -p <串口> monitor` 可以重新打开。
> - 以后**只改了配置**时，重新执行第 2、3 条命令即可，不用再执行 `set-target`。

## 第 5 步：运行测试

下面的命令都在串口监视器里输入，**输入后按回车**。日志会不停滚动，直接输入即可，不影响命令执行。

### 5.1 连接 Wi-Fi

```bash
join <Wi-Fi 名称> <Wi-Fi 密码>
```

例如 `join MyWiFi 12345678`（没有密码的热点只写名称）。看到下面这行就连上了：

```text
I (12345) cmd_wifi: Got IP: 192.168.1.100
```

Wi-Fi 会保存在开发板上，**以后开机自动连接**，不用再输入。

### 5.2 启动 watch

```bash
watch_start
```

等待 10 秒左右，看到下面几行说明启动成功，设备已在线：

```text
I (5915) av_esp: camera initialized: sensor 1280x720 -> JPEG 640x360 max_fps=15 q50
I (8837) cmd_watch: IM status online=1 code=0 OK
I (8837) cmd_watch: watch running: device_id=watch_device room=room_1
```

> **说明：** 第一行是摄像头启动成功。如果看到的是 `camera init failed`，先执行 `restart` 重启开发板，再执行一次 `watch_start` 即可。

### 5.3 手机呼叫设备

1. 打开手机 App，用**同一套账号**登录，房间号填 `WATCH_CFG_ROOM_ID` 的值（上例为 `room_1`）。
2. 呼叫设备 ID（上例为 `watch_device`）。
3. 设备收到来电会**自动接听**。接通后：
   - 手机上能看到设备摄像头的画面，听到设备麦克风的声音；
   - 设备屏幕上显示手机画面（需接屏幕子板），扬声器播放手机的声音。

串口里能看到呼叫状态变化：

```text
I (60001) cmd_watch: call state=2 peer=phone_user    // 来电
I (60100) cmd_watch: call state=3 peer=phone_user    // 通话中
I (90000) cmd_watch: call state=0 peer=phone_user    // 已挂断
```

### 5.4 常用命令

| 命令 | 作用 |
|---|---|
| `watch_state` | 查看状态：`running=1` 表示已启动，`im_online=1` 表示在线 |
| `watch_call -u <手机 user_id>` | 设备主动呼叫手机 |
| `watch_hangup` | 挂断当前通话 |
| `watch_stop` | 停止 watch（下线） |
| `restart` | 重启开发板，重启后需重新执行 `watch_start` |

## 常见问题

| 现象 | 解决方法 |
|---|---|
| 编译报错 `WATCH_CFG_...` 为空，或启动后提示配置无效 | `watch/config.h` 里的账号没填或填错，回到 3.3 节检查。 |
| `idf.py: command not found` | 当前终端不是「ESP-IDF 终端」。请从桌面或开始菜单打开「ESP-IDF 终端」再执行命令。 |
| `set-target` 报 `'esp32s31' is not one of ...`，或编译报错 `esp32s31 需要 ESP-IDF v6.1.x` | 当前「ESP-IDF 终端」对应的 ESP-IDF 不是 v6.1。安装 v6.1 后打开它对应的「ESP-IDF 终端」（`idf.py --version` 输出 `ESP-IDF v6.1`），删除工程目录下的 `build` 文件夹，重新执行 4.2 节的命令。 |
| 烧录报错 `Failed to connect` / `No serial data received` / `port is busy` | 1. 确认开发板已上电（电源开关打开、指示灯亮），USB 线插在 **UART** 口。<br/>2. 关掉其他占用串口的程序（另一个串口监视器、串口助手等）。<br/>3. 换一根 USB 数据线。<br/>4. 按住板子上的 **BOOT** 键，再按一下 **RST** 键，松开 BOOT 后重新烧录。 |
| `join` 后一直连不上 Wi-Fi | 确认是 **2.4GHz** Wi-Fi 且已开启（手机热点注意不要自动关闭），名称和密码区分大小写；名称里有空格时用英文引号括起来。 |
| `watch_start` 报 `SNTP sync timeout` | 设备需要联网对时。确认 Wi-Fi 能上外网，再执行一次 `watch_start`。 |
| `watch_start` 报 `IoT login timeout` 或 IM 一直不是 `online=1` | 检查 `config.h` 里的 SDKAppID 和 SecretKey 是否填对、是否填反（TRTC 和 IM 是两套）。 |
| 日志出现 `camera init failed`，手机看不到设备画面 | 先执行 `restart`，再执行 `watch_start`；多试一两次仍失败，请断电检查摄像头排线是否插紧。 |
| 通话正常但设备屏幕不显示手机画面 | 确认已接 ESP32-S3-LCD-EV-Board-SUB3 屏幕子板，且是断电后再连接的。 |
| 手机呼叫后设备没反应 | 1. `watch_state` 确认 `im_online=1`。<br/>2. 确认手机和设备用的是同一套账号、呼叫的是设备 ID、房间号一致。 |
