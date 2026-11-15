# ASR3602 watch 对接指南

> **临时发布包说明：** 当前 `platform/asr3602/` 只提供平台适配骨架和接口入口，`sdk/lib/` 中的两个库来自 ESP32，仅用于占位，不能直接在 ASR3602 上编译运行。客户需要根据自身 ASR3602 SDK、目标设备和基线，实现平台接口并替换为匹配的正式库后再编译验证。
>
> **目标设备：** ASR3602 目标设备或 EVB，由客户自行提供并确认摄像头、LCD、音频等外设型号。
>
> **手机端：** 使用匹配的 watch 手机端 App，由客户自行获取。

本文介绍如何在翱捷（ASR）3602 设备上跑通 **watch** 示例和手机端进行**双向音视频通话**。

1. **准备硬件**：一台可烧录的 ASR3602 设备。

2. **搭建环境**：按 ASR SDK 的要求安装 ARM DS-5、MSYS2 等工具。

3. **下载源码并填账号**：改一个配置文件。

4. **集成编译烧录**：拷贝发布包中的模块内容、注册模块、添加启动入口，编译出固件包后烧录。

5. **运行测试**：联网、启动 watch、手机呼叫。

> **注意：**
> ASR3602 的 SDK、编译器和烧录工具都不公开下载，需要先从**翱捷科技或方案商**获取，并确认能编出、烧录原版固件，再按本文集成 watch。


## 第 1 步：准备硬件

- 一台 ASR3602 目标设备或 EVB，需支持烧录自编固件；摄像头、LCD、音频等外设型号由客户自行确认。

- 烧录 / 日志用的 USB 线，以及进入下载模式的方法（向设备提供方确认）。

- 一部装好匹配的 watch 手机端 App 的手机，用来呼叫设备。

## 第 2 步：搭建编译环境

ASR SDK 对编译环境有固定要求，**以芯片厂商随 SDK 提供的环境说明为准**。通常需要：

| 工具 | 说明 |
| --- | --- |
| ARM DS-5（ARM Compiler 5） | SDK 中的闭源库由 ARM Compiler 5（armcc）编译，**必须使用 SDK 指定的版本**，并自备有效授权。安装后把 `armcc` 所在目录加入 PATH。 |
| MSYS2 | 提供 `make`、`awk`、`sed`、`tar` 等工具，编译命令都在 MSYS2 终端里执行。 |
| ActivePerl | SDK 编译脚本依赖。安装后把 `C:\msys64\usr\bin\perl.exe` 改名（如 `perl_msys.exe`），否则会用到 MSYS2 自带的 perl，导致编译出错。 |
| Python 3 | SDK 编译脚本依赖，版本按厂商说明。 |
| cmake、ninja、gcc | SDK 的 `prebuilts` 目录已自带，无需单独安装。 |
| aboot | ASR 烧录工具，用于烧录固件包，由厂商提供。 |
| ASR 日志工具 | 用于查看设备运行日志（如 CATStudio），由厂商提供。 |

验证环境：打开 MSYS2 终端，执行下面的命令。`armcc` 输出中包含 `ARM Compiler 5`，`perl` 输出中包含 `ActiveState`，就说明装好了。

```bash
armcc --vsn
perl --version
```

## 第 3 步：下载源码并填写账号

### 3.1 下载源码

```bash
git clone https://github.com/Tencent-RTC/Tencent_IoT_App.git
cd Tencent_IoT_App/solutions/watch/device/asr3602
```

`device/asr3602` 目录就是要集成进 SDK 的 watch 模块，包含 watch 源码、ASR3602 平台适配骨架、预编译库占位文件和模块编译配置。

### 3.2 准备账号

watch 需要 **TRTC**（音视频）和 **IM**（即时通信，用于呼叫信令）两套账号，在腾讯云控制台各创建一个应用，记下 **SDKAppID** 和 **SecretKey**：

