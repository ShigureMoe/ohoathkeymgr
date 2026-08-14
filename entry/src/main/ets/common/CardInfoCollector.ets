/**
 * 卡片信息收集器：对一张已建立的卡片连接（NFC 或 USB）执行
 *  1. SELECT OATH → 解析 OATH version / 密码保护状态（逆向自 yubikit/oath.py _parse_select）
 *  2. SELECT MANAGEMENT → INS_READ_CONFIG 分页读取 DeviceInfo TLV（逆向自 yubikit/management.py）
 *  3. 组装与 ykman info / ykman oath info 对应字段的 JSON 对象
 */
import { CardTransport, SmartCardProtocol, ApduUtils, Tlv, Aids } from './ApduUtils';
import { CardInfoResult, YkmanInfoJson, OathInfoJson } from '../model/DeviceInfoModel';

/** OATH SELECT 响应 TLV tag（逆向自 oath.py） */
const TAG_VERSION = 0x79;
const TAG_CHALLENGE = 0x74;

/** Management DeviceInfo TLV tag（逆向自 management.py） */
const TAG_USB_SUPPORTED = 0x01;
const TAG_SERIAL = 0x02;
const TAG_USB_ENABLED = 0x03;
const TAG_FORM_FACTOR = 0x04;
const TAG_VERSION_DEVINFO = 0x05;
const TAG_NFC_SUPPORTED = 0x0D;
const TAG_NFC_ENABLED = 0x0E;
const TAG_NFC_RESTRICTED = 0x17;
const TAG_MORE_DATA = 0x10;

/** Management 应用指令（逆向自 management.py） */
const INS_READ_CONFIG = 0x1D;

/** CAPABILITY 位掩码（逆向自 management.py） */
const CAP_OTP = 0x01;
const CAP_U2F = 0x02;
const CAP_OPENPGP = 0x08;
const CAP_PIV = 0x10;
const CAP_OATH = 0x20;
const CAP_HSMAUTH = 0x100;
const CAP_FIDO2 = 0x200;

/** FORM_FACTOR 映射（逆向自 management.py FORM_FACTOR.__str__） */
const FORM_FACTOR_NAMES: Record<number, string> = {
  '0': 'Unknown',
  '1': 'Keychain (USB-A)',
  '2': 'Nano (USB-A)',
  '3': 'Keychain (USB-C)',
  '4': 'Nano (USB-C)',
  '5': 'Keychain (USB-C, Lightning)',
  '6': 'Bio (USB-A)',
  '7': 'Bio (USB-C)'
};

/** 应用名展开（对标 CAPABILITY.display_name） */
function capabilityNames(mask: number): string[] {
  const names: string[] = [];
  const items: Array<[number, string]> = [
    [CAP_FIDO2, 'FIDO2'], [CAP_HSMAUTH, 'YubiHSM Auth'], [CAP_OATH, 'OATH'],
    [CAP_OPENPGP, 'OpenPGP'], [CAP_PIV, 'PIV'], [CAP_U2F, 'FIDO U2F'], [CAP_OTP, 'Yubico OTP']
  ];
  for (const item of items) {
    if ((mask & item[0]) !== 0) {
      names.push(item[1]);
    }
  }
  return names;
}

/** 版本字节 [ma, mi, pa] → "x.y.z" 或 null */
function versionTriple(data: Uint8Array | undefined): [number, number, number] | null {
  if (data === undefined || data.length < 3) {
    return null;
  }
  return [data[0], data[1], data[2]];
}

/** 解析 ASCII 版本字符串 "x.y.z"（逆向自 core Version.from_string，正则 \b\d+.\d.\d\b） */
function parseVersionString(text: string): [number, number, number] | null {
  const pattern = new RegExp('\\b(\\d+)\\.(\\d)\\.(\\d)\\b');
  const m = text.match(pattern);
  if (m === null || m.length < 4) {
    return null;
  }
  return [parseInt(m[1]), parseInt(m[2]), parseInt(m[3])];
}

/** 版本三元组 → "x.y.z"；null → "unknown" */
function formatVersion(v: [number, number, number] | null): string {
  if (v === null) {
    return 'unknown';
  }
  return v[0] + '.' + v[1] + '.' + v[2];
}

