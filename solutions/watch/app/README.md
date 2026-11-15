# Watch App 接入指南

> 本仓库包含公开占位配置。clone 后可以编译 Debug 版本，但必须按本文填写自己的 TRTC／IM 账号，才能完成真实登录、消息和通话联调。真实 `SecretKey` 只用于本地调试，不要提交到公开仓库。

本文介绍如何编译 Android／iOS 手机 App，并与手表 **双向视频通话**。

## 第 1 步：准备手表和账号

### 1.1 手表端

先按照设备端文档完成固件编译、烧录和联网（SIM 卡或 Wi-Fi），并启动 watch。设备端日志出现以下内容后，再启动手机 App：

```text
[watch] IM status online=1 code=0 OK
[watch] watch running: device_id=watch_device room=260101
```

### 1.2 腾讯云账号

手机和手表必须使用**同一套** TRTC 账号和**同一套** IM 账号（TRTC 与 IM 的 `SDKAppID` 不要求相同）：

| 账号 | 控制台 | 需要记下 |
| --- | --- | --- |
| TRTC | [TRTC 控制台](https://console.cloud.tencent.com/trtc/app) | `SDKAppID`、`SecretKey` |
| IM | [IM 控制台](https://console.cloud.tencent.com/im) | `SDKAppID`、`SecretKey` |

### 1.3 两端参数对应关系

| App 端 | 设备端 | 要求 |
| --- | --- | --- |
| `TRTC_ROOM_ID`（登录页房间号） | `WATCH_CFG_ROOM_ID` | 完全一致；登录页为数字键盘，请使用纯数字，例如 `260101` |
| 绑定手表时输入的 `deviceName` | `WATCH_CFG_DEVICE_ID` | 完全一致，区分大小写和空格，例如 `watch_device` |

## 第 2 步：搭建 App 编译环境

| 工具 | 要求 |
| --- | --- |
| Android Studio | 当前稳定版 |
| JDK | 11 |
| Android SDK | compile／target SDK 34 |
| 真机 | Android 10（API 29）及以上的 `arm64-v8a` 真机，已开启 USB 调试 |

工程自带 Gradle Wrapper，Android IoT／TRTC SDK 使用仓库内的 `android/app/libs/LiteAVSDK_IOT_13.4.0.25071.aar`，IMSDK 从 Maven 联网下载。

| 工具 | 要求 |
| --- | --- |
| macOS + Xcode | Xcode 16 及以上 |
| iOS SDK | 15.0 及以上 |
| 真机 | 已完成开发者账号签名配置的 iPhone |

工程通过 CocoaPods 集成 iOS IoT／TRTC 和 IM SDK。首次编译前请在 `ios` 目录执行 `pod install`，然后使用生成的 `WatchApp.xcworkspace` 打开工程。

**说明：**

模拟器只能验证界面和流程，真实音视频通话必须使用 Android `arm64-v8a` 真机或签名后的 iPhone 真机。

## 第 3 步：下载源码并填写账号

### 3.1 下载源码

```bash
git clone https://github.com/Tencent-RTC/Tencent_IoT_App.git
cd Tencent_IoT_App/solutions/watch/app
```

### 3.2 填写账号

打开对应平台的配置文件，只修改以下字段：

文件：`android/app/src/main/java/com/tencent/iot/watchapp/config/WatchSdkConfig.kt`

```kotlin
const val TRTC_SDK_APP_ID: Long = 1400000000L
const val TRTC_SECRET_KEY: String = "replace-with-trtc-secret"
const val IM_SDK_APP_ID: Long = 1600000000L
const val IM_SECRET_KEY: String = "replace-with-im-secret"
const val TRTC_ROOM_ID: String = "260101"
```

文件：`ios/WatchApp/WatchApp/Sources/Config/WatchSdkConfig.swift`

```swift
static let TRTC_SDK_APP_ID: Int64 = 1400000000
static let TRTC_SECRET_KEY = "replace-with-trtc-secret"
static let IM_SDK_APP_ID: Int64 = 1600000000
static let IM_SECRET_KEY = "replace-with-im-secret"
static let TRTC_ROOM_ID = "260101"
```

**注意：**

- 配置会编译进 App，修改账号后需重新编译安装。

- 真实 `SecretKey` 仅用于本地调试，不要提交到公开仓库，也不要打印到日志。

## 第 4 步：编译并安装 App

连接手机后，在仓库根目录执行：

```bash
./android/gradlew -p android :app:assembleDebug
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.tencent.iot.watchapp/.app.MainActivity
```

1. 在 `ios` 目录执行 `pod install`，然后用 Xcode 打开生成的 `WatchApp.xcworkspace`，选择 `WatchApp` Scheme。

2. 运行目标选择 iPhone 真机，在 **Signing & Capabilities** 中选择开发团队和 Provisioning Profile。

3. 点击 **Run** 编译、安装并启动。

首次启动时，请允许 App 使用摄像头和麦克风。

## 第 5 步：登录并验证

按下图从左到右依次操作：登录 App → 绑定手表 → 发起通话。

1. **登录**：填写房间号、SDKAppID 和 SDKAppSecret，点击 **登录**。

2. **绑定手表**：在 **添加 > 添加手表** 中输入设备号，点击 **绑定**。

3. **发起通话**：点击底部通话按钮，选择手表和通话类型，手表自动接听。

**注意：**

- 房间号须与设备端 `WATCH_CFG_ROOM_ID` 一致，设备号须与 `WATCH_CFG_DEVICE_ID` 一致。
- 登录页只能临时修改 TRTC 参数，IM 账号固定读取配置文件。
- 当前为本地绑定，更换手机或账号后需重新绑定。

## 日志查看

```bash
adb logcat -s WatchApp
```

登录成功后应看到 `IMSDK login success` 和 `IoT login success`。

```bash
log stream --style compact --predicate 'subsystem == "com.tencent.iot.watchapp"'
```

也可以在 Xcode 的 **Devices and Simulators** 或 Console.app 中查看。

## 常见问题

| 现象 | 处理方法 |
| --- | --- |
| 登录失败 | 检查 `TRTC_*` 和 `IM_*` 是否都已填写、两套 `SDKAppID` 是否填反；修改配置后需重新编译安装。 |
| 能登录但消息收发失败 | 检查 IM 账号是否与手表固件一致，`deviceName` 是否与 `WATCH_CFG_DEVICE_ID` 完全一致。 |
| 通话列表里没有手表 | 先通过 **绑定手表** 输入 `deviceName`，当前版本不会自动发现设备。 |
| 呼叫不到手表 | 检查手表是否在线，`deviceName` 和房间号是否与设备端一致。 |
| 没有画面或声音 | 检查摄像头、麦克风权限和系统音量；确认使用的是真机而非模拟器，挂断后重新发起通话。 |
| 修改账号后仍是旧账号 | 卸载旧 App 后重新安装最新构建的安装包。 |
