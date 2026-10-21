import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import pasteboard from '@ohos.pasteboard'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { image } from '@kit.ImageKit'
import fs from '@ohos.file.fs'
import { fileUri } from '@kit.CoreFileKit'
import emitter from '@ohos.events.emitter'
import window from '@ohos.window'
import display from '@ohos.display'
import common from '@ohos.app.ability.common'
import { AppState, DeviceModel } from '../model/AppModel'
import {
  TXIoTMonitorSession,
  TXIoTMonitorSessionListener,
  TXIoTStreamType,
  TXIoTPTZCommand,
  TXIoTLocalRecordingParams,
  TXIoTErrorCode,
  TXIoTPlayState,
  TXIoTDeviceId
} from '@tencentcloud/liteavsdk_iot'
import {
  PrimaryButton,
  CancelButton,
  DialogTitleText,
  SecondaryText,
  AppColor,
  AppFontSize,
  AppRadius,
  GradientNavBar
} from '../components/AppTheme'
import { CommonBottomSheet } from '../components/CommonBottomSheet'

@Entry
@Component
struct DeviceDetailPage {
  @State device: DeviceModel | null = null
  // 多路拉流的通道列表（来自 AppState.currentChannelList）
  @State channelList: number[] = [0]
  // 当前激活的通道（为截图/录像/云台/画质按钮的目标通道）
  @State activeChannelId: number = 0
  // 每通道 XComponent 是否已就绪
  @State channelReady: Record<string, boolean> = {}
  @State isTalking: boolean = false
  @State isRecording: boolean = false
  @State isMuted: boolean = false
  @State isHighQuality: boolean = true
  @State showPTZ: boolean = false
  @State currentTime: string = ''
  @State sessionEstablished: boolean = false
  @State showCommandInput: boolean = false
  @State recordingDurationMs: number = 0
  // 横屏/竖屏状态
  @State isFullscreen: boolean = false
  // 分享相关状态
  @State showShareTokenDialog: boolean = false
  @State shareTokenJson: string = ''
  // 加载遮罩（单通道时显示，对齐 Android loadingOverlay）
  @State loadingOverlay: boolean = true
  // 拉流失败遮罩（对齐 Android streamErrorView，点击重试）
  @State streamFailed: boolean = false
  // 非致命错误码（对齐 Android NON_FATAL_ERROR_CODES：仅 toast，不中断拉流）
  private readonly NON_FATAL_ERROR_CODES: TXIoTErrorCode[] = [
    TXIoTErrorCode.ERR_MIC_OCCUPY,
    TXIoTErrorCode.ERR_CAMERA_OCCUPY,
    TXIoTErrorCode.ERR_SPEAKER_START_FAIL,
    TXIoTErrorCode.ERR_MIC_NOT_AUTHORIZED,
    TXIoTErrorCode.ERR_CAMERA_NOT_AUTHORIZED
  ]
  // emitter 事件 ID，用于子线程 → UI 线程通信
  private readonly SNAPSHOT_EVENT_ID: number = 10086
  private readonly RECORDING_SAVE_EVENT_ID: number = 10087
  @State commandText: string =
    '{\n  "method": "report",\n  "clientToken": "demo-1",\n  "params": {\n    "_sys_call_status": 0\n  }\n}'
  private timeTimer: number = -1
  // IoT 监控会话实例（新版 SDK 的 TXIoTMonitorSession，直接使用，不再经过适配器）
  private mediaSession: TXIoTMonitorSession | null = null
  // 监控会话目标设备（startSession 需要传入）
  private monitorDeviceId: TXIoTDeviceId = new TXIoTDeviceId()
  // 是否首次会话（对齐 Android isFirstSession）
  private isFirstSession: boolean = true
  // 会话是否处于暂停/后台状态（对齐 Android onPause/onResume）
  private isSessionPaused: boolean = false
  // 已向 SDK 发起会话请求；用于避免多个 XComponent 的 onLoad 重复启动会话
  private isSessionStartRequested: boolean = false
  // 多通道截图批量收集
  private snapshotExpectedCount: number = 0
  private snapshotCompletedCount: number = 0
  private snapshotPendingPaths: string[] = []
  // 多通道录像批量收集
  private recordingChannels: number[] = []
  private recordingFilePaths: string[] = []

  /** 根据通道 ID 生成唯一 XComponent ID */
  private xcomponentId(channelId: number): string {
    return `iot_remote_video_${channelId}`
  }

