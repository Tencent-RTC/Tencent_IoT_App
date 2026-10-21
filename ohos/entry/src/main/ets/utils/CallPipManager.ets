/**
 * CallPipManager.ets
 *
 * 音视频/语音通话画中画（PiP）管理器。
 *
 * 背景：HarmonyOS 系统相机会在应用退后台后回收采集能力（CAMERA 权限为 inuse 级别，
 * BackgroundMode 长时任务也不含相机类型），导致视频通话切后台后摄像头采集与视频推流中断。
 * 官方对通话场景的解决方案是画中画：应用处于画中画态时视为前台可见。
 * - 视频通话：PiP 接管远端渲染 XComponent，相机采集与推流持续；
 * - 语音通话：PiP 接管占位 XComponent 并叠加自定义通话信息浮层，后台通话面板保持可达。
 * 本管理器与 CallBackgroundTaskManager（VOIP 长时任务，保进程与音频）互补。
 *
 * 设计：独立单例，不依赖 CallManager/CallPage。
 * - 通话侧仅在通话开始时调用 prepare()、结束时调用 release()；
 * - PiP 控制面板动作（挂断/麦克风/摄像头）通过 PipActionHandler 回调反向通知，由通话侧自行映射；
 * - 页面侧只需把对应 XComponentController 传给相应 XComponent。
 */

import { BuilderNode, FrameNode, NodeController, PiPWindow, UIContext } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import common from '@ohos.app.ability.common'

// 说明：XComponentController 为 ArkUI 全局声明类型（component/xcomponent.d.ts），无需 import。

/** 语音通话 PiP 占位 XComponent 的 id（无 native 插件，仅作 surface 载体） */
export const AUDIO_PIP_VIEW_ID = 'iot_call_audio_pip_stub'

/** PiP 控制面板动作回调（由通话层注册，避免本模块反向依赖通话逻辑） */
export interface PipActionHandler {
  /** 挂断按钮 */
  onHangUp: () => void
  /** 麦克风开关（on=true 打开） */
  onMicSwitch: (on: boolean) => void
  /** 摄像头开关（on=true 打开，语音通话 PiP 不含此控件，不会触发） */
  onCameraSwitch: (on: boolean) => void
}

/** 语音通话 PiP 自定义浮层参数 */
class AudioPipOverlayParams {
  title: string = ''
  subtitle: string = ''

  constructor(title: string, subtitle: string) {
    this.title = title
    this.subtitle = subtitle
  }
}

