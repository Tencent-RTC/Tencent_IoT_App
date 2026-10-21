import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { CallBackgroundTaskManager } from '../utils/CallBackgroundTaskManager';
import { CallPipManager } from '../utils/CallPipManager';
import { CallManager } from '../utils/CallManager';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 强制使用浅色模式，禁止跟随系统深色模式
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    // 注入 UIAbilityContext：CallManager 在通话活跃时使用其申请 VOIP 长时任务。
    CallBackgroundTaskManager.initialize(this.context);
    // 注入 UIAbilityContext：CallPipManager 在视频通话活跃时使用其创建画中画。
    CallPipManager.initialize(this.context);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    // Ability 销毁时不保留通知/后台运行资格，SDK 会话也将随进程终止。
    CallBackgroundTaskManager.stop();
    CallPipManager.release();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  /**
   * 申请麦克风和摄像头权限
   */
  async requestAVPermissions(): Promise<void> {
    const permissions: Permissions[] = [
      'ohos.permission.MICROPHONE',
      'ohos.permission.CAMERA'
    ];
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const result = await atManager.requestPermissionsFromUser(this.context, permissions);
      const allGranted = result.authResults.every(
        (r) => r === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      );
      if (allGranted) {
        hilog.info(DOMAIN, 'testTag', '✅ 音视频权限已授权');
      } else {
        hilog.warn(DOMAIN, 'testTag', '⚠️ 音视频权限被拒绝');
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '❌ 权限申请失败: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      // 设置状态栏和导航栏为白色背景、深色图标
      try {
        const mainWindow = windowStage.getMainWindowSync();
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#FFFFFF',
          statusBarContentColor: '#000000',
          navigationBarColor: '#FFFFFF',
          navigationBarContentColor: '#000000'
        });
      } catch (e) {
        hilog.warn(DOMAIN, 'testTag', '设置系统栏颜色失败: %{public}s', JSON.stringify(e));
      }

      // 页面加载完成后再申请音视频权限，确保窗口已显示
      this.requestAVPermissions();
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // 经桌面图标/最近任务/通知栏回前台时，系统不会自动关闭画中画，需主动停止以归还渲染 surface
    CallPipManager.onAppForeground();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // 冗余确保：正常路径在拨号/来电时已申请；此处覆盖极短时间内切后台的竞态。
    CallManager.ensureBackgroundProtection();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}