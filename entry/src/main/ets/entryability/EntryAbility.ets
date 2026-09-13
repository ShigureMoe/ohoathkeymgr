import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppContextHolder } from '../common/AppContextHolder';
import { Log } from '../common/Log';
import { NfcListener } from '../common/NfcCardTransport';
import { AppPreferences } from '../storage/AppPreferences';
import { ConnectionManager } from '../service/ConnectionManager';
import { TokenRefreshScheduler } from '../service/TokenRefreshScheduler';
import { ThemeManager } from '../service/ThemeManager';
import { LanguageManager } from '../service/LanguageManager';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContextHolder.context = this.context;
    AppPreferences.init(this.context);
    ConnectionManager.getInstance().init(this.context);
    ThemeManager.apply(this.context);
    // 恢复用户选择的应用语言（非 follow-system 时还原系统偏好语言；app-i18n D1）
    LanguageManager.initOnCreate();
    TokenRefreshScheduler.getInstance().start();
    Log.info('%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    TokenRefreshScheduler.getInstance().stop();
    Log.info('%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Log.error('Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      Log.info('%{public}s', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // 释放读卡器模式（退出读卡器模式并恢复卡模拟），避免窗口销毁后 NFC 监听泄漏
    NfcListener.stop();
  }

  onForeground(): void {
    Log.info('%{public}s', 'Ability onForeground');
    // 恢复 NFC 待卡监听（onBackground 中已退订，系统要求退出前台即 tag.off）
    ConnectionManager.getInstance().resumeNfcIdle();
  }

  onBackground(): void {
    // 应用退到后台时释放读卡器模式（文档要求退出前台即调用 tag.off）
    NfcListener.stop();
  }
}