/**
 * CCID 消息层（纯逻辑，不依赖系统 API，可本地单测）
 * 依据 USB CCID Class Spec 1.1 的公共消息格式：
 *  - 消息头 10 字节：bMessageType(0) dwLength(1-4, 小端) bSlot(5) bSeq(6)
 *    bStatus(7, 仅 RDR_to_PC) bError(8, 仅 RDR_to_PC) bSpecific(8, 仅 PC_to_RDR) rfu(9)
 *  - PC_to_RDR_IccPowerOn(0x62)：offset 9 为 powerSelect（0=Auto 1=5V 2=3V 3=1.8V）
 *  - PC_to_RDR_XfrBlock(0x6F)：offset 7=bBWI offset 8=bLevelParameter，abData 自 offset 10 起
 *  - RDR_to_PC_DataBlock(0x80)：offset 7=bStatus 8=bError 9=bChainParameter
 *  - RDR_to_PC_SlotStatus(0x81)：IccPowerOff / GetSlotStatus / Abort 的响应类型
 *  - PC_to_RDR_Abort(0x6A)：终止进行中的传输（超时恢复）
 */

/** CCID 消息类型 */
export class CcidMsgType {
  static readonly ICC_POWER_ON = 0x62;
  static readonly ICC_POWER_OFF = 0x63;
  static readonly GET_SLOT_STATUS = 0x65;
  static readonly ABORT = 0x6A;
  static readonly XFR_BLOCK = 0x6F;
  static readonly DATA_BLOCK = 0x80;
  static readonly SLOT_STATUS = 0x81;
}

/** IccPowerOn 电压选择（bSpecific, offset 9） */
export class CcidPowerSelect {
  static readonly AUTO = 0;
  static readonly VOLTAGE_5V = 1;
  static readonly VOLTAGE_3V = 2;
  static readonly VOLTAGE_1P8V = 3;
}

/** bStatus 编码（RDR_to_PC 消息 offset 7，0=成功） */
export class CcidStatus {
  static readonly SUCCESS = 0x00;
  static readonly CMD_NOT_SUPPORTED = 0x01;
  static readonly CMD_ABORTED = 0x02;
  static readonly ICC_MUTE = 0x03;
  static readonly XFR_PARITY_ERROR = 0x80;
  static readonly XFR_OVERRUN = 0x81;
  static readonly HW_ERROR = 0x82;
  static readonly SW_ERROR = 0x83;
  static readonly OVERFLOW = 0x84;
  static readonly INSUFFICIENT_BUFFER = 0x85;
  static readonly APP_ERROR = 0x86;
  static readonly POWERED_OFF = 0x87;
  static readonly ICC_PRESENT = 0x88;
  static readonly ICC_ABSENT = 0x89;
  static readonly SLOT_NOT_CONNECTED = 0x8A;
  static readonly SLOT_NOT_CONFIGURED = 0x8B;
  static readonly WRONG_LENGTH = 0x8C;
  /** 时间扩展请求（CanoKey 等设备处理较慢时发送，等待额外 BTW，非错误） */
  static readonly TIME_EXTN = 0x11;
}

/** 解析后的 RDR_to_PC 消息 */
export interface CcidResponse {
  messageType: number;
  slot: number;
  seq: number;
  status: number;
  error: number;
  chain: number;
  data: Uint8Array;
}

/** 字节流抽象：USB bulk 端点或测试 mock */
export interface ByteStream {
  write(data: Uint8Array): Promise<number>;
  read(buf: Uint8Array): Promise<number>;
}

/** CCID 协议实现：请求构造、响应解析、seq 校验、链式拼接、背靠背缓冲 */
export class CcidProtocol {
  static readonly HEADER_LEN = 10;
  /** 短格式 APDU 上限：4 头 + Lc + 255 数据 + Le */
  static readonly MAX_SHORT_APDU = 261;
  /** 链式响应块数上限（防御死循环） */
  private static readonly MAX_CHAIN_BLOCKS = 8;
  /**
   * 容忍的乱序响应条数：部分设备（如 CanoKey）会重复发送上一条响应或滞留
   * 上一条命令的响应（seq 与期望不符），正确响应在其后。丢弃并继续读，
   * 连续超出上限才判定协议错误。
   */
  private static readonly MAX_SEQ_MISMATCH_TOLERANCE = 3;

