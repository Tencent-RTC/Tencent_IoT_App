import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import { window } from '@kit.ArkUI'
import { AppState, UserModel } from '../model/AppModel'
import { saveCurrentUser } from '../utils/StorageUtil'
import { TXIoTEngineListener, TXIoTUserSignature, TXIoTErrorCode, TXIoTRegion } from '@tencentcloud/liteavsdk_iot'
import cryptoFramework from '@ohos.security.cryptoFramework'
import util from '@ohos.util'
import { PrimaryHeroButton, PageTitleText, SecondaryText, AppColor } from '../components/AppTheme'

// Sign params interface (consistent with Android SignatureUtil)
interface SignParams {
  AppKey: string;
  Nonce: number;
  RequestId: string;
  Timestamp: number;
  OpenID: string;
}

@Entry
@Component
struct LoginPage {
  // Login form
  @State appKey: string = ''
  @State appSecret: string = ''
  @State selectedRegionIndex: number = 0
  private readonly regionOptions: Array<SelectOption> = [
    { value: '国内' },
    { value: '海外' }
  ]
  @State userId: string = ''
  @State isLoading: boolean = false
  // SDK login listener
  private loginListener: TXIoTEngineListener | null = null

  aboutToAppear(): void {
    this.setupImmersiveMode()
    this.checkLoginState()
  }

  aboutToDisappear(): void {
    this.removeLoginListener()
    this.restoreSystemBar()
  }

