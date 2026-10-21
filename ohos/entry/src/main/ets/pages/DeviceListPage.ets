import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import pasteboard from '@ohos.pasteboard'
import window from '@ohos.window'
import { AppState, DeviceModel, DeviceSettings } from '../model/AppModel'
import { saveDevices } from '../utils/StorageUtil'
import { CallManager, CallMode, CallState } from '../utils/CallManager'
import {
  TXIoTDeviceInfo,
  TXIoTFamilyInfo,
  TXIoTDeviceId,
  TXIoTDeviceStatus,
  TXIoTEngineListener,
  TXIoTErrorCode,
  TXIoTPageResult
} from '@tencentcloud/liteavsdk_iot'
import { ContextMenuBuilder, ContextMenuItem as CMenuItem } from '../components/ContextMenu'
import { DeviceHardwareType } from '../utils/DeviceHardwareType'
import {
  PrimaryButton,
  CancelButton,
  DialogTitleText,
  SecondaryText,
  DragHandle,
  CaptionText,
  AppColor,
  NavBar,
  SectionTitleText,
  DialogInputField
} from '../components/AppTheme'
import { CommonBottomSheet } from '../components/CommonBottomSheet'

@Entry
@Component
struct DeviceListPage {
  @State devices: DeviceModel[] = []
  @State showDeleteDialog: boolean = false
  @State deleteDeviceId: string = ''
  @State isLoading: boolean = false
  @State currentFamilyName: string = ''
  @State familyList: TXIoTFamilyInfo[] = []
  @State showFamilySwitchDialog: boolean = false
  // 首次家庭列表加载是否已完成（完成后 onPageShow 才做静默重拉，避免与 aboutToAppear 首载重复）
  private familyInitDone: boolean = false
  // Call related
  @State currentMenuDevice: DeviceModel | null = null
  @State incomingBannerVisible: boolean = false
  @State incomingPeerName: string = ''
  @State incomingPeerAvatar: string = ''
  @State incomingIsVideo: boolean = false
  private callListener = () => {
    this.syncCallState()
  }
  // Channel selector related
  @State showChannelSelector: boolean = false
  @State selectedDeviceForChannels: DeviceModel | null = null
  @State selectedChannels: number[] = [0]
  private readonly availableChannels: number[] = [0, 1, 2, 3]
  // Alias modify dialog
  @State showAliasDialog: boolean = false
  @State aliasInputValue: string = ''
  @State aliasTargetDevice: DeviceModel | null = null
  // Share token dialog
  @State showShareTokenDialog: boolean = false
  @State shareTokenContent: string = ''
  // Pull-to-refresh
  @State isRefreshing: boolean = false
  // Status bar height for immersive design
  @StorageProp('statusBarHeight') statusBarHeight: number = 48
  // Engine listener for push messages & login expiry
  private engineListener: TXIoTEngineListener = {
    onLoginSuccess: () => {
    },
    onLoginFailure: () => {
    },
    onUserSignatureExpired: () => {
      this.onSignatureExpired()
    },
    onReceivePushMessage: () => {
      this.onPushStatusChange()
    }
  }

  // ─── Lifecycle ───────────────────────────────────────────────

  aboutToAppear() {
    this.devices = AppState.devices
    this.currentFamilyName = AppState.currentFamilyName || ''
    this.initFamilyThenLoadDevices()
    CallManager.init()
    CallManager.addListener(this.callListener)
    this.syncCallState()
    AppState.engine().addListener(this.engineListener)
    this.setupImmersiveStatusBar()
  }

