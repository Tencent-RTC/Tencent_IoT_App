# 守望手表通话 App 架构说明


## 1. 项目概览

这是一个家长端手机 App，负责与儿童手表进行消息通信和音视频通话。Android 和 iOS 具备对应的功能模块，但页面实现和 SDK 接入方式按平台分别维护。

核心能力如下：

| 能力 | 作用 | 主要入口 |
| --- | --- | --- |
| 登录与会话 | 登录 IM 和 IoT／TRTC，维护 App 的登录状态 | `app`、`config`、`im`、`call` |
| 手表绑定 | 保存设备号，展示设备列表，选择通话目标 | `watch` |
| IM 消息 | 会话列表、历史消息、文本消息、群组成员和会话设置 | `im`、Android `ui`、iOS `UI` |
| 音视频通话 | 呼叫、接听、拒接、挂断、摄像头、麦克风、扬声器和远端视频 | `call` |
| 页面导航 | 登录页、消息页、定位页、设备页、个人页和通话页 | `app`、`ui`、`UI`、`watch`、`im`、`call` |

### 1.1 端到端关系

```text
手机页面
  │
  ├── 登录 ──> ImService ──> Tencent IM SDK
  │       └──> IoTSession ──> IoT／TRTC SDK
  │
  ├── 消息页面 ──> ImService ──> Tencent IM SDK
  │
  ├── 手表页面 ──> WatchBindingStore
  │
  └── 通话页面 ──> CallCoordinator
                         ├── CallSignaling
                         │      └── ImCallSignalTransport ──> ImService ──> IM SDK
                         └── CallMediaSession ──> IoTSession ──> IoT／TRTC SDK
```

通话由两条链路组成：

1. `CallSignaling` 通过 IM 传递呼叫、接听、拒接和挂断信令。
2. `CallMediaSession` 通过 IoT／TRTC SDK 建立媒体会话，控制音视频和渲染视图。

`CallCoordinator` 将两条链路组合成页面可调用的通话接口。

### 1.2 手表端对应关系

手表端代码位于同级目录 `../device`，手机端和手表端通过以下数据关联：

| 数据 | 手机端 | 手表端 |
| --- | --- | --- |
| TRTC／IoT 房间号 | 登录页的 `TRTC_ROOM_ID` | `WATCH_CFG_ROOM_ID` |
| 手表设备号 | 绑定时输入的 `deviceName` | `WATCH_CFG_DEVICE_ID` |
| TRTC 账号 | `WatchSdkConfig` 或登录页参数 | `WATCH_CFG_TRTC_*` |
| IM 账号 | `WatchSdkConfig` | `WATCH_CFG_IM_*` |

## 2. 仓库结构

```text
solutions/watch/
├── app/                         # Android／iOS 手机 App
│   ├── android/                 # Android Studio／Gradle 工程
│   ├── ios/                     # Xcode／CocoaPods 工程
│   ├── README.md                # 编译、配置和联调说明
│   └── ARCHITECTURE.md          # 本文档
└── device/                      # 手表端固件工程
    ├── asr3602/
    ├── esp32/
    └── w317/
```

### 2.1 App 根目录

| 路径 | 内容 |
| --- | --- |
| `README.md` | 开发环境、账号配置、编译安装和联调流程 |
| `ARCHITECTURE.md` | 当前模块结构和功能定位 |
| `android/` | Android App 源码、资源和 Gradle 配置 |
| `ios/` | iOS App 源码、Xcode 工程和 CocoaPods 配置 |
| `.gitignore` | 构建产物、Pods、IDE 状态和本地配置的忽略规则 |

### 2.2 SDK 依赖

| 平台 | IoT／TRTC SDK | IM SDK |
| --- | --- | --- |
| Android | `android/app/libs/LiteAVSDK_IOT_13.4.0.25071.aar` | `com.tencent.imsdk:imsdk-plus:9.0.7652` |
| iOS | CocoaPods `TXLiteAVSDK_IOT`，版本由 `ios/Podfile.lock` 锁定 | CocoaPods `TXIMSDK_Plus_iOS_XCFramework`，版本由 `ios/Podfile.lock` 锁定 |

iOS 工程应通过 `ios/WatchApp.xcworkspace` 打开。`ios/Pods/` 是 CocoaPods 生成目录，不属于源码模块；Android 的 IoT／TRTC AAR 由 Gradle 从 `android/app/libs/` 引用，IM SDK 从 Maven 下载。