/** 设备类型名推导（简化的 support.get_name 逆向） */
function deviceTypeName(info: DeviceInfoState): string {
  const version = info.firmwareVersion !== 'unknown' ? parseVersionString(info.firmwareVersion) : null;
  if (version === null) {
    return 'Unknown';
  }
  const major = version[0];
  if (major === 3) {
    return 'YubiKey NEO';
  }
  if (major === 4) {
    const only = info.usbSupported & ~(CAP_OTP | CAP_U2F);
    if ((info.usbSupported & (CAP_OTP | CAP_U2F)) === (CAP_OTP | CAP_U2F) && only === 0) {
      return 'YubiKey Edge';
    }
    return 'YubiKey 4';
  }
  if (major === 5) {
    const isNano = info.formFactorCode === 2 || info.formFactorCode === 4;
    const isC = info.formFactorCode === 3 || info.formFactorCode === 4 || info.formFactorCode === 7;
    const isBio = info.formFactorCode === 6 || info.formFactorCode === 7;
    const fidoOnly = (info.usbSupported & (CAP_OTP | CAP_OATH | CAP_PIV | CAP_OPENPGP | CAP_HSMAUTH)) === 0 &&
      (info.usbSupported & (CAP_U2F | CAP_FIDO2)) !== 0;
    if (info.serial === null && fidoOnly) {
      return 'Security Key';
    }
    const parts: string[] = ['YubiKey'];
    if (!isBio) {
      parts.push('5');
    }
    if (info.formFactorCode === 5) {
      parts.push('Ci');
    } else if (isC) {
      parts.push('C');
    }
    if (isNano) {
      parts.push('Nano');
    }
    return parts.join(' ').replace('5 C', '5C');
  }
  return 'YubiKey';
}

/** 收集过程中的中间状态 */
interface DeviceInfoState {
  serial: number | null;
  formFactorCode: number;
  usbEnabled: number;
  usbSupported: number;
  nfcSupported: number;
  nfcEnabled: number;
  nfcRestricted: boolean;
  firmwareVersion: string;
}

class InfoStateHolder implements DeviceInfoState {
  serial: number | null = null;
  formFactorCode: number = 0;
  usbEnabled: number = 0;
  usbSupported: number = 0;
  nfcSupported: number = 0;
  nfcEnabled: number = 0;
  nfcRestricted: boolean = false;
  firmwareVersion: string = 'unknown';
}

/** 应用一个 DeviceInfo TLV（逆向自 management.py DeviceInfo.parse_tlvs） */
function applyDeviceInfoTlv(state: InfoStateHolder, tag: number, value: Uint8Array): void {
  if (tag === TAG_SERIAL) {
    state.serial = ApduUtils.bytesToInt(value) === 0 ? null : ApduUtils.bytesToInt(value);
  } else if (tag === TAG_FORM_FACTOR) {
    state.formFactorCode = ApduUtils.bytesToInt(value) & 0x0F;
  } else if (tag === TAG_USB_SUPPORTED) {
    state.usbSupported = ApduUtils.bytesToInt(value);
  } else if (tag === TAG_USB_ENABLED) {
    state.usbEnabled = ApduUtils.bytesToInt(value);
  } else if (tag === TAG_NFC_SUPPORTED) {
    state.nfcSupported = ApduUtils.bytesToInt(value);
  } else if (tag === TAG_NFC_ENABLED) {
    state.nfcEnabled = ApduUtils.bytesToInt(value);
  } else if (tag === TAG_NFC_RESTRICTED) {
    state.nfcRestricted = value.length > 0 && value[0] === 1;
  } else if (tag === TAG_VERSION_DEVINFO) {
    const vt = versionTriple(value);
    if (vt !== null) {
      state.firmwareVersion = formatVersion(vt);
    }
  }
}

