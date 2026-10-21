/**
 * CallManager.ets
 * 音视频通话管理器（对齐 Android: IoTCallActivity + IncomingCallManager）
 * - 统一管理通话状态（idle/calling/ringing/connected/ended）
 * - 通过 TXIoTEngine.getCallSession() 接入真实 SDK 通话能力
 * - 被叫来电：保留 WebSocket 推送入口（当前 SDK 无被叫回调，对齐 Android 等待 SDK 支持）
 */

import emitter from '@ohos.events.emitter'
import { AppState } from '../model/AppModel'
import { CallBackgroundTaskManager } from './CallBackgroundTaskManager'
import { CallPipManager } from './CallPipManager'
import {
  TXIoTAudioPlaybackDevice,
  TXIoTCallEndReason,
  TXIoTCallListener,
  TXIoTCallMediaType,
  TXIoTCallSession,
  TXIoTCallUser,
  TXIoTCamera,
  TXIoTDeviceId,
  TXIoTErrorCode
} from '@tencentcloud/liteavsdk_iot'

// 通话模式
export enum CallMode {
  AUDIO = 0, // 语音通话
  VIDEO = 1 // 视频通话
}

// 通话状态
export enum CallState {
  IDLE = 'idle',
  CALLING = 'calling', // 主叫：呼叫中，等待对方接受
  RINGING = 'ringing', // 被叫：收到邀请
  CONNECTED = 'connected', // 通话中
  ENDED = 'ended' // 通话结束
}

// 通话会话
export interface CallSession {
  sessionId: string
  peerName: string
  peerAvatar?: string
  mode: CallMode
  isCaller: boolean // 自己是否为主叫方
  productId: string
  deviceId: string // 设备 deviceName
}

// 状态变更订阅回调
export type CallStateListener = () => void

// 来电事件 emitter id（供 WebSocket 接入层发送）
export const INCOMING_CALL_EVENT_ID = 10086

// 通话页 XComponent 渲染视图 ID（TXView 即 XComponent id 字符串）
export const CALL_LOCAL_VIEW_ID = 'iot_call_local_preview'
export const CALL_REMOTE_VIEW_ID = 'iot_call_remote_view'

/**
 * 通话管理器（全局单例）
 */
class CallManagerInner {
  currentSession: CallSession | null = null
  state: CallState = CallState.IDLE
  durationSeconds: number = 0
  // UI 控件状态（复用同一页面）
  micOn: boolean = true
  speakerOn: boolean = false
  cameraOn: boolean = true
  blurBackground: boolean = false
  // 远端是否已有视频帧到达（由 onCallUserVideoAvailable 回调驱动）
  hasRemoteVideoFrame: boolean = false
  // 通话结束原因文案（ENDED 状态展示，对齐 Android reasonText）
  endReason: string = ''
  // 一次性提示消息（CallPage 观察后 toast 并消费，对齐 Android show() 分支提示）
  notice: string = ''
  // 当前是否前置摄像头
  private frontCamera: boolean = true
  private timer: number = -1
  private listeners: CallStateListener[] = []
  private eventInited: boolean = false
  private sdkListenerRegistered: boolean = false