  // 媒体会话监听器（对齐 Android mediaSessionListener）
  private sessionListener: TXIoTMonitorSessionListener = {
    onSessionEstablished: () => {
      console.info('✅ 媒体会话建立成功')
      this.sessionEstablished = true
      this.streamFailed = false
      this.showToast('连接成功')
      // 拉流时保持屏幕常亮
      this.setKeepScreenOn(true)
      // 对齐 Android：会话建立后重新绑定已就绪的视频组件。
      this.startRemoteViews()
      // 再次同步音频状态，覆盖 SDK 建立远端音轨期间的默认状态。
      this.applyRemoteAudioMuteState(this.isMuted)
    },
    onSessionReconnecting: () => {
      console.info('🔄 媒体会话重连中...')
      this.sessionEstablished = false
      this.showToast('重连中...')
      // 对齐 Android: 单通道时显示加载遮罩
      if (this.channelList.length <= 1) {
        this.loadingOverlay = true
      }
    },
    onSessionRecovery: () => {
      console.info('✅ 媒体会话恢复')
      this.sessionEstablished = true
      this.showToast('已恢复连接')
    },
    onRemoteStreamAvailable: (channelId: number, available: boolean) => {
      console.info(`📺 远程流状态变化: channelId=${channelId}, available=${available}`)
    },
    onRenderFirstFrame: (channelId: number) => {
      console.info(`🎬 首帧渲染: channelId=${channelId}`)
      this.streamFailed = false
      // 对齐 Android: 单通道时隐藏加载遮罩
      if (this.channelList.length <= 1) {
        this.loadingOverlay = false
      }
    },
    onPlayStateChanged: (channelId: number, state: TXIoTPlayState) => {
      console.info(`▶️ 播放状态变化: channelId=${channelId}, state=${state}`)
      // 对齐 Android: 根据播放状态控制加载遮罩
      const loading = state !== TXIoTPlayState.PLAYING
      if (this.channelList.length <= 1) {
        this.loadingOverlay = loading
      }
    },
    onSnapshotComplete: (channelId: number, pixelMap: image.PixelMap | null, errCode: TXIoTErrorCode) => {
      if (errCode !== TXIoTErrorCode.ERR_SUCCESS || !pixelMap) {
        console.error(`❌ 截图失败: channelId=${channelId}, errCode=${errCode}`)
        this.onSnapshotCollected(channelId, null)
        return
      }
      console.info(`📸 截图成功: channelId=${channelId}，正在打包...`)
      this.packSnapshot(channelId, pixelMap)
    },
    onLocalRecordBegin: (channelId: number, errCode: TXIoTErrorCode, storagePath: string) => {
      if (errCode !== TXIoTErrorCode.ERR_SUCCESS) {
        console.error(`❌ 录像启动失败: channelId=${channelId}, errCode=${errCode}`)
        return
      }
      console.info(`🎬 录像开始: channelId=${channelId}, path=${storagePath}`)
      this.recordingChannels.push(channelId)
      this.isRecording = true
      this.recordingDurationMs = 0
      // 仅在首个通道开始录像时提示
      if (this.recordingChannels.length === 1) {
        this.showToast('录像开始')
      }
    },
    onLocalRecording: (channelId: number, durationMs: number, storagePath: string) => {
      this.recordingDurationMs = durationMs
    },
    onLocalRecordComplete: (channelId: number, errCode: TXIoTErrorCode, storagePath: string) => {
      const success = errCode === TXIoTErrorCode.ERR_SUCCESS
      console.info(
        `🎬 录像${success ? '完成' : '失败'}: channelId=${channelId}, errCode=${errCode}, path=${storagePath}`)
      if (success) {
        this.recordingFilePaths.push(storagePath)
      }
      this.recordingChannels = this.recordingChannels.filter(ch => ch !== channelId)
      // 所有通道录像均已结束
      if (this.recordingChannels.length === 0) {
        this.isRecording = false
        this.recordingDurationMs = 0
        if (this.recordingFilePaths.length > 0) {
          const paths = this.recordingFilePaths
          this.recordingFilePaths = []
          emitter.emit(
            { eventId: this.RECORDING_SAVE_EVENT_ID },
            { data: { filePaths: paths } }
          )
        } else {
          this.showToast('录像失败')
        }
      }
    },
    onError: (channelId: number, errCode: TXIoTErrorCode, errMsg: string) => {
      console.error(`❌ 媒体会话错误: channelId=${channelId}, ${errCode}, ${errMsg}`)
      // 对齐 Android NON_FATAL_ERROR_CODES：外设占用/未授权仅提示，不中断拉流
      if (this.NON_FATAL_ERROR_CODES.indexOf(errCode) >= 0) {
        this.showToast(errMsg)
        if (this.isTalking) {
          this.stopTalking()
        }
        return
      }
      // 对齐 Android：ERR_DEVICE_SWITCH_TO_VOIP 专属文案，其余统一提示拉流失败
      if (errCode === TXIoTErrorCode.ERR_DEVICE_SWITCH_TO_VOIP) {
        this.showToast('设备已切换为通话模式，停止拉流')
      } else {
        this.showToast(`拉流失败：${errMsg}`)
      }
      this.streamFailed = true
      this.sessionEstablished = false
      this.isSessionStartRequested = false
      this.loadingOverlay = false
      this.setKeepScreenOn(false)
      // 对齐 Android handleError：致命错误后停止拉流并停止会话，
      // 否则重试时 startSession 作用于已启动的失败会话会被 SDK 忽略、不再回调 onError
      this.stopRemoteViews()
      this.mediaSession?.stopSession()
    }
  }

  /**
   * 在所有目标通道完成 startRemoteView 注册后设置统一的远端音频状态。
   * 这样首次入房会按正确通道列表建立音频订阅；会话建立后会再同步一次。
   */
  private applyRemoteAudioMuteState(muted: boolean): void {
    this.mediaSession?.muteAllRemoteAudio(muted)
  }

  aboutToAppear() {
    this.device = AppState.currentDevice
    // 从全局状态读取用户选择的通道列表
    const chs = AppState.currentChannelList && AppState.currentChannelList.length > 0
      ? AppState.currentChannelList.slice()
      : [0]
    this.channelList = chs
    this.activeChannelId = chs[0]
    this.startTimer()
    // 订阅截图事件（在 UI 主线程中执行，确保 showAssetsCreationDialog 可以正常弹出）
    emitter.on({ eventId: this.SNAPSHOT_EVENT_ID }, async (event) => {
      const tmpPaths = event.data?.tmpPaths as string[]
      if (!tmpPaths || tmpPaths.length === 0) {
        return
      }
      await this.saveSnapshotsToAlbum(tmpPaths)
    })
    // 订阅录像保存事件
    emitter.on({ eventId: this.RECORDING_SAVE_EVENT_ID }, async (event) => {
      const filePaths = event.data?.filePaths as string[]
      if (!filePaths || filePaths.length === 0) {
        return
      }
      await this.saveRecordingsToAlbum(filePaths)
    })
    // 启动媒体会话
    this.startMediaSession()
  }

  aboutToDisappear() {
    if (this.timeTimer !== -1) {
      clearInterval(this.timeTimer)
    }
    // 取消订阅截图事件和录像保存事件
    emitter.off(this.SNAPSHOT_EVENT_ID)
    emitter.off(this.RECORDING_SAVE_EVENT_ID)
    // 离开页面时恢复竖屏
    if (this.isFullscreen) {
      this.setWindowOrientation(false)
    }
    // 页面销毁时恢复允许息屏
    this.setKeepScreenOn(false)
    // 停止媒体会话（对齐 Android onDestroy）
    this.stopMediaSession()
  }

  // 页面显示/隐藏生命周期（对齐 Android onResume/onPause）
  onPageShow() {
    // 对齐 Android onResume: 恢复会话
    if (this.isSessionPaused && this.device) {
      this.isSessionPaused = false
      this.isSessionStartRequested = false
      this.startSessionWhenViewsReady()
      // 恢复前台拉流时保持屏幕常亮
      this.setKeepScreenOn(true)
      console.info('🔄 回到前台，重新启动会话')
    }
  }

