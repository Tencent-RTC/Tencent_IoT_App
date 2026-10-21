import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import { AppState, DeviceModel } from '../model/AppModel'
import { TXIoTDeviceId, TXIoTErrorCode } from '@tencentcloud/liteavsdk_iot'
import {
  PageTitleText,
  SectionTitleText,
  BodyText,
  NavBar,
  GradientNavBar,
  CompactInputField,
  AppColor
} from '../components/AppTheme'

@Entry
@Component
struct DevicePropertiesPage {
  @State device: DeviceModel | null = null
  @State propertiesJson: string = ''
  @State isLoadingProps: boolean = false
  @State aliasName: string = ''
  @State isSavingAlias: boolean = false

  aboutToAppear() {
    this.device = AppState.currentDevice
    this.aliasName = this.device?.name || ''
    this.loadProperties()
  }

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  goBack() {
    router.back()
  }

  getFamilyId(): string {
    return AppState.currentFamilyId
  }

  loadProperties() {
    const device = this.device
    if (!device) {
      return
    }
    const fid = this.getFamilyId()
    const pid = device.productId || ''
    const dn = device.deviceName || device.id
    if (!fid || !pid || !dn) {
      this.showToast('设备信息不完整')
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = pid
    deviceId.deviceName = dn
    this.isLoadingProps = true
    dm.getProperties(deviceId, {
      onSuccess: (propertiesJson: string) => {
        this.isLoadingProps = false
        this.propertiesJson = propertiesJson
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoadingProps = false
        this.showToast(errorMessage || '获取属性失败')
      }
    })
  }

  saveAliasName() {
    const name = this.aliasName.trim()
    if (!name) {
      return
    }
    const device = this.device
    if (!device) {
      return
    }
    const pid = device.productId || ''
    const dn = device.deviceName || device.id
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = pid
    deviceId.deviceName = dn
    this.isSavingAlias = true
    dm.modifyAliasName(deviceId, name, {
      onSuccess: (_: void) => {
        this.isSavingAlias = false
        this.showToast('别名已更新为「' + name + '」')
        // 同步更新本地设备名称
        if (this.device) {
          const updated: DeviceModel = {
            id: this.device.id,
            name: name,
            location: this.device.location,
            online: this.device.online,
            signal: this.device.signal,
            firmware: this.device.firmware,
            addTime: this.device.addTime,
            settings: this.device.settings,
            productId: this.device.productId,
            deviceName: this.device.deviceName,
            familyId: this.device.familyId,
            roomId: this.device.roomId,
            iconUrl: this.device.iconUrl
          }
          this.device = updated
          AppState.currentDevice = updated
        }
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isSavingAlias = false
        this.showToast(errorMessage || '修改失败')
      }
    })
  }

  build() {
    Column() {
      // 顶部导航栏
      GradientNavBar({
        title: '设备属性', onBack: (): void => {
          this.goBack()
        }
      })

      Scroll() {
        Column({ space: 0 }) {
          // 别名卡片
          Column({ space: 0 }) {
            Row({ space: 8 }) {
              Text('✏️').fontSize(16)
              Text('设备别名')
                .fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 14,
              bottom: 10
            })

            Row({ space: 12 }) {
              TextInput({ placeholder: '输入设备别名', text: this.aliasName })
                .layoutWeight(1)
                .height(44)
                .fontSize(15)
                .fontColor(AppColor.TextPrimary)
                .backgroundColor(AppColor.BgGray)
                .borderRadius(8)
                .onChange(val => {
                  this.aliasName = val
                })

              if (this.isSavingAlias) {
                Text('保存中...').fontSize(14).fontColor(AppColor.TextSecondary)
              } else {
                Button('保存')
                  .height(40)
                  .fontSize(14)
                  .fontColor('#ffffff')
                  .fontWeight(FontWeight.Normal)
                  .backgroundColor(this.aliasName.trim() ? '#1890ff' : 'rgba(24,144,255,0.4)')
                  .borderRadius(8)
                  .padding({ left: 16, right: 16 })
                  .enabled(this.aliasName.trim().length > 0)
                  .onClick(() => this.saveAliasName())
              }
            }
            .width('100%').padding({ left: 16, right: 16, bottom: 16 })
          }
          .backgroundColor(AppColor.BgCard).borderRadius(12)
          .shadow({
            radius: 4,
            color: 'rgba(0,0,0,0.06)',
            offsetX: 0,
            offsetY: 2
          })
          .margin({ left: 16, right: 16, top: 16 })

          // 属性卡片
          Column({ space: 0 }) {
            Row() {
              Row({ space: 8 }) {
                Text('📋').fontSize(16)
                Text('设备属性')
                  .fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
              }
              .layoutWeight(1)

              Button() {
                Row({ space: 4 }) {
                  if (this.isLoadingProps) {
                    Text('刷新中...').fontSize(13).fontColor('#1890ff')
                  } else {
                    Text('↻').fontSize(16).fontColor('#1890ff')
                    Text('刷新').fontSize(13).fontColor('#1890ff')
                  }
                }
              }
              .height(32)
              .backgroundColor(Color.Transparent)
              .padding({ left: 8, right: 8 })
              .enabled(!this.isLoadingProps)
              .onClick(() => this.loadProperties())
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 14,
              bottom: 10
            })

            if (!this.propertiesJson && !this.isLoadingProps) {
              Column({ space: 10 }) {
                Text('🔍').fontSize(40)
                Text('点击刷新获取设备属性').fontSize(14).fontColor(AppColor.TextSecondary)
              }
              .width('100%').padding({ top: 30, bottom: 30 })
              .alignItems(HorizontalAlign.Center)
            } else if (this.isLoadingProps) {
              Column({ space: 10 }) {
                Text('⏳').fontSize(40)
                Text('获取中...').fontSize(14).fontColor(AppColor.TextSecondary)
              }
              .width('100%').padding({ top: 30, bottom: 30 })
              .alignItems(HorizontalAlign.Center)
            } else {
              Text(this.propertiesJson)
                .fontSize(12)
                .fontColor(AppColor.TextPrimary)
                .fontFamily('monospace')
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 16 })
                .backgroundColor(AppColor.BgGray)
                .borderRadius(8)
                .margin({ left: 16, right: 16, bottom: 16 })
            }
          }
          .backgroundColor(AppColor.BgCard).borderRadius(12)
          .shadow({
            radius: 4,
            color: 'rgba(0,0,0,0.06)',
            offsetX: 0,
            offsetY: 2
          })
          .margin({ left: 16, right: 16, top: 16 })

          // 基本信息卡片
          Column({ space: 0 }) {
            Row({ space: 8 }) {
              Text('ℹ️').fontSize(16)
              Text('基本信息')
                .fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 14,
              bottom: 10
            })

            // 产品 ID
            Row() {
              Text('产品 ID').fontSize(14).fontColor(AppColor.TextSecondary).width(80)
              Text(this.device?.productId || '-')
                .fontSize(14).fontColor(AppColor.TextPrimary).layoutWeight(1).maxLines(1)
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
            .border({ width: { bottom: 1 }, color: { bottom: '#f0f0f0' } })

            // 设备名称
            Row() {
              Text('设备名称').fontSize(14).fontColor(AppColor.TextSecondary).width(80)
              Text(this.device?.deviceName || '-')
                .fontSize(14).fontColor(AppColor.TextPrimary).layoutWeight(1).maxLines(1)
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
            .border({ width: { bottom: 1 }, color: { bottom: '#f0f0f0' } })

            // 显示名称
            Row() {
              Text('显示名称').fontSize(14).fontColor(AppColor.TextSecondary).width(80)
              Text(this.device?.name || '-')
                .fontSize(14).fontColor(AppColor.TextPrimary).layoutWeight(1).maxLines(1)
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
          }
          .backgroundColor(AppColor.BgCard).borderRadius(12)
          .shadow({
            radius: 4,
            color: 'rgba(0,0,0,0.06)',
            offsetX: 0,
            offsetY: 2
          })
          .margin({
            left: 16,
            right: 16,
            top: 16,
            bottom: 24
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .backgroundColor(AppColor.BgGray)
    }
    .width('100%').height('100%')
    .backgroundColor(AppColor.BgGray)
  }
}
