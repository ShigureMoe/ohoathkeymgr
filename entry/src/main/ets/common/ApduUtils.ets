/**
 * APDU / TLV 协议工具层
 * 全部依据对 example/yubikey-manager 的逆向：
 *  - yubikit/core/smartcard/__init__.py：AID、ShortApduFormatter、ResponseChainingProcessor(0x61→0xC0)
 *  - yubikit/core/__init__.py：Tlv、Version
 *  - yubikit/oath.py：OATH SELECT 响应解析（TAG_VERSION=0x79 / TAG_CHALLENGE=0x74）
 *  - yubikit/management.py：INS_READ_CONFIG=0x1D 分页读 DeviceInfo TLV
 */
import { util } from '@kit.ArkTS';

/** YubiKey 智能卡应用 AID（逆向自 core/smartcard AID 枚举） */
export class Aids {
  static readonly OTP: Uint8Array = Aids.fromHex('a0000005272001');
  static readonly MANAGEMENT: Uint8Array = Aids.fromHex('a000000527471117');
  static readonly OATH: Uint8Array = Aids.fromHex('a0000005272101');
  static readonly PIV: Uint8Array = Aids.fromHex('a000000308');
  static readonly OPENPGP: Uint8Array = Aids.fromHex('d27600012401');

  private static fromHex(hex: string): Uint8Array {
    const out = new Uint8Array(hex.length / 2);
    for (let i = 0; i < out.length; i++) {
      out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    }
    return out;
  }
}

/** ISO 7816 TLV 解码（逆向自 core/__init__.py Tlv 类） */
export class Tlv {
  tag: number;
  value: Uint8Array;

  constructor(tag: number, value: Uint8Array) {
    this.tag = tag;
    this.value = value;
  }

  /** 解析连续 TLV 列表；长度字段支持单字节（<0x80）与多字节长格式 */
  static parseList(data: Uint8Array): Tlv[] {
    const result: Tlv[] = [];
    let offset = 0;
    while (offset < data.length) {
      let tag = data[offset];
      offset += 1;
      if ((tag & 0x1F) === 0x1F) { // long form tag
        tag = (tag << 8) | data[offset];
        offset += 1;
      }
      let len = data[offset];
      offset += 1;
      if (len > 0x80) {
        const nBytes = len - 0x80;
        len = ApduUtils.bytesToInt(data.subarray(offset, offset + nBytes));
        offset += nBytes;
      }
      result.push(new Tlv(tag, data.subarray(offset, offset + len)));
      offset += len;
    }
    return result;
  }

  /** 解析为 tag → value 字典 */
  static parseDict(data: Uint8Array): Map<number, Uint8Array> {
    const map = new Map<number, Uint8Array>();
    for (const tlv of Tlv.parseList(data)) {
      map.set(tlv.tag, tlv.value);
    }
    return map;
  }
}

/** 通用字节工具 */
export class ApduUtils {
  static bytesToInt(data: Uint8Array): number {
    let value = 0;
    for (let i = 0; i < data.length; i++) {
      value = (value * 256) + data[i];
    }
    return value;
  }

  static intToBytes(value: number, minLen: number): Uint8Array {
    const bitLen = value === 0 ? 1 : Math.ceil(Math.log2(value + 1));
    const len = Math.max(minLen, Math.ceil(bitLen / 8));
    const out = new Uint8Array(len);
    let v = value;
    for (let i = len - 1; i >= 0; i--) {
      out[i] = v & 0xFF;
      v = Math.floor(v / 256);
    }
    return out;
  }

  static toHex(data: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < data.length; i++) {
      hex += data[i].toString(16).padStart(2, '0');
    }
    return hex;
  }

  static concat(...arrays: Uint8Array[]): Uint8Array {
    let total = 0;
    for (const arr of arrays) {
      total += arr.length;
    }
    const out = new Uint8Array(total);
    let offset = 0;
    for (const arr of arrays) {
      out.set(arr, offset);
      offset += arr.length;
    }
    return out;
  }

  static utf8Decode(data: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(data);
  }

  /** 常量时间字节比较（用于验证响应比对，避免时序侧信道） */
  static constantEquals(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) {
      return false;
    }
    let diff = 0;
    for (let i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff === 0;
  }
}

