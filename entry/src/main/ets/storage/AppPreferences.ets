/** 应用偏好设置（Preferences 封装）：暗黑模式等设置项 + 持久化密码存储载体 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class AppPreferences {
  private static store: preferences.Preferences | undefined = undefined;
  private static readonly STORE_NAME = 'oath_keeper';

  /** 同步加载偏好存储（getPreferencesSync，实例有缓存）：调用返回后即可读取，消除启动期读取竞态；加载异常时保持 store 未就绪，读取方按默认值回退（主题默认跟随系统），不抛出 */
  static init(context: common.Context): void {
    try {
      AppPreferences.store = preferences.getPreferencesSync(context, { name: AppPreferences.STORE_NAME });
    } catch (e) {
      // 偏好加载失败（如文件损坏）：保持 store 为 undefined，getString 等按默认值回退，应用按"跟随系统"启动
    }
  }

  static getString(key: string, def: string): string {
    const s = AppPreferences.store;
    if (s === undefined) {
      return def;
    }
    const v = s.getSync(key, def);
    return typeof v === 'string' ? v : def;
  }

  static putString(key: string, value: string): void {
    const s = AppPreferences.store;
    if (s === undefined) {
      return;
    }
    s.putSync(key, value);
    s.flush();
  }

  static remove(key: string): void {
    const s = AppPreferences.store;
    if (s === undefined) {
      return;
    }
    s.deleteSync(key);
    s.flush();
  }

  /** 获取全部键值（供持久化密码列表扫描） */
  static getAll(): Map<string, string> {
    const out = new Map<string, string>();
    const s = AppPreferences.store;
    if (s === undefined) {
      return out;
    }
    const all = s.getAllSync() as Record<string, Object>;
    const keys = Object.keys(all);
    for (const key of keys) {
      const v = all[key];
      if (typeof v === 'string') {
        out.set(key, v);
      }
    }
    return out;
  }
}