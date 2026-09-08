/**
 * 统一日志与错误消息工具
 * - Log：hilog 薄封装，单一 DOMAIN/TAG 来源，替代各文件局部
 *   LOG_DOMAIN/LOG_TAG/NfcLog/DOMAIN 常量与内联的 (0x0000, 'OathKeeper')
 * - errorMessage()：安全提取 catch(e) 的消息——Error、BusinessError（非 Error
 *   子类但结构带 message）、string 等抛出值均不返回 undefined，
 *   替代裸 (e as Error).message（非 Error 抛出时会得到 undefined）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

export class Log {
  static readonly DOMAIN = 0x0000;
  static readonly TAG = 'OathKeeper';

  static debug(fmt: string, ...args: Array<string | number>): void {
    hilog.debug(Log.DOMAIN, Log.TAG, fmt, ...args);
  }

  static info(fmt: string, ...args: Array<string | number>): void {
    hilog.info(Log.DOMAIN, Log.TAG, fmt, ...args);
  }

  static warn(fmt: string, ...args: Array<string | number>): void {
    hilog.warn(Log.DOMAIN, Log.TAG, fmt, ...args);
  }

  static error(fmt: string, ...args: Array<string | number>): void {
    hilog.error(Log.DOMAIN, Log.TAG, fmt, ...args);
  }
}

/** 安全提取错误消息：兼容 Error、BusinessError（结构带 message）、string 等抛出值 */
export function errorMessage(e: Object): string {
  if (e instanceof Error) {
    return e.message;
  }
  const msg = (e as Error).message;
  if (typeof msg === 'string' && msg.length > 0) {
    return msg;
  }
  return String(e);
}
