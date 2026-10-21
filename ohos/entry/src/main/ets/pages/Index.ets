import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import { AppState } from '../model/AppModel'
import { getCurrentUser, getDevices } from '../utils/StorageUtil'
import { TXIoTEngineListener, TXIoTUserSignature, TXIoTErrorCode } from '@tencentcloud/liteavsdk_iot'
import cryptoFramework from '@ohos.security.cryptoFramework'
import util from '@ohos.util'
import { AppColor } from '../components/AppTheme'

@Entry
@Component
struct SplashPage {
  @State isLoading: boolean = true

  async aboutToAppear() {
    // 检查登录状态
    const context = getContext(this)
    const user = await getCurrentUser(context)
    if (user) {
      AppState.currentUser = user
      AppState.devices = await getDevices(context, user.id)

      // 使用 SDK getLoginUserInfo 判断是否已登录（对应 iOS: UserManager.checkLoginValid()）
      // 注意：如果签名已过期，SDK 会通过 onUserSignatureExpired 回调通知
      const loginUserInfo = AppState.engine().getLoginUserInfo()
      if (loginUserInfo) {
        // SDK 已登录，直接跳转
        console.info('✅ SDK 已登录，直接跳转')
        router.replaceUrl({ url: 'pages/DeviceListPage' })
      } else {
        // SDK 未登录，尝试使用保存的凭据重新登录
        try {
          const appKey = AppState.currentUser?.appKey ?? ''
          const appSecret = AppState.currentUser?.appSecret ?? ''
          const userId = AppState.currentUser?.userId ?? ''

          if (appKey && appSecret && userId) {
            // 构造签名并调用 SDK login（对应 iOS: UserManager.login()）
            const timestamp = Math.floor(Date.now() / 1000)
            const nonce = Math.floor(Math.random() * 2147483647) + 1
            const requestId = `${timestamp}-${nonce}`

            const sortedQuery = [
              `AppKey=${appKey}`,
              `Nonce=${nonce}`,
              `RequestId=${requestId}`,
              `Timestamp=${timestamp}`,
              `OpenID=${userId}`
            ].sort().join('&')

            const encoder = new util.TextEncoder()
            const keyData = encoder.encodeInto(appSecret)
            const msgData = encoder.encodeInto(sortedQuery)
            const mac = cryptoFramework.createMac('SHA1')
            const symKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC')
            const symKeyBlob: cryptoFramework.DataBlob = { data: keyData }
            const symKey = await symKeyGenerator.convertKey(symKeyBlob)
            await mac.init(symKey)
            const updateData: cryptoFramework.DataBlob = { data: msgData }
            await mac.update(updateData)
            const result = await mac.doFinal()
            const base64 = new util.Base64Helper()
            const signature = base64.encodeToStringSync(result.data)

            const userSignature = new TXIoTUserSignature()
            userSignature.requestId = requestId
            userSignature.timestamp = timestamp
            userSignature.nonce = nonce
            userSignature.signature = signature

            // 注册登录结果监听器
            const loginListener: TXIoTEngineListener = {
              onLoginSuccess: () => {
                console.info('✅ 自动登录成功')
                AppState.engine().removeListener(loginListener)
                router.replaceUrl({ url: 'pages/DeviceListPage' })
              },
              onLoginFailure: (errCode: TXIoTErrorCode, errMsg: string) => {
                console.error(`❌ 自动登录失败: ${errMsg}`)
                AppState.engine().removeListener(loginListener)
                router.replaceUrl({ url: 'pages/LoginPage' })
              }
            }
            AppState.engine().addListener(loginListener)
            AppState.engine().login(appKey, userId, userSignature)
            // 登录后注册全局推送监听（内部保证只注册一次）
            AppState.setupPushNotification()
          } else {
            router.replaceUrl({ url: 'pages/LoginPage' })
          }
        } catch (err) {
          console.error('❌ 自动登录失败:', err)
          router.replaceUrl({ url: 'pages/LoginPage' })
        }
      }
    } else {
      router.replaceUrl({ url: 'pages/LoginPage' })
    }
  }

  build() {
    Column() {
      LoadingProgress()
        .width(60)
        .height(60)
        .color('#1890ff')
      Text('TXIoTDemo')
        .fontSize(24)
        .fontWeight(FontWeight.Normal)
        .fontColor(AppColor.TextPrimary)
        .margin({ top: 20 })
      Text('安全守护，智能生活')
        .fontSize(14)
        .fontColor(AppColor.TextSecondary)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColor.BgGray)
  }
}