/** APDU 构造与响应处理（逆向自 core/smartcard：ShortApduFormatter + ResponseChainingProcessor） */
export class Apdu {
  /** 短格式 APDU：CLA INS P1 P2 [Lc data] [Le]；无 data 无 le 时补 Lc=0 */
  static format(cla: number, ins: number, p1: number, p2: number, data: Uint8Array, le: number): Uint8Array {
    const head = new Uint8Array([cla, ins, p1, p2]);
    if (data.length > 0) {
      const lc = new Uint8Array([data.length]);
      if (le > 0) {
        return ApduUtils.concat(head, lc, data, new Uint8Array([le]));
      }
      return ApduUtils.concat(head, lc, data);
    }
    if (le > 0) {
      return ApduUtils.concat(head, new Uint8Array([le]));
    }
    return ApduUtils.concat(head, new Uint8Array([0]));
  }

  /** SELECT 指令：00 A4 04 00 Lc AID */
  static select(aid: Uint8Array): Uint8Array {
    return Apdu.format(0x00, 0xA4, 0x04, 0x00, aid, 0);
  }

  /**
   * SEND_REMAINING：00 A5 00 00 [Le]（OATH 响应链续传，逆向自 yubikit ResponseChainingProcessor，
   * INS.SEND_REMAINING=0xA5）。YubiKey 与 CanoKey 的 OATH 应用均不支持标准 GET RESPONSE(0xC0)。
   * Le 取上次 SW2（剩余字节数）；SW2=0 时发 case-1 四字节形式。
   */
  static sendRemaining(le: number): Uint8Array {
    if (le <= 0) {
      return new Uint8Array([0x00, 0xA5, 0x00, 0x00]);
    }
    return new Uint8Array([0x00, 0xA5, 0x00, 0x00, le & 0xFF]);
  }

  static readonly SW_OK = 0x9000;
  /** SELECT 失败的应用不可用 SW 集合（逆向自 SmartCardProtocol.select） */
  static readonly SW_APP_NOT_AVAILABLE: number[] = [0x6A82, 0x6999, 0x6D00, 0x6B00];
}

/** 传输适配器：NFC 与 USB 共享的收发接口 */
export interface CardTransport {
  /** 发送 APDU 原始字节（短格式），返回完整响应体（含 SW 的链式合并结果） */
  transmit(apdu: Uint8Array): Promise<Uint8Array>;
  /** 关闭连接（USB 下电后释放管道；NFC 重置连接） */
  close(): Promise<void>;
}

/** 智能卡协议层：SELECT + 响应链 + SW 校验（对标 SmartCardProtocol） */
export class SmartCardProtocol {
  private conn: CardTransport;

  constructor(conn: CardTransport) {
    this.conn = conn;
  }

  async sendApdu(cla: number, ins: number, p1: number, p2: number, data: Uint8Array, le: number): Promise<Uint8Array> {
    const apdu = Apdu.format(cla, ins, p1, p2, data, le);
    let response = await this.conn.transmit(apdu);
    // 响应链：SW1=0x61 表示还有更多数据，以 SW2 为 Le 循环 SEND_REMAINING
    // （逆向自 yubikit ResponseChainingProcessor；OATH 应用不支持标准 GET RESPONSE）
    let buf = new Uint8Array(0);
    let sw1 = response.length >= 2 ? response[response.length - 2] : 0;
    let chainGuard = 0;
    while (sw1 === 0x61) {
      buf = ApduUtils.concat(buf, response.subarray(0, response.length - 2));
      chainGuard += 1;
      if (chainGuard > 32) {
        throw new Error('APDU response chain too long');
      }
      response = await this.conn.transmit(Apdu.sendRemaining(response[response.length - 1]));
      sw1 = response.length >= 2 ? response[response.length - 2] : 0;
    }
    buf = ApduUtils.concat(buf, response);
    if (buf.length < 2) {
      throw new Error('APDU response too short');
    }
    const sw = (buf[buf.length - 2] << 8) | buf[buf.length - 1];
    if (sw !== Apdu.SW_OK) {
      throw new Error('APDU error: SW=0x' + sw.toString(16));
    }
    return buf.subarray(0, buf.length - 2);
  }

  /** SELECT 应用；应用不可用时抛 Error（消息含 'not available'） */
  async select(aid: Uint8Array): Promise<Uint8Array> {
    let response: Uint8Array = new Uint8Array(0);
    try {
      response = await this.sendApdu(0x00, 0xA4, 0x04, 0x00, aid, 0);
      return response;
    } catch (e) {
      const msg = (e as Error).message;
      const isNotAvailable = Apdu.SW_APP_NOT_AVAILABLE.some((sw) => msg.includes('0x' + sw.toString(16)));
      if (isNotAvailable) {
        throw new Error('Application not available');
      }
      throw (e as Error);
    }
  }
}