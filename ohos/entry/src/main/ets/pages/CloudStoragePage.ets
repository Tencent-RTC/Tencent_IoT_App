import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import window from '@ohos.window'
import i18n from '@ohos.i18n'
import display from '@ohos.display'
import common from '@ohos.app.ability.common'
import { Context } from '@ohos.abilityAccessCtrl'
import {
  TXVodPlayer,
  ITXVodPlayCallback,
  TXVodConstants,
  TXVodPlayConfig,
  TXVodDef,
  getV2TXLivePremierShareInstance,
  TXIoTEvent,
  TXIoTVideoFile,
  TXIoTFamilyInfo,
  TXIoTDeviceInfo,
  TXIoTDeviceManager,
  TXIoTCloudStorage,
  TXIoTDeviceId,
  TXIoTErrorCode,
  TXIoTPageResult
} from '@tencentcloud/liteavsdk_iot'
import { AppState } from '../model/AppModel'
import { ContextMenuBuilder, ContextMenuItem as CMenuItem } from '../components/ContextMenu'

interface CloudStorageParams {
  productId: string
  deviceName: string
  aliasName: string
  online: boolean
  familyId: string
}

/**
 * 一次播放会话：可以是"事件"（多文件按墙上时间顺序播放）或"单文件"。
 * 内部以"墙上时间"为统一坐标系。
 */
class PlaybackSession {
  files: TXIoTVideoFile[]
  startWallMs: number
  endWallMs: number
  totalDurationMs: number
  currentIndex: number = 0
  initialIndex: number = 0
  private pendingSeekWallMs: number | null = null

  private constructor(files: TXIoTVideoFile[], startWallMs: number, endWallMs: number, totalDurationMs: number) {
    this.files = files
    this.startWallMs = startWallMs
    this.endWallMs = endWallMs
    this.totalDurationMs = totalDurationMs
  }

  currentFile(): TXIoTVideoFile | null {
    return this.currentIndex >= 0 && this.currentIndex < this.files.length ? this.files[this.currentIndex] : null
  }

  resetToStart(): void {
    this.currentIndex = this.initialIndex
    this.pendingSeekWallMs = null
  }

  markPendingSeekWallMs(wallMs: number): void {
    this.pendingSeekWallMs = wallMs
  }

  consumePendingSeekWallMs(): number | null {
    const v = this.pendingSeekWallMs
    this.pendingSeekWallMs = null
    return v
  }

  advanceToNextValidSegment(): boolean {
    let idx = this.currentIndex + 1
    while (idx < this.files.length) {
      if (this.files[idx].startTimeMs < this.endWallMs) {
        this.currentIndex = idx
        return true
      }
      idx++
    }
    return false
  }

  findFileIndexForWallMs(wallMs: number): number {
    if (this.files.length === 0) {
      return -1
    }
    for (let i = 0; i < this.files.length; i++) {
      const f = this.files[i]
      if (wallMs >= f.startTimeMs && wallMs < (f.startTimeMs + f.durationMs)) {
        return i
      }
    }
    const nextIdx = this.files.findIndex((f: TXIoTVideoFile) => f.startTimeMs >= wallMs)
    return nextIdx >= 0 ? nextIdx : this.files.length - 1
  }

  static forEvent(event: TXIoTEvent, files: TXIoTVideoFile[]): PlaybackSession {
    const start = event.eventTimeMs
    const duration = Math.max(event.durationMs, 0)
    let end: number
    if (duration > 0) {
      end = start + duration
    } else {
      const last = files[files.length - 1]
      end = last.startTimeMs + last.durationMs
    }
    const total = Math.max(end - start, 0)
    const session = new PlaybackSession(files, start, end, total)
    const idx = session.findFileIndexForWallMs(start)
    session.currentIndex = idx >= 0 ? idx : 0
    session.initialIndex = session.currentIndex
    return session
  }

  static forSingleFile(file: TXIoTVideoFile): PlaybackSession {
    const start = file.startTimeMs
    const duration = Math.max(file.durationMs, 0)
    return new PlaybackSession([file], start, start + duration, duration)
  }
}

class NearestVideoResult {
  file: TXIoTVideoFile
  playTimeMs: number

  constructor(file: TXIoTVideoFile, playTimeMs: number) {
    this.file = file
    this.playTimeMs = playTimeMs
  }
}

class CloudStorageEventPage {
  dataList: TXIoTEvent[]
  nextPageToken: string

  constructor(dataList: TXIoTEvent[], nextPageToken: string) {
    this.dataList = dataList
    this.nextPageToken = nextPageToken
  }
}

@Entry
@Component
struct CloudStoragePage {
  // 前往腾讯云点播播放器页面购买：https://cloud.tencent.com/document/product/881/74588
  // 如果不打算使用腾讯云点播播放器，可以将以下两个常量设置为空字符串
  private static readonly LICENSE_URL: string = 
  private static readonly LICENSE_KEY: string = 
  private static readonly CHANNEL_COUNT: number = 4
  private static readonly BASE_TIMELINE_HOURS_ON_SCREEN: number = 1.5
  private static readonly PLAYBACK_STOP_RETRY_MS: number = 100
  private static readonly PLAYBACK_STOP_MAX_RETRIES: number = 40
  private static readonly PLAY_PAUSE_AUTO_HIDE_DELAY_MS: number = 3000
  private static readonly FULLSCREEN_AUTO_HIDE_DELAY_MS: number = 5000

  @State productId: string = ''
  @State deviceName: string = ''
  @State aliasName: string = ''
  @State online: boolean = false
  private familyId: string = ''

  @State currentChannelId: number = 0

  @State selectedDate: string = ''
  @State dateList: string[] = []
  @State eventList: TXIoTEvent[] = []
  private allEventsForTimeline: TXIoTEvent[] = []

  @State listLoading: boolean = false
  @State isListEmpty: boolean = false
  @State videoLoading: boolean = false
  @State isFullscreen: boolean = false
  @State isMuted: boolean = true
  @State isPlaybackPaused: boolean = false
  @State showPlayPauseButton: boolean = false
  @State showFullscreenControls: boolean = false
  @State showReplayOverlay: boolean = false
  @State timelineCenterTimeText: string = ''

  @State showSnapshot: boolean = false
  @State snapshotLoading: boolean = false
  @State snapshotUrl: string = ''
  @State snapshotTitle: string = ''

