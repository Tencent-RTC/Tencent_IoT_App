import {
  getIoTEngineInstance,
  TXIoTEngine,
  TXIoTEngineListener,
  TXIoTPushMessage
} from '@tencentcloud/liteavsdk_iot'
import emitter from '@ohos.events.emitter'

// 推送消息 emitter 事件 ID（应用级常量，原 IoTAPIBridge.PUSH_MSG_EVENT_ID）
export const PUSH_MSG_EVENT_ID = 10001

// 用户模型
export interface UserModel {
  id: string
  username: string
  phone: string
  password?: string
  loginType?: string
  appKey?: string
  appSecret?: string
  userId?: string
}

// 设备设置模型
export interface DeviceSettings {
  motionDetection: boolean
  soundAlarm: boolean
  nightVision: boolean
}

// 设备模型
export interface DeviceModel {
  id: string
  name: string
  location: string
  online: boolean
  signal: string
  firmware: string
  addTime: string
  settings: DeviceSettings
  // SDK 相关字段（对应 iOS 端 Device.productId / Device.deviceName）
  productId?: string
  deviceName?: string
  familyId?: string
  roomId?: string
  iconUrl?: string
  // 是否为分享设备（对应 iOS 端 getSharedDevices 返回的设备）
  isShared?: boolean
}

// 推送消息模型（对应 iOS: PushMessageItem）
export interface PushMessageItem {
  id: string
  messageTime: number // 时间戳 ms
  type: number
  subType: number
  topic: string
  payload: string
  productId: string
  deviceName: string
}

// 应用全局状态
export class AppState {
  static currentUser: UserModel | null = null
  static devices: DeviceModel[] = []
  static currentDevice: DeviceModel | null = null
  static isRecording: boolean = false
  static isTalking: boolean = false
  // 当前家庭ID（登录后由设备列表页拉取家庭列表时设置）
  static currentFamilyId: string = ''
  // 当前家庭名称
  static currentFamilyName: string = ''
  // 家庭列表变更标志（对齐 Android EXTRA_FAMILY_LIST_CHANGED）：
  // 家庭管理页创建/重命名/删除/退出家庭成功后置 true，设备列表页 onPageShow 检测后重载家庭列表
  static familyListChanged: boolean = false
  // 当前进入设备详情页所选的通道列表（对应 iOS: channelList）
  static currentChannelList: number[] = [0]
  // 推送消息全局存储（对应 iOS: PushMessageStore.shared.messages）
  // 全局推送监听收到消息后直接写入，消息列表页直接读取，不依赖 emitter
  static pushMessages: PushMessageItem[] = []

  // ==================== IoT 引擎（直接使用 SDK，不再经过 IoTAPIBridge 中间层） ====================

  // 引擎单例引用：getIoTEngineInstance 在整个 App 生命周期内复用同一实例，
  // 以保证登录态在各页面间共享
  private static _engine: TXIoTEngine | null = null
  // 全局推送监听器（仅注册一次）
  private static _pushListener: TXIoTEngineListener | null = null

  /**
   * 获取 TXIoTEngine 单例
   * 各页面直接通过此方法拿到 engine 后调用对应 Manager（FamilyManager/DeviceManager/...）
   */
  static engine(): TXIoTEngine {
    if (!AppState._engine) {
      AppState._engine = getIoTEngineInstance()
      console.info('✅ TXIoTEngine 创建成功')
    }
    return AppState._engine
  }

  /**
   * 注册全局推送消息监听（登录成功后调用，内部保证只注册一次）
   * 新版 TXIoTPushMessage 仅包含 messageTime/type/subType/deviceId 四个字段
   */
  static setupPushNotification(): void {
    if (AppState._pushListener) {
      return
    }
    AppState._pushListener = {
      onReceivePushMessage: (pushMessage: TXIoTPushMessage) => {
        if (!pushMessage) {
          return
        }
        const type = pushMessage.type ?? 0
        const subType = pushMessage.subType ?? 0
        const productId = pushMessage.deviceId?.productId ?? ''
        const deviceName = pushMessage.deviceId?.deviceName ?? ''
        const messageTime = pushMessage.messageTime ?? Date.now()
        console.info(`📨 收到推送消息: type=${type}, subType=${subType}, device=${productId}/${deviceName}`)
        try {
          const msgItem: PushMessageItem = {
            id: String(Date.now()) + '_' + String(Math.random()),
            messageTime: messageTime > 0 ? messageTime : Date.now(),
            type: type,
            subType: subType,
            // 新版 SDK 推送消息不再返回 topic / payload，留空兼容旧 UI
            topic: '',
            payload: '',
            productId: productId,
            deviceName: deviceName
          }
          AppState.appendPushMessage(msgItem)
          const eventData: emitter.EventData = { data: { 'item': JSON.stringify(msgItem) } }
          emitter.emit({ eventId: PUSH_MSG_EVENT_ID }, eventData)
        } catch (err) {
          console.error(`[AppState] ❌ onReceivePushMessage 处理异常: ${JSON.stringify(err)}`)
        }
      }
    }
    AppState.engine().addListener(AppState._pushListener)
    console.info('✅ 全局推送监听器已注册')
  }

  /**
   * 退出登录：登出引擎并清理家庭ID
   */
  static logout(): void {
    AppState.engine().logout()
    AppState.currentFamilyId = ''
    console.info('🛑 已退出登录')
  }

  /** 追加一条推送消息，最多保留 200 条（对应 iOS: PushMessageStore.append） */
  static appendPushMessage(item: PushMessageItem): void {
    AppState.pushMessages = [item, ...AppState.pushMessages].slice(0, 200)
    console.info(`[AppState] appendPushMessage 后当前消息数: ${AppState.pushMessages.length}`)
  }

  /** 清空推送消息 */
  static clearPushMessages(): void {
    AppState.pushMessages = []
  }
}
