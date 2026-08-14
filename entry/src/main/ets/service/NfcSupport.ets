/**
 * NFC 可用性检测与提示文案：
 *  1. canIUse 查询平台系统能力 → 不支持 = UNSUPPORTED
 *  2. nfcController.isNfcAvailable() 芯片可用性 → 不可用 = HARDWARE_MISSING（模拟器等）
 *  3. isNfcOpen() 开关状态 → 关闭 = SWITCH_OFF
 */
import { nfcController } from '@kit.ConnectivityKit';
import { NfcAvailability } from '../model/UiState';

export class NfcSupport {
  /** 检测当前 NFC 可用性（全部异常兜底为最严格状态） */
  static check(): NfcAvailability {
    let syscap = false;
    try {
      syscap = canIUse('SystemCapability.Communication.NFC.Core');
    } catch (e) {
      syscap = false;
    }
    if (!syscap) {
      return NfcAvailability.UNSUPPORTED;
    }
    let available = false;
    try {
      available = nfcController.isNfcAvailable();
    } catch (e) {
      available = false;
    }
    if (!available) {
      return NfcAvailability.HARDWARE_MISSING;
    }
    let open = false;
    try {
      open = nfcController.isNfcOpen();
    } catch (e) {
      open = false;
    }
    return open ? NfcAvailability.READY : NfcAvailability.SWITCH_OFF;
  }

  /** 各状态对应的用户提示文案（弹窗/Toast 共用） */
  static messageFor(avail: NfcAvailability): string {
    if (avail === NfcAvailability.SWITCH_OFF) {
      return '系统 NFC 开关未打开，请到系统设置开启后重试';
    }
    if (avail === NfcAvailability.UNSUPPORTED) {
      return '当前设备不支持 NFC';
    }
    if (avail === NfcAvailability.HARDWARE_MISSING) {
      return 'NFC 硬件不可用（模拟器环境无 NFC 芯片）';
    }
    return '';
  }

  /** 弹窗内 NFC 项副标题 */
  static labelFor(avail: NfcAvailability): string {
    if (avail === NfcAvailability.SWITCH_OFF) {
      return 'NFC（开关未开启）';
    }
    if (avail === NfcAvailability.UNSUPPORTED) {
      return 'NFC（设备不支持）';
    }
    if (avail === NfcAvailability.HARDWARE_MISSING) {
      return 'NFC（硬件不可用）';
    }
    return 'NFC';
  }

  /** 该状态是否允许点击发起连接 */
  static selectable(avail: NfcAvailability): boolean {
    return avail === NfcAvailability.READY;
  }
}