/** 语音通话 PiP 自定义浮层（覆盖在占位 XComponent 之上） */
@Builder
function audioPipOverlay(params: AudioPipOverlayParams) {
  Column({ space: 8 }) {
    Text(params.title)
      .fontSize(17)
      .fontColor('#ffffff')
      .fontWeight(FontWeight.Medium)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    Text(params.subtitle)
      .fontSize(13)
      .fontColor('rgba(255,255,255,0.7)')
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .backgroundColor('#2d261f') // 与语音通话页背景一致
}

/** 语音通话 PiP 浮层节点控制器：随 prepare 创建、随 release 销毁 */
class AudioPipNodeController extends NodeController {
  private node: BuilderNode<[AudioPipOverlayParams]> | null = null
  private title: string

  constructor(title: string) {
    super()
    this.title = title
  }

  makeNode(uiContext: UIContext): FrameNode | null {
    this.node = new BuilderNode(uiContext)
    this.node.build(wrapBuilder<[AudioPipOverlayParams]>(audioPipOverlay),
      new AudioPipOverlayParams(this.title, ''))
    return this.node.getFrameNode()
  }

  /** 更新浮层文案（通话计时驱动，非语音通话画中画时为 null 自然空转） */
  updateOverlay(title: string, subtitle: string): void {
    this.title = title
    this.node?.update(new AudioPipOverlayParams(title, subtitle))
  }

  disposeNode(): void {
    this.node?.dispose()
    this.node = null
  }
}

class CallPipManagerInner {
  private context: common.UIAbilityContext | null = null
  private pipController: PiPWindow.PiPController | null = null
  private actionHandler: PipActionHandler | null = null
  private restoreHandler: (() => void) | null = null
  private audioNodeController: AudioPipNodeController | null = null
  // 视频通话：远端渲染 XComponent 控制器（PiP 通过它将远端画面迁移到画中画窗口）
  private readonly remoteXComponentController: XComponentController = new XComponentController()
  // 语音通话：占位 XComponent 控制器（实际展示内容由自定义浮层提供）
  private readonly audioXComponentController: XComponentController = new XComponentController()
  private prepared: boolean = false
  private creating: boolean = false
  private pipStarted: boolean = false
  // 每次 prepare/release 递增，避免异步 create 完成晚于通话结束而遗留画中画
  private requestVersion: number = 0

  /** 在 EntryAbility.onCreate 中注入当前 UIAbilityContext。 */
  initialize(context: common.UIAbilityContext): void {
    this.context = context
  }

  /** 视频通话远端渲染 XComponent 的控制器（CallPage 远端 XComponent 需传入它） */
  get xComponentController(): XComponentController {
    return this.remoteXComponentController
  }

  /** 语音通话占位 XComponent 的控制器（CallPage 语音背景中的占位 XComponent 需传入它） */
  get audioStubXComponentController(): XComponentController {
    return this.audioXComponentController
  }

  /** 注册 PiP 控制面板动作回调（覆盖式注册） */
  setActionHandler(handler: PipActionHandler | null): void {
    this.actionHandler = handler
  }

  /** 注册画中画还原回调：PiP 停止、surface 归还主窗口后触发，通话层可在此重绑渲染视图 */
  setRestoreHandler(handler: (() => void) | null): void {
    this.restoreHandler = handler
  }

  /**
   * 应用回到前台时调用（EntryAbility.onForeground）。
   * 系统仅在用户点击小窗“还原”按钮时自动归位；经桌面图标/最近任务/通知栏回前台时
   * 画中画不会自动关闭，surface 仍挂在 PiP 窗口导致页面白屏，需在此主动停止。
   */
  onAppForeground(): void {
    const controller = this.pipController
    if (!controller || !this.pipStarted) {
      return
    }
    controller.stopPiP().catch((err: BusinessError) => {
      // 用户点击小窗还原按钮时系统已在还原流程中，重复停止会报错，忽略即可
      console.info(`ℹ️ [CallPip] 前台主动停止画中画: ${err.code} ${err.message}`)
    })
  }

  /**
   * 为通话准备画中画：创建 PiPController 并开启“退后台自动启动画中画”。
   * 重复调用安全且幂等；系统不支持 PiP 时静默降级（后台能力缺失，行为与现状一致）。
   *
   * @param forVideoCall true=视频通话（接管远端画面）；false=语音通话（占位视图+信息浮层）
   * @param peerName 对端名称，语音通话浮层展示用
   */
  prepare(forVideoCall: boolean, peerName: string = ''): void {
    if (this.prepared || this.creating) {
      return
    }
    const context = this.context
    if (!context) {
      console.warn('⚠️ [CallPip] UIAbilityContext 未初始化，无法准备画中画')
      return
    }
    if (!canIUse('SystemCapability.Window.SessionManager') || !PiPWindow.isPiPEnabled()) {
      console.warn('⚠️ [CallPip] 当前系统不支持画中画，跳过后台画中画能力')
      return
    }

    this.creating = true
    const version = ++this.requestVersion
    this.createPipController(context, version, forVideoCall, peerName)
  }

  /** 通话结束/挂断/复位时释放画中画：关闭自动启动并停止已启动的画中画窗口。 */
  release(): void {
    const controller = this.pipController
    ++this.requestVersion
    this.prepared = false
    this.creating = false
    this.pipController = null
    // 浮层节点与 PiPController 同生命周期：通话中 PiP 会反复启停，不能在中途 dispose，
    // 统一在 release（通话真正结束）时销毁。
    this.audioNodeController?.disposeNode()
    this.audioNodeController = null
    if (!controller) {
      return
    }
    try {
      controller.setAutoStartEnabled(false)
      controller.off('stateChange')
      controller.off('controlPanelActionEvent')
      if (this.pipStarted) {
        controller.stopPiP().catch((err: BusinessError) => {
          console.info(`ℹ️ [CallPip] 停止画中画: ${err.code} ${err.message}`)
        })
      }
    } catch (e) {
      console.warn(`⚠️ [CallPip] 释放画中画异常: ${JSON.stringify(e)}`)
    }
    this.pipStarted = false
  }

  /** 更新语音通话画中画浮层文案（通话计时每秒调用；非语音 PiP 时内部为空实现） */
  updateAudioCallOverlay(title: string, subtitle: string): void {
    this.audioNodeController?.updateOverlay(title, subtitle)
  }

  private async createPipController(context: common.UIAbilityContext, version: number,
    forVideoCall: boolean, peerName: string): Promise<void> {
    try {
      const config: PiPWindow.PiPConfiguration = {
        context: context,
        componentController: forVideoCall ? this.remoteXComponentController : this.audioXComponentController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_CALL,
        // 控制面板与通话页主控件对齐：语音通话不含摄像头开关
        controlGroups: forVideoCall
          ? [
            PiPWindow.VideoCallControlGroup.MICROPHONE_SWITCH,
            PiPWindow.VideoCallControlGroup.HANG_UP_BUTTON,
            PiPWindow.VideoCallControlGroup.CAMERA_SWITCH
          ]
          : [
            PiPWindow.VideoCallControlGroup.MICROPHONE_SWITCH,
            PiPWindow.VideoCallControlGroup.HANG_UP_BUTTON
          ]
      }
      if (!forVideoCall) {
        // 语音通话：占位 surface 无实际内容，叠加自定义浮层展示对端名称与计时
        this.audioNodeController = new AudioPipNodeController(peerName)
        config.customUIController = this.audioNodeController
        // 语音窗口采用 16:9 横向比例（占位 XComponent 为全屏尺寸，不能沿用其宽高）
        config.contentWidth = 1080
        config.contentHeight = 608
      }
      const controller = await PiPWindow.create(config)
      // 用户可能在 create 期间挂断，直接丢弃新建的控制器
      if (version !== this.requestVersion) {
        this.audioNodeController?.disposeNode()
        this.audioNodeController = null
        return
      }
      this.pipController = controller
      this.prepared = true
      this.registerCallbacks(controller)
      // 关键开关：应用退后台时自动拉起画中画，使应用保持前台可见态
      controller.setAutoStartEnabled(true)
      console.info(`✅ [CallPip] ${forVideoCall ? '视频' : '语音'}通话画中画已就绪（退后台自动启动）`)
    } catch (err) {
      const e = err as BusinessError
      console.error(`❌ [CallPip] 创建画中画控制器失败: ${e?.code} ${e?.message ?? JSON.stringify(err)}`)
    } finally {
      if (version === this.requestVersion) {
        this.creating = false
      }
    }
  }

  private registerCallbacks(controller: PiPWindow.PiPController): void {
    controller.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
      this.onPipStateChange(state, reason)
    })
    controller.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, status?: number) => {
      this.onControlPanelAction(event, status)
    })
  }

  private onPipStateChange(state: PiPWindow.PiPState, reason: string): void {
    switch (state) {
      case PiPWindow.PiPState.STARTED:
        this.pipStarted = true
        console.info(`✅ [CallPip] 画中画已启动`)
        break
      case PiPWindow.PiPState.STOPPED:
        // 回前台还原或主动停止后复位标志（控制器保留，可再次自动启动）
        this.pipStarted = false
        console.info(`ℹ️ [CallPip] 画中画已停止`)
        // surface 已归还主窗口，通知通话层重绑远端渲染视图（与 XComponent onLoad 重绑互为冗余）
        this.restoreHandler?.()
        break
      case PiPWindow.PiPState.ERROR:
        this.pipStarted = false
        console.error(`❌ [CallPip] 画中画错误, reason=${reason}`)
        break
      default:
        // ABOUT_TO_START / ABOUT_TO_STOP / ABOUT_TO_RESTORE 为过渡态，仅记录
        console.info(`ℹ️ [CallPip] state=${state} reason=${reason}`)
        break
    }
  }

  private onControlPanelAction(event: PiPWindow.PiPActionEventType, status?: number): void {
    console.info(`ℹ️ [CallPip] 控制面板事件: ${event}, status=${status}`)
    const handler = this.actionHandler
    if (!handler) {
      return
    }
    switch (event) {
      case 'hangUp':
        handler.onHangUp()
        break
      case 'micStateChanged':
        handler.onMicSwitch(status === 1)
        break
      case 'videoStateChanged':
        handler.onCameraSwitch(status === 1)
        break
      default:
        break
    }
  }
}

export const CallPipManager: CallPipManagerInner = new CallPipManagerInner()
