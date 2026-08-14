/**
 * OATH 凭据数据模型（对标 yubikit/oath.py）
 * CredentialInfo：卡片上的凭据（LIST/CALCULATE ALL 解析产物）
 * CredentialData：写入用凭据数据（手动表单/otpauth 解析产物）
 */
import { util } from '@kit.ArkTS';

/** OATH 凭据类型（指令字节高 4 位，见 oath.py OATH_TYPE） */
export enum OtpType {
  HOTP = 0x10,
  TOTP = 0x20
}

/** 哈希算法（见 oath.py HASH_ALGORITHM） */
export enum HashAlgorithm {
  SHA1 = 0x01,
  SHA256 = 0x02,
  SHA512 = 0x03
}

/** 卡片上的凭据描述（LIST / CALCULATE ALL 返回） */
export class CredentialInfo {
  /** 设备标识（由 salt 派生，重置后变化） */
  deviceId: string;
  /** 卡片上的凭据 ID（原始名称字节，含 [period/][issuer:]account） */
  credId: Uint8Array;
  /** credId 的 UTF-8 文本 */
  name: string;
  /** 解析出的 Issuer（无则为空串） */
  issuer: string;
  /** 解析出的 Account */
  account: string;
  otpType: OtpType;
  /** TOTP 周期秒；HOTP 为 0 */
  period: number;
  /** 是否触摸凭据（LIST 时未知，CALCULATE ALL 时才确定） */
  touch: boolean;

  constructor(deviceId: string, credId: Uint8Array, issuer: string, account: string,
    otpType: OtpType, period: number, touch: boolean) {
    this.deviceId = deviceId;
    this.credId = credId;
    this.name = OathName.encode(credId);
    this.issuer = issuer;
    this.account = account;
    this.otpType = otpType;
    this.period = period;
    this.touch = touch;
  }

  /** 展示用标题：优先 Issuer，其次 Account */
  getLabel(): string {
    if (this.issuer.length > 0) {
      return this.issuer;
    }
    return this.account;
  }
}

/** 单次计算出的码值（code + 有效期，对标 oath.py Code） */
export class CodeInfo {
  code: string;
  validFrom: number;
  validTo: number;

  constructor(code: string, validFrom: number, validTo: number) {
    this.code = code;
    this.validFrom = validFrom;
    this.validTo = validTo;
  }
}

/** 写入卡片前的凭据数据（手动表单 / otpauth 解析共用） */
export class CredentialData {
  issuer: string = '';
  account: string = '';
  secret: Uint8Array = new Uint8Array(0);
  otpType: OtpType = OtpType.TOTP;
  algorithm: HashAlgorithm = HashAlgorithm.SHA1;
  digits: number = 6;
  /** TOTP 周期秒，默认 30 */
  period: number = 30;
  /** HOTP 初始计数器，默认 0 */
  counter: number = 0;
  /** 需要触摸（设备固件不支持时置 false） */
  touch: boolean = false;

  /** 重名判定键（Issuer + Account） */
  getDisplayName(): string {
    if (this.issuer.length > 0) {
      return this.issuer + ':' + this.account;
    }
    return this.account;
  }
}

/** 凭据 ID 解析结果（对标 oath.py _parse_cred_id） */
export class CredentialNameParts {
  issuer: string = '';
  account: string = '';
  /** TOTP 周期秒；HOTP 为 0 */
  period: number = 0;
}

/** 凭据 ID 文本编解码（对标 oath.py _format_cred_id / _parse_cred_id） */
export class OathName {
  static readonly DEFAULT_PERIOD = 30;

  /** UTF-8 编码 */
  static encode(credId: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(credId);
  }

  /** 格式化凭据 ID：[period/][issuer:]account */
  static format(issuer: string, account: string, otpType: OtpType, period: number): string {
    let id = '';
    if (otpType === OtpType.TOTP && period !== OathName.DEFAULT_PERIOD) {
      id = id + period + '/';
    }
    if (issuer.length > 0) {
      id = id + issuer + ':';
    }
    return id + account;
  }

  /** 解析凭据 ID → issuer/account/period */
  static parse(credId: string, otpType: OtpType): CredentialNameParts {
    const parts = new CredentialNameParts();
    if (otpType === OtpType.TOTP) {
      const pattern = new RegExp('^((\\d+)/)?(([^:]+):)?(.+)$');
      const m = credId.match(pattern);
      if (m !== null && m.length >= 6) {
        const periodStr = m[2];
        const issuer = m[4];
        parts.period = periodStr !== undefined && periodStr !== null && periodStr.length > 0
          ? parseInt(periodStr) : OathName.DEFAULT_PERIOD;
        parts.issuer = issuer !== undefined && issuer !== null ? issuer : '';
        parts.account = m[5] === undefined ? credId : m[5];
      } else {
        parts.period = OathName.DEFAULT_PERIOD;
        parts.account = credId;
      }
      return parts;
    }
    if (credId.indexOf(':') >= 0 && credId.charAt(0) !== ':') {
      const idx = credId.indexOf(':');
      parts.issuer = credId.substring(0, idx);
      parts.account = credId.substring(idx + 1);
    } else {
      parts.issuer = '';
      parts.account = credId.charAt(0) === ':' ? credId.substring(1) : credId;
    }
    parts.period = 0;
    return parts;
  }
}