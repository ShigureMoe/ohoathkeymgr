/**
 * OATH 协议封装（对标 yubikit/oath.py 的 OathSession）
 * 覆盖 REQ M2 全部需求：SELECT / VALIDATE / LIST / CALCULATE / CALCULATE ALL /
 * PUT / DELETE / SET CODE / RESET。
 * 密钥派生(PBKDF2-HMAC-SHA1×1000)与 HMAC 应答基于 cryptoFramework。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { Aids, ApduUtils, CardTransport, SmartCardProtocol, Tlv } from '../common/ApduUtils';
import {
  CodeInfo, CredentialData, CredentialInfo, HashAlgorithm, OathName, OtpType
} from '../model/Credential';

/** OATH 指令与 TLV tag（逆向自 oath.py） */
export class OathConst {
  static readonly INS_LIST = 0xA1;
  static readonly INS_PUT = 0x01;
  static readonly INS_DELETE = 0x02;
  static readonly INS_SET_CODE = 0x03;
  static readonly INS_RESET = 0x04;
  static readonly INS_CALCULATE = 0xA2;
  static readonly INS_VALIDATE = 0xA3;
  static readonly INS_CALCULATE_ALL = 0xA4;

  static readonly TAG_NAME = 0x71;
  static readonly TAG_NAME_LIST = 0x72;
  static readonly TAG_KEY = 0x73;
  static readonly TAG_CHALLENGE = 0x74;
  static readonly TAG_RESPONSE = 0x75;
  static readonly TAG_TRUNCATED = 0x76;
  static readonly TAG_HOTP = 0x77;
  static readonly TAG_PROPERTY = 0x78;
  static readonly TAG_VERSION = 0x79;
  static readonly TAG_IMF = 0x7A;
  static readonly TAG_TOUCH = 0x7C;

  static readonly DEFAULT_PERIOD = 30;
  static readonly MASK_TYPE = 0xF0;
  static readonly PROP_REQUIRE_TOUCH = 0x02;
  static readonly HMAC_MIN_KEY_SIZE = 14;

  /** YubiKey 固件 ≥4.2.6 支持触摸属性（4.2.6 = 4 2 6） */
  static readonly TOUCH_MIN_FW = [4, 2, 6];
}

/** CALCULATE ALL 单条结果（无码值者为 HOTP/触摸凭据） */
export class CalculateAllEntry {
  credId: Uint8Array;
  name: string;
  otpType: OtpType;
  /** TOTP 周期秒；HOTP 为 0 */
  period: number;
  touch: boolean;
  code: CodeInfo | null;

  constructor(credId: Uint8Array, name: string, otpType: OtpType, period: number,
    touch: boolean, code: CodeInfo | null) {
    this.credId = credId;
    this.name = name;
    this.otpType = otpType;
    this.period = period;
    this.touch = touch;
    this.code = code;
  }
}

/** OATH 会话：一次卡片连接上的协议上下文（SELECT 后持有 salt/challenge） */
export class OathSession {
  private protocol: SmartCardProtocol;
  private salt: Uint8Array | null;
  private challenge: Uint8Array | null;
  private versionText: string;
  private deviceId: string;
  /** 卡片是否设置了安全密码（与是否解锁无关，重置/移除密码后变化） */
  private hasKey: boolean;

  private constructor(protocol: SmartCardProtocol, salt: Uint8Array | null,
    challenge: Uint8Array | null, versionText: string, deviceId: string, hasKey: boolean) {
    this.protocol = protocol;
    this.salt = salt;
    this.challenge = challenge;
    this.versionText = versionText;
    this.deviceId = deviceId;
    this.hasKey = hasKey;
  }

  /** SELECT OATH 应用并解析版本/lock 状态 */
  static async open(transport: CardTransport): Promise<OathSession> {
    const protocol = new SmartCardProtocol(transport);
    return OathSession.openWithProtocol(protocol);
  }

  private static async openWithProtocol(protocol: SmartCardProtocol): Promise<OathSession> {
    let response: Uint8Array;
    try {
      response = await protocol.select(Aids.OATH);
    } catch (e) {
      throw new Error('OATH 应用不可用：' + (e as Error).message);
    }
    const map = Tlv.parseDict(response);
    const versionData = map.get(OathConst.TAG_VERSION);
    const versionText = OathSession.versionToText(versionData);
    let salt: Uint8Array | null = null;
    const saltData = map.get(OathConst.TAG_NAME);
    if (saltData !== undefined && saltData.length > 0) {
      salt = saltData;
    }
    let challenge: Uint8Array | null = null;
    const challengeData = map.get(OathConst.TAG_CHALLENGE);
    if (challengeData !== undefined && challengeData.length > 0) {
      challenge = challengeData;
    }
    const deviceId = salt === null ? '' : await OathSession.deriveDeviceId(salt);
    return new OathSession(protocol, salt, challenge, versionText, deviceId, challenge !== null);
  }

