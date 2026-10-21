import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import window from '@ohos.window'
import { AppState, DeviceModel } from '../model/AppModel'
import {
  TXIoTDeviceId,
  TXIoTErrorCode,
  TXIoTEngineListener,
  TXIoTPushMessage,
  TXIoTPushMessageSubType,
  TXIoTPushMessageType
} from '@tencentcloud/liteavsdk_iot'
import { AppColor } from '../components/AppTheme'

// 物模型属性 ID（对齐 Android LampDetailActivity 常量）
const PROP_POWER_SWITCH: string = 'power_switch'
const PROP_BRIGHTNESS: string = 'brightness'
const PROP_COLOR_TEMP: string = 'color_temp'
const PROP_LIGHT_MODE: string = 'light_mode'

const COLOR_TEMP_MIN: number = 2700
const COLOR_TEMP_MAX: number = 6500

interface SceneMode {
  id: number
  name: string
  icon: string
}

// 场景模式（对齐 Android light_mode 枚举值与文案）
const SCENE_MODES: SceneMode[] = [
  { id: 0, name: '手动', icon: '🔧' },
  { id: 1, name: '阅读', icon: '📖' },
  { id: 2, name: '休闲', icon: '☕' },
  { id: 3, name: '夜灯', icon: '🌙' }
]

@Entry
@Component
struct LampDetailPage {
  @State device: DeviceModel | null = null
  @State isLoading: boolean = false
  @State isRefreshing: boolean = false
  @State isOnline: boolean = false
  @State powerOn: boolean = false
  @State brightnessValue: number = 80
  @State colorTemp: number = 4000
  @State lightMode: number = 0
  @StorageProp('statusBarHeight') statusBarHeight: number = 48

  private engineListener: TXIoTEngineListener = {
    onReceivePushMessage: (pushMessage: TXIoTPushMessage): void => {
      this.handlePushMessage(pushMessage)
    }
  }

