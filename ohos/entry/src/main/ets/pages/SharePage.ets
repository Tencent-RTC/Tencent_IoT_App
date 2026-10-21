import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import pasteboard from '@ohos.pasteboard'
import { AppState } from '../model/AppModel'
import { TXIoTUserInfo, TXIoTDeviceId, TXIoTErrorCode } from '@tencentcloud/liteavsdk_iot'
import {
  PrimaryButton,
  DangerButton,
  CancelButton,
  DialogTitleText,
  SecondaryText,
  PageTitleText,
  NavBar,
  GradientNavBar,
  AppColor
} from '../components/AppTheme'

interface SharedUser {
  name: string
  id: string
  userId: string
}

@Entry
@Component
struct SharePage {
  @State sharedUsers: SharedUser[] = []
  @State showShareTokenDialog: boolean = false
  @State shareTokenJson: string = ''
  @State showRemoveDialog: boolean = false
  @State removeTarget: SharedUser | null = null
  @State isLoading: boolean = false

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  goBack() {
    router.back()
  }

  aboutToAppear() {
    // 加载已分享用户列表（对应 iOS: family.getDeviceSharedUsers）
    this.loadSharedUsers()
  }

  /**
   * 加载已分享用户列表
   * 对应 iOS: family.getDeviceSharedUsers(deviceId, callback)
   */
  loadSharedUsers() {
    const device = AppState.currentDevice
    if (!device) {
      return
    }
    const familyId = device.familyId || AppState.currentFamilyId
    const productId = device.productId || ''
    const deviceName = device.deviceName || device.id
    if (!familyId || !productId || !deviceName) {
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = productId
    deviceId.deviceName = deviceName

    this.isLoading = true
    dm.getDeviceSharedUsers(deviceId, {
      onSuccess: (users: TXIoTUserInfo[]) => {
        this.isLoading = false
        this.sharedUsers = users.map((u: TXIoTUserInfo): SharedUser => ({
          name: u.nickName || u.userId,
          id: u.userId,
          userId: u.userId
        }))
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoading = false
        console.warn(`⚠️ 获取分享用户列表失败: ${errorMessage}`)
      }
    })
  }

  /**
   * 创建设备分享 Token
   * 对应 iOS: family.createDeviceSharingToken(deviceId) { token, errorCode, errorMessage in ... }
   */
  createShareToken() {
    const device = AppState.currentDevice
    if (!device) {
      this.showToast('设备信息不存在')
      return
    }
    const familyId = device.familyId || AppState.currentFamilyId
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

  /**
   * 确认取消分享
   * 对应 iOS: family.revokeDeviceSharing(deviceId, callback)
   */
  confirmRemoveShare() {
    if (this.removeTarget) {
      const device = AppState.currentDevice
      if (!device) {
        this.showToast('设备信息不存在')
        return
      }
      const productId = device.productId || ''
      const deviceName = device.deviceName || device.id
      const targetUserId = this.removeTarget.userId
      const dm = AppState.engine().getDeviceManager()
      if (!dm) {
        this.showToast('设备管理器未初始化')
        return
      }
      const deviceId = new TXIoTDeviceId()
      deviceId.productId = productId
      deviceId.deviceName = deviceName

      dm.unbindDeviceSharedWithMe(deviceId, {
        onSuccess: (_: void) => {
          const idx = this.sharedUsers.findIndex(u => u.userId === targetUserId)
          if (idx > -1) {
            this.sharedUsers.splice(idx, 1)
          }
          this.removeTarget = null
          this.showRemoveDialog = false
          this.showToast('已取消共享')
        },
        onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
          this.showToast(errorMessage || '取消共享失败')
        }
      })
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      GradientNavBar({
        title: '设备共享管理', onBack: (): void => {
          this.goBack()
        }
      })

      Scroll() {
        Column({ space: 0 }) {
          // 创建分享 Token 区域（对应 iOS: ShareTokenSheet）
          Column() {
            Text('设备分享')
              .fontSize(14).fontColor(AppColor.TextSecondary)
              .width('100%').padding({ left: 5, bottom: 12 })

            Column() {
              Row() {
                // 蓝色图标
                Column() {
                  Text('🔑').fontSize(22)
                }
                .width(48)
                .height(48)
                .borderRadius(24)
                .backgroundColor('#1890ff')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .margin({ right: 15 })

                Text('创建分享 Token')
                  .fontSize(16).fontColor(AppColor.TextPrimary).layoutWeight(1)

                Text('›').fontSize(20).fontColor(AppColor.TextSecondary)
              }
              .width('100%')
              .padding({
                left: 20,
                right: 20,
                top: 18,
                bottom: 18
              })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.createShareToken()
              })
            }
            .backgroundColor(AppColor.BgCard)
            .borderRadius(12)
            .shadow({
              radius: 4,
              color: 'rgba(0,0,0,0.08)',
              offsetX: 0,
              offsetY: 2
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 20 })

          // 共享用户列表
          Column() {
            Text('共享用户列表')
              .fontSize(14).fontColor(AppColor.TextSecondary)
              .width('100%').padding({ left: 5, bottom: 12 })

            Column() {
              if (this.sharedUsers.length === 0) {
                Text('暂无共享用户')
                  .fontSize(14)
                  .fontColor(AppColor.TextSecondary)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 30, bottom: 30 })
              } else {
                ForEach(this.sharedUsers, (user: SharedUser, index: number) => {
                  Row() {
                    // 灰色头像
                    Column() {
                      Text('👤').fontSize(22)
                    }
                    .width(48)
                    .height(48)
                    .borderRadius(24)
                    .backgroundColor('#d0d0d0')
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .margin({ right: 15 })

                    Column({ space: 4 }) {
                      Text(user.name).fontSize(16).fontColor(AppColor.TextPrimary)
                      Text(user.id).fontSize(13).fontColor(AppColor.TextSecondary)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Text('›').fontSize(20).fontColor(AppColor.TextSecondary)
                  }
                  .width('100%')
                  .padding({
                    left: 20,
                    right: 20,
                    top: 18,
                    bottom: 18
                  })
                  .alignItems(VerticalAlign.Center)
                  .border({
                    width: { bottom: index < this.sharedUsers.length - 1 ? 1 : 0 },
                    color: { bottom: '#f0f0f0' }
                  })
                  .onClick(() => {
                    this.removeTarget = user
                    this.showRemoveDialog = true
                  })
                })
              }
            }
            .backgroundColor(AppColor.BgCard)
            .borderRadius(12)
            .shadow({
              radius: 4,
              color: 'rgba(0,0,0,0.08)',
              offsetX: 0,
              offsetY: 2
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 20 })

          Column().height(40)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .backgroundColor(AppColor.BgGray)

      // 创建分享 Token 展示弹窗（对应 iOS: ShareTokenSheet）
      if (this.showShareTokenDialog) {
        Stack() {
          Column()
            .width('100%').height('100%')
            .backgroundColor(AppColor.BgMask)
            .onClick(() => {
              this.showShareTokenDialog = false;
              this.shareTokenJson = ''
            })

          Column({ space: 16 }) {
            Text('设备分享 Token')
              .attributeModifier(DialogTitleText)

            Text('🔑').fontSize(50)

            // Token 内容展示区
            Text(this.shareTokenJson)
              .fontSize(13)
              .fontColor(AppColor.TextPrimary)
              .fontFamily('monospace')
              .width('100%')
              .padding(12)
              .backgroundColor(AppColor.BgGray)
              .border({ width: 1, color: AppColor.DividerDashed, radius: 8 })
              .textAlign(TextAlign.Start)

            // 复制按钮
            Button() {
              Row({ space: 6 }) {
                Text('📋').fontSize(14)
                Text('复制分享内容').fontSize(15).fontColor('#ffffff').fontWeight(FontWeight.Normal)
              }
            }
            .attributeModifier(PrimaryButton)
            .onClick(() => {
              const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareTokenJson)
              const systemPasteboard = pasteboard.getSystemPasteboard()
              systemPasteboard.setDataSync(pasteboardData)
              this.showToast('已复制到剪贴板')
            })

            Text('请将此内容发送给对方，对方在「绑定分享」中粘贴此内容即可绑定设备。')
              .fontSize(13).fontColor(AppColor.TextSecondary).textAlign(TextAlign.Center)

            Button('完成')
              .attributeModifier(CancelButton)
              .onClick(() => {
                this.showShareTokenDialog = false;
                this.shareTokenJson = ''
              })
          }
          .width('85%').padding(28)
          .backgroundColor(AppColor.BgCard).borderRadius(12)
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 }).zIndex(100)
      }

      // 取消共享弹窗
      if (this.showRemoveDialog) {
        Stack() {
          Column()
            .width('100%').height('100%')
            .backgroundColor(AppColor.BgMask)
            .onClick(() => {
              this.showRemoveDialog = false
            })

          Column({ space: 0 }) {
            Text('取消共享')
              .attributeModifier(DialogTitleText)
              .margin({ bottom: 12 })
            Text('确定要取消该用户的设备共享权限吗？')
              .attributeModifier(SecondaryText).textAlign(TextAlign.Center)
              .margin({ bottom: 24 })
            Row({ space: 12 }) {
              Button('取消')
                .attributeModifier(CancelButton).layoutWeight(1)
                .onClick(() => {
                  this.showRemoveDialog = false
                })
              Button('确定')
                .attributeModifier(DangerButton).layoutWeight(1)
                .onClick(() => this.confirmRemoveShare())
            }
            .width('100%')
          }
          .width('85%')
          .padding(30)
          .backgroundColor(AppColor.BgCard)
          .borderRadius(12)
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.BgGray)
  }
}
