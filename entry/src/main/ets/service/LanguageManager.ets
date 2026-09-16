/**
 * 语言偏好管理（app-i18n / D1，与 ThemeManager 同范式静态类）：
 *  - 三态偏好：'follow-system'（默认）| 'zh-Hans' | 'en-US'，持久化于 Preferences key 'app_language'
 *  - apply：经 i18n.System.setAppPreferredLanguage 应用（仅影响本应用）；
 *    具体语言即时生效；'follow-system' 映射为 'default'，按平台约束需应用重启后生效
 *  - 自存三态的原因：getAppPreferredLanguage 在 default 态返回系统语言，
 *    无法区分"跟随系统"与"恰好为该语言"，故必须自行持久化以下拉框选中态
 *  - 防抖（fix-lang-switch-jank D2）：用户主动切换（persistAndApply）时持久化即时执行，
 *    应用延迟 300ms 防抖执行（连续切换仅最后一次生效），确保任何弹层/子窗口完全收起后
 *    才触发系统配置更新，规避"配置更新 × 菜单子窗口"死循环；防抖期间应用被杀无影响
 *    （偏好已持久化，下次启动 initOnCreate 恢复）。启动恢复路径（initOnCreate）无延迟。
 */
import { i18n } from '@kit.LocalizationKit';
import { AppPreferences } from '../storage/AppPreferences';
import { Log } from '../common/Log';

export class LanguageManager {
  static readonly FOLLOW_SYSTEM = 'follow-system';
  static readonly ZH_HANS = 'zh-Hans';
  static readonly EN_US = 'en-US';
  private static readonly KEY = 'app_language';
  // 用户主动切换路径的应用防抖延迟（毫秒）：覆盖弹层收起动画与子窗口销毁时长
  private static readonly APPLY_DELAY_MS = 300;
  // 待执行应用的定时器句柄（-1 表示无待执行任务）
  private static pendingApplyTimer: number = -1;

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

  /**
   * 持久化并应用（用户主动切换入口，fix-lang-switch-jank D2）：
   * 持久化即时执行（中断安全）；具体语言应用防抖延迟 300ms——新调用清除旧定时器
   * 并重新计时，连续切换仅最后一次生效（只触发一次系统配置更新）。
   * follow-system 分支立即应用：'default' 不触发本进程刷新（无死循环风险），
   * 且系统侧记录须在任意重启（含防抖窗口内被杀）前落定为 'default'，
   * 保证"选中后重启一次"即跟随系统，不残留历史具体语言。
   */
  static persistAndApply(pref: string): void {
    AppPreferences.putString(LanguageManager.KEY, pref);
    if (LanguageManager.pendingApplyTimer >= 0) {
      clearTimeout(LanguageManager.pendingApplyTimer);
      LanguageManager.pendingApplyTimer = -1;
    }
    if (pref === LanguageManager.FOLLOW_SYSTEM) {
      LanguageManager.apply(pref);
      return;
    }
    LanguageManager.pendingApplyTimer = setTimeout(() => {
      LanguageManager.pendingApplyTimer = -1;
      LanguageManager.apply(pref);
    }, LanguageManager.APPLY_DELAY_MS);
  }

  /**
   * EntryAbility.onCreate 调用：无条件恢复偏好语言（还原上次选择）。
   * follow-system 也需 apply（'default'）：防抖期间应用被杀时用户最后一次
   * setAppPreferredLanguage 可能未执行，历史残留的具体语言会盖过"跟随系统"，
   * 启动时下发 'default' 清除残留（启动路径无弹层/子窗口，且 'default' 本就需重启生效）。
   */
  static initOnCreate(): void {
    LanguageManager.apply(LanguageManager.getPersisted());
  }
}