export class CardInfoCollector {
  /**
   * 轻量读取卡片序列号（Management DeviceInfo 第一页）。
   * 返回 null 表示不可读（老设备/管理应用受限）。
   */
  static async readSerial(conn: CardTransport): Promise<number | null> {
    const protocol = new SmartCardProtocol(conn);
    try {
      await protocol.select(Aids.MANAGEMENT);
      const encoded = await protocol.sendApdu(0x00, INS_READ_CONFIG, 0, 0x00, new Uint8Array(0), 0);
      if (encoded.length < 1) {
        return null;
      }
      const lenField = encoded[0];
      const payload = encoded.subarray(1, 1 + lenField);
      const pageTlvs = Tlv.parseDict(payload);
      const serialTlv = pageTlvs.get(TAG_SERIAL);
      if (serialTlv === undefined || serialTlv.length === 0) {
        return null;
      }
      const serial = ApduUtils.bytesToInt(serialTlv);
      return serial === 0 ? null : serial;
    } catch (e) {
      return null;
    }
  }

  /**
   * 在给定传输上收集 ykman info + ykman oath info
   */
  static async collect(conn: CardTransport, transportName: string): Promise<CardInfoResult> {
    const protocol = new SmartCardProtocol(conn);

    // ---- OATH 应用 ----
    const oathSelect = await protocol.select(Aids.OATH);
    const oathTlvs = Tlv.parseDict(oathSelect);
    const oathVersionData = oathTlvs.get(TAG_VERSION);
    const challenge = oathTlvs.get(TAG_CHALLENGE);
    const locked = challenge !== undefined && challenge.length > 0;
    const oathInfo: OathInfoJson = {
      oathVersion: formatVersion(versionTriple(oathVersionData)),
      passwordProtection: locked ? 'enabled' : 'disabled',
      locked: locked
    };

    // ---- Management 应用（不可用则降级为 unknown）----
    const state = new InfoStateHolder();
    try {
      const mgmtSelect = await protocol.select(Aids.MANAGEMENT);
      // 管理应用 SELECT 响应为 ASCII 固件版本字符串（逆向自 _ManagementSmartCardBackend）
      const versionFromSelect = parseVersionString(ApduUtils.utf8Decode(mgmtSelect));
      if (versionFromSelect !== null) {
        state.firmwareVersion = formatVersion(versionFromSelect);
      }

      // 分页读取 DeviceInfo：响应 = [长度字节] + TLV；TAG_MORE_DATA 表示剩余页数
      let moreData = 1;
      let page = 0;
      while (moreData > 0) {
        moreData -= 1;
        const encoded = await protocol.sendApdu(0x00, INS_READ_CONFIG, page, 0x00, new Uint8Array(0), 0);
        if (encoded.length < 1) {
          break;
        }
        const lenField = encoded[0];
        const payload = encoded.subarray(1, 1 + lenField);
        const pageTlvs = Tlv.parseDict(payload);
        const more = pageTlvs.get(TAG_MORE_DATA);
        if (more !== undefined && more.length > 0) {
          moreData = more[0];
        }
        pageTlvs.delete(TAG_MORE_DATA);
        pageTlvs.forEach((value: Uint8Array, tag: number) => {
          applyDeviceInfoTlv(state, tag, value);
        });
        page += 1;
      }
    } catch (e) {
      // 管理应用不可用或读取失败：保持降级值
    }

    // ---- 组装 ----
    let nfcTransport = 'unsupported';
    if (state.nfcSupported !== 0) {
      nfcTransport = state.nfcRestricted
        ? 'restricted'
        : (state.nfcEnabled !== 0 ? 'enabled' : 'disabled');
    }

    const ykmanInfo: YkmanInfoJson = {
      deviceType: deviceTypeName(state),
      serialNumber: state.serial,
      firmwareVersion: state.firmwareVersion,
      formFactor: FORM_FACTOR_NAMES[state.formFactorCode] === undefined ? 'Unknown' : FORM_FACTOR_NAMES[state.formFactorCode],
      usbInterfaces: capabilityNames(state.usbEnabled),
      nfcTransport: nfcTransport,
      applications: capabilityNames(state.usbSupported)
    };

    const result: CardInfoResult = {
      transport: transportName,
      ykmanInfo: ykmanInfo,
      oathInfo: oathInfo
    };
    return result;
  }
}