## 3. Android 结构

Android 包名为 `com.tencent.iot.watchapp`，源码位于：

```text
android/app/src/main/java/com/tencent/iot/watchapp/
├── app/
├── call/
├── config/
├── im/
├── ui/
└── watch/
```

### 3.1 Android 应用入口：`app/`

| 文件 | 职责 |
| --- | --- |
| `MainActivity.kt` | Activity 入口；创建 `CallCoordinator`，初始化 IM，处理登录、Tab、聊天、设备和通话页面切换 |
| `AppScreen.kt` | 顶层页面状态：登录页、主 Tab、通话相关页面 |
| `AppSessionViewModel.kt` | 保存当前顶层页面和登录／退出后的页面状态 |

Android 当前由 `MainActivity` 负责应用级组装。业务模块通过公开方法和状态流与 Activity 交互，页面 View 放在对应功能包中。

### 3.2 Android 通话：`call/`

| 文件 | 职责 | 关键类型或入口 |
| --- | --- | --- |
| `CallCoordinator.kt` | 组合信令、媒体、IoT 登录和通话状态，向页面提供通话操作 | `login`、`startCall`、`acceptIncoming`、`rejectIncoming`、`hangup`、媒体控制 |
| `CallSignaling.kt` | 通话信令状态机，处理呼叫、接听、拒接、挂断、超时和信令断开 | `CallSignalPhase`、`CallSignalState` |
| `CallSignal.kt` | 信令数据模型、编码和解码 | `CallSignal`、`CallSignalCodec` |
| `CallStateStore.kt` | 保存面向 UI 的通话状态 | `CallPhase`、`CallUiState` |
| `CallMediaSession.kt` | IoT／媒体 SDK 适配；创建通话、绑定远端、控制摄像头和音频 | `callDevice`、`prepareIncomingCall`、`bindRemoteView` |
| `CallVideoSurface.kt` | 视频渲染表面抽象 | `bindRemote`、`startLocalVideo`、`setCameraEnabled` |
| `IoTSession.kt` | IoT SDK 登录、退出、会话获取和资源释放 | `login`、`logout`、`callSession`、`release` |
| `IotSessionConfig.kt` | IoT 登录运行参数 | `channel`、`appId`、`appSecret` |
| `IotCredentials.kt` | 用户签名数据和签名提供者抽象 | `IoTUserSignature`、`IoTSignatureProvider` |
| `TrtcSignatureProvider.kt` | 当前 TRTC／IoT 签名实现 | `IoTSignatureProvider` 实现 |
| `TencentUserSigGenerator.kt` | IM UserSig 生成辅助 | UserSig 生成逻辑 |

Android 通话页面使用 `ui/AndroidCallVideoSurface.kt` 将 `TXCloudVideoView` 适配为 `CallVideoSurface`。因此通话业务代码不直接依赖页面 View。

### 3.3 Android IM：`im/`

| 文件 | 职责 |
| --- | --- |
| `ImService.kt` | IM SDK 初始化、登录、退出、会话刷新、消息历史、文本消息、群组、会话设置和来电信令 |
| `ImCallSignalTransport.kt` | 将 `ImService` 适配为 `CallSignalTransport` |
| `ImSdkAuth.kt` | IM 登录认证参数和认证辅助 |
| `ConversationMapper.kt` | 将 IM SDK 会话转换为 App 会话模型 |
| `MessageConversation.kt` | 会话、消息和草稿等领域模型 |
| `MessagesAdapter.kt` | 消息列表 RecyclerView 适配器 |
| `ChatView.kt` | 聊天详情页，负责消息展示、输入和发送 |
| `ChatInfoView.kt` | 会话详情页，负责置顶、免打扰、清空历史等操作 |
| `GroupMemberPickerView.kt` | 群成员选择和邀请页面 |

`ImService` 是 Android 端 IM 能力的主要入口。通话模块只通过 `ImCallSignalTransport` 使用其中的信令能力。

### 3.4 Android 手表：`watch/`

