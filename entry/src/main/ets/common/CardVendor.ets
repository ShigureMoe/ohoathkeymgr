/**
 * 卡片设备身份与厂商识别
 * 对齐 canokey-manager 的 is_canokey 三层模式：
 *  - 传输层只暴露原始身份（CardTransport.getIdentity()，逆向自 connection.pid/atr）
 *  - 厂商识别规则集中在本文件 CardDetector（逆向自 canokey.py is_canokey 纯函数）
 *  - workaround 决策在协议层按 厂商+固件版本 组装（如 OathSession 的 readOnSuccess）
 * 新增厂商只需在 CardDetector 加规则，新增 workaround 只需在决策处加分支，传输层不动。
 */

/** 设备身份原始信息（USB: VID/PID；NFC: ATS 历史字节），由传输层提供 */
export interface CardIdentity {
  /** USB 厂商 ID（非 USB 传输为 undefined） */
  usbVendorId?: number;
  /** USB 产品 ID（非 USB 传输为 undefined） */
  usbProductId?: number;
  /** NFC ATS 历史字节（非 NFC 传输或不可读时为 undefined） */
  historicalBytes?: Uint8Array;
}

/** 卡片厂商（依据身份信息识别；UNKNOWN 表示未识别的第三方 CCID/NFC 卡） */
export enum CardVendor {
  YUBIKEY = 0,
  CANOKEY = 1,
  UNKNOWN = 2,
}

/** CanoKey USB 标识（逆向自 canokey-manager core PID.CK_FIDO_CCID，VID 为 CanoKeys 组织） */
const CANOKEY_USB_VID = 0x20A0;
const CANOKEY_USB_PID = 0x42D4;
/** Yubico（YubiKey）USB 厂商 ID（yubikit core PID 枚举所属厂商） */
const YUBIKEY_USB_VID = 0x1050;

/** 厂商识别（逆向自 canokey-manager is_canokey：USB 按 VID/PID，NFC 按历史字节含 "CanoKey"） */
export class CardDetector {
  static detect(identity: CardIdentity): CardVendor {
    if (identity.usbVendorId === CANOKEY_USB_VID && identity.usbProductId === CANOKEY_USB_PID) {
      return CardVendor.CANOKEY;
    }
    if (identity.usbVendorId === YUBIKEY_USB_VID) {
      return CardVendor.YUBIKEY;
    }
    const hist = identity.historicalBytes;
    if (hist !== undefined && CardDetector.asciiOf(hist).includes('CanoKey')) {
      return CardVendor.CANOKEY;
    }
    return CardVendor.UNKNOWN;
  }

  /** 字节转可见 ASCII 字符串（不可见字节替换为 '.'，用于子串匹配） */
  private static asciiOf(data: Uint8Array): string {
    let text = '';
    for (let i = 0; i < data.length; i++) {
      const c = data[i];
      text += (c >= 0x20 && c <= 0x7E) ? String.fromCharCode(c) : '.';
    }
    return text;
  }
}
