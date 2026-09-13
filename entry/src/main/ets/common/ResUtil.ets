/**
 * 资源取串工具（app-i18n / D3）：服务层（非组件上下文）获取 string 资源的唯一入口。
 *  - str：无参词条取串；AppContextHolder.context 未就绪（极端时机）时返回空串防御，不抛出
 *  - strWithArgs：带 %s/%d 占位符词条取串，参数按序替换
 * 组件层文案直接用 $r() 直传 Resource；toast(msg: string) 回调与服务层 throw 场景经本类取串。
 */
import { AppContextHolder } from './AppContextHolder';

export class ResUtil {
  /** 取无参 string 资源；context 未就绪或取串异常时返回空串（不崩溃） */
  static str(res: Resource): string {
    const ctx = AppContextHolder.context;
    if (ctx === undefined) {
      return '';
    }
    try {
      return ctx.resourceManager.getStringSync(res.id);
    } catch (e) {
      // 资源缺失等异常：回落空串，由调用链按原始错误呈现
      return '';
    }
  }

  /** 取带 %s/%d 占位符的 string 资源并按序替换参数 */
  static strWithArgs(res: Resource, ...args: Array<string | number>): string {
    const ctx = AppContextHolder.context;
    if (ctx === undefined) {
      return '';
    }
    try {
      return ctx.resourceManager.getStringSync(res.id, ...args);
    } catch (e) {
      // 同 str：异常回落空串
      return '';
    }
  }
}