| 文件 | 职责 |
| --- | --- |
| `WatchBindingStore.kt` | 按当前用户保存、读取和删除已绑定手表 |
| `BindWatchView.kt` | 输入设备号并完成绑定 |
| `DevicesView.kt` | 手表列表、设备卡片和当前设备选择 |
| `LocationView.kt` | 手表位置页面 |
| `WatchQrScannerView.kt` | 扫描手表二维码，可嵌入其他页面 |
| `AddContactView.kt` | 添加联系人或群组成员 |
| `WatchAvatarResolver.kt` | 根据设备或用户标识解析头像资源 |
| `GroupAvatarComposer.kt` | 合成群组头像 |
| `WatchMapView.kt` | 地图渲染视图 |

手表绑定信息的核心字段是 `productId` 和 `deviceName`。通话目标 `CallTarget` 从绑定数据中取得设备号，并把设备号用于 IM 信令和 IoT 呼叫。

### 3.5 Android 页面和资源：`ui/`、`res/`

| 路径 | 内容 |
| --- | --- |
| `ui/LoginView.kt` | 登录表单和登录状态展示 |
| `ui/MainTabView.kt` | 消息、定位、设备、个人四个主 Tab |
| `ui/MessagesView.kt` | 会话列表入口 |
| `ui/ProfileView.kt` | 个人页和退出登录 |
| `ui/CallTargetPickerView.kt` | 选择手表和通话类型 |
| `ui/OutgoingCallView.kt` | 呼出状态和取消呼叫 |
| `ui/IncomingCallView.kt` | 来电状态、接听和拒接 |
| `res/layout/` | 页面布局和列表项布局 |
| `res/drawable/`、`res/drawable-nodpi/` | 页面背景、图标、头像、通话控件和地图资源 |
| `res/values/` | 字符串、颜色、尺寸、样式和资源 ID |

## 4. iOS 结构

iOS 源码位于 `ios/WatchApp/WatchApp/Sources/`，按功能目录组织：

```text
ios/WatchApp/WatchApp/Sources/
├── App/
├── Call/
├── Config/
├── IM/
├── UI/
└── Watch/
```

### 4.1 iOS 应用入口：`App/`

| 文件 | 职责 |
| --- | --- |
| `AppDelegate.swift` | 应用生命周期入口 |
| `SceneDelegate.swift` | 场景和根窗口生命周期 |
| `RootViewController.swift` | 根页面容器 |
| `LoginViewController.swift` | 登录表单、登录参数和登录操作 |
| `MainTabViewController.swift` | 消息、定位、设备、个人四个主 Tab |
| `AppStateStore.swift` | 组装 `ImService`、`IoTSession` 和 `CallCoordinator`，维护认证状态、Tab 状态及通话操作 |

`AppStateStore` 是 iOS 端的应用级组装入口。页面通过它调用登录、退出、发起通话、接听、拒接、挂断和媒体控制。

### 4.2 iOS 通话：`Call/`

| 文件 | 职责 | 关键类型或入口 |
| --- | --- | --- |
| `CallCoordinator.swift` | 组合信令、媒体会话和 UI 状态，向页面提供通话操作 | `startCall`、`acceptIncoming`、`rejectIncoming`、`hangup` |
| `CallSignaling.swift` | 通话信令状态机 | `CallSignalPhase`、`CallSignalState` |
| `CallSignal.swift` | 信令模型和编解码 | `CallSignal`、`CallSignalCodec` |
| `CallStateStore.swift` | 保存通话 UI 状态 | `CallPhase`、`CallUIState` |
| `CallMediaSession.swift` | IoT／媒体 SDK 适配；处理媒体会话和音视频控制 | `startCall`、`prepareIncomingMedia`、`finish` |
| `CallVideoSurface.swift` | 视频渲染表面协议及 UIKit 适配 | `CallVideoSurface`、`UIKitCallVideoSurface` |
| `IoTSession.swift` | IoT SDK 登录、退出、会话和登录状态 | `login`、`logout`、`callSession` |
| `IotSessionConfig.swift` | IoT 登录运行参数 | `channel`、`appID`、`appSecret` |
| `IotCredentials.swift` | IoT 用户签名数据和签名协议 | `IoTUserSignature`、`IoTSignatureProvider` |
| `TrtcSignatureProvider.swift` | 当前 TRTC／IoT 签名实现 | `IoTSignatureProvider` 实现 |
| `CallTargetPickerViewController.swift` | 选择手表和通话类型 |
| `OutgoingCallViewController.swift` | 呼出页面 |
| `IncomingCallViewController.swift` | 来电页面 |

`CallMediaSession` 只接收媒体操作，`CallSignaling` 只处理信令状态，`CallStateStore` 只保存通话状态。页面通过 `CallCoordinator` 访问这些能力。

