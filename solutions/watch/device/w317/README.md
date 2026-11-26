# W317 watch 对接指南

> **临时发布包说明：** 当前 `platform/w317/` 只提供平台适配骨架和接口入口，`sdk/lib/` 中的两个库来自 ESP32，仅用于占位，不能直接在 W317 上编译运行。客户需要根据自身 W317 基线使用 `SCI_*` 实现平台接口，并替换为 W317 正式库后再编译验证。

本文介绍如何在紫光展锐 W317（UWS6131）跑通 **watch** 示例和手机端进行**双向音视频通话**。

1. **准备硬件**：一台可烧录的 W317 设备。

2. **搭建环境**：按展锐基线要求安装 Arm Compiler 6.13 等工具。

3. **下载源码并填账号**：改一个配置文件。

4. **集成编译烧录**：拷贝发布包中的模块内容、注册模块、添加启动入口，编译出 pac 后烧录。

5. **运行测试**：联网、启动 watch、手机呼叫。

> **注意：**
> W317 的基线（ms_code）、编译器和烧录工具都不公开下载，需要先从**紫光展锐或方案商**获取，并确认能编出、烧录原版固件，再按本文集成 watch。

## 第 1 步：准备硬件

- 一台 W317（UWS6131）开发板或工程机，需支持烧录自编固件。

- 烧录 / 数据线，以及进入下载模式的方法（向设备提供方确认）。

- 一部装好匹配的 watch 手机端 App 的手机，用来呼叫设备。

## 第 2 步：搭建编译环境

展锐基线对编译环境有固定要求，**以芯片厂商随基线提供的环境说明为准**。通常需要：

| 工具 | 说明 |
| --- | --- |
| Arm Compiler 6.13 | 基线中的闭源库由 6.13 编译，**必须使用同一版本**，并自备有效授权（设置 `ARMLMD_LICENSE_FILE`）。请完整安装或拷贝，不要用符号链接，否则会报 license 错误。 |
| Python 3.9 | 加入 PATH，并在安装目录把 `python.exe` 复制一份为 `python3.exe`（部分编译脚本调用 `python3`，缺少时会无提示退出）。 |
| ActivePerl、VC++ 2008 / 2010 x86 运行库 | 基线编译脚本依赖，版本按厂商说明。 |
| 展锐 USB 驱动、ResearchDownload | 用于烧录 pac 固件；驱动安装失败时需临时关闭 Windows 驱动签名校验。 |
| 展锐日志工具 | 用于查看设备运行日志，由厂商提供。 |

验证编译器：打开 **cmd**，执行下面的命令，输出中包含 `ARM Compiler 6.13` 就说明装好了。

```bash
armclang --vsn
```

## 第 3 步：下载源码并填写账号

### 3.1 下载源码

```bash
git clone https://github.com/Tencent-RTC/Tencent_IoT_App.git
cd Tencent_IoT_App\solutions\watch\device\w317
```

`device/w317/` 是发布包根目录；其中除 `README.md` 外的内容是要集成进基线的 watch 模块，包含 watch 源码、W317 平台适配、SDK 库和模块编译配置。当前临时分支的两个库来自 ESP32，仅作占位，不能直接用于 W317。

### 3.2 准备账号

watch 需要 **TRTC**（音视频）和 **IM**（即时通信，用于呼叫信令）两套账号，在腾讯云控制台各创建一个应用，记下 **SDKAppID** 和 **SecretKey**：

