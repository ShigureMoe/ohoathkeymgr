/**
 * 统一卡片通道（CardChannel）：USB 长连接与 NFC 碰卡会话的同一抽象。
 * 业务层（OathSessionManager）只面向该接口，不区分 NFC/USB：
 *  - withSession：执行一个需要已建立会话的操作（USB 复用长连接；NFC 触发碰卡会话）
 *  - getSerial：当前连接绑定的卡片序列号
 *  - autoCalculateTouch：是否自动计算触摸凭据（NFC 碰卡直接算 → true；USB 需用户触摸 → false）
 *  - autoRefreshSupported：是否支持后台自动刷新（USB 长连接 → true）
 */
import { tag } from '@kit.ConnectivityKit';
import { CardTransport } from '../common/ApduUtils';
import { NfcCardTransport } from '../common/NfcCardTransport';
import { CardInfoCollector } from '../common/CardInfoCollector';
import { OathSession } from '../protocol/OathProtocol';
import { AppState } from '../viewmodel/AppState';
import { DeviceInfoStore } from '../viewmodel/DeviceInfoStore';
import { NfcSessionRunner } from './NfcSessionRunner';

export interface CardChannel {
  /** 当前连接绑定的序列号；-1 表示未绑定 */
  getSerial(): number;
  /** 是否自动计算触摸凭据（NFC 实测直接可算 → true） */
  autoCalculateTouch(): boolean;
  /** 是否支持后台自动刷新（USB 长连接 → true） */
  autoRefreshSupported(): boolean;
  /** 执行需要已建立会话的操作；业务层对 NFC/USB 无感 */
  withSession<T>(work: (session: OathSession) => Promise<T>, toast: (msg: string) => void): Promise<T>;
  /** 断开通道 */
  disconnect(): Promise<void>;
}

/** USB 长连接通道：复用已验证的会话 */
export class UsbCardChannel implements CardChannel {
  private transport: CardTransport;
  private session: OathSession;
  private serial: number;

  constructor(transport: CardTransport, session: OathSession, serial: number) {
    this.transport = transport;
    this.session = session;
    this.serial = serial;
  }

  getSerial(): number {
    return this.serial;
  }

  autoCalculateTouch(): boolean {
    return false;
  }

  autoRefreshSupported(): boolean {
    return true;
  }

  withSession<T>(work: (session: OathSession) => Promise<T>, toast: (msg: string) => void): Promise<T> {
    return work(this.session);
  }

  getSession(): OathSession {
    return this.session;
  }

  async disconnect(): Promise<void> {
    try {
      await this.transport.close();
    } catch (e) {
      // 忽略关闭异常
    }
  }
}

/** NFC 碰卡通道：idle 监听 + 操作式会话 + 序列号绑定 */
export class NfcCardChannel implements CardChannel {
  private serial: number = -1;

  getSerial(): number {
    return this.serial;
  }

  autoCalculateTouch(): boolean {
    return true;
  }

  autoRefreshSupported(): boolean {
    return false;
  }

  /** 操作式会话：监听等卡 → 连接 → 序列号校验 → 提供会话 */
  withSession<T>(work: (session: OathSession) => Promise<T>, toast: (msg: string) => void): Promise<T> {
    return NfcSessionRunner.run(work, toast, async (transport: NfcCardTransport) => {
      await this.verifySerial(transport, toast);
    });
  }

  /** 已碰到的卡（idle 回调中）：直接建立会话并校验序列号 */
  async withTagSession<T>(tagInfo: tag.TagInfo, work: (session: OathSession) => Promise<T>,
    toast: (msg: string) => void): Promise<T> {
    const transport: NfcCardTransport = new NfcCardTransport(tagInfo);
    try {
      await transport.connect();
      await this.verifySerial(transport, toast);
      const session = await OathSession.open(transport);
      return await work(session);
    } finally {
      try {
        await transport.close();
      } catch (e) {
        // 忽略关闭异常
      }
    }
  }

  /** idle 待卡监听：碰卡回调由调用方（OM）处理 */
  startIdle(onTap: (tagInfo: tag.TagInfo) => void): void {
    NfcSessionRunner.startIdle(onTap);
  }

  stopIdle(): void {
    NfcSessionRunner.stopIdle();
  }

  resumeIdle(onTap: (tagInfo: tag.TagInfo) => void): void {
    if (!NfcSessionRunner.isBusy()) {
      NfcSessionRunner.startIdle(onTap);
    }
  }

  async disconnect(): Promise<void> {
    NfcSessionRunner.stopIdle();
    this.serial = -1;
  }

  /** 序列号绑定校验：未绑定则绑定；已绑定则必须匹配，否则拒绝 */
  private async verifySerial(transport: NfcCardTransport, toast: (msg: string) => void): Promise<void> {
    const serial = await CardInfoCollector.readSerial(transport);
    if (this.serial >= 0) {
      if (serial !== null && serial !== this.serial) {
        toast('该卡片不是当前连接的卡片（期望 ' + this.serial + '，实际 ' + serial + '）');
        throw new Error('该卡片不是当前连接的卡片');
      }
      return;
    }
    if (serial === null) {
      // 老设备不可读序列号：不绑定（兼容行为）
      return;
    }
    this.serial = serial;
    AppState.setBoundSerial(serial);
    try {
      const info = await CardInfoCollector.collect(transport, 'NFC');
      DeviceInfoStore.set(info);
    } catch (e) {
      DeviceInfoStore.clear();
    }
  }
}