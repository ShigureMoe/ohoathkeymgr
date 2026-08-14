/**
 * otpauth:// 与 otpauth-migration:// URI 解析（M3-2/M3-3）
 *  - otpauth://totp/{issuer:}account?secret=...&algorithm=...&digits=...&period=...&counter=...
 *  - otpauth-migration://offline?data=<base64 protobuf>（Google Authenticator 导出，一次多条）
 */
import { util } from '@kit.ArkTS';
import { Base32 } from './Base32';
import { CredentialData, HashAlgorithm, OtpType } from '../model/Credential';

/** 解析结果类别（供 UI 分流：单条 vs 多条迁移） */
export class ParseOutcome {
  credentials: CredentialData[] = [];
  /** 无法解析的 URI 数 */
  failures: number = 0;
}

export class OtpauthParser {
  /** 解析任意 URI（otpauth:// 或 otpauth-migration://）；不支持的 scheme 抛错 */
  static parseAny(raw: string): ParseOutcome {
    const text = raw.trim();
    const out = new ParseOutcome();
    if (OtpauthParser.hasPrefix(text, 'otpauth-migration://')) {
      const creds = OtpauthParser.parseMigration(text);
      for (const c of creds) {
        out.credentials.push(c);
      }
      return out;
    }
    if (OtpauthParser.hasPrefix(text, 'otpauth://')) {
      out.credentials.push(OtpauthParser.parseOtpauth(text));
      return out;
    }
    throw new Error('不支持的二维码内容');
  }

  /** 解析单条 otpauth:// */
  static parseOtpauth(uri: string): CredentialData {
    const rest = uri.substring('otpauth://'.length);
    const schemeEnd = rest.indexOf('://');
    if (schemeEnd === -1) {
      throw new Error('URI 格式不正确');
    }
    const afterScheme = rest.substring(schemeEnd + 3);
    const hostEnd = afterScheme.indexOf('/');
    const host = hostEnd === -1 ? afterScheme : afterScheme.substring(0, hostEnd);
    const pathAndQuery = hostEnd === -1 ? '' : afterScheme.substring(hostEnd + 1);
    const queryIdx = pathAndQuery.indexOf('?');
    let path = queryIdx === -1 ? pathAndQuery : pathAndQuery.substring(0, queryIdx);
    const query = queryIdx === -1 ? '' : pathAndQuery.substring(queryIdx + 1);

    const params = OtpauthParser.parseQuery(query);
    const typeText = host.toLowerCase();
    const otpType = typeText === 'hotp' ? OtpType.HOTP : OtpType.TOTP;

    // 路径 [issuer:]account（先 urldecode）
    path = decodeURIComponent(path);
    let issuerFromPath = '';
    let account = path;
    const colonIdx = path.indexOf(':');
    if (colonIdx > 0) {
      issuerFromPath = path.substring(0, colonIdx);
      account = path.substring(colonIdx + 1);
    }
    if (account.length === 0) {
      throw new Error('凭据名称缺失');
    }

    const secretStr = params.get('secret');
    if (secretStr === undefined || secretStr.length === 0) {
      throw new Error('缺少 secret 参数');
    }
    const secret = Base32.decode(secretStr);

    const cred = new CredentialData();
    cred.otpType = otpType;
    cred.secret = secret;
    cred.account = account;
    const issuerParam = params.get('issuer');
    cred.issuer = issuerParam !== undefined && issuerParam.length > 0 ? decodeURIComponent(issuerParam) : issuerFromPath;
    const algo = params.get('algorithm');
    if (algo !== undefined && algo.toUpperCase() === 'SHA256') {
      cred.algorithm = HashAlgorithm.SHA256;
    } else if (algo !== undefined && algo.toUpperCase() === 'SHA512') {
      cred.algorithm = HashAlgorithm.SHA512;
    } else {
      cred.algorithm = HashAlgorithm.SHA1;
    }
    const digitsStr = params.get('digits');
    if (digitsStr !== undefined && digitsStr.length > 0) {
      const digits = parseInt(digitsStr);
      cred.digits = digits >= 6 && digits <= 8 ? digits : 6;
    }
    const periodStr = params.get('period');
    if (periodStr !== undefined && periodStr.length > 0) {
      const period = parseInt(periodStr);
      cred.period = period > 0 ? period : 30;
    }
    const counterStr = params.get('counter');
    if (counterStr !== undefined && counterStr.length > 0) {
      const counter = parseInt(counterStr);
      cred.counter = counter > 0 ? counter : 0;
    }
    return cred;
  }

  /** 解析 otpauth-migration URI（Google Authenticator 导出格式） */
  static parseMigration(uri: string): CredentialData[] {
    // 格式：otpauth-migration://offline?data=<base64>
    const rest = uri.substring('otpauth-migration://'.length);
    const qIdx = rest.indexOf('?');
    const query = qIdx === -1 ? '' : rest.substring(qIdx + 1);
    const params = OtpauthParser.parseQuery(query);
    const data = params.get('data');
    if (data === undefined || data.length === 0) {
      throw new Error('迁移数据缺失');
    }
    if (data.indexOf('%') >= 0) {
      throw new Error('迁移数据需先 URL 解码');
    }
    const bytes = OtpauthParser.base64Decode(data);
    return OtpauthParser.parseMigrationPayload(bytes);
  }

  // ---------- protobuf（otpauth-migration schema） ----------

  private static parseMigrationPayload(payload: Uint8Array): CredentialData[] {
    const reader = new ProtoReader(payload);
    const creds: CredentialData[] = [];
    while (true) {
      const field = reader.nextField();
      if (field === null) {
        break;
      }
      if (field.field === 1 && field.wire === 2) {
        const data = reader.readBytes();
        const cred = OtpauthParser.parseOtpParams(data);
        if (cred !== undefined) {
          creds.push(cred);
        }
      } else {
        reader.skipField(field.wire);
      }
    }
    if (creds.length === 0) {
      throw new Error('迁移数据中无有效凭据');
    }
    return creds;
  }