  /**
   * Enable immersive full-screen mode (consistent with Android blue status bar)
   * Layout extends behind status bar; gradient header fills the status area
   */
  private setupImmersiveMode(): void {
    try {
      const context = getContext(this)
      window.getLastWindow(context).then((mainWindow: window.Window): void => {
        mainWindow.setWindowLayoutFullScreen(true)
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: '#FFFFFF',
          navigationBarColor: '#FFFFFF',
          navigationBarContentColor: '#000000'
        })
      }).catch((err: Error): void => {
        console.warn('Failed to set immersive mode: ' + JSON.stringify(err))
      })
    } catch (e) {
      console.warn('Failed to get window: ' + JSON.stringify(e))
    }
  }

  /**
   * Restore default system bar when leaving the page
   */
  private restoreSystemBar(): void {
    try {
      const context = getContext(this)
      window.getLastWindow(context).then((mainWindow: window.Window): void => {
        mainWindow.setWindowLayoutFullScreen(false)
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#FFFFFF',
          statusBarContentColor: '#000000',
          navigationBarColor: '#FFFFFF',
          navigationBarContentColor: '#000000'
        })
      }).catch((err: Error): void => {
        console.warn('Failed to restore system bar: ' + JSON.stringify(err))
      })
    } catch (e) {
      console.warn('Failed to get window: ' + JSON.stringify(e))
    }
  }

  private removeLoginListener(): void {
    if (this.loginListener) {
      AppState.engine().removeListener(this.loginListener)
      this.loginListener = null
    }
  }

  private showToast(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  /**
   * Sort params by key and join as query string
   * (consistent with Android SignatureUtil.format)
   */
  private createSortedQueryString(params: SignParams): string {
    const sortedParams = [
      `OpenID=${params.OpenID}`,
      `Timestamp=${params.Timestamp}`,
      `Nonce=${params.Nonce}`,
      `AppKey=${params.AppKey}`,
      `RequestId=${params.RequestId}`
    ]
    return sortedParams.sort().join('&')
  }

  /**
   * HMAC-SHA1 signature, result Base64 encoded
   */
  private async signMessage(message: string, secret: string): Promise<string> {
    const encoder = new util.TextEncoder()
    const keyData = encoder.encodeInto(secret)
    const msgData = encoder.encodeInto(message)

    const mac = cryptoFramework.createMac('SHA1')
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC')
    const symKeyBlob: cryptoFramework.DataBlob = { data: keyData }
    const symKey = await symKeyGenerator.convertKey(symKeyBlob)
    await mac.init(symKey)
    const updateData: cryptoFramework.DataBlob = { data: msgData }
    await mac.update(updateData)
    const result = await mac.doFinal()

    const base64 = new util.Base64Helper()
    return base64.encodeToStringSync(result.data)
  }

  /**
   * Check login state (consistent with Android checkLoginState)
   */
  private checkLoginState(): void {
    const loginUserInfo = AppState.engine().getLoginUserInfo()
    if (loginUserInfo) {
      router.replaceUrl({ url: 'pages/DeviceListPage' })
    }
  }

  /**
   * Validate input fields (consistent with Android: show individual toast)
   */
  private validateInput(): boolean {
    if (!this.userId) {
      this.showToast('请输入UserId')
      return false
    }
    if (!this.appKey) {
      this.showToast('请输入AppKey')
      return false
    }
    if (!this.appSecret) {
      this.showToast('请输入AppSecret')
      return false
    }
    return true
  }

  /**
   * Save current user info
   */
  private async saveUserInfo(): Promise<void> {
    const context = getContext(this)
    const currentUser: UserModel = {
      id: this.userId,
      username: this.userId,
      phone: '',
      appKey: this.appKey,
      appSecret: this.appSecret,
      userId: this.userId
    }
    AppState.currentUser = currentUser
    await saveCurrentUser(context, currentUser)
  }

  /**
   * Register SDK login listener and perform login
   */
  private performSdkLogin(userSignature: TXIoTUserSignature): void {
    this.loginListener = {
      onLoginSuccess: () => {
        console.info('✅ SDK login success')
        this.isLoading = false
        this.removeLoginListener()
        router.replaceUrl({ url: 'pages/DeviceListPage' })
      },
      onLoginFailure: (errCode: TXIoTErrorCode, errMsg: string) => {
        console.error(`❌ SDK login failure: ${errMsg} (code: ${errCode})`)
        this.isLoading = false
        this.removeLoginListener()
        this.showToast(errMsg)
      }
    }
    AppState.engine().addListener(this.loginListener)
    AppState.engine().login(
      this.appKey,
      this.userId,
      userSignature,
      this.selectedRegionIndex === 0 ? TXIoTRegion.DEFAULT : TXIoTRegion.OVERSEAS
    )
    // 登录后注册全局推送监听（内部保证只注册一次）
    AppState.setupPushNotification()
  }

  /**
   * Build TXIoTUserSignature from form data
   */
  private async buildUserSignature(): Promise<TXIoTUserSignature> {
    const timestamp = Math.floor(Date.now() / 1000)
    const nonce = Math.floor(Math.random() * 2147483647) + 1
    const requestId = this.generateUUID()

    const params: SignParams = {
      AppKey: this.appKey,
      Nonce: nonce,
      RequestId: requestId,
      Timestamp: timestamp,
      OpenID: this.userId,
    }

    const sortedQuery = this.createSortedQueryString(params)
    const signature = await this.signMessage(sortedQuery, this.appSecret)

    const userSignature = new TXIoTUserSignature()
    userSignature.requestId = requestId
    userSignature.timestamp = timestamp
    userSignature.nonce = nonce
    userSignature.signature = signature
    return userSignature
  }

  /**
   * Login (consistent with Android LoginActivity.login())
   */
  async handleLogin(): Promise<void> {
    if (!this.validateInput()) {
      return
    }
    if (this.isLoading) {
      return
    }
    this.isLoading = true

    try {
      const userSignature = await this.buildUserSignature()
      await this.saveUserInfo()
      this.performSdkLogin(userSignature)
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err)
      this.showToast(errorMessage)
    } finally {
      this.isLoading = false
    }
  }

  /**
   * Generate UUID (consistent with Android UUID.randomUUID())
   */
  private generateUUID(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0
      const v = c === 'x' ? r : (r & 0x3 | 0x8)
      return v.toString(16)
    })
  }

  /**
   * Header icon with ring background (consistent with Android ic_video_camera)
   */
  @Builder
  HeaderIcon() {
    Stack() {
      Circle()
        .width(80)
        .height(80)
        .fill('rgba(255,255,255,0.2)')
      Image($r('app.media.ic_video_camera'))
        .width(64)
        .height(64)
        .fillColor('#FFFFFF')
    }
    .width(80)
    .height(80)
  }

  /**
   * Header banner (consistent with Android bg_login_header gradient)
   */
  @Builder
  HeaderBanner() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      this.HeaderIcon()

      Text('TXIoTDemo')
        .fontSize(26)
        .fontWeight(FontWeight.Normal)
        .fontColor('#FFFFFF')
        .letterSpacing(0.5)
        .margin({ top: 14 })

      Text('安全守护，智能生活')
        .fontSize(14)
        .fontColor('#CCFFFFFF')
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 64, bottom: 60 })
    .linearGradient({
      direction: GradientDirection.Right,
      colors: [['#1A73E8', 0.0], ['#006EFF', 1.0]]
    })
    .borderRadius({ bottomLeft: 32, bottomRight: 32 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  /**
   * Form field label (consistent with Android field labels)
   */
  @Builder
  FieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(AppColor.TextPrimary)
      .fontWeight(FontWeight.Normal)
      .margin({ bottom: 8 })
      .alignSelf(ItemAlign.Start)
  }

  /**
   * Form input field (consistent with Android bg_login_input style)
   */
  @Builder
  InputField(placeholder: string, text: string, isPassword: boolean, onChange: (val: string) => void) {
    Row() {
      TextInput({ placeholder: placeholder, text: text })
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .border({ width: 0 })
        .fontSize(15)
        .fontColor(AppColor.TextPrimary)
        .placeholderColor('#C8CDD8')
        .type(isPassword ? InputType.Password : InputType.Normal)
        .onChange(onChange)
    }
    .width('100%')
    .height(52)
    .borderRadius(14)
    .backgroundColor('#F7F8FA')
    .border({ width: 1, color: '#E7E8EB', radius: 14 })
    .padding({ left: 16, right: 16 })
  }

  /**
   * Login form title section (consistent with Android card header)
   */
  @Builder
  FormTitle() {
    Text('账号登录')
      .attributeModifier(PageTitleText)
      .margin({ bottom: 6 })
      .alignSelf(ItemAlign.Start)

    Text('请填写以下信息完成登录')
      .fontSize(13)
      .fontColor(AppColor.TextSecondary)
      .margin({ bottom: 28 })
      .alignSelf(ItemAlign.Start)
  }

  /**
   * Login form fields (consistent with Android: UserId → AppKey → AppSecret → Region)
   */
  @Builder
  FormFields() {
    this.FieldLabel('UserId')
    this.InputField('请输入 UserId', this.userId, false, (val: string) => {
      this.userId = val
    })

    Column().height(16)

    this.FieldLabel('AppKey')
    this.InputField('请输入 AppKey', this.appKey, false, (val: string) => {
      this.appKey = val
    })

    Column().height(16)

    this.FieldLabel('AppSecret')
    this.InputField('请输入 AppSecret', this.appSecret, true, (val: string) => {
      this.appSecret = val
    })

    Column().height(16)

    this.FieldLabel('登录地区')
    Select(this.regionOptions)
      .selected(this.selectedRegionIndex)
      .width('100%')
      .height(52)
      .backgroundColor('#F7F8FA')
      .border({ width: 1, color: '#E7E8EB', radius: 14 })
      .borderRadius(14)
      .padding({ left: 16, right: 16 })
      .onSelect((index: number) => {
        this.selectedRegionIndex = index
      })
  }

  /**
   * Login button (consistent with Android bg_primary_button style)
   * 已抽出到 AppTheme.PrimaryHeroButton —— 高 54、字 17、渐变蓝、圆角 14
   */
  @Builder
  LoginButton() {
    Button('登 录')
      .attributeModifier(PrimaryHeroButton)
      .margin({ top: 32 })
      .onClick(() => this.handleLogin())
  }

  /**
   * Login form (consistent with Android: UserId → AppKey → AppSecret → Region)
   */
  @Builder
  LoginForm() {
    this.FormTitle()
    this.FormFields()
    this.LoginButton()
  }

  build() {
    Scroll() {
      Column() {
        // Blue gradient header banner
        this.HeaderBanner()

        // White login card (overlapping the banner bottom, extends to screen bottom)
        Column() {
          this.LoginForm()
        }
        .width('100%')
        .padding({
          left: 28,
          right: 28,
          top: 36,
          bottom: 28
        })
        .backgroundColor(AppColor.BgCard)
        .borderRadius({ topLeft: 24, topRight: 24 })
        .margin({ top: -48 })
        .flexGrow(1)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .backgroundColor(AppColor.BgCard)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(AppColor.BgCard)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}