### 4.3 iOS IM：`IM/`

| 文件 | 职责 |
| --- | --- |
| `ImService.swift` | IM SDK 初始化、登录、退出、会话、消息、群组和来电信令回调 |
| `ImCallSignalTransport.swift` | 将 `ImService` 适配为 `CallSignalTransport` |
| `ImSdkAuth.swift` | IM 登录认证参数和认证辅助 |
| `ConversationMapper.swift` | 会话模型转换 |
| `MessageConversation.swift` | 会话、消息和草稿等领域模型 |
| `ChatViewController.swift` | 聊天详情页 |
| `ChatInfoViewController.swift` | 会话详情和会话设置 |
| `GroupMemberPickerViewController.swift` | 群成员选择和邀请 |

消息列表位于 `UI/MessagesViewController.swift`，因为它属于主 Tab 页面；聊天详情和群组操作位于 `IM/`，因为它们直接使用 IM 领域模型和服务。

### 4.4 iOS 手表：`Watch/`

| 文件 | 职责 |
| --- | --- |
| `WatchBindingStore.swift` | 保存和读取当前用户的手表绑定信息 |
| `BindWatchViewController.swift` | 绑定手表页面 |
| `DevicesViewController.swift` | 手表列表和设备选择 |
| `LocationViewController.swift` | 手表定位页面 |
| `WatchQrScannerViewController.swift` | 二维码扫描页面及相机生命周期 |
| `AddContactViewController.swift` | 添加联系人或群成员 |
| `WatchAvatarResolver.swift` | 手表和用户头像解析 |
| `GroupAvatarComposer.swift` | 群组头像合成 |
| `WatchMapView.swift` | 地图视图 |

### 4.5 iOS 配置和通用 UI：`Config/`、`UI/`

| 路径 | 职责 |
| --- | --- |
| `Config/WatchSdkConfig.swift` | SDK App ID、SecretKey、房间号和默认手表产品配置 |
| `UI/Theme.swift` | 颜色、字体和通用视觉样式 |
| `UI/WatchLogger.swift` | iOS 日志封装 |
| `UI/ProfileViewController.swift` | 个人页 |
| `UI/MessagesViewController.swift` | 会话列表页 |

## 5. 模块关系和数据流

### 5.1 登录

```text
Android LoginView                    iOS LoginViewController
        │                                      │
        ├── MainActivity                       └── AppStateStore
        │       │                                      │
        │       ├── ImService.login                ├── ImService.login
        │       └── CallCoordinator.login           └── IoTSession.login
        │              └── IoTSession.login
        │
        └── 登录状态合并后进入主页面
```

Android 需要同时等待 IM 和 IoT 登录结果；iOS 由 `AppStateStore` 监听两类登录状态，并将状态传给登录页面和根页面。

### 5.2 IM 消息

```text
MessagesView / ChatView
          │
          └── ImService
                ├── 会话列表与会话状态
                ├── 历史消息与实时消息
                ├── 文本消息发送
                └── Tencent IM SDK
```

`ConversationMapper` 和 `MessageConversation` 位于 SDK 模型与页面模型之间。页面不需要直接处理 `V2TIMConversation` 或 `V2TIMMessage`。

### 5.3 通话

```text
通话页面
   │
   └── CallCoordinator
         ├── CallStateStore                 ──> CallUIState
         ├── CallSignaling
         │     └── CallSignalTransport
         │             └── ImCallSignalTransport
         │                    └── ImService ──> IM SDK
         └── CallMediaSession
                └── IoTSession ──> IoT／TRTC SDK
```

呼出流程：

1. 页面创建 `CallTarget` 和 `CallMediaType`。
2. `CallCoordinator` 更新本地通话状态。
3. `CallSignaling` 发送呼叫信令。
4. `CallMediaSession` 调用 IoT／TRTC SDK 建立媒体会话。
5. 媒体开始后，信令状态和 UI 状态进入 `ACTIVE`。

来电流程：

1. `ImService` 收到 IM 消息并交给 `ImCallSignalTransport`。
2. `CallSignaling` 解码并识别来电。
3. `CallCoordinator` 根据绑定信息生成 `CallTarget`，更新来电状态。
4. 页面选择接听或拒接。
5. 接听时创建媒体会话并发送接听信令；拒接时发送拒接信令并结束本地状态。

