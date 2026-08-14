/**
 * 连接管理器（M1-4/5/6）：同时最多一个连接（NFC 模式或一个 USB 连接）。
 *   - USB：长连接（打开→attachUsb 验证→CONNECTED），断开检测依赖每 30s 心跳
 *     （CALCULATE ALL 失败 → onDeviceLost，注入到 TokenRefreshScheduler）
 *   - NFC：仅模式选择，无长连接；实际连接由 OathSessionManager.withSession 走 NfcSessionRunner
 *   - 切换/断开：清空会话密码、令牌缓存、定时器
 */
import { common } from '@kit.AbilityKit';
import { ConnMode, ConnStatus, NfcAvailability } from '../model/UiState';
import { AppState } from '../viewmodel/AppState';
import { TokenStore } from '../viewmodel/TokenStore';
import { DeviceInfoStore } from '../viewmodel/DeviceInfoStore';
import { SessionPasswordStore } from '../security/SessionPasswordStore';
import { UsbCcidTransport, UsbCardDevice } from '../common/UsbCcidTransport';
import { NfcListener } from '../common/NfcCardTransport';
import { CardInfoCollector } from '../common/CardInfoCollector';
import { OathSession } from '../protocol/OathProtocol';
import { OathSessionManager } from './OathSessionManager';
import { TokenRefreshScheduler } from './TokenRefreshScheduler';
import { NfcSupport } from './NfcSupport';
import { UsbCardChannel, NfcCardChannel } from './CardChannel';

/** 连接事件监听（struct 字段不能为 interface 类型，故用 class） */
export class ConnectionListener {
  /** 模式或状态变化（顶栏图标联动） */
  onStatusChanged: (mode: ConnMode, status: ConnStatus) => void = () => {
  };
  /** USB 设备丢失 */
  onDeviceLost: (message: string) => void = () => {
  };
}

export class ConnectionManager {
  private static instance: ConnectionManager | undefined = undefined;
  private listeners: ConnectionListener[] = [];
  private mode: ConnMode = ConnMode.NONE;
  private status: ConnStatus = ConnStatus.DISCONNECTED;
  private usbDeviceLabel: string = '';
  private initialized: boolean = false;
  private idleToaster: (msg: string) => void = (msg: string) => {
  };

  static getInstance(): ConnectionManager {
    if (ConnectionManager.instance === undefined) {
      ConnectionManager.instance = new ConnectionManager();
    }
    return ConnectionManager.instance;
  }

  getMode(): ConnMode {
    return this.mode;
  }

  getStatus(): ConnStatus {
    return this.status;
  }

  getDeviceLabel(): string {
    return this.usbDeviceLabel;
  }