  private stream: ByteStream;
  private seq: number = 0;
  private pending: Uint8Array = new Uint8Array(0);

  constructor(stream: ByteStream) {
    this.stream = stream;
  }

  /** 上电（电压 Auto），返回 ATR */
  async powerOn(): Promise<Uint8Array> {
    const msg = CcidProtocol.buildPowerOn(this.nextSeq(), CcidPowerSelect.AUTO);
    const resp = await this.request(msg);
    if (resp.messageType !== CcidMsgType.DATA_BLOCK) {
      throw new Error('CCID power on failed: unexpected response type 0x' + resp.messageType.toString(16));
    }
    return resp.data;
  }

  /** 下电；规范响应为 RDR_to_PC_SlotStatus */
  async powerOff(): Promise<void> {
    const msg = CcidProtocol.buildHeader(CcidMsgType.ICC_POWER_OFF, this.nextSeq(), 0);
    const resp = await this.request(msg);
    if (resp.messageType !== CcidMsgType.SLOT_STATUS) {
      throw new Error('CCID power off failed: unexpected response type 0x' + resp.messageType.toString(16));
    }
  }

  /** 传输短格式 APDU，返回响应数据（不含 SW） */
  async transmit(apdu: Uint8Array): Promise<Uint8Array> {
    if (apdu.length > CcidProtocol.MAX_SHORT_APDU) {
      throw new Error('CCID short-form APDU too long: ' + apdu.length);
    }
    const msg = CcidProtocol.buildHeader(CcidMsgType.XFR_BLOCK, this.nextSeq(), apdu.length);
    msg.set(apdu, CcidProtocol.HEADER_LEN);
    const resp = await this.request(msg);
    if (resp.messageType !== CcidMsgType.DATA_BLOCK) {
      throw new Error('CCID transmit failed: unexpected response type 0x' + resp.messageType.toString(16));
    }
    return resp.data;
  }

  /** 终止进行中的传输（超时恢复），响应为 SlotStatus */
  async abort(): Promise<void> {
    const msg = CcidProtocol.buildHeader(CcidMsgType.ABORT, this.nextSeq(), 0);
    const resp = await this.request(msg);
    if (resp.messageType !== CcidMsgType.SLOT_STATUS) {
      throw new Error('CCID abort failed: unexpected response type 0x' + resp.messageType.toString(16));
    }
  }

  /** 构造 PC_to_RDR_IccPowerOn 消息；offset 9 = powerSelect（bSpecific） */
  static buildPowerOn(seq: number, powerSelect: number): Uint8Array {
    const msg = CcidProtocol.buildHeader(CcidMsgType.ICC_POWER_ON, seq, 0);
    msg[9] = powerSelect;
    return msg;
  }

  /** 构造通用 PC_to_RDR 消息头（10 字节 + payload）；XfrBlock 的 bBWI/bLevelParameter 默认 0 */
  static buildHeader(type: number, seq: number, payloadLen: number): Uint8Array {
    const msg = new Uint8Array(CcidProtocol.HEADER_LEN + payloadLen);
    msg[0] = type;
    msg[1] = payloadLen & 0xFF;
    msg[2] = (payloadLen >> 8) & 0xFF;
    msg[3] = (payloadLen >> 16) & 0xFF;
    msg[4] = (payloadLen >> 24) & 0xFF;
    msg[5] = 0; // slot 0
    msg[6] = seq;
    return msg;
  }

  /** 解析一条完整 CCID 消息（长度不足抛错） */
  static parseMessage(msg: Uint8Array): CcidResponse {
    if (msg.length < CcidProtocol.HEADER_LEN) {
      throw new Error('CCID message too short: ' + msg.length);
    }
    const dwLength = CcidProtocol.readDwLength(msg);
    if (CcidProtocol.HEADER_LEN + dwLength > msg.length) {
      throw new Error('CCID message truncated: header=' + CcidProtocol.HEADER_LEN + ' body=' + dwLength);
    }
    return {
      messageType: msg[0],
      slot: msg[5],
      seq: msg[6],
      status: msg[7],
      error: msg[8],
      chain: msg[9],
      data: msg.subarray(CcidProtocol.HEADER_LEN, CcidProtocol.HEADER_LEN + dwLength)
    };
  }

