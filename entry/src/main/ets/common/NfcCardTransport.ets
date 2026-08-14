/**
 * NFC 读卡器模式适配器
 * 依据 HarmonyOS @ohos.nfc.tag / tagSession：
 *  - tag.on('readerMode', elementName, discTech, cb)：前台读卡器模式（需 ohos.permission.NFC_TAG）
 *  - tag.getIsoDep(tagInfo).connect() / transmit(data: number[]): Promise<number[]>
 * YubiKey / CanoKey NFC 均暴露 ISO-DEP（Type 4）标签，通过 ISO 7816 APDU 通信。
 */
import { tag } from '@kit.ConnectivityKit';
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardTransport } from './ApduUtils';

/** 延迟工具（毫秒） */
function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

/** NFC 监听会话：注册 readerMode，等到标签即回调 */
export class NfcListener {
  private static elementName: bundleManager.ElementName | undefined;
  private static onTagFound: ((tagInfo: tag.TagInfo) => void) | undefined;
  private static listening: boolean = false;
  /**
   * consume=true（操作会话）：回调后清空 onTagFound，防止同一标签重复回调；
   * consume=false（idle 常驻）：保留回调，用户移开卡片再放上会再次触发。
   */
  private static consumeMode: boolean = true;

  static isListening(): boolean {
    return NfcListener.listening;
  }

  /** 开始监听 NFC 标签；发现标签后回调 onTagFound（回调内完成连接与 APDU 流程） */
  static start(elementName: bundleManager.ElementName, onTagFound: (tagInfo: tag.TagInfo) => void,
    consume: boolean): boolean {
    if (NfcListener.listening) {
      return false;
    }
    NfcListener.elementName = elementName;
    NfcListener.onTagFound = onTagFound;
    NfcListener.consumeMode = consume;
    try {
      tag.on('readerMode', elementName, [tag.NFC_A], NfcListener.handleTag);
      NfcListener.listening = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 停止监听并退出读卡器模式（恢复卡模拟） */
  static stop(): void {
    if (NfcListener.listening) {
      try {
        if (NfcListener.elementName !== undefined) {
          tag.off('readerMode', NfcListener.elementName, NfcListener.handleTag);
        }
      } catch (e) {
        // 忽略退订异常
      }
      NfcListener.listening = false;
      NfcListener.onTagFound = undefined;
    }
  }

  private static handleTag(err: BusinessError, tagInfo: tag.TagInfo): void {
    if (err) {
      return;
    }
    if (tagInfo == null) {
      return;
    }
    // 注意：此处不能先 tag.off('readerMode')——退出读卡器模式会重置 RF 场，
    // 导致随后 connect() 报 "Tag lost"。退订延后到 APDU 流程结束（由调用方执行）。
    const cb = NfcListener.onTagFound;
    if (NfcListener.consumeMode) {
      NfcListener.onTagFound = undefined; // 操作会话：防同一标签重复回调
    }
    if (cb !== undefined) {
      cb(tagInfo);
    }
  }
}

/** 基于 IsoDepTag 的 CardTransport 实现 */
export class NfcCardTransport implements CardTransport {
  private isoDep: tag.IsoDepTag;

  constructor(tagInfo: tag.TagInfo) {
    this.isoDep = tag.getIsoDep(tagInfo);
  }

/**
 * 连接 ISO-DEP：回调时 RF 场已建立，先立即 connect；
 * 失败（如 "Not in RF mode"）后按 150/300ms 间隔重试，
 * 期间 RF 场通常已重新稳定。连接成功后短暂缓冲，等待 ISO-DEP 链路就绪。
 */
  async connect(): Promise<void> {
    const attempts: number[] = [0, 150, 300];
    let lastError = '';
    for (let i = 0; i < attempts.length; i++) {
      const wait = attempts[i];
      if (wait > 0) {
        await delay(wait);
      }
      if (this.isoDep.isConnected()) {
        await delay(60);
        return;
      }
      try {
        this.isoDep.connect();
        await delay(60);
        return;
      } catch (e) {
        lastError = (e as Error).message;
      }
    }
    throw new Error('NFC connect failed: ' + lastError);
  }

  /**
   * 发送 APDU：I/O 通信失败（场短暂波动/链路未就绪）时短延时重试。
   */
  async transmit(apdu: Uint8Array): Promise<Uint8Array> {
    const data: number[] = [];
    for (let i = 0; i < apdu.length; i++) {
      data.push(apdu[i]);
    }
    let lastError = '';
    const retries = [0, 120, 250];
    for (let i = 0; i < retries.length; i++) {
      if (retries[i] > 0) {
        await delay(retries[i]);
      }
      try {
        const response: number[] = await this.isoDep.transmit(data);
        const out = new Uint8Array(response.length);
        for (let j = 0; j < response.length; j++) {
          out[j] = response[j];
        }
        return out;
      } catch (e) {
        lastError = (e as Error).message;
      }
    }
    throw new Error('NFC transmit failed: ' + lastError);
  }

  close(): Promise<void> {
    try {
      this.isoDep.resetConnection();
    } catch (e) {
      // 忽略重置异常
    }
    return Promise.resolve();
  }
}