  private setupImmersiveStatusBar(): void {
    const context = getContext(this) as Context
    window.getLastWindow(context, (err, win) => {
      if (err.code) {
        console.error(`LampDetailPage 状态栏设置失败: ${JSON.stringify(err)}`)
        return
      }
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#ffffff'
      })
      win.setWindowLayoutFullScreen(true)
      const avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      AppStorage.setOrCreate<number>('statusBarHeight', avoidArea.topRect.height)
    })
  }

  aboutToAppear() {
    this.setupImmersiveStatusBar()
    this.device = AppState.currentDevice
    this.isOnline = this.device?.online === true
    AppState.engine().addListener(this.engineListener)
    this.loadProperties(false)
  }

  aboutToDisappear() {
    AppState.engine().removeListener(this.engineListener)
  }

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  goBack() {
    router.back()
  }

  private buildDeviceId(): TXIoTDeviceId | null {
    const device = this.device
    if (!device) {
      return null
    }
    const productId = device.productId || ''
    const deviceName = device.deviceName || device.id
    if (!productId || !deviceName) {
      return null
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = productId
    deviceId.deviceName = deviceName
    return deviceId
  }

  private isDeviceOnline(): boolean {
    return this.isOnline
  }

  private handlePushMessage(pushMessage: TXIoTPushMessage): void {
    if (pushMessage.type !== TXIoTPushMessageType.STATUS_CHANGE) {
      return
    }
    const pushedDeviceId = pushMessage.deviceId
    const currentDeviceId = this.buildDeviceId()
    if (!pushedDeviceId || !currentDeviceId ||
      pushedDeviceId.productId !== currentDeviceId.productId ||
      pushedDeviceId.deviceName !== currentDeviceId.deviceName) {
      return
    }
    this.isOnline = pushMessage.subType === TXIoTPushMessageSubType.ONLINE
  }

  /** 拉取物模型属性（对齐 Android loadProperties / onRefresh） */
  loadProperties(isRefresh: boolean): void {
    const deviceId = this.buildDeviceId()
    if (!deviceId) {
      this.showToast('设备信息不完整')
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    if (isRefresh) {
      this.isRefreshing = true
    } else {
      this.isLoading = true
    }
    dm.getProperties(deviceId, {
      onSuccess: (propertiesJson: string) => {
        this.parseProperties(propertiesJson)
        this.isLoading = false
        this.isRefreshing = false
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoading = false
        this.isRefreshing = false
        this.showToast(`获取属性失败：${errorMessage}`)
      }
    })
  }

  private asPropertyMap(value: Object | null | undefined): Record<string, Object> | null {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return null
    }
    return value as Record<string, Object>
  }

  private extractProperties(propertiesJson: string): Record<string, Object> | null {
    try {
      const root = this.asPropertyMap(JSON.parse(propertiesJson) as Object)
      if (!root) {
        return null
      }
      const container = this.asPropertyMap(root['properties']) ||
        this.asPropertyMap(root['data']) || root
      return this.asPropertyMap(container['Reported']) ||
        this.asPropertyMap(container['reported']) || container
    } catch (err) {
      console.error(`LampDetailPage 属性解析失败: ${err}`)
      return null
    }
  }

  private readInteger(properties: Record<string, Object>, propertyId: string): number | null {
    const value = properties[propertyId]
    if (typeof value === 'number') {
      return Number.isFinite(value) ? Math.round(value) : null
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0
    }
    if (typeof value === 'string') {
      const parsed = Number(value)
      return Number.isFinite(parsed) && Number.isInteger(parsed) ? parsed : null
    }
    return null
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max)
  }

  private applyPropertyValue(propertyId: string, value: number): void {
    if (propertyId === PROP_POWER_SWITCH) {
      this.powerOn = value !== 0
    } else if (propertyId === PROP_BRIGHTNESS) {
      this.brightnessValue = this.clamp(value, 1, 100)
    } else if (propertyId === PROP_COLOR_TEMP) {
      this.colorTemp = this.clamp(value, COLOR_TEMP_MIN, COLOR_TEMP_MAX)
    } else if (propertyId === PROP_LIGHT_MODE) {
      this.lightMode = this.clamp(value, 0, 3)
    }
  }

  /** 兼容 Android 端的 properties、data、顶层属性及 Reported 响应结构。 */
  private parseProperties(propertiesJson: string): void {
    const properties = this.extractProperties(propertiesJson)
    if (!properties) {
      return
    }
    const powerSwitch = this.readInteger(properties, PROP_POWER_SWITCH)
    if (powerSwitch !== null) {
      this.applyPropertyValue(PROP_POWER_SWITCH, powerSwitch)
    }
    const brightness = this.readInteger(properties, PROP_BRIGHTNESS)
    if (brightness !== null) {
      this.applyPropertyValue(PROP_BRIGHTNESS, brightness)
    }
    const colorTemp = this.readInteger(properties, PROP_COLOR_TEMP)
    if (colorTemp !== null) {
      this.applyPropertyValue(PROP_COLOR_TEMP, colorTemp)
    }
    const lightMode = this.readInteger(properties, PROP_LIGHT_MODE)
    if (lightMode !== null) {
      this.applyPropertyValue(PROP_LIGHT_MODE, lightMode)
    }
  }

  /** 下发单项物模型指令，并与 Android 一样立即刷新本地 UI。 */
  sendCommand(propertyId: string, value: number): void {
    if (!this.isDeviceOnline()) {
      this.showToast('设备已离线')
      return
    }
    const deviceId = this.buildDeviceId()
    if (!deviceId) {
      this.showToast('设备信息不完整')
      return
    }
    const normalizedValue = Math.round(value)
    this.applyPropertyValue(propertyId, normalizedValue)
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const command: Record<string, number> = {}
    command[propertyId] = normalizedValue
    dm.sendCommand(deviceId, JSON.stringify(command), {
      onSuccess: (_response: string) => {
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(`指令发送失败：${errorMessage}`)
      }
    })
  }

  /** 滑条拖动结束或点击时才下发指令（对齐 Android onStopTrackingTouch）。 */
  private onSliderChange(propertyId: string, value: number, mode: SliderChangeMode): void {
    const normalizedValue = Math.round(value)
    this.applyPropertyValue(propertyId, normalizedValue)
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.sendCommand(propertyId, normalizedValue)
    }
  }

  build() {
    Column() {
      // 顶部导航栏：尺寸、渐变和状态胶囊对齐 Android LampDetailActivity。
      Row() {
        Button() {
          Text('←').fontSize(22).fontColor('#ffffff')
        }
        .width(44).height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.goBack())

        Text(this.device?.name || '')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 5 }) {
          Circle()
            .width(6).height(6)
            .fill(this.isOnline ? '#1AAD19' : '#999999')
          Text(this.isOnline ? '在线' : '离线')
            .fontSize(12).fontColor('#ffffff')
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor('rgba(255,255,255,0.18)')
        .borderRadius(20)
        .margin({ right: 4 })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: px2vp(this.statusBarHeight), bottom: 0 })
      .alignItems(VerticalAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [[AppColor.BrandStart, 0.0], [AppColor.BrandEnd, 1.0]]
      })

      // 下拉刷新 + 内容区
      Refresh({ refreshing: $$this.isRefreshing }) {
        Scroll() {
          Column({ space: 16 }) {
            if (this.isLoading) {
              Column({ space: 10 }) {
                LoadingProgress().width(32).height(32).color('#006EFF')
                Text('加载中...').fontSize(14).fontColor(AppColor.TextSecondary)
              }
              .width('100%')
              .padding({ top: 40, bottom: 40 })
              .alignItems(HorizontalAlign.Center)
            }

            // 电源开关卡片
            Row() {
              Stack() {
                Circle()
                  .width(52).height(52)
                  .fill(this.powerOn ? '#E8F3FF' : '#F0F0F0')
                Text('💡')
                  .fontSize(24)
                  .opacity(this.powerOn ? 1.0 : 0.4)
              }
              .width(52).height(52)

              Column({ space: 4 }) {
                Text('电源开关')
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
                Text(this.powerOn ? '已开启' : '已关闭')
                  .fontSize(13)
                  .fontColor(this.powerOn ? '#006EFF' : AppColor.TextSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 14 })

              Toggle({ type: ToggleType.Switch, isOn: this.powerOn })
                .selectedColor('#006EFF')
                .enabled(this.isDeviceOnline())
                .onChange((isOn: boolean) => {
                  if (this.isDeviceOnline() && isOn !== this.powerOn) {
                    this.sendCommand(PROP_POWER_SWITCH, isOn ? 1 : 0)
                  }
                })
            }
            .width('100%')
            .padding(16)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(AppColor.BgCard)
            .borderRadius(12)
            .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
            .opacity(this.isDeviceOnline() ? 1.0 : 0.6)

            // 亮度卡片
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text('🔆').fontSize(18)
                Text('亮度')
                  .fontSize(15).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
              }
              Row() {
                Slider({
                  value: this.brightnessValue,
                  min: 1,
                  max: 100,
                  step: 1,
                  style: SliderStyle.OutSet
                })
                  .layoutWeight(1)
                  .blockColor('#006EFF')
                  .trackColor('#E0E0E0')
                  .selectedColor('#006EFF')
                  .enabled(this.isDeviceOnline())
                  .onChange((value: number, mode: SliderChangeMode) => {
                    this.onSliderChange(PROP_BRIGHTNESS, value, mode)
                  })
                Text(`${Math.round(this.brightnessValue)}%`)
                  .fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
                  .width(48)
                  .textAlign(TextAlign.End)
                  .margin({ left: 12 })
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(AppColor.BgCard)
            .borderRadius(12)
            .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
            .opacity(this.isDeviceOnline() ? 1.0 : 0.6)

            // 色温卡片
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text('🌡️').fontSize(18)
                Text('色温')
                  .fontSize(15).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
              }
              Row() {
                Slider({
                  value: this.colorTemp,
                  min: COLOR_TEMP_MIN,
                  max: COLOR_TEMP_MAX,
                  step: 100,
                  style: SliderStyle.OutSet
                })
                  .layoutWeight(1)
                  .blockColor('#006EFF')
                  .trackColor('#E0E0E0')
                  .selectedColor('#006EFF')
                  .enabled(this.isDeviceOnline())
                  .onChange((value: number, mode: SliderChangeMode) => {
                    this.onSliderChange(PROP_COLOR_TEMP, value, mode)
                  })
                Text(`${Math.round(this.colorTemp)}K`)
                  .fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
                  .width(56)
                  .textAlign(TextAlign.End)
                  .margin({ left: 12 })
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(AppColor.BgCard)
            .borderRadius(12)
            .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
            .opacity(this.isDeviceOnline() ? 1.0 : 0.6)

            // 场景模式卡片
            Column({ space: 12 }) {
              Row({ space: 8 }) {
                Text('🎬').fontSize(18)
                Text('场景模式')
                  .fontSize(15).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
              }
              Row({ space: 10 }) {
                ForEach(SCENE_MODES, (scene: SceneMode) => {
                  Column({ space: 6 }) {
                    Text(scene.icon).fontSize(18)
                    Text(scene.name)
                      .fontSize(12)
                      .fontColor(this.lightMode === scene.id ? '#006EFF' : AppColor.TextPrimary)
                  }
                  .layoutWeight(1)
                  .padding({ top: 12, bottom: 12 })
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor(this.lightMode === scene.id ? '#E8F3FF' : '#F7F8FA')
                  .borderRadius(10)
                  .border({
                    width: 1,
                    color: this.lightMode === scene.id ? '#006EFF' : Color.Transparent
                  })
                  .enabled(this.isDeviceOnline())
                  .onClick(() => {
                    if (this.isDeviceOnline() && this.lightMode !== scene.id) {
                      this.sendCommand(PROP_LIGHT_MODE, scene.id)
                    }
                  })
                }, (scene: SceneMode) => scene.id.toString())
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(AppColor.BgCard)
            .borderRadius(12)
            .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
            .opacity(this.isDeviceOnline() ? 1.0 : 0.6)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
      .layoutWeight(1)
      .onRefreshing(() => {
        this.loadProperties(true)
      })
    }
    .width('100%').height('100%')
    .backgroundColor('#F2F4F8')
  }
}