  onPageHide() {
    // 对齐 Android onPause: 退后台时自动停止对讲、录制
    this.stopTalkAndRecordingOnBackground()
    // 对齐 Android onPause: 暂时停止会话
    if (this.mediaSession && this.isSessionStartRequested) {
      this.mediaSession.stopSession()
      this.sessionEstablished = false
      this.isSessionStartRequested = false
      this.isSessionPaused = true
      // 退后台时恢复允许息屏
      this.setKeepScreenOn(false)
      console.info('⏸ 退后台，停止会话')
    }
  }

  /** 对齐 Android stopTalkAndRecording: 退后台时自动停止对讲、录制 */
  private stopTalkAndRecordingOnBackground(): void {
    if (this.isTalking) {
      if (this.mediaSession) {
        try {
          this.mediaSession.stopLocalAudio()
        } catch (e) {
        }
      }
      this.isTalking = false
      this.showToast('已进入后台，已停止对讲')
    }
    if (this.isRecording) {
      const channels = this.recordingChannels.slice()
      for (const ch of channels) {
        try {
          this.mediaSession?.stopLocalRecording(ch)
        } catch (e) {
        }
      }
      this.isRecording = false
      this.recordingDurationMs = 0
      this.showToast('已进入后台，已停止录制')
    }
  }

  startTimer() {
    this.updateTime()
    this.timeTimer = setInterval(() => {
      this.updateTime()
    }, 1000)
  }

  updateTime() {
    const now = new Date()
    const y = now.getFullYear()
    const m = String(now.getMonth() + 1).padStart(2, '0')
    const d = String(now.getDate()).padStart(2, '0')
    const h = String(now.getHours()).padStart(2, '0')
    const min = String(now.getMinutes()).padStart(2, '0')
    const s = String(now.getSeconds()).padStart(2, '0')
    this.currentTime = `${y}/${m}/${d} ${h}:${min}:${s}`
  }

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  goBack() {
    router.back()
  }

  goToProperties() {
    router.pushUrl({ url: 'pages/DevicePropertiesPage' })
  }

  // ==================== 媒体会话管理 ====================

  /**
   * 所有 XComponent 就绪后，按“注册全部通道 → 设置音频状态 → 启动会话”的顺序建连。
   * 若先 startSession，鸿蒙 SDK 会以默认通道 0 请求房间信息，导致非 0 通道只建立视频流。
   */
  private startSessionWhenViewsReady(): void {
    if (!this.mediaSession || this.isSessionPaused || this.isSessionStartRequested) {
      return
    }
    for (const channelId of this.channelList) {
      if (!this.channelReady[this.xcomponentId(channelId)]) {
        return
      }
    }

    this.startRemoteViews()
    this.applyRemoteAudioMuteState(this.isMuted)
    this.isSessionStartRequested = true
    this.streamFailed = false
    this.mediaSession.startSession(this.monitorDeviceId)
    console.info(`🎬 媒体会话已启动，通道列表: ${JSON.stringify(this.channelList)}`)
  }

  /**
   * 启动媒体会话（对齐 Android startMediaSession）
   */
  startMediaSession() {
    if (!this.device) {
      console.error('❌ 设备信息为空，无法启动媒体会话')
      return
    }
    const familyId = this.device.familyId || AppState.currentFamilyId
    const productId = this.device.productId || ''
    const deviceName = this.device.deviceName || this.device.id

    if (!familyId || !productId || !deviceName) {
      console.warn('⚠️ 设备信息不完整，无法启动媒体会话')
      return
    }

    // 获取媒体会话（新版 SDK：engine.getMonitorSession() 为单例，startSession 时传入 deviceId）
    const session = AppState.engine().getMonitorSession()
    if (!session) {
      console.error('❌ 无法获取媒体会话')
      return
    }

    const deviceId = new TXIoTDeviceId()
    deviceId.productId = productId
    deviceId.deviceName = deviceName
    this.monitorDeviceId = deviceId

    this.mediaSession = session
    // 添加监听器（对齐 Android mediaSession?.addListener）
    this.mediaSession.addListener(this.sessionListener)
    // 首次会话默认静音，与 Android 保持一致。
    if (this.isFirstSession) {
      this.isFirstSession = false
      this.isMuted = true
    }
    this.streamFailed = false
    this.sessionEstablished = false
    this.isSessionStartRequested = false
    this.startSessionWhenViewsReady()
    console.info(`🎬 媒体会话已初始化，设备: ${productId}/${deviceName}，等待通道组件就绪`)
  }

  /**
   * 停止媒体会话（对齐 Android onDestroy: stopSession + removeListener）
   */
  stopMediaSession() {
    if (this.mediaSession) {
      // 停止所有正在录像的通道
      const recChannels = this.recordingChannels.slice()
      for (const ch of recChannels) {
        try {
          this.mediaSession.stopLocalRecording(ch)
        } catch (e) {
          // 忽略单个通道停止异常
        }
      }
      // 停止所有通道的远程渲染（对齐 Android stopAllRemoteViews）
      for (const ch of this.channelList) {
        try {
          this.mediaSession.stopRemoteView(ch)
        } catch (e) {
          // 忽略单个通道停止异常
        }
      }
      this.mediaSession.removeListener(this.sessionListener)
      this.mediaSession.stopSession()
      this.mediaSession = null
      this.sessionEstablished = false
      this.isSessionPaused = false
      this.isSessionStartRequested = false
      this.isRecording = false
      this.recordingDurationMs = 0
      this.recordingChannels = []
      this.recordingFilePaths = []
      console.info('🛑 媒体会话已销毁')
    }
  }

  /** 为所有通道开始拉流（对齐 Android startRemoteViews） */
  private startRemoteViews(): void {
    for (const ch of this.channelList) {
      this.startRemoteViewFor(ch)
    }
  }

  /** 停止所有通道拉流（对齐 Android stopAllRemoteViews） */
  private stopRemoteViews(): void {
    if (!this.mediaSession) {
      return
    }
    for (const ch of this.channelList) {
      try {
        this.mediaSession.stopRemoteView(ch)
      } catch (e) {
        console.warn(`⚠️ 停止拉流异常: channelId=${ch}, ${e}`)
      }
    }
  }

  /** 拉流失败重试（对齐 Android retryStream） */
  private retryStream(): void {
    if (!this.mediaSession) {
      return
    }
    this.streamFailed = false
    this.loadingOverlay = true
    this.isSessionStartRequested = false
    // 会话已在 onError 中停止；按首次建连相同顺序重新注册通道后启动。
    this.startSessionWhenViewsReady()
  }

