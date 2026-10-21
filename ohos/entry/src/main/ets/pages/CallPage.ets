/**
 * CallPage.ets
 * 音视频通话统一页面（复用）
 * - 支持 4 个状态：calling / ringing / connected / ended
 * - 音频、视频复用同一页面，仅按钮 / 背景差异
 *
 * 路由参数：
 *   { mode: 0|1, peerName: string, peerAvatar?: string, isCaller: boolean }
 * 若不传参，则直接读 CallManager.currentSession
 */

import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import window from '@ohos.window'
import common from '@ohos.app.ability.common'
import {
  CALL_LOCAL_VIEW_ID,
  CALL_REMOTE_VIEW_ID,
  CallManager,
  CallMode,
  CallState
} from '../utils/CallManager'
import { AUDIO_PIP_VIEW_ID, CallPipManager } from '../utils/CallPipManager'

interface CallRouteParams {
  mode?: number
  peerName?: string
  peerAvatar?: string
  isCaller?: boolean
  productId?: string
  deviceId?: string
}

@Entry
@Component
struct CallPage {
  @State state: string = CallState.IDLE
  @State mode: number = CallMode.AUDIO
  @State peerName: string = ''
  @State peerAvatar: string = ''
  @State durationText: string = '00:00'
  @State statusText: string = ''
  @State micOn: boolean = true
  @State speakerOn: boolean = false
  @State cameraOn: boolean = true
  @State blurBackground: boolean = false
  @State hasRemoteVideoFrame: boolean = false
  @State tick: number = 0 // 强制刷新用
  private listener = () => {
    this.syncFromManager()
  }

  aboutToAppear(): void {
    // 如果路由传了参数（主叫），则发起呼叫；否则复用当前 session（被叫）
    const params = router.getParams() as CallRouteParams
    if (params && params.peerName && CallManager.state === CallState.IDLE) {
      // 主叫
      CallManager.startCall(
        params.peerName,
        (params.mode === 1 ? CallMode.VIDEO : CallMode.AUDIO),
        params.peerAvatar,
        params.productId ?? '',
        params.deviceId ?? ''
      )
    }
    CallManager.addListener(this.listener)
    this.syncFromManager()
    this.setKeepScreenOn(true)
  }

  aboutToDisappear(): void {
    CallManager.removeListener(this.listener)
    this.setKeepScreenOn(false)
  }

  /** 通话期间保持屏幕常亮（对齐 Android keepScreenOn） */
  private setKeepScreenOn(keep: boolean): void {
    try {
      window.getLastWindow(getContext(this) as common.UIAbilityContext).then((win: window.Window) => {
        win.setWindowKeepScreenOn(keep)
      })
    } catch (err) {
      console.warn(`CallPage 设置屏幕常亮失败: ${err}`)
    }
  }

  private syncFromManager(): void {
    this.state = CallManager.state
    this.mode = CallManager.currentSession?.mode ?? CallMode.AUDIO
    this.peerName = CallManager.currentSession?.peerName ?? ''
    this.peerAvatar = CallManager.currentSession?.peerAvatar ?? ''
    this.durationText = CallManager.durationText
    this.statusText = CallManager.statusText
    this.micOn = CallManager.micOn
    this.speakerOn = CallManager.speakerOn
    this.cameraOn = CallManager.cameraOn
    this.blurBackground = CallManager.blurBackground
    this.hasRemoteVideoFrame = CallManager.hasRemoteVideoFrame
    this.tick++
    // 消费一次性提示（通话被拒绝/未响应/忙线/设备未在线/错误，对齐 Android show() 分支 toast）
    if (CallManager.notice.length > 0) {
      promptAction.showToast({ message: CallManager.consumeNotice(), duration: 2000 })
    }
    // 状态回到 IDLE 时自动关闭页面
    if (this.state === CallState.IDLE) {
      try {
        router.back()
      } catch (e) { /* ignore */
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景
      if (this.mode === CallMode.VIDEO) {
        this.VideoBackground()
      } else {
        this.AudioBackground()
      }

      // 遵照 iOS 的遮罩策略：
      // - 音频通话：始终深色遮罩（突出文字）
      // - 视频通话：连接前/未有帧 则淺遮罩显示头像；已接通且有帧时不遮罩
      if (this.mode === CallMode.AUDIO) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('rgba(0,0,0,0.55)')
      } else if (this.mode === CallMode.VIDEO &&
        (this.state !== CallState.CONNECTED || !this.hasRemoteVideoFrame)) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('rgba(0,0,0,0.35)')
      }

      // 主内容
      Column() {
        this.TopBar()

        // 视频通话中且已有远端帧：右上角本地预览小窗；其余情况均显示头像+昵称
        if (this.state === CallState.CONNECTED &&
          this.mode === CallMode.VIDEO &&
          this.hasRemoteVideoFrame) {
          Row() {
            Blank()
            this.LocalPreviewWindow()
          }
          .width('100%')
          .padding({ right: 16, top: 60 })

          Blank()
        } else {
          // 头像 + 昵称
          this.PeerInfoBlock()
          Blank()
          Text(this.statusText)
            .fontSize(15)
            .fontColor('rgba(255,255,255,0.85)')
            .margin({ bottom: 24 })
        }

        // 底部按钮区
        this.BottomControls()
        Column().height(36)
      }
      .width('100%')
      .height('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .height('100%')
  }

  // ========== 顶部栏 ==========
  @Builder
  TopBar() {
    Row() {
      // 左侧占位（保持计时居中）
      Column().width(40).height(40)

      Blank()

      // 通话中：计时
      if (this.state === CallState.CONNECTED) {
        Text(this.durationText)
          .fontSize(15).fontColor('#ffffff').fontWeight(FontWeight.Normal)
      }

      Blank()

      // 右侧占位（保持计时居中）
      Column().width(40).height(40)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4 })
  }

