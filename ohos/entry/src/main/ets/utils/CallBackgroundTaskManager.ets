/**
 * CallBackgroundTaskManager.ets
 *
 * 为音视频通话申请 HarmonyOS VOIP 长时任务。
 * Android 端的通话 Activity 在退后台后仍保持 SDK 会话；HarmonyOS 需要显式申请
 * BackgroundMode.VOIP，否则 UIAbility 被挂起时 SDK 会话会被系统回收并触发 onCallEnd。
 */

import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager'
import wantAgent from '@ohos.wantAgent'
import common from '@ohos.app.ability.common'

const WANT_AGENT_REQUEST_CODE: number = 10001

class CallBackgroundTaskManagerInner {
  private context: common.UIAbilityContext | null = null
  private active: boolean = false
  private starting: boolean = false
  // 每次 start/stop 递增，避免异步申请完成晚于挂断而遗留后台任务
  private requestVersion: number = 0

  /** 在 EntryAbility.onCreate 中注入当前 UIAbilityContext。 */
  initialize(context: common.UIAbilityContext): void {
    this.context = context
  }

  /**
   * 申请 VOIP 长时任务。对 calling/ringing/connected 状态重复调用是安全且幂等的。
   * 系统会为长时任务展示通知；点击通知可回到当前 EntryAbility。
   */
  start(): void {
    if (this.active || this.starting) {
      return
    }
    const context = this.context
    if (!context) {
      console.warn('⚠️ [CallBackgroundTask] UIAbilityContext 未初始化，无法申请 VOIP 长时任务')
      return
    }

    this.starting = true
    const version = ++this.requestVersion
    this.requestVoipTask(context, version)
  }

  /** 在通话结束、挂断或 Ability 销毁时取消 VOIP 长时任务。 */
  stop(): void {
    const context = this.context
    const shouldStop = this.active || this.starting
    ++this.requestVersion
    this.active = false
    this.starting = false
    if (!context || !shouldStop) {
      return
    }
    this.stopVoipTask(context)
  }

  private async requestVoipTask(context: common.UIAbilityContext, version: number): Promise<void> {
    try {
      // 用当前 Ability 动态信息构造通知点击后的回跳目标，避免硬编码 bundleName/abilityName。
      const agent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: WANT_AGENT_REQUEST_CODE,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      })
      // 用户可能已在创建 WantAgent 期间挂断，不能继续创建后台任务。
      if (version !== this.requestVersion) {
        return
      }

      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.VOIP,
        agent
      )

      // 若 startBackgroundRunning 完成前已挂断，立即撤销刚创建的任务，避免残留通知。
      if (version !== this.requestVersion) {
        await this.stopVoipTask(context)
        return
      }
      this.active = true
      console.info('✅ [CallBackgroundTask] VOIP 长时任务已启动')
    } catch (err) {
      // 不影响前台通话；配置/权限异常会留下可诊断日志。
      console.error(`❌ [CallBackgroundTask] 启动 VOIP 长时任务失败: ${JSON.stringify(err)}`)
    } finally {
      if (version === this.requestVersion) {
        this.starting = false
      }
    }
  }

  private async stopVoipTask(context: common.UIAbilityContext): Promise<void> {
    try {
      await backgroundTaskManager.stopBackgroundRunning(context)
      console.info('✅ [CallBackgroundTask] VOIP 长时任务已停止')
    } catch (err) {
      // 任务尚未真正创建或已被系统回收时 stop 会失败，均无需影响通话清理流程。
      console.info(`ℹ️ [CallBackgroundTask] 停止 VOIP 长时任务: ${JSON.stringify(err)}`)
    }
  }
}

export const CallBackgroundTaskManager: CallBackgroundTaskManagerInner = new CallBackgroundTaskManagerInner()