  private setupImmersiveStatusBar() {
    const context = getContext(this) as Context
    window.getLastWindow(context, (err, win) => {
      if (err.code) {
        console.error(`❌ setupImmersiveStatusBar error: ${JSON.stringify(err)}`)
        return
      }
      // Make status bar transparent so the blue gradient shows through
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#ffffff'
      })
      // Enable full-screen layout so content extends behind status bar
      win.setWindowLayoutFullScreen(true)
      // Get status bar height and store it
      const avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      const statusBarHeight = avoidArea.topRect.height
      AppStorage.setOrCreate<number>('statusBarHeight', statusBarHeight)
    })
  }

  aboutToDisappear() {
    CallManager.removeListener(this.callListener)
    AppState.engine().removeListener(this.engineListener)
  }

  onPageShow() {
    this.currentFamilyName = AppState.currentFamilyName || ''
    this.devices = [...AppState.devices]
    this.syncCallState()
    // 对齐 Android onResume 每次 reloadFamilyList：首次进入已由 aboutToAppear 加载，
    // 此后每次回到本页都静默重拉家庭列表（远端增删家庭/被踢出等变更可及时体现）；
    // familyListChanged 时立即重载且显示加载态
    if (this.familyInitDone) {
      this.refreshFamilyList(AppState.familyListChanged)
      AppState.familyListChanged = false
    }
    this.loadDevicesFromSDK()
  }

  // ─── Call State ──────────────────────────────────────────────

  private syncCallState(): void {
    const state = CallManager.state
    const session = CallManager.currentSession
    if (state !== CallState.RINGING || !session) {
      this.incomingBannerVisible = false
      return
    }
    this.incomingPeerName = session.peerName
    this.incomingPeerAvatar = session.peerAvatar || ''
    this.incomingIsVideo = session.mode === CallMode.VIDEO
    this.incomingBannerVisible = true
  }

  private startAudioCall(device: DeviceModel): void {
    CallManager.startCall(device.name, CallMode.AUDIO, device.iconUrl,
      device.productId || '', device.deviceName || device.id)
    router.pushUrl({ url: 'pages/CallPage' })
  }

  private startVideoCall(device: DeviceModel): void {
    CallManager.startCall(device.name, CallMode.VIDEO, device.iconUrl,
      device.productId || '', device.deviceName || device.id)
    router.pushUrl({ url: 'pages/CallPage' })
  }

  private expandIncomingBanner(): void {
    this.incomingBannerVisible = false
    router.pushUrl({ url: 'pages/CallPage' })
  }

  private answerFromBanner(): void {
    this.incomingBannerVisible = false
    CallManager.answer()
    router.pushUrl({ url: 'pages/CallPage' })
  }

  private rejectFromBanner(): void {
    this.incomingBannerVisible = false
    CallManager.hangup()
  }

  // ─── Engine Events ───────────────────────────────────────────

  private onSignatureExpired(): void {
    this.showToast('登录已过期，请重新登录')
    router.replaceUrl({ url: 'pages/LoginPage' })
  }

  private onPushStatusChange(): void {
    const fid = AppState.currentFamilyId
    if (fid) {
      this.loadDevicesFromSDK(fid)
    }
  }

  // ─── Modify Alias ───────────────────────────────────────────

  private showModifyAliasDialog(device: DeviceModel): void {
    this.aliasTargetDevice = device
    this.aliasInputValue = device.name || ''
    this.showAliasDialog = true
  }

  private confirmModifyAlias(): void {
    const device = this.aliasTargetDevice
    if (!device) {
      this.showAliasDialog = false;
      return
    }
    const newAlias = this.aliasInputValue.trim()
    if (!newAlias) {
      this.showToast('别名不能为空');
      return
    }
    this.doModifyAlias(device, newAlias)
  }

  private doModifyAlias(device: DeviceModel, newAlias: string): void {
    const productId = device.productId || ''
    const deviceName = device.deviceName || device.id
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = productId
    deviceId.deviceName = deviceName
    dm.modifyAliasName(deviceId, newAlias, {
      onSuccess: (_: void) => {
        this.onModifyAliasResult(true, null, device, newAlias)
      },
      onError: (_errorCode: TXIoTErrorCode, errMsg: string) => {
        this.onModifyAliasResult(false, errMsg, device, newAlias)
      }
    })
  }

  private onModifyAliasResult(success: boolean, errMsg: string | null, device: DeviceModel, newAlias: string): void {
    if (!success) {
      this.showToast(errMsg || '修改别名失败');
      return
    }
    const idx = AppState.devices.findIndex(d => d.id === device.id)
    if (idx >= 0) {
      AppState.devices[idx].name = newAlias
    }
    this.devices = [...AppState.devices]
    this.persistDevices()
    this.showAliasDialog = false
    this.showToast('修改别名成功')
  }

  // ─── Device Share ───────────────────────────────────────────

  private createShareToken(device: DeviceModel): void {
    const familyId = device.familyId || AppState.currentFamilyId
    const productId = device.productId || ''
    const deviceName = device.deviceName || device.id
    if (!familyId || !productId || !deviceName) {
      this.showToast('设备信息不完整，无法分享')
      return
    }
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
        this.onShareTokenResult(true, JSON.stringify(payload, null, 2), null)
      },
      onError: (_errorCode: TXIoTErrorCode, errMsg: string) => {
        this.onShareTokenResult(false, null, errMsg)
      }
    })
  }

  private onShareTokenResult(success: boolean, jsonStr: string | null, errMsg: string | null): void {
    if (success && jsonStr) {
      this.shareTokenContent = jsonStr
      this.showShareTokenDialog = true
    } else {
      this.showToast(errMsg || '生成分享码失败')
    }
  }

  // ─── Utility ─────────────────────────────────────────────────

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  getSignalIcon(signal: string): string {
    return signal === '强' ? '●●●' : signal === '中' ? '●●○' : '●○○'
  }

  // ─── Family Init ─────────────────────────────────────────────

  initFamilyThenLoadDevices() {
    this.refreshFamilyList(true)
  }

  /**
   * 重载家庭列表（对齐 Android reloadFamilyList）
   * @param showLoading 是否显示加载态（首次进入/家庭发生变更时为 true；静默刷新为 false）
   */
  private refreshFamilyList(showLoading: boolean) {
    if (showLoading) {
      this.isLoading = true
    }
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      if (showLoading) {
        this.isLoading = false
        this.showToast('家庭管理器未初始化')
      }
      return
    }
    fm.getFamilyList({
      onSuccess: (familyList: TXIoTFamilyInfo[]) => {
        if (familyList && familyList.length > 0) {
          this.onFamilyListLoaded(familyList, showLoading)
        } else if (showLoading) {
          // 仅首次/变更重载时走默认家庭创建；静默刷新拿到空列表不改动现有状态
          this.createDefaultFamily()
        }
      },
      onError: (_errorCode: TXIoTErrorCode, _errorMessage: string) => {
        if (showLoading) {
          this.createDefaultFamily()
        }
        // 静默刷新失败保留现有列表，避免网络抖动导致已显示的家庭被清空
      }
    })
  }

  /**
   * 对齐 Android onFamilyListLoaded：当前家庭仍存在则保持，否则兜底选中第一个
   * @param isInitLoad 首次/变更重载后需触发设备刷新；静默刷新仅在切换了家庭时才刷新设备
   */
  private onFamilyListLoaded(familyList: TXIoTFamilyInfo[], isInitLoad: boolean): void {
    this.familyInitDone = true
    this.familyList = familyList
    const existingFid = AppState.currentFamilyId
    const targetFamily = familyList.find(f => f.familyId === existingFid) || familyList[0]
    const fid = targetFamily.familyId
    const fname = targetFamily.name || ''
    const familyChanged = fid !== existingFid
    this.applyFamilySelection(fid, fname)
    console.info(`✅ 家庭列表获取成功，当前家庭ID: ${fid}，名称: ${fname}`)
    if (isInitLoad || familyChanged) {
      // 当前家庭已不存在（被删除/被踢出）时重载新家庭的设备
      this.loadDevicesFromSDK(fid)
    }
  }

  private applyFamilySelection(fid: string, fname: string): void {
    AppState.currentFamilyId = fid
    AppState.currentFamilyName = fname
    this.currentFamilyName = fname
  }

  private createDefaultFamily(): void {
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.isLoading = false
      this.showToast('未找到家庭信息，请重新登录')
      return
    }
    fm.createFamily('我的家庭', {
      onSuccess: (info: TXIoTFamilyInfo) => {
        this.familyInitDone = true
        this.applyFamilySelection(info.familyId, '我的家庭')
        console.info(`✅ 默认家庭创建成功: ${info.familyId}`)
        this.loadDevicesFromSDK(info.familyId)
      },
      onError: (_errorCode: TXIoTErrorCode, createError: string) => {
        this.familyInitDone = true
        this.isLoading = false
        console.warn(`⚠️ 家庭创建失败: ${createError}`)
        this.showToast('未找到家庭信息，请重新登录')
      }
    })
  }

  // ─── Load Devices ────────────────────────────────────────────

  loadDevicesFromSDK(familyId?: string, isRefresh: boolean = false) {
    const fid = familyId || AppState.currentFamilyId
    if (!fid) {
      console.warn('⚠️ 未找到家庭ID，跳过设备列表加载')
      if (isRefresh) {
        this.isRefreshing = false
      }
      return
    }
    // 下拉刷新时不切换 isLoading，避免 Refresh 容器被 LoadingView 替换造成闪烁
    if (!isRefresh) {
      this.isLoading = true
    }

    let ownedList: TXIoTDeviceInfo[] = []
    let sharedList: TXIoTDeviceInfo[] = []
    let ownedError: string | null = null
    let completedCount = 0

    const onBothCompleted = () => {
      completedCount++
      if (completedCount < 2) {
        return
      }
      if (!isRefresh) {
        this.isLoading = false
      }
      this.isRefreshing = false
      this.mergeAndApplyDevices(ownedList, sharedList, ownedError, fid)
    }

    this.fetchOwnedDevices(fid, (list, err) => {
      ownedList = list
      ownedError = err
      onBothCompleted()
    })
    this.fetchSharedDevices(fid, (list) => {
      sharedList = list
      onBothCompleted()
    })
  }

  private fetchOwnedDevices(fid: string, cb: (list: TXIoTDeviceInfo[], err: string | null) => void): void {
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      cb([], '设备管理器未初始化')
      return
    }
    dm.getDeviceList(fid, '', {
      onSuccess: (result: TXIoTPageResult<TXIoTDeviceInfo>) => {
        const deviceList = result.dataList || []
        console.info(`✅ 获取自有设备列表成功，共 ${deviceList.length} 台`)
        cb(deviceList, null)
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        const err = errorMessage || '获取设备列表失败'
        console.error(`❌ 获取自有设备列表失败: ${err}`)
        cb([], err)
      }
    })
  }

  private fetchSharedDevices(fid: string, cb: (list: TXIoTDeviceInfo[]) => void): void {
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      cb([])
      return
    }
    dm.getDeviceListSharedWithMe('', {
      onSuccess: (result: TXIoTPageResult<TXIoTDeviceInfo>) => {
        const deviceList = result.dataList || []
        console.info(`✅ 获取分享设备列表成功，共 ${deviceList.length} 台`)
        cb(deviceList)
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        console.warn(`⚠️ 获取分享设备列表失败: ${errorMessage}`)
        cb([])
      }
    })
  }

  private mergeAndApplyDevices(
    ownedList: TXIoTDeviceInfo[],
    sharedList: TXIoTDeviceInfo[],
    ownedError: string | null,
    fid: string
  ): void {
    if (ownedList.length === 0 && ownedError !== null && sharedList.length === 0) {
      console.error(`❌ 加载设备列表失败: ${ownedError}`)
      return
    }
    // 保留旧设备的 online 状态：仅当列表接口未返回 status 字段时沿用旧值，
    // 避免列表先变灰再被状态刷新回来造成闪烁
    const prevOnlineMap = new Map<string, boolean>()
    for (const d of AppState.devices) {
      prevOnlineMap.set(`${d.productId || ''}/${d.deviceName || d.id}`, d.online)
    }
    const mergedDevices = this.buildMergedDeviceList(ownedList, sharedList, prevOnlineMap)
    AppState.devices = mergedDevices
    this.devices = [...AppState.devices]
    console.info(`✅ 成功加载 ${this.devices.length} 台设备（自有: ${ownedList.length}，分享: ${sharedList.length}）`)
    this.persistDevices()
    this.fetchDeviceStatus(fid)
  }

  private buildMergedDeviceList(
    ownedList: TXIoTDeviceInfo[],
    sharedList: TXIoTDeviceInfo[],
    prevOnlineMap: Map<string, boolean>
  ): DeviceModel[] {
    const settings: DeviceSettings = { motionDetection: true, soundAlarm: true, nightVision: true }
    const ownedIds = new Set<string>()
    const mergedDevices: DeviceModel[] = []

    for (const info of ownedList) {
      const key = `${info.deviceId?.productId || ''}/${info.deviceId?.deviceName || ''}`
      ownedIds.add(key)
      mergedDevices.push(this.mapDeviceInfo(info, settings, false, prevOnlineMap))
    }
    for (const info of sharedList) {
      const key = `${info.deviceId?.productId || ''}/${info.deviceId?.deviceName || ''}`
      if (!ownedIds.has(key)) {
        mergedDevices.push(this.mapDeviceInfo(info, settings, true, prevOnlineMap))
      }
    }
    return mergedDevices
  }

  private mapDeviceInfo(
    info: TXIoTDeviceInfo,
    settings: DeviceSettings,
    isShared: boolean,
    prevOnlineMap: Map<string, boolean>
  ): DeviceModel {
    // 在线状态对齐 Android fetchDeviceStatus：直接读取列表接口返回的 info.status.isOnline
    // （分享设备的状态由 getDeviceListSharedWithMe 同样返回）；status 缺失时沿用旧值避免闪烁
    const key = `${info.deviceId?.productId || ''}/${info.deviceId?.deviceName || ''}`
    const online = info.status ? info.status.isOnline : (prevOnlineMap.get(key) ?? false)
    return {
      id: info.deviceId?.deviceName || '',
      name: info.aliasName || info.deviceId?.deviceName || '',
      location: info.roomId || '',
      online: online,
      signal: '强',
      firmware: '',
      addTime: new Date().toISOString(),
      settings: settings,
      productId: info.deviceId?.productId || '',
      deviceName: info.deviceId?.deviceName || '',
      familyId: info.familyId || '',
      roomId: info.roomId || '',
      iconUrl: info.iconUrl || '',
      isShared: isShared
    }
  }

  private persistDevices(): void {
    if (!AppState.currentUser) {
      return
    }
    const context = getContext(this)
    saveDevices(context, AppState.currentUser.id, AppState.devices)
  }

  // ─── Device Status ───────────────────────────────────────────

  fetchDeviceStatus(familyId: string) {
    if (!familyId || this.devices.length === 0) {
      return
    }
    const deviceIdList = this.buildDeviceIdList()
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      return
    }
    console.info(`🔄 开始获取设备在线状态，共 ${deviceIdList.length} 台设备...`)
    // 新版 SDK 不再提供独立的批量状态接口，TXIoTDeviceInfo.status 在设备列表中已直接返回，
    // 这里拉取一次最新设备列表并按设备ID下标对齐生成状态列表
    dm.getDeviceList(familyId, '', {
      onSuccess: (result: TXIoTPageResult<TXIoTDeviceInfo>) => {
        const list = result.dataList || []
        const map: Map<string, TXIoTDeviceStatus> = new Map()
        for (const info of list) {
          const k = `${info.deviceId?.productId || ''}/${info.deviceId?.deviceName || ''}`
          if (info.status) {
            map.set(k, info.status)
          }
        }
        // 仅更新本次返回中含状态的设备；getDeviceList 只含自有设备，
        // 分享设备不在其中，兜底沿用其当前状态而非强制离线
        const statusList: TXIoTDeviceStatus[] = deviceIdList.map((d, i) => {
          const k = `${d.productId}/${d.deviceName}`
          const fallback: TXIoTDeviceStatus =
            { isOnline: this.devices[i]?.online ?? false, onlineDuration: 0, bringOnlineTime: 0 } as TXIoTDeviceStatus
          return map.get(k) || fallback
        })
        if (statusList.length > 0) {
          this.applyDeviceStatus(deviceIdList, statusList)
        }
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        console.warn(`⚠️ 获取设备在线状态失败: ${errorMessage}`)
      }
    })
  }

  private buildDeviceIdList(): TXIoTDeviceId[] {
    return this.devices.map((d: DeviceModel) => {
      const did = new TXIoTDeviceId()
      did.productId = d.productId || ''
      did.deviceName = d.deviceName || d.id
      return did
    })
  }

  private applyDeviceStatus(deviceIdList: TXIoTDeviceId[], statusList: TXIoTDeviceStatus[]): void {
    const statusMap: Map<string, boolean> = new Map()
    for (let i = 0; i < statusList.length && i < deviceIdList.length; i++) {
      const key = `${deviceIdList[i].productId}/${deviceIdList[i].deviceName}`
      statusMap.set(key, statusList[i].isOnline)
    }
    // 不可变更新：仅当 online 真正变化时才生成新数组，避免无谓刷新
    let changed = false
    const newDevices = AppState.devices.map((d: DeviceModel) => {
      const key = `${d.productId || ''}/${d.deviceName || d.id}`
      if (statusMap.has(key)) {
        const newOnline = statusMap.get(key) as boolean
        if (d.online !== newOnline) {
          changed = true
          const updated: DeviceModel = {
            id: d.id,
            name: d.name,
            location: d.location,
            online: newOnline,
            signal: d.signal,
            firmware: d.firmware,
            addTime: d.addTime,
            settings: d.settings,
            productId: d.productId,
            deviceName: d.deviceName,
            familyId: d.familyId,
            roomId: d.roomId,
            iconUrl: d.iconUrl,
            isShared: d.isShared
          }
          return updated
        }
      }
      return d
    })
    if (changed) {
      AppState.devices = newDevices
      this.devices = [...newDevices]
      console.info('✅ 设备在线状态更新完成')
    }
  }

  // ─── Navigation ──────────────────────────────────────────────

  goToAddDevice() {
    router.pushUrl({ url: 'pages/AddDevicePage' })
  }

  goToUserProfile() {
    router.pushUrl({ url: 'pages/UserProfilePage' })
  }

  goToCloudStorage(device: DeviceModel) {
    const productId = device.productId || ''
    const deviceName = device.deviceName || device.id
    if (!productId || !deviceName) {
      this.showToast('设备信息不完整，无法查看云存')
      return
    }
    router.pushUrl({
      url: 'pages/CloudStoragePage',
      params: {
        productId: productId,
        deviceName: deviceName,
        aliasName: device.name || '',
        online: device.online,
        familyId: device.familyId || AppState.currentFamilyId
      }
    })
  }

  // 对齐 Android getDetailEntry：吸顶灯走灯具控制页，摄像头走监控页通道选择
  goToDeviceDetail(device: DeviceModel) {
    if (DeviceHardwareType.isCeilingLamp(device.productId || '')) {
      AppState.currentDevice = device
      router.pushUrl({ url: 'pages/LampDetailPage' })
      return
    }
    this.selectedDeviceForChannels = device
    this.selectedChannels = [0]
    this.showChannelSelector = true
  }

  confirmChannelsAndNavigate() {
    const device = this.selectedDeviceForChannels
    if (!device) {
      animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        this.showChannelSelector = false
      })
      return
    }
    if (this.selectedChannels.length === 0) {
      this.showToast('请至少选择一个通道')
      return
    }
    const sorted = [...this.selectedChannels].sort((a, b) => a - b)
    AppState.currentDevice = device
    AppState.currentChannelList = sorted
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showChannelSelector = false
    })
    console.info(`🎯 准备跳转设备详情，设备: ${device.name}, 通道: ${JSON.stringify(sorted)}`)
    router.pushUrl({ url: 'pages/DeviceDetailPage' })
  }

  toggleChannel(ch: number) {
    const idx = this.selectedChannels.indexOf(ch)
    if (idx >= 0) {
      this.selectedChannels = this.selectedChannels.filter(c => c !== ch)
    } else {
      this.selectedChannels = [...this.selectedChannels, ch]
    }
  }

  private dismissChannelSelector(): void {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showChannelSelector = false
    })
  }

  private dismissFamilySwitch(): void {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showFamilySwitchDialog = false
    })
  }

  // ─── Family Switch ───────────────────────────────────────────

  loadFamilyListAndSwitch() {
    // 打开弹窗前先触发一次静默重拉，新加入/被删除的家庭在最新数据回来后自动刷新弹窗内容
    this.refreshFamilyList(false)
    if (this.familyList && this.familyList.length > 0) {
      this.showFamilySwitchDialog = true
      return
    }
    this.waitAndShowFamilyDialog(6)
  }

  private waitAndShowFamilyDialog(retries: number) {
    setTimeout(() => {
      if (this.familyList && this.familyList.length > 0) {
        this.showFamilySwitchDialog = true
      } else if (retries > 1) {
        this.waitAndShowFamilyDialog(retries - 1)
      } else {
        this.showFamilySwitchDialog = true
      }
    }, 500)
  }

  selectFamily(family: TXIoTFamilyInfo) {
    this.applyFamilySelection(family.familyId, family.name || '')
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showFamilySwitchDialog = false
    })
    this.devices = []
    AppState.devices = []
    this.isLoading = true
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.loadDevicesFromSDK(family.familyId)
      return
    }
    fm.getFamilyList({
      onSuccess: (list: TXIoTFamilyInfo[]) => {
        this.familyList = list
        this.loadDevicesFromSDK(family.familyId)
      },
      onError: (_errorCode: TXIoTErrorCode, _errorMessage: string) => {
        this.loadDevicesFromSDK(family.familyId)
      }
    })
  }

  // ─── Unbind Device ───────────────────────────────────────────

  unbindDevice(device: DeviceModel) {
    const familyId = device.familyId || AppState.currentFamilyId
    const productId = device.productId || ''
    const deviceName = device.deviceName || device.id

    if (!familyId || !productId || !deviceName) {
      this.showToast('设备信息不完整，无法解绑')
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = productId
    deviceId.deviceName = deviceName
    dm.unbindDevice(familyId, deviceId, {
      onSuccess: (_: void) => {
        this.onUnbindResult(true, null, device)
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.onUnbindResult(false, errorMessage, device)
      }
    })
  }

  private onUnbindResult(success: boolean, errorMessage: string | null | undefined, device: DeviceModel): void {
    if (success) {
      AppState.devices = AppState.devices.filter(d => d.id !== device.id)
      this.devices = [...AppState.devices]
      this.persistDevices()
      this.showToast('设备解绑成功')
    } else {
      this.showToast(errorMessage || '设备解绑失败')
    }
    this.showDeleteDialog = false
    this.deleteDeviceId = ''
  }

  // ─── Builder: Top Nav Bar + Family Bar (Blue Gradient Header) ─────

  @Builder
  TopNavBar() {
    Column() {
      // Title row
      Row() {
        Text('我的设备')
          .fontSize(22).fontWeight(FontWeight.Normal).fontColor('#ffffff')
          .layoutWeight(1)

        Row({ space: 10 }) {
          Button() {
            Text('🔔').fontSize(16)
          }
          .width(40)
          .height(40)
          .backgroundColor(AppColor.BgCard)
          .borderRadius(12)
          .onClick(() => router.pushUrl({ url: 'pages/MessageListPage' }))

          Button() {
            Text('+').fontSize(20).fontColor('#006EFF').fontWeight(FontWeight.Normal)
          }
          .width(40)
          .height(40)
          .backgroundColor(AppColor.BgCard)
          .borderRadius(12)
          .onClick(() => this.goToAddDevice())

          Button() {
            Text('👤').fontSize(16)
          }
          .width(40)
          .height(40)
          .backgroundColor(AppColor.BgCard)
          .borderRadius(12)
          .onClick(() => this.goToUserProfile())
        }
      }
      .width('100%').height(48)

      // Family capsule - left aligned
      this.FamilyCapsule()
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: px2vp(this.statusBarHeight) + 8,
      bottom: 16
    })
    .linearGradient({
      angle: 135,
      colors: [['#1A73E8', 0.0], ['#006EFF', 1.0]]
    })
  }

  @Builder
  FamilyCapsule() {
    Row() {
      Row({ space: 6 }) {
        Text('🏠').fontSize(14)
        Text(this.currentFamilyName || '加载中...')
          .fontSize(14)
          .fontWeight(FontWeight.Normal)
          .fontColor('#ffffff')
          .maxLines(1)
          .constraintSize({ maxWidth: 160 })
      }
      .height(36).padding({ left: 14, right: 10 })
      .onClick(() => {
        this.loadFamilyListAndSwitch()
      })

      Column().width(2).height(18).backgroundColor('rgba(255,255,255,0.5)')

      Text('管理')
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.8)')
        .height(36)
        .padding({ left: 10, right: 14 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/FamilyManagePage' })
        })
    }
    .alignSelf(ItemAlign.Start)
    .margin({ top: 12 })
    .backgroundColor('rgba(255,255,255,0.15)').borderRadius(20)
  }

  @Builder
  FamilyBar() {
    // Kept empty - family bar is now integrated into TopNavBar header
  }

  // ─── Builder: Loading View ───────────────────────────────────

  @Builder
  LoadingView() {
    Column({ space: 12 }) {
      LoadingProgress().width(40).height(40).color('#006EFF')
      Text('加载设备列表中...').fontSize(14).fontColor(AppColor.TextSecondary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#F2F4F8')
  }

  // ─── Builder: Empty View ─────────────────────────────────────

  @Builder
  EmptyView() {
    Column({ space: 0 }) {
      // Icon container matching Android style
      Column() {
        Text('📹').fontSize(40)
      }
      .width(100)
      .height(100)
      .borderRadius(28)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [['#E8F0FF', 0.0], ['#D0E4FF', 1.0]]
      })

      Text('暂无设备')
        .attributeModifier(SectionTitleText).margin({ top: 20 })
      Text('点击下方按钮添加您的第一台设备')
        .attributeModifier(CaptionText).margin({ top: 8 })
      Button('添加设备')
        .attributeModifier(PrimaryButton)
        .width(180)
        .height(50)
        .borderRadius(25)
        .margin({ top: 28 })
        .onClick(() => this.goToAddDevice())
    }
    .width('100%')
    .layoutWeight(1)
    .padding(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#F2F4F8')
  }

  // ─── Builder: Device Card ────────────────────────────────────

  // Animation state for device card press
  @State pressedDeviceId: string = ''

  @Builder
  DeviceCardTop(device: DeviceModel) {
    Row() {
      // Device icon with gradient background
      Column() {
        if (device.iconUrl) {
          Image(device.iconUrl).width(32).height(32).objectFit(ImageFit.Contain)
        } else {
          Text('📹').fontSize(22)
        }
      }
      .width(56)
      .height(56)
      .borderRadius(14)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [['#E8F0FF', 0.0], ['#D0E4FF', 1.0]]
      })

      // Name + status
      Column({ space: 8 }) {
        Row({ space: 4 }) {
          Text(device.name)
            .fontSize(16)
            .fontWeight(FontWeight.Normal)
            .fontColor(AppColor.TextPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (device.isShared) {
            Text('分享')
              .fontSize(9)
              .fontColor('#ffffff')
              .padding({
                left: 4,
                right: 4,
                top: 1,
                bottom: 1
              })
              .backgroundColor('rgba(0,110,255,0.7)')
              .borderRadius(4)
          }
        }.width('100%')

        Row({ space: 5 }) {
          Circle().width(7).height(7)
            .fill(device.online ? '#52c41a' : '#C8CDD8')
          Text(device.online ? '在线' : '离线')
            .attributeModifier(CaptionText)
        }
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 14 })

      // Menu button (uses same ContextMenuBuilder pattern as FamilyManagePage)
      Stack() {
        Text('⋮').fontSize(22).fontColor('#C8CDD8').fontWeight(FontWeight.Normal)
      }
      .width(36).height(36)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.currentMenuDevice = device
        }
      })
      .bindMenu(this.deviceMenuBuilder)
    }
    .width('100%').alignItems(VerticalAlign.Center)
  }

  @Builder
  DeviceCardBottom(device: DeviceModel) {
    Column().width('100%').height(1).backgroundColor('#F2F4F8')
      .margin({ top: 10, bottom: 8 })
    Text((device.productId || '') + '/' + (device.deviceName || device.id))
      .fontSize(11).fontColor('#C8CDD8')
      .alignSelf(ItemAlign.Start)
  }

  @Builder
  DeviceCard(device: DeviceModel) {
    Column({ space: 0 }) {
      this.DeviceCardTop(device)
      this.DeviceCardBottom(device)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .backgroundColor(AppColor.BgCard)
    .borderRadius(18)
    .shadow({
      radius: 4,
      color: 'rgba(0,0,0,0.04)',
      offsetX: 0,
      offsetY: 1
    })
    .scale({ x: this.pressedDeviceId === device.id ? 0.97 : 1.0, y: this.pressedDeviceId === device.id ? 0.97 : 1.0 })
    .animation({ duration: 150, curve: Curve.EaseInOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedDeviceId = device.id
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedDeviceId = ''
      }
    })
    .onClick(() => this.goToDeviceDetail(device))
  }

  // ─── Builder: Device List ────────────────────────────────────

  @Builder
  DeviceListView() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      List({ space: 0 }) {
        ForEach(this.devices, (device: DeviceModel) => {
          ListItem() {
            Column() {
              this.DeviceCard(device)
            }
            .padding({
              left: 16,
              right: 16,
              top: 0,
              bottom: 12
            })
          }
        })
        ListItem() {
          Column().height(16)
        }
      }
      .width('100%').layoutWeight(1).backgroundColor('#F2F4F8')
      .padding({ top: 16 })
    }
    .onRefreshing(() => {
      // 以刷新模式加载：不切换 isLoading，数据回来后由 loadDevicesFromSDK 关闭 isRefreshing
      this.loadDevicesFromSDK(undefined, true)
    })
    .layoutWeight(1)
  }

  // ─── Builder: Family Switch Dialog (removed, now uses CommonBottomSheet) ───

  // ─── Builder: Channel Selector Dialog (removed, now uses CommonBottomSheet) ───

  // ─── Builder: Family Manage Sheet removed — now navigates to FamilyManagePage ────

  @Builder
  ChannelGrid() {
    Row() {
      ForEach(this.availableChannels, (ch: number) => {
        Stack() {
          Circle().width(60).height(60)
            .fill(this.selectedChannels.indexOf(ch) >= 0 ? '#1890ff' : '#ffffff')
          Circle()
            .width(60)
            .height(60)
            .stroke(this.selectedChannels.indexOf(ch) >= 0 ? '#1890ff' : AppColor.DividerDashed)
            .strokeWidth(2)
            .fill(Color.Transparent)
          Text(`通道${ch}`).fontSize(14).fontWeight(FontWeight.Normal)
            .fontColor(this.selectedChannels.indexOf(ch) >= 0 ? '#ffffff' : AppColor.TextPrimary)
        }
        .width(60).height(60)
        .onClick(() => this.toggleChannel(ch))
      })
    }
    .width('100%')
    .height(76)
    .padding({ left: 20, right: 20 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  // ─── Builder: Channel Grid (used by CommonBottomSheet) ─────────

  // ─── Builder: Device Context Menu (same ContextMenuBuilder as FamilyManagePage) ─────

  @Builder
  deviceMenuBuilder() {
    ContextMenuBuilder(this.buildDeviceMenuItems())
  }

  /** 按设备类型动态构建菜单（对齐 Android：吸顶灯隐藏通话/云存入口） */
  private buildDeviceMenuItems(): CMenuItem[] {
    const isLamp = this.currentMenuDevice
      ? DeviceHardwareType.isCeilingLamp(this.currentMenuDevice.productId || '')
      : false
    const items: CMenuItem[] = []
    if (!isLamp) {
      items.push(
        {
          text: '视频通话',
          icon: '📹',
          color: '#000000',
          onAction: () => {
            if (this.currentMenuDevice) {
              this.startVideoCall(this.currentMenuDevice)
            }
          }
        } as CMenuItem,
        { separator: true } as CMenuItem,
        {
          text: '语音通话',
          icon: '📞',
          color: '#000000',
          onAction: () => {
            if (this.currentMenuDevice) {
              this.startAudioCall(this.currentMenuDevice)
            }
          }
        } as CMenuItem,
        { separator: true } as CMenuItem
      )
    }
    items.push(
      {
        text: '修改别名',
        icon: '✏️',
        color: '#000000',
        onAction: () => {
          if (this.currentMenuDevice) {
            this.showModifyAliasDialog(this.currentMenuDevice)
          }
        }
      } as CMenuItem,
      { separator: true } as CMenuItem
    )
    if (!isLamp) {
      items.push(
        {
          text: '云存',
          icon: '☁️',
          color: '#000000',
          onAction: () => {
            if (this.currentMenuDevice) {
              this.goToCloudStorage(this.currentMenuDevice)
            }
          }
        } as CMenuItem,
        { separator: true } as CMenuItem
      )
    }
    items.push(
      {
        text: '分享',
        icon: '🔗',
        color: '#000000',
        onAction: () => {
          if (this.currentMenuDevice) {
            this.createShareToken(this.currentMenuDevice)
          }
        }
      } as CMenuItem,
      { separator: true } as CMenuItem,
      {
        text: '解绑设备',
        icon: '🗑',
        color: '#000000',
        onAction: () => {
          if (this.currentMenuDevice) {
            this.deleteDeviceId = this.currentMenuDevice.id
            this.showDeleteDialog = true
          }
        }
      } as CMenuItem
    )
    return items
  }

  private copyShareToken(): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareTokenContent)
    const systemPasteboard = pasteboard.getSystemPasteboard()
    systemPasteboard.setDataSync(pasteData)
    this.showShareTokenDialog = false
    this.showToast('分享码已复制')
  }

  // ─── Builder: Incoming Banner ────────────────────────────────

  @Builder
  IncomingBanner() {
    Column() {
      Row({ space: 12 }) {
        this.BannerAvatar()
        Column({ space: 4 }) {
          Text(this.incomingPeerName)
            .fontSize(15).fontColor('#ffffff').fontWeight(FontWeight.Normal).maxLines(1)
          Text(this.incomingIsVideo ? '邀请你视频通话...' : '邀请你语音通话...')
            .fontSize(12).fontColor('rgba(255,255,255,0.75)').maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)

        Button() {
          Text('📞').fontSize(17).fontColor('#ffffff')
        }
        .width(40)
        .height(40)
        .backgroundColor('#e64c4c')
        .borderRadius(20)
        .onClick(() => this.rejectFromBanner())

        Button() {
          Text('📞').fontSize(17).fontColor('#ffffff')
        }
        .width(40)
        .height(40)
        .backgroundColor('#38c76a')
        .borderRadius(20)
        .onClick(() => this.answerFromBanner())
      }
      .width('100%')
      .padding({
        left: 14,
        right: 14,
        top: 10,
        bottom: 10
      })
      .backgroundColor('rgba(0,0,0,0.55)')
      .borderRadius(14)
      .onClick(() => this.expandIncomingBanner())
    }
    .width('94%').position({ x: '3%', y: 8 }).zIndex(9999)
    .transition(
      TransitionEffect.opacity(0)
        .combine(TransitionEffect.translate({ y: -80 }))
        .animation({ duration: 300, curve: Curve.EaseOut })
    )
  }

  @Builder
  BannerAvatar() {
    if (this.incomingPeerAvatar && this.incomingPeerAvatar.length > 0) {
      Image(this.incomingPeerAvatar)
        .width(46).height(46).borderRadius(8).objectFit(ImageFit.Cover)
    } else {
      Column() {
        Text('👤').fontSize(22)
      }
      .width(46)
      .height(46)
      .borderRadius(8)
      .backgroundColor('#8c7454')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  // ─── Main Build ──────────────────────────────────────────────

  build() {
    Column() {
      this.TopNavBar()
      this.FamilyBar()

      if (this.isLoading) {
        this.LoadingView()
      } else if (this.devices.length === 0) {
        this.EmptyView()
      } else {
        this.DeviceListView()
      }

      CommonBottomSheet({
        show: $showDeleteDialog,
        title: '解绑设备',
        showCaption: false,
        confirmText: '解绑',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          const device = this.devices.find(d => d.id === this.deleteDeviceId)
          if (device) {
            this.unbindDevice(device)
          }
        },
        onCancel: () => {
          this.deleteDeviceId = ''
        }
      }) {
        Column({ space: 12 }) {
          Text(`确定要解绑设备「${this.devices.find(d => d.id === this.deleteDeviceId)?.name || ''}」吗？`)
            .fontSize(15).fontColor(AppColor.TextPrimary)
            .width('100%').textAlign(TextAlign.Center)
          Text('此操作不可撤销，解绑后将无法再控制该设备。')
            .fontSize(13).fontColor(AppColor.TextSecondary)
            .width('100%').textAlign(TextAlign.Center)
        }
        .width('100%').padding({ left: 24, right: 24, top: 8 })
      }

      CommonBottomSheet({
        show: $showFamilySwitchDialog,
        title: '🏠 选择家庭',
        caption: `当前：${this.currentFamilyName}`,
        showCaption: true,
        showConfirm: false,
        cancelText: '取消',
        onCancel: () => {
        }
      }) {
        if (this.familyList.length === 0) {
          Text('暂无家庭')
            .fontSize(16)
            .fontColor(AppColor.TextSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 24, bottom: 24 })
        } else {
          Column() {
            ForEach(this.familyList, (family: TXIoTFamilyInfo) => {
              Row({ space: 14 }) {
                Column() {
                  Text('🏠').fontSize(17)
                }
                .width(40)
                .height(40)
                .borderRadius(20)
                .backgroundColor('#EEF4FF')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Text(family.name || '未命名家庭')
                  .fontSize(15).fontColor(AppColor.TextPrimary).layoutWeight(1).maxLines(1)

                if (family.familyId === AppState.currentFamilyId) {
                  Text('✓')
                    .fontSize(15)
                    .fontColor(AppColor.Brand)
                    .fontWeight(FontWeight.Normal)
                    .width(24)
                    .height(24)
                    .textAlign(TextAlign.Center)
                }
              }
              .width('100%').height(60)
              .padding({ left: 20, right: 20 })
              .onClick(() => this.selectFamily(family))
            }, (family: TXIoTFamilyInfo) => family.familyId)
          }
          .width('100%')
        }
      }

      CommonBottomSheet({
        show: $showChannelSelector,
        title: '选择视频通道',
        caption: `设备：${this.selectedDeviceForChannels?.productId ||
          ''}/${this.selectedDeviceForChannels?.deviceName || this.selectedDeviceForChannels?.id || ''}`,
        showCaption: true,
        confirmText: '确定',
        cancelText: '取消',
        onConfirm: () => {
          this.confirmChannelsAndNavigate()
        },
        onCancel: () => {
          this.selectedChannels = [0]
        }
      }) {
        Column() {
          this.ChannelGrid()
        }
        .width('100%').padding({ top: 12 })
      }

      CommonBottomSheet({
        show: $showAliasDialog,
        title: '修改设备别名',
        caption: `${this.aliasTargetDevice?.productId || ''}/${this.aliasTargetDevice?.deviceName ||
          this.aliasTargetDevice?.id || ''}`,
        showCaption: true,
        confirmText: '保存',
        confirmEnabled: this.aliasInputValue.trim().length > 0,
        cancelText: '取消',
        onConfirm: () => {
          this.confirmModifyAlias()
        }
      }) {
        Column() {
          TextInput({ text: this.aliasInputValue, placeholder: '请输入新的别名' })
            .width('100%')
            .attributeModifier(DialogInputField)
            .onChange((value: string) => {
              this.aliasInputValue = value
            })
        }
        .width('100%').padding({ left: 20, right: 20 })
      }

      CommonBottomSheet({
        show: $showShareTokenDialog,
        title: '🔑 设备分享码',
        caption: '请将此内容发送给对方',
        showCaption: true,
        confirmText: '📋 复制分享码',
        cancelText: '取消',
        onConfirm: () => {
          this.copyShareToken()
        }
      }) {
        Column({ space: 12 }) {
          Scroll() {
            Text(this.shareTokenContent)
              .fontSize(13)
              .fontColor(AppColor.TextPrimary)
              .fontFamily('monospace')
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding(12)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .height(132)
          .backgroundColor(AppColor.BgGray)
          .borderRadius(8)
          .border({ width: 1, color: AppColor.BorderInput, radius: 8 })

          Text('对方在「绑定分享」中粘贴此内容即可绑定设备。')
            .fontSize(13).fontColor(AppColor.TextSecondary)
            .width('100%').textAlign(TextAlign.Center)
        }
        .width('100%').padding({ left: 20, right: 20 })
      }

      if (this.incomingBannerVisible) {
        this.IncomingBanner()
      }
    }
    .width('100%').height('100%').backgroundColor('#F2F4F8')
  }
}
