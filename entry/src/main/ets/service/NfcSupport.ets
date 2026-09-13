/**
 * NFC 可用性检测与提示文案：
 *  1. canIUse 查询平台系统能力 → 不支持 = UNSUPPORTED
 *  2. nfcController.isNfcAvailable() 芯片可用性 → 不可用 = HARDWARE_MISSING（模拟器等）
 *  3. isNfcOpen() 开关状态 → 关闭 = SWITCH_OFF
 */
import { nfcController } from '@kit.ConnectivityKit';
import { NfcAvailability } from '../model/UiState';
import { ResUtil } from '../common/ResUtil';

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

  /** 各状态对应的用户提示文案（弹窗/Toast 共用；资源化取串） */
  static messageFor(avail: NfcAvailability): string {
    if (avail === NfcAvailability.SWITCH_OFF) {
      return ResUtil.str($r('app.string.nfc_switch_off'));
    }
    if (avail === NfcAvailability.UNSUPPORTED) {
      return ResUtil.str($r('app.string.nfc_unsupported'));
    }
    if (avail === NfcAvailability.HARDWARE_MISSING) {
      return ResUtil.str($r('app.string.nfc_unavailable'));
    }
    return '';
  }

  /** 弹窗内 NFC 项副标题（'NFC' 技术缩写不译） */
  static labelFor(avail: NfcAvailability): string {
    if (avail === NfcAvailability.SWITCH_OFF) {
      return ResUtil.str($r('app.string.nfc_label_switch_off'));
    }
    if (avail === NfcAvailability.UNSUPPORTED) {
      return ResUtil.str($r('app.string.nfc_label_unsupported'));
    }
    if (avail === NfcAvailability.HARDWARE_MISSING) {
      return ResUtil.str($r('app.string.nfc_label_unavailable'));
    }
    return 'NFC';
  }

  /** 该状态是否允许点击发起连接 */
  static selectable(avail: NfcAvailability): boolean {
    return avail === NfcAvailability.READY;
  }
}