  @State timelineHasVideo: boolean = false
  @State timelineCanvasWidthVp: number = 1
  private timelineFiles: TXIoTVideoFile[] = []
  private timelineViewportWidthVp: number = 0
  private timelineHourWidthVp: number = 0
  private timelineDensityPixels: number = 1
  private timelineScaledDensity: number = 1
  private readonly timelineHeightVp: number = 56
  private timelineSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private timelineCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.timelineSettings)
  private timelineScroller: Scroller = new Scroller()
  private playPauseHideTimer: number | null = null
  private fullscreenAutoHideTimer: number | null = null
  private isUserScrollingTimeline: boolean = false
  private isTimelinePositionedByUser: boolean = false
  private pinnedCenterTimeMs: number | null = null
  private timelineTouchStartX: number = 0
  private timelineTouchStartY: number = 0
  private timelineTouchMoved: boolean = false

  private vodPlayer: TXVodPlayer | null = null
  private videoSurfaceId: string = ''
  private currentPlayerWasUsed: boolean = false
  private isPlayerStarted: boolean = false
  private isWaitingForPlayBegin: boolean = false
  private isPlayerStopping: boolean = false
  private wasPausedByPageHide: boolean = false
  private currentSession: PlaybackSession | null = null
  private lastSession: PlaybackSession | null = null
  private pendingSession: PlaybackSession | null = null
  private pendingSeekWallMs: number | null = null
  private playbackStopRetryTimer: number | null = null
  private playbackStopRetryCount: number = 0
  private retiringPlayer: TXVodPlayer | null = null
  private retiringStopRetryTimer: number | null = null
  private retiringStopRetryCount: number = 0
  private currentFileDurationMs: number = 0
  private currentPlayWallMs: number | null = null
  private xcomponentController: XComponentController = new XComponentController()
  private timeZoneId: string = 'Asia/Shanghai'
  private pageActive: boolean = false
  private pageVisible: boolean = false
  private dayListRequestId: number = 0
  private eventListRequestId: number = 0
  private statusRequestId: number = 0
  private orientationRequestId: number = 0
  private previousLayoutFullScreen: boolean | null = null
  private previousStatusBarHidden: boolean = false
  private previousSystemBarProperties: window.SystemBarProperties | null = null
  private previousOrientation: window.Orientation | null = null
  // 云存实例：本页只服务单个设备，按页缓存一次即可（直接使用 SDK，不再经过中间层）
  private cloudStorage: TXIoTCloudStorage | null = null

  @StorageProp('statusBarHeight') statusBarHeight: number = 48

  private readonly eventTypeNames: Record<string, string> = {
    '1': '门铃呼叫事件',
    '2': '运动检测事件',
    '3': '人形检测事件',
    '4': '区域入侵事件',
    '5': '区域徘徊事件',
    '6': '异常声音事件',
    '100': '人脸识别抓拍',
    '101': '开门状态抓拍'
  }

  // ─── 生命周期 ───────────────────────────────────────────────

  aboutToAppear(): void {
    this.pageActive = true
    this.pageVisible = true
    const params = router.getParams() as CloudStorageParams
    if (params) {
      this.productId = params.productId || ''
      this.deviceName = params.deviceName || ''
      this.aliasName = params.aliasName || this.deviceName
      this.online = params.online === true
      this.familyId = params.familyId || ''
    }
    this.setupImmersiveStatusBar()
    if (!this.productId || !this.deviceName) {
      this.showToast('设备信息无效')
      router.back()
      return
    }
    this.setupLicense()
    this.resolveTimeZone()
    this.initTimelineScale()
    this.setupVideoView()
    this.queryDeviceStatus()
    this.loadDayList()
  }

  aboutToDisappear(): void {
    this.pageVisible = false
    this.dayListRequestId++
    this.eventListRequestId++
    this.statusRequestId++
    this.orientationRequestId++
    this.cancelPlayPauseHideTimer()
    this.cancelFullscreenAutoHide()
    this.cancelPendingPlayback()
    this.currentSession = null
    this.lastSession = null
    const player = this.vodPlayer
    this.vodPlayer = null
    if (player) {
      this.retainPlayerForFinalStop(player)
    }
    this.isPlayerStarted = false
    this.isWaitingForPlayBegin = false
    this.isPlayerStopping = false
    this.videoSurfaceId = ''
    this.setKeepScreenOn(false)
    this.restoreWindowAppearance()
    this.pageActive = false
  }

  onPageHide(): void {
    this.pageVisible = false
    if (!this.isPlayerStarted || this.isPlaybackPaused) {
      return
    }
    this.runSafely(() => {
      this.vodPlayer?.pause()
      this.wasPausedByPageHide = true
      this.setKeepScreenOn(false)
    })
  }

  onPageShow(): void {
    this.pageVisible = true
    this.runSafely(() => {
      if (this.wasPausedByPageHide && this.isPlayerStarted && !this.isPlaybackPaused) {
        this.wasPausedByPageHide = false
        this.vodPlayer?.resume()
        this.setKeepScreenOn(true)
      }
    })
  }

  onBackPress(): boolean {
    if (this.isFullscreen) {
      this.exitFullscreen()
      return true
    }
    return false
  }

  private setupImmersiveStatusBar(): void {
    const context = getContext(this) as Context
    window.getLastWindow(context, (err, win) => {
      if (err.code || !this.pageActive) {
        return
      }
      this.runSafely(() => {
        const properties = win.getWindowProperties()
        this.previousLayoutFullScreen = properties.isLayoutFullScreen
        this.previousStatusBarHidden = properties.isFullScreen
        this.previousSystemBarProperties = win.getWindowSystemBarProperties()
        this.previousOrientation = win.getPreferredOrientation()
      })
      win.setWindowSystemBarEnable(['status', 'navigation'])
      win.setWindowSystemBarProperties({ statusBarColor: '#00000000', statusBarContentColor: '#FFFFFF' })
      win.setWindowLayoutFullScreen(true)
      const avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      AppStorage.setOrCreate<number>('statusBarHeight', avoidArea.topRect.height)
    })
  }

  private restoreWindowAppearance(): void {
    const context = getContext(this) as Context
    window.getLastWindow(context, (err, win) => {
      if (err.code) {
        return
      }
      this.runSafely(() => {
        win.setWindowSystemBarEnable(this.previousStatusBarHidden ? ['navigation'] : ['status', 'navigation'])
        if (this.previousSystemBarProperties) {
          win.setWindowSystemBarProperties(this.previousSystemBarProperties)
        }
        if (this.previousLayoutFullScreen !== null) {
          win.setWindowLayoutFullScreen(this.previousLayoutFullScreen)
        }
        win.setPreferredOrientation(this.previousOrientation ?? window.Orientation.PORTRAIT)
      })
    })
  }

  private setupLicense(): void {
    this.runSafely(() => {
      const context = getContext(this) as Context
      getV2TXLivePremierShareInstance(context).setLicence(CloudStoragePage.LICENSE_URL, CloudStoragePage.LICENSE_KEY)
    })
  }

  private resolveTimeZone(): void {
    this.runSafely(() => {
      const id = i18n.getTimeZone().getID()
      if (id) {
        this.timeZoneId = id
      }
    })
  }

  private initTimelineScale(): void {
    this.runSafely(() => {
      const defaultDisplay = display.getDefaultDisplaySync()
      const density = defaultDisplay.densityPixels > 0 ? defaultDisplay.densityPixels : 1
      this.timelineDensityPixels = density
      this.timelineScaledDensity = defaultDisplay.scaledDensity > 0 ? defaultDisplay.scaledDensity : density
      const widthVp = defaultDisplay.width / density
      if (widthVp > 0) {
        this.timelineViewportWidthVp = widthVp
        this.timelineHourWidthVp = widthVp / CloudStoragePage.BASE_TIMELINE_HOURS_ON_SCREEN
        this.timelineCanvasWidthVp = this.timelineHourWidthVp * 24 + widthVp
      }
    })
  }

  // ─── 播放器 ─────────────────────────────────────────────────

  private setupVideoView(): void {
    const player = new TXVodPlayer(getContext(this) as Context)
    const config = new TXVodPlayConfig()
    config.enableAccurateSeek = true
    config.progressInterval = 500
    player.setConfig(config)
    player.setAutoPlay(true)
    player.setLoop(false)
    this.runSafely(() => player.setMute(this.isMuted))
    player.setVodPlayCallback({
      onPlayEvent: (callbackPlayer: TXVodPlayer, event: number,
        eventData?: Map<string, TXVodDef.ParamType>) => {
        if (callbackPlayer !== this.vodPlayer) {
          return
        }
        this.handlePlayEvent(event, eventData)
      },
      onNetStatus: (callbackPlayer: TXVodPlayer, statusData: Map<string, TXVodDef.ParamType>) => {
      }
    } as ITXVodPlayCallback)
    this.vodPlayer = player
    this.currentPlayerWasUsed = false
    if (this.videoSurfaceId.length > 0) {
      player.setVideoRenderTarget(this.videoSurfaceId)
    }
  }

  private numOf(data: Map<string, TXVodDef.ParamType> | undefined, key: string): number {
    if (!data) {
      return 0
    }
    const v = data.get(key)
    return typeof v === 'number' ? v : 0
  }

  private strOf(data: Map<string, TXVodDef.ParamType> | undefined, key: string): string {
    if (!data) {
      return ''
    }
    const v = data.get(key)
    return typeof v === 'string' ? v : ''
  }

  private handlePlayEvent(event: number, data?: Map<string, TXVodDef.ParamType>): void {
    if (!this.pageActive) {
      return
    }
    if (this.pendingSession) {
      if (event === TXVodConstants.VOD_PLAY_EVT_PLAY_END) {
        this.cancelPlaybackStopRetry()
        this.vodPlayer = null
        this.isPlayerStarted = false
        this.isWaitingForPlayBegin = false
        this.isPlayerStopping = false
        this.setupVideoView()
        this.startPendingSession()
        return
      }
      this.tryStopPlayerForPendingSession()
      return
    }
    if (!this.pageVisible && (event === TXVodConstants.VOD_PLAY_EVT_PLAY_BEGIN ||
      event === TXVodConstants.VOD_PLAY_EVT_RCV_FIRST_I_FRAME ||
      event === TXVodConstants.VOD_PLAY_EVT_PLAY_PROGRESS ||
      event === TXVodConstants.VOD_PLAY_EVT_VOD_LOADING_END)) {
      this.wasPausedByPageHide = true
      this.runSafely(() => this.vodPlayer?.pause())
      this.setKeepScreenOn(false)
      return
    }
    switch (event) {
      case TXVodConstants.VOD_PLAY_EVT_VOD_PLAY_PREPARED:
        break
      case TXVodConstants.VOD_PLAY_EVT_RCV_FIRST_I_FRAME:
        this.isWaitingForPlayBegin = false
        this.videoLoading = false
        break
      case TXVodConstants.VOD_PLAY_EVT_PLAY_BEGIN:
        this.isWaitingForPlayBegin = false
        this.videoLoading = false
        this.isPlaybackPaused = false
        this.setKeepScreenOn(true)
        this.showPlayPauseButtonWithAutoHide()
        break
      case TXVodConstants.VOD_PLAY_EVT_PLAY_LOADING:
        if (this.isPlayerStarted) {
          this.videoLoading = true
        }
        break
      case TXVodConstants.VOD_PLAY_EVT_VOD_LOADING_END:
        if (!this.isWaitingForPlayBegin) {
          this.videoLoading = false
        }
        break
      case TXVodConstants.VOD_PLAY_EVT_PLAY_PROGRESS:
        if (!this.isWaitingForPlayBegin) {
          this.updatePlayProgress(data)
        }
        break
      case TXVodConstants.VOD_PLAY_EVT_PLAY_END:
        this.onSegmentPlayEnd()
        break
      default:
        if (event < 0) {
          this.handlePlayError(event, data)
        }
        break
    }
  }

  private onSegmentPlayEnd(): void {
    if (!this.isPlayerStarted || this.isWaitingForPlayBegin) {
      return
    }
    const session = this.currentSession
    // 自然播完时 native 播放器已经停止；直接进入干净实例重建流程，避免对已结束实例执行 stopPlay。
    this.isPlayerStarted = false
    this.isWaitingForPlayBegin = false
    if (!session) {
      this.finishPlaybackSession()
      return
    }
    if (session.advanceToNextValidSegment()) {
      this.startSession(session, null)
      return
    }
    this.finishPlaybackSession()
  }

  private onSessionDurationReached(): void {
    this.finishPlaybackSession()
  }

  private finishPlaybackSession(): void {
    this.stopCurrentPlayback()
    this.videoLoading = false
    this.showReplayOverlayIfNeeded()
    this.currentSession = null
    this.currentFileDurationMs = 0
  }

  private showReplayOverlayIfNeeded(): void {
    if (this.lastSession == null) {
      return
    }
    this.cancelPlayPauseHideTimer()
    this.showPlayPauseButton = false
    this.showReplayOverlay = true
  }

  private replayLastSession(): void {
    const session = this.lastSession
    if (!session) {
      return
    }
    session.resetToStart()
    this.startSession(session)
  }

  private handlePlayError(event: number, data?: Map<string, TXVodDef.ParamType>): void {
    if (!this.isPlayerStarted) {
      return
    }
    const msg = this.strOf(data, TXVodConstants.EVT_DESCRIPTION)
    console.error(`[CloudStorage] 视频播放错误 event=${event} msg=${msg}`)
    this.videoLoading = false
    this.cancelPlayPauseHideTimer()
    this.showPlayPauseButton = false
    this.showReplayOverlay = false
    this.isPlaybackPaused = false
    this.isWaitingForPlayBegin = false
    this.setKeepScreenOn(false)
    const player = this.vodPlayer
    const stopped = !player || this.stopPlayerNow(player) === 0
    this.isPlayerStarted = !stopped
    this.isPlayerStopping = !stopped
    if (!stopped) {
      this.playbackStopRetryCount = 0
      this.schedulePlaybackStopRetry()
    }
    this.showToast(msg.length > 0 ? `视频播放失败：${msg}` : '视频播放失败')
    this.currentSession = null
    this.currentFileDurationMs = 0
  }

  private updatePlayProgress(data?: Map<string, TXVodDef.ParamType>): void {
    if (!data) {
      return
    }
    const progressMs = this.numOf(data, TXVodConstants.EVT_PLAY_PROGRESS_MS)
    const durationMs = this.numOf(data, TXVodConstants.EVT_PLAY_DURATION_MS)
    if (durationMs > 0) {
      this.currentFileDurationMs = durationMs
    }
    const session = this.currentSession
    if (!session || session.totalDurationMs <= 0) {
      return
    }
    const currentFile = session.currentFile()
    if (!currentFile) {
      return
    }
    const wallMs = currentFile.startTimeMs + progressMs
    if (wallMs >= session.endWallMs) {
      this.onSessionDurationReached()
      return
    }
    this.currentPlayWallMs = wallMs
    if (!this.isUserScrollingTimeline) {
      const timelineWallMs = this.clampTimeToSelectedDay(wallMs)
      this.pinnedCenterTimeMs = null
      this.timelineCenterTimeText = this.timeOfDay(timelineWallMs)
      this.centerTimelineAtTime(timelineWallMs)
    }
  }

  // ─── 播放/暂停 ───────────────────────────────────────────────

  private togglePlayPause(): void {
    const player = this.vodPlayer
    if (!player || !this.isPlayerStarted) {
      return
    }
    if (this.isPlaybackPaused) {
      this.runSafely(() => player.resume())
      this.isPlaybackPaused = false
      this.setKeepScreenOn(true)
      this.schedulePlayPauseAutoHide()
    } else {
      this.runSafely(() => player.pause())
      this.isPlaybackPaused = true
      this.setKeepScreenOn(false)
      this.cancelPlayPauseHideTimer()
    }
  }

  private showPlayPauseButtonWithAutoHide(): void {
    if (!this.isPlayerStarted || this.currentSession == null) {
      return
    }
    this.showPlayPauseButton = true
    this.schedulePlayPauseAutoHide()
  }

  private schedulePlayPauseAutoHide(): void {
    this.cancelPlayPauseHideTimer()
    if (this.isFullscreen || this.isPlaybackPaused) {
      return
    }
    this.playPauseHideTimer = setTimeout(() => {
      this.playPauseHideTimer = null
      this.showPlayPauseButton = false
    }, CloudStoragePage.PLAY_PAUSE_AUTO_HIDE_DELAY_MS)
  }

  private cancelPlayPauseHideTimer(): void {
    if (this.playPauseHideTimer !== null) {
      clearTimeout(this.playPauseHideTimer)
      this.playPauseHideTimer = null
    }
  }

  private updatePlayPauseVisibility(visible: boolean): void {
    this.showPlayPauseButton = visible && this.isPlayerStarted && this.currentSession != null
  }

  private toggleMute(): void {
    this.isMuted = !this.isMuted
    this.runSafely(() => this.vodPlayer?.setMute(this.isMuted))
  }

  private setKeepScreenOn(enable: boolean): void {
    try {
      const context = getContext(this) as common.UIAbilityContext
      window.getLastWindow(context, (err, win) => {
        if (err && err.code) {
          return
        }
        win.setWindowKeepScreenOn(enable, () => {
        })
      })
    } catch (err) {
    }
  }

  // ─── 播放 ──────────────────────────────────────────────────

  private playEvent(event: TXIoTEvent): void {
    const eventEndMs = event.durationMs > 0 ? event.eventTimeMs + event.durationMs : Number.MAX_SAFE_INTEGER
    const files = (event.videoFiles || [])
      .filter((f: TXIoTVideoFile) => f.startTimeMs > 0 && f.durationMs > 0)
      .filter((f: TXIoTVideoFile) =>
        f.startTimeMs + f.durationMs > event.eventTimeMs && f.startTimeMs < eventEndMs)
      .sort((a: TXIoTVideoFile, b: TXIoTVideoFile) => a.startTimeMs - b.startTimeMs)
    if (files.length === 0) {
      this.showToast('当前记录暂无可播放的视频')
      return
    }
    this.startSession(PlaybackSession.forEvent(event, files))
  }

  private playVideoFile(videoFile: TXIoTVideoFile, seekWallMs: number | null = null): void {
    this.startSession(PlaybackSession.forSingleFile(videoFile), seekWallMs)
  }

  private startSession(session: PlaybackSession, seekWallMs: number | null = null): void {
    if (!this.vodPlayer) {
      this.showToast('播放器未初始化')
      return
    }
    this.isUserScrollingTimeline = false
    this.timelineTouchMoved = false
    this.isTimelinePositionedByUser = true
    this.showReplayOverlay = false
    this.hideSnapshotPreview()
    this.videoLoading = true
    this.lastSession = session
    this.pendingSession = session
    this.pendingSeekWallMs = seekWallMs
    if (!this.isPlayerStopping) {
      this.playbackStopRetryCount = 0
    }
    if (this.isPlayerStarted || this.isWaitingForPlayBegin || this.isPlayerStopping) {
      this.tryStopPlayerForPendingSession()
      return
    }
    if (this.currentPlayerWasUsed) {
      this.vodPlayer = null
      this.setupVideoView()
    }
    this.startPendingSession()
  }

  private startPendingSession(): void {
    const session = this.pendingSession
    if (!session) {
      return
    }
    const seekWallMs = this.pendingSeekWallMs
    this.pendingSession = null
    this.pendingSeekWallMs = null
    this.cancelPlaybackStopRetry()
    this.isPlayerStopping = false
    this.currentSession = session
    this.currentFileDurationMs = 0
    this.startCurrentSegment(session, seekWallMs)
  }

  private stopPlayerNow(player: TXVodPlayer): number {
    this.runSafely(() => player.setMute(true))
    this.runSafely(() => player.pause())
    try {
      return player.stopPlay(true)
    } catch (e) {
      console.error(`[CloudStorage] 停止视频异常: ${JSON.stringify(e)}`)
      return -1
    }
  }

  private retainPlayerForFinalStop(player: TXVodPlayer): void {
    this.cancelRetiringStopRetry()
    this.retiringPlayer = player
    this.retiringStopRetryCount = 0
    this.tryStopRetiringPlayer()
  }

  private tryStopRetiringPlayer(): void {
    const player = this.retiringPlayer
    if (!player) {
      return
    }
    if (this.stopPlayerNow(player) === 0) {
      this.retiringPlayer = null
      this.cancelRetiringStopRetry()
      return
    }
    if (this.retiringStopRetryCount >= CloudStoragePage.PLAYBACK_STOP_MAX_RETRIES) {
      console.error('[CloudStorage] 播放器退役停止超时')
      this.retiringPlayer = null
      this.cancelRetiringStopRetry()
      return
    }
    this.retiringStopRetryCount++
    this.retiringStopRetryTimer = setTimeout(() => {
      this.retiringStopRetryTimer = null
      this.tryStopRetiringPlayer()
    }, CloudStoragePage.PLAYBACK_STOP_RETRY_MS)
  }

  private cancelRetiringStopRetry(): void {
    if (this.retiringStopRetryTimer !== null) {
      clearTimeout(this.retiringStopRetryTimer)
      this.retiringStopRetryTimer = null
    }
  }

  private tryStopPlayerForPendingSession(): void {
    if (!this.pendingSession) {
      return
    }
    const player = this.vodPlayer
    if (!player) {
      this.setupVideoView()
      this.startPendingSession()
      return
    }
    const stopResult = this.stopPlayerNow(player)
    if (stopResult === 0) {
      this.cancelPlaybackStopRetry()
      this.vodPlayer = null
      this.isPlayerStarted = false
      this.isWaitingForPlayBegin = false
      this.isPlayerStopping = false
      this.setupVideoView()
      this.startPendingSession()
      return
    }
    this.isPlayerStopping = true
    this.schedulePlaybackStopRetry()
  }

  private tryStopPlayerWithoutPendingSession(): void {
    const player = this.vodPlayer
    if (!player) {
      this.isPlayerStopping = false
      return
    }
    if (this.stopPlayerNow(player) === 0) {
      this.cancelPlaybackStopRetry()
      this.isPlayerStarted = false
      this.isWaitingForPlayBegin = false
      this.isPlayerStopping = false
      return
    }
    this.isPlayerStopping = true
    this.schedulePlaybackStopRetry()
  }

  private schedulePlaybackStopRetry(): void {
    if (this.playbackStopRetryTimer !== null) {
      return
    }
    this.playbackStopRetryTimer = setTimeout(() => {
      this.playbackStopRetryTimer = null
      if (!this.pageActive || !this.isPlayerStopping) {
        return
      }
      this.playbackStopRetryCount++
      if (this.playbackStopRetryCount > CloudStoragePage.PLAYBACK_STOP_MAX_RETRIES) {
        const hadPendingSession = this.pendingSession !== null
        this.pendingSession = null
        this.pendingSeekWallMs = null
        this.isPlayerStopping = false
        this.videoLoading = false
        if (hadPendingSession) {
          this.showToast('视频切换失败，请重试')
        }
        return
      }
      if (this.pendingSession) {
        this.tryStopPlayerForPendingSession()
      } else {
        this.tryStopPlayerWithoutPendingSession()
      }
    }, CloudStoragePage.PLAYBACK_STOP_RETRY_MS)
  }

  private cancelPlaybackStopRetry(): void {
    if (this.playbackStopRetryTimer !== null) {
      clearTimeout(this.playbackStopRetryTimer)
      this.playbackStopRetryTimer = null
    }
  }

  private cancelPendingPlayback(): void {
    this.pendingSession = null
    this.pendingSeekWallMs = null
    this.playbackStopRetryCount = 0
    this.cancelPlaybackStopRetry()
  }

  private startCurrentSegment(session: PlaybackSession, seekWallMs: number | null): void {
    const player = this.vodPlayer
    if (!player) {
      this.onPlayStartFailed()
      return
    }
    const file = session.currentFile()
    if (!file) {
      this.finishPlaybackSession()
      return
    }
    this.videoLoading = true
    this.isWaitingForPlayBegin = true
    if (seekWallMs !== null) {
      session.markPendingSeekWallMs(seekWallMs)
    }
    const pendingSeek = session.consumePendingSeekWallMs()
    const targetWallMs = pendingSeek !== null ? pendingSeek : Math.max(file.startTimeMs, session.startWallMs)
    this.scrollTimelineToTime(targetWallMs)
    const offsetMs = Math.max(targetWallMs - file.startTimeMs, 0)
    this.runSafely(() => {
      player.setMute(this.isMuted)
      player.setStartTime(offsetMs / 1000)
    })
    if (!this.startPlayWithVideoFile(player, file)) {
      this.onPlayStartFailed()
      return
    }
    this.currentPlayerWasUsed = true
    this.isPlayerStarted = true
  }

  private onPlayStartFailed(): void {
    this.videoLoading = false
    this.cancelPlayPauseHideTimer()
    this.showPlayPauseButton = false
    this.showReplayOverlay = false
    this.isPlaybackPaused = false
    this.isWaitingForPlayBegin = false
    this.isPlayerStarted = false
    this.setKeepScreenOn(false)
    this.showToast('视频播放失败')
    this.currentSession = null
    this.currentFileDurationMs = 0
  }

  private stopCurrentPlayback(): void {
    const shouldStop = this.isPlayerStarted || this.isWaitingForPlayBegin || this.isPlayerStopping
    this.cancelPendingPlayback()
    this.cancelPlayPauseHideTimer()
    this.showPlayPauseButton = false
    this.isPlaybackPaused = false
    this.setKeepScreenOn(false)
    this.currentFileDurationMs = 0
    if (!this.vodPlayer || !shouldStop) {
      this.isPlayerStarted = false
      this.isWaitingForPlayBegin = false
      this.isPlayerStopping = false
      return
    }
    this.playbackStopRetryCount = 0
    this.tryStopPlayerWithoutPendingSession()
  }

  private startPlayWithVideoFile(player: TXVodPlayer, videoFile: TXIoTVideoFile): boolean {
    const appId = parseInt(videoFile.vodAppId) || 0
    const fileId = videoFile.vodFileId
    const sign = videoFile.vodPlaySign
    try {
      // 优先使用云存签名 URL：SDK 会同步记录 playUrl，快速切换时 stopPlay 可以可靠停止。
      // fileId 模式需要先异步查询播放信息，在该窗口内 stopPlay 可能返回失败。
      const url = videoFile.videoUrl
      if (url && url.length > 0 && url.toLowerCase().startsWith('https://')) {
        player.startVodPlay(TXVodDef.TXPlayInfoParams.createWithUrl(url))
        return true
      }
      if (appId > 0 && fileId && fileId.length > 0) {
        player.startVodPlay(TXVodDef.TXPlayInfoParams.createWithFileId(appId, fileId, sign))
        return true
      }
      this.showToast('当前记录暂无可播放的视频')
      return false
    } catch (e) {
      console.error(`[CloudStorage] 播放异常: ${JSON.stringify(e)}`)
      return false
    }
  }

  // ─── 抓图预览 ───────────────────────────────────────────────

  private viewSnapshot(event: TXIoTEvent): void {
    const url = event.thumbnailUrl
    if (!url || url.length === 0) {
      this.showToast('当前抓图暂无可查看的图片')
      return
    }
    this.stopCurrentPlayback()
    this.currentSession = null
    this.showReplayOverlay = false
    this.isUserScrollingTimeline = false
    this.isTimelinePositionedByUser = true
    this.scrollTimelineToTime(event.eventTimeMs)
    this.snapshotTitle = this.buildSnapshotTitle(event)
    this.snapshotUrl = url
    this.snapshotLoading = true
    this.showSnapshot = true
  }

  private hideSnapshotPreview(): void {
    this.showSnapshot = false
    this.snapshotLoading = false
    this.snapshotUrl = ''
    this.snapshotTitle = ''
  }

  private buildSnapshotTitle(event: TXIoTEvent): string {
    const typeName = this.snapshotEventTypeName(event.eventType)
    const time = this.timeOfDay(event.eventTimeMs)
    return typeName.length === 0 ? time : `${typeName} · ${time}`
  }

  private snapshotEventTypeName(eventType: string): string {
    if (eventType === '100') {
      return '人脸识别抓拍'
    }
    if (eventType === '101') {
      return '开门状态抓拍'
    }
    return ''
  }

  // ─── 通道 ──────────────────────────────────────────────────

  private channelText(): string {
    return this.currentChannelId === 0 ? '无通道' : `通道 ${this.currentChannelId}`
  }

  private onChannelSelected(channelId: number): void {
    if (channelId === this.currentChannelId || channelId < 0 || channelId >= CloudStoragePage.CHANNEL_COUNT) {
      return
    }
    this.currentChannelId = channelId
    this.resetForChannelSwitch()
    this.loadDayList()
  }

  private resetForChannelSwitch(): void {
    this.dayListRequestId++
    this.eventListRequestId++
    this.stopCurrentPlayback()
    this.videoLoading = false
    this.currentSession = null
    this.lastSession = null
    this.showReplayOverlay = false
    this.hideSnapshotPreview()
    this.showFullscreenControls = false
    this.cancelFullscreenAutoHide()
    this.isUserScrollingTimeline = false
    this.isTimelinePositionedByUser = false
    this.pinnedCenterTimeMs = null
    if (this.isFullscreen) {
      this.exitFullscreen()
    }
    this.selectedDate = ''
    this.dateList = []
    this.eventList = []
    this.allEventsForTimeline = []
    this.timelineFiles = []
    this.timelineHasVideo = false
    this.timelineCenterTimeText = ''
    this.currentPlayWallMs = null
    this.isListEmpty = false
    this.drawTimeline()
  }

  // ─── 数据加载 ───────────────────────────────────────────────

  /** 获取云存实例（懒加载，按当前设备缓存） */
  private getCloudStorage(): TXIoTCloudStorage | null {
    if (!this.cloudStorage) {
      if (!this.productId || !this.deviceName) {
        return null
      }
      const deviceId = new TXIoTDeviceId()
      deviceId.productId = this.productId
      deviceId.deviceName = this.deviceName
      this.cloudStorage = AppState.engine().getCloudStorage(deviceId)
    }
    return this.cloudStorage
  }

  private loadDayList(): void {
    const requestId = ++this.dayListRequestId
    const channelId = this.currentChannelId
    this.eventListRequestId++
    this.listLoading = true
    this.isListEmpty = false
    console.info(`[CloudStorage] loadDayList tz=${this.timeZoneId} channel=${channelId} ` +
      `device=${this.productId}/${this.deviceName}`)
    const storage = this.getCloudStorage()
    if (!storage) {
      if (!this.isDayRequestCurrent(requestId, channelId)) {
        return
      }
      this.listLoading = false
      this.showToast('云存初始化失败')
      this.renderDateList([])
      return
    }
    storage.getDayList(channelId, this.timeZoneId, {
      onSuccess: (days: string[]) => {
        if (!this.isDayRequestCurrent(requestId, channelId)) {
          return
        }
        this.listLoading = false
        console.info(`[CloudStorage] dayList 返回 ${days ? days.length : 0} 天: ${JSON.stringify(days || [])}`)
        this.renderDateList(days || [])
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        if (!this.isDayRequestCurrent(requestId, channelId)) {
          return
        }
        this.listLoading = false
        this.showToast(errorMessage.length > 0 ? `获取云存日期失败：${errorMessage}` : '获取云存日期失败')
        this.renderDateList([])
      }
    })
  }

  private isDayRequestCurrent(requestId: number, channelId: number): boolean {
    return this.pageActive && requestId === this.dayListRequestId && channelId === this.currentChannelId
  }

  private renderDateList(days: string[]): void {
    if (days.length === 0) {
      this.stopCurrentPlayback()
      this.currentSession = null
      this.lastSession = null
      this.showReplayOverlay = false
      this.hideSnapshotPreview()
      this.dateList = []
      this.selectedDate = ''
      this.eventList = []
      this.allEventsForTimeline = []
      this.isTimelinePositionedByUser = false
      this.pinnedCenterTimeMs = null
      this.currentPlayWallMs = null
      this.refreshTimeline([])
      this.isListEmpty = true
      return
    }
    const sorted = [...days].sort((a: string, b: string) => (a < b ? 1 : (a > b ? -1 : 0)))
    const target = this.selectedDate.length > 0 && sorted.indexOf(this.selectedDate) >= 0
      ? this.selectedDate
      : sorted[0]
    this.dateList = sorted
    this.isListEmpty = false
    this.selectDate(target, true)
  }

  private selectDate(date: string, forceReload: boolean = false): void {
    const dateChanged = this.selectedDate !== date
    if (!dateChanged && !forceReload && this.allEventsForTimeline.length > 0) {
      return
    }
    if (dateChanged) {
      this.stopCurrentPlayback()
      this.currentSession = null
      this.lastSession = null
      this.showReplayOverlay = false
      this.hideSnapshotPreview()
      this.currentPlayWallMs = null
    }
    this.selectedDate = date
    this.loadEventList(date)
  }

  private loadEventList(date: string): void {
    const requestId = ++this.eventListRequestId
    const channelId = this.currentChannelId
    this.listLoading = true
    this.isListEmpty = false
    this.eventList = []
    this.allEventsForTimeline = []
    this.isTimelinePositionedByUser = false
    this.pinnedCenterTimeMs = null
    this.refreshTimeline([])
    this.loadEventPage(date, '', requestId, channelId, new Set<string>())
  }

  private loadEventPage(date: string, pageToken: string, requestId: number, channelId: number,
    visitedTokens: Set<string>): void {
    if (!this.isEventRequestCurrent(date, requestId, channelId)) {
      return
    }
    const storage = this.getCloudStorage()
    if (!storage) {
      this.onEventPageError(date, requestId, channelId, '云存初始化失败')
      return
    }
    visitedTokens.add(pageToken)
    // console.info(`[CloudStorage] loadEventPage date=${date} channel=${channelId} tz=${this.timeZoneId} token=${pageToken}`)
    storage.getEventList(channelId, this.timeZoneId, date, pageToken, {
      onSuccess: (result: TXIoTPageResult<TXIoTEvent> | TXIoTEvent[]) => {
        console.info(JSON.stringify(result, null, 2))
        const page = this.normalizeEventPage(result)
        console.info(`[CloudStorage] eventPageSuccess date=${date} token=${pageToken} ` +
          `dataList=${page.dataList.length} nextToken=${page.nextPageToken}`)
        if (page.dataList.length > 0) {
          const first = page.dataList[0]
          // console.info(`[CloudStorage] firstEvent type=${String(first.eventType)} time=${first.eventTimeMs} ` +
          //   `duration=${first.durationMs} videoFiles=${(first.videoFiles || []).length}`)
        }
        this.onEventPageSuccess(date, requestId, channelId, page.dataList, page.nextPageToken, visitedTokens)
      },
      onError: (errorCode: TXIoTErrorCode, errorMessage: string) => {
        // console.error(`[CloudStorage] eventPageError date=${date} channel=${channelId} ` +
        //   `code=${errorCode} message=${errorMessage}`)
        this.onEventPageError(date, requestId, channelId, errorMessage || '')
      }
    })
  }

  private normalizeEventPage(result: TXIoTPageResult<TXIoTEvent> | TXIoTEvent[]): CloudStorageEventPage {
    if (Array.isArray(result)) {
      return new CloudStorageEventPage(result, '')
    }
    return new CloudStorageEventPage(result.dataList || [], result.nextPageToken || '')
  }

  private isEventRequestCurrent(date: string, requestId: number, channelId: number): boolean {
    return this.pageActive && requestId === this.eventListRequestId &&
      channelId === this.currentChannelId && date === this.selectedDate
  }

  private onEventPageSuccess(date: string, requestId: number, channelId: number, pageData: TXIoTEvent[],
    nextToken: string, visitedTokens: Set<string>): void {
    if (!this.isEventRequestCurrent(date, requestId, channelId)) {
      return
    }
    if (pageData.length > 0) {
      this.allEventsForTimeline = this.allEventsForTimeline.concat(pageData)
      const visibleEvents = pageData.filter((e: TXIoTEvent) => e.eventType && e.eventType.length > 0)
      if (visibleEvents.length > 0) {
        this.eventList = [...this.eventList, ...visibleEvents]
          .sort((a: TXIoTEvent, b: TXIoTEvent) => b.eventTimeMs - a.eventTimeMs)
      }
      this.refreshTimeline(this.allEventsForTimeline)
    }
    if (nextToken.length > 0 && pageData.length > 0 && !visitedTokens.has(nextToken)) {
      this.loadEventPage(date, nextToken, requestId, channelId, visitedTokens)
      return
    }
    this.eventList = [...this.eventList].sort((a: TXIoTEvent, b: TXIoTEvent) => b.eventTimeMs - a.eventTimeMs)
    this.listLoading = false
    this.isListEmpty = this.eventList.length === 0
    if (this.allEventsForTimeline.length === 0) {
      this.refreshTimeline([])
    }
    this.logAllEvents(date);
  }

  private logAllEvents(date: string) {
    console.info(`Date[${date}] pagination finished, total ${this.allEventsForTimeline.length} events fetched`);
    this.allEventsForTimeline.forEach((event, index) => {
      if (event.videoFiles && event.videoFiles.length > 0) {
        console.info(
            `Event[${index}] ` +
            `eventType=${event.eventType} ` +
            `eventTimeMs=${event.eventTimeMs} ` +
            `durationMs=${event.durationMs} ` +
            `videoFiles=${event.videoFiles.length} ` +
            `url=${event.videoFiles[0].videoUrl}`
        )
      }
    });
  }

  private onEventPageError(date: string, requestId: number, channelId: number, errorMessage: string): void {
    if (!this.isEventRequestCurrent(date, requestId, channelId)) {
      return
    }
    this.listLoading = false
    this.showToast(errorMessage.length > 0 ? `获取云存事件失败：${errorMessage}` : '获取云存事件失败')
    this.isListEmpty = this.eventList.length === 0
    if (this.allEventsForTimeline.length === 0) {
      this.refreshTimeline([])
    }
  }

  private refreshTimeline(events: TXIoTEvent[]): void {
    const videoFiles: TXIoTVideoFile[] = []
    for (const e of events) {
      for (const f of (e.videoFiles || [])) {
        if (f.startTimeMs > 0 && f.durationMs > 0) {
          videoFiles.push(f)
        }
      }
    }
    this.timelineFiles = videoFiles.sort((a: TXIoTVideoFile, b: TXIoTVideoFile) => a.startTimeMs - b.startTimeMs)
    this.timelineHasVideo = videoFiles.length > 0
    this.drawTimeline()
    if (videoFiles.length > 0 && !this.isUserScrollingTimeline && !this.isPlaybackTimeDriven() &&
      !this.isTimelinePositionedByUser) {
      this.scrollTimelineToTime(this.timelineFiles[0].startTimeMs)
    }
  }

  private queryDeviceStatus(): void {
    const requestId = ++this.statusRequestId
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      return
    }
    if (this.familyId.length > 0) {
      this.queryDeviceStatusInFamily(dm, this.familyId, '', requestId)
      return
    }
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      return
    }
    fm.getFamilyList({
      onSuccess: (familyList: TXIoTFamilyInfo[]) => {
        if (!this.pageActive || requestId !== this.statusRequestId) {
          return
        }
        for (const family of familyList) {
          this.queryDeviceStatusInFamily(dm, family.familyId, '', requestId)
        }
      },
      onError: (_errorCode: TXIoTErrorCode, _errorMessage: string) => {
      }
    })
  }

  private queryDeviceStatusInFamily(dm: TXIoTDeviceManager, familyId: string, pageToken: string,
    requestId: number): void {
    dm.getDeviceList(familyId, pageToken, {
      onSuccess: (result: TXIoTPageResult<TXIoTDeviceInfo>) => {
        if (!this.pageActive || requestId !== this.statusRequestId) {
          return
        }
        const devices = result.dataList || []
        const matched = devices.find((d: TXIoTDeviceInfo) =>
          d.deviceId?.productId === this.productId && d.deviceId?.deviceName === this.deviceName)
        if (matched && matched.status) {
          this.online = matched.status.isOnline
          return
        }
        const nextToken = result.nextPageToken || ''
        if (nextToken.length > 0 && nextToken !== pageToken && devices.length > 0) {
          this.queryDeviceStatusInFamily(dm, familyId, nextToken, requestId)
        }
      },
      onError: (_errorCode: TXIoTErrorCode, _errorMessage: string) => {
      }
    })
  }

  // ─── 时间线 ────────────────────────────────────────────────

  private dayStartMs(): number {
    if (!this.selectedDate) {
      return 0
    }
    const parts = this.selectedDate.split('-')
    if (parts.length < 3) {
      return 0
    }
    return new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]), 0, 0, 0, 0).getTime()
  }

  private timelineSidePadding(): number {
    return this.timelineViewportWidthVp / 2
  }

  private timeToX(timeMs: number): number {
    return this.timelineSidePadding() + ((timeMs - this.dayStartMs()) / 3600000) * this.timelineHourWidthVp
  }

  private xToTime(x: number): number {
    const dayStart = this.dayStartMs()
    const dayEnd = dayStart + 24 * 60 * 60 * 1000
    if (dayStart <= 0 || this.timelineHourWidthVp <= 0) {
      return dayStart
    }
    const timeMs = dayStart + ((x - this.timelineSidePadding()) / this.timelineHourWidthVp) * 3600000
    return Math.min(Math.max(timeMs, dayStart), dayEnd - 1000)
  }

  private timeAtCenter(scrollX: number): number {
    const dayEnd = this.dayStartMs() + 24 * 60 * 60 * 1000
    const t = this.xToTime(scrollX + this.timelineViewportWidthVp / 2)
    return t >= dayEnd ? dayEnd - 1000 : t
  }

  /**
   * 云存文件可能跨越日期边界。时间轴只呈现 selectedDate 当天的区间，
   * 因此用于游标显示和滚动定位的时间也必须限制在该区间内。
   */
  private clampTimeToSelectedDay(timeMs: number): number {
    const dayStart = this.dayStartMs()
    if (dayStart <= 0) {
      return timeMs
    }
    const dayEnd = dayStart + 24 * 60 * 60 * 1000
    return Math.min(Math.max(timeMs, dayStart), dayEnd - 1000)
  }

  private isPlaybackTimeDriven(): boolean {
    return !this.isUserScrollingTimeline && this.isPlayerStarted && this.currentSession != null
  }

  private videoFileAt(timeMs: number): TXIoTVideoFile | null {
    const hit = this.timelineFiles.find((f: TXIoTVideoFile) =>
      timeMs >= f.startTimeMs && timeMs < (f.startTimeMs + f.durationMs))
    return hit ?? null
  }

  private nearestVideoFileNear(timeMs: number, rangeMs: number = 10000): NearestVideoResult | null {
    let bestAfter: TXIoTVideoFile | null = null
    let bestAfterDiff = Number.MAX_VALUE
    let bestBefore: TXIoTVideoFile | null = null
    let bestBeforeDiff = Number.MAX_VALUE
    for (const f of this.timelineFiles) {
      const end = f.startTimeMs + f.durationMs
      if (timeMs >= f.startTimeMs && timeMs < end) {
        return new NearestVideoResult(f, timeMs)
      }
      if (f.startTimeMs >= timeMs) {
        const diff = f.startTimeMs - timeMs
        if (diff >= 0 && diff <= rangeMs && diff < bestAfterDiff) {
          bestAfterDiff = diff
          bestAfter = f
        }
      } else if (end <= timeMs) {
        const diff = timeMs - end
        if (diff >= 0 && diff <= rangeMs && diff < bestBeforeDiff) {
          bestBeforeDiff = diff
          bestBefore = f
        }
      }
    }
    if (bestAfter) {
      return new NearestVideoResult(bestAfter, bestAfter.startTimeMs)
    }
    if (bestBefore) {
      const endTimeMs = bestBefore.startTimeMs + bestBefore.durationMs
      const safeTailMs = Math.min(2000, bestBefore.durationMs)
      return new NearestVideoResult(bestBefore, Math.max(bestBefore.startTimeMs, endTimeMs - safeTailMs))
    }
    return null
  }

  private onTimelineTouch(e: TouchEvent): void {
    const touchX = e.changedTouches.length > 0 ? e.changedTouches[0].x :
      (e.touches.length > 0 ? e.touches[0].x : this.timelineTouchStartX)
    const touchY = e.changedTouches.length > 0 ? e.changedTouches[0].y :
      (e.touches.length > 0 ? e.touches[0].y : this.timelineTouchStartY)
    if (e.type === TouchType.Down) {
      this.timelineTouchStartX = touchX
      this.timelineTouchStartY = touchY
      this.timelineTouchMoved = false
      this.isUserScrollingTimeline = false
      return
    }
    if (e.type === TouchType.Move) {
      if (Math.abs(touchX - this.timelineTouchStartX) >= 4) {
        this.timelineTouchMoved = true
        this.isUserScrollingTimeline = true
        this.pinnedCenterTimeMs = null
      }
      if (this.isFullscreen) {
        this.scheduleFullscreenAutoHide()
      }
      return
    }
    if (e.type === TouchType.Cancel) {
      this.isUserScrollingTimeline = false
      this.timelineTouchMoved = false
      return
    }
    if (e.type === TouchType.Up && !this.timelineTouchMoved) {
      this.onTimelineTap(touchX, touchY)
    }
  }

  private onTimelineTap(viewportX: number, viewportY: number): void {
    const barTop = 20
    const barBottom = barTop + 28
    if (viewportY < barTop - 4 || viewportY > barBottom + 4) {
      return
    }
    const contentX = this.timelineScroller.currentOffset().xOffset + viewportX
    const tappedTime = this.xToTime(contentX)
    const file = this.videoFileAt(tappedTime)
    if (file) {
      this.isTimelinePositionedByUser = true
      this.playVideoFile(file, tappedTime)
    }
  }

  private onTimelineDidScroll(): void {
    this.updateTimelineCenterTime()
  }

  private onTimelineScrollStop(): void {
    if (this.isUserScrollingTimeline) {
      this.onTimelineScrollIdle()
    }
  }

  private updateTimelineCenterTime(): void {
    if (this.isPlaybackTimeDriven()) {
      return
    }
    if (this.pinnedCenterTimeMs !== null) {
      this.timelineCenterTimeText = this.timeOfDay(this.pinnedCenterTimeMs)
      return
    }
    const scrollX = this.timelineScroller.currentOffset().xOffset
    const centerTime = this.timeAtCenter(scrollX)
    this.timelineCenterTimeText = this.timeOfDay(centerTime)
  }

  private onTimelineScrollIdle(): void {
    if (!this.isUserScrollingTimeline) {
      return
    }
    this.isUserScrollingTimeline = false
    this.timelineTouchMoved = false
    this.pinnedCenterTimeMs = null
    this.isTimelinePositionedByUser = true
    const scrollX = this.timelineScroller.currentOffset().xOffset
    const centerTime = this.timeAtCenter(scrollX)
    this.timelineCenterTimeText = this.timeOfDay(centerTime)

    const directFile = this.videoFileAt(centerTime)
    if (directFile) {
      this.playVideoFile(directFile, centerTime)
      return
    }
    const nearest = this.nearestVideoFileNear(centerTime)
    if (nearest) {
      this.playVideoFile(nearest.file, nearest.playTimeMs)
    } else {
      this.showToast('该时间点附近无录像')
    }
  }

  private centerTimelineAtTime(timeMs: number): void {
    const targetX = this.timeToX(this.clampTimeToSelectedDay(timeMs))
    const scrollTo = Math.max(targetX - this.timelineViewportWidthVp / 2, 0)
    this.timelineScroller.scrollTo({ xOffset: scrollTo, yOffset: 0 })
  }

  private scrollTimelineToTime(timeMs: number): void {
    const targetTimeMs = this.clampTimeToSelectedDay(timeMs)
    this.pinnedCenterTimeMs = targetTimeMs
    this.timelineCenterTimeText = this.timeOfDay(targetTimeMs)
    const targetX = this.timeToX(targetTimeMs)
    const scrollTo = Math.max(targetX - this.timelineViewportWidthVp / 2, 0)
    this.timelineScroller.scrollTo({ xOffset: scrollTo, yOffset: 0, animation: { duration: 300, curve: Curve.EaseOut } })
  }

  private onTimelineViewportChange(widthVp: number): void {
    if (widthVp <= 0 || Math.abs(widthVp - this.timelineViewportWidthVp) < 1) {
      return
    }
    this.timelineViewportWidthVp = widthVp
    this.timelineHourWidthVp = widthVp / CloudStoragePage.BASE_TIMELINE_HOURS_ON_SCREEN
    this.timelineCanvasWidthVp = this.timelineHourWidthVp * 24 + widthVp
    this.drawTimeline()
    this.refreshTimelineLayout()
  }

  private refreshTimelineLayout(): void {
    if (this.isPlayerStarted && this.currentPlayWallMs !== null) {
      this.centerTimelineAtTime(this.currentPlayWallMs)
      return
    }
    if (this.timelineFiles.length > 0) {
      this.centerTimelineAtTime(this.timelineFiles[0].startTimeMs)
    }
  }

  private drawTimeline(): void {
    const ctx = this.timelineCtx
    const hourWidth = this.timelineHourWidthVp
    const sidePadding = this.timelineSidePadding()
    const w = this.timelineCanvasWidthVp
    const h = this.timelineHeightVp
    ctx.clearRect(0, 0, Math.max(w, 1), h)
    if (hourWidth <= 0 || w <= 1) {
      return
    }
    const dark = this.isFullscreen
    const barTop = 20
    const barHeight = 28

    ctx.fillStyle = dark ? '#3A3A3A' : '#E4E7ED'
    this.fillRoundRect(ctx, sidePadding, barTop, hourWidth * 24, barHeight, 2)

    const dayStart = this.dayStartMs()
    const dayEnd = dayStart + 24 * 60 * 60 * 1000
    if (dayEnd > dayStart && this.timelineFiles.length > 0) {
      ctx.fillStyle = '#3D6EFF'
      for (const f of this.timelineFiles) {
        const s = Math.min(Math.max(f.startTimeMs, dayStart), dayEnd)
        const e = Math.min(Math.max(f.startTimeMs + f.durationMs, dayStart), dayEnd)
        if (e <= s) {
          continue
        }
        const left = this.timeToX(s)
        const right = Math.max(this.timeToX(e), left + 1)
        ctx.fillRect(left, barTop, right - left, barHeight)
      }
    }

    // Canvas 的 font 单位固定是物理 px；而时间轴的布局坐标使用 vp。
    // Android 端的刻度文字为 10sp，使用 scaledDensity 换算，避免在高密度屏上
    // 出现刻度文字远小于时间轴和 Android 端的情况。
    ctx.font = `${10 * this.timelineScaledDensity}px sans-serif`
    ctx.textAlign = 'center'
    // 与 Android TimelineView 的 dp(0.5f) 刻度线宽保持一致。
    ctx.lineWidth = Math.max(0.5 * this.timelineDensityPixels, 1)
    for (let hour = 0; hour <= 24; hour++) {
      const x = sidePadding + hour * hourWidth
      const tickLen = hour % 6 === 0 ? 6 : 3
      ctx.strokeStyle = dark ? '#666666' : '#9DA3B0'
      ctx.beginPath()
      ctx.moveTo(x, barTop - tickLen)
      ctx.lineTo(x, barTop)
      ctx.stroke()
      if (hour < 24) {
        ctx.fillStyle = dark ? '#B0B0B0' : '#6B7280'
        ctx.fillText(`${this.pad2(hour)}:00`, x, barTop - 8)
      }
    }
    ctx.textAlign = 'right'
    ctx.fillStyle = dark ? '#B0B0B0' : '#6B7280'
    ctx.fillText('23:59:59', sidePadding + 24 * hourWidth, barTop - 8)
    ctx.textAlign = 'center'

    const now = Date.now()
    if (now >= dayStart && now <= dayEnd) {
      const nowX = this.timeToX(now)
      ctx.strokeStyle = '#FF4D4F'
      ctx.lineWidth = Math.max(1.5 * this.timelineDensityPixels, 1)
      ctx.beginPath()
      ctx.moveTo(nowX, barTop - 4)
      ctx.lineTo(nowX, barTop + barHeight + 4)
      ctx.stroke()
    }
  }

  private fillRoundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    const rr = Math.min(r, w / 2, h / 2)
    ctx.beginPath()
    ctx.moveTo(x + rr, y)
    ctx.arcTo(x + w, y, x + w, y + h, rr)
    ctx.arcTo(x + w, y + h, x, y + h, rr)
    ctx.arcTo(x, y + h, x, y, rr)
    ctx.arcTo(x, y, x + w, y, rr)
    ctx.closePath()
    ctx.fill()
  }

  // ─── 全屏 ──────────────────────────────────────────────────

  private toggleFullscreen(): void {
    if (this.isFullscreen) {
      this.exitFullscreen()
    } else {
      this.enterFullscreen()
    }
  }

  private enterFullscreen(): void {
    if (this.isFullscreen) {
      return
    }
    this.isFullscreen = true
    this.setWindowOrientation(true)
    this.cancelPlayPauseHideTimer()
    this.showFullscreenControls = true
    this.updatePlayPauseVisibility(true)
    this.drawTimeline()
    this.refreshTimelineLayout()
    this.scheduleFullscreenAutoHide()
  }

  private exitFullscreen(): void {
    if (!this.isFullscreen) {
      return
    }
    this.isFullscreen = false
    this.cancelFullscreenAutoHide()
    this.showFullscreenControls = true
    this.setWindowOrientation(false)
    this.updatePlayPauseVisibility(true)
    this.drawTimeline()
    this.refreshTimelineLayout()
    this.schedulePlayPauseAutoHide()
  }

  private setFullscreenControlsVisible(visible: boolean): void {
    this.showFullscreenControls = visible
    this.updatePlayPauseVisibility(visible)
  }

  private scheduleFullscreenAutoHide(): void {
    this.cancelFullscreenAutoHide()
    this.fullscreenAutoHideTimer = setTimeout(() => {
      this.fullscreenAutoHideTimer = null
      this.setFullscreenControlsVisible(false)
    }, CloudStoragePage.FULLSCREEN_AUTO_HIDE_DELAY_MS)
  }

  private cancelFullscreenAutoHide(): void {
    if (this.fullscreenAutoHideTimer !== null) {
      clearTimeout(this.fullscreenAutoHideTimer)
      this.fullscreenAutoHideTimer = null
    }
  }

  private onVideoAreaTap(): void {
    if (this.isFullscreen) {
      const visible = !this.showFullscreenControls
      this.setFullscreenControlsVisible(visible)
      if (visible) {
        this.scheduleFullscreenAutoHide()
      } else {
        this.cancelFullscreenAutoHide()
      }
      return
    }
    if (this.showPlayPauseButton) {
      this.cancelPlayPauseHideTimer()
      this.showPlayPauseButton = false
    } else {
      this.showPlayPauseButtonWithAutoHide()
    }
  }

  private setWindowOrientation(landscape: boolean): void {
    const requestId = ++this.orientationRequestId
    try {
      const context = getContext(this) as common.UIAbilityContext
      window.getLastWindow(context, (err, win) => {
        if ((err && err.code) || !this.pageActive || requestId !== this.orientationRequestId ||
          landscape !== this.isFullscreen) {
          return
        }
        win.setWindowSystemBarEnable(landscape ? ['navigation'] : ['status', 'navigation'])
        win.setPreferredOrientation(landscape ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT)
      })
    } catch (e) {
      console.error(`[CloudStorage] setWindowOrientation 异常: ${JSON.stringify(e)}`)
    }
  }

  // ─── 工具 ──────────────────────────────────────────────────

  private showToast(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  private runSafely(block: () => void): void {
    try {
      block()
    } catch (e) {
    }
  }

  private pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }

  private timeOfDay(ms: number): string {
    const d = new Date(ms)
    return `${this.pad2(d.getHours())}:${this.pad2(d.getMinutes())}:${this.pad2(d.getSeconds())}`
  }

  private formatEventType(eventType: string): string {
    if (!eventType || eventType.length === 0) {
      return '事件'
    }
    return this.eventTypeNames[eventType] ?? eventType
  }

  private formatEventDuration(durationMs: number): string {
    const totalSec = Math.max(Math.floor(durationMs / 1000), 0)
    if (totalSec < 60) {
      return `${totalSec}s`
    }
    return `${Math.floor(totalSec / 60)}:${this.pad2(totalSec % 60)}`
  }

  private relativeWeekDay(date: string): string {
    const parts = date.split('-')
    if (parts.length < 3) {
      return ''
    }
    const target = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]), 0, 0, 0, 0)
    const today = new Date()
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 0, 0, 0, 0)
    const diffDays = Math.floor((todayStart.getTime() - target.getTime()) / (24 * 60 * 60 * 1000))
    if (diffDays === 0) {
      return '今天'
    }
    if (diffDays === 1) {
      return '昨天'
    }
    const names = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
    return names[target.getDay()]
  }

  private dayOf(date: string): string {
    const parts = date.split('-')
    return parts.length >= 3 ? this.pad2(parseInt(parts[2])) : date
  }

  private monthOf(date: string): string {
    const parts = date.split('-')
    return parts.length >= 2 ? `${this.pad2(parseInt(parts[1]))}月` : ''
  }

  private isSnapshotEvent(event: TXIoTEvent): boolean {
    return !event.videoFiles || event.videoFiles.length === 0
  }

  private eventListKey(event: TXIoTEvent): string {
    const first = event.videoFiles && event.videoFiles.length > 0 ? event.videoFiles[0] : null
    return `${event.eventTimeMs}-${event.eventType}-${first?.startTimeMs ?? 0}-${first?.durationMs ?? 0}-${first?.videoUrl ?? ''}`
  }

  // ─── Builder ───────────────────────────────────────────────

  @Builder
  channelMenuBuilder() {
    ContextMenuBuilder([
      { text: '无通道', onAction: () => this.onChannelSelected(0) } as CMenuItem,
      { separator: true } as CMenuItem,
      { text: '通道 1', onAction: () => this.onChannelSelected(1) } as CMenuItem,
      { separator: true } as CMenuItem,
      { text: '通道 2', onAction: () => this.onChannelSelected(2) } as CMenuItem,
      { separator: true } as CMenuItem,
      { text: '通道 3', onAction: () => this.onChannelSelected(3) } as CMenuItem
    ])
  }

  @Builder
  TopBar() {
    Row() {
      Button() {
        Image($r('app.media.ic_cloud_back')).width(24).height(24)
      }
      .width(44).height(44)
      .padding(10)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回')
      .onClick(() => router.back())

      Column({ space: 1 }) {
        Row({ space: 6 }) {
          Circle().width(8).height(8).fill(this.online ? '#52C41A' : '#C8CDD8')
          Text(this.deviceName)
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 180 })
        }.justifyContent(FlexAlign.Center)

        Row({ space: 6 }) {
          Text(`${this.productId}/${this.deviceName}`)
            .fontSize(10).fontColor('#CCFFFFFF')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 200 })
          Row() {
            Text(this.channelText()).fontSize(10).fontColor('#006EFF')
            Text(' ▾').fontSize(9).fontColor('#006EFF')
          }
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .bindMenu(this.channelMenuBuilder)
        }.justifyContent(FlexAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Button() {
        Image($r('app.media.ic_cloud_refresh')).width(24).height(24)
      }
      .width(44).height(44)
      .padding(10)
      .backgroundColor(Color.Transparent)
      .accessibilityText('刷新')
      .onClick(() => this.loadDayList())
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: px2vp(this.statusBarHeight) + 4, bottom: 4 })
    .linearGradient({ angle: 135, colors: [['#1A73E8', 0.0], ['#006EFF', 1.0]] })
  }

  @Builder
  VideoArea() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: 'cloud_vod_view',
        type: XComponentType.SURFACE,
        controller: this.xcomponentController
      })
        .width('100%').height('100%')
        .onLoad(() => {
          const surfaceId = this.xcomponentController.getXComponentSurfaceId()
          this.videoSurfaceId = surfaceId
          this.vodPlayer?.setVideoRenderTarget(surfaceId)
        })

      if (this.videoLoading) {
        LoadingProgress().width(48).height(48).color('#FFFFFF')
      }

      if (this.isFullscreen && this.showFullscreenControls) {
        Column() {
          Column() {
            this.TimelineContent()
          }
          .width('100%')
          .padding({ top: 10, bottom: 8 })
          .backgroundColor('#B3000000')
          .onTouch((event: TouchEvent) => event.stopPropagation())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
      }

      if (this.showPlayPauseButton) {
        Button() {
          Image(this.isPlaybackPaused
            ? $r('app.media.ic_cloud_video_play')
            : $r('app.media.ic_cloud_video_pause'))
            .width(24).height(24)
        }
        .width(56).height(56).borderRadius(28)
        .padding(14)
        .backgroundColor('#80000000')
        .border({ width: 1, color: '#FFFFFF' })
        .accessibilityText(this.isPlaybackPaused ? '播放' : '暂停')
        .onClick(() => {
          this.togglePlayPause()
          if (this.isFullscreen) {
            this.scheduleFullscreenAutoHide()
          }
        })
        .onTouch((event: TouchEvent) => event.stopPropagation())
      }

      if (this.showReplayOverlay) {
        Column({ space: 10 }) {
          Button() {
            Image($r('app.media.ic_cloud_refresh')).width(24).height(24)
          }
          .width(56).height(56).borderRadius(28)
          .padding(14)
          .backgroundColor('#80000000')
          .border({ width: 1, color: '#FFFFFF' })
          .accessibilityText('重新播放')
          .onClick(() => this.replayLastSession())
          .onTouch((event: TouchEvent) => event.stopPropagation())
          Text('播放结束').fontSize(13).fontColor('#FFFFFF')
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#80000000')
      }

      if (!this.isFullscreen || this.showFullscreenControls) {
        Row() {
          Blank()
          Column({ space: 12 }) {
            Button() {
              Image(this.isMuted ? $r('app.media.ic_sound_off') : $r('app.media.ic_sound_on'))
                .width(20).height(20)
            }
            .width(36).height(36).borderRadius(18)
            .padding(8)
            .backgroundColor('#80000000')
            .border({ width: 1, color: '#FFFFFF' })
            .accessibilityText(this.isMuted ? '开启声音' : '静音')
            .onClick(() => {
              this.toggleMute()
              if (this.isFullscreen) {
                this.scheduleFullscreenAutoHide()
              }
            })
            .onTouch((event: TouchEvent) => event.stopPropagation())
            Button() {
              Image(this.isFullscreen ? $r('app.media.ic_fullscreen_exit') : $r('app.media.ic_fullscreen'))
                .width(20).height(20)
            }
            .width(36).height(36).borderRadius(18)
            .padding(8)
            .backgroundColor('#80000000')
            .border({ width: 1, color: '#FFFFFF' })
            .accessibilityText(this.isFullscreen ? '退出全屏' : '进入全屏')
            .onClick(() => this.toggleFullscreen())
            .onTouch((event: TouchEvent) => event.stopPropagation())
          }
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ right: 12 })
      }

      if (this.showSnapshot) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(this.snapshotUrl)
            .width('100%').height('100%').objectFit(ImageFit.Contain)
            .onComplete(() => {
              this.snapshotLoading = false
            })
            .onError(() => {
              this.snapshotLoading = false
            })
          if (this.snapshotLoading) {
            LoadingProgress().width(40).height(40).color('#FFFFFF')
              .position({ x: 'calc(50% - 20vp)', y: 'calc(50% - 20vp)' })
          }
          if (this.snapshotTitle.length > 0) {
            Text(this.snapshotTitle)
              .fontSize(13).fontColor('#FFFFFF')
              .padding({ left: 10, right: 10, top: 2, bottom: 2 })
              .position({ x: 'calc(50% - 80vp)', y: 8 })
              .constraintSize({ maxWidth: 160 })
              .textAlign(TextAlign.Center)
          }
          Text('×')
            .fontSize(22).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            .width(36).height(36).textAlign(TextAlign.Center)
            .margin({ top: 6, right: 6 })
            .accessibilityText('关闭图片')
            .onClick(() => this.hideSnapshotPreview())
            .onTouch((event: TouchEvent) => event.stopPropagation())
        }
        .width('100%').height('100%')
        .backgroundColor('#000000')
        .onTouch((event: TouchEvent) => event.stopPropagation())
      }
    }
    .width('100%')
    .height(this.isFullscreen ? '100%' : 220)
    .backgroundColor('#000000')
    .clip(true)
    .onClick(() => this.onVideoAreaTap())
  }

  @Builder
  DateChip(date: string) {
    Column({ space: 1 }) {
      Text(this.relativeWeekDay(date))
        .fontSize(11)
        .fontColor(date === this.selectedDate ? '#CCFFFFFF' : '#9DA3B0')
      Text(this.dayOf(date))
        .fontSize(17).fontWeight(FontWeight.Bold)
        .fontColor(date === this.selectedDate ? '#FFFFFF' : '#15161A')
      Text(this.monthOf(date))
        .fontSize(10)
        .fontColor(date === this.selectedDate ? '#CCFFFFFF' : '#9DA3B0')
    }
    .width(48).height(56)
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(date === this.selectedDate ? '#006EFF' : '#FFFFFF')
    .border({ width: date === this.selectedDate ? 0 : 1, color: '#E0E4EC' })
    .margin({ right: 8 })
    .onClick(() => this.selectDate(date))
  }

  @Builder
  DateScroll() {
    Scroll() {
      Row() {
        ForEach(this.dateList, (date: string) => {
          this.DateChip(date)
        })
      }.padding({ left: 6, right: 6 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ top: 4, bottom: 3 })
    .backgroundColor('#F5F6FA')
  }

  @Builder
  TimelineContent() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll(this.timelineScroller) {
        Canvas(this.timelineCtx)
          .width(Math.max(this.timelineCanvasWidthVp, 1))
          .height(this.timelineHeightVp)
          .onReady(() => {
            this.drawTimeline()
            this.refreshTimelineLayout()
          })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(this.timelineHeightVp)
      .onAreaChange((oldArea: Area, newArea: Area) => this.onTimelineViewportChange(newArea.width as number))
      .onTouch((e: TouchEvent) => this.onTimelineTouch(e))
      .onDidScroll((scrollOffset: number, scrollState: ScrollState) => this.onTimelineDidScroll())
      .onScrollStop(() => this.onTimelineScrollStop())

      if (this.timelineHasVideo) {
        Column() {
          Column()
            .width(2).height(40)
            .backgroundColor('#00C160')
          Text(this.timelineCenterTimeText)
            .height(16)
            .fontSize(9)
            .fontColor('#FFFFFF')
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor('#00C160')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }

      if (!this.timelineHasVideo) {
        Text('🎬 该日无全时录像')
          .fontSize(12)
          .fontColor(this.isFullscreen ? '#99FFFFFF' : '#9DA3B0')
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height(this.timelineHeightVp)
  }

  @Builder
  Timeline() {
    Column() {
      this.TimelineContent()
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 10, bottom: 8 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  EventCard(event: TXIoTEvent) {
    Row({ space: 9 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (event.thumbnailUrl && event.thumbnailUrl.length > 0) {
          Image(event.thumbnailUrl)
            .width(78).height(58).borderRadius(12).objectFit(ImageFit.Cover)
        } else {
          Column()
            .width(78).height(58).borderRadius(12)
            .backgroundColor('#E6E8EC')
        }
        if (!this.isSnapshotEvent(event)) {
          Image($r('app.media.ic_cloud_play_circle'))
            .width(26).height(26)
        }
      }
      .width(78).height(58)
      .borderRadius(12)
      .backgroundColor('#E6E8EC')
      .clip(true)

      Column({ space: 3 }) {
        Row() {
          Text(this.formatEventType(event.eventType))
            .fontSize(10).fontColor('#006EFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#E8F2FF')
            .borderRadius(10)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Text(this.isSnapshotEvent(event) ? '抓图' : this.formatEventDuration(event.durationMs))
            .fontSize(10).fontColor('#9DA3B0')
        }
        .width('100%')

        Text(this.timeOfDay(event.eventTimeMs))
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor('#15161A')
          .maxLines(1)

        Row({ space: 3 }) {
          if (!this.isSnapshotEvent(event)) {
            Image($r('app.media.ic_cloud_play_circle'))
              .width(11).height(11).fillColor('#006EFF')
          }
          Text(this.isSnapshotEvent(event) ? '点击查看图片' : '点击播放视频')
            .fontSize(10).fontColor('#6B7280')
        }
      }
      .height(58)
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(9)
    .margin({ top: 4, bottom: 4 })
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .shadow({ radius: 2, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: 1 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.isSnapshotEvent(event)) {
        this.viewSnapshot(event)
      } else {
        this.playEvent(event)
      }
    })
  }

  @Builder
  EventList() {
    Stack({ alignContent: Alignment.Center }) {
      List({ space: 0 }) {
        ForEach(this.eventList, (event: TXIoTEvent) => {
          ListItem() {
            this.EventCard(event)
          }
        }, (event: TXIoTEvent) => this.eventListKey(event))
      }
      .width('100%').height('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 16 })

      if (this.listLoading) {
        LoadingProgress().width(36).height(36).color('#006EFF')
      } else if (this.isListEmpty) {
        Text('☁️ 暂无云存记录').fontSize(14).fontColor('#9DA3B0')
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#F5F6FA')
  }

  build() {
    Column() {
      if (!this.isFullscreen) {
        this.TopBar()
      }
      this.VideoArea()
      if (!this.isFullscreen) {
        if (this.dateList.length > 0) {
          this.DateScroll()
        }
        this.Timeline()
        this.EventList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6FA')
  }
}
