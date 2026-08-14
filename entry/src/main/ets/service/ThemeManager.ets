/** 暗黑模式应用（S12）：读取偏好并设置应用颜色模式 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppPreferences } from '../storage/AppPreferences';

export class ThemeManager {
  static readonly THEME_SYSTEM = 'system';
  static readonly THEME_DARK = 'dark';
  static readonly THEME_LIGHT = 'light';

  static apply(context: common.Context): void {
    const theme = AppPreferences.getString('ui_theme', ThemeManager.THEME_SYSTEM);
    let mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (theme === ThemeManager.THEME_DARK) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (theme === ThemeManager.THEME_LIGHT) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      context.getApplicationContext().setColorMode(mode);
    } catch (e) {
      // 忽略设置失败
    }
  }
}