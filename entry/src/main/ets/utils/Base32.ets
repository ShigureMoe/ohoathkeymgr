/** Base32 解码（RFC 4648）：忽略大小写、空格与连字符，支持省略 padding，无效字符抛错 */
export class Base32 {
  private static readonly ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /** 解码 Base32 字符串为字节数组 */
  static decode(input: string): Uint8Array {
    let cleaned = '';
    for (let i = 0; i < input.length; i++) {
      const ch = input.charAt(i);
      if (ch === ' ' || ch === '-' || ch === '\t' || ch === '\n' || ch === '\r') {
        continue;
      }
      cleaned += ch;
    }
    // 去掉尾部 padding
    let end = cleaned.length;
    while (end > 0 && cleaned.charAt(end - 1) === '=') {
      end -= 1;
    }
    cleaned = cleaned.substring(0, end).toUpperCase();

    let bits = 0;
    let value = 0;
    const out: number[] = [];
    for (let i = 0; i < cleaned.length; i++) {
      const idx = Base32.ALPHABET.indexOf(cleaned.charAt(i));
      if (idx < 0) {
        throw new Error('Invalid Base32 character: ' + cleaned.charAt(i));
      }
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        out.push((value >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return new Uint8Array(out);
  }

  /** 解码并校验长度合法性（otpauth secret 8~128 字节）；返回 null 表示解码失败 */
  static tryDecode(input: string): Uint8Array | null {
    try {
      return Base32.decode(input);
    } catch (e) {
      return null;
    }
  }
}