### 5.4 手表绑定与通话目标

```text
绑定页面
   └── WatchBindingStore.bind(productId, deviceName)
          └── 本地绑定数据

设备／通话目标选择页面
   └── WatchBindingStore.all() / current()
          └── CallTarget(productId, deviceName)
                 ├── IM 信令目标：deviceName
                 └── IoT 呼叫目标：productId + deviceName
```

手表绑定是本地数据，不等同于 IM 会话列表。`ImService` 会根据 IM 会话和绑定手表信息补充页面所需的设备会话展示。

## 6. 功能定位索引

需要修改某个功能时，先按下表定位入口，再沿模块调用链阅读。

| 功能 | Android | iOS | 相关 SDK 或数据 |
| --- | --- | --- | --- |
| 登录表单 | `ui/LoginView.kt`、`MainActivity.kt` | `App/LoginViewController.swift`、`App/AppStateStore.swift` | IM、IoT／TRTC |
| 登录账号默认值 | `config/WatchSdkConfig.kt` | `Config/WatchSdkConfig.swift` | SDK App ID、SecretKey、房间号 |
| IM 初始化／登录 | `im/ImService.kt` | `IM/ImService.swift` | Tencent IM SDK |
| 会话列表 | `ui/MessagesView.kt`、`im/ConversationMapper.kt` | `UI/MessagesViewController.swift`、`IM/ConversationMapper.swift` | IM 会话 |
| 聊天详情 | `im/ChatView.kt` | `IM/ChatViewController.swift` | 消息历史、文本消息 |
| 群组创建／邀请 | `im/GroupMemberPickerView.kt`、`im/ImService.kt` | `IM/GroupMemberPickerViewController.swift`、`IM/ImService.swift` | IM 群组 |
| 置顶／免打扰／清空历史 | `im/ChatInfoView.kt`、`im/ImService.kt` | `IM/ChatInfoViewController.swift`、`IM/ImService.swift` | IM 会话设置 |
| 绑定手表 | `watch/BindWatchView.kt`、`watch/WatchBindingStore.kt` | `Watch/BindWatchViewController.swift`、`Watch/WatchBindingStore.swift` | `deviceName`、`productId` |
| 手表列表 | `watch/DevicesView.kt` | `Watch/DevicesViewController.swift` | 本地绑定数据 |
| 扫码绑定 | `watch/WatchQrScannerView.kt` | `Watch/WatchQrScannerViewController.swift` | 相机、二维码 |
| 手表定位 | `watch/LocationView.kt`、`watch/WatchMapView.kt` | `Watch/LocationViewController.swift`、`Watch/WatchMapView.swift` | 地图和设备位置 |
| 选择通话目标 | `ui/CallTargetPickerView.kt` | `Call/CallTargetPickerViewController.swift` | `CallTarget`、绑定手表 |
| 发起通话 | `MainActivity.startCall`、`call/CallCoordinator.kt` | `App/AppStateStore.swift`、`Call/CallCoordinator.swift` | IM 信令、IoT／TRTC |
| 来电处理 | `call/CallSignaling.kt`、`ui/IncomingCallView.kt` | `Call/CallSignaling.swift`、`Call/IncomingCallViewController.swift` | IM 来电信令 |
| 视频画面 | `ui/AndroidCallVideoSurface.kt`、`call/CallMediaSession.kt` | `Call/CallVideoSurface.swift`、`Call/CallMediaSession.swift` | `TXCloudVideoView`、UIKit |
| 摄像头／麦克风／扬声器 | `call/CallCoordinator.kt`、`call/CallMediaSession.kt` | `Call/CallCoordinator.swift`、`Call/CallMediaSession.swift` | IoT／TRTC SDK |
| 呼叫状态 | `call/CallStateStore.kt`、`call/CallSignaling.kt` | `Call/CallStateStore.swift`、`Call/CallSignaling.swift` | `CallPhase`、`CallSignalPhase` |
| 头像 | `watch/WatchAvatarResolver.kt`、`watch/GroupAvatarComposer.kt` | `Watch/WatchAvatarResolver.swift`、`Watch/GroupAvatarComposer.swift` | 本地资源 |
| 日志 | `config/WatchLogger.kt` | `UI/WatchLogger.swift` | Android Logcat、统一日志接口 |

## 7. 可移植模块边界

### 7.1 只移植音视频通话

通话功能的业务核心文件：

