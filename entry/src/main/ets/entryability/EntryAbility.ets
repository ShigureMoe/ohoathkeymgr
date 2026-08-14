import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContextHolder } from '../common/AppContextHolder';
import { NfcListener } from '../common/NfcCardTransport';
import { AppPreferences } from '../storage/AppPreferences';
import { ConnectionManager } from '../service/ConnectionManager';
import { TokenRefreshScheduler } from '../service/TokenRefreshScheduler';
import { ThemeManager } from '../service/ThemeManager';
const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContextHolder.context = this.context;
    AppPreferences.init(this.context);
    ConnectionManager.getInstance().init(this.context);
    ThemeManager.apply(this.context);
    TokenRefreshScheduler.getInstance().start();
    hilog.info(DOMAIN, 'OathKeeper', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    TokenRefreshScheduler.getInstance().stop();
    hilog.info(DOMAIN, 'OathKeeper', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'OathKeeper', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'OathKeeper', '%{public}s', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // 释放读卡器模式（退出读卡器模式并恢复卡模拟），避免窗口销毁后 NFC 监听泄漏
    NfcListener.stop();
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'OathKeeper', '%{public}s', 'Ability onForeground');
    // 恢复 NFC 待卡监听（onBackground 中已退订，系统要求退出前台即 tag.off）
    ConnectionManager.getInstance().resumeNfcIdle();
  }

  onBackground(): void {
    // 应用退到后台时释放读卡器模式（文档要求退出前台即调用 tag.off）
    NfcListener.stop();
  }
}