  /** EntryAbility.onCreate 调用：注册心跳失联回调（断开检测） */
  init(context: common.UIAbilityContext): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    TokenRefreshScheduler.setLostHandler((msg: string) => {
      this.handleUsbLost(msg);
    });
    AppState.setMode('none');
    AppState.setStatus('disconnected');
  }

  subscribe(listener: ConnectionListener): void {
    this.listeners.push(listener);
  }

  unsubscribe(listener: ConnectionListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notifyStatus(): void {
    const modeText = ConnectionManager.modeText(this.mode);
    const statusText = ConnectionManager.statusText(this.status);
    AppState.setMode(modeText);
    AppState.setStatus(statusText);
    AppState.setDeviceLabel(this.usbDeviceLabel);
    for (const l of this.listeners) {
      l.onStatusChanged(this.mode, this.status);
    }
  }

  private notifyLost(message: string): void {
    for (const l of this.listeners) {
      l.onDeviceLost(message);
    }
  }

  /** 选择 NFC 模式（S2）：按可用性细分提示；成功即进入"待碰卡"监听并重置序列号绑定 */
  connectNfc(toast: (msg: string) => void): boolean {
    const avail = NfcSupport.check();
    if (avail !== NfcAvailability.READY) {
      toast(NfcSupport.messageFor(avail));
      return false;
    }
    this.idleToaster = toast;
    AppState.setBoundSerial(-1);
    void this.switchTo(ConnMode.NFC);
    return true;
  }

  /** 连接 USB 设备（S1）：打开通道 → 采集信息 → SELECT OATH → 验证 → 构建通道 → 首次刷新 */
  async connectUsb(device: UsbCardDevice, toast: (msg: string) => void): Promise<void> {
    await this.switchTo(ConnMode.USB);
    this.mode = ConnMode.USB;
    this.status = ConnStatus.CONNECTING;
    this.usbDeviceLabel = device.label;
    this.notifyStatus();
    try {
      const transport = await UsbCcidTransport.open(device);
      // 采集设备信息（Management），并记录绑定序列号（"当前连接"概念统一）
      let hasKey = false;
      let serial = -1;
      try {
        const info = await CardInfoCollector.collect(transport, 'USB');
        DeviceInfoStore.set(info);
        if (info.ykmanInfo.serialNumber !== null) {
          serial = info.ykmanInfo.serialNumber;
        }
      } catch (e) {
        DeviceInfoStore.clear();
      }
      if (serial >= 0) {
        AppState.setBoundSerial(serial);
      }
      const session = await OathSession.open(transport);
      hasKey = session.getHasKey();
      const ok = await OathSessionManager.getInstance().authenticate(session, toast);
      if (!ok) {
        try {
          await transport.close();
        } catch (e) {
        }
        throw new Error('解锁失败，连接已断开');
      }
      const channel = new UsbCardChannel(transport, session, serial);
      OathSessionManager.getInstance().setChannel(channel, hasKey);
      this.status = ConnStatus.CONNECTED;
      this.notifyStatus();
      try {
        await OathSessionManager.getInstance().refreshCurrent(toast);
      } catch (e) {
        this.handleUsbLost('读取令牌失败：' + (e as Error).message);
        throw new Error('读取令牌失败');
      }
      TokenRefreshScheduler.getInstance().start();
    } catch (e) {
      if (this.status === ConnStatus.CONNECTED) {
        throw (e as Error);
      }
      OathSessionManager.getInstance().clearChannel();
      this.status = ConnStatus.FAILED;
      this.notifyStatus();
      throw (e as Error);
    }
  }

  /** 切换连接：断开当前并清空会话状态（S11） */
  async switchTo(target: ConnMode): Promise<void> {
    if (this.mode === target && target === ConnMode.NFC) {
      return;
    }
    if (this.mode !== ConnMode.NONE) {
      await this.disconnect();
    }
    if (target === ConnMode.NFC) {
      this.mode = ConnMode.NFC;
      this.status = ConnStatus.DISCONNECTED;
      TokenRefreshScheduler.getInstance().start();
      // 构建 NFC 通道并进入"待碰卡"监听（S2）
      const channel = new NfcCardChannel();
      OathSessionManager.getInstance().setChannel(channel, false);
      channel.startIdle((tagInfo) => {
        OathSessionManager.getInstance().handleNfcIdleTap(tagInfo, this.idleToaster);
      });
      this.notifyStatus();
    }
  }

  /** 主动断开（S11）：清理会话密码/令牌缓存/定时器/待卡监听/序列号绑定 */
  async disconnect(): Promise<void> {
    NfcListener.stop();
    const ch = OathSessionManager.getInstance().getChannel();
    if (ch !== undefined) {
      try {
        await ch.disconnect();
      } catch (e) {
        // 忽略断开异常
      }
    }
    OathSessionManager.getInstance().clearChannel();
    SessionPasswordStore.clear();
    TokenStore.getInstance().clear();
    AppState.setCredentialCount(0);
    AppState.setBoundSerial(-1);
    TokenRefreshScheduler.getInstance().stop();
    this.mode = ConnMode.NONE;
    this.status = ConnStatus.DISCONNECTED;
    this.usbDeviceLabel = '';
    this.notifyStatus();
  }

  private handleUsbLost(message: string): void {
    TokenStore.getInstance().markAllStale();
    this.status = ConnStatus.FAILED;
    this.notifyStatus();
    this.notifyLost(message);
  }

  /** 回到前台时恢复 NFC 待卡监听（后台被系统回收 readerMode 后） */
  resumeNfcIdle(): void {
    const ch = OathSessionManager.getInstance().getChannel();
    if (ch !== undefined && ch instanceof NfcCardChannel) {
      ch.resumeIdle((tagInfo) => {
        OathSessionManager.getInstance().handleNfcIdleTap(tagInfo, this.idleToaster);
      });
    }
  }

  private static modeText(mode: ConnMode): string {
    if (mode === ConnMode.NFC) {
      return 'nfc';
    }
    if (mode === ConnMode.USB) {
      return 'usb';
    }
    return 'none';
  }

  private static statusText(status: ConnStatus): string {
    if (status === ConnStatus.CONNECTING) {
      return 'connecting';
    }
    if (status === ConnStatus.CONNECTED) {
      return 'connected';
    }
    if (status === ConnStatus.FAILED) {
      return 'failed';
    }
    return 'disconnected';
  }
}