  /** dwLength（offset 1-4，小端） */
  static readDwLength(msg: Uint8Array): number {
    return msg[1] + (msg[2] << 8) + (msg[3] << 16) + (msg[4] * 0x1000000);
  }

  /**
   * 发送请求并读取响应：
   *  - 校验每条响应 bSeq 与请求序号严格递增对应；乱序响应（滞留/重复）丢弃并继续读
   *  - bStatus = TIME_EXTN(0x11) 为时间扩展请求，跳过等待真正响应；其他非 0 抛错
   *  - DataBlock 的 bChainParameter > 0 时继续读取后续数据块并拼接
   */
  private async request(msg: Uint8Array): Promise<CcidResponse> {
    const reqSeq = msg[6];
    const sent = await this.stream.write(msg);
    if (sent !== msg.length) {
      throw new Error('CCID write incomplete: ' + sent + '/' + msg.length);
    }
    let expectSeq = reqSeq;
    let data = new Uint8Array(0);
    let firstType = 0;
    let firstSlot = 0;
    let blocks = 0;
    let mismatches = 0;
    while (true) {
      const resp = await this.readMessage();
      if (resp.status === CcidStatus.TIME_EXTN) {
        // 设备请求时间扩展：跳过，继续等待真正响应
        continue;
      }
      if (resp.seq !== expectSeq) {
        mismatches += 1;
        if (mismatches > CcidProtocol.MAX_SEQ_MISMATCH_TOLERANCE) {
          throw new Error('CCID seq mismatch: expect=' + expectSeq + ', got=' + resp.seq +
            ', type=0x' + resp.messageType.toString(16) + ', status=' + resp.status +
            ', error=' + resp.error + ', data=' + CcidProtocol.hex(resp.data));
        }
        // 滞留/重复响应：丢弃并继续读下一条
        continue;
      }
      if (resp.status !== 0) {
        throw new Error('CCID error status=' + resp.status + ', error=' + resp.error);
      }
      expectSeq = (expectSeq + 1) & 0xFF;
      blocks += 1;
      if (blocks > CcidProtocol.MAX_CHAIN_BLOCKS) {
        throw new Error('CCID chain too long');
      }
      if (firstType === 0) {
        firstType = resp.messageType;
        firstSlot = resp.slot;
      }
      data = CcidProtocol.concat(data, resp.data);
      if (resp.messageType !== CcidMsgType.DATA_BLOCK || resp.chain === 0) {
        return {
          messageType: firstType,
          slot: firstSlot,
          seq: expectSeq,
          status: 0,
          error: 0,
          chain: 0,
          data: data
        };
      }
    }
  }

  /**
   * 读取一条完整 CCID 消息：
   *  - 一次 read 可能返回多条消息（设备背靠背发送），多余部分入 pending 缓冲
   *  - 一条消息可能被拆成多次 read（分片），循环补读拼接
   */
  private async readMessage(): Promise<CcidResponse> {
    if (this.pending.length >= CcidProtocol.HEADER_LEN) {
      const parsed = CcidProtocol.parseMessage(this.pending);
      this.pending = this.pending.subarray(CcidProtocol.HEADER_LEN + parsed.data.length);
      return parsed;
    }
    let buf = this.pending;
    this.pending = new Uint8Array(0);
    while (buf.length < CcidProtocol.HEADER_LEN) {
      buf = CcidProtocol.concat(buf, await this.readChunk());
    }
    const total = CcidProtocol.HEADER_LEN + CcidProtocol.readDwLength(buf);
    while (buf.length < total) {
      buf = CcidProtocol.concat(buf, await this.readChunk());
    }
    const msg = buf.subarray(0, total);
    this.pending = buf.subarray(total);
    return CcidProtocol.parseMessage(msg);
  }

  private async readChunk(): Promise<Uint8Array> {
    const chunk = new Uint8Array(4096);
    const n = await this.stream.read(chunk);
    if (n <= 0) {
      throw new Error('CCID read failed, ret=' + n);
    }
    return chunk.subarray(0, n);
  }

  private nextSeq(): number {
    const s = this.seq;
    this.seq = (this.seq + 1) & 0xFF;
    return s;
  }

  private static concat(...arrays: Uint8Array[]): Uint8Array {
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

  static hex(data: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < data.length; i++) {
      hex += data[i].toString(16).padStart(2, '0');
    }
    return hex;
  }
}
