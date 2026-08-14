/**
 * 扫码服务（M5-4 / S4）：调用 Scan Kit 默认界面扫码（系统预授权相机）。
 * 返回识别到的码值文本，由调用方走 otpauth 解析与写入管线。
 */
import { scanCore, scanBarcode } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';

export class ScanService {
  /** 拉起系统扫码界面；返回原始码值（不支持默认界面扫码时抛错） */
  static async scan(context: common.Context): Promise<string> {
    // API 26 起可先查询设备是否支持默认界面扫码
    let supported = true;
    try {
      supported = scanCore.isDefaultScanSupported();
    } catch (e) {
      supported = true;
    }
    if (!supported) {
      throw new Error('当前设备不支持默认界面扫码');
    }
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: true
    };
    const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
    return result.originalValue;
  }
}