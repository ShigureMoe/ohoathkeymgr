/**
 * 语言偏好管理（app-i18n / D1，与 ThemeManager 同范式静态类）：
 *  - 三态偏好：'follow-system'（默认）| 'zh-Hans' | 'en-US'，持久化于 Preferences key 'app_language'
 *  - apply：经 i18n.System.setAppPreferredLanguage 应用（仅影响本应用）；
 *    具体语言即时生效；'follow-system' 映射为 'default'，按平台约束需应用重启后生效
 *  - 自存三态的原因：getAppPreferredLanguage 在 default 态返回系统语言，
 *    无法区分"跟随系统"与"恰好为该语言"，故必须自行持久化以下拉框选中态
 */
import { i18n } from '@kit.LocalizationKit';
import { AppPreferences } from '../storage/AppPreferences';
import { Log } from '../common/Log';

export class LanguageManager {
  static readonly FOLLOW_SYSTEM = 'follow-system';
  static readonly ZH_HANS = 'zh-Hans';
  static readonly EN_US = 'en-US';
  private static readonly KEY = 'app_language';

  /** 读取持久化的语言偏好（未设置时默认跟随系统） */
  static getPersisted(): string {
    return AppPreferences.getString(LanguageManager.KEY, LanguageManager.FOLLOW_SYSTEM);
  }

  /** 应用语言偏好到系统应用偏好语言机制（follow-system → 'default'）；失败吞异常记 Log */
  static apply(pref: string): void {
    const lang = pref === LanguageManager.FOLLOW_SYSTEM ? 'default' : pref;
    try {
      i18n.System.setAppPreferredLanguage(lang);
    } catch (e) {
      // 设置失败（极端系统状态）：不中断交互，下次选择/重启时重试
      Log.error('setAppPreferredLanguage failed: %{public}s', String(e));
    }
  }

  /** 持久化并应用（下拉框选择入口） */
  static persistAndApply(pref: string): void {
    AppPreferences.putString(LanguageManager.KEY, pref);
    LanguageManager.apply(pref);
  }

  /** EntryAbility.onCreate 调用：非 follow-system 时恢复系统偏好语言（还原上次选择） */
  static initOnCreate(): void {
    const pref = LanguageManager.getPersisted();
    if (pref !== LanguageManager.FOLLOW_SYSTEM) {
      LanguageManager.apply(pref);
    }
  }
}