  // ========== SDK 通话回调（对齐 Android sessionListener） ==========
  private sdkListener: TXIoTCallListener = {
    onError: (code: TXIoTErrorCode, msg: string) => {
      console.error(`❌ [CallManager] onError code=${code} msg=${msg}`)
      this.showNotice(`错误(${code}): ${msg}`)
    },
    onCallBegin: (_mediaType: TXIoTCallMediaType) => {
      console.info('📞 [CallManager] 对方已接受，通话开始')
      this.state = CallState.CONNECTED
      // 冗余确认一次：通话已建立时必须持有 VOIP 长时任务，保障退后台后会话不被挂起。
      this.ensureBackgroundProtection()
      this.startTimer()
      this.notify()
    },
    onCallEnd: (_mediaType: TXIoTCallMediaType, reason: TXIoTCallEndReason) => {
      console.info(`📞 [CallManager] 通话结束 reason=${reason}`)
      this.releaseSdkMedia()
      this.stopTimer()
      // 通话实际结束后立即取消通知和后台运行资格，不能等 2 秒结束态展示结束。
      CallBackgroundTaskManager.stop()
      CallPipManager.release()
      this.endReason = CallManagerInner.endReasonText(reason)
      this.state = CallState.ENDED
      this.hasRemoteVideoFrame = false
      this.notify()
      // 2 秒后自动复位（页面随之关闭）
      setTimeout(() => {
        if (this.state === CallState.ENDED) {
          this.resetToIdle()
        }
      }, 2000)
    },
    onCallRejected: (_callUser: TXIoTCallUser) => {
      this.showNotice('通话被拒绝')
    },
    onCallNoResponse: (_callUser: TXIoTCallUser) => {
      this.showNotice('对方未响应')
    },
    onCallLineBusy: (_callUser: TXIoTCallUser) => {
      this.showNotice('对方忙线')
    },
    onCallUserOffline: (_callUser: TXIoTCallUser) => {
      this.showNotice('设备未在线')
    },
    onCallUserAudioAvailable: (_callUser: TXIoTCallUser, available: boolean) => {
      console.info(`📞 [CallManager] 远端音频可用=${available}`)
    },
    onCallUserVideoAvailable: (callUser: TXIoTCallUser, available: boolean) => {
      console.info(`📞 [CallManager] 远端视频可用=${available}`)
      if (available && this.currentSession?.mode === CallMode.VIDEO) {
        // 对齐 Android：远端视频可用时（重新）绑定远端渲染视图
        this.getSession()?.startRemoteView(callUser, CALL_REMOTE_VIEW_ID)
      }
      this.markRemoteVideoAvailable(available)
    },
    onCallNetworkQualityChanged: () => {
    }
  }

  /**
   * 初始化：订阅 WebSocket 来电事件
   * 入口建议在 App 启动或登录成功后调用一次
   */
  init(): void {
    if (this.eventInited) {
      return
    }
    this.eventInited = true
    emitter.on({ eventId: INCOMING_CALL_EVENT_ID }, (event) => {
      const data = event.data || {}
      const session: CallSession = {
        sessionId: (data.sessionId as string) || `${Date.now()}`,
        peerName: (data.peerName as string) || '未知联系人',
        peerAvatar: data.peerAvatar as string,
        mode: (data.mode as number) === 1 ? CallMode.VIDEO : CallMode.AUDIO,
        isCaller: false,
        productId: (data.productId as string) || '',
        deviceId: (data.deviceId as string) || ''
      }
      this.receiveIncomingCall(session)
    })
    // PiP 控制面板动作映射到通话控件（CallPipManager 不反向依赖本模块）
    CallPipManager.setActionHandler({
      onHangUp: () => this.hangup(),
      onMicSwitch: (on: boolean) => {
        if (on !== this.micOn) {
          this.toggleMic()
        }
      },
      onCameraSwitch: (on: boolean) => {
        if (on !== this.cameraOn) {
          this.toggleCamera()
        }
      }
    })
    // 画中画停止、surface 归还主窗口后重绑远端视图（内部已按视频模式守卫，语音通话为空操作）
    CallPipManager.setRestoreHandler(() => {
      this.bindRemoteView()
    })
    console.info('📞 [CallManager] inited, listening incoming call events')
  }

  /** 订阅状态变更（UI 层用来触发 @State 刷新） */
  addListener(listener: CallStateListener): void {
    this.listeners.push(listener)
  }

  removeListener(listener: CallStateListener): void {
    const idx = this.listeners.indexOf(listener)
    if (idx >= 0) {
      this.listeners.splice(idx, 1)
    }
  }

  private notify(): void {
    for (const l of this.listeners) {
      try {
        l()
      } catch (e) { /* ignore */
      }
    }
  }

  /** 展示一次性提示（由 CallPage toast 消费） */
  private showNotice(msg: string): void {
    this.notice = msg
    this.notify()
  }

  /** CallPage 取走并清空当前提示 */
  consumeNotice(): string {
    const n = this.notice
    this.notice = ''
    return n
  }

  /**
   * 通话激活态确保已申请 VOIP 长时任务。
   * 可由通话状态机和 EntryAbility.onBackground 重复调用，内部幂等。
   */
  ensureBackgroundProtection(): void {
    if (this.state === CallState.CALLING || this.state === CallState.RINGING ||
      this.state === CallState.CONNECTED) {
      CallBackgroundTaskManager.start()
    }
  }