| 账号 | 去哪里拿 | 需要记下 |
| --- | --- | --- |
| TRTC | [TRTC 控制台 → 应用管理](https://console.cloud.tencent.com/trtc/app) | SDKAppID、SecretKey |
| IM | [IM 控制台 → 应用列表](https://console.cloud.tencent.com/im) | SDKAppID、SecretKey |

> **注意：**
> 匹配的 watch 手机端 App 必须使用**同一套** TRTC 和 IM 账号，否则互相呼叫不到。


### 3.3 填写配置文件

用任意文本编辑器打开 `device/asr3602/config.h`，**只改下面几行**：

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
> - 配置会编译进固件，**改完配置要重新编译烧录**才生效。如果已经把 watch 拷进 SDK（见 4.2），请改 SDK 里那份 `product/craneg_modem/watch/config.h`。
> - 填好的 `config.h` 里有明文 SecretKey，只适合开发调试，**不要提交或推送到公开仓库**。


## 第 4 步：集成、编译和烧录

### 4.1 准备 SDK

从芯片厂商获取 ASR3602 对应的 SDK，解压到不含空格和中文的路径（下文以 `C:\asr_sdk` 为例，在 MSYS2 中为 `/c/asr_sdk`），并向厂商确认设备对应的**编译参数**（下文以 `TARGET_OS=ALIOS PS_MODE=LITE_LTEONLY CHIP_ID=CRANEL` 为例）。

集成 watch 前，先按厂商说明编译并烧录一次原版固件，确认环境和设备都正常。

### 4.2 拷贝 watch 模块

把 `device/asr3602` 中除 `README.md` 外的内容拷贝到 SDK 的产品目录下，得到 `C:\asr_sdk\product\craneg_modem\watch`。

### 4.3 把 watch 模块加入编译

打开 SDK 的 `product/craneg_modem/CMakeLists.txt`（具体文件以 SDK 为准），添加 watch 模块，并把它链接进固件：

```cmake
add_subdirectory(watch)
target_link_libraries(${固件目标名} PRIVATE watch)
```

其中 `${固件目标名}` 换成该文件里生成固件的目标名。

### 4.4 添加启动入口

在 SDK 的界面应用代码（`gui/lv_watch/lv_apps/` 下）里选一个触发点（例如计步应用的入口函数），调用 `watch_start()`；需要停止时调用 `watch_stop()`：

```c
#include "watch_asr3602.h"

static void pedometer_on_open(void)
{
    /* ... 原有逻辑 ... */
    watch_start();
}
```

- `watch_start()` 只创建 watch 自己的任务后立即返回，不会阻塞界面；重复调用会被忽略。

- watch 任务会先等待设备注网并完成对时，再登录 IM，所以在开机后任意时刻调用都可以。

### 4.5 编译

打开 MSYS2 终端，进入 SDK 目录依次执行：

```bash
cd /c/asr_sdk
make craneg_modem_sdk   TARGET_OS=ALIOS PS_MODE=LITE_LTEONLY CHIP_ID=CRANEL -j8
make craneg_modem_watch TARGET_OS=ALIOS PS_MODE=LITE_LTEONLY CHIP_ID=CRANEL
```

- 第一条编译 modem 侧 SDK，只在第一次或 SDK 本身有改动时需要执行，耗时较长。

- 第二条编译应用侧固件，并打包成整包烧录文件。

编译成功后，在 `out/product/craneg_modem_watch/` 目录下生成整包烧录文件（`.zip`，文件名包含芯片型号和存储配置）。

之后只改了 `config.h` 或 watch 代码时，只需重新执行第二条命令。

### 4.6 烧录

1. 打开 aboot，选择上一步生成的整包 `.zip` 文件。

2. 用 USB 线连接设备，并让设备进入下载模式（方法向设备提供方确认）。

3. 在 aboot 中选择对应端口，开始下载。

4. 等待进度完成，设备自动重启。

## 第 5 步：运行测试

### 5.1 联网

插入能上网的 SIM 卡后开机，等待设备注册上 4G 网络。

### 5.2 启动 watch

在设备上触发 4.4 中添加的入口（如打开计步应用），调用 `watch_start()`。

用 ASR 日志工具查看设备日志，搜索 `[watch]`，看到下面两行说明启动成功，设备已在线：

```text
[watch] IM status online=1 code=0 OK
[watch] watch running: device_id=watch_device room=room_1
```

### 5.3 手机呼叫设备

1. 打开匹配的 watch 手机端 App，用**同一套账号**登录，房间号填 `WATCH_CFG_ROOM_ID` 的值（上例为 `room_1`）。

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
| `armcc: command not found` 或报 license 错误 | 确认 DS-5 已安装、`armcc` 所在目录已加入 PATH，并配置了有效授权。 |
| 编译报正则匹配、perl 相关错误 | MSYS2 自带的 perl 没有改名，`perl --version` 应显示 `ActiveState`，见第 2 步。 |
| 编译报 `subst` 盘符映射失败 | 上次编译异常退出留下了盘符映射，在 cmd 中执行 `subst X: /d` 后重试（盘符以报错为准）。 |
| aboot 识别不到设备 | 确认 USB 驱动已安装、设备已进入下载模式，并在 aboot 中选对端口。 |
| 一直看不到 `IM status online=1` | 1. 确认 SIM 卡有流量、设备已注网。<br>2. 检查 `config.h` 里的 SDKAppID 和 SecretKey 是否填对、是否填反（TRTC 和 IM 是两套）。 |
| 手机呼叫不到设备 | 确认匹配的 watch 手机端 App 与设备使用同一套账号，呼叫的 ID 与 `WATCH_CFG_DEVICE_ID` 一致。 |
