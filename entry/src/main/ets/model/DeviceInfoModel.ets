/**
 * 卡片信息数据模型，对应 ykman info 与 ykman oath info 的输出字段
 */

/** OATH 应用信息（对应 ykman oath info） */
export interface OathInfoJson {
  /** OATH 应用版本，来自 OATH SELECT 响应 TLV(0x79) */
  oathVersion: string;
  /** 密码保护状态：enabled / disabled（SELECT 响应含 challenge 即已设置密码） */
  passwordProtection: string;
  /** 是否已设置安全密码（session.locked） */
  locked: boolean;
}

/** 设备信息（对应 ykman info 中除应用状态表外的字段） */
export interface YkmanInfoJson {
  /** 设备类型名（对标 ykman 的 Device type，由版本/形态推导） */
  deviceType: string;
  /** 序列号（管理应用 DeviceInfo TLV 0x02），不可读时为 null */
  serialNumber: number | null;
  /** 固件版本（管理应用 DeviceInfo TLV 0x05 或管理应用 SELECT 响应） */
  firmwareVersion: string;
  /** 形态因子（TLV 0x04 低 4 位映射） */
  formFactor: string;
  /** USB 使能的应用（TLV 0x03 capability 位掩码展开） */
  usbInterfaces: string[];
  /** NFC 传输状态：enabled / disabled / unsupported */
  nfcTransport: string;
  /** 应用能力（capability 位掩码展开），对应 ykman info 的应用状态表 */
  applications: string[];
}

/** 一次测试会话的完整结果（打印为 JSON 日志） */
export interface CardInfoResult {
  /** 传输方式：NFC / USB */
  transport: string;
  /** ykman info 部分 */
  ykmanInfo: YkmanInfoJson;
  /** ykman oath info 部分 */
  oathInfo: OathInfoJson;
}

/** 测试页回调，NFC/USB 测试完成后统一走此接口 */
export interface TestCallback {
  onResult(result: CardInfoResult): void;
  onError(message: string): void;
}