  // ========== 主叫：发起呼叫（对齐 Android initCallSession） ==========
  startCall(peerName: string, mode: CallMode, peerAvatar: string | undefined, productId: string, deviceName: string): void {
    this.currentSession = {
      sessionId: `${Date.now()}`,
      peerName: peerName,
      peerAvatar: peerAvatar,
      mode: mode,
      isCaller: true,
      productId: productId,
      deviceId: deviceName
    }
    this.state = CallState.CALLING
    this.durationSeconds = 0
    this.micOn = true
    this.speakerOn = mode === CallMode.VIDEO
    this.cameraOn = mode === CallMode.VIDEO
    this.blurBackground = false
    this.hasRemoteVideoFrame = false
    this.endReason = ''
    this.frontCamera = true
    // 从呼叫发起阶段开始申请保活，用户切后台等待对方接听时也不会被系统挂起。
    this.ensureBackgroundProtection()
    // 音视频通话均准备画中画：退后台自动拉起；视频保持摄像头采集与推流，语音保持通话面板可达
    CallPipManager.prepare(mode === CallMode.VIDEO, peerName)

    const session = this.ensureSession()
    if (!session) {
      this.showNotice('通话服务未初始化')
      this.resetToIdle()
      return
    }
    if (!productId || !deviceName) {
      this.showNotice('设备信息不完整')
      this.resetToIdle()
      return
    }

    // 对齐 Android：视频通话先开本地摄像头与远端视图，再开麦克风、发起呼叫
    if (mode === CallMode.VIDEO) {
      session.openCamera(TXIoTCamera.FRONT, CALL_LOCAL_VIEW_ID)
      session.startRemoteView(this.buildCallUser(), CALL_REMOTE_VIEW_ID)
    }
    session.openMicrophone()
    session.callDevice(this.buildDeviceId(),
      mode === CallMode.VIDEO ? TXIoTCallMediaType.VIDEO : TXIoTCallMediaType.AUDIO)
    session.selectAudioPlaybackDevice(
      this.speakerOn ? TXIoTAudioPlaybackDevice.SPEAKER_PHONE : TXIoTAudioPlaybackDevice.EAR_PIECE)

    console.info(`📞 [CallManager] 发起${mode === CallMode.VIDEO ? '视频' : '语音'}通话 → ${peerName} (${productId}/${deviceName})`)
    this.notify()
  }

  // ========== 被叫：收到来电（当前 SDK 无被叫回调，保留推送入口） ==========
  receiveIncomingCall(session: CallSession): void {
    if (this.state !== CallState.IDLE) {
      console.warn('⚠️ [CallManager] 已在通话中，忽略新来电')
      return
    }
    this.currentSession = session
    this.state = CallState.RINGING
    this.durationSeconds = 0
    this.micOn = true
    this.speakerOn = session.mode === CallMode.VIDEO
    this.cameraOn = session.mode === CallMode.VIDEO
    this.blurBackground = false
    this.hasRemoteVideoFrame = false
    this.endReason = ''
    this.frontCamera = true
    // 被叫响铃阶段也需要后台保活，避免用户切后台时来电会话被系统回收。
    this.ensureBackgroundProtection()
    // 音视频来电均准备画中画
    CallPipManager.prepare(session.mode === CallMode.VIDEO, session.peerName)

    // 对齐 Android：来电时也提前开启麦克风/摄像头/远端视图
    const sdkSession = this.ensureSession()
    if (sdkSession) {
      if (session.mode === CallMode.VIDEO) {
        sdkSession.openCamera(TXIoTCamera.FRONT, CALL_LOCAL_VIEW_ID)
        sdkSession.startRemoteView(this.buildCallUser(), CALL_REMOTE_VIEW_ID)
      }
      sdkSession.openMicrophone()
      sdkSession.selectAudioPlaybackDevice(
        this.speakerOn ? TXIoTAudioPlaybackDevice.SPEAKER_PHONE : TXIoTAudioPlaybackDevice.EAR_PIECE)
    }
    console.info(`📞 [CallManager] 收到来电 ← ${session.peerName}`)
    this.notify()
  }

