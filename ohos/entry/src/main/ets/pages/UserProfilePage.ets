/**
 * 个人信息页面 —— 对齐 Android PersonalInfoActivity
 *
 * 结构：渐变头部(返回+标题+头像+昵称) → 白色卡片(账号信息/昵称行/用户ID行) → 退出登录按钮 → 版本号
 */

import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import { AppState, UserModel } from '../model/AppModel'
import { saveCurrentUser } from '../utils/StorageUtil'
import { TXIoTUserInfo } from '@tencentcloud/liteavsdk_iot'
import { AppColor, DialogTitleText, BodyText, CaptionText, GradientNavBar } from '../components/AppTheme'
import { ConfirmDialog } from '../components/ConfirmDialog'

@Entry
@Component
struct UserProfilePage {
  @State userName: string = ''
  @State userId: string = ''
  @State avatarUrl: string = ''
  @State showLogoutDialog: boolean = false

  aboutToAppear() {
    this.loadUserInfo()
  }

  loadUserInfo() {
    const userInfo: TXIoTUserInfo | null = AppState.engine().getLoginUserInfo()
    if (userInfo) {
      this.userName = userInfo.nickName || ''
      this.userId = userInfo.userId || ''
      this.avatarUrl = userInfo.avatarUrl || ''
    }
    // 降级：从 AppState 读取
    if (!this.userName && AppState.currentUser) {
      this.userName = AppState.currentUser.username
    }
    if (!this.userId && AppState.currentUser?.userId) {
      this.userId = AppState.currentUser.userId
    }
  }

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  goBack() {
    router.back()
  }

  async handleLogout() {
    AppState.logout()
    AppState.currentUser = null
    AppState.devices = []
    AppState.currentDevice = null
    const context = getContext(this)
    await saveCurrentUser(context, null)
    this.showToast('已退出登录')
    router.clear()
    router.pushUrl({ url: 'pages/LoginPage' })
  }

  build() {
    Stack() {
      Column() {
        // ===== 顶部渐变导航栏 =====
        GradientNavBar({
          title: '个人信息', onBack: () => {
            this.goBack()
          }
        })

        // ===== 内容区 =====
        Column() {
          // 头像 + 昵称
          Column({ space: 10 }) {
            // 头像
            Stack({ alignContent: Alignment.Center }) {
              // 外圈光晕
              Column()
                .width(84).height(84)
                .borderRadius(42)
                .border({ width: 3, color: '#E8EAF0' })

              // 头像图片
              if (this.avatarUrl.length > 0) {
                Image(this.avatarUrl)
                  .width(72).height(72)
                  .borderRadius(36)
                  .objectFit(ImageFit.Cover)
              } else {
                Column() {
                  Text('👤').fontSize(36)
                }
                .width(72)
                .height(72)
                .borderRadius(36)
                .backgroundColor('#EEF4FF')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
            }

            // 昵称
            Text(this.userName || '未设置昵称')
              .fontSize(20).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 28, bottom: 20 })

          Column() {
            // 分区标题
            Text('账号信息')
              .attributeModifier(CaptionText)
              .width('100%')
              .margin({ bottom: 10 })

            // 昵称行
            Row() {
              Column() {
                Text('👤').fontSize(16)
              }
              .width(36)
              .height(36)
              .borderRadius(8)
              .backgroundColor('#EEF4FF')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Text('昵称')
                .fontSize(15).fontColor(AppColor.TextPrimary)
                .layoutWeight(1)
                .margin({ left: 14 })

              Text(this.userName || '未设置')
                .attributeModifier(BodyText).fontColor(AppColor.TextSecondary)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

              Text('›').fontSize(22).fontColor('#C8CDD8').margin({ left: 6 })
            }
            .width('100%')
            .height(60)
            .padding({ left: 16, right: 16 })
            .backgroundColor(AppColor.BgCard)
            .borderRadius(14)

            // 用户ID行
            Row() {
              Column() {
                Text('🆔').fontSize(16)
              }
              .width(36)
              .height(36)
              .borderRadius(8)
              .backgroundColor('#EEF4FF')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Text('用户ID')
                .fontSize(15).fontColor(AppColor.TextPrimary)
                .layoutWeight(1)
                .margin({ left: 14 })

              Text(this.userId || '未获取')
                .attributeModifier(BodyText).fontColor(AppColor.TextSecondary)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .height(60)
            .padding({ left: 16, right: 16 })
            .margin({ top: 2 })
            .backgroundColor(AppColor.BgCard)
            .borderRadius(14)

            // 退出登录按钮
            Button('退出登录')
              .width('100%')
              .height(54)
              .fontSize(16)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Normal)
              .borderRadius(14)
              .backgroundColor(Color.Transparent)
              .linearGradient({ angle: 135, colors: [['#FF6B6B', 0], ['#FF4444', 1]] })
              .margin({ top: 32 })
              .onClick(() => {
                this.showLogoutDialog = true
              })

            // 版本信息
            Text('IoT Link App')
              .fontSize(12)
              .fontColor('#C8CDD8')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 20 })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 28 })
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#F2F4F8')
      }
      .width('100%').height('100%')
      .backgroundColor('#F2F4F8')

      // 退出确认弹窗
      ConfirmDialog({
        show: $showLogoutDialog,
        title: '退出登录',
        message: '确定要退出登录吗？',
        confirmText: '退出',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
            this.showLogoutDialog = false
          })
          this.handleLogout()
        },
        onCancel: () => {
        }
      })
    }
  }
}