  /** 解析 OtpParameters 子消息 */
  private static parseOtpParams(data: Uint8Array): CredentialData | undefined {
    const reader = new ProtoReader(data);
    const cred = new CredentialData();
    let hasSecret = false;
    let name = '';
    let type = 0;
    let algorithm = 0;
    let digits = 0;
    let counter = 0;
    while (true) {
      const field = reader.nextField();
      if (field === null) {
        break;
      }
      if (field.field === 1 && field.wire === 2) {
        cred.secret = reader.readBytes();
        hasSecret = cred.secret.length > 0;
      } else if (field.field === 2 && field.wire === 2) {
        name = reader.readString();
      } else if (field.field === 3 && field.wire === 2) {
        cred.issuer = reader.readString();
      } else if (field.field === 4 && field.wire === 0) {
        algorithm = reader.readVarint();
      } else if (field.field === 5 && field.wire === 0) {
        digits = reader.readVarint();
      } else if (field.field === 6 && field.wire === 0) {
        type = reader.readVarint();
      } else if (field.field === 7 && field.wire === 0) {
        counter = reader.readVarint();
      } else {
        reader.skipField(field.wire);
      }
    }
    if (!hasSecret) {
      return undefined;
    }
    // name 通常为 "issuer:account" 或 "issuer/account"
    if (name.length > 0) {
      if (name.indexOf(':') > 0) {
        cred.issuer = name.substring(0, name.indexOf(':'));
        cred.account = name.substring(name.indexOf(':') + 1);
      } else if (name.indexOf('/') > 0) {
        const slash = name.indexOf('/');
        cred.issuer = name.substring(0, slash);
        cred.account = name.substring(slash + 1);
      } else {
        if (cred.issuer.length === 0) {
          cred.issuer = name;
        }
        cred.account = name;
      }
    }
    if (type === 1) {
      cred.otpType = OtpType.HOTP;
    } else {
      cred.otpType = OtpType.TOTP;
    }
    if (algorithm === 2) {
      cred.algorithm = HashAlgorithm.SHA256;
    } else if (algorithm === 3) {
      cred.algorithm = HashAlgorithm.SHA512;
    } else {
      cred.algorithm = HashAlgorithm.SHA1;
    }
    if (digits === 2) {
      cred.digits = 8;
    } else {
      cred.digits = 6;
    }
    cred.counter = counter;
    return cred;
  }

  // ---------- 工具 ----------

  private static hasPrefix(text: string, prefix: string): boolean {
    return text.length >= prefix.length && text.substring(0, prefix.length) === prefix;
  }

  /** 解析 query 参数（+ 与 %XX 解码） */
  private static parseQuery(query: string): Map<string, string> {
    const out = new Map<string, string>();
    if (query.length === 0) {
      return out;
    }
    const parts = query.split('&');
    for (const part of parts) {
      const eq = part.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key = decodeURIComponent(part.substring(0, eq).replace(new RegExp('\\+', 'g'), ' '));
      const value = decodeURIComponent(part.substring(eq + 1).replace(new RegExp('\\+', 'g'), ' '));
      out.set(key, value);
    }
    return out;
  }

  /** Base64 解码（migration data 为标准 base64 或 URL-safe） */
  private static base64Decode(text: string): Uint8Array {
    const urlSafe = text.replace(new RegExp('-', 'g'), '+').replace(new RegExp('_', 'g'), '/');
    const padded = urlSafe.padEnd(urlSafe.length + ((4 - urlSafe.length % 4) % 4), '=');
    const helper = new util.Base64Helper();
    return helper.decodeSync(padded);
  }
}

/** 极简 protobuf 读取器（仅 varint/len-delimited/skip；无效数据抛错） */
export class ProtoReader {
  private data: Uint8Array;
  private offset: number = 0;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  /** 读取下一个字段头；返回 null 表示结束 */
  nextField(): ProtoField | null {
    if (this.offset >= this.data.length) {
      return null;
    }
    const key = this.readVarint();
    const field = key >>> 3;
    const wire = key & 0x07;
    return new ProtoField(field, wire);
  }

  readVarint(): number {
    let result = 0;
    let shift = 0;
    while (this.offset < this.data.length && shift < 53) {
      const b = this.data[this.offset];
      this.offset += 1;
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) === 0) {
        return result;
      }
      shift += 7;
    }
    if (shift >= 53) {
      // 超出 number 安全范围，取低 32 位回退
      return result >>> 0;
    }
    throw new Error('protobuf 读取越界');
  }

  readBytes(): Uint8Array {
    const len = this.readVarint();
    if (this.offset + len > this.data.length) {
      throw new Error('protobuf 长度越界');
    }
    const out = this.data.subarray(this.offset, this.offset + len);
    this.offset += len;
    return out;
  }

  readString(): string {
    const bytes = this.readBytes();
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(bytes);
  }

  skipField(wire: number): void {
    if (wire === 0) {
      this.readVarint();
    } else if (wire === 1) {
      this.offset += 8;
    } else if (wire === 2) {
      const len = this.readVarint();
      this.offset += len;
    } else if (wire === 5) {
      this.offset += 4;
    }
    // wire 3/4（group）不出现于该 schema，忽略
  }
}

/** protobuf 字段头 */
export class ProtoField {
  field: number;
  wire: number;

  constructor(field: number, wire: number) {
    this.field = field;
    this.wire = wire;
  }
}