  // ========== 接听 ==========
  answer(): void {
    if (this.state !== CallState.RINGING) {
      return
    }
    this.state = CallState.CONNECTED
    this.ensureBackgroundProtection()
    this.startTimer()
    // 注意：当前 SDK 无显式 accept 接口（与 Android 一致），接听即本地进入通话态
    console.info('📞 [CallManager] 已接听')
    this.notify()
  }

  // ========== 挂断（主叫取消/被叫拒绝/通话中挂断） ==========
  hangup(): void {
    this.stopTimer()
    try {
      this.getSession()?.hangup()
    } catch (e) {
      console.warn(`⚠️ [CallManager] hangup 异常: ${e}`)
    }
    this.releaseSdkMedia()
    console.info('📞 [CallManager] 挂断')
    this.resetToIdle()
  }

  // ========== 对方挂断（WebSocket 推送路径） ==========
  peerHangup(): void {
    // 对方已结束通话，立即撤销后台任务而非等待 2 秒结束态 UI 自动关闭。
    CallBackgroundTaskManager.stop()
    CallPipManager.release()
    this.releaseSdkMedia()
    this.stopTimer()
    this.endReason = '对方已挂断'
    this.state = CallState.ENDED
    this.hasRemoteVideoFrame = false
    this.notify()
    // 2 秒后自动关闭
    setTimeout(() => {
      if (this.state === CallState.ENDED) {
        this.resetToIdle()
      }
    }, 2000)
    console.info('📞 [CallManager] 对方已挂断')
  }

  // ========== UI 控件切换（对齐 Android setListener） ==========
  toggleMic(): void {
    this.micOn = !this.micOn
    const session = this.getSession()
    if (this.micOn) {
      session?.openMicrophone()
    } else {
      session?.closeMicrophone()
    }
    this.notify()
  }

  toggleSpeaker(): void {
    this.speakerOn = !this.speakerOn
    this.getSession()?.selectAudioPlaybackDevice(
      this.speakerOn ? TXIoTAudioPlaybackDevice.SPEAKER_PHONE : TXIoTAudioPlaybackDevice.EAR_PIECE)
    this.notify()
  }

  toggleCamera(): void {
    this.cameraOn = !this.cameraOn
    const session = this.getSession()
    if (this.cameraOn) {
      session?.openCamera(this.frontCamera ? TXIoTCamera.FRONT : TXIoTCamera.BACK, CALL_LOCAL_VIEW_ID)
    } else {
      session?.closeCamera()
    }
    this.notify()
  }

  toggleBlur(): void {
    this.blurBackground = !this.blurBackground;
    this.notify()
  }

  switchCamera(): void {
    this.frontCamera = !this.frontCamera
    this.getSession()?.switchCamera(this.frontCamera ? TXIoTCamera.FRONT : TXIoTCamera.BACK)
    console.info(`📞 [CallManager] switchCamera front=${this.frontCamera}`)
    this.notify()
  }

  /** XComponent onLoad 后绑定本地摄像头预览（视频通话且摄像头开启时） */
  bindLocalView(): void {
    if (this.currentSession?.mode !== CallMode.VIDEO || !this.cameraOn) {
      return
    }
    this.getSession()?.openCamera(this.frontCamera ? TXIoTCamera.FRONT : TXIoTCamera.BACK, CALL_LOCAL_VIEW_ID)
  }

  /** XComponent onLoad 后绑定远端渲染视图（视频通话时） */
  bindRemoteView(): void {
    if (this.currentSession?.mode !== CallMode.VIDEO) {
      return
    }
    this.getSession()?.startRemoteView(this.buildCallUser(), CALL_REMOTE_VIEW_ID)
  }

  /** 远端视频可用状态（onCallUserVideoAvailable 驱动） */
  markRemoteVideoAvailable(available: boolean): void {
    if (this.hasRemoteVideoFrame === available) {
      return
    }
    this.hasRemoteVideoFrame = available
    this.notify()
  }

  // ========== 内部：SDK 会话与资源管理 ==========

  private getSession(): TXIoTCallSession | null {
    return AppState.engine().getCallSession()
  }