```text
call/CallCoordinator
call/CallSignaling
call/CallSignal
call/CallStateStore
call/CallMediaSession
call/CallVideoSurface
call/IoTSession
call/IotCredentials
call/IotSessionConfig
call/TrtcSignatureProvider
im/ImCallSignalTransport
im/ImService 中的通话信令收发部分
```

iOS 对应目录为 `Call/` 和 `IM/` 中的同名文件。移植后的宿主需要提供：

- `CallSignalTransport` 的实现，用于发送和接收呼叫信令。
- IoT／TRTC SDK 登录参数和签名提供者。
- 远端视频渲染视图适配器。
- 手表目标的 `productId`、`deviceName` 和通话类型。

通话页面文件只负责展示状态和响应按钮，不能替代 `CallCoordinator`、`CallSignaling` 或 `CallMediaSession`。

### 7.2 只移植 IM 消息

消息功能的核心文件：

```text
im/ImService
im/ImSdkAuth
im/ConversationMapper
im/MessageConversation
```

iOS 对应目录为 `IM/`。页面层根据平台选择 `MessagesView`／`ChatView` 或 `MessagesViewController`／`ChatViewController`。如果不需要通话，可以不引入 `CallCoordinator`、`CallMediaSession` 和 IoT／TRTC SDK，但需要移除 `ImService` 中通话信令的调用入口。

### 7.3 只移植手表绑定和设备列表

绑定和设备展示的核心文件：

```text
watch/WatchBindingStore
watch/BindWatchView
watch/DevicesView
watch/WatchAvatarResolver
watch/GroupAvatarComposer
```

iOS 对应目录为 `Watch/`。这部分只依赖本地绑定数据和页面资源，不依赖 IM SDK；定位页面另需地图视图和设备位置数据来源。

## 8. 配置、构建和测试入口

### 8.1 配置入口

| 平台 | 文件 | 内容 |
| --- | --- | --- |
| Android | `android/app/src/main/java/com/tencent/iot/watchapp/config/WatchSdkConfig.kt` | TRTC／IM App ID、SecretKey、房间号和默认手表配置 |
| iOS | `ios/WatchApp/WatchApp/Sources/Config/WatchSdkConfig.swift` | TRTC／IM App ID、SecretKey、房间号和默认手表配置 |
| 手表 | `../device/<target>/config.h` | 手表端 TRTC／IM 账号、房间号和设备号 |

仓库中的配置文件只保留占位值。真实 SecretKey 不应提交到仓库或打印到日志。

### 8.2 构建入口

| 平台 | 工程入口 | 依赖入口 |
| --- | --- | --- |
| Android | `android/gradlew`、`android/settings.gradle.kts` | `android/app/build.gradle.kts`，本地 AAR 和 Maven 依赖在此声明 |
| iOS | `ios/WatchApp.xcworkspace` | `ios/Podfile`、`ios/Podfile.lock` |

iOS 执行 `pod install` 后使用 Workspace，不使用裸的 `WatchApp.xcodeproj` 编译。Android 使用 Gradle Wrapper，IoT／TRTC 使用仓库内的本地 AAR；Android 和设备侧二进制 SDK 由 Git LFS 管理。

### 8.3 测试入口

| 路径 | 内容 |
| --- | --- |
| `android/app/src/test/` | Android JVM 单元测试，包括信令编解码、通话状态和 UserSig 测试 |
| `ios/WatchApp/WatchAppUITests/` | iOS UI 测试 |

## 9. 阅读顺序

按以下顺序可以最快建立项目上下文：

1. `README.md`：确认环境、账号配置、依赖安装和启动方式。
2. 对应平台的 `config/WatchSdkConfig`：确认账号、房间号和默认设备配置。
3. Android `MainActivity.kt` 或 iOS `AppStateStore.swift`：确认应用如何组装模块和切换页面。
4. `im/ImService` 或 `IM/ImService`：确认登录、会话、消息和信令入口。
5. `call/CallCoordinator` 或 `Call/CallCoordinator`：确认通话功能的统一调用入口。
6. `CallSignaling` 和 `CallMediaSession`：分别确认信令状态机和音视频 SDK 调用。
7. `watch/WatchBindingStore` 或 `Watch/WatchBindingStore`：确认手表设备号和本地绑定数据。

定位单个功能时，直接使用第 6 节的功能索引，不需要从页面目录逐层搜索。