  // ========== 头像 + 昵称 ==========
  @Builder
  PeerInfoBlock() {
    Column({ space: 12 }) {
      // 头像（使用 Image，失败时退回占位）
      if (this.peerAvatar && this.peerAvatar.length > 0) {
        Image(this.peerAvatar)
          .width(88).height(88)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)
      } else {
        Stack() {
          Column()
            .width(88).height(88)
            .borderRadius(12)
            .linearGradient({
              angle: 180,
              colors: [[0xffae8c6a, 0], [0xff806048, 1.0]]
            })
          Text('👤').fontSize(36)
        }
      }
      Text(this.peerName)
        .fontSize(20).fontWeight(FontWeight.Normal).fontColor('#ffffff')
    }
    .margin({ top: this.mode === CallMode.VIDEO ? 80 : 120 })
  }

  // ========== 底部按钮区（根据状态切换） ==========
  @Builder
  BottomControls() {
    if (this.state === CallState.CALLING) {
      // 主叫呼叫中：按 mode 区分两套 UI
      //  - 语音：图1 样式（麦克风 / 取消 / 扬声器）
      //  - 视频：图2 样式（上排 麦/扬声器/摄像头 + 下排 空占位/挂断/翻转）
      if (this.mode === CallMode.VIDEO) {
        Column({ space: 24 }) {
          this.ConnectedVideoTopRow()
          this.ConnectedVideoBottomRow()
        }
      } else {
        this.CallerActions()
      }
    } else if (this.state === CallState.RINGING) {
      if (this.mode === CallMode.VIDEO) {
        Column({ space: 24 }) {
          this.VideoRingingSecondaryRow()
          this.RejectAnswerRow()
        }
      } else {
        this.RejectAnswerRow()
      }
    } else if (this.state === CallState.CONNECTED) {
      if (this.mode === CallMode.VIDEO) {
        Column({ space: 24 }) {
          this.ConnectedVideoTopRow()
          this.ConnectedVideoBottomRow()
        }
      } else {
        this.ConnectedAudioRow()
      }
    } else if (this.state === CallState.ENDED) {
      this.EndedActions()
    }
  }

  // ---------- 子按钮行 ----------

  // 主叫：麦克风 / 取消 / 扬声器
  @Builder
  CallerActions() {
    Row({ space: 32 }) {
      // 麦克风
      Column({ space: 8 }) {
        Button() {
          Image(this.micOn ? $r('app.media.ic_mic_on') : $r('app.media.ic_mic_off'))
            .width(24).height(24)
            .fillColor(this.micOn ? '#000000' : '#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.micOn ? '#ffffff' : 'rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.toggleMic())

        Text(this.micOn ? '麦克风已开' : '麦克风已关')
          .fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      // 挂断
      Column({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_call'))
            .width(24).height(24)
            .fillColor('#ffffff')
            .rotate({ angle: 135 })
        }
        .width(64)
        .height(64)
        .backgroundColor('#e64c4c')
        .borderRadius(32)
        .onClick(() => CallManager.hangup())

        Text('取消').fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      // 扬声器
      Column({ space: 8 }) {
        Button() {
          Image(this.speakerOn ? $r('app.media.ic_sound_on') : $r('app.media.ic_sound_off'))
            .width(24).height(24)
            .fillColor(this.speakerOn ? '#000000' : '#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.speakerOn ? '#ffffff' : 'rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.toggleSpeaker())

        Text(this.speakerOn ? '扬声器已开' : '扬声器已关')
          .fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  // 被叫：拒绝 / 接听
  @Builder
  RejectAnswerRow() {
    Row({ space: 90 }) {
      Column({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_call'))
            .width(24).height(24)
            .fillColor('#ffffff')
            .rotate({ angle: 135 })
        }
        .width(64)
        .height(64)
        .backgroundColor('#e64c4c')
        .borderRadius(32)
        .onClick(() => CallManager.hangup())

        Text('拒绝').fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      Column({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_call'))
            .width(24).height(24)
            .fillColor('#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor('#38c76a')
        .borderRadius(32)
        .onClick(() => CallManager.answer())

        Text('接听').fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  // 视频被叫次要行：翻转 / 摄像头
  @Builder
  VideoRingingSecondaryRow() {
    Row({ space: 60 }) {
      // 翻转
      Column({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_call_camera_flip'))
            .width(24).height(24)
            .fillColor('#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor('rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.switchCamera())

        Text('翻转').fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      // 摄像头
      Column({ space: 8 }) {
        Button() {
          Image(this.cameraOn ? $r('app.media.ic_video_camera') : $r('app.media.ic_video_slash'))
            .width(24).height(24)
            .fillColor(this.cameraOn ? '#000000' : '#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.cameraOn ? '#ffffff' : 'rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.toggleCamera())

        Text(this.cameraOn ? '摄像头已开' : '摄像头已关')
          .fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  // 通话中（音频）：麦克风 / 挂断 / 扬声器
  @Builder
  ConnectedAudioRow() {
    Row({ space: 32 }) {
      // 麦克风
      Column({ space: 8 }) {
        Button() {
          Image(this.micOn ? $r('app.media.ic_mic_on') : $r('app.media.ic_mic_off'))
            .width(24).height(24)
            .fillColor(this.micOn ? '#000000' : '#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.micOn ? '#ffffff' : 'rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.toggleMic())

        Text(this.micOn ? '麦克风已开' : '麦克风已关')
          .fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      // 挂断
      Column({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_call'))
            .width(24).height(24)
            .fillColor('#ffffff')
            .rotate({ angle: 135 })
        }
        .width(64)
        .height(64)
        .backgroundColor('#e64c4c')
        .borderRadius(32)
        .onClick(() => CallManager.hangup())

        Text('挂断').fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      // 扬声器
      Column({ space: 8 }) {
        Button() {
          Image(this.speakerOn ? $r('app.media.ic_sound_on') : $r('app.media.ic_sound_off'))
            .width(24).height(24)
            .fillColor(this.speakerOn ? '#000000' : '#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.speakerOn ? '#ffffff' : 'rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.toggleSpeaker())

        Text(this.speakerOn ? '扬声器已开' : '扬声器已关')
          .fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  // 通话中（视频）上排：麦克风 / 扬声器 / 摄像头
  @Builder
  ConnectedVideoTopRow() {
    Row({ space: 32 }) {
      Column({ space: 8 }) {
        Button() {
          Image(this.micOn ? $r('app.media.ic_mic_on') : $r('app.media.ic_mic_off'))
            .width(24).height(24)
            .fillColor(this.micOn ? '#000000' : '#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.micOn ? '#ffffff' : 'rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.toggleMic())

        Text(this.micOn ? '麦克风已开' : '麦克风已关')
          .fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      Column({ space: 8 }) {
        Button() {
          Image(this.speakerOn ? $r('app.media.ic_sound_on') : $r('app.media.ic_sound_off'))
            .width(24).height(24)
            .fillColor(this.speakerOn ? '#000000' : '#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.speakerOn ? '#ffffff' : 'rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.toggleSpeaker())

        Text(this.speakerOn ? '扬声器已开' : '扬声器已关')
          .fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      Column({ space: 8 }) {
        Button() {
          Image(this.cameraOn ? $r('app.media.ic_video_camera') : $r('app.media.ic_video_slash'))
            .width(24).height(24)
            .fillColor(this.cameraOn ? '#000000' : '#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.cameraOn ? '#ffffff' : 'rgba(0,0,0,0.35)')
        .borderRadius(32)
        .onClick(() => CallManager.toggleCamera())

        Text(this.cameraOn ? '摄像头已开' : '摄像头已关')
          .fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  // 通话中（视频）下排：左侧占位 / 挂断（居中）/ 翻转
  @Builder
  ConnectedVideoBottomRow() {
    Row({ space: 70 }) {
      // 左侧空占位，宽度与右侧「翻转」按钮一致，保持挂断居中
      Column().width(52).height(52)

      Button() {
        Image($r('app.media.ic_call'))
          .width(24).height(24)
          .fillColor('#ffffff')
          .rotate({ angle: 135 })
      }
      .width(64)
      .height(64)
      .backgroundColor('#e64c4c')
      .borderRadius(32)
      .onClick(() => CallManager.hangup())

      Button() {
        Image($r('app.media.ic_call_camera_flip'))
          .width(24).height(24)
          .fillColor('#ffffff')
      }
      .width(52)
      .height(52)
      .backgroundColor('rgba(0,0,0,0.35)')
      .borderRadius(26)
      .onClick(() => CallManager.switchCamera())
    }
    .justifyContent(FlexAlign.Center)
  }

  // 已结束：拒绝（关闭） / 接听（重拨预留）
  @Builder
  EndedActions() {
    Row({ space: 90 }) {
      Column({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_call'))
            .width(24).height(24)
            .fillColor('#ffffff')
            .rotate({ angle: 135 })
        }
        .width(64)
        .height(64)
        .backgroundColor('#e64c4c')
        .borderRadius(32)
        .onClick(() => CallManager.hangup())

        Text('关闭').fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }

      Column({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_call'))
            .width(24).height(24)
            .fillColor('#ffffff')
        }
        .width(64)
        .height(64)
        .backgroundColor('#38c76a')
        .borderRadius(32)
        .onClick(() => CallManager.hangup())

        Text('重拨').fontSize(12).fontColor('rgba(255,255,255,0.9)')
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  // ========== 背景 ==========
  @Builder
  VideoBackground() {
    Stack() {
      // 远端视频渲染视图（TXIoTCallSession.startRemoteView 绑定此 XComponent id）
      // controller 由 CallPipManager 持有：退后台时画中画接管该 surface 继续渲染
      XComponent({
        id: CALL_REMOTE_VIEW_ID,
        type: XComponentType.SURFACE,
        libraryname: 'liteavsdk',
        controller: CallPipManager.xComponentController
      })
        .width('100%')
        .height('100%')
        .onLoad(() => CallManager.bindRemoteView())
      // 未接通或无远端视频帧：全屏展示本地摄像头预览
      // （对齐 Android：iot_video_local 初始 MATCH_PARENT 全屏，接通且有远端帧后才缩为右上角小窗）
      // 与 LocalPreviewWindow 互斥挂载，保证同一 XComponent id 任意时刻仅一个实例
      if (!(this.state === CallState.CONNECTED && this.hasRemoteVideoFrame)) {
        if (this.cameraOn) {
          // 本地摄像头渲染视图（TXIoTCallSession.openCamera 绑定此 XComponent id）
          XComponent({ id: CALL_LOCAL_VIEW_ID, type: XComponentType.SURFACE, libraryname: 'liteavsdk' })
            .width('100%')
            .height('100%')
            .onLoad(() => CallManager.bindLocalView())
        } else {
          // 摄像头未开启：退回深色渐变占位
          Column()
            .width('100%').height('100%')
            .linearGradient({
              angle: 180,
              colors: [[0xffcccccc, 0], [0xff7f7f7f, 1.0]]
            })
        }
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  AudioBackground() {
    Stack() {
      // 语音通话画中画占位视图：被下方不透明深色背景遮盖不可见；
      // 退后台时 PiP 接管该 surface（实际展示内容由 CallPipManager 自定义浮层提供）
      XComponent({
        id: AUDIO_PIP_VIEW_ID,
        type: XComponentType.SURFACE,
        controller: CallPipManager.audioStubXComponentController
      })
        .width('100%')
        .height('100%')
      Column()
        .width('100%').height('100%')
        .backgroundColor('#2d261f')
      Column()
        .width(400)
        .height(400)
        .borderRadius(200)
        .backgroundColor('rgba(88,71,56,0.6)')
        .blur(80)
        .margin({ top: 100 })
    }
    .width('100%').height('100%')
  }

  // 本地预览小窗（视频通话右上角，对齐 Android local_preview）
  // 摄像头关闭时覆盖一个“视频栅杠”提示（与 iOS 对齐）
  @Builder
  LocalPreviewWindow() {
    Stack() {
      // 本地摄像头渲染视图（TXIoTCallSession.openCamera 绑定此 XComponent id）
      XComponent({ id: CALL_LOCAL_VIEW_ID, type: XComponentType.SURFACE, libraryname: 'liteavsdk' })
        .width(110).height(160)
        .borderRadius(10)
        .onLoad(() => CallManager.bindLocalView())
      // 摄像头关闭：深色遮罩 + 视频栅杠图标
      if (!this.cameraOn) {
        Column()
          .width(110).height(160)
          .borderRadius(10)
          .backgroundColor('#333333')
        Image($r('app.media.ic_video_slash'))
          .width(32).height(32)
          .fillColor('rgba(255,255,255,0.85)')
      }
    }
  }
}