  /** 获取 SDK 通话会话并保证监听器已注册（仅注册一次） */
  private ensureSession(): TXIoTCallSession | null {
    const session = this.getSession()
    if (session && !this.sdkListenerRegistered) {
      session.addListener(this.sdkListener)
      this.sdkListenerRegistered = true
    }
    return session
  }

  private buildDeviceId(): TXIoTDeviceId {
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = this.currentSession?.productId || ''
    deviceId.deviceName = this.currentSession?.deviceId || ''
    return deviceId
  }

  private buildCallUser(): TXIoTCallUser {
    const callUser = new TXIoTCallUser()
    callUser.deviceId = this.buildDeviceId()
    return callUser
  }

  /** 释放本地/远端音视频资源（对齐 Android releaseAndFinish 的清理） */
  private releaseSdkMedia(): void {
    const session = this.getSession()
    if (!session) {
      return
    }
    try {
      if (this.currentSession?.mode === CallMode.VIDEO) {
        session.stopRemoteView(this.buildCallUser())
        session.closeCamera()
      }
      session.closeMicrophone()
    } catch (e) {
      console.warn(`⚠️ [CallManager] 释放通话资源异常: ${e}`)
    }
  }

  private resetToIdle(): void {
    // 覆盖本地挂断、参数校验失败和通话结束延迟复位等所有清理路径。
    CallBackgroundTaskManager.stop()
    CallPipManager.release()
    this.state = CallState.IDLE
    this.currentSession = null
    this.durationSeconds = 0
    this.hasRemoteVideoFrame = false
    this.endReason = ''
    this.notify()
  }

  /** 通话结束原因文案（对齐 Android reasonText） */
  private static endReasonText(reason: TXIoTCallEndReason): string {
    switch (reason) {
      case TXIoTCallEndReason.LOCAL_HANGUP:
        return '已挂断'
      case TXIoTCallEndReason.REMOTE_HANGUP:
        return '对方已挂断'
      case TXIoTCallEndReason.NETWORK_ERROR:
        return '网络异常'
      case TXIoTCallEndReason.CALL_PERMISSION_DENIED:
        return '无通话权限'
      default:
        return '通话已结束'
    }
  }

  // ========== 计时器 ==========
  private startTimer(): void {
    this.stopTimer()
    this.durationSeconds = 0
    this.timer = setInterval(() => {
      this.durationSeconds += 1
      // 语音通话画中画浮层同步计时（非语音 PiP 时内部为空实现）
      CallPipManager.updateAudioCallOverlay(this.currentSession?.peerName ?? '', this.durationText)
      this.notify()
    }, 1000)
  }

  private stopTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  // ========== 展示工具 ==========
  get durationText(): string {
    const m = Math.floor(this.durationSeconds / 60)
    const s = this.durationSeconds % 60
    const mm = m < 10 ? `0${m}` : `${m}`
    const ss = s < 10 ? `0${s}` : `${s}`
    return `${mm}:${ss}`
  }

  get statusText(): string {
    if (!this.currentSession) {
      return ''
    }
    switch (this.state) {
      case CallState.CALLING:
        return '等待对方接受邀请...'
      case CallState.RINGING:
        return this.currentSession.mode === CallMode.AUDIO ? '邀请你语音通话...' : '邀请你视频通话...'
      case CallState.CONNECTED:
        return this.durationText
      case CallState.ENDED:
        return this.endReason || '通话已结束'
      default:
        return ''
    }
  }
}

// 导出单例
export const CallManager: CallManagerInner = new CallManagerInner()

/**
 * 外部便捷触发来电（WebSocket 消息到达时调用此方法）
 * 示例：
 *   triggerIncomingCall({ peerName: '门口机', mode: 1, productId: 'xxx', deviceId: 'dev_001' })
 */
export interface IncomingCallPayload {
  sessionId?: string
  peerName: string
  peerAvatar?: string
  mode: number // 0=audio, 1=video
  productId?: string
  deviceId?: string
}

export function triggerIncomingCall(payload: IncomingCallPayload): void {
  emitter.emit(
    { eventId: INCOMING_CALL_EVENT_ID },
    {
      data: {
        sessionId: payload.sessionId,
        peerName: payload.peerName,
        peerAvatar: payload.peerAvatar,
        mode: payload.mode,
        productId: payload.productId,
        deviceId: payload.deviceId
      }
    }
  )
}