| 账号 | 去哪里拿 | 需要记下 |
| --- | --- | --- |
| TRTC | [TRTC 控制台 → 应用管理](https://console.cloud.tencent.com/trtc/app) | SDKAppID、SecretKey |
| IM | [IM 控制台 → 应用列表](https://console.cloud.tencent.com/im) | SDKAppID、SecretKey |

> **注意：**
> 匹配的 watch 手机端 App 必须使用**同一套** TRTC 和 IM 账号，否则互相呼叫不到。

### 3.3 填写配置文件

用任意文本编辑器打开 `device/w317/config.h`，**只改下面几行**：

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
> - 配置会编译进固件，**改完配置要重新编译烧录**才生效。如果已经把 watch 拷进基线（见 4.2），请改基线里那份 `ms_code\external\watch\config.h`。
> - 填好的 `config.h` 里有明文 SecretKey，只适合开发调试，**不要提交或推送到公开仓库**。

## 第 4 步：集成、编译和烧录

### 4.1 准备基线

从芯片厂商获取 W317 对应的基线，解压到不含空格和中文的路径（下文以 `D:\ms_code` 为例），并向厂商确认设备对应的**产品代号**（下文以 `UWS6131E_WC_2c12` 为例）。

集成 watch 前，先按厂商说明编译并烧录一次原版固件，确认环境和设备都正常。

### 4.2 拷贝 watch 模块

把 `device/w317/` 中除 `README.md` 外的模块内容拷贝到基线的 `external` 目录下，得到 `D:\ms_code\external\watch`。

### 4.3 把 watch 模块加入编译

在基线的模块配置文件（如 `ANTISW3.modules`，具体位置以基线为准）中添加：

```bash
COMPLIBS_DBG += watch
```

### 4.4 添加启动入口

在基线的应用代码里选一个触发点（例如秒表应用的「开始」按钮回调），调用 `watch_start()`；需要停止时调用 `watch_stop()`：

```c
#include "watch_w317.h"

static void stopwatch_on_start(void)
{
/* ... 原有逻辑 ... */
watch_start();
}
```

- 完成 W317 平台适配后，`watch_start()` 应只创建 watch 自己的任务并立即返回，不阻塞界面；重复调用应被忽略。当前临时发布包只提供该接口骨架。

- 完成 W317 平台适配后，watch 任务应先等待设备联网并完成对时，再登录 IM。

### 4.5 编译

打开 **cmd**，进入基线目录执行：

```bash
cd /d D:\ms_code
make p=UWS6131E_WC_2c12 new image -j8
```

编译成功后生成 pac 固件：

```text
D:\ms_code\build\UWS6131E_WC_2c12_builddir\img\ANTISW3_UWS6131E_WC_2c12.pac
```

之后只改了 `config.h` 或 watch 代码时，可以只重编 watch 模块，速度更快：

```bash
make p=UWS6131E_WC_2c12 m=watch update image -j1
```

### 4.6 烧录

1. 打开 ResearchDownload，点击第一个按钮（Load Packet），选择上一步生成的 pac 文件。

2. 点击 Settings：Option 页勾选 **Repartition**；Backup 页取消勾选两个 File Backup 文件。

3. 点击开始下载（提示会覆盖 IMEI 时选「是」）。

4. 用数据线连接设备，并让设备进入下载模式（按键方式向设备提供方确认）。

5. 等待进度完成，设备自动重启。

## 第 5 步：运行测试

### 5.1 联网

插入能上网的 SIM 卡后开机，等待设备注册上网络（基线支持 Wi-Fi 时，也可以在设置里连接 Wi-Fi）。

### 5.2 启动 watch

在设备上触发 4.4 中添加的入口（如进入秒表点击「开始」），调用 `watch_start()`。

用展锐日志工具查看设备日志，搜索 `[watch]`，看到下面两行说明启动成功，设备已在线：

```text
[watch] IM status online=1 code=0 OK
[watch] watch running: device_id=watch_device room=room_1
```

### 5.3 手机呼叫设备

1. 打开手机 App，用**同一套账号**登录，房间号填 `WATCH_CFG_ROOM_ID` 的值（上例为 `room_1`）。

2. 呼叫设备 ID（上例为 `watch_device`）。

3. 设备收到来电会**自动接听**。接通后：

- 手机上能看到设备摄像头的画面，听到设备麦克风的声音；

- 设备屏幕上显示手机画面，扬声器播放手机的声音。

日志里能看到呼叫状态变化：

```text
[watch] call state=2 peer=phone_user    // 来电
[watch] call state=3 peer=phone_user    // 通话中
[watch] call state=0 peer=phone_user    // 已挂断
```

## 常见问题

| 现象 | 解决方法 |
| --- | --- |
| `armclang` 报 license 错误 | 检查 `ARMLMD_LICENSE_FILE` 是否设置正确；编译器不要用符号链接方式安装。 |
| 编译成功但没有生成 pac | 编译命令缺少 `image`，应为 `make p=<产品代号> new image`。 |
| ResearchDownload 识别不到设备 | 确认展锐 USB 驱动已安装、设备已进入下载模式；不要使用 Windows on ARM 电脑。 |
| 一直看不到 `IM status online=1` | 1. 确认 SIM 卡有流量、设备已注网。2. 检查 `config.h` 里的 SDKAppID 和 SecretKey 是否填对、是否填反（TRTC 和 IM 是两套）。 |
| 手机呼叫不到设备 | 确认手机 App 与设备使用同一套账号，呼叫的 ID 与 `WATCH_CFG_DEVICE_ID` 一致。 |