  getVersion(): string {
    return this.versionText;
  }

  getDeviceId(): string {
    return this.deviceId;
  }

  /** 是否已设置安全密码（SELECT 响应含 challenge，解锁后仍保持） */
  getHasKey(): boolean {
    return this.hasKey;
  }

  /** 当前是否处于锁定态（解锁后即 false，直到换卡片/重开会话） */
  isLocked(): boolean {
    return this.challenge !== null;
  }

  /** 由密码派生访问密钥（PBKDF2-HMAC-SHA1×1000, 16 字节） */
  async deriveKey(password: string): Promise<Uint8Array> {
    const salt = this.salt;
    if (salt === null) {
      throw new Error('缺少卡片 salt');
    }
    const passBytes = OathSession.utf8Encode(password);
    const kdf = cryptoFramework.createKdf('PBKDF2|SHA1');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: passBytes,
      salt: salt,
      iterations: 1000,
      keySize: 16
    };
    const derived: cryptoFramework.DataBlob = await kdf.generateSecret(spec);
    return derived.data;
  }

  /** VALIDATE：挑战-响应解锁；失败抛错（对标 oath.py validate） */
  async validate(key: Uint8Array): Promise<void> {
    const deviceChallenge = this.challenge;
    if (deviceChallenge === null) {
      return;
    }
    const response = await OathSession.hmacSha1(key, deviceChallenge);
    const clientChallenge = await OathSession.randomBytes(8);
    const data = ApduUtils.concat(
      OathSession.wrap(OathConst.TAG_RESPONSE, response),
      OathSession.wrap(OathConst.TAG_CHALLENGE, clientChallenge));
    const resp = await this.protocol.sendApdu(0, OathConst.INS_VALIDATE, 0, 0, data, 0);
    const map = Tlv.parseDict(resp);
    const verification = map.get(OathConst.TAG_RESPONSE);
    if (verification === undefined || !ApduUtils.constantEquals(verification, await OathSession.hmacSha1(key, clientChallenge))) {
      throw new Error('验证失败，密码错误');
    }
    this.challenge = null;
  }

  /** SET CODE：设置新密码（key=null 表示移除密码；对标 oath.py set_key/unset_key） */
  async setCode(key: Uint8Array | null): Promise<void> {
    let data: Uint8Array;
    if (key === null) {
      data = OathSession.wrap(OathConst.TAG_KEY, new Uint8Array(0));
    } else {
      const challenge = await OathSession.randomBytes(8);
      const response = await OathSession.hmacSha1(key, challenge);
      const keyField = ApduUtils.concat(new Uint8Array([0x21]), key); // TOTP|SHA1 头字节
      data = ApduUtils.concat(
        OathSession.wrap(OathConst.TAG_KEY, keyField),
        OathSession.wrap(OathConst.TAG_CHALLENGE, challenge),
        OathSession.wrap(OathConst.TAG_RESPONSE, response));
    }
    await this.protocol.sendApdu(0, OathConst.INS_SET_CODE, 0, 0, data, 0);
    this.challenge = null;
    this.hasKey = key !== null;
  }

  /** RESET：重置 OATH 应用并刷新会话状态 */
  async reset(): Promise<void> {
    await this.protocol.sendApdu(0, OathConst.INS_RESET, 0xDE, 0xAD, new Uint8Array(0), 0);
    const fresh = await OathSession.openWithProtocol(this.protocol);
    this.salt = fresh.salt;
    this.challenge = fresh.challenge;
    this.versionText = fresh.versionText;
    this.deviceId = fresh.deviceId;
    this.hasKey = fresh.hasKey;
  }

  /** LIST：获取凭据列表（M2-3） */
  async listCredentials(): Promise<CredentialInfo[]> {
    const resp = await this.protocol.sendApdu(0, OathConst.INS_LIST, 0, 0, new Uint8Array(0), 0);
    const tlvs = Tlv.parseList(resp);
    const creds: CredentialInfo[] = [];
    for (const tlv of tlvs) {
      if (tlv.tag !== OathConst.TAG_NAME_LIST) {
        continue;
      }
      const v = tlv.value;
      if (v.length < 1) {
        continue;
      }
      const mask = v[0] & OathConst.MASK_TYPE;
      const otpType: OtpType = mask === 0x10 ? OtpType.HOTP : OtpType.TOTP;
      const nameBytes = v.subarray(1);
      const name = OathName.encode(nameBytes);
      const parts = OathName.parse(name, otpType);
      creds.push(new CredentialInfo(this.deviceId, nameBytes, parts.issuer, parts.account,
        otpType, parts.period, false));
    }
    return creds;
  }

  /** CALCULATE：单个凭据计算（M2-4；触摸凭据由"等待触摸"语义：ERS 协议中该指令会等待触摸） */
  async calculate(credId: Uint8Array, otpType: OtpType, period: number, timestampSec: number): Promise<CodeInfo> {
    const challenge = otpType === OtpType.TOTP
      ? OathSession.challengeFor(period, timestampSec)
      : new Uint8Array(0);
    const data = ApduUtils.concat(
      OathSession.wrap(OathConst.TAG_NAME, credId),
      OathSession.wrap(OathConst.TAG_CHALLENGE, challenge));
    // P2=0x01 截断模式（对标 oath.py calculate_code）：响应 = Tlv(0x76, [digits, 4字节码])
    const resp = await this.protocol.sendApdu(0, OathConst.INS_CALCULATE, 0, 0x01, data, 0);
    const map = Tlv.parseDict(resp);
    const truncated = map.get(OathConst.TAG_TRUNCATED);
    if (truncated === undefined || truncated.length < 5) {
      throw new Error('CALCULATE 响应异常');
    }
    return OathSession.formatCode(truncated, otpType, period, timestampSec);
  }

  /** CALCULATE ALL：批量取 TOTP（M2-3/M2-10；非 30s 周期凭据按实际周期重算） */
  async calculateAll(timestampSec: number): Promise<CalculateAllEntry[]> {
    const challenge = OathSession.challengeFor(OathConst.DEFAULT_PERIOD, timestampSec);
    const resp = await this.protocol.sendApdu(0, OathConst.INS_CALCULATE_ALL, 0, 0x01,
      OathSession.wrap(OathConst.TAG_CHALLENGE, challenge), 0);
    const tlvs = Tlv.parseList(resp);
    const entries: CalculateAllEntry[] = [];
    let i = 0;
    while (i < tlvs.length) {
      const nameTlv = tlvs[i];
      if (nameTlv.tag !== OathConst.TAG_NAME || i + 1 >= tlvs.length) {
        i += 1;
        continue;
      }
      const respTlv = tlvs[i + 1];
      const credId = nameTlv.value;
      const name = OathName.encode(credId);
      let otpType = OtpType.TOTP;
      if (respTlv.tag === OathConst.TAG_HOTP) {
        otpType = OtpType.HOTP;
      }
      const parts = OathName.parse(name, otpType);
      let touch = false;
      if (respTlv.tag === OathConst.TAG_TOUCH) {
        touch = true;
      }
      let code: CodeInfo | null = null;
      if (respTlv.tag === OathConst.TAG_TRUNCATED) {
        if (parts.period === OathConst.DEFAULT_PERIOD) {
          code = OathSession.formatCode(respTlv.value, OtpType.TOTP, parts.period, timestampSec);
        } else {
          // 非标准周期：按实际周期单独重算（对标 oath.py）
          code = await this.calculate(credId, OtpType.TOTP, parts.period, timestampSec);
        }
      }
      entries.push(new CalculateAllEntry(credId, name, otpType, parts.period, touch, code));
      i += 2;
    }
    return entries;
  }

  /** PUT：添加凭据（M2-5，含触摸属性 0x78:0x02 与 HOTP 计数器） */
  async putCredential(cred: CredentialData): Promise<void> {
    const credIdStr = OathName.format(cred.issuer, cred.account, cred.otpType, cred.period);
    const credId = OathSession.utf8Encode(credIdStr);
    let secret = await OathSession.shortenKey(cred.secret, cred.algorithm);
    secret = OathSession.padTo(secret, OathConst.HMAC_MIN_KEY_SIZE);
    const head = new Uint8Array([cred.otpType | cred.algorithm, cred.digits & 0xFF]);
    const keyField = ApduUtils.concat(head, secret);
    let data = ApduUtils.concat(
      OathSession.wrap(OathConst.TAG_NAME, credId),
      OathSession.wrap(OathConst.TAG_KEY, keyField));
    if (cred.touch) {
      data = ApduUtils.concat(data, new Uint8Array([OathConst.TAG_PROPERTY, OathConst.PROP_REQUIRE_TOUCH]));
    }
    if (cred.counter > 0) {
      data = ApduUtils.concat(data, OathSession.wrap(OathConst.TAG_IMF, OathSession.int32Be(cred.counter)));
    }
    await this.protocol.sendApdu(0, OathConst.INS_PUT, 0, 0, data, 0);
  }

  /** DELETE：删除凭据（M2-6） */
  async deleteCredential(credId: Uint8Array): Promise<void> {
    await this.protocol.sendApdu(0, OathConst.INS_DELETE, 0, 0,
      OathSession.wrap(OathConst.TAG_NAME, credId), 0);
  }

  /** 内部传输（供上层直接发送） */
  getProtocol(): SmartCardProtocol {
    return this.protocol;
  }

  // ---------- 内部工具 ----------

  private static versionToText(data: Uint8Array | undefined): string {
    if (data === undefined || data.length < 3) {
      return 'unknown';
    }
    return data[0] + '.' + data[1] + '.' + data[2];
  }

  private static async deriveDeviceId(salt: Uint8Array): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    const blob: cryptoFramework.DataBlob = { data: salt };
    await md.update(blob);
    const digest = await md.digest();
    const short = digest.data.subarray(0, 16);
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(short).replace(new RegExp('=+$'), '');
  }

  /** TOTP challenge（8 字节大端时间槽） */
  private static challengeFor(period: number, timestampSec: number): Uint8Array {
    const step = Math.floor(timestampSec / period);
    const out = new Uint8Array(8);
    let v = step;
    for (let i = 7; i >= 0; i--) {
      out[i] = v & 0xFF;
      v = Math.floor(v / 256);
    }
    return out;
  }

  private static int32Be(value: number): Uint8Array {
    const out = new Uint8Array(4);
    out[0] = (value >> 24) & 0xFF;
    out[1] = (value >> 16) & 0xFF;
    out[2] = (value >> 8) & 0xFF;
    out[3] = value & 0xFF;
    return out;
  }

  /** 码值格式化（对标 oath.py _format_code）；truncated = [digits, 4 字节] */
  private static formatCode(truncated: Uint8Array, otpType: OtpType, period: number,
    timestampSec: number): CodeInfo {
    const digits = truncated.length > 0 ? truncated[0] : 6;
    let num = 0;
    for (let i = 1; i < truncated.length; i++) {
      num = num * 256 + truncated[i];
    }
    const code = String((num & 0x7FFFFFFF) % Math.pow(10, digits)).padStart(digits, '0');
    if (otpType === OtpType.TOTP) {
      const step = Math.floor(timestampSec / period);
      return new CodeInfo(code, step * period, (step + 1) * period);
    }
    return new CodeInfo(code, timestampSec, Number.MAX_SAFE_INTEGER);
  }

  /** 超长密钥先哈希（对标 oath.py _hmac_shorten_key） */
  private static async shortenKey(secret: Uint8Array, algo: HashAlgorithm): Promise<Uint8Array> {
    let blockSize = 64;
    let algoName = 'SHA1';
    if (algo === HashAlgorithm.SHA256) {
      blockSize = 64;
      algoName = 'SHA256';
    } else if (algo === HashAlgorithm.SHA512) {
      blockSize = 128;
      algoName = 'SHA512';
    }
    if (secret.length <= blockSize) {
      return secret;
    }
    const md = cryptoFramework.createMd(algoName);
    const blob: cryptoFramework.DataBlob = { data: secret };
    await md.update(blob);
    const digest = await md.digest();
    return digest.data;
  }

  private static padTo(data: Uint8Array, minLen: number): Uint8Array {
    if (data.length >= minLen) {
      return data;
    }
    const out = new Uint8Array(minLen);
    out.set(data, 0);
    return out;
  }

  /** 构造 [tag, len, value...]（短格式 tag 单字节、len < 128） */
  private static wrap(tag: number, value: Uint8Array): Uint8Array {
    const head = new Uint8Array(2);
    head[0] = tag;
    head[1] = value.length;
    return ApduUtils.concat(head, value);
  }

  private static utf8Encode(text: string): Uint8Array {
    const encoder = new util.TextEncoder('utf-8');
    return encoder.encodeInto(text);
  }

  private static async randomBytes(length: number): Promise<Uint8Array> {
    const rand = cryptoFramework.createRandom();
    const blob = await rand.generateRandom(length);
    return blob.data;
  }

  private static async hmacSha1(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
    const generator = cryptoFramework.createSymKeyGenerator('HMAC');
    const keyBlob: cryptoFramework.DataBlob = { data: key };
    const symKey = await generator.convertKey(keyBlob);
    // 官方示例：createMac 参数为摘要算法名（如 'SHA256'），HMAC 由 HMAC 类型 SymKey 决定
    const mac = cryptoFramework.createMac('SHA1');
    await mac.init(symKey);
    const dataBlob: cryptoFramework.DataBlob = { data: data };
    await mac.update(dataBlob);
    const out = await mac.doFinal();
    return out.data;
  }
}