  /**
   * 将单个通道的截图 PixelMap 打包为 JPEG 写入沙箱，收集路径
   * 所有通道截图收集完毕后通过 emitter 切回 UI 主线程批量保存相册
   */
  async packSnapshot(channelId: number, pixelMap: image.PixelMap) {
    const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 95 }
    const imagePacker = image.createImagePacker()
    let tmpPath: string | null = null
    try {
      const arrayBuffer: ArrayBuffer = await imagePacker.packing(pixelMap, packOpts)
      const context = getContext(this)
      tmpPath = `${context.tempDir}/snapshot_ch${channelId}_${Date.now()}.jpg`
      const tmpFile = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      fs.writeSync(tmpFile.fd, arrayBuffer)
      fs.closeSync(tmpFile)
    } catch (err) {
      console.error(`❌ 截图打包失败: ${JSON.stringify(err)}`)
      tmpPath = null
    } finally {
      imagePacker.release()
      pixelMap.release()
    }
    this.onSnapshotCollected(channelId, tmpPath)
  }

  /** 收集单个通道截图结果，全部收集完毕后触发批量保存 */
  onSnapshotCollected(channelId: number, tmpPath: string | null) {
    if (tmpPath) {
      this.snapshotPendingPaths.push(tmpPath)
    }
    this.snapshotCompletedCount++
    if (this.snapshotCompletedCount >= this.snapshotExpectedCount) {
      this.flushSnapshots()
    }
  }

  /** 所有通道截图收集完毕，通过 emitter 切到 UI 主线程批量保存 */
  flushSnapshots() {
    const paths = this.snapshotPendingPaths
    this.snapshotPendingPaths = []
    this.snapshotExpectedCount = 0
    this.snapshotCompletedCount = 0
    if (paths.length === 0) {
      this.showToast('截图失败')
      return
    }
    emitter.emit(
      { eventId: this.SNAPSHOT_EVENT_ID },
      { data: { tmpPaths: paths } }
    )
  }

  /**
   * 在 UI 主线程（emitter 回调）中批量调用 showAssetsCreationDialog
   * 一次弹框保存所有通道截图，对齐官方示例：srcFileUris → showAssetsCreationDialog → copyFileSync
   */
  async saveSnapshotsToAlbum(tmpPaths: string[]) {
    try {
      const srcFileUris = tmpPaths.map(p => fileUri.getUriFromPath(p))
      const photoCreationConfigs: photoAccessHelper.PhotoCreationConfig[] = []
      for (let i = 0; i < tmpPaths.length; i++) {
        const config: photoAccessHelper.PhotoCreationConfig = {
          fileNameExtension: 'jpg',
          photoType: photoAccessHelper.PhotoType.IMAGE,
        }
        photoCreationConfigs.push(config)
      }
      const context = getContext(this)
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      // UI 主线程中调用，弹出系统保存确认弹框（支持多文件）
      const desFileUris = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs)
      console.info(`showAssetsCreationDialog success, data is ${desFileUris}`)
      if (desFileUris.length > 0) {
        for (let i = 0; i < srcFileUris.length && i < desFileUris.length; i++) {
          const srcFile = fs.openSync(srcFileUris[i], fs.OpenMode.READ_ONLY)
          const desFile = fs.openSync(desFileUris[i], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
          fs.copyFileSync(srcFile.fd, desFile.fd)
          fs.closeSync(srcFile)
          fs.closeSync(desFile)
        }
        console.info('📸 截图已保存到相册')
        this.showToast(desFileUris.length > 1 ? `已保存${desFileUris.length}张截图到相册` : '截图已保存到相册')
      } else {
        console.warn('⚠️ 用户取消了截图保存')
        this.showToast('已取消保存')
      }
    } catch (err) {
      console.error(`❌ 截图保存失败: ${JSON.stringify(err)}`)
      this.showToast('截图保存失败')
    } finally {
      for (const p of tmpPaths) {
        fs.unlink(p).catch(() => {})
      }
    }
  }

  /**
   * 批量将录像文件保存到相册
   * 对应 iOS: DeviceDetailViewModel.saveVideoToAlbum(filePath:)，扩展为多通道
   */
  async saveRecordingsToAlbum(filePaths: string[]) {
    try {
      const srcFileUris = filePaths.map(p => fileUri.getUriFromPath(p))
      const photoCreationConfigs: photoAccessHelper.PhotoCreationConfig[] = []
      for (let i = 0; i < filePaths.length; i++) {
        const config: photoAccessHelper.PhotoCreationConfig = {
          fileNameExtension: 'mp4',
          photoType: photoAccessHelper.PhotoType.VIDEO,
        }
        photoCreationConfigs.push(config)
      }
      const context = getContext(this)
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      // UI 主线程中调用，弹出系统保存确认弹框（支持多文件）
      const desFileUris = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs)
      console.info(`showAssetsCreationDialog success, data is ${desFileUris}`)
      if (desFileUris.length > 0) {
        for (let i = 0; i < srcFileUris.length && i < desFileUris.length; i++) {
          const srcFile = fs.openSync(srcFileUris[i], fs.OpenMode.READ_ONLY)
          const desFile = fs.openSync(desFileUris[i], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
          fs.copyFileSync(srcFile.fd, desFile.fd)
          fs.closeSync(srcFile)
          fs.closeSync(desFile)
        }
        console.info('🎬 录像已保存到相册')
        this.showToast(desFileUris.length > 1 ? `已保存${desFileUris.length}个录像到相册` : '录像已保存到相册')
      } else {
        console.warn('⚠️ 用户取消了录像保存')
        this.showToast('已取消保存')
      }
    } catch (err) {
      console.error(`❌ 录像保存失败: ${JSON.stringify(err)}`)
      this.showToast('录像保存失败')
    } finally {
      for (const p of filePaths) {
        fs.unlink(p).catch(() => {})
      }
    }
  }

  /**
   * 绑定指定通道的远程视频渲染
   * 需在对应通道的 XComponent 就绪（onLoad）且 mediaSession 存在后调用
   */
  startRemoteViewFor(channelId: number) {
    const xid = this.xcomponentId(channelId)
    if (!this.mediaSession || !this.channelReady[xid]) {
      return
    }
    const streamType = this.isHighQuality ? TXIoTStreamType.HD : TXIoTStreamType.SD
    // 对应 Android：会话启动前先注册全部已就绪通道，再由 startSession 统一请求房间信息。
    this.mediaSession.startRemoteView(channelId, streamType, xid)
    console.info(`📺 startRemoteView 已调用：channelId=${channelId}, xcomponentId=${xid}, streamType=${streamType}, muted=${this.isMuted}`)
  }

  // ==================== 横竖屏切换 ====================

  /**
   * 切换全屏横屏/竖屏
   * 对应 iOS: DeviceDetailViewModel.toggleFullscreen()
   */
  toggleFullscreen() {
    this.isFullscreen = !this.isFullscreen
    this.setWindowOrientation(this.isFullscreen)
  }

  /**
   * 设置窗口方向
   * @param landscape true=横屏，false=竖屏
   */
  private setWindowOrientation(landscape: boolean) {
    try {
      const context = getContext(this) as common.UIAbilityContext
      window.getLastWindow(context, (err, win) => {
        if (err && err.code) {
          console.error(`❌ 获取窗口失败: ${JSON.stringify(err)}`)
          return
        }
        const targetOrientation = landscape
          ? window.Orientation.LANDSCAPE
          : window.Orientation.PORTRAIT
        win.setPreferredOrientation(targetOrientation, (err2) => {
          if (err2 && err2.code) {
            console.error(`❌ 设置屏幕方向失败: ${JSON.stringify(err2)}`)
          } else {
            console.info(`✅ 屏幕方向切换为: ${landscape ? '横屏' : '竖屏'}`)
          }
        })
      })
    } catch (err) {
      console.error(`❌ setWindowOrientation 异常: ${JSON.stringify(err)}`)
    }
  }

  /**
   * 设置屏幕常亮（拉流时防止息屏）
   * @param enable true=保持常亮，false=允许息屏
   */
  private setKeepScreenOn(enable: boolean) {
    try {
      const context = getContext(this) as common.UIAbilityContext
      window.getLastWindow(context, (err, win) => {
        if (err && err.code) {
          console.error(`❌ 获取窗口失败(setKeepScreenOn): ${JSON.stringify(err)}`)
          return
        }
        win.setWindowKeepScreenOn(enable, (err2) => {
          if (err2 && err2.code) {
            console.error(`❌ 设置屏幕常亮失败(${enable}): ${JSON.stringify(err2)}`)
          } else {
            console.info(`✅ 屏幕常亮设置成功: ${enable}`)
          }
        })
      })
    } catch (err) {
      console.error(`❌ setKeepScreenOn 异常: ${JSON.stringify(err)}`)
    }
  }

  // ==================== 云台控制 ====================

  handlePTZ(direction: string) {
    const names: Record<string, string> = {
      'up': '上',
      'down': '下',
      'left': '左',
      'right': '右',
      'home': '复位'
    }
    this.showToast(`云台${names[direction]}控制中...`)
    // 发送云台指令（对应 iOS: viewModel.sendPTZCommand(channelId:, command:)）
    this.sendPTZCommand(direction)
  }

  /**
   * 发送云台控制指令
   * 对应 iOS: DeviceDetailView.sendPTZCommand(_:) + TXIoTMediaSession.sendPTZCommand
   */
  sendPTZCommand(direction: string) {
    if (!this.mediaSession) {
      console.warn('⚠️ 媒体会话未建立，无法发送云台指令')
      return
    }
    let command: TXIoTPTZCommand
    switch (direction) {
      case 'up':
        command = TXIoTPTZCommand.UP;
        break
      case 'down':
        command = TXIoTPTZCommand.DOWN;
        break
      case 'left':
        command = TXIoTPTZCommand.LEFT;
        break
      case 'right':
        command = TXIoTPTZCommand.RIGHT;
        break
      case 'home':
        command = TXIoTPTZCommand.STOP;
        break
      default:
        command = TXIoTPTZCommand.STOP;  break
    }
    // 对当前活跃通道下发云台指令
    this.mediaSession.sendPTZCommand(this.activeChannelId, command, 5)
    console.info(`🕹️ 云台指令发送: direction=${direction}, command=${command}, channelId=${this.activeChannelId}`)
  }

  // ==================== 对讲功能 ====================

  toggleTalk() {
    if (this.isTalking) {
      this.stopTalking()
    } else {
      this.startTalking()
    }
  }

  /**
   * 开始对讲（仅音频，对齐 Android startLocalAudio）
   */
  startTalking() {
    if (!this.mediaSession) {
      this.showToast('媒体会话未建立')
      return
    }
    this.isTalking = true
    // 启动本地音频上行（对齐 Android mediaSession.startLocalAudio）
    this.mediaSession.startLocalAudio()
    console.info('🎤 开始对讲')
    this.showToast('对讲已开启')
  }

  /**
   * 停止对讲（仅音频，对齐 Android stopLocalAudio）
   */
  stopTalking() {
    if (!this.mediaSession) {
      return
    }
    this.isTalking = false
    // 停止本地音频上行（对齐 Android mediaSession.stopLocalAudio）
    this.mediaSession.stopLocalAudio()
    console.info('🔇 停止对讲')
    this.showToast('对讲已关闭')
  }

  // ==================== 截图与录像 ====================

  formatRecordTime(): string {
    const totalSec = Math.floor(this.recordingDurationMs / 1000)
    const min = String(Math.floor(totalSec / 60)).padStart(2, '0')
    const sec = String(totalSec % 60).padStart(2, '0')
    return `● REC ${min}:${sec}`
  }

  takeSnapshot() {
    if (!this.mediaSession) {
      this.showToast('媒体会话未建立')
      return
    }
    // 初始化批量截图收集，对所有通道发起截图请求
    this.snapshotExpectedCount = this.channelList.length
    this.snapshotCompletedCount = 0
    this.snapshotPendingPaths = []
    for (const ch of this.channelList) {
      this.mediaSession.takeSnapshot(ch)
    }
    console.info(`📸 发起截图请求: ${this.channelList.length} 个通道`)
  }

  toggleRecording() {
    if (!this.mediaSession) {
      this.showToast('媒体会话未建立')
      return
    }
    if (this.isRecording) {
      // 停止所有正在录像的通道
      const activeChannels = this.recordingChannels.slice()
      for (const ch of activeChannels) {
        this.mediaSession.stopLocalRecording(ch)
        console.info(`🛑 停止录像, channelId=${ch}`)
      }
    } else {
      // 对所有通道开始录像
      this.recordingFilePaths = []
      const context = getContext(this)
      for (const ch of this.channelList) {
        const params = new TXIoTLocalRecordingParams()
        params.filePath = `${context.tempDir}/record_ch${ch}_${Date.now()}.mp4`
        this.mediaSession.startLocalRecording(ch, params)
        console.info(`🎬 开始录像, channelId=${ch}, path=${params.filePath}`)
      }
    }
  }

  // ==================== 音频控制 ====================

  toggleSound() {
    this.isMuted = !this.isMuted
    // 对齐 Android: muteAllRemoteAudio(isMuted) —— 所有通道
    this.applyRemoteAudioMuteState(this.isMuted)
    this.showToast(this.isMuted ? '已静音' : '已开声音')
  }

  /**
   * 切换画质（高清/标清）
   * 对齐 Android toggleQuality: isHighQuality 双态切换
   */
  toggleQuality() {
    this.isHighQuality = !this.isHighQuality
    const streamType = this.isHighQuality ? TXIoTStreamType.HD : TXIoTStreamType.SD
    // 对齐 Android: 对所有通道切换流类型
    if (this.mediaSession) {
      for (const ch of this.channelList) {
        this.mediaSession.switchRemoteStream(ch, streamType)
      }
    }
    this.showToast(this.isHighQuality ? '已切换为高清' : '已切换为标清')
  }

  // ==================== 设备指令 ====================

  /**
   * 发送设备指令
   * 对应 iOS: DeviceDetailViewModel.sendDeviceCommand(jsonData:)
   */
  sendDeviceCommand(jsonData: string) {
    if (!this.device) {
      return
    }
    const productId = this.device.productId || ''
    const deviceName = this.device.deviceName || this.device.id
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = productId
    deviceId.deviceName = deviceName

    dm.sendCommand(deviceId, jsonData, {
      onSuccess: (result: string) => {
        console.info(`✅ 设备指令发送成功，响应: ${result}`)
        this.showToast('指令发送成功')
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        console.error(`❌ 设备指令发送失败: ${errorMessage}`)
        this.showToast(errorMessage || '指令发送失败')
      }
    })
  }

  // ==================== 设备分享 ====================

  /**
   * 创建设备分享 Token，生成包含 productId/deviceName/token 的 JSON
   * 对应 iOS: DeviceDetailViewModel.createShareToken(completion:)
   */
  createShareToken() {
    if (!this.device) {
      return
    }
    const familyId = this.device.familyId || AppState.currentFamilyId
    const productId = this.device.productId || ''
    const deviceName = this.device.deviceName || this.device.id
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = productId
    deviceId.deviceName = deviceName

    dm.createDeviceSharingToken(familyId, deviceId, {
      onSuccess: (token: string) => {
        const payload: Record<string, string> = {
          'productId': productId,
          'deviceName': deviceName,
          'token': token
        }
        this.shareTokenJson = JSON.stringify(payload, null, 2)
        this.showShareTokenDialog = true
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '创建分享 Token 失败')
      }
    })
  }

  @Builder
  PTZPanel() {
    Column() {
      // 圆形云台控制盘
      Stack() {
        // 背景圆
        Circle()
          .width(280).height(280)
          .fill('#f0f0f0')
          .shadow({
            radius: 8,
            color: 'rgba(0,0,0,0.1)',
            offsetX: 0,
            offsetY: 2
          })

        // 上
        Button() {
          Image($r('app.media.ic_ptz_up'))
            .width(24).height(24)
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .borderRadius(22)
        .position({ x: 118, y: 20 })
        .onClick(() => this.handlePTZ('up'))

        // 下
        Button() {
          Image($r('app.media.ic_ptz_down'))
            .width(24).height(24)
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .borderRadius(22)
        .position({ x: 118, y: 216 })
        .onClick(() => this.handlePTZ('down'))

        // 左
        Button() {
          Image($r('app.media.ic_ptz_left'))
            .width(24).height(24)
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .borderRadius(22)
        .position({ x: 20, y: 118 })
        .onClick(() => this.handlePTZ('left'))

        // 右
        Button() {
          Image($r('app.media.ic_ptz_right'))
            .width(24).height(24)
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .borderRadius(22)
        .position({ x: 216, y: 118 })
        .onClick(() => this.handlePTZ('right'))

        // 中心复位（对齐 Android: sendCommandToDevice("{\"cmd\":\"center\"}")）
        Button() {
          Circle().width(16).height(16).fill('#999999')
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .borderRadius(22)
        .position({ x: 118, y: 118 })
        .onClick(() => {
          this.sendDeviceCommand('{"cmd":"center"}')
        })
      }
      .width(280).height(280)
      .margin({ top: 20, bottom: 30 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColor.BgCard)
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  CommandInputPanel() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .backgroundColor(AppColor.BgMask)
        .onClick(() => {
          this.showCommandInput = false
        })

      Column({ space: 12 }) {
        Text('发送设备指令')
          .attributeModifier(DialogTitleText)

        TextArea({ text: this.commandText })
          .width('100%')
          .height(200)
          .fontSize(13)
          .fontColor(AppColor.TextPrimary)
          .backgroundColor(AppColor.BgGray)
          .border({ width: 1, color: AppColor.DividerDashed, radius: 8 })
          .onChange(val => {
            this.commandText = val
          })

        Row({ space: 12 }) {
          Button('取消')
            .attributeModifier(CancelButton).layoutWeight(1)
            .onClick(() => {
              this.showCommandInput = false
            })
          Button('发送')
            .attributeModifier(PrimaryButton).layoutWeight(1)
            .onClick(() => {
              const trimmed = this.commandText.trim()
              if (trimmed) {
                this.sendDeviceCommand(trimmed)
              }
              this.showCommandInput = false
            })
        }
        .width('100%')
      }
      .width('90%')
      .padding(24)
      .backgroundColor(AppColor.BgCard)
      .borderRadius(12)
    }
    .width('100%').height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(100)
  }

  /**
   * 多通道网格视图（对齐 iOS: MultiChannelGridView）
   * - 1 路：铺满
   * - 2 路：无论横竖屏都使用左右布局（与 iOS 一致）
   * - 3/4 路：2x2 网格
   */
  @Builder
  ChannelGrid() {
    if (this.channelList.length <= 1) {
      this.ChannelCell(this.channelList[0] ?? 0)
    } else if (this.channelList.length === 2) {
      // 竖屏/横屏下统一采用左右布局，与 iOS 保持一致
      Row() {
        Column() {
          this.ChannelCell(this.channelList[0])
        }.layoutWeight(1).height('100%')

        Column() {
          this.ChannelCell(this.channelList[1])
        }.layoutWeight(1).height('100%')
      }
      .width('100%').height('100%')
    } else {
      // 3 / 4 路：2x2 网格
      Column() {
        Row() {
          Column() {
            this.ChannelCell(this.channelList[0])
          }.layoutWeight(1).height('100%')

          Column() {
            if (this.channelList.length > 1) {
              this.ChannelCell(this.channelList[1])
            } else {
              Column().width('100%').height('100%').backgroundColor('#000000')
            }
          }.layoutWeight(1).height('100%')
        }
        .layoutWeight(1).width('100%')

        Row() {
          Column() {
            if (this.channelList.length > 2) {
              this.ChannelCell(this.channelList[2])
            } else {
              Column().width('100%').height('100%').backgroundColor('#000000')
            }
          }.layoutWeight(1).height('100%')

          Column() {
            if (this.channelList.length > 3) {
              this.ChannelCell(this.channelList[3])
            } else {
              Column().width('100%').height('100%').backgroundColor('#000000')
            }
          }.layoutWeight(1).height('100%')
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    }
  }

  /**
   * 单个通道视图单元
   */
  @Builder
  ChannelCell(channelId: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({
        id: this.xcomponentId(channelId),
        type: XComponentType.SURFACE,
        libraryname: 'liteavsdk'
      })
        .width('100%').height('100%')
        .onLoad(() => {
          const xid = this.xcomponentId(channelId)
          console.info(`✅ XComponent 已就绪，xcomponentId=${xid}`)
          const newReady: Record<string, boolean> = {}
          Object.keys(this.channelReady).forEach(k => {
            newReady[k] = this.channelReady[k]
          })
          newReady[xid] = true
          this.channelReady = newReady
          if (this.isSessionStartRequested) {
            // 会话运行中发生组件重建时，仅重新绑定当前通道。
            this.startRemoteViewFor(channelId)
          } else {
            // 首次建连需等所有目标通道都注册完毕，避免 SDK 退回默认通道 0。
            this.startSessionWhenViewsReady()
          }
        })
        .onDestroy(() => {
          const xid = this.xcomponentId(channelId)
          console.info(`🗑️ XComponent 已销毁，xcomponentId=${xid}`)
          const newReady: Record<string, boolean> = {}
          Object.keys(this.channelReady).forEach(k => {
            newReady[k] = this.channelReady[k]
          })
          newReady[xid] = false
          this.channelReady = newReady
        })

      // 通道标签
      Text(`通道 ${channelId}`)
        .fontSize(11)
        .fontColor('#ffffff')
        .fontWeight(FontWeight.Normal)
        .padding({
          left: 6,
          right: 6,
          top: 2,
          bottom: 2
        })
        .backgroundColor('rgba(0,0,0,0.55)')
        .borderRadius(4)
        .margin({ left: 6, top: 6 })
    }
    .width('100%').height('100%')
    .backgroundColor('#000000')
    .onClick(() => {
      this.activeChannelId = channelId
    })
  }

  build() {
    Stack() {
      Column() {
        // ===== 顶部渐变导航栏（全屏时隐藏）=====
        if (!this.isFullscreen) {
          GradientNavBar({
            title: this.device?.name || '', onBack: () => {
              this.goBack()
            }
          }) {
            // 通道信息胶囊
            Text(this.channelList.length > 1 ? `多通道(${this.channelList.length})` : '单通道')
              .fontSize(12)
              .fontColor('#ffffff')
              .padding({
                left: 10,
                right: 10,
                top: 4,
                bottom: 4
              })
              .backgroundColor('rgba(255,255,255,0.2)')
              .borderRadius(12)
          }
        }

        // ===== 视频播放区域（对齐 Android videoContainer: 240dp）=====
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            this.ChannelGrid()
          }
          .width('100%').height('100%')
          .backgroundColor('#000000')

          // 加载遮罩（单通道时显示，对齐 Android loadingOverlay）
          if (this.loadingOverlay && this.channelList.length <= 1) {
            Stack() {
              Column({ space: 8 }) {
                LoadingProgress()
                  .width(32).height(32)
                  .color('#FFFFFF')
                Text('加载中...')
                  .fontSize(14).fontColor('#FFFFFF')
              }
            }
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.6)')
          }

          // 拉流失败遮罩（对齐 Android streamErrorView，点击重试）
          if (this.streamFailed) {
            Stack() {
              Text('拉流失败，点击重试')
                .fontSize(14).fontColor('#FFFFFF')
            }
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.6)')
            .onClick(() => this.retryStream())
          }

          // 录像时长显示（对齐 Android tvRecordDuration: "● REC %02d:%02d"）
          if (this.isRecording) {
            Text(this.formatRecordTime())
              .fontSize(12)
              .fontColor('#FF4444')
              .backgroundColor('rgba(0,0,0,0.6)')
              .padding({
                left: 8,
                right: 8,
                top: 3,
                bottom: 3
              })
              .borderRadius(3)
              .position({ x: 10, y: 10 })
          }

          // 右侧悬浮控制按钮（对齐 Android: sound/quality/fullscreen）
          Column({ space: 12 }) {
            Button() {
              if (this.isMuted) {
                Image($r('app.media.ic_sound_off'))
                  .width(24).height(24)
              } else {
                Image($r('app.media.ic_sound_on'))
                  .width(24).height(24)
              }
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => this.toggleSound())

            Button() {
              Text(this.isHighQuality ? '高清' : '标清')
                .fontSize(10).fontWeight(FontWeight.Normal).fontColor('#ffffff')
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => this.toggleQuality())

            Button() {
              if (this.isFullscreen) {
                Image($r('app.media.ic_fullscreen_exit'))
                  .width(24).height(24)
              } else {
                Image($r('app.media.ic_fullscreen'))
                  .width(24).height(24)
              }
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => this.toggleFullscreen())
          }
          .position({ x: '100%', y: 40 })
          .translate({ x: -52, y: 0 })
        }
        .width('100%')
        .height(this.isFullscreen ? '100%' : 240)
        .backgroundColor('#0D0D0D')
        .clip(true)

        // 横屏时仅渲染视频区，隐藏底部控制栏与操作按钮区
        if (!this.isFullscreen) {

          // ===== 底部控制按钮栏（对齐 Android linearLayout2: 3 按钮）=====
          Row() {
            // 对讲（对齐 Android btnTalk + tvTalkLabel）
            Column({ space: 8 }) {
              Button() {
                Image($r('app.media.ic_talk'))
                  .width(22).height(22)
                  .fillColor(this.isTalking ? AppColor.Danger : AppColor.Brand)
              }
              .width(46)
              .height(46)
              .backgroundColor(AppColor.BgInput)
              .borderRadius(AppRadius.Card)
              .onClick(() => this.toggleTalk())

              Text(this.isTalking ? '对讲中' : '对讲').fontSize(AppFontSize.Caption).fontColor(AppColor.TextPrimary)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Center)

            // 截图（对齐 Android btnSnapshot）
            Column({ space: 8 }) {
              Button() {
                Image($r('app.media.ic_snapshot'))
                  .width(22).height(22)
                  .fillColor(AppColor.Brand)
              }
              .width(46)
              .height(46)
              .backgroundColor(AppColor.BgInput)
              .borderRadius(AppRadius.Card)
              .onClick(() => this.takeSnapshot())

              Text('截图').fontSize(AppFontSize.Caption).fontColor(AppColor.TextPrimary)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Center)

            // 录像（对齐 Android btnRecord + tvRecordLabel）
            Column({ space: 8 }) {
              Button() {
                Image($r('app.media.ic_record'))
                  .width(22).height(22)
                  .fillColor(this.isRecording ? AppColor.Danger : AppColor.Brand)
              }
              .width(46)
              .height(46)
              .backgroundColor(AppColor.BgInput)
              .borderRadius(AppRadius.Card)
              .onClick(() => this.toggleRecording())

              Text(this.isRecording ? '录像中' : '录像').fontSize(AppFontSize.Caption).fontColor(AppColor.TextPrimary)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .padding({
            top: 16,
            bottom: 12,
            left: 16,
            right: 16
          })
          .backgroundColor('#FFFFFF')

          // ===== 云台控制面板（对齐 Android ptzPanel: weight=1 填充）=====
          Column() {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(220).height(220)
                .borderRadius(110)
                .backgroundColor('#F5F5F5')

              // 上
              Button() {
                Image($r('app.media.ic_ptz_up'))
                  .width(24).height(24)
              }
              .width(50)
              .height(50)
              .backgroundColor('#FFFFFF')
              .borderRadius(25)
              .shadow({ radius: 4, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 1 })
              .position({ x: 85, y: 10 })
              .onClick(() => this.handlePTZ('up'))

              // 下
              Button() {
                Image($r('app.media.ic_ptz_down'))
                  .width(24).height(24)
              }
              .width(50)
              .height(50)
              .backgroundColor('#FFFFFF')
              .borderRadius(25)
              .shadow({ radius: 4, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 1 })
              .position({ x: 85, y: 160 })
              .onClick(() => this.handlePTZ('down'))

              // 左
              Button() {
                Image($r('app.media.ic_ptz_left'))
                  .width(24).height(24)
              }
              .width(50)
              .height(50)
              .backgroundColor('#FFFFFF')
              .borderRadius(25)
              .shadow({ radius: 4, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 1 })
              .position({ x: 10, y: 85 })
              .onClick(() => this.handlePTZ('left'))

              // 右
              Button() {
                Image($r('app.media.ic_ptz_right'))
                  .width(24).height(24)
              }
              .width(50)
              .height(50)
              .backgroundColor('#FFFFFF')
              .borderRadius(25)
              .shadow({ radius: 4, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 1 })
              .position({ x: 160, y: 85 })
              .onClick(() => this.handlePTZ('right'))

              // 中心复位（对齐 Android: sendCommandToDevice("{\"cmd\":\"center\"}")）
              Button() {
                Column()
                  .width(40).height(40)
                  .borderRadius(20)
                  .backgroundColor('#006EFF')
              }
              .width(40)
              .height(40)
              .backgroundColor(Color.Transparent)
              .position({ x: 90, y: 90 })
              .onClick(() => {
                this.sendDeviceCommand('{"cmd":"center"}')
              })
            }
            .width(220).height(220)
            .margin({ top: 16, bottom: 20 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#FFFFFF')

          // ===== 分享按钮行（对齐 Android actionButtonsRow）=====
          Row({ space: 12 }) {
            Button() {
              Row({ space: 8 }) {
                Image($r('app.media.ic_share'))
                  .width(20).height(20)
                Text('创建分享').fontSize(14).fontColor('#006EFF').fontWeight(FontWeight.Normal)
              }
            }
            .layoutWeight(1)
            .height(48)
            .backgroundColor(Color.Transparent)
            .border({ width: 1.5, color: '#006EFF', radius: 14 })
            .onClick(() => this.createShareToken())
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 24 })
          .backgroundColor('#FFFFFF')

        } // end if (!this.isFullscreen)

        // 指令输入弹窗
        if (this.showCommandInput) {
          this.CommandInputPanel()
        }

        // 创建分享 Token 展示弹窗（对齐 iOS: CommonBottomSheet title "设备分享码", hint nil, confirmTitle "复制分享码", cancelTitle "关闭"）
        CommonBottomSheet({
          show: $showShareTokenDialog,
          title: '设备分享码',
          showCaption: false,
          confirmText: '复制分享码',
          cancelText: '关闭',
          onConfirm: () => {
            const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareTokenJson)
            const systemPasteboard = pasteboard.getSystemPasteboard()
            systemPasteboard.setDataSync(pasteboardData)
            this.showToast('已复制到剪贴板')
          },
          onCancel: () => {
            this.shareTokenJson = ''
          }
        }) {
          Column() {
            Text(this.shareTokenJson)
              .fontSize(12)
              .fontColor(AppColor.TextPrimary)
              .fontFamily('monospace')
              .width('100%')
              .padding({
                left: 14,
                right: 14,
                top: 14,
                bottom: 14
              })
              .backgroundColor('#F7F8FA')
              .borderRadius(12)
              .textAlign(TextAlign.Start)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }

      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0D0D0D')
  }
}
